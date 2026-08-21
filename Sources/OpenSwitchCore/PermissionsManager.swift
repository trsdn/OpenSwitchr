import AppKit
import CoreGraphics
import Foundation
import Observation

/// Tracks the two TCC permissions OpenSwitch depends on.
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
        startWatchingForGrant()
    }

    public func requestScreenRecording() {
        // The first call triggers the system prompt; the result only becomes
        // true after the user grants it, hence the watcher below.
        _ = CGRequestScreenCaptureAccess()
        startWatchingForGrant()
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
    /// pending and stops the moment both permissions are resolved or after a
    /// bounded window of time.
    private func startWatchingForGrant() {
        pollTimer?.invalidate()
        watchDeadline = Date().addingTimeInterval(120)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.checkPendingGrant()
            }
        }
    }

    private func checkPendingGrant() {
        refresh()
        let expired = watchDeadline.map { Date() > $0 } ?? true
        if (accessibility == .granted && screenRecording == .granted) || expired {
            stopWatching()
        }
    }
}
