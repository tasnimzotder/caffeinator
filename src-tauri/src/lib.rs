mod commands;
mod power;
mod state;

use state::AppState;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{
    include_image,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager,
};
use tauri_plugin_autostart::MacosLauncher;
use tauri_plugin_positioner::{Position, WindowExt};

/// Timestamp of last focus loss — used to debounce tray icon toggle
static LAST_FOCUS_LOST_MS: AtomicI64 = AtomicI64::new(0);

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn setup_tray(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let quit = MenuItem::with_id(app, "quit", "Quit Caffeinator", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&quit])?;

    let tray = TrayIconBuilder::with_id("main")
        .icon(include_image!("icons/tray-icon@2x.png"))
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| {
            if event.id.as_ref() == "quit" {
                if let Some(state) = app.try_state::<AppState>() {
                    let _ = state.deactivate_if_active();
                }
                app.exit(0);
            }
        })
        .on_tray_icon_event(|tray, event| {
            // Forward event to positioner so it tracks tray icon location
            tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);

            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    if window.is_visible().unwrap_or(false) {
                        let _ = window.hide();
                    } else {
                        // If the window was just hidden by focus loss (< 300ms ago),
                        // the user clicked the tray icon to dismiss — don't re-show.
                        let elapsed = now_ms() - LAST_FOCUS_LOST_MS.load(Ordering::SeqCst);
                        if elapsed < 300 {
                            return;
                        }
                        // Position centered below the tray icon
                        let _ = window.as_ref().window().move_window(Position::TrayCenter);
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
            }
        })
        .build(app)?;

    let _ = tray;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]),
        ))
        .manage(AppState::default())
        .on_window_event(|window, event| {
            // Hide when clicking outside the window (focus loss)
            if let tauri::WindowEvent::Focused(false) = event {
                LAST_FOCUS_LOST_MS.store(now_ms(), Ordering::SeqCst);
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::activate,
            commands::deactivate,
            commands::get_status,
            commands::toggle,
            commands::update_tray_title,
            commands::get_power_profile,
            commands::quit_app,
            commands::get_autostart_enabled,
            commands::set_autostart_enabled,
        ])
        .setup(|app| {
            setup_tray(app)?;

            #[cfg(target_os = "macos")]
            {
                app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
