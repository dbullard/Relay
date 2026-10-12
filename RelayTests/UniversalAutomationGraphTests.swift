import XCTest
@testable import Relay

final class UniversalAutomationGraphTests: XCTestCase {

    // MARK: - AutomationMode roundtrip

    func testAutomationModeDefaultsToUniversal() throws {
        let tab = DashboardTab(name: "Test", tiles: [])
        XCTAssertEqual(tab.automationMode, .universal)
    }

    func testAutomationModeRoundtripsUniversal() throws {
        var tab = DashboardTab(name: "Test", tiles: [])
        tab.automationMode = .universal
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(DashboardTab.self, from: data)
        XCTAssertEqual(decoded.automationMode, .universal)
    }

    func testAutomationModeDefaultsToPerTabOnMissingKey() throws {
        // Simulate an old file with no automationMode key
        var tab = DashboardTab(name: "Old", tiles: [])
        tab.automationMode = .perTab
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tab)) as! [String: Any]
        json.removeValue(forKey: "automationMode")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(DashboardTab.self, from: data)
        XCTAssertEqual(decoded.automationMode, .perTab)
    }

    // MARK: - Payload universalGraph roundtrip

    func testPayloadUniversalGraphDefaultsToNil() throws {
        let payload = DashboardDocument.Payload(
            version: 5,
            tabs: [],
            rosters: [],
            selectedTabIndex: 0
        )
        XCTAssertNil(payload.universalGraph)
    }

    func testPayloadUniversalGraphRoundtrips() throws {
        var payload = DashboardDocument.Payload(
            version: 5,
            tabs: [],
            rosters: [],
            selectedTabIndex: 0
        )
        payload.universalGraph = DashboardGraph()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(DashboardDocument.Payload.self, from: data)
        XCTAssertNotNil(decoded.universalGraph)
    }

    func testPayloadUniversalGraphNilOnMissingKey() throws {
        var payload = DashboardDocument.Payload(
            version: 5,
            tabs: [],
            rosters: [],
            selectedTabIndex: 0
        )
        payload.universalGraph = nil
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [String: Any]
        json.removeValue(forKey: "universalGraph")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(DashboardDocument.Payload.self, from: data)
        XCTAssertNil(decoded.universalGraph)
    }

    // MARK: - Runtime universal graph substitution

    func testRuntimeUsesUniversalGraphForUniversalTab() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var universalGraph = DashboardGraph()
        universalGraph.name = "universal"

        var tab = DashboardTab(name: "Tab", tiles: [])
        tab.automationMode = .universal
        tab.graph = nil  // no per-tab graph

        runtime.setUniversalGraph(universalGraph)
        let effective = runtime.effectiveGraph(for: tab)
        XCTAssertEqual(effective?.name, "universal")
    }

    func testRuntimeUsesPerTabGraphForPerTabTab() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var universalGraph = DashboardGraph()
        universalGraph.name = "universal"

        var tabGraph = DashboardGraph()
        tabGraph.name = "perTab"

        var tab = DashboardTab(name: "Tab", tiles: [])
        tab.automationMode = .perTab
        tab.graph = tabGraph

        runtime.setUniversalGraph(universalGraph)
        let effective = runtime.effectiveGraph(for: tab)
        XCTAssertEqual(effective?.name, "perTab")
    }

    // MARK: - Console action failure notifications

    func testTestQuConsoleActionsPostsFailedWhenNoActionsConfigured() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let graph = DashboardGraph()
        let nodeId = UUID()

        let expectation = expectation(forNotification: ActionNodeNotifications.consoleActionFailed, object: nil) { note in
            guard let id = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, id == nodeId else { return false }
            return (note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String) == "No Qu actions configured on this node"
        }

        runtime.testQuConsoleActions(graph: graph, consoleNodeId: nodeId)
        wait(for: [expectation], timeout: 2.0)
    }

    func testTestQuConsoleActionsPostsFailedWhenNotLinkedToDevice() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var graph = DashboardGraph()
        let nodeId = UUID()
        graph.quConsoleActionsByNodeId[nodeId.uuidString] = [
            DashboardGraph.QuConsoleAction(kind: .sceneRecall)
        ]

        let expectation = expectation(forNotification: ActionNodeNotifications.consoleActionFailed, object: nil) { note in
            guard let id = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, id == nodeId else { return false }
            return (note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String) == "Not linked to a console device"
        }

        runtime.testQuConsoleActions(graph: graph, consoleNodeId: nodeId)
        wait(for: [expectation], timeout: 2.0)
    }

    func testTestQuConsoleActionsPostsFailedWhenLinkedDeviceMissing() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var graph = DashboardGraph()
        let nodeId = UUID()
        graph.quConsoleActionsByNodeId[nodeId.uuidString] = [
            DashboardGraph.QuConsoleAction(kind: .sceneRecall)
        ]
        graph.consoleDeviceIdByNodeId[nodeId.uuidString] = UUID() // guaranteed not to match a real device

        let expectation = expectation(forNotification: ActionNodeNotifications.consoleActionFailed, object: nil) { note in
            guard let id = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, id == nodeId else { return false }
            return (note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String) == "Linked console device was removed"
        }

        runtime.testQuConsoleActions(graph: graph, consoleNodeId: nodeId)
        wait(for: [expectation], timeout: 2.0)
    }

    func testTestDigiCoConsoleActionsPostsFailedWhenNoActionsConfigured() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let graph = DashboardGraph()
        let nodeId = UUID()

        let expectation = expectation(forNotification: ActionNodeNotifications.consoleActionFailed, object: nil) { note in
            guard let id = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, id == nodeId else { return false }
            return (note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String) == "No DiGiCo actions configured on this node"
        }

        runtime.testDigiCoConsoleActions(graph: graph, consoleNodeId: nodeId)
        wait(for: [expectation], timeout: 2.0)
    }

    func testTestDigiCoConsoleActionsPostsFailedWhenNotLinkedToDevice() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var graph = DashboardGraph()
        let nodeId = UUID()
        graph.digicoConsoleActionsByNodeId[nodeId.uuidString] = [
            DashboardGraph.DiGiCoConsoleAction(kind: .macro, channelIndex: 1)
        ]

        let expectation = expectation(forNotification: ActionNodeNotifications.consoleActionFailed, object: nil) { note in
            guard let id = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, id == nodeId else { return false }
            return (note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String) == "Not linked to a console device"
        }

        runtime.testDigiCoConsoleActions(graph: graph, consoleNodeId: nodeId)
        wait(for: [expectation], timeout: 2.0)
    }

    func testTestDigiCoConsoleActionsPostsFailedWhenLinkedDeviceMissing() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var graph = DashboardGraph()
        let nodeId = UUID()
        graph.digicoConsoleActionsByNodeId[nodeId.uuidString] = [
            DashboardGraph.DiGiCoConsoleAction(kind: .macro, channelIndex: 1)
        ]
        graph.consoleDeviceIdByNodeId[nodeId.uuidString] = UUID() // guaranteed not to match a real device

        let expectation = expectation(forNotification: ActionNodeNotifications.consoleActionFailed, object: nil) { note in
            guard let id = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, id == nodeId else { return false }
            return (note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String) == "Linked console device was removed"
        }

        runtime.testDigiCoConsoleActions(graph: graph, consoleNodeId: nodeId)
        wait(for: [expectation], timeout: 2.0)
    }

    func testProPresenterTriggerMatchesWhenEventAndProfileAndFilterAllMatch() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var cfg = DashboardGraph.ProPresenterTriggerConfig()
        cfg.event = .messageChanged
        cfg.filter = "Running Long"
        let profileId = UUID()

        let matched = runtime.proPresenterTriggerShouldFire(
            cfg: cfg,
            cfgResolvedProfileId: profileId,
            notificationResolvedProfileId: profileId,
            notificationEvent: .messageChanged,
            notificationValue: "Running Long"
        )

        XCTAssertTrue(matched)
    }

    func testProPresenterTriggerDoesNotMatchDifferentEvent() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var cfg = DashboardGraph.ProPresenterTriggerConfig()
        cfg.event = .slideChanged
        let profileId = UUID()

        let matched = runtime.proPresenterTriggerShouldFire(
            cfg: cfg,
            cfgResolvedProfileId: profileId,
            notificationResolvedProfileId: profileId,
            notificationEvent: .presentationChanged,
            notificationValue: "Announcements"
        )

        XCTAssertFalse(matched)
    }

    func testProPresenterTriggerDoesNotMatchDifferentProfile() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var cfg = DashboardGraph.ProPresenterTriggerConfig()
        cfg.event = .slideChanged

        let matched = runtime.proPresenterTriggerShouldFire(
            cfg: cfg,
            cfgResolvedProfileId: UUID(),
            notificationResolvedProfileId: UUID(),
            notificationEvent: .slideChanged,
            notificationValue: "Verse 2"
        )

        XCTAssertFalse(matched)
    }

    func testProPresenterTriggerDoesNotMatchWhenFilterDoesNotMatch() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var cfg = DashboardGraph.ProPresenterTriggerConfig()
        cfg.event = .slideChanged
        cfg.filter = "Closing Slide"
        let profileId = UUID()

        let matched = runtime.proPresenterTriggerShouldFire(
            cfg: cfg,
            cfgResolvedProfileId: profileId,
            notificationResolvedProfileId: profileId,
            notificationEvent: .slideChanged,
            notificationValue: "Verse 2"
        )

        XCTAssertFalse(matched)
    }

    func testProPresenterTriggerMatchesAnyValueWhenFilterIsEmpty() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var cfg = DashboardGraph.ProPresenterTriggerConfig()
        cfg.event = .slideChanged
        cfg.filter = ""
        let profileId = UUID()

        let matched = runtime.proPresenterTriggerShouldFire(
            cfg: cfg,
            cfgResolvedProfileId: profileId,
            notificationResolvedProfileId: profileId,
            notificationEvent: .slideChanged,
            notificationValue: "Whatever Slide"
        )

        XCTAssertTrue(matched)
    }

    func testProPresenterTriggerFilterIsCaseInsensitive() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        var cfg = DashboardGraph.ProPresenterTriggerConfig()
        cfg.event = .presentationChanged
        cfg.filter = "announcements"
        let profileId = UUID()

        let matched = runtime.proPresenterTriggerShouldFire(
            cfg: cfg,
            cfgResolvedProfileId: profileId,
            notificationResolvedProfileId: profileId,
            notificationEvent: .presentationChanged,
            notificationValue: "Announcements"
        )

        XCTAssertTrue(matched)
    }
}
