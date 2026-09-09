# Caffeinator for Raycast

Control the same native session from Raycast or the menu bar. Requires the updated Caffeinator app containing the local control service.

## Install locally

1. Build and install the Caffeinator app from the repository root with `make install`.
2. In this directory run `bun install` and `bun run build`.
3. Run Raycast's **Import Extension** command and select this directory. Alternatively, `bun run dev` starts development and imports the commands.
4. In extension preferences, leave **Launch Automatically** enabled. Set **Application Path** if the app lives somewhere other than `/Applications/Caffeinator.app`.

This is a local extension; it has not been published to the Raycast Store.

## Commands

- **Start Session**: choose a mode and preset/custom duration.
- **Toggle Keep Awake**: start the saved app defaults, or stop the current session.
- **Stop Session**: release the active assertion and restore any Server Mode override.
- **Session Status**: see mode, time remaining, busy state, and recovery errors. Refreshes every five seconds.
- **Open Caffeinator**: show the app window.

Server Mode uses the app's macOS authorization flow; the extension never reads or stores administrator credentials. If authorization is canceled, check status and retry restoration. Requests are not automatically replayed after a lost response.

## Development

`bun run build` validates and bundles the extension; `bun run typecheck` checks TypeScript. The transport uses a user-only Unix socket at `~/.config/caffeinator/control.sock`; no network port or shell command execution is exposed.
