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

    // MARK: - Windows nothing but depth can tell apart

    /// Distinct stand-ins, so a test can assert *which* accessibility window a
    /// link points at. `dummyElement()` returns the same system-wide element
    /// every time, which is fine when the assertion is only "linked at all".
    private func distinctElement(_ seed: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(seed)
    }

    private func axWindow(
        element: AXUIElement,
        title: String,
        frame: CGRect,
        minimized: Bool = false
    ) -> AXWindowLinker.AXWindow {
        AXWindowLinker.AXWindow(element: element, title: title, frame: frame, isMinimized: minimized)
    }

    private func entry(
        id: CGWindowID,
        title: String?,
        frame: CGRect,
        zOrder: Int,
        onScreen: Bool = true
    ) -> CGWindowEntry {
        CGWindowEntry(
            id: id,
            pid: 42,
            title: title,
            ownerName: "App",
            frame: frame,
            isOnScreen: onScreen,
            zOrder: zOrder
        )
    }

    /// The bug that prompted all of this: four Microsoft Edge windows shared a
    /// frame *and* a title, every pairing scored the same, and the winner was
    /// decided by an unstable sort. Clicking a Dock preview raised whichever
    /// window that lottery had picked.
    @Test("Windows identical in frame and title link front-to-front")
    func identicalWindowsLinkByDepth() {
        let frame = CGRect(x: 2060, y: 420, width: 1000, height: 665)
        let front = distinctElement(1)
        let back = distinctElement(2)

        let links = AXWindowLinker.link(
            axWindows: [
                axWindow(element: front, title: "Connect Form", frame: frame),
                axWindow(element: back, title: "Connect Form", frame: frame)
            ],
            to: [
                entry(id: 10, title: "Connect Form", frame: frame, zOrder: 0),
                entry(id: 20, title: "Connect Form", frame: frame, zOrder: 1)
            ]
        )

        #expect(links[10]?.element == front)
        #expect(links[20]?.element == back)
    }

    @Test("Reversing the depth order reverses the links")
    func identicalWindowsFollowDepth() {
        let frame = CGRect(x: 2060, y: 420, width: 1000, height: 665)
        let first = distinctElement(1)
        let second = distinctElement(2)

        let links = AXWindowLinker.link(
            axWindows: [
                axWindow(element: first, title: "Connect Form", frame: frame),
                axWindow(element: second, title: "Connect Form", frame: frame)
            ],
            to: [
                entry(id: 10, title: "Connect Form", frame: frame, zOrder: 5),
                entry(id: 20, title: "Connect Form", frame: frame, zOrder: 4)
            ]
        )

        #expect(links[20]?.element == first)
        #expect(links[10]?.element == second)
    }

    /// Edge reports "Connect Form" to CoreGraphics and "Connect Form –
    /// Standbymodus - Microsoft Edge – Geschäftlich" to accessibility, so
    /// demanding equality scored every one of its windows zero on title.
    @Test("A decorated accessibility title still matches its bare counterpart")
    func decoratedTitlesMatch() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let alpha = distinctElement(1)
        let beta = distinctElement(2)

        // Depth deliberately contradicts the titles: without title matching,
        // depth alone would pair them the other way round.
        let links = AXWindowLinker.link(
            axWindows: [
                axWindow(element: alpha, title: "Alpha - Microsoft Edge", frame: frame),
                axWindow(element: beta, title: "Beta - Microsoft Edge", frame: frame)
            ],
            to: [
                entry(id: 10, title: "Beta", frame: frame, zOrder: 0),
                entry(id: 20, title: "Alpha", frame: frame, zOrder: 1)
            ]
        )

        #expect(links[20]?.element == alpha)
        #expect(links[10]?.element == beta)
    }

    @Test("A short shared prefix is a coincidence, not a match")
    func shortPrefixIsNotAMatch() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let links = AXWindowLinker.link(
            axWindows: [axWindow(title: "Ab", frame: frame)],
            to: [
                entry(id: 10, title: "Abendessen", frame: frame, zOrder: 0),
                entry(id: 20, title: "Ab", frame: frame, zOrder: 1)
            ]
        )

        // The exact match must win over the longer string that merely starts
        // with the same two characters.
        #expect(links[20] != nil)
        #expect(links[10] == nil)
    }

    @Test("Linking is deterministic across repeated calls")
    func linkingIsDeterministic() {
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        let elements = (1...4).map { distinctElement(pid_t($0)) }
        let axWindows = elements.map { axWindow(element: $0, title: "Same", frame: frame) }
        let entries = (0..<4).map {
            entry(id: CGWindowID(10 + $0), title: "Same", frame: frame, zOrder: $0)
        }

        let first = AXWindowLinker.link(axWindows: axWindows, to: entries)
        for _ in 0..<20 {
            let again = AXWindowLinker.link(axWindows: axWindows, to: entries)
            for id in entries.map(\.id) {
                #expect(first[id]?.element == again[id]?.element)
            }
        }
        #expect(first[10]?.element == elements[0])
        #expect(first[13]?.element == elements[3])
    }

    // MARK: - Which windows count as switchable

    @Test("A standard window is switchable")
    func standardWindowIsSwitchable() {
        #expect(AXWindowLinker.isSwitchable(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false
        ))
    }

    @Test("A window that omits its subrole is treated as a normal window")
    func missingSubroleIsSwitchable() {
        #expect(AXWindowLinker.isSwitchable(
            role: kAXWindowRole as String,
            subrole: nil,
            isMinimized: false
        ))
    }

    @Test("A dialog on screen is not a switch target")
    func onScreenDialogIsNotSwitchable() {
        #expect(!AXWindowLinker.isSwitchable(
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            isMinimized: false
        ))
    }

    /// macOS relabels a minimized window's subrole from `AXStandardWindow` to
    /// `AXDialog`, so filtering on subrole alone hid every window the moment it
    /// went to the Dock — which is precisely when a switcher is worth having.
    @Test("A minimized window survives being relabelled a dialog")
    func minimizedDialogIsSwitchable() {
        #expect(AXWindowLinker.isSwitchable(
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            isMinimized: true
        ))
    }

    @Test("Anything that is not a window is never switchable")
    func nonWindowRoleIsNotSwitchable() {
        for minimized in [true, false] {
            #expect(!AXWindowLinker.isSwitchable(
                role: kAXSheetRole as String,
                subrole: kAXStandardWindowSubrole as String,
                isMinimized: minimized
            ))
        }
    }
}
