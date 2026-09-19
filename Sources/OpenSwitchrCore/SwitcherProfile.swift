import Foundation

/// Which question the switcher is answering when it opens.
///
/// A second hotkey is cheap in principle and expensive in practice: it adds a
/// chord to detect in a callback that must stay trivial, and a settings surface
/// that doubles if every filter axis appears twice. This keeps both down. The
/// second profile is *fixed* — "this application's windows", which is awkward to
/// say as a search query — and inherits every other axis from the configured
/// filter, so there is one toggle and no second copy of the settings.
public enum SwitcherProfile: Equatable, Sendable {
    /// Everything the user's configured filter lists.
    case configured
    /// The frontmost application's windows only.
    case currentApplication

    private static let tabKeyCode = 48
    private static let graveKeyCode = 50

    /// The profile a key opens, or `nil` if it is not a switcher key.
    ///
    /// A lookup on an integer, so the event tap callback stays trivial: the
    /// decision lives here where it can be tested, not in the callback.
    public static func profile(forKeyCode keyCode: Int, secondHotkeyEnabled: Bool) -> SwitcherProfile? {
        switch keyCode {
        case tabKeyCode: return .configured
        case graveKeyCode: return secondHotkeyEnabled ? .currentApplication : nil
        default: return nil
        }
    }

    /// `base`, adjusted for this profile. Only the application scope ever
    /// changes; every other axis stays what the user configured.
    public func filter(from base: WindowFilter) -> WindowFilter {
        switch self {
        case .configured:
            return base
        case .currentApplication:
            var filter = base
            filter.applications = .frontmostOnly
            return filter
        }
    }
}
