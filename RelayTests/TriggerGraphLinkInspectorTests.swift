import XCTest
@testable import Relay

@MainActor
final class TriggerGraphLinkInspectorTests: XCTestCase {

    private var savedDevices: [ExternalDeviceConfig] = []

    override func setUp() {
        super.setUp()
        savedDevices = ExternalDevicesStore.shared.devices
    }

    override func tearDown() {
        ExternalDevicesStore.shared.devices = savedDevices
        super.tearDown()
    }

    /// Mirrors how enableConsoleDestinationNode actually creates a console node: a random
    /// (non-deterministic) node id, recorded in consoleDeviceIdByNodeId. The node's groupKey
    /// here deliberately does NOT contain "console" -- unlike real production nodes (whose
    /// groupKey is always "destination.console") -- so this test can only pass via the
    /// consoleDeviceIdByNodeId dictionary lookup, not via the looksLikeConsoleNodeKey string
    /// fallback that masks the bug in production today.
    func testDirectLinkedConsoleExternalDeviceIdsFindsDeviceViaConsoleDeviceIdByNodeId() {
        let consoleDevice = ExternalDeviceConfig(name: "Test Console", kind: .audioConsole, host: "127.0.0.1", port: 0)
        ExternalDevicesStore.shared.devices = [consoleDevice]

        var graph = DashboardGraph()
        let triggerNodeId = UUID()
        let consoleNodeInstance = DashboardGraph.ModuleGroupNodeInstance(groupKey: "mixerNodeUniqueGroupKey")
        graph.moduleGroupNodeInstances.append(consoleNodeInstance)
        graph.consoleDeviceIdByNodeId[consoleNodeInstance.id.uuidString] = consoleDevice.id

        graph.links.append(
            GraphLink(
                fromTileId: triggerNodeId,
                fromPortId: "node:\(triggerNodeId.uuidString)",
                toTileId: consoleNodeInstance.id,
                toPortId: "node:\(consoleNodeInstance.id.uuidString)",
                kind: .automation
            )
        )

        let result = TriggerGraphLinkInspector.directLinkedConsoleExternalDeviceIds(graph: graph, nodeId: triggerNodeId)

        XCTAssertEqual(result, [consoleDevice.id])
    }

    func testIsDirectlyLinkedToConsoleNodeTrueViaConsoleDeviceIdByNodeId() {
        let consoleDevice = ExternalDeviceConfig(name: "Test Console", kind: .audioConsole, host: "127.0.0.1", port: 0)
        ExternalDevicesStore.shared.devices = [consoleDevice]

        var graph = DashboardGraph()
        let triggerNodeId = UUID()
        let consoleNodeInstance = DashboardGraph.ModuleGroupNodeInstance(groupKey: "mixerNodeUniqueGroupKey")
        graph.moduleGroupNodeInstances.append(consoleNodeInstance)
        graph.consoleDeviceIdByNodeId[consoleNodeInstance.id.uuidString] = consoleDevice.id

        graph.links.append(
            GraphLink(
                fromTileId: triggerNodeId,
                fromPortId: "node:\(triggerNodeId.uuidString)",
                toTileId: consoleNodeInstance.id,
                toPortId: "node:\(consoleNodeInstance.id.uuidString)",
                kind: .automation
            )
        )

        XCTAssertTrue(TriggerGraphLinkInspector.isDirectlyLinkedToConsoleNode(graph: graph, nodeId: triggerNodeId))
    }
}
