import CoreGraphics
import Testing

@testable import OpenSwitchrCore

@Suite("WindowlessApplications")
struct WindowlessApplicationsTests {

    private func app(_ pid: pid_t, _ name: String, bundleID: String? = nil) -> RunningApplication {
        RunningApplication(pid: pid, bundleID: bundleID ?? "com.example.\(name.lowercased())", name: name)
    }

    @Test("Only applications with no window in the index become entries")
    func onlyWindowless() {
        let entries = WindowlessApplications.entries(
            running: [app(10, "Safari"), app(20, "Notes"), app(30, "Mail")],
            windowedPIDs: [10, 30],
            ownPID: 1
        )
        #expect(entries.map(\.pid) == [20])
    }

    @Test("Our own process is never listed")
    func excludesSelf() {
        let entries = WindowlessApplications.entries(running: [app(1, "OpenSwitchr")], windowedPIDs: [], ownPID: 1)
        #expect(entries.isEmpty)
    }

    @Test("An entry stands for the application: its name is the title, and it is marked application-only")
    func entryShape() throws {
        let entry = try #require(
            WindowlessApplications.entries(running: [app(20, "Notes")], windowedPIDs: [], ownPID: 1).first
        )
        #expect(entry.isApplicationOnly)
        #expect(entry.appName == "Notes")
        #expect(entry.displayTitle == "Notes")
        #expect(entry.bundleID == "com.example.notes")
        #expect(entry.element == nil)
        #expect(!entry.isMinimized)
    }

    @Test("Entries get distinct identities that cannot collide with a real window id")
    func syntheticIdentities() {
        let entries = WindowlessApplications.entries(
            running: [app(20, "Notes"), app(21, "Maps")],
            windowedPIDs: [],
            ownPID: 1
        )
        #expect(Set(entries.map(\.id)).count == 2)
        #expect(entries.allSatisfy { $0.id >= WindowlessApplications.idBase })
        #expect(WindowlessApplications.isApplicationOnly(id: entries[0].id))
        #expect(!WindowlessApplications.isApplicationOnly(id: 4_242))
    }

    @Test("Entries are ordered by name, so the list does not shuffle between opens")
    func orderedByName() {
        let entries = WindowlessApplications.entries(
            running: [app(3, "zed"), app(1, "Arc"), app(2, "Mail")],
            windowedPIDs: [],
            ownPID: 99
        )
        #expect(entries.map(\.appName) == ["Arc", "Mail", "zed"])
    }
}
