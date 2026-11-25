/// The shortcut overview's content: every binding in plain words, grouped,
/// with runs like ⌥1 … ⌥9 folded into one line.
public enum ShortcutList {
    public struct Row: Equatable {
        public var keys: String          // "⌥⇧J", "⌥1 … 9"
        public var label: String
    }
    public struct Group: Equatable {
        public var title: String
        public var rows: [Row]
    }

    public static let order = ["Workspaces", "Windows", "Layout", "Displays", "Tools"]

    public static func groups(_ keys: [KeyChord: Command], workspaces: [String]) -> [Group] {
        var byGroup: [String: [(sort: String, row: Row)]] = [:]

        // Fold numbered runs: the same modifiers and command kind for 1…9.
        var folded: [String: (mods: Set<Modifier>, keys: [String], label: String, group: String)] = [:]
        var rest: [(KeyChord, Command)] = []
        for (chord, cmd) in keys {
            if Int(chord.key) != nil, let (kind, label, group) = numbered(cmd) {
                let id = glyphs(chord.modifiers) + kind
                folded[id, default: (chord.modifiers, [], label, group)].keys.append(chord.key)
            } else {
                rest.append((chord, cmd))
            }
        }
        for (_, f) in folded {
            let ks = f.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
            let mods = glyphs(f.mods)
            let text = ks.count > 2 ? "\(mods)\(ks.first!) … \(ks.last!)" : ks.map { mods + $0 }.joined(separator: " ")
            byGroup[f.group, default: []].append(("0" + f.label, Row(keys: text, label: f.label)))
        }
        for (chord, cmd) in rest {
            let (label, group) = describe(cmd)
            byGroup[group, default: []].append((label, Row(keys: glyphs(chord), label: label)))
        }
        return order.compactMap { title in
            guard let rows = byGroup[title], !rows.isEmpty else { return nil }
            return Group(title: title, rows: rows.sorted { $0.sort < $1.sort }.map(\.row))
        }
    }

    /// Commands that come in a 1…9 series: (kind, label, group).
    static func numbered(_ c: Command) -> (String, String, String)? {
        switch c {
        case .greedyView: return ("gv", "Show workspace", "Workspaces")
        case .view: return ("v", "Go to workspace", "Workspaces")
        case .shift: return ("sh", "Move window to workspace", "Workspaces")
        case .focusScreen: return ("fs", "Focus display", "Displays")
        case .shiftToScreen: return ("ss", "Move window to display", "Displays")
        default: return nil
        }
    }

    public static func describe(_ c: Command) -> (label: String, group: String) {
        switch c {
        case .greedyView(let i): return ("Show workspace \(i + 1)", "Workspaces")
        case .view(let i): return ("Go to workspace \(i + 1)", "Workspaces")
        case .shift(let i): return ("Move window to workspace \(i + 1)", "Workspaces")
        case .workspaceBack: return ("Previous workspace (back and forth)", "Workspaces")
        case .workspaceNext: return ("Next workspace", "Workspaces")
        case .workspacePrev: return ("Previous workspace", "Workspaces")
        case .shiftNext: return ("Move window to next workspace", "Workspaces")
        case .shiftPrev: return ("Move window to previous workspace", "Workspaces")
        case .focusDown: return ("Focus next window", "Windows")
        case .focusUp: return ("Focus previous window", "Windows")
        case .focusMaster: return ("Focus master", "Windows")
        case .swapDown: return ("Swap with next window", "Windows")
        case .swapUp: return ("Swap with previous window", "Windows")
        case .swapMaster: return ("Swap with master", "Windows")
        case .focusDirection(let d): return ("Focus window \(d.rawValue)", "Windows")
        case .swapDirection(let d): return ("Swap with window \(d.rawValue)", "Windows")
        case .toggleFloat: return ("Float / tile window", "Windows")
        case .close: return ("Close window", "Windows")
        case .sendKey(let c): return ("Send \(glyphs(c.modifiers))\(c.key.uppercased())", "Tools")
        case .nextLayout: return ("Next layout", "Layout")
        case .toggleFullscreen: return ("Toggle fullscreen", "Layout")
        case .shrink: return ("Narrower master", "Layout")
        case .expand: return ("Wider master", "Layout")
        case .incMaster: return ("More windows in master", "Layout")
        case .decMaster: return ("Fewer windows in master", "Layout")
        case .taller: return ("Taller window", "Layout")
        case .shorter: return ("Shorter window", "Layout")
        case .resetSizes: return ("Reset sizes", "Layout")
        case .focusScreen(let s): return ("Focus display \(s + 1)", "Displays")
        case .shiftToScreen(let s): return ("Move window to display \(s + 1)", "Displays")
        case .focusNextScreen: return ("Focus next display", "Displays")
        case .focusPrevScreen: return ("Focus previous display", "Displays")
        case .shiftToNextScreen: return ("Move window to next display", "Displays")
        case .shiftToPrevScreen: return ("Move window to previous display", "Displays")
        case .windowSearch: return ("Search windows", "Tools")
        case .appRule: return ("Always open app on…", "Tools")
        case .scratchpad(let n): return ("Scratchpad \(n)", "Tools")
        case .terminal: return ("Terminal", "Tools")
        case .spawn(let cmd): return ("Run \(cmd.count > 28 ? String(cmd.prefix(27)) + "…" : cmd)", "Tools")
        case .refresh: return ("Re-tile", "Tools")
        case .reload: return ("Reload config", "Tools")
        case .restart: return ("Restart Kachel", "Tools")
        case .quit: return ("Quit Kachel", "Tools")
        case .settings: return ("Settings", "Tools")
        case .welcome: return ("Welcome and setup check", "Tools")
        case .shortcuts: return ("Show shortcuts", "Tools")
        case .setLayout(let k): return ("Layout: \(k.rawValue)", "Layout")
        case .prevLayout: return ("Previous layout", "Layout")
        case .toggleTiling: return ("Pause / resume tiling", "Layout")
        case .increaseWindowLimit: return ("More tiled windows", "Layout")
        case .decreaseWindowLimit: return ("Fewer tiled windows", "Layout")
        case .toggleFocusFollowsMouse: return ("Focus follows pointer on / off", "Tools")
        }
    }

    /// macOS order and symbols: ⌃ ⌥ ⇧ ⌘.
    public static func glyphs(_ mods: Set<Modifier>) -> String {
        [(Modifier.ctrl, "⌃"), (.alt, "⌥"), (.shift, "⇧"), (.cmd, "⌘")]
            .filter { mods.contains($0.0) }.map(\.1).joined()
    }

    public static func glyphs(_ chord: KeyChord) -> String {
        glyphs(chord.modifiers) + keyGlyph(chord.key)
    }

    public static func keyGlyph(_ key: String) -> String {
        switch key {
        case "return", "enter": return "↩"
        case "tab": return "⇥"
        case "space": return "Space"
        case "escape", "esc": return "⎋"
        case "delete", "backspace": return "⌫"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "comma": return ","
        case "period": return "."
        case "slash": return "/"
        case "minus": return "-"
        case "equal": return "="
        case "semicolon": return ";"
        case "quote": return "'"
        case "grave": return "`"
        case "leftbracket": return "["
        case "rightbracket": return "]"
        case "backslash": return "\\"
        default: return key.count == 1 ? key.uppercased() : key.uppercased()
        }
    }
}


extension Command {
    /// How this command is written in config.yaml (parseCommand's inverse).
    public var configText: String {
        switch self {
        case .greedyView(let i): return "workspace \(i + 1)"
        case .view(let i): return "view \(i + 1)"
        case .shift(let i): return "shift \(i + 1)"
        case .focusScreen(let s): return "focus-screen \(s + 1)"
        case .shiftToScreen(let s): return "shift-to-screen \(s + 1)"
        case .focusDirection(let d): return "focus \(d.rawValue)"
        case .swapDirection(let d): return "swap \(d.rawValue)"
        case .scratchpad(let n): return "scratchpad \(n)"
        case .sendKey(let c): return "send-key \(c.description)"
        case .spawn(let cmd): return "spawn \(cmd)"
        case .setLayout(let k): return "layout \(k.configName)"
        default:
            // The rest are single words: focusDown → focus-down.
            return String(describing: self).reduce(into: "") { s, ch in
                if ch.isUppercase { s += "-" + ch.lowercased() } else { s.append(ch) }
            }
        }
    }
}
