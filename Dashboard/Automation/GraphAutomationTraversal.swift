//
//  GraphAutomationTraversal.swift
//  Relay
//
//  Created by David Bullard on 1/19/26.
//


import Foundation

// MARK: - Graph Automation Traversal (UI-independent)

/// Pure graph traversal helpers for automation. No SwiftUI dependencies.
/// Used by GraphDashboardView *and* by a background GraphRuntime (Canvas mode).
enum GraphAutomationTraversal {
    enum UtilityBranch: String {
        case `true`
        case `false`
    }

    struct DownstreamConnection: Equatable {
        var sourceNodeId: UUID
        var sourcePortId: String
        var targetNodeId: UUID
        var targetGroupKey: String?
    }

    static func defaultPortId(for nodeId: UUID) -> String {
        "node:\(nodeId.uuidString)"
    }

    static func repeaterOutputPortId(nodeId: UUID, index: Int) -> String {
        "repeater:\(nodeId.uuidString):\(max(0, index))"
    }

    static func conditionOutputPortId(nodeId: UUID, branch: UtilityBranch) -> String {
        "condition:\(nodeId.uuidString):\(branch.rawValue)"
    }

    static func toggleOutputPortId(nodeId: UUID, isOn: Bool) -> String {
        "toggle:\(nodeId.uuidString):\(isOn ? "on" : "off")"
    }

    static func sequenceOutputPortId(nodeId: UUID, step: Int) -> String {
        "sequence:\(nodeId.uuidString):\(max(0, step))"
    }

    static func buttonOutputPortId(nodeId: UUID, buttonConfigId: UUID) -> String {
        "button:\(nodeId.uuidString):\(buttonConfigId.uuidString)"
    }

    static func smartLightOutputPortId(nodeId: UUID, kind: String) -> String {
        "smartlight:\(nodeId.uuidString):\(kind)"
    }

    static func wordTriggerRulePortId(nodeId: UUID, ruleId: UUID) -> String {
        "wordTrigger:\(nodeId.uuidString):rule:\(ruleId.uuidString)"
    }

    static func currentTimeTextPortId(nodeId: UUID) -> String {
        "currentTime:\(nodeId.uuidString):text"
    }

    static func currentTimeNumberPortId(nodeId: UUID) -> String {
        "currentTime:\(nodeId.uuidString):number"
    }

    static func downstreamConnections(
        graph: DashboardGraph,
        sourceNodeId: UUID,
        sourcePortId: String? = nil,
        resolveNodeIdFromPortId: (String) -> UUID?
    ) -> [DownstreamConnection] {
        var results: [DownstreamConnection] = []
        for link in graph.links where link.isEnabled && link.kind != .identity {
            let fromId = resolveNodeIdFromPortId(link.fromPortId) ?? link.fromTileId
            guard fromId == sourceNodeId else { continue }
            if let sourcePortId, link.fromPortId != sourcePortId { continue }

            let toId = resolveNodeIdFromPortId(link.toPortId) ?? link.toTileId
            let targetGroupKey = graph.moduleGroupNodeInstances.first(where: { $0.id == toId })?.groupKey
            results.append(
                DownstreamConnection(
                    sourceNodeId: sourceNodeId,
                    sourcePortId: link.fromPortId,
                    targetNodeId: toId,
                    targetGroupKey: targetGroupKey
                )
            )
        }
        return results
    }

    /// Returns the action node instances (id + key) directly connected from `triggerNodeId`.
    /// Non-recursive (one hop) by design.
    static func downstreamActionInstances(
        graph: DashboardGraph,
        triggerNodeId: UUID,
        sourcePortId: String? = nil,
        resolveNodeIdFromPortId: (String) -> UUID?
    ) -> [(nodeId: UUID, key: String)] {
        downstreamConnections(
            graph: graph,
            sourceNodeId: triggerNodeId,
            sourcePortId: sourcePortId,
            resolveNodeIdFromPortId: resolveNodeIdFromPortId
        ).compactMap { connection in
            guard let key = connection.targetGroupKey, key.hasPrefix("action.") else { return nil }
            return (connection.targetNodeId, key)
        }
    }

    static func downstreamNodeIds(
        graph: DashboardGraph,
        triggerNodeId: UUID,
        matchingGroupKeys: Set<String>,
        sourcePortId: String? = nil,
        resolveNodeIdFromPortId: (String) -> UUID?
    ) -> [UUID] {
        guard !matchingGroupKeys.isEmpty else { return [] }
        return downstreamConnections(
            graph: graph,
            sourceNodeId: triggerNodeId,
            sourcePortId: sourcePortId,
            resolveNodeIdFromPortId: resolveNodeIdFromPortId
        ).compactMap { connection in
            guard let key = connection.targetGroupKey, matchingGroupKeys.contains(key) else { return nil }
            return connection.targetNodeId
        }
    }

    /// Resolves a stable node id from a port id string, preferring the persisted
    /// reverse index and falling back to parsing well-known port-id prefixes.
    /// Mirrors GraphAutomationRuntime's private resolver of the same name -- that
    /// copy is left untouched (it has ~20 existing call sites in a runtime file
    /// that's already been carefully hardened), but the UI layer needs this same
    /// pure logic to compute wiring state directly from the graph model.
    static func resolveNodeId(fromPortId portId: String, graph: DashboardGraph) -> UUID? {
        if let mapped = graph.nodeIdByPortId[portId] { return mapped }

        if portId.hasPrefix("node:") {
            return UUID(uuidString: String(portId.dropFirst(5)))
        }
        if portId.hasPrefix("tile:") {
            return UUID(uuidString: String(portId.dropFirst(5)))
        }
        if portId.hasPrefix("repeater:") || portId.hasPrefix("condition:") ||
           portId.hasPrefix("toggle:") || portId.hasPrefix("sequence:") ||
           portId.hasPrefix("smartlight:") ||
           portId.hasPrefix("currentTime:") {
            let parts = portId.split(separator: ":")
            guard parts.count >= 2 else { return nil }
            return UUID(uuidString: String(parts[1]))
        }
        return nil
    }
}
