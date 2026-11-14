import Foundation

/// The window switcher's brain: which windows match what you typed, and in
/// which order. No AppKit, so it's unit-tested.
public enum WindowSearch {
    public struct Candidate: Equatable {
        public var id: WindowID
        public var app: String
        public var title: String
        public var workspace: Int        // index
        public var recency: Int          // 0 = used most recently
        public var isFocused: Bool       // the window you're in right now

        public init(id: WindowID, app: String, title: String, workspace: Int, recency: Int, isFocused: Bool) {
            self.id = id; self.app = app; self.title = title
            self.workspace = workspace; self.recency = recency; self.isFocused = isFocused
        }
    }

    /// Empty query: everything, by workspace then recency (the overview).
    /// Otherwise: only matches, best first; recency breaks ties, and the
    /// window you're already in goes last.
    public static func results(_ query: String, in candidates: [Candidate]) -> [Candidate] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens.isEmpty {
            return candidates.sorted { ($0.workspace, $0.recency) < ($1.workspace, $1.recency) }
        }
        let scored: [(Candidate, Int)] = candidates.compactMap { c in
            var total = 0
            for t in tokens {
                // App names count a little more than titles ("chr" → Chrome first).
                let a = score(t, in: c.app).map { $0 + 5 }
                let b = score(t, in: c.title)
                guard let s = [a, b].compactMap({ $0 }).max() else { return nil }
                total += s
            }
            return (c, total)
        }
        return scored.sorted { l, r in
            if l.0.isFocused != r.0.isFocused { return !l.0.isFocused }
            if l.1 != r.1 { return l.1 > r.1 }
            return l.0.recency < r.0.recency
        }.map(\.0)
    }

    /// Subsequence match with bonuses for consecutive letters and word starts.
    /// nil when the letters don't all appear in order.
    public static func score(_ query: String, in text: String) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        let orig = Array(text)
        let t = orig.map { Character($0.lowercased()) }

        // Try every start position of the first letter; keep the best.
        var best: Int?
        for start in t.indices where t[start] == q[0] {
            var qi = 0, score = 0, last = -2
            var i = start
            while i < t.count, qi < q.count {
                if t[i] == q[qi] {
                    var s = 1
                    if i == last + 1 { s += 5 }
                    if i == 0 || !(t[i - 1].isLetter || t[i - 1].isNumber) { s += 8 }
                    else if orig[i].isUppercase, orig[i - 1].isLowercase { s += 6 }
                    score += s
                    last = i
                    qi += 1
                }
                i += 1
            }
            guard qi == q.count else { break }      // later starts can't do better on coverage
            score -= start / 4                       // earlier matches read better
            best = max(best ?? .min, score)
        }
        return best
    }
}
