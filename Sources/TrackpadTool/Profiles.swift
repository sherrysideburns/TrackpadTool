import AppKit
import UniformTypeIdentifiers

// MARK: - The .tpt file

/// A TrackpadTool profile, as stored in a .tpt file (plain JSON).
/// It only ever holds data: gestures, modules and per-app overrides.
/// Never code, never file paths.
struct ProfileFile: Codable, Equatable {
    static let formatName = "TrackpadTool profile"
    /// 2 (0.7): files say which parts they hold (`parts`).
    static let currentFormat = 2

    var format: String = ProfileFile.formatName
    var formatVersion: Int = ProfileFile.currentFormat
    var name: String
    var note: String?
    var createdWith: String?
    var created: Date?
    var modules: [String: Bool] = [:]
    var bindings: [String: ActionConfig] = [:]
    var apps: [String: AppProfile] = [:]
    // Added in 0.6; older files simply don't have them.
    var stageSetOn: Bool?
    var stageBindings: [String: ActionConfig]?
    var cornerSizes: [String: CornerSize]?
    // Added in 0.7: the parts this combo holds; nil = a complete setup.
    var parts: [String]?
    // Added in 0.9: keyboard shortcuts.
    var keyShortcuts: [KeyBinding]?
}

extension UTType {
    static var trackpadToolProfile: UTType {
        UTType(filenameExtension: "tpt") ?? .json
    }
}

/// Why a file was refused.
struct ProfileError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

enum ProfileValidator {
    static let maxFileSize = 256 * 1024
    static let maxApps = 50

    /// Reads and checks a .tpt file. Anything unexpected → refused, nothing changes.
    static func load(_ url: URL) throws -> ProfileFile {
        // Read at most one byte past the limit, whatever the file says its
        // size is (a link to something huge can't make us read it all).
        // Only ordinary files (a pipe or device would make the read wait forever).
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
            throw ProfileError(reason: "The file can't be read.")
        }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxFileSize + 1) ?? Data()
        } catch {
            throw ProfileError(reason: "The file can't be read.")
        }
        guard !data.isEmpty else { throw ProfileError(reason: "The file is empty.") }
        guard data.count <= maxFileSize else { throw ProfileError(reason: "The file is too large to be a TrackpadTool combo.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: ProfileFile
        do {
            file = try decoder.decode(ProfileFile.self, from: data)
        } catch {
            throw ProfileError(reason: "This isn't a valid TrackpadTool profile, or it contains an action this version doesn't know.")
        }
        try validate(file)
        return sanitized(file)
    }

    static func validate(_ f: ProfileFile) throws {
        func fail(_ s: String) throws -> Never { throw ProfileError(reason: s) }
        if f.format != ProfileFile.formatName { try fail("This isn't a TrackpadTool profile.") }
        if f.formatVersion > ProfileFile.currentFormat {
            try fail("This profile was made by a newer TrackpadTool. Update TrackpadTool first.")
        }
        if f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || f.name.count > 80 { try fail("The combo's name is missing or too long.") }
        if (f.note?.count ?? 0) > 500 { try fail("The combo's description is too long.") }
        if (f.createdWith?.count ?? 0) > 40 { try fail("The combo's version label is too long.") }
        for text in [f.name, f.note ?? "", f.createdWith ?? ""] + f.apps.values.map(\.name) where hasHiddenCharacters(text) {
            try fail("The combo contains hidden or text-direction characters, which could make it look like something else.")
        }
        let moduleKeys = Set(ModuleID.allCases.map(\.rawValue))
        if let bad = f.modules.keys.first(where: { !moduleKeys.contains($0) }) { try fail("Unknown module “\(bad.prefix(40))”.") }
        try checkBindings(f.bindings)
        try checkBindings(f.stageBindings ?? [:])
        let partKeys = Set(ComboPart.allCases.map(\.rawValue))
        if let bad = f.parts?.first(where: { !partKeys.contains($0) }) {
            try fail("Unknown combo part “\(bad.prefix(40))”.")
        }
        let cornerKeys = Set(Corner.allCases.map(\.rawValue))
        if let bad = f.cornerSizes?.keys.first(where: { !cornerKeys.contains($0) }) {
            try fail("Unknown trackpad corner “\(bad.prefix(40))”.")
        }
        if f.apps.count > maxApps { try fail("Too many app-specific setups (over \(maxApps)).") }
        let keys = f.keyShortcuts ?? []
        if keys.count > 100 { try fail("Too many keyboard shortcuts (over 100).") }
        let allowedFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        for k in keys {
            if let s = k.shortcut, s.keyCode > 127 || s.modifiers & ~allowedFlags.rawValue != 0 {
                try fail("A keyboard shortcut in this combo isn't valid.")
            }
            if [.keyboardShortcut, .openApp, .middleClick].contains(k.action.kind) {
                try fail("A keyboard shortcut in this combo runs an action shortcuts can't use.")
            }
            if let s = k.shortcut, !s.isSafeEverywhere {
                try fail("A keyboard shortcut in this combo has no ⌘, ⌥ or ⌃ and would block normal typing.")
            }
        }
        for (id, app) in f.apps {
            if !isBundleID(id) { try fail("“\(id.prefix(40))” isn't a valid app identifier.") }
            if app.name.isEmpty || app.name.count > 80 { try fail("An app name is missing or too long.") }
            try checkBindings(app.bindings)
        }
    }

    private static func checkBindings(_ bindings: [String: ActionConfig]) throws {
        let gestureKeys = Set(Gesture.allCases.map(\.rawValue))
        let allowedFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        for (key, config) in bindings {
            if !gestureKeys.contains(key) { throw ProfileError(reason: "Unknown gesture “\(key.prefix(40))”.") }
            if let s = config.shortcut {
                if s.keyCode > 127 || s.modifiers & ~allowedFlags.rawValue != 0 || s.display.count > 24 {
                    throw ProfileError(reason: "A keyboard shortcut in this profile isn't valid.")
                }
            }
            if let id = config.appID, !isBundleID(id) {
                throw ProfileError(reason: "An “Open app” action points to an invalid app identifier.")
            }
        }
    }

    /// Control characters (other than line breaks in notes) and characters
    /// that flip text direction, which can disguise what text says.
    static func hasHiddenCharacters(_ s: String) -> Bool {
        let hidden: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
                                   0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF]
        return s.unicodeScalars.contains { u in
            if u == "\n" { return false }
            return CharacterSet.controlCharacters.contains(u) || hidden.contains(u.value)
                || (0xE0000...0xE007F).contains(u.value)   // invisible tag characters
        }
    }

    static func isBundleID(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9][A-Za-z0-9.\\-]{0,154}$", options: .regularExpression) != nil
    }

    /// Drops anything we never trust from a file: file paths.
    /// Also rebuilds every shortcut's label from its keys, so what the
    /// review screen shows is what will actually be pressed.
    private static func sanitized(_ f: ProfileFile) -> ProfileFile {
        func clean(_ config: ActionConfig) -> ActionConfig {
            var c = config
            c.appPath = nil
            if var s = c.shortcut {
                s.display = Shortcut.label(keyCode: s.keyCode, modifiers: s.modifiers)
                c.shortcut = s
            }
            return c
        }
        var f = f
        f.keyShortcuts = f.keyShortcuts?.map { k in
            var k = k
            k.id = UUID()   // ids from a file could repeat
            k.action = clean(k.action)
            if let s = k.shortcut { k.shortcut = Shortcut.make(s.keyCode, s.flags) }
            return k
        }
        f.bindings = f.bindings.mapValues(clean)
        f.stageBindings = f.stageBindings?.mapValues(clean)
        f.apps = f.apps.mapValues { app in
            var a = app
            a.path = nil
            a.bindings = app.bindings.mapValues(clean)
            return a
        }
        return f
    }
}

// MARK: - Presets

struct Preset: Identifiable {
    let id: String
    let name: String
    let summary: String
    var bindings: [Gesture: ActionKind] = [:]
    /// nil = a complete setup; otherwise only these parts.
    var parts: [ComboPart]? = nil
    var cornerSize: CornerSize? = nil
    var stageBindings: [Gesture: ActionKind] = [:]

    var file: ProfileFile {
        var f = ProfileFile(name: name, note: summary, createdWith: AppInfo.version)
        for m in ModuleID.allCases { f.modules[m.rawValue] = true }
        for (g, k) in bindings { f.bindings[g.key] = ActionConfig(kind: k) }
        if let size = cornerSize {
            f.cornerSizes = Dictionary(uniqueKeysWithValues: Corner.allCases.map { ($0.rawValue, size) })
        }
        if !stageBindings.isEmpty {
            f.stageSetOn = true
            f.stageBindings = Dictionary(uniqueKeysWithValues: stageBindings.map { ($0.key.key, ActionConfig(kind: $0.value)) })
        }
        if let parts = parts { return f.keeping(Set(parts)) }
        return f
    }

    /// Each preset's file, built once (the Combos page shows them on every redraw).
    private static let files: [String: ProfileFile] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.file) })

    static func file(for preset: Preset) -> ProfileFile { files[preset.id] ?? preset.file }

    static let all: [Preset] = [
        Preset(id: "windows", name: "Windows user",
               summary: "Three fingers down hides everything, up brings it back, left/right is the app switcher. Three-finger click is a middle click; TipTap switches tabs.",
               bindings: [.threeSwipeDown: .hideAllApps, .threeSwipeUp: .restoreHiddenApps,
                          .threeSwipeLeft: .windowSwitcher, .threeSwipeRight: .windowSwitcher,
                          .threeClick: .middleClick, .tipTapLeft: .previousTab, .tipTapRight: .nextTab]),
        Preset(id: "power", name: "Mac power user",
               summary: "Three fingers snap and size the front window; four fingers switch apps and hide or restore everything. Middle click and TipTap tabs included.",
               bindings: [.threeSwipeLeft: .snapLeft, .threeSwipeRight: .snapRight,
                          .threeSwipeUp: .toggleMaximizeWindow, .threeSwipeDown: .minimizeWindow,
                          .fourSwipeLeft: .windowSwitcher, .fourSwipeRight: .windowSwitcher,
                          .fourSwipeDown: .hideAllApps, .fourSwipeUp: .restoreHiddenApps,
                          .threeClick: .middleClick, .tipTapLeft: .previousTab, .tipTapRight: .nextTab]),
        Preset(id: "stage", name: "Stage Manager",
               summary: "Three fingers left/right switch apps; four fingers flip stages, turn Stage Manager on/off (up) and show or hide the recent apps (down).",
               bindings: [.threeSwipeLeft: .windowSwitcher, .threeSwipeRight: .windowSwitcher,
                          .fourSwipeLeft: .stageSwitcher, .fourSwipeRight: .stageSwitcher,
                          .fourSwipeUp: .toggleStageManager, .fourSwipeDown: .toggleStageStrip,
                          .threeClick: .middleClick, .tipTapLeft: .previousTab, .tipTapRight: .nextTab]),
        Preset(id: "minimal", name: "Minimal",
               summary: "Leaves macOS's own gestures alone. Only adds a three-finger middle click and TipTap to switch tabs.",
               bindings: [.threeClick: .middleClick, .tipTapLeft: .previousTab, .tipTapRight: .nextTab]),
        // Small combos: one part each, mix them into any setup.
        Preset(id: "corner-snap", name: "Corner snapping",
               summary: "Click a corner of the trackpad to snap the front window into that quarter of the screen. Small corners.",
               bindings: [.cornerTopLeft: .snapTopLeft, .cornerTopRight: .snapTopRight,
                          .cornerBottomLeft: .snapBottomLeft, .cornerBottomRight: .snapBottomRight],
               parts: [.cornerClicks], cornerSize: .small),
        Preset(id: "four-snap", name: "Snap on four fingers",
               summary: "Four fingers left/right snap the front window to a half, up maximizes or restores it, down minimizes it.",
               bindings: [.fourSwipeLeft: .snapLeft, .fourSwipeRight: .snapRight,
                          .fourSwipeUp: .toggleMaximizeWindow, .fourSwipeDown: .minimizeWindow],
               parts: [.fourFingers]),
        Preset(id: "stage-flow", name: "Stage Manager flow",
               summary: "Only while Stage Manager is on: three fingers left/right flip stages, up shows or hides the recent apps, down jumps back to the last stage.",
               parts: [.stageManager],
               stageBindings: [.threeSwipeLeft: .stageSwitcher, .threeSwipeRight: .stageSwitcher,
                               .threeSwipeUp: .toggleStageStrip, .threeSwipeDown: .previousStage])
    ]
}

// MARK: - Saved templates and backups

struct SavedTemplate: Identifiable {
    var id: URL { url }
    let url: URL
    let file: ProfileFile
    let modified: Date
}

struct PendingImport: Identifiable {
    let id = UUID()
    let file: ProfileFile
    let sourceName: String
    /// Actions worth a second look before importing.
    let flagged: [String]
}

/// Tabs on the Profiles page.
enum ProfileTab: String, CaseIterable, Identifiable {
    case ready, templates, imported
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ready: return "Ready-made"
        case .templates: return "My combos"
        case .imported: return "Imported"
        }
    }
}

final class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    @Published private(set) var templates: [SavedTemplate] = []
    @Published private(set) var imported: [SavedTemplate] = []
    @Published private(set) var backups: [URL] = []
    @Published var pending: PendingImport?
    /// Shown as a banner on the Combos page; fades by itself after a few seconds.
    @Published var message: String? {
        didSet {
            guard let m = message, m != oldValue else { return }
            Log.info("Combos: " + m)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                if self?.message == m { self?.message = nil }
            }
        }
    }
    @Published var tab: ProfileTab = .ready

    let profilesDir: URL
    let importedDir: URL
    let backupsDir: URL
    let baseDir: URL
    private var store: SettingsStore { SettingsStore.shared }

    private init() {
        baseDir = SettingsStore.shared.fileURL.deletingLastPathComponent()
        profilesDir = baseDir.appendingPathComponent("Profiles", isDirectory: true)
        importedDir = profilesDir.appendingPathComponent("Imported", isDirectory: true)
        backupsDir = baseDir.appendingPathComponent("Backups", isDirectory: true)
        for dir in [profilesDir, importedDir, backupsDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        reload()
    }

    private func loadProfiles(in dir: URL) -> [SavedTemplate] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension.lowercased() == "tpt" }.compactMap { url in
            guard let f = try? ProfileValidator.load(url) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return SavedTemplate(url: url, file: f, modified: date)
        }.sorted { $0.file.name.localizedCompare($1.file.name) == .orderedAscending }
    }

    func reload() {
        let fm = FileManager.default
        templates = loadProfiles(in: profilesDir)
        imported = loadProfiles(in: importedDir)
        backups = ((try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: Current setup → file

    /// The current setup as a combo, holding only `parts` (nil = everything).
    func currentFile(named name: String, note: String? = nil, parts: Set<ComboPart>? = nil) -> ProfileFile {
        let full = completeFile(named: name, note: note)
        return parts.map { full.keeping($0) } ?? full
    }

    /// Every part of the current setup, with the parts listed.
    private func completeFile(named name: String, note: String?) -> ProfileFile {
        let s = store.settings
        var f = ProfileFile(name: name, note: note, createdWith: AppInfo.version, created: Date())
        f.modules = s.modules
        f.bindings = s.bindings.mapValues(Self.portable)
        f.stageSetOn = s.stageSetOn
        f.stageBindings = s.stageBindings.mapValues(Self.portable)
        f.cornerSizes = s.cornerSizes
        f.apps = s.apps.mapValues { app in
            AppProfile(name: app.name, path: nil, bindings: app.bindings.mapValues(Self.portable))
        }
        f.keyShortcuts = s.keyShortcuts.map { k in
            var k = k
            k.action = Self.portable(k.action)
            return k
        }
        f.parts = ComboPart.allCases.map(\.rawValue)
        return f
    }

    /// Replaces a file path with the app's identifier, so exports never reveal folders.
    private static func portable(_ c: ActionConfig) -> ActionConfig {
        var c = c
        if let p = c.appPath {
            if c.appID == nil { c.appID = Bundle(path: p)?.bundleIdentifier }
            c.appPath = nil
        }
        return c
    }

    private func encode(_ f: ProfileFile) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(f)
    }

    // MARK: Save, export, import

    /// Saves the chosen parts of the current setup under My combos.
    func saveCombo(name: String, note: String?, parts: Set<ComboPart>) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let url = uniqueURL(in: profilesDir, name: clean)
        do {
            try encode(currentFile(named: clean, note: note, parts: parts)).write(to: url, options: .atomic)
            message = "Saved “\(clean)” to My combos."
            tab = .templates
        } catch {
            message = "Couldn’t save the combo: \(error.localizedDescription)"
        }
        reload()
    }

    /// Writes a combo as it is (from the lists) to a .tpt file.
    func export(_ file: ProfileFile, to url: URL) {
        do {
            try encode(file).write(to: url, options: .atomic)
            message = "Exported “\(file.name)” to \(url.lastPathComponent)."
        } catch {
            message = "Couldn’t export: \(error.localizedDescription)"
        }
    }

    func export(to url: URL, name: String, note: String?, parts: Set<ComboPart>) {
        do {
            try encode(currentFile(named: name, note: note, parts: parts)).write(to: url, options: .atomic)
            message = "Exported “\(name)” to \(url.lastPathComponent)."
        } catch {
            message = "Couldn’t export: \(error.localizedDescription)"
        }
    }

    /// Reads a file and opens the review sheet. Nothing changes until you confirm.
    func beginImport(_ url: URL) {
        Log.breadcrumb("Combos: reviewing \(url.lastPathComponent)")
        do {
            let f = try ProfileValidator.load(url)
            pending = PendingImport(file: f, sourceName: url.lastPathComponent, flagged: flags(in: f))
            message = nil
        } catch {
            pending = nil
            message = "“\(url.lastPathComponent)” wasn’t imported. \(error.localizedDescription)"
        }
    }

    /// Adds the chosen parts of the reviewed combo to the Imported tab, and
    /// optionally uses them right away. The checked, cleaned-up version is
    /// stored, not the original file.
    func addPending(andUse use: Bool, parts: Set<ComboPart>, keepRest: Bool, skipApps: Set<String> = []) {
        guard let p = pending, !parts.isEmpty else { return }
        pending = nil
        var file = p.file.keeping(parts)
        for id in skipApps { file.apps[id] = nil }
        let url = uniqueURL(in: importedDir, name: file.name)
        do {
            try encode(file).write(to: url, options: .atomic)
        } catch {
            message = "Couldn’t add “\(file.name)”: \(error.localizedDescription)"
            return
        }
        tab = .imported
        reload()
        if use {
            apply(file, keepRest: keepRest, label: "Imported and now using “\(file.name)”.")
        } else {
            message = "Added “\(file.name)” to Imported. Click Use when you want it."
        }
    }

    /// A file name in `dir` that doesn't overwrite an existing profile.
    private func uniqueURL(in dir: URL, name: String) -> URL {
        let base = Self.fileName(name)
        var url = dir.appendingPathComponent(base).appendingPathExtension("tpt")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension("tpt")
            n += 1
        }
        return url
    }

    /// Opens the cheat sheet for a saved or imported profile.
    func openCheatSheet(for file: ProfileFile) {
        Log.breadcrumb("Combos: cheat sheet for “\(file.name)”")
        let url = baseDir.appendingPathComponent("Cheat sheet – \(Self.fileName(file.name)).html")
        do {
            try CheatSheet.html(for: file).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } catch {
            message = "Couldn’t make the cheat sheet: \(error.localizedDescription)"
        }
    }

    func applyTemplate(_ t: SavedTemplate, keepRest: Bool) {
        apply(t.file, keepRest: keepRest, label: "Now using “\(t.file.name)”.")
    }

    func applyPreset(_ p: Preset, keepRest: Bool) {
        apply(p.file, keepRest: keepRest, label: "Now using “\(p.name)”.")
    }

    func deleteTemplate(_ t: SavedTemplate) {
        NSWorkspace.shared.recycle([t.url]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
    }

    /// Uses a combo. Each part it holds replaces that part of your setup
    /// completely (a gesture the combo leaves out goes back to macOS
    /// default). With `keepRest`, everything else stays as it is; without,
    /// everything else goes back to the defaults. Backs up first.
    private func apply(_ f: ProfileFile, keepRest: Bool, label: String) {
        backUp()
        var s = store.settings
        if !keepRest {
            s.bindings = [:]
            s.stageSetOn = false
            s.stageBindings = [:]
            s.cornerSizes = [:]
            s.apps = [:]
            s.keyShortcuts = []
            for m in ModuleID.allCases { s.modules[m.rawValue] = m.defaultOn }
        }
        let parts = f.partSet
        for part in parts {
            switch part {
            case .stageManager:
                s.stageSetOn = f.stageSetOn ?? !(f.stageBindings ?? [:]).isEmpty
                s.stageBindings = (f.stageBindings ?? [:]).mapValues(Self.localized)
            case .shortcuts:
                s.keyShortcuts = (f.keyShortcuts ?? []).map { k in
                    var k = k
                    k.action = Self.localized(k.action)
                    return k
                }
            case .perApp:
                s.apps = [:]
                for (id, app) in f.apps {
                    let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
                    s.apps[id] = AppProfile(name: app.name, path: path, bindings: app.bindings.mapValues(Self.localized))
                }
            default:
                for g in part.gestures {
                    s.bindings[g.key] = f.bindings[g.key].map(Self.localized)
                }
                if part == .cornerClicks { s.cornerSizes = f.cornerSizes ?? [:] }
            }
        }
        // A complete combo used on its own brings its module switches along;
        // otherwise only switch on what the combo needs.
        if parts == Set(ComboPart.allCases) && !keepRest {
            for m in ModuleID.allCases { s.modules[m.rawValue] = f.modules[m.rawValue] ?? m.defaultOn }
        } else {
            for m in f.neededModules { s.modules[m.rawValue] = true }
        }
        store.settings = s
        message = label + " Your previous setup was backed up."
        reload()
    }

    /// Finds the app on this Mac for an "Open app" action.
    private static func localized(_ c: ActionConfig) -> ActionConfig {
        var c = c
        if c.appPath == nil, let id = c.appID {
            c.appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
        }
        return c
    }

    // MARK: Backups

    private static let backupNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Saves the current settings and keeps the newest 10 backups. The
    /// caller reloads the lists afterwards (once).
    private func backUp() {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(store.settings) else { return }
        // Milliseconds too, so two changes in the same second don't overwrite
        // each other's backup (which made Undo skip a step).
        let millis = Int(Date().timeIntervalSince1970 * 1000) % 1000
        let name = "settings-\(Self.backupNameFormatter.string(from: Date()))-\(String(format: "%03d", millis)).json"
        try? data.write(to: backupsDir.appendingPathComponent(name), options: .atomic)
        let all = ((try? FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in all.dropFirst(10) { try? FileManager.default.removeItem(at: old) }
    }

    func undoLast() {
        guard let latest = backups.first,
              let data = try? Data(contentsOf: latest),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else {
            message = "There’s no backup to go back to."
            return
        }
        store.settings = s
        try? FileManager.default.removeItem(at: latest)
        message = "Went back to your previous setup."
        reload()
    }

    private static let backupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var lastBackupDate: String? {
        guard let name = backups.first?.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "settings-", with: "") else { return nil }
        guard let d = Self.backupNameFormatter.date(from: String(name.prefix(15))) else { return nil }
        return Self.backupDateFormatter.string(from: d)
    }

    // MARK: Review

    /// What deserves a look before importing: things that open apps or press keys.
    func flags(in f: ProfileFile) -> [String] {
        var out: [String] = []
        func scan(_ bindings: [String: ActionConfig], where place: String) {
            for (key, c) in bindings.sorted(by: { $0.key < $1.key }) {
                guard let g = Gesture(rawValue: key) else { continue }
                switch c.kind {
                case .openApp:
                    let installed = c.appID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                    let name = installed.map { FileManager.default.displayName(atPath: $0.path) } ?? (c.appID ?? "an app")
                    out.append("\(g.fullTitle)\(place): opens \(name)\(installed == nil ? " (not installed)" : "")")
                case .keyboardShortcut:
                    out.append("\(g.fullTitle)\(place): presses \(c.shortcut?.display ?? "a shortcut")")
                case .forceQuit:
                    out.append("\(g.fullTitle)\(place): opens the Force Quit window")
                default: break
                }
            }
        }
        scan(f.bindings, where: "")
        scan(f.stageBindings ?? [:], where: " with Stage Manager on")
        for (_, app) in f.apps.sorted(by: { $0.key < $1.key }) { scan(app.bindings, where: " in \(app.name)") }
        for k in f.keyShortcuts ?? [] where k.action.kind != .macDefault {
            if let s = k.shortcut { out.append("Keyboard \(s.display), in every app: \(k.action.readable)") }
        }
        return out
    }

    private static func fileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return String(cleaned.prefix(60))
    }

    // MARK: Cheat sheet

    /// Writes the cheat sheet for the current setup and opens it in the browser.
    func openCheatSheet() {
        let url = baseDir.appendingPathComponent("Cheat sheet.html")
        do {
            try CheatSheet.html(for: currentFile(named: "My TrackpadTool setup")).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } catch {
            message = "Couldn’t make the cheat sheet: \(error.localizedDescription)"
        }
    }

    func exportCheatSheet(to url: URL, for file: ProfileFile) {
        do {
            try CheatSheet.html(for: file).write(to: url, atomically: true, encoding: .utf8)
            message = "Saved the cheat sheet as \(url.lastPathComponent)."
        } catch {
            message = "Couldn’t save the cheat sheet: \(error.localizedDescription)"
        }
    }
}

// MARK: - Cheat sheet

extension Gesture {
    var fullTitle: String { "\(group.title) · \(title)" }
}

extension ActionConfig {
    /// One line for the cheat sheet and the review screen.
    var readable: String {
        switch kind {
        case .keyboardShortcut: return "Keyboard shortcut \(shortcut?.display ?? "(not recorded)")"
        case .openApp:
            if let url = resolvedAppURL { return "Open \(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))" }
            return "Open app \(appID ?? "")"
        default: return kind.title
        }
    }
}

enum CheatSheet {
    /// A self-contained HTML page listing what each gesture does in a profile.
    static func html(for f: ProfileFile) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func isOn(_ m: ModuleID?) -> Bool { m.map { f.modules[$0.rawValue] ?? $0.defaultOn } ?? true }
        func rows(_ bindings: [String: ActionConfig]) -> String {
            var html = ""
            for group in GestureGroup.allCases where isOn(group.module) {
                let used = group.gestures.compactMap { g -> (Gesture, ActionConfig)? in
                    guard let c = bindings[g.key], c.kind != .macDefault, isOn(c.kind.module) else { return nil }
                    return (g, c)
                }
                guard !used.isEmpty else { continue }
                html += "<h3>\(esc(group.title))</h3><table>"
                for (g, c) in used {
                    html += "<tr><td class=g>\(esc(g.title))</td><td><b>\(esc(c.readable))</b><div class=what>\(esc(c.explanation(for: g)))</div></td></tr>"
                }
                html += "</table>"
            }
            return html.isEmpty ? "<p class=muted>No gestures set — everything uses macOS's own behavior.</p>" : html
        }
        let date = DateFormatter.localizedString(from: f.created ?? Date(), dateStyle: .long, timeStyle: .none)
        var body = "<h1>\(esc(f.name))</h1><p class=muted>TrackpadTool \(esc(f.createdWith ?? AppInfo.version)) · \(esc(date))</p>"
        if let note = f.note, !note.isEmpty { body += "<p>\(esc(note))</p>" }
        body += "<p class=muted>\(esc(f.contentsSummary))</p>"
        body += "<h2>All apps</h2>" + rows(f.bindings)
        if isOn(.stageManager), f.stageSetOn == true, let stage = f.stageBindings, !stage.isEmpty {
            body += "<h2>While Stage Manager is on</h2><p class=muted>These replace the gestures above while Stage Manager is on.</p>" + rows(stage)
        }
        if isOn(.perAppGestures) {
            for (_, app) in f.apps.sorted(by: { $0.value.name < $1.value.name }) where !app.bindings.isEmpty {
                body += "<h2>In \(esc(app.name))</h2><p class=muted>These replace the all-apps setup in this app.</p>" + rows(app.bindings)
            }
        }
        let keys = (f.keyShortcuts ?? []).filter { $0.shortcut != nil && $0.action.kind != .macDefault }
        if !keys.isEmpty {
            body += "<h2>Keyboard shortcuts</h2><table>"
            for k in keys {
                body += "<tr><td class=g>\(esc(k.shortcut?.display ?? ""))</td><td><b>\(esc(k.action.readable))</b><div class=what>\(esc(k.action.explanation(for: .threeClick)))</div></td></tr>"
            }
            body += "</table>"
        }
        let on = ModuleID.allCases.filter { isOn($0) }.map { esc($0.title) }.joined(separator: " · ")
        body += "<h2>Modules on</h2><p>\(on)</p><p class=muted>Gestures left on “macOS default” are not listed.</p>"
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>\(esc(f.name)) – TrackpadTool cheat sheet</title>
        <style>
        body{font:15px -apple-system,system-ui,sans-serif;max-width:720px;margin:40px auto;padding:0 20px;color:#1d1d1f;background:#fff}
        h1{font-size:28px;margin:0 0 4px}h2{font-size:19px;margin:32px 0 8px}h3{font-size:13px;text-transform:none;color:#6e6e73;margin:18px 0 6px}
        table{width:100%;border-collapse:collapse}td{padding:7px 10px;border-bottom:1px solid #e5e5ea;vertical-align:top}td.g{width:40%;font-weight:600}
        .muted{color:#6e6e73;font-size:13px}.what{color:#3a3a3c;font-size:13.5px;margin-top:2px}
        @media (prefers-color-scheme:dark){body{background:#1c1c1e;color:#f5f5f7}td{border-color:#38383a}.muted,h3{color:#98989d}.what{color:#c7c7cc}}
        @media print{body{margin:0}}
        </style></head><body>\(body)</body></html>
        """
    }
}
