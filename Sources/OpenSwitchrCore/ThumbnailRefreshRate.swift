import Foundation

/// How eagerly a visible thumbnail re-captures.
///
/// This trades freshness for CPU. It is expressed as named steps rather than a
/// free slider because the only value that matters is the resulting age
/// threshold, and a handful of predictable steps keep the cache useful.
///
/// None of these introduce a timer. The value becomes an age threshold that is
/// checked when a tile *asks* for a thumbnail, so nothing runs while no
/// frontend is on screen.
public enum ThumbnailRefreshRate: String, CaseIterable, Sendable {

    /// Capture every time a tile appears. Sharpest, and the most expensive.
    case always

    case seconds2
    case seconds5
    case seconds15

    /// Never re-capture. A thumbnail is taken once and reused until the window
    /// closes or the cache is evicted, which makes repeat opens nearly free.
    case onlyOnOpen

    /// The age above which a cached capture counts as stale.
    public var maxAge: TimeInterval {
        switch self {
        case .always: 0
        case .seconds2: 2
        case .seconds5: 5
        case .seconds15: 15
        case .onlyOnOpen: .infinity
        }
    }

    public var title: String {
        switch self {
        case .always: "Always fresh"
        case .seconds2: "At most every 2 s"
        case .seconds5: "At most every 5 s"
        case .seconds15: "At most every 15 s"
        case .onlyOnOpen: "Only once per window"
        }
    }

    /// The step used when nothing is stored. `ThumbnailStore.defaultMaxAge` is
    /// derived from this, so the two cannot drift apart.
    public static let `default` = ThumbnailRefreshRate.seconds5
}
