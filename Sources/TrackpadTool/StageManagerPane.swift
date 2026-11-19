import SwiftUI
import Combine

/// Mirrors the Stage Manager switches in System Settings › Desktop & Dock,
/// re-read whenever the page shows or the app comes forward.
final class StageOptionsModel: ObservableObject {
    @Published var on = false
    @Published var stripHidden = false
    @Published var allAtOnce = true
    @Published var desktopItems = false
    @Published var widgets = true
    @Published var clickWallpaperAlways = true

    init() { reload() }

    /// Re-reads the switches. Only changed values are published, so a
    /// reload never causes a redraw by itself.
    func reload() {
        func set<T: Equatable>(_ kp: ReferenceWritableKeyPath<StageOptionsModel, T>, _ v: T) {
            if self[keyPath: kp] != v { self[keyPath: kp] = v }
        }
        set(\.on, StageManager.isOn)
        set(\.stripHidden, StageManager.stripHidden)
        set(\.allAtOnce, StageManager.windowsAllAtOnce)
        set(\.desktopItems, StageManager.showDesktopItems)
        set(\.widgets, StageManager.showWidgets)
        set(\.clickWallpaperAlways, StageManager.clickWallpaperAlways)
    }

    func binding<T>(_ keyPath: ReferenceWritableKeyPath<StageOptionsModel, T>,
                    write: @escaping (T) -> Void) -> Binding<T> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { value in
                self[keyPath: keyPath] = value
                write(value)
            }
        )
    }
}

struct StageManagerPane: View {
    @EnvironmentObject var store: SettingsStore
    @ObservedObject var status: StatusWatcher
    @ObservedObject var nav: NavigationModel
    @StateObject private var model = StageOptionsModel()

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Stage Manager",
                       subtitle: "Stage Manager’s own options, and gestures that only apply while it’s on.")
            Form {
                Section {
                    Toggle("Stage Manager", isOn: model.binding(\.on) { StageManager.set(on: $0) })
                    Picker("Recent apps on the left", selection: model.binding(\.stripHidden) { StageManager.set(stripHidden: $0) }) {
                        Text("Always show").tag(false)
                        Text("Hide until you point at the edge").tag(true)
                    }
                    Picker("Show windows from an app", selection: model.binding(\.allAtOnce) { StageManager.windowsAllAtOnce = $0 }) {
                        Text("All at once").tag(true)
                        Text("One at a time").tag(false)
                    }
                    Toggle("Show desktop items", isOn: model.binding(\.desktopItems) { StageManager.showDesktopItems = $0 })
                    Toggle("Show widgets", isOn: model.binding(\.widgets) { StageManager.showWidgets = $0 })
                    Picker("Click wallpaper to reveal desktop", selection: model.binding(\.clickWallpaperAlways) { StageManager.clickWallpaperAlways = $0 }) {
                        Text("Always").tag(true)
                        Text("Only in Stage Manager").tag(false)
                    }
                } header: {
                    Text("Options")
                } footer: {
                    Text("These are the same switches as in System Settings › Desktop & Dock. The last one applies with Stage Manager off too. If a change doesn’t show right away, it does after you log out and back in.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: $store.settings.stageSetOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Different gestures while Stage Manager is on")
                            Text("Each gesture starts as “Same as normal”; change only the ones you want different.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if store.settings.stageSetOn {
                        HStack {
                            Text(changedSummary).foregroundStyle(.secondary)
                            Spacer()
                            if !store.settings.stageBindings.isEmpty {
                                Button("Reset to normal") { store.settings.stageBindings = [:] }
                            }
                            Button("Edit Stage Manager gestures…") {
                                nav.app = Settings.stageScope
                                nav.pane = .gestures
                            }
                        }
                        if !changed.isEmpty {
                            ForEach(changed, id: \.gesture) { item in
                                LabeledContent(item.gesture.fullTitle, value: item.config.readable)
                                    .font(.callout)
                            }
                        }
                    }
                } header: {
                    Text("Gestures")
                } footer: {
                    Text(status.stageManagerOn && store.settings.stageSetOn
                         ? "Stage Manager is on now, so these gestures are in use."
                         : "Gestures switch over the moment Stage Manager turns on or off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        // Not onReceive(status.$stageManagerOn): that publisher is rebuilt on
        // every redraw, re-sends its value, and the reload redraws again —
        // an endless loop that froze 0.6 on this page.
        .onChange(of: status.stageManagerOn) { _ in model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
    }

    private struct Changed {
        let gesture: Gesture
        let config: ActionConfig
    }

    private var changed: [Changed] {
        Gesture.allCases.compactMap { g in
            guard let c = store.settings.stageBindings[g.key], c != store.globalConfig(for: g) else { return nil }
            return Changed(gesture: g, config: c)
        }
    }

    private var changedSummary: String {
        switch changed.count {
        case 0: return "Same as your normal setup so far"
        case 1: return "1 gesture differs"
        default: return "\(changed.count) gestures differ"
        }
    }
}
