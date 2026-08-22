import AppKit
import SwiftUI

@main
struct OpenSwitchrApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("OpenSwitchr", systemImage: "rectangle.stack") {
            MenuBarView(model: delegate.model)
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
