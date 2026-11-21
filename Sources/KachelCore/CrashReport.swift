import Foundation

/// The parts of a macOS crash report (`~/Library/Logs/DiagnosticReports/Kachel-….ips`)
/// worth putting in a bug report: what happened and where. Only names of
/// functions and libraries, no paths, nothing about the user's windows.
public struct CrashReport: Equatable {
    public var appVersion: String
    public var osVersion: String
    public var exception: String          // "EXC_BAD_ACCESS (SIGBUS)"
    public var frames: [String]           // "0  Kachel  closure #1 in Battery.init()  Battery.swift:25"
    /// The first function of Kachel's own on the crashed thread, for the title.
    public var kachelSymbol: String?

    /// An .ips file is one line of JSON (the header) and then the report as JSON.
    public static func parse(_ text: String) -> CrashReport? {
        guard let nl = text.firstIndex(of: "\n"),
              let header = try? JSONSerialization.jsonObject(with: Data(text[..<nl].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: nl)...].utf8)) as? [String: Any]
        else { return nil }
        let app = header["app_version"] as? String ?? "?"
        let os = (header["os_version"] as? String ?? "?").replacingOccurrences(of: "macOS ", with: "")

        var exception = "unknown"
        if let e = body["exception"] as? [String: Any] {
            exception = (e["type"] as? String ?? "?") + ((e["signal"] as? String).map { " (\($0))" } ?? "")
        } else if let t = body["termination"] as? [String: Any], let ind = t["indicator"] as? String {
            exception = ind
        }

        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "?" }
        var frames: [String] = []
        var own: String?
        if let threads = body["threads"] as? [[String: Any]] {
            let i = body["faultingThread"] as? Int ?? threads.firstIndex { $0["triggered"] as? Bool == true } ?? 0
            if threads.indices.contains(i), let list = threads[i]["frames"] as? [[String: Any]] {
                for (n, f) in list.prefix(25).enumerated() {
                    let image = (f["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil } ?? "?"
                    var line = "\(n)".padding(toLength: 3, withPad: " ", startingAt: 0)
                        + image.padding(toLength: 18, withPad: " ", startingAt: 0)
                        + (f["symbol"] as? String ?? "???")
                    if let file = f["sourceFile"] as? String, let l = f["sourceLine"] as? Int, !file.hasPrefix("/<") {
                        line += "  \((file as NSString).lastPathComponent):\(l)"
                    }
                    frames.append(line)
                    if own == nil, image == "Kachel", let sym = f["symbol"] as? String { own = sym }
                }
            }
        }
        return CrashReport(appVersion: app, osVersion: os, exception: exception, frames: frames, kachelSymbol: own)
    }

    /// The text for the issue's Log field.
    public var summary: String {
        (["Kachel \(appVersion) crashed: \(exception)", "", "Crashed thread:"] + frames).joined(separator: "\n")
    }

    /// A new GitHub issue with the bug form filled in. It opens in the browser,
    /// so the user sees everything before sending it.
    public func issueURL(repo: String = "jklaiber/kachel") -> URL? {
        var c = URLComponents(string: "https://github.com/\(repo)/issues/new")!
        c.queryItems = [
            .init(name: "template", value: "bug_report.yml"),
            .init(name: "title", value: "Crash: \(exception)" + (kachelSymbol.map { " in \($0)" } ?? "")),
            .init(name: "what", value: "Kachel crashed. (What were you doing just before?)"),
            .init(name: "kachel", value: appVersion),
            .init(name: "macos", value: osVersion),
            .init(name: "log", value: summary),
        ]
        return c.url
    }
}
