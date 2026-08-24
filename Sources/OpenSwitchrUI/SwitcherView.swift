import OpenSwitchrCore
import SwiftUI

/// The full-screen switcher overlay contents.
public struct SwitcherView: View {

    private let windows: [WindowInfo]
    private let selectedIndex: Int
    private let query: String
    private let thumbnails: ThumbnailProvider
    private let tileSize: CGSize
    private let showsCloseButtons: Bool
    private let onActivate: (Int) -> Void
    private let onClose: (Int) -> Void
    private let onQuitApp: (Int) -> Void
    private let onHover: (Int) -> Void

    public init(
        windows: [WindowInfo],
        selectedIndex: Int,
        query: String,
        thumbnails: ThumbnailProvider,
        tileSize: CGSize,
        showsCloseButtons: Bool = false,
        onActivate: @escaping (Int) -> Void,
        onClose: @escaping (Int) -> Void = { _ in },
        onQuitApp: @escaping (Int) -> Void = { _ in },
        onHover: @escaping (Int) -> Void
    ) {
        self.windows = windows
        self.selectedIndex = selectedIndex
        self.query = query
        self.thumbnails = thumbnails
        self.tileSize = tileSize
        self.showsCloseButtons = showsCloseButtons
        self.onActivate = onActivate
        self.onClose = onClose
        self.onQuitApp = onQuitApp
        self.onHover = onHover
    }

    public var body: some View {
        VStack(spacing: 10) {
            header

            if windows.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                .foregroundStyle(.secondary)

            if query.isEmpty {
                Text(selectionSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(query)
                    .font(.system(size: 12, weight: .medium))
            }

            Spacer()

            Text("\(windows.count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private var selectionSubtitle: String {
        guard windows.indices.contains(selectedIndex) else { return "No windows" }
        return windows[selectedIndex].appName
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "No open windows on this Space" : "No matches")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: tileSize.width + 16), spacing: 4)],
                    spacing: 4
                ) {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        WindowTile(
                            window: window,
                            isSelected: index == selectedIndex,
                            thumbnailSize: tileSize,
                            thumbnails: thumbnails,
                            showsCloseButton: showsCloseButtons,
                            onActivate: { onActivate(index) },
                            onClose: { onClose(index) },
                            onQuitApp: { onQuitApp(index) },
                            onHover: { isHovering in
                                if isHovering { onHover(index) }
                            }
                        )
                        .id(window.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: selectedIndex) { _, newValue in
                guard windows.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(windows[newValue].id, anchor: .center)
                }
            }
        }
    }
}
