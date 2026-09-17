import Foundation

/// Whether a modifier release should commit the switcher session, across the
/// gap between the hotkey opening the overlay and the overlay reporting
/// itself visible.
///
/// `.open` is emitted from the event tap's own thread and reaches the
/// controller asynchronously, so there is a window — roughly the ~25 ms warm
/// overlay cost, longer cold — in which a modifier release is observed while
/// the overlay has not yet reported itself visible. Gating the release on
/// `overlayVisible` alone drops that release: no `.commit` is emitted, and
/// the overlay appears after the user has already let go, with nothing left
/// to drive it away.
///
/// This tracks the open request separately from confirmed visibility, so a
/// release during that gap still commits.
public struct HotkeySessionGate: Sendable {
    private var sessionRequested = false

    public init() {}

    /// Call when `.open` is emitted.
    public mutating func opened() {
        sessionRequested = true
    }

    /// Call whenever the controller reports the overlay's visibility,
    /// whichever way it changed. Clears the pending request either way: once
    /// visibility has been reported once, `overlayVisible` itself is the
    /// authority.
    public mutating func visibilityReported() {
        sessionRequested = false
    }

    /// Whether a modifier release right now should commit the session.
    public func shouldCommitOnRelease(overlayVisible: Bool) -> Bool {
        overlayVisible || sessionRequested
    }
}
