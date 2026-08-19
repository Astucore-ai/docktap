# Docktap

Windows-style click-to-minimize on the macOS Dock. An [Astucore](https://astucore.ai) app ([source](https://github.com/Astucore-ai/docktap)).

Click the Dock icon of the app that is already in front: its windows minimize. Click the same icon again: they come back. Click any other icon and the Dock behaves as usual.

## Install

Requires macOS 13+ on Apple silicon (the checked-in build script targets `arm64`).

```bash
git clone https://github.com/Astucore-ai/docktap.git
cd docktap
./scripts/build.sh
open /Applications/Docktap.app
```

Then enable **Docktap** in **System Settings → Privacy & Security → Accessibility**. If the click never fires, also enable it under **Input Monitoring**. macOS binds those permissions to the app’s signature — toggle them off and on if a rebuild stops working.

## Use

| Click | Result |
| --- | --- |
| Dock icon of the focused app (windows visible) | Minimize those windows |
| Same icon again | Restore (native Dock) |
| Any other app’s icon | Activate / launch as usual |
| ⌘ ⌥ ⌃ ⇧ + click | Passed through (hide, show others, menus) |
| Right-click / Control-click | Dock menu, unchanged |

The app lives in the menu bar. **Quit** is restarted by launchd on purpose. Use **Stop until next login** to actually unload it.

Default action is a real **minimize** (the yellow traffic light), not Hide, so the next Dock click restores the windows. Settings can switch to Hide, or minimize only the focused window instead of every visible one.

This Mac already has **Minimize windows into application icon** on, which matches the Windows taskbar.

## Persistence

`~/Library/LaunchAgents/com.astucore.docktap.plist`

- `RunAtLoad` — starts at login
- `KeepAlive` — relaunches if the process dies
- `AssociatedBundleIdentifiers` — so Accessibility applies to the LaunchAgent job

Config lives at `~/Library/Application Support/Docktap/config.json`. Status for debugging is `status.json` next to it. Logs: `~/Library/Logs/Docktap.log`.

## Development

```text
Sources/     AppKit menu-bar app, Dock AX cache, click monitor
Resources/   Info.plist, app icon
scripts/     build.sh, ensure-identity.sh, smoke-test.swift
```

`./scripts/build.sh [icon.png]` creates a local code-signing identity in `signing/` (gitignored) so Accessibility survives rebuilds.

```bash
swift scripts/smoke-test.swift
```

## License

MIT © Astucore
