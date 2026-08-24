import AppKit
import OpenSwitchrCore
import SwiftUI

/// One window in the switcher grid or a Dock preview row.
///
/// Renders instantly from the app icon and only upgrades to a live thumbnail
/// once the capture arrives, so no tile ever blocks the overlay.
public struct WindowTile: View {

    private let window: WindowInfo
    private let isSelected: Bool
    private let thumbnailSize: CGSize
    private let thumbnails: ThumbnailProvider
    private let showsCloseButton: Bool
    private let onActivate: () -> Void
    private let onClose: (() -> Void)?
    private let onQuitApp: (() -> Void)?
    private let onHover: (Bool) -> Void

    @State private var isPointerInside = false

    public init(
        window: WindowInfo,
        isSelected: Bool,
        thumbnailSize: CGSize,
        thumbnails: ThumbnailProvider,
        showsCloseButton: Bool = false,
        onActivate: @escaping () -> Void,
        onClose: (() -> Void)? = nil,
        onQuitApp: (() -> Void)? = nil,
        onHover: @escaping (Bool) -> Void = { _ in }
    ) {
        self.window = window
        self.isSelected = isSelected
        self.thumbnailSize = thumbnailSize
        self.thumbnails = thumbnails
        self.showsCloseButton = showsCloseButton
        self.onActivate = onActivate
        self.onClose = onClose
        self.onQuitApp = onQuitApp
        self.onHover = onHover
    }

    public var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: isSelected ? 3 : 1)
                )
                .overlay(alignment: .topLeading) { closeButton }
                .overlay(alignment: .topTrailing) { quitButton }

            label
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { hovering in
            isPointerInside = hovering
            onHover(hovering)
        }
        .onAppear { thumbnails.request(window.id, maxPixelSize: thumbnailSize.width * 2) }
        .accessibilityLabel(Text("\(window.appName): \(window.displayTitle)"))
    }

    /// Only drawn while the pointer is on this tile. A permanent control would
    /// turn a row of previews into a row of buttons, and it puts a destructive
    /// action next to every click target.
    @ViewBuilder
    private var closeButton: some View {
        if showsCloseButton, let onClose {
            tileControl(
                systemName: "xmark.circle.fill",
                tint: Color.black.opacity(0.55),
                help: "Close window",
                label: "Close \(window.displayTitle)",
                action: onClose
            )
        }
    }

    /// Quitting ends every window of the app, not just this one, so it sits in
    /// the opposite corner from close rather than beside it — the two are one
    /// slip apart otherwise, and only one of them is undoable. It is red for the
    /// same reason. `NSRunningApplication.terminate()` is the polite request, so
    /// an app with unsaved work still gets to put its own dialog up.
    @ViewBuilder
    private var quitButton: some View {
        if showsCloseButton, let onQuitApp {
            tileControl(
                systemName: "power.circle.fill",
                tint: Color.red.opacity(0.85),
                help: "Quit \(window.appName)",
                label: "Quit \(window.appName)",
                action: onQuitApp
            )
        }
    }

    /// Deliberately a tap gesture and not a `Button`: both frontends live in a
    /// panel whose `canBecomeKey` is `false`, and AppKit controls in a window
    /// that can never become key can swallow the click that would otherwise
    /// activate them. The tile's own activation already goes through
    /// `onTapGesture` for that reason, so these use the one mechanism these
    /// panels are known to deliver. The inner gesture wins over the tile's, so
    /// neither control also raises the window.
    @ViewBuilder
    private func tileControl(
        systemName: String,
        tint: Color,
        help: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        if isPointerInside {
            Image(systemName: systemName)
                .font(.system(size: 15))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, tint)
                .padding(5)
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .help(help)
                .accessibilityLabel(Text(label))
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = thumbnails.image(for: window.id) {
            Image(decorative: image, scale: 2, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(window.isMinimized ? 0.55 : 1)
        } else {
            iconPlaceholder
        }
    }

    private var iconPlaceholder: some View {
        ZStack {
            if let icon = AppIconCache.icon(forPID: window.pid) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(64, thumbnailSize.height * 0.5))
                    .opacity(0.9)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            if let icon = AppIconCache.icon(forPID: window.pid) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }

            Text(window.displayTitle)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)

            if window.isMinimized {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Minimized")
            }
        }
        .frame(width: thumbnailSize.width, alignment: .center)
    }
}
