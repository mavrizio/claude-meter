// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeMeter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MeterCore", targets: ["MeterCore"]),
        .executable(name: "ClaudeMeterApp", targets: ["ClaudeMeterApp"]),
        .executable(name: "claude-meter-statusline", targets: ["claude-meter-statusline"]),
    ],
    targets: [
        // State, protocol, serial port, Claude Code settings: no UI, unit-tested.
        .target(name: "MeterCore"),
        // Menu bar app (SwiftUI).
        .executableTarget(name: "ClaudeMeterApp", dependencies: ["MeterCore"]),
        // Claude Code statusLine command, shipped inside the app bundle.
        .executableTarget(name: "claude-meter-statusline", dependencies: ["MeterCore"]),
        .testTarget(name: "MeterCoreTests", dependencies: ["MeterCore"]),
    ]
)
