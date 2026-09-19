import CoreGraphics
import Foundation

/// A running application, as much of it as this needs.
public struct RunningApplication: Equatable, Sendable {
    public let pid: pid_t
    public let bundleID: String?
    public let name: String

    public init(pid: pid_t, bundleID: String?, name: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}

/// Running applications with no open windows, as entries the switcher can list.
///
/// `WindowIndex` contains windows, so an application with every window closed
/// contributes nothing to it. Rather than make the index carry a second kind of
/// item (and teach both frontends, the thumbnail cache and every action about an
/// enum), an entry here is a `WindowInfo` marked ``WindowInfo/isApplicationOnly``
/// with a synthetic id: every consumer already understands it, and the few that
/// must treat it differently — capture, raise, close — can ask.
///
/// Built when the switcher opens and only if the setting is on, from a list the
/// caller already has, so the cost that made the index resolve *only* processes
/// that own a window is never paid on the rebuild path.
public enum WindowlessApplications {

    /// Synthetic ids start here. Real `CGWindowID`s are small, increasing
    /// integers, so this range does not collide with one.
    public static let idBase: UInt32 = 0xF000_0000

    public static func isApplicationOnly(id: CGWindowID) -> Bool {
        id >= idBase
    }

    public static func entries(
        running: [RunningApplication],
        windowedPIDs: Set<pid_t>,
        ownPID: pid_t
    ) -> [WindowInfo] {
        running
            .filter { $0.pid != ownPID && !windowedPIDs.contains($0.pid) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { app in
                WindowInfo(
                    id: idBase | (UInt32(truncatingIfNeeded: app.pid) & 0x0FFF_FFFF),
                    pid: app.pid,
                    bundleID: app.bundleID,
                    appName: app.name,
                    title: "",
                    frame: .zero,
                    isMinimized: false,
                    isOnScreen: false,
                    element: nil,
                    isApplicationOnly: true
                )
            }
    }
}
