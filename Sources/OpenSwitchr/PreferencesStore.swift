import Foundation
import Observation
import OpenSwitchrCore
import ServiceManagement

/// User preferences, stored in `UserDefaults` — no separate plist.
@MainActor
@Observable
public final class PreferencesStore {

    private enum Key {
        static let holdModifier = "holdModifier"
        static let switcherEnabled = "switcherEnabled"
        static let dockHoverEnabled = "dockHoverEnabled"
        static let dockHoverDelay = "dockHoverDelay"
        static let dockHideDelay = "dockHideDelay"
        static let thumbnailBudgetMB = "thumbnailBudgetMB"
        static let thumbnailRefreshRate = "thumbnailRefreshRate"
        static let tileWidth = "tileWidth"
        static let showCloseButton = "showCloseButton"
        static let tilePreference = "tilePreference"
        static let appRules = "appRules"
        static let secondHotkeyEnabled = "secondHotkeyEnabled"
        static let dockScrollCycling = "dockScrollCycling"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let fitTilesToWindowCount = "fitTilesToWindowCount"
        static let launchAtLogin = "launchAtLogin"
        static let dockHoverInstantSwitch = "dockHoverInstantSwitch"
        static let switcherApplicationScope = "switcherApplicationScope"
        static let switcherMinimizedPolicy = "switcherMinimizedPolicy"
        static let switcherWindowless = "switcherWindowless"
        static let switcherScreenScope = "switcherScreenScope"
        static let switcherOrder = "switcherOrder"
    }

    private let defaults: UserDefaults

    /// The default for anything added here lives exactly once, because a
    /// registered default and the fallback used when a stored value no longer
    /// parses are two spellings of the same value, and they have drifted apart
    /// in this file's history before.
    private enum Default {
        static let dockHoverInstantSwitch = true
        static let tilePreference = TilePreference.previews
        static let fitTilesToWindowCount = true
        static let secondHotkeyEnabled = false
        static let dockScrollCycling = false
        static let automaticUpdateChecks = true

        /// Derived rather than restated: `WindowFilter.switcherDefault` is the
        /// one place the switcher's starting profile is written down.
        static let filter = WindowFilter.switcherDefault
    }

    // Every preference is a *stored* property that writes through to
    // UserDefaults on change. The @Observable macro only tracks stored
    // properties: computed accessors over UserDefaults are invisible to
    // SwiftUI, so a Picker would write the new value and then re-render with
    // the old one, which looks exactly like a setting that refuses to change.

    public var holdModifier: HotkeyMonitor.HoldModifier {
        didSet { defaults.set(holdModifier.rawValue, forKey: Key.holdModifier) }
    }

    public var switcherEnabled: Bool {
        didSet { defaults.set(switcherEnabled, forKey: Key.switcherEnabled) }
    }

    public var dockHoverEnabled: Bool {
        didSet { defaults.set(dockHoverEnabled, forKey: Key.dockHoverEnabled) }
    }

    public var dockHoverDelay: TimeInterval {
        didSet { defaults.set(dockHoverDelay, forKey: Key.dockHoverDelay) }
    }

    public var dockHideDelay: TimeInterval {
        didSet { defaults.set(dockHideDelay, forKey: Key.dockHideDelay) }
    }

    /// Whether the hover delay applies only to the first preview.
    ///
    /// The delay exists so that sweeping across the Dock on the way somewhere
    /// else does not fire a panel. Once one is open the user has already said
    /// what they want, and waiting again for every icon they move onto reads as
    /// the app lagging.
    public var dockHoverInstantSwitch: Bool {
        didSet { defaults.set(dockHoverInstantSwitch, forKey: Key.dockHoverInstantSwitch) }
    }

    // The switcher's filter profile. The Dock preview does not get one: it is
    // already scoped to the application under the pointer, so every further
    // restriction could only hide windows the user pointed at.

    public var switcherApplicationScope: WindowFilter.ApplicationScope {
        didSet { defaults.set(switcherApplicationScope.rawValue, forKey: Key.switcherApplicationScope) }
    }

    public var switcherWindowless: WindowFilter.WindowlessPolicy {
        didSet { defaults.set(switcherWindowless.rawValue, forKey: Key.switcherWindowless) }
    }

    public var switcherMinimizedPolicy: WindowFilter.MinimizedPolicy {
        didSet { defaults.set(switcherMinimizedPolicy.rawValue, forKey: Key.switcherMinimizedPolicy) }
    }

    public var switcherScreenScope: WindowFilter.ScreenScope {
        didSet { defaults.set(switcherScreenScope.rawValue, forKey: Key.switcherScreenScope) }
    }

    public var switcherOrder: WindowFilter.Order {
        didSet { defaults.set(switcherOrder.rawValue, forKey: Key.switcherOrder) }
    }

    /// The four axes as the one value the switcher actually applies.
    public var switcherFilter: WindowFilter {
        WindowFilter(
            applications: switcherApplicationScope,
            minimized: switcherMinimizedPolicy,
            screens: switcherScreenScope,
            order: switcherOrder,
            windowless: switcherWindowless
        )
    }

    public var thumbnailBudgetMB: Int {
        didSet { defaults.set(thumbnailBudgetMB, forKey: Key.thumbnailBudgetMB) }
    }

    public var tileWidth: Double {
        didSet { defaults.set(tileWidth, forKey: Key.tileWidth) }
    }

    public var thumbnailRefreshRate: ThumbnailRefreshRate {
        didSet { defaults.set(thumbnailRefreshRate.rawValue, forKey: Key.thumbnailRefreshRate) }
    }

    /// Off by default. A close control sits one pixel from a click target that
    /// focuses a window, and losing unsaved work to a misclick is a far worse
    /// first impression than having to enable a setting.
    public var showCloseButton: Bool {
        didSet { defaults.set(showCloseButton, forKey: Key.showCloseButton) }
    }

    /// What the user asked for; the automatic rules in `TileModePolicy` can
    /// still move a surface to icons on their own, never the other way.
    public var tilePreference: TilePreference {
        didSet { defaults.set(tilePreference.rawValue, forKey: Key.tilePreference) }
    }

    /// On by default: it only ever makes switcher tiles smaller so every
    /// window fits without scrolling, and the configured width stays the upper
    /// limit, so nobody's chosen size is exceeded.
    public var fitTilesToWindowCount: Bool {
        didSet { defaults.set(fitTilesToWindowCount, forKey: Key.fitTilesToWindowCount) }
    }

    /// The per-application rules. Nothing stored means the shipped defaults,
    /// and so does stored data that no longer parses: falling back to an empty
    /// table would silently switch off the stand-aside protection.
    public var appRules: AppRuleTable {
        didSet {
            if let data = try? appRules.encoded() {
                defaults.set(data, forKey: Key.appRules)
            }
        }
    }

    /// Off by default: the backtick key is the macOS shortcut for cycling an
    /// application's own windows, and turning this on replaces it.
    public var secondHotkeyEnabled: Bool {
        didSet { defaults.set(secondHotkeyEnabled, forKey: Key.secondHotkeyEnabled) }
    }

    /// Off by default: it takes over scrolling while the pointer is on a Dock
    /// icon, which the Dock otherwise handles itself.
    public var dockScrollCycling: Bool {
        didSet { defaults.set(dockScrollCycling, forKey: Key.dockScrollCycling) }
    }

    /// On by default, like the updater in the sibling apps: an app that installs
    /// code should not need to be told to look for fixes. It is the only thing
    /// here that opens a network connection, and turning it off stops that.
    public var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: Key.automaticUpdateChecks) }
    }

    /// When the last automatic check ran, so a relaunch does not check again the
    /// same day. Internal state, not a preference the user sets.
    public var lastUpdateCheck: Date? {
        didSet {
            if let lastUpdateCheck {
                defaults.set(lastUpdateCheck.timeIntervalSince1970, forKey: Key.lastUpdateCheck)
            } else {
                defaults.removeObject(forKey: Key.lastUpdateCheck)
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.holdModifier: HotkeyMonitor.HoldModifier.command.rawValue,
            Key.switcherEnabled: true,
            Key.dockHoverEnabled: true,
            Key.dockHoverDelay: 0.18,
            Key.dockHideDelay: 0.25,
            Key.dockHoverInstantSwitch: Default.dockHoverInstantSwitch,
            Key.thumbnailBudgetMB: 96,
            Key.thumbnailRefreshRate: ThumbnailRefreshRate.default.rawValue,
            Key.tileWidth: 200.0,
            Key.showCloseButton: false,
            Key.tilePreference: Default.tilePreference.rawValue,
            Key.secondHotkeyEnabled: Default.secondHotkeyEnabled,
            Key.dockScrollCycling: Default.dockScrollCycling,
            Key.automaticUpdateChecks: Default.automaticUpdateChecks,
            Key.fitTilesToWindowCount: Default.fitTilesToWindowCount,
            Key.switcherApplicationScope: Default.filter.applications.rawValue,
            Key.switcherMinimizedPolicy: Default.filter.minimized.rawValue,
            Key.switcherWindowless: Default.filter.windowless.rawValue,
            Key.switcherScreenScope: Default.filter.screens.rawValue,
            Key.switcherOrder: Default.filter.order.rawValue
        ])

        // An unknown stored modifier means the value was removed from the app,
        // so it falls back rather than leaving the switcher without a hotkey.
        holdModifier = HotkeyMonitor.HoldModifier(
            rawValue: defaults.string(forKey: Key.holdModifier) ?? ""
        ) ?? .command
        switcherEnabled = defaults.bool(forKey: Key.switcherEnabled)
        dockHoverEnabled = defaults.bool(forKey: Key.dockHoverEnabled)
        dockHoverDelay = defaults.double(forKey: Key.dockHoverDelay)
        dockHideDelay = defaults.double(forKey: Key.dockHideDelay)
        dockHoverInstantSwitch = defaults.bool(forKey: Key.dockHoverInstantSwitch)
        thumbnailBudgetMB = defaults.integer(forKey: Key.thumbnailBudgetMB)
        thumbnailRefreshRate = ThumbnailRefreshRate(
            rawValue: defaults.string(forKey: Key.thumbnailRefreshRate) ?? ""
        ) ?? .default
        tileWidth = defaults.double(forKey: Key.tileWidth)
        showCloseButton = defaults.bool(forKey: Key.showCloseButton)
        fitTilesToWindowCount = defaults.bool(forKey: Key.fitTilesToWindowCount)
        appRules = AppRuleTable.decode(from: defaults.data(forKey: Key.appRules))
        secondHotkeyEnabled = defaults.bool(forKey: Key.secondHotkeyEnabled)
        dockScrollCycling = defaults.bool(forKey: Key.dockScrollCycling)
        automaticUpdateChecks = defaults.bool(forKey: Key.automaticUpdateChecks)
        lastUpdateCheck = (defaults.object(forKey: Key.lastUpdateCheck) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
        tilePreference = TilePreference(
            rawValue: defaults.string(forKey: Key.tilePreference) ?? ""
        ) ?? Default.tilePreference

        // Same fallback rule as the hold modifier: a stored value the app no
        // longer recognises means the case was removed, so it reverts to the
        // registered default rather than leaving the switcher without a filter.
        switcherApplicationScope = WindowFilter.ApplicationScope(
            rawValue: defaults.string(forKey: Key.switcherApplicationScope) ?? ""
        ) ?? Default.filter.applications
        switcherWindowless = WindowFilter.WindowlessPolicy(
            rawValue: defaults.string(forKey: Key.switcherWindowless) ?? ""
        ) ?? Default.filter.windowless
        switcherMinimizedPolicy = WindowFilter.MinimizedPolicy(
            rawValue: defaults.string(forKey: Key.switcherMinimizedPolicy) ?? ""
        ) ?? Default.filter.minimized
        switcherScreenScope = WindowFilter.ScreenScope(
            rawValue: defaults.string(forKey: Key.switcherScreenScope) ?? ""
        ) ?? Default.filter.screens
        switcherOrder = WindowFilter.Order(
            rawValue: defaults.string(forKey: Key.switcherOrder) ?? ""
        ) ?? Default.filter.order

        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Mirrors the real registration state rather than trusting a stored flag,
    /// but has to be a stored property so SwiftUI can observe it. The setter
    /// performs the registration and then re-reads what the system actually
    /// did, so a failed registration snaps the toggle back instead of lying.
    public var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration fails for unsigned or non-bundled builds.
            }

            let actual = SMAppService.mainApp.status == .enabled
            if actual != launchAtLogin {
                launchAtLogin = actual
            }
        }
    }
}
