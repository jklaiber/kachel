import AppKit
import ApplicationServices
import KachelCore

// The `kachel` command (Homebrew links it as `kachel`), or `Kachel --ctl …`.
if (CommandLine.arguments[0] as NSString).lastPathComponent == "kachel" {
    Ctl.client(Array(CommandLine.arguments.dropFirst()))
}
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--ctl" {
    Ctl.client(Array(CommandLine.arguments.dropFirst(2)))
}

// `Kachel --watchdog <pid> <bundle>`: the helper that puts windows back if
// Kachel dies (see Watchdog.swift). Nothing else of the app runs in it.
if let i = CommandLine.arguments.firstIndex(of: "--watchdog"), CommandLine.arguments.count > i + 2,
   let pid = pid_t(CommandLine.arguments[i + 1]) {
    Watchdog.run(parent: pid, bundle: CommandLine.arguments[i + 2])
}

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

// The `kachel` command (see Ctl.swift).
Ctl.listen({ WindowManager.shared.ctl($0) }, current: { WindowManager.shared.currentEvents() })
WindowManager.shared.onEvent = { Ctl.broadcast(kind: $0, line: $1) }
WindowManager.shared.eventsWanted = { Ctl.subscribed > 0 }

/// A quit from outside (`brew upgrade` quits Kachel this way, as do logout
/// and AppleScript) goes the same way as mod-shift-q: windows come back first.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Log.info("asked to quit (Apple Event or logout)")
        WindowManager.shared.quit()      // exits
        return .terminateNow
    }
}
let appDelegate = AppDelegate()
app.delegate = appDelegate

// Bar, config and hotkeys come up right away, so you can see what's going on
// even before Accessibility is granted.
WindowManager.shared.startUI()
CrashPrompt.scheduleChecks()

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
