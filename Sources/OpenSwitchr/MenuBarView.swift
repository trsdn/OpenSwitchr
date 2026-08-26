import AppKit
import OpenSwitchrCore
import SwiftUI

struct MenuBarView: View {

    @Bindable var model: AppModel

    /// `SettingsLink` opens the window but offers no hook to run alongside it,
    /// and `LSUIElement` means opening a window never activates the app — the
    /// Settings window would appear behind whatever the user was looking at.
    /// Driving the open explicitly is what makes room for the activation.
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if model.permissions.isOperational {
                statusSection
            } else {
                permissionSection
            }

            Divider()

            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit OpenSwitchr") {
                model.stop()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        // Startup deliberately does not live here. This menu is built lazily
        // when it is opened, so a user who never clicks the menu bar icon
        // would get an app that does nothing. See AppDelegate.
        .onAppear { model.permissions.refresh() }
    }

    private var statusSection: some View {
        Group {
            Text("\(model.index.windows.count) windows on this Space")
            Text("Switcher: \(model.preferences.holdModifier.symbol)-Tab")
            if model.preferences.switcherEnabled && !model.switcherHotkeyActive {
                Text("Switcher hotkey unavailable")
            }
            if model.preferences.dockHoverEnabled && !model.dockHoverActive {
                Text("Dock hover unavailable")
            }
            Button("Refresh window list") {
                Task { await model.index.rebuildConcurrently() }
            }
        }
    }

    private var permissionSection: some View {
        Group {
            Text("Accessibility permission required")
            Button("Grant Accessibility…") {
                model.permissions.requestAccessibility()
            }
            Button("Open System Settings…") {
                model.permissions.openAccessibilitySettings()
            }
            Button("Try again") {
                model.start()
            }
        }
    }
}
