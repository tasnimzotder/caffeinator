use core_foundation::base::TCFType;
use core_foundation::string::CFString;
use std::sync::atomic::{AtomicU32, Ordering};

#[link(name = "IOKit", kind = "framework")]
extern "C" {
    fn IOPMAssertionCreateWithName(
        assertion_type: core_foundation::string::CFStringRef,
        assertion_level: u32,
        assertion_name: core_foundation::string::CFStringRef,
        assertion_id: *mut u32,
    ) -> i32;

    fn IOPMAssertionRelease(assertion_id: u32) -> i32;
}

const K_IOPM_ASSERTION_LEVEL_ON: u32 = 255;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum AssertionType {
    NoIdleSleep,
    NoDisplaySleep,
    PreventSystemSleep,
    NetworkActive,
    BackgroundTask,
}

impl AssertionType {
    fn as_cfstring(&self) -> CFString {
        let s = match self {
            AssertionType::NoIdleSleep => "PreventUserIdleSystemSleep",
            AssertionType::NoDisplaySleep => "PreventUserIdleDisplaySleep",
            AssertionType::PreventSystemSleep => "PreventSystemSleep",
            AssertionType::NetworkActive => "NetworkClientActive",
            AssertionType::BackgroundTask => "BackgroundTask",
        };
        CFString::new(s)
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            AssertionType::NoIdleSleep => "Idle",
            AssertionType::NoDisplaySleep => "Display",
            AssertionType::PreventSystemSleep => "System",
            AssertionType::NetworkActive => "Network",
            AssertionType::BackgroundTask => "Background",
        }
    }
}

static CURRENT_ASSERTION_ID: AtomicU32 = AtomicU32::new(0);

pub fn create_assertion(assertion_type: AssertionType, reason: &str) -> Result<u32, String> {
    let type_cf = assertion_type.as_cfstring();
    let reason_cf = CFString::new(reason);
    let mut assertion_id: u32 = 0;

    let result = unsafe {
        IOPMAssertionCreateWithName(
            type_cf.as_concrete_TypeRef(),
            K_IOPM_ASSERTION_LEVEL_ON,
            reason_cf.as_concrete_TypeRef(),
            &mut assertion_id,
        )
    };

    if result == 0 {
        CURRENT_ASSERTION_ID.store(assertion_id, Ordering::SeqCst);
        Ok(assertion_id)
    } else {
        Err(format!("Failed to create power assertion: error code {}", result))
    }
}

pub fn release_assertion(assertion_id: u32) -> Result<(), String> {
    if assertion_id == 0 {
        return Ok(());
    }

    let result = unsafe { IOPMAssertionRelease(assertion_id) };

    if result == 0 {
        CURRENT_ASSERTION_ID.store(0, Ordering::SeqCst);
        Ok(())
    } else {
        Err(format!("Failed to release power assertion: error code {}", result))
    }
}

#[allow(dead_code)]
pub fn get_current_assertion_id() -> u32 {
    CURRENT_ASSERTION_ID.load(Ordering::SeqCst)
}

#[allow(dead_code)]
pub fn has_active_assertion() -> bool {
    get_current_assertion_id() != 0
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PowerProfile {
    pub source: String,
    pub display_sleep: Option<u32>,
    pub disk_sleep: Option<u32>,
    pub system_sleep: Option<u32>,
    pub assertions: Vec<String>,
}

pub fn get_power_profile() -> Result<PowerProfile, String> {
    use std::process::Command;

    // Get current power settings
    let pmset_output = Command::new("pmset")
        .arg("-g")
        .output()
        .map_err(|e| format!("Failed to run pmset: {}", e))?;

    let pmset_str = String::from_utf8_lossy(&pmset_output.stdout);

    // Parse power source
    let source = if pmset_str.contains("AC Power") {
        "AC Power".to_string()
    } else if pmset_str.contains("Battery Power") {
        "Battery".to_string()
    } else {
        "Unknown".to_string()
    };

    // Parse sleep values
    let display_sleep = parse_pmset_value(&pmset_str, "displaysleep");
    let disk_sleep = parse_pmset_value(&pmset_str, "disksleep");
    let system_sleep = parse_pmset_value(&pmset_str, "sleep");

    // Get active assertions
    let assertions_output = Command::new("pmset")
        .args(["-g", "assertions"])
        .output()
        .map_err(|e| format!("Failed to run pmset assertions: {}", e))?;

    let assertions_str = String::from_utf8_lossy(&assertions_output.stdout);
    let assertions = parse_assertions(&assertions_str);

    Ok(PowerProfile {
        source,
        display_sleep,
        disk_sleep,
        system_sleep,
        assertions,
    })
}

fn parse_pmset_value(output: &str, key: &str) -> Option<u32> {
    for line in output.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with(key) {
            // Format: "displaysleep         10"
            let parts: Vec<&str> = trimmed.split_whitespace().collect();
            if parts.len() >= 2 {
                return parts[1].parse().ok();
            }
        }
    }
    None
}

fn parse_assertions(output: &str) -> Vec<String> {
    let mut assertions = Vec::new();
    let mut in_listed = false;

    for line in output.lines() {
        if line.contains("Listed by owning process") {
            in_listed = true;
            continue;
        }
        if in_listed && line.trim().starts_with("pid") {
            // Format: "   pid 1234(processName): [0x000012345678901234] 00:00:00 AssertionType named: "reason""
            if let Some(start) = line.find("):") {
                let rest = &line[start + 2..];
                if let Some(bracket_end) = rest.find(']') {
                    let after_bracket = &rest[bracket_end + 1..];
                    // Get the assertion type and name
                    let parts: Vec<&str> = after_bracket.trim().splitn(3, ' ').collect();
                    if parts.len() >= 2 {
                        let assertion_info = format!(
                            "{}: {}",
                            parts.get(1).unwrap_or(&"Unknown"),
                            line.split('(').next().unwrap_or("").trim().replace("pid ", "PID ")
                        );
                        assertions.push(assertion_info);
                    }
                }
            }
        }
    }

    assertions
}
