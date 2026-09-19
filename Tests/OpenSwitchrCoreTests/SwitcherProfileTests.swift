import Testing

@testable import OpenSwitchrCore

@Suite("SwitcherProfile")
struct SwitcherProfileTests {

    private let tab = 48
    private let grave = 50

    @Test("Tab always opens the switcher with the configured filter")
    func tabIsTheEverythingProfile() {
        #expect(SwitcherProfile.profile(forKeyCode: tab, secondHotkeyEnabled: false) == .configured)
        #expect(SwitcherProfile.profile(forKeyCode: tab, secondHotkeyEnabled: true) == .configured)
    }

    @Test("The backtick key opens the current-application profile only when the second hotkey is on")
    func graveNeedsTheSetting() {
        #expect(SwitcherProfile.profile(forKeyCode: grave, secondHotkeyEnabled: true) == .currentApplication)
        #expect(SwitcherProfile.profile(forKeyCode: grave, secondHotkeyEnabled: false) == nil)
    }

    @Test("Any other key is not a switcher key")
    func otherKeys() {
        #expect(SwitcherProfile.profile(forKeyCode: 0, secondHotkeyEnabled: true) == nil)
        #expect(SwitcherProfile.profile(forKeyCode: 36, secondHotkeyEnabled: true) == nil)
    }

    @Test("The configured profile leaves the user's filter exactly as it is")
    func configuredIsIdentity() {
        let filter = WindowFilter(
            applications: .excludingFrontmost, minimized: .hide, screens: .surfaceScreenOnly, order: .alphabetical)
        #expect(SwitcherProfile.configured.filter(from: filter) == filter)
    }

    @Test("The current-application profile changes only which applications, never the other axes")
    func currentApplicationChangesOneAxis() {
        // The whole point of a fixed profile: the second hotkey is a different
        // question ("this app's windows"), not a second copy of every setting.
        let filter = WindowFilter(
            applications: .all, minimized: .hide, screens: .surfaceScreenOnly, order: .alphabetical)
        let result = SwitcherProfile.currentApplication.filter(from: filter)
        #expect(result.applications == .frontmostOnly)
        #expect(result.minimized == .hide)
        #expect(result.screens == .surfaceScreenOnly)
        #expect(result.order == .alphabetical)
    }
}
