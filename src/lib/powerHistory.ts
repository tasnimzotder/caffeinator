import type {
  AssertionType,
  PowerHistory,
  PowerHistoryPoint,
  SessionHistory,
} from "../types";

type UnknownRecord = Record<string, unknown>;

function record(value: unknown, message: string): UnknownRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(message);
  }
  return value as UnknownRecord;
}

function read(source: UnknownRecord, snake: string, camel: string) {
  return source[snake] ?? source[camel] ?? null;
}

function finite(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function timestamp(value: unknown): number {
  const number = finite(value);
  if (number === null || number < 0) {
    throw new Error("Power history contains an invalid timestamp.");
  }
  return Math.round(number);
}

function mode(value: unknown): AssertionType {
  if (
    value === "NoIdleSleep" ||
    value === "NoDisplaySleep" ||
    value === "ServerMode" ||
    value === "NetworkActive" ||
    value === "BackgroundTask"
  ) {
    return value;
  }
  throw new Error("Power history contains an invalid session mode.");
}

function point(value: unknown): PowerHistoryPoint {
  const source = record(value, "Power history contains an invalid sample.");
  return {
    sampled_at_ms: timestamp(read(source, "sampled_at_ms", "sampledAtMs")),
    system_watts: finite(read(source, "system_watts", "systemWatts")),
    battery_watts: finite(read(source, "battery_watts", "batteryWatts")),
    battery_percent: finite(
      read(source, "battery_percent", "batteryPercent"),
    ),
  };
}

function session(value: unknown): SessionHistory {
  const source = record(value, "Power history contains an invalid session.");
  const ended = read(source, "ended_at_ms", "endedAtMs");
  const planned = read(
    source,
    "planned_duration_seconds",
    "plannedDurationSeconds",
  );
  const reason = read(source, "end_reason", "endReason");
  return {
    id: timestamp(source.id),
    mode: mode(source.mode),
    started_at_ms: timestamp(read(source, "started_at_ms", "startedAtMs")),
    ended_at_ms: ended === null ? null : timestamp(ended),
    planned_duration_seconds:
      planned === null ? null : timestamp(planned),
    end_reason:
      reason === "stopped" ||
      reason === "expired" ||
      reason === "replaced" ||
      reason === "interrupted"
        ? reason
        : null,
  };
}

export function normalizePowerHistory(value: unknown): PowerHistory {
  const source = record(value, "Caffeinator returned invalid power history.");
  const points = source.points;
  const sessions = source.sessions;
  if (!Array.isArray(points) || !Array.isArray(sessions)) {
    throw new Error("Caffeinator returned invalid power history.");
  }
  const average = read(
    source,
    "average_system_watts",
    "averageSystemWatts",
  );
  const peak = read(source, "peak_system_watts", "peakSystemWatts");
  const sampleCount = timestamp(read(source, "sample_count", "sampleCount"));
  const sessionSeconds = timestamp(
    read(source, "session_seconds", "sessionSeconds"),
  );
  return {
    from_ms: timestamp(read(source, "from_ms", "fromMs")),
    to_ms: timestamp(read(source, "to_ms", "toMs")),
    average_system_watts: finite(average),
    peak_system_watts: finite(peak),
    sample_count: sampleCount,
    session_seconds: sessionSeconds,
    points: points.map(point),
    sessions: sessions.map(session),
  };
}
