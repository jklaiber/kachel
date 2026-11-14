import AppKit
import ApplicationServices

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
