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
        onHover: @escaping (Bool) -> Void = { _ in }
    ) {
        self.window = window
        self.isSelected = isSelected
        self.thumbnailSize = thumbnailSize
        self.thumbnails = thumbnails
        self.showsCloseButton = showsCloseButton
        self.onActivate = onActivate
        self.onClose = onClose
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
    ///
    /// Deliberately a tap gesture and not a `Button`: both frontends live in a
    /// panel whose `canBecomeKey` is `false`, and AppKit controls in a window
    /// that can never become key can swallow the click that would otherwise
    /// activate them. The tile's own activation already goes through
    /// `onTapGesture` for that reason, so the close target uses the one
    /// mechanism these panels are known to deliver. The inner gesture wins over
    /// the tile's, so closing never also raises the window.
    @ViewBuilder
    private var closeButton: some View {
        if showsCloseButton, let onClose, isPointerInside {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.black.opacity(0.55))
                .padding(5)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .help("Close window")
                .accessibilityLabel(Text("Close \(window.displayTitle)"))
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
