import type { PowerTelemetry } from "../types";

type UnknownRecord = Record<string, unknown>;

function record(value: unknown): UnknownRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("macOS returned an invalid power reading.");
  }
  return value as UnknownRecord;
}

function read(source: UnknownRecord, snake: string, camel: string) {
  return source[snake] ?? source[camel] ?? null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function nonNegativeInteger(value: unknown): number | null {
  const number = finiteNumber(value);
  return number === null ? null : Math.max(0, Math.round(number));
}

export function normalizePowerTelemetry(value: unknown): PowerTelemetry {
  const source = record(value);
  const state = read(source, "charging_state", "chargingState");
  const chargingState =
    state === "charging" ||
    state === "full" ||
    state === "plugged_in" ||
    state === "battery"
      ? state
      : "unknown";
  const updatedAt = nonNegativeInteger(
    read(source, "updated_at_ms", "updatedAtMs"),
  );

  return {
    battery_percent: finiteNumber(
      read(source, "battery_percent", "batteryPercent"),
    ),
    charging_state: chargingState,
    system_watts: finiteNumber(read(source, "system_watts", "systemWatts")),
    adapter_input_watts: finiteNumber(
      read(source, "adapter_input_watts", "adapterInputWatts"),
    ),
    battery_watts: finiteNumber(read(source, "battery_watts", "batteryWatts")),
    adapter_rating_watts: finiteNumber(
      read(source, "adapter_rating_watts", "adapterRatingWatts"),
    ),
    battery_voltage: finiteNumber(
      read(source, "battery_voltage", "batteryVoltage"),
    ),
    battery_current_amps: finiteNumber(
      read(source, "battery_current_amps", "batteryCurrentAmps"),
    ),
    time_remaining_minutes: nonNegativeInteger(
      read(source, "time_remaining_minutes", "timeRemainingMinutes"),
    ),
    updated_at_ms: updatedAt ?? Date.now(),
  };
}
