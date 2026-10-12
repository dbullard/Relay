import SwiftUI

struct DashboardTileContextMenu: View {
    @Binding var tile: DashboardTileModel
    @Binding var tab: DashboardTab
    let isEmptyTile: Bool
    let isLiveMode: Bool
    let snapToGrid: Bool
    let gridSize: CGFloat
    let selectedTileIDs: Set<UUID>
    let onEditRequested: (Bool) -> Void
    let onDelete: () -> Void
    let onPersist: (_ reconcileGraphNodes: Bool) -> Void
    let onAlignSelectedTilesToGrid: () -> Void
    let onResolveTileOverlapsToGrid: () -> Void
    let onDistributeSpacingHorizontally: () -> Void
    let onDistributeSpacingVertically: () -> Void

    var body: some View {
        if !isEmptyTile {
            Button {
                onEditRequested(false)
            } label: {
                Label("Edit Tile(s)…", systemImage: "slider.horizontal.3")
            }
        }

        if !isLiveMode {
            Button {
                NotificationCenter.default.post(name: .createTileGroupRequested, object: nil)
            } label: {
                DashboardSymbolLabel("Group Tile(s)…", preferred: "square.grid.2x2")
            }

            Divider()

            Button {
                duplicateTile()
            } label: {
                Label("Duplicate Tile", systemImage: "square.on.square")
            }
            .disabled(selectedTileIDs.count > 1)

            Divider()
            
            Button {
                onDistributeSpacingHorizontally()
            } label: {
                Label("Tidy Up Horizontally", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .disabled(selectedTileIDs.count < 2)
            
            Button {
                onDistributeSpacingVertically()
            } label: {
                Label("Tidy Up Vertically", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .disabled(selectedTileIDs.count < 2)

            if snapToGrid, gridSize > 0 {
                Button {
                    onAlignSelectedTilesToGrid()
                } label: {
                    DashboardSymbolLabel("Align Selected Tiles to Grid", preferred: "square.grid.3x3")
                }
            }

            if gridSize > 0 {
                Button {
                    onResolveTileOverlapsToGrid()
                } label: {
                    DashboardSymbolLabel("Resolve Tile Overlaps", preferred: "arrow.triangle.branch")
                }
            }
        }

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label(selectedTileIDs.count > 1 ? "Delete Tile(s)" : "Delete Tile", systemImage: "trash")
        }
    }

    private func duplicateTile() {
        let offsetDelta: CGFloat = 24
        let newOffset = CGSize(
            width: tile.offset.width + offsetDelta,
            height: tile.offset.height + offsetDelta
        )
        let duplicatedModules = tile.modules?.map { module in
            DashboardModuleModel(
                kind: module.kind.duplicatedForCanvasCopy(),
                order: module.order,
                id: UUID(),
                pcoConfig: module.pcoConfig,
                shureConfig: module.shureConfig,
                shureOverviewConfig: module.shureOverviewConfig,
                sennheiserConfig: module.sennheiserConfig,
                proPresenterConfig: module.proPresenterConfig,
                resolumeConfig: module.resolumeConfig,
                timeConfig: module.timeConfig,
                timecodeConfig: module.timecodeConfig,
                dawTransportConfig: module.dawTransportConfig,
                rosterTeamAssignmentsConfig: module.rosterTeamAssignmentsConfig,
                paddingTop: module.paddingTop,
                paddingBottom: module.paddingBottom,
                moduleScale: module.moduleScale,
                moduleHeightPoints: module.moduleHeightPoints
            )
        }

        let duplicate = DashboardTileModel(
            name: tile.name,
            kind: ((tile.modules?.isEmpty ?? true) ? tile.kind : .empty),
            modules: duplicatedModules,
            moduleLayout: tile.moduleLayout,
            offset: newOffset,
            size: tile.size,
            shureShowDeviceName: tile.shureShowDeviceName,
            shureShowChannelName: tile.shureShowChannelName,
            shureShowIPPort: tile.shureShowIPPort,
            shureShowFrequency: tile.shureShowFrequency,
            shureShowBattery: tile.shureShowBattery,
            shureShowRFStrength: tile.shureShowRFStrength,
            showsTitle: tile.showsTitle,
            contentPadding: tile.contentPadding
        )

        tab.tiles.append(duplicate)
        onPersist(true)
    }
}
