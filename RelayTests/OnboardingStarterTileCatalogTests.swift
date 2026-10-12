import XCTest
@testable import Relay

final class OnboardingStarterTileCatalogTests: XCTestCase {

    func test_availableEntries_excludesProOnlyKinds() {
        let entries = OnboardingStarterTileCatalog.availableEntries()

        XCTAssertFalse(entries.contains { $0.id == "rta" })
        XCTAssertFalse(entries.contains { $0.id == "spectrograph" })
        XCTAssertFalse(entries.contains { $0.id == "shure" })
        XCTAssertFalse(entries.contains { $0.id == "propresenter" })
        XCTAssertFalse(entries.contains { $0.id == "button" })
        XCTAssertFalse(entries.contains { $0.id == "ndi" })
    }

    func test_availableEntries_includesPCOEntriesEvenWhenDisconnected() {
        let entries = OnboardingStarterTileCatalog.availableEntries()

        XCTAssertTrue(entries.contains { $0.id == "pcoRundown" })
        XCTAssertTrue(entries.contains { $0.id == "pcoTeamAssignments" })
    }

    func test_availableEntries_alwaysIncludesRosterEntries() {
        let entries = OnboardingStarterTileCatalog.availableEntries()
        XCTAssertTrue(entries.contains { $0.id == "rosterTeamAssignments" })
        XCTAssertTrue(entries.contains { $0.id == "rosterPicker" })
    }

    func test_availableEntries_matchesExpectedFreeSet() {
        let entries = OnboardingStarterTileCatalog.availableEntries()
        let ids = Set(entries.map(\.id))

        XCTAssertEqual(ids, [
            "pcoRundown", "pcoTeamAssignments", "rosterTeamAssignments", "person",
            "text", "image", "rosterPicker", "document", "webpage", "time",
            "separator", "timecode"
        ])
    }
}
