use core_foundation::base::TCFType;
use core_foundation::string::CFString;

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
    /// "Server Mode" in the UI — keeps the system awake 24/7 and survives lid
    /// closure via pmset. Enum variant name matches user-facing label.
    #[serde(alias = "LidClose")] // backwards-compat with old settings.json
    ServerMode,
    NetworkActive,
    BackgroundTask,
}

impl AssertionType {
    fn as_cfstring(&self) -> CFString {
        let s = match self {
            // ServerMode keeps the CPU awake via PreventUserIdleSystemSleep; display
            // sleep and screen lock follow normal macOS timers. Surviving lid closure
            // is handled separately by `enable_lid_close_prevention` (pmset).
            AssertionType::NoIdleSleep | AssertionType::ServerMode => "PreventUserIdleSystemSleep",
            AssertionType::NoDisplaySleep => "PreventUserIdleDisplaySleep",
            AssertionType::NetworkActive => "NetworkClientActive",
            AssertionType::BackgroundTask => "BackgroundTask",
        };
        CFString::new(s)
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            AssertionType::NoIdleSleep => "Idle",
            AssertionType::NoDisplaySleep => "Display",
            AssertionType::ServerMode => "Server Mode",
            AssertionType::NetworkActive => "Network",
            AssertionType::BackgroundTask => "Background",
        }
    }

    /// Whether activating this mode additionally requires `pmset -b disablesleep 1`
    /// (to survive lid closure / battery-mode sleep on power cuts). Currently only
    /// ServerMode needs this.
    pub fn needs_lid_close_prevention(&self) -> bool {
        matches!(self, AssertionType::ServerMode)
    }
}

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
        Ok(())
    } else {
        Err(format!("Failed to release power assertion: error code {}", result))
    }
}

/// Enable lid-close sleep prevention via `pmset -b disablesleep 1`.
/// Prompts for admin credentials via macOS authorization dialog.
pub fn enable_lid_close_prevention() -> Result<(), String> {
    use std::process::Command;
    let output = Command::new("osascript")
        .args([
            "-e",
            "do shell script \"pmset -b disablesleep 1; pmset -b sleep 0\" with administrator privileges",
        ])
        .output()
        .map_err(|e| format!("Failed to prompt for admin: {}", e))?;

    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("Lid-close prevention failed: {}", stderr.trim()))
    }
}

/// Disable lid-close sleep prevention. Best-effort — does not fail the caller.
pub fn disable_lid_close_prevention() {
    use std::process::Command;
    // Try with admin privileges; if user cancels, the setting persists
    let _ = Command::new("osascript")
        .args([
            "-e",
            "do shell script \"pmset -b disablesleep 0; pmset -b sleep 5\" with administrator privileges",
        ])
        .output();
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PowerProfile {
    pub source: String,
    pub display_sleep: Option<u32>,
    pub disk_sleep: Option<u32>,
    pub system_sleep: Option<u32>,
    /// Process names currently preventing system sleep (parsed from pmset's
    /// "(sleep prevented by X, Y)" parenthetical). When non-empty, the
    /// `system_sleep` timer is being overridden at runtime.
    pub system_sleep_prevented_by: Vec<String>,
    pub assertions: Vec<String>,
}

pub fn get_power_profile() -> Result<PowerProfile, String> {
    use std::process::Command;

    // Current power settings (sleep timers, "prevented by" info).
    // NB: `pmset -g` does NOT include "AC Power"/"Battery Power" strings — that
    // info lives only in `pmset -g ps`, which we query separately below.
    let pmset_output = Command::new("pmset")
        .arg("-g")
        .output()
        .map_err(|e| format!("Failed to run pmset: {}", e))?;
    let pmset_str = String::from_utf8_lossy(&pmset_output.stdout);

    // Current power source.
    let ps_output = Command::new("pmset")
        .args(["-g", "ps"])
        .output()
        .map_err(|e| format!("Failed to run pmset -g ps: {}", e))?;
    let ps_str = String::from_utf8_lossy(&ps_output.stdout);
    let source = if ps_str.contains("AC Power") {
        "AC Power".to_string()
    } else if ps_str.contains("Battery Power") {
        "Battery".to_string()
    } else {
        "Unknown".to_string()
    };

    // Parse sleep timer values (raw pmset config; may be overridden at runtime).
    let display_sleep = parse_pmset_value(&pmset_str, "displaysleep");
    let disk_sleep = parse_pmset_value(&pmset_str, "disksleep");
    let system_sleep = parse_pmset_value(&pmset_str, "sleep");
    let system_sleep_prevented_by = parse_sleep_prevented_by(&pmset_str);

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
        system_sleep_prevented_by,
        assertions,
    })
}

/// Parse the "(sleep prevented by X, Y, Z)" parenthetical from the `sleep` line.
/// Returns empty vec if no override is active.
fn parse_sleep_prevented_by(output: &str) -> Vec<String> {
    const MARKER: &str = "(sleep prevented by ";
    for line in output.lines() {
        let trimmed = line.trim();
        // Guard against matching unrelated keys like "sleepDisabled"
        if !(trimmed.starts_with("sleep ") || trimmed.starts_with("sleep\t")) {
            continue;
        }
        let Some(start) = trimmed.find(MARKER) else { continue };
        let after = &trimmed[start + MARKER.len()..];
        let Some(end) = after.find(')') else { continue };
        return after[..end]
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
    }
    Vec::new()
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
