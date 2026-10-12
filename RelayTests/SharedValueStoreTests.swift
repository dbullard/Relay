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
