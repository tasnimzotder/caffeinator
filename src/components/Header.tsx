import type { CaffeinateStatus } from "../types";
import { MODE_INFO } from "../types";
import { PowerProfileButton } from "./PowerProfileButton";
import { CoffeeIcon } from "./CoffeeIcon";

interface HeaderProps {
  status: CaffeinateStatus;
}

export function Header({ status }: HeaderProps) {
  const modeLabel = status.mode ? MODE_INFO[status.mode].label : null;

  return (
    <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
      <div className="flex items-center gap-3">
        <div
          className={`${status.is_active ? "animate-bounce" : ""}`}
          style={{ animationDuration: "2s" }}
        >
          <CoffeeIcon size={28} className="text-neutral-300" />
        </div>
        <div>
          <h1 className="font-semibold text-white">
            Caffeinator
          </h1>
          <p className="text-xs">
            {status.is_active ? (
              <span className="text-amber-500 flex items-center gap-1">
                <span className="w-1.5 h-1.5 bg-amber-500 rounded-full animate-pulse" />
                Active — {modeLabel}
              </span>
            ) : (
              <span className="text-neutral-400">
                Ready
              </span>
            )}
          </p>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <PowerProfileButton />
      </div>
    </div>
  );
}
