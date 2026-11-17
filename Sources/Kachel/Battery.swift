import AppKit
import IOKit.ps

/// The internal battery, from IOKit's power sources (what the menu bar's
/// battery uses). macOS tells us when it changes, so nothing is polled.
final class Battery {
    struct State: Equatable {
        var percent: Int
        var charging: Bool
        var onPower: Bool        // plugged in (charging or full)
    }

    /// nil: no battery, e.g. on an iMac or a Mac mini.
    private(set) var state: State?
    var onChange: (() -> Void)?
    private var source: CFRunLoopSource?

    init() {
        read()
        let me = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let battery = Unmanaged<Battery>.fromOpaque(ctx).takeUnretainedValue()
            battery.read()
            battery.onChange?()
        }, me)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    /// Screenshots and the settings preview: a made-up battery.
    func setDemo(_ s: State?) { state = s }

    func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            state = nil
            return
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            state = State(percent: Int((Double(current) * 100 / Double(max)).rounded()),
                          charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                          onPower: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
            return
        }
        state = nil
    }

    /// The SF Symbol, like the menu bar's: a bolt when plugged in, otherwise
    /// filled in quarters.
    static func symbol(_ s: State) -> String {
        if s.charging || s.onPower { return "battery.100percent.bolt" }
        switch s.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Red like the menu bar's when it's nearly empty and not plugged in.
    static func isLow(_ s: State) -> Bool { s.percent <= 10 && !s.onPower }

    /// Battery settings, where a click on the widget goes.
    static let settingsURL = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
}
