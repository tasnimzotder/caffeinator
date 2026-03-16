use crate::power::{self, AssertionType};
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CaffeinateStatus {
    pub is_active: bool,
    pub mode: Option<AssertionType>,
    pub remaining_seconds: Option<u64>,
    pub total_seconds: Option<u64>,
}

impl Default for CaffeinateStatus {
    fn default() -> Self {
        Self {
            is_active: false,
            mode: None,
            remaining_seconds: None,
            total_seconds: None,
        }
    }
}

struct InnerState {
    assertion_id: u32,
    mode: Option<AssertionType>,
    start_time: Option<Instant>,
    duration: Option<Duration>,
}

pub struct AppState {
    inner: Mutex<InnerState>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            inner: Mutex::new(InnerState {
                assertion_id: 0,
                mode: None,
                start_time: None,
                duration: None,
            }),
        }
    }
}

impl AppState {
    pub fn get_status(&self) -> CaffeinateStatus {
        let inner = self.inner.lock().unwrap();
        let is_active = inner.assertion_id != 0;

        let remaining_seconds = if is_active {
            match (inner.start_time, inner.duration) {
                (Some(start), Some(dur)) => {
                    let elapsed = start.elapsed();
                    if elapsed >= dur {
                        Some(0)
                    } else {
                        Some((dur - elapsed).as_secs())
                    }
                }
                _ => None, // Indefinite
            }
        } else {
            None
        };

        let total_seconds = inner.duration.map(|d| d.as_secs());

        CaffeinateStatus {
            is_active,
            mode: inner.mode,
            remaining_seconds,
            total_seconds,
        }
    }

    pub fn set_active(&self, id: u32, mode: AssertionType, duration_secs: Option<u64>) {
        let mut inner = self.inner.lock().unwrap();
        inner.assertion_id = id;
        inner.mode = Some(mode);
        inner.start_time = Some(Instant::now());
        inner.duration = duration_secs.map(Duration::from_secs);
    }

    /// Release any active assertion and clear state.
    /// Takes the assertion ID atomically, clears state, then releases outside the lock.
    pub fn deactivate_if_active(&self) -> Result<(), String> {
        let assertion_id = {
            let mut inner = self.inner.lock().unwrap();
            let id = inner.assertion_id;
            inner.assertion_id = 0;
            inner.mode = None;
            inner.start_time = None;
            inner.duration = None;
            id
        };
        if assertion_id != 0 {
            power::release_assertion(assertion_id)?;
        }
        Ok(())
    }
}
