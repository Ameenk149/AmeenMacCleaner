# Ameen Mac Cleaner

A free, open-source Mac cleaner. See what's using your disk, uninstall apps along with the files they leave behind, and clear caches and other junk. No subscription, no telemetry, no upsells.

> 🤖 **Vibe-coded with AI.** Almost all of this app was written by AI (Claude) from plain-English prompts, then tested by a human on real Macs. It's a hobby project, not a commercial product. Read the [safety notes](#safety) before you delete anything, and keep a backup.

## Features

- **Storage Overview**: disk usage at a glance, plus an estimate of how much space you can free.
- **Space Explorer**: drill through folders sorted by size, with percentage bars. Folder sizes are cached, so moving between folders is fast.
- **App Uninstaller**: finds apps in `/Applications`, `~/Applications`, and anywhere Spotlight knows about (Downloads, external drives…). It shows each app's caches, preferences, containers, saved state and support files, and removes them with the app. You can uninstall several apps at once. Apps that are running are quit first.
- **Junk Cleanup**: one-click categories:
  - User caches and logs / crash reports
  - Xcode DerivedData, old device support files, Simulator caches, Archives
  - Developer caches (npm, pnpm, Gradle, `~/.cache`)
  - Mail attachments
  - Installer files (`.dmg`, `.pkg`, `.iso`, `.xip`) in Downloads
  - Trash
- **Leftovers**: files in `~/Library` that belong to apps you've already deleted. Nothing is selected by default, so you review them first.
- **Large Files**: finds big files in your home folder, showing when each was last modified and last opened.

## Safety

- **Trash by default.** Everything except items already in the Trash can go to the Trash, so you can restore it. "Delete Permanently" is a separate option.
- **Protected paths.** The remover refuses to delete system locations (`/System`, `/usr`, `/Library`…), your home folder, or top-level folders like `~/Library`, `~/Documents` and `~/Library/Caches`. It only deletes things inside them.
- **Apple apps protected by SIP** are marked and can't be removed.
- **Admin prompt only when needed.** If a file is owned by root, macOS asks for your password. The app never stores your password.
- **No network access.** Nothing leaves your Mac.

Even so, this is AI-written software that deletes files. Look at what's selected before you confirm, and keep Time Machine (or another backup) running.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon or Intel
- To build from source: Xcode 15+ or the Swift 5.9+ toolchain

## Install

### Download

Get the latest `.dmg` from [Releases](https://github.com/Ameenk149/AmeenMacCleaner/releases) and drag the app to Applications.

The builds aren't notarized. The first time you open the app, macOS will block it. Open it anyway from **System Settings → Privacy & Security** ("Open Anyway"), or run:

```bash
xattr -dr com.apple.quarantine "/Applications/Ameen Mac Cleaner.app"
```

### Build from source

```bash
git clone https://github.com/Ameenk149/AmeenMacCleaner.git
```

```bash
cd AmeenMacCleaner && ./build.sh
```

```bash
open "build/Ameen Mac Cleaner.app"
```

To make a universal DMG for sharing:

```bash
./make_dmg.sh
```

To sign and notarize the DMG with your own Developer ID, set `DEVELOPER_ID` and `NOTARY_PROFILE`. The header of [make_dmg.sh](make_dmg.sh) explains how.

For development, `swift run` also works, but the app runs without its bundle and icon.

## Full Disk Access

Without Full Disk Access, macOS hides some folders (Mail, some containers, other apps' data), so scans can miss things. For complete results, add the app under **System Settings → Privacy & Security → Full Disk Access**. The app links to that page if a removal fails.

## Project structure

```
Package.swift                 Swift package (SwiftUI, macOS 14+)
Sources/AmeenMacCleaner/
  AmeenMacCleanerApp.swift    App entry point
  AppState.swift              Shared state and scan orchestration
  Scanners.swift              App, Library, leftover, junk and large-file scanners
  Explorer.swift              Space Explorer with folder-size cache
  Remover.swift               Trash / permanent delete with safety checks
  Models.swift                Data types and junk categories
  Utilities.swift             Paths, sizes, permissions helpers
  Views/                      SwiftUI screens
Resources/Info.plist          App bundle metadata
Scripts/make_icon.swift       Generates the app icon
build.sh / make_dmg.sh        Build the .app / a shareable .dmg
```

## Contributing

Issues and pull requests are welcome, whether they're written by hand or vibe-coded. Please:

- Test any change that deletes files on a real Mac (ideally a spare user account or VM).
- Keep deletion behavior conservative. A new junk category that might hold user data should be off by default (`defaultSelected: false` in `Models.swift`).
- Describe what you tested in the PR.

## License

[MIT](LICENSE). Use it, fork it, ship it. No warranty: you're responsible for what you delete.
