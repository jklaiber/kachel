import Foundation
import Yams

// Settings come from ~/.config/kachel/config.yaml. The default file below is
// the single source of truth: it is written to disk on first launch and is
// also what any missing setting falls back to.

public enum Modifier: String, CaseIterable {
    case cmd, ctrl, alt, shift
}

public struct KeyChord: Hashable, CustomStringConvertible {
    public var modifiers: Set<Modifier>
    /// Key name as written in the config: "j", "1", "return", "comma", "f5", …
    public var key: String

    public init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public var description: String {
        let order: [Modifier] = [.cmd, .ctrl, .alt, .shift]
        return (order.filter(modifiers.contains).map(\.rawValue) + [key]).joined(separator: "-")
    }
}

public enum Command: Equatable {
    case greedyView(Int)        // 0-based workspace index
    case view(Int)
    case shift(Int)
    case focusScreen(Int)       // 0-based screen index
    case shiftToScreen(Int)
    case focusDown, focusUp, focusMaster
    case swapDown, swapUp, swapMaster
    case nextLayout, shrink, expand, incMaster, decMaster
    case focusNextScreen, focusPrevScreen, shiftToNextScreen, shiftToPrevScreen
    case workspaceNext, workspacePrev, shiftNext, shiftPrev
    case toggleFloat, refresh, close, terminal, reload, restart, quit
    case windowSearch, appRule
    case spawn(String)
}

public enum BarWidget: String, CaseIterable {
    case workspaces, layout, title, cpu, memory, network, date, clock
}

public struct BarSettings: Equatable {
    public var enabled = true
    /// nil = same height as the menu bar at the top.
    public var height: Double?
    public var fontSize: Double = 13
    public var left: [BarWidget] = [.workspaces, .layout, .title]
    public var right: [BarWidget] = [.network, .cpu, .memory, .date, .clock]
    public var hideEmptyWorkspaces = false
    public var clockFormat = "HH:mm"
    public var dateFormat = "EEE d MMM"
    public var interval: Double = 2          // seconds between cpu/memory/network samples
    public var background: Background = .transparent
    public var appearance: Appearance = .auto
    public init() {}

    public enum Background: String { case transparent, blur }
    /// auto = white or black text depending on the wallpaper, like the menu bar.
    public enum Appearance: String { case auto, light, dark }

    public func shows(_ w: BarWidget) -> Bool { left.contains(w) || right.contains(w) }
}

/// Trackpad swipes (needs macOS's own horizontal swipe turned off).
public struct GestureSettings: Equatable {
    public var enabled = true
    public var fingers = 3
    /// workspace-next / -prev from a swipe skip empty workspaces (xmonad's HiddenNonEmptyWS).
    public var skipEmpty = true
    public var left: Command? = .workspaceNext     // fingers move left → like macOS, the space to the right
    public var right: Command? = .workspacePrev
    public var up: Command?
    public var down: Command?
    public init() {}
}

public struct SettingsError: Error, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

public struct Settings {
    public var mod: Set<Modifier> = [.ctrl, .alt]
    public var workspaces = (1...9).map(String.init)
    public var gap: Double = 6
    public var ratio: Double = 0.5
    public var ratioStep: Double = 0.03
    public var mouseFollowsFocus = true
    public var terminal = "open -na Terminal"
    public var floating: Set<String> = []
    public var layouts: [LayoutKind] = [.tall, .mirrorTall, .column, .full]
    public var menubarIcon = false
    public var rules: [Rule] = []
    public var gestures = GestureSettings()
    public var bar = BarSettings()
    public var keys: [KeyChord: Command] = [:]

    public init() {}

    /// Parsed built-in defaults. The default YAML is tested, so this can't fail.
    public static let defaults: Settings = try! Settings.parse(defaultYAML)

    // MARK: - parsing

    public static func parse(_ yaml: String) throws -> Settings {
        let root: Any?
        do { root = try Yams.load(yaml: yaml) } catch { throw SettingsError("YAML: \(error)") }
        var s = Settings()
        // An empty file means "all defaults".
        guard let dict = (root ?? [String: Any]()) as? [String: Any] else {
            throw SettingsError("top level must be a mapping")
        }

        let known: Set<String> = ["mod", "workspaces", "gap", "ratio", "ratio-step", "mouse-follows-focus",
                                  "terminal", "floating", "bar", "keys", "layouts", "menubar-icon", "rules", "gestures"]
        if let bad = dict.keys.first(where: { !known.contains($0) }) {
            throw SettingsError("unknown setting '\(bad)'")
        }

        if let v = dict["mod"] { s.mod = try parseModifiers(string(v, "mod"), "mod") }
        if let v = dict["workspaces"] {
            guard let list = v as? [Any], !list.isEmpty else { throw SettingsError("workspaces must be a non-empty list") }
            s.workspaces = list.map { "\($0)" }
        }
        if let v = dict["gap"] { s.gap = try number(v, "gap") }
        if let v = dict["ratio"] { s.ratio = min(0.9, max(0.1, try number(v, "ratio"))) }
        if let v = dict["ratio-step"] { s.ratioStep = try number(v, "ratio-step") }
        if let v = dict["mouse-follows-focus"] { s.mouseFollowsFocus = try bool(v, "mouse-follows-focus") }
        if let v = dict["terminal"] { s.terminal = try string(v, "terminal") }
        if let v = dict["floating"] {
            guard let list = v as? [Any] else { throw SettingsError("floating must be a list of bundle IDs") }
            s.floating = Set(list.map { "\($0)" })
        }
        if let v = dict["layouts"] {
            guard let list = v as? [Any], !list.isEmpty else { throw SettingsError("layouts must be a non-empty list") }
            s.layouts = try list.map {
                guard let l = LayoutKind(configName: "\($0)") else {
                    throw SettingsError("layouts: unknown layout '\($0)' (use tall, wide, column, full)")
                }
                return l
            }
        }
        if let v = dict["gestures"] {
            guard let g = v as? [String: Any] else { throw SettingsError("gestures must be a mapping") }
            for (k, v) in g {
                func cmd() throws -> Command? {
                    v is NSNull ? nil : try parseCommand("\(v)", workspaceCount: s.workspaces.count, context: "gestures.\(k)")
                }
                switch k {
                case "enabled": s.gestures.enabled = try bool(v, "gestures.enabled")
                case "fingers":
                    let n = Int(try number(v, "gestures.fingers"))
                    guard n == 3 || n == 4 else { throw SettingsError("gestures.fingers must be 3 or 4") }
                    s.gestures.fingers = n
                case "skip-empty": s.gestures.skipEmpty = try bool(v, "gestures.skip-empty")
                case "swipe-left": s.gestures.left = try cmd()
                case "swipe-right": s.gestures.right = try cmd()
                case "swipe-up": s.gestures.up = try cmd()
                case "swipe-down": s.gestures.down = try cmd()
                default: throw SettingsError("unknown setting 'gestures.\(k)'")
                }
            }
        }
        if let v = dict["rules"] { s.rules = try parseRules(v, workspaces: s.workspaces) }
        if let v = dict["menubar-icon"] { s.menubarIcon = try bool(v, "menubar-icon") }
        if let v = dict["bar"] {
            guard let b = v as? [String: Any] else { throw SettingsError("bar must be a mapping") }
            for (k, v) in b {
                switch k {
                case "enabled": s.bar.enabled = try bool(v, "bar.enabled")
                case "height":
                    if let t = v as? String, t == "auto" { s.bar.height = nil }
                    else { s.bar.height = try number(v, "bar.height") }
                case "font-size": s.bar.fontSize = try number(v, "bar.font-size")
                case "left": s.bar.left = try widgets(v, "bar.left")
                case "right": s.bar.right = try widgets(v, "bar.right")
                case "hide-empty-workspaces": s.bar.hideEmptyWorkspaces = try bool(v, "bar.hide-empty-workspaces")
                case "clock-format": s.bar.clockFormat = try string(v, "bar.clock-format")
                case "date-format": s.bar.dateFormat = try string(v, "bar.date-format")
                case "interval": s.bar.interval = max(0.5, try number(v, "bar.interval"))
                case "background":
                    guard let b = BarSettings.Background(rawValue: "\(v)") else {
                        throw SettingsError("bar.background must be transparent or blur")
                    }
                    s.bar.background = b
                case "appearance":
                    guard let a = BarSettings.Appearance(rawValue: "\(v)") else {
                        throw SettingsError("bar.appearance must be auto, light or dark")
                    }
                    s.bar.appearance = a
                // from the first config version
                case "show-title":
                    if try !bool(v, "bar.show-title") { s.bar.left.removeAll { $0 == .title } }
                default: throw SettingsError("unknown setting 'bar.\(k)'")
                }
            }
        }

        // `keys:` replaces the whole default keymap; leave it out to keep the defaults.
        if let v = dict["keys"] {
            guard let k = v as? [String: Any] else { throw SettingsError("keys must be a mapping") }
            s.keys = try parseKeys(k, mod: s.mod, workspaceCount: s.workspaces.count)
        } else {
            s.keys = try parseKeys(try defaultKeyMap(), mod: s.mod, workspaceCount: s.workspaces.count)
        }
        return s
    }

    private static func defaultKeyMap() throws -> [String: Any] {
        let d = try Yams.load(yaml: defaultYAML) as? [String: Any]
        return d?["keys"] as? [String: Any] ?? [:]
    }

    static func parseKeys(_ map: [String: Any], mod: Set<Modifier>, workspaceCount: Int) throws -> [KeyChord: Command] {
        var out: [KeyChord: Command] = [:]
        for (chordText, value) in map {
            let chord = try parseChord(chordText, mod: mod)
            if value is NSNull { continue }                      // `mod-x: ~` unbinds
            let cmd = try parseCommand("\(value)", workspaceCount: workspaceCount, context: chordText)
            out[chord] = cmd
        }
        return out
    }

    /// "mod-shift-j", "ctrl+alt+return", "cmd-f5"
    public static func parseChord(_ text: String, mod: Set<Modifier>) throws -> KeyChord {
        let parts = text.lowercased().split(whereSeparator: { $0 == "-" || $0 == "+" }).map(String.init)
        guard let key = parts.last, !key.isEmpty else { throw SettingsError("bad key '\(text)'") }
        var mods: Set<Modifier> = []
        for p in parts.dropLast() {
            if p == "mod" { mods.formUnion(mod) } else { mods.insert(try modifier(p, text)) }
        }
        return KeyChord(modifiers: mods, key: key)
    }

    static func parseModifiers(_ text: String, _ ctx: String) throws -> Set<Modifier> {
        let parts = text.lowercased().split(whereSeparator: { $0 == "-" || $0 == "+" || $0 == " " })
        guard !parts.isEmpty else { throw SettingsError("\(ctx): empty modifier") }
        return Set(try parts.map { try modifier(String($0), ctx) })
    }

    static func modifier(_ p: String, _ ctx: String) throws -> Modifier {
        switch p {
        case "cmd", "command", "super", "win": return .cmd
        case "ctrl", "control": return .ctrl
        case "alt", "opt", "option": return .alt
        case "shift": return .shift
        default: throw SettingsError("\(ctx): unknown modifier '\(p)' (use cmd, ctrl, alt, shift or mod)")
        }
    }

    public static func parseCommand(_ text: String, workspaceCount: Int, context: String) throws -> Command {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let name = trimmed.prefix { !$0.isWhitespace }.lowercased()
        let arg = trimmed.dropFirst(name.count).trimmingCharacters(in: .whitespaces)

        func index(max: Int, what: String) throws -> Int {
            guard let n = Int(arg), n >= 1, n <= max else {
                throw SettingsError("\(context): '\(name)' needs a \(what) number 1…\(max)")
            }
            return n - 1
        }
        func noArg(_ c: Command) throws -> Command {
            guard arg.isEmpty else { throw SettingsError("\(context): '\(name)' takes no argument") }
            return c
        }

        switch name {
        case "workspace", "greedy-view": return .greedyView(try index(max: workspaceCount, what: "workspace"))
        case "view":                     return .view(try index(max: workspaceCount, what: "workspace"))
        case "shift", "move-to":         return .shift(try index(max: workspaceCount, what: "workspace"))
        case "focus-screen":             return .focusScreen(try index(max: 9, what: "screen"))
        case "shift-to-screen":          return .shiftToScreen(try index(max: 9, what: "screen"))
        case "focus-down":   return try noArg(.focusDown)
        case "focus-up":     return try noArg(.focusUp)
        case "focus-master": return try noArg(.focusMaster)
        case "swap-down":    return try noArg(.swapDown)
        case "swap-up":      return try noArg(.swapUp)
        case "swap-master":  return try noArg(.swapMaster)
        case "next-layout":  return try noArg(.nextLayout)
        case "shrink":       return try noArg(.shrink)
        case "expand":       return try noArg(.expand)
        case "inc-master":   return try noArg(.incMaster)
        case "dec-master":   return try noArg(.decMaster)
        case "focus-next-screen":    return try noArg(.focusNextScreen)
        case "focus-prev-screen":    return try noArg(.focusPrevScreen)
        case "shift-to-next-screen": return try noArg(.shiftToNextScreen)
        case "shift-to-prev-screen": return try noArg(.shiftToPrevScreen)
        case "workspace-next":       return try noArg(.workspaceNext)
        case "workspace-prev":       return try noArg(.workspacePrev)
        case "shift-next":           return try noArg(.shiftNext)
        case "shift-prev":           return try noArg(.shiftPrev)
        case "restart":              return try noArg(.restart)
        case "window-search":        return try noArg(.windowSearch)
        case "app-rule":             return try noArg(.appRule)
        case "toggle-float": return try noArg(.toggleFloat)
        case "refresh":      return try noArg(.refresh)
        case "close":        return try noArg(.close)
        case "terminal":     return try noArg(.terminal)
        case "reload":       return try noArg(.reload)
        case "quit":         return try noArg(.quit)
        case "spawn":
            guard !arg.isEmpty else { throw SettingsError("\(context): 'spawn' needs a shell command") }
            return .spawn(arg)
        default:
            throw SettingsError("\(context): unknown command '\(name)'")
        }
    }

    /// Rewrite one `bar.<key>:` line in a config file's text.
    public static func setBarList(_ text: String, key: String, _ items: [BarWidget]) -> String {
        var lines = text.components(separatedBy: "\n")
        let value = "[\(items.map(\.rawValue).joined(separator: ", "))]"
        guard let barLine = lines.firstIndex(where: { $0.hasPrefix("bar:") }) else {
            return text + (text.hasSuffix("\n") ? "" : "\n") + "bar:\n  \(key): \(value)\n"
        }
        // The bar section: following lines that are indented, blank or comments.
        var end = barLine + 1
        while end < lines.count, lines[end].isEmpty || lines[end].hasPrefix(" ") || lines[end].hasPrefix("#") { end += 1 }
        if let i = (barLine + 1..<end).first(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("\(key):") }) {
            let indent = String(lines[i].prefix { $0 == " " })
            let comment = lines[i].range(of: " #").map { String(lines[i][$0.lowerBound...]) } ?? ""
            lines[i] = "\(indent)\(key): \(value)\(comment)"
            // Drop a block-style list ("- cpu" lines) that followed the key.
            let j = i + 1
            while j < end, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("- "),
                  lines[j].prefix(while: { $0 == " " }).count >= indent.count {
                lines.remove(at: j)
                end -= 1
            }
        } else {
            lines.insert("  \(key): \(value)", at: barLine + 1)
        }
        return lines.joined(separator: "\n")
    }

    private static func widgets(_ v: Any, _ k: String) throws -> [BarWidget] {
        if v is NSNull { return [] }
        guard let list = v as? [Any] else { throw SettingsError("\(k) must be a list, e.g. [cpu, clock]") }
        return try list.map {
            guard let w = BarWidget(rawValue: "\($0)") else {
                let all = BarWidget.allCases.map(\.rawValue).joined(separator: ", ")
                throw SettingsError("\(k): unknown widget '\($0)' (use \(all))")
            }
            return w
        }
    }

    private static func string(_ v: Any, _ k: String) throws -> String {
        guard let s = v as? String else { throw SettingsError("\(k) must be text") }
        return s
    }
    private static func number(_ v: Any, _ k: String) throws -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        throw SettingsError("\(k) must be a number")
    }
    private static func bool(_ v: Any, _ k: String) throws -> Bool {
        guard let b = v as? Bool else { throw SettingsError("\(k) must be true or false") }
        return b
    }
}

extension Settings {
    public static let defaultYAML = #"""
# Kachel configuration  (~/.config/kachel/config.yaml)
# Saved changes apply immediately. If the file has an error, the bar shows it
# and the previous settings stay.

# Modifier used by "mod-…" below. Combine cmd, ctrl, alt (= option), shift.
# Option, like mod1 in your Amethyst config. On a Swiss keyboard this means
# Option+3/5/6/7/8/9 no longer type # [ ] | { } (use ctrl+alt to keep them).
mod: alt

# Workspace names. All monitors share these, like in xmonad.
workspaces: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

# Layouts cycled by next-layout, in order: tall, wide, column, full.
layouts: [tall, wide, column, full]

gap: 5                    # points between windows and at screen edges
ratio: 0.5                # master area share for new workspaces
ratio-step: 0.05          # how much shrink/expand change it
mouse-follows-focus: true # warp the pointer when focus moves to another screen
menubar-icon: false       # Kachel icon in the top menu bar (same menu as right-clicking the bar)

# Used by the `terminal` command. Examples: "open -na Ghostty",
# "open -na Alacritty", "open -na kitty", "open -na WezTerm", "open -na iTerm"
terminal: open -na Alacritty

# Bundle IDs whose windows always float (find one with: osascript -e 'id of app "Name"').
floating:
  - com.apple.systempreferences
  - com.apple.calculator
  - com.apple.archiveutility

# The bar at the bottom of every screen. Click a workspace to show it on that
# screen; right-click for the menu, where widgets can also be switched on and off.
bar:
  enabled: true
  height: auto            # auto = same as the menu bar at the top, or a number
  font-size: 13
  background: transparent # transparent = like the macOS menu bar; blur = frosted glass
  appearance: auto        # auto = white/black text depending on the wallpaper; light; dark
  # Widgets, in order: workspaces, layout, title, cpu, memory, network, date, clock.
  # Leave one out to hide it.
  left: [workspaces, layout, title]
  right: [network, cpu, memory, date, clock]
  hide-empty-workspaces: false
  date-format: "EEE d MMM"   # Unicode date patterns
  clock-format: "HH:mm"
  interval: 2               # seconds between cpu / memory / network updates

# Trackpad swipes switch workspaces on the screen under the pointer. Turn
# macOS's own swipe off first: System Settings → Trackpad → More Gestures →
# "Swipe between full-screen applications" → Off (or the other finger count).
gestures:
  enabled: true
  fingers: 3              # 3 or 4
  skip-empty: true        # swipes skip empty workspaces and ones shown on another screen
  swipe-left: workspace-next    # any command; ~ for nothing
  swipe-right: workspace-prev
  swipe-up: ~
  swipe-down: ~

# Rules, like xmonad's manageHook: where an app's windows open, or whether
# they float. mod-shift-p sets one for the focused app and writes it here.
#   - app: com.tinyspeck.slackmacgap   # bundle ID or app name
#     workspace: 9
#   - app: Calculator
#     float: true
#   - app: com.google.Chrome
#     title: "Meet"                    # only windows whose title contains this
#     workspace: 5
rules: []

# Keys: <modifiers>-<key>: <command>.  Modifiers: mod, cmd, ctrl, alt, shift.
# Key names: a–z, 0–9, return, tab, space, escape, delete, left, right, up,
# down, f1–f12, comma, period, slash, minus, equal, semicolon, quote,
# leftbracket, rightbracket, backslash, grave. Letters follow your keyboard
# layout (on a Swiss keyboard "z" is the key labelled Z).
#
# Commands:
#   workspace N            greedyView: show workspace N here (swaps screens if it is visible elsewhere)
#   view N                 like xmonad's W.view: jump to the screen already showing N
#   shift N                send the focused window to workspace N
#   workspace-next / workspace-prev    show the next / previous workspace here
#   shift-next / shift-prev            send the focused window to the next / previous workspace
#   focus-screen N         shift-to-screen N
#   focus-next-screen      focus-prev-screen
#   shift-to-next-screen   shift-to-prev-screen
#   focus-down  focus-up  focus-master  swap-down  swap-up  swap-master
#   next-layout  shrink  expand  inc-master  dec-master  toggle-float
#   window-search          search all open windows and jump to one
#   app-rule               choose the workspace the focused app always opens on
#   refresh  close  terminal  reload  restart  quit
#   spawn <shell command>
# A key mapped to ~ is unbound. This section replaces the defaults as a whole.
#
# Taken over from your Amethyst config (mod1 = Option, mod2 = Option+Shift).
# skhd already uses Option + q / return / f / b, so those stay free.
keys:
  # Workspaces (Amethyst has no key for this; xmonad's mod-N)
  mod-1: workspace 1
  mod-2: workspace 2
  mod-3: workspace 3
  mod-4: workspace 4
  mod-5: workspace 5
  mod-6: workspace 6
  mod-7: workspace 7
  mod-8: workspace 8
  mod-9: workspace 9
  # Amethyst throw-space-N
  mod-shift-1: shift 1
  mod-shift-2: shift 2
  mod-shift-3: shift 3
  mod-shift-4: shift 4
  mod-shift-5: shift 5
  mod-shift-6: shift 6
  mod-shift-7: shift 7
  mod-shift-8: shift 8
  mod-shift-9: shift 9
  # Amethyst throw-space-left / -right
  mod-shift-left: shift-prev
  mod-shift-right: shift-next

  # Amethyst focus-cw / focus-ccw, swap-cw / swap-ccw
  mod-j: focus-down
  mod-k: focus-up
  mod-shift-j: swap-down
  mod-shift-k: swap-up
  # Amethyst shrink-main / expand-main
  mod-h: shrink
  mod-l: expand
  # Amethyst cycle-layout
  mod-shift-space: next-layout
  # Amethyst focus-screen-cw
  mod-comma: focus-next-screen
  # Amethyst reevaluate-windows
  mod-z: refresh

  # Not in your Amethyst config (xmonad-style extras)
  mod-p: window-search      # like dmenu / XMonad.Prompt.Window on mod-p
  mod-shift-p: app-rule     # "always open this app on workspace N" (writes rules: above)
  mod-shift-comma: shift-to-next-screen
  mod-m: focus-master
  mod-shift-m: swap-master
  mod-t: toggle-float
  mod-shift-r: restart
  mod-shift-q: quit
"""#
}
