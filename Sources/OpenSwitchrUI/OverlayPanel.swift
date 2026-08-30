import AppKit
import SwiftUI

/// Base class for OpenSwitchr's floating surfaces.
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

    private var hosting: NSHostingView<AnyView>?

    /// Updates the panel's contents.
    ///
    /// The hosting view is created once and then only has its root view
    /// replaced. Building a fresh `NSHostingView` per update is what made the
    /// first overlay appearance cost ~220 ms, and it repeated that work on
    /// every selection change while the overlay was open.
    public func setContent<Content: View>(_ view: Content) {
        if let existing = hosting {
            existing.rootView = AnyView(view)
            return
        }

        let created = NSHostingView(rootView: AnyView(view))
        created.autoresizingMask = [.width, .height]
        hosting = created
        contentView = created
    }

    /// Shows the panel centred on `screen`, or on the screen that currently has
    /// the mouse when none is given.
    ///
    /// Callers that already decided which screen they mean must pass it. The
    /// switcher scopes its window list by display, so re-deriving the screen
    /// here would let it filter for one display and draw on another.
    public func showCentered(size: NSSize, on screen: NSScreen? = nil) {
        guard let screen = screen ?? Self.screenWithMouse() ?? NSScreen.main else { return }

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
