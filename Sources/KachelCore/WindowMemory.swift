import CryptoKit
import Foundation

/// Where windows were, kept across a reboot. Window IDs start over then, so a
/// window is recognised again by its app and title instead. Titles are only
/// kept as hashes: enough to recognise one, not to read it.
public struct RememberedWindow: Codable, Equatable {
    public var bundleID: String
    /// Hash of the exact title.
    public var title: String
    /// Hash of the title without "— Edited", "•", "(2)" and the like.
    public var looseTitle: String
    public var workspace: Int
    public var floating: Bool
    /// Position in its workspace's stack (0 = master).
    public var order: Int

    public init(bundleID: String, title: String, workspace: Int, floating: Bool, order: Int) {
        self.bundleID = bundleID
        self.title = WindowMemory.hash(title)
        self.looseTitle = WindowMemory.hash(WindowMemory.loose(title))
        self.workspace = workspace
        self.floating = floating
        self.order = order
    }
}

public enum WindowMemory {
    /// A window found after the restart.
    public struct Candidate {
        public var id: WindowID
        public var bundleID: String
        public var title: String
        public init(id: WindowID, bundleID: String, title: String) {
            self.id = id
            self.bundleID = bundleID
            self.title = title
        }
    }

    static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// What's left of a title once the bits that change on their own are gone:
    /// "• notes.md — Edited (2)" → "notes.md".
    public static func loose(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespaces)
        let patterns = [
            #"^[•●*]\s*"#,                                  // unsaved marker in front
            #"\s*[—–-]\s*(Edited|Bearbeitet|Modifié)$"#,     // macOS document state
            #"\s*\(\d+\)$"#,                                 // counter: (2)
            #"\s*\[\d+\]$"#,
            #"\s*[•●*]$"#,                                  // unsaved marker at the end
        ]
        for _ in 0..<2 {
            for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        }
        return t.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Which remembered place each window takes, matched per app:
    ///  1. the same title,
    ///  2. the same title apart from the bits that change on their own,
    ///  3. the rest of an app's windows go where all of that app's remaining
    ///     windows were, if that was one workspace.
    /// Windows that match nothing aren't in the result; `memory` loses what was used.
    public static func match(_ windows: [Candidate], in memory: inout [RememberedWindow]) -> [WindowID: RememberedWindow] {
        var result: [WindowID: RememberedWindow] = [:]
        var open = windows.sorted { $0.id < $1.id }
        let byOrder = { (a: RememberedWindow, b: RememberedWindow) in (a.workspace, a.order) < (b.workspace, b.order) }

        for key in [\RememberedWindow.title, \RememberedWindow.looseTitle] {
            var still: [Candidate] = []
            for w in open {
                let h = key == \RememberedWindow.title ? hash(w.title) : hash(loose(w.title))
                // Several with the same title (two "zsh"): first come, first served, in order.
                if let i = memory.indices.filter({ memory[$0].bundleID == w.bundleID && memory[$0][keyPath: key] == h })
                    .min(by: { byOrder(memory[$0], memory[$1]) }) {
                    result[w.id] = memory.remove(at: i)
                } else {
                    still.append(w)
                }
            }
            open = still
        }
        for w in open {
            let left = memory.filter { $0.bundleID == w.bundleID }
            guard let first = left.min(by: byOrder), left.allSatisfy({ $0.workspace == first.workspace }) else { continue }
            result[w.id] = first
            memory.removeAll { $0 == first }
        }
        return result
    }
}
