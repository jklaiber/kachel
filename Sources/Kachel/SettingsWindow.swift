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

    // MARK: undo / redo (versions of config.yaml's text)

    @Published var canUndo = false
    @Published var canRedo = false
    private var undoStack: [String] = []
    private var redoStack: [String] = []

    private func fileText() -> String? { try? String(contentsOf: Config.url, encoding: .utf8) }

    /// Apply a text edit; remember why it failed if it did, and keep the
    /// previous version for undo.
    func edit(_ transform: (String) -> String) {
        let before = fileText()
        lastSaveError = Config.edit(transform)
        remember(before)
        reload()
    }

    /// For changes made by other code that writes the file itself.
    func editExternally(_ change: () -> Void) {
        let before = fileText()
        change()
        remember(before)
        reload()
    }

    private func remember(_ before: String?) {
        guard lastSaveError == nil, let before, fileText() != before else { return }
        undoStack.append(before)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        canUndo = true; canRedo = false
    }

    func undo() {
        guard let prev = undoStack.popLast(), let now = fileText() else { return }
        redoStack.append(now)
        restore(prev)
    }

    func redo() {
        guard let next = redoStack.popLast(), let now = fileText() else { return }
        undoStack.append(now)
        restore(next)
    }

    private func restore(_ text: String) {
        try? text.write(to: Config.url, atomically: true, encoding: .utf8)
        WindowManager.shared.reload()
        canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty
        lastSaveError = nil
        reload()
    }

    // MARK: binding keys, with a warning when they're taken

    struct PendingKey { var title: String; var message: String; var apply: () -> Void }
    @Published var pendingKey: PendingKey?

    /// Bind `chord` to `command` (replacing the binding `replacing`, if any).
    /// If Kachel, macOS or skhd already uses the keys, ask first.
    func assign(_ chord: KeyChord, command: String, replacing old: KeyChord?) {
        let apply = { [self] in
            edit { t in
                var t = t
                if let old, old != chord { t = KSettings.setKey(t, chord: old, chordText: "", command: nil, mod: s.mod) }
                return KSettings.setKey(t, chord: chord, chordText: chordText(chord, mod: s.mod), command: command, mod: s.mod)
            }
        }
        if let conflict = KeyUse.conflict(for: chord, ignoring: old, keys: s.keys) {
            pendingKey = PendingKey(title: "\(ShortcutList.glyphs(chord)) is already used",
                                    message: conflict + "\n\nUse it for Kachel anyway?", apply: apply)
        } else {
            apply()
        }
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
                ToolbarItemGroup {
                    Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command).help("Undo the last change")
                    Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                        .disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo")
                    Button { Config.openInEditor() } label: { Label("Open config.yaml", systemImage: "doc.text") }
                        .help("Open config.yaml in your editor")
                }
            }
            .alert(model.pendingKey?.title ?? "", isPresented: Binding(get: { model.pendingKey != nil },
                                                                     set: { if !$0 { model.pendingKey = nil } })) {
                Button("Use Anyway") { model.pendingKey?.apply(); model.pendingKey = nil }
                Button("Cancel", role: .cancel) { model.pendingKey = nil }
            } message: {
                Text(model.pendingKey?.message ?? "")
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
                LabeledContent("Version") {
                    HStack {
                        Text(AppVersion.string).textSelection(.enabled)
                        Button("About Kachel") { AppVersion.showAbout() }
                    }
                }
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
                        if on != m.s.bar.shows(w) { m.editExternally { Config.toggleWidget(w); WindowManager.shared.reload() } }
                    }))
                }
                Toggle("Hide empty workspaces", isOn: m.binding({ $0.bar.hideEmptyWorkspaces }, {
                    m.nested("bar", "hide-empty-workspaces", SettingsModel.yaml($0))
                }))
                Picker("Update CPU, memory and network", selection: m.binding({ $0.bar.interval }, {
                    m.nested("bar", "interval", SettingsModel.yaml($0))
                })) {
                    ForEach(intervals(including: m.s.bar.interval), id: \.self) { s in
                        Text(s == 1 ? "Every second" : "Every \(SettingsModel.yaml(s)) seconds").tag(s)
                    }
                }
                .disabled(![BarWidget.cpu, .memory, .network].contains(where: m.s.bar.shows))
            }
            Section {
                Picker("Show", selection: m.binding({ $0.bar.windows }, { m.nested("bar", "windows", $0.rawValue) })) {
                    Text("Off").tag(BarSettings.WindowsStyle.off)
                    Text("Position").tag(BarSettings.WindowsStyle.position)
                    Text("Dots").tag(BarSettings.WindowsStyle.dots)
                    Text("Tabs").tag(BarSettings.WindowsStyle.tabs)
                }
                .pickerStyle(.segmented)
                Toggle("Only in the Full layout", isOn: m.binding({ $0.bar.windowsFullOnly }, {
                    m.nested("bar", "windows-full-only", SettingsModel.yaml($0))
                }))
                .disabled(m.s.bar.windows == .off)
                Toggle("Window count on each workspace", isOn: m.binding({ $0.bar.workspaceCounts }, {
                    m.nested("bar", "workspace-counts", SettingsModel.yaml($0))
                }))
                BarPreview(settings: m.s.bar)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            } header: {
                Text("Windows on This Workspace")
            } footer: {
                Text(windowsHelp(m.s.bar.windows)).font(.caption).foregroundStyle(.secondary)
            }
            Section("Date and Time") {
                TextField("Date format", text: $date).onSubmit { m.nested("bar", "date-format", KSettings.yamlScalar(date)) }
                TextField("Clock format", text: $clock).onSubmit { m.nested("bar", "clock-format", KSettings.yamlScalar(clock)) }
                Text("Unicode patterns, e.g. EEE d MMM or HH:mm:ss. Press Return to apply.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { date = m.s.bar.dateFormat; clock = m.s.bar.clockFormat }
    }

    private func windowsHelp(_ style: BarSettings.WindowsStyle) -> String {
        switch style {
        case .off: return "Only the focused window's title."
        case .position: return "Which window you're on and how many there are, next to the layout."
        case .dots: return "One dot per window, the focused one filled."
        case .tabs: return "Every window's name; the focused one is highlighted. Click a tab to switch to that window."
        }
    }

    /// The usual choices, plus whatever config.yaml has if it's something else.
    private func intervals(including current: Double) -> [Double] {
        Set([1, 2, 5, 10, 30, current]).sorted()
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
                swipeRow("Swipe left", "swipe-left", m.s.gestures.left)
                swipeRow("Swipe right", "swipe-right", m.s.gestures.right)
                swipeRow("Swipe up", "swipe-up", m.s.gestures.up)
                swipeRow("Swipe down", "swipe-down", m.s.gestures.down)
            }
        }
    }

    private func swipeRow(_ label: String, _ key: String, _ cmd: Command?) -> some View {
        LabeledContent(label) {
            CommandPicker(value: cmd, allowNone: true, settings: m.s) { m.nested("gestures", key, $0?.configText ?? "~") }
        }
    }
}

struct ShortcutsPane: View {
    @ObservedObject var m: SettingsModel
    @State private var newCommand: Command?

    var rows: [(chord: KeyChord, command: Command)] {
        m.s.keys.map { ($0.key, $0.value) }.sorted {
            let a = ShortcutList.describe($0.command), b = ShortcutList.describe($1.command)
            return (ShortcutList.order.firstIndex(of: a.group) ?? 9, a.label, $0.chord.description)
                < (ShortcutList.order.firstIndex(of: b.group) ?? 9, b.label, $1.chord.description)
        }
    }

    var body: some View {
        Form {
            Section("Add a Shortcut") {
                HStack {
                    CommandPicker(value: newCommand, settings: m.s) { newCommand = $0 }
                    Spacer()
                    KeyRecorder(chord: nil) { chord in
                        guard let cmd = newCommand else { NSSound.beep(); return }
                        m.assign(chord, command: cmd.configText, replacing: nil)
                        newCommand = nil
                    }
                    .frame(width: 130)
                }
                Text("Choose what it should do, then click Record and press the keys.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(ShortcutList.order, id: \.self) { group in
                let inGroup = rows.filter { ShortcutList.describe($0.command).group == group }
                if !inGroup.isEmpty {
                    Section(group) {
                        ForEach(inGroup, id: \.chord) { row in
                            HStack {
                                KeyRecorder(chord: row.chord) { new in
                                    guard new != row.chord else { return }
                                    m.assign(new, command: row.command.configText, replacing: row.chord)
                                }
                                .frame(width: 130)
                                CommandPicker(value: row.command, settings: m.s) { new in
                                    guard let new else { return }
                                    m.edit { KSettings.setKey($0, chord: row.chord, chordText: chordText(row.chord, mod: m.s.mod),
                                                              command: new.configText, mod: m.s.mod) }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    m.edit { KSettings.setKey($0, chord: row.chord, chordText: "", command: nil, mod: m.s.mod) }
                                } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove this shortcut")
                            }
                        }
                    }
                }
            }
        }
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
                ForEach(Array(m.s.rules.enumerated()), id: \.offset) { i, rule in
                    RuleRow(m: m, index: i, rule: rule)
                        // Fresh text field state when the rule at this position changes.
                        .id("\(i)|\(rule.app)|\(rule.title ?? "")|\(rule.titleNot)")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("**Window title contains**: only windows whose title contains this text. Empty: every window of the app.")
                    Text("**But not if it contains**: leaves out windows whose title contains one of these (separate with commas). For every Teams meeting, whatever it's called: leave the first field empty and put “Microsoft Teams, teams.microsoft.com” here, the titles of Teams' main window.")
                    Text("**Workspace**: new windows of the app open there, and you stay where you are.")
                    Text("**Float**: the window isn't tiled. It keeps its own size and position, above the tiled windows.")
                    Text("**Minimize**: while its workspace is out of sight, the window is minimized instead of moved into a corner. Teams, Zoom and Webex then show their small call window, and clicking it takes you back.")
                    Text("The first rule that matches a window counts, so put rules with a title above the app's other rules.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Menu("Add a Rule for…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            guard let id = app.bundleIdentifier else { return }
                            m.edit { KSettings.addRule($0, Rule(app: id), comment: app.localizedName) }
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
}

/// One rule: which windows (app, title) and what happens to them.
private struct RuleRow: View {
    @ObservedObject var m: SettingsModel
    let index: Int
    let rule: Rule
    @State private var title = ""
    @State private var titleNot = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.appName(rule.app)).fontWeight(.medium)
                Text(rule.app).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    m.edit { KSettings.setRule($0, at: index, rule: nil) }
                } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove this rule")
            }
            TextField("Window title contains", text: $title, prompt: Text("Any window"))
                .onSubmit { saveTitle() }
            TextField("But not if it contains", text: $titleNot, prompt: Text("Microsoft Teams, teams.microsoft.com"))
                .onSubmit { saveTitle() }
            HStack {
                Picker("Workspace", selection: Binding(get: { rule.workspace ?? "" }, set: { ws in
                    update { $0.workspace = ws.isEmpty ? nil : ws }
                })) {
                    Text("Any").tag("")
                    ForEach(m.s.workspaces, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 170)
                Spacer()
                Toggle("Float", isOn: Binding(get: { rule.float }, set: { on in update { $0.float = on } }))
                Toggle("Minimize", isOn: Binding(get: { rule.hide == .minimize }, set: { on in update { $0.hide = on ? .minimize : .park } }))
            }
        }
        .padding(.vertical, 4)
        .onAppear { title = rule.title ?? ""; titleNot = rule.titleNot.joined(separator: ", ") }
        .onDisappear { saveTitle() }
    }

    private func update(_ change: (inout Rule) -> Void) {
        // Only if this position still holds the rule we show (not after a removal).
        guard m.s.rules.indices.contains(index), m.s.rules[index] == rule else { return }
        var r = rule
        if title != (rule.title ?? "") { r.title = title.isEmpty ? nil : title }   // a typed, unsaved title
        if Self.list(titleNot) != rule.titleNot { r.titleNot = Self.list(titleNot) }
        change(&r)
        guard r != rule else { return }
        m.edit { KSettings.setRule($0, at: index, rule: r) }
    }

    private func saveTitle() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let not = Self.list(titleNot)
        guard t != (rule.title ?? "") || not != rule.titleNot else { return }
        update { $0.title = t.isEmpty ? nil : t; $0.titleNot = not }
    }

    /// "a, b" → ["a", "b"]
    static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func appName(_ id: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
    }
}

struct ScratchpadsPane: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        Form {
            ForEach(Array(m.s.scratchpads.enumerated()), id: \.element.name) { i, pad in
                ScratchpadEditor(m: m, pad: pad, index: i)
            }
            Section {
                Button {
                    var pad = Scratchpad(name: uniqueName(), app: "")
                    if let w = WindowManager.shared.focusedWindowInfo() { pad.app = w.app; pad.title = w.title.isEmpty ? nil : w.title }
                    if pad.app.isEmpty { pad.app = "com.apple.TextEdit" }
                    m.edit { KSettings.setScratchpads($0, m.s.scratchpads + [pad]) }
                } label: { Label("Add a Scratchpad", systemImage: "plus") }
                Text("A new scratchpad starts with the window you last used. Give it a key, and a run command so Kachel can start it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func uniqueName() -> String {
        let names = Set(m.s.scratchpads.map(\.name))
        return (1...).lazy.map { $0 == 1 ? "pad" : "pad\($0)" }.first { !names.contains($0) }!
    }
}

/// One scratchpad's settings. Text fields apply on Return; the rest at once.
struct ScratchpadEditor: View {
    @ObservedObject var m: SettingsModel
    var pad: Scratchpad
    var index: Int
    @State private var name = ""
    @State private var app = ""
    @State private var title = ""
    @State private var run = ""

    var body: some View {
        Section {
            TextField("Name", text: $name).onSubmit { rename() }
            HStack {
                TextField("App", text: $app, prompt: Text("bundle ID or app name")).onSubmit { save { $0.app = app } }
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { a in
                        Button(a.localizedName ?? a.bundleIdentifier ?? "?") { app = a.bundleIdentifier ?? ""; save { $0.app = app } }
                    }
                } label: { Image(systemName: "app.badge") }.menuStyle(.borderlessButton).fixedSize().help("Choose a running app")
            }
            TextField("Window title contains", text: $title, prompt: Text("optional")).onSubmit {
                save { $0.title = title.isEmpty ? nil : title }
            }
            TextField("Start with", text: $run, prompt: Text("shell command, e.g. open -a Notes")).onSubmit {
                save { $0.run = run.isEmpty ? nil : run }
            }
            Button("Take App and Title from the Focused Window") {
                guard let w = WindowManager.shared.focusedWindowInfo() else { NSSound.beep(); return }
                app = w.app; title = w.title
                save { $0.app = w.app; $0.title = w.title.isEmpty ? nil : w.title }
            }
            Slider(value: Binding(get: { pad.width }, set: { v in save { $0.width = (v * 20).rounded() / 20 } }), in: 0.2...1) {
                Text("Width: \(Int(pad.width * 100)) %")
            }
            Slider(value: Binding(get: { pad.height }, set: { v in save { $0.height = (v * 20).rounded() / 20 } }), in: 0.2...1) {
                Text("Height: \(Int(pad.height * 100)) %")
            }
            Picker("Position", selection: Binding(get: { pad.position }, set: { v in save { $0.position = v } })) {
                Text("Centred").tag(Scratchpad.Position.center)
                Text("At the top, like a drop-down").tag(Scratchpad.Position.top)
            }
            HStack {
                Text("Shortcut")
                Spacer()
                KeyRecorder(chord: key) { chord in m.assign(chord, command: "scratchpad \(pad.name)", replacing: key) }
                    .frame(width: 130)
            }
        } header: {
            HStack {
                Text(pad.name)
                Spacer()
                Button(role: .destructive) { delete() } label: { Label("Remove", systemImage: "trash") }
                    .buttonStyle(.borderless).labelStyle(.iconOnly).help("Remove this scratchpad")
            }
        }
        .onAppear { name = pad.name; app = pad.app; title = pad.title ?? ""; run = pad.run ?? "" }
    }

    private var key: KeyChord? { m.s.keys.first { $0.value == .scratchpad(pad.name) }?.key }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func save(_ change: (inout Scratchpad) -> Void) {
        var list = m.s.scratchpads
        guard list.indices.contains(index) else { return }
        change(&list[index])
        guard !list[index].app.isEmpty else { return }
        m.edit { KSettings.setScratchpads($0, list) }
    }

    /// Renaming also updates the keys and swipes that call it.
    private func rename() {
        let new = name.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, !new.contains(" "), new != pad.name else { name = pad.name; return }
        var list = m.s.scratchpads
        list[index].name = new
        let old = pad.name, s = m.s
        m.edit { t in
            var t = KSettings.setScratchpads(t, list)
            for (chord, cmd) in s.keys where cmd == .scratchpad(old) {
                t = KSettings.setKey(t, chord: chord, chordText: chordText(chord, mod: s.mod), command: "scratchpad \(new)", mod: s.mod)
            }
            for (k, c) in [("swipe-left", s.gestures.left), ("swipe-right", s.gestures.right),
                           ("swipe-up", s.gestures.up), ("swipe-down", s.gestures.down)] where c == .scratchpad(old) {
                t = KSettings.setNested(t, section: "gestures", key: k, value: "scratchpad \(new)")
            }
            return t
        }
    }

    /// Removing also removes the keys and swipes that call it.
    private func delete() {
        let s = m.s, old = pad.name
        m.edit { t in
            var t = t
            for (chord, cmd) in s.keys where cmd == .scratchpad(old) {
                t = KSettings.setKey(t, chord: chord, chordText: "", command: nil, mod: s.mod)
            }
            for (k, c) in [("swipe-left", s.gestures.left), ("swipe-right", s.gestures.right),
                           ("swipe-up", s.gestures.up), ("swipe-down", s.gestures.down)] where c == .scratchpad(old) {
                t = KSettings.setNested(t, section: "gestures", key: k, value: "~")
            }
            return KSettings.setScratchpads(t, s.scratchpads.filter { $0.name != old })
        }
    }
}

// MARK: - command picker

/// Choose a command from menus instead of typing it: grouped like the
/// shortcut overview, with submenus for workspaces, directions, displays and
/// scratchpads, and a field for shell commands.
struct CommandPicker: View {
    var value: Command?
    var allowNone = false
    var settings: KSettings
    var onPick: (Command?) -> Void
    @State private var askSpawn = false
    @State private var spawnText = ""

    var body: some View {
        HStack {
            Menu(label) {
                Section("Workspaces") {
                    numbered("Show workspace") { .greedyView($0) }
                    numbered("Go to workspace (W.view)") { .view($0) }
                    numbered("Move window to workspace") { .shift($0) }
                    item(.workspaceBack); item(.workspaceNext); item(.workspacePrev); item(.shiftNext); item(.shiftPrev)
                }
                Section("Windows") {
                    item(.focusDown); item(.focusUp); item(.focusMaster)
                    item(.swapDown); item(.swapUp); item(.swapMaster)
                    directions("Focus window") { .focusDirection($0) }
                    directions("Swap with window") { .swapDirection($0) }
                    item(.toggleFloat); item(.close)
                }
                Section("Layout") {
                    item(.nextLayout); item(.toggleFullscreen); item(.shrink); item(.expand)
                    item(.incMaster); item(.decMaster); item(.taller); item(.shorter); item(.resetSizes)
                }
                Section("Displays") {
                    Menu("Focus display") { ForEach(0..<3) { i in Button("Display \(i + 1) from the left") { onPick(.focusScreen(i)) } } }
                    Menu("Move window to display") { ForEach(0..<3) { i in Button("Display \(i + 1) from the left") { onPick(.shiftToScreen(i)) } } }
                    item(.focusNextScreen); item(.focusPrevScreen); item(.shiftToNextScreen); item(.shiftToPrevScreen)
                }
                Section("Tools") {
                    item(.windowSearch); item(.appRule)
                    if !settings.scratchpads.isEmpty {
                        Menu("Scratchpad") { ForEach(settings.scratchpads, id: \.name) { p in Button(p.name) { onPick(.scratchpad(p.name)) } } }
                    }
                    item(.terminal)
                    Button("Run a Shell Command…") {
                        if case .spawn(let c) = value { spawnText = c }
                        askSpawn = true
                    }
                    item(.shortcuts); item(.settings); item(.welcome)
                    item(.refresh); item(.reload); item(.restart); item(.quit)
                }
                if allowNone {
                    Divider()
                    Button("Nothing") { onPick(nil) }
                }
            }
            .fixedSize()
            if askSpawn || isSpawn {
                TextField("Shell command", text: $spawnText, prompt: Text("e.g. open -a Safari"))
                    .onSubmit {
                        let c = spawnText.trimmingCharacters(in: .whitespaces)
                        if !c.isEmpty { onPick(.spawn(c)) }
                        askSpawn = false
                    }
                    .frame(minWidth: 180)
            }
        }
        .onAppear { if case .spawn(let c) = value { spawnText = c } }
    }

    private var isSpawn: Bool { if case .spawn = value { return true } else { return false } }

    private var label: String {
        guard let value else { return allowNone ? "Nothing" : "Choose a Command" }
        if case .spawn = value { return "Run a Shell Command" }
        return ShortcutList.describe(value).label
    }

    private func item(_ c: Command) -> some View {
        Button(ShortcutList.describe(c).label) { onPick(c) }
    }

    private func numbered(_ title: String, _ make: @escaping (Int) -> Command) -> some View {
        Menu(title) {
            ForEach(Array(settings.workspaces.enumerated()), id: \.offset) { i, tag in
                Button("Workspace \(tag)") { onPick(make(i)) }
            }
        }
    }

    private func directions(_ title: String, _ make: @escaping (Direction) -> Command) -> some View {
        Menu(title) {
            ForEach(Direction.allCases, id: \.self) { d in Button(d.rawValue.capitalized) { onPick(make(d)) } }
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


/// The bar as it would look with these settings, drawn by the bar itself with
/// made-up windows: workspace 2 in Full, Safari focused, the second of four.
private struct BarPreview: NSViewRepresentable {
    let settings: BarSettings

    func makeNSView(context: Context) -> PreviewHost { PreviewHost() }
    func updateNSView(_ v: PreviewHost, context: Context) {
        var s = settings
        s.left = [.workspaces, .layout, .title]
        s.right = []
        s.hideEmptyWorkspaces = false
        v.settings = s
    }

    final class PreviewHost: NSView {
        var settings = BarSettings() { didSet { needsLayout = true } }

        override func layout() {
            super.layout()
            subviews.forEach { $0.removeFromSuperview() }
            var c = Bar.Content()
            c.isCurrentScreen = true
            c.isFullLayout = true
            c.layout = "Full"
            c.title = "Safari"
            let counts = [3, 4, 0, 1, 0]
            c.tags = counts.enumerated().map { i, n in
                Bar.Tag(name: "\(i + 1)", active: i == 1, visible: i == 1, hasWindows: n > 0, count: n)
            }
            c.windows = ["Claude", "Safari", "Notes", "Terminal"].enumerated().map { i, t in
                Bar.Window(id: UInt32(i + 1), title: t, focused: i == 1)
            }
            let v = Bar.demoView(width: bounds.width, height: bounds.height, settings: settings, content: c,
                                 now: Date(), cpu: 0, memory: 0, down: 0, up: 0)
            addSubview(v)
        }
    }
}
