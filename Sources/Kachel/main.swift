import AppKit
import ApplicationServices
import KachelCore

let app = NSApplication.shared

if CommandLine.arguments.contains("--version") {
    print("Kachel \(AppVersion.string)")
    exit(0)
}

// The complete default config with all comments (config.example.yaml in the repo).
if CommandLine.arguments.contains("--print-default-config") {
    print(Settings.defaultYAML)
    exit(0)
}

// Which key combinations macOS and skhd already use (the settings window warns about these).
if CommandLine.arguments.contains("--list-taken-keys") {
    for (title, map) in [("macOS", KeyUse.macOS()), ("skhd", KeyUse.skhd())] {
        print("\(title):")
        for (chord, what) in map.sorted(by: { ShortcutList.glyphs($0.key) < ShortcutList.glyphs($1.key) }) {
            print("  \(ShortcutList.glyphs(chord).padding(toLength: 10, withPad: " ", startingAt: 0)) \(what)")
        }
    }
    exit(0)
}

// README images: `Kachel --render-screenshots assets/screenshots` (see Screenshots.swift).
if let i = CommandLine.arguments.firstIndex(of: "--render-screenshots") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "assets/screenshots"
    do { try Screenshots.render(to: URL(fileURLWithPath: dir)) } catch { print("error: \(error)"); exit(1) }
    exit(0)
}
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar item: just our bar

// Restore parked windows on Ctrl-C / kill, not just on mod-shift-q.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { WindowManager.shared.quit() }
    src.resume()
    signalSources.append(src)
}

// If Kachel crashes, don't leave windows parked in a corner: put them back
// on screen first, then crash as usual. The next start restores workspaces
// from the state saved after every change.
for sig in [SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP] {
    signal(sig) { s in
        WindowManager.shared.emergencyRestore()
        signal(s, SIG_DFL)
        raise(s)
    }
}
NSSetUncaughtExceptionHandler { _ in WindowManager.shared.emergencyRestore() }

// Debug hooks for scripts:
//   kachel-ctl dump              → state into ~/Library/Logs/Kachel.log
//   kachel-ctl "workspace 2"     → run any config command
DistributedNotificationCenter.default().addObserver(forName: .init("io.github.jklaiber.kachel.ctl"), object: nil, queue: .main) { note in
    let text = (note.object as? String) ?? ""
    Log.info("ctl: \(text)")
    if text == "dump" { WindowManager.shared.dumpState(); return }
    do {
        let cmd = try Settings.parseCommand(text, workspaceCount: Config.current.workspaces.count, context: "ctl")
        WindowManager.shared.perform(cmd)
    } catch { Log.info("ctl: \(error)") }
}

// Bar, config and hotkeys come up right away, so you can see what's going on
// even before Accessibility is granted.
WindowManager.shared.startUI()

// startUI shows the welcome window and asks macOS for Accessibility.
if AXIsProcessTrusted() {
    WindowManager.shared.startManaging()
} else {
    Log.info("waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)")
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
        if AXIsProcessTrusted() {
            timer.invalidate()
            WindowManager.shared.startManaging()
        }
    }
}

app.run()
