import AppKit
import KachelCore

/// After a crash, the next Kachel offers to report it: a GitHub issue with the
/// crash details filled in, opened in the browser so you see it all before
/// sending. Nothing is sent by Kachel itself.
enum CrashPrompt {
    private static let seenKey = "crashReportsSeenUntil"
    private static var alert: NSAlert?
    private static var target: Target?

    /// At launch, and once more a bit later: macOS writes the report a few
    /// seconds after the crash, which can be after the watchdog restarted us.
    static func scheduleChecks() {
        check()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { check() }
    }

    static func check() {
        let d = UserDefaults.standard
        guard let seen = d.object(forKey: seenKey) as? Date else {
            // First start with this: older crashes aren't news.
            d.set(Date(), forKey: seenKey)
            return
        }
        guard alert == nil, let (url, date) = newestReport(after: seen) else { return }
        d.set(date, forKey: seenKey)
        guard let text = try? String(contentsOf: url, encoding: .utf8), let report = CrashReport.parse(text) else {
            Log.info("crash report \(url.lastPathComponent) could not be read")
            return
        }
        Log.info("found crash report \(url.lastPathComponent): \(report.exception)")
        show(report, file: url, restarted: restartedRecently())
    }

    private static func newestReport(after seen: Date) -> (URL, Date)? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("Kachel") && $0.pathExtension == "ips" }
            .compactMap { u in (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (u, $0) } }
            .filter { $0.1 > seen }
            .max { $0.1 < $1.1 }
    }

    private static func restartedRecently() -> Bool {
        guard let data = try? Data(contentsOf: Watchdog.crashURL),
              let c = try? JSONDecoder().decode(Watchdog.Crash.self, from: data) else { return false }
        return Date().timeIntervalSince(c.at) < 120
    }

    /// The alert, laid out and ready to show (its buttons get their actions in `show`).
    static func makeAlert(_ report: CrashReport, restarted: Bool) -> NSAlert {
        let a = NSAlert()
        a.messageText = "Kachel quit unexpectedly"
        a.informativeText = (restarted ? "It started again by itself, and windows that were out of sight are back on screen.\n\n" : "")
            + "Reporting it helps fix it: Kachel opens a new GitHub issue with the crash details filled in "
            + "(\(report.exception)), for you to look over and send. No window titles or files are included."
        a.addButton(withTitle: "Report on GitHub…")
        a.addButton(withTitle: "Show Crash Report")
        a.addButton(withTitle: "Not Now")
        // runModal() would lay it out; shown without it, we have to.
        a.layout()
        return a
    }

    /// Not modal: Kachel keeps managing windows while it's open.
    private static func show(_ report: CrashReport, file: URL, restarted: Bool) {
        let a = makeAlert(report, restarted: restarted)
        let t = Target(report: report, file: file)
        for (i, b) in a.buttons.enumerated() {
            b.tag = i
            b.target = t
            b.action = #selector(Target.clicked(_:))
        }
        alert = a
        target = t
        // Kachel has no Dock icon: activating alone leaves it behind other apps,
        // and an alert panel would vanish whenever another app is in front.
        a.window.hidesOnDeactivate = false
        a.window.center()
        a.window.orderFrontRegardless()
        a.window.makeKey()
        NSApp.activate()
    }

    fileprivate static func close() {
        alert?.window.orderOut(nil)
        alert = nil
        target = nil
    }

    private final class Target: NSObject {
        let report: CrashReport
        let file: URL
        init(report: CrashReport, file: URL) { self.report = report; self.file = file }

        @objc func clicked(_ sender: NSButton) {
            switch sender.tag {
            case 0:
                if let url = report.issueURL() { NSWorkspace.shared.open(url) }
                CrashPrompt.close()
            case 1:
                NSWorkspace.shared.activateFileViewerSelecting([file])   // stays open: report afterwards
            default:
                CrashPrompt.close()
            }
        }
    }
}
