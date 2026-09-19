import Foundation

/// How the user's display accessibility settings change what the panels draw.
///
/// The settings themselves are read by the views from the SwiftUI environment;
/// what each one *does* lives here, pure, so it can be tested without a window
/// server and stays in one place instead of being re-decided in three views.
///
/// macOS has no system text-size setting that reaches third-party apps, so
/// nothing here concerns type size: the panels use fixed point sizes.
public struct AccessibilityAppearance: Equatable, Sendable {

    public var reduceMotion: Bool
    public var reduceTransparency: Bool
    public var increasedContrast: Bool

    public init(reduceMotion: Bool = false, reduceTransparency: Bool = false, increasedContrast: Bool = false) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increasedContrast = increasedContrast
    }

    /// Whether the switcher may animate the selection scrolling into view.
    public var animatesSelectionScroll: Bool { !reduceMotion }

    /// Whether a panel may use a translucent material instead of an opaque fill.
    public var usesTranslucency: Bool { !reduceTransparency }

    /// Whether the small status marks on a tile use the quieter hierarchical
    /// style. Under increased contrast they step up one level, because the
    /// quietest level is what a low-vision reader loses first.
    public var usesQuietMarks: Bool { !increasedContrast }

    /// The lines and fills the panels draw that are not content, as an opacity of
    /// the primary label colour.
    public enum Chrome: Sendable {
        case panelBorder
        case tileBorder
        case tileFill
    }

    /// Faint by design at rest, and stronger under increased contrast so a tile's
    /// edge is still visible against the panel behind it.
    public func opacity(of chrome: Chrome) -> Double {
        switch chrome {
        case .panelBorder: return increasedContrast ? 0.35 : 0.10
        case .tileBorder: return increasedContrast ? 0.40 : 0.12
        case .tileFill: return increasedContrast ? 0.12 : 0.06
        }
    }
}
