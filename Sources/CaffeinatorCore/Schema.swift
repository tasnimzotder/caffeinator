import Foundation

enum Schema {
  static let v1 = """
    BEGIN IMMEDIATE;
    CREATE TABLE app_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    selected_mode TEXT NOT NULL CHECK (
    selected_mode IN ('NoIdleSleep', 'NoDisplaySleep', 'ServerMode', 'NetworkActive', 'BackgroundTask')
    ),
    selected_duration_seconds INTEGER CHECK (
    selected_duration_seconds IS NULL OR selected_duration_seconds BETWEEN 1 AND 604800
    )
    ) STRICT;
    PRAGMA user_version = 1;
    COMMIT;
    """
  static let v2 = """
    BEGIN IMMEDIATE;
    CREATE TABLE session_history (
    id INTEGER PRIMARY KEY,
    mode TEXT NOT NULL CHECK (
    mode IN ('NoIdleSleep', 'NoDisplaySleep', 'ServerMode', 'NetworkActive', 'BackgroundTask')
    ),
    started_at_ms INTEGER NOT NULL CHECK (started_at_ms >= 0),
    ended_at_ms INTEGER CHECK (ended_at_ms IS NULL OR ended_at_ms >= started_at_ms),
    planned_duration_seconds INTEGER CHECK (
    planned_duration_seconds IS NULL OR planned_duration_seconds BETWEEN 1 AND 604800
    ),
    end_reason TEXT CHECK (
    end_reason IS NULL OR end_reason IN ('stopped', 'expired', 'replaced', 'interrupted')
    )
    ) STRICT;
    CREATE INDEX session_history_started ON session_history(started_at_ms DESC);
    CREATE TABLE power_samples (
    sampled_at_ms INTEGER PRIMARY KEY CHECK (sampled_at_ms >= 0),
    system_watts REAL,
    adapter_input_watts REAL,
    battery_watts REAL,
    battery_percent REAL CHECK (
    battery_percent IS NULL OR battery_percent BETWEEN 0 AND 100
    ),
    charging_state TEXT NOT NULL CHECK (
    charging_state IN ('charging', 'full', 'plugged_in', 'battery', 'unknown')
    )
    ) STRICT;
    PRAGMA user_version = 2;
    COMMIT;
    """
}
