import CoreGraphics
import Testing

@testable import OpenSwitchrCore

@Suite("WindowFilter")
struct WindowFilterTests {

    private func window(
        id: CGWindowID,
        app: String = "Safari",
        title: String = "Window",
        pid: pid_t = 1,
        minimized: Bool = false,
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        openedRank: Int = 0
    ) -> WindowInfo {
        WindowInfo(
            id: id,
            pid: pid,
            bundleID: "com.example.\(app.lowercased())",
            appName: app,
            title: title,
            frame: frame,
            isMinimized: minimized,
            isOnScreen: !minimized,
            element: nil,
            openedRank: openedRank
        )
    }

    // MARK: - Defaults

    @Test("The default filter changes nothing at all")
    func defaultIsIdentity() {
        let windows = [window(id: 1), window(id: 2), window(id: 3)]
        #expect(WindowFilter().apply(to: windows).map(\.id) == [1, 2, 3])
    }

    @Test("The Dock preview profile keeps minimized windows, which is the point of hovering the Dock")
    func dockPreviewKeepsMinimized() {
        let windows = [window(id: 1), window(id: 2, minimized: true)]
        #expect(WindowFilter.dockPreview.apply(to: windows).map(\.id) == [1, 2])
    }

    // MARK: - Application scope

    @Test("Only the current application keeps that application's windows")
    func frontmostOnly() {
        let windows = [
            window(id: 1, app: "Safari", pid: 10),
            window(id: 2, app: "Xcode", pid: 20),
            window(id: 3, app: "Safari", pid: 10)
        ]
        let filter = WindowFilter(applications: .frontmostOnly)
        let result = filter.apply(to: windows, context: .init(frontmostPID: 10))

        #expect(result.map(\.id) == [1, 3])
    }

    @Test("Everything but the current application is the exact complement")
    func excludingFrontmost() {
        let windows = [
            window(id: 1, app: "Safari", pid: 10),
            window(id: 2, app: "Xcode", pid: 20)
        ]
        let filter = WindowFilter(applications: .excludingFrontmost)

        #expect(filter.apply(to: windows, context: .init(frontmostPID: 10)).map(\.id) == [2])
    }

    @Test("An unknown frontmost application must not empty the list")
    func unknownFrontmostShowsEverything() {
        let windows = [
            window(id: 1, app: "Safari", pid: 10),
            window(id: 2, app: "Xcode", pid: 20)
        ]

        // Both scopes would otherwise be free to remove every window, which is
        // the one outcome a switcher can never recover from.
        #expect(WindowFilter(applications: .frontmostOnly).apply(to: windows).map(\.id) == [1, 2])
        #expect(WindowFilter(applications: .excludingFrontmost).apply(to: windows).map(\.id) == [1, 2])
    }

    // MARK: - Minimized

    @Test("Hiding minimized windows removes them")
    func hideMinimized() {
        let windows = [window(id: 1), window(id: 2, minimized: true), window(id: 3)]
        #expect(WindowFilter(minimized: .hide).apply(to: windows).map(\.id) == [1, 3])
    }

    @Test("Showing minimized windows last is a partition that preserves the order within each half")
    func minimizedAfterOthers() {
        let windows = [
            window(id: 1, minimized: true),
            window(id: 2),
            window(id: 3, minimized: true),
            window(id: 4)
        ]

        #expect(WindowFilter(minimized: .showAfterOthers).apply(to: windows).map(\.id) == [2, 4, 1, 3])
    }

    @Test("Minimized windows go last within whatever order was chosen")
    func minimizedPartitionAppliesToSortedOrder() {
        let windows = [
            window(id: 1, app: "Zed", minimized: true),
            window(id: 2, app: "Safari"),
            window(id: 3, app: "Arc", minimized: true),
            window(id: 4, app: "Xcode")
        ]

        let filter = WindowFilter(minimized: .showAfterOthers, order: .alphabetical)

        // Alphabetical within each half: Safari before Xcode, then Arc before Zed.
        #expect(filter.apply(to: windows).map(\.id) == [2, 4, 3, 1])
    }

    // MARK: - Ordering stability

    @Test("Windows that compare equal keep the order the index handed over")
    func alphabeticalIsStable() {
        // Same application, same title: every field either comparator looks at
        // is equal, so an unstable sort is free to return these in any order.
        // The incoming order is most-recently-used, and the list is re-ordered
        // on every keystroke, so instability would move tiles under the user.
        let windows = (1...8).map { window(id: CGWindowID($0), app: "Safari", title: "Untitled") }
        let result = WindowFilter(order: .alphabetical).apply(to: windows)

        #expect(result.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test("Equal discovery ranks also keep the incoming order")
    func recentlyOpenedIsStable() {
        let windows = (1...8).map { window(id: CGWindowID($0), openedRank: 4) }
        let result = WindowFilter(order: .recentlyOpened).apply(to: windows)

        #expect(result.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test("The minimized partition preserves the incoming order inside each half")
    func partitionIsStableUnderIdentityOrder() {
        // Under `recentlyUsed` there is no sort at all, so this is the case
        // that catches an *unstable* comparator-based implementation: only
        // something that leaves the two halves alone can keep 2 before 4 and 1
        // before 3.
        let windows = [
            window(id: 1, minimized: true),
            window(id: 2),
            window(id: 3, minimized: true),
            window(id: 4)
        ]

        #expect(WindowFilter(minimized: .showAfterOthers).apply(to: windows).map(\.id) == [2, 4, 1, 3])
    }

    // MARK: - Frontmost resolution

    @Test("The frontmost application comes from the workspace, never from window order")
    func frontmostPIDUsesWorkspace() {
        #expect(WindowFilter.Context.frontmostPID(workspaceFrontmost: 42, ownPID: 7) == 42)
    }

    @Test("Our own process is never treated as the current application")
    func frontmostPIDRefusesOwnProcess() {
        // Scoping to a process that owns no window in the index would empty the
        // switcher, which is the one outcome it cannot recover from. Returning
        // nil ignores the scope instead.
        #expect(WindowFilter.Context.frontmostPID(workspaceFrontmost: 7, ownPID: 7) == nil)
    }

    @Test("An unknown workspace frontmost yields nil rather than a guess")
    func frontmostPIDWithoutWorkspace() {
        #expect(WindowFilter.Context.frontmostPID(workspaceFrontmost: nil, ownPID: 7) == nil)
    }

    // MARK: - Screen coordinate conversion

    @Test("On a single display the conversion is the identity")
    func conversionOnPrimaryDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(WindowFilter.coreGraphicsFrame(appKitFrame: primary, primaryHeight: 900) == primary)
    }

    @Test("A display above the primary lands at a negative y")
    func conversionForDisplayAbove() {
        // AppKit: sits on top of a 1440-high primary, so its frame starts at
        // y = 1440. CoreGraphics measures downwards from the primary's top, so
        // it has to end up above the origin.
        let above = CGRect(x: 913, y: 1440, width: 1920, height: 1080)
        let converted = WindowFilter.coreGraphicsFrame(appKitFrame: above, primaryHeight: 1440)

        #expect(converted == CGRect(x: 913, y: -1080, width: 1920, height: 1080))
    }

    @Test("A display below the primary lands at a positive y")
    func conversionForDisplayBelow() {
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let converted = WindowFilter.coreGraphicsFrame(appKitFrame: below, primaryHeight: 1440)

        #expect(converted == CGRect(x: 0, y: 1440, width: 1920, height: 1080))
    }

    @Test("A shorter secondary aligned to the primary's bottom keeps its bottom aligned")
    func conversionForShorterSecondary() {
        // The trap the flip exists for: taking the AppKit origin unchanged
        // would put this display at y = 0, level with the primary's *top*,
        // when it is actually level with its bottom.
        let secondary = CGRect(x: 1440, y: 0, width: 1280, height: 800)
        let converted = WindowFilter.coreGraphicsFrame(appKitFrame: secondary, primaryHeight: 1440)

        #expect(converted == CGRect(x: 1440, y: 640, width: 1280, height: 800))
    }

    // MARK: - Screen scope

    @Test("Restricting to one display drops windows that do not touch it")
    func screenScopeDropsOtherDisplays() {
        let onThisScreen = window(id: 1, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        let onAnotherScreen = window(id: 2, frame: CGRect(x: 2000, y: 100, width: 400, height: 300))

        let filter = WindowFilter(screens: .surfaceScreenOnly)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        #expect(filter.apply(to: [onThisScreen, onAnotherScreen], context: .init(screenFrame: screen)).map(\.id) == [1])
    }

    @Test("A window straddling two displays belongs to both")
    func straddlingWindowIsKept() {
        let straddling = window(id: 1, frame: CGRect(x: 1300, y: 100, width: 400, height: 300))
        let filter = WindowFilter(screens: .surfaceScreenOnly)

        #expect(filter.apply(to: [straddling], context: .init(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))).map(\.id) == [1])
    }

    @Test("Minimized windows survive a display restriction, because they are on no display")
    func minimizedExemptFromScreenScope() {
        // Its reported frame is off this screen, which is exactly the trap:
        // restricting by display would silently delete every minimized window.
        let minimized = window(id: 1, minimized: true, frame: CGRect(x: 5000, y: 5000, width: 1, height: 1))
        let filter = WindowFilter(screens: .surfaceScreenOnly)

        #expect(filter.apply(to: [minimized], context: .init(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))).map(\.id) == [1])
    }

    @Test("Without a screen frame the display restriction does nothing")
    func screenScopeNeedsAFrame() {
        let windows = [window(id: 1, frame: CGRect(x: 9000, y: 9000, width: 10, height: 10))]
        #expect(WindowFilter(screens: .surfaceScreenOnly).apply(to: windows).map(\.id) == [1])
    }

    // MARK: - Order

    @Test("Most recently used keeps the order the index handed over")
    func recentlyUsedIsIdentity() {
        let windows = [window(id: 3), window(id: 1), window(id: 2)]
        #expect(WindowFilter(order: .recentlyUsed).apply(to: windows).map(\.id) == [3, 1, 2])
    }

    @Test("Most recently opened sorts by discovery, newest first")
    func recentlyOpened() {
        let windows = [
            window(id: 1, openedRank: 5),
            window(id: 2, openedRank: 9),
            window(id: 3, openedRank: 7)
        ]
        #expect(WindowFilter(order: .recentlyOpened).apply(to: windows).map(\.id) == [2, 3, 1])
    }

    @Test("Alphabetical sorts by application first and title second")
    func alphabetical() {
        let windows = [
            window(id: 1, app: "Safari", title: "Zebra"),
            window(id: 2, app: "Arc", title: "Beta"),
            window(id: 3, app: "Safari", title: "Alpha")
        ]
        #expect(WindowFilter(order: .alphabetical).apply(to: windows).map(\.id) == [2, 3, 1])
    }

    @Test("Alphabetical ignores case, so a lowercase title does not sort to the end")
    func alphabeticalIsCaseInsensitive() {
        let windows = [
            window(id: 1, app: "Safari", title: "beta"),
            window(id: 2, app: "Safari", title: "Alpha")
        ]
        #expect(WindowFilter(order: .alphabetical).apply(to: windows).map(\.id) == [2, 1])
    }

    // MARK: - Composition

    @Test("Filtering happens before ordering")
    func filterRunsBeforeSort() {
        let windows = [
            window(id: 1, app: "Arc", pid: 20),
            window(id: 2, app: "Safari", pid: 10),
            window(id: 3, app: "Zed", pid: 10)
        ]

        let filter = WindowFilter(applications: .frontmostOnly, order: .alphabetical)
        let result = filter.apply(to: windows, context: .init(frontmostPID: 10))

        // Arc would sort first if the sort had seen it.
        #expect(result.map(\.id) == [2, 3])
    }

    @Test("A filter that removes everything returns an empty list rather than falling back")
    func canReturnNothing() {
        let windows = [window(id: 1, minimized: true)]
        #expect(WindowFilter(minimized: .hide).apply(to: windows).isEmpty)
    }
}
