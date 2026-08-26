import AppKit
import OpenSwitchrUI
import SwiftUI

@main
struct OpenSwitchrApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: delegate.model)
        } label: {
            // The same mark as the app icon, as a template image the menu bar
            // tints for light, dark, and the highlighted state.
            Image(nsImage: WindowMark.menuBarImage())
                .accessibilityLabel("OpenSwitchr")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The delegate owns the model because startup must not depend on any view
    /// existing. A `.menu`-style `MenuBarExtra` builds its content lazily when
    /// the user opens the menu, so anything started from the menu's `task`
    /// would never run for a user who simply launches the app and presses the
    /// hotkey.
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement already keeps OpenSwitchr out of the Dock; this makes the
        // behaviour explicit for `swift run` during development.
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
