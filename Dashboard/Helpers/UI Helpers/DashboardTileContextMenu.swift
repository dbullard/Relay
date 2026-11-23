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
    /// Registers an undo step (call before the edit it undoes).
    let onUndoSnapshot: (_ actionName: String) -> Void
    let onAlignSelectedTilesToGrid: () -> Void
    let onResolveTileOverlapsToGrid: () -> Void
    let onDistributeSpacingHorizontally: () -> Void
    let onDistributeSpacingVertically: () -> Void

    /// Tiles the menu acts on: the selection when this tile is part of it, otherwise just
    /// this tile (right-clicking a tile doesn't change the selection).
    private var targetTileIDs: Set<UUID> {
        selectedTileIDs.contains(tile.id) ? selectedTileIDs : [tile.id]
    }

    var body: some View {
        let targetCount = DashboardMenuTitles.targetTileCount(tileID: tile.id, selectedTileIDs: selectedTileIDs)

        if !isEmptyTile {
            Button {
                onEditRequested(false)
            } label: {
                Label(DashboardMenuTitles.editTiles(count: targetCount), systemImage: "slider.horizontal.3")
            }
        }

        if !isLiveMode {
            if !isEmptyTile {
                Divider()
            }

            Button {
                if targetCount > 1 {
                    // Same path as Edit ▸ Duplicate (⌘D), which duplicates the selection.
                    NotificationCenter.default.post(name: .duplicateTileRequested, object: nil)
                } else {
                    duplicateTile()
                }
            } label: {
                Label(DashboardMenuTitles.duplicateTiles(count: targetCount), systemImage: "square.on.square")
            }

            if targetCount >= 2 {
                Button {
                    NotificationCenter.default.post(name: .createTileGroupRequested, object: nil)
                } label: {
                    DashboardSymbolLabel(DashboardMenuTitles.groupTiles(count: targetCount), preferred: "square.grid.2x2")
                }
            }

            Button {
                NotificationCenter.default.post(name: .dashboardHideTilesRequested, object: targetTileIDs)
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }

            Divider()

            Menu {
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
                        DashboardSymbolLabel("Align to Grid", preferred: "square.grid.3x3")
                    }
                }

                if gridSize > 0 {
                    Button {
                        onResolveTileOverlapsToGrid()
                    } label: {
                        DashboardSymbolLabel("Resolve Overlaps", preferred: "arrow.triangle.branch")
                    }
                }
            } label: {
                Label("Arrange", systemImage: "rectangle.3.group")
            }

            Divider()
        }

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label(DashboardMenuTitles.deleteTiles(count: targetCount), systemImage: "trash")
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

        onUndoSnapshot("Duplicate Tile")
        tab.tiles.append(duplicate)
        onPersist(true)
    }
}
