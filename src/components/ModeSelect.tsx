import type { AssertionType } from "../types";
import { MODE_INFO } from "../types";

interface ModeSelectProps {
  selected: AssertionType;
  onChange: (mode: AssertionType) => void;
  disabled?: boolean;
}

const MODES: AssertionType[] = [
  "NoIdleSleep",
  "NoDisplaySleep",
  "LidClose",
  "NetworkActive",
  "BackgroundTask",
];

export function ModeSelect({ selected, onChange, disabled }: ModeSelectProps) {
  return (
    <div className="px-4 py-3">
      <p className="text-[11px] font-medium text-neutral-500 uppercase tracking-wider mb-2">
        Mode
      </p>
      <div className="grid grid-cols-3 gap-2">
        {MODES.map((type) => {
          const { label, icon: Icon, description } = MODE_INFO[type];
          return (
            <button
              key={type}
              onClick={() => onChange(type)}
              disabled={disabled}
              title={description}
              className={`flex flex-col items-center gap-1.5 px-2 py-2.5 rounded-lg text-xs font-medium transition-all duration-150 ${
                selected === type
                  ? "bg-amber-500/10 text-white ring-1 ring-amber-500/40 shadow-[0_0_20px_rgba(245,158,11,0.15)]"
                  : "bg-white/5 text-neutral-400 hover:bg-white/10 hover:text-neutral-200 hover:scale-[1.02]"
              } active:scale-95 disabled:opacity-50`}
            >
              <Icon size={18} strokeWidth={1.5} />
              <span>{label}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
