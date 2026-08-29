import AppKit
import CoreGraphics

// The AppKit bridge for `WindowFilter`, deliberately kept out of the filter
// itself so that type stays testable without a window server.

public extension WindowFilter {

    /// An AppKit screen frame expressed the way `WindowInfo.frame` is.
    ///
    /// This conversion exists exactly once because it is the kind of thing that
    /// drifts: CoreGraphics puts the origin at the top-left of the primary
    /// display with y growing downwards, AppKit puts it at the bottom-left.
    /// Comparing the two without the flip still looks right on a single
    /// display — the numbers happen to coincide — and silently matches the
    /// wrong display on any layout where the displays differ in height.
    static func coreGraphicsFrame(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(
            x: screen.frame.minX,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }
}

public extension WindowFilter.Context {

    /// Builds a context for a surface that is about to appear on `screen`.
    init(frontmostPID: pid_t?, screen: NSScreen?) {
        self.init(
            frontmostPID: frontmostPID,
            screenFrame: screen.map(WindowFilter.coreGraphicsFrame(of:))
        )
    }
}
