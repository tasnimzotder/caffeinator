//! Local control channel for Raycast. No TCP listener, shell commands, or
//! credentials: the Unix socket is readable/writable only by this macOS user.
use crate::{commands::STATUS_EVENT, power::AssertionType, state::AppState};
use std::{
    io::{BufRead, BufReader, Read, Write},
    os::unix::{
        fs::{FileTypeExt, PermissionsExt},
        net::{UnixListener, UnixStream},
    },
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
    time::Duration,
};
use tauri::{AppHandle, Emitter, Manager};

#[derive(serde::Deserialize)]
#[serde(tag = "command", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    Status,
    Preferences {
        mode: AssertionType,
        duration_secs: Option<u64>,
    },
    Start {
        mode: AssertionType,
        duration_secs: Option<u64>,
    },
    Toggle,
    Stop,
    Show,
}

fn handle(app: &AppHandle, mut stream: UnixStream) -> Result<(), String> {
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .map_err(|e| e.to_string())?;
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .map_err(|e| e.to_string())?;
    let mut line = String::new();
    BufReader::new((&stream).take(8193))
        .read_line(&mut line)
        .map_err(|e| e.to_string())?;
    let state = app.state::<AppState>();
    let result = if line.len() > 8192 || !line.ends_with('\n') {
        Err("Invalid request: expected a JSON line of at most 8192 bytes.".into())
    } else {
        serde_json::from_str::<Request>(&line)
            .map_err(|e| e.to_string())
            .and_then(|request| match request {
                Request::Status => Ok(()),
                Request::Preferences {
                    mode,
                    duration_secs,
                } => state.select_preferences(mode, duration_secs),
                Request::Start {
                    mode,
                    duration_secs,
                } => state.activate(mode, duration_secs),
                Request::Stop => state.deactivate_if_active(),
                Request::Toggle => state.toggle(),
                Request::Show => {
                    crate::show_main(app);
                    Ok(())
                }
            })
    };
    let status = state.get_status();
    let _ = app.emit(STATUS_EVENT, &status);
    if result.is_err() && status.recovery_required {
        crate::show_main(app);
    }
    let response =
        serde_json::json!({ "ok": result.is_ok(), "status": status, "error": result.err() });
    writeln!(stream, "{response}").map_err(|e| e.to_string())
}

pub fn start(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let dir = crate::storage::config_dir();
    std::fs::create_dir_all(&dir)?;
    let path = dir.join("control.sock");
    // The single-instance plugin has already claimed this app. Only remove a
    // stale socket, never an unexpected file or symbolic link at this path.
    match std::fs::symlink_metadata(&path) {
        Ok(metadata) if metadata.file_type().is_socket() => {
            if UnixStream::connect(&path).is_ok() {
                return Err("Another Caffeinator control service is running.".into());
            }
            std::fs::remove_file(&path)?;
        }
        Ok(_) => return Err("The control socket path is occupied by a non-socket file.".into()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e.into()),
    }
    let listener = UnixListener::bind(&path)?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    let app = app.clone();
    std::thread::spawn(move || {
        let clients = Arc::new(AtomicUsize::new(0));
        for stream in listener.incoming().flatten() {
            if clients.fetch_add(1, Ordering::SeqCst) >= 8 {
                clients.fetch_sub(1, Ordering::SeqCst);
                continue;
            }
            let clients = clients.clone();
            let app = app.clone();
            std::thread::spawn(move || {
                let _ = handle(&app, stream);
                clients.fetch_sub(1, Ordering::SeqCst);
            });
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_unknown_commands_and_fields() {
        assert!(serde_json::from_str::<Request>(r#"{"command":"shell","script":"bad"}"#).is_err());
        assert!(serde_json::from_str::<Request>(
            r#"{"command":"start","mode":"NoIdleSleep","duration_secs":60,"shell":"bad"}"#
        )
        .is_err());
    }
    #[test]
    fn accepts_indefinite_and_timed_sessions() {
        assert!(serde_json::from_str::<Request>(
            r#"{"command":"start","mode":"NoIdleSleep","duration_secs":null}"#
        )
        .is_ok());
        assert!(serde_json::from_str::<Request>(
            r#"{"command":"start","mode":"NoDisplaySleep","duration_secs":3600}"#
        )
        .is_ok());
        assert!(serde_json::from_str::<Request>(
            r#"{"command":"start","mode":"NoDisplaySleep","duration_secs":-1}"#
        )
        .is_err());
    }
}
