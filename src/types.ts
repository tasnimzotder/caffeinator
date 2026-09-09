import {
  Moon,
  Monitor,
  Server,
  Wifi,
  Cog,
  type LucideIcon,
} from "lucide-react";

export type AssertionType =
  | "NoIdleSleep"
  | "NoDisplaySleep"
  | "ServerMode"
  | "NetworkActive"
  | "BackgroundTask";

export interface CaffeinateStatus {
  is_active: boolean;
  mode: AssertionType | null;
  remaining_seconds: number | null;
  total_seconds: number | null;
  selected_mode: AssertionType;
  selected_duration: number | null;
  busy: boolean;
  recovery_required: boolean;
  error: string | null;
  revision: number;
}

export interface PowerProfile {
  source: string;
  display_sleep: number | null;
  disk_sleep: number | null;
  system_sleep: number | null;
  sleep_disabled: boolean;
  /** Process names preventing system sleep; when non-empty, the timer is overridden. */
  system_sleep_prevented_by: string[];
  assertions: string[];
}

export interface PowerTelemetry {
  battery_percent: number | null;
  charging_state: "charging" | "full" | "plugged_in" | "battery";
  system_watts: number | null;
  adapter_input_watts: number | null;
  battery_watts: number | null;
  adapter_rating_watts: number | null;
  battery_voltage: number | null;
  battery_current_amps: number | null;
  time_remaining_minutes: number | null;
  updated_at_ms: number;
}

export const DURATION_PRESETS = [
  { label: "30m", seconds: 30 * 60 },
  { label: "1h", seconds: 60 * 60 },
  { label: "2h", seconds: 2 * 60 * 60 },
  { label: "4h", seconds: 4 * 60 * 60 },
  { label: "∞", seconds: null },
];

export interface ModeInfo {
  label: string;
  icon: LucideIcon;
  description: string;
  activeLabel: string;
}

export const MODE_INFO: Record<AssertionType, ModeInfo> = {
  NoIdleSleep: {
    label: "Keep awake",
    icon: Moon,
    description: "Keep your Mac working. The display can sleep.",
    activeLabel: "Your Mac stays awake",
  },
  NoDisplaySleep: {
    label: "Keep display on",
    icon: Monitor,
    description: "Keep your Mac and its display awake.",
    activeLabel: "Your display stays on",
  },
  ServerMode: {
    label: "Server Mode",
    icon: Server,
    description:
      "Keep your Mac awake with the lid closed. Requires administrator access.",
    activeLabel: "Lid-close sleep is disabled",
  },
  NetworkActive: {
    label: "Network",
    icon: Wifi,
    description:
      "Keeps system awake while serving network clients (file sharing, etc.).",
    activeLabel: "Serving network clients",
  },
  BackgroundTask: {
    label: "Background",
    icon: Cog,
    description:
      "Keeps process running for background work. System may enter low power.",
    activeLabel: "Running background task",
  },
};
