import AppKit
import ApplicationServices
import Foundation

/// Everything OpenSwitchr can do *to* a window.
///
/// Shared by both frontends: the switcher overlay and the Dock preview panel
/// call exactly the same code, so behaviour cannot drift between them.
@MainActor
public enum WindowActions {

    /// Brings a window to the front and activates its app.
    ///
    /// Order matters. Raising first and activating second is what makes the
    /// *specific* window come forward rather than whichever window the app
    /// considers its main one.
    @discardableResult
    public static func focus(_ window: WindowInfo) -> Bool {
        var raised = false

        if let element = window.element {
            if window.isMinimized {
                AXBridge.setBool(element, kAXMinimizedAttribute as String, false)
            }
            raised = AXBridge.perform(element, kAXRaiseAction as String)
            AXBridge.setBool(element, kAXMainAttribute as String, true)
        }

        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [])
            return true
        }

        return raised
    }

    @discardableResult
    public static func minimize(_ window: WindowInfo) -> Bool {
        guard let element = window.element else { return false }
        return AXBridge.setBool(element, kAXMinimizedAttribute as String, true)
    }

    @discardableResult
    public static func restore(_ window: WindowInfo) -> Bool {
        guard let element = window.element else { return false }
        return AXBridge.setBool(element, kAXMinimizedAttribute as String, false)
    }

    @discardableResult
    public static func toggleMinimized(_ window: WindowInfo) -> Bool {
        window.isMinimized ? restore(window) : minimize(window)
    }

    @discardableResult
    public static func close(_ window: WindowInfo) -> Bool {
        guard let element = window.element else { return false }
        return AXBridge.pressCloseButton(element)
    }

    @discardableResult
    public static func hideApp(_ window: WindowInfo) -> Bool {
        NSRunningApplication(processIdentifier: window.pid)?.hide() ?? false
    }

    /// Switches to an application that has no window to raise: activates it and
    /// asks it to open one.
    ///
    /// Launching an already-running application sends it the reopen event, which
    /// is what a click on its Dock icon does, so this is the same behaviour
    /// rather than a new one. It is still an assumption: not every application
    /// makes a window on reopen, and some make the wrong one.
    public static func activateWindowless(_ window: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        app.activate(options: [])
        guard let url = app.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    @discardableResult
    public static func quitApp(_ window: WindowInfo) -> Bool {
        NSRunningApplication(processIdentifier: window.pid)?.terminate() ?? false
    }
}
