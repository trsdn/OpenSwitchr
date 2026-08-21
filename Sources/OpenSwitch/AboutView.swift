import SwiftUI

struct AboutView: View {

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("OpenSwitch")
                .font(.title2.weight(.semibold))

            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Dock hover previews and a window switcher on one shared window index.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Link("Source code", destination: URL(string: "https://github.com/trsdn/OpenSwitch")!)
                .font(.callout)

            Text("MIT licensed. Written from scratch — no code from GPL-licensed window switchers.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 24)
        }
        .padding(20)
    }
}
