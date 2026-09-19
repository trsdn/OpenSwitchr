import CoreGraphics
import Testing

@testable import OpenSwitchrCore

@Suite("TileSizing")
struct TileSizingTests {

    private let available: CGFloat = 1238  // 86% of a 1440 pt wide screen

    // MARK: - Columns

    @Test("Columns are how many tiles, with their gutters, fit in the padded width")
    func columns() {
        // (1238 - 32) / (200 + 16 + 4) = 5.48 -> 5
        #expect(TileSizing.columns(availableWidth: available, tileWidth: 200) == 5)
    }

    @Test("There is always at least one column, however narrow the space")
    func atLeastOneColumn() {
        #expect(TileSizing.columns(availableWidth: 10, tileWidth: 300) == 1)
    }

    // MARK: - Fit

    @Test("A few windows keep the configured width: it is the upper limit, not a floor")
    func fewWindowsKeepConfiguredWidth() {
        #expect(TileSizing.fit(windowCount: 3, availableWidth: available, configuredWidth: 200) == .width(200))
    }

    @Test("More windows than fit in the visible rows shrink the tile to the largest step that does")
    func shrinksToFit() {
        // At 320 only 3 columns fit, so 12 windows need 4 rows. At 280, 4 columns fit: 3 rows.
        #expect(TileSizing.fit(windowCount: 12, availableWidth: available, configuredWidth: 320) == .width(280))
    }

    @Test("The result is quantised, so the thumbnail cache keeps hitting")
    func quantised() {
        // 305 is not a step; the cap snaps down to 300.
        #expect(TileSizing.fit(windowCount: 1, availableWidth: available, configuredWidth: 305) == .width(300))
        if case .width(let width) = TileSizing.fit(windowCount: 9, availableWidth: available, configuredWidth: 320) {
            #expect(width.truncatingRemainder(dividingBy: TileSizing.step) == 0)
        }
    }

    @Test("Below the legible floor the answer is too small, not a smaller image")
    func tooSmall() {
        #expect(TileSizing.fit(windowCount: 100, availableWidth: available, configuredWidth: 320) == .tooSmall)
    }

    @Test("A configured width below the floor is raised to it")
    func floorApplies() {
        #expect(TileSizing.fit(windowCount: 1, availableWidth: available, configuredWidth: 100) == .width(120))
    }

    @Test("No windows keeps the configured width rather than dividing by nothing")
    func noWindows() {
        #expect(TileSizing.fit(windowCount: 0, availableWidth: available, configuredWidth: 200) == .width(200))
    }
}
