import Foundation

/// A wall-clock limit for one measurement, and the pure check that compares
/// measurements against a list of them.
///
/// The numbers this project cares about — index rebuild, cold thumbnails, cache
/// hits — used to live only in prose, and prose does not fail a build. They are
/// exactly the constraints most likely to be broken by a change that looks
/// unrelated: "do no work nobody can see" was learned from a window retitling
/// itself fifteen times a second at 3–7 % idle CPU.
///
/// The budgets themselves live next to the harness that produces the
/// measurements, in one file, and are raised deliberately in the commit that
/// justifies it rather than nudged until they pass.
public struct PerformanceBudget: Equatable, Sendable {
    public let name: String
    public let limitMilliseconds: Double

    public init(name: String, limitMilliseconds: Double) {
        self.name = name
        self.limitMilliseconds = limitMilliseconds
    }

    public struct Violation: Equatable, Sendable {
        public let name: String
        public let measuredMilliseconds: Double
        public let limitMilliseconds: Double
    }

    public struct Outcome: Equatable, Sendable {
        public let violations: [Violation]
        /// Budgets that had no measurement. Not a pass: a check that skipped
        /// what it could not measure would go green the day the measurement
        /// itself broke.
        public let unmeasured: [String]

        public var passes: Bool { violations.isEmpty && unmeasured.isEmpty }
    }

    /// Compares `measurements` (milliseconds, by budget name) against `budgets`.
    /// A measurement nobody set a budget for is ignored.
    public static func evaluate(
        _ measurements: [String: Double],
        against budgets: [PerformanceBudget]
    ) -> Outcome {
        var violations: [Violation] = []
        var unmeasured: [String] = []

        for budget in budgets {
            guard let measured = measurements[budget.name] else {
                unmeasured.append(budget.name)
                continue
            }
            if measured > budget.limitMilliseconds {
                violations.append(
                    Violation(
                        name: budget.name,
                        measuredMilliseconds: measured,
                        limitMilliseconds: budget.limitMilliseconds
                    )
                )
            }
        }
        return Outcome(violations: violations, unmeasured: unmeasured)
    }
}
