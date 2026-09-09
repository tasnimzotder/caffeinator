use crate::power::{self, AssertionType, PowerProfile};
use crate::state::{AppState, CaffeinateStatus};
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_autostart::ManagerExt;

pub const STATUS_EVENT: &str = "caffeinator://status";

pub(crate) async fn change(
    app: AppHandle,
    action: impl FnOnce(&AppState) -> Result<(), String> + Send + 'static,
) -> Result<CaffeinateStatus, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<AppState>();
        let result = action(&state);
        let status = state.get_status();
        let _ = app.emit(STATUS_EVENT, &status);
        if result.is_err() {
            crate::show_main(&app);
        }
        result.map(|_| status)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn activate(
    mode: AssertionType,
    duration_secs: Option<u64>,
    app: AppHandle,
) -> Result<CaffeinateStatus, String> {
    change(app, move |state| state.activate(mode, duration_secs)).await
}

#[tauri::command]
pub async fn deactivate(app: AppHandle) -> Result<CaffeinateStatus, String> {
    change(app, |state| state.deactivate_if_active()).await
}

#[tauri::command]
pub fn get_status(state: State<AppState>) -> CaffeinateStatus {
    state.get_status()
}

#[tauri::command]
pub async fn set_selected_mode(
    mode: AssertionType,
    app: AppHandle,
) -> Result<CaffeinateStatus, String> {
    change(app, move |state| state.select_mode(mode)).await
}

#[tauri::command]
pub async fn set_selected_duration(
    duration_secs: Option<u64>,
    app: AppHandle,
) -> Result<CaffeinateStatus, String> {
    change(app, move |state| state.select_duration(duration_secs)).await
}

#[tauri::command]
pub fn hide_window(app: AppHandle) -> Result<(), String> {
    app.get_webview_window("main")
        .ok_or("Window unavailable")?
        .hide()
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_power_profile() -> Result<PowerProfile, String> {
    tauri::async_runtime::spawn_blocking(power::get_power_profile)
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn get_power_telemetry() -> Result<crate::telemetry::PowerTelemetry, String> {
    tauri::async_runtime::spawn_blocking(crate::telemetry::read)
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn quit_app(app: AppHandle) -> Result<(), String> {
    deactivate(app.clone()).await?;
    crate::QUIT_ALLOWED.store(true, std::sync::atomic::Ordering::SeqCst);
    app.exit(0);
    Ok(())
}

#[tauri::command]
pub fn get_autostart_enabled(app: AppHandle) -> Result<bool, String> {
    app.autolaunch().is_enabled().map_err(|e| e.to_string())
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
