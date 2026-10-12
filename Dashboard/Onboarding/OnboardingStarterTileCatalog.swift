import Foundation

/// Free-tier-eligible tile types for the wizard's Starter Tiles step: every
/// DashboardModuleCatalog entry that doesn't require Pro. PCO entries stay visible even
/// before Planning Center is connected because free onboarding skips service setup; the
/// tile itself can lead users into connection/configuration later.
enum OnboardingStarterTileCatalog {
    static func availableEntries() -> [DashboardModuleCatalogItem] {
        DashboardModuleCatalog.all(initialPerson: nil, tileID: UUID())
            .filter { entry in
                !entry.requiresPro
            }
    }
}
