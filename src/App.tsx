import { useCallback, useEffect, useState } from "react";
import {
  Activity,
  ArrowRight,
  Check,
  ChevronDown,
  Clock3,
  Coffee,
  Command,
  ExternalLink,
  LoaderCircle,
  Monitor,
  Moon,
  Play,
  Power,
  RefreshCw,
  Settings2,
  ShieldCheck,
  Square,
  X,
  Zap,
} from "lucide-react";
import { getVersion } from "@tauri-apps/api/app";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useCaffeinate } from "./hooks/useCaffeinate";
import { command, native } from "./lib/backend";
import { MODE_INFO, type AssertionType, type PowerProfile } from "./types";
import "./App.css";
import { PowerTelemetry } from "./components/PowerTelemetry";
import { PowerHistory } from "./components/PowerHistory";

type View = "session" | "power" | "settings";
const PRESETS = [
  { label: "30 min", value: 1800 },
  { label: "1 hour", value: 3600 },
  { label: "2 hours", value: 7200 },
  { label: "4 hours", value: 14400 },
  { label: "Until stopped", value: null },
];
const MODES: AssertionType[] = ["NoIdleSleep", "NoDisplaySleep"];
const ADVANCED: AssertionType[] = [
  "ServerMode",
  "NetworkActive",
  "BackgroundTask",
];
function durationLabel(seconds: number | null): string {
  if (seconds === null) return "Until stopped";
  const h = Math.floor(seconds / 3600),
    m = Math.floor((seconds % 3600) / 60);
  if (seconds < 60) return `${seconds} sec`;
  return [h ? `${h}h` : "", m ? `${m}m` : ""].filter(Boolean).join(" ");
}
function countdown(seconds: number): string {
  const h = Math.floor(seconds / 3600),
    m = Math.floor((seconds % 3600) / 60),
    s = seconds % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
    : `${m}:${String(s).padStart(2, "0")}`;
}
function sleepLabel(minutes: number | null) {
  return minutes === null
    ? "Unavailable"
    : minutes === 0
      ? "Never"
      : durationLabel(minutes * 60);
}

function App() {
  const {
    status,
    ready,
    loading,
    error,
    activate,
    deactivate,
    selectMode,
    selectDuration,
    refresh,
    dismissError,
  } = useCaffeinate();
  const [view, setView] = useState<View>("session");
  const [advanced, setAdvanced] = useState<boolean | null>(null);
  const [custom, setCustom] = useState(false);
  const [hours, setHours] = useState("1");
  const [minutes, setMinutes] = useState("0");
  const [autostart, setAutostart] = useState(false);
  const [settingsLoading, setSettingsLoading] = useState(true);
  const [settingsError, setSettingsError] = useState<string | null>(null);
  const [version, setVersion] = useState("");
  const [profile, setProfile] = useState<PowerProfile | null>(null);
  const [profileLoading, setProfileLoading] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);
  const selected = status.selected_mode;
  const selectedDuration = status.selected_duration;
  const blocked = !ready || loading;
  const modeInfo = MODE_INFO[status.mode ?? selected];
  const endTime =
    status.remaining_seconds === null
      ? null
      : new Date(
          Date.now() + status.remaining_seconds * 1000,
        ).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

  useEffect(() => {
    command<boolean>("get_autostart_enabled")
      .then(setAutostart)
      .catch((e) => setSettingsError(String(e)))
      .finally(() => setSettingsLoading(false));
    if (native)
      getVersion()
        .then(setVersion)
        .catch(() => setVersion("Unknown"));
    else setVersion("Development preview");
  }, []);

  const fetchProfile = useCallback(async () => {
    setProfileLoading(true);
    setProfileError(null);
    try {
      setProfile(await command<PowerProfile>("get_power_profile"));
    } catch (e) {
      setProfileError(String(e));
    } finally {
      setProfileLoading(false);
    }
  }, []);
  useEffect(() => {
    if (view !== "power") return;
    fetchProfile();
    const onFocus = () => fetchProfile();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [view, status.is_active, status.recovery_required, fetchProfile]);

  const hide = useCallback(() => {
    command("hide_window").catch((e) => setSettingsError(String(e)));
  }, []);
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        hide();
      }
      if (
        event.metaKey &&
        event.key === "Enter" &&
        view === "session" &&
        !blocked &&
        !custom
      ) {
        event.preventDefault();
        if (status.is_active) deactivate();
        else activate(selected, selectedDuration);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [
    hide,
    view,
    blocked,
    custom,
    status.is_active,
    selected,
    selectedDuration,
    activate,
    deactivate,
  ]);

  async function toggleAutostart() {
    setSettingsLoading(true);
    setSettingsError(null);
    try {
      await command("set_autostart_enabled", { enabled: !autostart });
      setAutostart(!autostart);
    } catch (e) {
      setSettingsError(String(e));
    } finally {
      setSettingsLoading(false);
    }
  }
  async function openGuide() {
    const url = "https://github.com/tasnimzotder/caffeinator#raycast";
    try {
      if (native) await openUrl(url);
      else window.open(url, "_blank", "noopener,noreferrer");
    } catch (e) {
      setSettingsError(String(e));
    }
  }
  const customSeconds = Number(hours) * 3600 + Number(minutes) * 60;
  const validCustom =
    Number.isInteger(Number(hours)) &&
    Number.isInteger(Number(minutes)) &&
    Number(hours) >= 0 &&
    Number(minutes) >= 0 &&
    Number(minutes) < 60 &&
    customSeconds > 0 &&
    customSeconds <= 604800;
  const showAdvanced = advanced ?? ADVANCED.includes(selected);

  return (
    <div className="app-shell">
      <header className="app-header" data-tauri-drag-region>
        <div className="brand">
          <span className="brand-icon">
            <Coffee size={21} strokeWidth={1.6} />
          </span>
          <div>
            <span className="brand-name">Caffeinator</span>
            <span className="brand-caption">A little extra uptime.</span>
          </div>
        </div>
        <div className="header-right">
          <span
            className={`status-pill ${status.recovery_required ? "warning" : status.is_active ? "active" : ""}`}
          >
            <span className="status-dot" />
            {loading
              ? "Working"
              : !ready
                ? "Connecting"
                : status.recovery_required
                  ? "Needs attention"
                  : status.is_active
                    ? "Awake"
                    : "Standby"}
          </span>
          <button
            className="icon-button"
            onClick={hide}
            aria-label="Hide Caffeinator"
            title="Hide · Esc"
          >
            <X size={18} />
          </button>
        </div>
      </header>
      <nav className="navigation" aria-label="Main navigation">
        {(
          [
            { id: "session", label: "Session", icon: Clock3 },
            { id: "power", label: "Power", icon: Activity },
            { id: "settings", label: "Settings", icon: Settings2 },
          ] as const
        ).map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            className={view === id ? "nav-item selected" : "nav-item"}
            aria-current={view === id ? "page" : undefined}
            onClick={() => setView(id)}
          >
            <Icon size={16} />
            {label}
          </button>
        ))}
      </nav>
      <main className="main-content" id="main-content">
        {(error || settingsError) && (
          <div className="notice error-notice" role="alert">
            <ShieldCheck size={18} />
            <div>
              <strong>
                {status.recovery_required
                  ? "Restore your sleep settings"
                  : "Something needs attention"}
              </strong>
              <p>{error || settingsError}</p>
              <div className="notice-actions">
                <button
                  onClick={() => {
                    dismissError();
                    setSettingsError(null);
                    if (status.is_active) deactivate();
                    else refresh();
                  }}
                  disabled={loading}
                >
                  {status.is_active ? "Retry stop & restore" : "Refresh status"}
                </button>
                {!status.recovery_required && (
                  <button
                    onClick={() => {
                      dismissError();
                      setSettingsError(null);
                    }}
                  >
                    Dismiss
                  </button>
                )}
              </div>
            </div>
          </div>
        )}
        {view === "session" && (
          <section className="view-enter" aria-labelledby="session-heading">
            {!status.is_active ? (
              <>
                <div className="session-intro">
                  <div>
                    <h1 id="session-heading">Keep awake, your way.</h1>
                    <p>Pick a mode, set a duration, and carry on.</p>
                  </div>
                  <div className="coffee-orbit" aria-hidden="true">
                    <span className="orbit orbit-one" />
                    <span className="orbit orbit-two" />
                    <span className="orbit-spark">
                      <Zap size={13} fill="currentColor" />
                    </span>
                    <Coffee size={30} strokeWidth={1.2} />
                    <span className="orbit-dot" />
                  </div>
                </div>
                <div className="mode-grid">
                  {MODES.map((mode) => (
                    <ModeCard
                      key={mode}
                      mode={mode}
                      selected={selected === mode}
                      disabled={blocked}
                      onSelect={() => selectMode(mode)}
                    />
                  ))}
                </div>
                <button
                  className="disclosure"
                  aria-expanded={showAdvanced}
                  onClick={() => setAdvanced(!showAdvanced)}
                >
                  <ChevronDown
                    size={14}
                    className={showAdvanced ? "rotated" : ""}
                  />
                  More modes<span>Server, network & background</span>
                </button>
                {showAdvanced && (
                  <div className="advanced-modes">
                    {ADVANCED.map((mode) => (
                      <ModeCard
                        key={mode}
                        mode={mode}
                        selected={selected === mode}
                        disabled={blocked}
                        onSelect={() => selectMode(mode)}
                      />
                    ))}
                  </div>
                )}
                {selected === "ServerMode" && (
                  <div className="notice server-notice">
                    <ShieldCheck size={17} />
                    <p>
                      Administrator access is needed to start and restore Server
                      Mode. Your original sleep setting is saved for recovery.
                    </p>
                  </div>
                )}
                <div className="section-heading duration-heading">
                  <h2>How long?</h2>
                  <button
                    className={
                      custom ? "text-button selected-text" : "text-button"
                    }
                    onClick={() => {
                      setCustom(!custom);
                      setHours(
                        String(Math.floor((selectedDuration ?? 3600) / 3600)),
                      );
                      setMinutes(
                        String(
                          Math.floor(((selectedDuration ?? 3600) % 3600) / 60),
                        ),
                      );
                    }}
                    disabled={blocked}
                  >
                    Custom duration
                  </button>
                </div>
                <div
                  className="duration-options"
                  role="group"
                  aria-label="Session duration"
                >
                  {PRESETS.map(({ label, value }) => (
                    <button
                      key={label}
                      aria-pressed={selectedDuration === value && !custom}
                      className={
                        selectedDuration === value && !custom
                          ? "duration-option chosen"
                          : "duration-option"
                      }
                      disabled={blocked}
                      onClick={() => {
                        setCustom(false);
                        selectDuration(value);
                      }}
                    >
                      {label}
                    </button>
                  ))}
                </div>
                {custom && (
                  <form
                    className="custom-duration"
                    onSubmit={(event) => {
                      event.preventDefault();
                      if (validCustom) {
                        selectDuration(customSeconds);
                        setCustom(false);
                      }
                    }}
                  >
                    <label>
                      Hours
                      <input
                        type="number"
                        min="0"
                        max="168"
                        value={hours}
                        onChange={(e) => setHours(e.target.value)}
                      />
                    </label>
                    <label>
                      Minutes
                      <input
                        type="number"
                        min="0"
                        max="59"
                        value={minutes}
                        onChange={(e) => setMinutes(e.target.value)}
                      />
                    </label>
                    <button
                      className="secondary-button"
                      type="submit"
                      disabled={!validCustom || blocked}
                    >
                      Set duration
                    </button>
                    <p>
                      Up to 7 days. Use “Until stopped” for longer sessions.
                    </p>
                  </form>
                )}
                {!custom &&
                  !PRESETS.some((p) => p.value === selectedDuration) && (
                    <p className="custom-summary">
                      <Clock3 size={14} />
                      Custom duration: {durationLabel(selectedDuration)}
                    </p>
                  )}
                <div className="session-action">
                  <button
                    className="primary-button"
                    disabled={blocked || custom}
                    onClick={() => activate(selected, selectedDuration)}
                  >
                    {loading ? (
                      <LoaderCircle size={18} className="spin" />
                    ) : (
                      <Play size={17} fill="currentColor" />
                    )}
                    <span>
                      {loading ? "Starting your session…" : "Start session"}
                    </span>
                    <span className="button-detail">
                      {durationLabel(selectedDuration)}
                      <ArrowRight size={16} />
                    </span>
                  </button>
                  <p>
                    <ShieldCheck size={13} />
                    {selected === "ServerMode"
                      ? "Sleep settings will be restored when you stop."
                      : "Your normal sleep settings stay untouched."}
                    <kbd>⌘ ↵</kbd>
                  </p>
                </div>
              </>
            ) : (
              <>
                <div className="active-intro">
                  <span className="eyebrow">
                    {status.recovery_required
                      ? "RESTORATION NEEDED"
                      : "SESSION IN PROGRESS"}
                  </span>
                  <h1 id="session-heading">
                    {status.recovery_required
                      ? "Let’s finish safely."
                      : "You’re good to go."}
                  </h1>
                  <p>
                    {status.recovery_required
                      ? "Restore your previous sleep settings to finish this session."
                      : "Your Mac stays awake. Get on with your thing."}
                  </p>
                </div>
                <div
                  className={`timer-card ${status.recovery_required ? "needs-recovery" : ""}`}
                >
                  <div className="timer-top">
                    <span>
                      <span className="status-dot" />
                      {status.recovery_required
                        ? "Action required"
                        : modeInfo.activeLabel}
                    </span>
                    <Coffee size={22} strokeWidth={1.4} />
                  </div>
                  <div
                    className="timer-value"
                    role="timer"
                    aria-live="off"
                    aria-label={
                      status.remaining_seconds === null
                        ? "Running until stopped"
                        : `${status.remaining_seconds} seconds remaining`
                    }
                  >
                    {status.recovery_required ? (
                      <ShieldCheck size={58} strokeWidth={1.2} />
                    ) : status.remaining_seconds === null ? (
                      <span className="infinity">∞</span>
                    ) : (
                      countdown(status.remaining_seconds)
                    )}
                  </div>
                  <p className="timer-caption">
                    {status.recovery_required
                      ? "Your Mac may still have sleep disabled"
                      : status.remaining_seconds === null
                        ? "All the time you need"
                        : "remaining in this session"}
                  </p>
                  <div
                    className="progress-track"
                    role="progressbar"
                    aria-label="Session progress"
                    aria-valuemin={0}
                    aria-valuemax={100}
                    aria-valuenow={
                      status.total_seconds
                        ? Math.round(
                            (1 -
                              (status.remaining_seconds ?? 0) /
                                status.total_seconds) *
                              100,
                          )
                        : undefined
                    }
                  >
                    <span
                      style={{
                        width: status.total_seconds
                          ? `${Math.max(0, Math.min(100, (1 - (status.remaining_seconds ?? 0) / status.total_seconds) * 100))}%`
                          : "100%",
                      }}
                    />
                  </div>
                  <div className="timer-bottom">
                    <span>{durationLabel(status.total_seconds)} session</span>
                    <span>
                      {status.recovery_required
                        ? "Restore to finish"
                        : endTime
                          ? `Ends at ${endTime}`
                          : "Stop whenever you’re ready"}
                    </span>
                  </div>
                </div>
                <div className="session-facts">
                  <div>
                    <modeInfo.icon size={18} />
                    <span>
                      Active mode<strong>{modeInfo.label}</strong>
                    </span>
                  </div>
                  <div>
                    <Monitor size={18} />
                    <span>
                      Display
                      <strong>
                        {status.mode === "NoDisplaySleep"
                          ? "Stays on"
                          : "Follows macOS settings"}
                      </strong>
                    </span>
                  </div>
                </div>
                {status.mode === "ServerMode" && (
                  <div className="notice server-notice">
                    <ShieldCheck size={17} />
                    <p>
                      Stopping may ask for your administrator password to
                      restore the previous sleep setting.
                    </p>
                  </div>
                )}
                <button
                  className={
                    status.recovery_required ? "primary-button" : "stop-button"
                  }
                  onClick={deactivate}
                  disabled={blocked}
                >
                  {loading ? (
                    <LoaderCircle className="spin" size={17} />
                  ) : (
                    <Square size={14} fill="currentColor" />
                  )}
                  {loading
                    ? "Restoring sleep settings…"
                    : status.recovery_required
                      ? "Restore sleep settings"
                      : "End session"}
                  <kbd>⌘ ↵</kbd>
                </button>
                <p className="understated">
                  You can hide this window. Your session keeps running.
                </p>
              </>
            )}
          </section>
        )}
        {view === "power" && (
          <section className="view-enter" aria-labelledby="power-heading">
            <div className="page-heading">
              <div>
                <h1 id="power-heading">Power</h1>
                <p>Live draw, recorded trends, and sleep settings.</p>
              </div>
              <button
                className="icon-button bordered"
                aria-label="Refresh power information"
                onClick={fetchProfile}
                disabled={profileLoading}
              >
                <RefreshCw size={17} className={profileLoading ? "spin" : ""} />
              </button>
            </div>
            <PowerTelemetry />
            <PowerHistory />
            {profileError && (
              <div className="notice error-notice" role="alert">
                <p>{profileError}</p>
              </div>
            )}
            {!profile && profileLoading && (
              <div className="empty-state">
                <LoaderCircle className="spin" />
                <p>Reading power information…</p>
              </div>
            )}
            {profile && (
              <>
                <div className="section-heading">
                  <h2>Sleep preferences</h2>
                  <span>MACOS</span>
                </div>
                <div className="settings-card">
                  <PowerRow
                    icon={Monitor}
                    title="Display sleep"
                    detail="When your screen turns off"
                    value={sleepLabel(profile.display_sleep)}
                  />
                  <PowerRow
                    icon={Moon}
                    title="System sleep"
                    detail={
                      profile.sleep_disabled
                        ? "Global sleep override is enabled"
                        : profile.system_sleep_prevented_by.length
                          ? `Prevented by ${profile.system_sleep_prevented_by.join(", ")}`
                          : "When your Mac goes to sleep"
                    }
                    value={
                      profile.sleep_disabled ||
                      profile.system_sleep_prevented_by.length
                        ? "Prevented"
                        : sleepLabel(profile.system_sleep)
                    }
                  />
                  <PowerRow
                    icon={Power}
                    title="Disk sleep"
                    detail="When idle disks power down"
                    value={sleepLabel(profile.disk_sleep)}
                  />
                </div>
                <div className="section-heading">
                  <h2>Keeping your Mac awake</h2>
                  <span>{profile.assertions.length} ACTIVE</span>
                </div>
                <div className="assertion-list">
                  {profile.assertions.length ? (
                    profile.assertions.map((assertion, index) => (
                      <div key={index}>
                        <span className="assertion-dot" />
                        <span>{assertion}</span>
                      </div>
                    ))
                  ) : (
                    <div className="empty-assertions">
                      <Check size={18} />
                      <span>No active power assertions.</span>
                    </div>
                  )}
                </div>
                <p className="understated align-left">
                  A snapshot from macOS. Refresh to see the latest changes.
                </p>
              </>
            )}
          </section>
        )}
        {view === "settings" && (
          <section className="view-enter" aria-labelledby="settings-heading">
            <div className="page-heading">
              <div>
                <span className="eyebrow">MAKE IT YOURS</span>
                <h1 id="settings-heading">Small details. Your way.</h1>
                <p>Ready when you need a little more uptime.</p>
              </div>
            </div>
            <div className="section-heading">
              <h2>General</h2>
            </div>
            <div className="settings-card">
              <div className="setting-row">
                <div className="setting-icon">
                  <Power size={19} />
                </div>
                <div className="setting-copy">
                  <h3>Launch at login</h3>
                  <p>Start quietly in your menu bar.</p>
                </div>
                <button
                  className="switch"
                  role="switch"
                  aria-checked={autostart}
                  aria-label="Launch at login"
                  disabled={settingsLoading}
                  onClick={toggleAutostart}
                >
                  <span />
                </button>
              </div>
              <div className="setting-row">
                <div className="setting-icon">
                  <Clock3 size={19} />
                </div>
                <div className="setting-copy">
                  <h3>Your session defaults</h3>
                  <p>Mode and duration are remembered automatically.</p>
                </div>
                <Check size={17} className="muted-icon" />
              </div>
              <div className="setting-row">
                <div className="setting-icon">
                  <Monitor size={19} />
                </div>
                <div className="setting-copy">
                  <h3>Always close at hand</h3>
                  <p>Click the menu-bar icon to open. Click outside to hide.</p>
                </div>
              </div>
            </div>
            <div className="section-heading">
              <h2>Integrations</h2>
              <span>RAYCAST</span>
            </div>
            <div className="raycast-card">
              <div className="raycast-icon">
                <Command size={25} />
              </div>
              <div>
                <h3>A session, a few keystrokes away.</h3>
                <p>
                  Choose a mode and duration, toggle your saved session, or
                  check status directly from Raycast.
                </p>
                <button className="text-button" onClick={openGuide}>
                  Extension setup
                  <ExternalLink size={13} />
                </button>
              </div>
            </div>
            <div className="shortcut-row">
              <span>Start or end a session</span>
              <div>
                <kbd>⌘</kbd>
                <kbd>↵</kbd>
              </div>
            </div>
            <div className="shortcut-row">
              <span>Hide this window</span>
              <kbd>esc</kbd>
            </div>
            <button
              className="quit-button"
              disabled={loading}
              onClick={async () => {
                try {
                  await command("quit_app");
                } catch (e) {
                  setSettingsError(String(e));
                  refresh();
                }
              }}
            >
              <Power size={15} />
              Quit Caffeinator
              <span>
                {status.is_active
                  ? "Ends your current session"
                  : "See you next time"}
              </span>
            </button>
          </section>
        )}
      </main>
      <footer className="app-footer">
        <span>
          <span className="footer-dot" />
          {status.is_active
            ? "Taking care of the uptime."
            : "Ready when you are."}
        </span>
        <span>
          {version && (native ? `v${version}` : "Preview · simulated")}
        </span>
      </footer>
    </div>
  );
}

function ModeCard({
  mode,
  selected,
  disabled,
  onSelect,
}: {
  mode: AssertionType;
  selected: boolean;
  disabled: boolean;
  onSelect: () => void;
}) {
  const info = MODE_INFO[mode];
  return (
    <button
      className={`mode-card ${selected ? "chosen" : ""}`}
      aria-pressed={selected}
      title={info.description}
      disabled={disabled}
      onClick={onSelect}
    >
      <div className="mode-card-top">
        <span className="mode-icon">
          <info.icon size={19} strokeWidth={1.6} />
        </span>
        <span className="selection-dot">
          {selected && <Check size={10} strokeWidth={3} />}
        </span>
      </div>
      <h3>{info.label}</h3>
      <p>{info.description}</p>
    </button>
  );
}
function PowerRow({
  icon: Icon,
  title,
  detail,
  value,
}: {
  icon: typeof Monitor;
  title: string;
  detail: string;
  value: string;
}) {
  return (
    <div className="setting-row">
      <div className="setting-icon">
        <Icon size={19} />
      </div>
      <div className="setting-copy">
        <h3>{title}</h3>
        <p>{detail}</p>
      </div>
      <span className="setting-value">{value}</span>
    </div>
  );
}
export default App;
