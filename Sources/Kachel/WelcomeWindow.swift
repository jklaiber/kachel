import AppKit
import ApplicationServices
import SwiftUI

/// First launch (and the menu's "Welcome and Setup Check…"): Accessibility,
/// then the macOS settings that matter for a tiling window manager, each with
/// a way to fix it.
final class WelcomeWindow {
    private var window: NSWindow?
    private let model = SetupModel()

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: WelcomeView(model: model, close: { [weak self] in self?.window?.close() }))
            let w = NSWindow(contentViewController: host)
            w.title = "Welcome to Kachel"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            window = w
        }
        model.refresh()
        model.startWatching()
        window?.center()
        NSApp.comeForward()
        window?.makeKeyAndOrderFront(nil)
    }

    var isOpen: Bool { window?.isVisible == true }

    /// Back in front, e.g. after you granted Accessibility in System Settings.
    func bringToFront() {
        guard let window, window.isVisible else { return }
        model.refresh()
        // macOS may not let a background app activate itself; the window comes
        // to the front either way.
        window.orderFrontRegardless()
        NSApp.comeForward()
        window.makeKeyAndOrderFront(nil)
    }

    /// Show once, on the very first launch.
    func showOnFirstLaunch() {
        let key = "welcomeShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        show()
    }
}

// MARK: - checks

struct SetupCheck: Identifiable {
    enum Status { case ok, warn, info }
    struct Action { var label: String; var run: () -> Void }
    var id: String
    var status: Status
    var title: String
    var detail: String
    var actions: [Action] = []
}

final class SetupModel: ObservableObject {
    @Published var checks: [SetupCheck] = []
    @Published var startAtLogin = Config.current.startAtLogin
    private var timer: Timer?

    func startWatching() {
        timer?.invalidate()
        // Re-check while the window is open, so fixes show up as they happen.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        var c: [SetupCheck] = []
        let trusted = AXIsProcessTrusted()
        c.append(SetupCheck(
            id: "ax", status: trusted ? .ok : .warn, title: "Accessibility",
            detail: trusted ? "Kachel can move and resize windows."
                : "Kachel needs this to move and resize windows. Switch Kachel on in the list, then come back.",
            actions: trusted ? [] : [.init(label: "Open Settings") { Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }]))

        let others = Self.otherWindowManagers()
        c.append(SetupCheck(
            id: "others", status: others.isEmpty ? .ok : .warn, title: "Other window managers",
            detail: others.isEmpty ? "None running." : "\(others.map(\.name).joined(separator: ", ")) is running. Two tilers fight over the same windows.",
            actions: others.isEmpty ? [] : [.init(label: "Quit \(others.map(\.name).joined(separator: ", "))") {
                others.forEach { $0.app?.terminate() }
            }]))

        if let spaces = SpacesInfo.spacesPerDisplay() {
            let extra = spaces.filter { $0 > 1 }.count
            c.append(SetupCheck(
                id: "spaces", status: extra == 0 ? .ok : .warn, title: "One Space per display",
                detail: extra == 0 ? "Each display has a single Space, as Kachel expects."
                    : "Kachel's workspaces replace Spaces. Remove the extra Spaces in Mission Control (hover a Space, click ✕).",
                actions: extra == 0 ? [] : [.init(label: "Open Mission Control") { Self.run("/usr/bin/open", ["-a", "Mission Control"]) }]))
        }

        let mru = Self.bool("com.apple.dock", "mru-spaces") ?? true
        c.append(SetupCheck(
            id: "mru", status: mru ? .warn : .ok, title: "Automatically rearrange Spaces",
            detail: mru ? "macOS reorders Spaces by recent use. Turn it off so displays stay predictable."
                : "Off.",
            actions: mru ? [.init(label: "Turn Off") {
                Self.run("/usr/bin/defaults", ["write", "com.apple.dock", "mru-spaces", "-bool", "false"])
                Self.run("/usr/bin/killall", ["Dock"])
            }] : []))

        let grouped = Self.bool("com.apple.dock", "expose-group-apps") ?? false
        c.append(SetupCheck(
            id: "group", status: grouped ? .ok : .info, title: "Mission Control: group windows by app",
            detail: grouped ? "On: windows parked in a corner don't show up tiny in Mission Control."
                : "Recommended: Kachel parks hidden windows in a corner, which Mission Control shows very small.",
            actions: grouped ? [] : [.init(label: "Turn On") {
                Self.run("/usr/bin/defaults", ["write", "com.apple.dock", "expose-group-apps", "-bool", "true"])
                Self.run("/usr/bin/killall", ["Dock"])
            }]))

        // A Dock along the bottom takes the room Kachel's bar wants, and hides
        // the one-pixel slivers of parked windows when it hides itself.
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let dockSide = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String ?? "bottom"
        if dockSide == "bottom", Config.current.bar.enabled {
            let autohide = Self.bool("com.apple.dock", "autohide") ?? false
            c.append(SetupCheck(
                id: "dock", status: autohide ? .ok : .info, title: "Hide the Dock automatically",
                detail: autohide ? "On: the bar has the bottom of the screen to itself, and the Dock appears when you move the pointer there."
                    : "Recommended: the Dock and Kachel's bar both sit at the bottom. Hidden, the Dock appears when you move the pointer down, and the bar sits right at the edge.",
                actions: autohide ? [] : [.init(label: "Hide Automatically") {
                    Self.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
                    Self.run("/usr/bin/killall", ["Dock"])
                    // The room the Dock took is free now: place the bar and windows again.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { WindowManager.shared.reload() }
                }]))
        }

        let tiling = (Self.bool("com.apple.WindowManager", "EnableTilingByEdgeDrag") ?? true)
            || (Self.bool("com.apple.WindowManager", "EnableTopTilingByEdgeDrag") ?? true)
        c.append(SetupCheck(
            id: "tiling", status: tiling ? .warn : .ok, title: "macOS window tiling",
            detail: tiling ? "Dragging a window to a screen edge makes macOS tile it, which Kachel then undoes. Turn off the \"Drag windows to…\" options."
                : "Off.",
            actions: tiling ? [.init(label: "Open Desktop & Dock") { Self.open("x-apple.systempreferences:com.apple.Desktop-Settings.extension") }] : []))

        let stage = Self.bool("com.apple.WindowManager", "GloballyEnabled") ?? false
        c.append(SetupCheck(
            id: "stage", status: stage ? .warn : .ok, title: "Stage Manager",
            detail: stage ? "Stage Manager moves windows on its own. Turn it off while using Kachel." : "Off.",
            actions: stage ? [.init(label: "Open Desktop & Dock") { Self.open("x-apple.systempreferences:com.apple.Desktop-Settings.extension") }] : []))

        let g = Config.current.gestures
        if g.enabled {
            let key = g.fingers == 3 ? "TrackpadThreeFingerHorizSwipeGesture" : "TrackpadFourFingerHorizSwipeGesture"
            let macSwipe = (Self.int("com.apple.AppleMultitouchTrackpad", key) ?? 2) != 0
            c.append(SetupCheck(
                id: "swipe", status: macSwipe ? .warn : .ok, title: "Trackpad: \(g.fingers)-finger swipes",
                detail: macSwipe ? "macOS uses this swipe for Spaces too. In More Gestures, set \"Swipe between full-screen applications\" to Off."
                    : "Free for Kachel's workspace swipes.",
                actions: macSwipe ? [.init(label: "Open Trackpad") { Self.open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension") }] : []))
        }
        checks = c
        startAtLogin = Config.current.startAtLogin
    }

    func setStartAtLogin(_ on: Bool) {
        Config.setTopLevel(key: "start-at-login", value: on ? "true" : "false")
        WindowManager.shared.reload()
        startAtLogin = on
    }

    // MARK: helpers

    static func otherWindowManagers() -> [(name: String, app: NSRunningApplication?)] {
        let known = ["com.amethyst.Amethyst": "Amethyst", "bobko.aerospace": "AeroSpace",
                     "com.knollsoft.Rectangle": "Rectangle", "com.crowdcafe.windowmagnet": "Magnet",
                     "com.lwouis.alt-tab-macos": ""]
        var found: [(String, NSRunningApplication?)] = []
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, let name = known[id], !name.isEmpty { found.append((name, app)) }
        }
        // yabai is a plain process, not an app.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", "yabai"]
        p.standardOutput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        if p.terminationStatus == 0 { found.append(("yabai", nil)) }
        return found
    }

    static func bool(_ domain: String, _ key: String) -> Bool? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
    }

    static func int(_ domain: String, _ key: String) -> Int? {
        CFPreferencesAppSynchronize(domain as CFString)
        return (CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber)?.intValue
    }

    static func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    static func run(_ tool: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try? p.run(); p.waitUntilExit()
        Log.info("setup check: ran \(tool) \(args.joined(separator: " "))")
    }
}

/// How many Spaces each display has. Private but long-stable API (yabai uses it).
enum SpacesInfo {
    static func spacesPerDisplay() -> [Int]? {
        typealias ConnFn = @convention(c) () -> Int32
        typealias CopyFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
        let paths = ["/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                     "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"]
        for path in paths {
            guard let h = dlopen(path, RTLD_LAZY),
                  let c = dlsym(h, "CGSMainConnectionID") ?? dlsym(h, "_CGSDefaultConnection"),
                  let s = dlsym(h, "CGSCopyManagedDisplaySpaces") else { continue }
            let conn = unsafeBitCast(c, to: ConnFn.self)()
            guard let list = unsafeBitCast(s, to: CopyFn.self)(conn)?.takeRetainedValue() as? [[String: Any]] else { continue }
            // Count desktops only (type 0), not full-screen app Spaces.
            return list.map { d in ((d["Spaces"] as? [[String: Any]]) ?? []).filter { ($0["type"] as? Int ?? 0) == 0 }.count }
        }
        return nil
    }
}

// MARK: - view

struct WelcomeView: View {
    @ObservedObject var model: SetupModel
    var close: () -> Void
    var icon: NSImage = NSApp.applicationIconImage
    /// Offscreen rendering (README image): no scroll view or real toggle,
    /// which ImageRenderer can't draw.
    var rendering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: icon).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Kachel").font(.system(size: 26, weight: .bold))
                    Text("xmonad's workspaces, at home on macOS. A few settings make it work best:")
                        .foregroundStyle(.secondary)
                }
            }
            if rendering {
                VStack(spacing: 10) { ForEach(model.checks) { CheckRow(check: $0) } }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.checks) { CheckRow(check: $0) }
                    }
                }
            }
            HStack {
                if rendering {
                    Label("Start Kachel at login", systemImage: "checkmark.square.fill").labelStyle(.titleAndIcon)
                } else {
                    Toggle("Start Kachel at login", isOn: Binding(get: { model.startAtLogin }, set: { model.setStartAtLogin($0) }))
                }
                Spacer()
                Button("Keyboard Shortcuts") { WindowManager.shared.showOverview(hint: "Press any key to close") }
                Button("Done") { close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 24)
        .frame(width: 660, height: rendering ? nil : 700)
    }
}

struct CheckRow: View {
    var check: SetupCheck

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(check.title).font(.headline)
                Text(check.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ForEach(Array(check.actions.enumerated()), id: \.offset) { _, a in
                Button(a.label, action: a.run)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RowBackground())
    }

    private var icon: String {
        switch check.status {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    private var color: Color {
        switch check.status {
        case .ok: return .green
        case .warn: return .orange
        case .info: return .blue
        }
    }
}

/// Liquid Glass rows.
struct RowBackground: ViewModifier {
    /// Offscreen renders (README images, UI tests) can't draw glass: a soft fill there.
    static var plain = false
    func body(content: Content) -> some View {
        if Self.plain {
            content.background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        } else {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}


extension SetupModel {
    /// For README images: a typical first launch, no real system state.
    static func demo() -> SetupModel {
        let m = SetupModel()
        m.checks = [
            .init(id: "ax", status: .ok, title: "Accessibility", detail: "Kachel can move and resize windows."),
            .init(id: "others", status: .warn, title: "Other window managers",
                  detail: "Amethyst is running. Two tilers fight over the same windows.",
                  actions: [.init(label: "Quit Amethyst") {}]),
            .init(id: "spaces", status: .ok, title: "One Space per display",
                  detail: "Each display has a single Space, as Kachel expects."),
            .init(id: "mru", status: .warn, title: "Automatically rearrange Spaces",
                  detail: "macOS reorders Spaces by recent use. Turn it off so displays stay predictable.",
                  actions: [.init(label: "Turn Off") {}]),
            .init(id: "group", status: .info, title: "Mission Control: group windows by app",
                  detail: "Recommended: Kachel parks hidden windows in a corner, which Mission Control shows very small.",
                  actions: [.init(label: "Turn On") {}]),
            .init(id: "tiling", status: .ok, title: "macOS window tiling", detail: "Off."),
            .init(id: "stage", status: .ok, title: "Stage Manager", detail: "Off."),
            .init(id: "swipe", status: .ok, title: "Trackpad: 3-finger swipes", detail: "Free for Kachel's workspace swipes."),
        ]
        return m
    }
}
