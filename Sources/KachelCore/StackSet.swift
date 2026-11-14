import Foundation

public typealias WindowID = UInt32

public enum LayoutKind: String, CaseIterable, Codable {
    case tall = "Tall"          // master left, stack right
    case mirrorTall = "Wide"    // master on top, stack below (Amethyst "wide", xmonad Mirror Tall)
    case column = "Column"      // all windows side by side, equal width
    case threeColumn = "ThreeCol"   // master in the middle, stacks left and right (xmonad ThreeColMid)
    case full = "Full"

    /// Name in config.yaml.
    public var configName: String {
        switch self {
        case .tall: return "tall"
        case .mirrorTall: return "wide"
        case .column: return "column"
        case .threeColumn: return "three-column"
        case .full: return "full"
        }
    }

    public init?(configName: String) {
        switch configName.lowercased() {
        case "tall": self = .tall
        case "wide", "mirror", "mirror-tall": self = .mirrorTall
        case "column", "columns": self = .column
        case "three-column", "threecol", "3column", "three-columns": self = .threeColumn
        case "full", "fullscreen": self = .full
        default: return nil
        }
    }
}

public struct Workspace: Equatable {
    public internal(set) var tag: String
    public internal(set) var windows: [WindowID] = []   // index 0 = master
    public internal(set) var focused: WindowID?
    public var layout: LayoutKind = .tall
    public var nMaster: Int = 1
    public var ratio: Double = 0.5
    /// Toggled fullscreen (xmonad ToggleLayouts): show Full until toggled back.
    public var fullscreen = false
    /// Share of each window in its column, 1 = normal (xmonad ResizableTall).
    public var weights: [WindowID: Double] = [:]

    /// The layout actually used for tiling.
    public var effectiveLayout: LayoutKind { fullscreen ? .full : layout }

    public init(tag: String, ratio: Double = 0.5) {
        self.tag = tag
        self.ratio = ratio
    }
}

/// A port of xmonad's StackSet idea: a fixed set of workspaces, each screen
/// shows exactly one of them, one screen is "current".
public struct StackSet {
    public private(set) var workspaces: [Workspace]
    /// screen index -> index into `workspaces` that the screen shows
    public private(set) var screenWorkspace: [Int]
    public private(set) var currentScreen: Int = 0
    /// screen index -> the workspace it showed before (for back and forth)
    public private(set) var previousOnScreen: [Int: Int] = [:]
    public var floating: Set<WindowID> = []

    public init(tags: [String], screenCount: Int, ratio: Double = 0.5) {
        precondition(!tags.isEmpty, "need at least one workspace")
        workspaces = tags.map { Workspace(tag: $0, ratio: ratio) }
        screenWorkspace = Array(0..<max(1, min(screenCount, tags.count)))
    }

    // MARK: queries

    public var currentWorkspaceIndex: Int { screenWorkspace[currentScreen] }
    public var current: Workspace { workspaces[currentWorkspaceIndex] }
    public var allWindows: [WindowID] { workspaces.flatMap(\.windows) }

    public func screen(ofWorkspace i: Int) -> Int? { screenWorkspace.firstIndex(of: i) }
    public func workspaceIndex(of w: WindowID) -> Int? {
        workspaces.firstIndex { $0.windows.contains(w) }
    }
    public func isVisible(workspace i: Int) -> Bool { screen(ofWorkspace: i) != nil }

    // MARK: screens

    public mutating func setScreenCount(_ count: Int) {
        let n = max(1, min(count, workspaces.count))
        if n < screenWorkspace.count {
            screenWorkspace.removeLast(screenWorkspace.count - n)
        }
        while screenWorkspace.count < n {
            let free = workspaces.indices.first { !screenWorkspace.contains($0) }!
            screenWorkspace.append(free)
        }
        currentScreen = min(currentScreen, n - 1)
    }

    public mutating func focusScreen(_ s: Int) {
        guard screenWorkspace.indices.contains(s) else { return }
        currentScreen = s
    }

    /// Apply a new workspace list from the config. Windows of removed
    /// workspaces move to the last remaining one.
    public mutating func setTags(_ tags: [String]) {
        guard !tags.isEmpty else { return }
        if tags.count < workspaces.count {
            let orphans = workspaces[tags.count...].flatMap(\.windows)
            workspaces.removeLast(workspaces.count - tags.count)
            for w in orphans.reversed() { insert(w, into: tags.count - 1) }
            let screens = screenWorkspace.count
            screenWorkspace = screenWorkspace.filter { $0 < tags.count }
            setScreenCount(screens)
        }
        while workspaces.count < tags.count {
            workspaces.append(Workspace(tag: tags[workspaces.count], ratio: workspaces.last?.ratio ?? 0.5))
        }
        for i in workspaces.indices { workspaces[i].tag = tags[i] }
    }

    // MARK: workspace switching

    /// xmonad's W.greedyView: always bring workspace `i` to the current screen.
    /// If it is visible on another screen, the two screens swap workspaces.
    public mutating func greedyView(_ i: Int) {
        guard workspaces.indices.contains(i) else { return }
        if i != currentWorkspaceIndex { previousOnScreen[currentScreen] = currentWorkspaceIndex }
        if let s = screen(ofWorkspace: i) {
            screenWorkspace.swapAt(s, currentScreen)
        } else {
            screenWorkspace[currentScreen] = i
        }
    }

    /// xmonad's W.view: if `i` is visible elsewhere, just move focus to that screen.
    public mutating func view(_ i: Int) {
        guard workspaces.indices.contains(i) else { return }
        if let s = screen(ofWorkspace: i) {
            currentScreen = s
        } else {
            if i != currentWorkspaceIndex { previousOnScreen[currentScreen] = currentWorkspaceIndex }
            screenWorkspace[currentScreen] = i
        }
    }

    // MARK: windows

    /// Like xmonad's insertUp: the new window goes above the focused one and gets focus.
    public mutating func insert(_ w: WindowID, into target: Int? = nil) {
        guard workspaceIndex(of: w) == nil else { return }
        let i = target ?? currentWorkspaceIndex
        guard workspaces.indices.contains(i) else { return }
        var ws = workspaces[i]
        let at = ws.focused.flatMap { ws.windows.firstIndex(of: $0) } ?? 0
        ws.windows.insert(w, at: at)
        ws.focused = w
        workspaces[i] = ws
    }

    public mutating func remove(_ w: WindowID) {
        floating.remove(w)
        guard let i = workspaceIndex(of: w) else { return }
        var ws = workspaces[i]
        let idx = ws.windows.firstIndex(of: w)!
        ws.windows.remove(at: idx)
        ws.weights[w] = nil
        if ws.focused == w {
            ws.focused = ws.windows.isEmpty ? nil : ws.windows[min(idx, ws.windows.count - 1)]
        }
        workspaces[i] = ws
    }

    /// xmonad's W.shift: send a window to another workspace (focus stays here).
    public mutating func shift(_ w: WindowID, to target: Int) {
        guard let src = workspaceIndex(of: w), src != target,
              workspaces.indices.contains(target) else { return }
        let wasFloating = floating.contains(w)
        remove(w)
        insert(w, into: target)
        if wasFloating { floating.insert(w) }
    }

    /// Swap two windows' places, like dragging one onto the other: within a
    /// workspace they trade positions; across workspaces they trade
    /// workspaces (and positions). Focus marks follow the windows.
    public mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard a != b, let wa = workspaceIndex(of: a), let wb = workspaceIndex(of: b),
              let ia = workspaces[wa].windows.firstIndex(of: a),
              let ib = workspaces[wb].windows.firstIndex(of: b) else { return }
        if wa == wb {
            workspaces[wa].windows.swapAt(ia, ib)
            return
        }
        workspaces[wa].windows[ia] = b
        workspaces[wb].windows[ib] = a
        if workspaces[wa].focused == a { workspaces[wa].focused = b }
        if workspaces[wb].focused == b { workspaces[wb].focused = a }
    }

    /// Mark `w` focused in its workspace. Returns true if that workspace is
    /// visible (and makes its screen current).
    @discardableResult
    public mutating func focus(_ w: WindowID) -> Bool {
        guard let i = workspaceIndex(of: w) else { return false }
        workspaces[i].focused = w
        if let s = screen(ofWorkspace: i) {
            currentScreen = s
            return true
        }
        return false
    }

    public mutating func focusDown() { cycleFocus(+1) }
    public mutating func focusUp() { cycleFocus(-1) }
    public mutating func swapDown() { swapFocused(+1) }
    public mutating func swapUp() { swapFocused(-1) }

    /// The master is the first *tiled* window; floating windows never are.
    public mutating func focusMaster() {
        let floating = self.floating
        modifyCurrent { ws in
            if let m = ws.windows.first(where: { !floating.contains($0) }) { ws.focused = m }
        }
    }

    public mutating func swapMaster() {
        let floating = self.floating
        modifyCurrent { ws in
            guard let f = ws.focused, !floating.contains(f), let i = ws.windows.firstIndex(of: f),
                  let m = ws.windows.firstIndex(where: { !floating.contains($0) }), i != m else { return }
            ws.windows.swapAt(m, i)
        }
    }

    // MARK: layout

    /// Cycle through `order` (the config's `layouts:` list).
    public mutating func nextLayout(in order: [LayoutKind] = LayoutKind.allCases) {
        guard !order.isEmpty else { return }
        modifyCurrent { ws in
            ws.fullscreen = false
            let i = order.firstIndex(of: ws.layout) ?? -1
            ws.layout = order[(i + 1) % order.count]
        }
    }

    /// Set every workspace's layout (from config), e.g. the first of `layouts:`.
    public mutating func setLayoutIfUnlisted(_ order: [LayoutKind]) {
        guard let first = order.first else { return }
        for i in workspaces.indices where !order.contains(workspaces[i].layout) {
            workspaces[i].layout = first
        }
    }

    /// Workspace index `d` steps from the current one, wrapping around.
    public func neighbour(_ d: Int) -> Int {
        let n = workspaces.count
        return ((currentWorkspaceIndex + d) % n + n) % n
    }

    /// The workspace a "next/previous" swipe goes to, like xmonad's CycleWS
    /// with HiddenWS / HiddenNonEmptyWS: workspaces shown on another screen
    /// are skipped (swapping screens on a swipe is confusing), and with
    /// `skipEmpty` so are empty ones. nil when there's nowhere to go.
    /// The workspace this screen showed before the current one (xmonad toggleWS).
    public var previousWorkspace: Int? {
        previousOnScreen[currentScreen].flatMap { workspaces.indices.contains($0) && $0 != currentWorkspaceIndex ? $0 : nil }
    }

    public func cycleTarget(_ d: Int, skipEmpty: Bool, allowed: (Int) -> Bool = { _ in true }) -> Int? {
        let n = workspaces.count
        let here = currentWorkspaceIndex
        for step in 1..<max(n, 1) {
            let i = ((here + d * step) % n + n) % n
            if i == here { break }
            if isVisible(workspace: i) { continue }
            if skipEmpty && workspaces[i].windows.isEmpty { continue }
            if !allowed(i) { continue }
            return i
        }
        return nil
    }

    /// Screen index `d` steps from the current one, wrapping around.
    public func neighbourScreen(_ d: Int) -> Int {
        let n = screenWorkspace.count
        return ((currentScreen + d) % n + n) % n
    }

    // MARK: persistence across restarts

    public struct Snapshot: Codable {
        public var windows: [WindowID: Int]
        public var focused: [Int: WindowID]
        public var order: [Int: [WindowID]]
        public var floating: [WindowID]
        public var screenWorkspace: [Int]
        public var currentScreen: Int
        public var layouts: [Int: LayoutKind]
        public var ratios: [Int: Double]
        public var nMaster: [Int: Int]
        public var fullscreen: [Int: Bool]? = nil     // optional: older saved states lack it
        public var weights: [Int: [WindowID: Double]]? = nil
    }

    public var snapshot: Snapshot {
        var windows: [WindowID: Int] = [:], focused: [Int: WindowID] = [:], order: [Int: [WindowID]] = [:]
        var layouts: [Int: LayoutKind] = [:], ratios: [Int: Double] = [:], nMaster: [Int: Int] = [:]
        var fullscreen: [Int: Bool] = [:]
        var weights: [Int: [WindowID: Double]] = [:]
        for (i, ws) in workspaces.enumerated() {
            ws.windows.forEach { windows[$0] = i }
            order[i] = ws.windows
            if let f = ws.focused { focused[i] = f }
            layouts[i] = ws.layout; ratios[i] = ws.ratio; nMaster[i] = ws.nMaster
            if ws.fullscreen { fullscreen[i] = true }
            if !ws.weights.isEmpty { weights[i] = ws.weights }
        }
        return Snapshot(windows: windows, focused: focused, order: order, floating: Array(floating),
                        screenWorkspace: screenWorkspace, currentScreen: currentScreen,
                        layouts: layouts, ratios: ratios, nMaster: nMaster, fullscreen: fullscreen, weights: weights)
    }

    /// Restore a snapshot. Windows not in `existing` are dropped; existing
    /// windows the snapshot doesn't know are left for the caller to insert.
    public mutating func restore(_ snap: Snapshot, existing: Set<WindowID>) {
        for i in workspaces.indices {
            var ws = workspaces[i]
            ws.windows = (snap.order[i] ?? []).filter { existing.contains($0) && workspaceIndex(of: $0) == nil }
            ws.focused = snap.focused[i].flatMap { ws.windows.contains($0) ? $0 : nil } ?? ws.windows.first
            if let l = snap.layouts[i] { ws.layout = l }
            if let r = snap.ratios[i] { ws.ratio = r }
            if let n = snap.nMaster[i] { ws.nMaster = n }
            ws.fullscreen = snap.fullscreen?[i] ?? false
            ws.weights = (snap.weights?[i] ?? [:]).filter { ws.windows.contains($0.key) }
            workspaces[i] = ws
        }
        floating = Set(snap.floating.filter(existing.contains))
        let screens = screenWorkspace.count
        var restored: [Int] = []
        for w in snap.screenWorkspace where workspaces.indices.contains(w) && !restored.contains(w) {
            restored.append(w)
        }
        screenWorkspace = Array(restored.prefix(screens))
        setScreenCount(screens)
        currentScreen = min(max(0, snap.currentScreen), screenWorkspace.count - 1)
    }

    public mutating func incMaster(_ d: Int) {
        modifyCurrent { ws in ws.nMaster = max(0, ws.nMaster + d) }
    }

    /// Move focus off `w` (e.g. a scratchpad being hidden) to another window
    /// of its workspace that isn't in `excluding`, or to nothing.
    public mutating func focusOther(than w: WindowID, excluding: Set<WindowID> = []) {
        guard let i = workspaceIndex(of: w), workspaces[i].focused == w else { return }
        workspaces[i].focused = workspaces[i].windows.first { $0 != w && !excluding.contains($0) }
    }

    /// Make the focused window taller (factor > 1) or shorter in its column.
    public mutating func scaleFocusedWeight(_ factor: Double) {
        modifyCurrent { ws in
            guard let f = ws.focused else { return }
            ws.weights[f] = min(20, max(0.05, (ws.weights[f] ?? 1) * factor))
        }
    }

    public mutating func setWeights(_ w: [WindowID: Double], workspace i: Int) {
        guard workspaces.indices.contains(i) else { return }
        workspaces[i].weights = w
    }

    /// Back to equal sizes and the default split (AeroSpace balance-sizes).
    public mutating func resetSizes(ratio: Double) {
        modifyCurrent { ws in ws.weights = [:]; ws.ratio = ratio }
    }

    public mutating func toggleFullscreen() {
        modifyCurrent { ws in ws.fullscreen.toggle() }
    }

    /// Set a workspace's master ratio directly (mouse resize).
    public mutating func setRatio(_ r: Double, workspace i: Int) {
        guard workspaces.indices.contains(i) else { return }
        workspaces[i].ratio = min(0.9, max(0.1, r))
    }

    public mutating func adjustRatio(_ d: Double) {
        modifyCurrent { ws in ws.ratio = min(0.9, max(0.1, ws.ratio + d)) }
    }

    public mutating func toggleFloating(_ w: WindowID) {
        if floating.contains(w) { floating.remove(w) } else { floating.insert(w) }
    }

    // MARK: helpers

    private mutating func modifyCurrent(_ f: (inout Workspace) -> Void) {
        let i = currentWorkspaceIndex
        f(&workspaces[i])
    }

    private mutating func cycleFocus(_ d: Int) {
        modifyCurrent { ws in
            guard let f = ws.focused, let i = ws.windows.firstIndex(of: f), ws.windows.count > 1 else { return }
            let n = ws.windows.count
            ws.focused = ws.windows[(i + d + n) % n]
        }
    }

    private mutating func swapFocused(_ d: Int) {
        modifyCurrent { ws in
            guard let f = ws.focused, let i = ws.windows.firstIndex(of: f), ws.windows.count > 1 else { return }
            let n = ws.windows.count
            ws.windows.swapAt(i, (i + d + n) % n)
        }
    }
}
