import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

enum Pane: String, CaseIterable, Identifiable {
    case gestures, shortcuts, gestureSettings, modules, stageManager, profiles, permissions, general

    var id: Self { self }

    var title: String {
        switch self {
        case .gestures: return "Gestures"
        case .shortcuts: return "Shortcuts"
        case .gestureSettings: return "Gesture settings"
        case .modules: return "Modules"
        case .permissions: return "Permissions"
        case .general: return "General"
        case .profiles: return "Combos"
        case .stageManager: return "Stage Manager"
        }
    }

    var symbol: String {
        switch self {
        case .gestures: return "hand.point.up.left"
        case .shortcuts: return "command"
        case .gestureSettings: return "slider.horizontal.3"
        case .modules: return "square.grid.2x2"
        case .permissions: return "lock"
        case .general: return "gearshape"
        case .profiles: return "square.stack.3d.down.right"
        case .stageManager: return "squares.leading.rectangle"
        }
    }
}

/// Polls the things macOS doesn't notify us about.
final class StatusWatcher: ObservableObject {
    /// One for the whole app (the dropdown and the settings window share it).
    static let shared = StatusWatcher()

    @Published var accessibilityTrusted = AX.isTrusted
    @Published var listening = GestureEngine.shared.isListening
    @Published var stageManagerOn = StageManager.isOn
    private var timer: Timer?
    /// Windows that show this status right now; the check only runs while
    /// one is open, so TrackpadTool doesn't wake the Mac for nothing.
    private var viewers = Set<String>()

    private init() {}

    func watch(_ viewer: String, _ on: Bool) {
        if on { viewers.insert(viewer) } else { viewers.remove(viewer) }
        if viewers.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        }
    }

    /// Only publishes real changes: every publish redraws every open page,
    /// and would close a menu you have open.
    private func refresh() {
        let trusted = AX.isTrusted, listening = GestureEngine.shared.isListening, stage = StageManager.isOn
        if accessibilityTrusted != trusted { accessibilityTrusted = trusted }
        if self.listening != listening { self.listening = listening }
        if stageManagerOn != stage { stageManagerOn = stage }
    }

    deinit { timer?.invalidate() }
}

/// Which settings page is showing, and which app the Gestures page edits.
/// (A class instead of @State, because the @State macro needs full Xcode
/// and this builds with the Command Line Tools.)
final class NavigationModel: ObservableObject {
    static let shared = NavigationModel()
    @Published var pane: Pane? = .gestures {
        didSet { if pane != oldValue { Log.breadcrumb("Settings page: \(pane?.title ?? "none")") } }
    }
    /// Bundle identifier of the app being edited; nil = all apps.
    @Published var app: String?
    /// The force press calibration sheet is open.
    @Published var calibratingForce = false
}

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @ObservedObject private var status = StatusWatcher.shared
    @ObservedObject private var nav = NavigationModel.shared

    /// Gesture settings and Permissions are part of General; Shortcuts and
    /// Stage Manager only show in Advanced mode.
    private func showsInSidebar(_ p: Pane) -> Bool {
        switch p {
        case .gestureSettings, .permissions: return false
        case .shortcuts: return store.settings.advancedMode
        case .stageManager: return store.isOn(.stageManager) && store.settings.advancedMode
        default: return true
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases.filter(showsInSidebar), selection: $nav.pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            switch nav.pane ?? .gestures {
            case .gestures: GesturesPane(status: status, nav: nav)
            case .shortcuts:
                if store.settings.advancedMode { ShortcutsPane() } else { GeneralPane(status: status, nav: nav) }
            case .modules: ModulesPane(status: status)
            // Gesture settings and permissions now live on the General page.
            case .general, .gestureSettings, .permissions: GeneralPane(status: status, nav: nav)
            case .profiles: ProfilesPane()
            case .stageManager: StageManagerPane(status: status, nav: nav)
            }
        }
        .frame(minWidth: 820, minHeight: 640)
    }
}

struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 22)
    }
}

// MARK: - Gestures

struct GesturesPane: View {
    @EnvironmentObject var store: SettingsStore
    @ObservedObject var status: StatusWatcher
    @ObservedObject var nav: NavigationModel
    @StateObject private var conflicts = ConflictChecker()

    /// What's being edited: nil = the normal setup, Settings.stageScope =
    /// the Stage Manager setup, otherwise an app (Advanced mode only).
    private var app: String? {
        guard let id = nav.app else { return nil }
        if id == Settings.stageScope { return store.stageSetEnabled ? id : nil }
        guard perAppEditable, store.settings.apps[id] != nil else { return nil }
        return id
    }

    private var perAppEditable: Bool { store.settings.advancedMode && store.isOn(.perAppGestures) }
    private var showsScope: Bool { perAppEditable || store.stageSetEnabled }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Gestures",
                       subtitle: "Pick what each trackpad gesture does. “macOS default” leaves it untouched.")
            Form {
                if !store.settings.enabled {
                    Section {
                        HStack {
                            Label("Gestures are paused", systemImage: "pause.circle")
                            Spacer()
                            Button("Turn on") { store.settings.enabled = true }
                        }
                    }
                }
                if !status.accessibilityTrusted {
                    Section {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "lock.trianglebadge.exclamationmark")
                                .foregroundStyle(.orange)
                            Text("TrackpadTool needs Accessibility permission to switch and snap windows and send shortcuts. Without it, those gestures only show a reminder.")
                                .font(.callout)
                            Spacer()
                            Button("Allow…") { AX.requestTrust(); ConflictChecker.openAccessibilitySettings() }
                        }
                    }
                }
                let issues = conflicts.issues(store: store)
                if !issues.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("\(issues.count) gesture\(issues.count == 1 ? " clashes" : "s clash") with macOS")
                                .font(.callout)
                            Spacer()
                            Button("Show") { nav.pane = .general }
                        }
                    }
                }

                if showsScope {
                    Section {
                        HStack {
                            Picker("Gestures for", selection: scopeBinding) {
                                Text(perAppEditable ? "All apps" : "Normal").tag("")
                                if store.stageSetEnabled {
                                    Text("While Stage Manager is on").tag(Settings.stageScope)
                                }
                                if perAppEditable {
                                    if !store.sortedApps.isEmpty { Divider() }
                                    ForEach(store.sortedApps) { entry in
                                        Text(AppPresence.isInstalled(entry.id) ? entry.profile.name
                                             : "\(entry.profile.name) (waiting until installed)").tag(entry.id)
                                    }
                                    Divider()
                                    Text("Add an app…").tag("+add")
                                }
                            }
                            .pickerStyle(.menu)
                            if let app = app, app != Settings.stageScope {
                                Button("Remove this app") {
                                    store.removeApp(app)
                                    nav.app = nil
                                }
                            }
                        }
                        if app == Settings.stageScope {
                            Text("Changes here apply only while Stage Manager is on. Gestures left on “Same as normal” use your normal setup.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let app = app, let name = store.settings.apps[app]?.name {
                            Text(AppPresence.isInstalled(app)
                                 ? "Changes here apply only in \(name). Gestures left on “Same as all apps” follow your all-apps setup."
                                 : "\(name) isn't on this Mac. This setup waits and starts working if you install it.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if !perAppEditable && hiddenAppSetups > 0 {
                            Text("Your \(hiddenAppSetups) per-app setup\(hiddenAppSetups == 1 ? "" : "s") still work. Turn on Advanced mode in General to see or change them.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if hiddenAppSetups > 0 {
                    Section {
                        Text("Your \(hiddenAppSetups) per-app setup\(hiddenAppSetups == 1 ? "" : "s") still work. Turn on Advanced mode in General to see or change them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                ForEach(GestureGroup.allCases) { group in
                    if group == .forcePress && !store.isOn(.forcePress) && store.settings.advancedMode {
                        Section("Force press") {
                            LabeledContent {
                                Text("macOS default (Look Up)").foregroundStyle(.secondary)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Force press")
                                        Text("Turn on the Force press module to give it an action")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "hand.tap")
                                }
                            }
                        }
                    } else if store.showsGroup(group) {
                        Section {
                            ForEach(group.gestures) { gesture in
                                GestureRow(gesture: gesture, app: app)
                            }
                        } header: {
                            Text(group.title)
                        } footer: {
                            if let hint = footer(for: group) {
                                Text(hint).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { conflicts.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            conflicts.refresh()
        }
    }

    /// Per-app setups that exist but aren't shown outside Advanced mode.
    private var hiddenAppSetups: Int {
        guard !perAppEditable, store.isOn(.perAppGestures) else { return 0 }
        return store.settings.apps.values.filter { !$0.bindings.isEmpty }.count
    }

    /// One short line per group; the fine-tuning lives on General.
    private func footer(for group: GestureGroup) -> String? {
        switch group {
        case .cornerClicks: return "Corner sizes: General › Gesture settings."
        case .forcePress: return "How hard to press, and matching your Mac’s force click: General › Gesture settings."
        default: return group.hint
        }
    }

    private var scopeBinding: Binding<String> {
        Binding(
            get: { app ?? "" },
            set: { value in
                if value == "+add" {
                    DispatchQueue.main.async { chooseApp() }
                } else {
                    nav.app = value.isEmpty ? nil : value
                }
            }
        )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url, let id = store.addApp(at: url) {
            nav.app = id
        }
    }
}

struct GestureRow: View {
    @EnvironmentObject var store: SettingsStore
    let gesture: Gesture
    /// nil = editing "all apps".
    let app: String?

    var body: some View {
        let stored = store.storedConfig(for: gesture, app: app)
        let global = store.globalConfig(for: gesture)
        let editable: ActionConfig? = app == nil ? global : stored
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                ActionMenu(gesture: gesture,
                           current: app != nil && stored == nil ? nil : (stored ?? global).kind,
                           inheritTitle: app == nil ? nil : "\(inheritName) (\(global.kind.title))",
                           onSelect: select)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gesture.title)
                        Text(app != nil && stored == nil ? "Follows your \(app == Settings.stageScope ? "normal" : "all-apps") setup" : subtitle(stored ?? global))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: gesture.symbol)
                }
            }

            if editable?.kind == .keyboardShortcut {
                HStack {
                    Text("Shortcut").foregroundStyle(.secondary)
                    Spacer()
                    ShortcutRecorderButton(shortcut: shortcutBinding)
                }
                .padding(.leading, 28)
            }
            if editable?.kind == .openApp {
                HStack {
                    Text("App").foregroundStyle(.secondary)
                    Spacer()
                    Button(appName(editable) ?? "Choose app…") { chooseApp() }
                }
                .padding(.leading, 28)
            }
        }
    }

    private var inheritName: String {
        app == Settings.stageScope ? "Same as normal" : "Same as all apps"
    }

    private func select(_ kind: ActionKind?) {
        if let kind = kind {
            store.update(gesture, app: app) { $0.kind = kind }
        } else if let app = app {
            store.clearOverride(gesture, app: app)
        }
    }

    private var shortcutBinding: Binding<Shortcut?> {
        Binding(
            get: { store.storedConfig(for: gesture, app: app)?.shortcut },
            set: { newValue in store.update(gesture, app: app) { $0.shortcut = newValue } }
        )
    }

    private func appName(_ config: ActionConfig?) -> String? {
        guard let path = config?.appPath else { return nil }
        return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.update(gesture, app: app) { $0.appPath = url.path }
        }
    }

    private func subtitle(_ config: ActionConfig) -> String {
        let isClick = gesture.isClick || gesture.group == .tipTap || gesture.group == .edgeSwipes || gesture == .forcePress
        switch config.kind {
        case .macDefault: return gesture == .forcePress ? "Look Up, as usual" : "Not changed"
        case .doNothing: return gesture.isClick ? "Click is blocked" : "Ignored"
        case .hideAllApps: return "Like ⌘H in every app at once"
        case .restoreHiddenApps: return "Brings back what was hidden"
        case .windowSwitcher: return isClick ? "Jumps to your previous app" : "Like ⌘Tab: hold to browse, lift to switch"
        case .minimizeAllWindows: return "Every window goes into the Dock"
        case .minimizeWindow: return "Sends the front window to the Dock"
        case .restoreMinimizedWindow: return "Brings back the last window you minimized"
        case .toggleMaximizeWindow: return "Fills the screen; do it again to restore"
        case .maximizeAllWindows: return "Every open window fills its screen"
        case .snapLeft, .snapRight, .snapTop, .snapBottom, .snapTopLeft, .snapTopRight, .snapBottomLeft, .snapBottomRight,
             .snapLeftThird, .snapCenterThird, .snapRightThird, .snapLeftTwoThirds, .snapRightTwoThirds:
            return "Snaps the front window"
        case .maximizeWindow: return "Front window fills the screen"
        case .centerWindow: return "Moves the front window to the middle"
        case .restoreWindowSize: return "Puts a snapped window back as it was"
        case .moveToNextDisplay: return "Sends the front window to your other display"
        case .nextTab: return "Presses ⌘⇧]"
        case .previousTab: return "Presses ⌘⇧["
        case .newTab: return "Presses ⌘T"
        case .closeTab: return "Presses ⌘W"
        case .reopenTab: return "Presses ⌘⇧T"
        case .stageSwitcher: return isClick ? "Jumps to your previous stage" : "Browse stages, lift to switch"
        case .previousStage: return "Jumps back to the stage you used last"
        case .toggleStageManager: return "Switches Stage Manager on or off"
        case .toggleStageStrip: return "Shows or hides the recent apps on the left"
        case .keyboardShortcut: return config.shortcut.map { "Presses \($0.display)" } ?? "No shortcut recorded yet"
        case .openApp: return appName(config).map { "Opens \($0)" } ?? "No app chosen yet"
        case .forceQuit: return "Same as ⌘⌥⎋"
        case .middleClick: return "Clicks the middle mouse button"
        case .copy: return "Presses ⌘C"
        case .paste: return "Presses ⌘V"
        case .cut: return "Presses ⌘X"
        case .undo: return "Presses ⌘Z"
        case .redo: return "Presses ⇧⌘Z"
        case .pasteWithoutFormatting: return "Presses ⌥⇧⌘V"
        case .selectAll: return "Presses ⌘A"
        case .find: return "Presses ⌘F"
        case .findNext: return "Presses ⌘G"
        case .save: return "Presses ⌘S"
        case .newDocument: return "Presses ⌘N"
        case .deleteWord: return "Presses ⌥⌫"
        case .lineStart: return "Presses ⌘←"
        case .lineEnd: return "Presses ⌘→"
        case .documentStart: return "Presses ⌘↑"
        case .documentEnd: return "Presses ⌘↓"
        case .emojiPicker: return "Presses ⌃⌘Space"
        case .screenshotArea: return "Your screenshot shortcut (⇧⌘4)"
        case .playPause: return "Like the ⏯ key"
        case .nextTrack: return "Like the ⏭ key"
        case .previousTrack: return "Like the ⏮ key"
        case .volumeUp, .volumeDown, .mute: return "Like your keyboard's volume keys"
        case .screenshotScreen: return "Your screenshot shortcut (⇧⌘3)"
        case .screenshotWindow: return "Click a window to capture it"
        case .screenshotAreaToClipboard: return "Your shortcut for it (⌃⇧⌘4)"
        case .screenshotScreenToClipboard: return "Your shortcut for it (⌃⇧⌘3)"
        case .screenshotToolbar: return "Your shortcut for it (⇧⌘5)"
        case .missionControl: return "Every window and your Spaces"
        case .appExpose: return "Only the front app's windows"
        case .showDesktop: return "Windows aside; again to bring back"
        case .launchpad: return "Start an app"
        case .previousSpace: return "Your shortcut for it (⌃←)"
        case .nextSpace: return "Your shortcut for it (⌃→)"
        case .spotlight: return "Your Spotlight shortcut (⌘Space)"
        case .lockScreen: return "Presses ⌃⌘Q"
        }
    }
}

// MARK: - Modules

struct ModulesPane: View {
    @EnvironmentObject var store: SettingsStore
    @ObservedObject var status: StatusWatcher

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Modules",
                       subtitle: "Turn features on or off. A switched-off module does nothing at all.")
            Form {
                ForEach(ModuleKind.allCases, id: \.self) { kind in
                    let modules = visible.filter { $0.kind == kind }
                    if !modules.isEmpty {
                        Section {
                            ForEach(modules) { module in
                                moduleRow(module)
                            }
                        } header: {
                            Text(kind.title)
                        } footer: {
                            Text(kind.hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !store.settings.advancedMode {
                    Section {
                        HStack {
                            Text("Advanced mode shows \(hidden.count) more: \(hidden.map(\.title).joined(separator: ", ")).")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Turn on Advanced mode") { store.settings.advancedMode = true }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var visible: [ModuleID] {
        ModuleID.allCases.filter { store.settings.advancedMode || !$0.isAdvanced }
    }

    private var hidden: [ModuleID] {
        ModuleID.allCases.filter { $0.isAdvanced && !store.settings.advancedMode }
    }

    private func moduleRow(_ module: ModuleID) -> some View {
        Toggle(isOn: Binding(
            get: { store.isOn(module) },
            set: { store.setModule(module, on: $0) }
        )) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: module.symbol)
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(module.title).fontWeight(.semibold)
                        if module == .stageManager {
                            Text(status.stageManagerOn ? "On now" : "Off now")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(status.stageManagerOn
                                                           ? Color.green.opacity(0.2)
                                                           : Color.gray.opacity(0.2)))
                        }
                    }
                    Text(module.summary).font(.caption).foregroundStyle(.secondary)
                    if !module.actions.isEmpty {
                        Text(module.actions.filter { store.settings.advancedMode || !$0.isAdvanced }.map { $0.title.replacingOccurrences(of: "…", with: "") }
                                .joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .toggleStyle(.switch)
    }
}

// MARK: - Permissions

/// Permissions, shown on the General page.
struct PermissionsSections: View {
    @ObservedObject var status: StatusWatcher

    var body: some View {
        Section {
            HStack {
                Label("Accessibility", systemImage: "accessibility")
                Spacer()
                if status.accessibilityTrusted {
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Not allowed yet", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                }
            }
            HStack {
                Label("Reading the trackpad", systemImage: "hand.point.up.left")
                Spacer()
                Text(status.listening ? "Active" : "Idle").foregroundStyle(.secondary)
            }
            HStack {
                Button("Ask for access") { AX.requestTrust() }
                Button("Open Accessibility settings") { ConflictChecker.openAccessibilitySettings() }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Accessibility is needed to switch and snap windows, send shortcuts, and catch clicks and force presses. The trackpad is only read while a gesture is set. If gestures stop working after an update, remove TrackpadTool from the Accessibility list and add it again.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - General

final class LoginItemModel: ObservableObject {
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Couldn’t change this: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct GeneralPane: View {
    @EnvironmentObject var store: SettingsStore
    @ObservedObject var status: StatusWatcher
    @ObservedObject var nav: NavigationModel
    @StateObject private var login = LoginItemModel()
    @StateObject private var conflicts = ConflictChecker()

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "General", subtitle: "App behavior, gesture fine-tuning and permissions.")
            Form {
                Section {
                    Toggle("Gestures on", isOn: $store.settings.enabled)
                    Toggle(isOn: $store.settings.advancedMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Advanced mode")
                            Text("Shows every action and module, per-app gestures, shortcuts and open-app actions. Off keeps the lists short; anything you already set up keeps working.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Also show icon in Dock", isOn: $store.settings.showInDock)
                    Toggle("Open at login", isOn: Binding(
                        get: { login.openAtLogin },
                        set: { login.set($0) }
                    ))
                    if let error = login.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                GestureSettingsSections(nav: nav, conflicts: conflicts)
                PermissionsSections(status: status)
                Section {
                    Button("Restore the default setup") { store.resetToDefaults() }
                    Button("Show settings file in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
                Section {
                    if Log.previousSessionEndedUnexpectedly {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("TrackpadTool stopped unexpectedly last time (a crash, a freeze or Force Quit). The log has the details.")
                                .font(.callout)
                        }
                    }
                    HStack {
                        Button("Open log") { NSWorkspace.shared.open(Log.fileURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
                        Button("Copy log") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Log.tail(lines: 400), forType: .string)
                            GlassHUD.shared.show(symbol: "doc.on.doc", text: "Last 400 log lines copied")
                        }
                        Button("Clear log") { Log.clear() }
                    }
                } header: {
                    Text("Error log")
                } footer: {
                    Text("Kept in ~/Library/Logs/TrackpadTool. It records errors, crashes, freezes and what TrackpadTool was doing just before, so a problem can be traced. It stays on your Mac unless you share it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Version", value: AppInfo.version)
                    LabeledContent("Developer", value: "SherrySideBurns")
                    LabeledContent("Source code and updates") {
                        Link("GitHub", destination: AppInfo.website)
                    }
                    Button("Show welcome screen again") { (NSApp.delegate as? AppDelegate)?.showWelcome() }
                    Button("Quit TrackpadTool") { NSApp.terminate(nil) }
                } header: {
                    Text("About")
                }
            }
            .formStyle(.grouped)
        }
        .sheet(isPresented: $nav.calibratingForce) {
            ForceCalibrationSheet { value in
                if let value = value {
                    store.settings.forceCalibration = value
                    store.settings.forceStrength = .matchMac
                    Log.info(String(format: "Force press calibrated: macOS force-clicks at %.0f", value))
                }
                nav.calibratingForce = false
            }
        }
        .onAppear { conflicts.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            conflicts.refresh()
        }
    }
}

// MARK: - Gesture settings

/// The fine-tuning that used to sit between the gestures: corner sizes,
/// force press strength and calibration, and clashes with macOS gestures.
struct GestureSettingsSections: View {
    @EnvironmentObject var store: SettingsStore
    @ObservedObject var nav: NavigationModel
    @ObservedObject var conflicts: ConflictChecker

    var body: some View {
                Section {
                    if store.isOn(.cornerClicks) {
                        CornerSettingsRow()
                    } else {
                        moduleOff("Corner clicks")
                    }
                } header: {
                    Text("Corners")
                } footer: {
                    Text("How much of each trackpad corner counts as a corner click. Off always clicks normally.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // Force press is an Advanced feature; its settings show when it's in use.
                if store.settings.advancedMode || store.showsGroup(.forcePress) {
                    Section {
                        if store.isOn(.forcePress) {
                            HStack {
                                Picker("Force needed", selection: $store.settings.forceStrength) {
                                    ForEach(ForceStrength.allCases.filter { $0 != .matchMac || store.settings.forceCalibration != nil }) { s in
                                        Text(s.title).tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)
                                Button("Calibrate…") { nav.calibratingForce = true }
                            }
                        } else {
                            moduleOff("Force press")
                        }
                    } header: {
                        Text("Force press")
                    } footer: {
                        Text("Calibrate once (force click a pad three times) so the action happens together with your Mac’s force-click buzz: that’s “Match macOS”. Light, Medium and Firm instead use how much harder than a normal click you press. Set “Look up & data detectors” to “Tap with three fingers” or Off in Trackpad settings, or Look Up may pop up as well.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    let issues = conflicts.issues(store: store)
                    if issues.isEmpty {
                        Label("No clashes: macOS doesn’t use any gesture you’ve set.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(issues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Open Trackpad settings") { ConflictChecker.openTrackpadSettings() }
                    }
                } header: {
                    Text("Clashes with macOS")
                } footer: {
                    Text("When macOS uses the same gesture, both react. Switch it off in Trackpad settings to leave it to TrackpadTool.")
                        .font(.caption).foregroundStyle(.secondary)
                }
    }

    private func moduleOff(_ name: String) -> some View {
        HStack {
            Text("The \(name) module is off.").foregroundStyle(.secondary)
            Spacer()
            Button("Modules…") { nav.pane = .modules }
        }
    }
}

/// Whether an app is installed on this Mac, by bundle identifier. Cached
/// for a minute, since views ask on every redraw.
enum AppPresence {
    private static var cache: [String: (installed: Bool, at: Date)] = [:]

    static func isInstalled(_ bundleID: String) -> Bool {
        if let hit = cache[bundleID], Date().timeIntervalSince(hit.at) < 60 { return hit.installed }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        cache[bundleID] = (installed, Date())
        return installed
    }
}
