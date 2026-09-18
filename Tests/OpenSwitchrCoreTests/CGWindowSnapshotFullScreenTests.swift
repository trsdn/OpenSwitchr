import CoreGraphics
import Testing

@testable import OpenSwitchrCore

@Suite("CGWindowSnapshot full screen")
struct CGWindowSnapshotFullScreenTests {

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let secondScreen = CGRect(x: 1920, y: 0, width: 1440, height: 900)

    @Test("A window exactly matching a screen's frame is full screen")
    func exactMatch() {
        #expect(CGWindowSnapshot.isFullScreen(screen, matchingAnyOf: [screen]))
    }

    @Test("A normal, smaller window is not full screen")
    func smallerWindowIsNot() {
        let normal = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(!CGWindowSnapshot.isFullScreen(normal, matchingAnyOf: [screen]))
    }

    @Test("A window matching the second of several screens is full screen")
    func matchesAnyScreen() {
        #expect(CGWindowSnapshot.isFullScreen(secondScreen, matchingAnyOf: [screen, secondScreen]))
    }

    @Test("No screens means nothing is ever full screen")
    func emptyScreenList() {
        #expect(!CGWindowSnapshot.isFullScreen(screen, matchingAnyOf: []))
    }

    @Test("Sub-pixel rounding differences still count as full screen")
    func toleratesSubPixelRounding() {
        let almost = screen.insetBy(dx: 0.4, dy: -0.4)
        #expect(CGWindowSnapshot.isFullScreen(almost, matchingAnyOf: [screen]))
    }

    @Test("A window a few points short of the screen is not full screen")
    func meaningfullyShortIsNot() {
        let almostButNot = screen.insetBy(dx: 5, dy: 5)
        #expect(!CGWindowSnapshot.isFullScreen(almostButNot, matchingAnyOf: [screen]))
    }
}
