import CoreGraphics
import Foundation

/// Layout maths for how wide a switcher preview tile may be, as pure functions
/// over a count and a width so they need no `NSScreen`.
///
/// The configured width is an upper limit, never a floor: an automatic size only
/// ever makes tiles *smaller* so that every window is visible in the overlay's
/// rows without scrolling, and gives up when that would make a preview too small
/// to identify.
///
/// Sizes are quantised to steps. `ThumbnailStore` caches by capture size, so a
/// tile width that varied continuously with the window count would miss the
/// cache on nearly every request and turn a cheap layout change into a capture
/// storm. The step is also what reaches the capture size, so a snapped width is
/// captured at the step rather than at some exact layout width.
public enum TileSizing {

    /// The granularity a width is snapped to.
    public static let step: CGFloat = 20

    /// Below this a preview stops being identifiable; the answer is icon mode,
    /// not a smaller image.
    public static let minimumPreviewWidth: CGFloat = 120

    /// How many rows the overlay shows before it scrolls.
    public static let maxVisibleRows = 3

    /// Padding around the grid and the gutter around each tile, both in points.
    private static let gridPadding: CGFloat = 32
    private static let tileGutter: CGFloat = 16 + 4

    /// How many tiles of `tileWidth` fit across `availableWidth`.
    public static func columns(availableWidth: CGFloat, tileWidth: CGFloat) -> Int {
        max(1, Int(((availableWidth - gridPadding) / (tileWidth + tileGutter)).rounded(.down)))
    }

    public enum Fit: Equatable, Sendable {
        case width(CGFloat)
        /// Even the smallest legible tile would need more rows than the overlay
        /// shows. The caller should use icon tiles instead.
        case tooSmall
    }

    /// The widest step, no wider than `configuredWidth`, at which `windowCount`
    /// tiles fit in `maxVisibleRows` rows.
    public static func fit(windowCount: Int, availableWidth: CGFloat, configuredWidth: CGFloat) -> Fit {
        let cap = max(minimumPreviewWidth, (configuredWidth / step).rounded(.down) * step)
        guard windowCount > 0 else { return .width(cap) }

        var width = cap
        while width >= minimumPreviewWidth {
            let columns = columns(availableWidth: availableWidth, tileWidth: width)
            let rows = (windowCount + columns - 1) / columns
            if rows <= maxVisibleRows { return .width(width) }
            width -= step
        }
        return .tooSmall
    }
}
