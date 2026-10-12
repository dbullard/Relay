import XCTest
@testable import Relay

final class ConditionEvaluationMismatchTests: XCTestCase {

    func testPostConsoleActionFailedIncludesNodeIdAndMessage() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let nodeId = UUID()

        let expectation = expectation(forNotification: ActionNodeNotifications.consoleActionFailed, object: nil) { note in
            guard let id = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, id == nodeId else { return false }
            guard let message = note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String else { return false }
            return message == "Linked console device was removed"
        }

        runtime.postConsoleActionFailed(nodeId: nodeId, message: "Linked console device was removed")
        wait(for: [expectation], timeout: 1.0)
    }

    func testPostConsoleActionSucceededIncludesNodeId() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let nodeId = UUID()

        let expectation = expectation(forNotification: ActionNodeNotifications.consoleActionSucceeded, object: nil) { note in
            (note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID) == nodeId
        }

        runtime.postConsoleActionSucceeded(nodeId: nodeId)
        wait(for: [expectation], timeout: 1.0)
    }

    func testPostConditionEvaluationMismatchIncludesNodeIdAndMessage() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let nodeId = UUID()

        let expectation = expectation(forNotification: ActionNodeNotifications.conditionEvaluationMismatch, object: nil) { note in
            guard let id = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, id == nodeId else { return false }
            guard let message = note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String else { return false }
            return message == "'Greater Than' doesn't apply to text values"
        }

        runtime.postConditionEvaluationMismatch(nodeId: nodeId, message: "'Greater Than' doesn't apply to text values")
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - evaluateConditionText

    func testEvaluateConditionTextReturnsNilForNumericOperator() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let config = DashboardGraph.ConditionNodeConfig(sourceKind: .payloadText, operator: .greaterThan)
        XCTAssertNil(runtime.evaluateConditionText("hello", config: config))
    }

    func testEvaluateConditionTextReturnsResultForValidOperator() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let config = DashboardGraph.ConditionNodeConfig(sourceKind: .payloadText, operator: .equals, comparisonText: "hello")
        XCTAssertEqual(runtime.evaluateConditionText("hello", config: config), true)
    }

    // MARK: - evaluateConditionNumber

    func testEvaluateConditionNumberReturnsNilForTextOperator() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let config = DashboardGraph.ConditionNodeConfig(sourceKind: .payloadNumber, operator: .contains)
        XCTAssertNil(runtime.evaluateConditionNumber(5, config: config))
    }

    func testEvaluateConditionNumberReturnsResultForValidOperator() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let config = DashboardGraph.ConditionNodeConfig(sourceKind: .payloadNumber, operator: .greaterThan, comparisonNumber: 3)
        XCTAssertEqual(runtime.evaluateConditionNumber(5, config: config), true)
    }

    // MARK: - evaluateConditionBoolean

    func testEvaluateConditionBooleanReturnsNilForNumericOperator() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let config = DashboardGraph.ConditionNodeConfig(sourceKind: .payloadBoolean, operator: .greaterThan)
        XCTAssertNil(runtime.evaluateConditionBoolean(true, config: config))
    }

    func testEvaluateConditionBooleanReturnsResultForValidOperator() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let config = DashboardGraph.ConditionNodeConfig(sourceKind: .payloadBoolean, operator: .isTrue)
        XCTAssertEqual(runtime.evaluateConditionBoolean(true, config: config), true)
    }

    @MainActor
    func testVariableConditionUsesLinkedInputInsteadOfStoredValue() {
        let runtime = GraphAutomationRuntime.makeForTesting()
        let sourceID = UUID()
        let variableID = UUID()
        let conditionID = UUID()
        var graph = DashboardGraph()
        graph.moduleGroupNodeInstances = [
            .init(id: sourceID, groupKey: "source.staticLabel"),
            .init(id: variableID, groupKey: "utility.variable")
        ]
        graph.staticLabelSourceConfigByNodeId[sourceID.uuidString] = .init(id: sourceID, label: "true")
        graph.variableNodeConfigByNodeId[variableID.uuidString] = .init(
            id: variableID, name: "is_live", valueType: .boolean,
            manualBooleanValue: false, currentBooleanValue: false
        )
        graph.conditionNodeConfigByNodeId[conditionID.uuidString] = .init(
            id: conditionID, sourceKind: .variable, operator: .isTrue, variableNodeId: variableID
        )
        graph.links.append(GraphLink(
            fromTileId: sourceID, fromPortId: "node:\(sourceID.uuidString)",
            toTileId: variableID, toPortId: "node:\(variableID.uuidString)", kind: .patch
        ))
        var tab = DashboardTab(name: "Test", tiles: [])
        tab.graph = graph

        let result = runtime.evaluateCondition(
            nodeId: conditionID,
            payload: GraphTriggerPayload(sourceNodeId: sourceID),
            graph: &graph,
            tab: tab
        )
        XCTAssertTrue(result)
    }

    @MainActor
    func testSetVariableActionWritesTargetsType() {
        var variable = DashboardGraph.VariableNodeConfig(
            valueType: .boolean, manualBooleanValue: false, currentTextValue: "old"
        )
        let action = DashboardGraph.SetVariableActionConfig(
            valueType: .text, textValue: "unused", booleanValue: true
        )

        GraphRuntime.applySetVariableAction(action, to: &variable)

        XCTAssertEqual(variable.currentBooleanValue, true)
        XCTAssertEqual(variable.currentTextValue, "old")
    }
}
