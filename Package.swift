// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSwitch",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .target(
            name: "OpenSwitchCore"
        ),
        .target(
            name: "OpenSwitchUI",
            dependencies: ["OpenSwitchCore"]
        ),
        .executableTarget(
            name: "OpenSwitch",
            dependencies: ["OpenSwitchCore", "OpenSwitchUI"]
        ),
        // Command-line diagnostics for the parts of the core that can only be
        // judged against real windows: accessibility enumeration and the
        // AX-to-CGWindowID linking heuristic.
        .executableTarget(
            name: "openswitch-diag",
            dependencies: ["OpenSwitchCore"]
        ),
        .testTarget(
            name: "OpenSwitchCoreTests",
            dependencies: ["OpenSwitchCore"]
        )
    ]
)
