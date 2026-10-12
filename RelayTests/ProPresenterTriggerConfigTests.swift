import XCTest
@testable import Relay

final class ProPresenterTriggerConfigTests: XCTestCase {
    func testDefaultValues() {
        let cfg = DashboardGraph.ProPresenterTriggerConfig()
        XCTAssertNil(cfg.profileId)
        XCTAssertEqual(cfg.event, .slideChanged)
        XCTAssertEqual(cfg.filter, "")
        XCTAssertEqual(cfg.cooldownSeconds, 0.5)
    }

    func testCodableRoundTrip() throws {
        var cfg = DashboardGraph.ProPresenterTriggerConfig()
        cfg.profileId = UUID()
        cfg.event = .messageChanged
        cfg.filter = "Running Long"
        cfg.cooldownSeconds = 1.5

        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(DashboardGraph.ProPresenterTriggerConfig.self, from: data)

        XCTAssertEqual(decoded, cfg)
    }

    func testGraphRoundTripIncludesProPresenterTriggerConfigByNodeId() throws {
        var graph = DashboardGraph()
        let nodeId = UUID()
        var cfg = DashboardGraph.ProPresenterTriggerConfig()
        cfg.event = .timerChanged
        cfg.filter = "Countdown"
        graph.proPresenterTriggerConfigByNodeId[nodeId.uuidString] = cfg

        let data = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(DashboardGraph.self, from: data)

        XCTAssertEqual(decoded.proPresenterTriggerConfigByNodeId[nodeId.uuidString], cfg)
    }
}
