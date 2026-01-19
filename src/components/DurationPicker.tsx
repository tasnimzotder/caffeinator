import { useState } from "react";
import { DURATION_PRESETS } from "../types";

interface DurationPickerProps {
  onSelect: (seconds: number | null) => void;
  disabled?: boolean;
}

export function DurationPicker({ onSelect, disabled }: DurationPickerProps) {
  const [showCustom, setShowCustom] = useState(false);
  const [hours, setHours] = useState(0);
  const [minutes, setMinutes] = useState(30);

  const handleCustomSubmit = () => {
    const totalSeconds = hours * 3600 + minutes * 60;
    if (totalSeconds > 0) {
      onSelect(totalSeconds);
      setShowCustom(false);
    }
  };

  if (showCustom) {
    return (
      <div className="px-4 py-3 border-t border-white/5">
        <p className="text-[11px] font-medium text-neutral-500 uppercase tracking-wider mb-3">
          Custom Duration
        </p>
        <div className="flex items-center gap-3">
          <div className="flex-1">
            <label className="text-xs text-neutral-500">Hours</label>
            <input
              type="number"
              min={0}
              max={24}
              value={hours}
              onChange={(e) => setHours(Math.max(0, parseInt(e.target.value) || 0))}
              className="w-full mt-1 px-3 py-2 rounded-lg bg-white/5 text-white border border-white/10 focus:border-white/20 focus:outline-none"
            />
          </div>
          <div className="flex-1">
            <label className="text-xs text-neutral-500">Minutes</label>
            <input
              type="number"
              min={0}
              max={59}
              value={minutes}
              onChange={(e) =>
                setMinutes(Math.max(0, Math.min(59, parseInt(e.target.value) || 0)))
              }
              className="w-full mt-1 px-3 py-2 rounded-lg bg-white/5 text-white border border-white/10 focus:border-white/20 focus:outline-none"
            />
          </div>
        </div>
        <div className="flex gap-2 mt-3">
          <button
            onClick={() => setShowCustom(false)}
            className="flex-1 px-3 py-2 rounded-lg text-sm font-medium bg-white/5 text-neutral-300 hover:bg-white/10 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleCustomSubmit}
            disabled={hours === 0 && minutes === 0}
            className="flex-1 px-3 py-2 rounded-lg text-sm font-medium bg-emerald-600 text-white hover:bg-emerald-500 disabled:opacity-50 transition-colors"
          >
            Start
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="px-4 py-3 border-t border-white/5">
      <p className="text-[11px] font-medium text-neutral-500 uppercase tracking-wider mb-2">
        Duration
      </p>
      <div className="flex gap-2">
        {DURATION_PRESETS.map(({ label, seconds }) => (
          <button
            key={label}
            onClick={() => onSelect(seconds)}
            disabled={disabled}
            className="flex-1 px-3 py-2.5 rounded-lg text-sm font-medium bg-white/5 text-neutral-300 hover:bg-white/10 hover:text-white disabled:opacity-50 transition-all"
          >
            {label}
          </button>
        ))}
      </div>
      <button
        onClick={() => setShowCustom(true)}
        disabled={disabled}
        className="w-full mt-2 px-3 py-2 rounded-lg text-sm text-neutral-500 hover:text-neutral-300 hover:bg-white/5 disabled:opacity-50 transition-all"
      >
        Custom...
      </button>
    </div>
  );
}
