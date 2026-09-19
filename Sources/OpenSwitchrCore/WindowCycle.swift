import CoreGraphics
import Foundation

/// Which window an application's windows cycle to next.
///
/// The order is by window id, not by recency. The index keeps windows
/// most-recently-used first, so stepping "next" in that order from the window
/// just focused only ever ping-pongs between the two most recent; a stable order
/// visits every window.
public enum WindowCycle {

    /// The window `direction` steps away from `current`, wrapping at the ends, or
    /// `nil` when there is nothing to cycle to (fewer than two windows).
    ///
    /// When `current` is not among `windows`, cycling forwards starts at the
    /// first and backwards at the last.
    public static func target(
        among windows: [WindowInfo],
        current: CGWindowID?,
        direction: Int
    ) -> WindowInfo? {
        guard windows.count >= 2 else { return nil }

        let ordered = windows.sorted { $0.id < $1.id }
        let step = direction >= 0 ? 1 : -1

        guard let current, let index = ordered.firstIndex(where: { $0.id == current }) else {
            return step > 0 ? ordered.first : ordered.last
        }
        let count = ordered.count
        return ordered[((index + step) % count + count) % count]
    }
}
