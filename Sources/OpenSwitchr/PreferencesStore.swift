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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.holdModifier: HotkeyMonitor.HoldModifier.option.rawValue,
            Key.switcherEnabled: true,
            Key.dockHoverEnabled: true,
            Key.dockHoverDelay: 0.18,
            Key.dockHideDelay: 0.25,
            Key.thumbnailBudgetMB: 96,
            Key.tileWidth: 200.0
        ])
    }

    public var holdModifier: HotkeyMonitor.HoldModifier {
        get {
            HotkeyMonitor.HoldModifier(rawValue: defaults.string(forKey: Key.holdModifier) ?? "") ?? .option
        }
        set { defaults.set(newValue.rawValue, forKey: Key.holdModifier) }
    }

    public var switcherEnabled: Bool {
        get { defaults.bool(forKey: Key.switcherEnabled) }
        set { defaults.set(newValue, forKey: Key.switcherEnabled) }
    }

    public var dockHoverEnabled: Bool {
        get { defaults.bool(forKey: Key.dockHoverEnabled) }
        set { defaults.set(newValue, forKey: Key.dockHoverEnabled) }
    }

    public var dockHoverDelay: TimeInterval {
        get { defaults.double(forKey: Key.dockHoverDelay) }
        set { defaults.set(newValue, forKey: Key.dockHoverDelay) }
    }

    public var dockHideDelay: TimeInterval {
        get { defaults.double(forKey: Key.dockHideDelay) }
        set { defaults.set(newValue, forKey: Key.dockHideDelay) }
    }

    public var thumbnailBudgetMB: Int {
        get { defaults.integer(forKey: Key.thumbnailBudgetMB) }
        set { defaults.set(newValue, forKey: Key.thumbnailBudgetMB) }
    }

    public var tileWidth: Double {
        get { defaults.double(forKey: Key.tileWidth) }
        set { defaults.set(newValue, forKey: Key.tileWidth) }
    }

    /// Reflects the real registration state rather than a stored flag, so the
    /// UI cannot drift from what the system actually does.
    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration fails for unsigned or non-bundled builds; the
                // toggle simply stays off in that case.
            }
        }
    }
}
