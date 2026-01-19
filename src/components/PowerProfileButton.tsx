import { useState, useEffect } from "react";
import { Info, X, Battery, Plug, Moon, Monitor, HardDrive } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import type { PowerProfile } from "../types";

export function PowerProfileButton() {
  const [isOpen, setIsOpen] = useState(false);
  const [profile, setProfile] = useState<PowerProfile | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchProfile = async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await invoke<PowerProfile>("get_power_profile");
      setProfile(result);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen) {
      fetchProfile();
    }
  }, [isOpen]);

  const formatSleepTime = (minutes: number | null) => {
    if (minutes === null) return "Not set";
    if (minutes === 0) return "Never";
    if (minutes >= 60) {
      const h = Math.floor(minutes / 60);
      const m = minutes % 60;
      return m > 0 ? `${h}h ${m}m` : `${h}h`;
    }
    return `${minutes}m`;
  };

  return (
    <>
      <button
        onClick={() => setIsOpen(true)}
        className="p-1.5 rounded-lg hover:bg-white/10 transition-colors text-neutral-400 hover:text-white"
        title="Power Profile"
      >
        <Info size={16} />
      </button>

      {isOpen && (
        <div className="fixed inset-0 flex items-center justify-center z-50">
          <div
            className="absolute inset-0 bg-black/50"
            onClick={() => setIsOpen(false)}
          />
          <div className="relative bg-neutral-900 rounded-xl p-4 w-72 max-h-80 overflow-y-auto shadow-2xl border border-white/10">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-sm font-medium text-white">Power Profile</h2>
              <button
                onClick={() => setIsOpen(false)}
                className="p-1 rounded hover:bg-white/10 text-neutral-400 hover:text-white"
              >
                <X size={14} />
              </button>
            </div>

            {loading && (
              <div className="text-center py-4 text-neutral-400 text-sm">
                Loading...
              </div>
            )}

            {error && (
              <div className="text-center py-4 text-red-400 text-sm">
                {error}
              </div>
            )}

            {profile && !loading && (
              <div className="space-y-3">
                <div className="flex items-center gap-2 text-sm">
                  {profile.source === "AC Power" ? (
                    <Plug size={14} className="text-emerald-400" />
                  ) : (
                    <Battery size={14} className="text-yellow-400" />
                  )}
                  <span className="text-white">{profile.source}</span>
                </div>

                <div className="border-t border-white/10 pt-3 space-y-2">
                  <h3 className="text-xs font-medium text-neutral-500 uppercase tracking-wide">
                    Sleep Settings
                  </h3>
                  <div className="grid grid-cols-2 gap-2 text-xs">
                    <div className="flex items-center gap-1.5 text-neutral-400">
                      <Monitor size={12} />
                      <span>Display</span>
                    </div>
                    <div className="text-white text-right">
                      {formatSleepTime(profile.display_sleep)}
                    </div>

                    <div className="flex items-center gap-1.5 text-neutral-400">
                      <HardDrive size={12} />
                      <span>Disk</span>
                    </div>
                    <div className="text-white text-right">
                      {formatSleepTime(profile.disk_sleep)}
                    </div>

                    <div className="flex items-center gap-1.5 text-neutral-400">
                      <Moon size={12} />
                      <span>System</span>
                    </div>
                    <div className="text-white text-right">
                      {formatSleepTime(profile.system_sleep)}
                    </div>
                  </div>
                </div>

                {profile.assertions.length > 0 && (
                  <div className="border-t border-white/10 pt-3 space-y-2">
                    <h3 className="text-xs font-medium text-neutral-500 uppercase tracking-wide">
                      Active Assertions ({profile.assertions.length})
                    </h3>
                    <div className="space-y-1 max-h-24 overflow-y-auto">
                      {profile.assertions.map((assertion, i) => (
                        <div
                          key={i}
                          className="text-xs text-neutral-400 truncate"
                          title={assertion}
                        >
                          {assertion}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}
