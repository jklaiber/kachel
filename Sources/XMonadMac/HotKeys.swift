import AppKit
import Carbon.HIToolbox
import XMonadCore

/// Global hotkeys via Carbon's RegisterEventHotKey. Needs no permission at
/// all, and keys are swallowed so they never reach the focused app.
final class HotKeys {
    static let shared = HotKeys()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x584D_4F4E // "XMON"

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
    func bind(_ keys: [KeyChord: Command], perform: @escaping (Command) -> Void) -> [String] {
        unbindAll()
        let layout = KeyCodes.layoutMap()
        var problems: [String] = []
        for (chord, cmd) in keys.sorted(by: { $0.key.description < $1.key.description }) {
            guard let code = KeyCodes.code(for: chord.key, layout: layout) else {
                problems.append("unknown key '\(chord.key)' in \(chord)")
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
        Log.info("registered \(refs.count) hotkeys" + (problems.isEmpty ? "" : "; problems: \(problems)"))
        return problems
    }

    func unbindAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        Log.info("hotkey \(id) pressed")
        actions[id]?()
    }
}
