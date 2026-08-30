// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSwitchr",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .target(
            name: "OpenSwitchrCore"
        ),
        .target(
            name: "OpenSwitchrUI",
            dependencies: ["OpenSwitchrCore"]
        ),
        .executableTarget(
            name: "OpenSwitchr",
            dependencies: ["OpenSwitchrCore", "OpenSwitchrUI"]
        ),
        // Command-line diagnostics for the parts of the core that can only be
        // judged against real windows: accessibility enumeration and the
        // AX-to-CGWindowID linking heuristic.
        .executableTarget(
            name: "openswitchr-diag",
            dependencies: ["OpenSwitchrCore"]
        ),
        // Draws Resources/AppIcon.icns from the same `WindowMark` the menu bar
        // uses, so the app icon and the menu bar glyph cannot drift apart.
        .executableTarget(
            name: "openswitchr-icon",
            dependencies: ["OpenSwitchrUI"]
        ),
        .testTarget(
            name: "OpenSwitchrCoreTests",
            dependencies: ["OpenSwitchrCore"]
        )
    ]
)
