import Carbon.HIToolbox
import XMonadCore

/// Turns config key names into virtual key codes.
enum KeyCodes {
    static let named: [String: Int] = [
        "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space,
        "escape": kVK_Escape, "esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
        "forwarddelete": kVK_ForwardDelete, "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        // Punctuation by US position; layout lookup below wins when the
        // character exists unshifted on the user's layout.
        "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash,
        "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "semicolon": kVK_ANSI_Semicolon,
        "quote": kVK_ANSI_Quote, "leftbracket": kVK_ANSI_LeftBracket,
        "rightbracket": kVK_ANSI_RightBracket, "backslash": kVK_ANSI_Backslash,
        "grave": kVK_ANSI_Grave,
    ]
    static let punctuation: [String: Character] = [
        "comma": ",", "period": ".", "slash": "/", "minus": "-", "equal": "=", "semicolon": ";",
        "quote": "'", "leftbracket": "[", "rightbracket": "]", "backslash": "\\", "grave": "`",
    ]
    static let ansi: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
        "9": kVK_ANSI_9,
    ]

    /// Character typed by each key with no modifiers on the current layout.
    static func layoutMap() -> [Character: Int] {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var map: [Character: Int] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in 0..<128 {
                var dead: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var len = 0
                let st = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &dead, chars.count, &len, &chars)
                guard st == noErr, len == 1, let c = String(utf16CodeUnits: chars, count: len).lowercased().first,
                      map[c] == nil else { continue }
                map[c] = code
            }
        }
        return map
    }

    static func code(for key: String, layout: [Character: Int]) -> Int? {
        if key.count == 1, let c = key.first {
            return layout[c] ?? ansi[c]
        }
        if let c = punctuation[key], let code = layout[c] { return code }
        return named[key]
    }

    static func carbonMask(_ mods: Set<Modifier>) -> UInt32 {
        var m = 0
        if mods.contains(.cmd) { m |= cmdKey }
        if mods.contains(.ctrl) { m |= controlKey }
        if mods.contains(.alt) { m |= optionKey }
        if mods.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }
}
