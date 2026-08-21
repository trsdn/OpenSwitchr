import OpenSwitchCore
import SwiftUI

struct SettingsView: View {

    @Bindable var model: AppModel

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            appearance
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            permissions
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 340)
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section("Switcher") {
                Toggle("Enable window switcher", isOn: Binding(
                    get: { model.preferences.switcherEnabled },
                    set: { model.preferences.switcherEnabled = $0; model.applyPreferences() }
                ))

                Picker("Hold modifier", selection: Binding(
                    get: { model.preferences.holdModifier },
                    set: { model.preferences.holdModifier = $0; model.applyPreferences() }
                )) {
                    ForEach(HotkeyMonitor.HoldModifier.allCases, id: \.self) { modifier in
                        Text("\(modifier.symbol)-Tab").tag(modifier)
                    }
                }
                .disabled(!model.preferences.switcherEnabled)

                Text("⌘-Tab is left untouched so the system switcher keeps working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dock previews") {
                Toggle("Show window previews on Dock hover", isOn: Binding(
                    get: { model.preferences.dockHoverEnabled },
                    set: { model.preferences.dockHoverEnabled = $0; model.applyPreferences() }
                ))

                LabeledContent("Show after") {
                    Slider(
                        value: Binding(
                            get: { model.preferences.dockHoverDelay },
                            set: { model.preferences.dockHoverDelay = $0 }
                        ),
                        in: 0...1,
                        step: 0.02
                    ) {
                        Text("\(model.preferences.dockHoverDelay, format: .number.precision(.fractionLength(2))) s")
                    }
                }
                .disabled(!model.preferences.dockHoverEnabled)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.preferences.launchAtLogin },
                    set: { model.preferences.launchAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearance: some View {
        Form {
            Section("Previews") {
                LabeledContent("Tile width") {
                    Slider(
                        value: Binding(
                            get: { model.preferences.tileWidth },
                            set: { model.preferences.tileWidth = $0 }
                        ),
                        in: 140...320,
                        step: 10
                    ) {
                        Text("\(Int(model.preferences.tileWidth)) pt")
                    }
                }

                LabeledContent("Thumbnail memory budget") {
                    Stepper(
                        "\(model.preferences.thumbnailBudgetMB) MB",
                        value: Binding(
                            get: { model.preferences.thumbnailBudgetMB },
                            set: { model.preferences.thumbnailBudgetMB = $0 }
                        ),
                        in: 16...512,
                        step: 16
                    )
                }

                Text("The budget applies on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Permissions

    private var permissions: some View {
        Form {
            Section("Accessibility") {
                permissionRow(
                    granted: model.permissions.accessibility == .granted,
                    title: "Required to list windows, read the hotkey, and raise windows.",
                    action: { model.permissions.requestAccessibility() },
                    settings: { model.permissions.openAccessibilitySettings() }
                )
            }

            Section("Screen Recording") {
                permissionRow(
                    granted: model.permissions.screenRecording == .granted,
                    title: "Optional. Without it, tiles show app icons instead of live previews.",
                    action: { model.permissions.requestScreenRecording() },
                    settings: { model.permissions.openScreenRecordingSettings() }
                )
            }
        }
        .formStyle(.grouped)
        .onAppear { model.permissions.refresh() }
    }

    private func permissionRow(
        granted: Bool,
        title: String,
        action: @escaping () -> Void,
        settings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                granted ? "Granted" : "Not granted",
                systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(granted ? Color.green : Color.orange)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !granted {
                HStack {
                    Button("Request…", action: action)
                    Button("Open System Settings…", action: settings)
                }
            }
        }
    }
}
