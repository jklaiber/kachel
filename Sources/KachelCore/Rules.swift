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
/// window title. The first matching rule wins. `workspace` and `float` apply
/// when a window appears, not to windows you've since moved by hand; `hide`
/// applies whenever the window's workspace goes out of sight.
public struct Rule: Equatable {
    /// What happens to the window while its workspace isn't shown.
    public enum Hide: String, Equatable {
        case park          // moved into a screen corner (the default)
        case minimize      // minimized, so call apps show their small window
    }

    public var app: String
    public var title: String?
    /// Windows whose title contains any of these don't match (e.g. Teams'
    /// main window, so that a rule covers all its meeting windows).
    public var titleNot: [String] = []
    public var workspace: String?     // workspace name (or number)
    public var float = false
    public var hide = Hide.park

    public init(app: String, title: String? = nil, titleNot: [String] = [], workspace: String? = nil,
                float: Bool = false, hide: Hide = .park) {
        self.app = app; self.title = title; self.titleNot = titleNot; self.workspace = workspace
        self.float = float; self.hide = hide
    }

    public func matches(bundleID: String?, appName: String?, title windowTitle: String) -> Bool {
        let a = app.lowercased()
        guard a == bundleID?.lowercased() || a == appName?.lowercased() else { return false }
        if titleNot.contains(where: { !$0.isEmpty && windowTitle.localizedCaseInsensitiveContains($0) }) { return false }
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
            if let bad = d.keys.first(where: { !["app", "title", "title-not", "workspace", "float", "hide"].contains($0) }) {
                throw SettingsError("\(ctx): unknown setting '\(bad)' (use app, title, title-not, workspace, float, hide)")
            }
            guard let app = d["app"].map({ "\($0)" }), !app.isEmpty else { throw SettingsError("\(ctx) needs app:") }
            var r = Rule(app: app)
            if let t = d["title"], !(t is NSNull) { r.title = "\(t)" }
            if let t = d["title-not"], !(t is NSNull) {
                // One text, or a list of them.
                r.titleNot = (t as? [Any])?.map { "\($0)" } ?? ["\(t)"]
            }
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
            if let h = d["hide"], !(h is NSNull) {
                guard let mode = Rule.Hide(rawValue: "\(h)") else {
                    throw SettingsError("\(ctx): hide must be park or minimize")
                }
                r.hide = mode
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
            // Rules that look at the title (title: or title-not:) are more specific: leave them.
            let hasTitle = block.contains {
                let t = $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: "")
                return t.hasPrefix("title:") || t.hasPrefix("title-not:")
            }
            if isThisApp && !hasTitle {
                lines.removeSubrange(i..<j)
            } else {
                i = j
            }
        }

        if let rule {
            lines.insert(contentsOf: entryLines(rule, comment: comment.map { "   # \($0)" } ?? ""), at: sectionEnd())
        }
        return lines.joined(separator: "\n")
    }

    /// Add a rule at the end of the `rules:` list.
    public static func addRule(_ text: String, _ rule: Rule, comment: String? = nil) -> String {
        var lines = text.components(separatedBy: "\n")
        if let last = ruleEntries(lines).last {
            lines.insert(contentsOf: entryLines(rule, comment: comment.map { "   # \($0)" } ?? ""), at: last.upperBound)
            return lines.joined(separator: "\n")
        }
        // No rules yet: the app-wide editor knows how to create the section.
        return setRule(text, app: rule.app, rule: rule, comment: comment)
    }

    /// Replace (or with `rule == nil`, remove) the rule at `index` in the
    /// `rules:` list, whatever it matches; the other rules and every comment
    /// stay. The entry's own comment (`- app: … # Teams`) is kept unless a new
    /// one is given.
    public static func setRule(_ text: String, at index: Int, rule: Rule?, comment: String? = nil) -> String {
        var lines = text.components(separatedBy: "\n")
        let entries = ruleEntries(lines)
        guard entries.indices.contains(index) else { return text }
        let range = entries[index]
        guard let rule else {
            lines.removeSubrange(range)
            return lines.joined(separator: "\n")
        }
        let first = lines[range.lowerBound]
        var suffix = comment.map { "   # \($0)" } ?? ""
        if comment == nil, let hash = first.range(of: " #") {
            // Keep the comment with the spaces in front of it.
            var start = hash.lowerBound
            while start > first.startIndex, first[first.index(before: start)] == " " { start = first.index(before: start) }
            suffix = String(first[start...])
        }
        lines.replaceSubrange(range, with: entryLines(rule, comment: suffix))
        return lines.joined(separator: "\n")
    }

    /// The lines of one `- app: …` entry.
    static func entryLines(_ rule: Rule, comment: String) -> [String] {
        var entry = ["  - app: \(yamlScalar(rule.app))" + comment]
        if let t = rule.title, !t.isEmpty { entry.append("    title: \(yamlScalar(t))") }
        let not = rule.titleNot.filter { !$0.isEmpty }
        if not.count == 1 { entry.append("    title-not: \(yamlScalar(not[0]))") }
        if not.count > 1 { entry.append("    title-not: [\(not.map(yamlScalar).joined(separator: ", "))]") }
        if let w = rule.workspace { entry.append("    workspace: \(yamlScalar(w))") }
        if rule.float { entry.append("    float: true") }
        if rule.hide != .park { entry.append("    hide: \(rule.hide.rawValue)") }
        return entry
    }

    /// Line ranges of the entries under `rules:`, in order (the same order
    /// `Settings.rules` has).
    static func ruleEntries(_ lines: [String]) -> [Range<Int>] {
        guard let h = lines.firstIndex(where: { $0.hasPrefix("rules:") }) else { return [] }
        var end = h + 1
        while end < lines.count {
            let l = lines[end]
            if l.isEmpty || l.hasPrefix(" ") || l.hasPrefix("-") || l.hasPrefix("#") { end += 1 } else { break }
        }
        var result: [Range<Int>] = []
        var i = h + 1
        while i < end {
            guard lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("- ") else { i += 1; continue }
            let indent = lines[i].prefix { $0 == " " }.count
            var j = i + 1
            while j < end, !lines[j].isEmpty, !lines[j].hasPrefix("#"),
                  lines[j].prefix(while: { $0 == " " }).count > indent { j += 1 }
            result.append(i..<j)
            i = j
        }
        return result
    }

    public static func yamlScalar(_ s: String) -> String {
        let plain = s.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
        return plain && !s.isEmpty ? s : "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
