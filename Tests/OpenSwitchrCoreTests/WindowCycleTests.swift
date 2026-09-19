import CoreGraphics
import Testing

@testable import OpenSwitchrCore

@Suite("WindowCycle")
struct WindowCycleTests {

    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(
            id: id, pid: 1, bundleID: nil, appName: "App", title: "Window \(id)",
            frame: .zero, isMinimized: false, isOnScreen: true, element: nil
        )
    }

    @Test("Cycling forwards goes to the next window in a stable order")
    func forwards() {
        let windows = [window(30), window(10), window(20)]
        #expect(WindowCycle.target(among: windows, current: 10, direction: 1)?.id == 20)
    }

    @Test("Cycling backwards goes to the previous one")
    func backwards() {
        let windows = [window(30), window(10), window(20)]
        #expect(WindowCycle.target(among: windows, current: 20, direction: -1)?.id == 10)
    }

    @Test("It wraps around both ends")
    func wraps() {
        let windows = [window(10), window(20), window(30)]
        #expect(WindowCycle.target(among: windows, current: 30, direction: 1)?.id == 10)
        #expect(WindowCycle.target(among: windows, current: 10, direction: -1)?.id == 30)
    }

    @Test("The order does not depend on recency, so repeated steps visit every window")
    func orderIsStableUnderReordering() {
        // Most-recently-used order would put the window just focused first, and
        // stepping "next" from there would only ever ping-pong between two.
        var visited: [CGWindowID] = []
        var windows = [window(10), window(20), window(30)]
        var current: CGWindowID = 10
        for _ in 0..<3 {
            let next = WindowCycle.target(among: windows, current: current, direction: 1)!
            visited.append(next.id)
            current = next.id
            // Focusing it moves it to the front, as the index would.
            windows.sort { $0.id == current && $1.id != current }
        }
        #expect(visited == [20, 30, 10])
    }

    @Test("With one window or none there is nothing to cycle to")
    func nothingToCycle() {
        #expect(WindowCycle.target(among: [window(10)], current: 10, direction: 1) == nil)
        #expect(WindowCycle.target(among: [], current: nil, direction: 1) == nil)
    }

    @Test("An unknown current window starts from the first or last")
    func unknownCurrent() {
        let windows = [window(30), window(10), window(20)]
        #expect(WindowCycle.target(among: windows, current: nil, direction: 1)?.id == 10)
        #expect(WindowCycle.target(among: windows, current: 99, direction: -1)?.id == 30)
    }
}
