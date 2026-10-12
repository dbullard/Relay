import XCTest
@testable import Relay

@MainActor
final class SmartLightAutomationTests: XCTestCase {
    func testSmartLightColorParsesAndFormatsHex() {
        let color = SmartLightColor.parse("#3366CC")

        XCTAssertNotNil(color)
        XCTAssertEqual(color?.hexString, "#3366CC")
    }

    func testSmartLightActionConfigRoundTripsThroughDashboardGraphCoding() throws {
        let profileID = UUID()
        let config = DashboardGraph.SmartLightActionConfig(
            id: UUID(),
            profileID: profileID,
            providerType: .govee,
            deviceID: "device-123",
            action: SmartLightAction(
                kind: .setColorTemperature,
                colorTemperatureKelvin: 4200
            ),
            brightnessInputOverridesConfig: false,
            colorInputOverridesConfig: true,
            powerInputOverridesConfig: false,
            sceneName: "Warm Evening"
        )

        var graph = DashboardGraph()
        graph.smartLightActionConfigByNodeId["node-1"] = config

        let data = try XCTUnwrap(GraphDashboardPersistenceAdapter.encodeGraph(graph))
        let decoded = try XCTUnwrap(GraphDashboardPersistenceAdapter.decodeGraph(data))
        let decodedConfig = try XCTUnwrap(decoded.smartLightActionConfigByNodeId["node-1"])

        XCTAssertEqual(decodedConfig.profileID, profileID)
        XCTAssertEqual(decodedConfig.providerType, .govee)
        XCTAssertEqual(decodedConfig.deviceID, "device-123")
        XCTAssertEqual(decodedConfig.action.kind, .setColorTemperature)
        XCTAssertEqual(decodedConfig.action.colorTemperatureKelvin, 4200)
        XCTAssertEqual(decodedConfig.sceneName, "Warm Evening")
    }

    func testSmartLightKeychainStoreScopesSecretsByProfileAndKind() {
        let backend = InMemorySmartLightSecretBackend()
        let store = SmartLightKeychainStore(backend: backend)
        let firstProfileID = UUID()
        let secondProfileID = UUID()

        store.saveSecret("hue-key", profileID: firstProfileID, kind: .hueApplicationKey)
        store.saveSecret("govee-key", profileID: firstProfileID, kind: .goveeAPIKey)
        store.saveSecret("other-hue-key", profileID: secondProfileID, kind: .hueApplicationKey)

        XCTAssertEqual(store.loadSecret(profileID: firstProfileID, kind: .hueApplicationKey), "hue-key")
        XCTAssertEqual(store.loadSecret(profileID: firstProfileID, kind: .goveeAPIKey), "govee-key")
        XCTAssertEqual(store.loadSecret(profileID: secondProfileID, kind: .hueApplicationKey), "other-hue-key")

        store.clearSecrets(for: firstProfileID)

        XCTAssertNil(store.loadSecret(profileID: firstProfileID, kind: .hueApplicationKey))
        XCTAssertNil(store.loadSecret(profileID: firstProfileID, kind: .goveeAPIKey))
        XCTAssertEqual(store.loadSecret(profileID: secondProfileID, kind: .hueApplicationKey), "other-hue-key")
    }

    func testSmartLightProviderRegistryReturnsExpectedProviderImplementations() {
        let hueProvider = SmartLightProviderRegistry.makeProvider(
            profile: SmartLightProfile(providerType: .philipsHue)
        )
        let goveeProvider = SmartLightProviderRegistry.makeProvider(
            profile: SmartLightProfile(providerType: .govee)
        )
        let genericProvider = SmartLightProviderRegistry.makeProvider(
            profile: SmartLightProfile(providerType: .genericFuture)
        )

        XCTAssertEqual(hueProvider.providerType, .philipsHue)
        XCTAssertEqual(goveeProvider.providerType, .govee)
        XCTAssertEqual(genericProvider.providerType, .genericFuture)
    }

    func testGoveeDeviceStateDecodesSingleKeyProperties() throws {
        let payload = """
        {
          "data": {
            "device": "08:18:D0:C9:07:EA:6A:2A",
            "model": "H6010",
            "properties": [
              { "online": true },
              { "powerState": "off" },
              { "brightness": 100 },
              { "colorTemInKelvin": 3000 },
              { "colorTem": 3000 }
            ]
          },
          "message": "Success",
          "code": 200
        }
        """

        let response = try JSONDecoder().decode(GoveeDeviceStateResponse.self, from: Data(payload.utf8))
        let state = response.data.toState()

        XCTAssertEqual(state.isReachable, true)
        XCTAssertEqual(state.isOn, false)
        XCTAssertEqual(state.brightnessPercent, 100)
        XCTAssertEqual(state.colorTemperatureKelvin, 3000)
    }

    // Old files have only "deviceID" (no "deviceIDs"). Verify the custom decoder
    // handles missing keys gracefully and effectiveDeviceIDs still works.
    func testSmartLightActionConfigDecodesLegacyDeviceIDWithoutDeviceIDs() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "deviceID": "legacy-device",
          "action": { "kind": "turnOn" }
        }
        """
        let config = try JSONDecoder().decode(DashboardGraph.SmartLightActionConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.deviceID, "legacy-device")
        XCTAssertEqual(config.deviceIDs, [])
        XCTAssertEqual(config.effectiveDeviceIDs, ["legacy-device"])
    }

    func testActionWithResultsCanFeedDownstreamNodes() {
        XCTAssertTrue(
            GraphLinkPolicy.validate(from: .actionWithResults, to: .action).isAllowed
        )
        XCTAssertTrue(
            GraphLinkPolicy.validate(from: .actionWithResults, to: .delay).isAllowed
        )
        XCTAssertTrue(
            GraphLinkPolicy.validate(from: .actionWithResults, to: .variable).isAllowed
        )
    }

    // Regression: trigger → smart light via .automation link must be found by downstreamActionInstances.
    // Root cause was addOrReplaceLink hardcoding kind: .patch; traversal only processes .automation links.
    func testTriggerFiresSmartLightNodeViaAutomationLink() {
        let triggerNodeId = UUID()
        let smartLightNodeId = UUID()

        var graph = DashboardGraph()
        graph.moduleGroupNodeInstances.append(
            DashboardGraph.ModuleGroupNodeInstance(id: smartLightNodeId, groupKey: "action.smartLightControl")
        )
        graph.smartLightActionConfigByNodeId[smartLightNodeId.uuidString] = DashboardGraph.SmartLightActionConfig(
            id: smartLightNodeId,
            profileID: UUID(),
            providerType: .govee,
            deviceID: "device-123",
            action: SmartLightAction(kind: .turnOn)
        )

        let fromPortId = GraphAutomationTraversal.defaultPortId(for: triggerNodeId)
        let toPortId = GraphAutomationTraversal.defaultPortId(for: smartLightNodeId)
        graph.nodeIdByPortId[fromPortId] = triggerNodeId
        graph.nodeIdByPortId[toPortId] = smartLightNodeId

        graph.links.append(GraphLink(
            fromTileId: triggerNodeId,
            fromPortId: fromPortId,
            toTileId: smartLightNodeId,
            toPortId: toPortId,
            kind: .automation,
            isEnabled: true
        ))

        let actions = GraphAutomationTraversal.downstreamActionInstances(
            graph: graph,
            triggerNodeId: triggerNodeId,
            resolveNodeIdFromPortId: { graph.nodeIdByPortId[$0] }
        )

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.nodeId, smartLightNodeId)
        XCTAssertEqual(actions.first?.key, "action.smartLightControl")
    }

    // Existing graphs may have trigger→smart-light links stored as .patch (pre-fix).
    // The traversal now includes .patch links so these graphs work without migration.
    func testTriggerFindsSmartLightNodeViaPatchLinkForBackwardCompat() {
        let triggerNodeId = UUID()
        let smartLightNodeId = UUID()

        var graph = DashboardGraph()
        graph.moduleGroupNodeInstances.append(
            DashboardGraph.ModuleGroupNodeInstance(id: smartLightNodeId, groupKey: "action.smartLightControl")
        )

        let fromPortId = GraphAutomationTraversal.defaultPortId(for: triggerNodeId)
        let toPortId = GraphAutomationTraversal.defaultPortId(for: smartLightNodeId)
        graph.nodeIdByPortId[fromPortId] = triggerNodeId
        graph.nodeIdByPortId[toPortId] = smartLightNodeId

        graph.links.append(GraphLink(
            fromTileId: triggerNodeId,
            fromPortId: fromPortId,
            toTileId: smartLightNodeId,
            toPortId: toPortId,
            kind: .patch,
            isEnabled: true
        ))

        let actions = GraphAutomationTraversal.downstreamActionInstances(
            graph: graph,
            triggerNodeId: triggerNodeId,
            resolveNodeIdFromPortId: { graph.nodeIdByPortId[$0] }
        )

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.nodeId, smartLightNodeId)
    }
}

private final class InMemorySmartLightSecretBackend: SmartLightSecretStoreBackend {
    private var storage: [String: Data] = [:]

    func load(service: String, account: String) -> Data? {
        storage[storageKey(service: service, account: account)]
    }

    func save(service: String, account: String, data: Data) {
        storage[storageKey(service: service, account: account)] = data
    }

    func clear(service: String, account: String) {
        storage.removeValue(forKey: storageKey(service: service, account: account))
    }

    private func storageKey(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}
