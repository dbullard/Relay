import Foundation

/// Pure scope logic shared by the resolved editor binding and the scope UI.
/// No SwiftUI, no side effects — directly unit-testable.
enum AutomationScopeResolver {

    /// The graph the editor should display/edit for a tab.
    static func effectiveGraph(tab: DashboardTab, universalGraph: DashboardGraph?) -> DashboardGraph? {
        switch tab.automationMode {
        case .universal: return universalGraph
        case .perTab:    return tab.graph
        }
    }

    /// What should happen when the user switches a currently-private tab to shared.
    enum SwitchToSharedOutcome: Equatable {
        /// No meaningful per-tab content to lose — just switch.
        case switchImmediately
        /// The tab has distinct content; ask the user to promote it or adopt the shared graph.
        /// `hasExistingShared` is true when a non-empty universal graph already exists
        /// (promoting would replace it).
        case confirmPromoteOrAdopt(hasExistingShared: Bool)
    }

    static func switchToShared(tab: DashboardTab, universalGraph: DashboardGraph?) -> SwitchToSharedOutcome {
        guard let tabGraph = tab.graph,
              tabGraph.hasAutomationContent,
              tabGraph.id != universalGraph?.id else {
            return .switchImmediately
        }
        return .confirmPromoteOrAdopt(hasExistingShared: universalGraph?.hasAutomationContent == true)
    }

    /// Whether a source filter (e.g. WordTriggerRule.sourceIds) accepts an event from a given source.
    /// Empty filter means "any source".
    static func sourceMatches(filter: [UUID], eventSourceID: UUID) -> Bool {
        filter.isEmpty || filter.contains(eventSourceID)
    }
}
