import XCTest
@testable import Relay

final class LinkedComputerPersonVariablesTests: XCTestCase {
    @MainActor
    func testDiscoversOnlySyncedPersonModulesAndKeepsSameNamedSourcesDistinct() {
        let moduleID = UUID()
        let module = DashboardModuleModel(kind: .person(PersonTileModel(name: "Alex Doe", role: "", initials: "AD")), order: 0, id: moduleID)
        let person = PersonTileModel(name: "Alex Doe", role: "", initials: "AD")
        let tile = DashboardTileModel(name: "Alex", kind: .person(person), modules: [module], offset: .zero)
        var linked = DashboardTab(name: "Remote", tiles: [tile])
        linked.syncGroupID = "group-stable"
        linked.syncOwnerDeviceID = "device-host"
        linked.syncOwnerDeviceName = "Lighting Mac"
        var duplicate = DashboardTab(name: "Mirror", tiles: [tile])
        duplicate.syncGroupID = "another-group"
        let local = DashboardTab(name: "Local", tiles: [tile])

        let values = LinkedComputerPersonVariables.discover(in: [linked, duplicate, local])
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(Set(values.map(\.variableName)).count, 2)
        XCTAssertTrue(values.allSatisfy { $0.variableName.hasPrefix("person_alex_doe_") })
        XCTAssertEqual(values.first(where: { $0.sourceComputerName == "Lighting Mac" })?.sourceID,
                       "linked-person:group-stable:\(moduleID.uuidString)")
        XCTAssertEqual(values, LinkedComputerPersonVariables.discover(in: [linked, duplicate, local]))

        LinkedComputerPersonVariableStore.shared.update(tabs: [linked, duplicate, local])
        for value in values {
            XCTAssertEqual(GraphRuntime.resolveTextInterpolationToken("person:\(value.variableName)", tab: linked), "Alex Doe")
        }

        let disconnected = LinkedComputerPersonVariables.discover(in: [linked], disconnectedGroupIDs: ["group-stable"])
        XCTAssertTrue(disconnected[0].isDisconnected)
        XCTAssertTrue(disconnected[0].availabilityDescription.hasPrefix("Disconnected"))
    }

    func testUsesDiscoveredComputerNameWhenLegacyTabHasNoPersistedName() {
        let module = DashboardModuleModel(kind: .person(PersonTileModel(name: "Taylor", role: "", initials: "T")), order: 0)
        let person = PersonTileModel(name: "Taylor", role: "", initials: "T")
        let tile = DashboardTileModel(name: "Taylor", kind: .person(person), modules: [module], offset: .zero)
        var tab = DashboardTab(name: "Remote", tiles: [tile])
        tab.syncGroupID = "remote-group"
        tab.syncOwnerDeviceID = "host-id"

        let value = LinkedComputerPersonVariables.discover(
            in: [tab],
            computerNamesByDeviceID: ["host-id": "Stage Booth Mac"]
        ).first

        XCTAssertEqual(value?.sourceComputerName, "Stage Booth Mac")
    }

    @MainActor
    func testLinkedPersonVariableResolvesByStableVariableName() {
        let module = DashboardModuleModel(kind: .person(PersonTileModel(name: "Sam Rivera", role: "", initials: "SR")), order: 0)
        let person = PersonTileModel(name: "Sam Rivera", role: "", initials: "SR")
        let tile = DashboardTileModel(name: "Sam", kind: .person(person), modules: [module], offset: .zero)
        var tab = DashboardTab(name: "Remote", tiles: [tile])
        tab.syncGroupID = "remote-group"
        let store = LinkedComputerPersonVariableStore.shared
        store.update(tabs: [tab])
        XCTAssertEqual(store.value(named: "#{person_sam_rivera}"), "Sam Rivera")
        XCTAssertEqual(GraphRuntime.resolveTextInterpolationToken("person_sam_rivera", tab: tab), "Sam Rivera")
    }
}
