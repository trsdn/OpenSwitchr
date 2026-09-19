import CoreGraphics
import Testing

@testable import OpenSwitchrCore

@Suite("ScrollStepper")
struct ScrollStepperTests {

    @Test("Small deltas accumulate until they add up to a step")
    func accumulates() {
        var stepper = ScrollStepper(threshold: 12, minimumInterval: 0)
        #expect(stepper.add(delta: 4, at: 0) == 0)
        #expect(stepper.add(delta: 4, at: 1) == 0)
        #expect(stepper.add(delta: 4, at: 2) == 1)
    }

    @Test("Scrolling the other way steps backwards")
    func negativeDirection() {
        var stepper = ScrollStepper(threshold: 10, minimumInterval: 0)
        #expect(stepper.add(delta: -12, at: 0) == -1)
    }

    @Test("Reversing direction discards what was accumulated the other way")
    func reversalDiscards() {
        var stepper = ScrollStepper(threshold: 10, minimumInterval: 0)
        _ = stepper.add(delta: 8, at: 0)
        // 8 forwards must not cancel against 8 backwards into a phantom step.
        #expect(stepper.add(delta: -8, at: 1) == 0)
        #expect(stepper.add(delta: -8, at: 2) == -1)
    }

    @Test("One event is at most one step, however large the delta")
    func oneStepPerEvent() {
        // A trackpad flick delivers big deltas; cycling through five windows
        // for one flick would be a bug, not a feature.
        var stepper = ScrollStepper(threshold: 10, minimumInterval: 0)
        #expect(stepper.add(delta: 500, at: 0) == 1)
    }

    @Test("Steps are rate-limited, so momentum scrolling cannot run away")
    func rateLimited() {
        var stepper = ScrollStepper(threshold: 10, minimumInterval: 0.2)
        #expect(stepper.add(delta: 50, at: 0) == 1)
        #expect(stepper.add(delta: 50, at: 0.05) == 0)
        #expect(stepper.add(delta: 50, at: 0.1) == 0)
        #expect(stepper.add(delta: 50, at: 0.25) == 1)
    }

    @Test("A zero delta does nothing")
    func zero() {
        var stepper = ScrollStepper(threshold: 10, minimumInterval: 0)
        #expect(stepper.add(delta: 0, at: 0) == 0)
    }

    @Test("Resetting drops anything accumulated, for the next hover")
    func reset() {
        var stepper = ScrollStepper(threshold: 10, minimumInterval: 0)
        _ = stepper.add(delta: 8, at: 0)
        stepper.reset()
        #expect(stepper.add(delta: 8, at: 1) == 0)
    }
}
