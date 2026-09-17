import Testing

@testable import OpenSwitchrCore

@Suite("SwitcherSelection")
struct SwitcherSelectionTests {

    @Test("Opening forwards lands on the entry after the current window")
    func forwardFromHead() {
        // The classic case: most-recently-used order, current window at the
        // head, so a single press toggles to the previous window.
        #expect(SwitcherSelection.initialIndex(count: 5, currentIndex: 0, reverse: false) == 1)
    }

    @Test("Opening backwards lands on the entry before the current window")
    func backwardFromHead() {
        #expect(SwitcherSelection.initialIndex(count: 5, currentIndex: 0, reverse: true) == 4)
    }

    @Test("The current window is stepped away from wherever it sits")
    func stepsFromAnyPosition() {
        // A different order puts the current window somewhere else entirely,
        // and index 1 would then be arbitrary.
        #expect(SwitcherSelection.initialIndex(count: 5, currentIndex: 3, reverse: false) == 4)
        #expect(SwitcherSelection.initialIndex(count: 5, currentIndex: 3, reverse: true) == 2)
    }

    @Test("Stepping wraps around both ends")
    func wraps() {
        #expect(SwitcherSelection.initialIndex(count: 5, currentIndex: 4, reverse: false) == 0)
        #expect(SwitcherSelection.initialIndex(count: 5, currentIndex: 0, reverse: true) == 4)
    }

    @Test("A filtered-out current window selects the first entry, not the second")
    func currentWindowMissing() {
        // "Everything but the current application" removes the current window
        // by definition, so the head of that list is already the window the
        // user wants. Skipping to index 1 would step past it.
        #expect(SwitcherSelection.initialIndex(count: 5, currentIndex: nil, reverse: false) == 0)
        #expect(SwitcherSelection.initialIndex(count: 5, currentIndex: nil, reverse: true) == 4)
    }

    @Test("A single window is always the selection")
    func singleWindow() {
        #expect(SwitcherSelection.initialIndex(count: 1, currentIndex: 0, reverse: false) == 0)
        #expect(SwitcherSelection.initialIndex(count: 1, currentIndex: 0, reverse: true) == 0)
        #expect(SwitcherSelection.initialIndex(count: 1, currentIndex: nil, reverse: false) == 0)
    }

    @Test("An empty list selects nothing rather than trapping")
    func emptyList() {
        // The overlay is now presented even with nothing to show, so this is
        // reachable rather than theoretical.
        #expect(SwitcherSelection.initialIndex(count: 0, currentIndex: nil, reverse: false) == 0)
        #expect(SwitcherSelection.initialIndex(count: 0, currentIndex: 0, reverse: true) == 0)
    }

    @Test("An out-of-range current index is treated as absent")
    func outOfRangeCurrentIndex() {
        #expect(SwitcherSelection.initialIndex(count: 3, currentIndex: 9, reverse: false) == 0)
        #expect(SwitcherSelection.initialIndex(count: 3, currentIndex: -1, reverse: false) == 0)
    }
}
