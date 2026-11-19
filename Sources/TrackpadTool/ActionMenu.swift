import SwiftUI

/// The action picker for one gesture: macOS default and Do nothing on top,
/// then one submenu per module, so the list stays short. Outside Advanced
/// mode, rarely used actions are left out.
struct ActionMenu: View {
    @EnvironmentObject var store: SettingsStore
    /// nil for keyboard shortcuts (every action fits).
    let gesture: Gesture?
    /// The chosen action; nil when the gesture follows another setup.
    let current: ActionKind?
    /// Shown as the first item when the gesture can follow another setup
    /// ("Same as all apps (…)"); nil hides it.
    var inheritTitle: String?
    /// Actions not offered here (e.g. for keyboard shortcuts).
    var exclude: Set<ActionKind> = []
    /// Called with the new action, or nil for "same as …".
    let onSelect: (ActionKind?) -> Void

    var body: some View {
        Menu {
            if let title = inheritTitle {
                check(title, selected: current == nil) { onSelect(nil) }
                Divider()
            }
            ForEach(groups) { group in
                if group.module == nil {
                    ForEach(group.actions) { k in
                        check(k.title, selected: k == current) { onSelect(k) }
                    }
                    Divider()
                } else {
                    Menu(submenuTitle(group)) {
                        ForEach(group.actions) { k in
                            check(k.title, selected: k == current) { onSelect(k) }
                        }
                    }
                }
            }
        } label: {
            Text(label)
        }
        .menuIndicator(.visible)
        .fixedSize()
    }

    private var groups: [SettingsStore.OptionGroup] {
        store.optionGroups(current: current, gesture: gesture).compactMap { g in
            let actions = g.actions.filter { !exclude.contains($0) || $0 == current }
            return actions.isEmpty ? nil : SettingsStore.OptionGroup(module: g.module, actions: actions)
        }
    }

    private var label: String {
        guard let k = current else { return inheritTitle ?? "macOS default" }
        return k.title
    }

    /// A submenu that holds the chosen action gets a dot, so you can tell
    /// where it is without opening every submenu.
    private func submenuTitle(_ group: SettingsStore.OptionGroup) -> String {
        if let c = current, group.actions.contains(c) { return "\(group.title)  •" }
        return group.title
    }

    private func check(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { selected }, set: { _ in action() }))
    }
}
