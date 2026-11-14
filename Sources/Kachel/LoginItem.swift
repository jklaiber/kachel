import ServiceManagement

/// start-at-login: registers Kachel.app as a login item (System Settings →
/// General → Login Items lists it too).
enum LoginItem {
    static func apply(_ want: Bool) {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }     // swift run: nothing to register
        let service = SMAppService.mainApp
        let on = service.status == .enabled
        guard want != on else { return }
        do {
            if want { try service.register() } else { try service.unregister() }
            Log.info("start at login: \(want ? "on" : "off")")
        } catch {
            Log.info("start at login: could not turn \(want ? "on" : "off"): \(error.localizedDescription)")
        }
    }
}
