use crate::{
    power::{self, AssertionType},
    settings,
};
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CaffeinateStatus {
    pub is_active: bool,
    pub mode: Option<AssertionType>,
    pub selected_mode: AssertionType,
    pub selected_duration: Option<u64>,
    pub remaining_seconds: Option<u64>,
    pub total_seconds: Option<u64>,
    pub busy: bool,
    pub recovery_required: bool,
    pub error: Option<String>,
    pub revision: u64,
}

trait PowerControl: Send + Sync {
    fn create(&self, mode: AssertionType) -> Result<u32, String>;
    fn release(&self, id: u32) -> Result<(), String>;
    fn enable_server(&self) -> Result<(), String>;
    fn restore_server(&self) -> Result<(), String>;
    fn recovery_needed(&self) -> Result<bool, String>;
    fn save_preferences(&self, mode: AssertionType, duration: Option<u64>) -> Result<(), String>;
}

struct MacPower;
impl PowerControl for MacPower {
    fn save_preferences(&self, mode: AssertionType, duration: Option<u64>) -> Result<(), String> {
        settings::save(&settings::Settings {
            selected_mode: mode,
            selected_duration: duration,
            ..Default::default()
        })
        .map_err(|e| format!("Could not save your preferences: {e}"))
    }
    fn create(&self, mode: AssertionType) -> Result<u32, String> {
        power::create_assertion(mode, &format!("Caffeinator: {}", mode.display_name()))
    }
    fn release(&self, id: u32) -> Result<(), String> {
        power::release_assertion(id)
    }
    fn enable_server(&self) -> Result<(), String> {
        power::enable_lid_close_prevention()
    }
    fn restore_server(&self) -> Result<(), String> {
        power::disable_lid_close_prevention()
    }
    fn recovery_needed(&self) -> Result<bool, String> {
        power::recovery_needed()
    }
}

struct InnerState {
    assertion_id: Option<u32>,
    mode: Option<AssertionType>,
    start_time: Option<Instant>,
    duration: Option<Duration>,
    server_owned: bool,
    selected_mode: AssertionType,
    selected_duration: Option<u64>,
    busy: bool,
    error: Option<String>,
    revision: u64,
}

pub struct AppState {
    inner: Mutex<InnerState>,
    // Serialize complete transitions, including authorization. Status reads do
    // not take this lock, so the webview remains responsive during a prompt.
    operation: Mutex<()>,
    power: Box<dyn PowerControl>,
}

impl Default for AppState {
    fn default() -> Self {
        let settings = settings::load();
        let state = Self::new(Box::new(MacPower), settings.selected_mode);
        state.inner.lock().unwrap().selected_duration = settings
            .selected_duration
            .filter(|secs| *secs > 0 && *secs <= 7 * 24 * 3600);
        state
    }
}

impl AppState {
    fn new(power: Box<dyn PowerControl>, selected_mode: AssertionType) -> Self {
        let recovery = power.recovery_needed();
        let server_owned = recovery.as_ref().copied().unwrap_or(true);
        let error = match recovery {
            Ok(true) => Some("An interrupted Server Mode session needs restoration.".into()),
            Err(error) => Some(error),
            Ok(false) => None,
        };
        Self {
            inner: Mutex::new(InnerState {
                assertion_id: None,
                mode: server_owned.then_some(AssertionType::ServerMode),
                start_time: None,
                duration: None,
                server_owned,
                selected_mode,
                selected_duration: Some(3600),
                busy: false,
                error,
                revision: 0,
            }),
            operation: Mutex::new(()),
            power,
        }
    }

    pub fn get_status(&self) -> CaffeinateStatus {
        let inner = self.inner.lock().unwrap();
        let remaining_seconds = match (inner.start_time, inner.duration) {
            (Some(start), Some(duration)) => {
                let remaining = duration.saturating_sub(start.elapsed());
                Some(remaining.as_secs() + u64::from(remaining.subsec_nanos() > 0))
            }
            _ => None,
        };
        CaffeinateStatus {
            is_active: inner.assertion_id.is_some() || inner.server_owned,
            mode: inner.mode,
            selected_mode: inner.selected_mode,
            selected_duration: inner.selected_duration,
            remaining_seconds,
            total_seconds: inner.duration.map(|d| d.as_secs()),
            busy: inner.busy,
            recovery_required: inner.server_owned
                && (inner.error.is_some() || inner.assertion_id.is_none()),
            error: inner.error.clone(),
            revision: inner.revision,
        }
    }

    fn transition(&self, action: impl FnOnce() -> Result<(), String>) -> Result<(), String> {
        let _operation = self
            .operation
            .try_lock()
            .map_err(|_| "Another operation is in progress. Please wait.".to_string())?;
        {
            let mut inner = self.inner.lock().unwrap();
            inner.busy = true;
            inner.revision += 1;
        }
        let result = action();
        let mut inner = self.inner.lock().unwrap();
        inner.busy = false;
        inner.error = result.as_ref().err().cloned();
        inner.revision += 1;
        result
    }

    pub fn selected_mode(&self) -> AssertionType {
        self.inner.lock().unwrap().selected_mode
    }

    pub fn select_mode(&self, mode: AssertionType) -> Result<(), String> {
        self.select_preferences(mode, self.get_status().selected_duration)
    }

    pub fn select_duration(&self, duration: Option<u64>) -> Result<(), String> {
        self.select_preferences(self.selected_mode(), duration)
    }

    pub fn select_preferences(
        &self,
        mode: AssertionType,
        duration: Option<u64>,
    ) -> Result<(), String> {
        if duration.is_some_and(|secs| secs == 0 || secs > 7 * 24 * 3600) {
            return Err("Choose a duration between 1 second and 7 days.".into());
        }
        self.transition(|| {
            if self.get_status().is_active {
                return Err("Stop your session before changing its defaults.".into());
            }
            self.power.save_preferences(mode, duration)?;
            let mut inner = self.inner.lock().unwrap();
            inner.selected_mode = mode;
            inner.selected_duration = duration;
            Ok(())
        })
    }

    pub fn activate(&self, mode: AssertionType, duration_secs: Option<u64>) -> Result<(), String> {
        if duration_secs.is_some_and(|secs| secs == 0 || secs > 7 * 24 * 3600) {
            return Err("Choose a duration between 1 second and 7 days.".into());
        }
        self.transition(|| self.activate_locked(mode, duration_secs))
    }

    pub fn toggle(&self) -> Result<(), String> {
        self.transition(|| {
            let status = self.get_status();
            if status.is_active {
                self.cleanup()
            } else {
                self.activate_locked(status.selected_mode, status.selected_duration)
            }
        })
    }

    fn activate_locked(
        &self,
        mode: AssertionType,
        duration_secs: Option<u64>,
    ) -> Result<(), String> {
        if self.get_status().recovery_required {
            return Err("Restore the previous sleep settings before starting a session.".into());
        }
        self.power.save_preferences(mode, duration_secs)?;
        {
            let mut inner = self.inner.lock().unwrap();
            inner.selected_mode = mode;
            inner.selected_duration = duration_secs;
        }
        self.cleanup()?;
        let id = self.power.create(mode)?;
        {
            let mut inner = self.inner.lock().unwrap();
            inner.assertion_id = Some(id);
            inner.mode = Some(mode);
        }
        if mode.needs_lid_close_prevention() {
            let enabled = self.power.enable_server();
            self.inner.lock().unwrap().server_owned = self.power.recovery_needed().unwrap_or(true);
            if let Err(error) = enabled {
                // Retain any uncertain global override for explicit recovery.
                if let Err(release_error) = self.power.release(id) {
                    return Err(format!("{error} {release_error}"));
                }
                let mut inner = self.inner.lock().unwrap();
                inner.assertion_id = None;
                if !inner.server_owned {
                    inner.mode = None;
                }
                return Err(error);
            }
        }
        let mut inner = self.inner.lock().unwrap();
        inner.start_time = Some(Instant::now());
        inner.duration = duration_secs.map(Duration::from_secs);
        Ok(())
    }

    // Caller owns operation. Restore before release so a canceled prompt
    // cannot discard the assertion or its cleanup bookkeeping.
    fn cleanup(&self) -> Result<(), String> {
        let (id, server_owned) = {
            let inner = self.inner.lock().unwrap();
            (inner.assertion_id, inner.server_owned)
        };
        if server_owned {
            self.power.restore_server()?;
            self.inner.lock().unwrap().server_owned = false;
        }
        if let Some(id) = id {
            self.power.release(id)?;
        }
        let mut inner = self.inner.lock().unwrap();
        inner.assertion_id = None;
        inner.mode = None;
        inner.start_time = None;
        inner.duration = None;
        Ok(())
    }

    pub fn deactivate_if_active(&self) -> Result<(), String> {
        self.transition(|| self.cleanup())
    }

    pub fn expire_if_due(&self) {
        let status = self.get_status();
        if status.busy || status.error.is_some() || status.remaining_seconds != Some(0) {
            return;
        }
        let _ = self.transition(|| {
            // Recheck under the operation lock: never stop a newer session.
            if self.get_status().remaining_seconds == Some(0) {
                self.cleanup()?;
            }
            Ok(())
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicBool, AtomicU32, Ordering},
        Arc,
    };

    #[derive(Default)]
    struct FakePower {
        recovery: AtomicBool,
        fail_restore: AtomicBool,
        fail_release: AtomicBool,
        releases: AtomicU32,
    }
    impl PowerControl for Arc<FakePower> {
        fn save_preferences(&self, _: AssertionType, _: Option<u64>) -> Result<(), String> {
            Ok(())
        }
        fn create(&self, _: AssertionType) -> Result<u32, String> {
            Ok(42)
        }
        fn release(&self, _: u32) -> Result<(), String> {
            if self.fail_release.load(Ordering::SeqCst) {
                return Err("Release failed".into());
            }
            self.releases.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }
        fn enable_server(&self) -> Result<(), String> {
            self.recovery.store(true, Ordering::SeqCst);
            Ok(())
        }
        fn restore_server(&self) -> Result<(), String> {
            if self.fail_restore.load(Ordering::SeqCst) {
                return Err("Authorization canceled".into());
            }
            self.recovery.store(false, Ordering::SeqCst);
            Ok(())
        }
        fn recovery_needed(&self) -> Result<bool, String> {
            Ok(self.recovery.load(Ordering::SeqCst))
        }
    }
    fn fixture() -> (AppState, Arc<FakePower>) {
        let power = Arc::new(FakePower::default());
        (
            AppState::new(Box::new(power.clone()), AssertionType::NoIdleSleep),
            power,
        )
    }
    #[test]
    fn failed_restore_retains_assertion_and_supports_retry() {
        let (state, power) = fixture();
        state.activate(AssertionType::ServerMode, None).unwrap();
        power.fail_restore.store(true, Ordering::SeqCst);
        assert!(state.deactivate_if_active().is_err());
        assert!(state.get_status().is_active);
        assert!(state.get_status().recovery_required);
        assert_eq!(power.releases.load(Ordering::SeqCst), 0);
        power.fail_restore.store(false, Ordering::SeqCst);
        state.deactivate_if_active().unwrap();
        assert!(!state.get_status().is_active);
        assert!(!state.get_status().recovery_required);
        assert_eq!(power.releases.load(Ordering::SeqCst), 1);
    }
    #[test]
    fn failed_release_retains_id_for_retry() {
        let (state, power) = fixture();
        state.activate(AssertionType::NoIdleSleep, None).unwrap();
        power.fail_release.store(true, Ordering::SeqCst);
        assert!(state.deactivate_if_active().is_err());
        assert!(state.get_status().is_active);
        power.fail_release.store(false, Ordering::SeqCst);
        state.deactivate_if_active().unwrap();
        assert!(!state.get_status().is_active);
    }
    #[test]
    fn startup_recovery_blocks_new_activation() {
        let power = Arc::new(FakePower::default());
        power.recovery.store(true, Ordering::SeqCst);
        let state = AppState::new(Box::new(power), AssertionType::NoIdleSleep);
        assert!(state.get_status().recovery_required);
        assert!(state.activate(AssertionType::NoIdleSleep, None).is_err());
        state.deactivate_if_active().unwrap();
        state.activate(AssertionType::NoIdleSleep, None).unwrap();
    }
    #[test]
    fn expiry_does_not_repeat_failed_authorization() {
        let (state, power) = fixture();
        state.activate(AssertionType::ServerMode, Some(1)).unwrap();
        state.inner.lock().unwrap().start_time = Some(Instant::now() - Duration::from_secs(2));
        power.fail_restore.store(true, Ordering::SeqCst);
        state.expire_if_due();
        let revision = state.get_status().revision;
        state.expire_if_due();
        assert_eq!(state.get_status().revision, revision);
        assert!(state.get_status().recovery_required);
    }
    #[test]
    fn countdown_does_not_expire_early() {
        let (state, _) = fixture();
        state
            .activate(AssertionType::NoIdleSleep, Some(60))
            .unwrap();
        assert_eq!(state.get_status().remaining_seconds, Some(60));
    }
    #[test]
    fn invalid_duration_does_not_stop_existing_session() {
        let (state, _) = fixture();
        state.activate(AssertionType::NoIdleSleep, None).unwrap();
        assert!(state
            .activate(AssertionType::NoDisplaySleep, Some(0))
            .is_err());
        assert_eq!(state.get_status().mode, Some(AssertionType::NoIdleSleep));
    }
}
