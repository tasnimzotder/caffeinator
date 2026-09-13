import { useState, useEffect, useCallback, useRef } from "react";
import { command, subscribeStatus } from "../lib/backend";
import type { AssertionType, CaffeinateStatus } from "../types";

const DEFAULT_STATUS: CaffeinateStatus = {
  is_active: false,
  mode: null,
  selected_mode: "NoIdleSleep",
  selected_duration: 3600,
  remaining_seconds: null,
  total_seconds: null,
  busy: false,
  recovery_required: false,
  error: null,
  revision: -1,
};

export function useCaffeinate() {
  const [status, setStatus] = useState(DEFAULT_STATUS);
  const [ready, setReady] = useState(false);
  const [pending, setPending] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);
  const [dismissedRevision, setDismissedRevision] = useState<number | null>(
    null,
  );
  const inFlight = useRef(false);

  const accept = useCallback((next: CaffeinateStatus) => {
    setStatus((previous) => {
      if (next.revision < previous.revision) return previous;
      if (
        next.revision === previous.revision &&
        next.remaining_seconds !== null &&
        previous.remaining_seconds !== null &&
        next.remaining_seconds > previous.remaining_seconds
      )
        return previous;
      return next;
    });
    setReady(true);
  }, []);

  const refresh = useCallback(async () => {
    try {
      accept(await command<CaffeinateStatus>("get_status"));
      setLocalError(null);
    } catch (error) {
      setLocalError(String(error));
    }
  }, [accept]);

  const mutate = useCallback(
    async (name: string, args?: Record<string, unknown>) => {
      if (inFlight.current) return;
      inFlight.current = true;
      setPending(true);
      setLocalError(null);
      try {
        accept(await command<CaffeinateStatus>(name, args));
      } catch (error) {
        setLocalError(String(error));
        try {
          accept(await command<CaffeinateStatus>("get_status"));
        } catch {
          /* Keep the action error. */
        }
      } finally {
        inFlight.current = false;
        setPending(false);
      }
    },
    [accept],
  );

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | undefined;
    // Subscribe first, then fetch: no gap where native changes can be lost.
    subscribeStatus((next) => {
      if (!disposed) accept(next);
    })
      .then((cleanup) => {
        if (disposed) {
          cleanup();
          return;
        }
        unlisten = cleanup;
        refresh();
      })
      .catch(async (error) => {
        if (disposed) return;
        setLocalError(String(error));
        try {
          const next = await command<CaffeinateStatus>("get_status");
          if (!disposed) accept(next);
        } catch (refreshError) {
          if (!disposed) setLocalError(String(refreshError));
        }
      });
    const visibility = () => {
      if (document.visibilityState === "visible") refresh();
    };
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("focus", refresh);
    return () => {
      disposed = true;
      unlisten?.();
      document.removeEventListener("visibilitychange", visibility);
      window.removeEventListener("focus", refresh);
    };
  }, [accept, refresh]);

  return {
    status,
    ready,
    loading: pending || status.busy,
    error:
      localError ??
      (dismissedRevision === status.revision ? null : status.error),
    activate: (mode: AssertionType, durationSecs: number | null) =>
      mutate("activate", { mode, durationSecs }),
    deactivate: () => mutate("deactivate"),
    selectMode: (mode: AssertionType) => mutate("set_selected_mode", { mode }),
    selectDuration: (durationSecs: number | null) =>
      mutate("set_selected_duration", { durationSecs }),
    refresh,
    dismissError: () => {
      setLocalError(null);
      setDismissedRevision(status.revision);
    },
  };
}
