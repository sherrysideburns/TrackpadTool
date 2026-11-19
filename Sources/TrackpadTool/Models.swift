import AppKit
import CoreGraphics

// MARK: - Gestures

/// Sections of the Gestures page. Some belong to a module and only show
/// (and only listen) while that module is on.
enum GestureGroup: String, CaseIterable, Identifiable {
    case threeFingers, fourFingers, tipTap, edgeSwipes, cornerClicks, forcePress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeFingers: return "Three fingers"
        case .fourFingers: return "Four fingers"
        case .tipTap: return "TipTap"
        case .edgeSwipes: return "Edge swipes"
        case .cornerClicks: return "Corner clicks"
        case .forcePress: return "Force press"
        }
    }

    var hint: String? {
        switch self {
        case .threeFingers, .fourFingers: return nil
        case .tipTap: return "Rest one finger on the trackpad, then tap a second finger to its left or right."
        case .edgeSwipes: return "Put two fingers right at the edge of the trackpad and swipe inward."
        case .cornerClicks: return "Click with one finger in a corner of the trackpad."
        case .forcePress: return "Press with one finger until you feel a second, deeper click."
        }
    }

    /// The module that switches this kind of gesture on.
    var module: ModuleID? {
        switch self {
        case .threeFingers: return .threeFingers
        case .fourFingers: return .fourFingers
        case .tipTap: return .tipTap
        case .edgeSwipes: return .edgeSwipes
        case .cornerClicks: return .cornerClicks
        case .forcePress: return .forcePress
        }
    }

    var gestures: [Gesture] { Gesture.allCases.filter { $0.group == self } }

    /// Only shown in Advanced mode, unless one of its gestures is in use.
    var isAdvanced: Bool { self == .edgeSwipes }
}

// MARK: - Trackpad corners

enum Corner: String, CaseIterable, Identifiable, Codable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }

    var gesture: Gesture {
        switch self {
        case .topLeft: return .cornerTopLeft
        case .topRight: return .cornerTopRight
        case .bottomLeft: return .cornerBottomLeft
        case .bottomRight: return .cornerBottomRight
        }
    }

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

/// How much of the trackpad counts as a corner. Off = clicks there are
/// always normal clicks.
enum CornerSize: String, CaseIterable, Identifiable, Codable {
    case off, tiny, small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .tiny: return "Tiny"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Share of the trackpad's width and height that belongs to the corner.
    /// The trackpad is wider than tall, so the height share is larger.
    var width: Float {
        switch self {
        case .off: return 0
        case .tiny: return 0.08
        case .small: return 0.14
        case .medium: return 0.22
        case .large: return 0.30
        }
    }

    var height: Float {
        switch self {
        case .off: return 0
        case .tiny: return 0.12
        case .small: return 0.20
        case .medium: return 0.28
        case .large: return 0.38
        }
    }
}

/// Every gesture the app can recognise. The raw value is the key in the
/// settings file (the multi-finger keys match older versions).
enum Gesture: String, CaseIterable, Identifiable {
    case threeSwipeDown = "3-swipeDown", threeSwipeUp = "3-swipeUp"
    case threeSwipeLeft = "3-swipeLeft", threeSwipeRight = "3-swipeRight", threeClick = "3-click"
    case fourSwipeDown = "4-swipeDown", fourSwipeUp = "4-swipeUp"
    case fourSwipeLeft = "4-swipeLeft", fourSwipeRight = "4-swipeRight", fourClick = "4-click"
    case tipTapLeft = "tiptap-left", tipTapRight = "tiptap-right"
    case edgeLeft = "edge-left", edgeRight = "edge-right", edgeTop = "edge-top", edgeBottom = "edge-bottom"
    case cornerTopLeft = "corner-topLeft", cornerTopRight = "corner-topRight"
    case cornerBottomLeft = "corner-bottomLeft", cornerBottomRight = "corner-bottomRight"
    case forcePress = "force-press"

    var id: String { rawValue }
    var key: String { rawValue }

    var group: GestureGroup {
        switch self {
        case .threeSwipeDown, .threeSwipeUp, .threeSwipeLeft, .threeSwipeRight, .threeClick: return .threeFingers
        case .fourSwipeDown, .fourSwipeUp, .fourSwipeLeft, .fourSwipeRight, .fourClick: return .fourFingers
        case .tipTapLeft, .tipTapRight: return .tipTap
        case .edgeLeft, .edgeRight, .edgeTop, .edgeBottom: return .edgeSwipes
        case .cornerTopLeft, .cornerTopRight, .cornerBottomLeft, .cornerBottomRight: return .cornerClicks
        case .forcePress: return .forcePress
        }
    }

    var title: String {
        switch self {
        case .threeSwipeDown, .fourSwipeDown: return "Swipe down"
        case .threeSwipeUp, .fourSwipeUp: return "Swipe up"
        case .threeSwipeLeft, .fourSwipeLeft: return "Swipe left"
        case .threeSwipeRight, .fourSwipeRight: return "Swipe right"
        case .threeClick, .fourClick: return "Click"
        case .tipTapLeft: return "TipTap left"
        case .tipTapRight: return "TipTap right"
        case .edgeLeft: return "From the left edge"
        case .edgeRight: return "From the right edge"
        case .edgeTop: return "From the top edge"
        case .edgeBottom: return "From the bottom edge"
        case .cornerTopLeft: return "Top-left corner"
        case .cornerTopRight: return "Top-right corner"
        case .cornerBottomLeft: return "Bottom-left corner"
        case .cornerBottomRight: return "Bottom-right corner"
        case .forcePress: return "Force press"
        }
    }

    var symbol: String {
        switch self {
        case .threeSwipeDown, .fourSwipeDown: return "arrow.down"
        case .threeSwipeUp, .fourSwipeUp: return "arrow.up"
        case .threeSwipeLeft, .fourSwipeLeft: return "arrow.left"
        case .threeSwipeRight, .fourSwipeRight: return "arrow.right"
        case .threeClick, .fourClick: return "cursorarrow.click"
        case .tipTapLeft: return "arrow.left.circle"
        case .tipTapRight: return "arrow.right.circle"
        case .edgeLeft: return "arrow.right.to.line"
        case .edgeRight: return "arrow.left.to.line"
        case .edgeTop: return "arrow.down.to.line"
        case .edgeBottom: return "arrow.up.to.line"
        case .cornerTopLeft: return "arrow.up.left.square"
        case .cornerTopRight: return "arrow.up.right.square"
        case .cornerBottomLeft: return "arrow.down.left.square"
        case .cornerBottomRight: return "arrow.down.right.square"
        case .forcePress: return "hand.tap"
        }
    }

    /// Recognised from a physical click (needs the click watcher).
    var isClick: Bool {
        switch self {
        case .threeClick, .fourClick, .cornerTopLeft, .cornerTopRight, .cornerBottomLeft, .cornerBottomRight: return true
        default: return false
        }
    }

    /// Three/four-finger swipes, which can keep a switcher open while you browse.
    var isMultiFingerSwipe: Bool {
        switch group {
        case .threeFingers, .fourFingers: return self != .threeClick && self != .fourClick
        default: return false
        }
    }

    /// -1 for leftward gestures, +1 otherwise (where a switcher starts moving).
    var direction: Int {
        switch self {
        case .threeSwipeLeft, .fourSwipeLeft, .tipTapLeft, .edgeRight: return -1
        default: return 1
        }
    }

    static func swipe(fingers: Int, dx: Float, dy: Float, horizontal: Bool) -> Gesture? {
        switch (fingers, horizontal) {
        case (3, true): return dx > 0 ? .threeSwipeRight : .threeSwipeLeft
        case (3, false): return dy > 0 ? .threeSwipeUp : .threeSwipeDown
        case (4, true): return dx > 0 ? .fourSwipeRight : .fourSwipeLeft
        case (4, false): return dy > 0 ? .fourSwipeUp : .fourSwipeDown
        default: return nil
        }
    }
}

// MARK: - Modules

/// A module is a feature you can switch on or off.
enum ModuleKind: String, CaseIterable {
    case actions, gestures, features

    var title: String {
        switch self {
        case .actions: return "Actions"
        case .gestures: return "Gesture types"
        case .features: return "Features"
        }
    }

    var hint: String {
        switch self {
        case .actions: return "Add actions to every gesture dropdown."
        case .gestures: return "Add new kinds of gestures to the Gestures page."
        case .features: return "Change how gestures work."
        }
    }
}

enum ModuleID: String, Codable, CaseIterable, Identifiable {
    case windowControl
    case windowSnapping
    case tabs
    case stageManager
    case shortcutsAndApps
    case editing
    case media
    case screenshots
    case macControls
    case middleClick
    case threeFingers
    case fourFingers
    case tipTap
    case edgeSwipes
    case cornerClicks
    case forcePress
    case perAppGestures

    var id: String { rawValue }

    var kind: ModuleKind {
        switch self {
        case .windowControl, .windowSnapping, .tabs, .stageManager, .shortcutsAndApps, .editing, .media, .screenshots,
             .macControls, .middleClick: return .actions
        case .threeFingers, .fourFingers, .tipTap, .edgeSwipes, .cornerClicks, .forcePress: return .gestures
        case .perAppGestures: return .features
        }
    }

    var title: String {
        switch self {
        case .windowControl: return "Window control"
        case .windowSnapping: return "Window snapping"
        case .tabs: return "Tabs"
        case .stageManager: return "Stage Manager"
        case .shortcutsAndApps: return "Shortcuts and apps"
        case .editing: return "Editing"
        case .media: return "Media"
        case .screenshots: return "Screenshots"
        case .macControls: return "Mission Control and Spaces"
        case .middleClick: return "Middle click"
        case .threeFingers: return "Three fingers"
        case .fourFingers: return "Four fingers"
        case .tipTap: return "TipTap"
        case .edgeSwipes: return "Edge swipes"
        case .cornerClicks: return "Corner clicks"
        case .forcePress: return "Force press"
        case .perAppGestures: return "Per-app gestures"
        }
    }

    var summary: String {
        switch self {
        case .windowControl: return "Hide everything, bring it back, switch apps like ⌘Tab, and minimize windows."
        case .windowSnapping: return "Snap the front window to a half, a quarter or the full screen, like Windows Snap, or maximize every window."
        case .tabs: return "Next, previous, new, close and reopen tabs in browsers, Finder and most apps."
        case .stageManager: return "Turn Stage Manager on or off, flip between stages, and show or hide the recent apps strip."
        case .shortcutsAndApps: return "Run any keyboard shortcut, open an app, or bring up Force Quit."
        case .editing: return "Copy, paste, undo, find, save, jump through text and emoji, in any app."
        case .media: return "Play or pause, skip tracks and change the volume, like the media keys on your keyboard."
        case .screenshots: return "Capture an area, a window or the whole screen, to a file or the clipboard, or open the screenshot toolbar."
        case .macControls: return "Mission Control, App Exposé, Show Desktop, Launchpad, Spotlight, Lock Screen, and moving between Spaces."
        case .middleClick: return "Adds a middle-click action, handy for opening links in new tabs."
        case .threeFingers: return "Swipe or click with three fingers. Off hands every three-finger gesture back to macOS."
        case .fourFingers: return "Swipe or click with four fingers. Off hands every four-finger gesture back to macOS."
        case .tipTap: return "Rest one finger and tap another beside it. Starts set to previous/next tab."
        case .edgeSwipes: return "Swipe two fingers in from an edge of the trackpad."
        case .cornerClicks: return "Click in one of the four corners of the trackpad."
        case .forcePress: return "Give a force press its own action. Until you pick one, Look Up keeps working."
        case .perAppGestures: return "Give any gesture a different action in specific apps."
        }
    }

    var symbol: String {
        switch self {
        case .windowControl: return "rectangle.on.rectangle"
        case .windowSnapping: return "rectangle.split.2x1"
        case .tabs: return "square.on.square"
        case .stageManager: return "squares.leading.rectangle"
        case .shortcutsAndApps: return "keyboard"
        case .editing: return "doc.on.clipboard"
        case .media: return "playpause"
        case .screenshots: return "camera.viewfinder"
        case .macControls: return "rectangle.3.group"
        case .middleClick: return "computermouse"
        case .threeFingers: return "3.square"
        case .fourFingers: return "4.square"
        case .tipTap: return "hand.tap"
        case .edgeSwipes: return "rectangle.portrait.and.arrow.right"
        case .cornerClicks: return "square.dashed"
        case .forcePress: return "hand.point.up.braille"
        case .perAppGestures: return "app.badge"
        }
    }

    var defaultOn: Bool { self != .middleClick }

    /// Hidden on the Modules page unless Advanced mode is on.
    var isAdvanced: Bool {
        switch self {
        case .middleClick, .edgeSwipes, .perAppGestures, .shortcutsAndApps: return true
        default: return false
        }
    }

    var actions: [ActionKind] {
        ActionKind.allCases.filter { $0.module == self }
    }
}

// MARK: - Actions

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case macDefault
    case doNothing
    // Window control
    case hideAllApps
    case restoreHiddenApps
    case windowSwitcher
    case minimizeWindow
    case restoreMinimizedWindow
    case minimizeAllWindows
    // Window snapping
    case snapLeft, snapRight, snapTop, snapBottom
    case snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight
    case snapLeftThird, snapCenterThird, snapRightThird, snapLeftTwoThirds, snapRightTwoThirds
    case maximizeWindow, toggleMaximizeWindow, maximizeAllWindows
    case centerWindow, restoreWindowSize, moveToNextDisplay
    // Tabs
    case nextTab, previousTab, newTab, closeTab, reopenTab
    // Stage Manager
    case stageSwitcher
    case previousStage
    case toggleStageManager
    case toggleStageStrip
    // Shortcuts and apps
    case keyboardShortcut
    case openApp
    case forceQuit
    // Middle click
    case middleClick
    // Editing (added in 0.8)
    case copy, paste, cut, undo, redo, pasteWithoutFormatting, selectAll
    // More editing (added in 0.9)
    case find, findNext, save, newDocument, deleteWord
    case lineStart, lineEnd, documentStart, documentEnd, emojiPicker, screenshotArea
    // Media (added in 0.8)
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    // Screenshots (added in 0.10; screenshotArea above moved here)
    case screenshotScreen, screenshotWindow, screenshotAreaToClipboard, screenshotScreenToClipboard, screenshotToolbar
    // Mission Control and Spaces (added in 0.10)
    case missionControl, appExpose, showDesktop, launchpad, previousSpace, nextSpace, spotlight, lockScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macDefault: return "macOS default"
        case .doNothing: return "Do nothing"
        case .hideAllApps: return "Hide all apps"
        case .restoreHiddenApps: return "Restore hidden apps"
        case .windowSwitcher: return "App switcher (⌘Tab)"
        case .minimizeWindow: return "Minimize window"
        case .restoreMinimizedWindow: return "Bring back minimized window"
        case .minimizeAllWindows: return "Minimize all windows"
        case .snapLeft: return "Snap left half"
        case .snapRight: return "Snap right half"
        case .snapTop: return "Snap top half"
        case .snapBottom: return "Snap bottom half"
        case .snapTopLeft: return "Snap top-left quarter"
        case .snapTopRight: return "Snap top-right quarter"
        case .snapBottomLeft: return "Snap bottom-left quarter"
        case .snapBottomRight: return "Snap bottom-right quarter"
        case .snapLeftThird: return "Snap left third"
        case .snapCenterThird: return "Snap center third"
        case .snapRightThird: return "Snap right third"
        case .snapLeftTwoThirds: return "Snap left two-thirds"
        case .snapRightTwoThirds: return "Snap right two-thirds"
        case .maximizeWindow: return "Maximize window"
        case .toggleMaximizeWindow: return "Maximize or restore window"
        case .maximizeAllWindows: return "Maximize all windows"
        case .centerWindow: return "Center window"
        case .restoreWindowSize: return "Restore window size"
        case .moveToNextDisplay: return "Move to next display"
        case .nextTab: return "Next tab"
        case .previousTab: return "Previous tab"
        case .newTab: return "New tab"
        case .closeTab: return "Close tab"
        case .reopenTab: return "Reopen closed tab"
        case .stageSwitcher: return "Stage switcher"
        case .previousStage: return "Previous stage"
        case .toggleStageManager: return "Turn Stage Manager on/off"
        case .toggleStageStrip: return "Show/hide recent apps strip"
        case .keyboardShortcut: return "Keyboard shortcut…"
        case .openApp: return "Open app…"
        case .forceQuit: return "Force Quit window"
        case .middleClick: return "Middle click"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .cut: return "Cut"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .pasteWithoutFormatting: return "Paste without formatting"
        case .selectAll: return "Select all"
        case .find: return "Find"
        case .findNext: return "Find next"
        case .save: return "Save"
        case .newDocument: return "New document or window"
        case .deleteWord: return "Delete word"
        case .lineStart: return "Go to start of line"
        case .lineEnd: return "Go to end of line"
        case .documentStart: return "Go to top"
        case .documentEnd: return "Go to bottom"
        case .emojiPicker: return "Emoji & symbols"
        case .screenshotArea: return "Screenshot of an area"
        case .playPause: return "Play/Pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .screenshotScreen: return "Screenshot of the whole screen"
        case .screenshotWindow: return "Screenshot of a window"
        case .screenshotAreaToClipboard: return "Copy an area to the clipboard"
        case .screenshotScreenToClipboard: return "Copy the whole screen to the clipboard"
        case .screenshotToolbar: return "Screenshot & recording toolbar"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé (this app's windows)"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad / Apps"
        case .previousSpace: return "Space to the left"
        case .nextSpace: return "Space to the right"
        case .spotlight: return "Spotlight"
        case .lockScreen: return "Lock Screen"
        }
    }

    /// The key combination an editing or tab action presses.
    var keys: (code: UInt16, flags: CGEventFlags)? {
        switch self {
        case .nextTab: return (30, [.maskCommand, .maskShift])          // ⌘⇧]
        case .previousTab: return (33, [.maskCommand, .maskShift])      // ⌘⇧[
        case .newTab: return (17, .maskCommand)                         // ⌘T
        case .closeTab: return (13, .maskCommand)                       // ⌘W
        case .reopenTab: return (17, [.maskCommand, .maskShift])        // ⌘⇧T
        case .copy: return (8, .maskCommand)                            // ⌘C
        case .paste: return (9, .maskCommand)                           // ⌘V
        case .cut: return (7, .maskCommand)                             // ⌘X
        case .undo: return (6, .maskCommand)                            // ⌘Z
        case .redo: return (6, [.maskCommand, .maskShift])              // ⇧⌘Z
        case .pasteWithoutFormatting: return (9, [.maskCommand, .maskShift, .maskAlternate])   // ⌥⇧⌘V
        case .selectAll: return (0, .maskCommand)                       // ⌘A
        case .find: return (3, .maskCommand)                            // ⌘F
        case .findNext: return (5, .maskCommand)                        // ⌘G
        case .save: return (1, .maskCommand)                            // ⌘S
        case .newDocument: return (45, .maskCommand)                    // ⌘N
        case .deleteWord: return (51, .maskAlternate)                   // ⌥⌫
        case .lineStart: return (123, .maskCommand)                     // ⌘←
        case .lineEnd: return (124, .maskCommand)                       // ⌘→
        case .documentStart: return (126, .maskCommand)                 // ⌘↑
        case .documentEnd: return (125, .maskCommand)                   // ⌘↓
        case .emojiPicker: return (49, [.maskControl, .maskCommand])    // ⌃⌘Space
        case .screenshotArea: return (21, [.maskCommand, .maskShift])   // ⇧⌘4
        case .screenshotWindow: return (21, [.maskCommand, .maskShift]) // ⇧⌘4, then Space
        case .screenshotScreen: return (20, [.maskCommand, .maskShift]) // ⇧⌘3
        case .screenshotAreaToClipboard: return (21, [.maskCommand, .maskShift, .maskControl])    // ⌃⇧⌘4
        case .screenshotScreenToClipboard: return (20, [.maskCommand, .maskShift, .maskControl])  // ⌃⇧⌘3
        case .screenshotToolbar: return (23, [.maskCommand, .maskShift]) // ⇧⌘5
        case .previousSpace: return (123, [.maskControl, .maskSecondaryFn, .maskNumericPad])   // ⌃←
        case .nextSpace: return (124, [.maskControl, .maskSecondaryFn, .maskNumericPad])       // ⌃→
        case .spotlight: return (49, .maskCommand)                      // ⌘Space
        case .lockScreen: return (12, [.maskControl, .maskCommand])     // ⌃⌘Q
        default: return nil
        }
    }

    /// The media key an action presses (NX_KEYTYPE_* values).
    var mediaKey: Int32? {
        switch self {
        case .volumeUp: return 0         // NX_KEYTYPE_SOUND_UP
        case .volumeDown: return 1       // NX_KEYTYPE_SOUND_DOWN
        case .mute: return 7             // NX_KEYTYPE_MUTE
        case .playPause: return 16       // NX_KEYTYPE_PLAY
        case .nextTrack: return 19       // NX_KEYTYPE_FAST (what the keyboard's ⏭ sends)
        case .previousTrack: return 20   // NX_KEYTYPE_REWIND (what the keyboard's ⏮ sends)
        default: return nil
        }
    }

    var module: ModuleID? {
        switch self {
        case .macDefault, .doNothing: return nil
        case .hideAllApps, .restoreHiddenApps, .windowSwitcher, .minimizeWindow, .restoreMinimizedWindow,
             .minimizeAllWindows: return .windowControl
        case .snapLeft, .snapRight, .snapTop, .snapBottom, .snapTopLeft, .snapTopRight, .snapBottomLeft,
             .snapBottomRight, .snapLeftThird, .snapCenterThird, .snapRightThird, .snapLeftTwoThirds,
             .snapRightTwoThirds, .maximizeWindow, .toggleMaximizeWindow, .maximizeAllWindows, .centerWindow,
             .restoreWindowSize, .moveToNextDisplay: return .windowSnapping
        case .nextTab, .previousTab, .newTab, .closeTab, .reopenTab: return .tabs
        case .stageSwitcher, .previousStage, .toggleStageManager, .toggleStageStrip: return .stageManager
        case .keyboardShortcut, .openApp, .forceQuit: return .shortcutsAndApps
        case .middleClick: return .middleClick
        case .copy, .paste, .cut, .undo, .redo, .pasteWithoutFormatting, .selectAll,
             .find, .findNext, .save, .newDocument, .deleteWord, .lineStart, .lineEnd,
             .documentStart, .documentEnd, .emojiPicker: return .editing
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute: return .media
        case .screenshotArea, .screenshotScreen, .screenshotWindow, .screenshotAreaToClipboard,
             .screenshotScreenToClipboard, .screenshotToolbar: return .screenshots
        case .missionControl, .appExpose, .showDesktop, .launchpad, .previousSpace, .nextSpace,
             .spotlight, .lockScreen: return .macControls
        }
    }

    /// Only offered in Advanced mode (an action already chosen always shows).
    var isAdvanced: Bool {
        switch self {
        case .newTab, .closeTab, .reopenTab, .previousStage,
             .keyboardShortcut, .openApp, .forceQuit, .middleClick,
             .cut, .undo, .redo, .pasteWithoutFormatting, .selectAll, .nextTrack, .previousTrack,
             .findNext, .newDocument, .deleteWord, .lineStart, .lineEnd, .documentStart, .documentEnd,
             .screenshotScreenToClipboard, .lockScreen:
            return true
        default:
            return false
        }
    }

    /// Whether the action makes sense for a gesture (a middle click only
    /// fits gestures that are themselves a click or a tap).
    func fits(_ gesture: Gesture) -> Bool {
        switch self {
        case .middleClick:
            return gesture.isClick || gesture.group == .tipTap || gesture == .forcePress
        default:
            return true
        }
    }

    /// Actions that open a switcher you browse while your fingers stay down.
    var isSwitcher: Bool { self == .windowSwitcher || self == .stageSwitcher }

    /// Actions that work without Accessibility permission.
    var worksWithoutAccessibility: Bool {
        switch self {
        case .macDefault, .doNothing, .hideAllApps, .restoreHiddenApps, .openApp, .toggleStageManager, .toggleStageStrip,
             .missionControl, .appExpose, .showDesktop, .launchpad:
            return true
        default:
            return false
        }
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64   // CGEventFlags raw value
    var display: String

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    /// F1–F20 key codes: fine as a shortcut on their own.
    static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107,
                                            113, 106, 64, 79, 80, 90]

    /// A shortcut that works everywhere needs ⌘, ⌥ or ⌃ (or an F-key);
    /// a plain letter or Space would stop you typing it.
    var isSafeEverywhere: Bool {
        !flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty || Self.functionKeys.contains(keyCode)
    }
}

struct ActionConfig: Codable, Equatable {
    var kind: ActionKind = .macDefault
    var shortcut: Shortcut?
    var appPath: String?
    /// Bundle identifier of the app to open; used in exported profiles,
    /// which never contain file paths.
    var appID: String?

    static let macDefault = ActionConfig()

    init(kind: ActionKind = .macDefault, shortcut: Shortcut? = nil, appPath: String? = nil, appID: String? = nil) {
        self.kind = kind
        self.shortcut = shortcut
        self.appPath = appPath
        self.appID = appID
    }

    /// Where the app to open lives: the saved path if it still exists,
    /// otherwise wherever macOS finds the app by its identifier.
    var resolvedAppURL: URL? {
        if let p = appPath, FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        if let id = appID { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
        return nil
    }
}

/// Gesture overrides for one app.
struct AppProfile: Codable, Equatable {
    var name: String
    var path: String?
    var bindings: [String: ActionConfig] = [:]
}

// MARK: - Force press strength

/// How much harder than a normal click counts as a force press.
enum ForceStrength: String, Codable, CaseIterable, Identifiable {
    case light, medium, firm
    /// The pressure at which macOS itself force-clicks (needs calibrating).
    case matchMac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .firm: return "Firm"
        case .matchMac: return "Match macOS"
        }
    }

    /// Pressure needed, as a multiple of the pressure of the click itself.
    var ratio: Float {
        switch self {
        case .light: return 1.5
        case .medium: return 1.8
        case .firm: return 2.3
        case .matchMac: return 1.8   // until calibrated
        }
    }
}

// MARK: - Settings

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

struct Settings: Codable, Equatable {
    /// Bumped when saved settings need a one-time change on upgrade.
    static let currentVersion = 3
    /// Scope key used where an app identifier is expected, for the
    /// gestures that apply while Stage Manager is on.
    static let stageScope = "@stage"

    var version: Int = Settings.currentVersion
    var enabled: Bool = true
    var showInDock: Bool = false
    var modules: [String: Bool] = [:]
    var bindings: [String: ActionConfig] = [:]
    /// Per-app overrides, keyed by bundle identifier.
    var apps: [String: AppProfile] = [:]
    /// Shows every action, module and per-app setup.
    var advancedMode: Bool = false
    /// Corner size per trackpad corner; missing = medium.
    var cornerSizes: [String: CornerSize] = [:]
    /// Use a separate gesture setup while Stage Manager is on.
    var stageSetOn: Bool = false
    /// Gestures that differ while Stage Manager is on; missing = same as normal.
    var stageBindings: [String: ActionConfig] = [:]
    /// How hard a force press has to be.
    var forceStrength: ForceStrength = .medium
    /// Trackpad pressure at which macOS gives its force-click buzz, measured
    /// on the calibration pad.
    var forceCalibration: Float?
    /// Space between snapped windows and around them, in points (Advanced).
    var windowGap: Double = 0
    /// Keyboard shortcuts that run an action from anywhere (Shortcuts page).
    var keyShortcuts: [KeyBinding] = []
    /// Apps whose window snaps into place when they open (Advanced).
    var launchPositions: [String: LaunchPosition] = [:]

    /// Windows-style starting setup.
    static var windowsStyle: Settings {
        var s = Settings()
        for m in ModuleID.allCases { s.modules[m.rawValue] = m.defaultOn }
        s.bindings[Gesture.threeSwipeDown.key] = ActionConfig(kind: .hideAllApps)
        s.bindings[Gesture.threeSwipeUp.key] = ActionConfig(kind: .restoreHiddenApps)
        s.bindings[Gesture.threeSwipeLeft.key] = ActionConfig(kind: .windowSwitcher)
        s.bindings[Gesture.threeSwipeRight.key] = ActionConfig(kind: .windowSwitcher)
        s.addStageManagerDefaults()
        s.addTipTapDefaults()
        return s
    }

    /// Puts the Stage Manager actions on four-finger swipes that are still unused.
    mutating func addStageManagerDefaults() {
        modules[ModuleID.stageManager.rawValue] = true
        setIfUnused(.fourSwipeLeft, .stageSwitcher)
        setIfUnused(.fourSwipeRight, .stageSwitcher)
        setIfUnused(.fourSwipeUp, .toggleStageManager)
        setIfUnused(.fourSwipeDown, .toggleStageStrip)
    }

    /// TipTap left/right switch tabs.
    mutating func addTipTapDefaults() {
        setIfUnused(.tipTapLeft, .previousTab)
        setIfUnused(.tipTapRight, .nextTab)
    }

    /// Switches on modules added since these settings were saved.
    /// Returns true when something changed.
    mutating func upgrade() -> Bool {
        var changed = false
        if version < 2 {
            // 0.4: TrackpadTool lives in the menu bar; the Dock icon is opt-in.
            showInDock = false
            version = 2
            changed = true
        }
        if version < 3 {
            // 0.6: Advanced mode, corner sizes, Stage Manager gestures (all start off/default).
            version = 3
            changed = true
        }
        if modules[ModuleID.stageManager.rawValue] == nil {
            addStageManagerDefaults()
            changed = true
        }
        for m in ModuleID.allCases where modules[m.rawValue] == nil {
            modules[m.rawValue] = m.defaultOn
            if m == .tipTap { addTipTapDefaults() }
            changed = true
        }
        return changed
    }

    private mutating func setIfUnused(_ gesture: Gesture, _ action: ActionKind) {
        if (bindings[gesture.key]?.kind ?? .macDefault) == .macDefault {
            bindings[gesture.key] = ActionConfig(kind: action)
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? false
        modules = try c.decodeIfPresent([String: Bool].self, forKey: .modules) ?? [:]
        // Entry by entry: one action this version doesn't know (say, after
        // going back to an older version) drops that entry, not the whole setup.
        bindings = (try c.decodeIfPresent([String: Lossy<ActionConfig>].self, forKey: .bindings) ?? [:]).compactMapValues(\.value)
        apps = (try c.decodeIfPresent([String: Lossy<AppProfile>].self, forKey: .apps) ?? [:]).compactMapValues(\.value)
        advancedMode = try c.decodeIfPresent(Bool.self, forKey: .advancedMode) ?? false
        cornerSizes = (try? c.decodeIfPresent([String: CornerSize].self, forKey: .cornerSizes)) ?? [:]
        stageSetOn = try c.decodeIfPresent(Bool.self, forKey: .stageSetOn) ?? false
        stageBindings = (try c.decodeIfPresent([String: Lossy<ActionConfig>].self, forKey: .stageBindings) ?? [:]).compactMapValues(\.value)
        forceStrength = (try? c.decodeIfPresent(ForceStrength.self, forKey: .forceStrength)) ?? .medium
        forceCalibration = try? c.decodeIfPresent(Float.self, forKey: .forceCalibration)
        windowGap = (try? c.decodeIfPresent(Double.self, forKey: .windowGap)) ?? 0
        keyShortcuts = ((try? c.decodeIfPresent([Lossy<KeyBinding>].self, forKey: .keyShortcuts)) ?? []).compactMap(\.value)
        launchPositions = ((try? c.decodeIfPresent([String: Lossy<LaunchPosition>].self, forKey: .launchPositions)) ?? [:]).compactMapValues(\.value)
    }
}

// MARK: - What actions do (settings rows and cheat sheet)

extension ActionConfig {
    /// The app an "Open app" action opens, by name.
    var appName: String? {
        guard let url = resolvedAppURL else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// One full sentence: what happens when you do the gesture.
    func explanation(for gesture: Gesture) -> String {
        let clickLike = gesture.isClick || gesture.group == .tipTap || gesture.group == .edgeSwipes || gesture == .forcePress
        func snap(_ part: String) -> String { "Moves and resizes the front window to fill the \(part) of the screen." }
        switch kind {
        case .macDefault:
            return gesture == .forcePress ? "Look Up, as macOS normally does." : "Whatever macOS itself does with this gesture; TrackpadTool leaves it alone."
        case .doNothing:
            return gesture.isClick ? "Nothing: the click is blocked." : "Nothing: the gesture is ignored."
        case .hideAllApps: return "Hides every open app at once, as if you pressed ⌘H in each, so you see the desktop."
        case .restoreHiddenApps: return "Brings back the apps that Hide all apps put away."
        case .windowSwitcher:
            return clickLike ? "Jumps straight back to the app you used before."
                             : "Opens the app switcher, like ⌘Tab: keep your fingers down and move to browse, lift them to switch to the highlighted app."
        case .minimizeWindow: return "Minimizes the front window into the Dock."
        case .restoreMinimizedWindow: return "Brings back the window you minimized most recently."
        case .minimizeAllWindows: return "Minimizes every open window into the Dock."
        case .snapLeft: return snap("left half")
        case .snapRight: return snap("right half")
        case .snapTop: return snap("top half")
        case .snapBottom: return snap("bottom half")
        case .snapTopLeft: return snap("top-left quarter")
        case .snapTopRight: return snap("top-right quarter")
        case .snapBottomLeft: return snap("bottom-left quarter")
        case .snapBottomRight: return snap("bottom-right quarter")
        case .snapLeftThird: return snap("left third")
        case .snapCenterThird: return snap("middle third")
        case .snapRightThird: return snap("right third")
        case .snapLeftTwoThirds: return snap("left two-thirds")
        case .snapRightTwoThirds: return snap("right two-thirds")
        case .maximizeWindow: return "Makes the front window fill the screen (without going full screen)."
        case .toggleMaximizeWindow: return "Makes the front window fill the screen; do it again to put it back where it was."
        case .maximizeAllWindows: return "Makes every open window fill its screen; Restore window size puts each one back."
        case .centerWindow: return "Moves the front window to the middle of the screen, keeping its size."
        case .restoreWindowSize: return "Puts a snapped or maximized window back to the size and place it had before."
        case .moveToNextDisplay: return "Moves the front window to your next display."
        case .nextTab: return "Goes to the next tab (⌘⇧]) in browsers, Finder and most apps."
        case .previousTab: return "Goes to the previous tab (⌘⇧[) in browsers, Finder and most apps."
        case .newTab: return "Opens a new tab (⌘T)."
        case .closeTab: return "Closes the current tab (⌘W); with no tabs, the window."
        case .reopenTab: return "Reopens the tab you closed last (⌘⇧T), in browsers."
        case .stageSwitcher:
            return clickLike ? "Jumps back to the Stage Manager stage you used before."
                             : "Shows your Stage Manager stages: keep your fingers down and move to browse, lift them to switch."
        case .previousStage: return "Jumps back to the Stage Manager stage you used last."
        case .toggleStageManager: return "Turns Stage Manager on or off."
        case .toggleStageStrip: return "Shows or hides the recent apps on the left while Stage Manager is on."
        case .keyboardShortcut:
            return shortcut.map { "Presses \($0.display) for you, as if you typed it." } ?? "Presses a keyboard shortcut (none recorded yet)."
        case .openApp:
            if let name = appName { return "Opens \(name), or brings it to the front if it's already open." }
            if let id = appID { return "Opens the app \(id) (not installed on this Mac)." }
            return "Opens an app (none chosen yet)."
        case .forceQuit: return "Opens the Force Quit window (⌘⌥⎋) to close an app that hangs."
        case .middleClick: return "Clicks the middle mouse button: in browsers it opens a link in a new tab, or closes the tab you click."
        case .copy: return "Copies what's selected (⌘C)."
        case .paste: return "Pastes what you copied last (⌘V)."
        case .cut: return "Cuts what's selected, to paste elsewhere (⌘X)."
        case .undo: return "Undoes the last change (⌘Z)."
        case .redo: return "Redoes what you just undid (⇧⌘Z)."
        case .pasteWithoutFormatting: return "Pastes as plain text, matching the text around it (⌥⇧⌘V)."
        case .selectAll: return "Selects everything in the document or field (⌘A)."
        case .find: return "Opens Find in the front app (⌘F)."
        case .findNext: return "Jumps to the next match of what you searched for (⌘G)."
        case .save: return "Saves the document (⌘S)."
        case .newDocument: return "Opens a new document or window in the front app (⌘N)."
        case .deleteWord: return "Deletes the word before the cursor (⌥⌫)."
        case .lineStart: return "Moves the cursor to the start of the line (⌘←)."
        case .lineEnd: return "Moves the cursor to the end of the line (⌘→)."
        case .documentStart: return "Jumps to the top of the document or page (⌘↑)."
        case .documentEnd: return "Jumps to the bottom of the document or page (⌘↓)."
        case .emojiPicker: return "Opens the emoji and symbols picker where you're typing (⌃⌘Space)."
        case .screenshotArea: return "Takes a screenshot of an area you drag out (⇧⌘4)."
        case .playPause: return "Plays or pauses whatever is playing (Music, Spotify, a video in your browser), like the ⏯ key."
        case .nextTrack: return "Skips to the next track, like the ⏭ key."
        case .previousTrack: return "Goes back to the previous track (or the start of this one), like the ⏮ key."
        case .volumeUp: return "Turns the volume up one step, with the usual volume overlay."
        case .volumeDown: return "Turns the volume down one step, with the usual volume overlay."
        case .mute: return "Mutes or unmutes the sound."
        case .screenshotScreen: return "Saves a screenshot of the whole screen, where macOS normally puts screenshots (⇧⌘3)."
        case .screenshotWindow: return "Click a window to save a screenshot of just that window, with its shadow, where your screenshots go."
        case .screenshotAreaToClipboard: return "Drag out an area; it goes to the clipboard instead of a file, ready to paste (⌃⇧⌘4)."
        case .screenshotScreenToClipboard: return "Copies the whole screen to the clipboard, ready to paste (⌃⇧⌘3)."
        case .screenshotToolbar: return "Opens the screenshot toolbar: area, window or screen, screen recording, a timer and where to save (⇧⌘5)."
        case .missionControl: return "Shows every open window and your Spaces at the top, like swiping up with three fingers."
        case .appExpose: return "Spreads out only the windows of the app you're using, so you can pick one."
        case .showDesktop: return "Moves every window aside to show the desktop; do it again to bring them back."
        case .launchpad: return "Opens Launchpad, or the Apps view on newer macOS, to start an app."
        case .previousSpace: return "Moves to the Space (desktop or full-screen app) on the left (⌃←)."
        case .nextSpace: return "Moves to the Space (desktop or full-screen app) on the right (⌃→)."
        case .spotlight: return "Opens Spotlight search (⌘Space)."
        case .lockScreen: return "Locks your Mac right away; you need your password or Touch ID to get back in (⌃⌘Q)."
        }
    }
}

// MARK: - Resolving gestures (pure: safe on any thread with a copy)

extension Settings {
    func isOn(_ module: ModuleID) -> Bool {
        modules[module.rawValue] ?? module.defaultOn
    }

    /// A gesture whose kind belongs to a switched-off module is ignored.
    func isAvailable(_ gesture: Gesture) -> Bool {
        guard let m = gesture.group.module else { return true }
        return isOn(m)
    }

    func cornerSize(_ corner: Corner) -> CornerSize {
        cornerSizes[corner.rawValue] ?? .medium
    }

    /// The Stage Manager gesture setup is switched on.
    var stageSetEnabled: Bool { isOn(.stageManager) && stageSetOn }

    /// The action a gesture runs in an app (nil = no app known), with the
    /// Stage Manager setup applied when `stage` is true. Order: the app's
    /// own setup, then the Stage Manager setup, then the normal setup.
    func resolve(_ gesture: Gesture, app: String?, stage: Bool) -> ActionConfig {
        guard isAvailable(gesture) else { return .macDefault }
        var c = (stage ? stageBindings[gesture.key] : nil) ?? bindings[gesture.key] ?? .macDefault
        if isOn(.perAppGestures), let app = app, app != Settings.stageScope,
           let override = self.apps[app]?.bindings[gesture.key] {
            c = override
        }
        if let m = c.kind.module, !isOn(m) { return .macDefault }
        return c
    }
}

/// Decodes a value if it can, and nil instead of failing.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Keyboard shortcuts and launch positions

/// A global keyboard shortcut and the action it runs.
struct KeyBinding: Codable, Equatable, Identifiable {
    var id = UUID()
    var shortcut: Shortcut?
    var action: ActionConfig = .macDefault
}

/// Where an app's window goes when the app opens.
struct LaunchPosition: Codable, Equatable {
    var name: String
    var place: ActionKind = .maximizeWindow
}

extension ActionKind {
    /// Places a window can be snapped to when its app opens.
    static let launchPlaces: [ActionKind] = [
        .maximizeWindow, .centerWindow, .snapLeft, .snapRight, .snapTop, .snapBottom,
        .snapTopLeft, .snapTopRight, .snapBottomLeft, .snapBottomRight,
        .snapLeftThird, .snapCenterThird, .snapRightThird, .snapLeftTwoThirds, .snapRightTwoThirds
    ]
}

extension Shortcut {
    /// A shortcut from key codes and modifiers, with its label worked out.
    static func make(_ keyCode: UInt16, _ flags: CGEventFlags) -> Shortcut {
        Shortcut(keyCode: keyCode, modifiers: flags.rawValue,
                 display: Shortcut.label(keyCode: keyCode, modifiers: flags.rawValue))
    }

    /// Rectangle's standard window shortcuts.
    static let rectangleDefaults: [(Shortcut, ActionKind)] = {
        let co: CGEventFlags = [.maskControl, .maskAlternate]
        return [
            (make(123, co), .snapLeft), (make(124, co), .snapRight),
            (make(126, co), .snapTop), (make(125, co), .snapBottom),
            (make(32, co), .snapTopLeft), (make(34, co), .snapTopRight),
            (make(38, co), .snapBottomLeft), (make(40, co), .snapBottomRight),
            (make(2, co), .snapLeftThird), (make(3, co), .snapCenterThird), (make(5, co), .snapRightThird),
            (make(14, co), .snapLeftTwoThirds), (make(17, co), .snapRightTwoThirds),
            (make(36, co), .maximizeWindow), (make(8, co), .centerWindow),
            (make(51, co), .restoreWindowSize),
            (make(124, [.maskControl, .maskAlternate, .maskCommand]), .moveToNextDisplay)
        ]
    }()
}
