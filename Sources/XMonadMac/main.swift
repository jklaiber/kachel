import AppKit
import ApplicationServices

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, just the menu bar item

// Restore parked windows on Ctrl-C / kill, not just on mod-shift-q.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { WindowManager.shared.quit() }
    src.resume()
    signalSources.append(src)
}

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    WindowManager.shared.start()
} else {
    NSLog("XMonadMac: waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)")
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
        if AXIsProcessTrusted() {
            timer.invalidate()
            WindowManager.shared.start()
        }
    }
}

app.run()
