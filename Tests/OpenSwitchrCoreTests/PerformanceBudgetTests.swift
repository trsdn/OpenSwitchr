import Testing

@testable import OpenSwitchrCore

@Suite("PerformanceBudget")
struct PerformanceBudgetTests {

    private let budgets = [
        PerformanceBudget(name: "warm rebuild", limitMilliseconds: 100),
        PerformanceBudget(name: "cache hit", limitMilliseconds: 1),
    ]

    @Test("Everything within budget is a clean pass")
    func allWithinBudget() {
        let outcome = PerformanceBudget.evaluate(
            ["warm rebuild": 8.6, "cache hit": 0.1],
            against: budgets
        )
        #expect(outcome.passes)
        #expect(outcome.violations.isEmpty)
        #expect(outcome.unmeasured.isEmpty)
    }

    @Test("A measurement over its limit is a violation carrying both numbers")
    func overBudget() {
        let outcome = PerformanceBudget.evaluate(
            ["warm rebuild": 250, "cache hit": 0.1],
            against: budgets
        )
        #expect(!outcome.passes)
        #expect(outcome.violations.count == 1)
        #expect(outcome.violations[0].name == "warm rebuild")
        #expect(outcome.violations[0].measuredMilliseconds == 250)
        #expect(outcome.violations[0].limitMilliseconds == 100)
    }

    @Test("Exactly the limit is still within budget")
    func atTheLimit() {
        #expect(PerformanceBudget.evaluate(["warm rebuild": 100, "cache hit": 1], against: budgets).passes)
    }

    @Test("A budget with no measurement is reported, not silently passed")
    func unmeasuredIsNotAPass() {
        // A check that skips what it could not measure would go green the day
        // the measurement itself broke.
        let outcome = PerformanceBudget.evaluate(["warm rebuild": 8], against: budgets)
        #expect(outcome.unmeasured == ["cache hit"])
        #expect(!outcome.passes)
    }

    @Test("A measurement nobody set a budget for is ignored")
    func extraMeasurementIgnored() {
        let outcome = PerformanceBudget.evaluate(
            ["warm rebuild": 8, "cache hit": 0.1, "something else": 9_999],
            against: budgets
        )
        #expect(outcome.passes)
    }

    @Test("Several violations are all reported, in the order the budgets are listed")
    func manyViolations() {
        let outcome = PerformanceBudget.evaluate(
            ["warm rebuild": 500, "cache hit": 50],
            against: budgets
        )
        #expect(outcome.violations.map(\.name) == ["warm rebuild", "cache hit"])
    }
}
