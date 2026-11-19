import AppKit
import Carbon.HIToolbox

/// Global keyboard shortcuts (Shortcuts page). Uses the system's hot key
/// registration, so the keys are caught in every app without needing
/// Input Monitoring, and they don't reach the app in front.
final class HotKeyCenter: ObservableObject {
    static let shared = HotKeyCenter()

    /// Shortcuts macOS or another app already uses (they couldn't be taken).
    @Published private(set) var taken: Set<UUID> = []

    /// Runs an action (set by the engine).
    var run: ((ActionConfig, Shortcut) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: (ActionConfig, Shortcut)] = [:]
    private var bindings: [KeyBinding] = []
    private var enabled = false
    private var pauseCount = 0
    private var hasRegistered = false
    private var handler: EventHandlerRef?

    private init() {}

    /// Registers the shortcuts again (called whenever settings change).
    func update(_ bindings: [KeyBinding], enabled: Bool) {
        if bindings == self.bindings && enabled == self.enabled && pauseCount == 0 && hasRegistered { return }
        hasRegistered = true
        self.bindings = bindings
        self.enabled = enabled
        register()
    }

    /// While a shortcut is being recorded, our own shortcuts are released.
    func pause() {
        pauseCount += 1
        unregisterAll()
    }

    func resume() {
        pauseCount = max(0, pauseCount - 1)
        if pauseCount == 0 { register() }
    }

    private func register() {
        unregisterAll()
        guard enabled, pauseCount == 0 else { return }
        installHandler()
        var number: UInt32 = 1
        var seen = Set<String>()
        var failed = Set<UUID>()
        for b in bindings {
            guard let s = b.shortcut, b.action.kind != .macDefault else { continue }
            // A plain key (no ⌘, ⌥ or ⌃) would swallow normal typing.
            guard s.isSafeEverywhere else { failed.insert(b.id); continue }
            let key = "\(s.keyCode)-\(s.modifiers)"
            guard seen.insert(key).inserted else { failed.insert(b.id); continue }   // used twice
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5450_5453), id: number)   // 'TPTS'
            let status = RegisterEventHotKey(UInt32(s.keyCode), Self.carbonModifiers(s.flags), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref = ref {
                refs.append(ref)
                actions[number] = (b.action, s)
            } else {
                failed.insert(b.id)
            }
            number += 1
        }
        if failed != taken {
            taken = failed
            if !failed.isEmpty { Log.warn("\(failed.count) keyboard shortcut(s) are already in use elsewhere or set twice") }
        }
    }

    private func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        actions = [:]
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            if status == noErr { HotKeyCenter.shared.fire(hotKey.id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    fileprivate func fire(_ id: UInt32) {
        guard let (action, shortcut) = actions[id] else { return }
        DispatchQueue.main.async { [weak self] in self?.run?(action, shortcut) }
    }

    private static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.maskCommand) { m |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { m |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { m |= UInt32(optionKey) }
        if flags.contains(.maskControl) { m |= UInt32(controlKey) }
        return m
    }
}
