import XCTest
@testable import Relay

final class OSCSendValidationTests: XCTestCase {
    func testOSCActionConfigDecodesOldAddressOnlyConfigurationWithNoArguments() throws {
        let data = #"{"id":"00000000-0000-0000-0000-000000000001","targetIP":"10.0.0.2","targetPort":8000,"address":"/cmd"}"#.data(using: .utf8)!

        let config = try JSONDecoder().decode(DashboardGraph.OSCSendActionConfig.self, from: data)

        XCTAssertEqual(config.address, "/cmd")
        XCTAssertTrue(config.arguments.isEmpty)
    }

    func testOSCSendArgumentResolvesEveryPersistedValue() {
        let blob = Data([0xCA, 0xFE]).base64EncodedString()
        let values: [(DashboardGraph.OSCSendActionArgument.Value, OSCValue)] = [
            (.int32(7), .int32(7)),
            (.float32(1.5), .float32(1.5)),
            (.string("Call Plugin 1"), .string("Call Plugin 1")),
            (.blobBase64(blob), .blob(Data([0xCA, 0xFE]))),
            (.true, .bool(true)),
            (.false, .bool(false)),
            (.null, .null),
            (.impulse, .impulse),
            (.timetag(1), .timetag(1))
        ]

        for (value, expected) in values {
            XCTAssertEqual(DashboardGraph.OSCSendActionArgument(value: value).resolvedValue(), expected)
        }
    }

    func testOSCSendArgumentRejectsMalformedBase64Blob() {
        let argument = DashboardGraph.OSCSendActionArgument(value: .blobBase64("not base64!"))

        XCTAssertNil(argument.resolvedValue())
    }

    func testOSCSendPostsGrandMA3CommandArguments() {
        let nodeID = UUID()
        var graph = DashboardGraph()
        graph.oscSendActionConfigByNodeId[nodeID.uuidString] = .init(
            targetIP: "127.0.0.1",
            targetPort: 8000,
            address: "/cmd",
            arguments: [.init(value: .string("Call Plugin 1"))]
        )

        let sent = expectation(forNotification: ActionNodeNotifications.oscSend, object: nil) { notification in
            notification.userInfo?["address"] as? String == "/cmd"
                && notification.userInfo?["arguments"] as? [String] == ["s:\"Call Plugin 1\""]
        }

        GraphActionExecutor.execute(actionKey: "action.oscSend", nodeId: nodeID, graph: graph, context: nil)

        wait(for: [sent], timeout: 1)
    }

    func testOSCSendWithMalformedBlobDoesNotPostSendNotification() {
        let nodeID = UUID()
        var graph = DashboardGraph()
        graph.oscSendActionConfigByNodeId[nodeID.uuidString] = .init(
            targetIP: "127.0.0.1",
            targetPort: 8000,
            address: "/blob",
            arguments: [.init(value: .blobBase64("not base64!"))]
        )

        let sent = expectation(forNotification: ActionNodeNotifications.oscSend, object: nil)
        sent.isInverted = true

        GraphActionExecutor.execute(actionKey: "action.oscSend", nodeId: nodeID, graph: graph, context: nil)

        wait(for: [sent], timeout: 0.1)
    }

    func testNormalizedAddressPreservesWhitespaceEnteredWhileEditing() {
        XCTAssertEqual(
            OSCSendValidation.normalizedAddress("/Cue List "),
            "/Cue List "
        )
    }

    func testOSCSendWithBlankPortDoesNotPostSendNotification() {
        let nodeID = UUID()
        var graph = DashboardGraph()
        graph.oscSendActionConfigByNodeId[nodeID.uuidString] = .init(
            targetIP: "127.0.0.1",
            targetPort: 0,
            address: "/Cue List"
        )

        let unexpectedNotification = expectation(
            forNotification: ActionNodeNotifications.oscSend,
            object: nil
        )
        unexpectedNotification.isInverted = true

        GraphActionExecutor.execute(
            actionKey: "action.oscSend",
            nodeId: nodeID,
            graph: graph,
            context: nil
        )

        wait(for: [unexpectedNotification], timeout: 0.1)
    }
}
