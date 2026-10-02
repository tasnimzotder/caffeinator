import { describe, expect, test } from "bun:test";
import { normalizePowerTelemetry } from "../src/lib/powerTelemetry";

describe("normalizePowerTelemetry", () => {
  test("keeps native snake-case readings", () => {
    const sample = normalizePowerTelemetry({
      battery_percent: 72,
      charging_state: "charging",
      system_watts: 8.25,
      adapter_input_watts: 40.5,
      battery_watts: 32.25,
      adapter_rating_watts: 84,
      battery_voltage: 12.7,
      battery_current_amps: 2.54,
      time_remaining_minutes: 61,
      updated_at_ms: 1234,
    });

    expect(sample.system_watts).toBe(8.25);
    expect(sample.charging_state).toBe("charging");
    expect(sample.updated_at_ms).toBe(1234);
  });

  test("accepts camel-case IPC fields and converts invalid numbers to null", () => {
    const sample = normalizePowerTelemetry({
      batteryPercent: 73,
      chargingState: "full",
      systemWatts: 7.5,
      adapterInputWatts: Number.NaN,
      batteryWatts: 0,
      updatedAtMs: 5678,
    });

    expect(sample.battery_percent).toBe(73);
    expect(sample.system_watts).toBe(7.5);
    expect(sample.adapter_input_watts).toBeNull();
    expect(sample.updated_at_ms).toBe(5678);
  });

  test("rejects non-object responses", () => {
    expect(() => normalizePowerTelemetry(null)).toThrow(
      "invalid power reading",
    );
  });
});
