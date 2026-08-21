import CoreGraphics
import Testing

@testable import OpenSwitchCore

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
}
