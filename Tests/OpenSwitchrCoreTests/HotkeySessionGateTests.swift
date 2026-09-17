import Testing

@testable import OpenSwitchrCore

@Suite("HotkeySessionGate")
struct HotkeySessionGateTests {

    @Test("A release with no session requested and the overlay not visible does not commit")
    func idleDoesNotCommit() {
        let gate = HotkeySessionGate()
        #expect(gate.shouldCommitOnRelease(overlayVisible: false) == false)
    }

    @Test("A release while the overlay is already visible commits")
    func visibleCommits() {
        let gate = HotkeySessionGate()
        #expect(gate.shouldCommitOnRelease(overlayVisible: true) == true)
    }

    @Test("A release in the gap between opening and the overlay reporting visible still commits")
    func openedButNotYetVisibleCommits() {
        var gate = HotkeySessionGate()
        gate.opened()
        #expect(gate.shouldCommitOnRelease(overlayVisible: false) == true)
    }

    @Test("Once the controller reports visibility, the pending request is cleared")
    func visibilityReportedClearsThePendingRequest() {
        var gate = HotkeySessionGate()
        gate.opened()
        gate.visibilityReported()
        #expect(gate.shouldCommitOnRelease(overlayVisible: false) == false)
    }

    @Test("A later open starts a fresh pending window after a previous session ended")
    func reopeningAfterASessionEndedIsPendingAgain() {
        var gate = HotkeySessionGate()
        gate.opened()
        gate.visibilityReported()
        gate.opened()
        #expect(gate.shouldCommitOnRelease(overlayVisible: false) == true)
    }
}
