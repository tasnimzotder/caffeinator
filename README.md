<p align="center">
  <img src="src-tauri/icons/icon-readme.svg" alt="Caffeinator" width="96" height="96">
</p>

<h1 align="center">Caffeinator</h1>
<p align="center">A little extra uptime for your Mac.</p>

A macOS menu-bar utility with a warm, dark popover. Choose a mode and duration, then start a session. Close the window and Caffeinator keeps working.

## Features

- A 400 × 480 popover with Session, Power, and Settings views.
- A live countdown and menu-bar timer, independent of the window.
- Remembered mode and duration across the app, menu bar, and Raycast.
- Presets, custom durations up to seven days, and indefinite sessions.
- Launch at login, keyboard shortcuts, and click-outside dismissal.
- Live system watts, battery charging/discharging power, adapter input, battery percentage, voltage/current, and charging estimates, plus a 60-second trace (where supported by macOS).
- Native sleep preferences and active power assertions.
- Recoverable Server Mode with explicit error handling and saved original settings.

## Modes

| Mode | What it does |
| --- | --- |
| Keep awake | Prevents idle system sleep; the display follows macOS settings. |
| Keep display on | Prevents idle display and system sleep. |
| Server Mode | Prevents idle sleep and uses a privileged global sleep override to survive lid closure. |
| Network | Uses the macOS NetworkClientActive assertion for network work. |
| Background | Uses the macOS BackgroundTask assertion; macOS controls low-power behavior. |

Server Mode requires administrator authorization to change the global sleep override. The original value is recorded before changing it and restored when you stop. Normal sleep timers are never rewritten. If authorization or cleanup fails, the session remains visible and retryable. If the app crashes, it offers restoration on the next launch; it cannot restore a global setting while it is not running.

A Mac still needs available power. Server Mode cannot keep a depleted battery running, and network/background assertions are subject to macOS policy.

## Installation

```bash
brew install --cask tasnimzotder/tap/caffeinator
```

For a manual installation, download the DMG from [Releases](https://github.com/tasnimzotder/caffeinator/releases), then drag Caffeinator to Applications.

## Build from source

Requires macOS, Bun, Rust, and Xcode Command Line Tools.

```bash
bun install
make build      # Build the app bundle
make install    # Build and copy to /Applications
```

`bun run dev` opens a development-only browser preview with clearly labeled simulated sessions. `make dev` runs the native Tauri app against the frontend dev server.

## Raycast

The local extension lives in [extensions/raycast](extensions/raycast). It provides:

- **Start Session** — choose a mode and preset/custom duration.
- **Toggle Keep Awake** — start your saved defaults or end the current session.
- **Stop Session** — stop and restore sleep settings.
- **Session Status** — inspect the active mode, remaining time, and recovery state.
- **Open Caffeinator** — show the popover.

After installing the updated app:

```bash
cd extensions/raycast
bun install
bun run build
bun run dev
```

Alternatively, run Raycast’s **Import Extension** command and choose that directory. Automatic background launch is enabled by default. The application path is configurable in extension preferences. This extension is local and has not been published to the Raycast Store.

Raycast communicates with the same native state machine over a user-only Unix socket. It does not use a network port or handle administrator credentials.

## Shortcuts

- **⌘ Return**: start or stop from the Session view.
- **Escape**: hide the window.
- Click the menu-bar icon to reopen; right-click for quick actions.

## Verification

```bash
bun run build
cd src-tauri
cargo test
cargo clippy --all-targets -- -D warnings
cd ../extensions/raycast
bun test
bun run build
bun run typecheck
```

For an explicit native smoke test, launch the updated app, ensure no session is active, and run `bun scripts/verify-native.ts` from the root. It creates a three-second idle assertion, verifies expiry and unchanged power preferences, and restores the saved app defaults.

See [docs/INTERNALS.md](docs/INTERNALS.md) for lifecycle and recovery details.

## License

MIT
