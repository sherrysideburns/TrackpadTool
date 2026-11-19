import AppKit
import Combine

/// Holds the settings, saves them to
/// ~/Library/Application Support/TrackpadTool/settings.json
/// and tells the gesture engine when something changes.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            save()
            GestureEngine.shared.reconfigure()
            if settings.enabled != oldValue.enabled {
                DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.updateStatusIcon() }
            }
            if settings.showInDock != oldValue.showInDock {
                DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.applyDockPolicy() }
            }
        }
    }

    let fileURL: URL
    private(set) var isFirstLaunch: Bool

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("TrackpadTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")

        let data = try? Data(contentsOf: fileURL)
        var decoded: Settings?
        if let data = data {
            do {
                decoded = try JSONDecoder().decode(Settings.self, from: data)
            } catch {
                // Keep the unreadable file instead of overwriting it.
                let copy = dir.appendingPathComponent("settings.unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? data.write(to: copy)
                Log.error("Settings couldn't be read (\(error)). Started with the default setup; the old file was kept as \(copy.lastPathComponent).")
            }
        }
        if var loaded = decoded {
            let upgraded = loaded.upgrade()
            settings = loaded
            isFirstLaunch = false
            if upgraded { save() }
        } else {
            settings = .windowsStyle
            isFirstLaunch = data == nil
            save()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Modules

    func isOn(_ module: ModuleID) -> Bool { settings.isOn(module) }

    func setModule(_ module: ModuleID, on: Bool) {
        settings.modules[module.rawValue] = on
    }

    /// A gesture whose kind belongs to a switched-off module is ignored.
    func isAvailable(_ gesture: Gesture) -> Bool { settings.isAvailable(gesture) }

    // MARK: Bindings
    // `app` is nil for the normal setup, Settings.stageScope for the
    // Stage Manager setup, or an app's bundle identifier.

    /// The Stage Manager gesture setup is switched on (whether or not
    /// Stage Manager itself is on right now).
    var stageSetEnabled: Bool { settings.stageSetEnabled }

    /// The Stage Manager gesture setup applies right now.
    var stageSetActive: Bool { stageSetEnabled && StageManager.isOnCached }

    /// The setting as stored: for an app or the Stage Manager setup, nil
    /// means "same as the normal setup".
    func storedConfig(for gesture: Gesture, app: String?) -> ActionConfig? {
        if app == Settings.stageScope { return settings.stageBindings[gesture.key] }
        if let app = app { return settings.apps[app]?.bindings[gesture.key] }
        return settings.bindings[gesture.key] ?? .macDefault
    }

    func globalConfig(for gesture: Gesture) -> ActionConfig {
        settings.bindings[gesture.key] ?? .macDefault
    }

    /// The action that actually runs for a gesture in a given app.
    func effectiveConfig(for gesture: Gesture, app: String?) -> ActionConfig {
        resolve(gesture, app: app, stage: stageSetActive)
    }

    private func resolve(_ gesture: Gesture, app: String?, stage: Bool) -> ActionConfig {
        settings.resolve(gesture, app: app, stage: stage)
    }

    /// Every action a gesture could run anywhere (normal setup, Stage
    /// Manager setup, each app override).
    func allConfigs(for gesture: Gesture) -> [ActionConfig] {
        guard isAvailable(gesture) else { return [] }
        let stages = stageSetEnabled ? [false, true] : [false]
        var list: [ActionConfig] = []
        for stage in stages {
            list.append(resolve(gesture, app: nil, stage: stage))
            if isOn(.perAppGestures) {
                for app in settings.apps.keys { list.append(resolve(gesture, app: app, stage: stage)) }
            }
        }
        return list
    }

    func isUsed(_ gesture: Gesture) -> Bool {
        allConfigs(for: gesture).contains { $0.kind != .macDefault }
    }

    /// Whether a gesture group is shown: its module is on and, outside
    /// Advanced mode, it isn't an advanced group nobody uses.
    func showsGroup(_ group: GestureGroup) -> Bool {
        if let m = group.module, !isOn(m) { return false }
        if settings.advancedMode || !group.isAdvanced { return true }
        return group.gestures.contains { isUsed($0) }
    }

    func update(_ gesture: Gesture, app: String?, _ change: (inout ActionConfig) -> Void) {
        if app == Settings.stageScope {
            var c = settings.stageBindings[gesture.key] ?? globalConfig(for: gesture)
            change(&c)
            settings.stageBindings[gesture.key] = c
        } else if let app = app {
            guard settings.apps[app] != nil else { return }
            var c = settings.apps[app]?.bindings[gesture.key] ?? globalConfig(for: gesture)
            change(&c)
            settings.apps[app]?.bindings[gesture.key] = c
        } else {
            var c = globalConfig(for: gesture)
            change(&c)
            settings.bindings[gesture.key] = c
        }
    }

    func clearOverride(_ gesture: Gesture, app: String) {
        if app == Settings.stageScope {
            settings.stageBindings[gesture.key] = nil
        } else {
            settings.apps[app]?.bindings[gesture.key] = nil
        }
    }

    // MARK: Corners

    func cornerSize(_ corner: Corner) -> CornerSize { settings.cornerSize(corner) }

    func setCornerSize(_ corner: Corner, _ size: CornerSize) {
        settings.cornerSizes[corner.rawValue] = size
    }

    /// The size all four corners share, or nil when they differ.
    var sharedCornerSize: CornerSize? {
        let sizes = Set(Corner.allCases.map { cornerSize($0) })
        return sizes.count == 1 ? sizes.first : nil
    }

    /// Sets every corner at once (one change, one save).
    func setAllCornerSizes(_ size: CornerSize) {
        var sizes = settings.cornerSizes
        for c in Corner.allCases { sizes[c.rawValue] = size }
        settings.cornerSizes = sizes
    }

    // MARK: Apps

    /// Adds an app chosen in an open panel; returns its bundle identifier.
    func addApp(at url: URL) -> String? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        if settings.apps[id] == nil {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            settings.apps[id] = AppProfile(name: name, path: url.path)
        }
        return id
    }

    func removeApp(_ id: String) {
        settings.apps[id] = nil
    }

    struct AppEntry: Identifiable {
        let id: String
        let profile: AppProfile
    }

    var sortedApps: [AppEntry] {
        settings.apps.map { AppEntry(id: $0.key, profile: $0.value) }
            .sorted { $0.profile.name.localizedCompare($1.profile.name) == .orderedAscending }
    }

    // MARK: Dropdown options

    struct OptionGroup: Identifiable {
        /// nil for the first group (macOS default, Do nothing).
        let module: ModuleID?
        let actions: [ActionKind]
        var id: String { module?.rawValue ?? "basic" }
        var title: String { module?.title ?? "" }
    }

    /// Defaults first, then one group per switched-on action module.
    /// Outside Advanced mode, advanced actions are left out (the current
    /// one always stays, so nothing disappears).
    func optionGroups(current: ActionKind?, gesture: Gesture? = nil) -> [OptionGroup] {
        var groups = [OptionGroup(module: nil, actions: [.macDefault, .doNothing])]
        for m in ModuleID.allCases where m.kind == .actions && isOn(m) {
            let actions = m.actions.filter { k in
                if k == current { return true }
                if let g = gesture, !k.fits(g) { return false }
                return settings.advancedMode || !k.isAdvanced
            }
            if !actions.isEmpty { groups.append(OptionGroup(module: m, actions: actions)) }
        }
        if let current = current, !groups.contains(where: { $0.actions.contains(current) }) {
            groups.append(OptionGroup(module: current.module, actions: [current]))
        }
        return groups
    }

    func resetToDefaults() {
        let apps = settings.apps
        let advanced = settings.advancedMode
        settings = .windowsStyle
        settings.apps = apps
        settings.advancedMode = advanced
    }
}
