import {
  Activity,
  Clock3,
  Coffee,
  LoaderCircle,
  TrendingUp,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { command, preview } from "../lib/backend";
import { normalizePowerHistory } from "../lib/powerHistory";
import {
  MODE_INFO,
  type HistoryRange,
  type PowerHistory as History,
  type PowerHistoryPoint,
} from "../types";

const RANGES: { value: HistoryRange; label: string }[] = [
  { value: "hour", label: "1H" },
  { value: "day", label: "24H" },
  { value: "week", label: "7D" },
];

function duration(seconds: number) {
  if (seconds < 60) return `${seconds}s`;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (!hours) return `${minutes}m`;
  return minutes ? `${hours}h ${minutes}m` : `${hours}h`;
}

function rangeTime(timestamp: number, range: HistoryRange) {
  const date = new Date(timestamp);
  return range === "week"
    ? date.toLocaleDateString([], { weekday: "short" })
    : date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function sessionTime(timestamp: number) {
  return new Date(timestamp).toLocaleString([], {
    weekday: "short",
    hour: "numeric",
    minute: "2-digit",
  });
}

function buildLine(
  points: PowerHistoryPoint[],
  from: number,
  to: number,
  ceiling: number,
) {
  return points
    .filter((point) => point.system_watts !== null)
    .map((point) => {
      const x = ((point.sampled_at_ms - from) / Math.max(1, to - from)) * 320;
      const y = 82 - ((point.system_watts ?? 0) / ceiling) * 70;
      return `${Math.max(0, Math.min(320, x)).toFixed(1)},${Math.max(7, y).toFixed(1)}`;
    })
    .join(" ");
}

export function PowerHistory() {
  const [range, setRange] = useState<HistoryRange>("day");
  const [history, setHistory] = useState<History | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let disposed = false;
    let pending = false;
    const load = async () => {
      if (disposed || pending || document.visibilityState === "hidden") return;
      pending = true;
      try {
        const next = normalizePowerHistory(
          await command<unknown>("get_power_history", { range }),
        );
        if (!disposed) {
          setHistory(next);
          setError(null);
        }
      } catch (loadError) {
        if (!disposed) setError(String(loadError));
      } finally {
        pending = false;
        if (!disposed) setLoading(false);
      }
    };
    setLoading(true);
    load();
    const timer = setInterval(load, 30_000);
    const visible = () => load();
    document.addEventListener("visibilitychange", visible);
    return () => {
      disposed = true;
      clearInterval(timer);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [range]);

  const ceiling = Math.max(
    10,
    ...(history?.points.map((point) => point.system_watts ?? 0) ?? []),
    history?.peak_system_watts ?? 0,
  ) * 1.12;
  const line = useMemo(
    () =>
      history
        ? buildLine(history.points, history.from_ms, history.to_ms, ceiling)
        : "",
    [ceiling, history],
  );
  const averageY =
    history?.average_system_watts === null ||
    history?.average_system_watts === undefined
      ? null
      : 82 - (history.average_system_watts / ceiling) * 70;
  const hasPower = Boolean(line);

  return (
    <section className="history-panel" aria-labelledby="history-title">
      <div className="history-toolbar">
        <div>
          <span className="history-kicker">
            <Activity size={11} /> RECORDED LOCALLY
          </span>
          <h2 id="history-title">Power rhythm</h2>
        </div>
        <div
          className="range-switcher"
          role="group"
          aria-label="Power history range"
        >
          {RANGES.map((option) => (
            <button
              key={option.value}
              type="button"
              aria-pressed={range === option.value}
              onClick={() => setRange(option.value)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      {loading && !history ? (
        <div className="history-loading">
          <LoaderCircle className="spin" size={15} /> Building the timeline…
        </div>
      ) : history ? (
        <>
          <div className="history-metrics">
            <div>
              <span>Average</span>
              <strong>
                {history.average_system_watts === null
                  ? "—"
                  : history.average_system_watts.toFixed(1)}
                <small> W</small>
              </strong>
            </div>
            <div>
              <span>Peak</span>
              <strong>
                {history.peak_system_watts === null
                  ? "—"
                  : history.peak_system_watts.toFixed(1)}
                <small> W</small>
              </strong>
            </div>
            <div>
              <span>Session time</span>
              <strong>{duration(history.session_seconds)}</strong>
            </div>
          </div>

          <div className="history-chart">
            {hasPower ? (
              <svg
                viewBox="0 0 320 90"
                preserveAspectRatio="none"
                role="img"
                aria-label={`System power history from ${rangeTime(history.from_ms, range)} to ${rangeTime(history.to_ms, range)}`}
              >
                <defs>
                  <linearGradient id="power-history-fill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" stopColor="#efb35f" stopOpacity="0.3" />
                    <stop offset="1" stopColor="#efb35f" stopOpacity="0" />
                  </linearGradient>
                </defs>
                <line x1="0" y1="82" x2="320" y2="82" className="history-grid" />
                {averageY !== null && (
                  <line
                    x1="0"
                    y1={averageY}
                    x2="320"
                    y2={averageY}
                    className="history-average"
                  />
                )}
                <polygon points={`0,82 ${line} 320,82`} fill="url(#power-history-fill)" />
                <polyline points={line} className="history-line" />
              </svg>
            ) : (
              <div className="history-empty">
                <TrendingUp size={18} />
                <span>History starts filling in while Caffeinator is running.</span>
              </div>
            )}
            <div className="history-axis">
              <span>{rangeTime(history.from_ms, range)}</span>
              <span>{history.sample_count} readings</span>
              <span>Now</span>
            </div>
          </div>

          <div className="session-ledger">
            <div className="session-ledger-title">
              <span>
                <Coffee size={12} /> Awake sessions
              </span>
              <small>{preview ? "PREVIEW DATA" : "LATEST"}</small>
            </div>
            {history.sessions.length ? (
              history.sessions.slice(0, 3).map((session) => {
                const mode = MODE_INFO[session.mode];
                const end = session.ended_at_ms ?? history.to_ms;
                return (
                  <div className="session-history-row" key={session.id}>
                    <span className={session.ended_at_ms === null ? "session-pulse" : "session-mark"} />
                    <div>
                      <strong>{mode.label}</strong>
                      <span>{sessionTime(session.started_at_ms)}</span>
                    </div>
                    <span className="session-duration">
                      {duration(Math.max(0, Math.round((end - session.started_at_ms) / 1000)))}
                    </span>
                  </div>
                );
              })
            ) : (
              <div className="session-empty">
                <Clock3 size={15} /> Completed sessions will appear here.
              </div>
            )}
          </div>
        </>
      ) : null}

      {error && (
        <p className="history-error" role="status">
          History is temporarily unavailable. {error}
        </p>
      )}
    </section>
  );
}
