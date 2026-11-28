import AppKit
import KachelCore

/// What `kachel subscribe` watches. Compared after every change Kachel shows
/// in the bar, so an event goes out exactly when the bar would change.
struct EventState: Equatable {
    var workspace: Int
    /// The workspace on each display.
    var screens: [Int]
    var layouts: [String]
    var windows: [[WindowID]]
    var focused: WindowID?
    var title: String
}

extension WindowManager {
    static let eventKinds = ["workspace", "focus", "layout", "windows"]

    func eventState() -> EventState {
        let f = ss.current.focused.flatMap { windows[$0] != nil ? $0 : nil }
        return EventState(workspace: ss.currentWorkspaceIndex,
                          screens: ss.screenWorkspace,
                          layouts: ss.workspaces.map { tilingPaused ? "paused" : $0.effectiveLayout.configName },
                          windows: ss.workspaces.map { ws in ws.windows.filter { windows[$0] != nil && !scratchParked.contains($0) } },
                          focused: f, title: f.flatMap { windows[$0]?.title } ?? "")
    }

    /// Sends the events for what changed since the last call.
    func publishEvents() {
        guard managing, onEvent != nil, eventsWanted() else { return }
        let now = eventState()
        guard let before = lastEvents else { lastEvents = now; return }
        guard now != before else { return }
        lastEvents = now
        for (kind, line) in events(from: before, to: now) { onEvent?(kind, line) }
    }

    /// The events between two states (before nil: what a new subscriber gets first).
    func events(from before: EventState?, to now: EventState) -> [(kind: String, line: String)] {
        var out: [(String, String)] = []
        func tag(_ i: Int) -> String { ss.workspaces.indices.contains(i) ? ss.workspaces[i].tag : "" }
        func emit(_ kind: String, _ fields: [String: Any]) {
            var d = fields
            d["event"] = kind
            guard let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) else { return }
            out.append((kind, String(decoding: data, as: UTF8.self)))
        }
        if before == nil || before!.workspace != now.workspace || before!.screens != now.screens {
            emit("workspace", ["workspace": tag(now.workspace),
                               "previous": before.map { tag($0.workspace) } ?? NSNull(),
                               "screen": ss.currentScreen + 1,
                               "visible": now.screens.map(tag)])
        }
        if let before {
            for i in now.layouts.indices where i >= before.layouts.count || before.layouts[i] != now.layouts[i] {
                emit("layout", ["workspace": tag(i), "layout": now.layouts[i]])
            }
            for i in now.windows.indices where i >= before.windows.count || before.windows[i] != now.windows[i] {
                emit("windows", ["workspace": tag(i), "windows": now.windows[i]])
            }
        } else {
            emit("layout", ["workspace": tag(now.workspace), "layout": now.layouts[now.workspace]])
        }
        if before == nil || before!.focused != now.focused || before!.title != now.title {
            var window: Any = NSNull()
            if let id = now.focused, let w = windows[id] {
                window = ["id": id, "app": appName(of: w), "bundle-id": w.bundleID ?? "", "title": w.title]
            }
            emit("focus", ["workspace": tag(now.workspace), "window": window])
        }
        return out
    }

    /// For a new subscriber: where things are now.
    func currentEvents() -> [(kind: String, line: String)] {
        guard managing else { return [] }
        publishEvents()                   // the others hear what's pending first
        let now = eventState()
        lastEvents = now
        return events(from: nil, to: now)
    }
}
