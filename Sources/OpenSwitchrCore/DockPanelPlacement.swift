import CoreGraphics
import Foundation

/// Which screen edge the Dock sits on.
public enum DockEdge: Equatable, Sendable {
    case bottom, left, right
}

/// Where a Dock preview panel goes, derived from where the Dock item actually
/// is rather than from an assumption that the Dock is along the bottom.
///
/// All frames are in AppKit screen coordinates (origin bottom-left of the
/// primary display, y up). Pure, so it can be tested against synthetic display
/// layouts — including a display below or beside the primary, which is where
/// hard-coded assumptions land the panel on the wrong screen.
///
/// The edge and size are read from the Dock item's frame, which the hover
/// monitor already holds, so nothing here needs private API or polling.
public enum DockPanelPlacement {

    /// The edge the Dock is on, judged from the nearest screen edge.
    ///
    /// Nearest rather than "within a few points of": a Dock icon sits inside the
    /// Dock's own padding and is never that close to the edge, so requiring it
    /// treated every left or right Dock as a bottom one. Ties go to the bottom,
    /// the usual place.
    public static func edge(itemRect: CGRect, screenFrame: CGRect) -> DockEdge {
        let left = itemRect.minX - screenFrame.minX
        let right = screenFrame.maxX - itemRect.maxX
        let bottom = itemRect.minY - screenFrame.minY

        if bottom <= left && bottom <= right { return .bottom }
        return left <= right ? .left : .right
    }

    /// The screen containing the item's centre.
    ///
    /// The centre, not the first screen the item touches: an item near the seam
    /// between two displays intersects both, and `NSScreen.main` is the screen
    /// with the key window, which is not necessarily the one the pointer is on.
    public static func screenIndex(containing itemRect: CGRect, in frames: [CGRect]) -> Int? {
        let centre = CGPoint(x: itemRect.midX, y: itemRect.midY)
        return frames.firstIndex { $0.contains(centre) }
    }

    /// Where the panel's origin goes: beside the item, on the side away from the
    /// Dock, then clamped inside the visible frame so it never lands over the
    /// Dock, past a screen edge, or on another display.
    public static func origin(
        itemRect: CGRect,
        panelSize: CGSize,
        edge: DockEdge,
        visibleFrame: CGRect,
        gap: CGFloat = 8
    ) -> CGPoint {
        var origin: CGPoint
        switch edge {
        case .bottom:
            origin = CGPoint(x: itemRect.midX - panelSize.width / 2, y: itemRect.maxY + gap)
        case .left:
            origin = CGPoint(x: itemRect.maxX + gap, y: itemRect.midY - panelSize.height / 2)
        case .right:
            origin = CGPoint(x: itemRect.minX - panelSize.width - gap, y: itemRect.midY - panelSize.height / 2)
        }

        let margin: CGFloat = 4
        origin.x = min(max(origin.x, visibleFrame.minX + margin), visibleFrame.maxX - panelSize.width - margin)
        origin.y = min(max(origin.y, visibleFrame.minY + margin), visibleFrame.maxY - panelSize.height - margin)
        return origin
    }

    /// The size the panel needs. A bottom Dock gets a row; a side Dock gets a
    /// column beside it, because a row would run off the screen.
    public static func panelSize(windowCount: Int, tileSize: CGSize, edge: DockEdge) -> CGSize {
        let count = max(1, CGFloat(windowCount))
        let tileWidth = tileSize.width + 16 + 2
        let tileHeight = tileSize.height + 16 + 20 + 2

        switch edge {
        case .bottom:
            return CGSize(width: count * tileWidth + 16, height: tileSize.height + 16 + 20 + 16)
        case .left, .right:
            return CGSize(width: tileWidth + 16, height: count * tileHeight + 16)
        }
    }
}
