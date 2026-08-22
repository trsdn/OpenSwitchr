import Foundation
import Observation
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
        static let tileWidth = "tileWidth"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

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

    public var thumbnailBudgetMB: Int {
        didSet { defaults.set(thumbnailBudgetMB, forKey: Key.thumbnailBudgetMB) }
    }

    public var tileWidth: Double {
        didSet { defaults.set(tileWidth, forKey: Key.tileWidth) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.holdModifier: HotkeyMonitor.HoldModifier.command.rawValue,
            Key.switcherEnabled: true,
            Key.dockHoverEnabled: true,
            Key.dockHoverDelay: 0.18,
            Key.dockHideDelay: 0.25,
            Key.thumbnailBudgetMB: 96,
            Key.tileWidth: 200.0
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
        thumbnailBudgetMB = defaults.integer(forKey: Key.thumbnailBudgetMB)
        tileWidth = defaults.double(forKey: Key.tileWidth)
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
