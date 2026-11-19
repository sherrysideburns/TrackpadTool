import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Shortcuts: keyboard shortcuts that run an action from any app,
/// like Rectangle. Works like the Gestures page: each shortcut has an
/// action menu. In Advanced mode, also window gaps and where apps open.
struct ShortcutsPane: View {
    @EnvironmentObject var store: SettingsStore
    @ObservedObject private var hotKeys = HotKeyCenter.shared

    /// Actions that don't make sense on a key: pressing another shortcut,
    /// an app picker the row doesn't have, a mouse click.
    private let notForKeys: Set<ActionKind> = [.keyboardShortcut, .openApp, .middleClick]

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Shortcuts",
                       subtitle: "Press a key combination in any app to run an action, like Rectangle.")
            Form {
                Section {
                    if store.settings.keyShortcuts.isEmpty {
                        Text("No shortcuts yet. Add one, or start with Rectangle’s window shortcuts.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach($store.settings.keyShortcuts) { $binding in
                        row($binding)
                    }
                    HStack {
                        Button("Add shortcut") {
                            store.settings.keyShortcuts.append(KeyBinding())
                        }
                        Spacer()
                        Button("Add Rectangle’s window shortcuts") { addRectangleShortcuts() }
                    }
                } header: {
                    Text("Keyboard shortcuts")
                } footer: {
                    Text("Shortcuts work everywhere while gestures are on. A shortcut another app already uses (Rectangle, for example) can’t be taken: quit that app or pick another combination.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if store.settings.advancedMode {
                    Section {
                        HStack {
                            Slider(value: $store.settings.windowGap, in: 0...40, step: 2) {
                                Text("Gap between windows")
                            }
                            Text(store.settings.windowGap == 0 ? "None" : "\(Int(store.settings.windowGap)) pt")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    } header: {
                        Text("Window gaps")
                    } footer: {
                        Text("Space around snapped and maximized windows, from gestures and shortcuts alike.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section {
                        if store.settings.launchPositions.isEmpty {
                            Text("No apps yet.").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(launchApps, id: \.self) { id in
                            launchRow(id)
                        }
                        HStack {
                            Spacer()
                            Button("Add an app…") { addLaunchApp() }
                        }
                    } header: {
                        Text("When an app opens")
                    } footer: {
                        Text("The app’s first window snaps into this place each time the app starts.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: Shortcut rows

    private func row(_ binding: Binding<KeyBinding>) -> some View {
        let b = binding.wrappedValue
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ShortcutRecorderButton(shortcut: binding.shortcut)
                    .frame(minWidth: 150, alignment: .leading)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                ActionMenu(gesture: nil,
                           current: b.action.kind,
                           exclude: notForKeys,
                           onSelect: { kind in
                               if let kind = kind { binding.wrappedValue.action = ActionConfig(kind: kind) }
                           })
                Spacer()
                Button {
                    store.settings.keyShortcuts.removeAll { $0.id == b.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this shortcut")
            }
            if let s = b.shortcut, !s.isSafeEverywhere {
                Label("Add ⌘, ⌥ or ⌃ (or use an F-key): a plain key would stop you typing it", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if hotKeys.taken.contains(b.id) {
                Label("Already used by another app, or set twice", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if b.action.kind != .macDefault {
                Text(b.action.explanation(for: .threeClick))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Adds Rectangle's standard window shortcuts that aren't set yet.
    private func addRectangleShortcuts() {
        var list = store.settings.keyShortcuts
        let used = Set(list.compactMap { $0.shortcut.map { "\($0.keyCode)-\($0.modifiers)" } })
        let actionsSet = Set(list.map(\.action.kind))
        for (shortcut, kind) in Shortcut.rectangleDefaults
        where !used.contains("\(shortcut.keyCode)-\(shortcut.modifiers)") && !actionsSet.contains(kind) {
            list.append(KeyBinding(shortcut: shortcut, action: ActionConfig(kind: kind)))
        }
        store.settings.keyShortcuts = list
        if !store.isOn(.windowSnapping) { store.setModule(.windowSnapping, on: true) }
    }

    // MARK: Launch positions

    private var launchApps: [String] {
        store.settings.launchPositions.keys.sorted {
            (store.settings.launchPositions[$0]?.name ?? "") < (store.settings.launchPositions[$1]?.name ?? "")
        }
    }

    private func launchRow(_ id: String) -> some View {
        let position = store.settings.launchPositions[id] ?? LaunchPosition(name: id)
        return HStack {
            Text(AppPresence.isInstalled(id) ? position.name : "\(position.name) (waiting until installed)")
            Spacer()
            Picker("", selection: Binding(
                get: { position.place },
                set: { store.settings.launchPositions[id]?.place = $0 }
            )) {
                ForEach(ActionKind.launchPlaces) { kind in
                    Text(kind.title.replacingOccurrences(of: "Snap ", with: "").capitalizedFirst).tag(kind)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button {
                store.settings.launchPositions[id] = nil
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func addLaunchApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        store.settings.launchPositions[id] = LaunchPosition(name: name)
        if !store.isOn(.windowSnapping) { store.setModule(.windowSnapping, on: true) }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
