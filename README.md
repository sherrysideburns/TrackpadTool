# TrackpadTool

A menu bar app for macOS that lets you choose what your trackpad gestures do: snap and switch windows like on Windows, switch tabs, copy and paste, take screenshots, open Mission Control and more. Keyboard shortcuts can run the same actions.

By SherrySideBurns. Every change is listed in [CHANGELOG.md](CHANGELOG.md).

## What it can do

- **Gestures:** three- and four-finger swipes and clicks, TipTap (rest one finger, tap another beside it), swipes in from the edge, clicks in a trackpad corner, and force press (Advanced mode).
- **Actions:** hide and restore all apps, a ⌘Tab-style app switcher, minimize, window snapping (halves, quarters, thirds, maximize, next display), tabs, Stage Manager, editing (copy, paste, undo, find…), media keys, screenshots, Mission Control, App Exposé, Show Desktop, Spaces, Spotlight, middle click, a keyboard shortcut of your choice or opening an app.
- **Per app:** give a gesture a different action in one app (Advanced mode).
- **Keyboard shortcuts:** run any action from anywhere, including Rectangle's window shortcuts with one click (Advanced mode).
- **Combos:** save your setup, or parts of it, as a `.tpt` file to share. Imported files are always shown for review before anything changes.

Simple by default: rarely used options only appear after switching on **Advanced mode** in Settings › General.

## Install

TrackpadTool needs macOS 13 Ventura or newer and a trackpad.

1. Download `TrackpadTool.zip` from the latest release, unzip it and drag **TrackpadTool** into your Applications folder.
2. Open it. The first time, macOS blocks it because it isn't from an Apple-verified developer. Go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.
3. The welcome window asks you to allow **Accessibility** (System Settings › Privacy & Security › Accessibility). TrackpadTool needs this to move windows, press shortcuts for you and notice clicks.
4. Choose how to start: the Windows-style setup, or empty to pick everything yourself.
5. If macOS uses the same gestures, both react. The Gestures page tells you which ones to switch off in System Settings › Trackpad.

## Privacy

TrackpadTool works entirely on your Mac and sends nothing anywhere. It reads finger positions on the trackpad, not what you type or what's on screen. Its error log (`~/Library/Logs/TrackpadTool`) only records errors, crashes and freezes, and stays on your Mac unless you share it. **Report a problem…** (Settings › General) shows you the whole report before you send it yourself, by email or as a GitHub issue; your name, your Mac's name and your home folder are taken out.

## Build it yourself

You need Apple's free Command Line Tools (`xcode-select --install`). Full Xcode isn't needed.

```
git clone https://github.com/sherrysideburns/TrackpadTool.git
cd TrackpadTool
./build.sh --run
```

The app is built at `build/TrackpadTool.app`. Optional: double-click `setup-signing.command` once to create a local signing certificate, so macOS keeps the Accessibility permission across rebuilds.

## How the code is organized

- `Models.swift`: gestures, modules, actions, settings
- `SettingsStore.swift`: saves settings to `~/Library/Application Support/TrackpadTool/settings.json`
- `Multitouch.swift`: reads fingers from the trackpad (private MultitouchSupport framework)
- `GestureRecognizer.swift`: turns finger movement into swipes, TipTaps and edge swipes
- `GestureEngine.swift`: connects gestures to actions; watches clicks, corner clicks, force press and scrolling
- `ActionRunner.swift`: runs actions (keys, media keys, Dock features, screenshots)
- `WindowSnapper.swift`, `WindowSwitcher.swift`: window snapping and the app switcher
- `HotKeys.swift`, `ShortcutsPane.swift`: global keyboard shortcuts
- `Profiles.swift`, `Combos.swift`, `ProfilesView.swift`: combos (.tpt files)
- `SettingsView.swift`, `MenuBarPanel.swift`, `Welcome.swift`: the settings window, the menu bar dropdown and the first-launch window
- `Log.swift`: error log, crash and freeze notes

Every change on GitHub is compiled automatically (see the Actions tab).

## Licence

All rights reserved. You may look at the code; please ask before reusing it.
