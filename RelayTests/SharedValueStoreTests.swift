import XCTest
@testable import Relay

final class SharedValueStoreTests: XCTestCase {
    func testGeneratedNameAndTokenAreStable() {
        let value = SharedValue(
            name: "ULXD Rack 1 CH 2 Battery",
            binding: .shure(deviceID: UUID(), channel: 2, field: .batteryPercent)
        )

        XCTAssertEqual(value.name, "ulxd_rack_1_ch_2_battery")
        XCTAssertEqual(value.token, "#{ulxd_rack_1_ch_2_battery}")
    }

    func testLargeNumberDisplayDoesNotOverflowIntegerConversion() {
        let payload = SharedValuePayload.number(1e30)
        XCTAssertFalse(payload.displayValue.isEmpty)
    }

    func testDisconnectedValueRetainsLastKnownDisplayValue() {
        var value = SharedValue(name: "pastor_battery", binding: .manual)
        value.apply(payload: .number(64), at: Date(timeIntervalSince1970: 1))
        value.markDisconnected()

        XCTAssertEqual(value.payload, .number(64))
        XCTAssertEqual(value.displayValue, "64")
        XCTAssertEqual(value.status, .disconnected)
    }

    func testEquivalentNumberUpdateDoesNotChangeValue() {
        var value = SharedValue(name: "pastor_battery", binding: .manual)
        XCTAssertTrue(value.apply(payload: .number(64), at: Date(timeIntervalSince1970: 1)))
        XCTAssertTrue(value.apply(payload: .number(64.0), at: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(value.lastUpdatedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(value.payload, .number(64))
    }

    func testSameValueRestoresLiveStatusAfterDisconnect() {
        var value = SharedValue(name: "pastor_battery", binding: .manual)
        value.apply(payload: .number(64), at: Date(timeIntervalSince1970: 1))
        value.markDisconnected()
        XCTAssertTrue(value.apply(payload: .number(64), at: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(value.status, .live)
    }

    func testManualValueCanBeSetButSourceBoundValueCannot() async throws {
        let registry = SharedValueRegistry(storage: InMemorySharedValueStorage())
        let manual = try await registry.create(name: "event_name", binding: .manual)
        let wireless = try await registry.create(name: "battery", binding: .shure(deviceID: UUID(), channel: 1, field: .batteryPercent))

        let manualChanged = await registry.setManualValue(id: manual.id, payload: .text("Sunday Service"))
        let updatedManual = await registry.value(id: manual.id)
        let wirelessChanged = await registry.setManualValue(id: wireless.id, payload: .text("wrong"))
        XCTAssertTrue(manualChanged)
        XCTAssertEqual(updatedManual?.payload, .text("Sunday Service"))
        XCTAssertFalse(wirelessChanged)
    }

    func testNewValueIsNeverReceived() {
        let value = SharedValue(name: "new_battery", binding: .manual)

        XCTAssertNil(value.payload)
        XCTAssertEqual(value.status, .neverReceived)
    }

    func testRegistryRejectsDuplicateNormalizedName() async throws {
        let registry = SharedValueRegistry(storage: InMemorySharedValueStorage())
        _ = try await registry.create(name: "Pastor Battery", binding: .manual)

        do {
            _ = try await registry.create(name: "pastor_battery", binding: .manual)
            XCTFail("Expected duplicate name validation to fail")
        } catch let error as SharedValueValidationError {
            XCTAssertEqual(error, .duplicateName("pastor_battery"))
        }
    }

    func testRegistryPersistsLastKnownDisconnectedValue() async throws {
        let storage = InMemorySharedValueStorage()
        let registry = SharedValueRegistry(storage: storage)
        let value = try await registry.create(name: "pastor_battery", binding: .manual)
        _ = await registry.update(id: value.id, payload: .number(64), at: Date(timeIntervalSince1970: 1))
        await registry.markDisconnected(binding: .manual)
        await registry.persistNow()

        let restored = SharedValueRegistry(storage: storage)
        await restored.load()
        let loaded = await restored.value(named: "pastor_battery")
        XCTAssertEqual(loaded?.payload, .number(64))
        XCTAssertEqual(loaded?.status, .disconnected)
    }

    func testRegistrySnapshotExposesExplicitBindingsOnly() async throws {
        let registry = SharedValueRegistry(storage: InMemorySharedValueStorage())
        _ = try await registry.create(name: "pastor_battery", binding: .shure(deviceID: UUID(), channel: 2, field: .batteryPercent))

        let snapshot = await registry.snapshot()
        let bindings = await registry.bindings()
        XCTAssertEqual(snapshot.values.count, 1)
        XCTAssertEqual(bindings.count, 1)
    }

    func testOSCValueBecomesStaleAfterNoPackets() async throws {
        let registry = SharedValueRegistry(storage: InMemorySharedValueStorage())
        let value = try await registry.create(name: "cue", binding: .osc(address: "/cue", payloadType: .text))
        _ = await registry.update(id: value.id, payload: .text("Opening"), at: Date(timeIntervalSince1970: 1))
        let changed = await registry.markStaleOSCValues(now: Date(timeIntervalSince1970: 32), timeout: 30)
        let stale = await registry.value(id: value.id)
        XCTAssertTrue(changed)
        XCTAssertEqual(stale?.status, .stale)
        XCTAssertEqual(stale?.payload, .text("Opening"))
    }

    func testRestoredSourceValueStartsStaleUntilNewReceipt() async throws {
        let storage = InMemorySharedValueStorage()
        let original = SharedValueRegistry(storage: storage)
        let value = try await original.create(name: "cue", binding: .osc(address: "/cue", payloadType: .text))
        _ = await original.update(id: value.id, payload: .text("Opening"))
        await original.persistNow()

        let restored = SharedValueRegistry(storage: storage)
        await restored.load()
        let loaded = await restored.value(id: value.id)
        XCTAssertEqual(loaded?.status, .stale)
    }

    func testPinningSameSourceTwiceDoesNotCreateDuplicateVariables() async {
        let registry = SharedValueRegistry(storage: InMemorySharedValueStorage())
        let binding = SharedValueBinding.osc(address: "/mic/battery", payloadType: .number)
        let first = await registry.createSuggested(baseName: "mic_battery", binding: binding)
        let second = await registry.createSuggested(baseName: "mic_battery", binding: binding)
        let snapshot = await registry.snapshot()
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(snapshot.values.count, 1)
    }

    @MainActor
    func testReopeningVariablesDoesNotReplaceNewerInMemoryValue() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        await store.load()
        let value = try await store.create(name: "cue", binding: .osc(address: "/cue", payloadType: .text))
        _ = await store.update(id: value.id, payload: .text("Opening"))

        await store.load()

        XCTAssertEqual(store.snapshot.values.first?.payload, .text("Opening"))
    }
}

final class FileSharedValueStorageTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSharedValueStorageTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "FileSharedValueStorageTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var fileURL: URL { directory.appendingPathComponent("SharedValues.json") }

    func testSaveThenLoadRoundTrips() async {
        let storage = FileSharedValueStorage(fileURL: fileURL, defaults: defaults)
        await storage.save(Data("one".utf8))
        let reloaded = FileSharedValueStorage(fileURL: fileURL, defaults: defaults)
        let loaded = await reloaded.load()
        XCTAssertEqual(loaded, Data("one".utf8))
    }

    func testLegacyDefaultsValueIsMovedIntoTheFile() async {
        defaults.set(Data("legacy".utf8), forKey: FileSharedValueStorage.legacyDefaultsKey)
        let storage = FileSharedValueStorage(fileURL: fileURL, defaults: defaults)

        let loaded = await storage.load()

        XCTAssertEqual(loaded, Data("legacy".utf8))
        XCTAssertNil(defaults.data(forKey: FileSharedValueStorage.legacyDefaultsKey))
        XCTAssertEqual(try? Data(contentsOf: fileURL), Data("legacy".utf8))
    }

    func testLegacyDefaultsValueWinsOverAnExistingFile() async {
        // An import from the previous Relay writes the legacy key even after the file exists.
        let storage = FileSharedValueStorage(fileURL: fileURL, defaults: defaults)
        await storage.save(Data("file".utf8))
        defaults.set(Data("imported".utf8), forKey: FileSharedValueStorage.legacyDefaultsKey)

        let loaded = await FileSharedValueStorage(fileURL: fileURL, defaults: defaults).load()

        XCTAssertEqual(loaded, Data("imported".utf8))
        XCTAssertEqual(try? Data(contentsOf: fileURL), Data("imported".utf8))
    }

    func testSavingDoesNotWriteUserDefaults() async {
        let storage = FileSharedValueStorage(fileURL: fileURL, defaults: defaults)
        await storage.save(Data("value".utf8))
        XCTAssertNil(defaults.data(forKey: FileSharedValueStorage.legacyDefaultsKey))
    }
}
