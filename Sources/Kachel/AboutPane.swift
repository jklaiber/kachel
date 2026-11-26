import AppKit
import KachelCore
import SwiftUI

/// Settings → About: version and updates, where to get help, your files.
struct AboutPane: View {
    @ObservedObject var m: SettingsModel
    @ObservedObject var updates = UpdateCheck.shared
    /// Tests pass Kachel's icon (their own runner has none).
    var icon: NSImage = NSApp.applicationIconImage
    /// Tests: a fixed "checked at" instead of the real one.
    var checkedOverride: Date?

    static let docs = URL(string: "https://jklaiber.github.io/kachel/")!
    static let changelog = URL(string: "https://github.com/jklaiber/kachel/blob/main/CHANGELOG.md")!
    static let github = URL(string: "https://github.com/jklaiber/kachel")!
    static let newIssue = URL(string: "https://github.com/jklaiber/kachel/issues/new")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Image(nsImage: icon).resizable().frame(width: 88, height: 88)
                    Text("Kachel").font(.title.weight(.semibold))
                    Text("Version \(AppVersion.string)").foregroundStyle(.secondary).textSelection(.enabled)
                    Text("A tiling window manager for macOS, with xmonad's workspace model.")
                        .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            Section("Updates") {
                updateStatus
                Toggle(isOn: m.binding({ $0.checkForUpdates }, { m.top("check-for-updates", SettingsModel.yaml($0)) })) {
                    explained("Check for updates", "Once a day, Kachel asks GitHub for the latest release, with nothing about you or your Mac. A newer one shows up here and in the menu.")
                }
            }
            Section("Help") {
                link("Documentation", "book", Self.docs)
                link("What's new", "list.bullet.rectangle", Self.changelog)
                link("Report a problem or ask for a feature", "exclamationmark.bubble", Self.newIssue)
                link("Source code on GitHub", "chevron.left.forwardslash.chevron.right", Self.github)
            }
            Section("Your files") {
                LabeledContent {
                    HStack {
                        Button("Edit") { Config.openInEditor() }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Config.url]) }
                    }
                } label: {
                    explained("Configuration", Self.tilde(Config.url))
                }
                LabeledContent {
                    Button("Show Log") { NSWorkspace.shared.open(Log.url) }
                } label: {
                    explained("Log", Self.tilde(Log.url))
                }
            }
            Section {
                Text("© 2026 Julian Klaiber · MIT licence")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var updateStatus: some View {
        if ReleaseVersion(AppVersion.string) == nil {
            explained("Development build", "Built from the source code: there's no release to compare it with.")
        } else if let r = updates.available {
            LabeledContent {
                HStack {
                    Button("Copy Command") { UpdateCheck.copyCommand() }
                    Button("Release Notes") { NSWorkspace.shared.open(r.notes) }
                }
            } label: {
                Label { Text("Kachel \(r.version.description) is available") } icon: {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                }
                Text("Upgrade in Terminal: \(UpdateCheck.upgradeCommand)").textSelection(.enabled)
            }
        } else {
            LabeledContent {
                Button(updates.checking ? "Checking…" : "Check Now") { updates.checkNow() }
                    .disabled(updates.checking)
            } label: {
                if updates.failed {
                    Text("Couldn't reach GitHub")
                    Text("No connection, or GitHub didn't answer. Kachel tries again tomorrow.")
                } else if let at = checkedOverride ?? updates.lastChecked {
                    Text("Kachel is up to date")
                    Text("Checked \(at.formatted(date: .omitted, time: .shortened)).")
                } else {
                    Text("Not checked yet")
                    Text(m.s.checkForUpdates ? "Kachel checks a minute after it starts, then once a day." : "The daily check is off.")
                }
            }
        }
    }

    private func link(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Image(systemName: symbol).frame(width: 22)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func tilde(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
