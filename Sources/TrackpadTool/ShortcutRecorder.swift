import AppKit
import SwiftUI

extension Shortcut {
    init(event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var flags: CGEventFlags = []
        var symbols = ""
        if mods.contains(.control) { flags.insert(.maskControl); symbols += "⌃" }
        if mods.contains(.option) { flags.insert(.maskAlternate); symbols += "⌥" }
        if mods.contains(.shift) { flags.insert(.maskShift); symbols += "⇧" }
        if mods.contains(.command) { flags.insert(.maskCommand); symbols += "⌘" }
        if mods.contains(.function) { flags.insert(.maskSecondaryFn) }
        self.init(keyCode: event.keyCode,
                  modifiers: flags.rawValue,
                  display: symbols + Shortcut.keyName(event.keyCode, event.charactersIgnoringModifiers))
    }

    /// The label for a key code and modifiers, worked out from the keys
    /// themselves. Used for imported combos, so a file can't show one
    /// shortcut while pressing another.
    static func label(keyCode: UInt16, modifiers: UInt64) -> String {
        let flags = CGEventFlags(rawValue: modifiers)
        var symbols = ""
        if flags.contains(.maskControl) { symbols += "⌃" }
        if flags.contains(.maskAlternate) { symbols += "⌥" }
        if flags.contains(.maskShift) { symbols += "⇧" }
        if flags.contains(.maskCommand) { symbols += "⌘" }
        let ansi: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
            27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`"
        ]
        let key = ansi[keyCode] ?? keyName(keyCode, "key \(keyCode)")
        return symbols + key
    }

    static func keyName(_ code: UInt16, _ chars: String?) -> String {
        let names: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let name = names[code] { return name }
        return (chars ?? "?").uppercased()
    }
}

/// Listens for the next key combination. (A class instead of @State, because
/// the @State macro needs full Xcode.)
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var recording = false
    private var monitor: Any?

    func start(onRecord: @escaping (Shortcut) -> Void) {
        stop()
        recording = true
        // Our own global shortcuts would catch the keys first; pause them.
        HotKeyCenter.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !(event.keyCode == 53 && mods.isEmpty) {   // Esc alone cancels
                onRecord(Shortcut(event: event))
            }
            self?.stop()
            return nil
        }
    }

    func stop() {
        let was = recording
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if was { HotKeyCenter.shared.resume() }
    }
}

/// A button that records the next key combination you press.
struct ShortcutRecorderButton: View {
    @Binding var shortcut: Shortcut?
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        Button(recorder.recording ? "Press a shortcut… (Esc cancels)" : (shortcut?.display ?? "Record shortcut")) {
            if recorder.recording {
                recorder.stop()
            } else {
                let binding = $shortcut
                recorder.start { binding.wrappedValue = $0 }
            }
        }
        .onDisappear { recorder.stop() }
    }
}
