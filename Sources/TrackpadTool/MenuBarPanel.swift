import AppKit
import SwiftUI

/// The dropdown under the menu bar icon: every gesture with its action,
/// changeable right there.
struct MenuBarPanel: View {
    @EnvironmentObject var store: SettingsStore
    @ObservedObject var status: StatusWatcher
    @ObservedObject private var ui = PanelState.shared
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !status.accessibilityTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
                    Text("Needs Accessibility permission").font(.system(size: 12))
                    Spacer()
                    Button("Fix…") { AX.requestTrust(); ConflictChecker.openAccessibilitySettings() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                Divider()
            }
            if Log.previousSessionEndedUnexpectedly && !ui.crashNoticeDismissed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Stopped unexpectedly last time").font(.system(size: 12))
                    Spacer()
                    Button("Show log") { NSWorkspace.shared.open(Log.fileURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil) }
                        .controlSize(.small)
                    Button {
                        ui.crashNoticeDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                Divider()
            }
            if store.stageSetEnabled {
                Picker("", selection: $ui.stage) {
                    Text("Normal").tag(false)
                    Text("Stage Manager").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let note = note {
                        Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if visibleGroups.isEmpty {
                        Text("No gestures set up yet. Show all gestures to pick one.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }
                    ForEach(visibleGroups) { entry in
                        section(entry.group, entry.gestures)
                    }
                    Button(ui.showAll ? "Show only gestures in use" : "Show all gestures (\(hiddenCount) more)") {
                        ui.showAll.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(hiddenCount == 0 && !ui.showAll ? 0 : 1)
                }
                .padding(14)
            }
            .frame(height: listHeight)
            .opacity(store.settings.enabled ? 1 : 0.45)
            Divider()
            HStack {
                Button {
                    openSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 370)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("TrackpadTool").font(.system(size: 13, weight: .semibold))
                Text(store.settings.enabled ? "Gestures on · version \(AppInfo.version)" : "Paused · version \(AppInfo.version)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $store.settings.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The setup being shown: nil = normal, or the Stage Manager setup.
    private var scope: String? { store.stageSetEnabled && ui.stage ? Settings.stageScope : nil }

    private var note: String? {
        if scope != nil { return "Gestures while Stage Manager is on. “Same as normal” uses your normal setup." }
        if store.isOn(.perAppGestures) && !store.settings.apps.isEmpty && store.settings.advancedMode {
            return "Your setup for all apps. Per-app changes are in Settings."
        }
        return nil
    }

    /// A gesture is "in use" in this view when it does something here.
    private func inUse(_ g: Gesture) -> Bool {
        if scope != nil { return store.settings.stageBindings[g.key] != nil }
        return store.globalConfig(for: g).kind != .macDefault
    }

    private var visibleGroups: [GroupEntry] {
        GestureGroup.allCases.compactMap { group in
            guard store.showsGroup(group) else { return nil }
            let list = ui.showAll ? group.gestures : group.gestures.filter(inUse)
            return list.isEmpty ? nil : GroupEntry(group: group, gestures: list)
        }
    }

    private var hiddenCount: Int {
        GestureGroup.allCases.filter { store.showsGroup($0) }
            .flatMap(\.gestures).filter { !inUse($0) }.count
    }

    /// Grows with the list, up to a scrolling maximum.
    private var listHeight: CGFloat {
        let groups = visibleGroups
        let rows = groups.reduce(0) { $0 + $1.gestures.count }
        let estimate = CGFloat(groups.count) * 34 + CGFloat(rows) * 31 + (note == nil ? 0 : 30) + 70
        return min(max(estimate, 140), 460)
    }

    private func section(_ group: GestureGroup, _ gestures: [Gesture]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(group.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(gestures.enumerated()), id: \.offset) { index, gesture in
                    if index > 0 { Divider().padding(.leading, 34) }
                    MenuGestureRow(gesture: gesture, scope: scope, openSettings: openSettings)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }
}

private struct GroupEntry: Identifiable {
    let group: GestureGroup
    let gestures: [Gesture]
    var id: String { group.rawValue }
}

/// What the dropdown shows; kept while it closes and opens again.
final class PanelState: ObservableObject {
    static let shared = PanelState()
    @Published var showAll = false
    /// Showing the Stage Manager setup.
    @Published var stage = StageManager.isOn
    @Published var crashNoticeDismissed = false
}

private struct MenuGestureRow: View {
    @EnvironmentObject var store: SettingsStore
    let gesture: Gesture
    /// nil = normal setup, Settings.stageScope = Stage Manager setup.
    let scope: String?
    let openSettings: () -> Void

    var body: some View {
        let stored = store.storedConfig(for: gesture, app: scope)
        let config = stored ?? store.globalConfig(for: gesture)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: gesture.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(config.kind == .macDefault ? Color.secondary : Color.accentColor)
                    .frame(width: 18)
                Text(gesture.title).font(.system(size: 12.5))
                Spacer(minLength: 6)
                ActionMenu(gesture: gesture,
                           current: scope != nil && stored == nil ? nil : config.kind,
                           inheritTitle: scope == nil ? nil : "Same as normal",
                           onSelect: select)
                    .controlSize(.small)
            }
            if needsSetup(config) {
                Button("Finish setting this up in Settings") { openSettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func select(_ kind: ActionKind?) {
        if let kind = kind {
            store.update(gesture, app: scope) { $0.kind = kind }
        } else if let scope = scope {
            store.clearOverride(gesture, app: scope)
        }
    }

    private func needsSetup(_ c: ActionConfig) -> Bool {
        (c.kind == .keyboardShortcut && c.shortcut == nil) || (c.kind == .openApp && c.appPath == nil && c.appID == nil)
    }
}
