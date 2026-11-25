import AppKit
import KachelCore

/// `send-key cmd-w`: a real key press to the front app, like skhd --key.
enum KeySender {
    /// Marks Kachel's own key presses, so its event tap lets them pass
    /// instead of taking them for one of its shortcuts.
    static let marker: Int64 = 0x4B43_484C       // "KCHL"

    /// Exactly the given modifiers: the mod key you still hold while the
    /// shortcut fires doesn't leak in (left-alt + q must send ⌘W, not ⌥⌘W).
    static func send(_ chord: KeyChord) {
        guard let code = KeyCodes.code(for: chord.key, layout: KeyCodes.layoutMap()) else {
            Log.info("send-key: unknown key '\(chord.key)'")
            return
        }
        var flags: CGEventFlags = []
        if chord.modifiers.contains(.cmd) { flags.insert(.maskCommand) }
        if chord.modifiers.contains(.ctrl) { flags.insert(.maskControl) }
        if chord.modifiers.contains(.alt) { flags.insert(.maskAlternate) }
        if chord.modifiers.contains(.shift) { flags.insert(.maskShift) }
        // A private source: the events don't depend on (or change) the real
        // modifier state.
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cghidEventTap)
        }
        Log.info("send-key \(chord)")
    }
}
