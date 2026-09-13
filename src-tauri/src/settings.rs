//! Persisted user settings.
//!
//! SQLite lives at `~/.config/caffeinator/caffeinator.sqlite3`. The previous
//! `settings.json` format is imported once; the separate power recovery journal
//! intentionally remains a synced JSON file.

use crate::power::AssertionType;
use rusqlite::{params, Connection, OptionalExtension};
use std::{
    path::{Path, PathBuf},
    time::Duration,
};

const DATABASE_FILE: &str = "caffeinator.sqlite3";
const LEGACY_SETTINGS_FILE: &str = "settings.json";
const SCHEMA_VERSION: i64 = 1;

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

fn open(path: &Path) -> Result<Connection, String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("Cannot create settings directory: {error}"))?;
    }
    let connection = Connection::open(path)
        .map_err(|error| format!("Cannot open settings database: {error}"))?;
    connection
        .busy_timeout(Duration::from_secs(5))
        .map_err(|error| format!("Cannot configure settings database: {error}"))?;
    connection
        .execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA foreign_keys = ON;",
        )
        .map_err(|error| format!("Cannot configure settings database: {error}"))?;
    migrate_schema(&connection)?;
    Ok(connection)
}

fn migrate_schema(connection: &Connection) -> Result<(), String> {
    let version: i64 = connection
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .map_err(|error| format!("Cannot read settings schema: {error}"))?;
    if version > SCHEMA_VERSION {
        return Err(format!(
            "Settings database version {version} is newer than this app supports."
        ));
    }
    if version == 0 {
        connection
            .execute_batch(
                "BEGIN IMMEDIATE;
                 CREATE TABLE app_settings (
                   id INTEGER PRIMARY KEY CHECK (id = 1),
                   selected_mode TEXT NOT NULL
                     CHECK (
                       selected_mode IN (
                         'NoIdleSleep',
                         'NoDisplaySleep',
                         'ServerMode',
                         'NetworkActive',
                         'BackgroundTask'
                       )
                     ),
                   selected_duration_seconds INTEGER
                     CHECK (
                       selected_duration_seconds IS NULL OR
                       selected_duration_seconds BETWEEN 1 AND 604800
                     )
                 ) STRICT;
                 PRAGMA user_version = 1;
                 COMMIT;",
            )
            .map_err(|error| format!("Cannot initialize settings database: {error}"))?;
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
            "Settings database contains unknown mode {value:?}."
        )),
    }
}

fn read(connection: &Connection) -> Result<Option<Settings>, String> {
    let stored: Option<(String, Option<i64>)> = connection
        .query_row(
            "SELECT selected_mode, selected_duration_seconds
             FROM app_settings
             WHERE id = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|error| format!("Cannot read settings database: {error}"))?;
    stored
        .map(|(mode, duration)| {
            let selected_duration = duration
                .map(u64::try_from)
                .transpose()
                .map_err(|_| "Settings database contains an invalid duration.".to_string())?;
            Ok(Settings {
                selected_mode: parse_mode(&mode)?,
                selected_duration,
            })
        })
        .transpose()
}

fn save_to(connection: &Connection, settings: &Settings) -> Result<(), String> {
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
        .map_err(|error| format!("Cannot save settings database: {error}"))?;
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
    if let Some(settings) = read(&connection)? {
        return Ok(settings);
    }
    let legacy_settings = load_legacy(legacy);
    let settings = legacy_settings.unwrap_or_default();
    save_to(&connection, &settings)?;
    if legacy_settings.is_some() {
        let _ = std::fs::remove_file(legacy);
    }
    Ok(settings)
}

/// Load persisted settings. Missing or unreadable state falls back to defaults;
/// subsequent writes still report database errors to the caller.
pub fn load() -> Settings {
    load_from(&database_path(), &legacy_settings_path()).unwrap_or_default()
}

pub fn save(settings: &Settings) -> Result<(), String> {
    let connection = open(&database_path())?;
    save_to(&connection, settings)
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

    fn fixture() -> (PathBuf, PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!(
            "caffeinator-settings-{}-{}",
            std::process::id(),
            NEXT_DIR.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        (dir.join(DATABASE_FILE), dir.join(LEGACY_SETTINGS_FILE), dir)
    }

    #[test]
    fn round_trips_preferences_and_indefinite_duration() {
        let (database, _legacy, dir) = fixture();
        let connection = open(&database).unwrap();
        let expected = Settings {
            selected_mode: AssertionType::BackgroundTask,
            selected_duration: None,
        };
        save_to(&connection, &expected).unwrap();
        assert_eq!(read(&connection).unwrap(), Some(expected));
        drop(connection);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn imports_and_removes_legacy_json_after_database_commit() {
        let (database, legacy, dir) = fixture();
        std::fs::write(
            &legacy,
            r#"{"selected_mode":"LidClose","selected_duration":7200}"#,
        )
        .unwrap();
        let settings = load_from(&database, &legacy).unwrap();
        assert_eq!(settings.selected_mode, AssertionType::ServerMode);
        assert_eq!(settings.selected_duration, Some(7200));
        assert!(!legacy.exists());
        assert_eq!(load_from(&database, &legacy).unwrap(), settings);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
