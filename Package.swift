// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XMonadMac",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        // Pure model: StackSet, layouts, settings parsing. No AppKit, fully unit-testable.
        .target(name: "XMonadCore", dependencies: ["Yams"]),
        // The actual window manager (Accessibility API, hotkeys, bar).
        .executableTarget(name: "XMonadMac", dependencies: ["XMonadCore"]),
        .testTarget(name: "XMonadCoreTests", dependencies: ["XMonadCore"]),
    ]
)
