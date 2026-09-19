import Testing

@testable import OpenSwitchrCore

@Suite("WindowAdmission")
struct WindowAdmissionTests {

    @Test("A window with an accessibility counterpart is admitted whatever else is true")
    func linkedAlwaysAdmitted() {
        #expect(WindowAdmission.admits(hasAccessibilityLink: true, isOnScreen: false, title: nil))
        #expect(WindowAdmission.admits(hasAccessibilityLink: true, isOnScreen: true, title: ""))
    }

    @Test("An unlinked, titled, on-screen window is admitted")
    func unlinkedButRealIsAdmitted() {
        #expect(WindowAdmission.admits(hasAccessibilityLink: false, isOnScreen: true, title: "Document"))
    }

    @Test("An unlinked window that is not on screen is dropped")
    func unlinkedOffScreenIsDropped() {
        // Another Space, or a hidden surface: no accessibility element to act
        // on and nothing on screen to identify it by.
        #expect(!WindowAdmission.admits(hasAccessibilityLink: false, isOnScreen: false, title: "Document"))
    }

    @Test("An unlinked window with no title is dropped, whether the title is nil or empty")
    func unlinkedUntitledIsDropped() {
        // The untitled helper and overlay surfaces apps keep around. An empty
        // title alone is not the signal: plenty of real windows are untitled
        // while loading, which is why a link rescues them above.
        #expect(!WindowAdmission.admits(hasAccessibilityLink: false, isOnScreen: true, title: nil))
        #expect(!WindowAdmission.admits(hasAccessibilityLink: false, isOnScreen: true, title: ""))
    }
}
