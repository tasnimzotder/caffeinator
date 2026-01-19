import { Moon, Monitor, Zap, Wifi, Cog } from "lucide-react";
import type { AssertionType } from "../types";

interface TimerProps {
  remainingSeconds: number | null;
  totalSeconds: number | null;
  mode: AssertionType | null;
}

function formatTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;

  if (h > 0) {
    return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  }
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function formatEndTime(seconds: number): string {
  const end = new Date(Date.now() + seconds * 1000);
  return end.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

const MODE_INFO: Record<AssertionType, { label: string; Icon: typeof Moon }> = {
  NoIdleSleep: { label: "Preventing idle sleep", Icon: Moon },
  NoDisplaySleep: { label: "Keeping display on", Icon: Monitor },
  PreventSystemSleep: { label: "Preventing all sleep", Icon: Zap },
  NetworkActive: { label: "Keeping network active", Icon: Wifi },
  BackgroundTask: { label: "Running background task", Icon: Cog },
};

export function Timer({ remainingSeconds, totalSeconds, mode }: TimerProps) {
  const modeInfo = mode ? MODE_INFO[mode] : null;

  if (remainingSeconds === null) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center py-6">
        <div className="text-6xl font-light text-white">∞</div>
        <p className="text-sm text-neutral-400 mt-2">Running indefinitely</p>
        {modeInfo && (
          <div className="flex items-center gap-2 mt-4 px-3 py-1.5 rounded-full bg-white/5">
            <modeInfo.Icon size={14} className="text-neutral-400" />
            <span className="text-xs text-neutral-400">{modeInfo.label}</span>
          </div>
        )}
      </div>
    );
  }

  const progress = totalSeconds
    ? ((totalSeconds - remainingSeconds) / totalSeconds) * 100
    : 0;

  return (
    <div className="flex-1 flex flex-col items-center justify-center py-6">
      <div className="text-5xl font-mono font-medium tracking-tight text-white tabular-nums">
        {formatTime(remainingSeconds)}
      </div>
      <p className="text-sm text-neutral-400 mt-1">remaining</p>

      {totalSeconds && (
        <div className="w-48 mt-4">
          <div className="h-1.5 bg-white/10 rounded-full overflow-hidden">
            <div
              className="h-full bg-linear-to-r from-emerald-500 to-emerald-400 rounded-full transition-all duration-1000 ease-linear"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>
      )}

      <div className="flex items-center gap-4 mt-4">
        {modeInfo && (
          <div className="flex items-center gap-1.5 text-xs text-neutral-500">
            <modeInfo.Icon size={12} />
            <span>{modeInfo.label}</span>
          </div>
        )}
      </div>

      {remainingSeconds > 0 && (
        <p className="text-xs text-neutral-500 mt-2">
          Ends at {formatEndTime(remainingSeconds)}
        </p>
      )}
    </div>
  );
}
