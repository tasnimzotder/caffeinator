import { Moon, Monitor, Wifi, Cog, type LucideIcon } from "lucide-react";

export type AssertionType = "NoIdleSleep" | "NoDisplaySleep" | "NetworkActive" | "BackgroundTask";

export interface CaffeinateStatus {
  is_active: boolean;
  mode: AssertionType | null;
  remaining_seconds: number | null;
  total_seconds: number | null;
}

export interface PowerProfile {
  source: string;
  display_sleep: number | null;
  disk_sleep: number | null;
  system_sleep: number | null;
  assertions: string[];
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
  NoIdleSleep: { label: "Idle", icon: Moon, description: "Prevents idle system sleep. Display may still dim or turn off.", activeLabel: "Preventing idle sleep" },
  NoDisplaySleep: { label: "Display", icon: Monitor, description: "Keeps display on and prevents idle sleep. Lid close still sleeps.", activeLabel: "Keeping display on" },
  NetworkActive: { label: "Network", icon: Wifi, description: "Keeps system awake while serving network clients (file sharing, etc.).", activeLabel: "Serving network clients" },
  BackgroundTask: { label: "Background", icon: Cog, description: "Keeps process running for background work. System may enter low power.", activeLabel: "Running background task" },
};
