import XCTest
@testable import Relay

final class AutomationScopeResolverTests: XCTestCase {

    private func graph(withContent: Bool) -> DashboardGraph {
        var g = DashboardGraph()
        if withContent {
            g.moduleGroupNodeInstances = [DashboardGraph.ModuleGroupNodeInstance(groupKey: "moduleGroup.person")]
        }
        return g
    }

    func testEffectiveGraphUniversalReturnsUniversal() {
        var tab = DashboardTab(name: "T", tiles: [])
        tab.automationMode = .universal
        tab.graph = graph(withContent: false)
        let uni = graph(withContent: true)
        XCTAssertEqual(AutomationScopeResolver.effectiveGraph(tab: tab, universalGraph: uni)?.id, uni.id)
    }

    func testEffectiveGraphPerTabReturnsTabGraph() {
        var tab = DashboardTab(name: "T", tiles: [])
        tab.automationMode = .perTab
        let tg = graph(withContent: true)
        tab.graph = tg
        let uni = graph(withContent: true)
        XCTAssertEqual(AutomationScopeResolver.effectiveGraph(tab: tab, universalGraph: uni)?.id, tg.id)
    }

    func testSwitchToSharedEmptyTabSwitchesImmediately() {
        var tab = DashboardTab(name: "T", tiles: [])
        tab.automationMode = .perTab
        tab.graph = graph(withContent: false)
        XCTAssertEqual(
            AutomationScopeResolver.switchToShared(tab: tab, universalGraph: nil),
            .switchImmediately
        )
    }

    func testSwitchToSharedTabWithContentNoExistingSharedConfirms() {
        var tab = DashboardTab(name: "T", tiles: [])
        tab.automationMode = .perTab
        tab.graph = graph(withContent: true)
        XCTAssertEqual(
            AutomationScopeResolver.switchToShared(tab: tab, universalGraph: nil),
            .confirmPromoteOrAdopt(hasExistingShared: false)
        )
    }

    func testSwitchToSharedTabWithContentAndExistingSharedFlagsExistingShared() {
        var tab = DashboardTab(name: "T", tiles: [])
        tab.automationMode = .perTab
        tab.graph = graph(withContent: true)
        XCTAssertEqual(
            AutomationScopeResolver.switchToShared(tab: tab, universalGraph: graph(withContent: true)),
            .confirmPromoteOrAdopt(hasExistingShared: true)
        )
    }

    func testSwitchToSharedWhenTabGraphIsSameAsUniversalSwitchesImmediately() {
        let shared = graph(withContent: true)
        var tab = DashboardTab(name: "T", tiles: [])
        tab.automationMode = .perTab
        tab.graph = shared
        XCTAssertEqual(
            AutomationScopeResolver.switchToShared(tab: tab, universalGraph: shared),
            .switchImmediately
        )
    }

    // MARK: - Source Match Tests

    func testEmptySourceIdsMatchesAnySource() {
        XCTAssertTrue(AutomationScopeResolver.sourceMatches(filter: [], eventSourceID: UUID()))
    }

    func testSpecificSourceMatchesWhenContained() {
        let s = UUID()
        XCTAssertTrue(AutomationScopeResolver.sourceMatches(filter: [s], eventSourceID: s))
    }

    func testSpecificSourceRejectsWhenNotContained() {
        XCTAssertFalse(AutomationScopeResolver.sourceMatches(filter: [UUID()], eventSourceID: UUID()))
    }
}
