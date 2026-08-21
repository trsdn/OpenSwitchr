import AppKit
import SwiftUI

@main
struct OpenSwitchrApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("OpenSwitchr", systemImage: "rectangle.stack") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement already keeps OpenSwitchr out of the Dock; this makes the
        // behaviour explicit for `swift run` during development.
        NSApp.setActivationPolicy(.accessory)
    }
}
