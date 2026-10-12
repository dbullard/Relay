import SwiftUI

struct DashboardTileShell<Content: View>: View {
    let tile: DashboardTileModel
    let size: CGSize
    let cornerRadius: CGFloat
    let activeSnapEdges: Set<DashboardTileSnapEdge>
    let isLiveMode: Bool
    let content: Content

    init(
        tile: DashboardTileModel,
        size: CGSize,
        cornerRadius: CGFloat,
        activeSnapEdges: Set<DashboardTileSnapEdge>,
        isLiveMode: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.tile = tile
        self.size = size
        self.cornerRadius = cornerRadius
        self.activeSnapEdges = activeSnapEdges
        self.isLiveMode = isLiveMode
        self.content = content()
    }

    var body: some View {
        content
            .frame(
                width: size.width,
                height: size.height,
                alignment: .topLeading
            )
            .background(
                DashboardTileBackgroundFill(
                    tile: tile,
                    cornerRadius: cornerRadius
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                DashboardTileSnapHighlightOverlay(
                    activeEdges: activeSnapEdges,
                    isLiveMode: isLiveMode
                )
            }
            .overlay(alignment: .topLeading) {
                if tile.showsTitle {
                    DashboardTileTitleBadge(name: tile.name)
                }
            }
    }
}
