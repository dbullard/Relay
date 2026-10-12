import XCTest
@testable import Relay

final class SyncedTabModelsTests: XCTestCase {

    func testDashboardTabSyncedFieldsDefaultToUnsynced() {
        let tab = DashboardTab(name: "Stage Plot", tiles: [])
        XCTAssertNil(tab.syncGroupID)
        XCTAssertFalse(tab.syncDeviceTargetsEnabled)
        XCTAssertEqual(tab.syncRevision, 0)
        XCTAssertEqual(tab.syncLastEditedAt, 0)
        XCTAssertEqual(tab.syncLastEditedByDeviceID, "")
        XCTAssertEqual(tab.syncLastEditedByDeviceName, "")
    }

    func testDashboardTabSyncedFieldsRoundTripThroughCodable() throws {
        var tab = DashboardTab(name: "Stage Plot", tiles: [])
        tab.syncGroupID = "GROUP-123"
        tab.syncDeviceTargetsEnabled = true
        tab.syncRevision = 4
        tab.syncLastEditedAt = 1_700_000_000
        tab.syncLastEditedByDeviceID = "DEVICE-A"
        tab.syncLastEditedByDeviceName = "Booth Mac"

        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(DashboardTab.self, from: data)

        XCTAssertEqual(decoded.syncGroupID, "GROUP-123")
        XCTAssertTrue(decoded.syncDeviceTargetsEnabled)
        XCTAssertEqual(decoded.syncRevision, 4)
        XCTAssertEqual(decoded.syncLastEditedAt, 1_700_000_000)
        XCTAssertEqual(decoded.syncLastEditedByDeviceID, "DEVICE-A")
        XCTAssertEqual(decoded.syncLastEditedByDeviceName, "Booth Mac")
    }

    func testDashboardTabDecodesOlderJSONWithoutSyncFields() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","name":"Legacy Tab","tiles":[]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DashboardTab.self, from: legacyJSON)
        XCTAssertNil(decoded.syncGroupID)
        XCTAssertEqual(decoded.syncRevision, 0)
        XCTAssertEqual(decoded.syncLastEditedByDeviceID, "")
    }

    func testApplyingLegacySnapshotPreservesLocalSyncMembership() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","name":"Legacy Tab","tiles":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DashboardTab.self, from: legacyJSON)
        var current = DashboardTab(name: "Joined Tab", tiles: [])
        current.syncGroupID = "STABLE-GROUP"
        current.syncIsOwner = false
        current.syncOwnerDeviceID = "HOST-DEVICE"
        current.syncOwnerDeviceName = "Stage Booth Mac"
        current.syncRevision = 3

        let version = SyncedTabVersion(revision: 8, editedAt: 1_700_000_000, editedByDeviceID: "OLD-HOST")
        let snapshot = SyncedTabSnapshot(
            groupID: "STABLE-GROUP",
            tabName: "Legacy Tab",
            exportedTabJSON: legacyJSON,
            schemaVersion: 1,
            version: version,
            lastEditedByDeviceName: "Older Relay",
            hash: "legacy-hash"
        )

        let applied = SyncedTabSnapshotCompatibility.applying(snapshot, to: decoded, preserving: current)

        XCTAssertEqual(applied.id, current.id)
        XCTAssertEqual(applied.syncGroupID, "STABLE-GROUP")
        XCTAssertFalse(applied.syncIsOwner)
        XCTAssertEqual(applied.syncOwnerDeviceID, "HOST-DEVICE")
        XCTAssertEqual(applied.syncOwnerDeviceName, "Stage Booth Mac")
        XCTAssertEqual(applied.syncRevision, 8)
        XCTAssertEqual(applied.syncLastEditedByDeviceID, "OLD-HOST")
        XCTAssertEqual(applied.syncLastEditedByDeviceName, "Older Relay")
    }

    // MARK: - SyncedTabVersion

    func testSyncedTabVersionOrdersByRevisionFirst() {
        let lower = SyncedTabVersion(revision: 1, editedAt: 9999, editedByDeviceID: "Z")
        let higher = SyncedTabVersion(revision: 2, editedAt: 0, editedByDeviceID: "A")
        XCTAssertTrue(lower < higher)
    }

    func testSyncedTabVersionFallsBackToEditedAtWhenRevisionTied() {
        let lower = SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: "Z")
        let higher = SyncedTabVersion(revision: 1, editedAt: 2000, editedByDeviceID: "A")
        XCTAssertTrue(lower < higher)
    }

    func testSyncedTabVersionFallsBackToDeviceIDWhenFullyTied() {
        let lower = SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: "A")
        let higher = SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: "B")
        XCTAssertTrue(lower < higher)
        XCTAssertFalse(higher < lower)
        XCTAssertEqual(lower, lower)
    }

    // MARK: - SyncedTabManifest / SyncedTabSnapshot

    func testSyncedTabManifestRoundTripsThroughCodable() throws {
        let manifest = SyncedTabManifest(
            groupID: "GROUP-1",
            tabName: "Stage Plot",
            deviceID: "DEVICE-A",
            deviceName: "Booth Mac",
            version: SyncedTabVersion(revision: 3, editedAt: 1234, editedByDeviceID: "DEVICE-A"),
            summary: SyncedTabManifest.Summary(tileCount: 5, moduleTypes: ["shure", "propresenter"])
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SyncedTabManifest.self, from: data)

        XCTAssertEqual(decoded.id, "GROUP-1")
        XCTAssertEqual(decoded.tabName, "Stage Plot")
        XCTAssertEqual(decoded.version.revision, 3)
        XCTAssertEqual(decoded.summary.tileCount, 5)
        XCTAssertEqual(decoded.summary.moduleTypes, ["shure", "propresenter"])
    }

    func testSyncedTabSnapshotRoundTripsThroughCodable() throws {
        let snapshot = SyncedTabSnapshot(
            groupID: "GROUP-1",
            tabName: "Stage Plot",
            exportedTabJSON: Data("{\"name\":\"Stage Plot\"}".utf8),
            schemaVersion: 1,
            version: SyncedTabVersion(revision: 3, editedAt: 1234, editedByDeviceID: "DEVICE-A"),
            lastEditedByDeviceName: "Booth Mac",
            hash: "deadbeef"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SyncedTabSnapshot.self, from: data)

        XCTAssertEqual(decoded.groupID, "GROUP-1")
        XCTAssertEqual(decoded.exportedTabJSON, Data("{\"name\":\"Stage Plot\"}".utf8))
        XCTAssertEqual(decoded.version.revision, 3)
        XCTAssertEqual(decoded.lastEditedByDeviceName, "Booth Mac")
        XCTAssertEqual(decoded.hash, "deadbeef")
    }

    // MARK: - strippedForSyncContentHash / syncContentHash

    func testStrippedForSyncContentHashZeroesSyncFields() {
        var tab = DashboardTab(name: "Stage Plot", tiles: [])
        tab.syncGroupID = "GROUP-1"
        tab.syncDeviceTargetsEnabled = true
        tab.syncRevision = 7
        tab.syncLastEditedAt = 1234
        tab.syncLastEditedByDeviceID = "DEVICE-A"
        tab.syncLastEditedByDeviceName = "Booth Mac"

        let stripped = tab.strippedForSyncContentHash()

        XCTAssertNil(stripped.syncGroupID)
        XCTAssertFalse(stripped.syncDeviceTargetsEnabled)
        XCTAssertEqual(stripped.syncRevision, 0)
        XCTAssertEqual(stripped.syncLastEditedAt, 0)
        XCTAssertEqual(stripped.syncLastEditedByDeviceID, "")
        XCTAssertEqual(stripped.syncLastEditedByDeviceName, "")
        XCTAssertEqual(stripped.name, "Stage Plot")
    }

    func testSyncContentHashIgnoresSyncMetadataButReflectsContentChanges() {
        var tabA = DashboardTab(name: "Stage Plot", tiles: [])
        tabA.syncRevision = 1
        tabA.syncLastEditedAt = 1000
        tabA.syncLastEditedByDeviceID = "DEVICE-A"
        tabA.syncLastEditedByDeviceName = "Booth Mac"
        tabA.syncGroupID = "GROUP-1"

        var tabB = tabA
        tabB.syncRevision = 7
        tabB.syncLastEditedAt = 9999
        tabB.syncLastEditedByDeviceID = "DEVICE-B"
        tabB.syncLastEditedByDeviceName = "FOH Mac"
        tabB.syncGroupID = "GROUP-2"

        XCTAssertEqual(tabA.syncContentHash(), tabB.syncContentHash())

        var tabC = tabA
        tabC.name = "Different Name"
        XCTAssertNotEqual(tabA.syncContentHash(), tabC.syncContentHash())
    }
}
