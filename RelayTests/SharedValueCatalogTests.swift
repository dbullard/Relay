import XCTest
@testable import Relay

@MainActor
final class SharedValueCatalogTests: XCTestCase {
    func testClockAndRosterValuesUseStableKeys() {
        let column = DashboardRosterColumn(title: "Name")
        let row = DashboardRosterRow(values: [column.id.uuidString: "Alex Doe"])
        var tab = DashboardTab(name: "Weekend", tiles: [])
        tab.rosterColumns = [column]
        tab.rosterRows = [row]

        let observations = SharedValueCatalog.observations(
            now: Date(timeIntervalSince1970: 1_700_000_000),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            tabs: [tab]
        )

        XCTAssertEqual(observations.first(where: { $0.key == "clock:unix" })?.payload, .number(1_700_000_000))
        XCTAssertEqual(observations.first(where: { $0.key == "roster:\(tab.id):\(row.id):\(column.id)" })?.payload, .text("Alex Doe"))
    }

    func testClockDateAndTimeUseSelectedFormatsAndTimeZone() {
        let now = Date(timeIntervalSince1970: 0)
        let observations = SharedValueCatalog.observations(
            now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            clockFormats: [
                "clock:date": ClockFormatPreference(pattern: "yyyy/MM/dd"),
                "clock:time": ClockFormatPreference(pattern: "HH:mm", timeZoneIdentifier: "America/Chicago")
            ],
            tabs: []
        )
        XCTAssertEqual(observations.first(where: { $0.key == "clock:date" })?.payload, .text("1970/01/01"))
        XCTAssertEqual(observations.first(where: { $0.key == "clock:time" })?.payload, .text("18:00"))
    }

    func testConfiguredIntegrationEnabledState() {
        var device = ExternalDeviceConfig(name: "Console", kind: .audioConsole, host: "localhost", port: 9000)
        device.isEnabled = false
        let observations = SharedValueCatalog.observations(now: Date(), tabs: [], devices: [device])
        XCTAssertEqual(observations.first(where: { $0.key == "integration:\(device.id):enabled" })?.payload, .boolean(false))
    }

    func testPlanningCenterPlanAndCachedRowsBecomeTabScopedVariables() {
        var tab = DashboardTab(name: "Weekend", tiles: [])
        tab.serviceTypeID = "service-1"
        tab.serviceTypeName = "Worship"
        tab.planID = "plan-2"
        tab.planTitle = "Sunday AM"
        tab.planDateLabel = "Oct 4"
        tab.serviceTimeName = "9:00 AM"
        tab.teamName = "Band"
        tab.pcoSnapshotKey = PCOTileView.makeTabSnapshotKey(serviceTypeID: tab.serviceTypeID, planID: tab.planID, serviceTimeName: tab.serviceTimeName)
        tab.pcoCachedRundownRows = [PCORundownRow(
            id: "item-1", order: 1, title: "Opening Song", keyText: "G", type: "Song",
            lengthText: "4:00", arrangementText: "Acoustic", bpmText: "120", ccliText: "123",
            sequenceText: "V C V", notesText: "Start soft", noteTextsByCategory: [:],
            timeTextsByLabel: ["9:00 AM": "9:05 AM"], isHeader: false
        )]
        tab.pcoCachedTeamAssignments = [PCOTeamAssignmentRow(
            positionName: "Lead Vocal", personName: "Alex", teamName: "Band",
            status: .confirmed, serviceTimeLabels: ["9:00 AM"]
        )]

        let values = SharedValueCatalog.observations(now: Date(), tabs: [tab])
        func payload(_ suffix: String) -> SharedValuePayload? {
            values.first { $0.key == "planningcenter:\(tab.id):\(suffix)" }?.payload
        }
        XCTAssertEqual(payload("service_type_name"), .text("Worship"))
        XCTAssertEqual(payload("plan_title"), .text("Sunday AM"))
        XCTAssertEqual(payload("plan_date"), .text("Oct 4"))
        XCTAssertEqual(payload("service_time"), .text("9:00 AM"))
        XCTAssertEqual(payload("rundown:item-1:title"), .text("Opening Song"))
        XCTAssertEqual(payload("rundown:item-1:key"), .text("G"))
        XCTAssertEqual(payload("rundown:item-1:time"), .text("9:05 AM"))
        XCTAssertTrue(values.contains { $0.key.hasPrefix("planningcenter:\(tab.id):assignment:") && $0.key.hasSuffix(":status") && $0.payload == .text("confirmed") })
        XCTAssertTrue(values.contains { $0.key.hasPrefix("planningcenter:\(tab.id):assignment:") && $0.key.hasSuffix(":person") && $0.payload == .text("Alex") })
    }

    func testPlanningCenterIgnoresCachedRowsFromPreviousSelection() {
        var tab = DashboardTab(name: "Weekend", tiles: [])
        tab.serviceTypeID = "service-1"
        tab.planID = "new-plan"
        tab.pcoSnapshotKey = PCOTileView.makeTabSnapshotKey(serviceTypeID: "service-1", planID: "old-plan", serviceTimeName: nil)
        tab.pcoCachedRundownRows = [PCORundownRow(
            id: "old-item", order: 1, title: "Old Song", keyText: "", type: "", lengthText: "",
            arrangementText: "", bpmText: "", ccliText: "", sequenceText: "", notesText: "",
            noteTextsByCategory: [:], timeTextsByLabel: [:], isHeader: false
        )]
        let values = SharedValueCatalog.observations(now: Date(), tabs: [tab])
        XCTAssertFalse(values.contains { $0.key.contains("rundown:old-item") })
        XCTAssertEqual(values.first { $0.key == "planningcenter:\(tab.id):plan_id" }?.payload, .text("new-plan"))
    }

    func testPlanningCenterOrganizerGroupsRowsAndFiltersByType() {
        let tabID = UUID()
        let values = [
            SharedValue(name: "plan_title", binding: .system(key: "planningcenter:\(tabID):plan_title"), payload: .text("Sunday AM"), status: .live),
            SharedValue(name: "song_title", binding: .system(key: "planningcenter:\(tabID):rundown:item-1:title"), payload: .text("Opening Song"), status: .live),
            SharedValue(name: "song_key", binding: .system(key: "planningcenter:\(tabID):rundown:item-1:key"), payload: .text("G"), status: .live),
            SharedValue(name: "vocal_person", binding: .system(key: "planningcenter:\(tabID):assignment:lead_vocal_alex:1:person"), payload: .text("Alex"), status: .live),
            SharedValue(name: "vocal_position", binding: .system(key: "planningcenter:\(tabID):assignment:lead_vocal_alex:1:position"), payload: .text("Lead Vocal"), status: .live)
        ]
        let all = PlanningCenterVariableOrganizer.organize(values, tabNames: [tabID: "Weekend"], query: "", filter: .all)
        XCTAssertEqual(all.first?.sections.map(\.kind), [.plan, .rundown, .assignments])
        XCTAssertEqual(all.first?.sections.first(where: { $0.kind == .rundown })?.items.first?.title, "Opening Song")
        XCTAssertEqual(all.first?.sections.first(where: { $0.kind == .rundown })?.items.first?.fields.count, 2)
        XCTAssertEqual(all.first?.sections.first(where: { $0.kind == .assignments })?.items.first?.title, "Lead Vocal • Alex")

        let assignments = PlanningCenterVariableOrganizer.organize(values, tabNames: [tabID: "Weekend"], query: "", filter: .assignments)
        XCTAssertEqual(assignments.first?.sections.map(\.kind), [.assignments])
        XCTAssertEqual(assignments.first?.count, 2)
    }

    func testPlanningCenterSearchKeepsRelatedFieldsForMatchingItem() {
        let tabID = UUID()
        let values = [
            SharedValue(name: "song_title", binding: .system(key: "planningcenter:\(tabID):rundown:item-1:title"), payload: .text("Opening Song"), status: .live),
            SharedValue(name: "song_key", binding: .system(key: "planningcenter:\(tabID):rundown:item-1:key"), payload: .text("G"), status: .live),
            SharedValue(name: "closing_title", binding: .system(key: "planningcenter:\(tabID):rundown:item-2:title"), payload: .text("Closing Song"), status: .live)
        ]
        let groups = PlanningCenterVariableOrganizer.organize(values, tabNames: [tabID: "Weekend"], query: "Opening", filter: .all)
        let rundown = groups.first?.sections.first(where: { $0.kind == .rundown })
        XCTAssertEqual(rundown?.items.count, 1)
        XCTAssertEqual(rundown?.items.first?.fields.count, 2)
        XCTAssertEqual(groups.first?.count, 2)
    }

    func testPlanningCenterRundownFollowsServiceOrder() {
        let tabID = UUID()
        let values = [
            SharedValue(name: "closing_title", binding: .system(key: "planningcenter:\(tabID):rundown:item-2:title"), payload: .text("Closing Song"), status: .live),
            SharedValue(name: "closing_order", binding: .system(key: "planningcenter:\(tabID):rundown:item-2:order"), payload: .number(2), status: .live),
            SharedValue(name: "opening_title", binding: .system(key: "planningcenter:\(tabID):rundown:item-1:title"), payload: .text("Opening Song"), status: .live),
            SharedValue(name: "opening_order", binding: .system(key: "planningcenter:\(tabID):rundown:item-1:order"), payload: .number(1), status: .live)
        ]
        let groups = PlanningCenterVariableOrganizer.organize(values, tabNames: [:], query: "", filter: .rundown)
        XCTAssertEqual(groups.first?.sections.first?.items.map(\.title), ["Opening Song", "Closing Song"])
    }

    func testProPresenterAndLinkedComputerStatusAreIncluded() {
        let moduleID = UUID()
        var status = ProPresenterSlideStatus.empty
        status.isConnected = true
        status.presentationName = "Sunday"
        status.slideIndex = 2
        var tab = DashboardTab(name: "Remote", tiles: [])
        tab.syncGroupID = "group-1"

        let observations = SharedValueCatalog.observations(
            now: Date(), tabs: [tab],
            proPresenterStatuses: [moduleID: status],
            disconnectedGroupIDs: ["group-1"]
        )

        XCTAssertEqual(observations.first(where: { $0.key == "propresenter:\(moduleID):slide_number" })?.payload, .number(3))
        XCTAssertEqual(observations.first(where: { $0.key == "computer:group-1:connected" })?.payload, .boolean(false))
    }

    func testComputedValuesSupportMathAndRejectCycles() async throws {
        let registry = SharedValueRegistry(storage: InMemorySharedValueStorage())
        let source = try await registry.create(name: "battery", binding: .manual)
        _ = await registry.setManualValue(id: source.id, payload: .number(50))
        let computed = try await registry.create(name: "battery_double", binding: .computed(expression: "#{battery} * 2", payloadType: .number))
        let cycle = try await registry.create(name: "cycle", binding: .computed(expression: "#{cycle} + 1", payloadType: .number))

        await registry.recomputeComputedValues()

        let computedValue = await registry.value(id: computed.id)
        let cycleValue = await registry.value(id: cycle.id)
        XCTAssertEqual(computedValue?.payload, .number(100))
        XCTAssertNil(cycleValue?.payload)
    }

    func testStructuredPayloadPathResolvesTypedValue() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        let source = try await store.create(name: "event", binding: .manual)
        _ = await store.setManualValue(id: source.id, payload: .payload(#"{"person":{"name":"Alex"},"count":3}"#))
        let resolver = SharedValueResolver(store: store)

        XCTAssertEqual(resolver.resolvePayload(token: "#{shared:event.person.name}"), .text("Alex"))
        XCTAssertEqual(resolver.resolvePayload(token: "#{event.count}"), .number(3))
    }

    func testCatalogKeepsIdentityAndMarksMissingValuesStale() async {
        let registry = SharedValueRegistry(storage: InMemorySharedValueStorage())
        let first = SharedValueCatalogObservation(key: "source:1", name: "source_one", payload: .text("Ready"))
        _ = await registry.syncCatalog([first])
        let original = await registry.value(named: "source_one")
        _ = await registry.syncCatalog([.init(key: "source:1", name: "renamed", payload: .text("Live"))])
        let revised = await registry.value(named: "source_one")
        XCTAssertEqual(original?.id, revised?.id)
        XCTAssertEqual(revised?.payload, .text("Live"))
        _ = await registry.syncCatalog([])
        let missing = await registry.value(named: "source_one")
        XCTAssertEqual(missing?.status, .stale)
    }

    func testComputedTextAndComparison() async throws {
        let registry = SharedValueRegistry(storage: InMemorySharedValueStorage())
        let source = try await registry.create(name: "count", binding: .manual)
        _ = await registry.setManualValue(id: source.id, payload: .number(3))
        let label = try await registry.create(name: "label", binding: .computed(expression: "Count: #{count}", payloadType: .text))
        let comparison = try await registry.create(name: "high", binding: .computed(expression: "#{count} >= 2", payloadType: .boolean))
        await registry.recomputeComputedValues()
        let labelValue = await registry.value(id: label.id)
        let comparisonValue = await registry.value(id: comparison.id)
        XCTAssertEqual(labelValue?.payload, .text("Count: 3"))
        XCTAssertEqual(comparisonValue?.payload, .boolean(true))
    }
}
