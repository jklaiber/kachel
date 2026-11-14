// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XMonadMac",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure model: StackSet + layouts. No macOS APIs, fully unit-testable.
        .target(name: "XMonadCore"),
        // The actual window manager (Accessibility API, hotkeys, menu bar).
        .executableTarget(name: "XMonadMac", dependencies: ["XMonadCore"]),
        .testTarget(name: "XMonadCoreTests", dependencies: ["XMonadCore"]),
    ]
)
