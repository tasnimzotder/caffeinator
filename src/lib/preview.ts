// Development-only visual preview. This never controls macOS power settings.
import type { AssertionType, CaffeinateStatus } from "../types";

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
let autostart = false;
const listeners = new Set<(status: CaffeinateStatus) => void>();
function emit() {
  listeners.forEach((callback) => callback({ ...status }));
}
function stop() {
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
export function subscribe(callback: (status: CaffeinateStatus) => void) {
  listeners.add(callback);
  const timer = setInterval(() => {
    if (end !== null) {
      status.remaining_seconds = Math.max(
        0,
        Math.ceil((end - Date.now()) / 1000),
      );
      if (status.remaining_seconds === 0) stop();
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
    case "activate":
      status = {
        ...status,
        is_active: true,
        mode: args.mode as AssertionType,
        remaining_seconds: args.durationSecs as number | null,
        total_seconds: args.durationSecs as number | null,
        revision: status.revision + 1,
      };
      end =
        status.total_seconds === null
          ? null
          : Date.now() + status.total_seconds * 1000;
      break;
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
    case "quit_app":
    case "hide_window":
      return undefined as T;
    default:
      throw new Error(`Preview does not implement ${name}`);
  }
  emit();
  return { ...status } as T;
}
