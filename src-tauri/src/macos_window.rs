//! macOS-specific window behavior helpers.
//!
//! Fixes visibility of the main window when another app is in a macOS
//! full-screen Space. Without the correct NSWindow collection behavior,
//! clicking the tray icon while a full-screen app is active causes the
//! window to show in the *Desktop* Space — invisible to the user.

#![cfg(target_os = "macos")]

use objc2::rc::Retained;
use objc2_app_kit::{NSWindow, NSWindowCollectionBehavior};
use tauri::{Runtime, WebviewWindow};

/// Make the window capable of overlaying full-screen Spaces.
///
/// Sets the NSWindow's collection behavior to include:
///   - `CanJoinAllSpaces`     — window becomes a member of every Space
///   - `FullScreenAuxiliary`  — window may composite over a full-screen app
///
/// Both flags are required: without `CanJoinAllSpaces`, the window stays
/// pinned to the Desktop Space; without `FullScreenAuxiliary`, macOS
/// refuses to draw a non-fullscreen window on top of a full-screen Space.
///
/// Idempotent — safe to call on every window show.
pub fn set_fullscreen_overlay_behavior<R: Runtime>(window: &WebviewWindow<R>) {
    // Tauri hands us a raw pointer to the underlying NSWindow.
    let Ok(ns_window_ptr) = window.ns_window() else {
        return;
    };
    if ns_window_ptr.is_null() {
        return;
    }

    let ns_window = unsafe { Retained::retain(ns_window_ptr.cast::<NSWindow>()) };
    let Some(ns_window) = ns_window else { return };
    let behavior = NSWindowCollectionBehavior::CanJoinAllSpaces
        | NSWindowCollectionBehavior::FullScreenAuxiliary;
    unsafe { ns_window.setCollectionBehavior(behavior) };
}
