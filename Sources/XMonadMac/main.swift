import AppKit
import ApplicationServices
import XMonadCore

let app = NSApplication.shared
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

// Debug hooks for scripts:
//   xmonadmac-ctl dump              → state into ~/Library/Logs/XMonadMac.log
//   xmonadmac-ctl "workspace 2"     → run any config command
DistributedNotificationCenter.default().addObserver(forName: .init("local.xmonadmac.ctl"), object: nil, queue: .main) { note in
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

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
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
