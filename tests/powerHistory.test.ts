import { expect, test } from "bun:test";
import { normalizePowerHistory } from "../src/lib/powerHistory";

test("normalizes camel-case history returned by IPC", () => {
  const history = normalizePowerHistory({
    fromMs: 1000,
    toMs: 2000,
    averageSystemWatts: 12.5,
    peakSystemWatts: 18,
    sampleCount: 2,
    sessionSeconds: 60,
    points: [
      {
        sampledAtMs: 1500,
        systemWatts: 12.5,
        batteryWatts: -4,
        batteryPercent: 72,
      },
    ],
    sessions: [
      {
        id: 7,
        mode: "NoIdleSleep",
        startedAtMs: 1000,
        endedAtMs: null,
        plannedDurationSeconds: 3600,
        endReason: null,
      },
    ],
  });

  expect(history.points[0].system_watts).toBe(12.5);
  expect(history.sessions[0].mode).toBe("NoIdleSleep");
  expect(history.session_seconds).toBe(60);
});

test("rejects malformed history collections", () => {
  expect(() => normalizePowerHistory({ points: null, sessions: [] })).toThrow(
    "invalid power history",
  );
});
