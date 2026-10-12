import XCTest
@testable import Relay

@MainActor
final class SharedValueSourceAdapterTests: XCTestCase {
    func testPlanningCenterValuesFromSubscribedTabReportTheirSource() {
        var tab = DashboardTab(name: "Weekend", tiles: [])
        tab.syncGroupID = "group"
        tab.syncOwnerDeviceName = "Sanctuary Mac"
        let value = SharedValue(name: "planning_center_weekend_plan_title",
                                binding: .system(key: "planningcenter:\(tab.id):plan_title"))
        let coordinator = SharedValueSourceCoordinator.shared
        coordinator.updateTabs([tab], disconnectedGroupIDs: [])
        defer { coordinator.updateTabs([], disconnectedGroupIDs: []) }

        XCTAssertEqual(coordinator.syncedTabName(for: value), "Weekend")
        XCTAssertEqual(coordinator.syncedComputerName(for: value), "Sanctuary Mac")
    }

    func testShureBatteryBindingPublishesCachedPercent() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        let deviceID = UUID()
        _ = try await store.create(name: "pastor_battery", binding: .shure(deviceID: deviceID, channel: 2, field: .batteryPercent))
        let adapter = SharedValueWirelessAdapter(
            store: store,
            shureSnapshot: { _, _ in SharedValueWirelessSnapshot(batteryPercent: 64, rf: 3, audio: 0.4, connected: true) },
            sennheiserSnapshot: { _, _ in nil }
        )

        await adapter.refresh()

        XCTAssertEqual(store.snapshot.values.first?.payload, .number(64))
        XCTAssertEqual(store.snapshot.values.first?.status, .live)
    }

    func testNoBindingsDoNotReadWirelessSnapshot() async {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        var readCount = 0
        let adapter = SharedValueWirelessAdapter(
            store: store,
            shureSnapshot: { _, _ in readCount += 1; return nil },
            sennheiserSnapshot: { _, _ in readCount += 1; return nil }
        )

        await adapter.refresh()

        XCTAssertEqual(readCount, 0)
    }

    func testWirelessDisconnectMarksLastValueDisconnected() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        let deviceID = UUID()
        let value = try await store.create(name: "battery", binding: .shure(deviceID: deviceID, channel: 1, field: .batteryPercent))
        var connected = true
        let adapter = SharedValueWirelessAdapter(
            store: store,
            shureSnapshot: { _, _ in SharedValueWirelessSnapshot(batteryPercent: 64, rf: nil, audio: nil, connected: connected) },
            sennheiserSnapshot: { _, _ in nil }
        )
        await adapter.refresh()
        connected = false
        await adapter.refresh()
        XCTAssertEqual(store.snapshot.values.first(where: { $0.id == value.id })?.status, .disconnected)
    }

    func testOSCPinsOnlyItsExactAddressAndPayloadType() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        _ = try await store.create(name: "pastor_battery", binding: .osc(address: "/mic/1/battery", payloadType: .number))
        _ = try await store.create(name: "other", binding: .osc(address: "/mic/2/battery", payloadType: .number))
        let adapter = SharedValueOSCAdapter(store: store)

        await adapter.receive(address: "/mic/1/battery", text: "64", number: 64, boolean: nil)

        XCTAssertEqual(store.snapshot.recentOSCAddresses.first?.address, "/mic/1/battery")
        XCTAssertEqual(store.snapshot.values.first(where: { $0.name == "pastor_battery" })?.payload, .number(64))
        XCTAssertNil(store.snapshot.values.first(where: { $0.name == "other" })?.payload)
    }

    func testTriggerPayloadUpdatesOnlyMatchingPinnedField() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        let triggerID = UUID()
        let textValue = try await store.create(name: "cue_name", binding: .triggerPayload(triggerID: triggerID, field: "text", payloadType: .text))
        let otherValue = try await store.create(name: "other_cue", binding: .triggerPayload(triggerID: UUID(), field: "text", payloadType: .text))
        let adapter = SharedValueTriggerAdapter(store: store)

        await adapter.receive(triggerID: triggerID, text: "Opening", number: nil, boolean: nil)

        XCTAssertEqual(store.snapshot.values.first(where: { $0.id == textValue.id })?.payload, .text("Opening"))
        XCTAssertNil(store.snapshot.values.first(where: { $0.id == otherValue.id })?.payload)
        XCTAssertEqual(store.snapshot.recentTriggerValues.first?.triggerID, triggerID)
    }

    func testTriggerPublishesStructuredData() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        let triggerID = UUID()
        let value = try await store.create(name: "cue_data", binding: .triggerPayload(triggerID: triggerID, field: "data", payloadType: .payload))
        await SharedValueTriggerAdapter(store: store).receive(triggerID: triggerID, text: "Opening", number: 3, boolean: true)
        let resolver = SharedValueResolver(store: store)
        XCTAssertEqual(store.snapshot.values.first(where: { $0.id == value.id })?.status, .live)
        XCTAssertEqual(resolver.resolvePayload(token: "#{cue_data.number}"), .number(3))
        XCTAssertEqual(resolver.resolvePayload(token: "#{cue_data.boolean}"), .boolean(true))
    }
}
