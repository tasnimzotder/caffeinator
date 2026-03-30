use crate::power::{self, AssertionType, PowerProfile};
use crate::state::{AppState, CaffeinateStatus};
use tauri::{image::Image, AppHandle, State};
use tauri_plugin_autostart::ManagerExt;

const ICON_INACTIVE: &[u8] = include_bytes!("../icons/tray-icon@2x.png");
const ICON_ACTIVE: &[u8] = include_bytes!("../icons/tray-icon-active@2x.png");

#[tauri::command]
pub fn activate(
    mode: AssertionType,
    duration_secs: Option<u64>,
    state: State<AppState>,
) -> Result<CaffeinateStatus, String> {
    // Deactivate any existing assertion first
    state.deactivate_if_active()?;

    // For LidClose mode, enable pmset disablesleep first (prompts for admin)
    if mode.needs_lid_close_prevention() {
        power::enable_lid_close_prevention()?;
    }

    // Create IOKit assertion
    let reason = format!("Caffeinator: Preventing {} sleep", mode.display_name());
    let assertion_id = match power::create_assertion(mode, &reason) {
        Ok(id) => id,
        Err(e) => {
            // Rollback lid-close if IOKit assertion fails
            if mode.needs_lid_close_prevention() {
                power::disable_lid_close_prevention();
            }
            return Err(e);
        }
    };

    state.set_active(assertion_id, mode, duration_secs);
    Ok(state.get_status())
}

#[tauri::command]
pub fn deactivate(
    state: State<AppState>,
    app: AppHandle,
) -> Result<CaffeinateStatus, String> {
    state.deactivate_if_active()?;

    // Clear tray title
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
        tray.set_title(Some(&title)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn set_tray_active(active: bool, app: AppHandle) -> Result<(), String> {
    if let Some(tray) = app.tray_by_id("main") {
        let bytes = if active { ICON_ACTIVE } else { ICON_INACTIVE };
        let img = Image::from_bytes(bytes).map_err(|e| e.to_string())?;
        tray.set_icon(Some(img)).map_err(|e| e.to_string())?;
        tray.set_icon_as_template(true).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn get_power_profile() -> Result<PowerProfile, String> {
    power::get_power_profile()
}

#[tauri::command]
pub fn quit_app(state: State<AppState>, app: AppHandle) {
    let _ = state.deactivate_if_active();
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
