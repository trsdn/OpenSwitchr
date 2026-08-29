import OpenSwitchrCore
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

                Text("⌘-Tab is the default and replaces the macOS app switcher while OpenSwitchr is running. Quitting the app gives it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.preferences.switcherEnabled && !model.switcherHotkeyActive {
                    Label(
                        "The keyboard hotkey is not installed. Check the Accessibility permission below.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Window list") {
                Picker("Show", selection: Binding(
                    get: { model.preferences.switcherApplicationScope },
                    set: { model.preferences.switcherApplicationScope = $0 }
                )) {
                    ForEach(WindowFilter.ApplicationScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }

                Picker("Minimized windows", selection: Binding(
                    get: { model.preferences.switcherMinimizedPolicy },
                    set: { model.preferences.switcherMinimizedPolicy = $0 }
                )) {
                    ForEach(WindowFilter.MinimizedPolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                Picker("Displays", selection: Binding(
                    get: { model.preferences.switcherScreenScope },
                    set: { model.preferences.switcherScreenScope = $0 }
                )) {
                    ForEach(WindowFilter.ScreenScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }

                Picker("Order", selection: Binding(
                    get: { model.preferences.switcherOrder },
                    set: { model.preferences.switcherOrder = $0 }
                )) {
                    ForEach(WindowFilter.Order.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }

                Text("Applies to the switcher only. Dock previews always show every window of the application under the pointer, because that is the one you pointed at.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!model.preferences.switcherEnabled)

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

                Toggle("Switch instantly while a preview is open", isOn: Binding(
                    get: { model.preferences.dockHoverInstantSwitch },
                    set: { model.preferences.dockHoverInstantSwitch = $0 }
                ))
                .disabled(!model.preferences.dockHoverEnabled)

                Text("The delay keeps a preview from appearing when you sweep across the Dock on the way somewhere else. Once one is open you have already asked for it, so moving to the next icon need not wait again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                LabeledContent("Preview size") {
                    Slider(
                        value: Binding(
                            get: { model.preferences.tileWidth },
                            set: { model.preferences.tileWidth = $0; model.applyPreferences() }
                        ),
                        in: 140...320,
                        step: 10
                    ) {
                        Text("\(Int(model.preferences.tileWidth)) pt")
                    }
                }

                Picker("Refresh thumbnails", selection: Binding(
                    get: { model.preferences.thumbnailRefreshRate },
                    set: { model.preferences.thumbnailRefreshRate = $0; model.applyPreferences() }
                )) {
                    ForEach(ThumbnailRefreshRate.allCases, id: \.self) { rate in
                        Text(rate.title).tag(rate)
                    }
                }

                Text("Refreshing less often trades a slightly stale preview for less CPU. Nothing is captured while no preview is on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show close and quit buttons on previews", isOn: Binding(
                    get: { model.preferences.showCloseButton },
                    set: { model.preferences.showCloseButton = $0 }
                ))

                Text("Both appear only while the pointer is on a preview. Top left closes that window; top right quits the whole app, and is red because it is the one you cannot undo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Thumbnail memory budget") {
                    Stepper(
                        "\(model.preferences.thumbnailBudgetMB) MB",
                        value: Binding(
                            get: { model.preferences.thumbnailBudgetMB },
                            set: { model.preferences.thumbnailBudgetMB = $0; model.applyPreferences() }
                        ),
                        in: 16...512,
                        step: 16
                    )
                }
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
