import Foundation
import Testing

@testable import OpenSwitchrCore

@Suite("UpdateSchedule")
struct UpdateScheduleTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("A check is due when none has ever run")
    func neverChecked() {
        #expect(UpdateSchedule.isDue(enabled: true, lastCheck: nil, now: now))
    }

    @Test("It is not due again within a day")
    func notDueSoon() {
        let last = now.addingTimeInterval(-(UpdateSchedule.checkInterval - 60))
        #expect(!UpdateSchedule.isDue(enabled: true, lastCheck: last, now: now))
    }

    @Test("It is due once a full day has passed")
    func dueAfterADay() {
        let last = now.addingTimeInterval(-UpdateSchedule.checkInterval)
        #expect(UpdateSchedule.isDue(enabled: true, lastCheck: last, now: now))
    }

    @Test("Turning automatic checks off means never due, however long ago the last one was")
    func disabledNeverDue() {
        #expect(!UpdateSchedule.isDue(enabled: false, lastCheck: nil, now: now))
        #expect(!UpdateSchedule.isDue(enabled: false, lastCheck: .distantPast, now: now))
    }

    @Test("A last check in the future, from a clock that moved back, is due rather than stuck")
    func clockWentBackwards() {
        let last = now.addingTimeInterval(365 * 24 * 3600)
        #expect(UpdateSchedule.isDue(enabled: true, lastCheck: last, now: now))
    }

    @Test("The loop wakes more often than it checks, so a Mac that slept through the deadline catches up")
    func wakesMoreOftenThanItChecks() {
        #expect(UpdateSchedule.wakeInterval < UpdateSchedule.checkInterval)
    }
}

@Suite("UpdateState")
struct UpdateStateTests {

    @Test("Only checking, downloading and installing are busy")
    func busyStates() {
        #expect(UpdateState.checking.isBusy)
        #expect(UpdateState.downloading(version: "1.2.0").isBusy)
        #expect(UpdateState.installing.isBusy)
        #expect(!UpdateState.idle.isBusy)
        #expect(!UpdateState.upToDate.isBusy)
        #expect(!UpdateState.readyToInstall(version: "1.2.0").isBusy)
        #expect(!UpdateState.failed("x").isBusy)
    }

    @Test("A failed background check stays silent: being offline is not worth a banner")
    func backgroundFailureIsSilent() {
        #expect(UpdateState.afterFailure("offline", userInitiated: false) == .idle)
    }

    @Test("A check the user asked for always answers")
    func userFailureIsShown() {
        #expect(UpdateState.afterFailure("offline", userInitiated: true) == .failed("offline"))
    }

    @Test("No update found says so only to a user who asked")
    func noUpdateAnswer() {
        #expect(UpdateState.afterNoUpdate(userInitiated: true) == .upToDate)
        #expect(UpdateState.afterNoUpdate(userInitiated: false) == .idle)
    }

    @Test("Only a ready update can be installed")
    func installable() {
        #expect(UpdateState.readyToInstall(version: "1.2.0").isReadyToInstall)
        #expect(!UpdateState.downloading(version: "1.2.0").isReadyToInstall)
        #expect(!UpdateState.idle.isReadyToInstall)
    }
}
