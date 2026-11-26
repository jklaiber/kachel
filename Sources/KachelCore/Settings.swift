import Foundation
import Yams

// Settings come from ~/.config/kachel/config.yaml. The default file below is
// the single source of truth: it is written to disk on first launch and is
// also what any missing setting falls back to.

public enum Modifier: String, CaseIterable {
    case cmd, ctrl, alt, shift
}

/// Which physical key of a modifier counts, for `mod: left-alt`.
public enum ModifierSide: String { case left, right }

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
    case toggleFullscreen, workspaceBack, taller, shorter, resetSizes
    case settings, welcome, shortcuts
    case focusDirection(Direction), swapDirection(Direction)
    case scratchpad(String)
    case spawn(String)
    case sendKey(KeyChord)          // send-key cmd-w: post that key combination to the front app
    case setLayout(LayoutKind)          // layout <name>: straight to that layout
    case prevLayout, toggleTiling, toggleFocusFollowsMouse, increaseWindowLimit, decreaseWindowLimit
}

/// A widget in the bar: one of the built-in ones, or one of yours, defined
/// under `bar.widgets` and named in `left:` / `right:` like the others.
public struct BarWidget: RawRepresentable, Hashable, CaseIterable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
    private init(_ name: String) { rawValue = name }

    public static let workspaces = BarWidget("workspaces"), layout = BarWidget("layout"), title = BarWidget("title")
    public static let cpu = BarWidget("cpu"), memory = BarWidget("memory"), network = BarWidget("network")
    public static let battery = BarWidget("battery"), date = BarWidget("date"), clock = BarWidget("clock")
    /// Unread counts from the Dock badges of running apps.
    public static let badges = BarWidget("badges")

    /// The built-in widgets.
    public static let allCases: [BarWidget] = [workspaces, layout, title, cpu, memory, network, battery, badges, date, clock]
    public var isBuiltIn: Bool { Self.allCases.contains(self) }
}

/// A widget of yours: the first line a shell command prints, every few seconds.
public struct CustomWidget: Equatable {
    public var run: String
    /// Seconds between runs (at least 2).
    public var interval: Double = 10
    /// An SF Symbol in front of the text ("lock.fill").
    public var icon: String?
    /// A shell command run when you click it.
    public var click: String?
    public init(run: String) { self.run = run }
}

public struct BarSettings: Equatable {
    public var enabled = true
    /// nil = same height as the menu bar at the top.
    public var height: Double?
    public var fontSize: Double = 13
    public var left: [BarWidget] = [.workspaces, .layout, .title]
    public var right: [BarWidget] = [.badges, .network, .cpu, .memory, .battery, .date, .clock]
    /// Which apps' badges to show (bundle IDs or names); empty: every app with one.
    public var badgeApps: [String] = []
    /// Your own widgets, by name.
    public var custom: [String: CustomWidget] = [:]
    public var hideEmptyWorkspaces = false
    public var clockFormat = "HH:mm"
    public var dateFormat = "EEE d MMM"
    public var interval: Double = 2          // seconds between cpu/memory/network samples
    public var background: Background = .transparent
    public var appearance: Appearance = .auto
    /// The windows of the workspace you're on, shown next to the layout and title.
    public var windows: WindowsStyle = .tabs
    /// Only in the Full layout, where the other windows are hidden.
    public var windowsFullOnly = true
    /// A small window count next to each workspace.
    public var workspaceCounts = false
    /// The battery widget shows the percentage next to its icon.
    public var batteryPercentage = true
    /// The bar fades out while an auto-hidden Dock slides up over it.
    public var makeWayForDock = true
    public init() {}

    public enum WindowsStyle: String, CaseIterable {
        case off, position, dots, tabs
    }

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
    /// auto: like macOS's Spaces swipe, which follows the "Natural scrolling"
    /// setting. natural: fingers left = next. reversed: fingers left = previous.
    public var direction: SwipeDirection = .auto
    public enum SwipeDirection: String { case auto, natural, reversed }
    public var left: Command? = .workspaceNext     // fingers move left → like macOS, the space to the right
    public var right: Command? = .workspacePrev
    public var up: Command?
    public var down: Command?
    public init() {}
}

/// A window you summon and dismiss with one key (xmonad's NamedScratchpad).
public struct Scratchpad: Equatable {
    public var name: String
    public var app: String               // bundle ID or app name of its window
    public var title: String?            // only windows whose title contains this
    public var run: String?              // shell command that opens it if none is open
    public var width = 0.6               // share of the screen
    public var height = 0.6
    public var position: Position = .center
    public enum Position: String { case center, top }

    public init(name: String, app: String) { self.name = name; self.app = app }

    public var matcher: Rule { Rule(app: app, title: title) }
}

/// A coloured frame around the focused window.
public struct BorderSettings: Equatable {
    public var enabled = true
    public var width = 3.0
    public var color = "accent"           // "accent" (system accent colour) or "#RRGGBB"
    /// nil = automatic: follows each window's own corners (see FocusBorder).
    public var radius: Double? = nil
    public var smart = false              // no border when it's the only window on the screen
    public init() {}
}

public struct SettingsError: Error, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

public struct Settings {
    public var mod: Set<Modifier> = [.ctrl, .alt]
    /// `mod: left-alt`: only that key of the modifier counts as mod, the
    /// other one is left to the keyboard layout. Empty = both keys.
    public var modSides: [Modifier: ModifierSide] = [:]
    public var workspaces = (1...9).map(String.init)
    public var gap: Double = 6
    public var ratio: Double = 0.5
    public var ratioStep: Double = 0.03
    /// Move the pointer when focus moves: to the focused window's centre
    /// (window, like Amethyst), to its screen's centre (screen), or not (off).
    public var mouseFollowsFocus: MouseFollows = .window
    public enum MouseFollows: String { case off, screen, window }
    /// Focus the window under the pointer when it rests there.
    public var focusFollowsMouse = false
    /// Pressing the key of the workspace you're on goes back to the previous one.
    public var workspaceBackAndForth = false
    /// Space at the screen edges; nil = the same as `gap`.
    public var padding: Double?
    /// false: no edge padding on the built-in display.
    public var builtinPadding = true
    /// No gap and no padding when a single window is tiled on a display.
    public var smartGaps = false
    /// At most this many tiled windows per workspace; the others float. 0 = no limit.
    public var windowLimit = 0
    /// Sending a window to another workspace takes you there too.
    public var followMovedWindows = false
    /// Where a hidden workspace shows when Kachel follows focus to it by itself
    /// (a link opens, cmd-tab, the Dock): on this screen, or where it was last.
    public var followFocusScreen: FollowFocusScreen = .current
    public enum FollowFocusScreen: String { case current, last }

    /// All layouts, in the order the settings window lists them.
    public static let layoutOrder: [LayoutKind] = [.tall, .tallRight, .mirrorTall, .widescreenTall, .threeColumn,
                                                   .twoPane, .column, .row, .bsp, .full, .floating]
    /// Where new windows go: end of the stack, below/above the focused one, or master.
    public var newWindows: InsertPosition = .end
    /// A light trackpad tap when a swipe triggers or a dragged window snaps in.
    public var haptics = true
    /// Hold the modifier alone this long (seconds) to see all shortcuts; 0 = off.
    public var shortcutOverview = 0.8
    /// Workspace name -> screen pattern (see ScreenMatcher): always shown there.
    public var workspaceScreens: [String: String] = [:]
    /// The layout a workspace starts with, by name or number ("9", "mail").
    public var workspaceLayouts: [String: LayoutKind] = [:]

    /// Workspace `i`'s layout from `workspace-layouts`, if it has one.
    public func configuredLayout(forWorkspace i: Int) -> LayoutKind? {
        guard workspaces.indices.contains(i) else { return nil }
        return workspaceLayouts[workspaces[i]] ?? workspaceLayouts["\(i + 1)"]
    }
    public var terminal = "open -na Terminal"
    public var layouts: [LayoutKind] = [.tall, .mirrorTall, .threeColumn, .column, .full]
    public var menubarIcon = false
    public var rules: [Rule] = []
    public var gestures = GestureSettings()
    /// Windows without a fullscreen button are dialogs: float them (AeroSpace's heuristic).
    public var floatDialogs = true
    /// Float windows smaller than this in both directions (Amethyst's float-small-windows); 0 = off.
    public var floatSmallWindows = 0
    public var startAtLogin = false
    /// Once an hour, ask GitHub for the latest release (nothing else is sent).
    public var checkForUpdates = true
    public var scratchpads: [Scratchpad] = []
    public var border = BorderSettings()
    public var bar = BarSettings()
    public var keys: [KeyChord: Command] = [:]
    /// Things in the file that were ignored (unknown settings: typos, or
    /// settings of a newer Kachel). The rest of the file still applies.
    public var warnings: [String] = []

    public init() {}

    /// Parsed built-in defaults. The default YAML is tested, so this can't fail.
    public static let defaults: Settings = try! Settings.parse(defaultYAML)

    // MARK: - parsing

    public static func parse(_ yaml: String) throws -> Settings {
        let root: Any?
        do { root = try Yams.load(yaml: yaml) } catch { throw SettingsError("YAML: \(error)") }
        // Anything the file leaves out comes from the documented defaults.
        var s = yaml == defaultYAML ? Settings() : Settings.defaults
        // An empty file means "all defaults".
        guard let dict = (root ?? [String: Any]()) as? [String: Any] else {
            throw SettingsError("top level must be a mapping")
        }

        let known: Set<String> = ["mod", "workspaces", "gap", "ratio", "ratio-step", "mouse-follows-focus",
                                  "terminal", "bar", "keys", "layouts", "menubar-icon", "rules", "gestures",
                                  "float-dialogs", "float-small-windows", "start-at-login", "check-for-updates",
                                  "scratchpads", "border", "focus-follows-mouse",
                                  "workspace-back-and-forth", "workspace-screens", "workspace-layouts", "new-windows",
                                  "haptics", "shortcut-overview", "padding", "builtin-display-padding",
                                  "smart-gaps", "window-limit", "follow-moved-windows", "follow-focus-screen"]
        s.warnings = []
        for bad in dict.keys.sorted() where !known.contains(bad) {
            s.warnings.append(unknown(bad, known))
        }

        if let v = dict["mod"] { (s.mod, s.modSides) = try parseMod(string(v, "mod")) }
        if let v = dict["workspaces"] {
            guard let list = v as? [Any], !list.isEmpty else { throw SettingsError("workspaces must be a non-empty list") }
            s.workspaces = list.map { "\($0)" }
        }
        if let v = dict["gap"] { s.gap = try number(v, "gap") }
        if let v = dict["padding"] {
            if let t = v as? String, t == "auto" { s.padding = nil } else { s.padding = max(0, try number(v, "padding")) }
        }
        if let v = dict["builtin-display-padding"] { s.builtinPadding = try bool(v, "builtin-display-padding") }
        if let v = dict["smart-gaps"] { s.smartGaps = try bool(v, "smart-gaps") }
        if let v = dict["window-limit"] { s.windowLimit = max(0, Int(try number(v, "window-limit"))) }
        if let v = dict["follow-moved-windows"] { s.followMovedWindows = try bool(v, "follow-moved-windows") }
        if let v = dict["follow-focus-screen"] {
            guard let f = FollowFocusScreen(rawValue: "\(v)") else {
                throw SettingsError("follow-focus-screen must be current or last")
            }
            s.followFocusScreen = f
        }
        if let v = dict["ratio"] { s.ratio = min(0.9, max(0.1, try number(v, "ratio"))) }
        if let v = dict["ratio-step"] { s.ratioStep = try number(v, "ratio-step") }
        if let v = dict["mouse-follows-focus"] {
            if let b = v as? Bool { s.mouseFollowsFocus = b ? .window : .off }
            else if let m = MouseFollows(rawValue: "\(v)") { s.mouseFollowsFocus = m }
            else { throw SettingsError("mouse-follows-focus must be window, screen or off") }
        }
        if let v = dict["focus-follows-mouse"] { s.focusFollowsMouse = try bool(v, "focus-follows-mouse") }
        if let v = dict["haptics"] { s.haptics = try bool(v, "haptics") }
        if let v = dict["shortcut-overview"] {
            if let b = v as? Bool { s.shortcutOverview = b ? 0.8 : 0 }
            else { s.shortcutOverview = max(0, try number(v, "shortcut-overview")) }
        }
        if let v = dict["new-windows"] {
            guard let p = InsertPosition(rawValue: "\(v)") else {
                throw SettingsError("new-windows must be end, below, above or master")
            }
            s.newWindows = p
        }
        if let v = dict["workspace-back-and-forth"] { s.workspaceBackAndForth = try bool(v, "workspace-back-and-forth") }
        if let v = dict["workspace-screens"] {
            if v is NSNull { s.workspaceScreens = [:] }
            else {
                guard let m = v as? [String: Any] else {
                    throw SettingsError("workspace-screens must map workspaces to screens, e.g. \"9\": external")
                }
                s.workspaceScreens = [:]
                for (k, val) in m {
                    guard s.workspaces.contains(k) || Int(k).map({ $0 >= 1 && $0 <= s.workspaces.count }) == true else {
                        throw SettingsError("workspace-screens: there is no workspace '\(k)'")
                    }
                    s.workspaceScreens[k] = "\(val)"
                }
            }
        }
        if let v = dict["terminal"] { s.terminal = try string(v, "terminal") }
        if let v = dict["layouts"] {
            guard let list = v as? [Any], !list.isEmpty else { throw SettingsError("layouts must be a non-empty list") }
            s.layouts = try list.map {
                guard let l = LayoutKind(configName: "\($0)") else {
                    throw SettingsError("layouts: unknown layout '\($0)' (use tall, wide, column, full)")
                }
                return l
            }
        }
        if let v = dict["workspace-layouts"], !(v is NSNull) {
            guard let m = v as? [String: Any] else {
                throw SettingsError("workspace-layouts must map workspaces to layouts, e.g. \"9\": full")
            }
            s.workspaceLayouts = [:]
            for (k, val) in m {
                guard s.workspaces.contains(k) || Int(k).map({ $0 >= 1 && $0 <= s.workspaces.count }) == true else {
                    throw SettingsError("workspace-layouts: there is no workspace '\(k)'")
                }
                guard let kind = LayoutKind(configName: "\(val)") else {
                    throw SettingsError("workspace-layouts: unknown layout '\(val)' for workspace \(k)")
                }
                guard s.layouts.contains(kind) else {
                    throw SettingsError("workspace-layouts: '\(val)' for workspace \(k) isn't in layouts: (add it there)")
                }
                s.workspaceLayouts[k] = kind
            }
        }
        if let v = dict["float-dialogs"] { s.floatDialogs = try bool(v, "float-dialogs") }
        if let v = dict["float-small-windows"] {
            if let b = v as? Bool { s.floatSmallWindows = b ? 500 : 0 }
            else { s.floatSmallWindows = max(0, Int(try number(v, "float-small-windows"))) }
        }
        if let v = dict["start-at-login"] { s.startAtLogin = try bool(v, "start-at-login") }
        if let v = dict["check-for-updates"] { s.checkForUpdates = try bool(v, "check-for-updates") }
        if dict["scratchpads"] == nil, yaml != defaultYAML {
            s.scratchpads = Settings.defaults.scratchpads
        }
        if let v = dict["scratchpads"], !(v is NSNull) {
            guard let list = v as? [Any] else { throw SettingsError("scratchpads must be a list") }
            s.scratchpads = try list.enumerated().map { i, item in
                let ctx = "scratchpads[\(i + 1)]"
                guard let d = item as? [String: Any] else { throw SettingsError("\(ctx) must be a mapping") }
                let allowed = ["name", "app", "title", "run", "size", "position"]
                for bad in d.keys.sorted() where !allowed.contains(bad) {
                    s.warnings.append(unknown("\(ctx).\(bad)", allowed, last: bad))
                }
                guard let name = d["name"].map({ "\($0)" }), !name.isEmpty, !name.contains(" ") else {
                    throw SettingsError("\(ctx) needs a name: without spaces")
                }
                guard let app = d["app"].map({ "\($0)" }), !app.isEmpty else { throw SettingsError("\(ctx) needs app:") }
                var sp = Scratchpad(name: name, app: app)
                if let t = d["title"], !(t is NSNull) { sp.title = "\(t)" }
                if let r = d["run"], !(r is NSNull) { sp.run = "\(r)" }
                if let z = d["size"] {
                    guard let pair = z as? [Any], pair.count == 2,
                          let w = (pair[0] as? Double) ?? (pair[0] as? Int).map(Double.init),
                          let h = (pair[1] as? Double) ?? (pair[1] as? Int).map(Double.init),
                          (0.1...1).contains(w), (0.1...1).contains(h) else {
                        throw SettingsError("\(ctx): size must be [width, height] as shares of the screen, e.g. [0.6, 0.5]")
                    }
                    sp.width = w; sp.height = h
                }
                if let p = d["position"] {
                    guard let pos = Scratchpad.Position(rawValue: "\(p)") else {
                        throw SettingsError("\(ctx): position must be center or top")
                    }
                    sp.position = pos
                }
                return sp
            }
            let names = s.scratchpads.map(\.name)
            if let dup = names.first(where: { n in names.filter { $0 == n }.count > 1 }) {
                throw SettingsError("scratchpads: name '\(dup)' is used twice")
            }
        }
        if let v = dict["border"] {
            guard let b = v as? [String: Any] else { throw SettingsError("border must be a mapping") }
            for (k, v) in b {
                switch k {
                case "enabled": s.border.enabled = try bool(v, "border.enabled")
                case "width": s.border.width = max(1, min(12, try number(v, "border.width")))
                case "radius":
                    if let a = v as? String, a == "auto" { s.border.radius = nil }
                    else { s.border.radius = max(0, try number(v, "border.radius")) }
                case "smart": s.border.smart = try bool(v, "border.smart")
                case "color":
                    let c = "\(v)"
                    guard c == "accent" || c.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else {
                        throw SettingsError("border.color must be accent or a colour like \"#5DCAA5\"")
                    }
                    s.border.color = c
                default: s.warnings.append(unknown("border.\(k)", BorderKeys.all, last: k))
                }
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
                case "direction":
                    guard let d = GestureSettings.SwipeDirection(rawValue: "\(v)") else {
                        throw SettingsError("gestures.direction must be auto, natural or reversed")
                    }
                    s.gestures.direction = d
                case "swipe-left": s.gestures.left = try cmd()
                case "swipe-right": s.gestures.right = try cmd()
                case "swipe-up": s.gestures.up = try cmd()
                case "swipe-down": s.gestures.down = try cmd()
                default: s.warnings.append(unknown("gestures.\(k)", GesturesKeys.all, last: k))
                }
            }
        }
        if let v = dict["rules"] { s.rules = try parseRules(v, workspaces: s.workspaces) }
        if let v = dict["menubar-icon"] { s.menubarIcon = try bool(v, "menubar-icon") }
        if let v = dict["bar"] {
            guard let b = v as? [String: Any] else { throw SettingsError("bar must be a mapping") }
            var sides: [(String, Any)] = []          // left / right: once all widgets are known
            for (k, v) in b {
                switch k {
                case "enabled": s.bar.enabled = try bool(v, "bar.enabled")
                case "height":
                    if let t = v as? String, t == "auto" { s.bar.height = nil }
                    else { s.bar.height = try number(v, "bar.height") }
                case "font-size": s.bar.fontSize = try number(v, "bar.font-size")
                case "left", "right": sides.append((k, v))
                case "badges":
                    for (_, v2) in try block(v, "bar.badges", keys: ["apps"], warnings: &s.warnings) {
                        guard let list = v2 as? [Any] else { throw SettingsError("bar.badges.apps must be a list of apps") }
                        s.bar.badgeApps = list.map { "\($0)" }
                    }
                case "widgets":
                    s.bar.custom = try customWidgets(v, warnings: &s.warnings)
                // Each widget's own options, in a block named after it.
                case "workspaces":
                    for (k2, v2) in try block(v, "bar.workspaces", keys: ["hide-empty", "window-counts"], warnings: &s.warnings) {
                        if k2 == "hide-empty" { s.bar.hideEmptyWorkspaces = try bool(v2, "bar.workspaces.hide-empty") }
                        if k2 == "window-counts" { s.bar.workspaceCounts = try bool(v2, "bar.workspaces.window-counts") }
                    }
                case "title":
                    for (k2, v2) in try block(v, "bar.title", keys: ["windows", "only-in-full"], warnings: &s.warnings) {
                        if k2 == "windows" {
                            // YAML reads a bare `off` as false.
                            if let b = v2 as? Bool, !b { s.bar.windows = .off; continue }
                            guard let style = BarSettings.WindowsStyle(rawValue: "\(v2)") else {
                                throw SettingsError("bar.title.windows must be off, position, dots or tabs")
                            }
                            s.bar.windows = style
                        }
                        if k2 == "only-in-full" { s.bar.windowsFullOnly = try bool(v2, "bar.title.only-in-full") }
                    }
                case "stats":
                    for (_, v2) in try block(v, "bar.stats", keys: ["interval"], warnings: &s.warnings) {
                        s.bar.interval = max(0.5, try number(v2, "bar.stats.interval"))
                    }
                case "battery":
                    for (_, v2) in try block(v, "bar.battery", keys: ["percentage"], warnings: &s.warnings) {
                        s.bar.batteryPercentage = try bool(v2, "bar.battery.percentage")
                    }
                case "date":
                    for (_, v2) in try block(v, "bar.date", keys: ["format"], warnings: &s.warnings) {
                        s.bar.dateFormat = try string(v2, "bar.date.format")
                    }
                case "clock":
                    for (_, v2) in try block(v, "bar.clock", keys: ["format"], warnings: &s.warnings) {
                        s.bar.clockFormat = try string(v2, "bar.clock.format")
                    }
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
                case "make-way-for-dock": s.bar.makeWayForDock = try bool(v, "bar.make-way-for-dock")
                default: s.warnings.append(unknown("bar.\(k)", BarKeys.all, last: k))
                }
            }
            for (k, v) in sides {
                let list = try widgets(v, "bar.\(k)", custom: Set(s.bar.custom.keys))
                if k == "left" { s.bar.left = list } else { s.bar.right = list }
            }
        }

        // `keys:` replaces the whole default keymap; leave it out to keep the defaults.
        if let v = dict["keys"] {
            guard let k = v as? [String: Any] else { throw SettingsError("keys must be a mapping") }
            s.keys = try parseKeys(k, mod: s.mod, workspaceCount: s.workspaces.count)
        } else {
            s.keys = try parseKeys(try defaultKeyMap(), mod: s.mod, workspaceCount: s.workspaces.count)
        }
        // send-key must not send one of Kachel's own shortcuts: it would trigger itself.
        for (chord, cmd) in s.keys {
            if case .sendKey(let target) = cmd, s.keys[target] != nil {
                throw SettingsError("\(chord): send-key \(target) is itself a Kachel shortcut, it would trigger that")
            }
        }
        // Every `scratchpad NAME` must name a scratchpad.
        let names = Set(s.scratchpads.map(\.name))
        let used = s.keys.map { ($0.key.description, $0.value) }
            + [("gestures.swipe-left", s.gestures.left), ("gestures.swipe-right", s.gestures.right),
               ("gestures.swipe-up", s.gestures.up), ("gestures.swipe-down", s.gestures.down)]
                .compactMap { k, v in v.map { (k, $0) } }
        for (where_, cmd) in used {
            if case .scratchpad(let n) = cmd, !names.contains(n) {
                throw SettingsError("\(where_): there is no scratchpad '\(n)' (add it under scratchpads:)")
            }
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

    /// "alt", "ctrl+alt", "left-alt", "right-cmd+shift"
    public static func parseMod(_ text: String) throws -> (Set<Modifier>, [Modifier: ModifierSide]) {
        let parts = text.lowercased().split(whereSeparator: { $0 == "-" || $0 == "+" || $0 == " " }).map(String.init)
        var mods: Set<Modifier> = []
        var sides: [Modifier: ModifierSide] = [:]
        var side: ModifierSide?
        for p in parts {
            if let s = ModifierSide(rawValue: p) {
                guard side == nil else { throw SettingsError("mod: '\(text)' has '\(p)' twice in a row") }
                side = s
                continue
            }
            let m = try modifier(p, "mod")
            mods.insert(m)
            if let side { sides[m] = side }
            side = nil
        }
        if side != nil { throw SettingsError("mod: '\(text)' ends in left/right; write e.g. left-alt") }
        guard !mods.isEmpty else { throw SettingsError("mod: empty modifier") }
        return (mods, sides)
    }

    /// Back to config text: "left-alt", "ctrl+alt".
    public static func modText(_ mods: Set<Modifier>, sides: [Modifier: ModifierSide]) -> String {
        [Modifier.ctrl, .alt, .cmd, .shift].filter(mods.contains)
            .map { m in (sides[m].map { "\($0.rawValue)-" } ?? "") + m.rawValue }
            .joined(separator: "+")
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
        case "prev-layout", "previous-layout": return try noArg(.prevLayout)
        case "layout", "select-layout":
            guard let kind = LayoutKind(configName: arg) else {
                let names = LayoutKind.allCases.map(\.configName).joined(separator: ", ")
                throw SettingsError("\(context): 'layout' needs one of \(names)")
            }
            return .setLayout(kind)
        case "toggle-tiling":              return try noArg(.toggleTiling)
        case "toggle-focus-follows-mouse": return try noArg(.toggleFocusFollowsMouse)
        case "increase-window-limit":      return try noArg(.increaseWindowLimit)
        case "decrease-window-limit":      return try noArg(.decreaseWindowLimit)
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
        case "toggle-fullscreen":    return try noArg(.toggleFullscreen)
        case "workspace-back":       return try noArg(.workspaceBack)
        case "taller":               return try noArg(.taller)
        case "shorter":              return try noArg(.shorter)
        case "reset-sizes":          return try noArg(.resetSizes)
        case "settings":             return try noArg(.settings)
        case "welcome":              return try noArg(.welcome)
        case "shortcuts":            return try noArg(.shortcuts)
        case "scratchpad":
            guard !arg.isEmpty, !arg.contains(" ") else {
                throw SettingsError("\(context): 'scratchpad' needs a scratchpad name")
            }
            return .scratchpad(arg)
        case "toggle-float": return try noArg(.toggleFloat)
        case "refresh":      return try noArg(.refresh)
        case "close":        return try noArg(.close)
        case "terminal":     return try noArg(.terminal)
        case "reload":       return try noArg(.reload)
        case "quit":         return try noArg(.quit)
        case "spawn":
            guard !arg.isEmpty else { throw SettingsError("\(context): 'spawn' needs a shell command") }
            return .spawn(arg)
        case "send-key":
            guard !arg.isEmpty else { throw SettingsError("\(context): 'send-key' needs keys, e.g. send-key cmd-w") }
            let parts = arg.lowercased().split(whereSeparator: { $0 == "-" || $0 == "+" })
            guard !parts.dropLast().contains("mod") else {
                throw SettingsError("\(context): send-key takes real modifiers (cmd, ctrl, alt, shift), not mod")
            }
            return .sendKey(try parseChord(arg, mod: []))
        case "focus", "swap":
            // focus left / swap right … (focus-down / swap-down without a space
            // are the stack's next/previous and stay as they are)
            guard let d = Direction(rawValue: arg.lowercased()) else {
                throw SettingsError("\(context): '\(name)' needs a direction: left, right, up or down")
            }
            return name == "focus" ? .focusDirection(d) : .swapDirection(d)
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

    private static func widgets(_ v: Any, _ k: String, custom: Set<String>) throws -> [BarWidget] {
        if v is NSNull { return [] }
        guard let list = v as? [Any] else { throw SettingsError("\(k) must be a list, e.g. [cpu, clock]") }
        return try list.map {
            guard let w = BarWidget(rawValue: "\($0)"), w.isBuiltIn || custom.contains(w.rawValue) else {
                let all = BarWidget.allCases.map(\.rawValue).joined(separator: ", ")
                throw SettingsError("\(k): unknown widget '\($0)' (use \(all), or define it under bar.widgets)")
            }
            return w
        }
    }

    /// bar.widgets: name → {run, interval, icon, click}.
    private static func customWidgets(_ v: Any, warnings: inout [String]) throws -> [String: CustomWidget] {
        if v is NSNull { return [:] }
        guard let m = v as? [String: Any] else {
            throw SettingsError("bar.widgets must map names to widgets, e.g. vpn: {run: \"…\"}")
        }
        var out: [String: CustomWidget] = [:]
        for (name, def) in m {
            let ctx = "bar.widgets.\(name)"
            guard BarWidget(rawValue: name)?.isBuiltIn != true else { throw SettingsError("\(ctx): \(name) is a built-in widget, pick another name") }
            let d = try block(def, ctx, keys: ["run", "interval", "icon", "click"], warnings: &warnings)
            guard let run = d["run"].map({ "\($0)" }), !run.isEmpty else { throw SettingsError("\(ctx) needs run: (a shell command)") }
            var w = CustomWidget(run: run)
            if let i = d["interval"] { w.interval = max(2, try number(i, "\(ctx).interval")) }
            if let i = d["icon"] { w.icon = "\(i)" }
            if let c = d["click"] { w.click = "\(c)" }
            out[name] = w
        }
        return out
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
    /// A widget's block under `bar:`, e.g. `battery: {percentage: true}`; an
    /// empty block is fine, unknown keys aren't.
    private static func block(_ v: Any, _ k: String, keys: Set<String>, warnings: inout [String]) throws -> [String: Any] {
        if v is NSNull { return [:] }
        guard let d = v as? [String: Any] else { throw SettingsError("\(k) must be a mapping") }
        for bad in d.keys.sorted() where !keys.contains(bad) {
            warnings.append(unknown("\(k).\(bad)", keys, last: bad))
        }
        return d.filter { keys.contains($0.key) }
    }

    enum BorderKeys { static let all = ["enabled", "width", "radius", "smart", "color"] }
    enum GesturesKeys { static let all = ["enabled", "fingers", "skip-empty", "direction", "swipe-left", "swipe-right", "swipe-up", "swipe-down"] }
    enum BarKeys { static let all = ["badges", "widgets", "enabled", "height", "font-size", "left", "right", "workspaces", "title", "stats", "battery", "date", "clock", "background", "appearance", "make-way-for-dock"] }

    /// "unknown setting 'gapp' ignored (did you mean 'gap'?)"
    static func unknown<C: Collection>(_ path: String, _ allowed: C, last: String? = nil) -> String where C.Element == String {
        let key = last ?? path
        // A typo (a letter or two off), or the start of a longer name ("percent").
        let close = allowed.filter {
            editDistance($0, key) <= max(1, key.count / 4) || (key.count >= 4 && ($0.hasPrefix(key) || key.hasPrefix($0)))
        }.min { editDistance($0, key) < editDistance($1, key) }
        return "unknown setting '\(path)' ignored" + (close.map { " (did you mean '\($0)'?)" } ?? "")
    }

    /// Typos between two names: letters added, missing, changed, or two
    /// neighbours swapped ("titel" → "title" is one).
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
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
# left-alt / right-cmd …: only that key; the other one stays free for typing.
# Option, like Amethyst's mod1. On Swiss and German keyboards this means
# Option+3/5/6/7/8/9 no longer type # [ ] | { } (use ctrl+alt to keep them).
mod: alt

# Workspace names. All monitors share these, like in xmonad.
workspaces: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

# Layouts cycled by next-layout, in order. All of them: tall, tall-right, wide,
# widescreen-tall, three-column, two-pane, column, rows, bsp, full, floating.
layouts: [tall, wide, three-column, column, full]

gap: 5                    # points between windows
padding: auto             # points at the screen edges; auto = the same as gap
builtin-display-padding: true   # false: no edge padding on the MacBook's own display
smart-gaps: false         # true: no gap or padding when a window is alone on its display
window-limit: 0           # at most this many tiled windows per workspace, others float; 0 = no limit
ratio: 0.5                # master area share for new workspaces
ratio-step: 0.05          # how much shrink/expand change it
mouse-follows-focus: window   # pointer to the focused window's centre; screen = only between screens; off
focus-follows-mouse: false    # true: the window under the pointer gets focus when the pointer rests
workspace-back-and-forth: false   # true: the key of the workspace you're on goes back to the previous one
follow-moved-windows: false   # true: sending a window to another workspace takes you there too
# A window on a hidden workspace gets focus (a link opens in it, cmd-tab, the
# Dock): Kachel shows that workspace on this screen (current), or on the
# screen that showed it last (last; this screen keeps its workspace).
follow-focus-screen: current
new-windows: end              # where new windows go: end (last in the stack), below / above the
                              # focused window, or master (xmonad's default is above)
haptics: true                 # a light trackpad tap when a swipe triggers or a window snaps in
shortcut-overview: 0.8        # hold mod alone this many seconds to see all shortcuts; 0 = off

# Pin workspaces to a screen (AeroSpace's workspace-to-monitor assignment):
# they always show there while that screen is connected. Screens: main (menu
# bar), external, builtin, 1…n from left to right, or part of the display name.
workspace-screens: {}
#   "8": external
#   "9": external

# The layout a workspace starts with, when Kachel starts and when you change it
# here (it must be one of `layouts`). The others keep the layout they had.
workspace-layouts: {}
#   "1": full
#   "9": three-column
menubar-icon: false       # Kachel icon in the top menu bar (same menu as right-clicking the bar)

# Used by the `terminal` command. Examples: "open -na Ghostty",
# "open -na Alacritty", "open -na kitty", "open -na WezTerm", "open -na iTerm"
terminal: open -na Alacritty

# Dialogs (windows without a fullscreen button, e.g. preferences, progress
# windows) float automatically. Terminals are tiled regardless.
float-dialogs: true
# Also float windows smaller than this many points in both directions, like
# Amethyst's float-small-windows (0 = off; true = 500).
float-small-windows: 0

start-at-login: false     # launch Kachel when you log in (needs Kachel.app in /Applications)
check-for-updates: true   # once an hour, look up the latest release on GitHub; the menu says when there's a newer one

# The bar at the bottom of every screen. Click a workspace to show it on that
# screen; right-click for the menu, where widgets can also be switched on and off.
bar:
  # The bar as a whole
  enabled: true
  height: auto            # auto = same as the menu bar at the top, or a number
  font-size: 13
  background: transparent # transparent = like the macOS menu bar; blur = frosted glass
  appearance: auto        # auto = white/black text depending on the wallpaper; light; dark
  make-way-for-dock: true # an auto-hidden Dock slides up: the bar fades out until it hides again

  # Which widgets, in order, on the left and the right. Leave one out to hide it.
  # Widgets: workspaces, layout, title, cpu, memory, network, battery, badges, date,
  # clock, and your own (widgets: below).
  left: [workspaces, layout, title]
  right: [badges, network, cpu, memory, battery, date, clock]

  # Each widget's own options
  workspaces:
    hide-empty: false     # hide workspaces without windows
    window-counts: false  # a small window count next to each workspace
  title:
    windows: tabs         # the other windows of this workspace: position (2/4 next
                          # to the layout), dots, tabs (click one to switch) or off
    only-in-full: true    # only in the Full layout, where the others are hidden
  stats:
    interval: 2           # seconds between cpu / memory / network updates
  battery:
    percentage: true      # the percentage next to the icon; false = icon only
  date:
    format: "EEE d MMM"   # Unicode date patterns
  clock:
    format: "HH:mm"
  badges:
    apps: []                  # unread counts from Dock icons: bundle IDs or names; [] = every app with one

  # Your own widgets: the first line a shell command prints (every interval
  # seconds, at least 2; cut off after 2 s and 40 characters). Put the name in
  # left or right like the others. icon: an SF Symbol; click: a shell command.
  widgets: {}
  #   vpn: {run: "scutil --nc status Work | head -1", interval: 10, icon: lock.fill}

# Trackpad swipes switch workspaces on the screen under the pointer. Turn
# macOS's own swipe off first: System Settings → Trackpad → More Gestures →
# "Swipe between full-screen applications" → Off (or the other finger count).
gestures:
  enabled: true
  fingers: 3              # 3 or 4
  skip-empty: true        # swipes skip empty workspaces and ones shown on another screen
  direction: auto         # auto = like macOS (follows "Natural scrolling"); natural; reversed
  swipe-left: workspace-next    # natural direction; any command, ~ for nothing
  swipe-right: workspace-prev
  swipe-up: ~
  swipe-down: ~

# Scratchpads, like xmonad's NamedScratchpad: one key shows the window
# floating over whatever workspace you're on, the same key hides it again.
# If it isn't open yet, `run` starts it.
#   name      used by the command: scratchpad <name>
#   app       bundle ID or app name of its window; title (optional) narrows it down:
#             a case-insensitive "contains", so use a short, stable part (the file name)
#   run       a shell command (/bin/sh): quote paths with spaces, "$HOME/My Docs/notes.txt"
#             (~ isn't expanded inside quotes)
#   size      [width, height] as shares of the screen; position: center or top
scratchpads:
  - name: term
    app: org.alacritty
    title: scratchpad
    run: open -na Alacritty --args --title scratchpad -o window.dynamic_title=false
    size: [0.6, 0.55]
  # - name: notes
  #   app: com.apple.Notes
  #   run: open -a Notes
  #   size: [0.45, 0.7]

# A frame around the focused window, so you always see where you are.
border:
  enabled: true
  width: 3
  color: accent           # accent = your macOS accent colour, or "#RRGGBB"
  radius: auto            # auto = follow each window's corners, or a number
  smart: false            # true: no frame when a window is alone on its screen

# Rules, like xmonad's manageHook: where an app's windows open, or whether
# they float. mod-shift-p sets one for the focused app and writes it here.
# Find an app's bundle ID with: osascript -e 'id of app "Name"'
#   - app: com.tinyspeck.slackmacgap   # bundle ID or app name
#     workspace: 9
#   - app: com.google.Chrome
#     title: "Meet"                    # only windows whose title contains this
#     workspace: 5
# title-not leaves out windows whose title contains one of the texts.
# hide: minimize minimizes a window while its workspace is out of sight
# instead of moving it into a corner, so call apps show their small window.
rules:
  - app: com.apple.systempreferences   # System Settings
    float: true
  - app: com.apple.calculator   # Calculator
    float: true
  - app: com.apple.archiveutility   # Archive Utility
    float: true
  - app: com.microsoft.teams2   # Microsoft Teams: every meeting window (all but the main one)
    title-not: ["Microsoft Teams", teams.microsoft.com]
    hide: minimize

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
#   next-layout  prev-layout  shrink  expand  inc-master  dec-master  toggle-float
#   layout <name>          straight to a layout, e.g. layout full (names under layouts:)
#   toggle-tiling          pause tiling (windows stay put) and resume it
#   increase-window-limit  decrease-window-limit   change window-limit
#   toggle-focus-follows-mouse
#   workspace-back         the workspace this screen showed before (xmonad toggleWS)
#   taller  shorter        the focused window's share of its column (xmonad ResizableTall)
#   reset-sizes            equal sizes and the default split again
#   focus left|right|up|down   focus the window in that direction (across screens)
#   swap left|right|up|down    swap the focused window with the one in that direction
#   toggle-fullscreen      show the workspace in Full until toggled back
#   scratchpad <name>      show or hide a scratchpad (see scratchpads:)
#   window-search          search all open windows and jump to one
#   app-rule               choose the workspace the focused app always opens on
#   settings               open the settings window
#   welcome                the welcome window and macOS settings check
#   shortcuts              show all shortcuts (also: hold mod alone, see shortcut-overview)
#   refresh  close  terminal  reload  restart  quit
#   spawn <shell command>
#   send-key <keys>        press keys in the front app, e.g. send-key cmd-w (like skhd --key)
# A key mapped to ~ is unbound. This section replaces the defaults as a whole.
#
# Amethyst-style: mod is Amethyst's mod1 (Option), mod-shift its mod2 (Option+Shift).
# Option + q / return / f / b are left free (e.g. for skhd).
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
  mod-period: focus-prev-screen
  # Amethyst reevaluate-windows
  mod-z: refresh

  # Not in Amethyst (xmonad-style extras)
  mod-p: window-search      # like dmenu / XMonad.Prompt.Window on mod-p
  mod-s: scratchpad term    # show/hide the scratchpad terminal
  mod-shift-f: toggle-fullscreen   # mod-f is left free
  mod-tab: workspace-back   # back and forth between the last two workspaces
  mod-shift-h: shorter      # the focused window's height in its column
  mod-shift-l: taller       # (like mod-h / mod-l for the master)
  # Directional focus and swap (mod-arrows would break word jumps in text)
  ctrl-alt-left: focus left
  ctrl-alt-right: focus right
  ctrl-alt-up: focus up
  ctrl-alt-down: focus down
  ctrl-alt-shift-left: swap left
  ctrl-alt-shift-right: swap right
  ctrl-alt-shift-up: swap up
  ctrl-alt-shift-down: swap down
  mod-shift-p: app-rule     # "always open this app on workspace N" (writes rules: above)
  mod-shift-comma: shift-to-next-screen
  mod-shift-period: shift-to-prev-screen
  mod-m: focus-master
  mod-shift-m: swap-master
  mod-t: toggle-float
  mod-shift-r: restart
  mod-shift-q: quit
"""#
}
