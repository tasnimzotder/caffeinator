# Caffeinator internals

## Native state owns the session

React, the native tray, and Raycast all call the same Rust state machine in `state.rs`. A transition lock serializes activation, deactivation, and preference changes. Status has a separate short-lived lock, so a macOS authorization prompt does not block status reads. Commands that could prompt or wait run off the main UI thread. AppKit window changes are dispatched onto the main thread.

`CaffeinateStatus` includes activity, active and selected modes, selected duration, remaining and total seconds, busy state, recovery state, an actionable error, and a monotonically increasing revision. React subscribes before its initial status fetch and rejects stale revisions. The one-second status stream is independent of the minute-formatted tray title. Countdown values round upward, so expiration does not happen early.

Timer expiry rechecks the current deadline under the transition lock. It cannot stop a newer session using an old snapshot. A failed expiry cleanup records an error and stops automatic retries, avoiding repeated authorization prompts.

## Assertion lifecycle and Server Mode

Normal modes use an IOKit assertion owned by the app process. An assertion is retained in state until its release succeeds.

Server Mode also reads the global `SleepDisabled` value from `pmset -g` and records it in `~/.config/caffeinator/power-recovery.json`. The journal is written atomically and synced before requesting `pmset -a disablesleep 1`. Neither activation nor cleanup edits the user's normal sleep timers.

Deactivation restores the recorded override first, verifies the value, removes the journal, and then releases the assertion. A canceled prompt or failed restoration retains state for an explicit retry. An interrupted session is detected from the journal on startup; the app displays restoration instead of claiming readiness. A malformed or unsupported journal fails closed without guessing a replacement setting.

AppleScript error -128 identifies cancellation. General exit status 1 is not treated as cancellation.

The app cannot restore a global setting during a crash or force-quit; the journal makes restoration possible on the next launch. Regular Quit requests complete cleanup first and leave the app running if cleanup fails. macOS shutdown or process termination may bypass that path.

## Preferences

`~/.config/caffeinator/caffeinator.sqlite3` is the native source of truth for preferences, session history, and sampled power telemetry. SQLite uses WAL mode, a five-second busy timeout, constrained values, and explicit schema migrations. On first launch after upgrading, the app imports a valid `settings.json` row transactionally and then attempts to remove the legacy file. The crash-recovery journal remains a separate synced JSON file because it must be durable before privileged system settings change.

Mode and duration selections are persisted through native commands. A successful activation also updates the defaults and opens a session-history row, including sessions started from the tray or Raycast. Successful stop and expiry transitions close that row with a reason. Startup reconciliation marks orphaned normal sessions interrupted while preserving a recoverable Server Mode row until restoration finishes.

## Raycast control channel

`control.rs` binds `~/.config/caffeinator/control.sock` with mode 0600. The single-instance plugin prevents competing copies of the app. Existing non-socket files and symlinks at the socket path are rejected.

Each connection carries one newline-delimited JSON request and one response:

```json
{"command":"start","mode":"NoIdleSleep","duration_secs":1800}
```

Supported commands are `status`, `start`, `stop`, `toggle`, `show`, and `preferences`. Start and preferences accept a mode and a duration in seconds (null means indefinite). Responses have `ok`, `status`, and `error`.

Requests are bounded to 8192 bytes, reads/writes have timeouts, and concurrent connections are bounded. No arbitrary shell command, filesystem path, TCP listener, or administrator credential is exposed by the protocol.

The Raycast client probes with a read-only status request. If the socket is missing or refuses connection, it can launch the configured app with `open -g -a` and wait for availability. Once a mutating request is sent, it is never replayed automatically after an uncertain response. The extension's status view refreshes every five seconds.

## Live power telemetry

The Power view polls `get_power_telemetry` every two seconds while visible, without overlapping requests. `telemetry.rs` reads the AppleSmartBattery IORegistry service as a plist. PowerTelemetryData's SystemLoad, BatteryPower, and SystemPowerIn values are converted from milliwatts to watts. The adapter's rated Watts value is displayed separately from measured input. Voltage/current are converted from millivolts/milliamps; signed and unsigned two's-complement discharge current are both supported.

Battery percentage, charging/full/plugged-in state, and time remaining come from macOS battery fields. Missing sensors are unavailable, never invented as zero. The system-draw graph retains up to 60 seconds of readings. Failed reads are marked stale and retried. This uses read-only sensors and does not require administrator authorization.

## Recorded power history

While the app runs, a native worker samples the same read-only sensors every 30 seconds. Samples are stored in fixed 30-second buckets, so opening the Power view does not increase database growth. Raw samples are retained for seven days. The history command aggregates them into roughly screen-sized buckets for the last hour, day, or week and returns average draw, peak draw, sample count, overlapping session time, and recent sessions.

The Power view keeps the two-second live instrument separate from this durable timeline. Range changes and 30-second refreshes query the Rust-owned database through Tauri; neither React nor Raycast opens SQLite directly. The browser preview supplies deterministic simulated history through the same response contract.

## Interface and verification

The webview is a 400 × 480 popover with a scrollable content region, fixed navigation, and fixed footer. It hides on focus loss. Reduced-motion settings suppress animations, controls have keyboard focus indicators, and active actions disable while native transitions are pending.

The browser preview is available only in Vite development when there is no Tauri bridge. It explicitly labels sessions as simulated; release bundles require the native bridge.

Rust tests exercise recovery, retained assertions, expiry, invalid durations, SQLite schema upgrades, settings import, telemetry aggregation, session lifecycle history, power-output parsing, and control-request validation. Frontend tests cover native/camel-case IPC normalization. Raycast transport tests cover fragmented replies, malformed/oversized responses, connection errors, and non-replay after an uncertain toggle. The native smoke-test script checks a real short IOKit session without requesting privileged Server Mode.
