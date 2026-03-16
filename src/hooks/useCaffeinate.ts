import { useState, useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { AssertionType, CaffeinateStatus } from "../types";

const DEFAULT_STATUS: CaffeinateStatus = {
  is_active: false,
  mode: null,
  remaining_seconds: null,
  total_seconds: null,
};

function formatTrayTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) {
    return `${h}:${m.toString().padStart(2, "0")}`;
  }
  return `${m}m`;
}

export function useCaffeinate() {
  const [status, setStatus] = useState<CaffeinateStatus>(DEFAULT_STATUS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fetchingRef = useRef(false);
  const prevTrayTitleRef = useRef("");

  const prevTrayActiveRef = useRef(false);

  const updateTray = useCallback(async (s: CaffeinateStatus) => {
    // Switch tray icon on state change
    if (s.is_active !== prevTrayActiveRef.current) {
      prevTrayActiveRef.current = s.is_active;
      invoke("set_tray_active", { active: s.is_active }).catch(() => {});
    }

    const title = s.is_active
      ? (s.remaining_seconds !== null ? formatTrayTime(s.remaining_seconds) : "∞")
      : "";

    if (title === prevTrayTitleRef.current) return;
    prevTrayTitleRef.current = title;

    try {
      await invoke("update_tray_title", { title });
    } catch {
      // Ignore tray update errors
    }
  }, []);

  const fetchStatus = useCallback(async () => {
    if (fetchingRef.current) return;
    fetchingRef.current = true;

    try {
      const result = await invoke<CaffeinateStatus>("get_status");
      setStatus(result);
      updateTray(result);
      setError(null);

      // Auto-deactivate when timer expires
      if (result.is_active && result.remaining_seconds === 0) {
        await invoke("deactivate");
        const newStatus = await invoke<CaffeinateStatus>("get_status");
        setStatus(newStatus);
        updateTray(newStatus);
      }
    } catch (e) {
      setError(String(e));
    } finally {
      fetchingRef.current = false;
    }
  }, [updateTray]);

  const activate = useCallback(
    async (mode: AssertionType, durationSecs: number | null) => {
      setLoading(true);
      setError(null);
      try {
        const result = await invoke<CaffeinateStatus>("activate", {
          mode,
          durationSecs,
        });
        setStatus(result);
        updateTray(result);
      } catch (e) {
        setError(String(e));
      } finally {
        setLoading(false);
      }
    },
    [updateTray]
  );

  const deactivate = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await invoke<CaffeinateStatus>("deactivate");
      setStatus(result);
      updateTray(result);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [updateTray]);

  // Initial fetch + visibility listener
  useEffect(() => {
    fetchStatus();

    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        fetchStatus();
      }
    };
    document.addEventListener("visibilitychange", handleVisibilityChange);

    return () => {
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [fetchStatus]);

  // Poll every second only when active
  useEffect(() => {
    if (!status.is_active) return;

    const interval = setInterval(fetchStatus, 1000);
    return () => clearInterval(interval);
  }, [fetchStatus, status.is_active]);

  return {
    status,
    loading,
    error,
    activate,
    deactivate,
    refresh: fetchStatus,
  };
}
