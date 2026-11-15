import AppKit
import KachelCore

/// Who else uses a key combination: another Kachel binding, a macOS shortcut
/// (System Settings → Keyboard → Keyboard Shortcuts), or skhd.
enum KeyUse {
    static func conflict(for chord: KeyChord, ignoring: KeyChord?, keys: [KeyChord: Command]) -> String? {
        if chord != ignoring, let c = keys[chord] {
            return "Kachel uses it for “\(ShortcutList.describe(c).label)”. That shortcut will be replaced."
        }
        if let what = macOS()[chord] { return "macOS uses it for “\(what)”." }
        if let action = skhd()[chord] { return "skhd uses it (\(action))." }
        return nil
    }

    // MARK: macOS

    private static let names: [Int: String] = [
        7: "Move focus to the menu bar", 8: "Move focus to the Dock", 9: "Move focus to the active window",
        10: "Move focus to the window toolbar", 11: "Move focus to the floating window", 27: "Move focus to the next window",
        28: "Save picture of screen as a file", 29: "Copy picture of screen", 30: "Save picture of selected area",
        31: "Copy picture of selected area", 32: "Mission Control", 33: "Application windows", 36: "Show Desktop",
        52: "Turn Dock hiding on/off", 60: "Select the previous input source", 61: "Select next source in Input menu",
        64: "Show Spotlight search", 65: "Show Finder search window", 79: "Move left a space", 81: "Move right a space",
        118: "Switch to Desktop 1", 119: "Switch to Desktop 2", 120: "Switch to Desktop 3", 121: "Switch to Desktop 4",
        122: "Switch to Desktop 5", 123: "Switch to Desktop 6", 124: "Switch to Desktop 7", 125: "Switch to Desktop 8",
        126: "Switch to Desktop 9", 162: "Accessibility controls", 184: "Screenshot and recording options",
    ]

    /// macOS's own shortcuts: a few fixed ones plus everything enabled under
    /// System Settings → Keyboard → Keyboard Shortcuts.
    static func macOS() -> [KeyChord: String] {
        var out: [KeyChord: String] = [
            KeyChord(modifiers: [.cmd], key: "tab"): "Switch apps",
            KeyChord(modifiers: [.cmd], key: "space"): "Show Spotlight search",
            KeyChord(modifiers: [.cmd, .shift], key: "3"): "Save picture of screen as a file",
            KeyChord(modifiers: [.cmd, .shift], key: "4"): "Save picture of selected area",
            KeyChord(modifiers: [.cmd, .shift], key: "5"): "Screenshot and recording options",
            KeyChord(modifiers: [.ctrl, .cmd], key: "q"): "Lock Screen",
            KeyChord(modifiers: [.cmd], key: "q"): "Quit the app",
            KeyChord(modifiers: [.cmd], key: "w"): "Close the window",
            KeyChord(modifiers: [.cmd], key: "h"): "Hide the app",
            KeyChord(modifiers: [.cmd], key: "m"): "Minimize the window",
        ]
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        guard let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                  "com.apple.symbolichotkeys" as CFString) as? [String: Any] else { return out }
        let reverse = keyNames()
        for (id, entry) in all {
            guard let e = entry as? [String: Any], let value = e["value"] as? [String: Any],
                  let params = value["parameters"] as? [Int], params.count == 3,
                  let name = reverse[params[1]] else { continue }
            var mods: Set<Modifier> = []
            if params[2] & 131072 != 0 { mods.insert(.shift) }
            if params[2] & 262144 != 0 { mods.insert(.ctrl) }
            if params[2] & 524288 != 0 { mods.insert(.alt) }
            if params[2] & 1048576 != 0 { mods.insert(.cmd) }
            let chord = KeyChord(modifiers: mods, key: name)
            if (e["enabled"] as? Bool) == true {
                out[chord] = names[Int(id) ?? -1] ?? "a macOS keyboard shortcut"
            } else {
                out[chord] = nil
            }
        }
        return out
    }

    /// Virtual key code → Kachel's key name.
    private static func keyNames() -> [Int: String] {
        var r: [Int: String] = [:]
        for (c, code) in KeyCodes.ansi { r[code] = String(c) }
        for (c, code) in KeyCodes.layoutMap() where c.isLetter || c.isNumber { r[code] = String(c) }
        for (n, code) in KeyCodes.named where !["enter", "esc", "backspace"].contains(n) { r[code] = n }
        return r
    }

    // MARK: skhd

    static func skhd() -> [KeyChord: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for path in [".config/skhd/skhdrc", ".skhdrc"] {
            if let text = try? String(contentsOf: home.appendingPathComponent(path), encoding: .utf8) {
                return KeyConflicts.skhd(text)
            }
        }
        return [:]
    }
}
