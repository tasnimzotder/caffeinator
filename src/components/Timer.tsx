import type { AssertionType } from "../types";
import { MODE_INFO } from "../types";

interface TimerProps {
  remainingSeconds: number | null;
  totalSeconds: number | null;
  mode: AssertionType | null;
  onStop: () => void;
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

const CIRCUMFERENCE = 2 * Math.PI * 80; // r=80

export function Timer({ remainingSeconds, totalSeconds, mode, onStop }: TimerProps) {
  const modeInfo = mode ? MODE_INFO[mode] : null;

  // Indefinite mode
  if (remainingSeconds === null) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center py-6">
        <div className="relative w-40 h-40 flex items-center justify-center">
          <svg viewBox="0 0 180 180" width="160" height="160" className="absolute inset-0">
            <defs>
              <linearGradient id="ring-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor="#f59e0b" />
                <stop offset="100%" stopColor="#fb923c" />
              </linearGradient>
            </defs>
            {/* Background track */}
            <circle cx="90" cy="90" r="80" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="6" />
            {/* Pulsing ring at ~30% */}
            <circle
              cx="90" cy="90" r="80"
              fill="none"
              stroke="url(#ring-gradient)"
              strokeWidth="6"
              strokeLinecap="round"
              strokeDasharray={CIRCUMFERENCE}
              strokeDashoffset={CIRCUMFERENCE * 0.3}
              transform="rotate(-90 90 90)"
              className="ring-pulse"
              style={{ filter: "drop-shadow(0 0 12px rgba(245, 158, 11, 0.4))" }}
            />
          </svg>
          <div className="relative text-center">
            <div className="text-4xl font-light text-white">∞</div>
          </div>
        </div>
        <p className="text-sm text-neutral-400 mt-3">Running indefinitely</p>
        {modeInfo && (
          <div className="flex items-center gap-2 mt-3 px-3 py-1.5 rounded-full bg-white/5">
            <modeInfo.icon size={14} className="text-neutral-400" />
            <span className="text-xs text-neutral-400">{modeInfo.activeLabel}</span>
          </div>
        )}
        <button
          onClick={onStop}
          className="mt-4 px-5 py-1.5 text-sm font-medium text-red-500 hover:text-red-400 hover:bg-red-500/10 rounded-lg transition-all"
        >
          Stop
        </button>
      </div>
    );
  }

  // Timed mode
  const progress = totalSeconds
    ? ((totalSeconds - remainingSeconds) / totalSeconds)
    : 0;
  const offset = progress * CIRCUMFERENCE;

  return (
    <div className="flex-1 flex flex-col items-center justify-center py-6">
      <div className="relative w-40 h-40 flex items-center justify-center">
        <svg viewBox="0 0 180 180" width="160" height="160" className="absolute inset-0">
          <defs>
            <linearGradient id="ring-gradient-timed" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#f59e0b" />
              <stop offset="100%" stopColor="#fb923c" />
            </linearGradient>
          </defs>
          {/* Background track */}
          <circle cx="90" cy="90" r="80" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="6" />
          {/* Progress ring */}
          <circle
            cx="90" cy="90" r="80"
            fill="none"
            stroke="url(#ring-gradient-timed)"
            strokeWidth="6"
            strokeLinecap="round"
            strokeDasharray={CIRCUMFERENCE}
            strokeDashoffset={offset}
            transform="rotate(-90 90 90)"
            style={{
              transition: "stroke-dashoffset 1s linear",
              filter: "drop-shadow(0 0 12px rgba(245, 158, 11, 0.4))",
            }}
          />
        </svg>
        <div className="relative text-center">
          <div className="text-3xl font-mono font-medium tracking-tight text-white tabular-nums">
            {formatTime(remainingSeconds)}
          </div>
          <p className="text-sm text-neutral-400 mt-0.5">remaining</p>
        </div>
      </div>

      <div className="flex items-center gap-4 mt-4">
        {modeInfo && (
          <div className="flex items-center gap-1.5 text-xs text-neutral-500">
            <modeInfo.icon size={12} />
            <span>{modeInfo.activeLabel}</span>
          </div>
        )}
      </div>

      {remainingSeconds > 0 && (
        <p className="text-xs text-neutral-500 mt-2">
          Ends at {formatEndTime(remainingSeconds)}
        </p>
      )}

      <button
        onClick={onStop}
        className="mt-4 px-5 py-1.5 text-sm font-medium text-red-500 hover:text-red-400 hover:bg-red-500/10 rounded-lg transition-all"
      >
        Stop
      </button>
    </div>
  );
}
