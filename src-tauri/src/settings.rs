//! Persisted user settings.
//!
//! Lives at `~/.config/caffeinator/settings.json`. XDG-style path (unusual
//! for macOS apps, but matches the user's convention across their tooling).

use crate::power::AssertionType;
use std::path::PathBuf;

const SETTINGS_FILE: &str = "settings.json";
const CURRENT_VERSION: u32 = 2;

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
pub struct Settings {
    #[serde(default)]
    pub version: u32,
    pub selected_mode: AssertionType,
    #[serde(default = "default_duration")]
    pub selected_duration: Option<u64>,
}

fn default_duration() -> Option<u64> {
    Some(3600)
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            version: CURRENT_VERSION,
            selected_mode: AssertionType::NoIdleSleep,
            selected_duration: default_duration(),
        }
    }
}

pub(crate) fn config_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".config").join("caffeinator")
}

/// Load persisted settings. Returns defaults on any failure (missing file,
/// malformed JSON, etc.) — this is UI state, not critical data.
///
/// Runs schema migrations in-place. If the on-disk version is older than
/// `CURRENT_VERSION`, the file is rewritten after migration.
pub fn load() -> Settings {
    let path = config_dir().join(SETTINGS_FILE);
    let Some(raw) = std::fs::read_to_string(&path).ok() else {
        return Settings::default();
    };
    let Some(mut parsed) = serde_json::from_str::<Settings>(&raw).ok() else {
        return Settings::default();
    };

    if parsed.version < CURRENT_VERSION {
        parsed = migrate(parsed);
        let _ = save(&parsed);
    }
    parsed
}

/// Apply forward migrations until `settings.version == CURRENT_VERSION`.
fn migrate(mut s: Settings) -> Settings {
    // Future migrations land here as match arms.
    // v1 introduced versioning; v2 remembers the duration (serde supplies 1h).
    while s.version < CURRENT_VERSION {
        s.version += 1;
    }
    s
}

/// Persist settings. Creates parent directory if missing.
pub fn save(settings: &Settings) -> std::io::Result<()> {
    let dir = config_dir();
    std::fs::create_dir_all(&dir)?;
    let path = dir.join(SETTINGS_FILE);
    let json = serde_json::to_string_pretty(settings)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    atomic_write(&path, &json)
}

/// Replace only after the complete file is durable. Used for the recovery
/// journal too, which must reach disk before changing system settings.
pub(crate) fn atomic_write(path: &std::path::Path, json: &str) -> std::io::Result<()> {
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

    #[test]
    fn legacy_file_enters_migration() {
        // Pre-v1 files lack the `version` field; serde default must kick in.
        let legacy = r#"{"selected_mode":"NoIdleSleep"}"#;
        let parsed: Settings = serde_json::from_str(legacy).unwrap();
        assert_eq!(parsed.version, 0);
        let migrated = migrate(parsed);
        assert_eq!(migrated.version, CURRENT_VERSION);
        assert_eq!(migrated.selected_mode, AssertionType::NoIdleSleep);
    }

    #[test]
    fn server_mode_alias_still_loads() {
        let legacy = r#"{"selected_mode":"LidClose"}"#;
        let parsed: Settings = serde_json::from_str(legacy).unwrap();
        assert!(matches!(parsed.selected_mode, AssertionType::ServerMode));
    }
}
