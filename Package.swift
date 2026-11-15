// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kachel",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        // Pure model: StackSet, layouts, settings parsing. No AppKit, fully unit-testable.
        .target(name: "KachelCore", dependencies: ["Yams"]),
        // The actual window manager (Accessibility API, hotkeys, bar).
        .executableTarget(name: "Kachel", dependencies: ["KachelCore"]),
        .testTarget(name: "KachelCoreTests", dependencies: ["KachelCore"]),
    ]
)
