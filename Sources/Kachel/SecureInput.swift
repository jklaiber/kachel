import AppKit
import Carbon.HIToolbox

/// Secure Event Input: an app (Terminal's Secure Keyboard Entry, a password
/// prompt, a password manager) asks macOS to hide key presses from other
/// apps. Event taps then get no keys at all, so one-sided shortcuts
/// (mod: left-alt) stop working until that app lets go. Kachel can't turn it
/// off; it can only tell you who holds it.
enum SecureInput {
    /// The app holding secure input, or nil when it's off.
    static func holder() -> String? {
        guard IsSecureEventInputEnabled() else { return nil }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        guard let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid != 0 else {
            return "an app"
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
    }
}
