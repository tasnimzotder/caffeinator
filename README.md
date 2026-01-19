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

- **Timer Presets** - 30m, 1h, 2h, 4h, or indefinite
- **Custom Duration** - Set any duration
- **Sleep Modes** - Idle, Display, or System sleep prevention
- **Menu Bar Timer** - See remaining time in the menu bar
- **Launch at Login** - Start automatically

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

## License

MIT
