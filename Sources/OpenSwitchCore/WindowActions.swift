import AppKit
import ApplicationServices
import Foundation

/// Everything OpenSwitch can do *to* a window.
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

    @discardableResult
    public static func quitApp(_ window: WindowInfo) -> Bool {
        NSRunningApplication(processIdentifier: window.pid)?.terminate() ?? false
    }
}
