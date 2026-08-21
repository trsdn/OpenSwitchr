import AppKit
import OpenSwitchCore
import OpenSwitchUI
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

    public private(set) var isVisible = false

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
            scheduleHide()
            return
        }

        hideTask?.cancel()
        hideTask = nil

        guard item != currentItem || !isVisible else { return }

        let delay = preferences.dockHoverDelay
        showTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.show(for: item)
        }
    }

    private func scheduleHide() {
        guard isVisible else { return }
        let delay = preferences.dockHideDelay
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // Keep the panel open while the pointer is inside it, so the user
            // can actually move from the Dock icon onto a preview tile.
            if self.isMouseInsidePanel() { return }
            self.hide()
        }
    }

    // MARK: - Presentation

    private func show(for item: DockHoverMonitor.DockItem) {
        let matches = resolveWindows(for: item)
        guard !matches.isEmpty else {
            hide()
            return
        }

        currentItem = item
        windows = matches
        hoveredIndex = nil

        let tile = tileSize()
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
                onActivate: { [weak self] index in
                    guard let self, self.windows.indices.contains(index) else { return }
                    let window = self.windows[index]
                    WindowActions.focus(window)
                    self.index.noteFocus(windowID: window.id)
                    self.hide()
                },
                onHover: { [weak self] index in
                    guard let self, self.hoveredIndex != index else { return }
                    self.hoveredIndex = index
                    self.render()
                }
            )
        )
    }

    private func tileSize() -> CGSize {
        let width = max(120, preferences.tileWidth * 0.9)
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }

    /// Places the panel next to the Dock item, on whichever edge the Dock is.
    ///
    /// Accessibility reports frames with the origin at the top-left of the
    /// primary display, while AppKit windows use a bottom-left origin, so the
    /// vertical axis has to be flipped.
    private func panelOrigin(for item: DockHoverMonitor.DockItem, size: NSSize) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let itemRect = NSRect(
            x: item.frame.origin.x,
            y: primaryHeight - item.frame.origin.y - item.frame.height,
            width: item.frame.width,
            height: item.frame.height
        )

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
        if let bundleID = item.bundleID {
            let matches = index.windows(forBundleID: bundleID)
            if !matches.isEmpty { return matches }
        }
        guard !item.title.isEmpty else { return [] }
        return index.windows.filter { $0.appName == item.title }
    }

    // MARK: - Mouse tracking

    /// The only mouse monitor in OpenSwitch, and it exists only while a preview
    /// panel is already on screen. It is torn down the moment the panel hides.
    private func startMouseTracking() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.isVisible else { return }
                if !self.isMouseInsidePanel() && !self.isMouseInsideCurrentDockItem() {
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
        panel.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
    }

    private func isMouseInsideCurrentDockItem() -> Bool {
        guard let item = currentItem else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(
            x: item.frame.origin.x,
            y: primaryHeight - item.frame.origin.y - item.frame.height,
            width: item.frame.width,
            height: item.frame.height
        )
        return rect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    // MARK: - Teardown

    public func hide() {
        showTask?.cancel()
        hideTask?.cancel()
        showTask = nil
        hideTask = nil
        stopMouseTracking()

        guard isVisible else { return }
        panel.hidePanel()
        isVisible = false
        currentItem = nil
        windows = []
        hoveredIndex = nil
    }
}
