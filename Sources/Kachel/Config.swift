import AppKit
import KachelCore

/// Loads ~/.config/kachel/config.yaml, writes the commented default on
/// first launch, and notices when the file is saved.
enum Config {
    /// The settings in effect. Starts with the built-in defaults.
    static private(set) var current = Settings.defaults
    /// Last error from loading the file, shown in the bar.
    static private(set) var error: String?

    static let url: URL = {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("kachel/config.yaml")
    }()

    private static var lastModified: Date?

    /// Returns true if the file was (re)read, successfully or not.
    @discardableResult
    static func load(force: Bool = false) -> Bool {
        let fm = FileManager.default
        migrateFromXMonadMac()
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Settings.defaultYAML.write(to: url, atomically: true, encoding: .utf8)
                Log.info("wrote default config to \(url.path)")
            } catch {
                Log.info("could not write default config: \(error)")
            }
        }
        let mtime = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard force || mtime != lastModified else { return false }
        lastModified = mtime

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            current = try Settings.parse(text)
            error = nil
            defer { NotificationCenter.default.post(name: didLoad, object: nil) }
            Log.info("loaded \(url.path): \(current.keys.count) keys, mod=\(KSettings.modText(current.mod, sides: current.modSides))")
        } catch {
            self.error = "\(error)"
            Log.info("config error (keeping previous settings): \(error)")
            NotificationCenter.default.post(name: didLoad, object: nil)
        }
        return true
    }

    /// Show or hide a bar widget by rewriting just `bar.left` / `bar.right` in
    /// the file, leaving comments and everything else alone.
    static func toggleWidget(_ w: BarWidget) {
        var bar = current.bar
        if bar.shows(w) {
            bar.left.removeAll { $0 == w }
            bar.right.removeAll { $0 == w }
        } else {
            let defaults = BarSettings()
            if defaults.left.contains(w) { bar.left = insert(w, into: bar.left, order: defaults.left) }
            else { bar.right = insert(w, into: bar.right, order: defaults.right) }
        }
        do {
            var text = try String(contentsOf: url, encoding: .utf8)
            text = Settings.setBarList(text, key: "left", bar.left)
            text = Settings.setBarList(text, key: "right", bar.right)
            try text.write(to: url, atomically: true, encoding: .utf8)
            Log.info("bar: \(w.rawValue) \(bar.shows(w) ? "on" : "off")")
        } catch {
            Log.info("could not update config: \(error)")
        }
    }

    /// Put `w` where it sits in the default order, relative to what's already shown.
    private static func insert(_ w: BarWidget, into list: [BarWidget], order: [BarWidget]) -> [BarWidget] {
        var list = list
        let rank = order.firstIndex(of: w) ?? order.count
        let at = list.firstIndex { (order.firstIndex(of: $0) ?? order.count) > rank } ?? list.count
        list.insert(w, at: at)
        return list
    }

    /// Write (or remove) the app-wide rule for `app` into the config file.
    static func setRule(app: String, rule: Rule?, comment: String?) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            try Settings.setRule(text, app: app, rule: rule, comment: comment).write(to: url, atomically: true, encoding: .utf8)
            Log.info("rule for \(app): " + (rule.map { "workspace \($0.workspace ?? "-") float \($0.float)" } ?? "removed"))
        } catch {
            Log.info("could not update config: \(error)")
        }
    }

    static func setTopLevel(key: String, value: String) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            try Settings.setTopLevel(text, key: key, value: value).write(to: url, atomically: true, encoding: .utf8)
            Log.info("config: \(key) = \(value)")
        } catch {
            Log.info("could not update config: \(error)")
        }
    }

    /// Kachel used to be called XMonadMac: bring its config over once, so
    /// keys, rules and bar settings survive the rename. The old file stays.
    private static func migrateFromXMonadMac() {
        let fm = FileManager.default
        let old = url.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("xmonadmac/config.yaml")
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: old.path),
              var text = try? String(contentsOf: old, encoding: .utf8) else { return }
        text = text
            .replacingOccurrences(of: "# XMonadMac configuration  (~/.config/xmonadmac/config.yaml)",
                                  with: "# Kachel configuration  (~/.config/kachel/config.yaml)")
            .replacingOccurrences(of: "# XMonadMac icon in the top menu bar", with: "# Kachel icon in the top menu bar")
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            Log.info("moved config from \(old.path) to \(url.path) (the old file can be deleted)")
        } catch {
            Log.info("could not move old config: \(error)")
        }
    }

    /// Posted after every (re)load, so the settings window can follow edits
    /// made anywhere (the file itself, the bar's menu, the rule picker).
    static let didLoad = Notification.Name("KachelConfigDidLoad")

    /// Change config.yaml's text through `transform`, apply it, and roll back
    /// if the result doesn't load. Returns the error, or nil.
    @discardableResult
    static func edit(_ transform: (String) -> String) -> String? {
        guard let old = try? String(contentsOf: url, encoding: .utf8) else { return "could not read \(url.path)" }
        let new = transform(old)
        guard new != old else { return nil }
        do { try new.write(to: url, atomically: true, encoding: .utf8) } catch { return "\(error)" }
        WindowManager.shared.reload()
        if let e = error {
            Log.info("settings: change rejected, restoring the previous config: \(e)")
            try? old.write(to: url, atomically: true, encoding: .utf8)
            WindowManager.shared.reload()
            return e
        }
        return nil
    }

    static func openInEditor() {
        NSWorkspace.shared.open(url)
    }
}
