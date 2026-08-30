import CoreGraphics
import Testing

@testable import OpenSwitchrCore

@Suite("MRUTracker")
struct MRUTrackerTests {

    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(
            id: id,
            pid: 1,
            bundleID: nil,
            appName: "App",
            title: "Window \(id)",
            frame: .zero,
            isMinimized: false,
            isOnScreen: true,
            element: nil
        )
    }

    @Test("Seeding preserves front-to-back z-order")
    func seedFollowsZOrder() {
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [3, 1, 2])

        #expect(tracker.sorted([window(1), window(2), window(3)]).map(\.id) == [3, 1, 2])
    }

    @Test("Touching a window makes it most recent")
    func touchPromotes() {
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [1, 2, 3])
        tracker.touch(3)

        #expect(tracker.sorted([window(1), window(2), window(3)]).map(\.id) == [3, 1, 2])
    }

    @Test("Re-seeding never reshuffles windows that are already ranked")
    func reseedKeepsHistory() {
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [1, 2])
        tracker.touch(2)

        // A rebuild reports the same windows plus a new one.
        tracker.seed(zOrdered: [1, 2, 9])

        let order = tracker.sorted([window(1), window(2), window(9)]).map(\.id)
        #expect(order.firstIndex(of: 2)! < order.firstIndex(of: 1)!)
    }

    @Test("A newly seeded window sorts ahead of untouched older ones")
    func newWindowsRankAboveStaleOnes() {
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [1, 2])
        tracker.seed(zOrdered: [1, 2, 9])

        #expect(tracker.rank(of: 9) > tracker.rank(of: 1))
    }

    @Test("Retaining prunes bookkeeping for closed windows")
    func retainPrunes() {
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [1, 2, 3])
        tracker.retain(only: [1])

        #expect(tracker.rank(of: 1) > 0)
        #expect(tracker.rank(of: 2) == 0)
        #expect(tracker.rank(of: 3) == 0)
    }

    @Test("Forgetting a window removes its rank")
    func forgetRemovesRank() {
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [1])
        tracker.forget(1)

        #expect(tracker.rank(of: 1) == 0)
    }

    // MARK: - Discovery order

    @Test("Discovery order follows front-to-back z-order, like use order does")
    func seedRecordsDiscovery() {
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [1, 2, 3])

        // Seeded back-to-front, so the frontmost window is the most recent.
        #expect(tracker.openedRank(of: 1) > tracker.openedRank(of: 2))
        #expect(tracker.openedRank(of: 2) > tracker.openedRank(of: 3))
    }

    @Test("Using a window does not make it look newly opened")
    func touchLeavesDiscoveryAlone() {
        // The whole point of the second map: "most recently opened" must not
        // collapse into "most recently used".
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [1, 2, 3])
        let before = tracker.openedRank(of: 3)

        tracker.touch(3)

        #expect(tracker.rank(of: 3) > tracker.rank(of: 1))
        #expect(tracker.openedRank(of: 3) == before)
        #expect(tracker.openedRank(of: 1) > tracker.openedRank(of: 3))
    }

    @Test("A window first seen through use still gets a discovery rank")
    func touchSeedsDiscoveryForUnknownWindow() {
        // `seed` skips anything already ranked, so without this the window
        // would have no discovery rank for the rest of the session and would
        // sort last under "most recently opened" forever.
        var tracker = MRUTracker()
        tracker.touch(9)
        tracker.seed(zOrdered: [9])

        #expect(tracker.openedRank(of: 9) > 0)
    }

    @Test("Discovery bookkeeping is pruned with the rest")
    func retainPrunesDiscovery() {
        var tracker = MRUTracker()
        tracker.seed(zOrdered: [1, 2])
        tracker.retain(only: [1])

        #expect(tracker.openedRank(of: 1) > 0)
        #expect(tracker.openedRank(of: 2) == 0)

        tracker.forget(1)
        #expect(tracker.openedRank(of: 1) == 0)
    }
}
