# Native architecture

Caffeinator is a Swift Package executable bundled as a macOS accessory app. It has no webview, Rust runtime, remote backend, or third-party Swift dependency.

```text
Caffeinator.app
├── AppKit status item and transient popover
├── SwiftUI screens and main-thread view models
└── CaffeinatorCore
    ├── SessionEngine: serialized transitions and independent status reads
    ├── MacPower: IOKit assertions and recoverable pmset override
    ├── Storage: existing SQLite schema and legacy settings import
    ├── TelemetryReader: read-only AppleSmartBattery data
    └── ControlServer: bounded user-only Unix socket for Raycast
```

## Threading and session lifecycle

AppKit and SwiftUI run on the main thread. Session operations and sensor subprocesses run on background queues. `SessionEngine` uses an operation lock for complete transitions and a short-held state lock for snapshots. Status remains readable while an authorization prompt is open. Overlapping commands fail rather than queue duplicate toggles.

Durations are validated before replacing a session. Countdown uses monotonic uptime and rounds remaining fractional seconds upward. A one-second ticker schedules expiration. Expiry rechecks the current session under the operation lock, never repeats a failed authorization automatically, and leaves explicit retry available.

Cleanup restores the global override before releasing the IOKit assertion. Failed restoration retains ownership; failed assertion release retains the ID. Normal quit waits for successful cleanup. Crashes release per-process IOKit assertions through macOS, while Server Mode's journal remains for next-launch restoration.

## Server Mode

`power-recovery.json` retains version 1 and `sleep_disabled` (0 or 1). Its temporary file is flushed and renamed, and the parent directory is synced before running the fixed, validated `pmset -a disablesleep` command through administrator authorization. No user text enters the script. The applied value is read back. The journal is cleared only after the original value is verified. Invalid journals fail closed and are preserved.

## Storage

`caffeinator.sqlite3` retains schema version 2, table/column names, WAL mode, and a five-second busy timeout. Version 0 creates the existing settings and history schema; version 1 adds history without replacing preferences. Newer schemas are rejected. Legacy `LidClose` maps to `ServerMode`. Legacy JSON is kept after successful import for rollback reference.

Power samples are bucketed at 30 seconds and trimmed after seven days. Hour/day/week views aggregate with the original bucket intervals, and session duration is clipped to the requested range. SQL parameters are bound. Database access is serialized independently of session status.

## Control service and startup

The Swift process takes an exclusive file lock before initializing/reconciling the database. It also checks the existing control socket for the previous Tauri implementation. Only stale sockets may be removed; non-socket paths are preserved. The socket mode is 0600. At most eight clients run concurrently, requests must be newline-terminated JSON of at most 8192 bytes, unknown commands/fields are rejected, and nullable status fields remain explicitly encoded for Raycast compatibility.

Launch-at-login uses `SMAppService.mainApp`. A legacy Caffeinator LaunchAgent is removed only after successful replacement or an explicit disable. Single-instance reopen uses a distributed local notification; Raycast `show` opens the popover even before the first tray click.

## Packaging

`tools/build-app.sh` builds via SwiftPM, writes the application Info.plist, copies the icon, and ad-hoc signs and verifies the app. `tools/build-dmg.sh` adds an Applications link, creates the DMG, checks integrity, and prints SHA256. `VERSION` and the root package manifest must agree. CI validates Swift tests, the native build/protocol, and Raycast. Tagged releases publish the DMG and update the Homebrew cask. Publishing a Swift release requires macOS 13 in the generated cask.

The release is not notarized without a Developer ID certificate and Apple developer credentials.
