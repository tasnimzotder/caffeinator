<p align="center"><img src="assets/icon-readme.svg" alt="Caffeinator" width="96" height="96"></p>
<h1 align="center">Caffeinator</h1>
<p align="center">A little extra uptime for your Mac.</p>

A native macOS menu-bar utility written in Swift, with SwiftUI screens and an AppKit popover. Choose a mode and duration, then start a session. Close the popover and Caffeinator keeps working.

## Features

- A compact 400 × 500 popover with Session, Power, History, and Settings screens.
- Live session countdown and menu-bar timer, independent of the popover.
- Remembered mode and duration shared with the Raycast extension.
- Presets, custom durations up to seven days, and indefinite sessions.
- Launch at login, keyboard shortcuts, right-click actions, and click-outside dismissal.
- Live measured system watts, adapter input, signed battery power, battery level, voltage/current, and charging estimates, where the hardware exposes them.
- Native Swift Charts for the seven-day power timeline, plus awake-session history.
- Current sleep preferences and active power assertions.
- Recoverable Server Mode with a durable journal of the original sleep override.

## Modes

| Mode | Behavior |
| --- | --- |
| Keep awake | Prevent idle system sleep; the display follows macOS settings. |
| Keep display on | Prevent idle display sleep using a macOS power assertion. |
| Server Mode | Prevent idle sleep and use an authorized global override to survive lid closure. |
| Network | Use the macOS NetworkClientActive assertion for network work. |
| Background | Use the macOS BackgroundTask assertion; macOS controls low-power behavior. |

Server Mode requires administrator authorization. The original global sleep override is synced to disk before changing it and restored when you stop. Normal sleep timers are never rewritten. Failed authorization or cleanup remains visible and retryable. After a crash, the app offers restoration on its next launch; it cannot restore a global setting while it is not running. A depleted battery still shuts the Mac down.

## Requirements and installation

The Swift version requires **macOS 13 or later**. The published 0.1.x releases use the previous Tauri implementation; this branch prepares the native 0.2.0 release.

```bash
brew install --cask tasnimzotder/tap/caffeinator
```

Or download a DMG from [Releases](https://github.com/tasnimzotder/caffeinator/releases) and drag Caffeinator to Applications.

Builds are ad-hoc signed. They are not Developer ID signed or notarized; downloaded builds may require explicit approval in macOS Privacy & Security.

## Build from source

Install Xcode or its Command Line Tools with Swift 5.9 or newer. Open `Package.swift` in Xcode, or use:

```bash
make test       # Swift core tests, with warnings treated as errors
make build      # Ad-hoc-signed dist/Caffeinator.app
make dev        # Build and open the native app
make dmg        # Build and verify a DMG in dist/
make install    # Copy to /Applications after quitting the existing app
```

Bun and Rust are not required to build the app. Bun is only used for the optional Raycast extension. `CAFFEINATOR_ARCH=x86_64 make build` builds an Intel app locally; the release workflow currently publishes Apple Silicon DMGs.

## Data compatibility

Settings, sessions, and power samples retain the existing SQLite schema at `~/.config/caffeinator/caffeinator.sqlite3`. Settings-only version 1 databases upgrade to version 2. Legacy `settings.json` is imported when no database preference row exists and kept as a rollback reference. Power samples are retained for seven days. The existing `power-recovery.json` journal is compatible with the Swift implementation.

Quit the previous Caffeinator process before launching the Swift build against your real data. A running control socket is never replaced. Tests and development previews can use `CAFFEINATOR_CONFIG_DIR=/path/to/disposable/folder` to isolate storage.

## Raycast

The extension in [extensions/raycast](extensions/raycast) provides **Start Session**, **Toggle Keep Awake**, **Stop Session**, **Session Status**, and **Open Caffeinator**. Its protocol and default `/Applications/Caffeinator.app` path are unchanged.

```bash
cd extensions/raycast
bun install --frozen-lockfile
bun run typecheck
bun test tests
bun run build
bun run dev
```

Or use Raycast’s **Import Extension** command. The extension is local and has not been published to the Raycast Store. Its user-only Unix socket listens at `~/.config/caffeinator/control.sock`; it opens no TCP port and handles no administrator credentials.

## Shortcuts and verification

- **⌘ Return** starts or stops from Session.
- **Escape** dismisses the popover.
- Left-click the tray icon to open; right-click for quick actions.

```bash
make test
make build
python3 tools/verify-native.py dist/Caffeinator.app/Contents/MacOS/caffeinator
```

The integration check uses temporary data, exercises four real IOKit assertion modes, start/stop/toggle/show, timed expiry, protocol validation, single-instance behavior, and preference/history persistence. It verifies configured power settings are unchanged. It does not invoke privileged Server Mode; its failure and recovery paths are tested with injected power controls.

See [docs/INTERNALS.md](docs/INTERNALS.md) for lifecycle details.

## License

MIT
