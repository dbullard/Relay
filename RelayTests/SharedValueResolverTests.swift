import XCTest
@testable import Relay

@MainActor
final class SharedValueResolverTests: XCTestCase {
    func testAutomationTextInterpolationResolvesRepeatedTokensAtExecution() {
        let rendered = SharedValueTextInterpolation.render("#{clock} / #clock / #{missing}") {
            $0 == "clock" ? "10:30" : nil
        }
        XCTAssertEqual(rendered, "10:30 / 10:30 / ")
    }

    func testAutomationJSONInterpolationEscapesVariableValues() throws {
        let rendered = SharedValueTextInterpolation.renderJSON("{\"name\":\"#{person}\"}") {
            $0 == "person" ? "Sam \"Lead\"" : nil
        }
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: String])
        XCTAssertEqual(decoded["name"], "Sam \"Lead\"")
    }

    func testVariablesWindowSelectionInsertsIntoAutomationTarget() {
        let target = SharedValueBindingInsertionTarget()
        var inserted: String?
        target.onInsert = { token in inserted = token; return true }
        let picker = SharedValuePickerCoordinator.shared
        picker.target = target
        defer { picker.target = nil }

        XCTAssertEqual(picker.insertOrCopy(name: "clock_local_time"), .inserted)
        XCTAssertEqual(inserted, "#{clock_local_time}")
    }

    func testVariableNodeUsesSelectedUniversalValueAndCoercesType() {
        let config = DashboardGraph.VariableNodeConfig(
            valueType: .number, manualNumberValue: 9,
            sharedValueToken: "#{clock_unix_timestamp}", currentNumberValue: 4
        )
        XCTAssertEqual(GraphRuntime.resolvedSharedVariableValue(config) { token in
            XCTAssertEqual(token, "#{clock_unix_timestamp}")
            return "123.8"
        }, "123")
        XCTAssertEqual(GraphRuntime.resolvedSharedVariableValue(config) { _ in nil }, "")
    }

    func testOlderVariableNodeConfigDecodesWithoutUniversalSource() throws {
        let config = DashboardGraph.VariableNodeConfig(name: "legacy", valueType: .text, manualTextValue: "old")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        object.removeValue(forKey: "sharedValueToken")
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(DashboardGraph.VariableNodeConfig.self, from: data).sharedValueToken)
    }

    func testNotifyActionResolvesVariableTextWhenItFires() {
        let nodeID = UUID()
        var graph = DashboardGraph()
        graph.notifyActionConfigByNodeId[nodeID.uuidString] = .init(
            title: "Plan #{plan}", message: "Starts at #{time}"
        )
        var capturedTitle: String?
        var capturedMessage: String?
        let observer = NotificationCenter.default.addObserver(
            forName: ActionNodeNotifications.notify, object: nil, queue: nil
        ) { note in
            capturedTitle = note.userInfo?[ActionNodeUserInfoKeys.title] as? String
            capturedMessage = note.userInfo?[ActionNodeUserInfoKeys.message] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let context = GraphActionExecutor.ExecutionContext(
            consoleExternalDeviceIds: [], renderVariableText: { text in
                SharedValueTextInterpolation.render(text) { ["plan": "Sunday", "time": "10:30"][$0] }
            }
        )
        GraphActionExecutor.execute(actionKey: "action.notify", nodeId: nodeID, graph: graph, context: context)
        XCTAssertEqual(capturedTitle, "Plan Sunday")
        XCTAssertEqual(capturedMessage, "Starts at 10:30")
    }

    func testSetVariableActionDoesNotWriteIntoUniversalSource() {
        let actionID = UUID()
        let variableID = UUID()
        var graph = DashboardGraph()
        graph.variableNodeConfigByNodeId[variableID.uuidString] = .init(
            id: variableID, name: "live_plan", sharedValueToken: "#{planning_center_plan}"
        )
        graph.setVariableActionConfigByNodeId[actionID.uuidString] = .init(targetVariableNodeId: variableID)
        var fired = false
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("Relay.SetVariableActionFired"), object: nil, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(observer) }
        GraphActionExecutor.execute(actionKey: "action.setVariable", nodeId: actionID, graph: graph, context: nil)
        XCTAssertFalse(fired)
    }

    func testBothTokenFormsResolveSharedValue() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        _ = try await store.create(name: "pastor_battery", binding: .manual)
        let value = try XCTUnwrap(store.snapshot.values.first)
        _ = await store.update(id: value.id, payload: .number(64))
        let resolver = SharedValueResolver(store: store)

        XCTAssertEqual(resolver.resolveText(token: "#pastor_battery"), "64")
        XCTAssertEqual(resolver.resolveText(token: "#{pastor_battery}"), "64")
        XCTAssertEqual(resolver.resolveText(token: "#{shared:pastor_battery}"), "64")
    }

    func testNeverReceivedValueDoesNotResolve() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        _ = try await store.create(name: "new_battery", binding: .manual)
        let resolver = SharedValueResolver(store: store)

        XCTAssertNil(resolver.resolveText(token: "#new_battery"))
    }

    func testCompletionCandidateExposesStatusAndSource() async throws {
        let store = SharedValueStore(registry: SharedValueRegistry(storage: InMemorySharedValueStorage()))
        _ = try await store.create(name: "pastor_battery", binding: .manual)
        let resolver = SharedValueResolver(store: store)

        let candidate = try XCTUnwrap(resolver.completionCandidates(query: "pastor").first)
        XCTAssertEqual(candidate.name, "pastor_battery")
        XCTAssertEqual(candidate.status, .neverReceived)
        XCTAssertEqual(candidate.token, "#{pastor_battery}")
    }
}
