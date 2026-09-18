import CoreGraphics
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
