import ApplicationServices
import CoreGraphics
import Testing

@testable import OpenSwitchrCore

/// Covers the highest-risk logic in OpenSwitchr: reconstructing the link between
/// accessibility windows and CoreGraphics window IDs without the private
/// `_AXUIElementGetWindow`. A wrong link shows the wrong preview on a tile.
@Suite("AXWindowLinker")
struct AXWindowLinkerTests {

    /// Any valid AXUIElement works as a stand-in; the linker only ever compares
    /// the title, frame, and minimized flag carried alongside it.
    private func dummyElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    private func axWindow(title: String, frame: CGRect, minimized: Bool = false) -> AXWindowLinker.AXWindow {
        AXWindowLinker.AXWindow(element: dummyElement(), title: title, frame: frame, isMinimized: minimized)
    }

    private func entry(
        id: CGWindowID,
        title: String?,
        frame: CGRect,
        onScreen: Bool = true
    ) -> CGWindowEntry {
        CGWindowEntry(
            id: id,
            pid: 42,
            title: title,
            ownerName: "App",
            frame: frame,
            isOnScreen: onScreen,
            zOrder: Int(id)
        )
    }

    @Test("Identical frame and title link")
    func exactMatchLinks() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let links = AXWindowLinker.link(
            axWindows: [axWindow(title: "Report", frame: frame)],
            to: [entry(id: 5, title: "Report", frame: frame)]
        )

        #expect(links[5]?.title == "Report")
    }

    @Test("A small coordinate disagreement still links")
    func toleratesSmallFrameDrift() {
        let axFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let cgFrame = CGRect(x: 101, y: 99, width: 800, height: 601)

        let links = AXWindowLinker.link(
            axWindows: [axWindow(title: "Report", frame: axFrame)],
            to: [entry(id: 5, title: "Report", frame: cgFrame)]
        )

        #expect(links[5] != nil)
    }

    @Test("Same-sized windows are told apart by position")
    func distinguishesBySamePositionNotJustSize() {
        let left = CGRect(x: 0, y: 0, width: 400, height: 300)
        let right = CGRect(x: 500, y: 0, width: 400, height: 300)

        let links = AXWindowLinker.link(
            axWindows: [axWindow(title: "Left", frame: left), axWindow(title: "Right", frame: right)],
            to: [entry(id: 1, title: "Right", frame: right), entry(id: 2, title: "Left", frame: left)]
        )

        #expect(links[1]?.title == "Right")
        #expect(links[2]?.title == "Left")
    }

    @Test("Links are one-to-one even when candidates are identical")
    func linksAreOneToOne() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let links = AXWindowLinker.link(
            axWindows: [axWindow(title: "Same", frame: frame), axWindow(title: "Same", frame: frame)],
            to: [entry(id: 1, title: "Same", frame: frame), entry(id: 2, title: "Same", frame: frame)]
        )

        #expect(links.count == 2)
        #expect(Set(links.keys) == [1, 2])
    }

    @Test("A minimized window never links to an on-screen one")
    func minimizedNeverLinksToOnScreen() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let links = AXWindowLinker.link(
            axWindows: [axWindow(title: "Report", frame: frame, minimized: true)],
            to: [entry(id: 1, title: "Report", frame: frame, onScreen: true)]
        )

        #expect(links.isEmpty)
    }

    @Test("A minimized window links to its off-screen entry")
    func minimizedLinksToOffScreen() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let links = AXWindowLinker.link(
            axWindows: [axWindow(title: "Report", frame: frame, minimized: true)],
            to: [entry(id: 1, title: "Report", frame: frame, onScreen: false)]
        )

        #expect(links[1] != nil)
    }

    @Test("One window on each side links even when nothing else agrees")
    func singleWindowFallback() {
        let links = AXWindowLinker.link(
            axWindows: [axWindow(title: "Mid-animation", frame: CGRect(x: 0, y: 0, width: 10, height: 10))],
            to: [entry(id: 9, title: "Settled", frame: CGRect(x: 700, y: 400, width: 900, height: 700))]
        )

        #expect(links[9] != nil)
    }

    @Test("Empty input produces no links")
    func emptyInputs() {
        #expect(AXWindowLinker.link(axWindows: [], to: []).isEmpty)
        #expect(AXWindowLinker.link(
            axWindows: [],
            to: [entry(id: 1, title: "x", frame: .zero)]
        ).isEmpty)
    }
}
