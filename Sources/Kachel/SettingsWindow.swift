import AppKit
import KachelCore
import SwiftUI

/// Kachel's settings (SwiftUI has its own `Settings`).
typealias KSettings = KachelCore.Settings

/// Kachel's settings, in the style of System KSettings. Every change is written
/// into config.yaml (comments and hand-written parts kept) and applied at once;
/// a change that wouldn't load is rolled back and shown.
final class SettingsWindow {
    private var window: NSWindow?
    private let model = SettingsModel()

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Kachel Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.setContentSize(NSSize(width: 820, height: 600))
            w.minSize = NSSize(width: 720, height: 460)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        model.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - model

final class SettingsModel: ObservableObject {
    @Published var s = Config.current
    @Published var error: String?
    @Published var lastSaveError: String?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: Config.didLoad, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        s = Config.current
        error = Config.error
    }

    /// Apply a text edit; remember why it failed if it did.
    func edit(_ transform: (String) -> String) {
        lastSaveError = Config.edit(transform)
        reload()
    }

    func top(_ key: String, _ value: String) { edit { KSettings.setTopLevel($0, key: key, value: value) } }
    func nested(_ section: String, _ key: String, _ value: String) {
        edit { KSettings.setNested($0, section: section, key: key, value: value) }
    }

    /// A binding that reads from the current settings and writes through `save`.
    func binding<T>(_ get: @escaping (KSettings) -> T, _ save: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: { get(self.s) }, set: { save($0) })
    }

    static func yaml(_ b: Bool) -> String { b ? "true" : "false" }
    static func yaml(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

// MARK: - window

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", bar = "Bar", border = "Focus Border", trackpad = "Trackpad"
    case shortcuts = "Shortcuts", rules = "App Rules", scratchpads = "Scratchpads"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .bar: return "menubar.rectangle"
        case .border: return "square.dashed"
        case .trackpad: return "hand.draw"
        case .shortcuts: return "keyboard"
        case .rules: return "macwindow.on.rectangle"
        case .scratchpads: return "rectangle.on.rectangle.angled"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            VStack(spacing: 0) {
                if let e = model.error ?? model.lastSaveError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(e).font(.callout).lineLimit(3)
                        Spacer()
                    }
                    .padding(10).background(Color.orange.opacity(0.12))
                }
                Group {
                    switch pane ?? .general {
                    case .general: GeneralPane(m: model)
                    case .bar: BarPane(m: model)
                    case .border: BorderPane(m: model)
                    case .trackpad: TrackpadPane(m: model)
                    case .shortcuts: ShortcutsPane(m: model)
                    case .rules: RulesPane(m: model)
                    case .scratchpads: ScratchpadsPane(m: model)
                    }
                }
                .formStyle(.grouped)
            }
            .toolbar {
                ToolbarItem {
                    Button { Config.openInEditor() } label: { Label("Open config.yaml", systemImage: "doc.text") }
                        .help("Open config.yaml in your editor")
                }
            }
            .navigationTitle((pane ?? .general).rawValue)
        }
    }
}

// MARK: - panes

struct GeneralPane: View {
    @ObservedObject var m: SettingsModel
    @State private var workspacesText = ""
    @State private var terminalText = ""

    static let mods: [(String, String)] = [("alt", "⌥ Option"), ("ctrl+alt", "⌃⌥ Control-Option"),
                                           ("alt+cmd", "⌥⌘ Option-Command"), ("ctrl+cmd", "⌃⌘ Control-Command")]

    var body: some View {
        Form {
            Section("Keyboard") {
                Picker("Modifier (mod)", selection: m.binding({ modName($0.mod) }, { m.top("mod", $0) })) {
                    ForEach(Self.mods, id: \.0) { Text($0.1).tag($0.0) }
                    if !Self.mods.contains(where: { $0.0 == modName(m.s.mod) }) {
                        Text(ShortcutList.glyphs(m.s.mod)).tag(modName(m.s.mod))
                    }
                }
                Slider(value: m.binding({ $0.shortcutOverview }, { m.top("shortcut-overview", SettingsModel.yaml(($0 * 10).rounded() / 10)) }),
                       in: 0...2, step: 0.1) {
                    Text("Shortcut overview after holding mod")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("2 s") }
            }
            Section("Workspaces") {
                TextField("Names", text: $workspacesText, prompt: Text("1 2 3 4 5 6 7 8 9"))
                    .onSubmit {
                        let names = workspacesText.split(separator: " ").map(String.init)
                        if !names.isEmpty { m.top("workspaces", KSettings.flowList(names)) }
                    }
                Text("Separated by spaces; press Return to apply.").font(.caption).foregroundStyle(.secondary)
                Toggle("The key of the current workspace goes back to the previous one",
                       isOn: m.binding({ $0.workspaceBackAndForth }, { m.top("workspace-back-and-forth", SettingsModel.yaml($0)) }))
                ForEach(m.s.workspaces, id: \.self) { tag in
                    Picker("Workspace \(tag) always on", selection: m.binding({ $0.workspaceScreens[tag] ?? "" }, { pin(tag, $0) })) {
                        Text("Any display").tag("")
                        Text("Main display").tag("main")
                        Text("External display").tag("external")
                        Text("Built-in display").tag("builtin")
                        ForEach(1...max(1, NSScreen.screens.count), id: \.self) { Text("Display \($0) from the left").tag("\($0)") }
                        if let p = m.s.workspaceScreens[tag], !["main", "external", "builtin"].contains(p), Int(p) == nil {
                            Text(p).tag(p)
                        }
                    }
                }
            }
            Section("Windows") {
                Picker("New windows", selection: m.binding({ $0.newWindows }, { m.top("new-windows", $0.rawValue) })) {
                    Text("At the end of the stack").tag(InsertPosition.end)
                    Text("Below the focused window").tag(InsertPosition.below)
                    Text("Above the focused window (xmonad)").tag(InsertPosition.above)
                    Text("As the new master").tag(InsertPosition.master)
                }
                Toggle("Float dialogs (windows without a fullscreen button)",
                       isOn: m.binding({ $0.floatDialogs }, { m.top("float-dialogs", SettingsModel.yaml($0)) }))
                Stepper(value: m.binding({ $0.floatSmallWindows }, { m.top("float-small-windows", String($0)) }), in: 0...1000, step: 50) {
                    Text(m.s.floatSmallWindows == 0 ? "Float small windows: off" : "Float windows smaller than \(m.s.floatSmallWindows) pt")
                }
            }
            Section("Layout") {
                Stepper(value: m.binding({ $0.gap }, { m.top("gap", SettingsModel.yaml($0)) }), in: 0...40) {
                    Text("Gap between windows: \(Int(m.s.gap)) pt")
                }
                Slider(value: m.binding({ $0.ratio }, { m.top("ratio", SettingsModel.yaml(($0 * 100).rounded() / 100)) }), in: 0.2...0.8) {
                    Text("Master size for new workspaces: \(Int(m.s.ratio * 100)) %")
                }
                ForEach([LayoutKind.tall, .mirrorTall, .threeColumn, .column, .full], id: \.self) { kind in
                    Toggle("Layout: \(kind.rawValue)", isOn: m.binding({ $0.layouts.contains(kind) }, { on in
                        var l = m.s.layouts.filter { $0 != kind }
                        if on { l = [LayoutKind.tall, .mirrorTall, .threeColumn, .column, .full].filter { l.contains($0) || $0 == kind } }
                        if !l.isEmpty { m.top("layouts", KSettings.flowList(l.map(\.configName))) }
                    }))
                }
            }
            Section("Mouse and Trackpad") {
                Picker("Pointer follows focus", selection: m.binding({ $0.mouseFollowsFocus }, { m.top("mouse-follows-focus", $0.rawValue) })) {
                    Text("To the focused window").tag(KSettings.MouseFollows.window)
                    Text("Only between displays").tag(KSettings.MouseFollows.screen)
                    Text("Never").tag(KSettings.MouseFollows.off)
                }
                Toggle("Focus follows the pointer", isOn: m.binding({ $0.focusFollowsMouse }, { m.top("focus-follows-mouse", SettingsModel.yaml($0)) }))
                Toggle("Trackpad feedback", isOn: m.binding({ $0.haptics }, { m.top("haptics", SettingsModel.yaml($0)) }))
            }
            Section("Kachel") {
                Toggle("Start at login", isOn: m.binding({ $0.startAtLogin }, { m.top("start-at-login", SettingsModel.yaml($0)) }))
                Toggle("Icon in the menu bar", isOn: m.binding({ $0.menubarIcon }, { m.top("menubar-icon", SettingsModel.yaml($0)) }))
                TextField("Terminal command", text: $terminalText).onSubmit { m.top("terminal", KSettings.yamlScalar(terminalText)) }
            }
        }
        .onAppear { workspacesText = m.s.workspaces.joined(separator: " "); terminalText = m.s.terminal }
    }

    private func modName(_ mods: Set<Modifier>) -> String {
        [Modifier.ctrl, .alt, .cmd, .shift].filter(mods.contains).map { $0 == .ctrl ? "ctrl" : $0.rawValue }.joined(separator: "+")
    }

    private func pin(_ tag: String, _ pattern: String) {
        var map = m.s.workspaceScreens
        map[tag] = pattern.isEmpty ? nil : pattern
        let flow = map.isEmpty ? "{}" : "{" + map.sorted { $0.key < $1.key }
            .map { "\"\($0.key)\": \(KSettings.yamlScalar($0.value))" }.joined(separator: ", ") + "}"
        m.top("workspace-screens", flow)
    }
}

struct BarPane: View {
    @ObservedObject var m: SettingsModel
    @State private var date = ""
    @State private var clock = ""

    var body: some View {
        Form {
            Section {
                Toggle("Show the bar", isOn: m.binding({ $0.bar.enabled }, { m.nested("bar", "enabled", SettingsModel.yaml($0)) }))
                Toggle("Same height as the menu bar", isOn: m.binding({ $0.bar.height == nil }, {
                    m.nested("bar", "height", $0 ? "auto" : "30")
                }))
                if let h = m.s.bar.height {
                    Stepper(value: m.binding({ _ in h }, { m.nested("bar", "height", SettingsModel.yaml($0)) }), in: 18...60) {
                        Text("Height: \(Int(h)) pt")
                    }
                }
                Stepper(value: m.binding({ $0.bar.fontSize }, { m.nested("bar", "font-size", SettingsModel.yaml($0)) }), in: 9...20) {
                    Text("Text size: \(Int(m.s.bar.fontSize)) pt")
                }
                Picker("Background", selection: m.binding({ $0.bar.background }, { m.nested("bar", "background", $0.rawValue) })) {
                    Text("Transparent, like the menu bar").tag(BarSettings.Background.transparent)
                    Text("Frosted glass").tag(BarSettings.Background.blur)
                }
                Picker("Text colour", selection: m.binding({ $0.bar.appearance }, { m.nested("bar", "appearance", $0.rawValue) })) {
                    Text("Automatic, from the wallpaper").tag(BarSettings.Appearance.auto)
                    Text("Dark text").tag(BarSettings.Appearance.light)
                    Text("Light text").tag(BarSettings.Appearance.dark)
                }
            }
            Section("Shows") {
                ForEach(BarWidget.allCases, id: \.self) { w in
                    Toggle(w.menuTitle, isOn: m.binding({ $0.bar.shows(w) }, { on in
                        if on != m.s.bar.shows(w) { Config.toggleWidget(w); WindowManager.shared.reload(); m.reload() }
                    }))
                }
                Toggle("Hide empty workspaces", isOn: m.binding({ $0.bar.hideEmptyWorkspaces }, {
                    m.nested("bar", "hide-empty-workspaces", SettingsModel.yaml($0))
                }))
            }
            Section("Date and Time") {
                TextField("Date format", text: $date).onSubmit { m.nested("bar", "date-format", KSettings.yamlScalar(date)) }
                TextField("Clock format", text: $clock).onSubmit { m.nested("bar", "clock-format", KSettings.yamlScalar(clock)) }
                Text("Unicode patterns, e.g. EEE d MMM or HH:mm:ss. Press Return to apply.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { date = m.s.bar.dateFormat; clock = m.s.bar.clockFormat }
    }
}

struct BorderPane: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Frame the focused window", isOn: m.binding({ $0.border.enabled }, { m.nested("border", "enabled", SettingsModel.yaml($0)) }))
                Slider(value: m.binding({ $0.border.width }, { m.nested("border", "width", SettingsModel.yaml($0.rounded())) }), in: 1...8, step: 1) {
                    Text("Width: \(Int(m.s.border.width)) pt")
                }
                Toggle("Use the accent colour", isOn: m.binding({ $0.border.color == "accent" }, {
                    m.nested("border", "color", $0 ? "accent" : "\"#E8965A\"")
                }))
                if m.s.border.color != "accent" {
                    ColorPicker("Colour", selection: m.binding({ Color(nsColor: NSColor(hex: $0.border.color) ?? .orange) }, { c in
                        m.nested("border", "color", "\"\(NSColor(c).hexString)\"")
                    }), supportsOpacity: false)
                }
                Toggle("Corners follow each window", isOn: m.binding({ $0.border.radius == nil }, {
                    m.nested("border", "radius", $0 ? "auto" : "12")
                }))
                if let r = m.s.border.radius {
                    Stepper(value: m.binding({ _ in r }, { m.nested("border", "radius", SettingsModel.yaml($0)) }), in: 0...32) {
                        Text("Corner radius: \(Int(r)) pt")
                    }
                }
                Toggle("No frame when a window is alone on its display",
                       isOn: m.binding({ $0.border.smart }, { m.nested("border", "smart", SettingsModel.yaml($0)) }))
            }
        }
    }
}

struct TrackpadPane: View {
    @ObservedObject var m: SettingsModel
    @State private var swipes: [String: String] = [:]
    static let dirs = [("swipe-left", "Swipe left"), ("swipe-right", "Swipe right"), ("swipe-up", "Swipe up"), ("swipe-down", "Swipe down")]

    var body: some View {
        Form {
            Section {
                Toggle("Switch workspaces with swipes", isOn: m.binding({ $0.gestures.enabled }, { m.nested("gestures", "enabled", SettingsModel.yaml($0)) }))
                Picker("Fingers", selection: m.binding({ $0.gestures.fingers }, { m.nested("gestures", "fingers", String($0)) })) {
                    Text("Three").tag(3); Text("Four").tag(4)
                }
                Picker("Direction", selection: m.binding({ $0.gestures.direction }, { m.nested("gestures", "direction", $0.rawValue) })) {
                    Text("Like macOS (follows Natural scrolling)").tag(GestureSettings.SwipeDirection.auto)
                    Text("Natural").tag(GestureSettings.SwipeDirection.natural)
                    Text("Reversed").tag(GestureSettings.SwipeDirection.reversed)
                }
                Toggle("Skip empty workspaces", isOn: m.binding({ $0.gestures.skipEmpty }, { m.nested("gestures", "skip-empty", SettingsModel.yaml($0)) }))
            }
            Section("Commands") {
                ForEach(Self.dirs, id: \.0) { key, label in
                    TextField(label, text: Binding(get: { swipes[key] ?? "" }, set: { swipes[key] = $0 }), prompt: Text("nothing"))
                        .onSubmit {
                            let v = (swipes[key] ?? "").trimmingCharacters(in: .whitespaces)
                            m.nested("gestures", key, v.isEmpty ? "~" : v)
                        }
                }
                Text("Any command, e.g. workspace-next, window-search, scratchpad term. Press Return to apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let g = m.s.gestures
            swipes = ["swipe-left": g.left.map(commandText) ?? "", "swipe-right": g.right.map(commandText) ?? "",
                      "swipe-up": g.up.map(commandText) ?? "", "swipe-down": g.down.map(commandText) ?? ""]
        }
    }
}

struct ShortcutsPane: View {
    @ObservedObject var m: SettingsModel
    @State private var newCommand = ""
    @State private var adding = false

    var rows: [(chord: KeyChord, command: Command)] {
        m.s.keys.map { ($0.key, $0.value) }.sorted {
            let a = ShortcutList.describe($0.command), b = ShortcutList.describe($1.command)
            return (a.group, a.label, $0.chord.description) < (b.group, b.label, $1.chord.description)
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.chord) { row in
                    HStack {
                        KeyRecorder(chord: row.chord) { new in
                            guard new != row.chord else { return }
                            let cmd = commandText(row.command)
                            m.edit { t in
                                let removed = KSettings.setKey(t, chord: row.chord, chordText: "", command: nil, mod: m.s.mod)
                                return KSettings.setKey(removed, chord: new, chordText: chordText(new, mod: m.s.mod), command: cmd, mod: m.s.mod)
                            }
                        }
                        .frame(width: 130)
                        Text(ShortcutList.describe(row.command).label)
                        Spacer()
                        Text(commandText(row.command)).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            m.edit { KSettings.setKey($0, chord: row.chord, chordText: "", command: nil, mod: m.s.mod) }
                        } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
            }
            Section("Add a Shortcut") {
                TextField("Command", text: $newCommand, prompt: Text("e.g. scratchpad term, spawn open -a Safari"))
                HStack {
                    Text(validation ?? "Then record the keys:").font(.caption).foregroundStyle(validation == nil ? Color.secondary : .orange)
                    Spacer()
                    KeyRecorder(chord: nil) { chord in
                        guard validation == nil, !newCommand.isEmpty else { return }
                        m.edit { KSettings.setKey($0, chord: chord, chordText: chordText(chord, mod: m.s.mod), command: newCommand, mod: m.s.mod) }
                        newCommand = ""
                    }
                    .frame(width: 130)
                }
            }
        }
    }

    private var validation: String? {
        guard !newCommand.isEmpty else { return nil }
        do { _ = try KSettings.parseCommand(newCommand, workspaceCount: m.s.workspaces.count, context: "command"); return nil }
        catch { return "\(error)" }
    }
}

struct RulesPane: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        Form {
            Section {
                if m.s.rules.isEmpty {
                    Text("No rules yet. Add one below, or press ⌥⇧P on any window.").foregroundStyle(.secondary)
                }
                ForEach(Array(m.s.rules.enumerated()), id: \.offset) { _, rule in
                    HStack {
                        Text(appName(rule.app)).frame(width: 180, alignment: .leading)
                        if let t = rule.title {
                            Text("title contains “\(t)”").foregroundStyle(.secondary)
                            Spacer()
                            Text("edit in config.yaml").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker("", selection: Binding(get: { rule.workspace ?? "" }, set: { ws in
                                save(rule, workspace: ws.isEmpty ? nil : ws, float: rule.float)
                            })) {
                                Text("Any workspace").tag("")
                                ForEach(m.s.workspaces, id: \.self) { Text("Workspace \($0)").tag($0) }
                            }.labelsHidden().frame(width: 160)
                            Toggle("Float", isOn: Binding(get: { rule.float }, set: { save(rule, workspace: rule.workspace, float: $0) }))
                            Spacer()
                            Button(role: .destructive) {
                                m.edit { KSettings.setRule($0, app: rule.app, rule: nil) }
                            } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section {
                Menu("Add a Rule for…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            guard let id = app.bundleIdentifier else { return }
                            m.edit { KSettings.setRule($0, app: id, rule: Rule(app: id, workspace: m.s.workspaces.first), comment: app.localizedName) }
                        }
                    }
                }
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func save(_ rule: Rule, workspace: String?, float: Bool) {
        var r = rule
        r.workspace = workspace
        r.float = float
        let keep = (r.workspace == nil && !r.float) ? nil : r
        m.edit { KSettings.setRule($0, app: rule.app, rule: keep, comment: appName(rule.app)) }
    }

    private func appName(_ id: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
    }
}

struct ScratchpadsPane: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(m.s.scratchpads, id: \.name) { sp in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(sp.name).font(.headline)
                            Spacer()
                            let keys = m.s.keys.filter { $0.value == .scratchpad(sp.name) }.map { ShortcutList.glyphs($0.key) }
                            Text(keys.joined(separator: " ")).font(.body.monospaced())
                        }
                        Text("\(sp.app)\(sp.title.map { ", title “\($0)”" } ?? "") · \(Int(sp.width * 100)) × \(Int(sp.height * 100)) % · \(sp.position.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Scratchpads are edited in config.yaml (see the examples there).")
            }
            Section {
                Button("Edit Scratchpads in config.yaml") { Config.openInEditor() }
            }
        }
    }
}

// MARK: - key recorder

/// Click, then press a key combination. Kachel's own hotkeys are paused while
/// recording, or they would catch the keys first.
struct KeyRecorder: NSViewRepresentable {
    var chord: KeyChord?
    var onRecord: (KeyChord) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.onRecord = onRecord
        b.chord = chord
        return b
    }

    func updateNSView(_ b: RecorderButton, context: Context) {
        b.onRecord = onRecord
        b.chord = chord
    }
}

final class RecorderButton: NSButton {
    var onRecord: ((KeyChord) -> Void)?
    var chord: KeyChord? { didSet { if !recording { refresh() } } }
    private var recording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(start)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    private func refresh() {
        title = recording ? "Type keys…" : (chord.map(ShortcutList.glyphs) ?? "Record")
    }

    @objc private func start() {
        recording = true
        refresh()
        HotKeys.shared.unbindAll()
        window?.makeFirstResponder(self)
    }

    private func stop() {
        recording = false
        refresh()
        WindowManager.shared.reload()          // hotkeys back
    }

    override func keyDown(with e: NSEvent) {
        guard recording else { return super.keyDown(with: e) }
        if e.keyCode == 53 { stop(); return }          // esc cancels
        var mods: Set<Modifier> = []
        if e.modifierFlags.contains(.command) { mods.insert(.cmd) }
        if e.modifierFlags.contains(.option) { mods.insert(.alt) }
        if e.modifierFlags.contains(.control) { mods.insert(.ctrl) }
        if e.modifierFlags.contains(.shift) { mods.insert(.shift) }
        guard !mods.isEmpty, let key = KeyCodes.name(for: e) else { NSSound.beep(); return }
        let c = KeyChord(modifiers: mods, key: key)
        stop()
        chord = c
        onRecord?(c)
    }

    override func resignFirstResponder() -> Bool {
        if recording { stop() }
        return super.resignFirstResponder()
    }
}

// MARK: - helpers

/// How a command is written in config.yaml.
func commandText(_ c: Command) -> String { c.configText }

/// `mod-shift-j` when the chord includes the modifier, else explicit.
func chordText(_ c: KeyChord, mod: Set<Modifier>) -> String {
    let order: [Modifier] = [.ctrl, .alt, .shift, .cmd]
    if mod.isSubset(of: c.modifiers) {
        let rest = order.filter { c.modifiers.contains($0) && !mod.contains($0) }.map { $0 == .alt ? "alt" : $0.rawValue }
        return (["mod"] + rest + [c.key]).joined(separator: "-")
    }
    return (order.filter(c.modifiers.contains).map(\.rawValue) + [c.key]).joined(separator: "-")
}

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
