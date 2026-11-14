import AppKit
import XMonadCore

/// Loads ~/.config/xmonadmac/config.yaml, writes the commented default on
/// first launch, and notices when the file is saved.
enum Config {
    /// The settings in effect. Starts with the built-in defaults.
    static private(set) var current = Settings.defaults
    /// Last error from loading the file, shown in the bar.
    static private(set) var error: String?

    static let url: URL = {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("xmonadmac/config.yaml")
    }()

    private static var lastModified: Date?

    /// Returns true if the file was (re)read, successfully or not.
    @discardableResult
    static func load(force: Bool = false) -> Bool {
        let fm = FileManager.default
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
            Log.info("loaded \(url.path): \(current.keys.count) keys, mod=\(KeyChord(modifiers: current.mod, key: "").description)")
        } catch {
            self.error = "\(error)"
            Log.info("config error (keeping previous settings): \(error)")
        }
        return true
    }

    static func openInEditor() {
        NSWorkspace.shared.open(url)
    }
}
