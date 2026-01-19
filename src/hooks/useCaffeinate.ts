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

async function updateTrayTitle(status: CaffeinateStatus) {
  try {
    if (status.is_active) {
      const title =
        status.remaining_seconds !== null
          ? formatTrayTime(status.remaining_seconds)
          : "∞";
      await invoke("update_tray_title", { title });
    } else {
      await invoke("update_tray_title", { title: "" });
    }
  } catch {
    // Ignore tray update errors
  }
}

export function useCaffeinate() {
  const [status, setStatus] = useState<CaffeinateStatus>(DEFAULT_STATUS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const statusRef = useRef(status);
  const fetchingRef = useRef(false);

  // Keep ref in sync with state
  useEffect(() => {
    statusRef.current = status;
  }, [status]);

  const fetchStatus = useCallback(async () => {
    // Prevent concurrent fetches
    if (fetchingRef.current) return;
    fetchingRef.current = true;

    try {
      const result = await invoke<CaffeinateStatus>("get_status");
      setStatus(result);
      statusRef.current = result;
      updateTrayTitle(result);
      setError(null);

      // Auto-deactivate when timer expires
      if (result.is_active && result.remaining_seconds === 0) {
        await invoke("deactivate");
        const newStatus = await invoke<CaffeinateStatus>("get_status");
        setStatus(newStatus);
        statusRef.current = newStatus;
        updateTrayTitle(newStatus);
      }
    } catch (e) {
      setError(String(e));
    } finally {
      fetchingRef.current = false;
    }
  }, []);

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
        statusRef.current = result;
        updateTrayTitle(result);
      } catch (e) {
        setError(String(e));
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const deactivate = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await invoke<CaffeinateStatus>("deactivate");
      setStatus(result);
      statusRef.current = result;
      updateTrayTitle(result);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  const toggle = useCallback(
    async (mode: AssertionType, durationSecs: number | null) => {
      setLoading(true);
      setError(null);
      try {
        const result = await invoke<CaffeinateStatus>("toggle", {
          mode,
          durationSecs,
        });
        setStatus(result);
        statusRef.current = result;
        updateTrayTitle(result);
      } catch (e) {
        setError(String(e));
      } finally {
        setLoading(false);
      }
    },
    []
  );

  // Poll status every second to update countdown
  useEffect(() => {
    fetchStatus();

    // Always poll every second to catch state changes
    const interval = setInterval(() => {
      fetchStatus();
    }, 1000);

    // Refresh when window becomes visible
    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        fetchStatus();
      }
    };
    document.addEventListener("visibilitychange", handleVisibilityChange);

    return () => {
      clearInterval(interval);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [fetchStatus]);

  return {
    status,
    loading,
    error,
    activate,
    deactivate,
    toggle,
    refresh: fetchStatus,
  };
}
