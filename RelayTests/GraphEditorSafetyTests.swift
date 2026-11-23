import XCTest
import CoreGraphics
import SwiftUI
@testable import Relay

/// Pure logic behind the Automation editor's link selection, action run status, link
/// rejection messages and console-assignment undo.
@MainActor
final class GraphEditorSafetyTests: XCTestCase {

    // MARK: - Link hit-testing

    func testDistanceIsZeroAtEndpointsAndOnTheCurve() {
        let p0 = CGPoint(x: 0, y: 0)
        let p3 = CGPoint(x: 300, y: 120)

        XCTAssertEqual(GraphLinkGeometry.distance(from: p0, toCurveFrom: p0, to: p3), 0, accuracy: 0.001)
        XCTAssertEqual(GraphLinkGeometry.distance(from: p3, toCurveFrom: p0, to: p3), 0, accuracy: 0.001)

        let mid = GraphLinkGeometry.point(at: 0.5, from: p0, to: p3)
        XCTAssertEqual(GraphLinkGeometry.distance(from: mid, toCurveFrom: p0, to: p3), 0, accuracy: 0.5)
    }

    func testCurveMidpointOfSymmetricLinkIsTheCenter() {
        let mid = GraphLinkGeometry.point(at: 0.5, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 400, y: 200))
        XCTAssertEqual(mid.x, 200, accuracy: 0.001)
        XCTAssertEqual(mid.y, 100, accuracy: 0.001)
    }

    func testDistanceFollowsTheBezierNotTheStraightLine() {
        // A backwards link leaves its output heading right (control points are >= 80pt out),
        // so near the start it bulges away from the straight chord between the ends.
        let p0 = CGPoint(x: 100, y: 0)
        let p3 = CGPoint(x: 0, y: 200)
        let onBulge = GraphLinkGeometry.point(at: 0.15, from: p0, to: p3)
        XCTAssertGreaterThan(onBulge.x, p0.x)
        XCTAssertEqual(GraphLinkGeometry.distance(from: onBulge, toCurveFrom: p0, to: p3), 0, accuracy: 0.5)
        // The chord's point at the same height is well off the drawn curve.
        let onChord = CGPoint(x: p0.x - onBulge.y / 2, y: onBulge.y)
        XCTAssertGreaterThan(GraphLinkGeometry.distance(from: onChord, toCurveFrom: p0, to: p3), 10)
    }

    func testHitTestFindsCurveWithinToleranceOnly() {
        let id = UUID()
        let curve = GraphLinkGeometry.Curve(id: id, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 400, y: 0))
        // A horizontal link is a straight line along y = 0.
        XCTAssertEqual(GraphLinkGeometry.hitTest(CGPoint(x: 200, y: 6), curves: [curve], tolerance: 8), id)
        XCTAssertNil(GraphLinkGeometry.hitTest(CGPoint(x: 200, y: 12), curves: [curve], tolerance: 8))
        XCTAssertNil(GraphLinkGeometry.hitTest(CGPoint(x: 200, y: 6), curves: [], tolerance: 8))
    }

    func testHitTestPicksTheNearestOfOverlappingCurves() {
        let upper = GraphLinkGeometry.Curve(id: UUID(), from: CGPoint(x: 0, y: 0), to: CGPoint(x: 400, y: 0))
        let lower = GraphLinkGeometry.Curve(id: UUID(), from: CGPoint(x: 0, y: 10), to: CGPoint(x: 400, y: 10))
        XCTAssertEqual(GraphLinkGeometry.hitTest(CGPoint(x: 200, y: 7), curves: [upper, lower], tolerance: 8), lower.id)
        XCTAssertEqual(GraphLinkGeometry.hitTest(CGPoint(x: 200, y: 3), curves: [upper, lower], tolerance: 8), upper.id)
    }

    func testCurvesFollowNodeCentersPlusPortOffsets() {
        let a = UUID(), b = UUID(), link = UUID()
        let spec = GraphLinkSpec(
            linkId: link,
            fromNodeId: a,
            fromOffset: CGPoint(x: 215, y: 0),
            toNodeId: b,
            toOffset: CGPoint(x: -195, y: 0),
            isEventFlow: false
        )
        let centers = [a: CGPoint(x: 100, y: 50), b: CGPoint(x: 900, y: 70)]
        let curve = GraphLinkGeometry.curves(for: [spec]) { centers[$0] ?? .zero }[0]
        XCTAssertEqual(curve.id, link)
        XCTAssertEqual(curve.from, CGPoint(x: 315, y: 50))
        XCTAssertEqual(curve.to, CGPoint(x: 705, y: 70))
    }

    func testBezierPathUsesTheSameCurveAsHitTesting() {
        let p0 = CGPoint(x: 10, y: 20)
        let p3 = CGPoint(x: 210, y: 220)
        let bounds = GraphLinksCanvasView.bezierPath(from: p0, to: p3).boundingRect
        let mid = GraphLinkGeometry.point(at: 0.5, from: p0, to: p3)
        XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(mid))
        XCTAssertTrue(GraphLinkGeometry.bounds(from: p0, to: p3).insetBy(dx: -0.5, dy: -0.5).contains(bounds))
    }

    // MARK: - Action run status

    func testHTTPStatusMapping() {
        XCTAssertEqual(GraphActionRunStatus.forHTTPStatus(200), .succeeded("HTTP 200"))
        XCTAssertEqual(GraphActionRunStatus.forHTTPStatus(204), .succeeded("HTTP 204"))
        guard case .failed(let notFound) = GraphActionRunStatus.forHTTPStatus(404) else {
            return XCTFail("404 should fail")
        }
        XCTAssertTrue(notFound.contains("404"))
        XCTAssertTrue(GraphActionRunStatus.forHTTPStatus(500).isFailure)
        XCTAssertTrue(GraphActionRunStatus.forHTTPStatus(0).isFailure)
    }

    func testOSCPreflightNamesTheMissingField() {
        XCTAssertNotNil(GraphActionRunStatus.oscPreflightFailure(host: "", port: 8000, address: "/a"))
        XCTAssertTrue(GraphActionRunStatus.oscPreflightFailure(host: "10.0.0.2", port: 0, address: "/a")?.contains("port") == true)
        XCTAssertTrue(GraphActionRunStatus.oscPreflightFailure(host: "10.0.0.2", port: 8000, address: "")?.contains("address") == true)
        XCTAssertNil(GraphActionRunStatus.oscPreflightFailure(host: "10.0.0.2", port: 8000, address: "/a"))
    }

    func testSendResultsMapToStatus() {
        XCTAssertEqual(GraphActionRunStatus.forOSCSend(handedOff: true, host: "10.0.0.2", port: 8000), .succeeded("Sent to 10.0.0.2:8000"))
        XCTAssertTrue(GraphActionRunStatus.forOSCSend(handedOff: false, host: "10.0.0.2", port: 8000).isFailure)
        XCTAssertEqual(GraphActionRunStatus.forMIDISend(sent: true), .succeeded("Sent"))
        XCTAssertTrue(GraphActionRunStatus.forMIDISend(sent: false).isFailure)
        XCTAssertTrue(GraphActionRunStatus.running.isRunning)
        XCTAssertFalse(GraphActionRunStatus.running.isFailure)
    }

    func testFailureMessageFallsBackWhenErrorHasNoText() {
        struct Blank: LocalizedError { var errorDescription: String? { "  " } }
        XCTAssertEqual(GraphActionRunStatus.failureMessage(for: Blank(), fallback: "Nope"), "Nope")
        struct Real: LocalizedError { var errorDescription: String? { "Timed out" } }
        XCTAssertEqual(GraphActionRunStatus.failureMessage(for: Real(), fallback: "Nope"), "Timed out")
    }

    func testOSCSendWithBlankPortReportsFailureOnTheNode() {
        let nodeID = UUID()
        var graph = DashboardGraph()
        graph.oscSendActionConfigByNodeId[nodeID.uuidString] = .init(
            targetIP: "127.0.0.1",
            targetPort: 0,
            address: "/Cue List"
        )

        let reported = expectation(forNotification: ActionNodeNotifications.runStatusChanged, object: nil) { note in
            guard note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID == nodeID,
                  let status = note.userInfo?[ActionNodeUserInfoKeys.runStatus] as? GraphActionRunStatus else { return false }
            return status.isFailure
        }

        GraphActionExecutor.execute(actionKey: "action.oscSend", nodeId: nodeID, graph: graph, context: nil)

        wait(for: [reported], timeout: 1)
    }

    func testHTTPRequestWithoutURLReportsFailureOnTheNode() {
        let nodeID = UUID()
        var graph = DashboardGraph()
        graph.httpRequestActionConfigByNodeId[nodeID.uuidString] = DashboardGraph.HTTPRequestActionConfig()

        let reported = expectation(forNotification: ActionNodeNotifications.runStatusChanged, object: nil) { note in
            guard note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID == nodeID,
                  case .failed(let message)? = note.userInfo?[ActionNodeUserInfoKeys.runStatus] as? GraphActionRunStatus else { return false }
            return message.contains("URL")
        }

        GraphActionExecutor.execute(actionKey: "action.httpRequest", nodeId: nodeID, graph: graph, context: nil)

        wait(for: [reported], timeout: 1)
    }

    func testShureSendWithoutDeviceReportsFailureOnTheNode() {
        let nodeID = UUID()
        var graph = DashboardGraph()
        graph.shureSendActionConfigByNodeId[nodeID.uuidString] = DashboardGraph.ShureSendActionConfig()

        let reported = expectation(forNotification: ActionNodeNotifications.runStatusChanged, object: nil) { note in
            note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID == nodeID
                && (note.userInfo?[ActionNodeUserInfoKeys.runStatus] as? GraphActionRunStatus)?.isFailure == true
        }

        GraphActionExecutor.execute(actionKey: "action.shureSend", nodeId: nodeID, graph: graph, context: nil)

        wait(for: [reported], timeout: 1)
    }

    // MARK: - Link rejection messages

    func testEveryLinkFailureReasonHasAMessage() {
        let reasons: [GraphLinkFailureReason] = [
            .sameNode, .receiverDoesNotAcceptLinks, .sourceCannotLinkToReceiver,
            .conditionalsDisabled, .variablesDisabled, .consoleCapabilityMismatch
        ]
        for reason in reasons {
            XCTAssertFalse(reason.message(sourceName: "People", receiverName: "FOH Qu").isEmpty, "\(reason)")
        }
        XCTAssertTrue(GraphLinkFailureReason.sourceCannotLinkToReceiver
            .message(sourceName: "Planning Center", receiverName: "OSC Send")
            .contains("Planning Center"))
        XCTAssertTrue(GraphLinkFailureReason.consoleCapabilityMismatch
            .message(sourceName: "People", receiverName: "FOH Qu")
            .contains("FOH Qu"))
    }

    func testPolicyRejectionCarriesAReasonForTheMessage() {
        let validation = GraphLinkPolicy.validate(from: .source, to: .action)
        XCTAssertFalse(validation.isAllowed)
        XCTAssertEqual(validation.failureReason, .sourceCannotLinkToReceiver)
    }

    // MARK: - Undo for state outside the graph

    func testValueUndoRestoresAndRedoReapplies() {
        let proxy = GraphDashboardUndoProxy()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        var stored: [String: Int] = ["Soprano 1 — Ann": 45]
        let apply: ([String: Int]) -> [String: Int] = { value in
            let replaced = stored
            stored = value
            return replaced
        }

        // "Clear": store the new value, register the old one.
        let previous = stored
        stored = [:]
        undoManager.beginUndoGrouping()
        proxy.registerValueUndo(actionName: "Clear Channel Assignments", previous: previous, undoManager: undoManager, apply: apply)
        undoManager.endUndoGrouping()

        XCTAssertEqual(undoManager.undoActionName, "Clear Channel Assignments")
        undoManager.undo()
        XCTAssertEqual(stored, ["Soprano 1 — Ann": 45])
        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        XCTAssertEqual(stored, [:])
        undoManager.undo()
        XCTAssertEqual(stored, ["Soprano 1 — Ann": 45])
    }

    func testPortHitShapeIsLargerThanItsDrawnFrame() {
        let drawn = CGRect(x: 0, y: 0, width: 26, height: 20)
        let hit = GraphPortHitShape().path(in: drawn).boundingRect
        XCTAssertGreaterThanOrEqual(hit.height, 28)
        XCTAssertLessThanOrEqual(hit.height, 34, "stacked ports are 34pt apart")
        XCTAssertGreaterThan(hit.maxX, drawn.maxX, "reaches past the node edge, where the nub is")
        XCTAssertEqual(hit.midY, drawn.midY, accuracy: 0.001)
    }
}
