import type { CaffeinateStatus } from "../types";
import { PowerProfileButton } from "./PowerProfileButton";
import { CoffeeIcon } from "./CoffeeIcon";

interface HeaderProps {
  status: CaffeinateStatus;
  onStop: () => void;
}

export function Header({ status, onStop }: HeaderProps) {
  const modeLabel = status.mode
    ? {
        NoIdleSleep: "Idle",
        NoDisplaySleep: "Display",
        PreventSystemSleep: "System",
        NetworkActive: "Network",
        BackgroundTask: "Background",
      }[status.mode]
    : null;

  return (
    <div className="flex items-center justify-between px-4 py-3 border-b border-white/10 dark:border-white/5">
      <div className="flex items-center gap-3">
        <div
          className={`${status.is_active ? "animate-bounce" : ""}`}
          style={{ animationDuration: "2s" }}
        >
          <CoffeeIcon size={28} className="text-neutral-700 dark:text-neutral-300" />
        </div>
        <div>
          <h1 className="font-semibold text-neutral-800 dark:text-white">
            Caffeinator
          </h1>
          <p className="text-xs">
            {status.is_active ? (
              <span className="text-emerald-500 dark:text-emerald-400 flex items-center gap-1">
                <span className="w-1.5 h-1.5 bg-emerald-500 rounded-full animate-pulse" />
                Active — {modeLabel}
              </span>
            ) : (
              <span className="text-neutral-500 dark:text-neutral-400">
                Ready
              </span>
            )}
          </p>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <PowerProfileButton />
        {status.is_active && (
          <button
            onClick={onStop}
            className="px-3 py-1.5 text-sm font-medium text-red-500 hover:text-red-400 hover:bg-red-500/10 rounded-lg transition-all"
          >
            Stop
          </button>
        )}
      </div>
    </div>
  );
}
