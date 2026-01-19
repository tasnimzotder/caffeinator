import { useState, useEffect } from "react";
import "./App.css";
import { useCaffeinate } from "./hooks/useCaffeinate";
import { Header } from "./components/Header";
import { Timer } from "./components/Timer";
import { ModeSelect } from "./components/ModeSelect";
import { DurationPicker } from "./components/DurationPicker";
import { Github, LogOut } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { getVersion } from "@tauri-apps/api/app";
import type { AssertionType } from "./types";

function App() {
  const { status, loading, error, activate, deactivate } = useCaffeinate();
  const [selectedMode, setSelectedMode] = useState<AssertionType>("NoIdleSleep");
  const [autostart, setAutostart] = useState(false);
  const [version, setVersion] = useState("");

  useEffect(() => {
    invoke<boolean>("get_autostart_enabled").then(setAutostart).catch(() => {});
    getVersion().then(setVersion).catch(() => {});
  }, []);

  const toggleAutostart = async () => {
    const newValue = !autostart;
    try {
      await invoke("set_autostart_enabled", { enabled: newValue });
      setAutostart(newValue);
    } catch {
      // Revert on error
    }
  };

  const handleActivate = (durationSecs: number | null) => {
    activate(selectedMode, durationSecs);
  };

  return (
    <div className="h-screen p-2">
      <div className="app-container h-full flex flex-col">
        <Header status={status} onStop={deactivate} />

        {error && (
          <div className="px-4 py-2 bg-red-500/20 text-red-400 text-xs">
            Error: {error}
          </div>
        )}

        <div className="flex-1">
          {status.is_active ? (
            <Timer
              remainingSeconds={status.remaining_seconds}
              totalSeconds={status.total_seconds}
              mode={status.mode}
            />
          ) : (
            <>
              <ModeSelect
                selected={selectedMode}
                onChange={setSelectedMode}
                disabled={loading}
              />
              <DurationPicker onSelect={handleActivate} disabled={loading} />
            </>
          )}
        </div>

        <footer className="px-4 py-2 border-t border-white/10 flex items-center justify-between">
          <button
            onClick={toggleAutostart}
            className="flex items-center gap-2 text-xs text-neutral-500 hover:text-neutral-300 transition-colors"
          >
            <div
              className={`w-8 h-4 rounded-full transition-colors ${
                autostart ? "bg-emerald-600" : "bg-white/20"
              }`}
            >
              <div
                className={`w-4 h-4 rounded-full bg-white shadow transition-transform ${
                  autostart ? "translate-x-4" : "translate-x-0"
                }`}
              />
            </div>
            <span>Launch at Login</span>
          </button>
          <div className="flex items-center gap-3">
            {version && (
              <span className="text-[10px] text-neutral-600">v{version}</span>
            )}
            <a
              href="https://github.com/tasnimzotder/caffeinator"
              target="_blank"
              rel="noopener noreferrer"
              className="text-neutral-500 hover:text-neutral-300 transition-colors"
            >
              <Github size={14} />
            </a>
            <button
              onClick={() => invoke("quit_app")}
              className="text-neutral-500 hover:text-red-400 transition-colors"
            >
              <LogOut size={14} />
            </button>
          </div>
        </footer>
      </div>
    </div>
  );
}

export default App;
