import Foundation

enum GraphDashboardPersistenceAdapter {
    static func encodeGraph(_ graph: DashboardGraph) -> Data? {
        try? JSONEncoder().encode(graph)
    }

    static func decodeGraph(_ data: Data) -> DashboardGraph? {
        try? JSONDecoder().decode(DashboardGraph.self, from: data)
    }

    static func setHasHiddenNodesFlag(_ hasHiddenNodes: Bool) {
        UserDefaults.standard.set(hasHiddenNodes, forKey: "dashboard_has_hidden_nodes")
    }
}
