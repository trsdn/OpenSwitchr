import AppUpdater
import Foundation
import Observation
import OpenSwitchrCore
import OSLog

/// Checks GitHub Releases for a newer OpenSwitchr and installs it in place.
///
/// Backed by [AppUpdater](https://github.com/mxcl/AppUpdater). It accepts only a
/// release asset named exactly `<repository>-<semver>.dmg` and only if the app
/// inside carries the same Developer ID Team ID, signing identifier and bundle
/// identifier as this one, so a swapped asset does not install.
///
/// GitHub artifact attestation is deliberately not required: the notarization
/// broker builds a release in its own repository, so there is no provenance from
/// `trsdn/OpenSwitchr` for AppUpdater to check against, and for a `swift build`
/// product its `Bundle.module` lookup never looks in `Contents/Resources`, which
/// makes verifying one end in a `fatalError`. The Developer ID checks still apply.
///
/// This is the only thing in the app that opens a network connection, and only
/// to GitHub. It is off the moment "Check for Updates Automatically" is, and a
/// manual check is always the user's own request.
@MainActor
@Observable
final class UpdateManager {

    private(set) var state: UpdateState = .idle

    /// Runs right before the bundle is replaced, so the app can let go of the
    /// event tap, the Dock observer and the panels instead of being killed
    /// mid-gesture. The Accessibility and Screen Recording grants are tied to the
    /// code signature, so it is the broker's job to keep that stable across
    /// updates; nothing here can.
    @ObservationIgnored var onWillInstall: (() -> Void)?

    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let updater = AppUpdater(owner: "trsdn", repo: "OpenSwitchr")
    @ObservationIgnored private let log = Logger(subsystem: "com.openswitchr.app", category: "updates")
    @ObservationIgnored private var preparedUpdate: PreparedUpdate?
    @ObservationIgnored private var automaticCheckTask: Task<Void, Never>?

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    // MARK: - Automatic checks

    /// Starts (or restarts) the background loop, or stops it when the setting is
    /// off. Safe to call whenever the setting changes.
    func applyAutomaticChecksSetting() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
        guard preferences.automaticUpdateChecks else { return }

        // Wakes hourly but checks at most once a day, so a Mac that sleeps
        // through the deadline still catches up.
        automaticCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self,
                   UpdateSchedule.isDue(
                       enabled: self.preferences.automaticUpdateChecks,
                       lastCheck: self.preferences.lastUpdateCheck,
                       now: Date()
                   ) {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(UpdateSchedule.wakeInterval))
            }
        }
    }

    func stopAutomaticChecks() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
    }

    // MARK: - Check, install, dismiss

    /// Looks for a newer release and, if there is one, downloads and validates it
    /// so that installing is a single click.
    func check(userInitiated: Bool) async {
        guard !state.isBusy, preparedUpdate == nil else { return }
        if userInitiated {
            state = .checking
        } else {
            preferences.lastUpdateCheck = Date()
        }

        do {
            guard let update = try await updater.check() else {
                log.info("No update available")
                state = .afterNoUpdate(userInitiated: userInitiated)
                return
            }
            log.notice("Update available: \(update.version, privacy: .public)")
            state = .downloading(version: update.version)
            preparedUpdate = try await update.prepareInstallation()
            state = .readyToInstall(version: update.version)
        } catch is CancellationError {
            state = .idle
        } catch {
            log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = .afterFailure(error.localizedDescription, userInitiated: userInitiated)
        }
    }

    /// Replaces the app and relaunches it. On success this never returns.
    func installAndRelaunch() async {
        guard let prepared = preparedUpdate else { return }
        preparedUpdate = nil
        state = .installing
        stopAutomaticChecks()
        onWillInstall?()

        do {
            try await prepared.installAndRelaunch()
        } catch {
            log.error("Install failed: \(error.localizedDescription, privacy: .public)")
            state = .installFailed(error.localizedDescription)
        }
    }

    /// Throws the downloaded update away. The next check finds it again.
    func dismiss() async {
        if let prepared = preparedUpdate {
            preparedUpdate = nil
            await prepared.discard()
        }
        state = .idle
    }
}
