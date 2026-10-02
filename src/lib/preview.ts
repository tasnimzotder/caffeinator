// Development-only visual preview. This never controls macOS power settings.
import type {
  AssertionType,
  CaffeinateStatus,
  HistoryRange,
  PowerHistory,
  SessionHistory,
} from "../types";

let status: CaffeinateStatus = {
  is_active: false,
  mode: null,
  selected_mode: "NoIdleSleep",
  remaining_seconds: null,
  total_seconds: null,
  busy: false,
  recovery_required: false,
  error: null,
  revision: 0,
  selected_duration: 3600,
};
let end: number | null = null;
let activeSessionId: number | null = null;
let nextSessionId = 4;
let autostart = false;
const now = Date.now();
const sessions: SessionHistory[] = [
  {
    id: 1,
    mode: "NoIdleSleep",
    started_at_ms: now - 42 * 60 * 1000,
    ended_at_ms: now - 12 * 60 * 1000,
    planned_duration_seconds: 1800,
    end_reason: "expired",
  },
  {
    id: 2,
    mode: "NoDisplaySleep",
    started_at_ms: now - 7.5 * 60 * 60 * 1000,
    ended_at_ms: now - 6 * 60 * 60 * 1000,
    planned_duration_seconds: 5400,
    end_reason: "stopped",
  },
  {
    id: 3,
    mode: "BackgroundTask",
    started_at_ms: now - 30 * 60 * 60 * 1000,
    ended_at_ms: now - 28 * 60 * 60 * 1000,
    planned_duration_seconds: 7200,
    end_reason: "expired",
  },
];
const listeners = new Set<(status: CaffeinateStatus) => void>();

function emit() {
  listeners.forEach((callback) => callback({ ...status }));
}

function stop(reason: SessionHistory["end_reason"] = "stopped") {
  if (activeSessionId !== null) {
    const session = sessions.find((candidate) => candidate.id === activeSessionId);
    if (session) {
      session.ended_at_ms = Date.now();
      session.end_reason = reason;
    }
  }
  activeSessionId = null;
  status = {
    ...status,
    is_active: false,
    mode: null,
    total_seconds: null,
    remaining_seconds: null,
    revision: status.revision + 1,
  };
  end = null;
}

function previewHistory(range: HistoryRange): PowerHistory {
  const to = Date.now();
  const durationMs =
    range === "hour"
      ? 60 * 60 * 1000
      : range === "day"
        ? 24 * 60 * 60 * 1000
        : 7 * 24 * 60 * 60 * 1000;
  const count = range === "hour" ? 31 : range === "day" ? 49 : 57;
  const from = to - durationMs;
  const points = Array.from({ length: count }, (_, index) => {
    const phase = index / Math.max(1, count - 1);
    const workCycle = Math.sin(phase * Math.PI * 5.2) * 2.4;
    const shorterCycle = Math.sin(phase * Math.PI * 17) * 0.8;
    return {
      sampled_at_ms: from + phase * durationMs,
      system_watts: 10.8 + workCycle + shorterCycle + (phase > 0.72 ? 2.2 : 0),
      battery_watts: -6.4 + Math.sin(phase * Math.PI * 3),
      battery_percent: 78 - phase * 16,
    };
  });
  const visibleSessions = sessions
    .filter(
      (session) =>
        session.started_at_ms <= to && (session.ended_at_ms ?? to) >= from,
    )
    .sort((left, right) => right.started_at_ms - left.started_at_ms);
  const systemReadings = points.flatMap((point) =>
    point.system_watts === null ? [] : [point.system_watts],
  );
  const sessionSeconds = visibleSessions.reduce((total, session) => {
    const overlapStart = Math.max(from, session.started_at_ms);
    const overlapEnd = Math.min(to, session.ended_at_ms ?? to);
    return total + Math.max(0, Math.round((overlapEnd - overlapStart) / 1000));
  }, 0);
  return {
    from_ms: from,
    to_ms: to,
    average_system_watts:
      systemReadings.reduce((sum, value) => sum + value, 0) /
      Math.max(1, systemReadings.length),
    peak_system_watts: Math.max(...systemReadings),
    sample_count: points.length,
    session_seconds: sessionSeconds,
    points,
    sessions: visibleSessions,
  };
}

export function subscribe(callback: (status: CaffeinateStatus) => void) {
  listeners.add(callback);
  const timer = setInterval(() => {
    if (end !== null) {
      status.remaining_seconds = Math.max(
        0,
        Math.ceil((end - Date.now()) / 1000),
      );
      if (status.remaining_seconds === 0) stop("expired");
    }
    emit();
  }, 1000);
  return () => {
    listeners.delete(callback);
    clearInterval(timer);
  };
}

export async function previewCommand<T>(
  name: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  switch (name) {
    case "get_status":
      return { ...status } as T;
    case "set_selected_mode":
      status.selected_mode = args.mode as AssertionType;
      status.revision++;
      break;
    case "set_selected_duration":
      status.selected_duration = args.durationSecs as number | null;
      status.revision++;
      break;
    case "activate": {
      if (status.is_active) stop("replaced");
      const mode = args.mode as AssertionType;
      const durationSecs = args.durationSecs as number | null;
      activeSessionId = nextSessionId++;
      sessions.push({
        id: activeSessionId,
        mode,
        started_at_ms: Date.now(),
        ended_at_ms: null,
        planned_duration_seconds: durationSecs,
        end_reason: null,
      });
      status = {
        ...status,
        is_active: true,
        mode,
        remaining_seconds: durationSecs,
        total_seconds: durationSecs,
        revision: status.revision + 1,
      };
      end = durationSecs === null ? null : Date.now() + durationSecs * 1000;
      break;
    }
    case "deactivate":
      stop();
      break;
    case "get_autostart_enabled":
      return autostart as T;
    case "set_autostart_enabled":
      autostart = Boolean(args.enabled);
      return undefined as T;
    case "set_window_pinned":
      return undefined as T;
    case "get_power_profile":
      return {
        source: "AC Power",
        display_sleep: 10,
        disk_sleep: 10,
        system_sleep: 5,
        sleep_disabled: status.mode === "ServerMode",
        system_sleep_prevented_by: status.is_active ? ["Caffeinator"] : [],
        assertions: status.is_active
          ? ["PreventUserIdleSystemSleep: PID 1234"]
          : [],
      } as T;
    case "get_power_telemetry":
      return {
        battery_percent: 62,
        charging_state: "charging",
        system_watts: 11.5 + Math.sin(Date.now() / 3000) * 2,
        battery_watts: 32.8,
        adapter_input_watts: 44.3,
        adapter_rating_watts: 84,
        battery_voltage: 12.6,
        battery_current_amps: 2.6,
        time_remaining_minutes: 48,
        updated_at_ms: Date.now(),
      } as T;
    case "get_power_history":
      return previewHistory(args.range as HistoryRange) as T;
    case "quit_app":
    case "hide_window":
      return undefined as T;
    default:
      throw new Error(`Preview does not implement ${name}`);
  }
  emit();
  return { ...status } as T;
}
