mod commands;
#[cfg(target_os = "macos")]
mod macos_window;
mod power;
mod settings;
mod state;

use power::AssertionType;
use state::AppState;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{
    image::Image,
    menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem, Submenu},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager,
};
use tauri_plugin_autostart::MacosLauncher;
use tauri_plugin_positioner::{Position, WindowExt};

static LAST_FOCUS_LOST_MS: AtomicI64 = AtomicI64::new(0);

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

const ICON_INACTIVE: &[u8] = include_bytes!("../icons/tray-icon@2x.png");
const ICON_ACTIVE: &[u8] = include_bytes!("../icons/tray-icon-active@2x.png");

fn format_tray_time(seconds: u64) -> String {
    let h = seconds / 3600;
    let m = (seconds % 3600) / 60;
    if h > 0 {
        format!("{}:{:02}", h, m)
    } else {
        format!("{}m", m)
    }
}

fn set_tray_icon(app: &AppHandle, active: bool) {
    if let Some(tray) = app.tray_by_id("main") {
        let bytes = if active { ICON_ACTIVE } else { ICON_INACTIVE };
        if let Ok(img) = Image::from_bytes(bytes) {
            let _ = tray.set_icon(Some(img));
            let _ = tray.set_icon_as_template(true);
        }
    }
}

/// Menu-ID ↔ AssertionType mapping for the "Mode" submenu.
const MODE_MENU: [(&str, AssertionType); 5] = [
    ("mode_idle", AssertionType::NoIdleSleep),
    ("mode_display", AssertionType::NoDisplaySleep),
    ("mode_server", AssertionType::ServerMode),
    ("mode_network", AssertionType::NetworkActive),
    ("mode_background", AssertionType::BackgroundTask),
];

fn mode_from_menu_id(id: &str) -> Option<AssertionType> {
    MODE_MENU.iter().find(|(i, _)| *i == id).map(|(_, m)| *m)
}

/// Clones of the Mode submenu's check items, stashed in Tauri-managed state
/// so the menu handler can toggle radio marks without re-traversing the menu
/// tree (TrayIcon has no `menu()` getter in Tauri v2, and menu items are
/// cheap Arc-backed handles so cloning is fine).
struct ModeCheckItems {
    items: Vec<(AssertionType, CheckMenuItem<tauri::Wry>)>,
}

/// Set radio-style check marks on the Mode submenu so only `selected` is ticked.
fn update_mode_check_states(app: &AppHandle, selected: AssertionType) {
    let Some(handles) = app.try_state::<ModeCheckItems>() else { return };
    for (mode, item) in &handles.items {
        let _ = item.set_checked(*mode == selected);
    }
}

fn setup_tray(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    // Read the current sticky mode (already populated from settings by setup()).
    let selected = app
        .try_state::<AppState>()
        .map(|s| s.selected_mode())
        .unwrap_or(AssertionType::NoIdleSleep);

    // Mode submenu — radio-style check items, one pre-checked from persisted settings.
    let mode_idle = CheckMenuItem::with_id(
        app, "mode_idle", "Idle", true,
        selected == AssertionType::NoIdleSleep, None::<&str>,
    )?;
    let mode_display = CheckMenuItem::with_id(
        app, "mode_display", "Display", true,
        selected == AssertionType::NoDisplaySleep, None::<&str>,
    )?;
    let mode_server = CheckMenuItem::with_id(
        app, "mode_server", "Server Mode", true,
        selected == AssertionType::ServerMode, None::<&str>,
    )?;
    let mode_network = CheckMenuItem::with_id(
        app, "mode_network", "Network", true,
        selected == AssertionType::NetworkActive, None::<&str>,
    )?;
    let mode_background = CheckMenuItem::with_id(
        app, "mode_background", "Background", true,
        selected == AssertionType::BackgroundTask, None::<&str>,
    )?;
    let mode_submenu = Submenu::with_id_and_items(
        app, "mode", "Mode", true,
        &[&mode_idle, &mode_display, &mode_server, &mode_network, &mode_background],
    )?;

    // Stash the check items so the menu handler can flip radio marks later.
    app.manage(ModeCheckItems {
        items: vec![
            (AssertionType::NoIdleSleep, mode_idle.clone()),
            (AssertionType::NoDisplaySleep, mode_display.clone()),
            (AssertionType::ServerMode, mode_server.clone()),
            (AssertionType::NetworkActive, mode_network.clone()),
            (AssertionType::BackgroundTask, mode_background.clone()),
        ],
    });

    // Duration submenu (now includes 4h, matching the webview's preset set).
    let start_30m = MenuItem::with_id(app, "start_30m", "30 Minutes", true, None::<&str>)?;
    let start_1h = MenuItem::with_id(app, "start_1h", "1 Hour", true, None::<&str>)?;
    let start_2h = MenuItem::with_id(app, "start_2h", "2 Hours", true, None::<&str>)?;
    let start_4h = MenuItem::with_id(app, "start_4h", "4 Hours", true, None::<&str>)?;
    let start_indef = MenuItem::with_id(app, "start_indef", "Indefinite", true, None::<&str>)?;
    let start_submenu = Submenu::with_id_and_items(
        app, "start", "Start for", true,
        &[&start_30m, &start_1h, &start_2h, &start_4h, &start_indef],
    )?;

    let stop = MenuItem::with_id(app, "stop", "Stop", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Caffeinator", true, None::<&str>)?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let sep2 = PredefinedMenuItem::separator(app)?;
    let sep3 = PredefinedMenuItem::separator(app)?;

    let menu = Menu::with_items(
        app,
        &[&mode_submenu, &sep1, &start_submenu, &sep2, &stop, &sep3, &quit],
    )?;

    let tray = TrayIconBuilder::with_id("main")
        .icon(Image::from_bytes(ICON_INACTIVE)?)
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| {
            let id = event.id.as_ref();
            match id {
                "quit" => {
                    if let Some(state) = app.try_state::<AppState>() {
                        let _ = state.deactivate_if_active();
                    }
                    app.exit(0);
                }
                "stop" => {
                    if let Some(state) = app.try_state::<AppState>() {
                        let _ = state.deactivate_if_active();
                        if let Some(tray) = app.tray_by_id("main") {
                            let _ = tray.set_title(Some(""));
                        }
                        set_tray_icon(app, false);
                    }
                }
                "start_30m" | "start_1h" | "start_2h" | "start_4h" | "start_indef" => {
                    let duration_secs: Option<u64> = match id {
                        "start_30m" => Some(30 * 60),
                        "start_1h" => Some(60 * 60),
                        "start_2h" => Some(2 * 60 * 60),
                        "start_4h" => Some(4 * 60 * 60),
                        _ => None,
                    };
                    if let Some(state) = app.try_state::<AppState>() {
                        let _ = state.deactivate_if_active();
                        let mode = state.selected_mode();

                        // Mirror the IPC `activate` command's flow: if the mode needs
                        // lid-close prevention, prompt for admin before creating the
                        // IOKit assertion. Early-return (skip activation) if declined.
                        if mode.needs_lid_close_prevention() {
                            if let Err(e) = power::enable_lid_close_prevention() {
                                eprintln!("[caffeinator] lid-close prevention failed: {}", e);
                                return;
                            }
                        }

                        let reason = format!("Caffeinator: Preventing {} sleep", mode.display_name());
                        match power::create_assertion(mode, &reason) {
                            Ok(assertion_id) => {
                                state.set_active(assertion_id, mode, duration_secs);
                                set_tray_icon(app, true);
                                if let Some(tray) = app.tray_by_id("main") {
                                    let title = match duration_secs {
                                        Some(secs) => format_tray_time(secs),
                                        None => "∞".to_string(),
                                    };
                                    let _ = tray.set_title(Some(&title));
                                }
                            }
                            Err(_) => {
                                // Rollback lid-close if the assertion failed after we enabled it.
                                if mode.needs_lid_close_prevention() {
                                    power::disable_lid_close_prevention();
                                }
                            }
                        }
                    }
                }
                other => {
                    // Mode radio-selection: update state, re-draw check marks, persist.
                    if let Some(mode) = mode_from_menu_id(other) {
                        if let Some(state) = app.try_state::<AppState>() {
                            state.set_selected_mode(mode);
                        }
                        update_mode_check_states(app, mode);
                        if let Err(e) = settings::save(&settings::Settings { selected_mode: mode }) {
                            eprintln!("[caffeinator] settings save failed: {}", e);
                        }
                    }
                }
            }
        })
        .on_tray_icon_event(|tray, event| {
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
                        let elapsed = now_ms() - LAST_FOCUS_LOST_MS.load(Ordering::SeqCst);
                        if elapsed < 300 {
                            return;
                        }
                        let _ = window.as_ref().window().move_window(Position::TrayCenter);
                        let _ = window.show();
                        #[cfg(target_os = "macos")]
                        macos_window::set_fullscreen_overlay_behavior(&window);
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
            commands::set_tray_active,
            commands::get_power_profile,
            commands::quit_app,
            commands::get_autostart_enabled,
            commands::set_autostart_enabled,
        ])
        .setup(|app| {
            // Apply persisted sticky mode before the tray builds its radio items.
            let persisted = settings::load();
            if let Some(state) = app.try_state::<AppState>() {
                state.set_selected_mode(persisted.selected_mode);
            }

            setup_tray(app)?;

            #[cfg(target_os = "macos")]
            {
                app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            }

            // Background timer: updates tray title every second, independent of webview
            let app_handle = app.handle().clone();
            std::thread::spawn(move || {
                let mut prev_title = String::new();
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(1));
                    if let Some(state) = app_handle.try_state::<AppState>() {
                        let status = state.get_status();

                        // Auto-deactivate when timer expires
                        if status.is_active && status.remaining_seconds == Some(0) {
                            let _ = state.deactivate_if_active();
                            if let Some(tray) = app_handle.tray_by_id("main") {
                                let _ = tray.set_title(Some(""));
                            }
                            set_tray_icon(&app_handle, false);
                            prev_title.clear();
                            continue;
                        }

                        let title = if status.is_active {
                            match status.remaining_seconds {
                                Some(secs) => format_tray_time(secs),
                                None => "∞".to_string(),
                            }
                        } else {
                            String::new()
                        };

                        if title != prev_title {
                            if let Some(tray) = app_handle.tray_by_id("main") {
                                let _ = tray.set_title(Some(&title));
                            }
                            prev_title = title;
                        }
                    }
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
