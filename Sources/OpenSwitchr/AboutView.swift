import OpenSwitchrUI
import SwiftUI

struct AboutView: View {

    /// Every value here is read back out of the bundle rather than written a
    /// second time in Swift. `Info.plist` is the one home for the app's
    /// identity, so the About tab cannot drift away from what actually shipped.
    private struct Identity {
        let version: String
        let copyright: String
        let repository: URL?
        let issues: URL?

        init(bundle: Bundle = .main) {
            let info = bundle.infoDictionary ?? [:]
            func string(_ key: String) -> String? { info[key] as? String }
            func url(_ key: String) -> URL? { string(key).flatMap(URL.init(string:)) }

            version = string("CFBundleShortVersionString") ?? "dev"
            copyright = string("NSHumanReadableCopyright") ?? ""
            repository = url("OSWRepositoryURL")
            issues = url("OSWIssueTrackerURL")
        }
    }

    private let identity = Identity()

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: WindowMark.templateImage(width: 52))
                .renderingMode(.template)
                .foregroundStyle(.tint)

            Text("OpenSwitchr")
                .font(.title2.weight(.semibold))

            Text("Version \(identity.version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Dock hover previews and a window switcher on one shared window index.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            HStack(spacing: 16) {
                if let repository = identity.repository {
                    Link("Source code", destination: repository)
                }
                if let issues = identity.issues {
                    Link("Report an issue", destination: issues)
                }
            }
            .font(.callout)

            if !identity.copyright.isEmpty {
                Text(identity.copyright)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            }
        }
        .padding(20)
    }
}
