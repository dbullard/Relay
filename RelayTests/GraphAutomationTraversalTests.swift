import XCTest
@testable import Relay

final class GraphAutomationTraversalTests: XCTestCase {
    func testResolveNodeIdPrefersPersistedReverseIndex() {
        var graph = DashboardGraph()
        let nodeId = UUID()
        let portId = "node:\(UUID().uuidString)"
        graph.nodeIdByPortId[portId] = nodeId

        let resolved = GraphAutomationTraversal.resolveNodeId(fromPortId: portId, graph: graph)

        XCTAssertEqual(resolved, nodeId)
    }

    func testResolveNodeIdParsesNodePrefixWhenNotInReverseIndex() {
        let graph = DashboardGraph()
        let nodeId = UUID()
        let portId = "node:\(nodeId.uuidString)"

        let resolved = GraphAutomationTraversal.resolveNodeId(fromPortId: portId, graph: graph)

        XCTAssertEqual(resolved, nodeId)
    }

    func testResolveNodeIdParsesTilePrefix() {
        let graph = DashboardGraph()
        let nodeId = UUID()
        let portId = "tile:\(nodeId.uuidString)"

        let resolved = GraphAutomationTraversal.resolveNodeId(fromPortId: portId, graph: graph)

        XCTAssertEqual(resolved, nodeId)
    }

    func testResolveNodeIdParsesColonDelimitedUtilityPrefixes() {
        let graph = DashboardGraph()
        let nodeId = UUID()

        for prefix in ["repeater", "condition", "toggle", "sequence", "smartlight", "currentTime"] {
            let portId = "\(prefix):\(nodeId.uuidString):extra"
            let resolved = GraphAutomationTraversal.resolveNodeId(fromPortId: portId, graph: graph)
            XCTAssertEqual(resolved, nodeId, "Failed to resolve prefix \(prefix)")
        }
    }

    func testResolveNodeIdReturnsNilForUnrecognizedPortId() {
        let graph = DashboardGraph()
        let resolved = GraphAutomationTraversal.resolveNodeId(fromPortId: "unknown:format", graph: graph)
        XCTAssertNil(resolved)
    }

    func testDownstreamConnectionsEmptyWhenTriggerHasNoLinks() {
        let graph = DashboardGraph()
        let triggerNodeId = UUID()

        let connections = GraphAutomationTraversal.downstreamConnections(
            graph: graph,
            sourceNodeId: triggerNodeId,
            resolveNodeIdFromPortId: { GraphAutomationTraversal.resolveNodeId(fromPortId: $0, graph: graph) }
        )

        XCTAssertTrue(connections.isEmpty)
    }

    func testDownstreamConnectionsNonEmptyWhenTriggerIsLinked() {
        var graph = DashboardGraph()
        let triggerNodeId = UUID()
        let actionNodeId = UUID()
        graph.moduleGroupNodeInstances.append(
            DashboardGraph.ModuleGroupNodeInstance(id: actionNodeId, groupKey: "action.oscSend")
        )
        graph.links.append(
            GraphLink(
                fromTileId: triggerNodeId,
                fromPortId: "node:\(triggerNodeId.uuidString)",
                toTileId: actionNodeId,
                toPortId: "node:\(actionNodeId.uuidString)",
                kind: .automation
            )
        )

        let connections = GraphAutomationTraversal.downstreamConnections(
            graph: graph,
            sourceNodeId: triggerNodeId,
            resolveNodeIdFromPortId: { GraphAutomationTraversal.resolveNodeId(fromPortId: $0, graph: graph) }
        )

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections.first?.targetNodeId, actionNodeId)
        XCTAssertEqual(connections.first?.targetGroupKey, "action.oscSend")
    }

    func testDownstreamConnectionsIgnoresDisabledLinks() {
        var graph = DashboardGraph()
        let triggerNodeId = UUID()
        let actionNodeId = UUID()
        graph.moduleGroupNodeInstances.append(
            DashboardGraph.ModuleGroupNodeInstance(id: actionNodeId, groupKey: "action.oscSend")
        )
        graph.links.append(
            GraphLink(
                fromTileId: triggerNodeId,
                fromPortId: "node:\(triggerNodeId.uuidString)",
                toTileId: actionNodeId,
                toPortId: "node:\(actionNodeId.uuidString)",
                kind: .automation,
                isEnabled: false
            )
        )

        let connections = GraphAutomationTraversal.downstreamConnections(
            graph: graph,
            sourceNodeId: triggerNodeId,
            resolveNodeIdFromPortId: { GraphAutomationTraversal.resolveNodeId(fromPortId: $0, graph: graph) }
        )

        XCTAssertTrue(connections.isEmpty, "A disabled link should not count as a downstream connection")
    }

    func testDownstreamConnectionsIgnoresIdentityKindLinks() {
        var graph = DashboardGraph()
        let triggerNodeId = UUID()
        let actionNodeId = UUID()
        graph.moduleGroupNodeInstances.append(
            DashboardGraph.ModuleGroupNodeInstance(id: actionNodeId, groupKey: "action.oscSend")
        )
        graph.links.append(
            GraphLink(
                fromTileId: triggerNodeId,
                fromPortId: "node:\(triggerNodeId.uuidString)",
                toTileId: actionNodeId,
                toPortId: "node:\(actionNodeId.uuidString)",
                kind: .identity
            )
        )

        let connections = GraphAutomationTraversal.downstreamConnections(
            graph: graph,
            sourceNodeId: triggerNodeId,
            resolveNodeIdFromPortId: { GraphAutomationTraversal.resolveNodeId(fromPortId: $0, graph: graph) }
        )

        XCTAssertTrue(connections.isEmpty, "An identity-kind link should not count as a downstream connection")
    }
}
