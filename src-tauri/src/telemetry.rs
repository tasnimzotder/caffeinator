//! Read-only battery/SMC telemetry. PowerTelemetryData reports milliwatts;
//! these are hardware readings, not charger ratings or per-process estimates.
use plist::{Dictionary, Value};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, serde::Serialize)]
pub struct PowerTelemetry {
    pub battery_percent: Option<f64>,
    pub charging_state: String,
    pub system_watts: Option<f64>,
    pub adapter_input_watts: Option<f64>,
    /// Signed battery power: positive charges, negative discharges.
    pub battery_watts: Option<f64>,
    pub adapter_rating_watts: Option<f64>,
    pub battery_voltage: Option<f64>,
    pub battery_current_amps: Option<f64>,
    pub time_remaining_minutes: Option<u64>,
    pub updated_at_ms: u64,
}

fn number(dict: &Dictionary, key: &str) -> Option<f64> {
    let value = dict.get(key)?;
    value
        .as_signed_integer()
        .map(|v| v as f64)
        .or_else(|| value.as_unsigned_integer().map(|v| (v as i64) as f64))
        .or_else(|| value.as_real())
}
fn watts(dict: &Dictionary, key: &str) -> Option<f64> {
    number(dict, key)
        .map(|v| v / 1000.0)
        .filter(|v| v.is_finite() && v.abs() < 2000.0)
}

fn parse(root: &Value) -> Result<PowerTelemetry, String> {
    let battery = root
        .as_array()
        .and_then(|array| array.first())
        .and_then(Value::as_dictionary)
        .ok_or("This Mac does not expose battery power telemetry.")?;
    let external = battery
        .get("ExternalConnected")
        .and_then(Value::as_boolean)
        .unwrap_or(false);
    let charging = battery
        .get("IsCharging")
        .and_then(Value::as_boolean)
        .unwrap_or(false);
    let full = battery
        .get("FullyCharged")
        .and_then(Value::as_boolean)
        .unwrap_or(false);
    let current = number(battery, "InstantAmperage")
        .or_else(|| number(battery, "Amperage"))
        .map(|v| v / 1000.0);
    let voltage = number(battery, "Voltage")
        .map(|v| v / 1000.0)
        .filter(|v| *v > 0.0 && *v < 30.0);
    let telemetry = battery
        .get("PowerTelemetryData")
        .and_then(Value::as_dictionary);
    let battery_watts = telemetry
        .and_then(|dict| watts(dict, "BatteryPower"))
        .or_else(|| voltage.zip(current).map(|(v, a)| v * a));
    let percent = number(battery, "CurrentCapacity")
        .zip(number(battery, "MaxCapacity"))
        .filter(|(_, max)| *max > 0.0)
        .map(|(capacity, max)| (capacity / max * 100.0).clamp(0.0, 100.0));
    let remaining = number(battery, "TimeRemaining")
        .filter(|value| *value > 0.0 && *value < 14400.0)
        .filter(|_| charging || !external)
        .map(|value| value as u64);
    Ok(PowerTelemetry {
        battery_percent: percent,
        charging_state: if charging {
            "charging"
        } else if full && external {
            "full"
        } else if external {
            "plugged_in"
        } else {
            "battery"
        }
        .into(),
        system_watts: telemetry
            .and_then(|dict| watts(dict, "SystemLoad"))
            .filter(|value| *value >= 0.0),
        adapter_input_watts: external
            .then(|| telemetry.and_then(|dict| watts(dict, "SystemPowerIn")))
            .flatten(),
        battery_watts,
        adapter_rating_watts: external
            .then(|| {
                battery
                    .get("AdapterDetails")
                    .and_then(Value::as_dictionary)
                    .and_then(|dict| number(dict, "Watts"))
                    .filter(|value| *value > 0.0)
            })
            .flatten(),
        battery_voltage: voltage,
        battery_current_amps: current,
        time_remaining_minutes: remaining,
        updated_at_ms: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64,
    })
}

pub fn read() -> Result<PowerTelemetry, String> {
    let output = std::process::Command::new("/usr/sbin/ioreg")
        .args(["-r", "-c", "AppleSmartBattery", "-a"])
        .output()
        .map_err(|e| format!("Cannot read power sensors: {e}"))?;
    if !output.status.success() {
        return Err("macOS could not read battery power sensors.".into());
    }
    let root = Value::from_reader_xml(std::io::Cursor::new(output.stdout))
        .map_err(|e| format!("Cannot decode power sensors: {e}"))?;
    parse(&root)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture(current: Value, external: bool) -> Value {
        let mut battery = Dictionary::new();
        battery.insert("InstantAmperage".into(), current);
        battery.insert("Voltage".into(), Value::Integer(12000.into()));
        battery.insert("CurrentCapacity".into(), Value::Integer(50.into()));
        battery.insert("MaxCapacity".into(), Value::Integer(100.into()));
        battery.insert("ExternalConnected".into(), Value::Boolean(external));
        battery.insert("IsCharging".into(), Value::Boolean(external));
        Value::Array(vec![Value::Dictionary(battery)])
    }
    #[test]
    fn converts_battery_current_and_voltage_to_watts() {
        let sample = parse(&fixture(Value::Integer(2000.into()), true)).unwrap();
        assert_eq!(sample.battery_watts, Some(24.0));
        assert_eq!(sample.battery_percent, Some(50.0));
        assert_eq!(sample.charging_state, "charging");
        assert_eq!(sample.system_watts, None); // never invent total system draw
    }
    #[test]
    fn handles_unsigned_twos_complement_discharge_current() {
        let sample = parse(&fixture(Value::Integer(((-1000_i64) as u64).into()), false)).unwrap();
        assert_eq!(sample.battery_current_amps, Some(-1.0));
        assert_eq!(sample.battery_watts, Some(-12.0));
        assert_eq!(sample.charging_state, "battery");
        assert_eq!(sample.adapter_input_watts, None);
    }
    #[test]
    fn separates_measured_power_from_adapter_rating() {
        let mut root = fixture(Value::Integer(2000.into()), true);
        let battery = root.as_array_mut().unwrap()[0].as_dictionary_mut().unwrap();
        let mut sensors = Dictionary::new();
        sensors.insert("SystemLoad".into(), Value::Integer(11383.into()));
        sensors.insert("BatteryPower".into(), Value::Integer(43168.into()));
        sensors.insert("SystemPowerIn".into(), Value::Integer(54551.into()));
        battery.insert("PowerTelemetryData".into(), Value::Dictionary(sensors));
        let mut adapter = Dictionary::new();
        adapter.insert("Watts".into(), Value::Integer(84.into()));
        battery.insert("AdapterDetails".into(), Value::Dictionary(adapter));
        let sample = parse(&root).unwrap();
        assert_eq!(sample.system_watts, Some(11.383));
        assert_eq!(sample.battery_watts, Some(43.168));
        assert_eq!(sample.adapter_input_watts, Some(54.551));
        assert_eq!(sample.adapter_rating_watts, Some(84.0));
    }
    #[test]
    fn missing_hardware_is_unavailable_instead_of_zero() {
        assert!(parse(&Value::Array(vec![])).is_err());
    }
}
