import CoreGraphics
import Testing

@testable import OpenSwitchrCore

/// Frames are in AppKit screen coordinates: origin at the bottom-left of the
/// primary display, y growing upwards.
@Suite("DockPanelPlacement")
struct DockPanelPlacementTests {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let panel = CGSize(width: 300, height: 200)

    // MARK: - Edge

    @Test("A Dock along the bottom is detected from an item near the bottom edge")
    func bottomEdge() {
        let item = CGRect(x: 700, y: 5, width: 60, height: 60)
        #expect(DockPanelPlacement.edge(itemRect: item, screenFrame: screen) == .bottom)
    }

    @Test("A left Dock is detected even though its icons are inset from the screen edge")
    func leftEdgeWithInsetIcons() {
        // The old check demanded the item be within 4 pt of the edge, and a Dock
        // icon never is: it sits inside the Dock's own padding.
        let item = CGRect(x: 14, y: 400, width: 60, height: 60)
        #expect(DockPanelPlacement.edge(itemRect: item, screenFrame: screen) == .left)
    }

    @Test("A right Dock is detected the same way")
    func rightEdgeWithInsetIcons() {
        let item = CGRect(x: 1366, y: 400, width: 60, height: 60)
        #expect(DockPanelPlacement.edge(itemRect: item, screenFrame: screen) == .right)
    }

    @Test("A secondary display is judged against its own frame, not the primary's")
    func secondaryDisplayEdge() {
        let secondary = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
        let item = CGRect(x: 2200, y: -175, width: 60, height: 60)
        #expect(DockPanelPlacement.edge(itemRect: item, screenFrame: secondary) == .bottom)
    }

    // MARK: - Screen

    @Test("The screen is the one containing the item's centre, not the first one it touches")
    func screenContainingCentre() {
        let frames = [screen, CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        // Straddling the seam, centre on the second display.
        let item = CGRect(x: 1420, y: 400, width: 60, height: 60)
        #expect(DockPanelPlacement.screenIndex(containing: item, in: frames) == 1)
    }

    @Test("An item on no screen at all has no screen")
    func noScreen() {
        #expect(DockPanelPlacement.screenIndex(containing: CGRect(x: 9000, y: 9000, width: 10, height: 10), in: [screen]) == nil)
    }

    // MARK: - Origin

    @Test("A bottom panel sits above the item, centred on it")
    func bottomOrigin() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let item = CGRect(x: 700, y: 5, width: 60, height: 60)
        let origin = DockPanelPlacement.origin(itemRect: item, panelSize: panel, edge: .bottom, visibleFrame: visible)
        #expect(origin.x == 580)
        #expect(origin.y == 73)
    }

    @Test("A left panel sits to the right of the item and never over the Dock")
    func leftOrigin() {
        let visible = CGRect(x: 80, y: 0, width: 1360, height: 875)
        let item = CGRect(x: 14, y: 400, width: 60, height: 60)
        let origin = DockPanelPlacement.origin(itemRect: item, panelSize: panel, edge: .left, visibleFrame: visible)
        #expect(origin.x >= visible.minX)
        #expect(origin.y == 330)
    }

    @Test("A right panel sits to the left of the item and stays on screen")
    func rightOrigin() {
        let visible = CGRect(x: 0, y: 0, width: 1360, height: 875)
        let item = CGRect(x: 1366, y: 400, width: 60, height: 60)
        let origin = DockPanelPlacement.origin(itemRect: item, panelSize: panel, edge: .right, visibleFrame: visible)
        #expect(origin.x + panel.width <= visible.maxX)
        #expect(origin.y == 330)
    }

    @Test("The panel is clamped inside the visible frame at the ends of the Dock")
    func clamped() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let farLeft = CGRect(x: 2, y: 5, width: 60, height: 60)
        let origin = DockPanelPlacement.origin(itemRect: farLeft, panelSize: panel, edge: .bottom, visibleFrame: visible)
        #expect(origin.x >= visible.minX)
    }

    @Test("On a display below the primary the panel keeps its negative coordinates")
    func negativeCoordinates() {
        let visible = CGRect(x: 1440, y: -180, width: 1920, height: 1055)
        let item = CGRect(x: 2200, y: -175, width: 60, height: 60)
        let origin = DockPanelPlacement.origin(itemRect: item, panelSize: panel, edge: .bottom, visibleFrame: visible)
        #expect(origin.y >= visible.minY)
        #expect(origin.y < visible.maxY)
    }

    // MARK: - Size

    @Test("A bottom Dock lays tiles out in a row, a side Dock in a column")
    func orientation() {
        let tile = CGSize(width: 200, height: 112)
        let row = DockPanelPlacement.panelSize(windowCount: 3, tileSize: tile, edge: .bottom)
        let column = DockPanelPlacement.panelSize(windowCount: 3, tileSize: tile, edge: .left)
        #expect(row.width > row.height)
        #expect(column.height > column.width)
        #expect(DockPanelPlacement.panelSize(windowCount: 3, tileSize: tile, edge: .right) == column)
    }

    @Test("Vertical is a layout of its own, not a rotated row: same tiles, same total area")
    func verticalHoldsTheSameTiles() {
        let tile = CGSize(width: 200, height: 112)
        let one = DockPanelPlacement.panelSize(windowCount: 1, tileSize: tile, edge: .left)
        let three = DockPanelPlacement.panelSize(windowCount: 3, tileSize: tile, edge: .left)
        #expect(three.width == one.width)
        #expect(three.height > one.height)
    }
}
