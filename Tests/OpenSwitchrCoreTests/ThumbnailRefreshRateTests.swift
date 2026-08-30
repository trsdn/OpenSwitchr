import Foundation
import Testing

@testable import OpenSwitchrCore

@Suite("ThumbnailRefreshRate")
struct ThumbnailRefreshRateTests {

    @Test("Always fresh treats any cached capture as stale")
    func alwaysIsZero() {
        #expect(ThumbnailRefreshRate.always.maxAge == 0)
    }

    @Test("Only-once never re-captures")
    func onlyOnOpenIsInfinite() {
        #expect(ThumbnailRefreshRate.onlyOnOpen.maxAge == .infinity)
    }

    @Test("Named steps map to their advertised age in seconds")
    func namedStepsMatchTheirTitles() {
        #expect(ThumbnailRefreshRate.seconds2.maxAge == 2)
        #expect(ThumbnailRefreshRate.seconds5.maxAge == 5)
        #expect(ThumbnailRefreshRate.seconds15.maxAge == 15)
    }

    @Test("Cheaper steps never refresh more often than dearer ones")
    func stepsAreOrdered() {
        let ordered: [ThumbnailRefreshRate] = [.always, .seconds2, .seconds5, .seconds15, .onlyOnOpen]
        let ages = ordered.map(\.maxAge)
        #expect(ages == ages.sorted())
    }

    @Test("The store's default age is the default step, so the two cannot drift")
    func storeDefaultMatchesDefaultStep() {
        #expect(ThumbnailStore.defaultMaxAge == ThumbnailRefreshRate.default.maxAge)
    }

    @Test("Every step survives a round trip through its stored raw value")
    func rawValuesRoundTrip() {
        for rate in ThumbnailRefreshRate.allCases {
            #expect(ThumbnailRefreshRate(rawValue: rate.rawValue) == rate)
        }
    }

    @Test("An unknown stored value falls back instead of losing thumbnails")
    func unknownRawValueFallsBack() {
        #expect(ThumbnailRefreshRate(rawValue: "everyFortnight") == nil)
    }
}
