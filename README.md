<p align="center">
  <img src="src-tauri/icons/icon-readme.svg" alt="Caffeinator" width="128" height="128">
</p>

<h1 align="center">Caffeinator</h1>

<p align="center">A minimal macOS menu bar app to keep your Mac awake.</p>

<p align="center">
  <a href="https://github.com/tasnimzotder/caffeinator/releases/latest"><img src="https://img.shields.io/github/v/release/tasnimzotder/caffeinator" alt="Release"></a>
  <a href="https://github.com/tasnimzotder/caffeinator/actions/workflows/release.yml"><img src="https://github.com/tasnimzotder/caffeinator/actions/workflows/release.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2011%2B-lightgrey" alt="Platform">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
</p>

## Features

- **Sleep Prevention Modes** — Idle, Display, Lid Close, Network, or Background
- **Lid Close Prevention** — Keep your Mac awake even with the lid closed (requires admin password)
- **Timer Presets** — 30m, 1h, 2h, 4h, or indefinite
- **Custom Duration** — Set any hours + minutes combination
- **Circular Progress Ring** — Animated countdown with amber glow
- **Menu Bar Timer** — Remaining time displayed next to the tray icon
- **Quick Start from Tray** — Right-click the menu bar icon to start a session without opening the window
- **Click Outside to Close** — Window hides when it loses focus
- **Launch at Login** — Start automatically on login
- **Power Profile** — View current sleep settings and active system assertions

## Modes

| Mode | Mechanism | Behavior |
|------|-----------|----------|
| **Idle** | IOKit `PreventUserIdleSystemSleep` | Prevents idle system sleep. Display may still dim or turn off. |
| **Display** | IOKit `PreventUserIdleDisplaySleep` | Keeps display on and prevents idle sleep. |
| **Lid Close** | `pmset disablesleep` + IOKit | Prevents all sleep including lid close. Requires admin password. Use with caution. |
| **Network** | IOKit `NetworkClientActive` | Keeps system awake while serving network clients (file sharing, etc.). |
| **Background** | IOKit `BackgroundTask` | Keeps process running for background work. System may enter low power. |

> **Note:** Lid Close mode uses `sudo pmset -b disablesleep 1` which disables all system sleep. If the app is force-quit without deactivating, run `sudo pmset -b disablesleep 0` manually to restore normal sleep behavior.

## Installation

### Homebrew

```bash
brew install --cask tasnimzotder/tap/caffeinator
```

### Manual

1. Download the `.dmg` from [Releases](https://github.com/tasnimzotder/caffeinator/releases)
2. Drag `Caffeinator.app` to Applications
3. Run `xattr -cr /Applications/Caffeinator.app` to remove quarantine
4. Launch from Applications

## Build from Source

Requires [Bun](https://bun.sh) and [Rust](https://rustup.rs).

```bash
git clone https://github.com/tasnimzotder/caffeinator.git
cd caffeinator
bun install
make build      # Build .app
make install    # Install to /Applications
```

See `make help` for all available commands.

## Tech Stack

- **Backend** — Rust + [Tauri v2](https://v2.tauri.app) with direct IOKit FFI
- **Frontend** — React 19 + Tailwind CSS 4
- **Tooling** — Bun

## License

MIT
