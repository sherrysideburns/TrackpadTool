# TrackpadTool

A menu bar app that lets you choose what trackpad gestures do, with Windows-style window control.

## Build and run

In Terminal:

```
cd TrackpadTool
./build.sh --run
```

This needs Apple's free Command Line Tools (`xcode-select --install` if the script asks). The app is built at `build/TrackpadTool.app`. You can move it to Applications.

## First launch

1. Allow **Accessibility** when asked (System Settings › Privacy & Security › Accessibility).
2. Turn off the macOS gestures that clash (the Gestures page tells you which):
   - System Settings › Trackpad › More Gestures: set "Mission Control", "App Exposé" and "Swipe between full-screen applications" to four fingers or off.
   - If three-finger drag is on (Accessibility › Pointer Control › Trackpad Options), turn it off.

## Starting setup

| Gesture | Action |
|---|---|
| 3 fingers down | Hide all apps (⌘H in every app at once) |
| 3 fingers up | Restore the hidden apps |
| 3 fingers left / right | Window switcher: keep fingers down and swipe to move, lift to switch |
| Force press | Untouched (Look Up keeps working) |

Stage Manager (four fingers, added only where those swipes were still free):

| Gesture | Action |
|---|---|
| 4 fingers left / right | Stage switcher: one tile per app/stage, lift to switch |
| 4 fingers up | Turn Stage Manager on/off |
| 4 fingers down | Show/hide the recent apps strip |

More gesture types (each a module you can switch off):

| Gesture | Starts as |
|---|---|
| TipTap left / right (rest one finger, tap another beside it) | Previous / next tab |
| Two-finger swipe in from an edge | macOS default |
| One-finger click in a corner | macOS default |
| Force press | macOS default (Look Up) |

Per-app gestures: on the Gestures page, pick an app under "Gestures for" to give gestures a different action there.

Every change is listed in [CHANGELOG.md](CHANGELOG.md).

## How it's organized

- `Models.swift`: gestures, modules, actions, settings
- `SettingsStore.swift`: saves settings to `~/Library/Application Support/TrackpadTool/settings.json`
- `Multitouch.swift`: reads fingers from the trackpad (private MultitouchSupport framework)
- `GestureRecognizer.swift`: turns finger movement into swipes, TipTaps and edge swipes
- `GestureEngine.swift`: connects gestures to actions (per app); watches clicks, corner clicks and force press
- `ActionRunner.swift`: hide/restore, minimize, tabs, shortcuts, open app, middle click
- `WindowSnapper.swift`: window snapping (halves, quarters, maximize, center, restore, next display)
- `WindowSwitcher.swift`: the Alt+Tab-style popup
- `SettingsView.swift`: the settings window (Gestures, Modules, Permissions, General)
- `GlassStyle.swift`: the small confirmation bubble (e.g. "Stage Manager on")
- `StageManager.swift`: turns Stage Manager and its recent apps strip on/off
- `tools/make_icon.py`: renders `Resources/AppIcon.icns` (needs Python with Pillow and NumPy)

To add a module: add a case to `ModuleID`, its actions to `ActionKind` (with `module` pointing at it), and handle them in `ActionRunner.run`.

## Good to know

- After rebuilding, macOS may treat the app as new. If gestures stop working, remove TrackpadTool from the Accessibility list and add it again.
- The app reads the trackpad only while at least one gesture is set to something other than "macOS default".
