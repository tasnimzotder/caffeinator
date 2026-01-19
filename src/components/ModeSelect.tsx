import { Moon, Monitor, Zap, Wifi, Cog } from "lucide-react";
import type { AssertionType } from "../types";

interface ModeSelectProps {
  selected: AssertionType;
  onChange: (mode: AssertionType) => void;
  disabled?: boolean;
}

const MODES: { type: AssertionType; label: string; Icon: typeof Moon; description: string }[] = [
  { type: "NoIdleSleep", label: "Idle", Icon: Moon, description: "Prevents system from sleeping when idle. Display may still turn off." },
  { type: "NoDisplaySleep", label: "Display", Icon: Monitor, description: "Keeps display on and prevents idle sleep." },
  { type: "PreventSystemSleep", label: "System", Icon: Zap, description: "Prevents all sleep, even when lid is closed (AC power only)." },
  { type: "NetworkActive", label: "Network", Icon: Wifi, description: "Keeps network connections alive for downloads and uploads." },
  { type: "BackgroundTask", label: "Background", Icon: Cog, description: "Allows background tasks to complete, may enter low power mode." },
];

export function ModeSelect({ selected, onChange, disabled }: ModeSelectProps) {
  return (
    <div className="px-4 py-3">
      <p className="text-[11px] font-medium text-neutral-500 uppercase tracking-wider mb-2">
        Mode
      </p>
      <div className="grid grid-cols-3 gap-2">
        {MODES.map(({ type, label, Icon, description }) => (
          <button
            key={type}
            onClick={() => onChange(type)}
            disabled={disabled}
            title={description}
            className={`flex flex-col items-center gap-1.5 px-2 py-2.5 rounded-lg text-xs font-medium transition-all ${
              selected === type
                ? "bg-white/15 text-white ring-1 ring-white/20"
                : "bg-white/5 text-neutral-400 hover:bg-white/10 hover:text-neutral-200"
            } disabled:opacity-50`}
          >
            <Icon size={18} strokeWidth={1.5} />
            <span>{label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
