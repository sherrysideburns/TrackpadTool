import AppKit
import SwiftUI

struct SwitcherItem: Identifiable {
    let id = UUID()
    let pid: pid_t
    let appName: String
    let icon: NSImage?
}

final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selected = 0
    @Published var iconSize: CGFloat = 112
}

/// ⌘Tab-style app switcher: one large icon per app, most recently used
/// first, including hidden apps and apps without windows. Swipe and hold to
/// move along the row, lift your fingers to switch; a quick swipe jumps
/// straight back to the previous app.
final class WindowSwitcher {
    static let shared = WindowSwitcher()

    let model = SwitcherModel()
    private var panel: NSPanel?
    private(set) var isOpen = false

    static let maxIcon: CGFloat = 112
    static let minIcon: CGFloat = 40
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 18
    static let nameHeight: CGFloat = 24

    /// Highlight around an icon.
    static func tile(_ icon: CGFloat) -> CGFloat { icon + icon * 0.2 }

    private init() {}

    /// Kept for callers; both modes now show one icon per app (with Stage
    /// Manager on, that's one icon per stage).
    enum Mode { case windows, apps }

    func begin(direction: Int, mode: Mode = .apps) {
        let items = collectApps()
        guard !items.isEmpty else { return }
        model.items = items
        model.selected = items.count > 1 ? wrap(direction) : 0
        show()
        isOpen = true
    }

    func step(_ direction: Int) {
        guard isOpen, !model.items.isEmpty else { return }
        model.selected = wrap(model.selected + direction)
    }

    func commit() {
        guard isOpen else { return }
        isOpen = false
        panel?.orderOut(nil)
        guard model.items.indices.contains(model.selected) else { return }
        focus(model.items[model.selected])
    }

    /// Jump straight back to the previous app, without browsing.
    func quickSwitch(mode: Mode = .apps) {
        // Straight to the previous app, without drawing the switcher.
        guard !isOpen else { return }
        let items = collectApps()
        guard !items.isEmpty else { return }
        focus(items[items.count > 1 ? 1 : 0])
    }

    private func wrap(_ i: Int) -> Int {
        let n = model.items.count
        return ((i % n) + n) % n
    }

    // MARK: Collect apps

    private func collectApps() -> [SwitcherItem] {
        // No Accessibility calls here: asking every app for its windows on
        // each swipe was slow, and a hung app stalled the switcher.
        appsFrontToBack().map { app in
            SwitcherItem(pid: app.processIdentifier, appName: app.localizedName ?? "App", icon: app.icon)
        }
    }

    /// Apps ordered most recently used first.
    private func appsFrontToBack() -> [NSRunningApplication] {
        let apps = regularApps()
        var order: [pid_t] = []
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            order.append(front)
        }
        for pid in AppRecency.shared.pids where !order.contains(pid) {
            order.append(pid)
        }
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in infos {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  !order.contains(pid) else { continue }
            order.append(pid)
        }
        return apps.sorted { a, b in
            let ia = order.firstIndex(of: a.processIdentifier) ?? Int.max
            let ib = order.firstIndex(of: b.processIdentifier) ?? Int.max
            if ia != ib { return ia < ib }
            return (a.localizedName ?? "") < (b.localizedName ?? "")
        }
    }

    // MARK: Focus

    /// Brings the whole app forward, like ⌘Tab: unhides it, and if every
    /// window was minimized, brings the first one back.
    private func focus(_ item: SwitcherItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else { return }
        ActionRunner.shared.forget(pid: item.pid)
        if app.isHidden { app.unhide() }
        // Only for the chosen app: bring a window back if all are minimized.
        let windows = AX.windows(of: item.pid).filter { AX.isStandardWindow($0) }
        if !windows.isEmpty, windows.allSatisfy({ AX.bool($0, kAXMinimizedAttribute as String) == true }) {
            AX.set(windows[0], kAXMinimizedAttribute as String, false)
        }
        AX.activate(app)
    }

    // MARK: Panel

    private func show() {
        if panel == nil {
            let p = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .popUpMenu
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.contentView = NSHostingView(rootView: SwitcherView(model: model))
            panel = p
        }
        guard let panel = panel else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Icons shrink so every app fits on one row, like ⌘Tab.
        let n = CGFloat(model.items.count)
        let available = frame.width * 0.92 - Self.padding * 2
        var icon = Self.maxIcon
        while icon > Self.minIcon && n * Self.tile(icon) + (n - 1) * Self.spacing > available {
            icon -= 4
        }
        model.iconSize = icon

        let tile = Self.tile(icon)
        let width = n * tile + max(n - 1, 0) * Self.spacing + Self.padding * 2
        let height = tile + Self.nameHeight + Self.padding * 2
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2,
                              width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
}

// MARK: - Switcher view

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        let tile = WindowSwitcher.tile(model.iconSize)
        HStack(alignment: .top, spacing: WindowSwitcher.spacing) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let selected = index == model.selected
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: tile * 0.18, style: .continuous)
                            .fill(Color.white.opacity(selected ? 0.22 : 0))
                        if let icon = item.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: model.iconSize, height: model.iconSize)
                        }
                    }
                    .frame(width: tile, height: tile)
                    Text(item.appName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: tile, height: WindowSwitcher.nameHeight - 6)
                        .opacity(selected ? 1 : 0)
                }
            }
        }
        .padding(WindowSwitcher.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

/// Remembers which apps were used most recently (Stage Manager hides
/// windows of other stages, so the on-screen order isn't enough).
final class AppRecency {
    static let shared = AppRecency()
    private(set) var pids: [pid_t] = []
    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        guard observer == nil else { return }
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { pids = [front] }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.pids.removeAll { $0 == app.processIdentifier }
            self?.pids.insert(app.processIdentifier, at: 0)
            if (self?.pids.count ?? 0) > 60 { self?.pids.removeLast() }
        }
    }
}
