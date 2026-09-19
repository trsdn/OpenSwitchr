import CoreGraphics
import Foundation
import Testing

@testable import OpenSwitchrCore

@Suite("AppRule")
struct AppRuleTests {

    private func window(bundleID: String?, title: String = "Window") -> WindowInfo {
        WindowInfo(
            id: 1,
            pid: 1,
            bundleID: bundleID,
            appName: "App",
            title: title,
            frame: .zero,
            isMinimized: false,
            isOnScreen: true,
            element: nil
        )
    }

    // MARK: - Rule lookup

    @Test("A bundle id matching a rule's prefix finds that rule")
    func matchesByPrefix() {
        let table = AppRuleTable(rules: [AppRule(bundleIDPrefix: "com.example.helper")])
        #expect(table.rule(forBundleID: "com.example.helper.launcher") != nil)
    }

    @Test("No rule matches a bundle id with no covering prefix")
    func noMatch() {
        let table = AppRuleTable(rules: [AppRule(bundleIDPrefix: "com.example.helper")])
        #expect(table.rule(forBundleID: "com.other.app") == nil)
    }

    @Test("A nil bundle id matches nothing")
    func nilBundleIDMatchesNothing() {
        let table = AppRuleTable(rules: [AppRule(bundleIDPrefix: "com.example.helper")])
        #expect(table.rule(forBundleID: nil) == nil)
    }

    @Test("The most specific of two matching prefixes wins")
    func longestPrefixWins() {
        let general = AppRule(bundleIDPrefix: "com.example", hide: .always)
        let specific = AppRule(bundleIDPrefix: "com.example.helper", hide: .never)
        let table = AppRuleTable(rules: [general, specific])
        #expect(table.rule(forBundleID: "com.example.helper")?.hide == .never)
    }

    // MARK: - Hiding

    @Test("A window is not hidden when no rule covers its bundle id")
    func hidesNothingWithoutARule() {
        let table = AppRuleTable(rules: [])
        #expect(table.hides(window(bundleID: "com.example.app")) == false)
    }

    @Test("hide: .never never hides")
    func hideNever() {
        let table = AppRuleTable(rules: [AppRule(bundleIDPrefix: "com.example", hide: .never)])
        #expect(table.hides(window(bundleID: "com.example.app")) == false)
    }

    @Test("hide: .always always hides")
    func hideAlways() {
        let table = AppRuleTable(rules: [AppRule(bundleIDPrefix: "com.example", hide: .always)])
        #expect(table.hides(window(bundleID: "com.example.app")) == true)
    }

    @Test("hide: .whenTitleContains hides only a matching title, case-insensitively")
    func hideWhenTitleContains() {
        let table = AppRuleTable(rules: [
            AppRule(bundleIDPrefix: "com.example", hide: .whenTitleContains("status"))
        ])
        #expect(table.hides(window(bundleID: "com.example.app", title: "Status Panel")) == true)
        #expect(table.hides(window(bundleID: "com.example.app", title: "Main Window")) == false)
    }

    // MARK: - Stand-aside decision

    @Test("Stands aside for a rule's app when it is full screen")
    func standsAsideWhenFullScreenAndRuled() {
        let table = AppRuleTable(rules: [
            AppRule(bundleIDPrefix: "com.example.remote", standAsideWhenFullScreen: true)
        ])
        #expect(table.shouldStandAside(frontmostBundleID: "com.example.remote", isFullScreen: true))
    }

    @Test("Does not stand aside for the same app when it is not full screen")
    func doesNotStandAsideWhenNotFullScreen() {
        let table = AppRuleTable(rules: [
            AppRule(bundleIDPrefix: "com.example.remote", standAsideWhenFullScreen: true)
        ])
        #expect(!table.shouldStandAside(frontmostBundleID: "com.example.remote", isFullScreen: false))
    }

    @Test("Does not stand aside for an app with no matching rule, even full screen")
    func doesNotStandAsideWithoutARule() {
        #expect(!AppRuleTable(rules: []).shouldStandAside(frontmostBundleID: "com.example.app", isFullScreen: true))
    }

    @Test("Does not stand aside for a rule that opts out")
    func doesNotStandAsideWhenRuleOptsOut() {
        let table = AppRuleTable(rules: [
            AppRule(bundleIDPrefix: "com.example.helper", standAsideWhenFullScreen: false)
        ])
        #expect(!table.shouldStandAside(frontmostBundleID: "com.example.helper", isFullScreen: true))
    }

    @Test("A nil frontmost bundle id never stands aside")
    func nilFrontmostNeverStandsAside() {
        let table = AppRuleTable(rules: [
            AppRule(bundleIDPrefix: "com.example.remote", standAsideWhenFullScreen: true)
        ])
        #expect(!table.shouldStandAside(frontmostBundleID: nil, isFullScreen: true))
    }

    // MARK: - Defaults

    @Test("The shipped defaults mark every entry stand-aside and none hidden")
    func defaultsAreStandAsideOnly() {
        #expect(!AppRuleTable.defaults.rules.isEmpty)
        for rule in AppRuleTable.defaults.rules {
            #expect(rule.standAsideWhenFullScreen == true)
            #expect(rule.hide == .never)
        }
    }
}

@Suite("AppRule persistence and counts")
struct AppRulePersistenceTests {

    private func window(bundleID: String?, title: String = "Window", id: UInt32 = 1) -> WindowInfo {
        WindowInfo(
            id: id, pid: 1, bundleID: bundleID, appName: "App", title: title,
            frame: .zero, isMinimized: false, isOnScreen: true, element: nil
        )
    }

    @Test("A table survives being stored and read back, with every hide policy")
    func roundTrip() throws {
        let table = AppRuleTable(rules: [
            AppRule(bundleIDPrefix: "com.a", hide: .never, standAsideWhenFullScreen: true),
            AppRule(bundleIDPrefix: "com.b", hide: .always),
            AppRule(bundleIDPrefix: "com.c", hide: .whenTitleContains("status"), standAsideWhenFullScreen: true),
        ])
        let decoded = AppRuleTable.decode(from: try table.encoded())
        #expect(decoded == table)
    }

    @Test("Nothing stored yet means the shipped defaults")
    func missingIsDefaults() {
        #expect(AppRuleTable.decode(from: nil) == .defaults)
    }

    @Test("Stored data that no longer parses falls back to the defaults rather than an empty table")
    func corruptIsDefaults() {
        #expect(AppRuleTable.decode(from: Data("not json".utf8)) == .defaults)
    }

    @Test("A table the user emptied on purpose stays empty")
    func emptyStaysEmpty() throws {
        let empty = AppRuleTable(rules: [])
        #expect(AppRuleTable.decode(from: try empty.encoded()) == empty)
    }

    @Test("An unknown hide kind in stored data is read as never hide, not a crash")
    func unknownHideKind() {
        let json = #"{"rules":[{"bundleIDPrefix":"com.x","hideKind":"future","hideText":"","standAside":false}]}"#
        let decoded = AppRuleTable.decode(from: Data(json.utf8))
        #expect(decoded.rules.first?.hide == .never)
    }

    @Test("A rule reports how many of the given windows it currently hides")
    func hiddenCount() {
        let rule = AppRule(bundleIDPrefix: "com.helper", hide: .always)
        let table = AppRuleTable(rules: [rule])
        let windows = [
            window(bundleID: "com.helper.one", id: 1),
            window(bundleID: "com.helper.two", id: 2),
            window(bundleID: "com.other", id: 3),
        ]
        #expect(table.hiddenCount(by: rule, in: windows) == 2)
    }

    @Test("A rule that hides nothing counts zero, so a settings row can say so")
    func hiddenCountZero() {
        let rule = AppRule(bundleIDPrefix: "com.helper", standAsideWhenFullScreen: true)
        let table = AppRuleTable(rules: [rule])
        #expect(table.hiddenCount(by: rule, in: [window(bundleID: "com.helper")]) == 0)
    }

    @Test("The more specific rule takes the windows, so the general one does not count them")
    func hiddenCountRespectsSpecificity() {
        let general = AppRule(bundleIDPrefix: "com.vendor", hide: .always)
        let specific = AppRule(bundleIDPrefix: "com.vendor.keep", hide: .never)
        let table = AppRuleTable(rules: [general, specific])
        let windows = [window(bundleID: "com.vendor.keep.app"), window(bundleID: "com.vendor.other", id: 2)]
        #expect(table.hiddenCount(by: general, in: windows) == 1)
        #expect(table.hiddenCount(by: specific, in: windows) == 0)
    }
}
