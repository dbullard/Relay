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

@MainActor
final class SharedValueSnapshotPublishTests: XCTestCase {
    func testTimestampOnlyDifferenceIsDetected() {
        var a = SharedValue(name: "battery", binding: .manual)
        a.apply(payload: .number(64), at: Date(timeIntervalSince1970: 1))
        var b = a
        b.lastUpdatedAt = Date(timeIntervalSince1970: 9)
        var c = a
        c.apply(payload: .number(65), at: Date(timeIntervalSince1970: 9))

        XCTAssertTrue(SharedValueStore.differOnlyInTimestamps(SharedValueSnapshot(values: [a]), SharedValueSnapshot(values: [b])))
        XCTAssertFalse(SharedValueStore.differOnlyInTimestamps(SharedValueSnapshot(values: [a]), SharedValueSnapshot(values: [c])))
        XCTAssertFalse(SharedValueStore.differOnlyInTimestamps(SharedValueSnapshot(values: [a]), SharedValueSnapshot(values: [a, b])))
    }

    func testRepeatedUnchangedValueIsNotRepublishedButNewValueIs() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        let value = try await store.create(name: "battery", binding: .manual)
        _ = await store.update(id: value.id, payload: .number(64), at: Date(timeIntervalSince1970: 100))
        // First timestamp-only refresh may publish; the next one within the interval must not.
        _ = await store.update(id: value.id, payload: .number(64), at: Date(timeIntervalSince1970: 102))
        let afterFirstRefresh = store.snapshot.values.first?.lastUpdatedAt
        _ = await store.update(id: value.id, payload: .number(64), at: Date(timeIntervalSince1970: 104))
        XCTAssertEqual(store.snapshot.values.first?.lastUpdatedAt, afterFirstRefresh)

        _ = await store.update(id: value.id, payload: .number(65), at: Date(timeIntervalSince1970: 105))
        XCTAssertEqual(store.snapshot.values.first?.payload, .number(65))
        XCTAssertEqual(store.snapshot.values.first?.lastUpdatedAt, Date(timeIntervalSince1970: 105))
    }
}

@MainActor
final class SharedValueCellTests: XCTestCase {
    func testValueNamedFollowsPayloadChangesAndAppearsWhenCreated() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        XCTAssertNil(store.value(named: "battery"))

        let value = try await store.create(name: "battery", binding: .manual)
        XCTAssertEqual(store.value(named: "battery")?.id, value.id)

        _ = await store.update(id: value.id, payload: .number(64), at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(store.value(named: "battery")?.payload, .number(64))

        await store.delete(id: value.id)
        XCTAssertNil(store.value(named: "battery"))
    }
}

@MainActor
final class SharedValueObservationScopeTests: XCTestCase {
    private func makeStore() async throws -> (SharedValueStore, SharedValue, SharedValue) {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        let clock = try await store.create(name: "clock_local_time", binding: .manual)
        let weekday = try await store.create(name: "clock_weekday", binding: .manual)
        _ = await store.update(id: clock.id, payload: .text("10:00:00"), at: Date(timeIntervalSince1970: 1))
        _ = await store.update(id: weekday.id, payload: .text("Monday"), at: Date(timeIntervalSince1970: 1))
        return (store, clock, weekday)
    }

    func testReadingOneTokenIsNotNotifiedByOtherValueChanges() async throws {
        let (store, clock, weekday) = try await makeStore()
        let resolver = SharedValueResolver(store: store)

        var notified = false
        withObservationTracking {
            _ = resolver.resolveText(token: "#clock_weekday")
        } onChange: {
            notified = true
        }

        _ = await store.update(id: clock.id, payload: .text("10:00:01"), at: Date(timeIntervalSince1970: 2))
        XCTAssertFalse(notified, "a weekday reader must not re-render when the clock ticks")

        _ = await store.update(id: weekday.id, payload: .text("Tuesday"), at: Date(timeIntervalSince1970: 3))
        XCTAssertTrue(notified, "a weekday reader must update when the weekday changes")
    }
}
