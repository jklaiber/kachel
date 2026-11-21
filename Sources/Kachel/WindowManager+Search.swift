import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - window search

    func touch(_ id: WindowID) {
        if mru.first == id { return }
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
        if mru.count > 200 { mru.removeLast(mru.count - 200) }
    }

    func toggleWindowSearch() {
        if switcher.isOpen { switcher.close(cancelled: true); return }
        syncFocusFromSystem(followHidden: false)
        let focused = ss.current.focused
        var apps: [pid_t: NSRunningApplication] = [:]
        var entries: [WindowSwitcher.Entry] = []
        for (i, ws) in ss.workspaces.enumerated() {
            for id in ws.windows where !scratchParked.contains(id) {
                guard let w = windows[id] else { continue }
                let app = apps[w.pid] ?? NSRunningApplication(processIdentifier: w.pid)
                apps[w.pid] = app
                entries.append(.init(id: id, app: app?.localizedName ?? w.bundleID ?? "?", title: w.title,
                                     icon: app?.icon, workspace: i, tag: ws.tag,
                                     visible: ss.isVisible(workspace: i), active: i == ss.currentWorkspaceIndex,
                                     recency: mru.firstIndex(of: id) ?? mru.count + Int(id % 1000),
                                     focused: id == focused))
            }
        }
        guard ss.currentScreen < screens.count else { return }
        let scr = screens[ss.currentScreen]
        let cfg = Config.current.bar
        switcher.open(entries, area: scr.nsVisible, bottom: cfg.enabled ? Bar.height(for: cfg) : 0)
    }

    /// ↩ in the search: show the window's workspace here (greedyView) and focus it.
    func goToWindow(_ id: WindowID) {
        guard let ws = ss.workspaceIndex(of: id) else { return }
        if ws != ss.currentWorkspaceIndex { show(ws) }
        ss.focus(id)
        render()
    }

    /// ⇧↩ in the search: move the window to this workspace and focus it.
    func bringWindow(_ id: WindowID) {
        let here = ss.currentWorkspaceIndex
        if ss.workspaceIndex(of: id) != here { ss.shift(id, to: here) }
        ss.focus(id)
        render()
    }

    // MARK: - app rules (mod-shift-p)

    func toggleRulePicker() {
        if rulePicker.isOpen { rulePicker.close(cancelled: true); return }
        syncFocusFromSystem(followHidden: false)
        guard let fid = ss.current.focused, let w = windows[fid] else {
            Log.info("app rule: no focused window")
            NSSound.beep()
            return
        }
        let name = appName(of: w)
        let key = w.bundleID ?? name                       // what the rule matches on
        let existing = Config.current.rules.first {
            $0.title == nil && $0.matches(bundleID: w.bundleID, appName: name, title: "")
        }
        let cfg = Config.current
        guard ss.currentScreen < screens.count else { return }
        rulePicker.onChoose = { [unowned self] choice in
            var r = existing ?? Rule(app: key)
            switch choice {
            case .workspace(let i): r.workspace = cfg.workspaces[i]
            case .toggleFloat: r.float.toggle()
            case .remove: break
            }
            let keep: Rule? = {
                if case .remove = choice { return nil }
                return (r.workspace == nil && !r.float) ? nil : r
            }()
            Config.setRule(app: existing?.app ?? key, rule: keep, comment: name)
            Config.load(force: true)
            self.applySettings(rebindKeys: false)
            self.applyRuleNow(bundleID: w.bundleID, appName: name)
        }
        rulePicker.open(app: name, icon: NSRunningApplication(processIdentifier: w.pid)?.icon,
                        tags: cfg.workspaces,
                        current: existing?.workspace.flatMap(cfg.workspaceIndex(named:)),
                        floats: existing?.float ?? false, hasRule: existing != nil,
                        area: screens[ss.currentScreen].nsVisible,
                        bottom: cfg.bar.enabled ? Bar.height(for: cfg.bar) : 0)
    }

    /// After setting a rule: move the app's open windows there now, and
    /// float or tile them to match. You stay on your workspace.
    func applyRuleNow(bundleID: String?, appName name: String) {
        var moved = 0
        for (id, w) in windows where w.bundleID == bundleID && appName(of: w) == name {
            let r = rule(for: w)
            if let ws = r?.workspace.flatMap(Config.current.workspaceIndex(named:)), ss.workspaceIndex(of: id) != ws {
                ss.shift(id, to: ws)
                moved += 1
            }
            if r?.float == true { ss.floating.insert(id) }
            else if !shouldFloat(w) { ss.floating.remove(id) }
        }
        Log.info("rule for \(name): moved \(moved) window(s)")
        render()
    }
}
