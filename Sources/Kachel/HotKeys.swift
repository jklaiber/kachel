import AppKit
import Carbon.HIToolbox
import KachelCore

/// Global hotkeys via Carbon's RegisterEventHotKey. Needs no permission at
/// all, and keys are swallowed so they never reach the focused app.
///
/// Carbon can't tell left Option from right Option, and takes both. With
/// `mod: left-alt` the shortcuts using that modifier go through an event tap
/// instead, which sees which key is held and lets the other one through to
/// the keyboard layout (needs Accessibility, which Kachel has anyway).
final class HotKeys {
    static let shared = HotKeys()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x4B43_484C // "KCHL"

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            HotKeys.shared.fire(hk.id)
            return noErr
        }, 1, &spec, nil, nil)
        if status != noErr { Log.info("InstallEventHandler failed: \(status)") }
    }

    /// Registers the whole keymap. Returns human-readable problems.
    func bind(_ keys: [KeyChord: Command], sides: [Modifier: ModifierSide] = [:],
              perform: @escaping (Command) -> Void) -> [String] {
        unbindAll()
        let layout = KeyCodes.layoutMap()
        var problems: [String] = []
        for (chord, cmd) in keys.sorted(by: { $0.key.description < $1.key.description }) {
            guard let code = KeyCodes.code(for: chord.key, layout: layout) else {
                problems.append("unknown key '\(chord.key)' in \(chord)")
                continue
            }
            if !chord.modifiers.isDisjoint(with: sides.keys) {
                tapped.append(TapChord(code: Int64(code), mods: chord.modifiers, sides: sides) { perform(cmd) })
                continue
            }
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), KeyCodes.carbonMask(chord.modifiers),
                                             EventHotKeyID(signature: signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = { perform(cmd) }
            } else {
                problems.append("\(chord) is taken by another app (error \(status))")
            }
        }
        if !tapped.isEmpty {
            if startTap() {
                Log.info("\(tapped.count) shortcuts only on \(sides.map { "\($0.value.rawValue) \($0.key.rawValue)" }.sorted().joined(separator: ", "))")
            } else {
                problems.append("shortcuts with \(sides.map { "\($0.value.rawValue)-\($0.key.rawValue)" }.sorted().joined(separator: ", ")) need Accessibility permission")
            }
        }
        Log.info("registered \(refs.count + tapped.count) hotkeys" + (problems.isEmpty ? "" : "; problems: \(problems)"))
        return problems
    }

    func unbindAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
        tapped.removeAll()
        swallowedUps.removeAll()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        tapSource = nil
    }

    // MARK: - one-sided modifiers

    private struct TapChord {
        var code: Int64
        var mods: Set<Modifier>
        var sides: [Modifier: ModifierSide]
        var action: () -> Void
    }

    private var tapped: [TapChord] = []
    /// Some shortcuts go through the event tap (one-sided modifiers), which
    /// secure input blocks.
    var usesTap: Bool { !tapped.isEmpty }
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    /// Keys whose press we swallowed: their release goes too.
    private var swallowedUps: Set<Int64> = []

    private func startTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, _ in
            HotKeys.shared.handle(type, event).map { Unmanaged.passUnretained($0) }
        }, userInfo: nil) else { return false }
        tap = t
        tapSource = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    /// nil = swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowedUps.remove(code) != nil ? nil : event
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard let hit = tapped.first(where: { $0.code == code && Self.matches($0, event.flags) }) else { return event }
            swallowedUps.insert(code)
            // Like Carbon hotkeys: once per press, not again while it repeats.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                Log.info("hotkey \(code) pressed (one-sided)")
                DispatchQueue.main.async(execute: hit.action)
            }
            return nil
        default:
            return event
        }
    }

    /// Exactly these modifiers, and the one-sided ones on the right side.
    private static func matches(_ c: TapChord, _ flags: CGEventFlags) -> Bool {
        let held: [Modifier: Bool] = [.cmd: flags.contains(.maskCommand), .alt: flags.contains(.maskAlternate),
                                      .ctrl: flags.contains(.maskControl), .shift: flags.contains(.maskShift)]
        for (m, down) in held where down != c.mods.contains(m) { return false }
        for (m, side) in c.sides where c.mods.contains(m) {
            if !flags.contains(Self.deviceFlag(m, side)) { return false }
        }
        return true
    }

    /// The left/right bits macOS puts in every key event (IOKit's NX_DEVICE…KEYMASK).
    static func deviceFlag(_ m: Modifier, _ side: ModifierSide) -> CGEventFlags {
        let raw: UInt64
        switch (m, side) {
        case (.ctrl, .left): raw = 0x0001
        case (.ctrl, .right): raw = 0x2000
        case (.shift, .left): raw = 0x0002
        case (.shift, .right): raw = 0x0004
        case (.cmd, .left): raw = 0x0008
        case (.cmd, .right): raw = 0x0010
        case (.alt, .left): raw = 0x0020
        case (.alt, .right): raw = 0x0040
        }
        return CGEventFlags(rawValue: raw)
    }

    fileprivate func fire(_ id: UInt32) {
        Log.info("hotkey \(id) pressed")
        actions[id]?()
    }
}
