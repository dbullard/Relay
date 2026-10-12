import XCTest
@testable import Relay

final class DevicePairingStoreTests: XCTestCase {

    func testStatusNotPairedWhenNoEntry() {
        let status = DevicePairingStore.status(for: "device-a", in: [:])
        XCTAssertEqual(status, .notPaired)
    }

    func testStatusPairedWhenEnabledEntry() {
        let devices = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, isEnabled: true, pairedAt: Date())]
        XCTAssertEqual(DevicePairingStore.status(for: "device-a", in: devices), .paired)
    }

    func testStatusBlockedWhenDisabledEntry() {
        let devices = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, isEnabled: false, pairedAt: Date())]
        XCTAssertEqual(DevicePairingStore.status(for: "device-a", in: devices), .blocked)
    }

    func testIsAuthorizedTrueOnlyWhenPaired() {
        let paired = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: nil, isEnabled: true, pairedAt: Date())]
        let blocked = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: nil, isEnabled: false, pairedAt: Date())]
        XCTAssertTrue(DevicePairingStore.isAuthorized(deviceId: "device-a", in: paired))
        XCTAssertFalse(DevicePairingStore.isAuthorized(deviceId: "device-a", in: blocked))
        XCTAssertFalse(DevicePairingStore.isAuthorized(deviceId: "device-a", in: [:]))
    }

    func testSetEnabledTrueCreatesNewEntryForNeverSeenDevice() {
        let updated = DevicePairingStore.setEnabled(true, deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, in: [:])
        XCTAssertEqual(DevicePairingStore.status(for: "device-a", in: updated), .paired)
        XCTAssertEqual(updated["device-a"]?.deviceName, "iPhone")
        XCTAssertEqual(updated["device-a"]?.sharesVariables, true)
    }

    func testExistingPairDecodesWithVariableSharingOn() throws {
        let oldJSON = #"{"deviceId":"device-a","deviceName":"Old Mac","deviceKind":"mac","isEnabled":true,"pairedAt":0}"#.data(using: .utf8)!
        let pair = try JSONDecoder().decode(PairedDevice.self, from: oldJSON)
        XCTAssertTrue(pair.sharesVariables)
        let disabled = DevicePairingStore.setSharesVariables(false, deviceId: pair.deviceId, in: [pair.deviceId: pair])
        XCTAssertFalse(disabled[pair.deviceId]?.sharesVariables == true)
    }

    func testVariableSwitchDoesNotChangePairing() {
        let paired = DevicePairingStore.setEnabled(true, deviceId: "device-a", deviceName: "Mac", deviceKind: .mac, in: [:])
        let off = DevicePairingStore.setSharesVariables(false, deviceId: "device-a", in: paired)
        XCTAssertEqual(DevicePairingStore.status(for: "device-a", in: off), .paired)
        XCTAssertFalse(off["device-a"]!.sharesVariables)
    }

    func testSetEnabledFalsePreBlocksNeverPairedDevice() {
        let updated = DevicePairingStore.setEnabled(false, deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, in: [:])
        XCTAssertEqual(DevicePairingStore.status(for: "device-a", in: updated), .blocked)
    }

    func testSetEnabledFalseRevokesExistingPairedDevice() {
        let paired = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, isEnabled: true, pairedAt: Date())]
        let updated = DevicePairingStore.setEnabled(false, deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, in: paired)
        XCTAssertEqual(DevicePairingStore.status(for: "device-a", in: updated), .blocked)
    }

    func testSetEnabledTrueRestoresTrustForBlockedDevice() {
        let blocked = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, isEnabled: false, pairedAt: Date())]
        let updated = DevicePairingStore.setEnabled(true, deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, in: blocked)
        XCTAssertEqual(DevicePairingStore.status(for: "device-a", in: updated), .paired)
    }

    func testSetEnabledPreservesOriginalPairedAtWhenTogglingExistingEntry() {
        let originalPairedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let paired = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, isEnabled: true, pairedAt: originalPairedAt)]

        let revoked = DevicePairingStore.setEnabled(false, deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, in: paired)
        XCTAssertEqual(revoked["device-a"]?.pairedAt, originalPairedAt)

        let restored = DevicePairingStore.setEnabled(true, deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, in: revoked)
        XCTAssertEqual(restored["device-a"]?.pairedAt, originalPairedAt)
    }

    func testSetEnabledUpdatesDeviceNameAndKindOnReapproval() {
        let paired = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "Old Name", deviceKind: .iphone, isEnabled: true, pairedAt: Date())]
        let updated = DevicePairingStore.setEnabled(true, deviceId: "device-a", deviceName: "New Name", deviceKind: .ipad, in: paired)
        XCTAssertEqual(updated["device-a"]?.deviceName, "New Name")
        XCTAssertEqual(updated["device-a"]?.deviceKind, .ipad)
    }

    func testRemoveDeletesExistingEntryEntirely() {
        let paired = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, isEnabled: true, pairedAt: Date())]
        let updated = DevicePairingStore.remove(deviceId: "device-a", in: paired)
        XCTAssertNil(updated["device-a"])
        XCTAssertEqual(DevicePairingStore.status(for: "device-a", in: updated), .notPaired)
    }

    func testRemoveOnMissingEntryIsANoOp() {
        let updated = DevicePairingStore.remove(deviceId: "device-a", in: [:])
        XCTAssertTrue(updated.isEmpty)
    }

    func testRemoveOnlyAffectsTheTargetDevice() {
        let devices = [
            "device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, isEnabled: true, pairedAt: Date()),
            "device-b": PairedDevice(deviceId: "device-b", deviceName: "iPad", deviceKind: .ipad, isEnabled: false, pairedAt: Date())
        ]
        let updated = DevicePairingStore.remove(deviceId: "device-a", in: devices)
        XCTAssertNil(updated["device-a"])
        XCTAssertEqual(updated["device-b"]?.deviceName, "iPad")
    }

    func testSaveLoadRoundTrip() {
        let suiteName = "DevicePairingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let devices = ["device-a": PairedDevice(deviceId: "device-a", deviceName: "iPhone", deviceKind: .iphone, isEnabled: true, pairedAt: Date())]
        DevicePairingStore.save(devices, to: defaults)
        let loaded = DevicePairingStore.load(from: defaults)
        XCTAssertEqual(loaded["device-a"]?.deviceId, "device-a")
        XCTAssertEqual(loaded["device-a"]?.isEnabled, true)
    }

    func testLoadReturnsEmptyWhenNothingSaved() {
        let suiteName = "DevicePairingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(DevicePairingStore.load(from: defaults).isEmpty)
    }

    // MARK: - Legacy name-keyed trust migration
    //
    // Builds before the TXT-record browse fix identified peers by their Bonjour service name,
    // so trust granted by the device that *started* pairing was saved under the other
    // computer's name instead of its stable deviceId. Requests identify themselves by
    // deviceId, so those entries never authorized anything.

    func testMigrationMovesNameKeyedEntryToDeviceId() {
        let pairedAt = Date(timeIntervalSince1970: 1_000)
        let legacy = ["FOH Mac mini": PairedDevice(deviceId: "FOH Mac mini", deviceName: "FOH Mac mini", deviceKind: nil, isEnabled: true, pairedAt: pairedAt)]
        let updated = DevicePairingStore.migratingLegacyNameKeyedEntry(
            toDeviceId: "UUID-FOH", deviceName: "FOH Mac mini", deviceKind: .mac, in: legacy
        )
        XCTAssertNil(updated["FOH Mac mini"])
        XCTAssertEqual(updated["UUID-FOH"]?.deviceId, "UUID-FOH")
        XCTAssertEqual(updated["UUID-FOH"]?.pairedAt, pairedAt)
        XCTAssertEqual(updated["UUID-FOH"]?.deviceKind, .mac)
        XCTAssertTrue(DevicePairingStore.isAuthorized(deviceId: "UUID-FOH", in: updated))
    }

    func testMigrationPreservesBlockedState() {
        let legacy = ["FOH Mac mini": PairedDevice(deviceId: "FOH Mac mini", deviceName: "FOH Mac mini", deviceKind: nil, isEnabled: false, pairedAt: Date())]
        let updated = DevicePairingStore.migratingLegacyNameKeyedEntry(
            toDeviceId: "UUID-FOH", deviceName: "FOH Mac mini", deviceKind: nil, in: legacy
        )
        XCTAssertEqual(DevicePairingStore.status(for: "UUID-FOH", in: updated), .blocked)
    }

    func testMigrationKeepsExistingDeviceIdEntryAndDropsLegacyDuplicate() {
        let devices = [
            "UUID-FOH": PairedDevice(deviceId: "UUID-FOH", deviceName: "FOH Mac mini", deviceKind: nil, isEnabled: false, pairedAt: Date()),
            "FOH Mac mini": PairedDevice(deviceId: "FOH Mac mini", deviceName: "FOH Mac mini", deviceKind: nil, isEnabled: true, pairedAt: Date())
        ]
        let updated = DevicePairingStore.migratingLegacyNameKeyedEntry(
            toDeviceId: "UUID-FOH", deviceName: "FOH Mac mini", deviceKind: nil, in: devices
        )
        XCTAssertNil(updated["FOH Mac mini"])
        XCTAssertEqual(DevicePairingStore.status(for: "UUID-FOH", in: updated), .blocked)
    }

    func testMigrationIgnoresEntriesThatAreAlreadyKeyedByDeviceId() {
        let devices = ["UUID-OTHER": PairedDevice(deviceId: "UUID-OTHER", deviceName: "FOH Mac mini", deviceKind: nil, isEnabled: true, pairedAt: Date())]
        let updated = DevicePairingStore.migratingLegacyNameKeyedEntry(
            toDeviceId: "UUID-FOH", deviceName: "FOH Mac mini", deviceKind: nil, in: devices
        )
        XCTAssertEqual(updated, devices)
    }

    func testMigrationIsNoOpWhenDeviceIdEqualsName() {
        let legacy = ["FOH Mac mini": PairedDevice(deviceId: "FOH Mac mini", deviceName: "FOH Mac mini", deviceKind: nil, isEnabled: true, pairedAt: Date())]
        let updated = DevicePairingStore.migratingLegacyNameKeyedEntry(
            toDeviceId: "FOH Mac mini", deviceName: "FOH Mac mini", deviceKind: nil, in: legacy
        )
        XCTAssertEqual(updated, legacy)
    }
}
