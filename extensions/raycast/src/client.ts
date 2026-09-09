import { getPreferenceValues, showToast, Toast } from "@raycast/api";
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { request } from "./transport";

export const MODES = {
  NoIdleSleep: "Keep awake",
  NoDisplaySleep: "Keep display on",
  ServerMode: "Server Mode",
  NetworkActive: "Network",
  BackgroundTask: "Background",
} as const;
export type Mode = keyof typeof MODES;
export interface Status {
  is_active: boolean;
  mode: Mode | null;
  selected_mode: Mode;
  selected_duration: number | null;
  remaining_seconds: number | null;
  total_seconds: number | null;
  busy: boolean;
  recovery_required: boolean;
  error: string | null;
}
type Request =
  | { command: "status" | "stop" | "toggle" | "show" }
  | { command: "start"; mode: Mode; duration_secs: number | null };
interface Response {
  ok: boolean;
  status: Status;
  error: string | null;
}
const socketPath = join(homedir(), ".config", "caffeinator", "control.sock");
let launch: Promise<void> | undefined;

function validate(value: Response): Response {
  if (
    !value ||
    typeof value.ok !== "boolean" ||
    !value.status ||
    typeof value.status.is_active !== "boolean" ||
    !(value.status.selected_mode in MODES)
  ) {
    throw new Error(
      "Caffeinator returned an incompatible response. Update the app and extension together.",
    );
  }
  return value;
}
async function ensureRunning() {
  try {
    validate(await request<Response>(socketPath, { command: "status" }, 5000));
    return;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code !== "ENOENT" && code !== "ECONNREFUSED") throw error;
  }
  const preferences = getPreferenceValues<{
    launchAutomatically: boolean;
    appPath: string;
  }>();
  if (!preferences.launchAutomatically)
    throw new Error(
      "Open Caffeinator first, or enable automatic launch in extension preferences.",
    );
  if (!launch) {
    launch = (async () => {
      await promisify(execFile)("/usr/bin/open", [
        "-g",
        "-a",
        preferences.appPath,
      ]);
      for (let attempt = 0; attempt < 40; attempt++) {
        await new Promise((resolve) => setTimeout(resolve, 250));
        try {
          validate(
            await request<Response>(socketPath, { command: "status" }, 1000),
          );
          return;
        } catch (error) {
          const code = (error as NodeJS.ErrnoException).code;
          if (code !== "ENOENT" && code !== "ECONNREFUSED") throw error;
        }
      }
      throw new Error(
        "Caffeinator opened but its control service is unavailable. Install the updated app.",
      );
    })().finally(() => {
      launch = undefined;
    });
  }
  await launch;
}
export async function control(message: Request, allowLaunch = true): Promise<Status> {
  if (allowLaunch) await ensureRunning();
  const response = validate(
    await request<Response>(
      socketPath,
      message,
      message.command === "status" ? 5000 : 180000,
    ),
  );
  if (!response.ok)
    throw new Error(
      response.error ?? "Caffeinator could not complete the request.",
    );
  return response.status;
}
export async function reportError(error: unknown) {
  await showToast({
    style: Toast.Style.Failure,
    title: "Caffeinator needs attention",
    message: error instanceof Error ? error.message : String(error),
  });
}
export function remainingLabel(seconds: number | null): string {
  if (seconds === null) return "Until stopped";
  const hours = Math.floor(seconds / 3600),
    minutes = Math.floor((seconds % 3600) / 60),
    remainder = seconds % 60;
  return hours
    ? `${hours}h ${minutes}m ${remainder}s`
    : minutes
      ? `${minutes}m ${remainder}s`
      : `${remainder}s`;
}
