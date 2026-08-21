import AppKit
import SwiftUI

/// Base class for OpenSwitch's floating surfaces.
///
/// Both the switcher overlay and the Dock preview use this. The important part
/// is `.nonactivatingPanel`: showing the overlay must not deactivate the app
/// the user is currently in, otherwise "switch back to the previous window"
/// would be broken by the switcher itself.
///
/// Keyboard input deliberately does **not** arrive through this panel. It comes
/// from the event tap, which is the only way to read a held modifier and to
/// swallow the Tab key.
public final class OverlayPanel: NSPanel {

    public init(contentRect: NSRect = NSRect(x: 0, y: 0, width: 800, height: 400)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    /// Never becomes key: taking key status would steal focus from the app the
    /// user is switching away from.
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Installs a SwiftUI hierarchy as the panel's content.
    public func setContent<Content: View>(_ view: Content) {
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    /// Shows the panel centred on the screen that currently has the mouse,
    /// which is the screen the user is looking at.
    public func showCentered(size: NSSize) {
        let screen = Self.screenWithMouse() ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }

    public func hidePanel() {
        orderOut(nil)
    }

    public static func screenWithMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
