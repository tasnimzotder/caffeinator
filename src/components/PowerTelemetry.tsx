import {
  BatteryCharging,
  BatteryFull,
  Battery,
  LoaderCircle,
  Plug,
  Zap,
} from "lucide-react";
import { useEffect, useState } from "react";
import { command, preview } from "../lib/backend";
import type { PowerTelemetry as Sample } from "../types";

const watts = (value: number | null) =>
  value === null ? "—" : `${Math.abs(value).toFixed(1)} W`;
function remaining(minutes: number) {
  const hours = Math.floor(minutes / 60),
    rest = minutes % 60;
  return [hours ? `${hours}h` : "", rest ? `${rest}m` : ""]
    .filter(Boolean)
    .join(" ");
}
export function PowerTelemetry() {
  const [sample, setSample] = useState<Sample | null>(null);
  const [history, setHistory] = useState<{ watts: number; at: number }[]>([]);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let disposed = false;
    let pending = false;
    let timer: ReturnType<typeof setTimeout>;
    const update = async () => {
      if (disposed || pending) return;
      clearTimeout(timer);
      if (document.visibilityState !== "hidden") {
        pending = true;
        try {
          const next = await command<Sample>("get_power_telemetry");
          if (!disposed) {
            setSample(next);
            setError(null);
            const watts = next.system_watts;
            if (watts !== null)
              setHistory((previous) => [
                ...previous.filter(
                  (point) => next.updated_at_ms - point.at <= 60000,
                ),
                { watts, at: next.updated_at_ms },
              ]);
          }
        } catch (error) {
          if (!disposed) setError(String(error));
        } finally {
          pending = false;
        }
      }
      if (!disposed) timer = setTimeout(update, 2000);
    };
    update();
    const visible = () => {
      if (document.visibilityState === "visible") update();
    };
    document.addEventListener("visibilitychange", visible);
    return () => {
      disposed = true;
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", visible);
    };
  }, []);
  if (!sample && !error)
    return (
      <div className="telemetry-loading">
        <LoaderCircle size={16} className="spin" />
        Reading live power sensors…
      </div>
    );
  if (!sample)
    return (
      <div className="notice" role="status">
        <Battery size={18} />
        <p>{error}</p>
      </div>
    );
  const charging = sample.charging_state === "charging";
  const pluggedIn = sample.charging_state !== "battery";
  const StateIcon = charging
    ? BatteryCharging
    : sample.charging_state === "full"
      ? BatteryFull
      : pluggedIn
        ? Plug
        : Battery;
  const stateText = charging
    ? "Charging"
    : sample.charging_state === "full"
      ? "Fully charged"
      : pluggedIn
        ? "Plugged in · not charging"
        : "On battery";
  const ceiling = Math.max(10, ...history.map((point) => point.watts)) * 1.2;
  const latest = history[history.length - 1]?.at ?? Date.now();
  const points = history
    .map(
      (point) =>
        `${300 - ((latest - point.at) / 60000) * 300},${42 - (point.watts / ceiling) * 38}`,
    )
    .join(" ");
  return (
    <div className={`telemetry-panel ${error ? "stale" : ""}`}>
      <div className="telemetry-heading">
        <span>
          <span className="status-dot" />
          {error
            ? "Last reading"
            : preview
              ? "Simulated live readings"
              : "Live power"}
        </span>
        <span>
          {error
            ? new Date(sample.updated_at_ms).toLocaleTimeString()
            : "Updates every 2s"}
        </span>
      </div>
      <div className="telemetry-main">
        <div>
          <span>System draw</span>
          <strong>
            {sample.system_watts === null
              ? "—"
              : sample.system_watts.toFixed(1)}
            <small>W</small>
          </strong>
        </div>
        <div className="battery-summary">
          <StateIcon size={23} strokeWidth={1.5} />
          <strong>
            {sample.battery_percent === null
              ? "—"
              : `${Math.round(sample.battery_percent)}%`}
          </strong>
          <span>{stateText}</span>
        </div>
      </div>
      {sample.system_watts !== null && (
        <div className="power-history">
          <svg
            viewBox="0 0 300 46"
            preserveAspectRatio="none"
            role="img"
            aria-label="System power over the last 60 seconds"
          >
            <line x1="0" y1="43" x2="300" y2="43" stroke="#ffffff15" />
            <polyline
              points={points}
              fill="none"
              stroke="#e2b278"
              strokeWidth="1.6"
              vectorEffect="non-scaling-stroke"
            />
            {history.length === 1 && (
              <circle
                cx="298"
                cy={42 - (history[0].watts / ceiling) * 38}
                r="2"
                fill="#e2b278"
              />
            )}
          </svg>
          <div>
            <span>Last 60 seconds</span>
            <span>{ceiling.toFixed(0)} W scale</span>
          </div>
        </div>
      )}
      {sample.system_watts === null && (
        <p className="telemetry-note">
          System draw is not reported by this Mac.
        </p>
      )}
      <div className="power-flow">
        <div>
          <Zap size={13} />
          <span>{charging ? "Battery charging" : "Battery draw"}</span>
          <strong>{watts(sample.battery_watts)}</strong>
        </div>
        <div>
          <Plug size={13} />
          <span>Adapter input</span>
          <strong>
            {pluggedIn ? watts(sample.adapter_input_watts) : "Unplugged"}
          </strong>
        </div>
      </div>
      <div className="telemetry-details">
        <span>
          {sample.adapter_rating_watts !== null
            ? `${sample.adapter_rating_watts.toFixed(0)} W charger rating`
            : "Battery power"}
        </span>
        <span>
          {sample.time_remaining_minutes !== null
            ? `~${remaining(sample.time_remaining_minutes)} ${charging ? "to full" : "remaining"}`
            : stateText}
        </span>
      </div>
      <div className="telemetry-details secondary">
        <span>
          {sample.battery_voltage === null
            ? "Voltage unavailable"
            : `${sample.battery_voltage.toFixed(2)} V battery`}
        </span>
        <span>
          {sample.battery_current_amps === null
            ? "Current unavailable"
            : `${sample.battery_current_amps.toFixed(2)} A battery current`}
        </span>
      </div>
      {error && (
        <p className="telemetry-note" role="status">
          Live readings paused: {error}
        </p>
      )}
    </div>
  );
}
