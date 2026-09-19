import Testing

@testable import OpenSwitchrCore

@Suite("Accessibility appearance")
struct AccessibilityAppearanceTests {

    @Test("With every setting off, the panels look exactly as they did before these settings were honoured")
    func defaultsAreUnchanged() {
        let a = AccessibilityAppearance()
        #expect(a.animatesSelectionScroll)
        #expect(a.usesTranslucency)
        #expect(a.usesQuietMarks)
        #expect(a.opacity(of: .panelBorder) == 0.10)
        #expect(a.opacity(of: .tileBorder) == 0.12)
        #expect(a.opacity(of: .tileFill) == 0.06)
    }

    @Test("Reduce Motion stops the selection scroll animating and touches nothing else")
    func reduceMotion() {
        let a = AccessibilityAppearance(reduceMotion: true)
        #expect(!a.animatesSelectionScroll)
        #expect(a.usesTranslucency)
        #expect(a.opacity(of: .tileBorder) == AccessibilityAppearance().opacity(of: .tileBorder))
    }

    @Test("Reduce Transparency asks for an opaque fill and touches nothing else")
    func reduceTransparency() {
        let a = AccessibilityAppearance(reduceTransparency: true)
        #expect(!a.usesTranslucency)
        #expect(a.animatesSelectionScroll)
    }

    @Test("Increased contrast strengthens every line and fill, and never weakens one")
    func increasedContrastStrengthensChrome() {
        let normal = AccessibilityAppearance()
        let high = AccessibilityAppearance(increasedContrast: true)
        for chrome in [AccessibilityAppearance.Chrome.panelBorder, .tileBorder, .tileFill] {
            #expect(high.opacity(of: chrome) > normal.opacity(of: chrome))
        }
        #expect(!high.usesQuietMarks)
    }

    @Test("Under increased contrast a tile's edge is at least a third opaque, so it reads against the panel")
    func increasedContrastEdgeIsVisible() {
        let high = AccessibilityAppearance(increasedContrast: true)
        #expect(high.opacity(of: .tileBorder) >= 0.33)
        #expect(high.opacity(of: .panelBorder) >= 0.33)
    }

    @Test("Settings combine independently")
    func settingsAreIndependent() {
        let all = AccessibilityAppearance(reduceMotion: true, reduceTransparency: true, increasedContrast: true)
        #expect(!all.animatesSelectionScroll)
        #expect(!all.usesTranslucency)
        #expect(!all.usesQuietMarks)
    }
}
