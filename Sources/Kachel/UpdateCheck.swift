import AppKit
import KachelCore

/// Once a day, asks GitHub for the latest release. Only that one public
/// request, with no details about you or your Mac. When there's a newer
/// version, the menus say so; nothing pops up by itself.
final class UpdateCheck: ObservableObject {
    static let shared = UpdateCheck()

    struct Release { var version: ReleaseVersion; var notes: URL }
    @Published private(set) var available: Release?
    /// For Settings → About.
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false
    @Published private(set) var failed = false
    var onChange: (() -> Void)?
    private var timer: Timer?

    static let upgradeCommand = "brew update && brew upgrade --cask kachel"
    private static let api = URL(string: "https://api.github.com/repos/jklaiber/kachel/releases/latest")!

    /// Follows `check-for-updates`. Dev builds have no version to compare.
    func apply(enabled: Bool) {
        guard enabled, ReleaseVersion(AppVersion.string) != nil else {
            timer?.invalidate()
            timer = nil
            if available != nil { available = nil; onChange?() }
            return
        }
        guard timer == nil else { return }
        // Not right at login, when everything else starts too.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        guard timer != nil else { return }
        checkNow()
    }

    /// The same one request, now (Settings → About → Check Now).
    func checkNow() {
        guard !checking, let mine = ReleaseVersion(AppVersion.string) else { return }
        checking = true
        var req = URLRequest(url: Self.api, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Kachel", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String, let latest = ReleaseVersion(tag) else {
                Log.info("update check failed: \(error.map { "\($0.localizedDescription)" } ?? "unexpected answer")")
                DispatchQueue.main.async { self?.checking = false; self?.failed = true }
                return
            }
            let notes = (json["html_url"] as? String).flatMap(URL.init(string:))
                ?? URL(string: "https://github.com/jklaiber/kachel/releases/latest")!
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                self.failed = false
                self.lastChecked = Date()
                let new = latest > mine ? Release(version: latest, notes: notes) : nil
                if new?.version != self.available?.version {
                    Log.info(new.map { "update available: \($0.version) (running \(mine))" } ?? "Kachel is up to date (\(mine))")
                    self.available = new
                    self.onChange?()
                }
            }
        }.resume()
    }

    /// What the menu item opens.
    func showDetails() {
        guard let r = available else { return }
        let a = NSAlert()
        a.messageText = "Kachel \(r.version) is available"
        a.informativeText = "You have \(AppVersion.string). To upgrade, run this in Terminal:\n\n"
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
