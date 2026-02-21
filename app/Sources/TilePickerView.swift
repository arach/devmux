import SwiftUI

struct TilePickerView: View {
    let sessionName: String
    let terminal: Terminal
    let onSelect: (TilePosition) -> Void
    let onGoToSpace: (Int) -> Void  // space ID
    let onDismiss: () -> Void

    @State private var hoveredTile: TilePosition?
    @State private var hoveredSpace: Int?  // space ID
    @State private var displaySpaces: [DisplaySpaces] = []
    @State private var windowSpaceId: Int = 0

    private let grid: [[TilePosition]] = [
        [.topLeft, .topRight],
        [.left, .right],
        [.bottomLeft, .bottomRight],
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("TILE WINDOW")
                    .font(Typo.pixel(12))
                    .foregroundColor(Palette.running)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Palette.textDim)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.surface)
                        )
                }
                .buttonStyle(.plain)
            }

            // Tile grid
            VStack(spacing: 3) {
                ForEach(grid, id: \.first?.id) { row in
                    HStack(spacing: 3) {
                        ForEach(row) { tile in
                            tileCell(tile)
                        }
                    }
                }
            }

            HStack(spacing: 3) {
                tileWideCell(.maximize)
                tileWideCell(.center)
            }

            // Spaces per display — navigate to space
            ForEach(displaySpaces, id: \.displayIndex) { display in
                if display.spaces.count > 1 || displaySpaces.count > 1 {
                    Rectangle()
                        .fill(Palette.border)
                        .frame(height: 0.5)
                        .padding(.vertical, 2)

                    HStack {
                        Text(displaySpaces.count > 1 ? "DISPLAY \(display.displayIndex + 1)" : "GO TO SPACE")
                            .font(Typo.pixel(10))
                            .foregroundColor(Palette.textMuted)
                        Spacer()
                        if windowSpaceId > 0 {
                            let windowOnDisplay = display.spaces.contains { $0.id == windowSpaceId }
                            if windowOnDisplay {
                                Text("window here")
                                    .font(Typo.mono(9))
                                    .foregroundColor(Palette.running)
                            }
                        }
                    }

                    HStack(spacing: 3) {
                        ForEach(display.spaces) { space in
                            spaceCell(space: space)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                )
        )
        .onAppear {
            displaySpaces = WindowTiler.getDisplaySpaces()
            // Find which space this session's window is on
            let tag = Terminal.windowTag(for: sessionName)
            if let (wid, _) = WindowTiler.findWindow(tag: tag),
               let space = WindowTiler.getSpacesForWindow(wid).first {
                windowSpaceId = space
            }
        }
    }

    private func tileCell(_ tile: TilePosition) -> some View {
        Button {
            onSelect(tile)
        } label: {
            Image(systemName: tile.icon)
                .font(.system(size: 14))
                .foregroundColor(hoveredTile == tile ? Palette.running : Palette.textDim)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveredTile == tile ? Palette.running.opacity(0.1) : Palette.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(
                                    hoveredTile == tile ? Palette.running.opacity(0.3) : Palette.border,
                                    lineWidth: 0.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveredTile = $0 ? tile : nil }
    }

    private func tileWideCell(_ tile: TilePosition) -> some View {
        Button {
            onSelect(tile)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tile.icon)
                    .font(.system(size: 12))
                Text(tile.label)
                    .font(Typo.mono(10))
            }
            .foregroundColor(hoveredTile == tile ? Palette.running : Palette.textDim)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredTile == tile ? Palette.running.opacity(0.1) : Palette.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                hoveredTile == tile ? Palette.running.opacity(0.3) : Palette.border,
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredTile = $0 ? tile : nil }
    }

    private func spaceCell(space: SpaceInfo) -> some View {
        let hasWindow = space.id == windowSpaceId
        return Button {
            onGoToSpace(space.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: space.isCurrent ? "desktopcomputer" : hasWindow ? "macwindow" : "rectangle.on.rectangle")
                    .font(.system(size: 10))
                Text("\(space.index)")
                    .font(Typo.monoBold(11))
            }
            .foregroundColor(
                hoveredSpace == space.id ? Palette.running :
                hasWindow ? Palette.running :
                space.isCurrent ? Palette.text : Palette.textDim
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        hoveredSpace == space.id ? Palette.running.opacity(0.1) :
                        hasWindow ? Palette.running.opacity(0.05) :
                        space.isCurrent ? Palette.bg.opacity(0.5) : Palette.bg
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                hoveredSpace == space.id ? Palette.running.opacity(0.3) :
                                hasWindow ? Palette.running.opacity(0.3) :
                                space.isCurrent ? Palette.borderLit : Palette.border,
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredSpace = $0 ? space.id : nil }
    }
}
