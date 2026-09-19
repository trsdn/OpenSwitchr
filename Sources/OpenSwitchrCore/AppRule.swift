import Foundation

/// A rule for one application, matched by a bundle-identifier prefix.
///
/// Prefix rather than exact match so a vendor shipping several bundle ids —
/// an App Store build and a direct-download build, say — is covered by one
/// entry.
public struct AppRule: Equatable, Sendable {

    /// Whether a window belonging to this application is hidden from every
    /// surface.
    public enum HidePolicy: Equatable, Sendable {
        case never
        case always
        /// Hidden only when the window's title contains this substring,
        /// matched case-insensitively.
        case whenTitleContains(String)
    }

    public var bundleIDPrefix: String
    public var hide: HidePolicy

    /// Whether the switcher hotkey should stand aside entirely — swallow
    /// nothing, raise nothing — while this application is frontmost and one
    /// of its windows covers its screen's full frame.
    ///
    /// Decided on the event tap path, which `AGENTS.md` requires to stay
    /// trivial: see `AppRuleTable.shouldStandAside`.
    public var standAsideWhenFullScreen: Bool

    public init(
        bundleIDPrefix: String,
        hide: HidePolicy = .never,
        standAsideWhenFullScreen: Bool = false
    ) {
        self.bundleIDPrefix = bundleIDPrefix
        self.hide = hide
        self.standAsideWhenFullScreen = standAsideWhenFullScreen
    }
}

/// The per-application rule table both frontends and the event tap consult.
///
/// Two problems share this one mechanism: some applications contribute
/// windows nobody switches to, and some — a remote desktop, a screen share, a
/// virtual machine running full screen — need the switcher hotkey to reach
/// the guest rather than raise an overlay over it. The second is a
/// correctness bug, not a preference, which is why `defaults` ships
/// non-empty.
public struct AppRuleTable: Equatable, Sendable {
    public var rules: [AppRule]

    public init(rules: [AppRule] = []) {
        self.rules = rules
    }

    /// The rule covering a bundle identifier, or `nil` if none does.
    ///
    /// When more than one rule's prefix matches, the most specific one wins
    /// — the longest prefix — so a general entry and a more specific
    /// override for the same vendor can coexist.
    public func rule(forBundleID bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return
            rules
            .filter { bundleID.hasPrefix($0.bundleIDPrefix) }
            .max { $0.bundleIDPrefix.count < $1.bundleIDPrefix.count }
    }

    /// Whether `window` should be hidden from every surface.
    public func hides(_ window: WindowInfo) -> Bool {
        guard let rule = rule(forBundleID: window.bundleID) else { return false }
        switch rule.hide {
        case .never:
            return false
        case .always:
            return true
        case .whenTitleContains(let substring):
            guard !substring.isEmpty else { return false }
            return window.title.range(of: substring, options: .caseInsensitive) != nil
        }
    }

    /// Whether the switcher hotkey should stand aside entirely right now.
    ///
    /// A pure decision from already-resolved facts — never from a fresh
    /// `NSWorkspace` or accessibility read — so the caller can compute it
    /// once whenever the frontmost application or its full-screen state
    /// changes and hand a single `Bool` to the event tap, which stays free of
    /// preferences, accessibility, and `NSWorkspace` the same way
    /// `HotkeySessionGate` keeps the tap free of main-actor state.
    public func shouldStandAside(frontmostBundleID: String?, isFullScreen: Bool) -> Bool {
        guard isFullScreen, let rule = rule(forBundleID: frontmostBundleID) else { return false }
        return rule.standAsideWhenFullScreen
    }

    /// Remote desktop, screen sharing, and virtual machine applications:
    /// holding the switcher hotkey while one of these is full screen should
    /// reach the guest, not raise an overlay over it. None are hidden by
    /// default — only ``AppRule/standAsideWhenFullScreen`` is set — because
    /// hiding is a matter of personal setup this table cannot guess.
    ///
    /// Bundle-identifier prefixes verified against each vendor's current and
    /// known past identifiers where that could be confirmed; a prefix rather
    /// than an exact match absorbs a vendor renaming a build. Incomplete or
    /// wrong for an application not covered here — this is a starting table,
    /// not a exhaustive one.
    public static let defaults = AppRuleTable(rules: [
        // Microsoft Remote Desktop: "com.microsoft.rdc.macos" (current),
        // "com.microsoft.rdc.mac" (older).
        AppRule(bundleIDPrefix: "com.microsoft.rdc", standAsideWhenFullScreen: true),
        AppRule(bundleIDPrefix: "com.teamviewer.TeamViewer", standAsideWhenFullScreen: true),
        AppRule(bundleIDPrefix: "com.realvnc.vncviewer", standAsideWhenFullScreen: true),
        AppRule(bundleIDPrefix: "com.vmware.fusion", standAsideWhenFullScreen: true),
        // Parallels Desktop ships more than one build under this stem — at
        // least ".console" and ".AppStore" variants have been observed.
        AppRule(bundleIDPrefix: "com.parallels.desktop", standAsideWhenFullScreen: true),
        AppRule(bundleIDPrefix: "com.utmapp.UTM", standAsideWhenFullScreen: true),
        // Apple's own Screen Sharing.app, used for both local screen sharing
        // and remote Mac management.
        AppRule(bundleIDPrefix: "com.apple.ScreenSharing", standAsideWhenFullScreen: true),
    ])
}

// MARK: - Persistence and counts

public extension AppRuleTable {

    /// The stored shape: plain strings and a flag, so a hide policy added later
    /// does not make an older stored table unreadable. Kept apart from the
    /// in-memory types on purpose; those can change shape without touching
    /// what is on disk.
    private struct Stored: Codable {
        var rules: [StoredRule]
    }

    private struct StoredRule: Codable {
        var bundleIDPrefix: String
        var hideKind: String
        var hideText: String
        var standAside: Bool
    }

    func encoded() throws -> Data {
        let stored = Stored(
            rules: rules.map { rule in
                let kind: String
                var text = ""
                switch rule.hide {
                case .never: kind = "never"
                case .always: kind = "always"
                case .whenTitleContains(let substring):
                    kind = "titleContains"
                    text = substring
                }
                return StoredRule(
                    bundleIDPrefix: rule.bundleIDPrefix,
                    hideKind: kind,
                    hideText: text,
                    standAside: rule.standAsideWhenFullScreen
                )
            })
        return try JSONEncoder().encode(stored)
    }

    /// Reads a stored table.
    ///
    /// Nothing stored, or data that no longer parses, yields the shipped
    /// defaults rather than an empty table: an empty one would silently switch
    /// off the stand-aside protection for a remote session, which is the
    /// correctness half of the whole feature. A table the user emptied *on
    /// purpose* is stored as an empty list and stays empty. An unknown hide kind
    /// is read as "never hide", the harmless direction.
    static func decode(from data: Data?) -> AppRuleTable {
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return .defaults
        }
        return AppRuleTable(
            rules: stored.rules.map { entry in
                let hide: AppRule.HidePolicy
                switch entry.hideKind {
                case "always": hide = .always
                case "titleContains": hide = .whenTitleContains(entry.hideText)
                default: hide = .never
                }
                return AppRule(
                    bundleIDPrefix: entry.bundleIDPrefix,
                    hide: hide,
                    standAsideWhenFullScreen: entry.standAside
                )
            })
    }

    /// How many of `windows` this rule is currently hiding, so a settings row
    /// can say what a rule costs. A rule that hides everything becomes a bug
    /// report reading "the switcher is empty"; showing the number is how it
    /// gets noticed first.
    ///
    /// Counted against the rule that actually governs each window, so a general
    /// rule is not credited with windows a more specific one claimed.
    func hiddenCount(by rule: AppRule, in windows: [WindowInfo]) -> Int {
        windows.filter { window in
            self.rule(forBundleID: window.bundleID) == rule && hides(window)
        }.count
    }
}
