import XCTest
@testable import Relay

@MainActor
final class LinkedDeviceVariablesTests: XCTestCase {
    func testFreeSnapshotsNeverExportProValues() {
        let values = [
            SharedValue(name: "free_note", binding: .manual, payload: .text("Hi")),
            SharedValue(name: "console_name", binding: .system(key: "console:device:output"), payload: .text("Main")),
            SharedValue(name: "copied_name", binding: .computed(expression: "#{console_name}", payloadType: .text), payload: .text("Main"))
        ]
        XCTAssertEqual(LinkedDeviceVariableSnapshot.outbound(from: values, localTabIDs: [], hasPro: false).map(\.name), ["free_note"])
        let tab = Data("{\"text\":\"#{free_note} #{console_name} #{copied_name}\"}".utf8)
        XCTAssertEqual(SyncedTabVariableSnapshot.referenced(in: tab, values: values, hasPro: false).map(\.name), ["free_note"])
    }

    func testOutboundExcludesSubscribedTabDataAndConnectionState() {
        let local = UUID()
        let remote = UUID()
        let values = [
            SharedValue(name: "manual_note", binding: .manual, payload: .text("Hello"), status: .live),
            SharedValue(name: "local_roster", binding: .system(key: "roster:\(local):row:column"), payload: .text("Local"), status: .live),
            SharedValue(name: "remote_roster", binding: .system(key: "roster:\(remote):row:column"), payload: .text("Remote"), status: .live),
            SharedValue(name: "local_pco", binding: .system(key: "planningcenter:\(local):plan_title"), payload: .text("Local"), status: .live),
            SharedValue(name: "remote_pco", binding: .system(key: "planningcenter:\(remote):plan_title"), payload: .text("Remote"), status: .live),
            SharedValue(name: "remote_connected", binding: .system(key: "computer:group:connected"), payload: .boolean(true), status: .live)
        ]
        let outbound = LinkedDeviceVariableSnapshot.outbound(from: values, localTabIDs: [local])
        XCTAssertEqual(Set(outbound.map(\.name)), ["manual_note", "local_roster", "local_pco"])
    }

    func testSyncedTabOnlyCarriesReferencedValueAndComputedDependency() {
        let values = [
            SharedValue(name: "score", binding: .manual, payload: .number(4), status: .live),
            SharedValue(name: "double_score", binding: .computed(expression: "#{score} * 2", payloadType: .number), payload: .number(8), status: .live),
            SharedValue(name: "private_note", binding: .manual, payload: .text("unrelated"), status: .live)
        ]
        let tab = Data("{\"label\":\"#{shared:double_score}\"}".utf8)
        let outbound = SyncedTabVariableSnapshot.referenced(in: tab, values: values)
        XCTAssertEqual(Set(outbound.map(\.name)), ["score", "double_score"])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: outbound.map { ($0.name, $0.kind) })["score"], .manual)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: outbound.map { ($0.name, $0.kind) })["double_score"], .computed)
    }

    func testWireCategoryIdentifiesSourceWithoutSharingBinding() throws {
        let value = SharedValue(name: "main_output", binding: .system(key: "console:device:output:1:name"), payload: .text("Main"), status: .live)
        let encoded = try JSONEncoder().encode(LinkedDeviceVariable(value))
        let decoded = try JSONDecoder().decode(LinkedDeviceVariable.self, from: encoded)
        XCTAssertEqual(decoded.kind, .consoles)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("console:device"))
    }

    func testOlderWireValueWithoutCategoryStillDecodes() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"score","status":"live"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LinkedDeviceVariable.self, from: json)
        XCTAssertNil(decoded.kind)
    }

    func testLegacyLinkedFeedGroupsBuiltInNamesAndWirelessSiblings() {
        let names = ["clock_local_date", "console_main_input_1_name", "axient_baptism_audio", "axient_baptism_connected", "custom_score"]
        let values = names.map {
            LinkedDeviceVariable(id: UUID(), name: $0, payload: .text("value"), status: .live, updatedAt: nil)
        }
        let store = LinkedDeviceVariableStore()
        store.receive(values, deviceID: "peer", deviceName: "Peer")
        let kinds = Dictionary(uniqueKeysWithValues: store.entries.map { ($0.value.name, $0.value.kind) })
        XCTAssertEqual(kinds["clock_local_date"], .clock)
        XCTAssertEqual(kinds["console_main_input_1_name"], .consoles)
        XCTAssertEqual(kinds["axient_baptism_audio"], .wireless)
        XCTAssertEqual(kinds["axient_baptism_connected"], .wireless)
        XCTAssertEqual(kinds["custom_score"], .other)
    }

    func testLegacySyncedFeedUsesSameCategoriesAndPreservesExplicitMetadata() {
        let values = [
            LinkedDeviceVariable(id: UUID(), name: "roster_team_row_1_name", payload: .text("Sam"), status: .live, updatedAt: nil),
            LinkedDeviceVariable(id: UUID(), name: "clock_custom", payload: .text("Hi"), status: .live, updatedAt: nil, kind: .manual)
        ]
        let store = SyncedTabVariableStore()
        store.receive(values, groupID: "group", tabName: "Tab", deviceName: "Peer")
        let kinds = Dictionary(uniqueKeysWithValues: store.entries.map { ($0.value.name, $0.value.kind) })
        XCTAssertEqual(kinds["roster_team_row_1_name"], .rosters)
        XCTAssertEqual(kinds["clock_custom"], .manual)
    }

    func testTurningOffSharingClearsOnlyDeviceFeed() {
        let device = LinkedDeviceVariableStore()
        let synced = SyncedTabVariableStore()
        let value = LinkedDeviceVariable(id: UUID(), name: "score", payload: .number(4), status: .live, updatedAt: nil)
        device.receive([value], deviceID: "peer", deviceName: "Peer")
        synced.receive([value], groupID: "tab", tabName: "Tab", deviceName: "Peer")
        device.clear(deviceID: "peer")
        XCTAssertTrue(device.entries.isEmpty)
        XCTAssertEqual(synced.entries.count, 1)
    }
}
