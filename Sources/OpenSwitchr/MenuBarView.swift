import AppKit
import OpenSwitchrCore
import SwiftUI

struct MenuBarView: View {

    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.permissions.isOperational {
                statusSection
            } else {
                permissionSection
            }

            Divider()

            SettingsLink {
                Text("Settings…")
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
