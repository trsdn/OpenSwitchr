import CoreGraphics
import Foundation

/// Most-recently-used ordering for windows.
///
/// The switcher lives and dies by this order, so it is kept as pure bookkeeping
/// over window IDs: seeded from CoreGraphics z-order at startup, then advanced
/// purely by focus events. No polling, no timestamps that drift.
public struct MRUTracker {

    /// Monotonic counter. Higher means more recently used.
    private var sequence: Int = 0
    private var ranks: [CGWindowID: Int] = [:]

    /// The rank a window had when it was first seen, kept separately because
    /// `ranks` moves on every focus and would otherwise lose it.
    private var discovery: [CGWindowID: Int] = [:]

    public init() {}

    /// Seeds ordering for windows never seen before, using the front-to-back
    /// z-order from CoreGraphics. Windows already ranked keep their rank, so a
    /// rebuild never reshuffles the user's recent history.
    public mutating func seed(zOrdered ids: [CGWindowID]) {
        for id in ids.reversed() where ranks[id] == nil {
            sequence += 1
            ranks[id] = sequence
            discovery[id] = sequence
        }
    }

    /// Marks a window as the most recently used one.
    public mutating func touch(_ id: CGWindowID) {
        sequence += 1
        ranks[id] = sequence
    }

    public mutating func forget(_ id: CGWindowID) {
        ranks.removeValue(forKey: id)
        discovery.removeValue(forKey: id)
    }

    /// Drops bookkeeping for windows that no longer exist, so the map cannot
    /// grow without bound over a long uptime.
    public mutating func retain(only ids: Set<CGWindowID>) {
        ranks = ranks.filter { ids.contains($0.key) }
        discovery = discovery.filter { ids.contains($0.key) }
    }

    public func rank(of id: CGWindowID) -> Int {
        ranks[id] ?? 0
    }

    /// When this window first entered the index. Higher means more recently.
    ///
    /// Only meaningful relative to other windows: for anything that was already
    /// open at launch it is a seeded z-order position, not an opening time.
    public func openedRank(of id: CGWindowID) -> Int {
        discovery[id] ?? 0
    }

    /// Sorts windows most-recently-used first.
    public func sorted(_ windows: [WindowInfo]) -> [WindowInfo] {
        windows.sorted { rank(of: $0.id) > rank(of: $1.id) }
    }
}
