import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - the kachel command

    /// One line from `kachel …` (see Ctl.swift).
    func ctl(_ text: String) -> (ok: Bool, output: String) {
        Log.info("kachel command: \(text)")
        let parts = text.split(separator: " ").map(String.init)
        switch parts.first {
        case "version": return (true, "Kachel.app \(AppVersion.string)")
        case "dump": dumpState(); return (true, "written to ~/Library/Logs/Kachel.log")
        case "query":
            guard managing else { return (false, "Kachel isn't managing windows yet (Accessibility permission)") }
            guard let what = parts.dropFirst().first, let json = query(what) else {
                return (false, "query what? workspaces, windows, screens or focused")
            }
            return (true, json)
        default:
            do {
                let cmd = try Settings.parseCommand(text, workspaceCount: Config.current.workspaces.count, context: "command")
                perform(cmd)
                return (true, "")
            } catch {
                return (false, "\(error)")
            }
        }
    }

    func query(_ what: String) -> String? {
        func window(_ id: WindowID) -> [String: Any] {
            let w = windows[id]
            var d: [String: Any] = [
                "id": id, "app": w.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? "",
                "bundle-id": w?.bundleID ?? "", "title": w?.title ?? "", "pid": w?.pid ?? 0,
                "workspace": ss.workspaceIndex(of: id).map { ss.workspaces[$0].tag } ?? NSNull(),
                "floating": ss.floating.contains(id), "visible": !hidden.contains(id),
                "focused": ss.current.focused == id,
            ]
            if let f = w?.frame { d["frame"] = ["x": f.minX, "y": f.minY, "width": f.width, "height": f.height] }
            return d
        }
        func workspace(_ i: Int) -> [String: Any] {
            let ws = ss.workspaces[i]
            return ["index": i + 1, "name": ws.tag, "layout": ws.effectiveLayout.configName,
                    "screen": ss.screenWorkspace.firstIndex(of: i).map { $0 + 1 } ?? NSNull(),
                    "visible": ss.screenWorkspace.contains(i), "focused": ss.currentWorkspaceIndex == i,
                    "windows": ws.windows, "focused-window": ws.focused ?? NSNull()]
        }
        let value: Any
        switch what {
        case "workspaces": value = ss.workspaces.indices.map(workspace)
        case "windows": value = ss.workspaces.flatMap(\.windows).map(window)
        case "screens":
            value = screens.enumerated().map { i, s -> [String: Any] in
                ["index": i + 1, "name": s.ns.localizedName, "builtin": s.builtin, "focused": ss.currentScreen == i,
                 "workspace": ss.screenWorkspace.indices.contains(i) ? ss.workspaces[ss.screenWorkspace[i]].tag : NSNull(),
                 "frame": ["x": s.frame.minX, "y": s.frame.minY, "width": s.frame.width, "height": s.frame.height]]
            }
        case "focused":
            value = ["workspace": workspace(ss.currentWorkspaceIndex),
                     "window": ss.current.focused.map(window) ?? NSNull()] as [String: Any]
        default: return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
