mod commands;
mod power;
mod state;

use state::AppState;
use tauri::{
    include_image,
    menu::{Menu, MenuItem},
    tray::{TrayIconBuilder, TrayIconEvent},
    Manager,
};
use tauri_plugin_autostart::MacosLauncher;

fn setup_tray(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    // Create menu for right-click
    let quit = MenuItem::with_id(app, "quit", "Quit Caffeinator", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&quit])?;

    // Build tray icon programmatically
    let tray = TrayIconBuilder::with_id("main")
        .icon(include_image!("icons/32x32.png"))
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(false) // Critical: don't open menu on left click
        .on_menu_event(|app, event| {
            if event.id.as_ref() == "quit" {
                // Clean up any active assertion before quitting
                if let Some(state) = app.try_state::<AppState>() {
                    let assertion_id = state.get_assertion_id();
                    if assertion_id != 0 {
                        let _ = power::release_assertion(assertion_id);
                    }
                }
                app.exit(0);
            }
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: tauri::tray::MouseButton::Left,
                button_state: tauri::tray::MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    if window.is_visible().unwrap_or(false) {
                        let _ = window.hide();
                    } else {
                        let _ = window.unminimize();
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
            }
        })
        .build(app)?;

    // Keep tray reference alive (it's stored in app state automatically)
    let _ = tray;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]),
        ))
        .manage(AppState::default())
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
        // Focus loss handler commented out for debugging
        // .on_window_event(|window, event| {
        //     if let WindowEvent::Focused(false) = event {
        //         let _ = window.hide();
        //     }
        // })
        .setup(|app| {
            setup_tray(app)?;

            // Hide dock icon on macOS for menu bar app behavior
            #[cfg(target_os = "macos")]
            {
                app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
