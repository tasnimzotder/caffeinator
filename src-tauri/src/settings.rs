//! Persisted user settings.
//!
//! Lives at `~/.config/caffeinator/settings.json`. XDG-style path (unusual
//! for macOS apps, but matches the user's convention across their tooling).

use crate::power::AssertionType;
use std::path::PathBuf;

const SETTINGS_FILE: &str = "settings.json";

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
pub struct Settings {
    pub selected_mode: AssertionType,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            selected_mode: AssertionType::NoIdleSleep,
        }
    }
}

fn config_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".config").join("caffeinator")
}

/// Load persisted settings. Returns defaults on any failure (missing file,
/// malformed JSON, etc.) — this is UI state, not critical data.
pub fn load() -> Settings {
    let path = config_dir().join(SETTINGS_FILE);
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

/// Persist settings. Creates parent directory if missing.
pub fn save(settings: &Settings) -> std::io::Result<()> {
    let dir = config_dir();
    std::fs::create_dir_all(&dir)?;
    let path = dir.join(SETTINGS_FILE);
    let json = serde_json::to_string_pretty(settings)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    std::fs::write(path, json)
}
