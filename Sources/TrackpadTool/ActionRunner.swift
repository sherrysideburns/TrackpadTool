import AppKit
import ApplicationServices
import Carbon

// MARK: - Accessibility helpers

enum AX {
    /// Our own process. Accessibility requests to ourselves are answered by
    /// our main thread, which is the one asking, so they can only time out.
    static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Caps every Accessibility request at half a second (the system default
    /// is about 6 s, which froze the app when another app didn't answer).
    /// Set on the system-wide element, it applies to all elements.
    static func limitWaiting() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        guard pid != ownPID else { return [] }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ on: Bool) -> Bool {
        let value: CFBoolean = on ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    static func isStandardWindow(_ window: AXUIElement) -> Bool {
        string(window, kAXSubroleAttribute as String) == (kAXStandardWindowSubrole as String)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Bring an app to the front, even though this app runs in the background.
    static func activate(_ app: NSRunningApplication) {
        if app.processIdentifier == ownPID {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        set(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute as String, true)
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

/// Apps that show up in the Dock (not menu bar helpers or background tools).
func regularApps() -> [NSRunningApplication] {
    let me = ProcessInfo.processInfo.processIdentifier
    return NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
    }
}

// MARK: - Actions

final class ActionRunner {
    static let shared = ActionRunner()

    /// Apps hidden by "Hide all apps", so "Restore" brings back exactly those.
    private var hiddenByUs: [pid_t] = []
    /// Windows minimized by "Minimize all windows".
    private var minimizedByUs: [AXUIElement] = []
    /// The app that was in front before hiding/minimizing.
    private var frontBefore: pid_t?

    private init() {}

    func run(_ config: ActionConfig) {
        switch config.kind {
        case .macDefault, .doNothing:
            break
        case .hideAllApps:
            hideAll()
        case .restoreHiddenApps:
            restore()
        case .minimizeAllWindows:
            minimizeAll()
        case .windowSwitcher:
            WindowSwitcher.shared.quickSwitch()
        case .minimizeWindow:
            minimizeFrontWindow()
        case .restoreMinimizedWindow:
            restoreLastMinimized()
        case .snapLeft, .snapRight, .snapTop, .snapBottom, .snapTopLeft, .snapTopRight, .snapBottomLeft,
             .snapBottomRight, .snapLeftThird, .snapCenterThird, .snapRightThird, .snapLeftTwoThirds,
             .snapRightTwoThirds, .maximizeWindow, .toggleMaximizeWindow, .centerWindow, .restoreWindowSize,
             .moveToNextDisplay:
            WindowSnapper.perform(config.kind)
        case .maximizeAllWindows:
            WindowSnapper.maximizeAll()
        case .nextTab, .previousTab, .newTab, .closeTab, .reopenTab,
             .copy, .paste, .cut, .undo, .redo, .pasteWithoutFormatting, .selectAll,
             .find, .findNext, .save, .newDocument, .lockScreen:
            // Menu shortcuts go by the letter, which sits elsewhere on
            // AZERTY, QWERTZ or Dvorak: press the key that types it here.
            if let k = config.kind.keys { post(keyCode: KeyLayout.localCode(forUSKey: k.code), flags: k.flags) }
        case .deleteWord, .lineStart, .lineEnd, .documentStart, .documentEnd, .emojiPicker:
            // These go by key position (or are keys like arrows and Space).
            if let k = config.kind.keys { post(keyCode: k.code, flags: k.flags) }
        case .screenshotArea, .screenshotScreen, .screenshotAreaToClipboard, .screenshotScreenToClipboard,
             .screenshotToolbar, .previousSpace, .nextSpace, .spotlight:
            runSystemShortcut(config.kind)
        case .screenshotWindow:
            // Window mode straight away, so no Space key can end up in the front app.
            Screenshot.captureWindow()
        case .missionControl:
            Dock.send("com.apple.expose.awake", fallbackArgument: nil)
        case .appExpose:
            Dock.send("com.apple.expose.front.awake", fallbackArgument: "2")
        case .showDesktop:
            Dock.send("com.apple.showdesktop.awake", fallbackArgument: "1")
        case .launchpad:
            Dock.openLaunchpad()
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute:
            if let key = config.kind.mediaKey { postMediaKey(key) }
        case .stageSwitcher, .previousStage:
            WindowSwitcher.shared.quickSwitch(mode: .apps)
        case .toggleStageManager:
            StageManager.toggle()
        case .toggleStageStrip:
            StageManager.toggleStrip()
        case .keyboardShortcut:
            if let s = config.shortcut { post(keyCode: s.keyCode, flags: s.flags) }
        case .openApp:
            if let url = config.resolvedAppURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else if config.appPath != nil || config.appID != nil {
                GlassHUD.shared.show(symbol: "questionmark.app", text: "That app isn't installed on this Mac")
            }
        case .forceQuit:
            // The Force Quit window checks that ⌘ and ⌥ are really held down.
            post(keyCode: 53, flags: [.maskCommand, .maskAlternate], pressModifiers: true)   // ⌘⌥⎋
        case .middleClick:
            middleClick()
        }
    }

    // MARK: Hide all / restore

    func hideAll() {
        let apps = regularApps().filter { !$0.isHidden }
        guard !apps.isEmpty else { return }
        if hiddenByUs.isEmpty && minimizedByUs.isEmpty {
            frontBefore = frontOtherApp()
        }
        for app in apps {
            if !hiddenByUs.contains(app.processIdentifier) { hiddenByUs.append(app.processIdentifier) }
            if !app.hide() {
                AX.set(AXUIElementCreateApplication(app.processIdentifier), kAXHiddenAttribute as String, true)
            }
        }
    }

    func restore() {
        for pid in hiddenByUs.reversed() {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { continue }
            if !app.unhide() {
                AX.set(AXUIElementCreateApplication(pid), kAXHiddenAttribute as String, false)
            }
        }
        for window in minimizedByUs {
            AX.set(window, kAXMinimizedAttribute as String, false)
        }
        if let pid = frontBefore, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { AX.activate(app) }
        }
        hiddenByUs = []
        minimizedByUs = []
        frontBefore = nil
    }

    /// The frontmost app, unless that's TrackpadTool itself (its Settings).
    private func frontOtherApp() -> pid_t? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != AX.ownPID else { return nil }
        return pid
    }

    /// Called when the switcher brings back an app, so Restore doesn't fight it.
    func forget(pid: pid_t) {
        hiddenByUs.removeAll { $0 == pid }
    }

    // MARK: One window

    /// Windows minimized one at a time, newest last, so they come back in reverse order.
    private var minimizedSingles: [(window: AXUIElement, pid: pid_t)] = []

    func minimizeFrontWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != AX.ownPID,
              let window = WindowSnapper.focusedWindow() else { return }
        if AX.set(window, kAXMinimizedAttribute as String, true) {
            minimizedSingles.append((window, app.processIdentifier))
            if minimizedSingles.count > 50 { minimizedSingles.removeFirst() }
        }
    }

    func restoreLastMinimized() {
        // Skip windows that were closed or brought back some other way.
        while let last = minimizedSingles.popLast() {
            guard let app = NSRunningApplication(processIdentifier: last.pid), !app.isTerminated,
                  AX.bool(last.window, kAXMinimizedAttribute as String) == true else { continue }
            AX.set(last.window, kAXMinimizedAttribute as String, false)
            AX.activate(app)
            AXUIElementPerformAction(last.window, kAXRaiseAction as CFString)
            return
        }
    }

    // MARK: Minimize all

    func minimizeAll() {
        if hiddenByUs.isEmpty && minimizedByUs.isEmpty {
            frontBefore = frontOtherApp()
        }
        for app in regularApps() where !app.isHidden {
            for window in AX.windows(of: app.processIdentifier)
            where AX.isStandardWindow(window) && AX.bool(window, kAXMinimizedAttribute as String) == false {
                if AX.set(window, kAXMinimizedAttribute as String, true) {
                    minimizedByUs.append(window)
                }
            }
        }
    }

    // MARK: Input events

    /// Presses a key combination. With `pressModifiers`, ⌘ ⌥ ⌃ ⇧ are
    /// pressed and released as real keys around it, for the parts of macOS
    /// that check which modifier keys are down rather than the key's flags.
    func post(keyCode: UInt16, flags: CGEventFlags, pressModifiers: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifierKeys: [(key: UInt16, flag: CGEventFlags)] = [
            (59, .maskControl), (58, .maskAlternate), (56, .maskShift), (55, .maskCommand),
        ]
        let pressed = pressModifiers ? modifierKeys.filter { flags.contains($0.flag) } : []
        var held: CGEventFlags = []
        for m in pressed {
            held.insert(m.flag)
            let e = CGEvent(keyboardEventSource: source, virtualKey: m.key, keyDown: true)
            e?.flags = held
            e?.post(tap: .cghidEventTap)
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        for m in pressed.reversed() {
            held.remove(m.flag)
            let e = CGEvent(keyboardEventSource: source, virtualKey: m.key, keyDown: false)
            e?.flags = held
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Screenshots, Spotlight and Spaces: presses the shortcut set for them
    /// in System Settings › Keyboard › Keyboard Shortcuts, which may differ
    /// from the standard one. If it's switched off, screenshots are taken
    /// directly; for the others a note says where to switch it on.
    private func runSystemShortcut(_ kind: ActionKind) {
        guard let id = SystemShortcuts.id(for: kind) else { return }
        switch SystemShortcuts.current(id) {
        case .some(.on(let code, let flags)):
            post(keyCode: code, flags: flags, pressModifiers: true)
        case .some(.off):
            if !Screenshot.takeDirectly(kind) {
                GlassHUD.shared.show(symbol: "keyboard",
                                     text: "\(kind.title) is off in Keyboard Shortcuts")
            }
        case .none:
            // Never changed: the standard shortcut.
            if let k = kind.keys { post(keyCode: k.code, flags: k.flags, pressModifiers: true) }
        }
    }

    /// Presses a media key (play, skip, volume) the way the keyboard does:
    /// a "system defined" event with the key type, down and then up.
    func postMediaKey(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    func middleClick() {
        let source = CGEventSource(stateID: .hidSystemState)
        let location = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: source, mouseType: .otherMouseDown,
                mouseCursorPosition: location, mouseButton: .center)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .otherMouseUp,
                mouseCursorPosition: location, mouseButton: .center)?.post(tap: .cghidEventTap)
    }
}

// MARK: - Dock features (Mission Control, App Exposé, Show Desktop, Launchpad)

/// Asks the Dock directly, the way the trackpad gestures and F3 do, so these
/// work whatever keyboard shortcuts are set and need no Accessibility.
enum Dock {
    private typealias SendFn = @convention(c) (CFString, Int32) -> Void

    /// CoreDockSendNotification lives in a private part of ApplicationServices.
    private static let sendFn: SendFn? = {
        let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        guard let sym = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else {
            Log.info("CoreDockSendNotification not found; using Mission Control.app instead")
            return nil
        }
        return unsafeBitCast(sym, to: SendFn.self)
    }()

    private static let missionControlApp: URL? = {
        for p in ["/System/Applications/Mission Control.app", "/Applications/Mission Control.app"]
        where FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }()

    /// Sends a Dock notification; without the private call, starts
    /// Mission Control.app (no argument = Mission Control, "1" = Show
    /// Desktop, "2" = App Exposé).
    static func send(_ name: String, fallbackArgument: String?) {
        if let send = sendFn {
            send(name as CFString, 0)
            return
        }
        guard let app = missionControlApp else { return }
        if let arg = fallbackArgument {
            let exe = app.appendingPathComponent("Contents/MacOS/Mission Control")
            let p = Process()
            p.executableURL = exe
            p.arguments = [arg]
            do { try p.run() } catch { Log.error("Couldn’t start Mission Control: \(error.localizedDescription)") }
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Newer macOS replaced Launchpad with the Apps view; open whichever exists.
    static func openLaunchpad() {
        for p in ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app", "/Applications/Launchpad.app"]
        where FileManager.default.fileExists(atPath: p) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: p), configuration: NSWorkspace.OpenConfiguration())
            return
        }
        send("com.apple.launchpad.toggle", fallbackArgument: nil)
    }
}

// MARK: - Keyboard layouts

/// Finds the key that types a letter in the keyboard layout in use, so
/// "Copy" presses ⌘C on AZERTY, QWERTZ and Dvorak too, not the key that
/// happens to be C on a US keyboard.
enum KeyLayout {
    /// The letter each US key position types, for the shortcuts we press.
    private static let usLetters: [UInt16: Character] = [
        0: "a", 1: "s", 3: "f", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        12: "q", 13: "w", 17: "t", 30: "]", 33: "[", 45: "n",
    ]
    private static var map: [Character: UInt16] = [:]
    private static var observer: NSObjectProtocol?

    /// The key code to press for a shortcut written for a US keyboard.
    /// Keeps the US key when the layout has no such letter (Cyrillic, Greek:
    /// macOS then reads ⌘ shortcuts as US anyway).
    static func localCode(forUSKey code: UInt16) -> UInt16 {
        guard let letter = usLetters[code] else { return code }
        return self.code(for: letter) ?? code
    }

    static func code(for char: Character) -> UInt16? {
        if observer == nil {
            observer = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil, queue: .main) { _ in map = [:] }
        }
        if map.isEmpty { rebuild() }
        return map[char]
    }

    private static func rebuild() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<128 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                guard UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                     OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 4, &length, &chars) == noErr,
                      length == 1,
                      let c = String(utf16CodeUnits: chars, count: length).lowercased().first,
                      map[c] == nil else { continue }
                map[c] = code
            }
        }
    }
}

// MARK: - System shortcuts (System Settings › Keyboard › Keyboard Shortcuts)

enum SystemShortcuts {
    enum State {
        case on(code: UInt16, flags: CGEventFlags)
        case off
    }

    /// macOS's numbers for these shortcuts.
    static func id(for kind: ActionKind) -> Int? {
        switch kind {
        case .screenshotScreen: return 28
        case .screenshotScreenToClipboard: return 29
        case .screenshotArea: return 30
        case .screenshotAreaToClipboard: return 31
        case .screenshotToolbar: return 184
        case .spotlight: return 64
        case .previousSpace: return 79
        case .nextSpace: return 81
        default: return nil
        }
    }

    /// The shortcut as set now; nil if it was never changed (standard one).
    static func current(_ id: Int) -> State? {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        guard let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any],
              let entry = all[String(id)] as? [String: Any] else { return nil }
        if let enabled = entry["enabled"] as? Bool, !enabled { return .off }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int], parameters.count >= 3 else { return nil }
        let code = parameters[1]
        guard code >= 0, code < 128 else { return .off }   // 65535 = no key set
        // Same bit layout as CGEventFlags (⇧ 0x20000, ⌃ 0x40000, ⌥ 0x80000, ⌘ 0x100000, fn 0x800000).
        return .on(code: UInt16(code), flags: CGEventFlags(rawValue: UInt64(parameters[2])))
    }
}

// MARK: - Screenshots without a shortcut

enum Screenshot {
    /// Takes a screenshot with the screencapture tool, for when its shortcut
    /// is switched off. false = not a screenshot action.
    static func takeDirectly(_ kind: ActionKind) -> Bool {
        let args: [String]
        switch kind {
        case .screenshotScreen: args = [fileArgument()]
        case .screenshotScreenToClipboard: args = ["-c"]
        case .screenshotArea: args = ["-i", fileArgument()]
        case .screenshotAreaToClipboard: args = ["-i", "-c"]
        case .screenshotToolbar: args = ["-i", "-U"]
        default: return false
        }
        run(args)
        return true
    }

    private static var prefs: UserDefaults? { UserDefaults(suiteName: "com.apple.screencapture") }
    private static var type: String { prefs?.string(forKey: "type") ?? "png" }

    /// Where macOS saves screenshots, with the same kind of name.
    private static func fileArgument() -> String {
        let folder = prefs?.string(forKey: "location").map { ($0 as NSString).expandingTildeInPath }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return (folder as NSString).appendingPathComponent("Screenshot \(formatter.string(from: Date())).\(type)")
    }

    private static func run(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-t", type] + args
        do { try process.run() } catch { Log.error("Couldn’t start screencapture: \(error.localizedDescription)") }
    }

    /// Lets you click a window and saves it where macOS saves screenshots,
    /// with the same kind of name.
    static func captureWindow() {
        run(["-i", "-W", fileArgument()])
    }
}
