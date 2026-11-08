import Foundation

/// Tile types for the wizard's Starter Tiles step: every DashboardModuleCatalog entry.
/// PCO entries stay visible even before Planning Center is connected, because setup is
/// optional; the tile itself can lead users into connection/configuration later.
enum OnboardingStarterTileCatalog {
    /// Starter tiles are limited to modules that work without extra hardware or setup.
    /// Everything else stays available from the module picker once the dashboard exists.
    static let starterIDs: Set<String> = [
        "pcoRundown", "pcoTeamAssignments", "rosterTeamAssignments", "person",
        "text", "image", "rosterPicker", "document", "webpage", "time",
        "separator", "timecode"
    ]

    static func availableEntries() -> [DashboardModuleCatalogItem] {
        DashboardModuleCatalog.all(initialPerson: nil, tileID: UUID())
            .filter { starterIDs.contains($0.id) }
    }
}
