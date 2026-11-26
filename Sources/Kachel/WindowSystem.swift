import AppKit
import ApplicationServices
import KachelCore

/// Everything WindowManager asks macOS about windows. AXWindowSystem is the
/// real one; the tests drive WindowManager with a fake (Tests/KachelTests).
protocol WindowSystem: AnyObject {
    /// Every window Kachel could manage, of every app. `known` is the last
    /// answer: windows whose handle didn't change are reused from it, and an
    /// app that doesn't answer keeps its windows from it.
    func windows(known: [WindowID: AppWindow]) -> [WindowID: AppWindow]
    /// Every window the window server knows, on any Space, visible or not.
    func windowServerIDs() -> Set<WindowID>
    /// What's on screen now (which windows, where, how big), as one number.
    /// Cheap: the window server answers, not the apps, so the poll can skip
    /// asking every app while it doesn't change.
    func onScreenSignature() -> Int
    /// The focused window of the frontmost app (not Kachel's own).
    func focusedWindow() -> WindowID?
    /// An app quit: forget what we kept for it.
    func appQuit(_ pid: pid_t)
    /// The displays, left to right; `reserveBottom` is kept free for the bar.
    func screens(reserveBottom: CGFloat) -> [Screen]
    /// When the Mac started: window IDs start over after a restart.
    var bootTime: Double { get }
    /// Run a shell command (`run:` of a scratchpad, `spawn`, the terminal).
    /// `done` gets its exit status and the start of what it printed to
    /// stderr, on the main thread.
    func run(_ command: String, done: @escaping (Int32, String) -> Void)
}

/// Where Kachel keeps its state between runs (a file; in tests, memory).
protocol StateStore: AnyObject {
    func load() -> Data?
    func save(_ data: Data) throws
}

final class FileStateStore: StateStore {
    let url: URL
    init(url: URL) { self.url = url }
    func load() -> Data? { try? Data(contentsOf: url) }
    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// The real one: Accessibility and the window server.
final class AXWindowSystem: WindowSystem {
    private var observers: [pid_t: AXObserver] = [:]
    /// Windows logged as left alone (they float above others on their own).
    private var leftAlone: Set<WindowID> = []
    private let apps = AppResponsiveness.shared
    /// How long one listing waits for all apps together; an app that isn't
    /// done by then keeps the windows it had and counts as not answering.
    private static let deadline: TimeInterval = 0.3
    /// Apps being checked in the background to see if they answer again.
    private var probing: Set<pid_t> = []

    /// One app's windows, read on a background thread.
    private final class Answer {
        var elements: [(AXUIElement, WindowID)] = []
        var ok = false
    }

    func windows(known: [WindowID: AppWindow]) -> [WindowID: AppWindow] {
        var result: [WindowID: AppWindow] = [:]
        let me = getpid()
        let raised = raisedWindows()
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }

        // Ask every app that answers, all at once, and wait at most `deadline`.
        let group = DispatchGroup()
        let lock = NSLock()
        var answers: [pid_t: Answer] = [:]
        for app in running where !apps.isSlow(app.processIdentifier) {
            let pid = app.processIdentifier
            let answer = Answer()
            lock.lock(); answers[pid] = answer; lock.unlock()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let read = Self.read(pid)
                lock.lock(); answer.elements = read.elements; answer.ok = read.ok; lock.unlock()
                group.leave()
            }
        }
        let inTime = group.wait(timeout: .now() + Self.deadline) == .success

        for app in running {
            let pid = app.processIdentifier
            lock.lock()
            let answer = answers[pid]
            let done = answer?.ok ?? false
            let elements = answer?.elements ?? []
            lock.unlock()
            guard done else {
                // Not answering (or busy, or still launching): keep what we
                // knew instead of forgetting its windows (and their workspaces).
                for (id, w) in known where w.pid == pid { result[id] = w }
                if answer != nil, !inTime { apps.set(pid, slow: true) }
                if apps.isSlow(pid) { probe(pid) }
                continue
            }
            ensureObserver(pid)
            for (el, id) in elements {
                if let level = raised[id] {
                    // The app keeps it above normal windows itself (Outlook's
                    // reminder, an "always on top" window), like a panel. As in
                    // Amethyst, it's left alone: not tiled, not cycled to, not
                    // parked when you switch workspaces. Its app decides where it goes.
                    if leftAlone.insert(id).inserted {
                        Log.info("leaving window \(id) (\(app.localizedName ?? "?")) alone: it floats above other windows (level \(level))")
                    }
                    continue
                }
                if let old = known[id] as? AXWindow, CFEqual(old.element, el) {
                    result[id] = old
                } else {
                    // New, or an app (Slack, Telegram) hid the window and brought it
                    // back with a new handle: the old one no longer answers.
                    if known[id] != nil {
                        Log.info("window \(id) (\(app.localizedName ?? "?")) came back with a new handle: using it")
                    }
                    result[id] = AXWindow(element: el, id: id, pid: pid, bundleID: app.bundleIdentifier)
                    if let obs = observers[pid] {
                        apps.queue(for: pid).async {
                            AXObserverAddNotification(obs, el, kAXUIElementDestroyedNotification as CFString, nil)
                            AXObserverAddNotification(obs, el, kAXWindowResizedNotification as CFString, nil)
                            AXObserverAddNotification(obs, el, kAXWindowMovedNotification as CFString, nil)
                        }
                    }
                }
            }
        }
        return result
    }

    /// An app's manageable windows. Runs on a background thread.
    private static func read(_ pid: pid_t) -> (elements: [(AXUIElement, WindowID)], ok: Bool) {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 1.0)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return ([], false) }
        var out: [(AXUIElement, WindowID)] = []
        for el in elements {
            AXUIElementSetMessagingTimeout(el, 1.0)
            guard isManageable(el), let id = axWindowID(el) else { continue }
            out.append((el, id))
        }
        return (out, true)
    }

    /// In the background: does an app that wasn't answering answer again?
    private func probe(_ pid: pid_t) {
        guard probing.insert(pid).inserted else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let start = Date()
            let ok = Self.read(pid).ok
            let fast = Date().timeIntervalSince(start) < AppResponsiveness.slowCall
            DispatchQueue.main.async {
                self?.probing.remove(pid)
                if ok, fast { self?.apps.set(pid, slow: false) }
            }
        }
    }

    func windowServerIDs() -> Set<WindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    func onScreenSignature() -> Int {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return 0 }
        let me = getpid()
        var h = Hasher()
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me else { continue }
            h.combine((w[kCGWindowNumber as String] as? NSNumber)?.uint32Value)
            h.combine(pid)
            if let b = w[kCGWindowBounds as String] as? [String: Any], let r = CGRect(dictionaryRepresentation: b as CFDictionary) {
                h.combine(r.minX); h.combine(r.minY); h.combine(r.width); h.combine(r.height)
            }
        }
        return h.finalize()
    }

    func focusedWindow() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid(), !apps.isSlow(app.processIdentifier) else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.5)
        return apps.timed(app.processIdentifier) { axElement(appEl, kAXFocusedWindowAttribute).flatMap(axWindowID) }
    }

    func screens(reserveBottom: CGFloat) -> [Screen] { Screen.all(reserveBottom: reserveBottom) }

    func run(_ command: String, done: @escaping (Int32, String) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.terminationHandler = { proc in
            let text = String(decoding: err.fileHandleForReading.availableData.prefix(300), as: UTF8.self)
            DispatchQueue.main.async { done(proc.terminationStatus, text) }
        }
        do { try p.run() } catch { done(127, "\(error)") }
    }

    let bootTime: Double = {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
    }()

    func appQuit(_ pid: pid_t) {
        apps.appQuit(pid)
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    /// Windows that sit above the normal window level, by ID, with their level.
    private func raisedWindows() -> [WindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        var out: [WindowID: Int] = [:]
        for w in list {
            guard let level = w[kCGWindowLayer as String] as? Int, level > 0,
                  let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            out[id] = level
        }
        return out
    }

    private func ensureObserver(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, axCallback, &obs) == .success, let obs else { return }
        observers[pid] = obs
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        // Subscribing asks the app: on its own queue. Apps that are still
        // launching refuse; then drop the observer so the next listing tries again.
        apps.queue(for: pid).async { [weak self] in
            let appEl = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appEl, 1.0)
            guard AXObserverAddNotification(obs, appEl, kAXWindowCreatedNotification as CFString, nil) == .success else {
                DispatchQueue.main.async {
                    guard let self, self.observers[pid] === obs else { return }
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
                    self.observers[pid] = nil
                }
                return
            }
            for n in [kAXFocusedWindowChangedNotification,
                      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                      kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
                AXObserverAddNotification(obs, appEl, n as CFString, nil)
            }
        }
    }
}
