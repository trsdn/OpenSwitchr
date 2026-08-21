import AppKit
import OpenSwitchCore
import SwiftUI

struct MenuBarView: View {

    @Bindable var model: AppModel
    @State private var didStart = false

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

            Button("Quit OpenSwitch") {
                model.stop()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .task {
            guard !didStart else { return }
            didStart = true
            model.start()
        }
    }

    private var statusSection: some View {
        Group {
            Text("\(model.index.windows.count) windows on this Space")
            Text("Switcher: \(model.preferences.holdModifier.symbol)-Tab")
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
