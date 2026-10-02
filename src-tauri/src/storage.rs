//! SQLite-backed application storage and the separate crash-recovery journal.
//!
//! SQLite lives at `~/.config/caffeinator/caffeinator.sqlite3`. The previous
//! `settings.json` format is imported once. Power recovery intentionally remains
//! a synced JSON file because it must be durable before a privileged system change.

use crate::{power::AssertionType, telemetry::PowerTelemetry};
use rusqlite::{params, Connection, OptionalExtension};
use std::{
    path::{Path, PathBuf},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const DATABASE_FILE: &str = "caffeinator.sqlite3";
const LEGACY_SETTINGS_FILE: &str = "settings.json";
const SCHEMA_VERSION: i64 = 2;
const SAMPLE_INTERVAL_MS: u64 = 30_000;
const SAMPLE_RETENTION_MS: u64 = 7 * 24 * 60 * 60 * 1000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Settings {
    pub selected_mode: AssertionType,
    pub selected_duration: Option<u64>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            selected_mode: AssertionType::NoIdleSleep,
            selected_duration: Some(3600),
        }
    }
}

#[derive(serde::Deserialize)]
struct LegacySettings {
    selected_mode: AssertionType,
    #[serde(default = "default_duration")]
    selected_duration: Option<u64>,
}

#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoryRange {
    Hour,
    Day,
    Week,
}

impl HistoryRange {
    fn duration_ms(self) -> u64 {
        match self {
            Self::Hour => 60 * 60 * 1000,
            Self::Day => 24 * 60 * 60 * 1000,
            Self::Week => 7 * 24 * 60 * 60 * 1000,
        }
    }

    fn bucket_ms(self) -> u64 {
        match self {
            Self::Hour => 60 * 1000,
            Self::Day => 30 * 60 * 1000,
            Self::Week => 3 * 60 * 60 * 1000,
        }
    }
}

#[derive(Debug, serde::Serialize)]
pub struct PowerHistoryPoint {
    pub sampled_at_ms: u64,
    pub system_watts: Option<f64>,
    pub battery_watts: Option<f64>,
    pub battery_percent: Option<f64>,
}

#[derive(Debug, serde::Serialize)]
pub struct SessionHistory {
    pub id: i64,
    pub mode: AssertionType,
    pub started_at_ms: u64,
    pub ended_at_ms: Option<u64>,
    pub planned_duration_seconds: Option<u64>,
    pub end_reason: Option<String>,
}

#[derive(Debug, serde::Serialize)]
pub struct PowerHistory {
    pub from_ms: u64,
    pub to_ms: u64,
    pub average_system_watts: Option<f64>,
    pub peak_system_watts: Option<f64>,
    pub sample_count: u64,
    pub session_seconds: u64,
    pub points: Vec<PowerHistoryPoint>,
    pub sessions: Vec<SessionHistory>,
}

fn default_duration() -> Option<u64> {
    Some(3600)
}

pub(crate) fn config_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".config").join("caffeinator")
}

fn database_path() -> PathBuf {
    config_dir().join(DATABASE_FILE)
}

fn legacy_settings_path() -> PathBuf {
    config_dir().join(LEGACY_SETTINGS_FILE)
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn open(path: &Path) -> Result<Connection, String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("Cannot create storage directory: {error}"))?;
    }
    let connection = Connection::open(path)
        .map_err(|error| format!("Cannot open Caffeinator database: {error}"))?;
    connection
        .busy_timeout(Duration::from_secs(5))
        .map_err(|error| format!("Cannot configure Caffeinator database: {error}"))?;
    connection
        .execute_batch("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")
        .map_err(|error| format!("Cannot configure Caffeinator database: {error}"))?;
    migrate_schema(&connection)?;
    Ok(connection)
}

fn migrate_schema(connection: &Connection) -> Result<(), String> {
    let mut version: i64 = connection
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .map_err(|error| format!("Cannot read storage schema: {error}"))?;
    if version > SCHEMA_VERSION {
        return Err(format!(
            "Caffeinator database version {version} is newer than this app supports."
        ));
    }
    if version == 0 {
        connection
            .execute_batch(
                "BEGIN IMMEDIATE;
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
                 COMMIT;",
            )
            .map_err(|error| format!("Cannot initialize settings storage: {error}"))?;
        version = 1;
    }
    if version == 1 {
        connection
            .execute_batch(
                "BEGIN IMMEDIATE;
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
                 COMMIT;",
            )
            .map_err(|error| format!("Cannot initialize history storage: {error}"))?;
    }
    Ok(())
}

fn mode_key(mode: AssertionType) -> &'static str {
    match mode {
        AssertionType::NoIdleSleep => "NoIdleSleep",
        AssertionType::NoDisplaySleep => "NoDisplaySleep",
        AssertionType::ServerMode => "ServerMode",
        AssertionType::NetworkActive => "NetworkActive",
        AssertionType::BackgroundTask => "BackgroundTask",
    }
}

fn parse_mode(value: &str) -> Result<AssertionType, String> {
    match value {
        "NoIdleSleep" => Ok(AssertionType::NoIdleSleep),
        "NoDisplaySleep" => Ok(AssertionType::NoDisplaySleep),
        "ServerMode" | "LidClose" => Ok(AssertionType::ServerMode),
        "NetworkActive" => Ok(AssertionType::NetworkActive),
        "BackgroundTask" => Ok(AssertionType::BackgroundTask),
        _ => Err(format!(
            "Caffeinator database contains unknown mode {value:?}."
        )),
    }
}

fn read_settings(connection: &Connection) -> Result<Option<Settings>, String> {
    let stored: Option<(String, Option<i64>)> = connection
        .query_row(
            "SELECT selected_mode, selected_duration_seconds FROM app_settings WHERE id = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|error| format!("Cannot read settings: {error}"))?;
    stored
        .map(|(mode, duration)| {
            Ok(Settings {
                selected_mode: parse_mode(&mode)?,
                selected_duration: duration.map(u64::try_from).transpose().map_err(|_| {
                    "Caffeinator database contains an invalid duration.".to_string()
                })?,
            })
        })
        .transpose()
}

fn save_settings(connection: &Connection, settings: &Settings) -> Result<(), String> {
    let duration = settings
        .selected_duration
        .map(i64::try_from)
        .transpose()
        .map_err(|_| "Selected duration is too large.".to_string())?;
    connection
        .execute(
            "INSERT INTO app_settings (id, selected_mode, selected_duration_seconds)
             VALUES (1, ?1, ?2)
             ON CONFLICT(id) DO UPDATE SET
               selected_mode = excluded.selected_mode,
               selected_duration_seconds = excluded.selected_duration_seconds",
            params![mode_key(settings.selected_mode), duration],
        )
        .map_err(|error| format!("Cannot save settings: {error}"))?;
    Ok(())
}

fn load_legacy(path: &Path) -> Option<Settings> {
    let raw = std::fs::read_to_string(path).ok()?;
    let legacy = serde_json::from_str::<LegacySettings>(&raw).ok()?;
    Some(Settings {
        selected_mode: legacy.selected_mode,
        selected_duration: legacy
            .selected_duration
            .filter(|seconds| *seconds > 0 && *seconds <= 7 * 24 * 3600),
    })
}

fn load_from(database: &Path, legacy: &Path) -> Result<Settings, String> {
    let connection = open(database)?;
    if let Some(settings) = read_settings(&connection)? {
        return Ok(settings);
    }
    let legacy_settings = load_legacy(legacy);
    let settings = legacy_settings.unwrap_or_default();
    save_settings(&connection, &settings)?;
    if legacy_settings.is_some() {
        let _ = std::fs::remove_file(legacy);
    }
    Ok(settings)
}

pub fn load() -> Settings {
    load_from(&database_path(), &legacy_settings_path()).unwrap_or_default()
}

pub fn save(settings: &Settings) -> Result<(), String> {
    let connection = open(&database_path())?;
    save_settings(&connection, settings)
}

pub fn start_session(mode: AssertionType, duration: Option<u64>) -> Result<i64, String> {
    let connection = open(&database_path())?;
    connection
        .execute(
            "INSERT INTO session_history (mode, started_at_ms, planned_duration_seconds)
             VALUES (?1, ?2, ?3)",
            params![mode_key(mode), now_ms(), duration],
        )
        .map_err(|error| format!("Cannot record session: {error}"))?;
    Ok(connection.last_insert_rowid())
}

pub fn end_session(id: i64, reason: &str) -> Result<(), String> {
    let connection = open(&database_path())?;
    connection
        .execute(
            "UPDATE session_history SET ended_at_ms = ?1, end_reason = ?2
             WHERE id = ?3 AND ended_at_ms IS NULL",
            params![now_ms(), reason, id],
        )
        .map_err(|error| format!("Cannot finish session history: {error}"))?;
    Ok(())
}

pub fn reconcile_sessions(server_recovery: bool) -> Result<Option<i64>, String> {
    let connection = open(&database_path())?;
    let survivor = if server_recovery {
        connection
            .query_row(
                "SELECT id FROM session_history
                 WHERE ended_at_ms IS NULL AND mode = 'ServerMode'
                 ORDER BY started_at_ms DESC LIMIT 1",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(|error| format!("Cannot reconcile session history: {error}"))?
    } else {
        None
    };
    connection
        .execute(
            "UPDATE session_history SET ended_at_ms = ?1, end_reason = 'interrupted'
             WHERE ended_at_ms IS NULL AND (?2 IS NULL OR id != ?2)",
            params![now_ms(), survivor],
        )
        .map_err(|error| format!("Cannot reconcile session history: {error}"))?;
    Ok(survivor)
}

pub fn record_power_sample(sample: &PowerTelemetry) -> Result<(), String> {
    let connection = open(&database_path())?;
    let bucket = sample.updated_at_ms / SAMPLE_INTERVAL_MS * SAMPLE_INTERVAL_MS;
    connection
        .execute(
            "INSERT INTO power_samples (
               sampled_at_ms, system_watts, adapter_input_watts, battery_watts,
               battery_percent, charging_state
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(sampled_at_ms) DO UPDATE SET
               system_watts = excluded.system_watts,
               adapter_input_watts = excluded.adapter_input_watts,
               battery_watts = excluded.battery_watts,
               battery_percent = excluded.battery_percent,
               charging_state = excluded.charging_state",
            params![
                bucket,
                sample.system_watts,
                sample.adapter_input_watts,
                sample.battery_watts,
                sample.battery_percent,
                sample.charging_state
            ],
        )
        .map_err(|error| format!("Cannot record power history: {error}"))?;
    connection
        .execute(
            "DELETE FROM power_samples WHERE sampled_at_ms < ?1",
            [now_ms().saturating_sub(SAMPLE_RETENTION_MS)],
        )
        .map_err(|error| format!("Cannot trim power history: {error}"))?;
    Ok(())
}

pub fn power_history(range: HistoryRange) -> Result<PowerHistory, String> {
    power_history_from(&open(&database_path())?, range, now_ms())
}

fn power_history_from(
    connection: &Connection,
    range: HistoryRange,
    to_ms: u64,
) -> Result<PowerHistory, String> {
    let from_ms = to_ms.saturating_sub(range.duration_ms());
    let bucket_ms = range.bucket_ms();
    let mut statement = connection
        .prepare(
            "SELECT (sampled_at_ms / ?2) * ?2 AS bucket,
                    AVG(system_watts), AVG(battery_watts), AVG(battery_percent)
             FROM power_samples
             WHERE sampled_at_ms >= ?1 AND sampled_at_ms <= ?3
             GROUP BY bucket ORDER BY bucket",
        )
        .map_err(|error| format!("Cannot query power history: {error}"))?;
    let points = statement
        .query_map(params![from_ms, bucket_ms, to_ms], |row| {
            Ok(PowerHistoryPoint {
                sampled_at_ms: row.get(0)?,
                system_watts: row.get(1)?,
                battery_watts: row.get(2)?,
                battery_percent: row.get(3)?,
            })
        })
        .map_err(|error| format!("Cannot query power history: {error}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("Cannot decode power history: {error}"))?;
    let (average_system_watts, peak_system_watts, sample_count) = connection
        .query_row(
            "SELECT AVG(system_watts), MAX(system_watts), COUNT(*)
             FROM power_samples WHERE sampled_at_ms >= ?1 AND sampled_at_ms <= ?2",
            params![from_ms, to_ms],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .map_err(|error| format!("Cannot summarize power history: {error}"))?;
    let session_seconds: u64 = connection
        .query_row(
            "SELECT COALESCE(SUM(
               MAX(0, MIN(COALESCE(ended_at_ms, ?2), ?2) - MAX(started_at_ms, ?1))
             ) / 1000, 0)
             FROM session_history
             WHERE started_at_ms <= ?2 AND COALESCE(ended_at_ms, ?2) >= ?1",
            params![from_ms, to_ms],
            |row| row.get(0),
        )
        .map_err(|error| format!("Cannot summarize session history: {error}"))?;
    let mut session_statement = connection
        .prepare(
            "SELECT id, mode, started_at_ms, ended_at_ms, planned_duration_seconds, end_reason
             FROM session_history
             WHERE started_at_ms <= ?2 AND COALESCE(ended_at_ms, ?2) >= ?1
             ORDER BY started_at_ms DESC LIMIT 6",
        )
        .map_err(|error| format!("Cannot query session history: {error}"))?;
    let raw_sessions = session_statement
        .query_map(params![from_ms, to_ms], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u64>(2)?,
                row.get::<_, Option<u64>>(3)?,
                row.get::<_, Option<u64>>(4)?,
                row.get::<_, Option<String>>(5)?,
            ))
        })
        .map_err(|error| format!("Cannot query session history: {error}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("Cannot decode session history: {error}"))?;
    let sessions = raw_sessions
        .into_iter()
        .map(
            |(id, mode, started_at_ms, ended_at_ms, planned_duration_seconds, end_reason)| {
                Ok(SessionHistory {
                    id,
                    mode: parse_mode(&mode)?,
                    started_at_ms,
                    ended_at_ms,
                    planned_duration_seconds,
                    end_reason,
                })
            },
        )
        .collect::<Result<Vec<_>, String>>()?;
    Ok(PowerHistory {
        from_ms,
        to_ms,
        average_system_watts,
        peak_system_watts,
        sample_count,
        session_seconds,
        points,
        sessions,
    })
}

/// Replace only after the complete file is durable. The power recovery journal
/// must reach disk before changing system settings.
pub(crate) fn atomic_write(path: &Path, json: &str) -> std::io::Result<()> {
    use std::io::Write;
    let temp = path.with_extension("json.tmp");
    let mut file = std::fs::File::create(&temp)?;
    file.write_all(json.as_bytes())?;
    file.sync_all()?;
    std::fs::rename(&temp, path)?;
    if let Some(parent) = path.parent() {
        std::fs::File::open(parent)?.sync_all()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static NEXT_DIR: AtomicUsize = AtomicUsize::new(0);

    fn fixture() -> (Connection, PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!(
            "caffeinator-storage-{}-{}",
            std::process::id(),
            NEXT_DIR.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let database = dir.join(DATABASE_FILE);
        (
            open(&database).unwrap(),
            dir.join(LEGACY_SETTINGS_FILE),
            dir,
        )
    }

    #[test]
    fn imports_legacy_settings_and_persists_them() {
        let (connection, legacy, dir) = fixture();
        drop(connection);
        std::fs::write(
            &legacy,
            r#"{"selected_mode":"LidClose","selected_duration":7200}"#,
        )
        .unwrap();
        let database = dir.join(DATABASE_FILE);
        let settings = load_from(&database, &legacy).unwrap();
        assert_eq!(settings.selected_mode, AssertionType::ServerMode);
        assert_eq!(settings.selected_duration, Some(7200));
        assert!(!legacy.exists());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn aggregates_samples_and_session_overlap_for_requested_range() {
        let (connection, _, dir) = fixture();
        connection
            .execute(
                "INSERT INTO power_samples
                 (sampled_at_ms, system_watts, battery_watts, battery_percent, charging_state)
                 VALUES (940000, 10.0, -5.0, 80.0, 'battery'),
                        (970000, 20.0, -6.0, 79.0, 'battery')",
                [],
            )
            .unwrap();
        connection
            .execute(
                "INSERT INTO session_history
                 (mode, started_at_ms, ended_at_ms, planned_duration_seconds, end_reason)
                 VALUES ('NoIdleSleep', 900000, 980000, 80, 'stopped')",
                [],
            )
            .unwrap();
        let history = power_history_from(&connection, HistoryRange::Hour, 1_000_000).unwrap();
        assert_eq!(history.sample_count, 2);
        assert_eq!(history.average_system_watts, Some(15.0));
        assert_eq!(history.peak_system_watts, Some(20.0));
        assert_eq!(history.session_seconds, 80);
        assert_eq!(history.sessions.len(), 1);
        assert_eq!(history.sessions[0].mode, AssertionType::NoIdleSleep);
        drop(connection);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn upgrades_the_released_settings_schema_without_losing_preferences() {
        let dir = std::env::temp_dir().join(format!(
            "caffeinator-storage-v1-{}-{}",
            std::process::id(),
            NEXT_DIR.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let database = dir.join(DATABASE_FILE);
        let connection = Connection::open(&database).unwrap();
        connection
            .execute_batch(
                "CREATE TABLE app_settings (
                   id INTEGER PRIMARY KEY,
                   selected_mode TEXT NOT NULL,
                   selected_duration_seconds INTEGER
                 );
                 INSERT INTO app_settings VALUES (1, 'NoDisplaySleep', 3600);
                 PRAGMA user_version = 1;",
            )
            .unwrap();
        migrate_schema(&connection).unwrap();
        assert_eq!(
            read_settings(&connection).unwrap(),
            Some(Settings {
                selected_mode: AssertionType::NoDisplaySleep,
                selected_duration: Some(3600),
            })
        );
        let version: i64 = connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, SCHEMA_VERSION);
        drop(connection);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
