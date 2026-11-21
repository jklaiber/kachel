import Foundation

/// Release versions like "0.1.17" (tags "v0.1.17"), for the update notice.
public struct ReleaseVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    /// nil for anything that isn't a plain release: "dev", "0.0.0-dev", "1.2-beta".
    public init?(_ text: String) {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("v") { t.removeFirst() }
        let p = t.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...4).contains(p.count), !p.contains(nil) else { return nil }
        parts = p.compactMap { $0 }
        if parts.allSatisfy({ $0 == 0 }) { return nil }
    }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: ReleaseVersion, b: ReleaseVersion) -> Bool { !(a < b) && !(b < a) }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}
