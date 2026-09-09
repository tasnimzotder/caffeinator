mod commands;
mod control;
#[cfg(target_os = "macos")]
mod macos_window;
mod power;
mod settings;
mod state;
mod telemetry;

use commands::STATUS_EVENT;
use state::AppState;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{
    image::Image,
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, PhysicalPosition,
};
use tauri_plugin_autostart::MacosLauncher;
use tauri_plugin_positioner::{Position, WindowExt};

static LAST_FOCUS_LOST_MS: AtomicI64 = AtomicI64::new(0);
static QUIT_ALLOWED: AtomicBool = AtomicBool::new(false);
static TRAY_POSITION_KNOWN: AtomicBool = AtomicBool::new(false);

fn show_main(app: &AppHandle) {
    let dispatcher = app.clone();
    let app = app.clone();
    // NSWindow collection behavior must be changed on the AppKit main thread.
    // This helper is also called by worker threads and the Raycast socket.
    let _ = dispatcher.run_on_main_thread(move || {
        if let Some(window) = app.get_webview_window("main") {
            // Positioner panics for TrayCenter until it receives a tray event.
            // Raycast and recovery can open the window before the first click.
            let position = if TRAY_POSITION_KNOWN.load(Ordering::SeqCst) {
                Position::TrayCenter
            } else {
                Position::TopRight
            };
            let _ = window.as_ref().window().move_window(position);
            let _ = window.show();
            #[cfg(target_os = "macos")]
            macos_window::set_fullscreen_overlay_behavior(&window);
            let _ = window.set_focus();
        }
    });
}

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

fn setup_tray(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let tray = TrayIconBuilder::with_id("main")
        .icon(Image::from_bytes(ICON_INACTIVE)?)
        .icon_as_template(true)
        .show_menu_on_left_click(false)
        .on_tray_icon_event(|tray, event| {
            tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);

            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                rect,
                ..
            } = event
            {
                let app = tray.app_handle();
                TRAY_POSITION_KNOWN.store(true, Ordering::SeqCst);
                if let Some(window) = app.get_webview_window("main") {
                    if window.is_visible().unwrap_or(false) {
                        let _ = window.hide();
                    } else {
                        let elapsed = now_ms() - LAST_FOCUS_LOST_MS.load(Ordering::SeqCst);
                        if elapsed < 300 {
                            return;
                        }

                        // Positioner::TrayCenter falls back to the tray item's
                        // top edge on macOS, which overlaps the menu bar. Use
                        // the click's physical tray rect so the panel sits just
                        // below the item and remains on the clicked display.
                        if let Ok(window_size) = window.outer_size() {
                            let scale = window.scale_factor().unwrap_or(1.0);
                            let tray_position = rect.position.to_physical::<f64>(1.0);
                            let tray_size = rect.size.to_physical::<f64>(1.0);
                            let gap = 6.0 * scale;
                            let edge = 10.0 * scale;
                            let tray_center = tray_position.x + tray_size.width / 2.0;
                            let mut x = tray_center - f64::from(window_size.width) / 2.0;
                            let mut y = tray_position.y + tray_size.height + gap;

                            if let Ok(monitors) = window.available_monitors() {
                                if let Some(monitor) = monitors.iter().find(|monitor| {
                                    let origin = monitor.position();
                                    let size = monitor.size();
                                    tray_center >= f64::from(origin.x)
                                        && tray_center < f64::from(origin.x) + f64::from(size.width)
                                        && tray_position.y >= f64::from(origin.y)
                                        && tray_position.y
                                            < f64::from(origin.y) + f64::from(size.height)
                                }) {
                                    let origin = monitor.position();
                                    let size = monitor.size();
                                    let min_x = f64::from(origin.x) + edge;
                                    let max_x = f64::from(origin.x) + f64::from(size.width)
                                        - f64::from(window_size.width)
                                        - edge;
                                    let min_y = f64::from(origin.y) + tray_size.height + gap;
                                    let max_y = f64::from(origin.y) + f64::from(size.height)
                                        - f64::from(window_size.height)
                                        - edge;
                                    x = x.clamp(min_x, max_x.max(min_x));
                                    y = y.clamp(min_y, max_y.max(min_y));
                                }
                            }

                            let _ = window.set_position(PhysicalPosition::new(
                                x.round() as i32,
                                y.round() as i32,
                            ));
                        } else {
                            let _ = window.as_ref().window().move_window(Position::TrayCenter);
                        }
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
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            show_main(app)
        }))
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
            commands::set_selected_mode,
            commands::set_selected_duration,
            commands::hide_window,
            commands::get_power_profile,
            commands::get_power_telemetry,
            commands::quit_app,
            commands::get_autostart_enabled,
            commands::set_autostart_enabled,
        ])
        .setup(|app| {
            control::start(app.handle())?;
            setup_tray(app)?;

            #[cfg(target_os = "macos")]
            {
                app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            }

            // The one-second event stream is independent of tray text changes.
            // Privileged expiry work runs separately so status remains readable.
            let app_handle = app.handle().clone();
            std::thread::spawn(move || {
                let mut prev_title = String::new();
                let mut prev_active = false;
                let expiry_running = std::sync::Arc::new(AtomicBool::new(false));
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(1));
                    let state = app_handle.state::<AppState>();
                    let status = state.get_status();
                    if !status.busy
                        && status.error.is_none()
                        && status.remaining_seconds == Some(0)
                        && !expiry_running.swap(true, Ordering::SeqCst)
                    {
                        let app = app_handle.clone();
                        let running = expiry_running.clone();
                        std::thread::spawn(move || {
                            let state = app.state::<AppState>();
                            state.expire_if_due();
                            let status = state.get_status();
                            let _ = app.emit(STATUS_EVENT, &status);
                            if status.error.is_some() {
                                show_main(&app);
                            }
                            running.store(false, Ordering::SeqCst);
                        });
                    }
                    let title = if status.recovery_required {
                        "!".to_string()
                    } else if status.is_active {
                        status
                            .remaining_seconds
                            .map(format_tray_time)
                            .unwrap_or_else(|| "∞".to_string())
                    } else {
                        String::new()
                    };
                    if status.is_active != prev_active {
                        set_tray_icon(&app_handle, status.is_active);
                        prev_active = status.is_active;
                    }
                    if title != prev_title {
                        if let Some(tray) = app_handle.tray_by_id("main") {
                            let _ = tray.set_title(Some(&title));
                        }
                        prev_title = title;
                    }
                    let _ = app_handle.emit(STATUS_EVENT, &status);
                }
            });
            if app.state::<AppState>().get_status().recovery_required {
                show_main(app.handle());
            }

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| {
            if let tauri::RunEvent::ExitRequested { api, .. } = event {
                if !QUIT_ALLOWED.load(Ordering::SeqCst) {
                    api.prevent_exit();
                    let app = app.clone();
                    tauri::async_runtime::spawn(async move {
                        if commands::quit_app(app.clone()).await.is_err() {
                            show_main(&app);
                        }
                    });
                }
            }
        });
}
