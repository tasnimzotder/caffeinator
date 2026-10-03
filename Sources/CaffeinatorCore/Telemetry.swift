import Foundation

public enum TelemetryReader {
  private static func number(_ dict: [String: Any], _ key: String) -> Double? {
    guard let n = dict[key] as? NSNumber else { return nil }
    // ioreg can encode negative amperage as unsigned 64-bit two's complement.
    let value =
      n.doubleValue > Double(Int64.max) ? Double(Int64(bitPattern: n.uint64Value)) : n.doubleValue
    return value.isFinite ? value : nil
  }
  private static func watts(_ dict: [String: Any], _ key: String) -> Double? {
    guard let value = number(dict, key).map({ $0 / 1000 }), abs(value) < 2000 else { return nil }
    return value
  }
  public static func parse(_ battery: [String: Any], now: Int64 = milliseconds()) -> Telemetry {
    let external = battery["ExternalConnected"] as? Bool ?? false
    let charging = battery["IsCharging"] as? Bool ?? false
    let full = battery["FullyCharged"] as? Bool ?? false
    let sensors = battery["PowerTelemetryData"] as? [String: Any] ?? [:]
    var sample = Telemetry()
    sample.updatedAtMS = now
    sample.chargingState =
      charging ? "charging" : full && external ? "full" : external ? "plugged_in" : "battery"
    sample.batteryCurrentAmps = (number(battery, "InstantAmperage") ?? number(battery, "Amperage"))
      .map { $0 / 1000 }
    if let voltage = number(battery, "Voltage").map({ $0 / 1000 }), voltage > 0, voltage < 30 {
      sample.batteryVoltage = voltage
    }
    if let capacity = number(battery, "CurrentCapacity"), let max = number(battery, "MaxCapacity"),
      max > 0
    {
      sample.batteryPercent = min(100, Swift.max(0, capacity / max * 100))
    }
    sample.systemWatts = watts(sensors, "SystemLoad").flatMap { $0 >= 0 ? $0 : nil }
    sample.batteryWatts = watts(sensors, "BatteryPower")
    if sample.batteryWatts == nil, let v = sample.batteryVoltage, let a = sample.batteryCurrentAmps
    {
      sample.batteryWatts = v * a
    }
    if external {
      sample.adapterInputWatts = watts(sensors, "SystemPowerIn")
      if let adapter = battery["AdapterDetails"] as? [String: Any],
        let rating = number(adapter, "Watts"), rating > 0
      {
        sample.adapterRatingWatts = rating
      }
    }
    if let remaining = number(battery, "TimeRemaining"), remaining > 0, remaining < 14400,
      charging || !external
    {
      sample.timeRemainingMinutes = Int(remaining)
    }
    return sample
  }
  public static func read() throws -> Telemetry {
    let result = try ProcessRunner.run("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-a"])
    guard result.status == 0 else { throw AppError("macOS could not read battery sensors.") }
    guard
      let root = try PropertyListSerialization.propertyList(from: result.output, format: nil)
        as? [[String: Any]], let battery = root.first
    else {
      throw AppError("This Mac does not expose battery power telemetry.")
    }
    return parse(battery)
  }
}
