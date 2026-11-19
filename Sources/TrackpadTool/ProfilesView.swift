import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Combos: ready-made combos, your own, imported ones; export
/// and import whole setups or single parts as .tpt files.
struct ProfilesPane: View {
    @ObservedObject private var manager = ProfileManager.shared
    @StateObject private var ui = CombosUI()

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Combos",
                       subtitle: "Gesture setups, whole or in parts. Save your own, mix them, share them.")
            HStack(spacing: 8) {
                Button("Save as combo…") { ui.compose(.save) }
                Button("Import…") { importFile() }
                Menu {
                    Button("Export combo…") { ui.compose(.export) }
                    Divider()
                    Button("Open cheat sheet") { manager.openCheatSheet() }
                    Button("Save cheat sheet…") { saveCheatSheet() }
                    if let date = manager.lastBackupDate {
                        Divider()
                        Button("Undo last change (backup from \(date))") { manager.undoLast() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Picker("", selection: $manager.tab) {
                    ForEach(ProfileTab.allCases) { tab in
                        Text(tabLabel(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Form {
                switch manager.tab {
                case .ready:
                    Section("Complete setups") {
                        ForEach(Preset.all.filter { $0.parts == nil }) { presetRow($0) }
                    }
                    Section {
                        ForEach(Preset.all.filter { $0.parts != nil }) { presetRow($0) }
                    } header: {
                        Text("Small combos")
                    } footer: {
                        Text("Small combos change one part and leave the rest of your setup alone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .templates:
                    Section {
                        if manager.templates.isEmpty {
                            Text("No combos yet: “Save as combo…” keeps your setup, or part of it.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(manager.templates) { t in
                            savedRow(t, detail: "Saved \(t.modified.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                case .imported:
                    Section {
                        if manager.imported.isEmpty {
                            Text("Nothing imported yet: use “Import…” or double-click a .tpt file.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(manager.imported) { t in
                            savedRow(t, detail: "Imported \(t.modified.formatted(date: .abbreviated, time: .shortened))"
                                     + (t.file.createdWith.map { " · made with TrackpadTool \($0)" } ?? ""))
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .overlay(alignment: .bottom) {
            if let message = manager.message {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    Text(message).font(.callout).lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 6, y: 2)
                .padding(.bottom, 16)
                .onTapGesture { manager.message = nil }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: manager.message)
        .onAppear { manager.reload() }
        .sheet(item: $manager.pending) { pending in
            ImportReview(pending: pending)
        }
        .sheet(item: $ui.composer) { composer in
            ComposeSheet(model: composer) { done in
                ui.composer = nil
                if done { DispatchQueue.main.async { finish(composer) } }
            }
        }
    }

    private func tabLabel(_ tab: ProfileTab) -> String {
        switch tab {
        case .ready: return tab.title
        case .templates: return "\(tab.title) (\(manager.templates.count))"
        case .imported: return "\(tab.title) (\(manager.imported.count))"
        }
    }

    private func presetRow(_ preset: Preset) -> some View {
        let file = Preset.file(for: preset)
        return comboRow(key: "preset:" + preset.id, name: preset.name, note: preset.summary, detail: nil, file: file) {
            confirmUse(file) { keep in manager.applyPreset(preset, keepRest: keep) }
        } menu: {
            Button("Cheat sheet") { manager.openCheatSheet(for: file) }
            Button("Export…") { exportCopy(of: file) }
        }
    }

    private func savedRow(_ t: SavedTemplate, detail: String) -> some View {
        comboRow(key: "file:" + t.url.path, name: t.file.name, note: t.file.note, detail: detail, file: t.file) {
            confirmUse(t.file) { keep in manager.applyTemplate(t, keepRest: keep) }
        } menu: {
            Button("Cheat sheet") { manager.openCheatSheet(for: t.file) }
            Button("Export…") { exportCopy(of: t.file) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([t.url]) }
            Divider()
            Button("Delete (moves to Trash)") { manager.deleteTemplate(t) }
        }
    }

    /// One combo: name, part icons and note; Use and a ⋯ menu. Click the
    /// row to fold the details open.
    private func comboRow<Items: View>(key: String, name: String, note: String?, detail: String?, file: ProfileFile,
                                       use: @escaping () -> Void, @ViewBuilder menu: () -> Items) -> some View {
        let open = ui.expanded.contains(key)
        let items = menu()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name).fontWeight(.semibold)
                        PartIcons(file: file)
                    }
                    if let note = note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(open ? nil : 1)
                    }
                }
                Spacer()
                Button("Use", action: use)
                Menu { items } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            .contentShape(Rectangle())
            .onTapGesture { ui.toggle(key) }
            if open {
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.contentsSummary).font(.caption)
                    if let detail = detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 2)
    }

    private func exportCopy(of file: ProfileFile) {
        Log.breadcrumb("Combos: export “\(file.name)”")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.trackpadToolProfile]
        panel.nameFieldStringValue = "\(file.name).tpt"
        if panel.runModal() == .OK, let url = panel.url {
            manager.export(file, to: url)
        }
    }

    // MARK: Actions

    /// Asks before using a combo, with the choice to keep or reset the rest.
    private func confirmUse(_ file: ProfileFile, _ apply: @escaping (_ keepRest: Bool) -> Void) {
        Log.breadcrumb("Combos: Use “\(file.name)”")
        let parts = file.orderedParts
        let alert = NSAlert()
        alert.messageText = "Use “\(file.name)”?"
        // Files placed straight into the Imported folder never went through
        // the import review, so the things worth checking are listed here too.
        let flags = manager.flags(in: file)
        let check = flags.isEmpty ? "" : "\n\nCheck these first:\n• " + flags.joined(separator: "\n• ")
        alert.informativeText = "This replaces: \(parts.map(\.title).joined(separator: ", ")).\n\nYour current setup is backed up first, so you can undo it.\(check)"
        let box = NSButton(checkboxWithTitle: "Reset everything else to macOS default", target: nil, action: nil)
        box.state = .off
        alert.accessoryView = box
        alert.addButton(withTitle: "Use")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { apply(box.state == .off) }
    }

    private func finish(_ composer: ComposerModel) {
        let name = composer.name.trimmingCharacters(in: .whitespaces)
        let note = composer.note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch composer.mode {
        case .save:
            manager.saveCombo(name: name, note: note.isEmpty ? nil : note, parts: composer.selection)
        case .export:
            Log.breadcrumb("Combos: opening the export save panel")
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.trackpadToolProfile]
            panel.nameFieldStringValue = "\(name).tpt"
            if panel.runModal() == .OK, let url = panel.url {
                manager.export(to: url, name: name, note: note.isEmpty ? nil : note, parts: composer.selection)
            }
        }
    }

    private func importFile() {
        Log.breadcrumb("Combos: opening the import panel")
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.trackpadToolProfile]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            manager.beginImport(url)
        }
    }

    private func saveCheatSheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "TrackpadTool cheat sheet.html"
        if panel.runModal() == .OK, let url = panel.url {
            manager.exportCheatSheet(to: url, for: manager.currentFile(named: "My TrackpadTool setup"))
        }
    }
}

// MARK: - Shared pieces

/// Which sheet is open on the Combos page.
final class CombosUI: ObservableObject {
    @Published var composer: ComposerModel?
    /// Rows folded open.
    @Published var expanded: Set<String> = []

    func toggle(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    func compose(_ mode: ComposerModel.Mode) {
        Log.breadcrumb(mode == .save ? "Combos: Save as combo" : "Combos: Export combo")
        composer = ComposerModel(mode: mode, source: ProfileManager.shared.currentFile(named: ""))
    }
}

/// Small icons for the parts a combo holds.
struct PartIcons: View {
    let file: ProfileFile

    var body: some View {
        HStack(spacing: 5) {
            ForEach(file.orderedParts.filter { file.hasContent($0) }) { part in
                Image(systemName: part.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                    .help(file.describe(part))
            }
        }
    }
}

/// A grid of selectable part tiles.
struct PartTiles: View {
    let file: ProfileFile
    /// Parts you can pick; the rest are shown dimmed.
    let available: Set<ComboPart>
    @Binding var selection: Set<ComboPart>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ComboPart.allCases) { part in
                tile(part)
            }
        }
    }

    private func tile(_ part: ComboPart) -> some View {
        let enabled = available.contains(part)
        let selected = enabled && selection.contains(part)
        return Button {
            if selection.contains(part) { selection.remove(part) } else { selection.insert(part) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: part.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .frame(height: 26)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                Text(part.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption(part))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(enabled ? file.describe(part) : "Not in this combo")
    }

    private func caption(_ part: ComboPart) -> String {
        guard available.contains(part) else { return "—" }
        let n = file.count(part)
        switch part {
        case .perApp: return n == 0 ? "No apps" : "\(n) app\(n == 1 ? "" : "s")"
        case .cornerClicks:
            let sizes = !(file.cornerSizes ?? [:]).isEmpty
            return n == 0 ? (sizes ? "Sizes only" : "Nothing set") : "\(n) set\(sizes ? " + sizes" : "")"
        default: return n == 0 ? "Nothing set" : "\(n) set"
        }
    }
}

// MARK: - Save / export

final class ComposerModel: ObservableObject, Identifiable {
    enum Mode { case save, export }

    let id = UUID()
    let mode: Mode
    /// The complete current setup.
    let source: ProfileFile
    @Published var name: String
    @Published var note = ""
    @Published var selection: Set<ComboPart>

    init(mode: Mode, source: ProfileFile) {
        self.mode = mode
        self.source = source
        name = mode == .save ? "" : "My TrackpadTool combo"
        selection = Set(source.orderedParts.filter { source.hasContent($0) })
    }

    var available: Set<ComboPart> { Set(source.orderedParts.filter { source.hasContent($0) }) }

    var preview: ProfileFile {
        var f = source.keeping(selection)
        f.name = name
        return f
    }
}

struct ComposeSheet: View {
    @ObservedObject var model: ComposerModel
    /// true = save or export, false = cancelled.
    let close: (Bool) -> Void

    var body: some View {
        let ready = !model.selection.isEmpty && !model.name.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.mode == .save ? "Save a combo" : "Export a combo")
                    .font(.system(size: 17, weight: .semibold))
                Text("Click the parts to include. Only what you pick goes into the combo.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            TextField("Name", text: $model.name)
                .textFieldStyle(.roundedBorder)
            TextField("Note for others (optional)", text: $model.note)
                .textFieldStyle(.roundedBorder)

            PartTiles(file: model.source, available: model.available, selection: $model.selection)
            HStack(spacing: 12) {
                Button("Select all") { model.selection = model.available }
                Button("Select none") { model.selection = [] }
                Spacer()
            }
            .buttonStyle(.link)
            .font(.callout)

            Text(model.selection.isEmpty ? "Pick at least one part." : model.preview.contentsSummary)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            HStack {
                Spacer()
                Button("Cancel") { close(false) }
                    .keyboardShortcut(.cancelAction)
                Button(model.mode == .save ? "Save" : "Export…") { close(true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

// MARK: - Import review

final class ImportModel: ObservableObject {
    let file: ProfileFile
    @Published var selection: Set<ComboPart> { didSet { recompute() } }
    @Published var keepRest = true
    /// Apps left out on purpose (all are kept by default, installed or not:
    /// a missing app's setup waits until it's installed).
    @Published var skippedApps: Set<String> = [] { didSet { recompute() } }
    /// The file's apps, sorted by name, with whether each is on this Mac.
    let appList: [ImportApp]
    /// Worked out once per change of selection, not on every redraw (each
    /// "Open app" needs an app lookup).
    @Published private(set) var preview: ProfileFile
    @Published private(set) var flagged: [String] = []
    @Published private(set) var rows: [ImportRow] = []

    init(file: ProfileFile) {
        self.file = file
        let initial = Set(file.orderedParts.filter { file.hasContent($0) })
        selection = initial
        preview = file.keeping(initial)
        appList = file.apps.map { ImportApp(id: $0.key, name: $0.value.name, installed: AppPresence.isInstalled($0.key)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        recompute()
    }

    private func recompute() {
        var p = file.keeping(selection)
        for id in skippedApps { p.apps[id] = nil }
        preview = p
        flagged = ProfileManager.shared.flags(in: preview)
        rows = ImportRow.rows(for: preview)
    }
}

/// An app with its own setup in an imported combo.
struct ImportApp: Identifiable {
    let id: String
    let name: String
    let installed: Bool
}

/// One line of the import review: a gesture and what it will do.
struct ImportRow: Hashable {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    /// "Corner clicks · Top-left corner" → "Snap top-left quarter", per chosen part.
    static func rows(for f: ProfileFile) -> [ImportRow] {
        var out: [ImportRow] = []
        for part in f.orderedParts {
            switch part {
            case .stageManager:
                for g in Gesture.allCases {
                    if let c = f.stageBindings?[g.key] { out.append(ImportRow("With Stage Manager on · \(g.fullTitle)", c.readable)) }
                }
            case .perApp:
                for (id, app) in f.apps.sorted(by: { $0.value.name < $1.value.name }) {
                    let waiting = AppPresence.isInstalled(id) ? "" : " (waits until installed)"
                    // Each gesture that's different in this app.
                    for g in Gesture.allCases {
                        if let c = app.bindings[g.key] {
                            out.append(ImportRow("In \(app.name)\(waiting) · \(g.fullTitle)", c.readable))
                        }
                    }
                }
            case .shortcuts:
                for k in f.keyShortcuts ?? [] {
                    if let s = k.shortcut, k.action.kind != .macDefault {
                        out.append(ImportRow("Shortcut \(s.display)", k.action.readable))
                    }
                }
            default:
                let set = part.gestures.filter { (f.bindings[$0.key]?.kind ?? .macDefault) != .macDefault }
                if set.isEmpty {
                    out.append(ImportRow(part.title, "everything back to macOS default"))
                }
                for g in set {
                    if let c = f.bindings[g.key] { out.append(ImportRow(g.fullTitle, c.readable)) }
                }
                if part == .cornerClicks, let sizes = f.cornerSizes, !sizes.isEmpty {
                    let text = Corner.allCases.map { (sizes[$0.rawValue] ?? .medium).title }
                    out.append(ImportRow("Corner sizes", Set(text).count == 1 ? "All \(text[0])" : text.joined(separator: ", ")))
                }
            }
        }
        return out
    }
}

/// Shown before an imported combo is added or used.
struct ImportReview: View {
    let pending: PendingImport
    @ObservedObject private var manager = ProfileManager.shared
    @StateObject private var model: ImportModel
    private var store: SettingsStore { SettingsStore.shared }

    init(pending: PendingImport) {
        self.pending = pending
        _model = StateObject(wrappedValue: ImportModel(file: pending.file))
    }

    var body: some View {
        let f = model.preview
        let flagged = model.flagged
        let switchOn = f.neededModules.filter { !store.isOn($0) }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import “\(pending.file.name)”?").font(.system(size: 17, weight: .semibold))
                Text("From \(pending.sourceName)\(pending.file.createdWith.map { " · made with TrackpadTool \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                if let note = pending.file.note, !note.isEmpty { Text(note).font(.callout) }
            }

            Text("This combo holds the parts below. Click to leave one out.")
                .font(.callout).foregroundStyle(.secondary)
            PartTiles(file: pending.file, available: pending.file.partSet, selection: $model.selection)

            if model.selection.contains(.perApp) && !model.appList.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apps in this combo").font(.system(size: 13, weight: .semibold))
                    ForEach(model.appList) { app in
                        Toggle(isOn: Binding(
                            get: { !model.skippedApps.contains(app.id) },
                            set: { on in
                                if on { model.skippedApps.remove(app.id) } else { model.skippedApps.insert(app.id) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Text(app.name)
                                Text(app.installed ? "Installed" : "Not on this Mac: waits until installed")
                                    .font(.caption)
                                    .foregroundStyle(app.installed ? Color.secondary : Color.orange)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !flagged.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Check these first", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                    ForEach(flagged, id: \.self) { Text("• " + $0).font(.callout) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.rows, id: \.self) { row in
                        HStack(alignment: .top) {
                            Text(row.label).foregroundStyle(.secondary)
                            Spacer()
                            Text(row.value)
                        }
                        .font(.callout)
                    }
                    if !switchOn.isEmpty {
                        Text("Also switches on: " + switchOn.map(\.title).joined(separator: ", "))
                            .font(.callout).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)

            Picker("When used:", selection: $model.keepRest) {
                Text("Keep the rest of my setup").tag(true)
                Text("Reset the rest to macOS default").tag(false)
            }
            .pickerStyle(.radioGroup)

            Text("Add puts the chosen parts on the Imported tab without changing anything. Add and use also switches to them; your setup is backed up first, so you can undo.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { manager.pending = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Add and use") {
                    manager.addPending(andUse: true, parts: model.selection, keepRest: model.keepRest, skipApps: model.skippedApps)
                }
                .disabled(model.selection.isEmpty)
                Button("Add") {
                    manager.addPending(andUse: false, parts: model.selection, keepRest: model.keepRest, skipApps: model.skippedApps)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
