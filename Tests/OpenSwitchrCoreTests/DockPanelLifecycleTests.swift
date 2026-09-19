import Foundation
import Testing

@testable import OpenSwitchrCore

@Suite("DockPanelLifecycle")
struct DockPanelLifecycleTests {

    private func shown(at now: TimeInterval = 0) -> DockPanelLifecycle {
        var lifecycle = DockPanelLifecycle()
        _ = lifecycle.panelShown(at: now)
        return lifecycle
    }

    @Test("Nothing happens while no panel is on screen")
    func hiddenIgnoresEverything() {
        var lifecycle = DockPanelLifecycle()
        #expect(lifecycle.pointerMoved(.outside, at: 1).isEmpty)
        #expect(lifecycle.hideTimerFired(pointer: .outside).isEmpty)
        #expect(lifecycle.inactivityTimerFired(at: 100) == .none)
        #expect(lifecycle.phase == .hidden)
    }

    @Test("Leaving to the outside schedules a hide once, not on every movement")
    func outsideSchedulesOnce() {
        var lifecycle = shown()
        #expect(lifecycle.pointerMoved(.outside, at: 1) == [.scheduleHide])
        #expect(lifecycle.pointerMoved(.outside, at: 2).isEmpty)
        #expect(lifecycle.phase == .hiding)
    }

    @Test("Crossing the gap onto the panel cancels the pending hide")
    func gapCrossingCancels() {
        var lifecycle = shown()
        _ = lifecycle.pointerMoved(.outside, at: 1)
        #expect(lifecycle.pointerMoved(.onPanel, at: 2) == [.cancelHide])
        #expect(lifecycle.phase == .visible)
    }

    @Test("Re-entering the Dock item cancels the pending hide too")
    func itemReentryCancels() {
        var lifecycle = shown()
        _ = lifecycle.pointerMoved(.outside, at: 1)
        #expect(lifecycle.pointerMoved(.onItem, at: 2) == [.cancelHide])
        #expect(lifecycle.phase == .visible)
    }

    @Test("Moving within the item and panel while visible does nothing")
    func insideIsQuiet() {
        var lifecycle = shown()
        #expect(lifecycle.pointerMoved(.onItem, at: 1).isEmpty)
        #expect(lifecycle.pointerMoved(.onPanel, at: 2).isEmpty)
        #expect(lifecycle.phase == .visible)
    }

    @Test("The hide timer hides when the pointer is still outside")
    func timerHidesWhenOutside() {
        var lifecycle = shown()
        _ = lifecycle.pointerMoved(.outside, at: 1)
        #expect(lifecycle.hideTimerFired(pointer: .outside) == [.hide])
        #expect(lifecycle.phase == .hidden)
    }

    @Test("The hide timer does not close a panel under the pointer")
    func timerSparesAPanelUnderThePointer() {
        var lifecycle = shown()
        _ = lifecycle.pointerMoved(.outside, at: 1)
        #expect(lifecycle.hideTimerFired(pointer: .onPanel).isEmpty)
        #expect(lifecycle.phase == .visible)
    }

    @Test("A stale timer after the pending hide was cancelled does nothing")
    func staleTimerIsIgnored() {
        var lifecycle = shown()
        _ = lifecycle.pointerMoved(.outside, at: 1)
        _ = lifecycle.pointerMoved(.onPanel, at: 2)
        #expect(lifecycle.hideTimerFired(pointer: .outside).isEmpty)
        #expect(lifecycle.phase == .visible)
    }

    // MARK: - Inactivity

    @Test("A panel with no activity for the bound closes itself")
    func inactivityHides() {
        var lifecycle = shown(at: 0)
        let bound = DockPanelLifecycle.inactivityBound
        #expect(lifecycle.inactivityTimerFired(at: bound) == .hide)
        #expect(lifecycle.phase == .hidden)
    }

    @Test("Activity pushes the deadline out instead of closing")
    func activityRearms() {
        var lifecycle = shown(at: 0)
        let bound = DockPanelLifecycle.inactivityBound
        _ = lifecycle.pointerMoved(.onPanel, at: bound - 1)
        #expect(lifecycle.inactivityTimerFired(at: bound) == .rearm(after: bound - 1))
        #expect(lifecycle.phase == .visible)
    }

    @Test("A click or hover on a tile counts as activity")
    func interactionCounts() {
        var lifecycle = shown(at: 0)
        let bound = DockPanelLifecycle.inactivityBound
        lifecycle.interaction(at: bound - 2)
        #expect(lifecycle.inactivityTimerFired(at: bound) == .rearm(after: bound - 2))
    }

    @Test("Hiding for any other reason resets it, and the next panel starts fresh")
    func resetsAndStartsFresh() {
        var lifecycle = shown(at: 0)
        lifecycle.panelHidden()
        #expect(lifecycle.phase == .hidden)
        _ = lifecycle.panelShown(at: 500)
        #expect(lifecycle.inactivityTimerFired(at: 500) == .rearm(after: DockPanelLifecycle.inactivityBound))
    }
}
