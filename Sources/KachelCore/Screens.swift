/// What we know about a display, for `workspace-screens:`.
public struct ScreenInfo: Equatable {
    public var name: String
    public var builtin: Bool
    public var main: Bool
    public init(name: String, builtin: Bool, main: Bool) { self.name = name; self.builtin = builtin; self.main = main }
}

public enum ScreenMatcher {
    /// Which screen (index, left to right) a pattern means:
    /// main (has the menu bar), external / secondary (first non-built-in),
    /// builtin / laptop, 1…n (left to right), or part of the display's name.
    /// nil when that screen isn't connected.
    public static func index(for pattern: String, in screens: [ScreenInfo]) -> Int? {
        let p = pattern.lowercased().trimmingCharacters(in: .whitespaces)
        switch p {
        case "main": return screens.firstIndex(where: \.main)
        case "external", "secondary": return screens.firstIndex { !$0.builtin }
        case "builtin", "built-in", "laptop": return screens.firstIndex(where: \.builtin)
        default:
            if let n = Int(p) { return n >= 1 && n <= screens.count ? n - 1 : nil }
            return screens.firstIndex { $0.name.lowercased().contains(p) }
        }
    }
}
