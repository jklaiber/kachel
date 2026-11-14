import Foundation

/// xmonad's manageHook, as data:
///
///   rules:
///     - app: com.tinyspeck.slackmacgap   # Slack
///       workspace: 9
///     - app: Calculator
///       float: true
///
/// `app` is a bundle ID or an app name; `title` (optional) must appear in the
/// window title. The first matching rule wins. Rules apply when a window
/// appears, not to windows you've since moved by hand.
public struct Rule: Equatable {
    public var app: String
    public var title: String?
    public var workspace: String?     // workspace name (or number)
    public var float = false

    public init(app: String, title: String? = nil, workspace: String? = nil, float: Bool = false) {
        self.app = app; self.title = title; self.workspace = workspace; self.float = float
    }

    public func matches(bundleID: String?, appName: String?, title windowTitle: String) -> Bool {
        let a = app.lowercased()
        guard a == bundleID?.lowercased() || a == appName?.lowercased() else { return false }
        if let t = title, !t.isEmpty { return windowTitle.localizedCaseInsensitiveContains(t) }
        return true
    }
}

extension Settings {
    /// Index of a workspace given by name, or by number 1…n.
    public func workspaceIndex(named value: String) -> Int? {
        if let i = workspaces.firstIndex(of: value) { return i }
        if let n = Int(value), n >= 1, n <= workspaces.count { return n - 1 }
        return nil
    }

    public func rule(bundleID: String?, appName: String?, title: String) -> Rule? {
        rules.first { $0.matches(bundleID: bundleID, appName: appName, title: title) }
    }

    static func parseRules(_ v: Any, workspaces: [String]) throws -> [Rule] {
        if v is NSNull { return [] }
        guard let list = v as? [Any] else { throw SettingsError("rules must be a list") }
        var probe = Settings()
        probe.workspaces = workspaces
        return try list.enumerated().map { i, item in
            let ctx = "rules[\(i + 1)]"
            guard let d = item as? [String: Any] else { throw SettingsError("\(ctx) must be a mapping with app: …") }
            if let bad = d.keys.first(where: { !["app", "title", "workspace", "float"].contains($0) }) {
                throw SettingsError("\(ctx): unknown setting '\(bad)' (use app, title, workspace, float)")
            }
            guard let app = d["app"].map({ "\($0)" }), !app.isEmpty else { throw SettingsError("\(ctx) needs app:") }
            var r = Rule(app: app)
            if let t = d["title"], !(t is NSNull) { r.title = "\(t)" }
            if let w = d["workspace"], !(w is NSNull) {
                let name = "\(w)"
                guard probe.workspaceIndex(named: name) != nil else {
                    throw SettingsError("\(ctx): there is no workspace '\(name)'")
                }
                r.workspace = name
            }
            if let f = d["float"] {
                guard let b = f as? Bool else { throw SettingsError("\(ctx): float must be true or false") }
                r.float = b
            }
            return r
        }
    }

    // MARK: - editing the file

    /// Replace (or with `rule == nil`, remove) the app-wide rule for `app` in
    /// a config file's text, keeping everything else. Rules with a `title:`
    /// are left alone: they're hand-written and more specific.
    public static func setRule(_ text: String, app: String, rule: Rule?, comment: String? = nil) -> String {
        var lines = text.components(separatedBy: "\n")

        // Find or create the `rules:` section.
        var head = lines.firstIndex { $0.hasPrefix("rules:") }
        if head == nil {
            guard rule != nil else { return text }
            let at = lines.firstIndex { $0.hasPrefix("# Keys:") } ?? lines.firstIndex { $0.hasPrefix("keys:") } ?? lines.count
            lines.insert(contentsOf: ["# Always put an app's windows on a workspace, or float them (mod-shift-p).", "rules:", ""], at: at)
            head = at + 1
        }
        let h = head!
        let afterKey = lines[h].dropFirst("rules:".count).trimmingCharacters(in: .whitespaces)
        if afterKey.hasPrefix("[]") || afterKey.hasPrefix("~") || afterKey.hasPrefix("null") {
            let comment = lines[h].range(of: " #").map { String(lines[h][$0.lowerBound...]) } ?? ""
            lines[h] = "rules:" + comment
        }

        func sectionEnd() -> Int {
            var e = h + 1
            while e < lines.count {
                let l = lines[e]
                if l.isEmpty || l.hasPrefix(" ") || l.hasPrefix("-") || l.hasPrefix("#") { e += 1 } else { break }
            }
            // Don't swallow the blank lines / comments that introduce the next section.
            while e > h + 1, lines[e - 1].trimmingCharacters(in: .whitespaces).isEmpty || lines[e - 1].hasPrefix("#") { e -= 1 }
            return e
        }

        // Remove the existing app-wide entry for this app.
        var i = h + 1
        while i < sectionEnd() {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { i += 1; continue }
            let indent = lines[i].prefix { $0 == " " }.count
            var j = i + 1
            // The entry's own keys are indented deeper than its "- ".
            while j < sectionEnd(), !lines[j].isEmpty, lines[j].prefix(while: { $0 == " " }).count > indent {
                j += 1
            }
            let block = lines[i..<j]
            let isThisApp = block.contains { l in
                let s = l.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: "")
                guard s.hasPrefix("app:") else { return false }
                var v = s.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if let hash = v.range(of: " #") { v = String(v[..<hash.lowerBound]) }
                v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                return v.lowercased() == app.lowercased()
            }
            let hasTitle = block.contains { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: "").hasPrefix("title:") }
            if isThisApp && !hasTitle {
                lines.removeSubrange(i..<j)
            } else {
                i = j
            }
        }

        if let rule {
            var entry = ["  - app: \(yamlScalar(rule.app))" + (comment.map { "   # \($0)" } ?? "")]
            if let w = rule.workspace { entry.append("    workspace: \(yamlScalar(w))") }
            if rule.float { entry.append("    float: true") }
            lines.insert(contentsOf: entry, at: sectionEnd())
        }
        return lines.joined(separator: "\n")
    }

    /// Set a top-level `key: value` line, keeping its comment; adds it before
    /// the keys section if it isn't there.
    public static func setTopLevel(_ text: String, key: String, value: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { $0.hasPrefix("\(key):") }) {
            let rest = lines[i].dropFirst(key.count + 1)
            let comment = rest.range(of: " #").map { String(rest[$0.lowerBound...]) } ?? ""
            let pad = comment.isEmpty ? "" : String(repeating: " ", count: max(1, 24 - key.count - value.count))
            lines[i] = "\(key): \(value)" + (comment.isEmpty ? "" : pad + comment.trimmingCharacters(in: .whitespaces))
        } else {
            let at = lines.firstIndex { $0.hasPrefix("# Keys:") } ?? lines.firstIndex { $0.hasPrefix("keys:") } ?? lines.count
            lines.insert("\(key): \(value)", at: at)
        }
        return lines.joined(separator: "\n")
    }

    private static func yamlScalar(_ s: String) -> String {
        let plain = s.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
        return plain && !s.isEmpty ? s : "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
