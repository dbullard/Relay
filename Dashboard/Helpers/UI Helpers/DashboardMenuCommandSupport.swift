//
//  DashboardMenuCommandSupport.swift
//  Relay
//
//  State and titles shared by the menu bar (`RelayCommands`), the context menus and
//  the iPad "more" menus, so one action has one name everywhere.
//

import SwiftUI
import Combine

/// What the menu bar needs to know about the dashboard to title and enable its items.
/// `DashboardRootView` publishes it; `RelayCommands` reads it.
struct DashboardMenuSnapshot: Equatable {
    var selectedTileCount: Int = 0
    var isInspectorVisible: Bool = false
    var isTileOverviewVisible: Bool = false
    var hasTilesInTab: Bool = false
    /// A local tab (not a LAN mirror) is showing, so tile and tab edits apply to it.
    var isEditableTabSelected: Bool = false
    /// The selected tab can be deleted (a local tab, and not the only tab).
    var canDeleteSelectedTab: Bool = false
}

/// Mirrors `DashboardMenuSnapshot` for `Commands`, which can't read the root view's state.
/// Publishes only when the snapshot actually changes.
final class DashboardMenuState: ObservableObject {
    static let shared = DashboardMenuState()

    let objectWillChange = ObservableObjectPublisher()
    private(set) var snapshot = DashboardMenuSnapshot()

    func update(_ newValue: DashboardMenuSnapshot) {
        guard newValue != snapshot else { return }
        objectWillChange.send()
        snapshot = newValue
    }
}

/// Menu item titles that depend on the view mode or the selection.
enum DashboardMenuTitles {
    static func deleteSelection(isAutomation: Bool) -> String {
        isAutomation ? "Delete Selected Nodes" : "Delete Selected Tiles"
    }

    static func tileOverviewToggle(isVisible: Bool) -> String {
        isVisible ? "Hide Tile Overview" : "Show Tile Overview"
    }

    static func inspectorToggle(isVisible: Bool) -> String {
        isVisible ? "Hide Inspector" : "Show Inspector"
    }

    /// How many tiles a tile's context menu acts on: the whole selection when the tile is
    /// part of it, otherwise just that tile (right-clicking a tile doesn't select it).
    static func targetTileCount(tileID: UUID, selectedTileIDs: Set<UUID>) -> Int {
        selectedTileIDs.contains(tileID) ? max(1, selectedTileIDs.count) : 1
    }

    static func editTiles(count: Int) -> String {
        count > 1 ? "Edit \(count) Tiles…" : "Edit Tile…"
    }

    static func duplicateTiles(count: Int) -> String {
        count > 1 ? "Duplicate \(count) Tiles" : "Duplicate Tile"
    }

    static func groupTiles(count: Int) -> String {
        "Group \(count) Tiles…"
    }

    static func deleteTiles(count: Int) -> String {
        count > 1 ? "Delete \(count) Tiles" : "Delete Tile"
    }
}

/// A View menu zoom command, applied to whichever viewport is showing.
enum ViewportZoomCommand: String {
    case zoomIn
    case zoomOut
    case actualSize

    /// Matches the zoom buttons' step in `ViewportPanZoomControls`.
    static let step: CGFloat = 0.12

    /// The new zoom and pan for the canvas viewport, zooming about the viewport centre and
    /// clamped to `range`. `nil` when nothing changes (already at a limit).
    func applied(
        zoom: CGFloat,
        pan: CGSize,
        contentSize: CGSize,
        viewportSize: CGSize,
        range: ClosedRange<CGFloat>
    ) -> (zoom: CGFloat, pan: CGSize)? {
        let centre = CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5)
        switch self {
        case .zoomIn:
            return ViewportZoomMath.anchoredZoom(
                currentZoom: zoom, currentPan: pan, proposedZoom: zoom + Self.step,
                anchorInView: centre, range: range
            )
        case .zoomOut:
            return ViewportZoomMath.anchoredZoom(
                currentZoom: zoom, currentPan: pan, proposedZoom: zoom - Self.step,
                anchorInView: centre, range: range
            )
        case .actualSize:
            return ViewportPanZoomControls.actualSizeViewport(contentSize: contentSize, viewportSize: viewportSize)
        }
    }
}
