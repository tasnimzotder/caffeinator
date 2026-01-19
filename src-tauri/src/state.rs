use crate::power::AssertionType;
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

pub struct AppState {
    pub assertion_id: Mutex<u32>,
    pub mode: Mutex<Option<AssertionType>>,
    pub start_time: Mutex<Option<Instant>>,
    pub duration: Mutex<Option<Duration>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            assertion_id: Mutex::new(0),
            mode: Mutex::new(None),
            start_time: Mutex::new(None),
            duration: Mutex::new(None),
        }
    }
}

impl AppState {
    pub fn get_status(&self) -> CaffeinateStatus {
        let assertion_id = *self.assertion_id.lock().unwrap();
        let mode = *self.mode.lock().unwrap();
        let start_time = *self.start_time.lock().unwrap();
        let duration = *self.duration.lock().unwrap();

        let is_active = assertion_id != 0;

        let remaining_seconds = if is_active {
            match (start_time, duration) {
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

        let total_seconds = duration.map(|d| d.as_secs());

        CaffeinateStatus {
            is_active,
            mode,
            remaining_seconds,
            total_seconds,
        }
    }

    pub fn set_active(&self, id: u32, mode: AssertionType, duration_secs: Option<u64>) {
        *self.assertion_id.lock().unwrap() = id;
        *self.mode.lock().unwrap() = Some(mode);
        *self.start_time.lock().unwrap() = Some(Instant::now());
        *self.duration.lock().unwrap() = duration_secs.map(Duration::from_secs);
    }

    pub fn clear(&self) {
        *self.assertion_id.lock().unwrap() = 0;
        *self.mode.lock().unwrap() = None;
        *self.start_time.lock().unwrap() = None;
        *self.duration.lock().unwrap() = None;
    }

    pub fn get_assertion_id(&self) -> u32 {
        *self.assertion_id.lock().unwrap()
    }

    #[allow(dead_code)]
    pub fn is_expired(&self) -> bool {
        let start_time = *self.start_time.lock().unwrap();
        let duration = *self.duration.lock().unwrap();

        match (start_time, duration) {
            (Some(start), Some(dur)) => start.elapsed() >= dur,
            _ => false,
        }
    }
}
