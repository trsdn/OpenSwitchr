import Foundation

/// Where the pointer is relative to a Dock preview and the icon that opened it.
public enum DockPointerRegion: Equatable, Sendable {
    case outside
    case onItem
    case onPanel
}

/// The lifetime of a Dock preview panel, as one state machine with its
/// transitions written down.
///
/// Both known hover bugs in this project lived in stale state, where the
/// panel's visible state and the app's idea of it disagreed. The Dock item and
/// the panel are treated as a single hover region: the pointer moving between
/// them is not a leave, and a hide that was scheduled while it crossed the gap
/// is cancelled the moment it arrives on either.
///
/// Pure: it decides, and the controller performs. Time is passed in rather than
/// read, and there is no timer here, so the one place a timer is tempting — the
/// inactivity bound — can be checked against an explicit clock.
public struct DockPanelLifecycle: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        case hidden
        case visible
        /// A hide has been scheduled and can still be cancelled.
        case hiding
    }

    public enum Effect: Equatable, Sendable {
        case scheduleHide
        case cancelHide
        case hide
    }

    public enum InactivityCheck: Equatable, Sendable {
        /// No panel is up; nothing to do.
        case none
        /// Activity moved the deadline; check again after this long.
        case rearm(after: TimeInterval)
        case hide
    }

    /// A panel with no pointer movement and no interaction for this long
    /// closes itself, so one opened by a pointer that then stopped does not
    /// stay up with nothing to dismiss it.
    public static let inactivityBound: TimeInterval = 10

    public private(set) var phase: Phase = .hidden
    private var lastActivity: TimeInterval = 0

    public init() {}

    public mutating func panelShown(at now: TimeInterval) -> [Effect] {
        phase = .visible
        lastActivity = now
        return []
    }

    /// The panel went away for a reason other than this machine's own hide.
    public mutating func panelHidden() {
        phase = .hidden
    }

    public mutating func pointerMoved(_ region: DockPointerRegion, at now: TimeInterval) -> [Effect] {
        guard phase != .hidden else { return [] }
        lastActivity = now

        switch region {
        case .outside:
            guard phase == .visible else { return [] }
            phase = .hiding
            return [.scheduleHide]
        case .onItem, .onPanel:
            guard phase == .hiding else { return [] }
            phase = .visible
            return [.cancelHide]
        }
    }

    /// A click or a hover on a tile.
    public mutating func interaction(at now: TimeInterval) {
        guard phase != .hidden else { return }
        lastActivity = now
    }

    /// Whether the scheduled hide should go ahead. Checked against where the
    /// pointer is *now*, not where it was when the hide was scheduled.
    public mutating func hideTimerFired(pointer: DockPointerRegion) -> [Effect] {
        guard phase == .hiding else { return [] }
        if pointer == .outside {
            phase = .hidden
            return [.hide]
        }
        phase = .visible
        return []
    }

    public mutating func inactivityTimerFired(at now: TimeInterval) -> InactivityCheck {
        guard phase != .hidden else { return .none }
        let elapsed = now - lastActivity
        if elapsed >= Self.inactivityBound {
            phase = .hidden
            return .hide
        }
        return .rearm(after: Self.inactivityBound - elapsed)
    }
}
