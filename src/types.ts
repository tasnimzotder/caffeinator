export type AssertionType = "NoIdleSleep" | "NoDisplaySleep" | "PreventSystemSleep" | "NetworkActive" | "BackgroundTask";

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
