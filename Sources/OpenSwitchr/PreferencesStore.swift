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
        static let launchAtLogin = "launchAtLogin"
        static let dockHoverInstantSwitch = "dockHoverInstantSwitch"
        static let switcherApplicationScope = "switcherApplicationScope"
        static let switcherMinimizedPolicy = "switcherMinimizedPolicy"
        static let switcherScreenScope = "switcherScreenScope"
        static let switcherOrder = "switcherOrder"
    }

    private let defaults: UserDefaults

    /// The default for anything added here lives exactly once, because a
    /// registered default and the fallback used when a stored value no longer
    /// parses are two places for the same number, and they have drifted apart
    /// in this file's history before.
    private enum Default {
        static let dockHoverInstantSwitch = true
        static let applicationScope = WindowFilter.ApplicationScope.all
        static let minimizedPolicy = WindowFilter.MinimizedPolicy.show
        static let screenScope = WindowFilter.ScreenScope.allScreens
        static let order = WindowFilter.Order.recentlyUsed
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
            order: switcherOrder
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
            Key.switcherApplicationScope: Default.applicationScope.rawValue,
            Key.switcherMinimizedPolicy: Default.minimizedPolicy.rawValue,
            Key.switcherScreenScope: Default.screenScope.rawValue,
            Key.switcherOrder: Default.order.rawValue
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

        // Same fallback rule as the hold modifier: a stored value the app no
        // longer recognises means the case was removed, so it reverts to the
        // registered default rather than leaving the switcher without a filter.
        switcherApplicationScope = WindowFilter.ApplicationScope(
            rawValue: defaults.string(forKey: Key.switcherApplicationScope) ?? ""
        ) ?? Default.applicationScope
        switcherMinimizedPolicy = WindowFilter.MinimizedPolicy(
            rawValue: defaults.string(forKey: Key.switcherMinimizedPolicy) ?? ""
        ) ?? Default.minimizedPolicy
        switcherScreenScope = WindowFilter.ScreenScope(
            rawValue: defaults.string(forKey: Key.switcherScreenScope) ?? ""
        ) ?? Default.screenScope
        switcherOrder = WindowFilter.Order(
            rawValue: defaults.string(forKey: Key.switcherOrder) ?? ""
        ) ?? Default.order

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
