import CoreGraphics
import Foundation

/// Which windows a surface wants, and in what order.
///
/// Both frontends read the same ``WindowIndex``, and they do not want the same
/// set: a Dock preview is scoped to one application by definition, while the
/// switcher is scoped to everything worth switching to. Holding that difference
/// in one value type keeps it in data rather than in two call sites that drift,
/// and keeps it testable — this is cheap to unit test and expensive to get
/// subtly wrong, which is the same reason ``WindowMatcher`` is pure.
///
/// Applying a filter is a filter and a sort over a list that is already in
/// memory. It performs no accessibility read of its own: every axis is answered
/// from what the index already gathered, because cost tracks round trips.
///
/// Composition order is fixed and matters: **filter, then sort, then let a
/// search query re-rank.** ``WindowMatcher/filter(_:query:)`` keeps the incoming
/// order as its tie-breaker, so the sort has to have run before it.
public struct WindowFilter: Equatable, Sendable {

    /// Which applications contribute windows.
    public enum ApplicationScope: String, CaseIterable, Sendable {
        case all
        case frontmostOnly
        case excludingFrontmost

        public var title: String {
            switch self {
            case .all: return "All applications"
            case .frontmostOnly: return "Only the current application"
            case .excludingFrontmost: return "Everything but the current application"
            }
        }
    }

    /// What happens to windows that are sitting in the Dock.
    public enum MinimizedPolicy: String, CaseIterable, Sendable {
        case show
        case hide
        /// Kept, but moved behind every window that is not minimized.
        ///
        /// This is a partition, not a sort key. Expressing it inside a
        /// comparator yields something that is not a strict weak ordering, and
        /// `sort` is entitled to behave badly with one.
        case showAfterOthers

        public var title: String {
            switch self {
            case .show: return "Show"
            case .hide: return "Hide"
            case .showAfterOthers: return "Show after the rest"
            }
        }
    }

    /// Whether windows on other displays are worth offering.
    public enum ScreenScope: String, CaseIterable, Sendable {
        case allScreens
        case surfaceScreenOnly

        public var title: String {
            switch self {
            case .allScreens: return "All displays"
            case .surfaceScreenOnly: return "Only this display"
            }
        }
    }

    public enum Order: String, CaseIterable, Sendable {
        case recentlyUsed
        case recentlyOpened
        case alphabetical

        public var title: String {
            switch self {
            case .recentlyUsed: return "Most recently used"
            case .recentlyOpened: return "Most recently opened"
            case .alphabetical: return "Application, then title"
            }
        }
    }

    /// Everything the filter needs to know about the world it runs in.
    ///
    /// Passed in rather than read, so the type stays free of AppKit and can be
    /// tested without a window server.
    public struct Context: Equatable, Sendable {

        /// The application the user is currently in.
        ///
        /// When this is `nil` the application scope is not applied at all: an
        /// unknown frontmost application must not be allowed to empty the
        /// switcher, and showing one window too many is the far cheaper
        /// mistake.
        public var frontmostPID: pid_t?

        /// The screen the surface is about to appear on, **in the coordinate
        /// space `WindowInfo.frame` uses** — CoreGraphics, origin at the
        /// top-left of the primary display, y growing downwards. Converting an
        /// AppKit screen frame is the caller's job, because only the caller
        /// knows which screen it means.
        public var screenFrame: CGRect?

        public init(frontmostPID: pid_t? = nil, screenFrame: CGRect? = nil) {
            self.frontmostPID = frontmostPID
            self.screenFrame = screenFrame
        }

        /// Which pid the application scope should treat as the current
        /// application.
        ///
        /// The window server's frontmost application is the authoritative
        /// answer, and deliberately the *only* one used. Window order is not an
        /// acceptable substitute: the index promotes a newly *discovered*
        /// window above everything else, so any background application opening
        /// a window would be mistaken for the one the user is in — which is
        /// exactly wrong for both `frontmostOnly` and `excludingFrontmost`.
        ///
        /// It also must never be our own pid. The overlay is a non-activating
        /// panel precisely so the user's application stays frontmost, but if
        /// that ever stopped holding, scoping to a process with no windows in
        /// the index would empty the switcher — the one outcome it cannot
        /// recover from. Returning `nil` instead means the scope is ignored and
        /// everything is shown, which fails in the harmless direction.
        public static func frontmostPID(workspaceFrontmost: pid_t?, ownPID: pid_t) -> pid_t? {
            guard let workspaceFrontmost, workspaceFrontmost != ownPID else { return nil }
            return workspaceFrontmost
        }
    }

    public var applications: ApplicationScope
    public var minimized: MinimizedPolicy
    public var screens: ScreenScope
    public var order: Order

    public init(
        applications: ApplicationScope = .all,
        minimized: MinimizedPolicy = .show,
        screens: ScreenScope = .allScreens,
        order: Order = .recentlyUsed
    ) {
        self.applications = applications
        self.minimized = minimized
        self.screens = screens
        self.order = order
    }

    /// What a Dock preview asks for.
    ///
    /// Not configurable, and deliberately permissive: the panel is already
    /// scoped to one application by the icon the pointer is on, so every
    /// further restriction can only remove windows the user explicitly asked to
    /// see. Minimized windows especially — a window in the Dock is exactly what
    /// someone hovering the Dock is looking for.
    public static let dockPreview = WindowFilter(
        applications: .all,
        minimized: .show,
        screens: .allScreens,
        order: .recentlyUsed
    )

    /// What the switcher starts with: exactly the behaviour the app had before
    /// this type existed.
    ///
    /// This is the *only* place those defaults are written down. `PreferencesStore`
    /// registers them and falls back to them from here rather than repeating
    /// the values, because a registered default and its parsing fallback are
    /// two spellings of one number and they have drifted apart in this project
    /// before.
    public static let switcherDefault = WindowFilter()

    /// The vertical flip between AppKit's screen geometry and the CoreGraphics
    /// geometry `WindowInfo.frame` uses, with no AppKit involved so it can be
    /// tested against synthetic display layouts.
    ///
    /// AppKit measures y upwards from the bottom-left of the primary display;
    /// CoreGraphics measures it downwards from the top-left of the same
    /// display. Both agree on x. `NSScreen`-flavoured callers go through
    /// `coreGraphicsFrame(of:)`.
    public static func coreGraphicsFrame(appKitFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: primaryHeight - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    // MARK: - Application

    /// Filters and orders `windows`, which are expected to arrive
    /// most-recently-used first, the way ``WindowIndex`` keeps them.
    public func apply(to windows: [WindowInfo], context: Context = Context()) -> [WindowInfo] {
        order(kept(windows, context: context))
    }

    private func kept(_ windows: [WindowInfo], context: Context) -> [WindowInfo] {
        windows.filter { window in
            includesApplication(of: window, context: context)
                && (minimized != .hide || !window.isMinimized)
                && includesScreen(of: window, context: context)
        }
    }

    private func includesApplication(of window: WindowInfo, context: Context) -> Bool {
        guard let frontmost = context.frontmostPID else { return true }
        switch applications {
        case .all: return true
        case .frontmostOnly: return window.pid == frontmost
        case .excludingFrontmost: return window.pid != frontmost
        }
    }

    private func includesScreen(of window: WindowInfo, context: Context) -> Bool {
        guard screens == .surfaceScreenOnly, let screenFrame = context.screenFrame else { return true }

        // A minimized window is on no display at all, and the frame the window
        // server still reports for it says nothing useful. Restricting by
        // display would silently drop every minimized window as a side effect
        // of an unrelated setting.
        guard !window.isMinimized else { return true }

        // Intersection rather than containment: a window straddling two
        // displays belongs to both, and requiring containment would drop it
        // from every list.
        guard window.frame.width > 0, window.frame.height > 0 else { return true }
        return screenFrame.intersects(window.frame)
    }

    private func order(_ windows: [WindowInfo]) -> [WindowInfo] {
        let ordered: [WindowInfo]

        switch order {
        case .recentlyUsed:
            // The index already hands windows over most-recently-used first,
            // so this is deliberately the identity. Re-sorting by a rank the
            // filter cannot see would only be a chance to get it wrong.
            ordered = windows
        case .recentlyOpened:
            ordered = Self.stableSorted(windows) { $0.openedRank > $1.openedRank }
        case .alphabetical:
            ordered = Self.stableSorted(windows) { lhs, rhs in
                let byApplication = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
                if byApplication != .orderedSame { return byApplication == .orderedAscending }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
        }

        guard minimized == .showAfterOthers else { return ordered }
        return ordered.filter { !$0.isMinimized } + ordered.filter(\.isMinimized)
    }

    /// Sorts without letting equal elements move relative to each other.
    ///
    /// `Array.sorted(by:)` is explicitly *not* guaranteed stable, and equal
    /// keys are not an edge case here: two untitled windows of the same
    /// application compare equal on every field either comparator looks at, and
    /// windows sharing a title are common. Because the incoming order is
    /// most-recently-used and the list is re-ordered on every keystroke, an
    /// unstable result would let tiles swap places under the user's fingers
    /// for no reason. Decorating with the incoming position and using it as the
    /// final tie-break is the same trick `WindowMatcher` already uses.
    private static func stableSorted(
        _ windows: [WindowInfo],
        by areInIncreasingOrder: (WindowInfo, WindowInfo) -> Bool
    ) -> [WindowInfo] {
        windows.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
