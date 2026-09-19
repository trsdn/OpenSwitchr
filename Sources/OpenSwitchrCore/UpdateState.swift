import Foundation

/// When an automatic update check is due.
///
/// Pure, with the clock passed in. The caller wakes on a short interval and asks
/// this whether a check is actually due, rather than sleeping for a full day: a
/// Mac that sleeps through the deadline would otherwise miss a plain 24-hour timer
/// indefinitely.
public enum UpdateSchedule {

    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static let wakeInterval: TimeInterval = 60 * 60

    public static func isDue(enabled: Bool, lastCheck: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        // A last check in the future means the clock moved back; treating it as
        // due beats being stuck until the clock catches up.
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }
}

/// Where an update check or install has got to.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case downloading(version: String)
    case readyToInstall(version: String)
    case installing
    case failed(String)
    /// The app already shut its own work down for the install, so the only way
    /// back to a working app is a relaunch.
    case installFailed(String)

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    public var isReadyToInstall: Bool {
        if case .readyToInstall = self { return true }
        return false
    }

    /// A failed background check stays out of sight: being offline is not worth
    /// a banner. A check the user asked for always answers.
    public static func afterFailure(_ message: String, userInitiated: Bool) -> UpdateState {
        userInitiated ? .failed(message) : .idle
    }

    public static func afterNoUpdate(userInitiated: Bool) -> UpdateState {
        userInitiated ? .upToDate : .idle
    }
}
