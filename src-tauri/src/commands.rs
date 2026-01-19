use crate::power::{self, AssertionType, PowerProfile};
use crate::state::{AppState, CaffeinateStatus};
use tauri::{AppHandle, State};
use tauri_plugin_autostart::ManagerExt;

#[tauri::command]
pub fn activate(
    mode: AssertionType,
    duration_secs: Option<u64>,
    state: State<AppState>,
) -> Result<CaffeinateStatus, String> {
    // Deactivate any existing assertion first
    let current_id = state.get_assertion_id();
    if current_id != 0 {
        power::release_assertion(current_id)?;
        state.clear();
    }

    // Create new assertion
    let reason = format!("Caffeinator: Preventing {} sleep", mode.display_name());
    let assertion_id = power::create_assertion(mode, &reason)?;

    // Update state
    state.set_active(assertion_id, mode, duration_secs);

    Ok(state.get_status())
}

#[tauri::command]
pub fn deactivate(
    state: State<AppState>,
    app: AppHandle,
) -> Result<CaffeinateStatus, String> {
    let current_id = state.get_assertion_id();
    if current_id != 0 {
        power::release_assertion(current_id)?;
    }
    state.clear();

    // Clear tray title - use empty string for macOS
    if let Some(tray) = app.tray_by_id("main") {
        let _ = tray.set_title(Some(""));
    }

    Ok(state.get_status())
}

#[tauri::command]
pub fn get_status(state: State<AppState>) -> CaffeinateStatus {
    state.get_status()
}

#[tauri::command]
pub fn toggle(
    mode: AssertionType,
    duration_secs: Option<u64>,
    state: State<AppState>,
    app: AppHandle,
) -> Result<CaffeinateStatus, String> {
    let status = state.get_status();
    if status.is_active {
        deactivate(state, app)
    } else {
        activate(mode, duration_secs, state)
    }
}

#[tauri::command]
pub fn update_tray_title(title: String, app: AppHandle) -> Result<(), String> {
    if let Some(tray) = app.tray_by_id("main") {
        // Use the title as-is, empty string clears on macOS
        if title.is_empty() {
            tray.set_title(Some(""))
                .map_err(|e| e.to_string())?;
        } else {
            tray.set_title(Some(title.as_str()))
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

#[tauri::command]
pub fn get_power_profile() -> Result<PowerProfile, String> {
    power::get_power_profile()
}

#[tauri::command]
pub fn quit_app(state: State<AppState>, app: AppHandle) {
    // Clean up any active assertion before quitting
    let assertion_id = state.get_assertion_id();
    if assertion_id != 0 {
        let _ = power::release_assertion(assertion_id);
    }
    app.exit(0);
}

#[tauri::command]
pub fn get_autostart_enabled(app: AppHandle) -> Result<bool, String> {
    app.autolaunch()
        .is_enabled()
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn set_autostart_enabled(enabled: bool, app: AppHandle) -> Result<(), String> {
    let autostart = app.autolaunch();
    if enabled {
        autostart.enable().map_err(|e| e.to_string())
    } else {
        autostart.disable().map_err(|e| e.to_string())
    }
}
