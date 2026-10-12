import Foundation
import Combine

/// A person name exposed by a synced tab. The source key is based on persisted sync and
/// module identities, never on a peer endpoint or display name (both can change on restart).
struct LinkedComputerPersonVariable: Identifiable, Equatable, Sendable {
    let sourceID: String
    let name: String
    let sourceComputerName: String
    var variableName: String
    let isDisconnected: Bool
    let lastUpdatedAt: Date?
    var id: String { sourceID }

    var availabilityDescription: String {
        let state = isDisconnected ? "Disconnected" : "Available"
        guard let lastUpdatedAt else { return state }
        return "\(state) • Updated \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
    }
}

enum LinkedComputerPersonVariables {
    static func discover(
        in tabs: [DashboardTab],
        disconnectedGroupIDs: Set<String> = [],
        computerNamesByDeviceID: [String: String] = [:]
    ) -> [LinkedComputerPersonVariable] {
        var found: [String: LinkedComputerPersonVariable] = [:]
        for tab in tabs {
            guard let groupID = tab.syncGroupID else { continue }
            for tile in tab.tiles {
                let modules: [DashboardModuleModel]
                if let existing = tile.modules {
                    modules = existing
                } else if case .person(let model) = tile.kind {
                    modules = [DashboardModuleModel(kind: .person(model), order: 0, id: tile.id)]
                } else {
                    modules = []
                }
                for module in modules {
                    guard case .person(let person) = module.kind else { continue }
                    let name = tab.resolvedPersonModel(person).name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, name.lowercased() != "person" else { continue }
                    let variableName = normalizeSharedValueName("person_\(name)")
                    guard !variableName.isEmpty else { continue }
                    let sourceID = "linked-person:\(groupID):\(module.id.uuidString)"
                    let sourceComputerName = tab.syncOwnerDeviceName.isEmpty
                        ? (tab.syncOwnerDeviceID.flatMap { computerNamesByDeviceID[$0] }
                            ?? (tab.syncLastEditedByDeviceName.isEmpty ? "Unknown computer" : tab.syncLastEditedByDeviceName))
                        : tab.syncOwnerDeviceName
                    found[sourceID] = found[sourceID] ?? LinkedComputerPersonVariable(
                        sourceID: sourceID,
                        name: name,
                        sourceComputerName: sourceComputerName,
                        variableName: variableName,
                        isDisconnected: disconnectedGroupIDs.contains(groupID),
                        lastUpdatedAt: tab.syncLastEditedAt > 0 ? Date(timeIntervalSince1970: tab.syncLastEditedAt) : nil
                    )
                }
            }
        }
        let counts = Dictionary(grouping: found.values, by: \.variableName).mapValues(\.count)
        return found.values.map { original in
            var value = original
            if counts[original.variableName, default: 0] > 1 {
                value.variableName = normalizeSharedValueName("\(original.variableName)_\(original.sourceID)")
            }
            return value
        }.sorted { $0.variableName < $1.variableName }
    }
}

@MainActor
final class LinkedComputerPersonVariableStore: ObservableObject {
    static let shared = LinkedComputerPersonVariableStore()
    @Published private(set) var variables: [LinkedComputerPersonVariable] = []

    func update(
        tabs: [DashboardTab],
        disconnectedGroupIDs: Set<String> = [],
        computerNamesByDeviceID: [String: String] = [:]
    ) {
        variables = LinkedComputerPersonVariables.discover(
            in: tabs,
            disconnectedGroupIDs: disconnectedGroupIDs,
            computerNamesByDeviceID: computerNamesByDeviceID
        )
    }

    func value(named name: String) -> String? {
        let key = normalizeSharedValueName(name)
        if let exact = variables.first(where: { $0.variableName == key }) { return exact.name }
        return variables.sorted { $0.sourceID < $1.sourceID }
            .first { normalizeSharedValueName("person_\($0.name)") == key }?.name
    }
}
