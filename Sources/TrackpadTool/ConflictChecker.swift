import AppKit

/// Checks which trackpad gestures macOS itself is using, so the settings
/// window can warn when one of your gestures would clash.
final class ConflictChecker: ObservableObject {
    @Published private(set) var threeHoriz = false
    @Published private(set) var threeVert = false
    @Published private(set) var fourHoriz = false
    @Published private(set) var fourVert = false
    @Published private(set) var threeFingerDrag = false
    @Published private(set) var notificationCenterSwipe = false
    @Published private(set) var cornerRightClick = false

    /// Built-in trackpad first; the Bluetooth domain only counts when the built-in one has no value.
    private let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad"
    ]

    func refresh() {
        // Setting Mission Control / App Exposé to "Off" is stored in the Dock's
        // preferences, not the trackpad's, so check both.
        let verticalInUse = dockFlag("showMissionControlGestureEnabled") || dockFlag("showAppExposeGestureEnabled")
        threeHoriz = isOn("TrackpadThreeFingerHorizSwipeGesture")
        threeVert = verticalInUse && isOn("TrackpadThreeFingerVertSwipeGesture")
        fourHoriz = isOn("TrackpadFourFingerHorizSwipeGesture")
        fourVert = verticalInUse && isOn("TrackpadFourFingerVertSwipeGesture")
        threeFingerDrag = isOn("TrackpadThreeFingerDrag")
        notificationCenterSwipe = isOn("TrackpadTwoFingerFromRightEdgeSwipeGesture")
        cornerRightClick = isOn("TrackpadCornerSecondaryClick")
    }

    private func isOn(_ key: String) -> Bool {
        for domain in domains {
            CFPreferencesAppSynchronize(domain as CFString)
            if let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber {
                return value.intValue != 0
            }
        }
        return false
    }

    /// A Dock gesture switch; missing means macOS's default, which is on.
    private func dockFlag(_ key: String) -> Bool {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber)?.boolValue ?? true
    }

    /// Plain-language warnings for the gestures you've changed.
    func issues(store: SettingsStore) -> [String] {
        func used(_ gestures: [Gesture]) -> Bool { gestures.contains { store.isUsed($0) } }
        var lines: [String] = []
        if threeFingerDrag && used([.threeSwipeUp, .threeSwipeDown, .threeSwipeLeft, .threeSwipeRight]) {
            lines.append("Three-finger drag is on, so three-finger swipes move windows. Turn it off in Accessibility › Pointer Control › Trackpad Options.")
        }
        if threeVert && used([.threeSwipeUp, .threeSwipeDown]) {
            lines.append("macOS uses three-finger swipe up/down for Mission Control and App Exposé. Set those to four fingers or off.")
        }
        if threeHoriz && used([.threeSwipeLeft, .threeSwipeRight]) {
            lines.append("macOS uses three-finger swipe left/right to switch between full-screen apps. Set it to four fingers or off.")
        }
        if fourVert && used([.fourSwipeUp, .fourSwipeDown]) {
            lines.append("macOS uses four-finger swipe up/down for Mission Control and App Exposé.")
        }
        if fourHoriz && used([.fourSwipeLeft, .fourSwipeRight]) {
            lines.append("macOS uses four-finger swipe left/right to switch between full-screen apps.")
        }
        if notificationCenterSwipe && used([.edgeRight]) {
            lines.append("macOS opens Notification Center with a two-finger swipe from the right edge. Turn that off in Trackpad › More Gestures, or both will happen.")
        }
        if cornerRightClick && used([.cornerBottomLeft, .cornerBottomRight]) {
            lines.append("Your trackpad right-clicks in a bottom corner. Set Secondary click to two fingers in Trackpad › Point & Click.")
        }
        return lines
    }

    static func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
