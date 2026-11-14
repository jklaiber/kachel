import Foundation

public typealias WindowID = UInt32

public enum LayoutKind: String, CaseIterable {
    case tall = "Tall"
    case mirrorTall = "Mirror"
    case full = "Full"
}

public struct Workspace: Equatable {
    public let tag: String
    public internal(set) var windows: [WindowID] = []   // index 0 = master
    public internal(set) var focused: WindowID?
    public var layout: LayoutKind = .tall
    public var nMaster: Int = 1
    public var ratio: Double = 0.5

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

    // MARK: workspace switching

    /// xmonad's W.greedyView: always bring workspace `i` to the current screen.
    /// If it is visible on another screen, the two screens swap workspaces.
    public mutating func greedyView(_ i: Int) {
        guard workspaces.indices.contains(i) else { return }
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

    public mutating func focusMaster() {
        modifyCurrent { ws in ws.focused = ws.windows.first }
    }

    public mutating func swapMaster() {
        modifyCurrent { ws in
            guard let f = ws.focused, let i = ws.windows.firstIndex(of: f), i > 0 else { return }
            ws.windows.swapAt(0, i)
        }
    }

    // MARK: layout

    public mutating func nextLayout() {
        modifyCurrent { ws in
            let all = LayoutKind.allCases
            let i = all.firstIndex(of: ws.layout)!
            ws.layout = all[(i + 1) % all.count]
        }
    }

    public mutating func incMaster(_ d: Int) {
        modifyCurrent { ws in ws.nMaster = max(0, ws.nMaster + d) }
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
