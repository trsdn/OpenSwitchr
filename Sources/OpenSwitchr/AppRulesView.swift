import AppKit
import OpenSwitchrCore
import SwiftUI

/// Edits the per-application rule table: hide an application's windows, and
/// stand aside for it while it is full screen.
///
/// Every edit goes back through `applyPreferences()`, because the stand-aside
/// decision is computed outside this view and has to be recomputed.
struct AppRulesView: View {

    @Bindable var model: AppModel
    @State private var newPrefix = ""

    private enum HideKind: String, CaseIterable {
        case never, always, titleContains

        var title: String {
            switch self {
            case .never: return "Never"
            case .always: return "Always"
            case .titleContains: return "When the title contains"
            }
        }

        init(_ policy: AppRule.HidePolicy) {
            switch policy {
            case .never: self = .never
            case .always: self = .always
            case .whenTitleContains: self = .titleContains
            }
        }
    }

    private var rules: [AppRule] { model.preferences.appRules.rules }

    var body: some View {
        Form {
            Section("Rules") {
                Text(
                    "Matched by bundle identifier prefix, so one entry covers a vendor's several builds. The most specific prefix wins."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if rules.isEmpty {
                    Text("No rules. Nothing is hidden and the hotkey never stands aside.")
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(rules.enumerated()), id: \.offset) { offset, rule in
                    row(offset, rule)
                }
            }

            Section("Add a rule") {
                HStack {
                    // The label is the field's own prompt rather than a leading label:
                    // beside the field it wrapped onto two lines in German and
                    // squeezed the field it names.
                    TextField(
                        "Bundle identifier prefix",
                        text: $newPrefix,
                        prompt: Text("Bundle identifier prefix")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(addTypedPrefix)
                    Button("Add", action: addTypedPrefix)
                        .disabled(newPrefix.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Menu("Add a running application") {
                    ForEach(runningApplications, id: \.bundleID) { app in
                        Button(app.name) { add(prefix: app.bundleID) }
                    }
                }

                Button("Restore the shipped defaults") {
                    model.preferences.appRules = .defaults
                    model.applyPreferences()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ offset: Int, _ rule: AppRule) -> some View {
        let hidden = model.preferences.appRules.hiddenCount(by: rule, in: model.index.windows)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rule.bundleIDPrefix)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button(role: .destructive) {
                    update { $0.remove(at: offset) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Delete the rule for \(rule.bundleIDPrefix)"))
            }

            Picker(
                "Hide windows",
                selection: Binding(
                    get: { HideKind(rule.hide) },
                    set: { kind in
                        update { rules in
                            switch kind {
                            case .never: rules[offset].hide = .never
                            case .always: rules[offset].hide = .always
                            case .titleContains: rules[offset].hide = .whenTitleContains("")
                            }
                        }
                    }
                )
            ) {
                ForEach(HideKind.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
            }

            if case .whenTitleContains(let text) = rule.hide {
                TextField(
                    "Title contains",
                    text: Binding(
                        get: { text },
                        set: { value in update { $0[offset].hide = .whenTitleContains(value) } }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }

            Toggle(
                "Stand aside while it is frontmost and full screen",
                isOn: Binding(
                    get: { rule.standAsideWhenFullScreen },
                    set: { value in update { $0[offset].standAsideWhenFullScreen = value } }
                ))

            // What a rule costs, stated where it is set. A rule that hides
            // everything otherwise shows up as a bug report that says the
            // switcher is empty.
            if rule.hide != .never {
                Text("Hides \(hidden) windows right now.")
                    .font(.caption)
                    .foregroundStyle(hidden > 0 ? .primary : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private struct RunningApp {
        let name: String
        let bundleID: String
    }

    private var runningApplications: [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return RunningApp(name: app.localizedName ?? bundleID, bundleID: bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addTypedPrefix() {
        add(prefix: newPrefix.trimmingCharacters(in: .whitespaces))
        newPrefix = ""
    }

    private func add(prefix: String) {
        guard !prefix.isEmpty, !rules.contains(where: { $0.bundleIDPrefix == prefix }) else { return }
        update { $0.append(AppRule(bundleIDPrefix: prefix)) }
    }

    private func update(_ change: (inout [AppRule]) -> Void) {
        var next = model.preferences.appRules.rules
        change(&next)
        model.preferences.appRules = AppRuleTable(rules: next)
        model.applyPreferences()
    }
}
