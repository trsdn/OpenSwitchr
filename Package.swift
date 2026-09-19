// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSwitchr",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // The one third-party dependency, for in-app updates from GitHub Releases.
        // Pinned exactly, with Package.resolved committed, so an update path that
        // downloads and installs code cannot drift underneath a release.
        .package(url: "https://github.com/mxcl/AppUpdater.git", exact: "4.1.2")
    ],
    targets: [
        .target(
            name: "OpenSwitchrCore"
        ),
        .target(
            name: "OpenSwitchrUI",
            dependencies: ["OpenSwitchrCore"],
            resources: [.process("UI.xcstrings")]
        ),
        .executableTarget(
            name: "OpenSwitchr",
            dependencies: [
                "OpenSwitchrCore",
                "OpenSwitchrUI",
                .product(name: "AppUpdater", package: "AppUpdater")
            ],
            resources: [.process("Localizable.xcstrings")]
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
