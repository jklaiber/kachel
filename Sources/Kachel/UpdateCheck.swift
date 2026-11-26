import AppKit
import KachelCore

/// Once an hour (and after the Mac wakes), asks GitHub for the latest
/// release. Only that one public request, with no details about you or your
/// Mac. It sends back GitHub's tag for the last answer, so "nothing new" is a
/// short, empty answer. (GitHub allows 60 requests an hour per network
/// address without an account; one an hour per Mac leaves plenty of room.)
/// When there's a newer version, the menus and Settings → About say so;
/// nothing pops up by itself.
final class UpdateCheck: ObservableObject {
    static let shared = UpdateCheck()

    struct Release: Equatable { var version: ReleaseVersion; var notes: URL }
    enum Outcome: Equatable { case upToDate, available(Release), failed(String) }

    @Published private(set) var available: Release?
    /// For Settings → About.
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false
    @Published private(set) var failed = false
    var onChange: (() -> Void)?

    static let interval: TimeInterval = 3600
    static let upgradeCommand = "brew update && brew upgrade --cask kachel"
    static let api = URL(string: "https://api.github.com/repos/jklaiber/kachel/releases/latest")!

    /// The request itself; tests answer it themselves.
    typealias Fetch = (URLRequest, @escaping (Data?, HTTPURLResponse?, Error?) -> Void) -> Void
    var fetch: Fetch = { req, done in
        URLSession.shared.dataTask(with: req) { data, response, error in done(data, response as? HTTPURLResponse, error) }.resume()
    }
    /// Tests: a version instead of the app's.
    var version: () -> String = { AppVersion.string }

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// GitHub's tag for its last answer, and that answer.
    private var etag: String?
    private var lastLatest: (version: ReleaseVersion, notes: URL)?

    /// Follows `check-for-updates`. Dev builds have no version to compare.
    func apply(enabled: Bool) {
        guard enabled, ReleaseVersion(version()) != nil else {
            timer?.invalidate()
            timer = nil
            wakeObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
            wakeObserver = nil
            if available != nil { available = nil; onChange?() }
            return
        }
        guard timer == nil else { return }
        // Not right at login, when everything else starts too.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in self?.check() }
        // The timer stands still while the Mac sleeps: look once it's awake
        // (and online again), if the last look is an hour old.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                guard let self, Date().timeIntervalSince(self.lastChecked ?? .distantPast) >= Self.interval else { return }
                self.check()
            }
        }
    }

    /// The automatic check: only while it's turned on.
    func check() {
        guard timer != nil else { return }
        checkNow()
    }

    /// The same one request, now (Check Now, Check for Updates…). `done` gets
    /// what came of it; nil if there's nothing to check (a dev build, or a
    /// check already running).
    func checkNow(done: ((Outcome?) -> Void)? = nil) {
        guard !checking, let mine = ReleaseVersion(version()) else { done?(nil); return }
        checking = true
        var req = URLRequest(url: Self.api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Kachel", forHTTPHeaderField: "User-Agent")
        if let etag, lastLatest != nil { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        fetch(req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let outcome = self.handle(data: data, response: response, error: error, mine: mine)
                done?(outcome)
            }
        }
    }

    private func handle(data: Data?, response: HTTPURLResponse?, error: Error?, mine: ReleaseVersion) -> Outcome {
        checking = false
        let latest: (version: ReleaseVersion, notes: URL)
        if response?.statusCode == 304, let last = lastLatest {
            latest = last                                  // nothing new since the last answer
        } else if response?.statusCode == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String, let v = ReleaseVersion(tag) {
            let notes = (json["html_url"] as? String).flatMap(URL.init(string:))
                ?? URL(string: "https://github.com/jklaiber/kachel/releases/latest")!
            latest = (v, notes)
            lastLatest = latest
            etag = response?.value(forHTTPHeaderField: "ETag")
        } else {
            let why = error?.localizedDescription ?? response.map { "GitHub answered \($0.statusCode)" } ?? "no answer"
            Log.info("update check failed: \(why)")
            failed = true
            return .failed(why)
        }
        failed = false
        lastChecked = Date()
        let new = latest.version > mine ? Release(version: latest.version, notes: latest.notes) : nil
        if new != available {
            Log.info(new.map { "update available: \($0.version) (running \(mine))" } ?? "Kachel is up to date (\(mine))")
            available = new
            onChange?()
        }
        return new.map { .available($0) } ?? .upToDate
    }

    /// Check for Updates… in the menus: always answers, also when there's nothing new.
    func checkFromMenu() {
        checkNow { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .available?:
                self.showDetails()
            case .upToDate?:
                Self.alert("Kachel \(self.version()) is up to date", "It's the latest release.")
            case .failed(let why)?:
                Self.alert("Couldn't check for updates", "GitHub couldn't be reached (\(why)). Try again later.")
            case nil:
                if ReleaseVersion(self.version()) == nil {
                    Self.alert("This is a development build", "It's built from the source code: there's no release to compare it with.")
                }
            }
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.comeForward()
        a.window.orderFrontRegardless()
        a.runModal()
    }

    /// What the menu item opens.
    func showDetails() {
        guard let r = available else { return }
        let a = NSAlert()
        a.messageText = "Kachel \(r.version) is available"
        a.informativeText = "You have \(version()). To upgrade, run this in Terminal:\n\n"
            + "\(Self.upgradeCommand)\n\n"
            + "Your config and workspaces stay as they are."
        a.addButton(withTitle: "Copy Command")
        a.addButton(withTitle: "Release Notes")
        a.addButton(withTitle: "Later")
        NSApp.comeForward()
        a.window.orderFrontRegardless()
        switch a.runModal() {
        case .alertFirstButtonReturn:
            Self.copyCommand()
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(r.notes)
        default:
            break
        }
    }

    static func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(upgradeCommand, forType: .string)
    }
}
