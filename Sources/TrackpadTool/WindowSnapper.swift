import AppKit
import ApplicationServices

/// Moves and resizes the front window, like Windows Snap.
/// Accessibility uses top-left screen coordinates; AppKit uses bottom-left.
enum WindowSnapper {
    /// Frames before a snap, so "Restore window size" can put them back.
    private static var saved: [(window: AXUIElement, frame: CGRect)] = []

    /// Snaps `window`, or the front window when none is given.
    static func perform(_ action: ActionKind, window given: AXUIElement? = nil) {
        guard let window = given ?? focusedWindow(), let frame = frame(of: window) else { return }
        switch action {
        case .toggleMaximizeWindow:
            // Already filling the screen and we know its old size: put it back.
            if let area = screenArea(for: frame), isClose(frame, part(area, x: 0, y: 0, w: 1, h: 1)),
               let i = saved.lastIndex(where: { CFEqual($0.window, window) }) {
                setFrame(window, saved[i].frame)
                saved.remove(at: i)
                return
            }
        case .restoreWindowSize:
            if let i = saved.lastIndex(where: { CFEqual($0.window, window) }) {
                setFrame(window, saved[i].frame)
                saved.remove(at: i)
            }
            return
        default:
            break
        }
        guard let t = target(action, frame: frame) else { return }
        remember(window, frame)
        setFrame(window, t.integral)
    }

    /// Where an action puts a window that's now at `frame` (top-left
    /// coordinates), or nil if it doesn't move it.
    static func target(_ action: ActionKind, frame: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        guard let screen = screen(containing: frame) else { return nil }
        let area = axRect(fromCocoa: screen.visibleFrame)
        let third: CGFloat = 1.0 / 3.0
        switch action {
        case .snapLeft: return part(area, x: 0, y: 0, w: 0.5, h: 1)
        case .snapRight: return part(area, x: 0.5, y: 0, w: 0.5, h: 1)
        case .snapTop: return part(area, x: 0, y: 0, w: 1, h: 0.5)
        case .snapBottom: return part(area, x: 0, y: 0.5, w: 1, h: 0.5)
        case .snapTopLeft: return part(area, x: 0, y: 0, w: 0.5, h: 0.5)
        case .snapTopRight: return part(area, x: 0.5, y: 0, w: 0.5, h: 0.5)
        case .snapBottomLeft: return part(area, x: 0, y: 0.5, w: 0.5, h: 0.5)
        case .snapBottomRight: return part(area, x: 0.5, y: 0.5, w: 0.5, h: 0.5)
        case .snapLeftThird: return part(area, x: 0, y: 0, w: third, h: 1)
        case .snapCenterThird: return part(area, x: third, y: 0, w: third, h: 1)
        case .snapRightThird: return part(area, x: 2 * third, y: 0, w: third, h: 1)
        case .snapLeftTwoThirds: return part(area, x: 0, y: 0, w: 2 * third, h: 1)
        case .snapRightTwoThirds: return part(area, x: third, y: 0, w: 2 * third, h: 1)
        case .maximizeWindow, .toggleMaximizeWindow: return part(area, x: 0, y: 0, w: 1, h: 1)
        case .centerWindow:
            let w = min(frame.width, area.width), h = min(frame.height, area.height)
            return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        case .moveToNextDisplay:
            guard screens.count > 1, let i = screens.firstIndex(of: screen) else { return nil }
            let next = axRect(fromCocoa: screens[(i + 1) % screens.count].visibleFrame)
            // Same relative place and size on the next display.
            let rx = (frame.minX - area.minX) / area.width, ry = (frame.minY - area.minY) / area.height
            let rw = frame.width / area.width, rh = frame.height / area.height
            return CGRect(x: next.minX + rx * next.width, y: next.minY + ry * next.height,
                          width: min(rw, 1) * next.width, height: min(rh, 1) * next.height)
        default:
            return nil
        }
    }

    private static func screenArea(for frame: CGRect) -> CGRect? {
        screen(containing: frame).map { axRect(fromCocoa: $0.visibleFrame) }
    }

    /// Makes every open (not minimized, not hidden) window fill its screen.
    /// "Restore window size" puts each one back.
    static func maximizeAll() {
        for app in regularApps() where !app.isHidden {
            for window in AX.windows(of: app.processIdentifier)
            where AX.isStandardWindow(window) && AX.bool(window, kAXMinimizedAttribute as String) != true {
                guard let frame = frame(of: window), let screen = screen(containing: frame) else { continue }
                let full = part(axRect(fromCocoa: screen.visibleFrame), x: 0, y: 0, w: 1, h: 1)
                if isClose(frame, full) { continue }
                remember(window, frame)
                setFrame(window, full.integral)
            }
        }
    }

    // MARK: Helpers

    static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 6 && abs(a.minY - b.minY) < 6 && abs(a.width - b.width) < 12 && abs(a.height - b.height) < 12
    }

    /// The gap between snapped windows and around them (Gesture settings,
    /// Advanced mode). 0 = windows touch.
    private static var gap: CGFloat { CGFloat(SettingsStore.shared.settings.windowGap) }

    /// A part of the screen area. With a gap, the outer edges keep `gap`
    /// from the screen edge and neighbouring parts keep `gap` between them.
    private static func part(_ r: CGRect, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        let g = gap
        let inner = r.insetBy(dx: g / 2, dy: g / 2)
        let p = CGRect(x: inner.minX + inner.width * x, y: inner.minY + inner.height * y,
                       width: inner.width * w, height: inner.height * h)
        return g > 0 ? p.insetBy(dx: g / 2, dy: g / 2) : p
    }

    private static func remember(_ window: AXUIElement, _ frame: CGRect) {
        // Keep the size from before the first snap, so restore goes all the way back.
        if saved.contains(where: { CFEqual($0.window, window) }) { return }
        saved.append((window, frame))
        if saved.count > 50 { saved.removeFirst() }
    }

    static func focusedWindow() -> AXUIElement? {
        // Our own windows (Settings) can't be moved through Accessibility
        // from our own main thread; the request would only time out.
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != AX.ownPID else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let pv = posValue, let sv = sizeValue,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &point)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private static func setFrame(_ window: AXUIElement, _ rect: CGRect) {
        var point = rect.origin, size = rect.size
        guard let pv = AXValueCreate(.cgPoint, &point), let sv = AXValueCreate(.cgSize, &size) else { return }
        // Size, then position, then size again: some apps clamp the size to the old screen.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
    }

    /// Height of the main display, which anchors both coordinate systems.
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func axRect(fromCocoa r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func screen(containing axFrame: CGRect) -> NSScreen? {
        var best: NSScreen?, bestArea: CGFloat = 0
        for s in NSScreen.screens {
            let overlap = axRect(fromCocoa: s.frame).intersection(axFrame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea { best = s; bestArea = area }
        }
        return best ?? NSScreen.main
    }
}

/// Snaps an app's first window into a fixed place when the app opens
/// (Shortcuts › When an app opens, Advanced mode).
final class LaunchPlacer {
    static let shared = LaunchPlacer()
    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            let s = SettingsStore.shared.settings
            guard s.enabled, s.isOn(.windowSnapping), let position = s.launchPositions[id] else { return }
            self?.place(app, position, attempt: 0)
        }
    }

    /// The window appears a moment after the app starts: try for a few seconds.
    private func place(_ app: NSRunningApplication, _ position: LaunchPosition, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.6 : 0.5)) { [weak self] in
            guard !app.isTerminated else { return }
            if let window = AX.windows(of: app.processIdentifier).first(where: { AX.isStandardWindow($0) }) {
                WindowSnapper.perform(position.place, window: window)
                Log.breadcrumb("Placed \(position.name) → \(position.place.title)")
            } else if attempt < 8 {
                self?.place(app, position, attempt: attempt + 1)
            }
        }
    }
}
