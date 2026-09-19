import Foundation

/// Turns a stream of scroll deltas into discrete steps.
///
/// Pure, with time passed in, so it can be tested against a synthetic stream.
/// A trackpad delivers many small deltas and a flick delivers a long tail of
/// momentum; without these rules a single gesture would cycle through every
/// window an application has.
public struct ScrollStepper: Sendable {

    /// Accumulated points that make one step. A notch of a mouse wheel is on the
    /// order of ten points, so one notch is one step.
    public static let defaultThreshold: CGFloat = 10

    /// Steps are at least this far apart, so momentum scrolling cannot run away.
    public static let defaultMinimumInterval: TimeInterval = 0.15

    private let threshold: CGFloat
    private let minimumInterval: TimeInterval
    private var accumulated: CGFloat = 0
    private var lastStep: TimeInterval = -.infinity

    public init(
        threshold: CGFloat = ScrollStepper.defaultThreshold,
        minimumInterval: TimeInterval = ScrollStepper.defaultMinimumInterval
    ) {
        self.threshold = threshold
        self.minimumInterval = minimumInterval
    }

    /// Adds one scroll event and returns the step it produces: `1`, `-1`, or `0`.
    ///
    /// At most one step per event however large the delta, reversing direction
    /// discards what was accumulated the other way (so opposite deltas never
    /// cancel into a phantom step), and a step inside the minimum interval of the
    /// last one is dropped along with the excess.
    public mutating func add(delta: CGFloat, at time: TimeInterval) -> Int {
        guard delta != 0 else { return 0 }

        if accumulated != 0, (accumulated > 0) != (delta > 0) {
            accumulated = 0
        }
        accumulated += delta

        guard abs(accumulated) >= threshold else { return 0 }

        let direction = accumulated > 0 ? 1 : -1
        accumulated = 0
        guard time - lastStep >= minimumInterval else { return 0 }
        lastStep = time
        return direction
    }

    public mutating func reset() {
        accumulated = 0
        lastStep = -.infinity
    }
}
