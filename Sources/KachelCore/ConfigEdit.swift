import Foundation

/// Careful edits of config.yaml's text for the settings window: change one
/// value, keep every comment and everything else as written.
extension Settings {
    /// `key: value` at the top level. A block that belonged to the old value
    /// (`workspaces:` followed by `  - …` lines) is replaced too; comments stay.
    /// Missing keys are added before the keys section.
    public static func setTopLevel(_ text: String, key: String, value: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { $0.hasPrefix("\(key):") }) {
            lines[i] = replacingValue(lines[i], key: key, indent: "", value: value)
            removeBlock(after: i, indent: 0, in: &lines)
        } else {
            let at = lines.firstIndex { $0.hasPrefix("# Keys:") } ?? lines.firstIndex { $0.hasPrefix("keys:") } ?? lines.count
            lines.insert("\(key): \(value)", at: at)
        }
        return lines.joined(separator: "\n")
    }

    /// `key: value` inside a top-level section (`bar:`, `border:`, `gestures:`).
    public static func setNested(_ text: String, section: String, key: String, value: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let head = lines.firstIndex(where: { $0.hasPrefix("\(section):") }) else {
            return text + (text.hasSuffix("\n") ? "" : "\n") + "\n\(section):\n  \(key): \(value)\n"
        }
        // A flow mapping like `bar: {enabled: false}` becomes a block first.
        let after = lines[head].dropFirst(section.count + 1).trimmingCharacters(in: .whitespaces)
        if after.hasPrefix("{"), let close = after.lastIndex(of: "}") {
            // Unfold `{a: 1, b: 2}` into a block, keeping every entry.
            let inner = after[after.index(after: after.startIndex)..<close]
            var entries: [String] = [], depth = 0, inQuote = false, cur = ""
            for ch in inner {
                if ch == "\"" { inQuote.toggle() }
                if !inQuote, "[{".contains(ch) { depth += 1 }
                if !inQuote, "]}".contains(ch) { depth -= 1 }
                if ch == ",", depth == 0, !inQuote { entries.append(cur); cur = "" } else { cur.append(ch) }
            }
            entries.append(cur)
            lines[head] = "\(section):"
            let block = entries.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { "  " + $0 }
            lines.insert(contentsOf: block, at: head + 1)
            return setNested(lines.joined(separator: "\n"), section: section, key: key, value: value)
        }
        var i = head + 1
        while i < lines.count, lines[i].isEmpty || lines[i].hasPrefix(" ") || lines[i].hasPrefix("#") {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            let indent = lines[i].prefix { $0 == " " }.count
            if indent == 2, t.hasPrefix("\(key):") {
                lines[i] = replacingValue(lines[i], key: key, indent: "  ", value: value)
                removeBlock(after: i, indent: 2, in: &lines)
                return lines.joined(separator: "\n")
            }
            i += 1
        }
        lines.insert("  \(key): \(value)", at: head + 1)
        return lines.joined(separator: "\n")
    }

    /// `key: value` in a block inside a section, e.g. `bar:` → `battery:` →
    /// `percentage: true`. The block (and the section) is added if missing;
    /// comments and everything else stay.
    public static func setNested(_ text: String, section: String, block: String, key: String, value: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let head = lines.firstIndex(where: { $0.hasPrefix("\(section):") }) else {
            return text + (text.hasSuffix("\n") ? "" : "\n") + "\n\(section):\n  \(block):\n    \(key): \(value)\n"
        }
        // The section's lines: blank, indented or comments.
        var end = head + 1
        while end < lines.count, lines[end].isEmpty || lines[end].hasPrefix(" ") || lines[end].hasPrefix("#") { end += 1 }
        // Not into the comments or blank lines that introduce the next section.
        while end > head + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty || lines[end - 1].hasPrefix("#") { end -= 1 }
        let indent = { (l: String) in l.prefix { $0 == " " }.count }
        if let b = (head + 1..<end).first(where: { indent(lines[$0]) == 2 && lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("\(block):") }) {
            var i = b + 1
            while i < end, lines[i].trimmingCharacters(in: .whitespaces).isEmpty || indent(lines[i]) > 2
                    || lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("#") && indent(lines[i]) > 2 {
                if indent(lines[i]) == 4, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("\(key):") {
                    lines[i] = replacingValue(lines[i], key: key, indent: "    ", value: value)
                    return lines.joined(separator: "\n")
                }
                i += 1
            }
            lines.insert("    \(key): \(value)", at: b + 1)
            return lines.joined(separator: "\n")
        }
        lines.insert(contentsOf: ["  \(block):", "    \(key): \(value)"], at: end)
        return lines.joined(separator: "\n")
    }

    /// Bind (or with `command == nil`, unbind) a key in `keys:`. The existing
    /// line is found by meaning, so `mod-j` and `alt-j` are the same key.
    public static func setKey(_ text: String, chord: KeyChord, chordText: String, command: String?, mod: Set<Modifier>) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let head = lines.firstIndex(where: { $0.hasPrefix("keys:") }) else {
            guard let command else { return text }
            return text + (text.hasSuffix("\n") ? "" : "\n") + "keys:\n  \(chordText): \(command)\n"
        }
        var i = head + 1, lastBinding = head
        while i < lines.count, lines[i].isEmpty || lines[i].hasPrefix(" ") || lines[i].hasPrefix("#") {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !t.hasPrefix("#"), let colon = t.firstIndex(of: ":") {
                lastBinding = i
                let k = String(t[..<colon])
                if let c = try? parseChord(k, mod: mod), c == chord {
                    if let command {
                        let comment = t.range(of: "  #").map { String(t[$0.lowerBound...]) } ?? ""
                        lines[i] = "  \(chordText): \(command)" + comment
                    } else {
                        lines.remove(at: i)
                    }
                    return lines.joined(separator: "\n")
                }
            }
            i += 1
        }
        if let command { lines.insert("  \(chordText): \(command)", at: lastBinding + 1) }
        return lines.joined(separator: "\n")
    }

    // MARK: helpers

    private static func replacingValue(_ line: String, key: String, indent: String, value: String) -> String {
        let rest = line.dropFirst(indent.count + key.count + 1)
        // Keep a trailing comment (" # …"), but not a "#" inside quotes.
        var comment = ""
        var inQuote = false
        var prev: Character = " "
        for (offset, ch) in rest.enumerated() {
            if ch == "\"" { inQuote.toggle() }
            if ch == "#", !inQuote, prev == " " {
                comment = String(rest.dropFirst(offset))
                break
            }
            prev = ch
        }
        let head = "\(indent)\(key): \(value)"
        guard !comment.isEmpty else { return head }
        let pad = String(repeating: " ", count: max(1, 30 - head.count))
        return head + pad + comment
    }

    /// Drop the lines that belonged to an old value: deeper-indented lines
    /// that aren't comments (block lists and mappings).
    private static func removeBlock(after i: Int, indent: Int, in lines: inout [String]) {
        while i + 1 < lines.count {
            let l = lines[i + 1]
            let t = l.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#"), l.prefix(while: { $0 == " " }).count > indent else { break }
            lines.remove(at: i + 1)
        }
    }

    /// `[a, b, c]` with each item quoted when needed.
    public static func flowList(_ items: [String]) -> String {
        "[" + items.map(yamlScalar).joined(separator: ", ") + "]"
    }
}

extension Settings {
    /// Replace the whole `scratchpads:` list (the settings window edits them as
    /// a whole). Comments above and around the section stay; comments inside
    /// the old entries don't.
    public static func setScratchpads(_ text: String, _ pads: [Scratchpad]) -> String {
        var entries: [String] = []
        for p in pads {
            entries.append("  - name: \(yamlScalar(p.name))")
            entries.append("    app: \(yamlScalar(p.app))")
            if let t = p.title, !t.isEmpty { entries.append("    title: \(yamlScalar(t))") }
            if let r = p.run, !r.isEmpty { entries.append("    run: \(yamlScalar(r))") }
            entries.append("    size: [\(trim(p.width)), \(trim(p.height))]")
            if p.position != .center { entries.append("    position: \(p.position.rawValue)") }
        }
        var lines = text.components(separatedBy: "\n")
        guard let head = lines.firstIndex(where: { $0.hasPrefix("scratchpads:") }) else {
            let block = pads.isEmpty ? ["scratchpads: []"] : ["scratchpads:"] + entries
            let at = lines.firstIndex { $0.hasPrefix("# Keys:") } ?? lines.firstIndex { $0.hasPrefix("keys:") } ?? lines.count
            lines.insert(contentsOf: block + [""], at: at)
            return lines.joined(separator: "\n")
        }
        // Drop the old entries: indented lines up to the next top-level line,
        // keeping indented comments (e.g. commented-out examples).
        var i = head + 1
        while i < lines.count, lines[i].isEmpty || lines[i].hasPrefix(" ") {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !t.hasPrefix("#") { lines.remove(at: i) } else { i += 1 }
        }
        lines[head] = pads.isEmpty ? "scratchpads: []" : "scratchpads:"
        lines.insert(contentsOf: entries, at: head + 1)
        return lines.joined(separator: "\n")
    }

    private static func trim(_ d: Double) -> String {
        let s = String(format: "%.2f", d)
        return s.hasSuffix("0") ? String(s.dropLast()) : s
    }
}

/// Key combinations other tools already use, to warn before taking them.
public enum KeyConflicts {
    /// Bindings in an skhd config: `lalt + shift - j : …` → chord.
    public static func skhd(_ text: String) -> [KeyChord: String] {
        var out: [KeyChord: String] = [:]
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let spec = line[..<colon].trimmingCharacters(in: .whitespaces)
            let action = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let parts = spec.components(separatedBy: " - ")
            guard parts.count == 2 else { continue }
            var mods: Set<Modifier> = []
            for m in parts[0].components(separatedBy: "+").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
                switch m {
                case "alt", "lalt", "ralt": mods.insert(.alt)
                case "cmd", "lcmd", "rcmd": mods.insert(.cmd)
                case "ctrl", "lctrl", "rctrl": mods.insert(.ctrl)
                case "shift", "lshift", "rshift": mods.insert(.shift)
                case "hyper": mods.formUnion([.alt, .cmd, .ctrl, .shift])
                case "meh": mods.formUnion([.alt, .ctrl, .shift])
                default: continue
                }
            }
            let key = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            guard !mods.isEmpty, !key.isEmpty, !key.hasPrefix("0x") else { continue }
            out[KeyChord(modifiers: mods, key: key)] = action
        }
        return out
    }
}
