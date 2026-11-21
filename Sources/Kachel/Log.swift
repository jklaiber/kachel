import Foundation

/// Appends to ~/Library/Logs/Kachel.log (and the unified log), so there is
/// always something to look at when "nothing works".
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Kachel.log")
    private static let handle: FileHandle? = {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Tests turn it off: they must not write into your log.
    static var enabled = true

    static func info(_ message: String) {
        guard enabled else { return }
        NSLog("Kachel: %@", message)
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        handle?.write(line.data(using: .utf8)!)
    }
}
