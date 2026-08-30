import Testing

@testable import OpenSwitchrCore

/// The grant watcher is the one place OpenSwitchr polls, so its stop condition
/// decides whether an idle app ever settles down again. TCC itself cannot be
/// driven from a test, so the decision is tested in isolation from it.
@Suite("PermissionsManager grant watcher")
struct PermissionsManagerTests {

    @Test("Stops once both permissions are granted")
    func stopsWhenFullyGranted() {
        #expect(
            PermissionsManager.shouldStopWatching(
                accessibility: .granted,
                screenRecording: .granted,
                expired: false
            )
        )
    }

    @Test("Keeps waiting while accessibility is still missing")
    func keepsWaitingWithoutAccessibility() {
        #expect(
            !PermissionsManager.shouldStopWatching(
                accessibility: .denied,
                screenRecording: .granted,
                expired: false
            )
        )
    }

    /// Screen recording only gates thumbnails, but the watcher also reports
    /// it, so a pending screen recording grant must not end the watch early.
    @Test("Keeps waiting while screen recording is still missing")
    func keepsWaitingWithoutScreenRecording() {
        #expect(
            !PermissionsManager.shouldStopWatching(
                accessibility: .granted,
                screenRecording: .denied,
                expired: false
            )
        )
    }

    /// A prompt-triggered watch is bounded. Without this the timer would
    /// outlive the prompt the user dismissed and poll forever.
    @Test("A deadline always wins")
    func expiryStopsTheWatch() {
        #expect(
            PermissionsManager.shouldStopWatching(
                accessibility: .denied,
                screenRecording: .denied,
                expired: true
            )
        )
    }
}
