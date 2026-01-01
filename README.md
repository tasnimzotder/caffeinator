# Caffeinator

[![Version](https://img.shields.io/badge/version-0.0.1--alpha-blue)](https://github.com/tasnimzotder/caffeinator/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](https://github.com/tasnimzotder/caffeinator)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A modern, developer-friendly macOS menu bar app for keeping your Mac awake.

## Features

- **Quick Timer Presets** - 30m, 1h, 2h, 4h, or indefinite
- **Custom Duration** - Set any duration with hour/minute picker
- **Editable Presets** - Customize timer presets to your workflow
- **Developer Presets** - Quick actions for Docker, Xcode, npm, deployments, etc.
- **Process Watching** - Keep awake while a specific app is running
- **Multiple Modes** - Display, Idle, System, and Disk sleep prevention
- **Global Shortcut** - Toggle with `Cmd+Shift+C`
- **Menu Bar Timer** - See remaining time at a glance
- **Launch at Login** - Start automatically with your Mac
- **CLI Tool** - Command-line interface for terminal users

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

## Building from Source

```bash
# Clone the repository
git clone https://github.com/tasnimzotder/caffeinator.git
cd caffeinator

# Build debug version
make build

# Run the app
make run

# Build release version
make release

# Create DMG installer
make dmg
```

## Project Structure

```
Caffeinator/
├── CaffeinatorApp.swift      # App entry point
├── Models/                   # Data models
├── ViewModels/               # Business logic
├── Views/                    # SwiftUI views
├── Components/               # Reusable UI components
└── Utilities/                # Helpers and utilities
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [GitHub Repository](https://github.com/tasnimzotder/caffeinator)
- [Report Issues](https://github.com/tasnimzotder/caffeinator/issues)
