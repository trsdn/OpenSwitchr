import CoreGraphics
import Foundation

/// How a tile is drawn, and therefore whether anything is captured for it.
public enum TileMode: Equatable, Sendable {
    /// A live thumbnail, upgraded from the application icon once it arrives.
    case previews
    /// The application icon and the title. Nothing is captured.
    case icons
}

/// What the user asked for. The automatic rules can only move this towards
/// `icons`, never away from it.
public enum TilePreference: String, CaseIterable, Sendable {
    case previews
    case iconsOnly

    public var title: String {
        switch self {
        case .previews: return "Previews"
        case .iconsOnly: return "Icons and titles only"
        }
    }
}

/// Decides whether a surface draws previews or icons.
///
/// Icon mode is the cheapest mode in the app, not a lesser one: when it is
/// chosen nothing calls `ThumbnailProvider.prefetch`, so a Space with forty
/// windows costs zero captures. Two situations make wanting a thumbnail simply
/// wrong, and both are handled here rather than left to the tile to fail at:
///
/// - Screen Recording is not granted, so every capture fails and the layout
///   would still be sized for images that will never arrive.
/// - There are so many windows that each preview is too small to identify
///   anything, and the app would be paying for a capture per window to produce
///   that.
public enum TileModePolicy {

    /// The switcher's default: past this many windows it draws icons. It is a
    /// setting (`PreferencesStore.switcherPreviewLimit`), because the right number
    /// depends on the display: the legibility floor in `TileSizing` already stops
    /// previews that would be too small to identify, so this only bounds the cost
    /// of capturing a great many windows. It was 12 until a Space with 28 windows
    /// on a large display lost its previews for no reason a user could see.
    public static let switcherWindowThreshold = 30

    /// What the setting may be. Below the floor a preview list is barely a list, and
    /// past the ceiling the capture cost is what the limit exists to avoid.
    public static let switcherPreviewLimitRange = 4...60

    /// A stored value outside the range (an edited plist, a later version's
    /// value) is pulled back into it rather than trusted.
    public static func clampedSwitcherPreviewLimit(_ value: Int) -> Int {
        min(max(value, switcherPreviewLimitRange.lowerBound), switcherPreviewLimitRange.upperBound)
    }

    /// Separate from the switcher's, because the surfaces differ: a Dock hover
    /// is scoped to one application and rarely trips it, the switcher on a busy
    /// Space regularly will. Equal today; kept apart so tuning one is not a
    /// decision about the other.
    public static let dockPreviewWindowThreshold = 12

    public static func resolve(
        preference: TilePreference,
        screenRecordingGranted: Bool,
        windowCount: Int,
        threshold: Int
    ) -> TileMode {
        if preference == .iconsOnly { return .icons }
        if !screenRecordingGranted { return .icons }
        if windowCount > threshold { return .icons }
        return .previews
    }

    /// The tile a surface lays out for `mode`.
    ///
    /// Preview tiles are sixteen by nine at the configured width, floored so a
    /// tile never shrinks below legibility. Icon tiles are laid out for icons
    /// rather than for missing images: shorter, and never wider than a preview
    /// would have been, so switching mode never makes a panel grow.
    public static func tileSize(for mode: TileMode, previewWidth: CGFloat) -> CGSize {
        let width = max(120, previewWidth)
        switch mode {
        case .previews:
            return CGSize(width: width, height: (width * 9 / 16).rounded())
        case .icons:
            return CGSize(width: min(width, 150), height: 84)
        }
    }
}
