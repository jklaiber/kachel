import CryptoKit
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

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// A window title as it may appear in the log: never the text itself
    /// (mail subjects, document and customer names), but a tag that's the
    /// same for the same title during this run, so a window can be followed:
    /// `title #3fa2 (23 chars)`. The tag comes from a key made at launch, so
    /// it can't be traced back to the title by trying titles.
    static func title(_ t: String) -> String {
        guard !t.isEmpty else { return "no title" }
        let digest = HMAC<SHA256>.authenticationCode(for: Data(t.utf8), using: titleKey)
        return "title #" + digest.prefix(2).map { String(format: "%02x", $0) }.joined() + " (\(t.count) chars)"
    }
    private static let titleKey = SymmetricKey(size: .bits256)

    /// A frame for the log: "600×400 at (100, 100)".
    static func frame(_ r: CGRect?) -> String {
        guard let r else { return "no frame" }
        return "\(Int(r.width))×\(Int(r.height)) at (\(Int(r.minX)), \(Int(r.minY)))"
    }

    /// Tests turn it off: they must not write into your log.
    static var enabled = true

    /// Tests: lines go here instead of the file.
    static var sink: ((String) -> Void)?

    static func info(_ message: String) {
        // Your user name is in every path: write ~ instead.
        let message = message.replacingOccurrences(of: home, with: "~")
        if let sink { sink(message); return }
        guard enabled else { return }
        NSLog("Kachel: %@", message)
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        handle?.write(line.data(using: .utf8)!)
    }
}
