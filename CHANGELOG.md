# Changelog

All notable changes to TrackpadTool, newest first.
Versions follow [semantic versioning](https://semver.org) from 1.0.0 on: 1.0.1 is a fix, 1.1.0 adds features.

## 0.12 — 2026-11-19
- **Welcome:** a welcome window on first launch explains what TrackpadTool does, walks you through the Accessibility permission, and lets you choose the Windows-style setup or start empty. Settings › General › About can show it again (without touching your setup).
- **Advanced mode:** Middle click is now a normal module and action; Force press (gestures, module and its settings on General) moved to Advanced mode. A force press you already use keeps working and stays visible.
- **About:** new About section on General with version, developer, a link to GitHub, the welcome screen and Quit.
- **Privacy:** the error log no longer records every gesture and force press; what you do is only kept in memory and appears in a crash or freeze note. Only errors, crashes and freezes are written to the file.
- **App ID:** TrackpadTool's ID is now `com.sherrysideburns.TrackpadTool` (and its `.tpt` file type ID too). After updating, allow Accessibility once more, and switch Open at login on again if you use it. Settings, combos and old `.tpt` files are unaffected.
- **Energy:** the status checks (Accessibility, Stage Manager) only run while a TrackpadTool window or the dropdown is open.
- **Combos:** using a combo that was placed straight into the Imported folder now also lists what to check first (apps it opens, keys it presses).
- **README:** rewritten for people installing the app: features, install steps, privacy, building it yourself.

## 0.11.2 — 2026-11-19
- **Screenshots, Spotlight, Spaces:** these actions use your own shortcut from System Settings › Keyboard › Keyboard Shortcuts (for example a changed “Copy area to clipboard”), not always the standard one. A switched-off screenshot shortcut is taken directly instead; for Spotlight and Spaces a note says it's switched off.
- **Force Quit, Spotlight:** ⌘, ⌥, ⌃ and ⇧ are now pressed as real keys around these shortcuts, because macOS checks that they're held down.

## 0.11.1 — 2026-11-19
- **General:** removed the action self-test again (it was only used to check 0.11).

## 0.11 — 2026-11-19
- **Keyboard layouts:** editing, tab and Lock Screen actions press the right key on AZERTY, QWERTZ and Dvorak (Select all no longer quits apps on AZERTY, Undo no longer closes windows).
- **Trackpads:** a trackpad connected after login (Bluetooth, desktop Macs) is picked up; two trackpads can't confuse the gesture reader; the trackpad list is checked every 10 s instead of every 2 s (less energy).
- **Swipes:** after a swipe, the next two-finger scroll is no longer swallowed.
- **Accessibility:** when Accessibility is allowed again after being taken away, clicks, force press and scroll holding work again without restarting.
- **Shortcuts:** shortcuts need ⌘, ⌥ or ⌃ (or an F-key) to work everywhere, so a plain key can't block typing; combos with such shortcuts are refused and the import review lists every keyboard shortcut; shortcuts are only re-registered when they change.
- **Screenshots:** Screenshot of a window starts in window mode directly, so a stray Space can't reach the front app.
- **App switcher:** jumping to the previous app no longer flashes the switcher.
- **Edit menu:** TrackpadTool's own Edit menu has Undo, Redo, Cut, Paste and Match Style, and Find.
- **Error log:** no more false “Not responding” lines after the Mac sleeps.
- **Combos:** import hardening: hidden zero-width characters refused, repeated shortcut ids renumbered, only ordinary files read.

## 0.10.1 — 2026-11-19
- **Three/four-finger swipes:** the page no longer scrolls before a swipe's action. Trackpad scrolling is held back while 3 or 4 fingers are down (only for finger counts that have a swipe set), until all fingers lift, including the momentum after. A scroll already under way is ended cleanly. A mouse wheel is never affected.

## 0.10 — 2026-11-19
- **Screenshots:** new module: area (moved from Editing), whole screen, a window, area or screen to the clipboard, and the screenshot & recording toolbar (⇧⌘5).
- **Mission Control and Spaces:** new module: Mission Control, App Exposé, Show Desktop and Launchpad / Apps (sent straight to the Dock, no shortcut needed), Space to the left/right (⌃← / ⌃→), Spotlight and Lock Screen.

## 0.9.1 — 2026-11-19
- **Settings:** Gesture settings (corners, force press, clashes with macOS) and Permissions moved onto the General page; both left the sidebar. Links on the Gestures page now point to General.
- **Shortcuts:** the Shortcuts page only shows in Advanced mode. Shortcuts you already set keep working when Advanced mode is off.

## 0.9 — 2026-11-19
- **Shortcuts:** new Shortcuts page (Rectangle clone): keyboard shortcuts that run any action from any app, each with an action menu like the Gestures page; one button adds Rectangle's window shortcuts (⌃⌥ arrows, U/I/J/K quarters, D/F/G thirds, E/T two-thirds, ↩ maximize, C center, ⌫ restore, ⌃⌥⌘→ next display); shortcuts taken by another app are flagged.
- **Actions:** window snapping: left, center and right third, left and right two-thirds; all snapping actions are now available in simple mode.
- **Shortcuts:** Advanced mode: gap between snapped windows (0–40 pt) and “When an app opens”, which snaps an app's first window into a chosen place each time it starts.
- **Actions:** more editing actions: Find, Find next, Save, New document, Delete word, Go to start/end of line, Go to top/bottom, Emoji & symbols, Screenshot of an area.
- **Combos:** keyboard shortcuts are a combo part (export, import, cheat sheet); the import review lists every gesture a per-app setup changes, e.g. “In Spotify · Three fingers · Swipe left → Next track”.

## 0.8 — 2026-11-19
- **Actions:** Editing module: Copy, Paste, Cut, Undo, Redo, Paste without formatting, Select all (Cut, Undo, Redo, Paste without formatting and Select all in Advanced mode).
- **Actions:** Media module: Play/Pause, Next track, Previous track, Volume up, Volume down, Mute, sent like the keyboard's media keys (next/previous track in Advanced mode).
- **Settings:** new Gesture settings page with corner sizes, force press strength and calibration, and clashes with macOS gestures; the Gestures page now only lists gestures, with one-line notes.
- **Settings:** the Stage Manager page only shows in Advanced mode (its options and Stage Manager gestures keep working).
- **Combos:** cleaner Combos page: Save as combo… and Import… with a ⋯ menu for the rest, tabs at the top, Ready-made split into complete setups and small combos, rows with Use and a ⋯ menu that fold open for details, and messages as a banner that fades.
- **Combos:** apps not on this Mac: the import review marks each app Installed or Not on this Mac and lets you untick it; setups for missing apps are kept and start working once the app is installed (shown as “waiting until installed”).

## 0.7.4 — 2026-11-19
- **Fix:** no more 6-second freezes: requests to other apps' windows give up after half a second, TrackpadTool never sends them to itself, and the app switcher no longer asks every app for its windows on each swipe.
- **Fix:** the click watcher runs on its own thread with its own copy of the settings, so clicks and drags never wait for TrackpadTool; if macOS pauses it anyway, a held click is dropped instead of getting stuck.
- **Fix:** Magic Mice are no longer read as trackpads; with two trackpads, each keeps its own fingers; a trackpad connected later is picked up within a few seconds; the trackpad reader's shared values are thread-safe.
- **Fix:** a thumb resting in a trackpad corner no longer turns an external-mouse click into a corner click; a light tap-and-drag no longer counts as a force press.
- **Security:** imported combos: shortcut labels are rebuilt from the actual keys (a file can't show ⌘C while pressing ⌘⌫); at most 256 KB is ever read; names, notes and version labels with hidden or text-direction characters are refused.
- **Error log:** crash notes only use crash-safe calls; the log rotates while running at 1 MB and no longer repeats the same warning every few seconds.
- **Fix:** using two combos within a second no longer overwrites a backup; one action an older version doesn't know drops only that gesture instead of resetting all settings.
- **Speed:** less work on the Combos page and import review per redraw, one shared status timer, reused date formats in the log, log notes written in the background, cheat sheets and the log open without waiting.

## 0.7.3 — 2026-11-18
- **Gestures:** force press calibration: Calibrate… opens a pad you force click three times; TrackpadTool measures the pressure at which your Mac gives its force-click buzz, and “Force needed: Match macOS” then runs the action together with that buzz.
- **Fix:** force press checks the pressure on every trackpad reading, so it reacts sooner; the unused pressure monitors are gone.

## 0.7.2 — 2026-11-18
- **Fix:** force press is read from the trackpad's own pressure data (macOS only sends force-click events to the app under the pointer). Pressing on to about 1.8× the pressure of your click, while still holding, is a force press.
- **Gestures:** “Force needed” (Light, Medium, Firm) sets how much harder than a normal click you have to press.
- **Error log:** the pressure of the first 30 clicks per session is logged, so the force press threshold can be tuned.

## 0.7.1 — 2026-11-18
- **Fix:** force press is caught three ways, whichever comes first; the log notes which way works on your Mac.
- **Settings:** force press is no longer hidden in the simple view.
- **Modules:** Three fingers and Four fingers are gesture modules: switch one off to hand all those gestures back to macOS.
- **Combos:** the cheat sheet explains what each action does.
- **App:** Settings › General names SherrySideBurns as the developer (also in the app's copyright line).
- **Error log:** the Combos page notes its actions in the log.

## 0.7 — 2026-11-18
- **App:** new icon: a white three-finger hand on a navy-to-azure gradient. The menu bar shows the same hand, following light and dark mode, dimmed while gestures are paused.
- **Combos:** Profiles are now Combos (page, tabs and buttons): Ready-made, My combos, Imported.
- **Combos:** save and export per part: click icon tiles (Three fingers, Four fingers, TipTap, Edge swipes, Corner clicks, Force press, Stage Manager, Per-app setups) to choose what goes in; a summary says what the combo holds and which modules it needs.
- **Combos:** import per part: the review shows the parts in the file, lists every gesture it changes and the modules it switches on, and lets you keep the rest of your setup or reset it to macOS default.
- **Combos:** using a combo replaces only the parts it holds; combo rows show part icons and what's inside.
- **Combos:** three small ready-made combos: Corner snapping, Snap on four fingers, Stage Manager flow.
- **Combos:** .tpt format version 2 records the parts in a file; older files still import as complete combos.

## 0.6.2 — 2026-11-18
- **Gestures:** corner clicks: new Tiny size, and an “All corners” picker that sets all four at once.
- **Error log:** being stopped by a rebuild, logout or Activity Monitor counts as quitting normally.

## 0.6.1 — 2026-11-18
- **Fix:** opening the Stage Manager page no longer freezes TrackpadTool.
- **Fix:** Stage Manager changes run in the background, and settings pages only redraw when something actually changed.
- **Error log:** new error log in ~/Library/Logs/TrackpadTool: errors, crashes, freezes longer than 4 seconds, and an unexpected end of the previous session. Settings › General › Error log: Open, Show in Finder, Copy, Clear.
- **Error log:** after an unexpected stop, the dropdown and the General page say so, with a Show log button.
- **Fix:** a settings file that can't be read is kept as a copy and logged, instead of being silently replaced.

## 0.6 — 2026-11-18
- **Settings:** Advanced mode (General page, off by default): the simple view leaves out rarely used actions and modules. Anything already set up keeps working and stays visible.
- **Menu bar:** calmer dropdown: shows only gestures that do something, with “Show all gestures” for the rest.
- **Menu bar:** action menus are grouped: macOS default and Do nothing on top, one submenu per module; actions that don't fit a gesture aren't offered.
- **Gestures:** corner clicks: set each trackpad corner to Off, Small, Medium or Large, with a drawing of the trackpad.
- **Stage Manager:** new Stage Manager page with its macOS options.
- **Stage Manager:** separate gesture setup while Stage Manager is on.
- **Profiles:** .tpt files also carry the Stage Manager gesture setup and corner sizes.

## 0.5.1 — 2026-11-18
- **Profiles:** importing a .tpt file no longer replaces your setup: after the review it is added to a new Imported tab.
- **Profiles:** the Profiles page has three tabs: Ready-made, My templates and Imported.
- **Profiles:** every profile has a Cheat sheet button; Show in Finder and Delete moved into a ⋯ menu.

## 0.5 — 2026-11-18
- **Switcher:** the window switcher is now a ⌘Tab-style app switcher, most recently used first.
- **Switcher:** switching brings the whole app forward, unhides it, and brings back a window if all were minimized; a quick swipe jumps to the previous app.
- **Profiles:** new Profiles page: four ready-made setups and your own templates.
- **Profiles:** export and import setups as .tpt files; double-clicking a .tpt opens a review before anything changes.
- **Security:** imported files are checked (size, format, known gestures and actions only); files never contain code or folder paths; a backup is made before every change, with Undo.
- **Profiles:** cheat sheet: a page listing what every gesture does.
- **Fix:** three- and four-finger clicks count again when fingers are placed at a relaxed pace.

## 0.4.1 — 2026-11-17
- **Fix:** click-and-drag works again while a multi-finger or corner click has an action.
- **Fix:** a three- or four-finger click only counts when those fingers land together.
- **Fix:** clicks ignore touch data older than 0.3 seconds.
- **Change:** multi-finger and corner click actions run when you let go, not when you press.

## 0.4 — 2026-11-17
- **Menu bar:** click the menu bar icon for a dropdown that lists every gesture and lets you change its action.
- **App:** lives in the menu bar only; the Dock icon is opt-in.
- **Actions:** Minimize window and Bring back minimized window.
- **Actions:** Maximize or restore window, and Maximize all windows.
- **Settings:** version number shown on the General page and in the dropdown.

## 0.3.1 — 2026-11-17
- **Setup:** setup-signing.command creates a “TrackpadTool Dev” signing certificate so the Accessibility permission survives rebuilds.

## 0.3 — 2026-11-17
- **Gestures:** new gesture types, each a module: TipTap left/right, two-finger edge swipes, one-finger corner clicks, force press actions.
- **Actions:** window snapping module: halves, quarters, maximize, center, restore size, move to next display.
- **Actions:** tabs module: next, previous, new, close, reopen tab.
- **Settings:** per-app gestures.
- **Fix:** gestures that need Accessibility show a reminder bubble instead of failing silently.
- **Fix:** the clash warning reads the built-in trackpad first and flags more clashes.

## 0.2.1 — 2026-11-17
- **Fix:** the clash warning no longer flags Mission Control or App Exposé when they're set to Off.
- **Look:** settings window back to the standard macOS look.

## 0.2 — 2026-11-17
- **Actions:** Stage Manager module: stage switcher, previous stage, Stage Manager on/off, recent apps strip on/off.
- **App:** app icon, optional Dock icon, confirmation bubble.

## 0.1.1 — 2026-11-17
- **Fix:** builds with Apple's Command Line Tools alone (no full Xcode needed).

## 0.1 — 2026-11-17
- First version: menu bar app with a dropdown per gesture: three/four-finger swipes and clicks, hide all apps and restore, window switcher, modules, shortcuts and open app, middle click.
