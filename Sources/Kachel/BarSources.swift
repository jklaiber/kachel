import AppKit
import ApplicationServices
import KachelCore

/// The red numbers on Dock icons (unread mail, messages), read from the Dock
/// through Accessibility: no scripts, works for any app that shows one.
enum DockBadges {
    struct Badge: Equatable {
        var bundleID: String?
        var name: String
        var label: String
        var appURL: URL?
    }

    /// Every Dock item with a badge. Runs off the main thread (the Dock may be slow).
    static func read() -> [Badge] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let kids = axCopy(app, kAXChildrenAttribute) as? [AXUIElement],
              let list = kids.first(where: { axString($0, kAXRoleAttribute) == kAXListRole }),
              let items = axCopy(list, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        var out: [Badge] = []
        for item in items {
            guard let label = axString(item, "AXStatusLabel"), !label.isEmpty else { continue }
            let url = axCopy(item, kAXURLAttribute).flatMap { $0 as? URL }
            out.append(Badge(bundleID: url.flatMap { Bundle(url: $0)?.bundleIdentifier },
                             name: axString(item, kAXTitleAttribute) ?? "?", label: label, appURL: url))
        }
        return out
    }

    /// Only the apps asked for (bundle ID or name), in that order; all when none are.
    static func pick(_ badges: [Badge], apps: [String]) -> [Badge] {
        guard !apps.isEmpty else { return badges }
        return apps.compactMap { want in
            badges.first { $0.bundleID?.caseInsensitiveCompare(want) == .orderedSame || $0.name.caseInsensitiveCompare(want) == .orderedSame }
        }
    }
}

/// Your own bar widgets: a shell command, its first line shown.
final class CustomWidgetRunner {
    /// What each widget shows now (nil before its first run, or when it printed nothing).
    private(set) var text: [String: String] = [:]
    var onChange: (() -> Void)?
    private var timers: [String: Timer] = [:]
    private var running: Set<String> = []
    private var widgets: [String: CustomWidget] = [:]

    static let maxLength = 40
    static let timeout: TimeInterval = 2

    /// Start (or restart) the widgets that are in the bar.
    func apply(_ widgets: [String: CustomWidget], shown: Set<String>) {
        let active = widgets.filter { shown.contains($0.key) }
        guard active != self.widgets else { return }
        timers.values.forEach { $0.invalidate() }
        timers = [:]
        text = text.filter { active[$0.key] != nil }
        self.widgets = active
        for (name, w) in active {
            run(name)
            timers[name] = Timer.scheduledTimer(withTimeInterval: w.interval, repeats: true) { [weak self] _ in self?.run(name) }
        }
    }

    private func run(_ name: String) {
        guard let w = widgets[name], running.insert(name).inserted else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let line = Self.firstLine(of: w.run)
            DispatchQueue.main.async {
                guard let self else { return }
                self.running.remove(name)
                guard self.widgets[name] != nil, self.text[name] != line else { return }
                self.text[name] = line
                self.onChange?()
            }
        }
    }

    /// The command's first line, shortened; nil if it printed nothing or took too long.
    static func firstLine(of command: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning {
            p.terminate()
            Log.info("bar widget command took longer than \(Int(timeout)) s, stopped: \(command)")
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let first = String(decoding: data.prefix(4096), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !first.isEmpty else { return nil }
        return first.count > maxLength ? String(first.prefix(maxLength - 1)) + "…" : first
    }

    /// Screenshots and tests: a made-up output.
    func setDemo(_ name: String, _ line: String?) { text[name] = line }

    /// Run a widget's click command.
    static func click(_ command: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        try? p.run()
    }
}
