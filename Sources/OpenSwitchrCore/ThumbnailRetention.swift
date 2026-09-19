import CoreGraphics
import Foundation

/// How long a cached thumbnail is kept, and in what order they are given up.
///
/// A minimized window is the one case where a cached thumbnail cannot be
/// re-created: ScreenCaptureKit cannot capture it, so whatever was captured
/// before it went to the Dock is the only preview there will ever be. That is
/// also the moment a preview is worth the most, since the window is not on
/// screen and the image is the only thing telling one of five untitled
/// documents from the others. The rules here are therefore separated from the
/// store, which cannot be unit tested without a window server.
public enum ThumbnailRetention {

    /// Whether a cached thumbnail may still be served as-is.
    ///
    /// A minimized window is exempt from the age limit: it can never satisfy
    /// the refresh the limit exists to trigger, so applying it would revert the
    /// preview to an icon `maxAge` seconds after minimizing, which reads as a
    /// bug that comes and goes.
    public static func isFresh(age: TimeInterval, maxAge: TimeInterval, isMinimized: Bool) -> Bool {
        isMinimized || age < maxAge
    }

    public struct Candidate: Equatable {
        public let id: CGWindowID
        public let lastAccess: Date
        public let isMinimized: Bool

        public init(id: CGWindowID, lastAccess: Date, isMinimized: Bool) {
            self.id = id
            self.lastAccess = lastAccess
            self.isMinimized = isMinimized
        }
    }

    /// The order to evict in when the byte budget is exceeded: every live entry
    /// first, least recently used first, then minimized ones by the same rule.
    ///
    /// Deliberately one budget with an ordering rather than a second budget for
    /// minimized windows, because a second budget is a second default to keep
    /// in sync with the first.
    public static func evictionOrder(_ candidates: [Candidate]) -> [CGWindowID] {
        candidates
            .sorted { lhs, rhs in
                if lhs.isMinimized != rhs.isMinimized { return !lhs.isMinimized }
                return lhs.lastAccess < rhs.lastAccess
            }
            .map(\.id)
    }

    /// Windows that were minimized and are no longer: their kept thumbnail
    /// shows the pre-minimize contents, so it has to be dropped or the first
    /// frame after restoring is stale.
    public static func restored(previous: Set<CGWindowID>, current: Set<CGWindowID>) -> Set<CGWindowID> {
        previous.subtracting(current)
    }
}
