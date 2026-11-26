import AppKit

/// Kachel's version, from the app bundle (set by scripts/bundle.sh; releases
/// use the tag). A plain `swift build` binary has none and says "dev".
enum AppVersion {
    static var string: String {
        override ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    /// Tests: a fixed version (their own bundle is Xcode's test runner).
    static var override: String?

}
