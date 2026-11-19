import AppKit
import ApplicationServices

/// Notices an auto-hidden Dock along the bottom sliding up, and on which
/// screen, so the bar can step aside while it's there.
///
/// macOS has no notification for this. Nothing runs while the pointer is
/// elsewhere: only when it touches the bottom edge of a screen do we start
/// looking at the Dock (its frame, through Accessibility), until it's gone again.
final class DockWatch {
    /// The screen frame (Cocoa coordinates) the Dock is shown on; nil = hidden.
    var onChange: ((CGRect?) -> Void)?
    private(set) var shownOn: CGRect?

    private var monitors: [Any] = []
    private var timer: Timer?
    private var dockApp: AXUIElement?
    private var dockPID: pid_t = 0
    /// Without a readable Dock frame: when the pointer reached the edge.
    private var touchedAt: Date?

    deinit { stop() }

    func start() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(m)
        }
        // Over our own bar (it sits right at the edge) the events are ours.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in handler(e); return e }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        timer?.invalidate()
        timer = nil
        set(nil)
    }

    /// Only an auto-hiding Dock at the bottom covers the bar.
    static func hidesAtBottom() -> Bool {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let side = CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String ?? "bottom"
        let autohide = CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool ?? false
        return side == "bottom" && autohide
    }

    private func pointerMoved() {
        guard timer == nil else { return }
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(p) || abs(p.y - $0.frame.minY) < 1 && p.x >= $0.frame.minX && p.x < $0.frame.maxX }),
              p.y <= screen.frame.minY + 1, Self.hidesAtBottom() else { return }
        touchedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private func poll() {
        let p = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { $0.frame.insetBy(dx: 0, dy: -1).contains(p) }
        let now: CGRect?
        if let dock = dockFrame() {
            // Up: the Dock reaches into some screen by more than a sliver.
            now = NSScreen.screens.first { $0.frame.intersection(dock).height > 8 }?.frame
        } else {
            // Can't read it: like the Dock itself, up after its delay while the
            // pointer stays within its height of the bottom.
            let zone = Self.tileSize() + 24
            if let s = pointerScreen, p.y < s.frame.minY + zone, let t = touchedAt {
                now = Date().timeIntervalSince(t) >= Self.delay() ? s.frame : shownOn
            } else {
                now = nil
            }
        }
        set(now)
        // Down again and the pointer has left the edge: stop looking.
        if now == nil, let s = pointerScreen, p.y > s.frame.minY + 2 {
            timer?.invalidate()
            timer = nil
            touchedAt = nil
        } else if now == nil, pointerScreen == nil {
            timer?.invalidate()
            timer = nil
        }
    }

    private func set(_ r: CGRect?) {
        guard r != shownOn else { return }
        shownOn = r
        Log.info(r.map { "dock slid up on the screen at \($0), frame \(dockFrame().map { "\($0)" } ?? "unreadable")" } ?? "dock hidden again")
        onChange?(r)
    }

    /// The Dock's icon row, in Cocoa coordinates; nil when we can't read it.
    private func dockFrame() -> CGRect? {
        if dockApp == nil || NSRunningApplication(processIdentifier: dockPID) == nil {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
            dockPID = app.processIdentifier
            dockApp = AXUIElementCreateApplication(dockPID)
        }
        guard let dockApp,
              let kids = axCopy(dockApp, kAXChildrenAttribute) as? [AXUIElement],
              let list = kids.first(where: { axString($0, kAXRoleAttribute) == kAXListRole }),
              let pos = axPoint(list, kAXPositionAttribute),
              let size = axSize(list, kAXSizeAttribute), size.height > 0 else { return nil }
        // AX counts from the top of the main screen, Cocoa from the bottom.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: pos.x, y: top - pos.y - size.height, width: size.width, height: size.height)
    }

    private static func tileSize() -> CGFloat {
        CGFloat(CFPreferencesCopyAppValue("tilesize" as CFString, "com.apple.dock" as CFString) as? Double ?? 48)
    }

    private static func delay() -> Double {
        CFPreferencesCopyAppValue("autohide-delay" as CFString, "com.apple.dock" as CFString) as? Double ?? 0.5
    }
}
