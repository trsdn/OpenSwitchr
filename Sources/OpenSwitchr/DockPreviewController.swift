import AppKit
import OpenSwitchrCore
import OpenSwitchrUI
import SwiftUI

/// Shows and positions the window preview panel for a hovered Dock icon.
@MainActor
public final class DockPreviewController {

    private let index: WindowIndex
    private let thumbnails: ThumbnailProvider
    private let preferences: PreferencesStore
    private let panel = OverlayPanel()

    private var windows: [WindowInfo] = []
    private var hoveredIndex: Int?
    private var currentItem: DockHoverMonitor.DockItem?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var mouseMonitor: Any?

    /// An item whose hover resolved to no windows, kept so a later index
    /// rebuild can retry it. See ``indexDidRebuild()``.
    private var unresolvedItem: DockHoverMonitor.DockItem?

    public private(set) var isVisible = false

    /// Called whenever a hover ends, so the Dock monitor can reset its
    /// "last hovered item" state. Without it, re-hovering the same icon is
    /// indistinguishable from not moving at all.
    public var onHidden: (() -> Void)?

    public init(index: WindowIndex, thumbnails: ThumbnailProvider, preferences: PreferencesStore) {
        self.index = index
        self.thumbnails = thumbnails
        self.preferences = preferences
    }

    // MARK: - Hover handling

    public func hoverChanged(to item: DockHoverMonitor.DockItem?) {
        showTask?.cancel()
        showTask = nil

        guard let item else {
            // The pointer left the Dock, so a retry armed by an earlier hover
            // is no longer wanted. `scheduleHide()` cannot do this on our
            // behalf: it returns early when no panel is visible, which is
            // exactly the state an unresolved hover leaves behind.
            unresolvedItem = nil
            scheduleHide()
            return
        }

        hideTask?.cancel()
        hideTask = nil

        guard item != currentItem || !isVisible else { return }

        // Once a preview is on screen the user has already declared intent, so
        // moving along the Dock switches without waiting again. `isVisible` is
        // still true while a hide has merely been scheduled, which is
        // deliberate: that is exactly the moment a fast pointer is crossing the
        // gap between two icons.
        let delay = preferences.dockHoverInstantSwitch && isVisible ? 0 : preferences.dockHoverDelay

        // Showing straight away rather than sleeping for zero: the point of
        // this path is that nothing is scheduled at all.
        guard delay > 0 else {
            show(for: item)
            return
        }

        showTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.show(for: item)
        }
    }

    /// Retries a hover that resolved to nothing before the index caught up.
    ///
    /// Called after a rebuild. Hovering a Dock icon starts an asynchronous
    /// rebuild and then resolves the panel's contents; with the instant path
    /// those two happen in the wrong order, so an application whose window the
    /// index had not seen yet produced no panel and nothing ever tried again.
    /// The pointer must still be on the same icon — the user has otherwise
    /// moved on, and a panel appearing now would be a surprise rather than a
    /// recovery.
    public func indexDidRebuild() {
        guard let item = unresolvedItem else { return }
        unresolvedItem = nil
        guard isMouseInside(item) else { return }
        show(for: item, isRetry: true)
    }

    private func scheduleHide() {
        guard isVisible else { return }
        let delay = preferences.dockHideDelay
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
        // Keep the panel open while the pointer is anywhere in the hover
        // region, so the user can actually travel from the Dock icon onto
        // a preview tile without the panel closing on the way.
        if self.isMouseInHoverRegion() { return }
        self.hide()
        }
    }

    // MARK: - Presentation

    private func show(for item: DockHoverMonitor.DockItem, isRetry: Bool = false) {
        let matches = resolveWindows(for: item)
        guard !matches.isEmpty else {
            hide()
            // Hovering kicks off an index rebuild that does not block, and the
            // instant path resolves before it lands — so "no windows" may only
            // mean "not yet". Armed *once*, and only for a first attempt:
            // a retry that also came up empty means the icon genuinely has
            // nothing here, and re-arming would make every later rebuild try
            // again for as long as the pointer sits on it. Set after `hide()`,
            // which clears it.
            if !isRetry { unresolvedItem = item }
            return
        }
        unresolvedItem = nil

        currentItem = item
        windows = matches
        hoveredIndex = nil

        let tile = tileSize()
        // Once per shown row, not from `render()`, which also runs on hover.
        thumbnails.prefetch(matches.map(\.id), maxPixelSize: tile.width * 2)

        let size = DockPreviewView.panelSize(windowCount: matches.count, tileSize: tile)
        let clamped = NSSize(
            width: min(size.width, (NSScreen.main?.visibleFrame.width ?? 1200) * 0.9),
            height: size.height
        )

        render()
        panel.setFrame(NSRect(origin: panelOrigin(for: item, size: clamped), size: clamped), display: true)
        panel.orderFrontRegardless()
        isVisible = true
        startMouseTracking()
    }

    private func render() {
        panel.setContent(
            DockPreviewView(
                windows: windows,
                hoveredIndex: hoveredIndex,
                thumbnails: thumbnails,
                tileSize: tileSize(),
                showsCloseButtons: preferences.showCloseButton,
                onActivate: { [weak self] index in
                    guard let self, self.windows.indices.contains(index) else { return }
                    let window = self.windows[index]
                    WindowActions.focus(window)
                    self.index.noteFocus(windowID: window.id)
                    self.hide()
                },
                onClose: { [weak self] index in
                    self?.close(at: index)
                },
                onQuitApp: { [weak self] index in
                    self?.quitApp(at: index)
                },
                onHover: { [weak self] index in
                    guard let self, self.hoveredIndex != index else { return }
                    self.hoveredIndex = index
                    self.render()
                }
            )
        )
    }

    /// Closes a previewed window and updates the panel in place.
    ///
    /// The index is corrected immediately rather than waiting for the
    /// accessibility notification, which only marks the index stale and would
    /// leave a tile for a window that is already gone.
    private func close(at index: Int) {
        guard windows.indices.contains(index) else { return }
        let window = windows[index]
        guard WindowActions.close(window) else { return }

        self.index.remove(windowID: window.id)
        thumbnails.invalidate(window.id)
        windows.remove(at: index)
        hoveredIndex = nil

        // An empty panel is worse than no panel: nothing left to preview.
        guard !windows.isEmpty, let item = currentItem else {
            hide()
            return
        }

        let tile = tileSize()
        let size = DockPreviewView.panelSize(windowCount: windows.count, tileSize: tile)
        let clamped = NSSize(
            width: min(size.width, (NSScreen.main?.visibleFrame.width ?? 1200) * 0.9),
            height: size.height
        )
        render()
        panel.setFrame(NSRect(origin: panelOrigin(for: item, size: clamped), size: clamped), display: true)
    }

    /// Asks a previewed window's app to quit, then dismisses the panel.
    ///
    /// Unlike closing a window, this cannot be reflected in the index right
    /// away: `terminate()` is a request, not an outcome. An app with unsaved
    /// work puts up its own dialog and may never quit at all, so pretending its
    /// windows are gone would be a lie the next rebuild has to undo. The panel
    /// gets out of the way instead — every window it shows belongs to the app
    /// being asked to quit, and a save dialog needs the screen more than a
    /// preview does.
    private func quitApp(at index: Int) {
        guard windows.indices.contains(index) else { return }
        WindowActions.quitApp(windows[index])
        hide()
    }

    private func tileSize() -> CGSize {
        let width = max(120, preferences.tileWidth * 0.9)
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }

    /// Places the panel next to the Dock item, on whichever edge the Dock is.
    private func panelOrigin(for item: DockHoverMonitor.DockItem, size: NSSize) -> NSPoint {
        let itemRect = Self.screenRect(of: item)

        let screen = NSScreen.screens.first { $0.frame.intersects(itemRect) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 8

        let edge = dockEdge(itemRect: itemRect, screenFrame: screen?.frame ?? visible)

        var origin: NSPoint
        switch edge {
        case .bottom:
            origin = NSPoint(x: itemRect.midX - size.width / 2, y: itemRect.maxY + gap)
        case .left:
            origin = NSPoint(x: itemRect.maxX + gap, y: itemRect.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: itemRect.minX - size.width - gap, y: itemRect.midY - size.height / 2)
        }

        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        return origin
    }

    private enum DockEdge { case bottom, left, right }

    private func dockEdge(itemRect: NSRect, screenFrame: NSRect) -> DockEdge {
        if itemRect.minX <= screenFrame.minX + 4 { return .left }
        if itemRect.maxX >= screenFrame.maxX - 4 { return .right }
        return .bottom
    }

    private func resolveWindows(for item: DockHoverMonitor.DockItem) -> [WindowInfo] {
        var matches = item.bundleID.map { index.windows(forBundleID: $0) } ?? []
        if matches.isEmpty, !item.title.isEmpty {
            matches = index.windows.filter { $0.appName == item.title }
        }
        guard !matches.isEmpty else { return [] }

        // This surface has a profile too, even though it is the permissive one.
        // Going through it keeps the claim that both frontends are filtered the
        // same way true in code rather than only in the README.
        return WindowFilter.dockPreview.apply(to: matches)
    }

    // MARK: - Mouse tracking

    /// The only mouse monitor in OpenSwitchr, and it exists only while a preview
    /// panel is already on screen. It is torn down the moment the panel hides.
    private func startMouseTracking() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.isVisible else { return }
                if !self.isMouseInHoverRegion() {
                    self.scheduleHide()
                }
            }
        }
    }

    private func stopMouseTracking() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }

    private func isMouseInsidePanel() -> Bool {
        panel.frame.insetBy(dx: -Self.hoverSlack, dy: -Self.hoverSlack).contains(NSEvent.mouseLocation)
    }

    private func isMouseInside(_ item: DockHoverMonitor.DockItem) -> Bool {
        Self.screenRect(of: item).insetBy(dx: -Self.hoverSlack, dy: -Self.hoverSlack)
            .contains(NSEvent.mouseLocation)
    }

    /// How far outside a rectangle still counts as being on it.
    private static let hoverSlack: CGFloat = 8

    /// Everything that should keep the panel alive: the Dock item, the panel,
    /// and the corridor between them.
    ///
    /// Testing the two rectangles separately leaves a dead strip in the gap.
    /// The icon was generous by 4 points and the panel by 6 against a gap of 8,
    /// so the two regions overlapped by two points — and Dock magnification, a
    /// diagonal approach, or simply pausing on the way was enough to drop the
    /// pointer into neither and start the hide while the user was still
    /// travelling towards the panel. The union of the two is the region the
    /// user actually perceives as "the preview", and leaving it sideways or
    /// backwards still ends the hover.
    private func isMouseInHoverRegion() -> Bool {
        let mouse = NSEvent.mouseLocation
        if isMouseInsidePanel() { return true }
        guard let item = currentItem else { return false }

        let itemRect = Self.screenRect(of: item)
        if itemRect.insetBy(dx: -Self.hoverSlack, dy: -Self.hoverSlack).contains(mouse) { return true }
        guard isVisible else { return false }

        return itemRect.union(panel.frame)
            .insetBy(dx: -Self.hoverSlack, dy: -Self.hoverSlack)
            .contains(mouse)
    }

    /// A Dock item's frame in AppKit screen coordinates.
    ///
    /// Accessibility reports it with the origin at the top-left of the primary
    /// display and y growing downwards; AppKit windows use a bottom-left
    /// origin.
    private static func screenRect(of item: DockHoverMonitor.DockItem) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(
            x: item.frame.origin.x,
            y: primaryHeight - item.frame.origin.y - item.frame.height,
            width: item.frame.width,
            height: item.frame.height
        )
    }

    // MARK: - Teardown

    public func hide() {
        showTask?.cancel()
        hideTask?.cancel()
        showTask = nil
        hideTask = nil
        unresolvedItem = nil
        stopMouseTracking()
        // Fires even when no panel was on screen: hovering an icon without
        // windows also ends a hover, and the monitor must forget it either way.
        onHidden?()

        guard isVisible else { return }
        panel.hidePanel()
        isVisible = false
        currentItem = nil
        windows = []
        hoveredIndex = nil
    }
}
