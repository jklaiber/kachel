import AppKit
import ApplicationServices
import KachelCore

// Private but stable API used by Amethyst, yabai and AeroSpace to get a
// window's CGWindowID from its Accessibility element.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - small AX helpers

func axCopy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func axString(_ el: AXUIElement, _ attr: String) -> String? { axCopy(el, attr) as? String }
func axBool(_ el: AXUIElement, _ attr: String) -> Bool? { axCopy(el, attr) as? Bool }

func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    guard let v = axCopy(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

func axPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
    guard let v = axCopy(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
}

func axSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
    guard let v = axCopy(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
}

func axWindowID(_ el: AXUIElement) -> WindowID? {
    var wid: CGWindowID = 0
    guard _AXUIElementGetWindow(el, &wid) == .success, wid != 0 else { return nil }
    return wid
}

/// Standard, non-minimized, non-fullscreen windows are the ones we tile.
func isManageable(_ el: AXUIElement) -> Bool {
    guard axString(el, kAXRoleAttribute) == kAXWindowRole,
          axString(el, kAXSubroleAttribute) == kAXStandardWindowSubrole else { return false }
    if axBool(el, kAXMinimizedAttribute) == true { return false }
    if axBool(el, "AXFullScreen") == true { return false }
    // A window that can't be moved can't be tiled or parked either.
    var movable: DarwinBoolean = false
    AXUIElementIsAttributeSettable(el, kAXPositionAttribute as CFString, &movable)
    if !movable.boolValue { return false }
    return true
}

// MARK: - window wrapper

/// A window as WindowManager sees it. AXWindow is the real one (through
/// Accessibility); the tests use a fake.
protocol AppWindow: AnyObject {
    var id: WindowID { get }
    var pid: pid_t { get }
    var bundleID: String? { get }
    var title: String { get }
    var frame: CGRect? { get }
    /// The green "full screen" button. Dialogs, panels and utility windows don't have one.
    var hasFullscreenButton: Bool { get }
    var isResizable: Bool { get }
    func setFrame(_ r: CGRect)
    func move(to p: CGPoint)
    func setMinimized(_ on: Bool)
    func raise()
    func focus()
    func close()
}

/// Apps that don't answer Accessibility right now (busy, hung after sleep),
/// and a queue per app for everything Kachel asks of it. A hung app then
/// only holds up its own queue, never Kachel or other apps.
final class AppResponsiveness {
    static let shared = AppResponsiveness()
    /// Longer than this, and an app counts as not answering.
    static let slowCall: TimeInterval = 0.25

    private let lock = NSLock()
    private var slow: Set<pid_t> = []
    /// An app answers again: what was asked of it meanwhile may be lost, so
    /// WindowManager puts its windows in place once more. On the main thread.
    var onAnswersAgain: ((pid_t) -> Void)?
    private var queues: [pid_t: DispatchQueue] = [:]

    func queue(for pid: pid_t) -> DispatchQueue {
        lock.lock(); defer { lock.unlock() }
        if let q = queues[pid] { return q }
        let q = DispatchQueue(label: "kachel.app.\(pid)", qos: .userInitiated)
        queues[pid] = q
        return q
    }

    func isSlow(_ pid: pid_t) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return slow.contains(pid)
    }

    func set(_ pid: pid_t, slow isSlow: Bool) {
        lock.lock()
        let changed = isSlow ? slow.insert(pid).inserted : slow.remove(pid) != nil
        lock.unlock()
        guard changed else { return }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        Log.info(isSlow ? "\(name) isn't answering: not waiting for it" : "\(name) answers again")
        if !isSlow {
            DispatchQueue.main.async { self.onAnswersAgain?(pid) }
        }
    }

    /// Time a read from an app; a slow one marks the app.
    func timed<T>(_ pid: pid_t, _ read: () -> T) -> T {
        let start = Date()
        let v = read()
        if Date().timeIntervalSince(start) > Self.slowCall { set(pid, slow: true) }
        return v
    }

    func appQuit(_ pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        slow.remove(pid)
        queues[pid] = nil
    }

    /// Wait (up to `timeout`) for what was asked of every app, e.g. before
    /// quitting, so parked windows really are back on screen.
    func flush(timeout: TimeInterval) {
        lock.lock(); let all = Array(queues.values); lock.unlock()
        let group = DispatchGroup()
        for q in all { group.enter(); q.async { group.leave() } }
        _ = group.wait(timeout: .now() + timeout)
    }
}

final class AXWindow: AppWindow {
    let element: AXUIElement
    let id: WindowID
    let pid: pid_t
    let bundleID: String?
    private let apps = AppResponsiveness.shared
    /// Last known values, used while the app doesn't answer.
    private var lastFrame: CGRect?
    private var lastTitle = ""
    private var lastFullscreenButton: Bool?
    private var lastResizable: Bool?

    init(element: AXUIElement, id: WindowID, pid: pid_t, bundleID: String?) {
        self.element = element
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        AXUIElementSetMessagingTimeout(element, 0.5)
    }

    // MARK: reads: from the app, or what we last knew while it doesn't answer

    var frame: CGRect? {
        guard !apps.isSlow(pid) else { return lastFrame }
        let f: CGRect? = apps.timed(pid) {
            guard let p = axPoint(element, kAXPositionAttribute),
                  let s = axSize(element, kAXSizeAttribute) else { return nil }
            return CGRect(origin: p, size: s)
        }
        if let f { lastFrame = f }
        return f ?? lastFrame
    }

    /// The green "full screen" button. Dialogs, panels and utility windows
    /// don't have one.
    var hasFullscreenButton: Bool {
        guard !apps.isSlow(pid) else { return lastFullscreenButton ?? true }
        let v = apps.timed(pid) { axElement(element, "AXFullScreenButton") != nil }
        lastFullscreenButton = v
        return v
    }

    var isResizable: Bool {
        guard !apps.isSlow(pid) else { return lastResizable ?? true }
        let v: Bool = apps.timed(pid) {
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
            return settable.boolValue
        }
        lastResizable = v
        return v
    }

    var title: String {
        guard !apps.isSlow(pid) else { return lastTitle }
        if let t = apps.timed(pid, { axString(element, kAXTitleAttribute) }) { lastTitle = t }
        return lastTitle
    }

    // MARK: writes: on the app's own queue, Kachel doesn't wait

    func setFrame(_ r: CGRect) {
        let r = r.integral
        lastFrame = r
        later { w in
            w.withoutEnhancedUI {
                // size → position → size: the order Amethyst uses so windows
                // moving between differently sized screens end up correct.
                w.setSize(r.size)
                w.setPosition(r.origin)
                w.setSize(r.size)
            }
        }
    }

    func move(to p: CGPoint) {
        lastFrame?.origin = p
        later { w in w.withoutEnhancedUI { w.setPosition(p) } }
    }

    func setMinimized(_ on: Bool) {
        later { w in
            AXUIElementSetAttributeValue(w.element, kAXMinimizedAttribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
        }
    }

    func raise() {
        later { w in AXUIElementPerformAction(w.element, kAXRaiseAction as CFString) }
    }

    func focus() {
        let pid = pid
        later { w in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(w.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(w.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
        }
        // Activating the app goes through the window server, not the app: no waiting.
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    func close() {
        later { w in
            if let button = axElement(w.element, kAXCloseButtonAttribute) {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
        }
    }

    /// Run on the app's queue; slow calls there mark the app as not answering.
    private func later(_ work: @escaping (AXWindow) -> Void) {
        let pid = pid
        apps.queue(for: pid).async { [self] in
            let start = Date()
            work(self)
            if Date().timeIntervalSince(start) > 1.0 { AppResponsiveness.shared.set(pid, slow: true) }
        }
    }

    private func setPosition(_ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) {
            let err = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v)
            if err != .success { Log.info("window \(id): set position failed (AXError \(err.rawValue))") }
        }
    }

    private func setSize(_ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v)
        }
    }

    /// "AXEnhancedUserInterface" (set by e.g. VoiceOver-aware apps, Chrome,
    /// Electron) makes resizes animate and lag. Turn it off while moving.
    private func withoutEnhancedUI(_ body: () -> Void) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let key = "AXEnhancedUserInterface"
        let enabled = axBool(app, key) ?? false
        if enabled { AXUIElementSetAttributeValue(app, key as CFString, kCFBooleanFalse) }
        body()
        if enabled { AXUIElementSetAttributeValue(app, key as CFString, kCFBooleanTrue) }
    }
}

// MARK: - screens

/// A display, as plain data: the tests make up their own (see FakeWindowSystem).
struct Screen {
    /// Whole display, AX coordinates (top-left origin, y down).
    let frame: CGRect
    /// Area windows may use: without menu bar, Dock and our bar (AX coordinates).
    let visible: CGRect
    /// Without menu bar and Dock, Cocoa coordinates (bottom-left origin). The bar goes here.
    let nsVisible: NSRect
    /// The display's name, as in System Settings → Displays ("DELL U2720Q").
    let name: String
    /// The laptop's own display (for workspace-screens: builtin / external).
    let builtin: Bool
    /// The one with the menu bar.
    let main: Bool
    /// The real display; nil for made-up ones in tests.
    var ns: NSScreen? = nil

    /// Screens ordered left-to-right (then top-to-bottom), like xmonad's
    /// physical screen order for mod-w / mod-e / mod-r.
    static func all(reserveBottom: CGFloat = 0) -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let h = primary.frame.height
        func toAX(_ r: NSRect) -> CGRect {
            CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
        }
        return NSScreen.screens
            .map { ns in
                var usable = ns.visibleFrame
                usable.origin.y += reserveBottom
                usable.size.height -= reserveBottom
                let id = (ns.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                return Screen(frame: toAX(ns.frame), visible: toAX(usable), nsVisible: ns.visibleFrame,
                              name: ns.localizedName, builtin: id.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
                              main: ns == primary, ns: ns)
            }
            .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
}
