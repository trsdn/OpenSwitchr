import OpenSwitchCore
import SwiftUI

/// Contents of the panel that appears when hovering a Dock icon.
///
/// Same tiles, same thumbnail store, same actions as the switcher — only the
/// layout and the entry point differ. That shared foundation is the reason
/// OpenSwitch exists as one app instead of two.
public struct DockPreviewView: View {

    private let windows: [WindowInfo]
    private let hoveredIndex: Int?
    private let thumbnails: ThumbnailProvider
    private let tileSize: CGSize
    private let onActivate: (Int) -> Void
    private let onHover: (Int?) -> Void

    public init(
        windows: [WindowInfo],
        hoveredIndex: Int?,
        thumbnails: ThumbnailProvider,
        tileSize: CGSize,
        onActivate: @escaping (Int) -> Void,
        onHover: @escaping (Int?) -> Void
    ) {
        self.windows = windows
        self.hoveredIndex = hoveredIndex
        self.thumbnails = thumbnails
        self.tileSize = tileSize
        self.onActivate = onActivate
        self.onHover = onHover
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                WindowTile(
                    window: window,
                    isSelected: index == hoveredIndex,
                    thumbnailSize: tileSize,
                    thumbnails: thumbnails,
                    onActivate: { onActivate(index) },
                    onHover: { isHovering in
                        onHover(isHovering ? index : nil)
                    }
                )
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    /// Size the panel needs for the given window count.
    public static func panelSize(windowCount: Int, tileSize: CGSize) -> CGSize {
        let tileWidth = tileSize.width + 16 + 2
        return CGSize(
            width: max(1, CGFloat(windowCount)) * tileWidth + 16,
            height: tileSize.height + 16 + 20 + 16
        )
    }
}
