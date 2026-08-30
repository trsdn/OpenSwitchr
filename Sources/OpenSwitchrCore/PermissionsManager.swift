import AppKit
import CoreGraphics
import Foundation
import Observation

/// Tracks the two TCC permissions OpenSwitchr depends on.
///
/// Accessibility is mandatory: without it there is no window list, no hotkey
/// tap, and no way to raise a window. Screen recording is optional and only
/// gates thumbnails — the switcher stays fully usable with icon tiles.
@MainActor
@Observable
public final class PermissionsManager {

    public enum Status: Equatable, Sendable {
        case granted
        case denied
    }

    public private(set) var accessibility: Status = .denied
    public private(set) var screenRecording: Status = .denied

    /// Accessibility is required for the app to do anything at all.
    public var isOperational: Bool { accessibility == .granted }

    /// Called when accessibility flips from denied to granted, so the app can
    /// start itself instead of waiting for the user to find a "try again"
    /// button they have no reason to expect.
    public var onAccessibilityGranted: (() -> Void)?

    private var pollTimer: Timer?
    private var watchDeadline: Date?

    public init() {
        refresh()
    }

    /// Stops the pending-grant watcher. The timer is main-actor isolated and
    /// therefore cannot be torn down from `deinit`.
    public func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func refresh() {
        accessibility = AXBridge.isTrusted ? .granted : .denied
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Shows the system prompt that deep-links into System Settings.
    public func requestAccessibility() {
        _ = AXBridge.checkTrust(prompt: true)
        startWatchingForGrant(timeout: Self.promptTimeout)
    }

    public func requestScreenRecording() {
        // The first call triggers the system prompt; the result only becomes
        // true after the user grants it, hence the watcher below.
        _ = CGRequestScreenCaptureAccess()
        startWatchingForGrant(timeout: Self.promptTimeout)
    }

    /// Waits for a grant the app did not prompt for, which is the normal case:
    /// the user opens System Settings themselves, or the permission is granted
    /// long after launch. There is no deadline here because an app that is
    /// idle without the permission has nothing else to do, and the watcher
    /// stops the moment accessibility arrives.
    public func watchForAccessibilityGrant() {
        guard accessibility == .denied else { return }
        startWatchingForGrant(timeout: nil)
    }

    public func openAccessibilitySettings() {
        openSettings(anchor: "Privacy_Accessibility")
    }

    public func openScreenRecordingSettings() {
        openSettings(anchor: "Privacy_ScreenCapture")
    }

    private func openSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Granting a TCC permission produces no notification, so this is the one
    /// place where polling is acceptable. It only runs while a grant is
    /// pending and stops as soon as the outcome is settled.
    private func startWatchingForGrant(timeout: TimeInterval?) {
        pollTimer?.invalidate()
        watchDeadline = timeout.map { Date().addingTimeInterval($0) }

        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.checkPendingGrant()
            }
        }
    }

    private func checkPendingGrant() {
        let wasDenied = accessibility == .denied
        refresh()

        if wasDenied && accessibility == .granted {
            onAccessibilityGranted?()
        }

        let expired = watchDeadline.map { Date() > $0 } ?? false
        if Self.shouldStopWatching(
            accessibility: accessibility,
            screenRecording: screenRecording,
            expired: expired
        ) {
            stopWatching()
        }
    }

    /// Split out from the timer so the stop condition can be tested without
    /// TCC, which no test can influence. Pure, hence `nonisolated`.
    nonisolated static func shouldStopWatching(
        accessibility: Status,
        screenRecording: Status,
        expired: Bool
    ) -> Bool {
        if expired { return true }
        return accessibility == .granted && screenRecording == .granted
    }

    private static let pollInterval: TimeInterval = 1.0
    private static let promptTimeout: TimeInterval = 120
}
