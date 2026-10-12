//
//  RelayTests.swift
//  RelayTests
//
//  Created by David Bullard on 5/11/26.
//

import XCTest
@testable import Relay

@MainActor
final class RelayTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testDashboardGraphConsoleDeviceIdByNodeIdRoundtrip() throws {
        let nodeId = UUID()
        let deviceId = UUID()
        var graph = DashboardGraph()
        graph.consoleDeviceIdByNodeId[nodeId.uuidString] = deviceId

        let encoded = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(DashboardGraph.self, from: encoded)

        XCTAssertEqual(decoded.consoleDeviceIdByNodeId[nodeId.uuidString], deviceId)
    }

    func testDashboardGraphConsoleDeviceIdByNodeIdDefaultsToEmpty() throws {
        // Simulate an old save that lacks the key by encoding a graph, then stripping the key
        let graph = DashboardGraph()
        let encoded = try JSONEncoder().encode(graph)
        var dict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        dict.removeValue(forKey: "consoleDeviceIdByNodeId")
        let oldSaveData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(DashboardGraph.self, from: oldSaveData)
        XCTAssertTrue(decoded.consoleDeviceIdByNodeId.isEmpty)
    }

    func testCanManageSnapshotsIsTrueForDigiCo() {
        XCTAssertTrue(AudioConsoleModel.digico.capabilities.canManageSnapshots)
    }

    func testCanManageSnapshotsIsTrueForX32() {
        XCTAssertTrue(AudioConsoleModel.behringerX32.capabilities.canManageSnapshots)
        XCTAssertTrue(AudioConsoleModel.midasM32.capabilities.canManageSnapshots)
    }

    func testCanManageSnapshotsIsFalseForQu() {
        XCTAssertFalse(AudioConsoleModel.allenHeathQu.capabilities.canManageSnapshots)
    }

    func testCanManageSnapshotsIsFalseForDlive() {
        XCTAssertFalse(AudioConsoleModel.allenHeathDlive.capabilities.canManageSnapshots)
    }

    func testCanManageSnapshotsIsFalseForYamahaCLQL() {
        XCTAssertFalse(AudioConsoleModel.yamahaClQl.capabilities.canManageSnapshots)
    }

    func testChannelNameChangeUnsupportedForQu() {
        XCTAssertEqual(AudioConsoleModel.allenHeathQu.capabilities.channelNameChange, .unsupported)
    }

    func testChannelNameChangeSupportedForDlive() {
        XCTAssertEqual(AudioConsoleModel.allenHeathDlive.capabilities.channelNameChange, .supported)
    }

    func testStandardActionsSupportedForX32() {
        XCTAssertEqual(AudioConsoleModel.behringerX32.capabilities.channelMute, .supported)
        XCTAssertEqual(AudioConsoleModel.behringerX32.capabilities.channelLevel, .supported)
        XCTAssertEqual(AudioConsoleModel.behringerX32.capabilities.channelPan, .supported)
    }

    func testStandardActionsSupportedForYamahaDm7AndRivage() {
        XCTAssertEqual(AudioConsoleModel.yamahaDm7.capabilities.channelMute, .supported)
        XCTAssertEqual(AudioConsoleModel.yamahaRivage.capabilities.channelLevel, .supported)
        XCTAssertEqual(AudioConsoleModel.yamahaDm7.capabilities.channelPan, .supported)
    }

    func testStandardActionsUnsupportedForDigiCoAndQu() {
        XCTAssertEqual(AudioConsoleModel.digico.capabilities.channelMute, .unsupported)
        XCTAssertEqual(AudioConsoleModel.allenHeathQu.capabilities.channelLevel, .unsupported)
    }

    func testStandardActionsUnsupportedForYamahaClQlAndAllenHeath() {
        // Phase 2 will flip these to .supported once dLive/Avantis/SQ adapters exist.
        XCTAssertEqual(AudioConsoleModel.yamahaClQl.capabilities.channelMute, .unsupported)
        XCTAssertEqual(AudioConsoleModel.allenHeathDlive.capabilities.channelPan, .unsupported)
        XCTAssertEqual(AudioConsoleModel.allenHeathSq.capabilities.channelLevel, .unsupported)
    }

    func testAudioConsoleModelFromIdentifierResolvesBehringerWing() {
        XCTAssertEqual(AudioConsoleModel.from(identifier: "Behringer_Wing"), .behringerWing)
    }

    func testStandardActionsSupportedForBehringerWing() {
        XCTAssertEqual(AudioConsoleModel.behringerWing.capabilities.channelMute, .supported)
        XCTAssertEqual(AudioConsoleModel.behringerWing.capabilities.channelLevel, .supported)
        XCTAssertEqual(AudioConsoleModel.behringerWing.capabilities.channelPan, .supported)
        XCTAssertEqual(AudioConsoleModel.behringerWing.capabilities.sceneRecall, .supported)
    }

    func testBehringerWingIsBetaOrDebugOnly() {
        XCTAssertTrue(AudioConsoleModel.betaOrDebugOnlyModels.contains(.behringerWing))
        XCTAssertFalse(AudioConsoleModel.debugOnlyModels.contains(.behringerWing))
    }

    func testAudioConsoleModelFromIdentifierResolvesAvidVenueS6L() {
        XCTAssertEqual(AudioConsoleModel.from(identifier: "Avid_VenueS6L"), .avidVenueS6L)
    }

    func testStandardActionsSupportedForAvidVenueS6L() {
        XCTAssertEqual(AudioConsoleModel.avidVenueS6L.capabilities.channelMute, .supported)
        XCTAssertEqual(AudioConsoleModel.avidVenueS6L.capabilities.channelLevel, .supported)
        XCTAssertEqual(AudioConsoleModel.avidVenueS6L.capabilities.channelPan, .supported)
        XCTAssertEqual(AudioConsoleModel.avidVenueS6L.capabilities.sceneRecall, .supported)
    }

    func testAvidVenueS6LIsBetaOrDebugOnly() {
        XCTAssertTrue(AudioConsoleModel.betaOrDebugOnlyModels.contains(.avidVenueS6L))
        XCTAssertFalse(AudioConsoleModel.debugOnlyModels.contains(.avidVenueS6L))
    }

    func testConsoleTriggerSendConfigRoundtrip() throws {
        let nodeId = UUID()
        let triggerA = UUID()
        let triggerB = UUID()
        var graph = DashboardGraph()
        graph.consoleTriggerSendConfigByNodeId[nodeId.uuidString] = DashboardGraph.ConsoleTriggerSendConfig(
            assignmentsTriggerNodeId: triggerA,
            snapshotsTriggerNodeId: triggerB
        )

        let encoded = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(DashboardGraph.self, from: encoded)

        let config = decoded.consoleTriggerSendConfigByNodeId[nodeId.uuidString]
        XCTAssertEqual(config?.assignmentsTriggerNodeId, triggerA)
        XCTAssertEqual(config?.snapshotsTriggerNodeId, triggerB)
    }

    func testExternalDeviceConfigVenueFieldsRoundtrip() throws {
        var config = ExternalDeviceConfig(
            name: "S6L Test",
            kind: .audioConsole,
            host: "192.168.1.50",
            port: 8000,
            consoleModelIdentifier: AudioConsoleModel.avidVenueS6L.rawValue
        )
        config.venueTransportMode = .tcp
        config.venueMuteAddressTemplate = "/relay/ch/{channel}/mute"
        config.venueLevelAddressTemplate = "/relay/ch/{channel}/level"
        config.venuePanAddressTemplate = "/relay/ch/{channel}/pan"
        config.venueSceneRecallAddressTemplate = "/relay/scene/{scene}/recall"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ExternalDeviceConfig.self, from: data)

        XCTAssertEqual(decoded.venueTransportMode, .tcp)
        XCTAssertEqual(decoded.venueMuteAddressTemplate, "/relay/ch/{channel}/mute")
        XCTAssertEqual(decoded.venueLevelAddressTemplate, "/relay/ch/{channel}/level")
        XCTAssertEqual(decoded.venuePanAddressTemplate, "/relay/ch/{channel}/pan")
        XCTAssertEqual(decoded.venueSceneRecallAddressTemplate, "/relay/scene/{scene}/recall")
    }

    func testConsoleTriggerSendConfigDefaultsToEmpty() throws {
        let graph = DashboardGraph()
        let encoded = try JSONEncoder().encode(graph)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "consoleTriggerSendConfigByNodeId")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(DashboardGraph.self, from: stripped)
        XCTAssertTrue(decoded.consoleTriggerSendConfigByNodeId.isEmpty)
    }

    func testStandardConsoleActionsRoundtrip() throws {
        let nodeId = UUID()
        var graph = DashboardGraph()
        let action = DashboardGraph.StandardConsoleAction(
            kind: .level,
            channelIndex: 5,
            levelDb: -6.0
        )
        graph.standardConsoleActionsByNodeId[nodeId.uuidString] = [action]

        let encoded = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(DashboardGraph.self, from: encoded)

        let actions = decoded.standardConsoleActionsByNodeId[nodeId.uuidString]
        XCTAssertEqual(actions?.count, 1)
        XCTAssertEqual(actions?.first?.kind, .level)
        XCTAssertEqual(actions?.first?.channelIndex, 5)
        XCTAssertEqual(actions?.first?.levelDb, -6.0)
    }

    func testStandardConsoleActionsDefaultsToEmpty() throws {
        let graph = DashboardGraph()
        let encoded = try JSONEncoder().encode(graph)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "standardConsoleActionsByNodeId")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(DashboardGraph.self, from: stripped)
        XCTAssertTrue(decoded.standardConsoleActionsByNodeId.isEmpty)
    }

    func testStandardConsoleActionDefaults() {
        let action = DashboardGraph.StandardConsoleAction()
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.kind, .sceneRecall)
        XCTAssertEqual(action.channelIndex, 1)
        XCTAssertEqual(action.sceneNumber, "1.00")
        XCTAssertEqual(action.muteMode, .on)
        XCTAssertEqual(action.levelDb, 0.0)
        XCTAssertEqual(action.panValue, 0.0)
    }

    func testX32FaderValueFromDbAnchorPoints() {
        // Anchor points confirmed against Patrick-Gilles Maillot's X32/M32 OSC protocol doc.
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: 0.0), 0.75, accuracy: 0.0001)
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: 3.0), 0.825, accuracy: 0.0001)
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: 10.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: -90.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: -200.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: 200.0), 1.0, accuracy: 0.0001)
    }

    func testX32FaderValueSegmentBoundariesAreContinuous() {
        // Each segment boundary should agree from both sides (no discontinuity).
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: -10.0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: -30.0), 0.25, accuracy: 0.0001)
        XCTAssertEqual(X32OSCClient.faderValue(fromDb: -60.0), 0.0625, accuracy: 0.0001)
    }

    func testX32PanValueFromNormalized() {
        XCTAssertEqual(X32OSCClient.panValue(from: 0.0), 0.5, accuracy: 0.0001)   // center
        XCTAssertEqual(X32OSCClient.panValue(from: -1.0), 0.0, accuracy: 0.0001)  // full left
        XCTAssertEqual(X32OSCClient.panValue(from: 1.0), 1.0, accuracy: 0.0001)   // full right
        XCTAssertEqual(X32OSCClient.panValue(from: -2.0), 0.0, accuracy: 0.0001)  // clamped
        XCTAssertEqual(X32OSCClient.panValue(from: 2.0), 1.0, accuracy: 0.0001)   // clamped
    }

    func testYamahaSceneBankResolvesToSceneAOrBForBothDm7AndRivage() {
        // Confirmed against the official DM7 Series OSC Specifications v1.1.0:
        // the bank parameter is always "scene_a"/"scene_b", never "MIXER:Lib/Scene".
        XCTAssertEqual(
            YamahaConsoleService.resolvedSceneBank(family: .dm7, explicitBank: nil, fallbackBank: nil),
            "scene_a"
        )
        XCTAssertEqual(
            YamahaConsoleService.resolvedSceneBank(family: .rivage, explicitBank: nil, fallbackBank: nil),
            "scene_a"
        )
        XCTAssertEqual(
            YamahaConsoleService.resolvedSceneBank(family: .rivage, explicitBank: "scene_b", fallbackBank: nil),
            "scene_b"
        )
        XCTAssertEqual(
            YamahaConsoleService.resolvedSceneBank(family: .rivage, explicitBank: nil, fallbackBank: "scene_b"),
            "scene_b"
        )
    }

    func testYamahaLevelValueFromDb() {
        // Confirmed against DM7 Series OSC Specifications v1.1.0 Table 1 examples.
        XCTAssertEqual(YamahaConsoleService.levelValue(fromDb: 0.0), 0)
        XCTAssertEqual(YamahaConsoleService.levelValue(fromDb: -20.0), -2000)
        XCTAssertEqual(YamahaConsoleService.levelValue(fromDb: 10.0), 1000)
        XCTAssertEqual(YamahaConsoleService.levelValue(fromDb: -90.0), -32768) // treated as -inf
        XCTAssertEqual(YamahaConsoleService.levelValue(fromDb: -200.0), -32768) // clamped to -inf
        XCTAssertEqual(YamahaConsoleService.levelValue(fromDb: 200.0), 1000) // clamped to max
    }

    func testYamahaPanValueFromNormalized() {
        XCTAssertEqual(YamahaConsoleService.panValue(from: 0.0), 0)    // center
        XCTAssertEqual(YamahaConsoleService.panValue(from: -1.0), -63) // full left
        XCTAssertEqual(YamahaConsoleService.panValue(from: 1.0), 63)   // full right
        XCTAssertEqual(YamahaConsoleService.panValue(from: -2.0), -63) // clamped
        XCTAssertEqual(YamahaConsoleService.panValue(from: 2.0), 63)   // clamped
    }

}
