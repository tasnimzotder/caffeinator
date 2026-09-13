use core_foundation::base::TCFType;
use core_foundation::string::CFString;

#[link(name = "IOKit", kind = "framework")]
extern "C" {
    fn IOPMAssertionCreateWithName(
        assertion_type: core_foundation::string::CFStringRef,
        assertion_level: u32,
        assertion_name: core_foundation::string::CFStringRef,
        assertion_id: *mut u32,
    ) -> i32;

    fn IOPMAssertionRelease(assertion_id: u32) -> i32;
}

const K_IOPM_ASSERTION_LEVEL_ON: u32 = 255;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum AssertionType {
    NoIdleSleep,
    NoDisplaySleep,
    /// "Server Mode" in the UI — keeps the system awake 24/7 and survives lid
    /// closure via pmset. Enum variant name matches user-facing label.
    #[serde(alias = "LidClose")] // backwards-compat with old settings.json
    ServerMode,
    NetworkActive,
    BackgroundTask,
}

impl AssertionType {
    fn as_cfstring(&self) -> CFString {
        let s = match self {
            // ServerMode keeps the CPU awake via PreventUserIdleSystemSleep; display
            // sleep and screen lock follow normal macOS timers. Surviving lid closure
            // is handled separately by `enable_lid_close_prevention` (pmset).
            AssertionType::NoIdleSleep | AssertionType::ServerMode => "PreventUserIdleSystemSleep",
            AssertionType::NoDisplaySleep => "PreventUserIdleDisplaySleep",
            AssertionType::NetworkActive => "NetworkClientActive",
            AssertionType::BackgroundTask => "BackgroundTask",
        };
        CFString::new(s)
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            AssertionType::NoIdleSleep => "Idle",
            AssertionType::NoDisplaySleep => "Display",
            AssertionType::ServerMode => "Server Mode",
            AssertionType::NetworkActive => "Network",
            AssertionType::BackgroundTask => "Background",
        }
    }

    /// Whether activating this mode additionally requires `pmset -b disablesleep 1`
    /// (to survive lid closure / battery-mode sleep on power cuts). Currently only
    /// ServerMode needs this.
    pub fn needs_lid_close_prevention(&self) -> bool {
        matches!(self, AssertionType::ServerMode)
    }
}

pub fn create_assertion(assertion_type: AssertionType, reason: &str) -> Result<u32, String> {
    let type_cf = assertion_type.as_cfstring();
    let reason_cf = CFString::new(reason);
    let mut assertion_id: u32 = 0;

    let result = unsafe {
        IOPMAssertionCreateWithName(
            type_cf.as_concrete_TypeRef(),
            K_IOPM_ASSERTION_LEVEL_ON,
            reason_cf.as_concrete_TypeRef(),
            &mut assertion_id,
        )
    };

    if result == 0 {
        Ok(assertion_id)
    } else {
        Err(format!(
            "Failed to create power assertion: error code {}",
            result
        ))
    }
}

pub fn release_assertion(assertion_id: u32) -> Result<(), String> {
    if assertion_id == 0 {
        return Ok(());
    }

    let result = unsafe { IOPMAssertionRelease(assertion_id) };

    if result == 0 {
        Ok(())
    } else {
        Err(format!(
            "Failed to release power assertion: error code {}",
            result
        ))
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
struct RecoveryRecord {
    version: u32,
    sleep_disabled: u32,
}

fn recovery_path() -> std::path::PathBuf {
    crate::storage::config_dir().join("power-recovery.json")
}

fn read_recovery() -> Result<Option<RecoveryRecord>, String> {
    let raw = match std::fs::read_to_string(recovery_path()) {
        Ok(raw) => raw,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("Cannot read sleep recovery record: {e}")),
    };
    let record: RecoveryRecord = serde_json::from_str(&raw)
        .map_err(|e| format!("Cannot read sleep recovery record: {e}"))?;
    if record.version != 1 || record.sleep_disabled > 1 {
        return Err(
            "Unsupported sleep recovery record. Original settings have been preserved.".into(),
        );
    }
    Ok(Some(record))
}

pub fn recovery_needed() -> Result<bool, String> {
    read_recovery().map(|record| record.is_some())
}

fn pmset(args: &[&str]) -> Result<String, String> {
    let output = std::process::Command::new("/usr/bin/pmset")
        .args(args)
        .output()
        .map_err(|e| format!("Cannot read power settings: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "Cannot read power settings: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn sleep_disabled() -> Result<u32, String> {
    parse_pmset_value(&pmset(&["-g"])?, "SleepDisabled")
        .filter(|value| *value <= 1)
        .ok_or_else(|| {
            "macOS did not report its sleep override. Server Mode was not changed.".into()
        })
}

fn authorization_error(stderr: &str) -> String {
    if stderr.trim_end().ends_with("(-128)") {
        "Authorization canceled. Retry when you are ready.".into()
    } else {
        format!("Could not change sleep settings: {}", stderr.trim())
    }
}

fn set_sleep_disabled(value: u32) -> Result<(), String> {
    // Only a validated integer is interpolated; no user text enters the script.
    let script = format!(
        "do shell script \"/usr/bin/pmset -a disablesleep {value}\" with administrator privileges"
    );
    let output = std::process::Command::new("/usr/bin/osascript")
        .args(["-e", &script])
        .output()
        .map_err(|e| format!("Cannot request authorization: {e}"))?;
    if !output.status.success() {
        return Err(authorization_error(&String::from_utf8_lossy(
            &output.stderr,
        )));
    }
    if sleep_disabled()? != value {
        return Err("macOS did not apply the requested sleep setting. Retry restoration.".into());
    }
    Ok(())
}

/// Journal the original global override before changing it. The normal sleep
/// timers are never modified. A crash leaves a record that can be restored.
pub fn enable_lid_close_prevention() -> Result<(), String> {
    if recovery_needed()? {
        return Err("Restore the previous Server Mode session before starting another.".into());
    }
    let original = sleep_disabled()?;
    let record = RecoveryRecord {
        version: 1,
        sleep_disabled: original,
    };
    std::fs::create_dir_all(crate::storage::config_dir()).map_err(|e| e.to_string())?;
    let json = serde_json::to_string(&record).map_err(|e| e.to_string())?;
    crate::storage::atomic_write(&recovery_path(), &json).map_err(|e| e.to_string())?;
    if original != 1 {
        if let Err(error) = set_sleep_disabled(1) {
            // Cancellation normally changes nothing. Clear only after verifying
            // that the original value still holds; otherwise retain recovery.
            if sleep_disabled().ok() == Some(original) {
                let _ = std::fs::remove_file(recovery_path());
            }
            return Err(error);
        }
    }
    Ok(())
}

pub fn disable_lid_close_prevention() -> Result<(), String> {
    let Some(record) = read_recovery()? else {
        return Ok(());
    };
    if sleep_disabled()? != record.sleep_disabled {
        set_sleep_disabled(record.sleep_disabled)?;
    }
    std::fs::remove_file(recovery_path()).map_err(|e| {
        format!("Sleep settings restored, but recovery record could not be cleared: {e}")
    })
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PowerProfile {
    pub source: String,
    pub display_sleep: Option<u32>,
    pub disk_sleep: Option<u32>,
    pub system_sleep: Option<u32>,
    pub sleep_disabled: bool,
    /// Process names currently preventing system sleep (parsed from pmset's
    /// "(sleep prevented by X, Y)" parenthetical). When non-empty, the
    /// `system_sleep` timer is being overridden at runtime.
    pub system_sleep_prevented_by: Vec<String>,
    pub assertions: Vec<String>,
}

pub fn get_power_profile() -> Result<PowerProfile, String> {
    // Current power settings (sleep timers, "prevented by" info).
    // NB: `pmset -g` does NOT include "AC Power"/"Battery Power" strings — that
    // info lives only in `pmset -g ps`, which we query separately below.
    let pmset_str = pmset(&["-g"])?;

    // Current power source.
    let ps_str = pmset(&["-g", "ps"])?;
    let source = parse_power_source(&ps_str);

    // Parse sleep timer values (raw pmset config; may be overridden at runtime).
    let display_sleep = parse_pmset_value(&pmset_str, "displaysleep");
    let disk_sleep = parse_pmset_value(&pmset_str, "disksleep");
    let system_sleep = parse_pmset_value(&pmset_str, "sleep");
    let system_sleep_prevented_by = parse_sleep_prevented_by(&pmset_str);

    // Get active assertions
    let assertions_str = pmset(&["-g", "assertions"])?;
    let assertions = parse_assertions(&assertions_str);

    Ok(PowerProfile {
        source,
        display_sleep,
        disk_sleep,
        system_sleep,
        sleep_disabled: parse_pmset_value(&pmset_str, "SleepDisabled") == Some(1),
        system_sleep_prevented_by,
        assertions,
    })
}

fn parse_power_source(ps_str: &str) -> String {
    if ps_str.contains("AC Power") {
        "AC Power".to_string()
    } else if ps_str.contains("Battery Power") {
        "Battery".to_string()
    } else {
        "Unknown".to_string()
    }
}

/// Parse the "(sleep prevented by X, Y, Z)" parenthetical from the `sleep` line.
/// Returns empty vec if no override is active.
fn parse_sleep_prevented_by(output: &str) -> Vec<String> {
    const MARKER: &str = "(sleep prevented by ";
    for line in output.lines() {
        let trimmed = line.trim();
        // Guard against matching unrelated keys like "sleepDisabled"
        if !(trimmed.starts_with("sleep ") || trimmed.starts_with("sleep\t")) {
            continue;
        }
        let Some(start) = trimmed.find(MARKER) else {
            continue;
        };
        let after = &trimmed[start + MARKER.len()..];
        let Some(end) = after.find(')') else { continue };
        return after[..end]
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
    }
    Vec::new()
}

fn parse_pmset_value(output: &str, key: &str) -> Option<u32> {
    for line in output.lines() {
        let trimmed = line.trim();
        // Word-boundary match — guards against "sleep" matching "sleepDisabled".
        let Some(after_key) = trimmed.strip_prefix(key) else {
            continue;
        };
        if !after_key.starts_with(|c: char| c.is_whitespace()) {
            continue;
        }
        if let Some(first) = after_key.split_whitespace().next() {
            return first.parse().ok();
        }
    }
    None
}

fn parse_assertions(output: &str) -> Vec<String> {
    let mut assertions = Vec::new();
    let mut in_listed = false;

    for line in output.lines() {
        if line.contains("Listed by owning process") {
            in_listed = true;
            continue;
        }
        if in_listed && line.trim().starts_with("pid") {
            // Format: "   pid 1234(processName): [0x000012345678901234] 00:00:00 AssertionType named: "reason""
            if let Some(start) = line.find("):") {
                let rest = &line[start + 2..];
                if let Some(bracket_end) = rest.find(']') {
                    let after_bracket = &rest[bracket_end + 1..];
                    // Get the assertion type and name
                    let parts: Vec<&str> = after_bracket.trim().splitn(3, ' ').collect();
                    if parts.len() >= 2 {
                        let assertion_info = format!(
                            "{}: {}",
                            parts.get(1).unwrap_or(&"Unknown"),
                            line.split('(')
                                .next()
                                .unwrap_or("")
                                .trim()
                                .replace("pid ", "PID ")
                        );
                        assertions.push(assertion_info);
                    }
                }
            }
        }
    }

    assertions
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_error_minus_128_is_cancellation() {
        assert!(
            authorization_error("execution error: User canceled. (-128)")
                .starts_with("Authorization canceled")
        );
        assert!(
            authorization_error("execution error: synthetic failure (42)")
                .contains("synthetic failure")
        );
    }

    const SAMPLE_PMSET_G: &str = "\
System-wide power settings:
Currently in use:
 standby              1
 Sleep On Power Button 1
 womp                 1
 hibernatefile        /var/vm/sleepimage
 powernap             0
 networkoversleep     0
 disksleep            10
 sleep                5 (sleep prevented by caffeinator, powerd)
 hibernatemode        3
 ttyskeepawake        1
 displaysleep         15
 tcpkeepalive         1
 lidwake              1
";

    const SAMPLE_PMSET_G_NO_OVERRIDE: &str = "\
 disksleep            10
 sleep                5
 displaysleep         15
";

    const SAMPLE_PMSET_PS_AC: &str = "\
Now drawing from 'AC Power'
 -InternalBattery-0 (id=1234567)\t100%; charged; 0:00 remaining present: true
";

    const SAMPLE_PMSET_PS_BATT: &str = "\
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1234567)\t87%; discharging; 4:32 remaining present: true
";

    const SAMPLE_ASSERTIONS: &str = "\
Assertion status system-wide:
   BackgroundTask                 0
   PreventUserIdleDisplaySleep    0
   PreventUserIdleSystemSleep     1
Listed by owning process:
   pid 1234(caffeinator): [0x000012345678901234] 00:05:30 PreventUserIdleSystemSleep named: \"Caffeinator: Preventing Idle sleep\"
   pid 5678(powerd): [0x00009876543210ab] 00:00:01 ApplePushServiceTask named: \"com.apple.aps\"
";

    #[test]
    fn parses_displaysleep() {
        assert_eq!(parse_pmset_value(SAMPLE_PMSET_G, "displaysleep"), Some(15));
    }

    #[test]
    fn parses_disksleep() {
        assert_eq!(parse_pmset_value(SAMPLE_PMSET_G, "disksleep"), Some(10));
    }

    #[test]
    fn parses_sleep_value_when_prevented() {
        assert_eq!(parse_pmset_value(SAMPLE_PMSET_G, "sleep"), Some(5));
    }

    #[test]
    fn word_boundary_avoids_sleepdisabled() {
        let input = "sleepDisabled       1\n sleep        7\n";
        assert_eq!(parse_pmset_value(input, "sleep"), Some(7));
    }

    #[test]
    fn returns_none_for_missing_key() {
        assert!(parse_pmset_value(SAMPLE_PMSET_G, "doesnotexist").is_none());
    }

    #[test]
    fn parses_sleep_prevented_by_list() {
        let prevented = parse_sleep_prevented_by(SAMPLE_PMSET_G);
        assert_eq!(prevented, vec!["caffeinator", "powerd"]);
    }

    #[test]
    fn empty_prevented_by_when_no_override() {
        let prevented = parse_sleep_prevented_by(SAMPLE_PMSET_G_NO_OVERRIDE);
        assert!(prevented.is_empty());
    }

    #[test]
    fn ignores_sleepdisabled_line_in_prevented_by() {
        let input = "sleepDisabled          0\n sleep   5\n";
        assert!(parse_sleep_prevented_by(input).is_empty());
    }

    #[test]
    fn detects_ac_power() {
        assert_eq!(parse_power_source(SAMPLE_PMSET_PS_AC), "AC Power");
    }

    #[test]
    fn detects_battery_power() {
        assert_eq!(parse_power_source(SAMPLE_PMSET_PS_BATT), "Battery");
    }

    #[test]
    fn power_source_unknown_when_neither_present() {
        assert_eq!(parse_power_source(""), "Unknown");
    }

    #[test]
    fn parses_active_assertions() {
        let assertions = parse_assertions(SAMPLE_ASSERTIONS);
        assert_eq!(assertions.len(), 2);
        assert!(assertions[0].contains("PreventUserIdleSystemSleep"));
        assert!(assertions[0].contains("PID 1234"));
    }

    #[test]
    fn assertion_type_aliases_lid_close() {
        // Old settings.json files used "LidClose" before the rename. Must
        // still deserialize to ServerMode.
        let parsed: AssertionType = serde_json::from_str("\"LidClose\"").unwrap();
        assert_eq!(parsed, AssertionType::ServerMode);
    }

    #[test]
    fn server_mode_is_only_lid_close_consumer() {
        assert!(AssertionType::ServerMode.needs_lid_close_prevention());
        assert!(!AssertionType::NoIdleSleep.needs_lid_close_prevention());
        assert!(!AssertionType::NoDisplaySleep.needs_lid_close_prevention());
        assert!(!AssertionType::NetworkActive.needs_lid_close_prevention());
        assert!(!AssertionType::BackgroundTask.needs_lid_close_prevention());
    }
}
