import AppKit
import ApplicationServices
import XMonadCore

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
    return true
}

// MARK: - window wrapper

final class AXWindow {
    let element: AXUIElement
    let id: WindowID
    let pid: pid_t
    let bundleID: String?

    init(element: AXUIElement, id: WindowID, pid: pid_t, bundleID: String?) {
        self.element = element
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
    }

    var frame: CGRect? {
        guard let p = axPoint(element, kAXPositionAttribute),
              let s = axSize(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        return settable.boolValue
    }

    func setFrame(_ r: CGRect) {
        let r = r.integral
        withoutEnhancedUI {
            // size → position → size: the order Amethyst uses so windows
            // moving between differently sized screens end up correct.
            setSize(r.size)
            setPosition(r.origin)
            setSize(r.size)
        }
        if let f = frame, abs(f.minX - r.minX) > 2 || abs(f.minY - r.minY) > 2 {
            Log.info("window \(id) (\(bundleID ?? "?")) asked for \(r), is at \(f)")
        }
    }

    func move(to p: CGPoint) {
        withoutEnhancedUI { setPosition(p) }
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func focus() {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        raise()
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    var title: String { axString(element, kAXTitleAttribute) ?? "" }

    func close() {
        if let button = axElement(element, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
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
        let key = "AXEnhancedUserInterface"
        let enabled = axBool(app, key) ?? false
        if enabled { AXUIElementSetAttributeValue(app, key as CFString, kCFBooleanFalse) }
        body()
        if enabled { AXUIElementSetAttributeValue(app, key as CFString, kCFBooleanTrue) }
    }
}

// MARK: - screens

struct Screen {
    /// Whole display, AX coordinates (top-left origin, y down).
    let frame: CGRect
    /// Area windows may use: without menu bar, Dock and our bar (AX coordinates).
    let visible: CGRect
    /// Without menu bar and Dock, Cocoa coordinates (bottom-left origin). The bar goes here.
    let nsVisible: NSRect
    let ns: NSScreen

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
                return Screen(frame: toAX(ns.frame), visible: toAX(usable), nsVisible: ns.visibleFrame, ns: ns)
            }
            .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
}
