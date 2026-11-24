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
        NSApp.activate()
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
                } else if !model.s.warnings.isEmpty {
                    // Ignored settings (typos, or from a newer Kachel): the rest applies.
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(model.s.warnings, id: \.self) { Text($0).font(.callout) }
                            Text("Everything else in config.yaml applies.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit Config…") { Config.openInEditor() }.controlSize(.small)
                    }
                    .padding(10).background(Color.secondary.opacity(0.1))
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
    @State private var pinsOpen = NSScreen.screens.count > 1
    @State private var layoutsOpen = false

    static let mods: [(String, String)] = [("alt", "⌥ Option"), ("ctrl+alt", "⌃⌥ Control-Option"),
                                           ("alt+cmd", "⌥⌘ Option-Command"), ("ctrl+cmd", "⌃⌘ Control-Command")]

    var body: some View {
        Form {
            Section("Keyboard") {
                Picker("Modifier (mod)", selection: m.binding({ modName($0.mod) }, { name in
                    // Keep "left only" / "right only" when the modifier changes.
                    let mods = (try? KSettings.parseMod(name).0) ?? m.s.mod
                    let side = m.s.modSides.values.first
                    m.top("mod", KSettings.modText(mods, sides: side.map { s in Dictionary(uniqueKeysWithValues: mods.map { ($0, s) }) } ?? [:]))
                })) {
                    ForEach(Self.mods, id: \.0) { Text($0.1).tag($0.0) }
                    if !Self.mods.contains(where: { $0.0 == modName(m.s.mod) }) {
                        Text(ShortcutList.glyphs(m.s.mod)).tag(modName(m.s.mod))
                    }
                }
                Picker(selection: m.binding({ $0.modSides.values.first?.rawValue ?? "both" }, { side in
                    let s = ModifierSide(rawValue: side)
                    m.top("mod", KSettings.modText(m.s.mod, sides: s.map { s in Dictionary(uniqueKeysWithValues: m.s.mod.map { ($0, s) }) } ?? [:]))
                })) {
                    Text("Both sides").tag("both")
                    Text("Left keys only").tag("left")
                    Text("Right keys only").tag("right")
                } label: {
                    Text("Which keys")
                    Text("Left only leaves the right \(ShortcutList.glyphs(m.s.mod)) free for typing, e.g. for a keyboard layout that uses it.")
                }
                Slider(value: m.binding({ $0.shortcutOverview }, { m.top("shortcut-overview", SettingsModel.yaml(($0 * 10).rounded() / 10)) }),
                       in: 0...2, step: 0.1) {
                    Text(m.s.shortcutOverview == 0 ? "Shortcut overview: off"
                         : "Shortcut overview after holding mod: \(SettingsModel.yaml(m.s.shortcutOverview)) s")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("2 s") }
            }
            Section("Workspaces") {
                TextField("Names", text: $workspacesText, prompt: Text("1 2 3 4 5 6 7 8 9"))
                    .commitOnLeave {
                        let names = workspacesText.split(separator: " ").map(String.init)
                        if !names.isEmpty, names != m.s.workspaces { m.top("workspaces", KSettings.flowList(names)) }
                    }
                Text("Separated by spaces.").font(.caption).foregroundStyle(.secondary)
                Toggle("Go along when you move a window to another workspace",
                       isOn: m.binding({ $0.followMovedWindows }, { m.top("follow-moved-windows", SettingsModel.yaml($0)) }))
                Picker(selection: m.binding({ $0.followFocusScreen }, { m.top("follow-focus-screen", $0.rawValue) })) {
                    Text("On this display").tag(KSettings.FollowFocusScreen.current)
                    Text("On the display it was last on").tag(KSettings.FollowFocusScreen.last)
                } label: {
                    Text("A window on a hidden workspace gets focus")
                    Text("A link opens in it, ⌘Tab, the Dock: where its workspace shows up.")
                }
                Toggle("The key of the current workspace goes back to the previous one",
                       isOn: m.binding({ $0.workspaceBackAndForth }, { m.top("workspace-back-and-forth", SettingsModel.yaml($0)) }))
                DisclosureGroup("Pin workspaces to displays", isExpanded: $pinsOpen) {
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
                DisclosureGroup("Starting layout per workspace", isExpanded: $layoutsOpen) {
                    ForEach(Array(m.s.workspaces.enumerated()), id: \.element) { i, tag in
                        Picker("Workspace \(tag) starts with", selection: m.binding({ $0.configuredLayout(forWorkspace: i)?.configName ?? "" },
                                                                                   { startLayout(tag, $0) })) {
                            Text("The layout it had").tag("")
                            ForEach(m.s.layouts, id: \.self) { Text($0.rawValue).tag($0.configName) }
                        }
                    }
                    Text("Applies when Kachel starts and right after you change it here. Only layouts from Layouts below.")
                        .font(.caption).foregroundStyle(.secondary)
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
            Section("Tiling") {
                Stepper(value: m.binding({ $0.gap }, { m.top("gap", SettingsModel.yaml($0)) }), in: 0...40) {
                    Text("Gap between windows: \(Int(m.s.gap)) pt")
                }
                Toggle("Same space at the screen edges", isOn: m.binding({ $0.padding == nil }, {
                    m.top("padding", $0 ? "auto" : SettingsModel.yaml(m.s.gap))
                }))
                if let p = m.s.padding {
                    Stepper(value: m.binding({ _ in p }, { m.top("padding", SettingsModel.yaml($0)) }), in: 0...80) {
                        Text("Space at the screen edges: \(Int(p)) pt")
                    }
                }
                Toggle("Space at the edges on the built-in display", isOn: m.binding({ $0.builtinPadding }, {
                    m.top("builtin-display-padding", SettingsModel.yaml($0))
                }))
                Toggle("No gaps when a window is alone on its display", isOn: m.binding({ $0.smartGaps }, {
                    m.top("smart-gaps", SettingsModel.yaml($0))
                }))
                Slider(value: m.binding({ $0.ratio }, { m.top("ratio", SettingsModel.yaml(($0 * 100).rounded() / 100)) }), in: 0.2...0.8) {
                    Text("Master size for new workspaces: \(Int(m.s.ratio * 100)) %")
                }
                Stepper(value: m.binding({ $0.windowLimit }, { m.top("window-limit", String($0)) }), in: 0...20) {
                    Text(m.s.windowLimit == 0 ? "Tiled windows per workspace: no limit"
                         : "Tile at most \(m.s.windowLimit) windows per workspace; others float")
                }
            }
            Section {
                ForEach(KSettings.layoutOrder, id: \.self) { kind in
                    Toggle(kind.rawValue, isOn: m.binding({ $0.layouts.contains(kind) }, { on in
                        var l = m.s.layouts.filter { $0 != kind }
                        if on { l = KSettings.layoutOrder.filter { l.contains($0) || $0 == kind } }
                        if !l.isEmpty { m.top("layouts", KSettings.flowList(l.map(\.configName))) }
                    }))
                    .disabled(m.s.layouts == [kind])   // at least one stays
                }
            } header: {
                Text("Layouts")
            } footer: {
                Text("Next layout\(nextLayoutKey.map { " (\($0))" } ?? "") goes through these, in this order.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Mouse") {
                Picker("Pointer follows focus", selection: m.binding({ $0.mouseFollowsFocus }, { m.top("mouse-follows-focus", $0.rawValue) })) {
                    Text("To the focused window").tag(KSettings.MouseFollows.window)
                    Text("Only between displays").tag(KSettings.MouseFollows.screen)
                    Text("Never").tag(KSettings.MouseFollows.off)
                }
                Toggle("Focus follows the pointer", isOn: m.binding({ $0.focusFollowsMouse }, { m.top("focus-follows-mouse", SettingsModel.yaml($0)) }))
            }
            Section("Kachel") {
                Toggle("Start at login", isOn: m.binding({ $0.startAtLogin }, { m.top("start-at-login", SettingsModel.yaml($0)) }))
                Toggle("Icon in the menu bar", isOn: m.binding({ $0.menubarIcon }, { m.top("menubar-icon", SettingsModel.yaml($0)) }))
                TextField("Terminal command", text: $terminalText).commitOnLeave {
                    if !terminalText.isEmpty, terminalText != m.s.terminal { m.top("terminal", KSettings.yamlScalar(terminalText)) }
                }
                Toggle(isOn: m.binding({ $0.checkForUpdates }, { m.top("check-for-updates", SettingsModel.yaml($0)) })) {
                    Text("Check for updates")
                    Text("Once a day, Kachel looks up the latest release on GitHub. A newer one shows up in the menu.")
                }
                LabeledContent("Version") {
                    HStack {
                        Text(AppVersion.string).textSelection(.enabled)
                        if let r = UpdateCheck.shared.available {
                            Button("\(r.version.description) available…") { UpdateCheck.shared.showDetails() }
                        }
                        Button("About Kachel") { AppVersion.showAbout() }
                    }
                }
            }
        }
        .onAppear {
            workspacesText = m.s.workspaces.joined(separator: " "); terminalText = m.s.terminal
            if !m.s.workspaceScreens.isEmpty { pinsOpen = true }
            if !m.s.workspaceLayouts.isEmpty { layoutsOpen = true }
        }
    }

    /// The key for next-layout, e.g. ⌥⇧Space.
    private var nextLayoutKey: String? {
        m.s.keys.first { $0.value == .nextLayout }.map { ShortcutList.glyphs($0.key) }
    }

    private func modName(_ mods: Set<Modifier>) -> String {
        [Modifier.ctrl, .alt, .cmd, .shift].filter(mods.contains).map { $0 == .ctrl ? "ctrl" : $0.rawValue }.joined(separator: "+")
    }

    /// workspace-layouts, keyed by the workspace's name (numbers stay numbers).
    private func startLayout(_ tag: String, _ name: String) {
        var map = m.s.workspaceLayouts.mapValues(\.configName)
        // An entry by number for this workspace would win over the new one: drop it.
        if let i = m.s.workspaces.firstIndex(of: tag) { map["\(i + 1)"] = nil }
        map[tag] = name.isEmpty ? nil : name
        let flow = map.isEmpty ? "{}" : "{" + map.sorted { $0.key < $1.key }
            .map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", ") + "}"
        m.top("workspace-layouts", flow)
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

    private static let stats: Set<BarWidget> = [.cpu, .memory, .network]

    var body: some View {
        Form {
            Section("Appearance") {
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
                Toggle(isOn: m.binding({ $0.bar.makeWayForDock }, { m.nested("bar", "make-way-for-dock", SettingsModel.yaml($0)) })) {
                    Text("Make way for the Dock")
                    Text("When a hidden Dock slides up, the bar fades out until it's gone again.")
                }
            }
            side("Left Side", key: "left", m.s.bar.left)
            side("Right Side", key: "right", m.s.bar.right)
            let hidden = BarWidget.allCases.filter { !m.s.bar.shows($0) }
            if !hidden.isEmpty {
                Section {
                    ForEach(hidden, id: \.self) { w in row(w) }
                } header: {
                    Text("Not in the Bar")
                }
            }
        }
        .onAppear { date = m.s.bar.dateFormat; clock = m.s.bar.clockFormat }
    }

    /// One side of the bar: its widgets in order, each with its options beneath.
    @ViewBuilder private func side(_ title: String, key: String, _ list: [BarWidget]) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list, id: \.self) { w in
                    row(w, side: key, list: list)
                    options(w, lastStats: list.last(where: Self.stats.contains) == w)
                }
            } header: {
                Text(title)
            } footer: {
                if key == "right" {
                    Text("Drag a widget by its grip to move it, also to the other side.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ w: BarWidget, side: String? = nil, list: [BarWidget] = []) -> some View {
        HStack {
            if side != nil {
                // The grip: drag the row to move the widget, within its side or across.
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help("Drag to move")
            }
            Image(systemName: Self.icon(w)).foregroundStyle(.secondary).frame(width: 20)
            Text(w.menuTitle)
            Spacer()
            Toggle(w.menuTitle, isOn: m.binding({ $0.bar.shows(w) }, { on in
                if on != m.s.bar.shows(w) { m.editExternally { Config.toggleWidget(w); WindowManager.shared.reload() } }
            }))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onDrag {
            guard side != nil else { return NSItemProvider() }
            return NSItemProvider(object: w.rawValue as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard let side, let p = providers.first else { return false }
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let raw = obj as? String, let dragged = BarWidget(rawValue: raw) else { return }
                DispatchQueue.main.async { place(dragged, onto: w, side: side) }
            }
            return true
        }
        .contextMenu {
            if let side, let i = list.firstIndex(of: w) {
                Button("Move Up") { move(w, in: side, list, to: i - 1) }.disabled(i == 0)
                Button("Move Down") { move(w, in: side, list, to: i + 1) }.disabled(i == list.count - 1)
                Button(side == "left" ? "Move to the Right Side" : "Move to the Left Side") { moveAcross(w, from: side) }
            }
        }
    }

    /// A widget's own options, indented under it, while it's in the bar.
    @ViewBuilder private func options(_ w: BarWidget, lastStats: Bool) -> some View {
        Group {
            switch w {
            case .workspaces:
                Toggle("Hide empty workspaces", isOn: m.binding({ $0.bar.hideEmptyWorkspaces }, {
                    block("workspaces", "hide-empty", SettingsModel.yaml($0))
                }))
                Toggle("Window count on each workspace", isOn: m.binding({ $0.bar.workspaceCounts }, {
                    block("workspaces", "window-counts", SettingsModel.yaml($0))
                }))
            case .title:
                Picker("Other windows", selection: m.binding({ $0.bar.windows }, { block("title", "windows", $0.rawValue) })) {
                    Text("Off").tag(BarSettings.WindowsStyle.off)
                    Text("Position").tag(BarSettings.WindowsStyle.position)
                    Text("Dots").tag(BarSettings.WindowsStyle.dots)
                    Text("Tabs").tag(BarSettings.WindowsStyle.tabs)
                }
                .pickerStyle(.segmented)
                if m.s.bar.windows != .off {
                    Toggle("Only in the Full layout", isOn: m.binding({ $0.bar.windowsFullOnly }, {
                        block("title", "only-in-full", SettingsModel.yaml($0))
                    }))
                    BarPreview(settings: m.s.bar)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }
                Text(windowsHelp(m.s.bar.windows)).font(.caption).foregroundStyle(.secondary)
            case .cpu, .memory, .network:
                if lastStats {
                    Picker("Update CPU, memory and network", selection: m.binding({ $0.bar.interval }, {
                        block("stats", "interval", SettingsModel.yaml($0))
                    })) {
                        ForEach(intervals(including: m.s.bar.interval), id: \.self) { s in
                            Text(s == 1 ? "Every second" : "Every \(SettingsModel.yaml(s)) seconds").tag(s)
                        }
                    }
                }
            case .battery:
                Toggle("Show percentage", isOn: m.binding({ $0.bar.batteryPercentage }, {
                    block("battery", "percentage", SettingsModel.yaml($0))
                }))
            case .date:
                TextField("Format", text: $date, prompt: Text("EEE d MMM")).commitOnLeave {
                    if !date.isEmpty, date != m.s.bar.dateFormat { block("date", "format", KSettings.yamlScalar(date)) }
                }
            case .clock:
                TextField("Format", text: $clock, prompt: Text("HH:mm")).commitOnLeave {
                    if !clock.isEmpty, clock != m.s.bar.clockFormat { block("clock", "format", KSettings.yamlScalar(clock)) }
                }
            case .layout:
                EmptyView()
            }
        }
        .padding(.leading, 28)
    }

    private func block(_ block: String, _ key: String, _ value: String) {
        m.edit { KSettings.setNested($0, section: "bar", block: block, key: key, value: value) }
    }

    private func move(_ w: BarWidget, in side: String, _ list: [BarWidget], to j: Int) {
        guard let i = list.firstIndex(of: w), list.indices.contains(j) else { return }
        var l = list
        l.swapAt(i, j)
        m.edit { KSettings.setBarList($0, key: side, l) }
    }

    /// Dropped `dragged` on `target`'s row: it takes target's place. Moving
    /// down a side it lands after it, moving up or from the other side before;
    /// dropped on the last row, it goes last.
    private func place(_ dragged: BarWidget, onto target: BarWidget, side: String) {
        guard dragged != target else { return }
        var left = m.s.bar.left, right = m.s.bar.right
        let list = side == "left" ? left : right
        let from = list.firstIndex(of: dragged)
        guard let to = list.firstIndex(of: target) else { return }
        let after = (from.map { $0 < to } ?? false) || to == list.count - 1
        left.removeAll { $0 == dragged }
        right.removeAll { $0 == dragged }
        var dest = side == "left" ? left : right
        guard let t = dest.firstIndex(of: target) else { return }
        dest.insert(dragged, at: after ? t + 1 : t)
        if side == "left" { left = dest } else { right = dest }
        m.edit { KSettings.setBarList(KSettings.setBarList($0, key: "left", left), key: "right", right) }
    }

    private func moveAcross(_ w: BarWidget, from side: String) {
        var left = m.s.bar.left, right = m.s.bar.right
        if side == "left" { left.removeAll { $0 == w }; right.insert(w, at: 0) }
        else { right.removeAll { $0 == w }; left.append(w) }
        m.edit { KSettings.setBarList(KSettings.setBarList($0, key: "left", left), key: "right", right) }
    }

    static func icon(_ w: BarWidget) -> String {
        switch w {
        case .workspaces: return "square.grid.3x3"
        case .layout: return "rectangle.split.2x1"
        case .title: return "macwindow"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "arrow.up.arrow.down"
        case .battery: return "battery.75percent"
        case .date: return "calendar"
        case .clock: return "clock"
        }
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
                Toggle("Feedback on the trackpad", isOn: m.binding({ $0.haptics }, { m.top("haptics", SettingsModel.yaml($0)) }))
                    .help("A light tap when a swipe switches workspaces or a window snaps into place.")
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
                .commitOnLeave { saveTitle() }
            TextField("But not if it contains", text: $titleNot, prompt: Text("Microsoft Teams, teams.microsoft.com"))
                .commitOnLeave { saveTitle() }
            HStack {
                Picker("Workspace", selection: Binding(get: { rule.workspace ?? "" }, set: { ws in
                    update { $0.workspace = ws.isEmpty ? nil : ws }
                })) {
                    Text("Any").tag("")
                    ForEach(m.s.workspaces, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 170)
                Spacer()
                // Checkboxes: in a row, a switch's label and switch drift apart and it's
                // unclear which belongs to which; a checkbox sits right next to its label.
                Toggle("Float", isOn: Binding(get: { rule.float }, set: { on in update { $0.float = on } }))
                    .toggleStyle(.checkbox)
                    .help("Not tiled: keeps its own size and position, above the tiled windows.")
                Toggle("Minimize", isOn: Binding(get: { rule.hide == .minimize }, set: { on in update { $0.hide = on ? .minimize : .park } }))
                    .toggleStyle(.checkbox)
                    .padding(.leading, 12)
                    .help("Minimized while its workspace is out of sight, so call apps show their small window.")
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

/// One scratchpad's settings. Text fields apply when you leave them; the rest at once.
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
            TextField("Name", text: $name).commitOnLeave { rename() }
            HStack {
                TextField("App", text: $app, prompt: Text("bundle ID or app name")).commitOnLeave {
                    if app != pad.app { save { $0.app = app } }
                }
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { a in
                        Button(a.localizedName ?? a.bundleIdentifier ?? "?") { app = a.bundleIdentifier ?? ""; save { $0.app = app } }
                    }
                } label: { Image(systemName: "app.badge") }.menuStyle(.borderlessButton).fixedSize().help("Choose a running app")
            }
            TextField("Window title contains", text: $title, prompt: Text("optional")).commitOnLeave {
                if (title.isEmpty ? nil : title) != pad.title { save { $0.title = title.isEmpty ? nil : title } }
            }
            TextField("Start with", text: $run, prompt: Text("shell command, e.g. open -a Notes")).commitOnLeave {
                if (run.isEmpty ? nil : run) != pad.run { save { $0.run = run.isEmpty ? nil : run } }
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
        // Only if this position still holds this scratchpad (not after a removal).
        guard list.indices.contains(index), list[index].name == pad.name else { return }
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
                    item(.nextLayout); item(.prevLayout)
                    Menu("Switch to layout") {
                        ForEach(KSettings.layoutOrder, id: \.self) { k in Button(k.rawValue) { onPick(.setLayout(k)) } }
                    }
                    item(.toggleFullscreen); item(.shrink); item(.expand)
                    item(.incMaster); item(.decMaster); item(.taller); item(.shorter); item(.resetSizes)
                    item(.increaseWindowLimit); item(.decreaseWindowLimit); item(.toggleTiling)
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
                    item(.toggleFocusFollowsMouse)
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
                    .commitOnLeave {
                        let c = spawnText.trimmingCharacters(in: .whitespaces)
                        if !c.isEmpty, value != .spawn(c) { onPick(.spawn(c)) }
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


/// Text fields apply on Return and when you leave them (a click elsewhere,
/// Tab, another pane, closing the window), like the fields in System Settings.
/// The action must do nothing when the value didn't change.
private struct CommitOnLeave: ViewModifier {
    let commit: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onDisappear(perform: commit)
    }
}

extension View {
    fileprivate func commitOnLeave(_ commit: @escaping () -> Void) -> some View {
        modifier(CommitOnLeave(commit: commit))
    }
}
