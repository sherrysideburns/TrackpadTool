import AppKit

/// Stage Manager has no public API; its switches live in the
/// com.apple.WindowManager preferences (the same ones System Settings ›
/// Desktop & Dock changes), which macOS picks up right away.
enum StageManager {
    private static let domain = "com.apple.WindowManager"

    static var isOn: Bool { read("GloballyEnabled", default: false) }
    static var stripHidden: Bool { read("AutoHide", default: false) }

    /// `isOn`, re-read at most once a second. Used while a gesture runs.
    static var isOnCached: Bool {
        let now = Date()
        if now.timeIntervalSince(cacheTime) > 1 {
            cachedOn = isOn
            cacheTime = now
        }
        return cachedOn
    }
    private static var cachedOn = false
    private static var cacheTime = Date.distantPast

    // MARK: Options (System Settings › Desktop & Dock › Stage Manager)

    /// true = "All at once", false = "One at a time".
    static var windowsAllAtOnce: Bool {
        get { read("AppWindowGroupingBehavior", default: true) }
        set { write("AppWindowGroupingBehavior", newValue) }
    }

    /// Desktop items shown while Stage Manager is on.
    static var showDesktopItems: Bool {
        get { !read("HideDesktop", default: true) }
        set { write("HideDesktop", !newValue) }
    }

    /// Widgets shown while Stage Manager is on.
    static var showWidgets: Bool {
        get { !read("StageManagerHideWidgets", default: false) }
        set { write("StageManagerHideWidgets", !newValue) }
    }

    /// true = clicking the wallpaper always reveals the desktop,
    /// false = only in Stage Manager.
    static var clickWallpaperAlways: Bool {
        get { read("EnableStandardClickToShowDesktop", default: true) }
        set { write("EnableStandardClickToShowDesktop", newValue) }
    }

    static func set(on: Bool) {
        Log.breadcrumb("Stage Manager \(on ? "on" : "off")")
        write("GloballyEnabled", on)
        cachedOn = on
        cacheTime = Date()
    }

    static func set(stripHidden: Bool) { write("AutoHide", stripHidden) }

    // MARK: Actions

    static func toggle() {
        let on = !isOn
        set(on: on)
        GlassHUD.shared.show(symbol: "squares.leading.rectangle",
                             text: on ? "Stage Manager on" : "Stage Manager off")
    }

    static func toggleStrip() {
        if !isOn {
            GlassHUD.shared.show(symbol: "squares.leading.rectangle", text: "Stage Manager is off")
            return
        }
        let hide = !stripHidden
        set(stripHidden: hide)
        GlassHUD.shared.show(symbol: hide ? "sidebar.left" : "sidebar.squares.left",
                             text: hide ? "Recent apps hidden" : "Recent apps shown")
    }

    // MARK: Preferences

    private static func read(_ key: String, default value: Bool) -> Bool {
        CFPreferencesAppSynchronize(domain as CFString)
        guard let n = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber else { return value }
        return n.boolValue
    }

    /// Uses the `defaults` tool so the Window Manager is notified of the
    /// change. Runs in the background, one change after another: waiting for
    /// it on the main thread could let the interface redraw halfway through
    /// a change, which can freeze or crash SwiftUI.
    private static let writer = DispatchQueue(label: "TrackpadTool.stage-manager")

    private static func write(_ key: String, _ value: Bool) {
        writer.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            p.arguments = ["write", domain, key, "-bool", value ? "true" : "false"]
            p.standardOutput = FileHandle.nullDevice
            do {
                try p.run()
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    Log.error("Stage Manager setting \(key) = \(value) failed (defaults exit code \(p.terminationStatus))")
                } else {
                    Log.info("Stage Manager setting \(key) = \(value)")
                }
            } catch {
                Log.error("Could not change Stage Manager setting \(key): \(error.localizedDescription)")
            }
        }
    }
}
