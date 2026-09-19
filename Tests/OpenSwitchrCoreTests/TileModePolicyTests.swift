import CoreGraphics
import Testing

@testable import OpenSwitchrCore

@Suite("TileModePolicy")
struct TileModePolicyTests {

    private func resolve(
        _ preference: TilePreference = .previews,
        granted: Bool = true,
        count: Int = 5,
        threshold: Int = 12
    ) -> TileMode {
        TileModePolicy.resolve(
            preference: preference,
            screenRecordingGranted: granted,
            windowCount: count,
            threshold: threshold
        )
    }

    @Test("Previews are used when nothing argues against them")
    func previewsByDefault() {
        #expect(resolve() == .previews)
    }

    @Test("The icons-only preference always wins")
    func iconsOnlyPreference() {
        #expect(resolve(.iconsOnly) == .icons)
        #expect(resolve(.iconsOnly, granted: true, count: 1) == .icons)
    }

    @Test("Without Screen Recording every capture would fail, so icons are chosen")
    func noScreenRecording() {
        #expect(resolve(.previews, granted: false) == .icons)
    }

    @Test("More windows than the threshold switch to icons")
    func aboveThreshold() {
        #expect(resolve(count: 13, threshold: 12) == .icons)
    }

    @Test("Exactly the threshold still gets previews")
    func atThreshold() {
        #expect(resolve(count: 12, threshold: 12) == .previews)
    }

    @Test("The threshold is per surface: the same count can trip one and not the other")
    func thresholdIsPerSurface() {
        #expect(resolve(count: 10, threshold: 8) == .icons)
        #expect(resolve(count: 10, threshold: 12) == .previews)
    }

    @Test("An empty list stays in the preferred mode")
    func emptyList() {
        #expect(resolve(count: 0) == .previews)
    }

    @Test("Preview tiles keep the sixteen-by-nine shape and the 120 point floor")
    func previewTileSize() {
        #expect(TileModePolicy.tileSize(for: .previews, previewWidth: 320) == CGSize(width: 320, height: 180))
        #expect(TileModePolicy.tileSize(for: .previews, previewWidth: 50).width == 120)
    }

    @Test("Icon tiles are laid out for icons: shorter than a preview and never wider than one")
    func iconTileSize() {
        let preview = TileModePolicy.tileSize(for: .previews, previewWidth: 320)
        let icon = TileModePolicy.tileSize(for: .icons, previewWidth: 320)
        #expect(icon.height < preview.height)
        #expect(icon.width <= preview.width)
        #expect(TileModePolicy.tileSize(for: .icons, previewWidth: 120).width <= 120)
    }
}
