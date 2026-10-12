//
//  GraphDashboardView.swift
//  Relay
//
//  Created by David Bullard on 1/2/26.
//


#if canImport(SwiftUI)
import SwiftUI
#endif
import Foundation
import CryptoKit
#if os(macOS)
import AppKit
#endif

/// Graph view for a Dashboard tab.
/// Nodes are module-group nodes (e.g. all Person modules) plus graph-only console nodes.

struct GraphDashboardView: View {
@Binding var tab: DashboardTab
    var isLiveMode: Bool
    var lanPeers: [LANSharedTabsService.Peer] = []
    var lanNotificationsEnabled: Bool = false
/// Frozen snapshot of external devices captured by the parent view.
/// The graph should not observe the live store directly because frequent
/// device/wireless publishes can invalidate the entire automation canvas.
var externalDevicesSnapshot: [ExternalDeviceConfig] = []

/// Frozen snapshot of the canvas tiles/modules captured when entering Graph mode.
/// Graph view must NOT read live `tab.tiles`.
var tilesSnapshot: [DashboardTileModel] = []
/// Frozen snapshot of the Planning Center rundown (service order) captured when entering Graph mode.
/// Used for snapshot creation/rename workflows; graph view should not query live PCO.
var pcoRundownSnapshotTitles: [String] = []

/// Called whenever tab.graph changes so the parent can schedule an autosave.
var onGraphChanged: (() -> Void)? = nil

    // Always-on automation runtime (needed for OSC triggers in Graph mode)
@StateObject private var automationRuntime = GraphAutomationRuntime.shared

// MARK: - NotificationCenter bridge (keeps SwiftUI body type-checker happy)

@StateObject private var notificationHub = GraphDashboardNotificationHub()
@StateObject private var runtimeCoordinator = GraphDashboardRuntimeCoordinator()
@StateObject private var smartLightProfilesStore = SmartLightProfilesStore.shared
@EnvironmentObject private var subscriptionManager: SubscriptionManager
@State private var isBatchDeletingNodes: Bool = false
@StateObject private var undoProxy = GraphDashboardUndoProxy()
#if os(macOS)
@Environment(\.prodLinkIsWorkEnabled) private var isWorkEnabled
#else
private let isWorkEnabled: Bool = true
#endif
@Environment(\.undoManager) private var undoManager
    
// Drag state
@State private var dragStartByTileId: [UUID: CGPoint] = [:]
@State private var dragGrabOffsetByTileId: [UUID: CGPoint] = [:]
// During drag, keep positions locally to avoid hammering tab.graph (which triggers large SwiftUI invalidations).
@State private var transientNodePositions: [UUID: CGPoint] = [:]

/// Cache the last non-empty module groups so brief/transitionary empty snapshots
/// (e.g. during a flip) don't visually drop nodes.
@State private var cachedModuleGroups: [ModuleGroup] = []
// Cache: derived PCO team options (avoid recompute during SwiftUI updates)
@State private var cachedPeopleTeamOptionsFromTab: [String] = []
@State private var cachedSynthesizedPeopleMembersFromPCO: [ModuleMember] = []
// Add-node UI (graph-only module-group nodes)
@State private var showAddNodePopover: Bool = false
@State private var addNodeSearchText: String = ""
@State private var addNodeSelectedCategory: String = "All"
@State private var addNodeHelpMessage: AddNodeHelpContent? = nil
@State private var destinationPickerState: DestinationPickerState? = nil
@State private var showPeopleNameSettingsNodeId: UUID? = nil
@FocusState private var addNodeSearchIsFocused: Bool
// Link-drag state (source -> destination)
@State private var linkingFromNodeId: UUID? = nil
@State private var linkingFromPoint: CGPoint? = nil
@State private var linkingCurrentPoint: CGPoint? = nil
@State private var hoverReceiverNodeId: UUID? = nil
@State private var hoverInvalidReceiverNodeId: UUID? = nil
@State private var currentRepeaterOutputIndex: Int = 0
@State private var currentConditionOutputBranch: GraphAutomationTraversal.UtilityBranch = .`true`
@State private var currentToggleOutputIsOn: Bool = true
@State private var currentSequenceOutputStep: Int = 0
@State private var currentSmartLightOutputKind: String = "success"
@State private var currentWordTriggerRuleId: UUID = UUID()
@State private var currentButtonOutputConfigId: UUID? = nil

// MARK: - Marquee selection (Graph)

@State private var isMarqueeSelecting: Bool = false
@State private var marqueeStart: CGPoint? = nil
@State private var marqueeCurrent: CGPoint? = nil
@State private var isNodeDragging: Bool = false
@State private var selectedGraphNodeIds: Set<UUID> = []
@State private var suppressNextBackgroundTap: Bool = false
@State private var didInstallSendAllListenerInGraph: Bool = false
@FocusState private var graphIsFocused: Bool

@State private var measuredNodeSizes: [UUID: CGSize] = [:]
@State private var proPresenterTriggerErrors: [UUID: String] = [:]
@State private var appControlErrors: [UUID: String] = [:]
@State private var appControlRunningNodeIds: Set<UUID> = []
@State private var smartLightErrors: [UUID: String] = [:]
@State private var conditionMismatchErrors: [UUID: String] = [:]
@State private var smartLightRunningNodeIds: Set<UUID> = []
@State private var consoleActionErrors: [UUID: String] = [:]
@State private var consoleActionRunningNodeIds: Set<UUID> = []
@State private var lastTriggerFireAtByNodeId: [UUID: TimeInterval] = [:]
@State private var conditionComparisonTextDraftByNodeId: [UUID: String] = [:]
@State private var editingConditionComparisonNodeIds: Set<UUID> = []
@State private var showTriggerSendMigrationAlert: Bool = false
@AppStorage("relay.didShowTriggerSendMigrationNotice") private var didShowMigrationNotice: Bool = false
@State private var pendingGraphEditUndoBefore: Data? = nil
@State private var pendingGraphEditActionName: String? = nil
@State private var pendingGraphEditWorkItem: DispatchWorkItem? = nil
@State private var nodeSizePreferenceWorkItem: DispatchWorkItem? = nil
@State private var pendingCacheRefreshWorkItem: DispatchWorkItem? = nil
@State private var stableUUIDByKey: [String: UUID] = [:]
/// Caches decoded VistaPCORundownItem per packed string — avoids a new JSONDecoder + NSMutableDictionary
/// allocation on every buildGroups call. Same pattern as stableUUIDByKey.
@State private var rundownItemCache: [String: VistaPCORundownItem?] = [:]

private struct GraphNodeSizePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGSize] = [:]
    static func reduce(value: inout [UUID: CGSize], nextValue: () -> [UUID: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AddNodeHelpContent: Equatable {
    let title: String
    let message: String
}

#if os(macOS)
private struct GraphDeleteKeyMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onDelete: onDelete)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onDelete = onDelete
        context.coordinator.installMonitor()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onDelete: () -> Void
        private var localMonitor: Any?

        init(isEnabled: Bool, onDelete: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onDelete = onDelete
        }

        func installMonitor() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }
                if event.keyCode == 51 || event.keyCode == 117 {
                    self.onDelete()
                    return nil
                }
                return event
            }
        }

        func removeMonitor() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}

private func isGraphTextInputActive() -> Bool {
    if addNodeSearchIsFocused {
        return true
    }

    guard let responder = NSApp.keyWindow?.firstResponder else {
        return false
    }

    return responder is NSTextView
}

private func dismissGraphTextInput() {
    finalizePendingGraphEditUndo()
    addNodeSearchIsFocused = false
    if NSApp.keyWindow?.firstResponder is NSTextView {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

private func focusGraphSurface() {
    dismissGraphTextInput()
    graphIsFocused = true
    DispatchQueue.main.async {
        graphIsFocused = true
    }
}
#endif

@ViewBuilder
private func nodeSizeReporter(_ nodeId: UUID) -> some View {
    GeometryReader { proxy in
        Color.clear.preference(key: GraphNodeSizePreferenceKey.self, value: [nodeId: proxy.size])
    }
}

// MARK: - Graph selection + delete

private var consoleNodeIds: [UUID] {
    (tab.graph?.moduleGroupNodeInstances ?? [])
        .filter { $0.groupKey == "destination.console" }
        .map { $0.id }
}

private var consoleExternalDeviceIds: [UUID] {
    var seen = Set<UUID>()
    return consoleNodeIds.compactMap { nodeId -> UUID? in
        guard let deviceId = externalDeviceId(forConsoleNodeId: nodeId) else { return nil }
        return seen.insert(deviceId).inserted ? deviceId : nil
    }
}

private var availableVistaDestinationDevices: [ExternalDeviceConfig] {
    externalDevicesSnapshot
        .filter { $0.kind == .vistaConsole }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
}

private func consoleDevice(forNodeId nodeId: UUID) -> ExternalDeviceConfig? {
    guard let deviceId = externalDeviceId(forConsoleNodeId: nodeId) else { return nil }
    return externalDevicesSnapshot.first(where: { $0.id == deviceId })
}

private func isConsoleNodeId(_ nodeId: UUID) -> Bool {
    consoleNodeIds.contains(nodeId)
}

private func isCanvasBackedGroupNodeId(_ nodeId: UUID) -> Bool {
    let groups = computedModuleGroups()
    for g in groups where g.isCanvasBacked {
        if groupNodeId(for: g.key) == nodeId { return true }
    }
    return false
}

private func removeAllLinks(forNodeId nodeId: UUID) {
    guard tab.graph != nil else { return }
    let port = "node:\(nodeId.uuidString)"
    if !isBatchDeletingNodes {
        registerGraphUndo(actionName: "Unlink", before: snapshotGraphForUndo())
    }
    tab.graph?.links.removeAll(where: { link in
        link.fromTileId == nodeId || link.toTileId == nodeId ||
        link.fromPortId == port || link.toPortId == port
    })
}

private func deleteSelectedGraphNodes() {
    guard !selectedGraphNodeIds.isEmpty else { return }
    registerGraphUndo(actionName: "Delete Node", before: snapshotGraphForUndo())
    isBatchDeletingNodes = true
    defer { isBatchDeletingNodes = false }
    
    // Canvas-backed group nodes (e.g. People/Planning Center) should never be deleted.
    let groups = computedModuleGroups()
    let canvasBackedIds = Set(groups.filter { $0.isCanvasBacked }.map { groupNodeId(for: $0.key) })

    // Auto-mirrored canvas Button trigger nodes are also protected — they're owned by the canvas.
    let buttonTriggerIds = Set(
        (tab.graph?.moduleGroupNodeInstances ?? [])
            .filter { $0.groupKey == DashboardGraph.buttonTriggerGroupKey }
            .map(\.id)
    )

    let protectedIds = canvasBackedIds.union(buttonTriggerIds)

    // Only delete graph-only node instances (Sources/Triggers/Actions instances) that are not protected.
    let graphOnlyIds: [UUID] = selectedGraphNodeIds.filter { !protectedIds.contains($0) }

    // If nothing deletable is selected, just clear selection.
    guard !graphOnlyIds.isEmpty else {
        selectedGraphNodeIds.removeAll()
        return
    }

    for id in graphOnlyIds {
        // Remove links + layout for this node id.
        removeAllLinks(forNodeId: id)
        tab.graph?.tileLayouts.removeValue(forKey: id)

        // Remove the graph-only node instance.
        removeGraphOnlyModuleGroupNodeInstance(nodeId: id)

        // If we were linking from this node, reset link-drag state.
        if linkingFromNodeId == id {
            linkingFromNodeId = nil
            linkingFromPoint = nil
            linkingCurrentPoint = nil
            clearLinkHoverState()
        }
    }

    // Clear selection for deleted ids.
    selectedGraphNodeIds.subtract(graphOnlyIds)
    if selectedGraphNodeIds.isEmpty { selectedGraphNodeIds.removeAll() }
}

private func addNodeHelp(title: String, message: String) -> AddNodeHelpContent {
    AddNodeHelpContent(title: title, message: message)
}

private func unavailableAddNodeHelp(for group: AddableGroup) -> AddNodeHelpContent {
    switch group.id {
    case "destination.console":
        return addNodeHelp(
            title: "No Consoles Configured",
            message: "Add an audio console in Connections before adding this destination node."
        )
    case "destination.vista":
        return addNodeHelp(
            title: "No Vista Consoles Configured",
            message: "Add a Vista console in Connections before adding this destination node."
        )
    case "moduleGroup.shure":
        return addNodeHelp(
            title: "No Shure Devices Configured",
            message: "Add a Shure wireless device in Connections before adding this node."
        )
    case "moduleGroup.sennheiser":
        return addNodeHelp(
            title: "No Sennheiser Devices Configured",
            message: "Add a Sennheiser wireless device in Connections before adding this node."
        )
    case "action.shureSend":
        return addNodeHelp(
            title: "No Shure Control Devices",
            message: "Add a Shure device with control support in Connections before adding this action."
        )
    case "action.sennheiserSend":
        return addNodeHelp(
            title: "No Sennheiser Control Devices",
            message: "Add a Sennheiser device with control support in Connections before adding this action."
        )
    default:
        return addNodeHelp(
            title: "Node Unavailable",
            message: group.subtitle
        )
    }
}

private func canDeleteGraphNode(nodeId: UUID, key: String) -> Bool {
    if key == DashboardGraph.buttonTriggerGroupKey {
        return false
    }

    return !isCanvasBackedGroupNodeId(nodeId)
}

private func deleteGraphNode(nodeId: UUID, key: String) {
    guard canDeleteGraphNode(nodeId: nodeId, key: key) else { return }

    registerGraphUndo(actionName: "Delete Node", before: snapshotGraphForUndo())

    switch key {
    case "action.sendAllConsoles":
        tab.graph?.sendAllConsolesActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.oscSend":
        tab.graph?.oscSendActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.notify":
        tab.graph?.notifyActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.lanNotify":
        tab.graph?.lanNotifyActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.appControl":
        tab.graph?.appControlActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.midiSend":
        tab.graph?.midiSendActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.httpRequest":
        tab.graph?.httpRequestActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.setVariable":
        tab.graph?.setVariableActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.proPresenterTrigger":
        tab.graph?.proPresenterTriggerActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        proPresenterTriggerErrors.removeValue(forKey: nodeId)
    case "action.smartLightControl":
        tab.graph?.smartLightActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        smartLightErrors.removeValue(forKey: nodeId)
        smartLightRunningNodeIds.remove(nodeId)
    case "action.shureSend":
        tab.graph?.shureSendActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "action.sennheiserSend":
        tab.graph?.sennheiserSendActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "utility.delay":
        tab.graph?.delayActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "utility.condition":
        conditionComparisonTextDraftByNodeId.removeValue(forKey: nodeId)
        editingConditionComparisonNodeIds.remove(nodeId)
        tab.graph?.conditionNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        conditionMismatchErrors.removeValue(forKey: nodeId)
    case "utility.repeater":
        tab.graph?.repeaterActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "utility.toggle":
        tab.graph?.toggleNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "utility.counter":
        tab.graph?.counterNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "utility.sequence":
        tab.graph?.sequenceNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "utility.latch":
        tab.graph?.latchNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "destination.console":
        tab.graph?.consoleDeviceIdByNodeId.removeValue(forKey: nodeId.uuidString)
        tab.graph?.quConsoleActionsByNodeId.removeValue(forKey: nodeId.uuidString)
        tab.graph?.digicoConsoleActionsByNodeId.removeValue(forKey: nodeId.uuidString)
        tab.graph?.standardConsoleActionsByNodeId.removeValue(forKey: nodeId.uuidString)
        consoleActionErrors.removeValue(forKey: nodeId)
        consoleActionRunningNodeIds.remove(nodeId)
    case "moduleGroup.pcoItemChanged":
        tab.graph?.pcoItemChangedConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    case "moduleGroup.appState":
        tab.graph?.appStateTriggerConfigByNodeId.removeValue(forKey: nodeId.uuidString)
    default:
        break
    }

    if showPeopleNameSettingsNodeId == nodeId {
        showPeopleNameSettingsNodeId = nil
    }
    appControlErrors.removeValue(forKey: nodeId)
    appControlRunningNodeIds.remove(nodeId)
    smartLightErrors.removeValue(forKey: nodeId)
    smartLightRunningNodeIds.remove(nodeId)
    conditionMismatchErrors.removeValue(forKey: nodeId)
    consoleActionErrors.removeValue(forKey: nodeId)
    consoleActionRunningNodeIds.remove(nodeId)
    lastTriggerFireAtByNodeId.removeValue(forKey: nodeId)
    transientNodePositions.removeValue(forKey: nodeId)
    measuredNodeSizes.removeValue(forKey: nodeId)

    removeGraphOnlyModuleGroupNodeInstance(nodeId: nodeId)
    selectedGraphNodeIds.remove(nodeId)
    clearLinkHoverState()
}

private func duplicateSelectedGraphNodes() {
    guard tab.graph != nil else { return }
    guard !selectedGraphNodeIds.isEmpty else { return }

    let groups = computedModuleGroups()
    let canvasBackedIds = Set(groups.filter { $0.isCanvasBacked }.map { groupNodeId(for: $0.key) })
    let buttonTriggerIds = Set(
        (tab.graph?.moduleGroupNodeInstances ?? [])
            .filter { $0.groupKey == DashboardGraph.buttonTriggerGroupKey }
            .map(\.id)
    )
    let duplicableIds = selectedGraphNodeIds
        .filter { !canvasBackedIds.contains($0) && !buttonTriggerIds.contains($0) }
        .sorted { lhs, rhs in
            let left = nodePosition(for: lhs)
            let right = nodePosition(for: rhs)
            if left.y == right.y { return left.x < right.x }
            return left.y < right.y
        }

    guard !duplicableIds.isEmpty else { return }
    registerGraphUndo(actionName: duplicableIds.count == 1 ? "Duplicate Node" : "Duplicate Nodes", before: snapshotGraphForUndo())

    let offset = CGPoint(x: 36, y: 36)
    var idMap: [UUID: UUID] = [:]
    var newSelection: Set<UUID> = []

    for sourceId in duplicableIds {
        guard let instance = tab.graph?.moduleGroupNodeInstances.first(where: { $0.id == sourceId }) else { continue }
        let destinationId = UUID()
        idMap[sourceId] = destinationId
        newSelection.insert(destinationId)

        tab.graph?.moduleGroupNodeInstances.append(.init(id: destinationId, groupKey: instance.groupKey))

        let sourcePosition = nodePosition(for: sourceId)
        tab.graph?.tileLayouts[destinationId] = TileGraphLayout(
            position: CGPoint(x: sourcePosition.x + offset.x, y: sourcePosition.y + offset.y)
        )
        tab.graph?.hiddenNodeIds.removeAll(where: { $0 == destinationId })
        tab.graph?.nodeIdByPortId["node:\(destinationId.uuidString)"] = destinationId
        cloneGraphNodeConfiguration(from: sourceId, to: destinationId, groupKey: instance.groupKey)
    }

    if let graph = tab.graph {
        let duplicatedLinks = graph.links.compactMap { link -> GraphLink? in
            guard let fromId = idMap[link.fromTileId], let toId = idMap[link.toTileId] else { return nil }
            return GraphLink(
                fromTileId: fromId,
                fromPortId: remapGraphPortId(link.fromPortId, using: idMap),
                toTileId: toId,
                toPortId: remapGraphPortId(link.toPortId, using: idMap),
                kind: link.kind,
                isEnabled: link.isEnabled,
                label: link.label
            )
        }
        tab.graph?.links.append(contentsOf: duplicatedLinks)
    }

    selectedGraphNodeIds = newSelection
    cachedModuleGroups = buildModuleGroups()
}

private func postGraphSelectionCount() {
    NotificationCenter.default.post(
        name: .prodLinkGraphSelectionCountChanged,
        object: selectedGraphNodeIds.count
    )
}
    // MARK: - Undo (Graph)

    /// Snapshot the current graph for Undo/Redo.
    /// Uses Codable round-trip to avoid reference-sharing.
    private func snapshotGraphForUndo() -> Data? {
        guard let g = tab.graph else { return nil }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let encoded = GraphDashboardPersistenceAdapter.encodeGraph(g)
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        let details = "nodes=\(g.moduleGroupNodeInstances.count) links=\(g.links.count) bytes=\(encoded?.count ?? 0)"
        recordGraphPerfMetric(
            "graph.undo.snapshot.encode",
            duration: duration,
            details: details,
            slowThreshold: 0.015
        )
        incrementGraphCounter("graph.undo.snapshot.encode.calls")
        return encoded
    }

    private func restoreGraphFromUndo(_ data: Data?) {
        if let data {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let decoded = GraphDashboardPersistenceAdapter.decodeGraph(data)
            let duration = CFAbsoluteTimeGetCurrent() - startedAt
            let details = "bytes=\(data.count) success=\(decoded != nil)"
            recordGraphPerfMetric(
                "graph.undo.snapshot.decode",
                duration: duration,
                details: details,
                slowThreshold: 0.015
            )
            incrementGraphCounter("graph.undo.snapshot.decode.calls")
            if let decoded {
                tab.graph = decoded
            } else {
                // If decode fails, keep current state rather than corrupting graph.
                return
            }
        } else {
            tab.graph = nil
        }

        // Rebuild caches and clear transient interaction state
        refreshGraphCaches()
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
       
    }

    private func registerGraphUndo(actionName: String, before: Data?) {
        undoProxy.register(actionName: actionName, before: before, undoManager: undoManager)
    }

    private func finalizePendingGraphEditUndo() {
        pendingGraphEditWorkItem?.cancel()
        pendingGraphEditWorkItem = nil
        guard let before = pendingGraphEditUndoBefore else { return }
        let actionName = pendingGraphEditActionName ?? "Edit Node"
        pendingGraphEditUndoBefore = nil
        pendingGraphEditActionName = nil
        registerGraphUndo(actionName: actionName, before: before)
    }

    private func schedulePendingGraphEditUndo(actionName: String, before: Data?) {
        if pendingGraphEditUndoBefore == nil {
            pendingGraphEditUndoBefore = before
            pendingGraphEditActionName = actionName
        }
        pendingGraphEditWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            finalizePendingGraphEditUndo()
        }
        pendingGraphEditWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func commitGraphEdit(actionName: String = "Edit Node", _ mutation: () -> Void) {
        let before = snapshotGraphForUndo()
        mutation()
        let after = snapshotGraphForUndo()
        guard before != after else { return }
        #if os(macOS)
        if isGraphTextInputActive() {
            schedulePendingGraphEditUndo(actionName: actionName, before: before)
        } else {
            finalizePendingGraphEditUndo()
            registerGraphUndo(actionName: actionName, before: before)
        }
        #else
        registerGraphUndo(actionName: actionName, before: before)
        #endif
        Task { @MainActor in
            automationRuntime.setActiveTabSnapshot(tab)
        }
    }

    private func performGraphEdit(actionName: String, mutation: @escaping () -> Void) {
        commitGraphEdit(actionName: actionName) {
            mutation()
        }
    }

private func remapGraphPortId(_ portId: String, using idMap: [UUID: UUID]) -> String {
    func remap(_ sourceId: UUID, transform: (UUID) -> String) -> String {
        guard let destinationId = idMap[sourceId] else { return portId }
        return transform(destinationId)
    }

    if portId.hasPrefix("node:") {
        let rawNodeId = String(portId.dropFirst(5))
        guard let sourceId = UUID(uuidString: rawNodeId) else { return portId }
        return remap(sourceId) { GraphAutomationTraversal.defaultPortId(for: $0) }
    }

    if portId.hasPrefix("repeater:") {
        let parts = portId.split(separator: ":")
        guard parts.count == 3,
              let sourceId = UUID(uuidString: String(parts[1])),
              let index = Int(parts[2]) else {
            return portId
        }
        return remap(sourceId) { GraphAutomationTraversal.repeaterOutputPortId(nodeId: $0, index: index) }
    }

    if portId.hasPrefix("condition:") {
        let parts = portId.split(separator: ":")
        guard parts.count == 3,
              let sourceId = UUID(uuidString: String(parts[1])) else {
            return portId
        }
        let branch: GraphAutomationTraversal.UtilityBranch = String(parts[2]) == "true" ? .`true` : .`false`
        return remap(sourceId) { GraphAutomationTraversal.conditionOutputPortId(nodeId: $0, branch: branch) }
    }

    if portId.hasPrefix("smartlight:") {
        let parts = portId.split(separator: ":")
        guard parts.count == 3,
              let sourceId = UUID(uuidString: String(parts[1])) else {
            return portId
        }
        let kind = String(parts[2])
        return remap(sourceId) { GraphAutomationTraversal.smartLightOutputPortId(nodeId: $0, kind: kind) }
    }

    return portId
}

private func recordGraphPerfMetric(
    _ key: String,
    duration: TimeInterval,
    details: String? = nil,
    slowThreshold: TimeInterval? = nil
) {
    Task { @MainActor in
        RelayDiagnosticsStore.shared.recordPerformanceMetric(
            key,
            duration: duration,
            details: details,
            slowThreshold: slowThreshold
        )
    }
}

private func incrementGraphCounter(_ key: String, by amount: Int = 1) {
    Task { @MainActor in
        RelayDiagnosticsStore.shared.incrementCounter(key, by: amount)
    }
}

private func graphCGSizeApproximatelyEqual(_ lhs: CGSize?, _ rhs: CGSize, tolerance: CGFloat = 0.5) -> Bool {
    guard let lhs else { return false }
    return abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
}

private func graphCGPointApproximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat = 0.5) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

private func graphNodeSizeGrowthRequiresCollisionResolution(
    previous: CGSize?,
    current: CGSize,
    growthThreshold: CGFloat = 8
) -> Bool {
    guard let previous else { return false }
    return (current.width - previous.width) > growthThreshold || (current.height - previous.height) > growthThreshold
}

private func uniqueDuplicatedVariableName(
    from baseName: String,
    destinationId: UUID
) -> String {
    let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
    let seed = trimmedBase.isEmpty ? "variable" : trimmedBase
    let existingNormalizedNames = Set(
        tab.graph?.variableNodeConfigByNodeId.compactMap { key, value in
            key == destinationId.uuidString ? nil : normalizeGraphVariableName(value.name)
        } ?? []
    )

    var candidate = seed
    var suffix = 2
    while existingNormalizedNames.contains(normalizeGraphVariableName(candidate)) {
        candidate = "\(seed) \(suffix)"
        suffix += 1
    }
    return candidate
}

private func cloneGraphNodeConfiguration(from sourceId: UUID, to destinationId: UUID, groupKey: String) {
    let sourceKey = sourceId.uuidString
    let destinationKey = destinationId.uuidString

    switch groupKey {
    case "action.appControl":
        if var config = tab.graph?.appControlActionConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.appControlActionConfigByNodeId[destinationKey] = config
        }
    case "action.notify":
        if var config = tab.graph?.notifyActionConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.notifyActionConfigByNodeId[destinationKey] = config
        }
    case "action.lanNotify":
        if var config = tab.graph?.lanNotifyActionConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.lanNotifyActionConfigByNodeId[destinationKey] = config
        }
    case "action.oscSend":
        if var config = tab.graph?.oscSendActionConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.oscSendActionConfigByNodeId[destinationKey] = config
        }
    case "action.sendAllConsoles":
        if var config = tab.graph?.sendAllConsolesActionConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.sendAllConsolesActionConfigByNodeId[destinationKey] = config
        }
    case "action.smartLightControl":
        if var config = tab.graph?.smartLightActionConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.smartLightActionConfigByNodeId[destinationKey] = config
        }
    case "trigger.oscReceive":
        if var config = tab.graph?.oscReceiveConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.oscReceiveConfigByNodeId[destinationKey] = config
        }
    case "trigger.midiReceive":
        if var config = tab.graph?.midiReceiveConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.midiReceiveConfigByNodeId[destinationKey] = config
        }
    case "trigger.wordTrigger":
        if var config = tab.graph?.wordTriggerConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.wordTriggerConfigByNodeId[destinationKey] = config
        }
    case "trigger.dbThreshold":
        if var config = tab.graph?.dbThresholdConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.dbThresholdConfigByNodeId[destinationKey] = config
        }
    case "utility.repeater":
        if var config = tab.graph?.repeaterActionConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.repeaterActionConfigByNodeId[destinationKey] = config
        }
    case "utility.delay":
        if var config = tab.graph?.delayActionConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.delayActionConfigByNodeId[destinationKey] = config
        }
    case "utility.condition":
        if var config = tab.graph?.conditionNodeConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.conditionNodeConfigByNodeId[destinationKey] = config
        }
    case "utility.variable":
        if var config = tab.graph?.variableNodeConfigByNodeId[sourceKey] {
            config.id = destinationId
            config.name = uniqueDuplicatedVariableName(from: config.name, destinationId: destinationId)
            config.currentTextValue = nil
            config.currentNumberValue = nil
            config.currentBooleanValue = nil
            config.lastUpdatedAt = nil
            config.sourceNodeId = nil
            tab.graph?.variableNodeConfigByNodeId[destinationKey] = config
        }
    case "moduleGroup.keystrokeTrigger":
        if var config = tab.graph?.keystrokeTriggerConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.keystrokeTriggerConfigByNodeId[destinationKey] = config
        }
    case "destination.console":
        if let actions = tab.graph?.quConsoleActionsByNodeId[sourceKey] {
            tab.graph?.quConsoleActionsByNodeId[destinationKey] = actions
        }
        if let digicoActions = tab.graph?.digicoConsoleActionsByNodeId[sourceKey] {
            tab.graph?.digicoConsoleActionsByNodeId[destinationKey] = digicoActions
        }
        if let standardActions = tab.graph?.standardConsoleActionsByNodeId[sourceKey] {
            tab.graph?.standardConsoleActionsByNodeId[destinationKey] = standardActions
        }
        if let deviceId = tab.graph?.consoleDeviceIdByNodeId[sourceKey] {
            tab.graph?.consoleDeviceIdByNodeId[destinationKey] = deviceId
        }
    case "destination.vista":
        if var config = tab.graph?.vistaNodeConfigByNodeId[sourceKey] {
            config.id = destinationId
            config.externalDeviceConfig.id = UUID()
            tab.graph?.vistaNodeConfigByNodeId[destinationKey] = config
        }
    case "source.roster":
        if var config = tab.graph?.rosterSourceConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.rosterSourceConfigByNodeId[destinationKey] = config
        }
    case "source.consoleImport":
        if var config = tab.graph?.consoleLabelSourceConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.consoleLabelSourceConfigByNodeId[destinationKey] = config
        }
    case "source.wirelessImport":
        if var config = tab.graph?.wirelessLabelSourceConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.wirelessLabelSourceConfigByNodeId[destinationKey] = config
        }
    case "source.staticLabel":
        if var config = tab.graph?.staticLabelSourceConfigByNodeId[sourceKey] {
            config.id = destinationId
            tab.graph?.staticLabelSourceConfigByNodeId[destinationKey] = config
        }
    default:
        break
    }

    if let mode = tab.graph?.peopleSourceByNodeId[sourceKey] {
        tab.graph?.peopleSourceByNodeId[destinationKey] = mode
    }
    if let filters = tab.graph?.peopleTeamFiltersByNodeId[sourceKey] {
        tab.graph?.peopleTeamFiltersByNodeId[destinationKey] = filters
    }
    if let entries = tab.graph?.customPeopleByNodeId[sourceKey] {
        tab.graph?.customPeopleByNodeId[destinationKey] = entries.map {
            DashboardGraph.CustomPeopleEntry(position: $0.position, name: $0.name, teamName: $0.teamName)
        }
    }
}
private func handleNodeTapSelect(_ nodeId: UUID) {
    #if os(macOS)
    focusGraphSurface()
    #else
    graphIsFocused = true
    #endif
    #if os(macOS)
    let flags = NSEvent.modifierFlags
    let isShift = flags.contains(.shift)
    #else
    let isShift = false
    #endif

    if isShift {
        if selectedGraphNodeIds.contains(nodeId) {
            selectedGraphNodeIds.remove(nodeId)
        } else {
            selectedGraphNodeIds.insert(nodeId)
        }
    } else {
        selectedGraphNodeIds = [nodeId]
    }
}

private func selectAllVisibleGraphNodes() {
    #if os(macOS)
    focusGraphSurface()
    #else
    graphIsFocused = true
    #endif
    selectedGraphNodeIds = Set(allVisibleGraphNodeIds)
}

private var hiddenGraphNodeIds: Set<UUID> {
    Set(tab.graph?.hiddenNodeIds ?? [])
}

private func updateHiddenNodesFlag() {
    GraphDashboardPersistenceAdapter.setHasHiddenNodesFlag(!hiddenGraphNodeIds.isEmpty)
}

private func toggleHiddenForSelectedGraphNodes() {
    guard !selectedGraphNodeIds.isEmpty else { return }
    if tab.graph == nil { tab.graph = DashboardGraph() }

    let currentHidden = hiddenGraphNodeIds
    let shouldHide = selectedGraphNodeIds.contains { !currentHidden.contains($0) }

    registerGraphUndo(actionName: shouldHide ? "Hide Nodes" : "Show Nodes", before: snapshotGraphForUndo())

    var updatedHidden = currentHidden
    if shouldHide {
        updatedHidden.formUnion(selectedGraphNodeIds)
        selectedGraphNodeIds.removeAll()
    } else {
        updatedHidden.subtract(selectedGraphNodeIds)
    }

    tab.graph?.hiddenNodeIds = Array(updatedHidden)
    updateHiddenNodesFlag()
}

private func unhideAllGraphNodes() {
    guard let graph = tab.graph, !graph.hiddenNodeIds.isEmpty else { return }
    registerGraphUndo(actionName: "Show Hidden Nodes", before: snapshotGraphForUndo())
    tab.graph?.hiddenNodeIds = []
    updateHiddenNodesFlag()
}

// Basic pan/zoom can come later; leave at identity for now.
@State private var pan: CGSize = .zero
@State private var zoom: CGFloat = 1.0

// Node width constants for consistent layout and link offsets
private let senderNodeWidth: CGFloat = 420
private let consoleNodeWidth: CGFloat = 380

@AppStorage("relay.graph.forceDetailedNodeRendering")
private var forceDetailedNodeRendering: Bool = false
@State private var showGraphPerformanceNoticeDetails: Bool = false

// Read live mode directly from storage so node simplification is always
// current regardless of how isLiveMode is threaded from the parent.
@AppStorage("dashboard_live_mode_enabled")
private var liveModeFromStorage: Bool = false

private var graphNodeCountForPerformanceMode: Int {
    let canvasCount = cachedModuleGroups.filter(\.isCanvasBacked).count
    let graphCount = tab.graph?.moduleGroupNodeInstances.count ?? 0
    return canvasCount + graphCount
}

private var shouldUseGraphNodePerformanceMode: Bool {
    graphNodeCountForPerformanceMode >= 18
}

private var isGraphSimplifiedModeActive: Bool {
    shouldUseGraphNodePerformanceMode
}

private var showGraphPerformanceNotice: Bool {
    shouldUseGraphNodePerformanceMode
}

private func shouldRenderDetailedGraphNode(_ nodeId: UUID) -> Bool {
    guard isGraphSimplifiedModeActive else { return true }
    if selectedGraphNodeIds.contains(nodeId) { return true }
    if linkingFromNodeId == nodeId { return true }
    if hoverReceiverNodeId == nodeId || hoverInvalidReceiverNodeId == nodeId { return true }
    return false
}

private func graphNodeSummaryIcon(for key: String) -> String {
    if key == DashboardGraph.buttonTriggerGroupKey { return "button.programmable" }
    if key.hasPrefix("source.console") { return "text.line.first.and.arrowtriangle.forward" }
    if key.hasPrefix("source.wireless") { return "antenna.radiowaves.left.and.right" }
    if key.hasPrefix("source.") { return "arrow.down.circle.fill" }
    if key.hasPrefix("destination.") { return "arrow.up.circle.fill" }
    if key.hasPrefix("moduleGroup.person") { return "person.2.fill" }
    if key.hasPrefix("moduleGroup.pco") { return "list.bullet.rectangle.portrait" }
    if key.hasPrefix("moduleGroup.") { return "square.stack.3d.up.fill" }
    if key.hasPrefix("utility.variable") { return "number.square.fill" }
    if key.hasPrefix("utility.") { return "switch.2" }
    return "circle.grid.2x2.fill"
}

private func graphNodeSummarySubtitle(for key: String) -> String {
    if key == DashboardGraph.buttonTriggerGroupKey { return "Canvas Button Trigger" }
    if key == "utility.variable" { return "Variable" }
    if key == "source.consoleImport" { return "Console Import Source" }
    if key == "source.wirelessImport" { return "Wireless Import Source" }
    if key == "moduleGroup.person" { return "People Group" }
    if key == "moduleGroup.pco" { return "Planning Center" }
    if key.hasPrefix("moduleGroup.") { return "Canvas Group" }
    if key.hasPrefix("source.") { return "Source" }
    if key.hasPrefix("destination.") { return "Destination" }
    if key.hasPrefix("action.") { return "Action" }
    if key.hasPrefix("utility.") { return "Utility" }
    return key
}

private func graphNodeSummaryDetailText(
    nodeId: UUID,
    key: String,
    syntheticGroup: ModuleGroup
) -> String {
    let memberCount = syntheticGroup.members.count
    if memberCount > 0 {
        return "\(memberCount) linked item\(memberCount == 1 ? "" : "s")"
    }

    guard let graph = tab.graph else { return "No linked items" }
    let nodePort = "node:\(nodeId.uuidString)"
    let enabledLinks = graph.links.filter(\.isEnabled)
    let inboundCount = enabledLinks.filter { link in
        link.toTileId == nodeId || link.toPortId == nodePort
    }.count
    let outboundCount = enabledLinks.filter { link in
        link.fromTileId == nodeId || link.fromPortId == nodePort
    }.count

    if inboundCount == 0 && outboundCount == 0 {
        return "No linked items"
    }

    if key == "utility.variable" {
        var parts: [String] = []
        if inboundCount > 0 {
            parts.append("\(inboundCount) input link\(inboundCount == 1 ? "" : "s")")
        }
        if outboundCount > 0 {
            parts.append("\(outboundCount) output link\(outboundCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " • ")
    }

    let totalLinks = inboundCount + outboundCount
    return "\(totalLinks) linked connection\(totalLinks == 1 ? "" : "s")"
}

private var graphPerformanceNoticeButton: some View {
    Button {
        showGraphPerformanceNoticeDetails.toggle()
    } label: {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.yellow)
            .padding(8)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.64))
            )
            .overlay(
                Circle().stroke(Color.yellow.opacity(0.45), lineWidth: 1)
            )
    }
    .buttonStyle(.plain)
    .help("Automation performance mode")
    .popover(isPresented: $showGraphPerformanceNoticeDetails, arrowEdge: .top) {
        VStack(alignment: .leading, spacing: 10) {
            Text("Large automation graph")
                .font(.headline)

            Text("To keep editing responsive, Relay can simplify unselected node cards when many nodes are visible.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(isGraphSimplifiedModeActive
                 ? "Simplified node cards are currently enabled."
                 : "Full node details are currently enabled. Responsiveness may decrease on very large graphs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Show full node details", isOn: $forceDetailedNodeRendering)

            Text("Selected or actively linked nodes still expand for editing when simplification is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 360)
    }
}

private func graphNodeSummaryCard(
    title: String,
    subtitle: String,
    systemImage: String,
    accent: Color,
    width: CGFloat,
    detail: String? = nil
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius, style: .continuous)
                    .fill(accent.opacity(0.18))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }

        if let detail, !detail.isEmpty {
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(2)
        }
    }
    .padding(12)
    .frame(width: width, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.07))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(accent.opacity(0.22), lineWidth: 1)
    )
}

private func recordGraphNodeMount(kind: String, detailed: Bool) {
    RelayDiagnosticsStore.shared.incrementCounter("ui.graph.nodeMount")
    RelayDiagnosticsStore.shared.incrementCounter("ui.graph.nodeMount.\(detailed ? "detailed" : "summary")")
    RelayDiagnosticsStore.shared.incrementCounter("ui.graph.nodeMount.kind.\(kind).\(detailed ? "detailed" : "summary")")
}

private func recordGraphLayerPreparation(
    key: String,
    duration: TimeInterval,
    details: String
) {
    RelayDiagnosticsStore.shared.recordPerformanceMetric(
        key,
        duration: duration,
        details: details,
        slowThreshold: 0.010
    )
}

// MARK: - PCO Rundown Snapshot Titles (captured)

/// Prefer the live tab snapshot titles when present so Automation can react to
/// Planning Center changes without forcing a mode switch. Fall back to the
/// caller-provided captured snapshot, then reflection-based extraction.
private var resolvedPCORundownSnapshotTitles: [String] {
    // Sanitize to avoid accidentally treating unrelated UI labels as rundown items.

    // 1) Prefer the live tab snapshot when available.
    if !tab.pcoRundownSnapshotTitles.isEmpty {
        return sanitizeRundownTitles(tab.pcoRundownSnapshotTitles)
    }

    // 2) Fall back to the explicit snapshot passed in from the caller.
    if !pcoRundownSnapshotTitles.isEmpty {
        return sanitizeRundownTitles(pcoRundownSnapshotTitles)
    }

    // 3) If the tab has a directly stored string array snapshot, use it.
    if let direct = GraphReflectionAdapter.reflectedStringArray(from: tab, keys: [
        "pcoRundownSnapshotTitles",
        "rundownSnapshotTitles",
        "capturedRundownTitles"
    ]), !direct.isEmpty {
        return sanitizeRundownTitles(direct)
    }

    // 4) Best-effort: try to extract titles from common PCO order/rundown collections on the tab.
    if let any = GraphReflectionAdapter.reflectedAny(from: tab, keys: [
        "pcoRundownItems",
        "pcoRundownRows",
        "pcoServiceOrder",
        "pcoServiceOrderItems",
        "pcoOrder",
        "pcoOrderItems",
        "serviceOrder",
        "serviceOrderItems",
        "rundownItems",
        "rundownRows"
    ]) {
        let extracted = GraphReflectionAdapter.extractTitlesAndKeys(fromArrayAny: any)
        if !extracted.isEmpty {
            let packed: [String] = extracted.map { pair in
                let t = pair.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let k = pair.key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return k.isEmpty ? t : (t + "\n__KEY__:" + k)
            }
            return sanitizeRundownTitles(packed)
        }

        // Fallback: titles only
        let extractedTitles = GraphReflectionAdapter.extractTitles(fromArrayAny: any)
        if !extractedTitles.isEmpty {
            return sanitizeRundownTitles(extractedTitles)
        }
    }

    return []
}

private func graphPeopleLabelsForSendAll() -> [String] {
    let groups = computedModuleGroups()
    let canvasPeopleMembers = computedCanvasPeopleMembers(groups: groups)
    let synthesizedPeopleMembers = canvasPeopleMembers.isEmpty ? cachedSynthesizedPeopleMembersFromPCO : []
    let allPeopleMembers: [ModuleMember] = !canvasPeopleMembers.isEmpty
        ? canvasPeopleMembers
        : synthesizedPeopleMembers
    return allPeopleMembers
        .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}


private func installSendAllListenerIfNeeded() -> Bool {
    guard !didInstallSendAllListenerInGraph else { return false }
    didInstallSendAllListenerInGraph = true

    GraphActionExecutor.installSendAllToConsolesListener(
        snapshotDevicesProvider: {
            ExternalDevicesStore.shared.currentSnapshot().devices.map { $0 as Any }
        },
        rundownTitlesProvider: {
            resolvedPCORundownSnapshotTitles
        },
        peopleLabelsProvider: {
            graphPeopleLabelsForSendAll()
        },
        linkedConsoleIdsProvider: nil,
        pcoRundownLinkedConsoleIdsProvider: nil,
        rundownTitlesForConsoleProvider: { consoleId in
            let consoleNodeId = firstConsoleNodeId(forDeviceId: consoleId)
                ?? graphNodeId(forExternalDeviceId: consoleId)
            let groups = computedModuleGroups()
            let linked = isPCORundownLinked(toConsoleNodeId: consoleNodeId)
            return linked ? packedRundownSnapshotTitles(forConsoleNodeId: consoleNodeId, currentGroups: groups) : []
        },
        log: { _ in }
    )

    return true
}

private func refreshSendAllListenerForGraphChange() {
    didInstallSendAllListenerInGraph = false
    GraphActionExecutor.resetSendAllListener()
    _ = installSendAllListenerIfNeeded()
}

private func sanitizeRundownTitles(_ raw: [String]) -> [String] {
    // Remove empties, obvious non-rundown labels, and de-dup adjacent duplicates.
    // This prevents strings like tab names ("Tab 1"), generic "Tile"/"Person" labels,
    // or person assignment labels ("Soprano 1 — Beth") from being treated as snapshot titles.
    //
    // Supports packed key form: "Title\n__KEY__:A". Sanitization filters by the base title,
    // but preserves the packed key in the returned value.

    func unpack(_ s: String) -> (title: String, key: String?, raw: String) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let payload = VistaPCORundownPayloadCodec.decode(from: trimmed) {
            return (payload.title, payload.keyName, trimmed)
        }
        if let r = trimmed.range(of: "\n__KEY__:") {
            let t = String(trimmed[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let kRaw = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let k = kRaw.isEmpty ? nil : kRaw
            return (t, k, trimmed)
        }
        return (trimmed, nil, trimmed)
    }

    func repack(title: String, key: String?) -> String {
        guard let key, !key.isEmpty else { return title }
        return title + "\n__KEY__:" + key
    }

    let bannedExact: Set<String> = Set(
        [
            "tile", "tiles",
            "person", "people",
            "planning center",
            "pco",
            "tab", "tab 1", "tab 2",
            tab.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
    )

    let unpacked: [(title: String, key: String?, raw: String)] = raw
        .map { unpack($0) }
        .map {
            (
                title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                key: $0.key?.trimmingCharacters(in: .whitespacesAndNewlines),
                raw: $0.raw
            )
        }
        .filter { !$0.title.isEmpty }
        .filter { !bannedExact.contains($0.title.lowercased()) }
        // Exclude person-style labels like "Role — Name" which are not rundown items.
        .filter { !$0.title.contains(" — ") }

    guard !unpacked.isEmpty else { return [] }

    var result: [String] = []
    result.reserveCapacity(unpacked.count)

    var lastTitle: String? = nil
    var lastKey: String? = nil
    for item in unpacked {
        // De-dup adjacent duplicates by (title,key)
        if lastTitle == item.title, lastKey == item.key {
            continue
        }
        lastTitle = item.title
        lastKey = item.key
        if VistaPCORundownPayloadCodec.decode(from: item.raw) != nil {
            result.append(item.raw)
        } else {
            result.append(repack(title: item.title, key: item.key))
        }
    }
    return result
}

// MARK: - Graph-only Add Node (module-group nodes)

private struct AddableGroup: Identifiable {
    let id: String   // key
    let title: String
    let systemImage: String
    let category: String
    let subtitle: String
    let isEnabled: Bool
    var isBeta: Bool = false
    var requiresPro: Bool = false
}

private struct DestinationPickerOption: Identifiable {
    let id: UUID
    let title: String
}

private struct DestinationPickerState: Identifiable {
    let id = UUID()
    let groupKey: String
    let title: String
    let options: [DestinationPickerOption]
}

private var availableAudioConsoleDevices: [ExternalDeviceConfig] {
    externalDevicesSnapshot.filter { $0.kind == .audioConsole }
}

private var availableShureDevices: [ExternalDeviceConfig] {
    externalDevicesSnapshot.filter { $0.kind == .shureWireless }
}

private var availableSennheiserDevices: [ExternalDeviceConfig] {
    externalDevicesSnapshot.filter { $0.kind == .sennheiserWireless }
}

private var availableShureDestinationDevices: [ExternalDeviceConfig] {
    availableShureDevices.filter { $0.shureSupportsDestinationCommands }
}

    private var availableSennheiserDestinationDevices: [ExternalDeviceConfig] {
        availableSennheiserDevices.filter { $0.sennheiserSupportsDestinationCommands }
    }

private var addableGroups: [AddableGroup] {
    let sortedLANPeers = lanPeers.sorted {
        ($0.deviceName ?? $0.endpointKey).localizedCaseInsensitiveCompare($1.deviceName ?? $1.endpointKey) == .orderedAscending
    }
    let groups = [
        AddableGroup(
            id: "action.notify",
            title: "Show Notification",
            systemImage: "bell.fill",
            category: "Actions",
            subtitle: "Post an in-app notification",
            isEnabled: true
        ),
        AddableGroup(
            id: "action.lanNotify",
            title: "Send LAN Notification",
            systemImage: "wifi",
            category: "Actions",
            subtitle: sortedLANPeers.isEmpty ? "Send a notification to Relay peers on LAN" : "Send a notification to a Relay peer",
            isEnabled: lanNotificationsEnabled
        ),
        AddableGroup(
            id: "action.appControl",
            title: "In-App Action",
            systemImage: "macwindow.on.rectangle",
            category: "Actions",
            subtitle: "Switch tabs, toggle modes, refresh PCO, and save",
            isEnabled: true
        ),
        AddableGroup(
            id: "action.smartLightControl",
            title: "Smart Light Control",
            systemImage: "lightbulb.2",
            category: "Actions",
            subtitle: "Control Philips Hue, Govee, and future light providers",
            isEnabled: SmartLightFeatureFlags.isEnabled,
            isBeta: true,
            requiresPro: true
        ),
        AddableGroup(
            id: "action.midiSend",
            title: "MIDI Send",
            systemImage: "pianokeys",
            category: "Actions",
            subtitle: "Send a MIDI note, CC, PC, or SysEx message",
            isEnabled: true
        ),
        AddableGroup(
            id: "action.oscSend",
            title: "OSC Send",
            systemImage: "paperplane",
            category: "Actions",
            subtitle: "Send a custom OSC message",
            isEnabled: true
        ),
        AddableGroup(
            id: "action.httpRequest",
            title: "HTTP Request",
            systemImage: "network",
            category: "Actions",
            subtitle: "Send a GET, POST, or other HTTP request to any URL",
            isEnabled: true
        ),
        AddableGroup(
            id: "action.setVariable",
            title: "Set Variable",
            systemImage: "equal.square.fill",
            category: "Actions",
            subtitle: "Set a Variable node to a fixed value",
            isEnabled: isGraphVariablesFeatureEnabled
        ),
        AddableGroup(
            id: "action.proPresenterTrigger",
            title: "ProPresenter",
            systemImage: "play.rectangle.on.rectangle",
            category: "Destinations",
            subtitle: "Trigger a ProPresenter action",
            isEnabled: true
        ),
        AddableGroup(
            id: "destination.console",
            title: "Console",
            systemImage: "slider.horizontal.3",
            category: "Destinations",
            subtitle: "Send assignments, snapshots, and cues to a console",
            isEnabled: !availableAudioConsoleDevices.isEmpty
        ),
        AddableGroup(
            id: "destination.vista",
            title: "Vista",
            systemImage: "light.beacon.max",
            category: "Destinations",
            subtitle: "Export cue lists and trigger basic Vista OSC commands",
            isEnabled: isVistaIntegrationEnabled && !availableVistaDestinationDevices.isEmpty,
            isBeta: true
        ),
        AddableGroup(
            id: "action.shureSend",
            title: "Shure Wireless",
            systemImage: "dot.radiowaves.left.and.right",
            category: "Destinations",
            subtitle: "Send commands to Shure receivers",
            isEnabled: !availableShureDestinationDevices.isEmpty
        ),
        AddableGroup(
            id: "action.sennheiserSend",
            title: "Sennheiser Wireless",
            systemImage: "dot.radiowaves.left.and.right",
            category: "Destinations",
            subtitle: "Send commands to Sennheiser receivers",
            isEnabled: !availableSennheiserDestinationDevices.isEmpty
        ),
        AddableGroup(
            id: "action.sendAllConsoles",
            title: "Send to All Consoles",
            systemImage: "bolt.fill",
            category: "Actions",
            subtitle: "Fire Send All (assignments/snapshots) across every console",
            isEnabled: true
        ),
        AddableGroup(
            id: "utility.repeater",
            title: "Repeater",
            systemImage: "repeat",
            category: "Utility",
            subtitle: "Repeat downstream actions with a delay",
            isEnabled: true
        ),
        AddableGroup(
            id: "utility.delay",
            title: "Delay",
            systemImage: "clock.arrow.circlepath",
            category: "Utility",
            subtitle: "Pause a trigger before continuing",
            isEnabled: true
        ),
        AddableGroup(
            id: "utility.merge",
            title: "Merge",
            systemImage: "arrow.triangle.merge",
            category: "Utility",
            subtitle: "Combine multiple trigger inputs into a single output",
            isEnabled: true
        ),
        AddableGroup(
            id: "utility.toggle",
            title: "Toggle",
            systemImage: "switch.2",
            category: "Utility",
            subtitle: "Alternates between two outputs on each trigger fire",
            isEnabled: true
        ),
        AddableGroup(
            id: "utility.counter",
            title: "Counter",
            systemImage: "number.square",
            category: "Utility",
            subtitle: "Fire downstream only after receiving N triggers",
            isEnabled: true
        ),
        AddableGroup(
            id: "utility.sequence",
            title: "Sequence",
            systemImage: "list.number",
            category: "Utility",
            subtitle: "Cycle through outputs in order on each trigger fire",
            isEnabled: true
        ),
        AddableGroup(
            id: "utility.latch",
            title: "Latch / Gate",
            systemImage: "lock.open",
            category: "Utility",
            subtitle: "Block or allow triggers based on an enabled/disabled state",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.midiReceive",
            title: "MIDI Receive",
            systemImage: "pianokeys",
            category: "Triggers",
            subtitle: "Receive MIDI Program Change to trigger automations",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.oscReceive",
            title: "OSC Receive",
            systemImage: "dot.radiowaves.left.and.right",
            category: "Triggers",
            subtitle: "Receive OSC to trigger automations",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.sennheiser",
            title: "Sennheiser Wireless",
            systemImage: "music.microphone",
            category: "Triggers",
            subtitle: "Wireless status triggers",
            isEnabled: !availableSennheiserDevices.isEmpty
        ),
        AddableGroup(
            id: "moduleGroup.shure",
            title: "Shure Wireless",
            systemImage: "music.microphone",
            category: "Triggers",
            subtitle: "Wireless status triggers",
            isEnabled: !availableShureDevices.isEmpty
        ),
        AddableGroup(
            id: "moduleGroup.time",
            title: "Time",
            systemImage: "clock",
            category: "Triggers",
            subtitle: "Time-based triggers",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.dbThreshold",
            title: "dB Threshold",
            systemImage: "speaker.wave.2.fill",
            category: "Triggers",
            subtitle: "Trigger events when a SPL Meter crosses a threshold",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.manualTrigger",
            title: "Manual Trigger",
            systemImage: "hand.tap",
            category: "Triggers",
            subtitle: "Tap a button to fire a trigger event",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.keystrokeTrigger",
            title: "Keystroke Trigger",
            systemImage: "keyboard",
            category: "Triggers",
            subtitle: "Trigger automations from Relay keyboard shortcuts",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.pcoItemChanged",
            title: "PCO Plan Updated",
            systemImage: "arrow.triangle.2.circlepath",
            category: "Triggers",
            subtitle: "Fire when the Planning Center service plan is loaded or refreshed",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.proPresenterTrigger",
            title: "ProPresenter State",
            systemImage: "tv",
            category: "Triggers",
            subtitle: "Fire when the current slide, presentation, message, or timer changes in ProPresenter",
            isEnabled: isProPresenterTriggerFeatureEnabled,
            isBeta: true
        ),
        AddableGroup(
            id: "moduleGroup.appState",
            title: "App State",
            systemImage: "app.badge",
            category: "Triggers",
            subtitle: "Fire on app launch, live mode changes, or tab switches",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.transcription",
            title: "Word Trigger",
            systemImage: "text.bubble.fill",
            category: "Triggers",
            subtitle: "Trigger events based on filtered words from Canvas Live Transcription module",
            isEnabled: false
        ),
        AddableGroup(
            id: "moduleGroup.pco",
            title: "Planning Center",
            systemImage: "list.bullet.rectangle",
            category: "Sources",
            subtitle: "Service plan, items, schedule, and LIVE",
            isEnabled: true
        ),
        AddableGroup(
            id: "moduleGroup.person",
            title: "People",
            systemImage: "person.3.fill",
            category: "Sources",
            subtitle: "Team members and assignments",
            isEnabled: true
        ),
        AddableGroup(
            id: "source.roster",
            title: "Roster Value",
            systemImage: "tablecells",
            category: "Sources",
            subtitle: "Use a value from the tab roster",
            isEnabled: true
        ),
        AddableGroup(
            id: "source.consoleImport",
            title: "Console Channel Name",
            systemImage: "slider.horizontal.3",
            category: "Sources",
            subtitle: "Use a synced/imported console channel name",
            isEnabled: !availableAudioConsoleDevices.isEmpty
        ),
        AddableGroup(
            id: "source.wirelessImport",
            title: "Wireless Channel Name",
            systemImage: "dot.radiowaves.left.and.right",
            category: "Sources",
            subtitle: "Use a cached wireless channel name",
            isEnabled: !availableShureDevices.isEmpty || !availableSennheiserDevices.isEmpty
        ),
        AddableGroup(
            id: "source.staticLabel",
            title: "Static Label",
            systemImage: "tag.fill",
            category: "Sources",
            subtitle: "Use a fixed text label",
            isEnabled: true
        ),
        AddableGroup(
            id: "source.currentTime",
            title: "Current Time",
            systemImage: "clock.fill",
            category: "Sources",
            subtitle: "Provides the current time of day as text or a number",
            isEnabled: true
        )
    ]

    var allGroups = groups

    if isGraphConditionalsFeatureEnabled {
        allGroups.append(
            AddableGroup(
                id: "utility.condition",
                title: "If / Else",
                systemImage: "arrow.triangle.branch",
                category: "Utility",
                subtitle: "Branch flow using payload or variable values",
                isEnabled: true,
                isBeta: true
            )
        )
    }

    if isGraphVariablesFeatureEnabled {
        allGroups.append(
            AddableGroup(
                id: "utility.variable",
                title: "Variable",
                systemImage: "textformat.alt",
                category: "Utility",
                subtitle: "Store a text, number, or boolean value for reuse",
                isEnabled: true
            )
        )
    }

    if !isVistaIntegrationEnabled {
        allGroups.removeAll { $0.id == "destination.vista" }
    }

    return allGroups.sorted { lhs, rhs in
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private func groupTitle(for key: String) -> String {
    if key == "utility.condition" {
        return "If / Else"
    }
    if key == "utility.variable" {
        return "Variable"
    }
    if key == DashboardGraph.buttonTriggerGroupKey {
        return "Canvas Button"
    }
    return addableGroups.first(where: { $0.id == key })?.title ?? key
}

/// Looks up the live label of an auto-mirrored canvas Button node by its module id.
/// Falls back to "Canvas Button" if the source tile no longer exists.
private func resolveCanvasButtonTitle(forButtonModuleId moduleId: UUID) -> String {
    for tile in tab.tiles {
        guard let modules = tile.modules else { continue }
        for module in modules {
            if case .button(let buttonModel) = module.kind, buttonModel.id == moduleId {
                if buttonModel.buttons.count == 1 {
                    let trimmed = buttonModel.buttons[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "Canvas Button" : trimmed
                } else {
                    // For multi-button: use tile name, or first button + count
                    let tileName = tile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !tileName.isEmpty { return tileName }
                    let first = buttonModel.buttons[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return first.isEmpty ? "Button Group (\(buttonModel.buttons.count))" : "\(first) +\(buttonModel.buttons.count - 1)"
                }
            }
        }
    }
    return "Canvas Button"
}

private func resolveCanvasButtonLabel(forButtonConfigId configId: UUID, inNodeId nodeId: UUID) -> String {
    for tile in tab.tiles {
        guard let modules = tile.modules else { continue }
        for module in modules {
            if case .button(let buttonModel) = module.kind, buttonModel.id == nodeId {
                if let config = buttonModel.buttons.first(where: { $0.id == configId }) {
                    let trimmed = config.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "Button" : trimmed
                }
            }
        }
    }
    return "Button"
}

/// Returns the button configs for a multi-button canvas node (when count > 1), or empty array otherwise.
private func buttonsForButtonNode(_ nodeId: UUID) -> [ButtonConfig] {
    for tile in tab.tiles {
        guard let modules = tile.modules else { continue }
        for module in modules {
            if case .button(let buttonModel) = module.kind, buttonModel.id == nodeId {
                return buttonModel.buttons
            }
        }
    }
    return []
}

private func isMultiButtonNodeId(_ nodeId: UUID) -> Bool {
    buttonsForButtonNode(nodeId).count > 1
}

private func enableModuleGroupNode(_ key: String, canvasSize: CGSize) {
    guard key != "utility.condition" || isGraphConditionalsFeatureEnabled else { return }
    guard key != "utility.variable" || isGraphVariablesFeatureEnabled else { return }
    if tab.graph == nil { tab.graph = DashboardGraph() }
    guard tab.graph != nil else { return }

    let inst = DashboardGraph.ModuleGroupNodeInstance(groupKey: key)
    tab.graph?.moduleGroupNodeInstances.append(inst)

    ensureLayoutForModuleGroupNode(inst.id, groupKey: key)

    refreshGraphCaches()

    // If the new node landed outside the current viewport, zoom/pan to reveal it.
    revealNodeIfNeeded(nodeId: inst.id, viewSize: canvasSize)
}

private func enableConsoleDestinationNode(device: ExternalDeviceConfig, canvasSize: CGSize) {
    if tab.graph == nil { tab.graph = DashboardGraph() }
    guard tab.graph != nil else { return }

    // Use a fresh UUID per instance so the same device can have multiple nodes.
    let inst = DashboardGraph.ModuleGroupNodeInstance(groupKey: "destination.console")
    tab.graph?.moduleGroupNodeInstances.append(inst)
    tab.graph?.consoleDeviceIdByNodeId[inst.id.uuidString] = device.id

    ensureLayoutForConsoleNode(inst.id, device: device)

    refreshGraphCaches()

    revealNodeIfNeeded(nodeId: inst.id, viewSize: canvasSize)
}

private func enableVistaDestinationNode(device: ExternalDeviceConfig, canvasSize: CGSize) {
    if tab.graph == nil { tab.graph = DashboardGraph() }
    guard tab.graph != nil else { return }

    let nodeId = graphNodeId(forExternalDeviceId: device.id)
    if tab.graph?.moduleGroupNodeInstances.contains(where: { $0.id == nodeId }) == true {
        addNodeHelpMessage = addNodeHelp(
            title: "Vista Console Already Added",
            message: "This Vista destination node is already on the automation canvas."
        )
        return
    }

    let inst = DashboardGraph.ModuleGroupNodeInstance(id: nodeId, groupKey: "destination.vista")
    tab.graph?.moduleGroupNodeInstances.append(inst)

    let target = device.vistaConsoleTarget?.trimmingCharacters(in: .whitespacesAndNewlines)
    tab.graph?.vistaNodeConfigByNodeId[nodeId.uuidString] = DashboardGraph.VistaNodeConfig(
        id: nodeId,
        selectedDeviceID: device.id,
        externalDeviceConfig: DashboardGraph.VistaExternalDeviceConfig(
            id: device.id,
            displayName: device.name,
            host: device.host,
            oscPort: device.port,
            consoleTarget: (target?.isEmpty == false ? target! : "EX1"),
            isEnabled: device.isEnabled
        )
    )

    ensureLayoutForModuleGroupNode(nodeId, groupKey: "destination.vista")
    refreshGraphCaches()
    revealNodeIfNeeded(nodeId: nodeId, viewSize: canvasSize)
}

private func enableWirelessDestinationNode(groupKey: String, deviceId: UUID, canvasSize: CGSize) {
    if tab.graph == nil { tab.graph = DashboardGraph() }
    guard tab.graph != nil else { return }

    let inst = DashboardGraph.ModuleGroupNodeInstance(groupKey: groupKey)
    tab.graph?.moduleGroupNodeInstances.append(inst)

    var cfg = DashboardGraph.WirelessTriggerConfig()
    cfg.deviceID = deviceId
    if groupKey == "moduleGroup.shure" {
        tab.graph?.shureTriggerConfigByNodeId[inst.id.uuidString] = cfg
    } else if groupKey == "moduleGroup.sennheiser" {
        tab.graph?.sennheiserTriggerConfigByNodeId[inst.id.uuidString] = cfg
    }

    ensureLayoutForModuleGroupNode(inst.id, groupKey: groupKey)

    refreshGraphCaches()

    // If the new node landed outside the current viewport, zoom/pan to reveal it.
    revealNodeIfNeeded(nodeId: inst.id, viewSize: canvasSize)
}

private func handleDestinationSelection(groupKey: String, deviceId: UUID, canvasSize: CGSize) {
    addNodeHelpMessage = nil
    if groupKey == "destination.console" {
        guard let device = availableAudioConsoleDevices.first(where: { $0.id == deviceId }) else {
            addNodeHelpMessage = addNodeHelp(
                title: "Console Unavailable",
                message: "That console could not be found. Refresh Connections and try again."
            )
            return
        }
        enableConsoleDestinationNode(device: device, canvasSize: canvasSize)
    } else if groupKey == "destination.vista" {
        guard let device = availableVistaDestinationDevices.first(where: { $0.id == deviceId }) else {
            addNodeHelpMessage = addNodeHelp(
                title: "Vista Console Unavailable",
                message: "That Vista console could not be found. Refresh Connections and try again."
            )
            return
        }
        enableVistaDestinationNode(device: device, canvasSize: canvasSize)
    } else if groupKey == "moduleGroup.shure" || groupKey == "moduleGroup.sennheiser" {
        enableWirelessDestinationNode(groupKey: groupKey, deviceId: deviceId, canvasSize: canvasSize)
    }

    addNodeSearchText = ""
    showAddNodePopover = false
    destinationPickerState = nil
}

private func handleAddNodeSelection(_ group: AddableGroup, canvasSize: CGSize) {
    if !group.isEnabled {
        addNodeHelpMessage = unavailableAddNodeHelp(for: group)
        return
    }
    if group.requiresPro && !subscriptionManager.hasPro {
        addNodeHelpMessage = addNodeHelp(
            title: "Pro Required",
            message: "Smart Light Control is a Relay Pro feature. Upgrade to Pro to add this node."
        )
        return
    }

    if group.id == "destination.console" {
        let options = availableAudioConsoleDevices
            .map { DestinationPickerOption(id: $0.id, title: $0.name) }
        destinationPickerState = DestinationPickerState(
            groupKey: group.id,
            title: "Select Console",
            options: options
        )
        return
    }

    if group.id == "destination.vista" {
        let options = availableVistaDestinationDevices
            .map { DestinationPickerOption(id: $0.id, title: $0.name) }
        destinationPickerState = DestinationPickerState(
            groupKey: group.id,
            title: "Select Vista Console",
            options: options
        )
        return
    }

    if group.id == "moduleGroup.shure" {
        let options = availableShureDevices
            .map { DestinationPickerOption(id: $0.id, title: $0.name) }
        destinationPickerState = DestinationPickerState(
            groupKey: group.id,
            title: "Select Shure Device",
            options: options
        )
        return
    }

    if group.id == "moduleGroup.sennheiser" {
        let options = availableSennheiserDevices
            .map { DestinationPickerOption(id: $0.id, title: $0.name) }
        destinationPickerState = DestinationPickerState(
            groupKey: group.id,
            title: "Select Sennheiser Device",
            options: options
        )
        return
    }

    addNodeHelpMessage = nil
    enableModuleGroupNode(group.id, canvasSize: canvasSize)
    refreshGraphCaches()
    addNodeSearchText = ""
    showAddNodePopover = false
}

@ViewBuilder
private func addNodeRow(_ group: AddableGroup, canvasSize: CGSize) -> some View {
    Button {
        handleAddNodeSelection(group, canvasSize: canvasSize)
    } label: {
        addNodeRowLabel(group)
    }
    .buttonStyle(.plain)
    .disabled(false)
}

@ViewBuilder
private func addNodeRowLabel(_ group: AddableGroup) -> some View {
    let tint = addNodeCategoryColor(group.category)
    HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 2)
            .fill(tint.opacity(0.9))
            .frame(width: 4)

        Image(systemName: group.systemImage)
            .imageScale(.medium)
            .opacity(0.9)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(group.title)
                    .font(.subheadline)
                    .opacity(1.0)
                if group.isBeta {
                    BetaBadgeView(fontSize: 9, backgroundOpacity: 0.08, borderOpacity: 0.12)
                }
            }
            Text(group.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()

        if group.requiresPro && !subscriptionManager.hasPro {
            ProBadgeView(fontSize: 9)
        } else if group.isEnabled {
            Image(systemName: "plus")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(0.85)
        } else {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(0.7)
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
            .fill(Color.white.opacity(GraphNodeStyleTokens.subtleFillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                    .fill(tint.opacity(GraphNodeStyleTokens.elevatedFillOpacity))
            )
    )
}

@ViewBuilder
private func addNodeSidebar(categories: [String]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Button { addNodeSelectedCategory = "All" } label: {
            let tint = Color.white.opacity(0.35)
            HStack {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text("All").font(.subheadline)
                Spacer()
                if addNodeSelectedCategory == "All" {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(addNodeSelectedCategory == "All" ? Color.white.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)

        Text("Categories")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)

        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(categories.filter { $0 != "All" }, id: \.self) { cat in
                    Button { addNodeSelectedCategory = cat } label: {
                        let tint = addNodeCategoryColor(cat)
                        HStack {
                            Circle()
                                .fill(tint)
                                .frame(width: 6, height: 6)
                            Text(cat).font(.subheadline)
                            Spacer()
                            if addNodeSelectedCategory == cat {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(addNodeSelectedCategory == cat ? Color.white.opacity(0.08) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }

        Spacer(minLength: 0)
    }
    .frame(width: 200)
    .padding(.top, 10)
    .padding(.bottom, 10)
    .padding(.leading, 12)
    .padding(.trailing, 8)
}

private func addNodeCategoryColor(_ category: String) -> Color {
    GraphNodeCategory(categoryLabel: category).menuColor
}

@ViewBuilder
private func addNodeCandidatesList(candidates: [AddableGroup], query: String, canvasSize: CGSize) -> some View {
    VStack(spacing: 0) {
        HStack {
            Text(addNodeSelectedCategory == "All" ? "Available" : addNodeSelectedCategory)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if candidates.isEmpty {
                    Text(query.isEmpty ? "No nodes available" : "No matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(16)
                } else {
                    ForEach(candidates) { g in
                        addNodeRow(g, canvasSize: canvasSize)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.top, 2)
}

private func removeGraphOnlyModuleGroupNodeInstance(nodeId: UUID) {
    // Protect canvas-backed stable nodes.
    let computed = computedModuleGroups()
    let canvasKeys = Set(computed.filter { $0.isCanvasBacked }.map { $0.key })
    for key in canvasKeys {
        if groupNodeId(for: key) == nodeId { return }
    }

    // Protect auto-mirrored canvas Button trigger nodes — they only go away when
    // their backing canvas Button is deleted from the canvas.
    if tab.graph?.moduleGroupNodeInstances.contains(where: { $0.id == nodeId && $0.groupKey == DashboardGraph.buttonTriggerGroupKey }) == true {
        return
    }

    guard tab.graph != nil else { return }

    if let inst = tab.graph?.moduleGroupNodeInstances.first(where: { $0.id == nodeId }) {
        if inst.groupKey == "action.appControl" {
            tab.graph?.appControlActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "action.smartLightControl" {
            tab.graph?.smartLightActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "utility.repeater" {
            tab.graph?.repeaterActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "utility.delay" {
            tab.graph?.delayActionConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "utility.condition" {
            tab.graph?.conditionNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "utility.variable" {
            tab.graph?.variableNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "moduleGroup.keystrokeTrigger" {
            tab.graph?.keystrokeTriggerConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "moduleGroup.wordTrigger" {
            // Only remove if this node still has its own (unmigrated) config entry —
            // never remove the canonical transcription node's shared config.
            let canonicalKey = groupNodeId(for: "moduleGroup.transcription").uuidString
            if nodeId.uuidString != canonicalKey {
                tab.graph?.wordTriggerConfigByNodeId.removeValue(forKey: nodeId.uuidString)
            }
        }
        if inst.groupKey == "destination.console" {
            tab.graph?.quConsoleActionsByNodeId.removeValue(forKey: nodeId.uuidString)
            tab.graph?.digicoConsoleActionsByNodeId.removeValue(forKey: nodeId.uuidString)
            tab.graph?.standardConsoleActionsByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "destination.vista" {
            tab.graph?.vistaNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "source.roster" {
            tab.graph?.rosterSourceConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "source.consoleImport" {
            tab.graph?.consoleLabelSourceConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "source.wirelessImport" {
            tab.graph?.wirelessLabelSourceConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "source.staticLabel" {
            tab.graph?.staticLabelSourceConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }
        if inst.groupKey == "source.currentTime" {
            tab.graph?.currentTimeSourceConfigByNodeId.removeValue(forKey: nodeId.uuidString)
            // Clean up synthetic variable slot (only if it has the synthetic name prefix).
            if let v = tab.graph?.variableNodeConfigByNodeId[nodeId.uuidString],
               v.name.hasPrefix("_currentTime_") {
                tab.graph?.variableNodeConfigByNodeId.removeValue(forKey: nodeId.uuidString)
            }
        }
    }

    tab.graph?.moduleGroupNodeInstances.removeAll(where: { $0.id == nodeId })

    let port = "node:\(nodeId.uuidString)"
    tab.graph?.tileLayouts.removeValue(forKey: nodeId)
    tab.graph?.links.removeAll(where: { $0.fromPortId == port || $0.toPortId == port || $0.fromTileId == nodeId || $0.toTileId == nodeId })
    tab.graph?.nodeIdByPortId = tab.graph?.nodeIdByPortId.filter { $0.value != nodeId } ?? [:]

    if linkingFromNodeId == nodeId {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
    }

    refreshGraphCaches()
}

// MARK: - Manual People Node (Custom People)

private func customPeopleEntries(forNodeId nodeId: UUID) -> [DashboardGraph.CustomPeopleEntry] {
    let key = nodeId.uuidString
    return tab.graph?.customPeopleByNodeId[key] ?? []
}

private func setCustomPeopleEntries(_ entries: [DashboardGraph.CustomPeopleEntry], forNodeId nodeId: UUID) {
    let key = nodeId.uuidString
    commitGraphEdit {
        if tab.graph == nil { tab.graph = DashboardGraph() }
        tab.graph?.customPeopleByNodeId[key] = entries
    }
}

private func customPeopleEntriesBinding(forNodeId nodeId: UUID) -> Binding<[DashboardGraph.CustomPeopleEntry]> {
    Binding<[DashboardGraph.CustomPeopleEntry]>(
        get: { customPeopleEntries(forNodeId: nodeId) },
        set: { setCustomPeopleEntries($0, forNodeId: nodeId) }
    )
}

private func sourceMembers(nodeId: UUID, groupKey: String, graph: DashboardGraph) -> [ModuleMember] {
    guard groupKey.hasPrefix("source.") else { return [] }
    let values = GraphRuntime.resolveTextValues(nodeId: nodeId, portId: "node:\(nodeId.uuidString)", tab: tab)
    var seen = Set<String>()
    return values.compactMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
        return ModuleMember(
            tileId: tab.id,
            moduleId: stableUUID(for: "sourceMember|\(nodeId.uuidString)|\(trimmed)"),
            title: trimmed
        )
    }
}
// MARK: - People members per console (linked sources)

private func peopleMembersForConsoleNode(consoleNodeId: UUID,
                                     canvasPeopleMembers: [ModuleMember]) -> [ModuleMember] {
// If there is no graph yet, fall back to canvas members (legacy behavior).
guard let graph = tab.graph else { return canvasPeopleMembers }

let toPort = "node:\(consoleNodeId.uuidString)"
let canvasPeopleNodeId = groupNodeId(for: "moduleGroup.person")
let canvasFromPort = "node:\(canvasPeopleNodeId.uuidString)"

// Fast-path: if the canvas-backed People node is linked to this console, ALWAYS use the canvas list
let canvasLinked = graph.links.contains { link in
    link.isEnabled &&
    (link.fromPortId == canvasFromPort || link.fromTileId == canvasPeopleNodeId) &&
    (link.toPortId == toPort || link.toTileId == consoleNodeId)
}

if canvasLinked {
    return applyTeamFilter(canvasPeopleMembers, nodeId: canvasPeopleNodeId, graph: graph)
}
// Support both modern port-id links (node:<UUID>) and older links that only set tile ids.
let linkedFromNodeIds: [UUID] = graph.links
    .filter { link in
        guard link.isEnabled else { return false }
        // Prefer port-id matching; fall back to tile-id matching for older graphs.
        return (link.toPortId == toPort) || (link.toTileId == consoleNodeId)
    }
    .compactMap { link in
        nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
    }

// Only include people from People nodes that are actually linked to this console.
// If no People links exist, return an empty list (do NOT fall back to other People nodes or PCO).
guard !linkedFromNodeIds.isEmpty else {
    return []
}


var result: [ModuleMember] = []
var seen = Set<String>()

func appendUnique(_ members: [ModuleMember]) {
    for m in members {
        if seen.insert(m.title).inserted { result.append(m) }
    }
}

func customMembers(nodeId: UUID) -> [ModuleMember] {
    let entries = graph.customPeopleByNodeId[nodeId.uuidString] ?? []
    return entries.compactMap { entry in
        let pos = entry.position.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pos.isEmpty, !name.isEmpty else { return nil }
        return ModuleMember(
            tileId: tab.id,
            moduleId: stableUUID(for: "customPerson|\(nodeId.uuidString)|\(pos)|\(name)"),
            title: "\(pos) — \(name)",
            teamName: nil
        )
    }
}

for fromId in linkedFromNodeIds {
    // Canvas-backed People node
    if fromId == canvasPeopleNodeId {
        appendUnique(applyTeamFilter(canvasPeopleMembers, nodeId: fromId, graph: graph))
        continue
    }

    // Graph-only People instances
    if graph.moduleGroupNodeInstances.contains(where: { $0.id == fromId && $0.groupKey == "moduleGroup.person" }) {
        let mode = graph.peopleSourceByNodeId[fromId.uuidString] ?? "pco"

        if mode == "custom" {
            // Custom-only: no PCO, no team filter
            appendUnique(customMembers(nodeId: fromId))
        } else {
            // PCO mode: PCO + custom, with team filter
            // PERF: use cached synthesized list (rebuilt via refreshGraphCaches / PCO assignment onChange)
            var members = cachedSynthesizedPeopleMembersFromPCO
            members.append(contentsOf: customMembers(nodeId: fromId))
            appendUnique(applyTeamFilter(members, nodeId: fromId, graph: graph))
        }
        continue
    }

    if let sourceInstance = graph.moduleGroupNodeInstances.first(where: { $0.id == fromId && $0.groupKey.hasPrefix("source.") }) {
        appendUnique(sourceMembers(nodeId: fromId, groupKey: sourceInstance.groupKey, graph: graph))
    }
}

// If linked nodes produced no members (e.g. Custom mode with no entries), send nothing.
// PERF: hard-cap the list streamed into the console receiver UI.
let cap = 180
if result.count <= cap { return result }
return Array(result.prefix(cap))
}

private func peopleMembersForDestinationNode(destinationNodeId: UUID,
                                            canvasPeopleMembers: [ModuleMember]) -> [ModuleMember] {
    guard let graph = tab.graph else { return [] }

    let toPort = "node:\(destinationNodeId.uuidString)"
    let canvasPeopleNodeId = groupNodeId(for: "moduleGroup.person")

    let linkedFromNodeIds: [UUID] = graph.links
        .filter { link in
            guard link.isEnabled else { return false }
            return (link.toPortId == toPort) || (link.toTileId == destinationNodeId)
        }
        .compactMap { link in
            nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        }

    guard !linkedFromNodeIds.isEmpty else { return [] }

    var result: [ModuleMember] = []
    var seen = Set<String>()

    func appendUnique(_ members: [ModuleMember]) {
        for m in members {
            if seen.insert(m.title).inserted { result.append(m) }
        }
    }

    func customMembers(nodeId: UUID) -> [ModuleMember] {
        let entries = graph.customPeopleByNodeId[nodeId.uuidString] ?? []
        return entries.compactMap { entry in
            let pos = entry.position.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pos.isEmpty, !name.isEmpty else { return nil }
            return ModuleMember(
                tileId: tab.id,
                moduleId: stableUUID(for: "customPerson|\(nodeId.uuidString)|\(pos)|\(name)"),
                title: "\(pos) — \(name)",
                teamName: nil
            )
        }
    }

    for fromId in linkedFromNodeIds {
        if fromId == canvasPeopleNodeId {
            appendUnique(applyTeamFilter(canvasPeopleMembers, nodeId: fromId, graph: graph))
            continue
        }

        if graph.moduleGroupNodeInstances.contains(where: { $0.id == fromId && $0.groupKey == "moduleGroup.person" }) {
            let mode = graph.peopleSourceByNodeId[fromId.uuidString] ?? "pco"

            if mode == "custom" {
                appendUnique(customMembers(nodeId: fromId))
            } else {
                var members = cachedSynthesizedPeopleMembersFromPCO
                members.append(contentsOf: customMembers(nodeId: fromId))
                appendUnique(applyTeamFilter(members, nodeId: fromId, graph: graph))
            }
            continue
        }

        if let sourceInstance = graph.moduleGroupNodeInstances.first(where: { $0.id == fromId && $0.groupKey.hasPrefix("source.") }) {
            appendUnique(sourceMembers(nodeId: fromId, groupKey: sourceInstance.groupKey, graph: graph))
        }
    }

    let cap = 180
    if result.count <= cap { return result }
    return Array(result.prefix(cap))
}

private func applyTeamFilter(_ members: [ModuleMember], nodeId: UUID, graph: DashboardGraph) -> [ModuleMember] {
    let nodeFilter = Set(graph.peopleTeamFiltersByNodeId[nodeId.uuidString] ?? [])
    // When no node-specific filter, fall back to the tab's selected teams.
    let effective = nodeFilter.isEmpty ? tabTeamFilter : nodeFilter
    guard !effective.isEmpty else { return members }

    return members.filter { m in
        // Only include members that have a valid team AND that team is selected.
        // This prevents "teamless" items from leaking through.
        guard let t = m.teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else {
            return false
        }
        return effective.contains(t)
    }
}

private func splitPeopleLabel(_ label: String) -> (position: String, fullName: String) {
    let parts = label.components(separatedBy: " — ")
    if parts.count >= 2 {
        return (
            parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
            parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    return ("", label.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func formattedPeopleName(from label: String, format: String, casing: String) -> String {
    let parts = splitPeopleLabel(label)
    let full = parts.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    let comps = full.split(separator: " ").map(String.init)
    let first = comps.first ?? full
    let last = comps.last ?? full

    let base: String
    switch format {
    case "last":
        base = last
    case "position":
        base = parts.position.isEmpty ? full : parts.position
    default:
        base = first
    }

    let cased: String
    switch casing {
    case "upper":
        cased = base.uppercased()
    default:
        cased = base.lowercased().localizedCapitalized
    }

    if cased.count <= 8 { return cased }
    let shortened = NameShortener.shorten(cased, limit: 8)
    return shortened.count <= 8 ? shortened : String(shortened.prefix(8))
}

@ViewBuilder
private func peopleNameFormatSettingsPopover(
    title: String,
    nameFormat: Binding<String>,
    nameCasing: Binding<String>
) -> some View {
    let normalizedFormat = Binding(
        get: {
            let v = nameFormat.wrappedValue
            return v == "full" ? "first" : v
        },
        set: { nameFormat.wrappedValue = $0 }
    )

    let normalizedCasing = Binding(
        get: {
            let v = nameCasing.wrappedValue
            return v == "upper" ? "upper" : "title"
        },
        set: { nameCasing.wrappedValue = $0 }
    )

    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Button {
                showPeopleNameSettingsNodeId = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.medium)
                    .opacity(0.8)
            }
            .buttonStyle(.plain)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Name Format")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: normalizedFormat) {
                Text("First").tag("first")
                Text("Last").tag("last")
                Text("Position").tag("position")
            }
            .pickerStyle(.segmented)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Casing")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: normalizedCasing) {
                Text("Title Case").tag("title")
                Text("UPPERCASE").tag("upper")
            }
            .pickerStyle(.segmented)
        }
    }
    .padding(14)
    .frame(width: 320)
    .background(
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.black.opacity(0.85))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.white.opacity(GraphNodeStyleTokens.secondaryBorderOpacity), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
    )
    .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 8)
}

// MARK: - People Team Filters (Per Node)
private func peopleSourceModeBinding(forNodeId nodeId: UUID) -> Binding<String> {
    Binding<String>(
        get: { tab.graph?.peopleSourceByNodeId[nodeId.uuidString] ?? "pco" },
        set: { newValue in
            commitGraphEdit {
                if tab.graph == nil { tab.graph = DashboardGraph() }
                tab.graph?.peopleSourceByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}
private func peopleTeamSelection(forNodeId nodeId: UUID) -> Set<String> {
    let key = nodeId.uuidString
    let arr = tab.graph?.peopleTeamFiltersByNodeId[key] ?? []
    return Set(arr)
}

private func setPeopleTeamSelection(_ set: Set<String>, forNodeId nodeId: UUID) {
    commitGraphEdit {
        if tab.graph == nil { tab.graph = DashboardGraph() }
        tab.graph?.peopleTeamFiltersByNodeId[nodeId.uuidString] = Array(set).sorted()
    }
}

private func peopleTeamSelectionBinding(forNodeId nodeId: UUID) -> Binding<Set<String>> {
    Binding(
        get: { peopleTeamSelection(forNodeId: nodeId) },
        set: { setPeopleTeamSelection($0, forNodeId: nodeId) }
    )
}

/// Signature for the frozen tiles snapshot that changes when tiles or their module lists change.
/// Used to refresh graph caches when module composition changes but tile IDs stay the same.
private var tilesSnapshotSignature: Int {
    var h = 0
    for t in tilesSnapshot {
        h = h &* 31 &+ t.id.hashValue
        h = h &* 31 &+ (t.modules?.count ?? 0)
        h = h &* 31 &+ t.name.hashValue
    }
    return h
}

/// Fast, compiler-friendly check for whether the frozen tiles snapshot contains any Person content.
private func snapshotHasPersonTiles(_ tiles: [DashboardTileModel]) -> Bool {
    for tile in tiles {
        if let modules = tile.modules, !modules.isEmpty {
            for m in modules {
                if case .person = m.kind { return true }
            }
        }
        if case .person = tile.kind { return true }
    }
    return false
}

// MARK: - Body helpers (type-checker friendly)

private func computedModuleGroups() -> [ModuleGroup] {
    cachedModuleGroups
}

private func computedCanvasPeopleMembers(groups: [ModuleGroup]) -> [ModuleMember] {
    if let peopleGroup = groups.first(where: { $0.key == "moduleGroup.person" }) {
        return peopleGroup.members
    }

    // If the snapshot has any Person modules/tiles, ensure we have the People group.
    let hasPersonTiles = snapshotHasPersonTiles(tilesSnapshot)
    guard hasPersonTiles,
          let fallback = computedModuleGroups().first(where: { $0.key == "moduleGroup.person" })
    else {
        return []
    }

    DispatchQueue.main.async {
        if !cachedModuleGroups.contains(where: { $0.key == "moduleGroup.person" }) {
            cachedModuleGroups = cachedModuleGroups + [fallback]
        }
    }

    return fallback.members
}

private func graphSceneView(
    geoSize: CGSize,
    groups: [ModuleGroup],
    canvasPeopleMembers: [ModuleMember],
    teamOptions: [String]
)
-> some View {
    let scene = GraphDashboardCanvasView(
        geoSize: geoSize,
        isWorkEnabled: isWorkEnabled,
        showAddNodePopover: $showAddNodePopover,
        pan: $pan,
        zoom: $zoom,
        onBackgroundDoubleTap: {
            graphIsFocused = true
            addNodeSearchText = ""
            addNodeSelectedCategory = "All"
            showAddNodePopover = true
        }
    ) {
        // Keep the viewport region stable and only transform the graph content inside it.
        // If the event monitor moves with pan/zoom, wheel and magnify handling can stop
        // once the transformed layer drifts outside its original bounds.
        dottedGridLayer(in: geoSize, zoom: zoom)
        linksLayer(in: geoSize)
        moduleGroupNodesLayer(in: geoSize, groups: groups, peopleTeamOptions: teamOptions)
        consoleNodesLayer(in: geoSize, canvasPeopleMembers: canvasPeopleMembers, currentGroups: groups)
        vistaNodesLayer()
    } popover: {
        addNodePopover(in: geoSize, currentGroups: groups)
    }
    .coordinateSpace(.named("GraphSceneSpace"))
    .overlay(alignment: .bottom) {
        if !isLiveMode {
            ViewportPanZoomControls(
                pan: $pan,
                zoom: $zoom,
                zoomRange: 0.25...2.5,
                viewportSize: geoSize,
                onActualSize: {
                    centerGraphBounds(in: geoSize, zoomLevel: 1.0)
                },
                onFitToWindow: {
                    fitGraphToViewport(geoSize)
                }
            )
            .padding(.bottom, 12)
        }
    }
    .contentShape(Rectangle())
    .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard isWorkEnabled, !showAddNodePopover else { return }
                    if linkingFromNodeId != nil { return }
                    if isNodeDragging { return }

                    if marqueeStart == nil {
                        let startView = value.startLocation
                        let startGraph = graphPoint(fromViewPoint: startView)

                    let overNode = allVisibleGraphNodeIds.contains { id in
                        let center = nodePosition(for: id)
                        let r = nodeRect(center: center, size: nodeHitTestSize(for: id))
                        return r.contains(startGraph)
                    }
                    if overNode { return }

                    graphIsFocused = true
                    DispatchQueue.main.async {
                        graphIsFocused = true
                    }
                    isMarqueeSelecting = true
                    marqueeStart = startView
                    marqueeCurrent = startView
                }

                guard isMarqueeSelecting else { return }
                graphIsFocused = true
                DispatchQueue.main.async {
                    graphIsFocused = true
                }
                marqueeCurrent = value.location

                if let rect = marqueeRectInGraphSpace() {
                    selectedGraphNodeIds = nodesIntersectingMarquee(rect)
                }
            }
                .onEnded { _ in
                    if isMarqueeSelecting {
                    suppressNextBackgroundTap = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        suppressNextBackgroundTap = false
                    }
                    clearMarquee()
                    #if os(macOS)
                    focusGraphSurface()
                    #else
                    graphIsFocused = true
                    DispatchQueue.main.async {
                        graphIsFocused = true
                    }
                    #endif
                    }
                }
        )
    .simultaneousGesture(
        TapGesture()
            .onEnded {
                if suppressNextBackgroundTap { return }
                selectedGraphNodeIds.removeAll()
                #if os(macOS)
                focusGraphSurface()
                #endif
            }
    )
    .overlay {
        if let rect = marqueeRectInViewSpace(), isMarqueeSelecting {
            Path { p in
                p.addRect(rect)
            }
            .stroke(Color.accentColor.opacity(0.9), lineWidth: 1.5)
            .background(
                Path { p in p.addRect(rect) }
                    .fill(Color.accentColor.opacity(0.15))
            )
            .allowsHitTesting(false)
            .zIndex(900)
        }
    }
    .overlay { automationEmptyStateOverlay }

    // Hoist complex onChange expressions into simple locals to help the type-checker.
    let pcoTabSelectionRefreshKey = pcoTabSelectionRefreshSignature
    let teamNameValue = tab.teamName ?? ""
    let pcoTeamRefreshKey = pcoTeamRefreshSignature
    let pcoPeopleRefreshKey = pcoPeopleRefreshSignature
    let pcoRundownRefreshKey = pcoRundownRefreshSignature

    return applyGraphLifecycle(
        to: scene,
        geoSize: geoSize,
        groups: groups,
        pcoTabSelectionRefreshKey: pcoTabSelectionRefreshKey,
        pcoTeamRefreshKey: pcoTeamRefreshKey,
        teamNameValue: teamNameValue,
        pcoPeopleRefreshKey: pcoPeopleRefreshKey,
        pcoRundownRefreshKey: pcoRundownRefreshKey
    )
}

private func applyGraphLifecycle<Content: View>(
    to content: Content,
    geoSize: CGSize,
    groups: [ModuleGroup],
    pcoTabSelectionRefreshKey: String,
    pcoTeamRefreshKey: String,
    teamNameValue: String,
    pcoPeopleRefreshKey: String,
    pcoRundownRefreshKey: String
) -> some View {
    let lifecycleContent = content
    .onAppear {
        // Provide the *value* tab (never a Binding) so the runtime can always resolve it on main.
        configureGraphRuntimeBindings()
        // Wire Undo proxy
        undoProxy.snapshot = { snapshotGraphForUndo() }
        undoProxy.restore  = { data in restoreGraphFromUndo(data) }
        postGraphSelectionCount()
    }
    .task {
        guard isWorkEnabled else { return }
        let builtGroups = Self.buildGroups(from: captureModuleGroupInputs())
        cachedModuleGroups = builtGroups
        cachedSynthesizedPeopleMembersFromPCO = synthesizedPeopleMembersFromPCO()
        cachedPeopleTeamOptionsFromTab = recomputePCOTeamOptionsFromTab()
        ensureGraphInitialized(canvasSize: geoSize)
        pruneGraphStateForRemovedCanvasNodes(currentGroups: builtGroups)
    }
    .onPreferenceChange(GraphNodeSizePreferenceKey.self) { newSizes in
        // Merge size updates and resolve collisions when a node grows/shrinks.
        // Ignore sub-point jitter and coalesce bursts to avoid layout feedback loops.
        nodeSizePreferenceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            let startedAt = CFAbsoluteTimeGetCurrent()
            var changed: [UUID] = []
            var collisionCandidates: [UUID] = []

            for (id, sz) in newSizes {
                let prev = measuredNodeSizes[id]
                guard !graphCGSizeApproximatelyEqual(prev, sz) else { continue }
                changed.append(id)
                if graphNodeSizeGrowthRequiresCollisionResolution(previous: prev, current: sz) {
                    collisionCandidates.append(id)
                }
                measuredNodeSizes[id] = sz
            }

            guard !changed.isEmpty else { return }

            var moved = 0
            // Only resolve collisions when a previously measured node materially grows.
            for id in collisionCandidates {
                let current = nodePosition(for: id)
                let adjusted = resolveCollisionsForMovedNode(id, startingAt: current)
                if !graphCGPointApproximatelyEqual(adjusted, current) {
                    // Apply immediately so nodes can't overlap when their content grows.
                    transientNodePositions[id] = adjusted
                    moved += 1

                    // Persist into the graph layout model using TileGraphLayout.position.
                    if var layout = tab.graph?.tileLayouts[id] {
                        layout.position = CGPointCodable(adjusted)
                        tab.graph?.tileLayouts[id] = layout
                    } else {
                        tab.graph?.tileLayouts[id] = TileGraphLayout(position: adjusted)
                    }
                }
            }

            let duration = CFAbsoluteTimeGetCurrent() - startedAt
            let details = "reported=\(newSizes.count) changed=\(changed.count) candidates=\(collisionCandidates.count) moved=\(moved)"
            recordGraphPerfMetric(
                "graph.nodeSizePreference.apply",
                duration: duration,
                details: details,
                slowThreshold: 0.008
            )
            incrementGraphCounter("graph.nodeSizePreference.changedNodes", by: changed.count)
        }
        nodeSizePreferenceWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }
    .onChange(of: tab.id, initial: false) { _, _ in
        configureGraphRuntimeBindings()
    }
    .onAppear {
        NotificationCenter.default.post(
            name: Notification.Name("Relay.GraphSendAllAvailability"),
            object: computeSendAllAvailability()
        )
    }
    .onChange(of: consoleExternalDeviceIds, initial: false) { _, _ in
        NotificationCenter.default.post(
            name: Notification.Name("Relay.GraphSendAllAvailability"),
            object: computeSendAllAvailability()
        )
    }
    .onChange(of: tilesSnapshotSignature, initial: false) { _, _ in
        guard isWorkEnabled else { return }
        scheduleGraphCacheRefresh()
        ensureGraphInitialized(canvasSize: geoSize)
        pruneGraphStateForRemovedCanvasNodes(currentGroups: groups)
    }
    .onChange(of: notificationHub.addNodeRequestedTick, initial: false) { _, _ in
        guard isWorkEnabled else { return }
        addNodeSearchText = ""
        addNodeSelectedCategory = "All"
        showAddNodePopover = true
    }
    .onChange(of: notificationHub.dismissPopoversTick, initial: false) { _, _ in
        guard isWorkEnabled else { return }
        showAddNodePopover = false
    }
    .onChange(of: selectedGraphNodeIds, initial: true) { _, _ in
        postGraphSelectionCount()
    }

    let triggerContent = lifecycleContent
    .onReceive(NotificationCenter.default.publisher(for: TriggerNodeNotifications.fired)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let triggerId = ui[TriggerNodeUserInfoKeys.triggerNodeId] as? UUID else { return }
        guard shouldHandleTrigger(nodeId: triggerId) else { return }
        runActionsDownstream(of: triggerId, userInfo: ui)
    }
    .onReceive(NotificationCenter.default.publisher(for: .triggerNodeDidFire)) { note in
        // Back-compat: older trigger posts may carry nodeId as String.
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        if let id = ui["nodeId"] as? UUID {
            guard shouldHandleTrigger(nodeId: id) else { return }
            runActionsDownstream(of: id, userInfo: ui)
            return
        }
        if let s = ui["nodeId"] as? String, let id = UUID(uuidString: s) {
            guard shouldHandleTrigger(nodeId: id) else { return }
            runActionsDownstream(of: id, userInfo: ui)
            return
        }
        if let s = ui["nodeIdString"] as? String, let id = UUID(uuidString: s) {
            guard shouldHandleTrigger(nodeId: id) else { return }
            runActionsDownstream(of: id, userInfo: ui)
            return
        }
    }

    return triggerContent
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.proPresenterTriggerFailed)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        let message = ui[ActionNodeUserInfoKeys.errorMessage] as? String
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        proPresenterTriggerErrors[id] = trimmed?.isEmpty == false ? trimmed : "ProPresenter trigger failed"
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.proPresenterTriggerSucceeded)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        proPresenterTriggerErrors.removeValue(forKey: id)
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.appControlFailed)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        let message = ui[ActionNodeUserInfoKeys.errorMessage] as? String
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        appControlRunningNodeIds.remove(id)
        appControlErrors[id] = trimmed?.isEmpty == false ? trimmed : "Refresh failed"
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.appControlSucceeded)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        appControlRunningNodeIds.remove(id)
        appControlErrors.removeValue(forKey: id)
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.appControlStarted)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        appControlErrors.removeValue(forKey: id)
        appControlRunningNodeIds.insert(id)
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.smartLightStarted)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        smartLightErrors.removeValue(forKey: id)
        smartLightRunningNodeIds.insert(id)
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.smartLightSucceeded)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        smartLightRunningNodeIds.remove(id)
        smartLightErrors.removeValue(forKey: id)
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.smartLightFailed)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        let message = (ui[ActionNodeUserInfoKeys.errorMessage] as? String) ?? (ui[SmartLightActionUserInfoKeys.message] as? String)
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        smartLightRunningNodeIds.remove(id)
        smartLightErrors[id] = trimmed?.isEmpty == false ? trimmed : "Smart light action failed"
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.conditionEvaluationResolved)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        conditionMismatchErrors.removeValue(forKey: id)
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.conditionEvaluationMismatch)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        let message = ui[ActionNodeUserInfoKeys.errorMessage] as? String
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        conditionMismatchErrors[id] = trimmed?.isEmpty == false ? trimmed : "Operator doesn't apply to this value type"
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.consoleActionStarted)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        consoleActionErrors.removeValue(forKey: id)
        consoleActionRunningNodeIds.insert(id)
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.consoleActionSucceeded)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        consoleActionRunningNodeIds.remove(id)
        consoleActionErrors.removeValue(forKey: id)
    }
    .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.consoleActionFailed)) { note in
        guard isWorkEnabled else { return }
        let ui = note.userInfo ?? [:]
        guard let id = ui[ActionNodeUserInfoKeys.nodeId] as? UUID else { return }
        let message = ui[ActionNodeUserInfoKeys.errorMessage] as? String
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        consoleActionRunningNodeIds.remove(id)
        consoleActionErrors[id] = trimmed?.isEmpty == false ? trimmed : "Console action failed"
    }
    .onChange(of: pcoTabSelectionRefreshKey, initial: false) { _, _ in
        guard isWorkEnabled else { return }
        scheduleGraphCacheRefresh()
    }
    .onChange(of: pcoTeamRefreshKey, initial: false) { _, _ in
        guard isWorkEnabled else { return }
        cachedPeopleTeamOptionsFromTab = recomputePCOTeamOptionsFromTab()
    }
    .onChange(of: teamNameValue, initial: false) { _, _ in
        guard isWorkEnabled else { return }
        cachedPeopleTeamOptionsFromTab = recomputePCOTeamOptionsFromTab()
    }
    .onChange(of: pcoPeopleRefreshKey, initial: false) { _, _ in
        guard isWorkEnabled else { return }
        cachedSynthesizedPeopleMembersFromPCO = synthesizedPeopleMembersFromPCO()
    }
    .onChange(of: pcoRundownRefreshKey, initial: false) { _, _ in
        guard isWorkEnabled else { return }
        scheduleGraphCacheRefresh()
    }
}
// MARK: - Action Nodes (persisted in graph)

private func ensureGraphForActionConfig() {
    if tab.graph == nil { tab.graph = DashboardGraph() }
}

private func configureGraphRuntimeBindings() {
    runtimeCoordinator.configureBindings(
        runtime: automationRuntime,
        tabProvider: { self.tab },
        updater: { tabId, graph in
            guard self.tab.id == tabId else { return }
            applyRuntimeGraphUpdate(graph)
        }
    )
}

private func activateGraphRuntime() {
    runtimeCoordinator.activate(
        runtime: automationRuntime,
        tabProvider: { self.tab },
        updater: { tabId, graph in
            guard self.tab.id == tabId else { return }
            applyRuntimeGraphUpdate(graph)
        }
    )
}

private func sendAllConsolesActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.SendAllConsolesActionConfig> {
    Binding(
        get: {
            tab.graph?.sendAllConsolesActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.SendAllConsolesActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.sendAllConsolesActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func oscSendActionConfigBindingPersisted(forNodeId nodeId: UUID) -> Binding<DashboardGraph.OSCSendActionConfig> {
    Binding(
        get: {
            tab.graph?.oscSendActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.OSCSendActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.oscSendActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func notifyActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.NotifyActionConfig> {
    Binding(
        get: {
            tab.graph?.notifyActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.NotifyActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.notifyActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func lanNotifyActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.LANNotifyActionConfig> {
    Binding(
        get: {
            tab.graph?.lanNotifyActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.LANNotifyActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.lanNotifyActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func appControlActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.AppControlActionConfig> {
    Binding(
        get: {
            tab.graph?.appControlActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.AppControlActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.appControlActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func midiSendActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.MIDISendActionConfig> {
    Binding(
        get: {
            tab.graph?.midiSendActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.MIDISendActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.midiSendActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func httpRequestActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.HTTPRequestActionConfig> {
    Binding(
        get: { self.tab.graph?.httpRequestActionConfigByNodeId[nodeId.uuidString]
            ?? DashboardGraph.HTTPRequestActionConfig() },
        set: { self.tab.graph?.httpRequestActionConfigByNodeId[nodeId.uuidString] = $0 }
    )
}

private func setVariableActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.SetVariableActionConfig> {
    Binding(
        get: { self.tab.graph?.setVariableActionConfigByNodeId[nodeId.uuidString]
            ?? DashboardGraph.SetVariableActionConfig() },
        set: { self.tab.graph?.setVariableActionConfigByNodeId[nodeId.uuidString] = $0 }
    )
}

private func proPresenterTriggerActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.ProPresenterTriggerActionConfig> {
    Binding(
        get: {
            tab.graph?.proPresenterTriggerActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.ProPresenterTriggerActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.proPresenterTriggerActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func smartLightActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.SmartLightActionConfig> {
    Binding(
        get: {
            tab.graph?.smartLightActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.SmartLightActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.smartLightActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func shureSendActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.ShureSendActionConfig> {
    Binding(
        get: {
            tab.graph?.shureSendActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.ShureSendActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.shureSendActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func sennheiserSendActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.SennheiserSendActionConfig> {
    Binding(
        get: {
            tab.graph?.sennheiserSendActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.SennheiserSendActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.sennheiserSendActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func shureAdditionalChannelBinding(forNodeId nodeId: UUID, index: Int) -> Binding<Int> {
    let cfg = shureSendActionConfigBinding(forNodeId: nodeId)
    return Binding(
        get: {
            let values = cfg.wrappedValue.additionalChannelIndices
            guard values.indices.contains(index) else { return 1 }
            return values[index]
        },
        set: { newValue in
            var value = cfg.wrappedValue
            guard value.additionalChannelIndices.indices.contains(index) else { return }
            value.additionalChannelIndices[index] = newValue
            cfg.wrappedValue = value
        }
    )
}

private func sennheiserAdditionalChannelBinding(forNodeId nodeId: UUID, index: Int) -> Binding<Int> {
    let cfg = sennheiserSendActionConfigBinding(forNodeId: nodeId)
    return Binding(
        get: {
            let values = cfg.wrappedValue.additionalChannelIndices
            guard values.indices.contains(index) else { return 1 }
            return values[index]
        },
        set: { newValue in
            var value = cfg.wrappedValue
            guard value.additionalChannelIndices.indices.contains(index) else { return }
            value.additionalChannelIndices[index] = newValue
            cfg.wrappedValue = value
        }
    )
}

private func shureChannelAssignmentBinding(forNodeId nodeId: UUID, sourceName: String) -> Binding<Int?> {
    let cfg = shureSendActionConfigBinding(forNodeId: nodeId)
    return Binding(
        get: { cfg.wrappedValue.channelAssignments[sourceName] },
        set: { newValue in
            var value = cfg.wrappedValue
            if let newValue {
                value.channelAssignments[sourceName] = newValue
            } else {
                value.channelAssignments.removeValue(forKey: sourceName)
            }
            cfg.wrappedValue = value
        }
    )
}

private func sennheiserChannelAssignmentBinding(forNodeId nodeId: UUID, sourceName: String) -> Binding<Int?> {
    let cfg = sennheiserSendActionConfigBinding(forNodeId: nodeId)
    return Binding(
        get: { cfg.wrappedValue.channelAssignments[sourceName] },
        set: { newValue in
            var value = cfg.wrappedValue
            if let newValue {
                value.channelAssignments[sourceName] = newValue
            } else {
                value.channelAssignments.removeValue(forKey: sourceName)
            }
            cfg.wrappedValue = value
        }
    )
}

private func repeaterActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.RepeaterActionConfig> {
    Binding(
        get: {
            tab.graph?.repeaterActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.RepeaterActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.repeaterActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func delayActionConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.DelayActionConfig> {
    Binding(
        get: {
            tab.graph?.delayActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.DelayActionConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.delayActionConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func conditionNodeConfigBinding(forNodeId nodeId: UUID) -> Binding<DashboardGraph.ConditionNodeConfig> {
    Binding(
        get: {
            tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.ConditionNodeConfig()
        },
        set: { newValue in
            commitGraphEdit {
                ensureGraphForActionConfig()
                tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func mergedGraphPreservingEditorState(_ incomingGraph: DashboardGraph) -> DashboardGraph {
    guard let currentGraph = tab.graph else {
        return incomingGraph
    }

    var mergedGraph = incomingGraph

    for (nodeId, currentConfig) in currentGraph.variableNodeConfigByNodeId {
        guard var incomingConfig = mergedGraph.variableNodeConfigByNodeId[nodeId] else {
            mergedGraph.variableNodeConfigByNodeId[nodeId] = currentConfig
            continue
        }

        incomingConfig.id = currentConfig.id
        incomingConfig.name = currentConfig.name
        incomingConfig.valueType = currentConfig.valueType
        incomingConfig.manualTextValue = currentConfig.manualTextValue
        incomingConfig.manualNumberValue = currentConfig.manualNumberValue
        incomingConfig.manualBooleanValue = currentConfig.manualBooleanValue
        incomingConfig.sharedValueToken = currentConfig.sharedValueToken
        mergedGraph.variableNodeConfigByNodeId[nodeId] = incomingConfig
    }

    for (nodeId, currentConfig) in currentGraph.conditionNodeConfigByNodeId {
        guard var incomingConfig = mergedGraph.conditionNodeConfigByNodeId[nodeId] else {
            mergedGraph.conditionNodeConfigByNodeId[nodeId] = currentConfig
            continue
        }

        let draftText: String?
        if let nodeUUID = UUID(uuidString: nodeId) {
            draftText = conditionComparisonTextDraftByNodeId[nodeUUID]
        } else {
            draftText = nil
        }

        incomingConfig.id = currentConfig.id
        incomingConfig.sourceKind = currentConfig.sourceKind
        incomingConfig.operator = currentConfig.operator
        incomingConfig.variableNodeId = currentConfig.variableNodeId
        incomingConfig.comparisonText = draftText ?? currentConfig.comparisonText
        incomingConfig.comparisonNumber = currentConfig.comparisonNumber
        incomingConfig.comparisonBoolean = currentConfig.comparisonBoolean
        mergedGraph.conditionNodeConfigByNodeId[nodeId] = incomingConfig
    }

    return mergedGraph
}

private func applyRuntimeGraphUpdate(_ graph: DashboardGraph) {
    let mergedGraph = mergedGraphPreservingEditorState(graph)
    tab.graph = mergedGraph
    Task { @MainActor in
        automationRuntime.setActiveTabSnapshot(tab)
    }

    for (nodeIdString, config) in mergedGraph.conditionNodeConfigByNodeId {
        guard let nodeId = UUID(uuidString: nodeIdString) else { continue }
        syncConditionComparisonTextDraft(forNodeId: nodeId, config: config)
    }
}

private func conditionComparisonTextBinding(
    forNodeId nodeId: UUID,
    config: Binding<DashboardGraph.ConditionNodeConfig>
) -> Binding<String> {
    Binding(
        get: {
            conditionComparisonTextDraftByNodeId[nodeId] ?? config.wrappedValue.comparisonText
        },
        set: { newValue in
            conditionComparisonTextDraftByNodeId[nodeId] = newValue
            commitGraphEdit {
                ensureGraphForActionConfig()
                var updated = tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString] ?? config.wrappedValue
                updated.comparisonText = newValue
                tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString] = updated
            }
        }
    )
}

private func beginEditingConditionComparisonText(forNodeId nodeId: UUID, config: DashboardGraph.ConditionNodeConfig) {
    editingConditionComparisonNodeIds.insert(nodeId)
    if conditionComparisonTextDraftByNodeId[nodeId] == nil {
        conditionComparisonTextDraftByNodeId[nodeId] = config.comparisonText
    }
}

private func endEditingConditionComparisonText(forNodeId nodeId: UUID, config: Binding<DashboardGraph.ConditionNodeConfig>) {
    editingConditionComparisonNodeIds.remove(nodeId)
    let finalValue = conditionComparisonTextDraftByNodeId[nodeId] ?? config.wrappedValue.comparisonText
    let currentValue = tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString]?.comparisonText ?? config.wrappedValue.comparisonText
    if currentValue != finalValue {
        commitGraphEdit {
            ensureGraphForActionConfig()
            var updated = tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString] ?? config.wrappedValue
            updated.comparisonText = finalValue
            tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString] = updated
        }
    }
}

private func syncConditionComparisonTextDraft(forNodeId nodeId: UUID, config: DashboardGraph.ConditionNodeConfig) {
    guard !editingConditionComparisonNodeIds.contains(nodeId) else { return }
    if conditionComparisonTextDraftByNodeId[nodeId] != config.comparisonText {
        conditionComparisonTextDraftByNodeId[nodeId] = config.comparisonText
    }
}

#if os(macOS)
private func shouldHandleGraphDeleteKey() -> Bool {
    !selectedGraphNodeIds.isEmpty && !showAddNodePopover && !isGraphTextInputActive()
}
#endif

private func conditionOperatorNeedsText(
    _ op: DashboardGraph.ConditionNodeConfig.Operator,
    sourceKind: DashboardGraph.ConditionNodeConfig.SourceKind
) -> Bool {
    switch op {
    case .equals, .notEquals, .contains:
        return sourceKind != .payloadBoolean
    default:
        return false
    }
}

private func conditionOperatorNeedsNumber(
    _ op: DashboardGraph.ConditionNodeConfig.Operator,
    sourceKind: DashboardGraph.ConditionNodeConfig.SourceKind
) -> Bool {
    switch op {
    case .greaterThan, .lessThan:
        return true
    case .equals, .notEquals:
        return sourceKind == .payloadNumber
    default:
        return false
    }
}

private func conditionOperatorNeedsBoolean(
    _ op: DashboardGraph.ConditionNodeConfig.Operator,
    sourceKind: DashboardGraph.ConditionNodeConfig.SourceKind
) -> Bool {
    switch op {
    case .equals, .notEquals:
        return sourceKind == .payloadBoolean
    default:
        return false
    }
}


@ViewBuilder
private func actionGraphOnlyNodeView(nodeId: UUID, key: String) -> some View {
    let title = DashboardActionDescriptor.title(for: key)
    let subtitle = DashboardActionDescriptor.subtitle(for: key)

    let onRun: () -> Void = {
        if key == "action.proPresenterTrigger" {
            proPresenterTriggerErrors.removeValue(forKey: nodeId)
        }
        if key == "action.appControl" {
            appControlErrors.removeValue(forKey: nodeId)
            appControlRunningNodeIds.insert(nodeId)
        }
        if key == "action.smartLightControl" {
            smartLightErrors.removeValue(forKey: nodeId)
            smartLightRunningNodeIds.insert(nodeId)
        }
        runActionNode(nodeId: nodeId, key: key)
    }

    let isSelected = selectedGraphNodeIds.contains(nodeId)
    let isHoverReceiver = (hoverReceiverNodeId == nodeId)
    let isLinkingTarget = (linkingFromNodeId != nil)

    let proPresenterProfiles = ProPresenterProfilesStore.loadProfiles()
    let proPresenterGlobal = ProPresenterGlobalConnectionSettings.loadFromAppStorage()
    let showProPresenterWarning = key == "action.proPresenterTrigger"
        && proPresenterProfiles.isEmpty
        && !proPresenterGlobal.isValid
    let proPresenterError = proPresenterTriggerErrors[nodeId]
    let appControlError = key == "action.appControl" ? appControlErrors[nodeId] : nil
    let isAppControlRunning = key == "action.appControl" && appControlRunningNodeIds.contains(nodeId)
    let smartLightProfiles = smartLightProfilesStore.enabledProfiles
    let showSmartLightWarning = key == "action.smartLightControl" && smartLightProfiles.isEmpty
    let smartLightError = key == "action.smartLightControl" ? smartLightErrors[nodeId] : nil
    let isSmartLightRunning = key == "action.smartLightControl" && smartLightRunningNodeIds.contains(nodeId)

    let shureWarning = key == "action.shureSend" && availableShureDestinationDevices.isEmpty
        ? "No Shure devices with control support configured"
        : nil
    let sennheiserWarning = key == "action.sennheiserSend" && availableSennheiserDestinationDevices.isEmpty
        ? "No Sennheiser devices with control support configured"
        : nil

    let warningText = appControlError
        ?? proPresenterError
        ?? smartLightError
        ?? (showProPresenterWarning ? "No ProPresenter connections configured" : nil)
        ?? (showSmartLightWarning ? "No Smart Light connections configured" : nil)
        ?? shureWarning
        ?? sennheiserWarning
    let warningStyle: ActionNodeWarningStyle = appControlError != nil || proPresenterError != nil || smartLightError != nil
        ? .error
        : .warning
    let dismissWarning: (() -> Void)? = {
        if appControlError != nil {
            return {
                appControlErrors.removeValue(forKey: nodeId)
                appControlRunningNodeIds.remove(nodeId)
            }
        }
        if proPresenterError != nil {
            return {
                proPresenterTriggerErrors.removeValue(forKey: nodeId)
            }
        }
        if smartLightError != nil {
            return {
                smartLightErrors.removeValue(forKey: nodeId)
                smartLightRunningNodeIds.remove(nodeId)
            }
        }
        return nil
    }()

    let category = GraphNodeCategory(nodeKey: key)
    let isDestinationNode = category == .destinations
    let nodeTypeLabel = isDestinationNode ? "DESTINATION" : "ACTION"
    let nodeTypeAccessibilityLabel = isDestinationNode ? "Destination node" : "Action node"
    let nodeTypeBadgeColor = category.badgeColor
    let nodeTintColor = category.tintColor
    let showDetailed = shouldRenderDetailedGraphNode(nodeId)

    let base = Group {
        if showDetailed {
            if key == "action.smartLightControl" {
                let cfg = smartLightActionConfigBinding(forNodeId: nodeId)
                let outputs = connectedSmartLightOutputs(from: nodeId)
                SmartLightGraphNodeView(
                    nodeId: nodeId,
                    successConnected: outputs.success,
                    failureConnected: outputs.failure,
                    stateConnected: outputs.currentState,
                    showOutputPorts: cfg.wrappedValue.showOutputPorts,
                    isSelected: isSelected,
                    isHoverReceiver: isHoverReceiver,
                    isLinkingTarget: isLinkingTarget,
                    warningText: warningText,
                    warningStyle: warningStyle,
                    isRunning: isSmartLightRunning,
                    onDismissWarning: dismissWarning,
                    onTapSelect: { handleNodeTapSelect(nodeId) },
                    onRun: onRun,
                    onOutputDragChanged: { kind, value in
                        handleSmartLightOutputDragChanged(nodeId: nodeId, kind: kind, value: value)
                    },
                    onOutputDragEnded: { kind, value in
                        handleSmartLightOutputDragEnded(nodeId: nodeId, kind: kind, value: value)
                    },
                    settings: {
                        SmartLightNodeSettingsView(
                            config: cfg,
                            profiles: smartLightProfiles,
                            onTestAction: onRun
                        )
                    }
                )
            } else {
                ActionGraphNodeView(
                    nodeId: nodeId,
                    title: title,
                    subtitle: subtitle,
                    systemImage: DashboardActionDescriptor.systemImage(for: key),
                    nodeTypeLabel: nodeTypeLabel,
                    nodeTypeAccessibilityLabel: nodeTypeAccessibilityLabel,
                    nodeTypeBadgeColor: nodeTypeBadgeColor,
                    nodeTintColor: nodeTintColor,
                    warningText: warningText,
                    warningStyle: warningStyle,
                    isRunning: isAppControlRunning,
                    onDismissWarning: dismissWarning,
                    isSelected: isSelected,
                    isHoverReceiver: isHoverReceiver,
                    isLinkingTarget: isLinkingTarget,
                    onTapSelect: { handleNodeTapSelect(nodeId) },
                    onRun: onRun,
                    settings: {
            if key == "action.sendAllConsoles" {
                let cfg = sendAllConsolesActionConfigBinding(forNodeId: nodeId)

                // Bridge Double <-> Int for the reusable settings view.
                let staggerInt = Binding<Int>(
                    get: { cfg.wrappedValue.staggerMs },
                    set: { newValue in
                        var v = cfg.wrappedValue
                        v.staggerMs = max(0, newValue)
                        cfg.wrappedValue = v
                    }
                )

                SendAllActionSettingsView(
                    includeAssignments: Binding(
                        get: { cfg.wrappedValue.includeAssignments },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.includeAssignments = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    includeSnapshots: Binding(
                        get: { cfg.wrappedValue.includeSnapshots },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.includeSnapshots = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    staggerMs: staggerInt
                )

            } else if key == "action.oscSend" {
                let cfg = oscSendActionConfigBindingPersisted(forNodeId: nodeId)
                OSCSendActionSettingsView(
                    targetIP: Binding(
                        get: { cfg.wrappedValue.targetIP },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.targetIP = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    targetPort: Binding(
                        get: { cfg.wrappedValue.targetPort },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.targetPort = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    address: Binding(
                        get: { cfg.wrappedValue.address },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.address = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    arguments: Binding(
                        get: { cfg.wrappedValue.arguments },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.arguments = newValue
                            cfg.wrappedValue = v
                        }
                    )
                )
            } else if key == "action.proPresenterTrigger" {
                let cfg = proPresenterTriggerActionConfigBinding(forNodeId: nodeId)
                ProPresenterTriggerActionSettingsView(
                    profileId: Binding(
                        get: { cfg.wrappedValue.profileId },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.profileId = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    triggerPath: Binding(
                        get: { cfg.wrappedValue.triggerPath },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.triggerPath = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    profiles: proPresenterProfiles,
                    showMissingProfilesWarning: showProPresenterWarning
                )
            } else if key == "action.shureSend" {
                let cfg = shureSendActionConfigBinding(forNodeId: nodeId)
                let devices = availableShureDestinationDevices
                let selectedDevice = devices.first(where: { $0.id == cfg.wrappedValue.deviceId })
                let channelCount = max(1, selectedDevice?.effectiveShureChannelCount ?? 1)
                let linkedSourceNames = linkedPatchSourceTexts(forDestinationNodeId: nodeId)
                let linkedSourceName = linkedSourceNames.first

                VStack(alignment: .leading, spacing: 10) {
                    Text("Destination")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Picker("Device", selection: Binding<UUID?>(
                        get: { cfg.wrappedValue.deviceId },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.deviceId = newValue
                            cfg.wrappedValue = v
                        }
                    )) {
                        Text("Select device").tag(UUID?.none)
                        ForEach(devices, id: \.id) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if devices.isEmpty {
                        Text("No Shure devices with control support are configured.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Command", selection: Binding(
                        get: { cfg.wrappedValue.commandKind },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.commandKind = newValue
                            cfg.wrappedValue = v
                        }
                    )) {
                        Text("Set Channel Name").tag(DashboardGraph.ShureSendActionConfig.CommandKind.setChannelName)
                        Text("Raw Command").tag(DashboardGraph.ShureSendActionConfig.CommandKind.rawCommand)
                    }
                    .pickerStyle(.segmented)

                    if cfg.wrappedValue.commandKind == .setChannelName {
                        if linkedSourceNames.count <= 1 {
                            Picker("Channel", selection: Binding(
                                get: { cfg.wrappedValue.channelIndex },
                                set: { newValue in
                                    var v = cfg.wrappedValue
                                    v.channelIndex = newValue
                                    cfg.wrappedValue = v
                                }
                            )) {
                                ForEach(1...channelCount, id: \.self) { idx in
                                    Text("CH \(idx)").tag(idx)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if let linkedSourceName {
                            if linkedSourceNames.count > 1 {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Assignments (\(linkedSourceNames.count))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Auto") {
                                            var v = cfg.wrappedValue
                                            v.channelAssignments = [:]
                                            let channels = Array(1...channelCount)
                                            let startIndex = max(0, channels.firstIndex(of: max(1, min(channelCount, v.channelIndex))) ?? 0)
                                            var available = Array(channels[startIndex...]) + Array(channels[..<startIndex])
                                            for name in linkedSourceNames where !available.isEmpty {
                                                v.channelAssignments[name] = available.removeFirst()
                                            }
                                            cfg.wrappedValue = v
                                        }
                                        .font(.caption2)

                                        Button("Clear") {
                                            var v = cfg.wrappedValue
                                            v.channelAssignments.removeAll()
                                            cfg.wrappedValue = v
                                        }
                                        .font(.caption2)
                                    }

                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(linkedSourceNames.enumerated()), id: \.offset) { _, sourceName in
                                                HStack(spacing: 10) {
                                                    Text(sourceName)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Picker("", selection: shureChannelAssignmentBinding(forNodeId: nodeId, sourceName: sourceName)) {
                                                        Text("—").tag(Int?.none)
                                                        ForEach(1...channelCount, id: \.self) { idx in
                                                            Text("CH \(idx)").tag(Optional(idx))
                                                        }
                                                    }
                                                    .labelsHidden()
                                                    .frame(width: 120)
                                                }
                                                .frame(height: 24)
                                            }
                                        }
                                    }
                                    .frame(maxHeight: min(CGFloat(max(linkedSourceNames.count, 1)) * 28, 220))
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Linked Source")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(linkedSourceName)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                            }
                        } else {
                            let groups = computedModuleGroups()
                            let canvasPeopleMembers = computedCanvasPeopleMembers(groups: groups)
                            let linkedPeople = peopleMembersForDestinationNode(
                                destinationNodeId: nodeId,
                                canvasPeopleMembers: canvasPeopleMembers
                            )

                            if !linkedPeople.isEmpty {
                            HStack {
                                Text("Channel name")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                let isPresented = Binding(
                                    get: { showPeopleNameSettingsNodeId == nodeId },
                                    set: { newValue in
                                        if newValue {
                                            showPeopleNameSettingsNodeId = nodeId
                                        } else if showPeopleNameSettingsNodeId == nodeId {
                                            showPeopleNameSettingsNodeId = nil
                                        }
                                    }
                                )

                                Button {
                                    isPresented.wrappedValue = true
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: isPresented, arrowEdge: .trailing) {
                                    let settingsBinding = shureSendActionConfigBinding(forNodeId: nodeId)
                                    peopleNameFormatSettingsPopover(
                                        title: "Assignment Settings",
                                        nameFormat: Binding(
                                            get: { settingsBinding.wrappedValue.nameFormat },
                                            set: { newValue in
                                                var v = settingsBinding.wrappedValue
                                                v.nameFormat = newValue
                                                settingsBinding.wrappedValue = v
                                            }
                                        ),
                                        nameCasing: Binding(
                                            get: { settingsBinding.wrappedValue.nameCasing },
                                            set: { newValue in
                                                var v = settingsBinding.wrappedValue
                                                v.nameCasing = newValue
                                                settingsBinding.wrappedValue = v
                                            }
                                        )
                                    )
                                }
                            }

                            Picker("Channel name", selection: Binding(
                                get: { cfg.wrappedValue.channelName },
                                set: { newValue in
                                    var v = cfg.wrappedValue
                                    v.channelName = newValue
                                    v.channelNameSource = "people"
                                    cfg.wrappedValue = v
                                }
                            )) {
                                let current = cfg.wrappedValue.channelName
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !current.isEmpty, !linkedPeople.contains(where: { $0.title == current }) {
                                    Text(current).tag(current)
                                }
                                ForEach(linkedPeople) { person in
                                    let formatted = formattedPeopleName(
                                        from: person.title,
                                        format: cfg.wrappedValue.nameFormat,
                                        casing: cfg.wrappedValue.nameCasing
                                    )
                                    Text(formatted).tag(person.title)
                                }
                            }
                            .pickerStyle(.menu)
                            } else {
                                TextField("Channel name (max 8 chars)", text: Binding(
                                    get: { cfg.wrappedValue.channelName },
                                    set: { newValue in
                                        var v = cfg.wrappedValue
                                        v.channelName = newValue
                                        v.channelNameSource = "manual"
                                        cfg.wrappedValue = v
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    } else {
                        AutomationVariableTokenField(title: "Raw command (ex: GET 1 CHAN_NAME)", text: Binding(
                            get: { cfg.wrappedValue.rawCommand },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.rawCommand = newValue
                                cfg.wrappedValue = v
                            }
                        ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))
                    }
                }
            } else if key == "action.sennheiserSend" {
                let cfg = sennheiserSendActionConfigBinding(forNodeId: nodeId)
                let devices = availableSennheiserDestinationDevices
                let selectedDevice = devices.first(where: { $0.id == cfg.wrappedValue.deviceId })
                let selectedModel = selectedDevice?.sennheiserNetworkModel
                let channelCount = max(1, selectedModel?.channelCount ?? 1)
                let supportsActions = selectedModel?.supportsSscV1Control ?? false
                let linkedSourceNames = linkedPatchSourceTexts(forDestinationNodeId: nodeId)
                let linkedSourceName = linkedSourceNames.first
                let actionOptions: [(DashboardGraph.SennheiserSendActionConfig.CommandKind, String)] = supportsActions
                    ? [
                        (.setChannelName, "Set Channel Name"),
                        (.setMute, "Mute/Unmute"),
                        (.setGain, "Set Gain"),
                        (.setRfMute, "RF On/Off"),
                        (.advanced, "Advanced (Raw)")
                    ]
                    : [
                        (.advanced, "Advanced (Raw)")
                    ]

                VStack(alignment: .leading, spacing: 10) {
                    Text("Destination")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Picker("Device", selection: Binding<UUID?>(
                        get: { cfg.wrappedValue.deviceId },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.deviceId = newValue
                            cfg.wrappedValue = v
                        }
                    )) {
                        Text("Select device").tag(UUID?.none)
                        ForEach(devices, id: \.id) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if devices.isEmpty {
                        Text("No Sennheiser devices with control support are configured.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if !supportsActions {
                        Text("No action templates are available for this model. Use Advanced (Raw) to send direct requests.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Action", selection: Binding(
                        get: { cfg.wrappedValue.commandKind },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.commandKind = newValue
                            cfg.wrappedValue = v
                        }
                    )) {
                        ForEach(actionOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .pickerStyle(.menu)

                    if cfg.wrappedValue.commandKind == .setChannelName {
                        if linkedSourceNames.count <= 1 {
                            Picker("Channel", selection: Binding(
                                get: { cfg.wrappedValue.channelIndex },
                                set: { newValue in
                                    var v = cfg.wrappedValue
                                    v.channelIndex = max(1, min(channelCount, newValue))
                                    cfg.wrappedValue = v
                                }
                            )) {
                                ForEach(1...channelCount, id: \.self) { idx in
                                    Text("CH \(idx)").tag(idx)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if let linkedSourceName {
                            if linkedSourceNames.count > 1 {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Assignments (\(linkedSourceNames.count))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Auto") {
                                            var v = cfg.wrappedValue
                                            v.channelAssignments = [:]
                                            let channels = Array(1...channelCount)
                                            let startIndex = max(0, channels.firstIndex(of: max(1, min(channelCount, v.channelIndex))) ?? 0)
                                            var available = Array(channels[startIndex...]) + Array(channels[..<startIndex])
                                            for name in linkedSourceNames where !available.isEmpty {
                                                v.channelAssignments[name] = available.removeFirst()
                                            }
                                            cfg.wrappedValue = v
                                        }
                                        .font(.caption2)

                                        Button("Clear") {
                                            var v = cfg.wrappedValue
                                            v.channelAssignments.removeAll()
                                            cfg.wrappedValue = v
                                        }
                                        .font(.caption2)
                                    }

                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(linkedSourceNames.enumerated()), id: \.offset) { _, sourceName in
                                                HStack(spacing: 10) {
                                                    Text(sourceName)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Picker("", selection: sennheiserChannelAssignmentBinding(forNodeId: nodeId, sourceName: sourceName)) {
                                                        Text("—").tag(Int?.none)
                                                        ForEach(1...channelCount, id: \.self) { idx in
                                                            Text("CH \(idx)").tag(Optional(idx))
                                                        }
                                                    }
                                                    .labelsHidden()
                                                    .frame(width: 120)
                                                }
                                                .frame(height: 24)
                                            }
                                        }
                                    }
                                    .frame(maxHeight: min(CGFloat(max(linkedSourceNames.count, 1)) * 28, 220))
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Linked Source")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(linkedSourceName)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                            }
                        } else {
                            let groups = computedModuleGroups()
                            let canvasPeopleMembers = computedCanvasPeopleMembers(groups: groups)
                            let linkedPeople = peopleMembersForDestinationNode(
                                destinationNodeId: nodeId,
                                canvasPeopleMembers: canvasPeopleMembers
                            )

                            if !linkedPeople.isEmpty {
                            HStack {
                                Text("Channel name")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                let isPresented = Binding(
                                    get: { showPeopleNameSettingsNodeId == nodeId },
                                    set: { newValue in
                                        if newValue {
                                            showPeopleNameSettingsNodeId = nodeId
                                        } else if showPeopleNameSettingsNodeId == nodeId {
                                            showPeopleNameSettingsNodeId = nil
                                        }
                                    }
                                )

                                Button {
                                    isPresented.wrappedValue = true
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: isPresented, arrowEdge: .trailing) {
                                    let settingsBinding = sennheiserSendActionConfigBinding(forNodeId: nodeId)
                                    peopleNameFormatSettingsPopover(
                                        title: "Assignment Settings",
                                        nameFormat: Binding(
                                            get: { settingsBinding.wrappedValue.nameFormat },
                                            set: { newValue in
                                                var v = settingsBinding.wrappedValue
                                                v.nameFormat = newValue
                                                settingsBinding.wrappedValue = v
                                            }
                                        ),
                                        nameCasing: Binding(
                                            get: { settingsBinding.wrappedValue.nameCasing },
                                            set: { newValue in
                                                var v = settingsBinding.wrappedValue
                                                v.nameCasing = newValue
                                                settingsBinding.wrappedValue = v
                                            }
                                        )
                                    )
                                }
                            }

                            Picker("Channel name", selection: Binding(
                                get: { cfg.wrappedValue.channelName },
                                set: { newValue in
                                    var v = cfg.wrappedValue
                                    v.channelName = newValue
                                    v.channelNameSource = "people"
                                    cfg.wrappedValue = v
                                }
                            )) {
                                let current = cfg.wrappedValue.channelName
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !current.isEmpty, !linkedPeople.contains(where: { $0.title == current }) {
                                    Text(current).tag(current)
                                }
                                ForEach(linkedPeople) { person in
                                    let formatted = formattedPeopleName(
                                        from: person.title,
                                        format: cfg.wrappedValue.nameFormat,
                                        casing: cfg.wrappedValue.nameCasing
                                    )
                                    Text(formatted).tag(person.title)
                                }
                            }
                            .pickerStyle(.menu)
                            } else {
                                TextField("Channel name (max 8 chars)", text: Binding(
                                    get: { cfg.wrappedValue.channelName },
                                    set: { newValue in
                                        var v = cfg.wrappedValue
                                        v.channelName = String(newValue.prefix(8))
                                        v.channelNameSource = "manual"
                                        cfg.wrappedValue = v
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    } else if cfg.wrappedValue.commandKind == .setMute {
                        Picker("Channel", selection: Binding(
                            get: { cfg.wrappedValue.channelIndex },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.channelIndex = max(1, min(channelCount, newValue))
                                cfg.wrappedValue = v
                            }
                        )) {
                            ForEach(1...channelCount, id: \.self) { idx in
                                Text("CH \(idx)").tag(idx)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle("Muted", isOn: Binding(
                            get: { cfg.wrappedValue.muteEnabled },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.muteEnabled = newValue
                                cfg.wrappedValue = v
                            }
                        ))
                    } else if cfg.wrappedValue.commandKind == .setGain {
                        Picker("Channel", selection: Binding(
                            get: { cfg.wrappedValue.channelIndex },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.channelIndex = max(1, min(channelCount, newValue))
                                cfg.wrappedValue = v
                            }
                        )) {
                            ForEach(1...channelCount, id: \.self) { idx in
                                Text("CH \(idx)").tag(idx)
                            }
                        }
                        .pickerStyle(.menu)

                        let gainBinding = Binding<Double>(
                            get: { cfg.wrappedValue.gainDb },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                let clamped = min(42, max(-3, newValue))
                                v.gainDb = (clamped / 3).rounded() * 3
                                cfg.wrappedValue = v
                            }
                        )

                        HStack(spacing: 10) {
                            Text("Gain (dB)")
                                .font(.caption)
                                .opacity(0.8)
                                .frame(width: 70, alignment: .leading)

                            TextField("dB", value: gainBinding, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)

                            Stepper("", value: gainBinding, in: -3...42, step: 3)
                        }
                    } else if cfg.wrappedValue.commandKind == .setRfMute {
                        Text("RF On/Off is not supported for EW-DX SSC v1. Use Advanced (Raw) if your model exposes an endpoint.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if cfg.wrappedValue.commandKind == .advanced {
                        HStack(spacing: 12) {
                            Picker("Method", selection: Binding(
                                get: { cfg.wrappedValue.method },
                                set: { newValue in
                                    var v = cfg.wrappedValue
                                    v.method = newValue
                                    cfg.wrappedValue = v
                                }
                            )) {
                                ForEach(DashboardGraph.SennheiserSendActionConfig.HTTPMethod.allCases, id: \.self) { method in
                                    Text(method.rawValue).tag(method)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Scheme", selection: Binding(
                                get: { cfg.wrappedValue.scheme },
                                set: { newValue in
                                    var v = cfg.wrappedValue
                                    v.scheme = newValue
                                    cfg.wrappedValue = v
                                }
                            )) {
                                Text("http").tag("http")
                                Text("https").tag("https")
                            }
                            .pickerStyle(.menu)
                        }

                        AutomationVariableTokenField(title: "Path", text: Binding(
                            get: { cfg.wrappedValue.path },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.path = newValue
                                cfg.wrappedValue = v
                            }
                        ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))

                        Text("JSON Body")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        AutomationVariableTokenField(title: "JSON Body", text: Binding(
                            get: { cfg.wrappedValue.jsonBody },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.jsonBody = newValue
                                cfg.wrappedValue = v
                            }
                        ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab), multiline: true)
                        .frame(height: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(GraphNodeStyleTokens.secondaryBorderOpacity), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
                        )
                    }
                }
            } else if key == "action.notify" {
                let cfg = notifyActionConfigBinding(forNodeId: nodeId)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notification")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Text("Title")
                            .font(.caption)
                            .opacity(0.8)
                            .frame(width: 60, alignment: .leading)

                        AutomationVariableTokenField(title: "Title", text: Binding(
                            get: { cfg.wrappedValue.title },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.title = newValue
                                cfg.wrappedValue = v
                            }
                        ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        Text("Message")
                            .font(.caption)
                            .opacity(0.8)
                            .frame(width: 60, alignment: .leading)

                        AutomationVariableTokenField(title: "Message", text: Binding(
                            get: { cfg.wrappedValue.message },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.message = newValue
                                cfg.wrappedValue = v
                            }
                        ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        Text("Duration")
                            .font(.caption)
                            .opacity(0.8)
                            .frame(width: 60, alignment: .leading)

                        TextField("Seconds", value: Binding(
                            get: { cfg.wrappedValue.durationSeconds },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.durationSeconds = max(0.5, min(30, newValue))
                                cfg.wrappedValue = v
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                        Text("sec")
                            .font(.caption)
                            .opacity(0.7)

                        Spacer(minLength: 0)
                    }
                }
            } else if key == "action.lanNotify" {
                let cfg = lanNotifyActionConfigBinding(forNodeId: nodeId)
                let availablePeers = lanPeers.sorted {
                    ($0.deviceName ?? $0.endpointKey).localizedCaseInsensitiveCompare($1.deviceName ?? $1.endpointKey) == .orderedAscending
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("LAN Notification")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Picker("Target", selection: Binding(
                        get: { cfg.wrappedValue.targetMode },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.targetMode = newValue
                            cfg.wrappedValue = v
                        }
                    )) {
                        ForEach(DashboardGraph.LANNotifyActionConfig.TargetMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if cfg.wrappedValue.targetMode == .specificPeer {
                        if availablePeers.isEmpty {
                            Text("No LAN peers discovered yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Peer", selection: Binding(
                                // A target saved by an older build may be the peer's name; show it
                                // as that peer so the next selection saves the real deviceId.
                                get: {
                                    let saved = cfg.wrappedValue.peerDeviceId
                                    return availablePeers.first(where: { $0.matchesSavedTarget(saved) })?.deviceId ?? saved
                                },
                                set: { newValue in
                                    var v = cfg.wrappedValue
                                    v.peerDeviceId = newValue
                                    cfg.wrappedValue = v
                                }
                            )) {
                                Text("Select Peer").tag("")
                                ForEach(availablePeers, id: \.deviceId) { peer in
                                    Text(peer.deviceName ?? peer.endpointKey).tag(peer.deviceId)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    HStack(spacing: 10) {
                        Text("Title")
                            .font(.caption)
                            .opacity(0.8)
                            .frame(width: 60, alignment: .leading)

                        AutomationVariableTokenField(title: "Title", text: Binding(
                            get: { cfg.wrappedValue.title },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.title = newValue
                                cfg.wrappedValue = v
                            }
                        ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        Text("Message")
                            .font(.caption)
                            .opacity(0.8)
                            .frame(width: 60, alignment: .leading)

                        AutomationVariableTokenField(title: "Message", text: Binding(
                            get: { cfg.wrappedValue.message },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.message = newValue
                                cfg.wrappedValue = v
                            }
                        ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        Text("Duration")
                            .font(.caption)
                            .opacity(0.8)
                            .frame(width: 60, alignment: .leading)

                        TextField("Seconds", value: Binding(
                            get: { cfg.wrappedValue.durationSeconds },
                            set: { newValue in
                                var v = cfg.wrappedValue
                                v.durationSeconds = max(0.5, min(30, newValue))
                                cfg.wrappedValue = v
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                        Text("sec")
                            .font(.caption)
                            .opacity(0.7)

                        Spacer(minLength: 0)
                    }
                }
            } else if key == "action.appControl" {
                let cfg = appControlActionConfigBinding(forNodeId: nodeId)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Relay Action")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Picker("Action", selection: Binding(
                        get: { cfg.wrappedValue.actionKind },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.actionKind = newValue
                            cfg.wrappedValue = v
                        }
                    )) {
                        ForEach(DashboardGraph.AppControlActionConfig.ActionKind.allCases, id: \.self) { actionKind in
                            Text(actionKind.displayName).tag(actionKind)
                        }
                    }
                    .pickerStyle(.menu)

                    if cfg.wrappedValue.actionKind == .resyncDeviceNames {
                        NameRefreshDeviceOptionsEditor(
                            options: Binding(
                                get: { cfg.wrappedValue.refreshDeviceOptions },
                                set: { newValue in
                                    var v = cfg.wrappedValue
                                    v.refreshDeviceOptions = newValue
                                    cfg.wrappedValue = v
                                }
                            )
                        )
                    }
                }
            } else if key == "action.midiSend" {
                let cfg = midiSendActionConfigBinding(forNodeId: nodeId)
                MIDISendActionSettingsView(
                    destinationUniqueID: Binding(
                        get: { cfg.wrappedValue.destinationUniqueID },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.destinationUniqueID = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    messageKind: Binding(
                        get: { cfg.wrappedValue.messageKind },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.messageKind = newValue
                            cfg.wrappedValue = v
                        }
                    ),
                    channel: Binding(
                        get: { cfg.wrappedValue.channel },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.channel = max(1, min(16, newValue))
                            cfg.wrappedValue = v
                        }
                    ),
                    note: Binding(
                        get: { cfg.wrappedValue.note },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.note = max(0, min(127, newValue))
                            cfg.wrappedValue = v
                        }
                    ),
                    velocity: Binding(
                        get: { cfg.wrappedValue.velocity },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.velocity = max(0, min(127, newValue))
                            cfg.wrappedValue = v
                        }
                    ),
                    program: Binding(
                        get: { cfg.wrappedValue.program },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.program = max(0, min(127, newValue))
                            cfg.wrappedValue = v
                        }
                    ),
                    control: Binding(
                        get: { cfg.wrappedValue.control },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.control = max(0, min(127, newValue))
                            cfg.wrappedValue = v
                        }
                    ),
                    value: Binding(
                        get: { cfg.wrappedValue.value },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.value = max(0, min(127, newValue))
                            cfg.wrappedValue = v
                        }
                    ),
                    sysexHex: Binding(
                        get: { cfg.wrappedValue.sysexHex },
                        set: { newValue in
                            var v = cfg.wrappedValue
                            v.sysexHex = newValue
                            cfg.wrappedValue = v
                        }
                    )
                )
            } else if key == "action.httpRequest" {
                let cfg = httpRequestActionConfigBinding(forNodeId: nodeId)
                VStack(alignment: .leading, spacing: 8) {
                    AutomationVariableTokenField(title: "URL", text: Binding(
                        get: { cfg.wrappedValue.urlString },
                        set: { var v = cfg.wrappedValue; v.urlString = $0; cfg.wrappedValue = v }
                    ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))

                    Picker("Method", selection: Binding(
                        get: { cfg.wrappedValue.method },
                        set: { var v = cfg.wrappedValue; v.method = $0; cfg.wrappedValue = v }
                    )) {
                        ForEach(DashboardGraph.HTTPRequestActionConfig.Method.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    AutomationVariableTokenField(title: "Headers JSON (optional)", text: Binding(
                        get: { cfg.wrappedValue.headersJSON },
                        set: { var v = cfg.wrappedValue; v.headersJSON = $0; cfg.wrappedValue = v }
                    ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab), multiline: true)

                    AutomationVariableTokenField(title: "Body (optional)", text: Binding(
                        get: { cfg.wrappedValue.body },
                        set: { var v = cfg.wrappedValue; v.body = $0; cfg.wrappedValue = v }
                    ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab), multiline: true)

                    HStack {
                        Text("Timeout (s)")
                        Spacer()
                        TextField("", value: Binding(
                            get: { cfg.wrappedValue.timeoutSeconds },
                            set: { var v = cfg.wrappedValue; v.timeoutSeconds = max(1, $0); cfg.wrappedValue = v }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    }
                }
            } else if key == "action.setVariable" {
                let cfg = setVariableActionConfigBinding(forNodeId: nodeId)
                let targetType = cfg.wrappedValue.targetVariableNodeId
                    .flatMap { tab.graph?.variableNodeConfigByNodeId[$0.uuidString]?.valueType }
                    ?? cfg.wrappedValue.valueType
                let variableOptions = (tab.graph?.moduleGroupNodeInstances ?? [])
                    .filter { $0.groupKey == "utility.variable" }
                    .compactMap { inst -> (UUID, String)? in
                        guard let v = tab.graph?.variableNodeConfigByNodeId[inst.id.uuidString] else { return nil }
                        let name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (inst.id, name.isEmpty ? "Unnamed Variable" : name)
                    }
                    .sorted { $0.1 < $1.1 }

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Variable", selection: Binding<UUID?>(
                        get: { cfg.wrappedValue.targetVariableNodeId },
                        set: { var v = cfg.wrappedValue; v.targetVariableNodeId = $0; cfg.wrappedValue = v }
                    )) {
                        Text("Select Variable").tag(Optional<UUID>.none)
                        ForEach(variableOptions, id: \.0) { opt in
                            Text(opt.1).tag(Optional(opt.0))
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Type: \(targetType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let targetID = cfg.wrappedValue.targetVariableNodeId,
                       tab.graph?.variableNodeConfigByNodeId[targetID.uuidString]?.sharedValueToken != nil {
                        Text("This Variable node reads a universal variable and cannot be set by an action.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    switch targetType {
                    case .text:
                        AutomationVariableTokenField(title: "Value", text: Binding(
                            get: { cfg.wrappedValue.textValue },
                            set: { var v = cfg.wrappedValue; v.textValue = $0; cfg.wrappedValue = v }
                        ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))
                    case .number:
                        TextField("Value", value: Binding(
                            get: { Int(cfg.wrappedValue.numberValue) },
                            set: { var v = cfg.wrappedValue; v.numberValue = Double($0); cfg.wrappedValue = v }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                    case .float:
                        TextField("Value", value: Binding(
                            get: { cfg.wrappedValue.numberValue },
                            set: { var v = cfg.wrappedValue; v.numberValue = $0; cfg.wrappedValue = v }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                    case .boolean:
                        Toggle("Value", isOn: Binding(
                            get: { cfg.wrappedValue.booleanValue },
                            set: { var v = cfg.wrappedValue; v.booleanValue = $0; cfg.wrappedValue = v }
                        ))
                        .toggleStyle(.switch)
                    }
                }
            } else {
                Text("(More action types coming)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
                    }
                )
            }
        } else {
            graphNodeSummaryCard(
                title: title,
                subtitle: graphNodeSummarySubtitle(for: key),
                systemImage: DashboardActionDescriptor.systemImage(for: key),
                accent: nodeTintColor,
                width: senderNodeWidth,
                detail: warningText ?? subtitle
            )
        }
    }

    base
        .overlay(invalidLinkHoverOverlay(for: nodeId))
        .frame(width: 420)
        .background {
            if showDetailed {
                nodeSizeReporter(nodeId)
            }
        }
        .position(applyViewport(to: nodePosition(for: nodeId)))
        .gesture(nodeDragGesture(tileId: nodeId))
        .contextMenu {
            Button("Duplicate Node") {
                if !selectedGraphNodeIds.contains(nodeId) {
                    selectedGraphNodeIds = [nodeId]
                }
                duplicateSelectedGraphNodes()
            }

            Divider()
            Button("Clear Links") {
                removeIncomingLinks(toNodeId: nodeId)
                removeOutgoingLinks(fromNodeId: nodeId)
            }
            .disabled(tab.graph?.links.isEmpty ?? true)

            Divider()

            Button("Remove Node", role: .destructive) {
                deleteGraphNode(nodeId: nodeId, key: key)
            }
        }
        .onAppear {
            recordGraphNodeMount(kind: key, detailed: showDetailed)
            ensureLayoutForModuleGroupNode(nodeId, groupKey: key)
            ensureGraphForActionConfig()

            if key == "action.sendAllConsoles" {
                if tab.graph?.sendAllConsolesActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.sendAllConsolesActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.SendAllConsolesActionConfig()
                }
            }

            if key == "action.oscSend" {
                if tab.graph?.oscSendActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.oscSendActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.OSCSendActionConfig()
                }
            }

            if key == "action.proPresenterTrigger" {
                if tab.graph?.proPresenterTriggerActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.proPresenterTriggerActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.ProPresenterTriggerActionConfig()
                }
            }

            if key == "action.smartLightControl" {
                if tab.graph?.smartLightActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.smartLightActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.SmartLightActionConfig()
                }
                tab.graph?.nodeIdByPortId[GraphAutomationTraversal.smartLightOutputPortId(nodeId: nodeId, kind: "success")] = nodeId
                tab.graph?.nodeIdByPortId[GraphAutomationTraversal.smartLightOutputPortId(nodeId: nodeId, kind: "failure")] = nodeId
                tab.graph?.nodeIdByPortId[GraphAutomationTraversal.smartLightOutputPortId(nodeId: nodeId, kind: "currentState")] = nodeId
            }

            if key == "action.shureSend" {
                if tab.graph?.shureSendActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.shureSendActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.ShureSendActionConfig()
                }
            }

            if key == "action.sennheiserSend" {
                if tab.graph?.sennheiserSendActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.sennheiserSendActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.SennheiserSendActionConfig()
                }
            }

            if key == "action.notify" {
                if tab.graph?.notifyActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.notifyActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.NotifyActionConfig()
                }
            }

            if key == "action.lanNotify" {
                if tab.graph?.lanNotifyActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.lanNotifyActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.LANNotifyActionConfig()
                }
            }

            if key == "action.appControl" {
                if tab.graph?.appControlActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.appControlActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.AppControlActionConfig()
                }
            }

            if key == "action.midiSend" {
                if tab.graph?.midiSendActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.midiSendActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.MIDISendActionConfig()
                }
            }

            if key == "action.httpRequest" {
                if tab.graph?.httpRequestActionConfigByNodeId[nodeId.uuidString] == nil {
                    tab.graph?.httpRequestActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.HTTPRequestActionConfig()
                }
            }

            if key == "action.setVariable",
               tab.graph?.setVariableActionConfigByNodeId[nodeId.uuidString] == nil {
                tab.graph?.setVariableActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.SetVariableActionConfig()
            }
        }
}

@ViewBuilder
private func delayGraphOnlyNodeView(nodeId: UUID) -> some View {
    let isSelected = selectedGraphNodeIds.contains(nodeId)
    let isHoverReceiver = (hoverReceiverNodeId == nodeId)
    let isLinkingTarget = (linkingFromNodeId != nil)

    let cfg = delayActionConfigBinding(forNodeId: nodeId)

    let base = DelayGraphNodeView(
        nodeId: nodeId,
        isSelected: isSelected,
        isHoverReceiver: isHoverReceiver,
        isLinkingTarget: isLinkingTarget,
        onTapSelect: { handleNodeTapSelect(nodeId) },
        onRun: { runDelayNode(nodeId: nodeId) },
        onOutputDragChanged: { value in
            handleDelayOutputDragChanged(nodeId: nodeId, value: value)
        },
        onOutputDragEnded: { value in
            handleDelayOutputDragEnded(nodeId: nodeId, value: value)
        },
        settings: {
            let delayBinding = Binding<Int>(
                get: { max(0, cfg.wrappedValue.delayMs) },
                set: { newValue in
                    var v = cfg.wrappedValue
                    v.delayMs = max(0, min(10000, newValue))
                    cfg.wrappedValue = v
                }
            )

            DelayActionSettingsView(delayMs: delayBinding)
        }
    )

    base
        .overlay(invalidLinkHoverOverlay(for: nodeId))
        .frame(width: 420)
        .background(nodeSizeReporter(nodeId))
        .position(applyViewport(to: nodePosition(for: nodeId)))
        .gesture(nodeDragGesture(tileId: nodeId))
        .contextMenu {
            Button("Duplicate Node") {
                if !selectedGraphNodeIds.contains(nodeId) {
                    selectedGraphNodeIds = [nodeId]
                }
                duplicateSelectedGraphNodes()
            }

            Divider()
            Button("Clear Links") {
                removeIncomingLinks(toNodeId: nodeId)
                removeOutgoingLinks(fromNodeId: nodeId)
            }
            .disabled(tab.graph?.links.isEmpty ?? true)

            Divider()

            Button("Remove Node", role: .destructive) {
                deleteGraphNode(nodeId: nodeId, key: "utility.delay")
            }
        }
        .onAppear {
            ensureLayoutForModuleGroupNode(nodeId, groupKey: "utility.delay")
            ensureGraphForActionConfig()

            if tab.graph?.delayActionConfigByNodeId[nodeId.uuidString] == nil {
                tab.graph?.delayActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.DelayActionConfig()
            }

            if tab.graph == nil { tab.graph = DashboardGraph() }
            let portId = "node:\(nodeId.uuidString)"
            tab.graph?.nodeIdByPortId[portId] = nodeId
        }
}

@ViewBuilder
private func conditionGraphOnlyNodeView(nodeId: UUID) -> some View {
    let isSelected = selectedGraphNodeIds.contains(nodeId)
    let isHoverReceiver = (hoverReceiverNodeId == nodeId)
    let isLinkingTarget = (linkingFromNodeId != nil)
    let cfg = conditionNodeConfigBinding(forNodeId: nodeId)

    let variableOptions = (tab.graph?.moduleGroupNodeInstances ?? [])
        .filter { $0.groupKey == "utility.variable" }
        .compactMap { inst -> (UUID, String)? in
            guard let variable = tab.graph?.variableNodeConfigByNodeId[inst.id.uuidString] else { return nil }
            let name = variable.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return (inst.id, name.isEmpty ? "Unnamed Variable" : name)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }

    let connections = connectedConditionBranches(from: nodeId)

    let base = ConditionGraphNodeView(
        nodeId: nodeId,
        trueConnected: connections.trueConnected,
        falseConnected: connections.falseConnected,
        isSelected: isSelected,
        isHoverReceiver: isHoverReceiver,
        isLinkingTarget: isLinkingTarget,
        onTapSelect: { handleNodeTapSelect(nodeId) },
        onRun: { GraphAutomationRuntime.shared.debugRunConditionNode(nodeId: nodeId) },
        onOutputDragChanged: { branch, value in
            handleConditionOutputDragChanged(nodeId: nodeId, branch: branch, value: value)
        },
        onOutputDragEnded: { branch, value in
            handleConditionOutputDragEnded(nodeId: nodeId, branch: branch, value: value)
        },
        warningText: conditionMismatchErrors[nodeId],
        warningStyle: .error,
        onDismissWarning: conditionMismatchErrors[nodeId] != nil ? {
            conditionMismatchErrors.removeValue(forKey: nodeId)
        } : nil,
        settings: {
            VStack(alignment: .leading, spacing: 10) {
                    Picker("Source", selection: Binding(
                        get: { cfg.wrappedValue.sourceKind },
                        set: {
                            var v = cfg.wrappedValue
                            v.sourceKind = $0
                            cfg.wrappedValue = v
                        }
                    )) {
                        ForEach(DashboardGraph.ConditionNodeConfig.SourceKind.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.menu)

                    if cfg.wrappedValue.sourceKind == .variable {
                        Picker("Variable", selection: Binding<UUID?>(
                            get: { cfg.wrappedValue.variableNodeId },
                            set: {
                                var v = cfg.wrappedValue
                                v.variableNodeId = $0
                                cfg.wrappedValue = v
                            }
                        )) {
                            Text("Select Variable").tag(Optional<UUID>.none)
                            ForEach(variableOptions, id: \.0) { option in
                                Text(option.1).tag(Optional(option.0))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Picker("Operator", selection: Binding(
                        get: { cfg.wrappedValue.operator },
                        set: {
                            var v = cfg.wrappedValue
                            v.operator = $0
                            cfg.wrappedValue = v
                        }
                    )) {
                        ForEach(DashboardGraph.ConditionNodeConfig.Operator.allCases, id: \.self) { op in
                            Text(op.displayName).tag(op)
                        }
                    }
                    .pickerStyle(.menu)

                    if conditionOperatorNeedsText(cfg.wrappedValue.operator, sourceKind: cfg.wrappedValue.sourceKind) {
                        HStack(spacing: 6) {
                            TextField(
                                "Comparison Text",
                                text: conditionComparisonTextBinding(forNodeId: nodeId, config: cfg),
                                onEditingChanged: { editing in
                                    if editing {
                                        beginEditingConditionComparisonText(forNodeId: nodeId, config: cfg.wrappedValue)
                                    } else {
                                        endEditingConditionComparisonText(forNodeId: nodeId, config: cfg)
                                    }
                                }
                            )
                            .textFieldStyle(.roundedBorder)
                            AutomationVariableInsertButton(
                                title: "Comparison Text",
                                text: conditionComparisonTextBinding(forNodeId: nodeId, config: cfg)
                            )
                        }
                        .onAppear {
                            syncConditionComparisonTextDraft(forNodeId: nodeId, config: cfg.wrappedValue)
                        }
                        .onChange(of: cfg.wrappedValue.comparisonText, initial: true) { _, _ in
                            syncConditionComparisonTextDraft(forNodeId: nodeId, config: cfg.wrappedValue)
                        }
                    }

                    if conditionOperatorNeedsNumber(cfg.wrappedValue.operator, sourceKind: cfg.wrappedValue.sourceKind) {
                        HStack(spacing: 8) {
                            Text("Number")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0", value: Binding(
                                get: { cfg.wrappedValue.comparisonNumber },
                                set: {
                                    var v = cfg.wrappedValue
                                    v.comparisonNumber = $0
                                    cfg.wrappedValue = v
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    if conditionOperatorNeedsBoolean(cfg.wrappedValue.operator, sourceKind: cfg.wrappedValue.sourceKind) {
                        Toggle("Expected Boolean", isOn: Binding(
                            get: { cfg.wrappedValue.comparisonBoolean },
                            set: {
                                var v = cfg.wrappedValue
                                v.comparisonBoolean = $0
                                cfg.wrappedValue = v
                            }
                        ))
                        .toggleStyle(.switch)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        let lastMessage = cfg.wrappedValue.lastPayloadText
                            ?? cfg.wrappedValue.lastPayloadNumber.map { String($0) }
                            ?? cfg.wrappedValue.lastPayloadBoolean.map { $0 ? "true" : "false" }
                            ?? "—"

                        Text("Last Payload")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("Message: \(lastMessage)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Resolved Input: \(cfg.wrappedValue.lastResolvedValueSummary ?? "—")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Last Result: \(cfg.wrappedValue.lastEvaluationResult.map { $0 ? "TRUE" : "FALSE" } ?? "—")")
                            .font(.caption)
                            .foregroundStyle(cfg.wrappedValue.lastEvaluationResult == true ? .green : cfg.wrappedValue.lastEvaluationResult == false ? .red : .secondary)
                    }
                }
        }
    )

    base
        .overlay(invalidLinkHoverOverlay(for: nodeId))
        .frame(width: 420)
        .background(nodeSizeReporter(nodeId))
        .position(applyViewport(to: nodePosition(for: nodeId)))
        .gesture(nodeDragGesture(tileId: nodeId))
        .contextMenu {
            Button("Duplicate Node") {
                if !selectedGraphNodeIds.contains(nodeId) {
                    selectedGraphNodeIds = [nodeId]
                }
                duplicateSelectedGraphNodes()
            }

            Divider()
            Button("Clear Links") {
                removeIncomingLinks(toNodeId: nodeId)
                removeOutgoingLinks(fromNodeId: nodeId)
            }
            .disabled(tab.graph?.links.isEmpty ?? true)

            Divider()

            Button("Remove Node", role: .destructive) {
                deleteGraphNode(nodeId: nodeId, key: "utility.condition")
            }
        }
        .onAppear {
            ensureLayoutForModuleGroupNode(nodeId, groupKey: "utility.condition")
            ensureGraphForActionConfig()
            if tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString] == nil {
                tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString] = DashboardGraph.ConditionNodeConfig()
            }
            if let config = tab.graph?.conditionNodeConfigByNodeId[nodeId.uuidString] {
                syncConditionComparisonTextDraft(forNodeId: nodeId, config: config)
            }

            let portId = GraphAutomationTraversal.defaultPortId(for: nodeId)
            tab.graph?.nodeIdByPortId[portId] = nodeId
            tab.graph?.nodeIdByPortId[GraphAutomationTraversal.conditionOutputPortId(nodeId: nodeId, branch: .`true`)] = nodeId
            tab.graph?.nodeIdByPortId[GraphAutomationTraversal.conditionOutputPortId(nodeId: nodeId, branch: .`false`)] = nodeId
        }
}

@ViewBuilder
private func repeaterGraphOnlyNodeView(nodeId: UUID) -> some View {
    let isSelected = selectedGraphNodeIds.contains(nodeId)
    let isHoverReceiver = (hoverReceiverNodeId == nodeId)
    let isLinkingTarget = (linkingFromNodeId != nil)

    let cfg = repeaterActionConfigBinding(forNodeId: nodeId)

    let outputCount = max(1, cfg.wrappedValue.outputCount)
    let connectedOutputs = min(connectedActionCount(from: nodeId), outputCount)

    let base = RepeaterGraphNodeView(
        nodeId: nodeId,
        outputCount: outputCount,
        connectedOutputCount: connectedOutputs,
        isSelected: isSelected,
        isHoverReceiver: isHoverReceiver,
        isLinkingTarget: isLinkingTarget,
        onTapSelect: { handleNodeTapSelect(nodeId) },
        onRun: { runRepeaterNode(nodeId: nodeId) },
        onOutputDragChanged: { index, value in
            handleRepeaterOutputDragChanged(nodeId: nodeId, index: index, total: outputCount, value: value)
        },
        onOutputDragEnded: { index, value in
            handleRepeaterOutputDragEnded(nodeId: nodeId, index: index, total: outputCount, value: value)
        },
        settings: {
            let outputBinding = Binding<Int>(
                get: { max(1, cfg.wrappedValue.outputCount) },
                set: { newValue in
                    var v = cfg.wrappedValue
                    v.outputCount = max(1, min(8, newValue))
                    cfg.wrappedValue = v
                }
            )

            let repeatBinding = Binding<Int>(
                get: { max(1, cfg.wrappedValue.repeatCount) },
                set: { newValue in
                    var v = cfg.wrappedValue
                    v.repeatCount = max(1, min(50, newValue))
                    cfg.wrappedValue = v
                }
            )

            let delayBinding = Binding<Int>(
                get: { max(0, cfg.wrappedValue.delayMs) },
                set: { newValue in
                    var v = cfg.wrappedValue
                    v.delayMs = max(0, min(5000, newValue))
                    cfg.wrappedValue = v
                }
            )

            RepeaterActionSettingsView(
                outputCount: outputBinding,
                repeatCount: repeatBinding,
                delayMs: delayBinding
            )
        }
    )

    base
        .overlay(invalidLinkHoverOverlay(for: nodeId))
        .frame(width: 420)
        .background(nodeSizeReporter(nodeId))
        .position(applyViewport(to: nodePosition(for: nodeId)))
        .gesture(nodeDragGesture(tileId: nodeId))
        .contextMenu {
            Button("Duplicate Node") {
                if !selectedGraphNodeIds.contains(nodeId) {
                    selectedGraphNodeIds = [nodeId]
                }
                duplicateSelectedGraphNodes()
            }

            Divider()
            Button("Clear Links") {
                removeIncomingLinks(toNodeId: nodeId)
                removeOutgoingLinks(fromNodeId: nodeId)
            }
            .disabled(tab.graph?.links.isEmpty ?? true)

            Divider()

            Button("Remove Node", role: .destructive) {
                deleteGraphNode(nodeId: nodeId, key: "utility.repeater")
            }
        }
        .onAppear {
            ensureLayoutForModuleGroupNode(nodeId, groupKey: "utility.repeater")
            ensureGraphForActionConfig()

            if tab.graph?.repeaterActionConfigByNodeId[nodeId.uuidString] == nil {
                tab.graph?.repeaterActionConfigByNodeId[nodeId.uuidString] = DashboardGraph.RepeaterActionConfig()
            }

            if tab.graph == nil { tab.graph = DashboardGraph() }
            let portId = "node:\(nodeId.uuidString)"
            tab.graph?.nodeIdByPortId[portId] = nodeId
            let outputCount = max(1, tab.graph?.repeaterActionConfigByNodeId[nodeId.uuidString]?.outputCount ?? 1)
            for index in 0..<outputCount {
                let outputPortId = GraphAutomationTraversal.repeaterOutputPortId(nodeId: nodeId, index: index)
                tab.graph?.nodeIdByPortId[outputPortId] = nodeId
            }
        }
}
@ViewBuilder private var automationEmptyStateOverlay: some View {
    if !(tab.graph?.hasAutomationContent ?? false) && !showAddNodePopover {
        VStack(spacing: 6) {
            Image(systemName: tab.automationMode == .universal ? "link" : "lock")
                .font(.system(size: 22))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(tab.automationMode == .universal
                 ? "This automation is shared by all tabs."
                 : "This automation runs only on \u{201C}\(tab.name)\u{201D}.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
            Text("Add a trigger to get started.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(20)
        .allowsHitTesting(false)
    }
}

var body: some View {
    // Keep Graph mounted for flip animation/state, but skip heavy work when not visible.
    if !isWorkEnabled {
        Color.clear
    } else {
        GeometryReader { geo in
            let groups = computedModuleGroups()
            let canvasPeopleMembers = computedCanvasPeopleMembers(groups: groups)
            let peopleContext = GraphDashboardDataModel.resolvePeopleContext(
                groups: groups,
                canvasPeopleMembers: canvasPeopleMembers,
                cachedSynthesizedPeopleMembersFromPCO: cachedSynthesizedPeopleMembersFromPCO,
                pcoTeamOptionsFromTab: pcoTeamOptionsFromTab
            )

            graphSceneView(
                geoSize: geo.size,
                groups: peopleContext.groups,
                canvasPeopleMembers: peopleContext.canvasPeopleMembers,
                teamOptions: peopleContext.teamOptions
            )
            .focusable(true)
            .focused($graphIsFocused)
            #if os(macOS)
            .focusEffectDisabled(true)
            .onDeleteCommand {
                guard shouldHandleGraphDeleteKey() else { return }
                deleteSelectedGraphNodes()
            }
            .background(
                GraphDeleteKeyMonitor(
                    isEnabled: shouldHandleGraphDeleteKey(),
                    onDelete: deleteSelectedGraphNodes
                )
            )
            .onReceive(NotificationCenter.default.publisher(for: .duplicateGraphNodesRequested)) { _ in
                duplicateSelectedGraphNodes()
            }
            #endif
        }
        .onAppear {
            // Graph view must explicitly point the always-on runtime at the live bound tab.
            activateGraphRuntime()
            _ = installSendAllListenerIfNeeded()
            #if os(macOS)
            dismissGraphTextInput()
            #endif
        }
        .onDisappear {
            finalizePendingGraphEditUndo()
            addNodeSearchIsFocused = false
            graphIsFocused = false
            #if os(macOS)
            NSApp.keyWindow?.makeFirstResponder(nil)
            #endif
            selectedGraphNodeIds.removeAll()
            linkingFromNodeId = nil
            linkingFromPoint = nil
            linkingCurrentPoint = nil
            clearLinkHoverState()
        }
        .onChange(of: tab.id, initial: false) { _, _ in
            activateGraphRuntime()
            #if os(macOS)
            dismissGraphTextInput()
            #endif
        }
        .animation(.none, value: liveModeFromStorage)
        .onChange(of: isWorkEnabled, initial: false) { _, enabled in
            // Never disable automations from the Graph view; only re-enable when graph becomes active.
            guard enabled else { return }
            activateGraphRuntime()
        }
        .onChange(of: tab.graph?.links, initial: false) { _, _ in
            refreshSendAllListenerForGraphChange()
        }
        .onChange(of: tab.graph?.nodeIdByPortId.count ?? 0, initial: false) { _, _ in
            refreshSendAllListenerForGraphChange()
        }
        .onChange(of: tab.graph, initial: false) { _, _ in
            onGraphChanged?()
        }
        .onReceive(NotificationCenter.default.publisher(for: .prodlinkGraphSendAllToConsoles)) { note in
            let installedNow = installSendAllListenerIfNeeded()
            if installedNow {
                NotificationCenter.default.post(
                    name: .prodlinkGraphSendAllToConsoles,
                    object: note.object,
                    userInfo: note.userInfo
                )
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: .prodLinkToggleGraphNodeVisibilityRequested)) { _ in
            toggleHiddenForSelectedGraphNodes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .prodLinkDeleteGraphSelectionRequested)) { _ in
            deleteSelectedGraphNodes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .prodLinkUnhideAllGraphNodesRequested)) { _ in
            unhideAllGraphNodes()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .prodLinkGraphSelectionCountChanged, object: 0)
        }
        .onChange(of: hiddenGraphNodeIds, initial: true) { _, _ in
            updateHiddenNodesFlag()
        }
        .onAppear {
            if !didShowMigrationNotice {
                let assignmentsJSON = UserDefaults.standard.string(forKey: "osc.directSend.assignments") ?? "{}"
                let snapshotsJSON = UserDefaults.standard.string(forKey: "osc.directSend.snapshots") ?? "{}"
                let hasOldData = (assignmentsJSON != "{}" && !assignmentsJSON.isEmpty)
                    || (snapshotsJSON != "{}" && !snapshotsJSON.isEmpty)
                if hasOldData {
                    showTriggerSendMigrationAlert = true
                } else {
                    didShowMigrationNotice = true
                }
            }
        }
        .alert("Trigger-to-Console Settings Moved", isPresented: $showTriggerSendMigrationAlert) {
            Button("OK") {
                didShowMigrationNotice = true
            }
        } message: {
            Text("Your trigger-to-console send settings have moved to the console node. Please reconfigure your trigger bindings on each console node in the Automation view.")
        }
    }
}


@ViewBuilder
private func addNodePopover(in canvasSize: CGSize, currentGroups: [ModuleGroup]) -> some View {
    let query = addNodeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    let categories: [String] = {
        let cats = Array(Set(addableGroups.map { $0.category })).sorted()
        return ["All"] + cats
    }()

        let candidates: [AddableGroup] = {
            var base = addableGroups.filter { $0.isEnabled }
        if addNodeSelectedCategory != "All" {
            base = base.filter { $0.category == addNodeSelectedCategory }
        }
        if !query.isEmpty {
            base = base.filter { g in
                g.title.lowercased().contains(query) ||
                g.id.lowercased().contains(query) ||
                g.category.lowercased().contains(query)
            }
        }
        if addNodeSelectedCategory == "All" {
            base = base.sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        return base
    }()

    ZStack {
        // Dimmed backdrop (tap to dismiss)
        Button {
            showAddNodePopover = false
        } label: {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss add node popover")

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .imageScale(.medium)
                    .opacity(0.85)

                Text("Add Node")
                    .font(.headline)

                Spacer()

                Button { showAddNodePopover = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                        .opacity(0.75)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Search (module-browser style)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search nodes", text: $addNodeSearchText)
                    .textFieldStyle(.plain)
                    .focused($addNodeSearchIsFocused)

                if !addNodeSearchText.isEmpty {
                    Button { addNodeSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                    .fill(Color.white.opacity(GraphNodeStyleTokens.cardFillOpacity))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.25)

            // Two-column layout
            HStack(spacing: 0) {
                // Left sidebar
                addNodeSidebar(categories: categories)

                Divider().opacity(0.20)

                // Right list
                addNodeCandidatesList(candidates: candidates, query: query, canvasSize: canvasSize)
            }
            .frame(height: 420)
        }
        .frame(width: 660)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(radius: 28)
        .overlay {
            if let help = addNodeHelpMessage {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .overlay {
                            Button {
                                addNodeHelpMessage = nil
                            } label: {
                                Color.clear
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss help message")
                        }

                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .imageScale(.medium)
                                .foregroundStyle(.secondary)
                            Text(help.title)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Button {
                                addNodeHelpMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .imageScale(.medium)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(help.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(radius: 22)
                    .frame(maxWidth: 420)
                    .padding(24)
                }
            }
        }
    }
    .sheet(
        isPresented: Binding(
            get: { destinationPickerState != nil },
            set: { if !$0 { destinationPickerState = nil } }
        )
    ) {
        if let state = destinationPickerState {
            VStack(spacing: 12) {
                HStack {
                    Text("Select Destination")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Button("Cancel") {
                        destinationPickerState = nil
                    }
                    .keyboardShortcut(.cancelAction)
                }

                Text(state.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.options) { option in
                            Button {
                                handleDestinationSelection(groupKey: state.groupKey, deviceId: option.id, canvasSize: canvasSize)
                            } label: {
                                HStack {
                                    Text(option.title)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                                        .fill(Color.white.opacity(GraphNodeStyleTokens.cardFillOpacity))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
            .padding(16)
            .frame(width: 360)
        }
    }
    .onAppear {
        if !categories.contains(addNodeSelectedCategory) {
            addNodeSelectedCategory = "All"
        }
        DispatchQueue.main.async {
            addNodeSearchIsFocused = true
        }
        addNodeHelpMessage = nil
    }
//        .onTapGesture {
//            addNodeSearchIsFocused = false
//            showAddNodePopover = false
//        }
}

// MARK: - Module group node view builders (type-checker friendly)

@ViewBuilder
private func canvasBackedModuleGroupNodeView(
    nodeId: UUID,
    group: ModuleGroup,
    peopleTeamOptions: [String]
) -> some View {
    let base = ModuleGroupNodeView(
        nodeId: nodeId,
        group: group,
        tab: tab,
        consoleDevices: availableAudioConsoleDevices,
        shureDevices: availableShureDevices,
        sennheiserDevices: availableSennheiserDevices,
        peopleTeamOptions: (group.key == "moduleGroup.person" ? peopleTeamOptions : []),
        selectedPeopleTeams: (group.key == "moduleGroup.person"
                              ? peopleTeamSelectionBinding(forNodeId: nodeId)
                              : Binding.constant(Set<String>())),
        customPeople: Binding.constant([]),
        isSelected: selectedGraphNodeIds.contains(nodeId),
        peopleSourceMode: Binding.constant("pco"),
        graph: $tab.graph,
        performGraphEdit: performGraphEdit
    )

    base
        .frame(width: 420)
        .background(nodeSizeReporter(nodeId))
        .overlay(invalidLinkHoverOverlay(for: nodeId))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(linkingFromNodeId == nodeId ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(selectedGraphNodeIds.contains(nodeId) ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .trailing) {
            let isWordOrTranscriptionTrigger = group.key.contains("wordTrigger") || group.key.contains("transcription")
            let rules = isWordOrTranscriptionTrigger ? (tab.graph?.wordTriggerConfigByNodeId[nodeId.uuidString]?.rules ?? []) : []

            if isWordOrTranscriptionTrigger && !rules.isEmpty {
                // Per-rule output nubs — one per word trigger rule
                VStack(spacing: 14) {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 4) {
                            Text(rule.phrase.isEmpty ? "Rule \(index + 1)" : rule.phrase)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 70, alignment: .trailing)
                            ZStack(alignment: .trailing) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 26, height: 20)
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(
                                        DragGesture(minimumDistance: 4, coordinateSpace: .named("GraphSceneSpace"))
                                            .onChanged { handleWordTriggerOutputDragChanged(nodeId: nodeId, ruleId: rule.id, ruleIndex: index, total: max(1, rules.count), value: $0) }
                                            .onEnded   { handleWordTriggerOutputDragEnded(nodeId: nodeId, ruleId: rule.id, value: $0) }
                                    )
                                Circle()
                                    .fill(linkingFromNodeId == nodeId && currentWordTriggerRuleId == rule.id
                                          ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.70))
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                                    .offset(x: 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
            } else {
                // Default single output nub (Q‑Sys style)
                ZStack(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .highPriorityGesture(linkDragGestureFromSenderNub(nodeId: nodeId))
                        .accessibilityLabel("Link output")
                    Circle()
                        .fill(linkingFromNodeId == nodeId ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.70))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                        .offset(x: 5)
                        .allowsHitTesting(false)
                }
            }
        }
        .contentShape(Rectangle())
        .position(applyViewport(to: nodePosition(for: nodeId)))
        .simultaneousGesture(
            TapGesture().onEnded { handleNodeTapSelect(nodeId) }
        )
        .gesture(nodeDragGesture(tileId: nodeId))
        .contextMenu {
            Button("Clear Links") {
                removeOutgoingLinks(fromNodeId: nodeId)
            }
            .disabled(tab.graph?.links.isEmpty ?? true)

            // Canvas-backed group nodes are not removable.
        }
        .onAppear {
            ensureLayoutForModuleGroupNode(nodeId, groupKey: group.key)

            if tab.graph == nil { tab.graph = DashboardGraph() }
            let portId = "node:\(nodeId.uuidString)"
            tab.graph?.nodeIdByPortId[portId] = nodeId

            // Register per-rule ports for word/transcription trigger nodes.
            if group.key.contains("wordTrigger") || group.key.contains("transcription") {
                sweepOrphanedWordTriggerConfigs(canonicalNodeId: nodeId)
                let rules = tab.graph?.wordTriggerConfigByNodeId[nodeId.uuidString]?.rules ?? []
                for rule in rules {
                    tab.graph?.nodeIdByPortId[GraphAutomationTraversal.wordTriggerRulePortId(nodeId: nodeId, ruleId: rule.id)] = nodeId
                }
            }
        }
        .onChange(of: tab.graph?.wordTriggerConfigByNodeId[nodeId.uuidString]?.rules.count) { _, _ in
            guard group.key.contains("wordTrigger") || group.key.contains("transcription") else { return }
            let rules = tab.graph?.wordTriggerConfigByNodeId[nodeId.uuidString]?.rules ?? []
            for rule in rules {
                tab.graph?.nodeIdByPortId[GraphAutomationTraversal.wordTriggerRulePortId(nodeId: nodeId, ruleId: rule.id)] = nodeId
            }
        }
}

@ViewBuilder
private func graphOnlyModuleGroupNodeView(
    nodeId: UUID,
    key: String,
    syntheticGroup: ModuleGroup,
    peopleTeamOptions: [String]
) -> some View {
    if key == "destination.vista" {
        EmptyView()
    } else {
    let canReceiveLinks = GraphLinkPolicy.canReceiveLinks(
        nodeRole: linkNodeRole(for: nodeId),
        features: graphLinkFeatureFlags
    )
    let isHoverReceiver = (hoverReceiverNodeId == nodeId)
    let isHoverInvalidReceiver = (hoverInvalidReceiverNodeId == nodeId)
    let showDetailed = shouldRenderDetailedGraphNode(nodeId)
    let detailText = graphNodeSummaryDetailText(nodeId: nodeId, key: key, syntheticGroup: syntheticGroup)
    moduleGroupNodeBaseView(
        nodeId: nodeId,
        key: key,
        syntheticGroup: syntheticGroup,
        peopleTeamOptions: peopleTeamOptions,
        showDetailed: showDetailed,
        detailText: detailText
    )
        .frame(width: 420)
        .background {
            if showDetailed {
                nodeSizeReporter(nodeId)
            }
        }
        .overlay(invalidLinkHoverOverlay(for: nodeId))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(linkingFromNodeId == nodeId ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(selectedGraphNodeIds.contains(nodeId) ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(canReceiveLinks && isHoverReceiver ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .leading) {
            if canReceiveLinks {
                Circle()
                    .fill(
                        isHoverInvalidReceiver
                        ? Color.red.opacity(0.90)
                        : (isHoverReceiver ? Color.accentColor.opacity(0.95) : Color.purple.opacity(0.80))
                    )
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                    .offset(x: -5)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .trailing) {
            if isToggleNodeId(nodeId) {
                // Two output nubs: top = On, bottom = Off
                VStack(spacing: 14) {
                    ForEach([true, false], id: \.self) { isOn in
                        ZStack(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 26, height: 20)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 4, coordinateSpace: .named("GraphSceneSpace"))
                                        .onChanged { handleToggleOutputDragChanged(nodeId: nodeId, isOn: isOn, value: $0) }
                                        .onEnded   { handleToggleOutputDragEnded(nodeId: nodeId, isOn: isOn, value: $0) }
                                )
                            Circle()
                                .fill(linkingFromNodeId == nodeId && currentToggleOutputIsOn == isOn
                                      ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.70))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                                .offset(x: 5)
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else if isSequenceNodeId(nodeId) {
                // N output nubs (top → bottom = step 1 → step N)
                let total = sequenceOutputLimit(for: nodeId)
                VStack(spacing: 14) {
                    ForEach(0..<total, id: \.self) { step in
                        ZStack(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 26, height: 20)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 4, coordinateSpace: .named("GraphSceneSpace"))
                                        .onChanged { handleSequenceOutputDragChanged(nodeId: nodeId, step: step, total: total, value: $0) }
                                        .onEnded   { handleSequenceOutputDragEnded(nodeId: nodeId, step: step, total: total, value: $0) }
                                )
                            Circle()
                                .fill(linkingFromNodeId == nodeId && currentSequenceOutputStep == step
                                      ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.70))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                                .offset(x: 5)
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else if isWordTriggerNodeId(nodeId) {
                // Standalone word trigger nodes share the transcription node's config.
                let canonicalId = isStandaloneWordTriggerNodeId(nodeId)
                    ? groupNodeId(for: "moduleGroup.transcription")
                    : nodeId
                let rules = tab.graph?.wordTriggerConfigByNodeId[canonicalId.uuidString]?.rules ?? []
                let total = max(1, rules.count)
                VStack(spacing: 14) {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 4) {
                            Text(rule.phrase.isEmpty ? "Rule \(index + 1)" : rule.phrase)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 70, alignment: .trailing)
                            ZStack(alignment: .trailing) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 26, height: 20)
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(
                                        DragGesture(minimumDistance: 4, coordinateSpace: .named("GraphSceneSpace"))
                                            .onChanged { handleWordTriggerOutputDragChanged(nodeId: canonicalId, ruleId: rule.id, ruleIndex: index, total: total, value: $0) }
                                            .onEnded   { handleWordTriggerOutputDragEnded(nodeId: canonicalId, ruleId: rule.id, value: $0) }
                                    )
                                Circle()
                                    .fill(linkingFromNodeId == nodeId && currentWordTriggerRuleId == rule.id
                                          ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.70))
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                                    .offset(x: 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
            } else if isMultiButtonNodeId(nodeId) {
                let buttons = buttonsForButtonNode(nodeId)
                VStack(spacing: 14) {
                    ForEach(Array(buttons.enumerated()), id: \.element.id) { index, button in
                        HStack(spacing: 4) {
                            // Label: title → icon symbol name → "Button N"
                            let title = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            let iconLabel: String = {
                                switch button.icon.source {
                                case .preset: return button.icon.preset.title
                                case .symbol, .customSymbol:
                                    let s = button.icon.systemName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    return s.isEmpty ? "Button \(index + 1)" : s
                                case .none: return "Button \(index + 1)"
                                }
                            }()
                            Text(title.isEmpty ? iconLabel : title)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 70, alignment: .trailing)

                            ZStack(alignment: .trailing) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 26, height: 20)
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(
                                        DragGesture(minimumDistance: 4, coordinateSpace: .named("GraphSceneSpace"))
                                            .onChanged { handleButtonOutputDragChanged(nodeId: nodeId, buttonIndex: index, buttons: buttons, value: $0) }
                                            .onEnded { handleButtonOutputDragEnded(nodeId: nodeId, buttonIndex: index, buttons: buttons, value: $0) }
                                    )
                                Circle()
                                    .fill(linkingFromNodeId == nodeId && currentButtonOutputConfigId == button.id
                                          ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.70))
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                                    .offset(x: 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
            } else {
            ZStack(alignment: .trailing) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .highPriorityGesture(linkDragGestureFromSenderNub(nodeId: nodeId))
                    .accessibilityLabel("Link output")

                Circle()
                    .fill(
                        linkingFromNodeId == nodeId
                        ? Color.accentColor.opacity(0.95)
                        : (isGraphVariablesFeatureEnabled && key == "utility.variable" ? Color.purple.opacity(0.80) : Color.white.opacity(0.70))
                    )
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                    .offset(x: 5)
                    .allowsHitTesting(false)
            }
            } // end else (single nub)
        }
        .contentShape(Rectangle())
        .position(applyViewport(to: nodePosition(for: nodeId)))
        .simultaneousGesture(
            TapGesture().onEnded { handleNodeTapSelect(nodeId) }
        )
        .gesture(nodeDragGesture(tileId: nodeId))
        .contextMenu {
            let isButtonTrigger = key == DashboardGraph.buttonTriggerGroupKey

            Button("Duplicate Node") {
                if !selectedGraphNodeIds.contains(nodeId) {
                    selectedGraphNodeIds = [nodeId]
                }
                duplicateSelectedGraphNodes()
            }
            .disabled(isButtonTrigger)

            Divider()
            Button("Clear Links") {
                removeIncomingLinks(toNodeId: nodeId)
                removeOutgoingLinks(fromNodeId: nodeId)
            }
            .disabled(tab.graph?.links.isEmpty ?? true)

            if !isButtonTrigger {
                Divider()
                Button("Remove Node", role: .destructive) {
                    deleteGraphNode(nodeId: nodeId, key: key)
                }
            }
        }
        .onAppear {
            recordGraphNodeMount(kind: key, detailed: showDetailed)
            registerGraphOnlyModuleGroupNodeAppearance(nodeId: nodeId, key: key)
        }
        .onChange(of: tab.graph?.wordTriggerConfigByNodeId[groupNodeId(for: "moduleGroup.transcription").uuidString]?.rules.count) { _, _ in
            guard key == "moduleGroup.wordTrigger" else { return }
            registerGraphOnlyModuleGroupNodeAppearance(nodeId: nodeId, key: key)
        }
    }
}

@ViewBuilder
private func moduleGroupNodeBaseView(
    nodeId: UUID,
    key: String,
    syntheticGroup: ModuleGroup,
    peopleTeamOptions: [String],
    showDetailed: Bool,
    detailText: String
) -> some View {
    if showDetailed {
        if isTriggerGroupKey(key) {
            let sharedWordTriggerKey: String? = (key == "moduleGroup.wordTrigger")
                ? groupNodeId(for: "moduleGroup.transcription").uuidString
                : nil
            TriggerGraphNodeView(
                nodeId: nodeId,
                group: syntheticGroup,
                graph: $tab.graph,
                isSelected: selectedGraphNodeIds.contains(nodeId),
                performGraphEdit: performGraphEdit,
                pcoRundownSnapshotTitles: tab.pcoRundownSnapshotTitles,
                wordTriggerSharedConfigKey: sharedWordTriggerKey
            )
        } else {
            ModuleGroupNodeView(
                nodeId: nodeId,
                group: syntheticGroup,
                tab: tab,
                consoleDevices: availableAudioConsoleDevices,
                shureDevices: availableShureDevices,
                sennheiserDevices: availableSennheiserDevices,
                peopleTeamOptions: (key == "moduleGroup.person" ? peopleTeamOptions : []),
                selectedPeopleTeams: (key == "moduleGroup.person"
                                      ? peopleTeamSelectionBinding(forNodeId: nodeId)
                                      : Binding.constant(Set<String>())),
                customPeople: (key == "moduleGroup.person" ? customPeopleEntriesBinding(forNodeId: nodeId) : Binding.constant([])),
                isSelected: selectedGraphNodeIds.contains(nodeId),
                peopleSourceMode: (key == "moduleGroup.person"
                                  ? peopleSourceModeBinding(forNodeId: nodeId)
                                  : Binding.constant("pco")),
                graph: $tab.graph,
                performGraphEdit: performGraphEdit
            )
        }
    } else {
        graphNodeSummaryCard(
            title: syntheticGroup.title,
            subtitle: graphNodeSummarySubtitle(for: key),
            systemImage: graphNodeSummaryIcon(for: key),
            accent: GraphNodeCategory(nodeKey: key).tintColor,
            width: senderNodeWidth,
            detail: detailText
        )
    }
}

@ViewBuilder
private func moduleGroupNodesLayer(in size: CGSize, groups: [ModuleGroup], peopleTeamOptions: [String]) -> some View {
    let prepStart = CFAbsoluteTimeGetCurrent()
    let instances: [DashboardGraph.ModuleGroupNodeInstance] = tab.graph?.moduleGroupNodeInstances ?? []  
    let hidden = hiddenGraphNodeIds

    // Canvas-backed nodes should always appear when their backing tiles/modules exist.
    // Defensive: if caches are mid-refresh and `groups` is missing People even though person tiles exist,
    // build it once and include it so the node doesn't disappear.
    let canvasGroups: [ModuleGroup] = {
        // Normal path
        if groups.contains(where: { $0.key ==   "moduleGroup.person" }) {
            return groups.filter { $0.isCanvasBacked }
        }

        // If the snapshot has any Person modules/tiles, ensure the People group exists.
        let hasPersonTiles = snapshotHasPersonTiles(tilesSnapshot)

        guard hasPersonTiles,
              let fallback = computedModuleGroups().first(where: { $0.key == "moduleGroup.person" })
        else {
            return groups.filter { $0.isCanvasBacked }
        }

        return (groups + [fallback]).filter { $0.isCanvasBacked }
    }()

    let visibleCanvasGroups = canvasGroups.filter { !hidden.contains(groupNodeId(for: $0.key)) }
    let visibleInstances = instances.filter { !hidden.contains($0.id) }
    let detailedCanvasCount = visibleCanvasGroups.reduce(into: 0) { count, group in
        if shouldRenderDetailedGraphNode(groupNodeId(for: group.key)) { count += 1 }
    }
    let detailedInstanceCount = visibleInstances.reduce(into: 0) { count, inst in
        if shouldRenderDetailedGraphNode(inst.id) { count += 1 }
    }
    let _ = {
        recordGraphLayerPreparation(
            key: "ui.graph.moduleGroups.prepare",
            duration: CFAbsoluteTimeGetCurrent() - prepStart,
            details: "canvas=\(visibleCanvasGroups.count) instances=\(visibleInstances.count) detailed=\(detailedCanvasCount + detailedInstanceCount) summary=\((visibleCanvasGroups.count + visibleInstances.count) - (detailedCanvasCount + detailedInstanceCount))"
        )
        return 0
    }()
    ForEach(visibleCanvasGroups) { group in
        let nodeId = groupNodeId(for: group.key)
        canvasBackedModuleGroupNodeView(nodeId: nodeId, group: group, peopleTeamOptions: peopleTeamOptions)
    }

    ForEach(visibleInstances, id: \.id) { inst in
        let nodeId = inst.id
        let key = inst.groupKey

        Group {
            // Action nodes are graph-only and have their own UI.
            if key == "destination.console" {
                EmptyView()
            } else if key == "destination.vista" {
                EmptyView()
            } else if key.hasPrefix("action.") {
                actionGraphOnlyNodeView(nodeId: nodeId, key: key)
            } else if key == "utility.condition", isGraphConditionalsFeatureEnabled {
                conditionGraphOnlyNodeView(nodeId: nodeId)
            } else if key == "utility.condition" {
                EmptyView()
            } else if key == "utility.repeater" {
                repeaterGraphOnlyNodeView(nodeId: nodeId)
            } else if key == "utility.delay" {
                delayGraphOnlyNodeView(nodeId: nodeId)
            } else {
                let baseGroup = groups.first(where: { $0.key == key })

                let members: [ModuleMember] = {
                    if key == "moduleGroup.person" {
                        let mode = tab.graph?.peopleSourceByNodeId[nodeId.uuidString] ?? "pco"

                        func customMembers() -> [ModuleMember] {
                            let custom = tab.graph?.customPeopleByNodeId[nodeId.uuidString] ?? []
                            return custom.compactMap { entry in
                                let pos = entry.position.trimmingCharacters(in: .whitespacesAndNewlines)
                                let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !pos.isEmpty, !name.isEmpty else { return nil }
                                return ModuleMember(
                                    tileId: tab.id,
                                    moduleId: stableUUID(for: "customPerson|\(nodeId.uuidString)|\(entry.id.uuidString)"),
                                    title: "\(pos) — \(name)",
                                    teamName: entry.teamName
                                )
                            }
                        }

                        if mode == "custom" {
                            // Custom-only: no PCO
                            let custom = customMembers()
                            var seen = Set<String>()
                            return custom.filter { seen.insert($0.title).inserted }
                        } else {
                            // PCO mode: PCO list + custom additions (filtered by selected teams)
                            let nodeFilter = Set(tab.graph?.peopleTeamFiltersByNodeId[nodeId.uuidString] ?? [])
                            let effectiveTeams: Set<String> = nodeFilter.isEmpty ? tabTeamFilter : nodeFilter
                            func applyTeamFilter(_ members: [ModuleMember]) -> [ModuleMember] {
                                guard !effectiveTeams.isEmpty else { return members }
                                return members.filter { member in
                                    guard let team = member.teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
                                          !team.isEmpty else {
                                        return false
                                    }
                                    return effectiveTeams.contains(team)
                                }
                            }

                            var combined = cachedSynthesizedPeopleMembersFromPCO
                            combined.append(contentsOf: customMembers())
                            combined = applyTeamFilter(combined)

                            var seen = Set<String>()
                            return combined.filter { seen.insert($0.title).inserted }
                        }
                    }

                    // Other instance nodes: mirror canvas-backed members (if any)
                    if key.hasPrefix("source."), let graph = tab.graph {
                        return sourceMembers(nodeId: nodeId, groupKey: key, graph: graph)
                    }
                    return baseGroup?.members ?? []
                }()

                let resolvedTitle: String = {
                    if key == DashboardGraph.buttonTriggerGroupKey {
                        return resolveCanvasButtonTitle(forButtonModuleId: nodeId)
                    }
                    return baseGroup?.title ?? groupTitle(for: key)
                }()

                let synthetic = ModuleGroup(
                    key: key,
                    title: resolvedTitle,
                    members: members,
                    isCanvasBacked: key == DashboardGraph.buttonTriggerGroupKey
                )

                graphOnlyModuleGroupNodeView(
                    nodeId: nodeId,
                    key: key,
                    syntheticGroup: synthetic,
                    peopleTeamOptions: peopleTeamOptions
                )
            }
        }
    }
}

// MARK: - Console node view builders (type-checker friendly)

private func handleConsoleAssign(deviceId: UUID, personLabel: String, channel: Int?) {
    ExternalDevicesStore.shared.updateDevice(id: deviceId) { cfg in
        if let channel {
            cfg.consoleChannelAssignments[personLabel] = channel
        } else {
            cfg.consoleChannelAssignments.removeValue(forKey: personLabel)
        }
    }
}

private func normalizedConsolePositionKey(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .lowercased()
}

private func autoAssignedConsoleChannels(
    startingWith existingAssignments: [String: Int],
    config: ExternalDeviceConfig,
    members: [ModuleMember]
) -> [String: Int] {
    var assignments = existingAssignments

    // Channel options come from imported DiGiCo RTF when available.
    let options: [Int] = {
        if !config.digicoInputChannels.isEmpty { return config.digicoInputChannels.map(\.channel) }
        return Array(1...128)
    }()

    let normalizedDefaults: [String: Int] = Dictionary(
        uniqueKeysWithValues: config.consolePositionChannelDefaults.compactMap { key, channel in
            let normalized = normalizedConsolePositionKey(key)
            guard !normalized.isEmpty else { return nil }
            return (normalized, channel)
        }
    )

    // 1) Apply fixed position defaults first (e.g. "Soprano 1" -> 45).
    // Defaults are authoritative when Auto is pressed, even if a row
    // already has an older auto/manual assignment.
    for m in members {
        let position = m.title.components(separatedBy: " — ").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !position.isEmpty else { continue }

        let normalizedPosition = normalizedConsolePositionKey(position)
        if let fixed = normalizedDefaults[normalizedPosition], fixed > 0 {
            assignments[m.title] = fixed
        }
    }

    // 2) Fill remaining from the available list, avoiding duplicates.
    var used = Set(assignments.values)
    var available = options.filter { !used.contains($0) }

    for m in members {
        if assignments[m.title] != nil { continue }
        guard let next = available.first else { break }
        assignments[m.title] = next
        used.insert(next)
        available.removeFirst()
    }

    return assignments
}

private func handleConsoleAutoAssign(deviceId: UUID, members: [ModuleMember]) -> [String: Int] {
    guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceId }) else { return [:] }
    let assignments = autoAssignedConsoleChannels(
        startingWith: device.consoleChannelAssignments,
        config: device,
        members: members
    )

    ExternalDevicesStore.shared.updateDevice(id: deviceId) { cfg in
        cfg.consoleChannelAssignments = assignments
    }

    return assignments
}

private func handleConsoleClearAssignments(deviceId: UUID) {
    ExternalDevicesStore.shared.updateDevice(id: deviceId) { cfg in
        cfg.consoleChannelAssignments.removeAll()
    }
}

private func handleConsoleNameFormat(deviceId: UUID, format: String) {
    ExternalDevicesStore.shared.updateDevice(id: deviceId) { cfg in
        cfg.consoleNameFormat = format
    }
}

private func handleConsoleNameCasing(deviceId: UUID, casing: String) {
    ExternalDevicesStore.shared.updateDevice(id: deviceId) { cfg in
        cfg.consoleNameCasing = casing
    }
}

private func handleConsoleSnapshotCasing(deviceId: UUID, casing: String) {
    ExternalDevicesStore.shared.updateDevice(id: deviceId) { cfg in
        cfg.consoleSnapshotNameCasing = casing
    }
}

private func handleConsoleSnapshotShortenEnabled(deviceId: UUID, enabled: Bool) {
    ExternalDevicesStore.shared.updateDevice(id: deviceId) { cfg in
        cfg.consoleSnapshotShortenEnabled = enabled
    }
}

private func handleConsoleSnapshotShortenLimit(deviceId: UUID, limit: Int) {
    ExternalDevicesStore.shared.updateDevice(id: deviceId) { cfg in
        cfg.consoleSnapshotShortenLimit = limit
    }
}

private func registerGraphOnlyModuleGroupNodeAppearance(nodeId: UUID, key: String) {
    ensureLayoutForModuleGroupNode(nodeId, groupKey: key)

    if tab.graph == nil { tab.graph = DashboardGraph() }
    let portId = "node:\(nodeId.uuidString)"
    tab.graph?.nodeIdByPortId[portId] = nodeId

    let isVariableNode = key == "utility.variable"
    let hasVariableConfig = tab.graph?.variableNodeConfigByNodeId[nodeId.uuidString] != nil
    if isGraphVariablesFeatureEnabled && isVariableNode && !hasVariableConfig {
        tab.graph?.variableNodeConfigByNodeId[nodeId.uuidString] =
            DashboardGraph.VariableNodeConfig(id: nodeId)
    }

    // Register toggle output port IDs so link resolution works.
    if key == "utility.toggle" {
        let onPortId  = GraphAutomationTraversal.toggleOutputPortId(nodeId: nodeId, isOn: true)
        let offPortId = GraphAutomationTraversal.toggleOutputPortId(nodeId: nodeId, isOn: false)
        tab.graph?.nodeIdByPortId[onPortId]  = nodeId
        tab.graph?.nodeIdByPortId[offPortId] = nodeId
    }

    // Register sequence output port IDs (re-registers whenever stepCount changes).
    if key == "utility.sequence" {
        let stepCount = tab.graph?.sequenceNodeConfigByNodeId[nodeId.uuidString]?.stepCount ?? 3
        for step in 0..<stepCount {
            let stepPortId = GraphAutomationTraversal.sequenceOutputPortId(nodeId: nodeId, step: step)
            tab.graph?.nodeIdByPortId[stepPortId] = nodeId
        }
    }

    // Register word trigger rule port IDs (one per rule).
    // Standalone word trigger nodes share the transcription node's config and port IDs
    // so that rules added on either node are treated as identical by the runtime.
    if key == "moduleGroup.wordTrigger" {
        let canonicalNodeId = groupNodeId(for: "moduleGroup.transcription")
        let canonicalKey = canonicalNodeId.uuidString

        // One-time migration: a stale per-node config from before nodes were synced
        // (or before this node existed as an alias) would otherwise sit as an orphaned
        // entry that the runtime still evaluates independently, causing duplicate fires
        // and stale rules. Merge it into the canonical config, repoint any links that used
        // the old per-node port IDs to the matching canonical rule's port, then delete the
        // stale entry so it's never evaluated again.
        if nodeId.uuidString != canonicalKey,
           let staleCfg = tab.graph?.wordTriggerConfigByNodeId[nodeId.uuidString] {
            var canonicalCfg = tab.graph?.wordTriggerConfigByNodeId[canonicalKey] ?? DashboardGraph.WordTriggerConfig()
            var canonicalRuleIdByPhrase: [String: UUID] = [:]
            for canonicalRule in canonicalCfg.rules {
                let phraseKey = canonicalRule.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !phraseKey.isEmpty else { continue }
                canonicalRuleIdByPhrase[phraseKey] = canonicalRule.id
            }

            for staleRule in staleCfg.rules {
                let phraseKey = staleRule.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !phraseKey.isEmpty else { continue }

                let canonicalRuleId: UUID
                if let existingId = canonicalRuleIdByPhrase[phraseKey] {
                    canonicalRuleId = existingId
                } else {
                    canonicalCfg.rules.append(staleRule)
                    canonicalRuleIdByPhrase[phraseKey] = staleRule.id
                    canonicalRuleId = staleRule.id
                }

                let oldPortId = GraphAutomationTraversal.wordTriggerRulePortId(nodeId: nodeId, ruleId: staleRule.id)
                let newPortId = GraphAutomationTraversal.wordTriggerRulePortId(nodeId: canonicalNodeId, ruleId: canonicalRuleId)
                for idx in (tab.graph?.links.indices ?? 0..<0) {
                    if tab.graph?.links[idx].fromPortId == oldPortId {
                        tab.graph?.links[idx].fromPortId = newPortId
                    }
                }
                tab.graph?.nodeIdByPortId.removeValue(forKey: oldPortId)
            }

            tab.graph?.wordTriggerConfigByNodeId[canonicalKey] = canonicalCfg
            tab.graph?.wordTriggerConfigByNodeId.removeValue(forKey: nodeId.uuidString)
        }

        let rules = tab.graph?.wordTriggerConfigByNodeId[canonicalKey]?.rules ?? []
        for rule in rules {
            let rulePortId = GraphAutomationTraversal.wordTriggerRulePortId(nodeId: canonicalNodeId, ruleId: rule.id)
            tab.graph?.nodeIdByPortId[rulePortId] = canonicalNodeId
        }
    }

    // Register button trigger output port IDs (one per button config).
    if key == DashboardGraph.buttonTriggerGroupKey {
        let buttons = buttonsForButtonNode(nodeId)
        for button in buttons {
            let portId = GraphAutomationTraversal.buttonOutputPortId(nodeId: nodeId, buttonConfigId: button.id)
            tab.graph?.nodeIdByPortId[portId] = nodeId
        }
    }

    let isCurrentTimeNode = key == "source.currentTime"
    let hasCurrentTimeConfig = tab.graph?.currentTimeSourceConfigByNodeId[nodeId.uuidString] != nil
    if isCurrentTimeNode && !hasCurrentTimeConfig {
        tab.graph?.currentTimeSourceConfigByNodeId[nodeId.uuidString] =
            DashboardGraph.CurrentTimeSourceConfig(id: nodeId)
        // Seed synthetic variable slot so patch resolution works via existing GraphRuntime path.
        tab.graph?.variableNodeConfigByNodeId[nodeId.uuidString] =
            DashboardGraph.VariableNodeConfig(
                id: nodeId,
                name: "_currentTime_\(nodeId.uuidString.prefix(6))",
                valueType: .text
            )
    }
}

private func makeDetailedConsoleNodeView(
    device: ExternalDeviceConfig,
    nodeId: UUID,
    people: [ModuleMember],
    showAssignments: Bool,
    showSnapshots: Bool,
    showQuActions: Bool,
    showDigiCoActions: Bool,
    showStandardActions: Bool,
    packedTitles: [String],
    availablePositions: [String]
) -> ConsoleGraphNodeView {
    ConsoleGraphNodeView(
        device: device,
        nodeId: nodeId,
        linkedTriggerNodes: linkedTriggerNodes(forConsoleNodeId: nodeId),
        triggerSendConfig: consoleTriggerSendConfigBinding(forConsoleNodeId: nodeId),
        showAssignments: showAssignments,
        showSnapshots: showSnapshots,
        showQuActions: showQuActions,
        showStandardActions: showStandardActions,
        quActions: quActionsBinding(forConsoleNodeId: nodeId),
        standardActions: standardActionsBinding(forConsoleNodeId: nodeId),
        rundownSnapshotTitles: packedTitles,
        people: people,
        availablePositions: availablePositions,
        onAssign: { [self] personLabel, channel in
            handleConsoleAssign(deviceId: device.id, personLabel: personLabel, channel: channel)
        },
        onAutoAssign: { [self] in
            handleConsoleAutoAssign(deviceId: device.id, members: people)
        },
        onClearAssignments: { [self] in
            handleConsoleClearAssignments(deviceId: device.id)
        },
        onSetNameFormat: { [self] format in
            handleConsoleNameFormat(deviceId: device.id, format: format)
        },
        onSetNameCasing: { [self] casing in
            handleConsoleNameCasing(deviceId: device.id, casing: casing)
        },
        onSetSnapshotCasing: { [self] casing in
            handleConsoleSnapshotCasing(deviceId: device.id, casing: casing)
        },
        onSetSnapshotShortenEnabled: { [self] enabled in
            handleConsoleSnapshotShortenEnabled(deviceId: device.id, enabled: enabled)
        },
        onSetSnapshotShortenLimit: { [self] limit in
            handleConsoleSnapshotShortenLimit(deviceId: device.id, limit: limit)
        },
        onSetPositionDefault: { position, channel in
            ExternalDevicesStore.shared.updateDevice(id: device.id) { cfg in
                if let channel {
                    cfg.consolePositionChannelDefaults[position] = channel
                } else {
                    cfg.consolePositionChannelDefaults.removeValue(forKey: position)
                }
            }
        },
        onTestQuActions: { [self] in
            guard let graph = tab.graph else { return }
            consoleActionErrors.removeValue(forKey: nodeId)
            consoleActionRunningNodeIds.insert(nodeId)
            GraphAutomationRuntime.shared.testQuConsoleActions(graph: graph, consoleNodeId: nodeId)
        },
        onTestStandardActions: { [self] in
            guard let graph = tab.graph else { return }
            consoleActionErrors.removeValue(forKey: nodeId)
            consoleActionRunningNodeIds.insert(nodeId)
            GraphAutomationRuntime.shared.testStandardConsoleActions(graph: graph, consoleNodeId: nodeId)
        },
        showDigiCoActions: showDigiCoActions,
        digicoActions: digicoActionsBinding(forConsoleNodeId: nodeId),
        onTestDigiCoActions: { [self] in
            guard let graph = tab.graph else { return }
            consoleActionErrors.removeValue(forKey: nodeId)
            consoleActionRunningNodeIds.insert(nodeId)
            GraphAutomationRuntime.shared.testDigiCoConsoleActions(graph: graph, consoleNodeId: nodeId)
        },
        capabilityMismatchedSources: capabilityMismatchedSourceNames(forConsoleNodeId: nodeId, device: device),
        consoleActionWarningText: consoleActionErrors[nodeId],
        consoleActionWarningStyle: .error,
        isTestingConsoleAction: consoleActionRunningNodeIds.contains(nodeId),
        onDismissConsoleActionWarning: consoleActionErrors[nodeId] != nil ? {
            consoleActionErrors.removeValue(forKey: nodeId)
        } : nil,
        graph: $tab.graph
    )
}

@ViewBuilder
private func consoleNodeView(
    device: ExternalDeviceConfig,
    nodeId: UUID,
    pos: CGPoint,
    canvasPeopleMembers: [ModuleMember],
    currentGroups: [ModuleGroup]
) -> some View {
    let people = peopleMembersForConsoleNode(consoleNodeId: nodeId, canvasPeopleMembers: canvasPeopleMembers)
    let showAssignments = isPeopleLinked(toConsoleNodeId: nodeId)
    let showSnapshots = isPCORundownLinked(toConsoleNodeId: nodeId)
    let showQuActions = isQuConsole(device) && isTriggerLinked(toConsoleNodeId: nodeId)
    let showDigiCoActions = isDigiCoConsole(device) && isTriggerLinked(toConsoleNodeId: nodeId)
    let showStandardActions = isStandardActionConsole(device) && isTriggerLinked(toConsoleNodeId: nodeId)
    let packedTitles = packedRundownSnapshotTitles(forConsoleNodeId: nodeId, currentGroups: currentGroups)
    let availablePositions = allPCOPositions
    let showDetailed = shouldRenderDetailedGraphNode(nodeId)

    Group {
        if showDetailed {
            makeDetailedConsoleNodeView(device: device, nodeId: nodeId, people: people,
                showAssignments: showAssignments, showSnapshots: showSnapshots,
                showQuActions: showQuActions, showDigiCoActions: showDigiCoActions,
                showStandardActions: showStandardActions,
                packedTitles: packedTitles, availablePositions: availablePositions)
        } else {
            graphNodeSummaryCard(
                title: device.name,
                subtitle: "Console Destination",
                systemImage: "hifispeaker.fill",
                accent: GraphNodeCategory(nodeKey: "destination.console").tintColor,
                width: consoleNodeWidth,
                detail: [
                    showAssignments ? "\(people.count) assignments" : nil,
                    showSnapshots ? "\(packedTitles.count) snapshots" : nil,
                    (showQuActions || showDigiCoActions || showStandardActions) ? "trigger actions linked" : nil
                ]
                .compactMap { $0 }
                .joined(separator: " • ")
            )
        }
    }
    .frame(width: consoleNodeWidth)
    .background {
        if showDetailed {
            nodeSizeReporter(nodeId)
        }
    }
    .overlay(invalidLinkHoverOverlay(for: nodeId))
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(hoverReceiverNodeId == nodeId ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(selectedGraphNodeIds.contains(nodeId) ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 2)
    )
    .overlay(alignment: .leading) {
        Circle()
            .fill(hoverReceiverNodeId == nodeId ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.55))
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
            .offset(x: -5)
            .accessibilityLabel("Link input")
    }
    .position(applyViewport(to: pos))
    .simultaneousGesture(
        TapGesture().onEnded { handleNodeTapSelect(nodeId) }
    )
    .gesture(nodeDragGesture(tileId: nodeId))
    .contextMenu {
        Button("Duplicate Node") {
            if !selectedGraphNodeIds.contains(nodeId) {
                selectedGraphNodeIds = [nodeId]
            }
            duplicateSelectedGraphNodes()
        }

        Divider()
        Button("Clear Links") {
            removeIncomingLinks(toNodeId: nodeId)
            removeOutgoingLinks(fromNodeId: nodeId)
        }
        .disabled(tab.graph?.links.isEmpty ?? true)

        Divider()

        Button("Remove Node", role: .destructive) {
            deleteGraphNode(nodeId: nodeId, key: "destination.console")
        }
    }
    .onAppear { handleConsoleNodeAppear(nodeId: nodeId, device: device, showDetailed: showDetailed) }
}

private func handleConsoleNodeAppear(nodeId: UUID, device: ExternalDeviceConfig, showDetailed: Bool) {
    recordGraphNodeMount(kind: "destination.console", detailed: showDetailed)
    ensureLayoutForConsoleNode(nodeId, device: device)
    if tab.graph == nil { tab.graph = DashboardGraph() }
    let portId = "node:\(nodeId.uuidString)"
    tab.graph?.nodeIdByPortId[portId] = nodeId
}

@ViewBuilder
private func missingConsoleNodeView(nodeId: UUID) -> some View {
    let isSelected = selectedGraphNodeIds.contains(nodeId)
    let isHoverReceiver = (hoverReceiverNodeId == nodeId)

    VStack(alignment: .leading, spacing: 6) {
        Text("Console Missing")
            .font(.headline)
        Text("This console is no longer configured.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(width: consoleNodeWidth, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(GraphNodeStyleTokens.cardFillOpacity))
    )
    .overlay(invalidLinkHoverOverlay(for: nodeId))
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(isHoverReceiver ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 2)
    )
    .position(applyViewport(to: nodePosition(for: nodeId)))
    .simultaneousGesture(TapGesture().onEnded { handleNodeTapSelect(nodeId) })
    .gesture(nodeDragGesture(tileId: nodeId))
    .contextMenu {
        Button("Duplicate Node") {
            if !selectedGraphNodeIds.contains(nodeId) {
                selectedGraphNodeIds = [nodeId]
            }
            duplicateSelectedGraphNodes()
        }

        Divider()
        Button("Clear Links") {
            removeIncomingLinks(toNodeId: nodeId)
            removeOutgoingLinks(fromNodeId: nodeId)
        }
        .disabled(tab.graph?.links.isEmpty ?? true)

        Divider()

        Button("Remove Node", role: .destructive) {
            deleteGraphNode(nodeId: nodeId, key: "destination.console")
        }
    }
    .onAppear {
        ensureLayoutForModuleGroupNode(nodeId, groupKey: "destination.console")

        if tab.graph == nil { tab.graph = DashboardGraph() }
        let portId = "node:\(nodeId.uuidString)"
        tab.graph?.nodeIdByPortId[portId] = nodeId
    }
}

@ViewBuilder
private func consoleNodesLayer(in size: CGSize, canvasPeopleMembers: [ModuleMember], currentGroups: [ModuleGroup]) -> some View {
    let prepStart = CFAbsoluteTimeGetCurrent()
    let hidden = hiddenGraphNodeIds
    let visibleConsoleIds = consoleNodeIds.filter { !hidden.contains($0) }
    let detailedCount = visibleConsoleIds.reduce(into: 0) { count, nodeId in
        if shouldRenderDetailedGraphNode(nodeId) { count += 1 }
    }
    let _ = {
        recordGraphLayerPreparation(
            key: "ui.graph.consoleNodes.prepare",
            duration: CFAbsoluteTimeGetCurrent() - prepStart,
            details: "visible=\(visibleConsoleIds.count) detailed=\(detailedCount) summary=\(visibleConsoleIds.count - detailedCount)"
        )
        return 0
    }()

    Group {
        if !visibleConsoleIds.isEmpty {
            ForEach(visibleConsoleIds, id: \.self) { nodeId in
                if let device = consoleDevice(forNodeId: nodeId) {
                    let pos = nodePosition(for: nodeId)

                    consoleNodeView(
                        device: device,
                        nodeId: nodeId,
                        pos: pos,
                        canvasPeopleMembers: canvasPeopleMembers,
                        currentGroups: currentGroups
                    )
                } else {
                    missingConsoleNodeView(nodeId: nodeId)
                }
            }
        }
    }
}

private func vistaNodeConfigBinding(for nodeId: UUID) -> Binding<DashboardGraph.VistaNodeConfig> {
    Binding(
        get: {
            let current = tab.graph?.vistaNodeConfigByNodeId[nodeId.uuidString] ?? DashboardGraph.VistaNodeConfig(id: nodeId)
            return syncedVistaNodeConfig(
                current,
                linkedItems: linkedVistaRundownItems(for: nodeId),
                availableDevices: availableVistaDestinationDevices
            )
        },
        set: { newValue in
            commitGraphEdit {
                if tab.graph == nil { tab.graph = DashboardGraph() }
                tab.graph?.vistaNodeConfigByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func syncedVistaNodeConfig(
    _ current: DashboardGraph.VistaNodeConfig,
    linkedItems: [VistaPCORundownItem],
    availableDevices: [ExternalDeviceConfig]
) -> DashboardGraph.VistaNodeConfig {
    let defaultLabel = VistaCSVBuilder.defaultCuelistLabel(from: linkedItems)
    let currentLabel = current.cuelistLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let lastAutoLabel = current.lastAutoGeneratedCuelistLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let legacyAutoLabel = VistaCSVBuilder.defaultCuelistLabel(from: [])
    let selectedDevice = availableDevices.first(where: { $0.id == current.selectedDeviceID })
    let fallbackDevice: ExternalDeviceConfig? = {
        if availableDevices.count == 1 {
            return availableDevices[0]
        }
        return availableDevices.first { device in
            let target = device.vistaConsoleTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return device.host == current.externalDeviceConfig.host &&
                device.port == current.externalDeviceConfig.oscPort &&
                target == current.externalDeviceConfig.consoleTarget
        }
    }()
    let shouldUseAutoLabel =
        currentLabel.isEmpty ||
        (!lastAutoLabel.isEmpty && currentLabel == lastAutoLabel) ||
        (lastAutoLabel.isEmpty && currentLabel == legacyAutoLabel)

    var synced = current
    if shouldUseAutoLabel {
        synced.cuelistLabel = defaultLabel
        synced.lastAutoGeneratedCuelistLabel = defaultLabel
    }
    let resolvedDevice = selectedDevice ?? fallbackDevice
    synced.selectedDeviceID = resolvedDevice?.id
    if let resolvedDevice {
        synced.externalDeviceConfig.displayName = resolvedDevice.name
        synced.externalDeviceConfig.host = resolvedDevice.host
        synced.externalDeviceConfig.oscPort = resolvedDevice.port
        let target = resolvedDevice.vistaConsoleTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        synced.externalDeviceConfig.consoleTarget = target.isEmpty ? "EX1" : target
        synced.externalDeviceConfig.isEnabled = resolvedDevice.isEnabled
    }
    return synced
}

private func reconcileVistaNodeConfig(for nodeId: UUID, linkedItems: [VistaPCORundownItem]) {
    if tab.graph == nil { tab.graph = DashboardGraph() }
    let existing = tab.graph?.vistaNodeConfigByNodeId[nodeId.uuidString] ?? DashboardGraph.VistaNodeConfig(id: nodeId)
    let synced = syncedVistaNodeConfig(
        existing,
        linkedItems: linkedItems,
        availableDevices: availableVistaDestinationDevices
    )
    guard tab.graph?.vistaNodeConfigByNodeId[nodeId.uuidString] != synced else { return }
    tab.graph?.vistaNodeConfigByNodeId[nodeId.uuidString] = synced
}

private func linkedVistaRundownItems(for vistaNodeId: UUID) -> [VistaPCORundownItem] {
    guard isVistaIntegrationEnabled,
          isVistaLinkedToPCO(vistaNodeId: vistaNodeId),
          let graph = tab.graph else {
        return []
    }

    let toPort = "node:\(vistaNodeId.uuidString)"
    let groups = computedModuleGroups()
    let inboundLinks = graph.links.filter { link in
        link.isEnabled && (link.toPortId == toPort || link.toTileId == vistaNodeId)
    }

    for link in inboundLinks {
        let fromId = graph.nodeIdByPortId[link.fromPortId] ?? link.fromTileId
        guard isPCONodeId(fromId) else { continue }
        if let group = groups.first(where: { $0.key == "moduleGroup.pco" }) {
            return group.members.compactMap { member in
                VistaPCORundownPayloadCodec.decode(from: member.payload ?? member.title)
            }
        }
    }

    return tab.pcoRundownSnapshotTitles.compactMap { VistaPCORundownPayloadCodec.decode(from: $0) }
}

private func isVistaLinkedToPCO(vistaNodeId: UUID) -> Bool {
    guard isVistaIntegrationEnabled, let graph = tab.graph else { return false }
    let toPort = "node:\(vistaNodeId.uuidString)"
    return graph.links.contains { link in
        guard link.isEnabled, (link.toPortId == toPort || link.toTileId == vistaNodeId) else { return false }
        let fromId = graph.nodeIdByPortId[link.fromPortId] ?? link.fromTileId
        return isPCONodeId(fromId)
    }
}

@ViewBuilder
private func vistaNodeView(nodeId: UUID, pos: CGPoint) -> some View {
    let config = vistaNodeConfigBinding(for: nodeId)
    let items = linkedVistaRundownItems(for: nodeId)
    let device = vistaDevice(forNodeId: nodeId)
    let showDetailed = shouldRenderDetailedGraphNode(nodeId)

    Group {
        if showDetailed {
            VistaGraphNodeView(
                nodeId: nodeId,
                config: config,
                device: device,
                linkedItems: items,
                showTriggerControls: isTriggerLinked(toVistaNodeId: nodeId),
                isSelected: selectedGraphNodeIds.contains(nodeId)
            )
        } else {
            graphNodeSummaryCard(
                title: device?.name ?? "Vista",
                subtitle: "Vista Destination",
                systemImage: "light.beacon.max.fill",
                accent: GraphNodeCategory(nodeKey: "destination.vista").tintColor,
                width: senderNodeWidth,
                detail: items.isEmpty ? "No linked PCO items" : "\(items.count) linked PCO item\(items.count == 1 ? "" : "s")"
            )
        }
    }
    .frame(width: 420)
    .background {
        if showDetailed {
            nodeSizeReporter(nodeId)
        }
    }
    .overlay(invalidLinkHoverOverlay(for: nodeId))
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(hoverReceiverNodeId == nodeId ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(selectedGraphNodeIds.contains(nodeId) ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 2)
    )
    .overlay(alignment: .leading) {
        Circle()
            .fill(
                hoverInvalidReceiverNodeId == nodeId
                ? Color.red.opacity(0.90)
                : (hoverReceiverNodeId == nodeId ? Color.accentColor.opacity(0.95) : Color.blue.opacity(0.80))
            )
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
            .offset(x: -5)
            .accessibilityLabel("Link input")
    }
    .position(applyViewport(to: pos))
    .simultaneousGesture(TapGesture().onEnded { handleNodeTapSelect(nodeId) })
    .gesture(nodeDragGesture(tileId: nodeId))
    .contextMenu {
        Button("Duplicate Node") {
            if !selectedGraphNodeIds.contains(nodeId) {
                selectedGraphNodeIds = [nodeId]
            }
            duplicateSelectedGraphNodes()
        }

        Divider()
        Button("Clear Links") {
            removeIncomingLinks(toNodeId: nodeId)
            removeOutgoingLinks(fromNodeId: nodeId)
        }
        .disabled(tab.graph?.links.isEmpty ?? true)

        Divider()
        Button("Remove Node", role: .destructive) {
            deleteGraphNode(nodeId: nodeId, key: "destination.vista")
        }
    }
    .onAppear {
        recordGraphNodeMount(kind: "destination.vista", detailed: showDetailed)
        ensureLayoutForModuleGroupNode(nodeId, groupKey: "destination.vista")
        if tab.graph == nil { tab.graph = DashboardGraph() }
        let portId = "node:\(nodeId.uuidString)"
        tab.graph?.nodeIdByPortId[portId] = nodeId
        reconcileVistaNodeConfig(for: nodeId, linkedItems: items)
    }
    .onChange(of: items, initial: true) { _, newItems in
        reconcileVistaNodeConfig(for: nodeId, linkedItems: newItems)
    }
}

@ViewBuilder
private func vistaNodesLayer() -> some View {
    if isVistaIntegrationEnabled {
        let prepStart = CFAbsoluteTimeGetCurrent()
        let hidden = hiddenGraphNodeIds
        let vistaIds = (tab.graph?.moduleGroupNodeInstances ?? [])
            .filter { $0.groupKey == "destination.vista" && !hidden.contains($0.id) }
            .map(\.id)
        let detailedCount = vistaIds.reduce(into: 0) { count, nodeId in
            if shouldRenderDetailedGraphNode(nodeId) { count += 1 }
        }
        let _ = {
            recordGraphLayerPreparation(
                key: "ui.graph.vistaNodes.prepare",
                duration: CFAbsoluteTimeGetCurrent() - prepStart,
                details: "visible=\(vistaIds.count) detailed=\(detailedCount) summary=\(vistaIds.count - detailedCount)"
            )
            return 0
        }()

        ForEach(vistaIds, id: \.self) { nodeId in
            vistaNodeView(nodeId: nodeId, pos: nodePosition(for: nodeId))
        }
    }
}

private func isPCORundownLinked(toConsoleNodeId consoleNodeId: UUID) -> Bool {
    guard let graph = tab.graph else { return false }
    let toPort = "node:\(consoleNodeId.uuidString)"

    let canvasId = groupNodeId(for: "moduleGroup.pco")
    let pcoInstanceIds = Set(graph.moduleGroupNodeInstances
        .filter { $0.groupKey == "moduleGroup.pco" }
        .map { $0.id }
    )

    func resolveFromNodeId(for link: GraphLink) -> UUID? {
        if link.fromTileId == canvasId || pcoInstanceIds.contains(link.fromTileId) {
            return link.fromTileId
        }
        return graph.nodeIdByPortId[link.fromPortId]
    }

    for link in graph.links where link.isEnabled {
        let toMatches = (link.toPortId == toPort || link.toTileId == consoleNodeId)
        guard toMatches else { continue }

        if let fromNodeId = resolveFromNodeId(for: link) {
            if fromNodeId == canvasId || pcoInstanceIds.contains(fromNodeId) {
                return true
            }
        }
    }
    return false
}

private func isTriggerLinked(toConsoleNodeId consoleNodeId: UUID) -> Bool {
    guard let graph = tab.graph else { return false }
    let toPort = "node:\(consoleNodeId.uuidString)"

    for link in graph.links where link.isEnabled {
        let toMatches = (link.toPortId == toPort || link.toTileId == consoleNodeId)
        guard toMatches else { continue }
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        if isTriggerNodeId(fromId) { return true }
    }
    return false
}

private func isTriggerLinked(toVistaNodeId vistaNodeId: UUID) -> Bool {
    guard let graph = tab.graph else { return false }
    let toPort = "node:\(vistaNodeId.uuidString)"

    for link in graph.links where link.isEnabled {
        let toMatches = (link.toPortId == toPort || link.toTileId == vistaNodeId)
        guard toMatches else { continue }
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        if isTriggerNodeId(fromId) { return true }
    }
    return false
}

private func isQuConsole(_ device: ExternalDeviceConfig) -> Bool {
    guard let model = device.audioConsoleModel else { return false }
    switch model {
    case .allenHeathQu:
        return true
    default:
        return false
    }
}

private func isDigiCoConsole(_ device: ExternalDeviceConfig) -> Bool {
    device.audioConsoleModel == .digico
}

private func isStandardActionConsole(_ device: ExternalDeviceConfig) -> Bool {
    device.consoleCapabilities.channelMute == .supported
        || device.consoleCapabilities.channelLevel == .supported
        || device.consoleCapabilities.channelPan == .supported
}

private func quActionsBinding(forConsoleNodeId nodeId: UUID) -> Binding<[DashboardGraph.QuConsoleAction]> {
    Binding<[DashboardGraph.QuConsoleAction]>(
        get: {
            tab.graph?.quConsoleActionsByNodeId[nodeId.uuidString] ?? []
        },
        set: { newValue in
            commitGraphEdit {
                if tab.graph == nil { tab.graph = DashboardGraph() }
                tab.graph?.quConsoleActionsByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func standardActionsBinding(forConsoleNodeId nodeId: UUID) -> Binding<[DashboardGraph.StandardConsoleAction]> {
    Binding<[DashboardGraph.StandardConsoleAction]>(
        get: {
            tab.graph?.standardConsoleActionsByNodeId[nodeId.uuidString] ?? []
        },
        set: { newValue in
            commitGraphEdit {
                if tab.graph == nil { tab.graph = DashboardGraph() }
                tab.graph?.standardConsoleActionsByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func digicoActionsBinding(forConsoleNodeId nodeId: UUID) -> Binding<[DashboardGraph.DiGiCoConsoleAction]> {
    Binding<[DashboardGraph.DiGiCoConsoleAction]>(
        get: {
            tab.graph?.digicoConsoleActionsByNodeId[nodeId.uuidString] ?? []
        },
        set: { newValue in
            commitGraphEdit {
                if tab.graph == nil { tab.graph = DashboardGraph() }
                tab.graph?.digicoConsoleActionsByNodeId[nodeId.uuidString] = newValue
            }
        }
    )
}

private func consoleTriggerSendConfigBinding(forConsoleNodeId nodeId: UUID) -> Binding<DashboardGraph.ConsoleTriggerSendConfig> {
    Binding(
        get: {
            self.tab.graph?.consoleTriggerSendConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.ConsoleTriggerSendConfig()
        },
        set: { newValue in
            if self.tab.graph == nil { self.tab.graph = DashboardGraph() }
            self.tab.graph?.consoleTriggerSendConfigByNodeId[nodeId.uuidString] = newValue
        }
    )
}

    private let canvasDrawPadding: CGFloat = 2400

    @ViewBuilder
    private func linksLayer(in size: CGSize) -> some View {
        let pad = canvasDrawPadding
        let w = size.width + pad * 2
        let h = size.height + pad * 2

        Canvas { context, _ in
            func shift(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x + pad, y: p.y + pad)
            }

            func senderNubCenter(for nodeId: UUID) -> CGPoint {
                let center = nodePosition(for: nodeId)
                let width = measuredNodeSizes[nodeId]?.width ?? senderNodeWidth
                let nubOffset: CGFloat = 5
                return CGPoint(x: center.x + (width / 2.0) + nubOffset, y: center.y)
            }

            func senderNubCenter(for link: GraphLink, nodeId: UUID) -> CGPoint {
                if isRepeaterNodeId(nodeId) {
                    if let index = repeaterOutputIndex(fromPortId: link.fromPortId) {
                        return repeaterNubCenter(nodeId: nodeId, index: index)
                    }
                    return repeaterNubCenter(nodeId: nodeId, index: 0)
                }
                if isConditionNodeId(nodeId) {
                    if let branch = conditionOutputBranch(fromPortId: link.fromPortId) {
                        return conditionNubCenter(nodeId: nodeId, branch: branch)
                    }
                    return conditionNubCenter(nodeId: nodeId, branch: .true)
                }
                if isToggleNodeId(nodeId) {
                    let isOn = link.fromPortId.hasSuffix(":on")
                    return toggleNubCenter(nodeId: nodeId, isOn: isOn)
                }
                if isSequenceNodeId(nodeId) {
                    if let step = sequenceOutputStep(fromPortId: link.fromPortId) {
                        return sequenceNubCenter(nodeId: nodeId, step: step)
                    }
                    return sequenceNubCenter(nodeId: nodeId, step: 0)
                }
                if isSmartLightNodeId(nodeId) {
                    return smartLightNubCenter(nodeId: nodeId, kind: smartLightOutputKind(fromPortId: link.fromPortId) ?? "success")
                }
                if isWordTriggerNodeId(nodeId) {
                    let rules = tab.graph?.wordTriggerConfigByNodeId[nodeId.uuidString]?.rules ?? []
                    if let ruleId = wordTriggerRuleId(fromPortId: link.fromPortId),
                       let idx = rules.firstIndex(where: { $0.id == ruleId }) {
                        return wordTriggerRuleNubCenter(nodeId: nodeId, ruleIndex: idx, total: rules.count)
                    }
                    // Legacy link (node:<uuid> port): anchor to first rule nub so it doesn't float
                    if !rules.isEmpty {
                        return wordTriggerRuleNubCenter(nodeId: nodeId, ruleIndex: 0, total: rules.count)
                    }
                    return senderNubCenter(for: nodeId)
                }
                if isMultiButtonNodeId(nodeId) {
                    let buttons = buttonsForButtonNode(nodeId)
                    if let configId = buttonConfigId(fromPortId: link.fromPortId),
                       let idx = buttons.firstIndex(where: { $0.id == configId }) {
                        return buttonNubCenter(nodeId: nodeId, index: idx, total: buttons.count)
                    }
                    return senderNubCenter(for: nodeId)
                }
                return senderNubCenter(for: nodeId)
            }

            func repeaterOutputIndex(fromPortId portId: String) -> Int? {
                guard portId.hasPrefix("repeater:") else { return nil }
                let parts = portId.split(separator: ":")
                if let last = parts.last, let idx = Int(last) {
                    return idx
                }
                return nil
            }

            func repeaterNubCenter(nodeId: UUID, index: Int) -> CGPoint {
                let center = nodePosition(for: nodeId)
                let width = measuredNodeSizes[nodeId]?.width ?? senderNodeWidth
                let x = center.x + (width / 2.0)

                let total = max(1, repeaterOutputLimit(for: nodeId))
                let stackSpacing: CGFloat = 14
                let nubHeight: CGFloat = 10
                let stackHeight = CGFloat(total) * nubHeight + CGFloat(total - 1) * stackSpacing
                let yOffset = -stackHeight / 2 + nubHeight / 2 + CGFloat(index) * (nubHeight + stackSpacing)
                return CGPoint(x: x, y: center.y + yOffset)
            }

            func conditionOutputBranch(fromPortId portId: String) -> GraphAutomationTraversal.UtilityBranch? {
                guard portId.hasPrefix("condition:") else { return nil }
                let parts = portId.split(separator: ":")
                guard let rawBranch = parts.last else { return nil }
                return GraphAutomationTraversal.UtilityBranch(rawValue: String(rawBranch))
            }

            func conditionNubCenter(nodeId: UUID, branch: GraphAutomationTraversal.UtilityBranch) -> CGPoint {
                let yOffset: CGFloat = branch == .true ? -12 : 12
                return senderNubCenter(for: nodeId).applying(.init(translationX: 0, y: yOffset))
            }

            func toggleNubCenter(nodeId: UUID, isOn: Bool) -> CGPoint {
                let yOffset: CGFloat = isOn ? -12 : 12
                return senderNubCenter(for: nodeId).applying(.init(translationX: 0, y: yOffset))
            }

            func sequenceOutputStep(fromPortId portId: String) -> Int? {
                guard portId.hasPrefix("sequence:") else { return nil }
                let parts = portId.split(separator: ":")
                if let last = parts.last, let step = Int(last) { return step }
                return nil
            }

            func sequenceNubCenter(nodeId: UUID, step: Int) -> CGPoint {
                let center = nodePosition(for: nodeId)
                let width = measuredNodeSizes[nodeId]?.width ?? senderNodeWidth
                let x = center.x + (width / 2.0)
                let total = max(2, sequenceOutputLimit(for: nodeId))
                let stackSpacing: CGFloat = 14
                let nubHeight: CGFloat = 10
                let stackHeight = CGFloat(total) * nubHeight + CGFloat(total - 1) * stackSpacing
                let yOffset = -stackHeight / 2 + nubHeight / 2 + CGFloat(step) * (nubHeight + stackSpacing)
                return CGPoint(x: x, y: center.y + yOffset)
            }

            func smartLightOutputKind(fromPortId portId: String) -> String? {
                guard portId.hasPrefix("smartlight:") else { return nil }
                let parts = portId.split(separator: ":")
                guard let raw = parts.last else { return nil }
                return String(raw)
            }

            func smartLightNubCenter(nodeId: UUID, kind: String) -> CGPoint {
                let yOffset: CGFloat
                switch kind {
                case "success":
                    yOffset = -24
                case "failure":
                    yOffset = 0
                default:
                    yOffset = 24
                }
                return senderNubCenter(for: nodeId).applying(.init(translationX: 0, y: yOffset))
            }

            func wordTriggerRuleId(fromPortId portId: String) -> UUID? {
                // Format: "wordTrigger:<nodeId>:rule:<ruleId>"
                guard portId.hasPrefix("wordTrigger:") else { return nil }
                let parts = portId.split(separator: ":")
                guard parts.count == 4, let ruleId = UUID(uuidString: String(parts[3])) else { return nil }
                return ruleId
            }

            func wordTriggerRuleNubCenter(nodeId: UUID, ruleIndex: Int, total: Int) -> CGPoint {
                let center = nodePosition(for: nodeId)
                let width = measuredNodeSizes[nodeId]?.width ?? senderNodeWidth
                let x = center.x + (width / 2.0)
                let stackSpacing: CGFloat = 14
                let itemHeight: CGFloat = 20  // ZStack height (Rectangle frame), not circle diameter
                let totalCount = max(1, total)
                let stackHeight = CGFloat(totalCount) * itemHeight + CGFloat(totalCount - 1) * stackSpacing
                let yOffset = -stackHeight / 2 + itemHeight / 2 + CGFloat(ruleIndex) * (itemHeight + stackSpacing)
                return CGPoint(x: x, y: center.y + yOffset)
            }

            func buttonConfigId(fromPortId portId: String) -> UUID? {
                // Format: "button:<nodeId>:<configId>"
                guard portId.hasPrefix("button:") else { return nil }
                let parts = portId.split(separator: ":")
                guard parts.count == 3, let configId = UUID(uuidString: String(parts[2])) else { return nil }
                return configId
            }

            func buttonNubCenter(nodeId: UUID, index: Int, total: Int) -> CGPoint {
                let center = nodePosition(for: nodeId)
                let width = measuredNodeSizes[nodeId]?.width ?? senderNodeWidth
                let x = center.x + (width / 2.0) + 5
                let itemHeight: CGFloat = 20
                let stackSpacing: CGFloat = 14
                let totalCount = max(1, total)
                let totalHeight = CGFloat(totalCount) * itemHeight + CGFloat(totalCount - 1) * stackSpacing
                let topY = center.y - totalHeight / 2 + CGFloat(index) * (itemHeight + stackSpacing) + itemHeight / 2
                return CGPoint(x: x, y: topY)
            }

            func receiverNubCenter(for nodeId: UUID) -> CGPoint {
                let center = nodePosition(for: nodeId)
                let width = measuredNodeSizes[nodeId]?.width ?? consoleNodeWidth
                let nubOffset: CGFloat = 5
                return CGPoint(x: center.x - (width / 2.0) - nubOffset, y: center.y)
            }

            if let graph = tab.graph {
                let hidden = hiddenGraphNodeIds
                for link in graph.links where link.isEnabled {
                    let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
                    let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId

                    if hidden.contains(fromId) || hidden.contains(toId) {
                        continue
                    }

                    guard
                        tab.graph?.tileLayouts[fromId] != nil,
                        tab.graph?.tileLayouts[toId] != nil
                    else {
                        continue // Skip stale/ghost links
                    }

                    let p0 = senderNubCenter(for: link, nodeId: fromId)
                    let p3 = receiverNubCenter(for: toId)

                    let path = bezierPath(from: shift(p0), to: shift(p3))
                    context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 2.0)
                }
            }

            if let fromNode = linkingFromNodeId, let cur = linkingCurrentPoint {
                let start = linkingFromPoint ?? senderNubCenter(for: fromNode)
                let path = bezierPath(from: shift(start), to: shift(cur))
                let color: Color
                if hoverInvalidReceiverNodeId != nil {
                    color = Color.red.opacity(0.75)
                } else if hoverReceiverNodeId != nil {
                    color = Color.accentColor.opacity(0.75)
                } else {
                    color = Color.white.opacity(0.35)
                }
                context.stroke(path, with: .color(color), lineWidth: 2.0)
            }
        }
        .frame(width: w, height: h)
        .offset(x: -pad, y: -pad)
        .allowsHitTesting(false)
    }
    

private func bezierPath(from p0: CGPoint, to p3: CGPoint) -> Path {
    var path = Path()
    path.move(to: p0)
    let dxRaw = (p3.x - p0.x) * 0.45
    let dx = max(80, abs(dxRaw))
    let c1 = CGPoint(x: p0.x + dx, y: p0.y)
    let c2 = CGPoint(x: p3.x - dx, y: p3.y)
    path.addCurve(to: p3, control1: c1, control2: c2)
    return path
}

/// If we encode node ids into port ids, recover them. Otherwise nil.
private func nodeIdFromPortId(_ portId: String) -> UUID? {
    // Prefer the persisted reverse index (works even if we change portId formatting later).
    if let mapped = tab.graph?.nodeIdByPortId[portId] { return mapped }

    if portId.hasPrefix("node:") {
        let raw = String(portId.dropFirst("node:".count))
        return UUID(uuidString: raw)
    }

    if portId.hasPrefix("repeater:") || portId.hasPrefix("condition:") ||
        portId.hasPrefix("toggle:") || portId.hasPrefix("sequence:") ||
        portId.hasPrefix("smartlight:") || portId.hasPrefix("currentTime:") {
        let parts = portId.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    return nil
}

private func linkedPatchSourceNodeId(forDestinationNodeId destinationNodeId: UUID) -> UUID? {
    guard let graph = tab.graph else { return nil }
    for link in graph.links where link.isEnabled && link.kind == .patch {
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        guard toId == destinationNodeId else { continue }
        return nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
    }
    return nil
}

private func linkedPatchSourceText(forDestinationNodeId destinationNodeId: UUID) -> String? {
    linkedPatchSourceTexts(forDestinationNodeId: destinationNodeId).first
}

private func linkedPatchSourceTexts(forDestinationNodeId destinationNodeId: UUID) -> [String] {
    guard let graph = tab.graph else { return [] }
    for link in graph.links where link.isEnabled && link.kind == .patch {
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        guard toId == destinationNodeId else { continue }
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        return GraphRuntime.resolveTextValues(nodeId: fromId, portId: link.fromPortId, tab: tab)
            .map { raw in
                raw.unicodeScalars
                    .filter { !CharacterSet.controlCharacters.contains($0) }
                    .map(String.init)
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
    return []
}

private func isActionNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: { inst in
        inst.id == nodeId && inst.groupKey.hasPrefix("action.")
    })
}

private func isDestinationActionGroupKey(_ key: String) -> Bool {
    key == "action.shureSend" ||
    key == "action.sennheiserSend" ||
    key == "action.proPresenterTrigger"
}

private func isSmartLightNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "action.smartLightControl"
    })
}

private func isVistaNodeId(_ nodeId: UUID) -> Bool {
    guard isVistaIntegrationEnabled else { return false }
    return (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: { inst in
        inst.id == nodeId && inst.groupKey == "destination.vista"
    })
}

private func isDestinationActionNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: { inst in
        inst.id == nodeId && isDestinationActionGroupKey(inst.groupKey)
    })
}

private func isRepeaterNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: { inst in
        inst.id == nodeId && inst.groupKey == "utility.repeater"
    })
}

private func isDelayNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: { inst in
        inst.id == nodeId && inst.groupKey == "utility.delay"
    })
}

private func isConditionNodeId(_ nodeId: UUID) -> Bool {
    guard isGraphConditionalsFeatureEnabled else { return false }
    return (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: { inst in
        inst.id == nodeId && inst.groupKey == "utility.condition"
    })
}

private func isMergeNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "utility.merge"
    })
}

private func isToggleNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "utility.toggle"
    })
}

private func isCounterNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "utility.counter"
    })
}

private func isSequenceNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "utility.sequence"
    })
}

private func isWordTriggerNodeId(_ nodeId: UUID) -> Bool {
    // Standalone graph-only word trigger node
    if (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "moduleGroup.wordTrigger"
    }) { return true }
    // Canvas-backed word trigger or transcription node
    let groups = computedModuleGroups()
    return groups.contains(where: { group in
        (group.key.contains("wordTrigger") || group.key.contains("transcription"))
        && groupNodeId(for: group.key) == nodeId
    })
}

private func isStandaloneWordTriggerNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "moduleGroup.wordTrigger"
    })
}

/// Merges and removes any `wordTriggerConfigByNodeId` entries that no longer correspond to
/// the canonical transcription node or a live standalone word trigger node instance. These
/// orphans accumulate when a standalone word trigger node is deleted (pre-fix builds never
/// cleaned up its config) or when nodes were synced retroactively. Left alone, the runtime
/// still evaluates them every transcript update, causing duplicate fires from stale rules.
private func sweepOrphanedWordTriggerConfigs(canonicalNodeId: UUID) {
    guard let graph = tab.graph else { return }
    let canonicalKey = canonicalNodeId.uuidString
    let liveStandaloneKeys = Set(
        graph.moduleGroupNodeInstances
            .filter { $0.groupKey == "moduleGroup.wordTrigger" }
            .map { $0.id.uuidString }
    )

    let orphanedKeys = graph.wordTriggerConfigByNodeId.keys.filter { key in
        key != canonicalKey && !liveStandaloneKeys.contains(key)
    }
    guard !orphanedKeys.isEmpty else { return }

    var canonicalCfg = graph.wordTriggerConfigByNodeId[canonicalKey] ?? DashboardGraph.WordTriggerConfig()
    var canonicalRuleIdByPhrase: [String: UUID] = [:]
    for rule in canonicalCfg.rules {
        let phraseKey = rule.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !phraseKey.isEmpty else { continue }
        canonicalRuleIdByPhrase[phraseKey] = rule.id
    }

    for orphanKey in orphanedKeys {
        guard let orphanNodeId = UUID(uuidString: orphanKey) else {
            tab.graph?.wordTriggerConfigByNodeId.removeValue(forKey: orphanKey)
            continue
        }
        let orphanRules = graph.wordTriggerConfigByNodeId[orphanKey]?.rules ?? []
        for orphanRule in orphanRules {
            let phraseKey = orphanRule.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !phraseKey.isEmpty else { continue }

            let canonicalRuleId: UUID
            if let existingId = canonicalRuleIdByPhrase[phraseKey] {
                canonicalRuleId = existingId
            } else {
                canonicalCfg.rules.append(orphanRule)
                canonicalRuleIdByPhrase[phraseKey] = orphanRule.id
                canonicalRuleId = orphanRule.id
            }

            let oldPortId = GraphAutomationTraversal.wordTriggerRulePortId(nodeId: orphanNodeId, ruleId: orphanRule.id)
            let newPortId = GraphAutomationTraversal.wordTriggerRulePortId(nodeId: canonicalNodeId, ruleId: canonicalRuleId)
            for idx in (tab.graph?.links.indices ?? 0..<0) {
                if tab.graph?.links[idx].fromPortId == oldPortId {
                    tab.graph?.links[idx].fromPortId = newPortId
                }
            }
            tab.graph?.nodeIdByPortId.removeValue(forKey: oldPortId)
        }
        tab.graph?.wordTriggerConfigByNodeId.removeValue(forKey: orphanKey)
    }

    tab.graph?.wordTriggerConfigByNodeId[canonicalKey] = canonicalCfg
}

private func isLatchNodeId(_ nodeId: UUID) -> Bool {
    (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "utility.latch"
    })
}

private func isVariableNodeId(_ nodeId: UUID) -> Bool {
    guard isGraphVariablesFeatureEnabled else { return false }
    return (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: { inst in
        inst.id == nodeId && inst.groupKey == "utility.variable"
    })
}

private func isTriggerGroupKey(_ key: String) -> Bool {
    if key.contains("time") { return true }
    if key.contains("shure") { return true }
    if key.contains("sennheiser") { return true }
    if key.contains("oscReceive") { return true }
    if key.contains("midiReceive") { return true }
    if key.contains("transcription") { return true }
    if key.contains("wordTrigger") { return true }
    if key.contains("dbThreshold") { return true }
    if key.contains("manualTrigger") { return true }
    if key.contains("keystrokeTrigger") { return true }
    if key.contains("pcoItemChanged") { return true }
    if key.contains("appState") { return true }
    if key == DashboardGraph.buttonTriggerGroupKey { return true }
    return false
}

private func isTriggerNodeId(_ nodeId: UUID) -> Bool {
    if let inst = tab.graph?.moduleGroupNodeInstances.first(where: { $0.id == nodeId }) {
        return isTriggerGroupKey(inst.groupKey)
    }

    let groups = computedModuleGroups()
    if let group = groups.first(where: { groupNodeId(for: $0.key) == nodeId }) {
        return isTriggerGroupKey(group.key)
    }

    return false
}

/// Returns a human-readable display name for a trigger node (graph-only or canvas-backed).
private func displayNameForTriggerNode(_ nodeId: UUID) -> String {
    // Graph-only instances: type name + brief config detail
    if let inst = tab.graph?.moduleGroupNodeInstances.first(where: { $0.id == nodeId }) {
        let typeName = triggerGroupKeyDisplayName(inst.groupKey)
        let detail = triggerNodeConfigDetail(nodeId: nodeId, groupKey: inst.groupKey)
        return detail.isEmpty ? typeName : "\(typeName) — \(detail)"
    }
    // Canvas-backed triggers: prefer the tile's user-set name
    let groups = computedModuleGroups()
    if let group = groups.first(where: { groupNodeId(for: $0.key) == nodeId }) {
        if group.isCanvasBacked, let tileName = canvasTriggerTileName(forGroupKey: group.key) {
            return tileName
        }
        return triggerGroupKeyDisplayName(group.key)
    }
    return "Trigger"
}

/// Returns a brief config detail string to distinguish multiple graph-only trigger instances of the same type.
private func triggerNodeConfigDetail(nodeId: UUID, groupKey: String) -> String {
    let key = nodeId.uuidString
    switch groupKey {
    case "moduleGroup.oscReceive":
        let filter = tab.graph?.oscReceiveConfigByNodeId[key]?.addressFilter?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (filter?.isEmpty == false) ? (filter ?? "") : ""
    case "moduleGroup.midiReceive":
        guard let cfg = tab.graph?.midiReceiveConfigByNodeId[key] else { return "" }
        switch cfg.messageType {
        case .any:           return "Any"
        case .programChange: return "PC"
        case .noteOn:        return "Note On"
        case .noteOff:       return "Note Off"
        case .controlChange: return "CC"
        case .sysex:         return "SysEx"
        }
    case "moduleGroup.time":
        guard let cfg = tab.graph?.timeTriggerConfigByNodeId[key] else { return "" }
        switch cfg.mode {
        case .interval: return "\(Int(cfg.intervalSeconds))s"
        case .atTime:   return cfg.timeOfDay
        }
    case "moduleGroup.keystrokeTrigger":
        let k = tab.graph?.keystrokeTriggerConfigByNodeId[key]?.keyEquivalent ?? ""
        return k.isEmpty ? "" : "⌘\(k.uppercased())"
    case "moduleGroup.wordTrigger":
        let phrase = tab.graph?.wordTriggerConfigByNodeId[key]?.rules.first?.phrase ?? ""
        return phrase.isEmpty ? "" : "\"\(phrase)\""
    default:
        return ""
    }
}

/// For a canvas-backed trigger group, returns the tile name if there is exactly one
/// contributing tile with a non-empty user-set name.
private func canvasTriggerTileName(forGroupKey key: String) -> String? {
    let matchingTiles = tilesSnapshot.filter { tile in
        guard let modules = tile.modules else { return false }
        return modules.contains { module in
            switch module.kind {
            case .shureWireless:     return key == "moduleGroup.shure"
            case .sennheiserWireless: return key == "moduleGroup.sennheiser"
            case .liveTranscription: return key == "moduleGroup.transcription"
            case .dbReader:          return key == "moduleGroup.dbThreshold"
            default:                 return false
            }
        }
    }
    guard matchingTiles.count == 1,
          let name = matchingTiles.first?.name,
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return name
}

private func triggerGroupKeyDisplayName(_ key: String) -> String {
    switch key {
    case "moduleGroup.midiReceive":      return "MIDI Receive"
    case "moduleGroup.oscReceive":       return "OSC Receive"
    case "moduleGroup.time":             return "Time"
    case "moduleGroup.shure":            return "Shure"
    case "moduleGroup.sennheiser":       return "Sennheiser"
    case "moduleGroup.transcription":    return "Transcription"
    case "moduleGroup.dbThreshold":      return "dB Threshold"
    case "moduleGroup.manualTrigger":    return "Manual Trigger"
    case "moduleGroup.keystrokeTrigger": return "Keystroke"
    case "moduleGroup.wordTrigger":      return "Word Trigger"
    default:
        if key == DashboardGraph.buttonTriggerGroupKey { return "Button" }
        return "Trigger"
    }
}

/// Returns ordered (id, displayName) pairs for all trigger nodes linked to this console.
private func linkedTriggerNodes(forConsoleNodeId nodeId: UUID) -> [ConsoleTriggerNodeRef] {
    guard let graph = tab.graph else { return [] }
    var seen = Set<UUID>()
    var result: [ConsoleTriggerNodeRef] = []
    for link in graph.links where link.isEnabled {
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        guard toId == nodeId else { continue }
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        guard isTriggerNodeId(fromId), seen.insert(fromId).inserted else { continue }
        result.append(ConsoleTriggerNodeRef(id: fromId, name: displayNameForTriggerNode(fromId)))
    }
    return result
}

private struct LinkReceiverHit {
    let nodeId: UUID
    let validation: GraphLinkValidation
}

private func clearLinkHoverState() {
    hoverReceiverNodeId = nil
    hoverInvalidReceiverNodeId = nil
}

private func setLinkHoverState(_ hit: LinkReceiverHit?) {
    hoverReceiverNodeId = nil
    hoverInvalidReceiverNodeId = nil

    guard let hit else { return }
    if hit.validation.isAllowed {
        hoverReceiverNodeId = hit.nodeId
    } else {
        hoverInvalidReceiverNodeId = hit.nodeId
    }
}

@ViewBuilder
private func invalidLinkHoverOverlay(for nodeId: UUID) -> some View {
    RoundedRectangle(cornerRadius: 14)
        .stroke(hoverInvalidReceiverNodeId == nodeId ? Color.red.opacity(0.9) : Color.clear, lineWidth: 2)
}

private var graphLinkFeatureFlags: GraphLinkFeatureFlags {
    GraphLinkFeatureFlags(
        conditionalsEnabled: isGraphConditionalsFeatureEnabled,
        variablesEnabled: isGraphVariablesFeatureEnabled
    )
}

private func linkNodeRole(for nodeId: UUID) -> GraphLinkNodeRole {
    if consoleNodeIds.contains(nodeId) {
        return .consoleDestination
    }
    if isVistaNodeId(nodeId) {
        return .vistaDestination
    }
    if let inst = tab.graph?.moduleGroupNodeInstances.first(where: { $0.id == nodeId }),
       inst.groupKey == DashboardGraph.buttonTriggerGroupKey {
        return .trigger
    }
    let groups = computedModuleGroups()
    if let canvasGroup = groups.first(where: { groupNodeId(for: $0.key) == nodeId }) {
        return isTriggerGroupKey(canvasGroup.key) ? .trigger : .source
    }
    if isTriggerNodeId(nodeId) {
        return .trigger
    }
    if isRepeaterNodeId(nodeId) {
        return .repeater
    }
    if isDelayNodeId(nodeId) {
        return .delay
    }
    if isConditionNodeId(nodeId) {
        return .condition
    }
    if isVariableNodeId(nodeId) {
        return .variable
    }
    if isMergeNodeId(nodeId) {
        return .merge
    }
    if isToggleNodeId(nodeId) || isCounterNodeId(nodeId) || isSequenceNodeId(nodeId) || isLatchNodeId(nodeId) {
        return .repeater
    }
    if isActionNodeId(nodeId) {
        if isSmartLightNodeId(nodeId) {
            return .actionWithResults
        }
        return isDestinationActionNodeId(nodeId) ? .destinationAction : .action
    }
    if let inst = tab.graph?.moduleGroupNodeInstances.first(where: { $0.id == nodeId }) {
        return (inst.groupKey.hasPrefix("moduleGroup.") || inst.groupKey.hasPrefix("source."))
            ? .source : .unknown
    }
    return .unknown
}

private func linkValidation(fromNodeId: UUID, toReceiverNodeId: UUID) -> GraphLinkValidation {
    let roleValidation = GraphLinkPolicy.validate(
        from: linkNodeRole(for: fromNodeId),
        to: linkNodeRole(for: toReceiverNodeId),
        isSameNode: fromNodeId == toReceiverNodeId,
        features: graphLinkFeatureFlags
    )
    guard roleValidation.isAllowed else { return roleValidation }

    // Capability gate: only applies when the target is a console destination node.
    if consoleNodeIds.contains(toReceiverNodeId),
       let device = consoleDevice(forNodeId: toReceiverNodeId),
       let groupKey = sourceGroupKey(for: fromNodeId) {
        let caps = device.consoleCapabilities
        // Treat .unknown capability as unsupported (safe default — unrecognized models are blocked
        // until their capabilities are registered in AudioConsoleModel.capabilities).
        if groupKey.hasPrefix("moduleGroup.person") && caps.channelNameChange != .supported {
            return .rejected(.consoleCapabilityMismatch)
        }
        if groupKey.hasPrefix("moduleGroup.pco") && !caps.canManageSnapshots {
            return .rejected(.consoleCapabilityMismatch)
        }
    }

    return roleValidation
}

/// Returns the moduleGroup.* key for any source node (canvas-backed or graph-only).
private func sourceGroupKey(for nodeId: UUID) -> String? {
    if let inst = tab.graph?.moduleGroupNodeInstances.first(where: { $0.id == nodeId }) {
        return inst.groupKey
    }
    let groups = computedModuleGroups()
    if let group = groups.first(where: { groupNodeId(for: $0.key) == nodeId }) {
        return group.key
    }
    return nil
}

/// Returns human-readable names of source nodes whose links to this console
/// are now capability-mismatched (e.g. People → Qu which doesn't support channel naming).
private func capabilityMismatchedSourceNames(forConsoleNodeId nodeId: UUID, device: ExternalDeviceConfig) -> [String] {
    guard let graph = tab.graph else { return [] }
    let caps = device.consoleCapabilities
    var names = Set<String>()
    for link in graph.links where link.isEnabled {
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        guard toId == nodeId else { continue }
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        guard let groupKey = sourceGroupKey(for: fromId) else { continue }
        if groupKey.hasPrefix("moduleGroup.person") && caps.channelNameChange != .supported {
            names.insert("People")
        } else if groupKey.hasPrefix("moduleGroup.pco") && !caps.canManageSnapshots {
            names.insert("Planning Center")
        }
    }
    return names.sorted()
}

private func isPCONodeId(_ nodeId: UUID) -> Bool {
    if groupNodeId(for: "moduleGroup.pco") == nodeId {
        return true
    }
    return (tab.graph?.moduleGroupNodeInstances ?? []).contains(where: {
        $0.id == nodeId && $0.groupKey == "moduleGroup.pco"
    })
}

private func receiverCandidateNodeIds(for sourceNodeId: UUID? = nil) -> [UUID] {
    let allowedReceiverRoles: Set<GraphLinkNodeRole>? = sourceNodeId.map {
        GraphLinkPolicy.allowedReceiverRoles(for: linkNodeRole(for: $0), features: graphLinkFeatureFlags)
    }
    let candidateIds = consoleNodeIds + (tab.graph?.moduleGroupNodeInstances ?? [])
        .map(\.id)
    return candidateIds.filter { candidateId in
        let role = linkNodeRole(for: candidateId)
        guard GraphLinkPolicy.canReceiveLinks(nodeRole: role, features: graphLinkFeatureFlags) else {
            return false
        }
        guard let allowedReceiverRoles else {
            return true
        }
        return allowedReceiverRoles.contains(role)
    }
}

private func receiverHitTestRect(for nodeId: UUID) -> CGRect {
    let size = nodeHitTestSize(for: nodeId)
    let nubCenter = CGPoint(
        x: nodePosition(for: nodeId).x - (size.width / 2.0) - 5,
        y: nodePosition(for: nodeId).y
    )

    let role = linkNodeRole(for: nodeId)
    let hotspotWidth: CGFloat = role == .variable ? 88 : 56
    let hotspotHeight: CGFloat = role == .variable
        ? min(max(size.height * 0.72, 132), size.height + 28)
        : min(max(size.height * 0.42, 96), size.height + 24)
    return CGRect(
        x: nubCenter.x - 18,
        y: nubCenter.y - hotspotHeight / 2.0,
        width: hotspotWidth,
        height: hotspotHeight
    )
}

private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
    let clampedX = min(max(point.x, rect.minX), rect.maxX)
    let clampedY = min(max(point.y, rect.minY), rect.maxY)
    let dx = point.x - clampedX
    let dy = point.y - clampedY
    return dx * dx + dy * dy
}

/// Hold Option and drag from a source (module-group) node to a destination node to create a link.
/// Destinations are endpoints only (no output nub). Today: Consoles + Action nodes.
/// Returns the nearest receiver and whether the link is allowed.
private func receiverNodeHitTest(at viewPoint: CGPoint, fromNodeId: UUID? = nil) -> LinkReceiverHit? {
    let graphPointValue = graphPoint(fromViewPoint: viewPoint)
    let candidates = receiverCandidateNodeIds(for: fromNodeId)
    guard !candidates.isEmpty else { return nil }

    var best: (id: UUID, dist2: CGFloat)? = nil
    for id in candidates {
        let dist2 = distanceSquared(from: graphPointValue, to: receiverHitTestRect(for: id))
        if best == nil || dist2 < best!.dist2 {
            best = (id, dist2)
        }
    }

    // Use a small outer snap margin around the receiver-side hotspot.
    let snapMargin: CGFloat = 12
    if let best, best.dist2 <= snapMargin * snapMargin {
        let validation: GraphLinkValidation
        if let fromNodeId {
            validation = linkValidation(fromNodeId: fromNodeId, toReceiverNodeId: best.id)
        } else {
            validation = .allowed
        }
        return LinkReceiverHit(nodeId: best.id, validation: validation)
    }
    return nil
}

private func linkDragGestureFromSender(nodeId: UUID) -> some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .named("GraphSceneSpace"))
        .onChanged { value in
            #if os(macOS)
            let flags = NSEvent.modifierFlags
            let isOption = flags.contains(.option)
            #else
            let isOption = true // iOS: always allow for now (we can add a toggle later)
            #endif

            guard isOption else { return }

            if linkingFromNodeId == nil {
                linkingFromNodeId = nodeId
                linkingFromPoint = senderNubCenterPoint(nodeId: nodeId)
            }

            linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
            setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
        }
        .onEnded { value in
            defer {
                linkingFromNodeId = nil
                linkingFromPoint = nil
                linkingCurrentPoint = nil
                clearLinkHoverState()
            }

            guard let fromNode = linkingFromNodeId else { return }
            let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)

            if let hit, hit.validation.isAllowed {
                addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
            } else {
                // Dropped on empty space: treat as "unlatch" for this sender.
                removeOutgoingLinks(fromNodeId: fromNode)
            }
        }
}

/// Drag from the source node’s output nub to a destination node (console or action) to create a link.
/// This does NOT require holding Option.
private func linkDragGestureFromSenderNub(nodeId: UUID) -> some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .named("GraphSceneSpace"))
        .onChanged { value in
            if linkingFromNodeId == nil {
                linkingFromNodeId = nodeId
                linkingFromPoint = senderNubCenterPoint(nodeId: nodeId)
            }

            linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
            setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
        }
        .onEnded { value in
            defer {
                linkingFromNodeId = nil
                linkingFromPoint = nil
                linkingCurrentPoint = nil
                clearLinkHoverState()
            }

            guard let fromNode = linkingFromNodeId else { return }
            let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)

            if let hit, hit.validation.isAllowed {
                addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
            }
        }
}

private func senderNubCenterPoint(nodeId: UUID, yOffset: CGFloat = 0) -> CGPoint {
    let center = nodePosition(for: nodeId)
    let width = measuredNodeSizes[nodeId]?.width ?? senderNodeWidth
    let nubOffset: CGFloat = 5
    return CGPoint(x: center.x + (width / 2.0) + nubOffset, y: center.y + yOffset)
}

private func handleRepeaterOutputDragChanged(nodeId: UUID, index: Int, total: Int, value: DragGesture.Value) {
    if linkingFromNodeId == nil {
        linkingFromNodeId = nodeId
        currentRepeaterOutputIndex = max(0, index)
        let stackSpacing: CGFloat = 14
        let nubHeight: CGFloat = 10
        let totalCount = max(1, total)
        let stackHeight = CGFloat(totalCount) * nubHeight + CGFloat(totalCount - 1) * stackSpacing
        let yOffset = -stackHeight / 2 + nubHeight / 2 + CGFloat(index) * (nubHeight + stackSpacing)
        linkingFromPoint = senderNubCenterPoint(nodeId: nodeId, yOffset: yOffset)
    }

    linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
    setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
}

private func handleRepeaterOutputDragEnded(nodeId: UUID, index: Int, total: Int, value: DragGesture.Value) {
    defer {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
        currentRepeaterOutputIndex = 0
    }

    guard let fromNode = linkingFromNodeId else { return }
    let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)

    if let hit, hit.validation.isAllowed {
        addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
    }
}

private func handleDelayOutputDragChanged(nodeId: UUID, value: DragGesture.Value) {
    if linkingFromNodeId == nil {
        linkingFromNodeId = nodeId
        linkingFromPoint = senderNubCenterPoint(nodeId: nodeId)
    }

    linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
    setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
}

private func handleDelayOutputDragEnded(nodeId: UUID, value: DragGesture.Value) {
    defer {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
    }

    guard let fromNode = linkingFromNodeId else { return }
    let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)

    if let hit, hit.validation.isAllowed {
        addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
    }
}

private func handleConditionOutputDragChanged(nodeId: UUID, branch: GraphAutomationTraversal.UtilityBranch, value: DragGesture.Value) {
    if linkingFromNodeId == nil {
        linkingFromNodeId = nodeId
        currentConditionOutputBranch = branch
        let yOffset: CGFloat = branch == .true ? -12 : 12
        linkingFromPoint = senderNubCenterPoint(nodeId: nodeId, yOffset: yOffset)
    }

    linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
    setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
}

private func handleConditionOutputDragEnded(nodeId: UUID, branch: GraphAutomationTraversal.UtilityBranch, value: DragGesture.Value) {
    defer {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
        currentConditionOutputBranch = .`true`
    }

    currentConditionOutputBranch = branch
    guard let fromNode = linkingFromNodeId else { return }
    let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)
    if let hit, hit.validation.isAllowed {
        addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
    }
}

private func handleToggleOutputDragChanged(nodeId: UUID, isOn: Bool, value: DragGesture.Value) {
    if linkingFromNodeId == nil {
        linkingFromNodeId = nodeId
        currentToggleOutputIsOn = isOn
        let yOffset: CGFloat = isOn ? -12 : 12
        linkingFromPoint = senderNubCenterPoint(nodeId: nodeId, yOffset: yOffset)
    }
    linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
    setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
}

private func handleToggleOutputDragEnded(nodeId: UUID, isOn: Bool, value: DragGesture.Value) {
    defer {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
        currentToggleOutputIsOn = true
    }
    currentToggleOutputIsOn = isOn
    guard let fromNode = linkingFromNodeId else { return }
    let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)
    if let hit, hit.validation.isAllowed {
        addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
    }
}

private func handleSequenceOutputDragChanged(nodeId: UUID, step: Int, total: Int, value: DragGesture.Value) {
    if linkingFromNodeId == nil {
        linkingFromNodeId = nodeId
        currentSequenceOutputStep = max(0, step)
        let stackSpacing: CGFloat = 14
        let nubHeight: CGFloat = 10
        let totalCount = max(2, total)
        let stackHeight = CGFloat(totalCount) * nubHeight + CGFloat(totalCount - 1) * stackSpacing
        let yOffset = -stackHeight / 2 + nubHeight / 2 + CGFloat(step) * (nubHeight + stackSpacing)
        linkingFromPoint = senderNubCenterPoint(nodeId: nodeId, yOffset: yOffset)
    }
    linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
    setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
}

private func handleSequenceOutputDragEnded(nodeId: UUID, step: Int, total: Int, value: DragGesture.Value) {
    defer {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
        currentSequenceOutputStep = 0
    }
    guard let fromNode = linkingFromNodeId else { return }
    let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)
    if let hit, hit.validation.isAllowed {
        addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
    }
}

private func handleButtonOutputDragChanged(nodeId: UUID, buttonIndex: Int, buttons: [ButtonConfig], value: DragGesture.Value) {
    if linkingFromNodeId == nil {
        linkingFromNodeId = nodeId
        currentButtonOutputConfigId = buttons[buttonIndex].id
        let nodeCenter = nodePosition(for: nodeId)
        let nodeWidth = measuredNodeSizes[nodeId]?.width ?? senderNodeWidth
        let nubOffset: CGFloat = 5
        let itemHeight: CGFloat = 20
        let totalHeight = CGFloat(buttons.count) * itemHeight + CGFloat(buttons.count - 1) * 14
        let topY = nodeCenter.y - totalHeight / 2 + CGFloat(buttonIndex) * (itemHeight + 14) + itemHeight / 2
        linkingFromPoint = CGPoint(x: nodeCenter.x + nodeWidth / 2 + nubOffset, y: topY)
    }
    linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
    setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
}

private func handleButtonOutputDragEnded(nodeId: UUID, buttonIndex: Int, buttons: [ButtonConfig], value: DragGesture.Value) {
    defer {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        currentButtonOutputConfigId = nil
        clearLinkHoverState()
    }
    guard linkingFromNodeId != nil else { return }
    let hit = receiverNodeHitTest(at: value.location, fromNodeId: nodeId)
    if let hit, hit.validation.isAllowed {
        addOrReplaceLink(fromNodeId: nodeId, toReceiverNodeId: hit.nodeId)
    }
}

private func handleSmartLightOutputDragChanged(nodeId: UUID, kind: String, value: DragGesture.Value) {
    if linkingFromNodeId == nil {
        linkingFromNodeId = nodeId
        currentSmartLightOutputKind = kind
        let yOffset: CGFloat
        switch kind {
        case "success":
            yOffset = -24
        case "failure":
            yOffset = 0
        default:
            yOffset = 24
        }
        linkingFromPoint = senderNubCenterPoint(nodeId: nodeId, yOffset: yOffset)
    }

    linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
    setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
}

private func handleSmartLightOutputDragEnded(nodeId: UUID, kind: String, value: DragGesture.Value) {
    defer {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
        currentSmartLightOutputKind = "success"
    }

    currentSmartLightOutputKind = kind
    guard let fromNode = linkingFromNodeId else { return }
    let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)
    if let hit, hit.validation.isAllowed {
        addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
    }
}

private func handleWordTriggerOutputDragChanged(nodeId: UUID, ruleId: UUID, ruleIndex: Int, total: Int, value: DragGesture.Value) {
    if linkingFromNodeId == nil {
        linkingFromNodeId = nodeId
        currentWordTriggerRuleId = ruleId
        let stackSpacing: CGFloat = 14
        let itemHeight: CGFloat = 20  // ZStack height (Rectangle frame), not circle diameter
        let totalCount = max(1, total)
        let stackHeight = CGFloat(totalCount) * itemHeight + CGFloat(totalCount - 1) * stackSpacing
        let yOffset = -stackHeight / 2 + itemHeight / 2 + CGFloat(ruleIndex) * (itemHeight + stackSpacing)
        linkingFromPoint = senderNubCenterPoint(nodeId: nodeId, yOffset: yOffset)
    }
    linkingCurrentPoint = graphPoint(fromViewPoint: value.location)
    setLinkHoverState(receiverNodeHitTest(at: value.location, fromNodeId: nodeId))
}

private func handleWordTriggerOutputDragEnded(nodeId: UUID, ruleId: UUID, value: DragGesture.Value) {
    defer {
        linkingFromNodeId = nil
        linkingFromPoint = nil
        linkingCurrentPoint = nil
        clearLinkHoverState()
        currentWordTriggerRuleId = UUID()
    }
    guard let fromNode = linkingFromNodeId else { return }
    let hit = receiverNodeHitTest(at: value.location, fromNodeId: fromNode)
    if let hit, hit.validation.isAllowed {
        addOrReplaceLink(fromNodeId: fromNode, toReceiverNodeId: hit.nodeId)
    }
}

private func repeaterOutputLimit(for nodeId: UUID) -> Int {
    let key = nodeId.uuidString
    let fallback = DashboardGraph.RepeaterActionConfig().outputCount
    return tab.graph?.repeaterActionConfigByNodeId[key]?.outputCount ?? fallback
}

private func sequenceOutputLimit(for nodeId: UUID) -> Int {
    tab.graph?.sequenceNodeConfigByNodeId[nodeId.uuidString]?.stepCount ?? 3
}

private func connectedActionCount(from nodeId: UUID) -> Int {
    let links = tab.graph?.links ?? []
    var count = 0
    for link in links where link.isEnabled {
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        guard fromId == nodeId else { continue }
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        if isActionNodeId(toId) {
            count += 1
        }
    }
    return count
}

private func connectedConditionBranches(from nodeId: UUID) -> (trueConnected: Bool, falseConnected: Bool) {
    let links = tab.graph?.links ?? []
    let truePort = GraphAutomationTraversal.conditionOutputPortId(nodeId: nodeId, branch: .`true`)
    let falsePort = GraphAutomationTraversal.conditionOutputPortId(nodeId: nodeId, branch: .`false`)
    var trueConnected = false
    var falseConnected = false
    for link in links where link.isEnabled {
        if link.fromPortId == truePort {
            trueConnected = true
        } else if link.fromPortId == falsePort {
            falseConnected = true
        }
    }
    return (trueConnected, falseConnected)
}

private func connectedSmartLightOutputs(from nodeId: UUID) -> (success: Bool, failure: Bool, currentState: Bool) {
    let links = tab.graph?.links ?? []
    let successPort = GraphAutomationTraversal.smartLightOutputPortId(nodeId: nodeId, kind: "success")
    let failurePort = GraphAutomationTraversal.smartLightOutputPortId(nodeId: nodeId, kind: "failure")
    let currentStatePort = GraphAutomationTraversal.smartLightOutputPortId(nodeId: nodeId, kind: "currentState")
    var success = false
    var failure = false
    var currentState = false
    for link in links where link.isEnabled {
        if link.fromPortId == successPort {
            success = true
        } else if link.fromPortId == failurePort {
            failure = true
        } else if link.fromPortId == currentStatePort {
            currentState = true
        }
    }
    return (success, failure, currentState)
}

private func syncAutomationRuntimeActiveTab() {
    Task { @MainActor in
        automationRuntime.setActiveTabSnapshot(tab)
    }
}

private func addOrReplaceLink(fromNodeId: UUID, toReceiverNodeId: UUID) {
    if tab.graph == nil { tab.graph = DashboardGraph() }

    guard linkValidation(fromNodeId: fromNodeId, toReceiverNodeId: toReceiverNodeId).isAllowed else {
        return
    }

    // MVP: one link per sender->receiver pair (replace if exists)
        let fromPort: String = {
            if isRepeaterNodeId(fromNodeId) {
                let idx = max(0, min(repeaterOutputLimit(for: fromNodeId) - 1, currentRepeaterOutputIndex))
                return GraphAutomationTraversal.repeaterOutputPortId(nodeId: fromNodeId, index: idx)
            }
            if isConditionNodeId(fromNodeId) {
                return GraphAutomationTraversal.conditionOutputPortId(nodeId: fromNodeId, branch: currentConditionOutputBranch)
            }
            if isToggleNodeId(fromNodeId) {
                return GraphAutomationTraversal.toggleOutputPortId(nodeId: fromNodeId, isOn: currentToggleOutputIsOn)
            }
            if isSequenceNodeId(fromNodeId) {
                let limit = max(2, sequenceOutputLimit(for: fromNodeId))
                let step = max(0, min(limit - 1, currentSequenceOutputStep))
                return GraphAutomationTraversal.sequenceOutputPortId(nodeId: fromNodeId, step: step)
            }
            if isSmartLightNodeId(fromNodeId) {
                return GraphAutomationTraversal.smartLightOutputPortId(nodeId: fromNodeId, kind: currentSmartLightOutputKind)
            }
            if isWordTriggerNodeId(fromNodeId) {
                // Standalone word trigger nodes share the transcription node's port ID namespace.
                let canonicalId = isStandaloneWordTriggerNodeId(fromNodeId)
                    ? groupNodeId(for: "moduleGroup.transcription")
                    : fromNodeId
                return GraphAutomationTraversal.wordTriggerRulePortId(nodeId: canonicalId, ruleId: currentWordTriggerRuleId)
            }
            if isMultiButtonNodeId(fromNodeId), let configId = currentButtonOutputConfigId {
                return GraphAutomationTraversal.buttonOutputPortId(nodeId: fromNodeId, buttonConfigId: configId)
            }
            return GraphAutomationTraversal.defaultPortId(for: fromNodeId)
        }()

        let toPort = GraphAutomationTraversal.defaultPortId(for: toReceiverNodeId)

    if isRepeaterNodeId(fromNodeId) && isActionNodeId(toReceiverNodeId) {
        let limit = max(1, repeaterOutputLimit(for: fromNodeId))
        let existingLinks = tab.graph?.links.filter { link in
            let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
            let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
            return fromId == fromNodeId && isActionNodeId(toId)
        } ?? []

        let alreadyLinked = existingLinks.contains { link in
            let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
            return toId == toReceiverNodeId
        }

        if existingLinks.count >= limit && !alreadyLinked {
            return
        }
    }

    // Keep a stable reverse index so other views/runtimes can resolve portId -> nodeId reliably.
    tab.graph?.nodeIdByPortId[fromPort] = fromNodeId
    tab.graph?.nodeIdByPortId[toPort] = toReceiverNodeId

    if let idx = tab.graph?.links.firstIndex(where: {
        $0.fromPortId == fromPort && $0.toPortId == toPort
    }) {
        tab.graph?.links[idx].isEnabled = true
        tab.graph?.nodeIdByPortId[fromPort] = fromNodeId
        tab.graph?.nodeIdByPortId[toPort] = toReceiverNodeId
        syncAutomationRuntimeActiveTab()
        return
    }

    if isVariableNodeId(toReceiverNodeId) {
        removeIncomingLinks(toNodeId: toReceiverNodeId)
    }

    // Trigger/utility/actionWithResults sources carry events, not data — use .automation so the
    // automation traversal (downstreamConnections) can find them. Pure data flows stay .patch.
    let linkKind: LinkKind = {
        switch linkNodeRole(for: fromNodeId) {
        case .trigger, .buttonTrigger, .repeater, .delay, .condition, .merge, .actionWithResults:
            return .automation
        default:
            return .patch
        }
    }()

    let link = GraphLink(
        fromTileId: fromNodeId,
        fromPortId: fromPort,
        toTileId: toReceiverNodeId,
        toPortId: toPort,
        kind: linkKind,
        isEnabled: true,
        label: nil
    )
    registerGraphUndo(actionName: "Link Nodes", before: snapshotGraphForUndo())
    tab.graph?.links.append(link)
    syncAutomationRuntimeActiveTab()
}

// MARK: - Link removal helpers

private func removeOutgoingLinks(fromNodeId: UUID) {
    guard tab.graph != nil else { return }
    let fromPort = "node:\(fromNodeId.uuidString)"

    // Remove links created by either the newer port-id path or older tile-id-only path.
    let willRemove = tab.graph?.links.contains(where: { link in
        link.fromPortId == fromPort || link.fromTileId == fromNodeId
    }) ?? false

    if willRemove {
        // Avoid nested undo steps when called as part of a node delete.
        if !isBatchDeletingNodes {
            registerGraphUndo(actionName: "Unlink", before: snapshotGraphForUndo())
        }
    }

    tab.graph?.links.removeAll(where: { link in
        link.fromPortId == fromPort || link.fromTileId == fromNodeId
    })
    syncAutomationRuntimeActiveTab()
}

private func removeIncomingLinks(toNodeId: UUID) {
    guard tab.graph != nil else { return }
    let toPort = "node:\(toNodeId.uuidString)"

    // Remove links created by either the newer port-id path or older tile-id-only path.
    let willRemove = tab.graph?.links.contains(where: { link in
        link.toPortId == toPort || link.toTileId == toNodeId
    }) ?? false

    if willRemove {
        // Avoid nested undo steps when called as part of a node delete.
        if !isBatchDeletingNodes {
            registerGraphUndo(actionName: "Unlink", before: snapshotGraphForUndo())
        }
    }

    tab.graph?.links.removeAll(where: { link in
        link.toPortId == toPort || link.toTileId == toNodeId
    })

    if isVariableNodeId(toNodeId), var config = tab.graph?.variableNodeConfigByNodeId[toNodeId.uuidString] {
        config.currentTextValue = nil
        config.currentNumberValue = nil
        config.currentBooleanValue = nil
        config.lastUpdatedAt = nil
        config.sourceNodeId = nil
        tab.graph?.variableNodeConfigByNodeId[toNodeId.uuidString] = config
    }
    syncAutomationRuntimeActiveTab()
}


private func ensureLayoutForConsoleNode(_ nodeId: UUID, device: ExternalDeviceConfig) {
    if tab.graph == nil { tab.graph = DashboardGraph() }
    if tab.graph?.tileLayouts[nodeId] == nil {
        let seed = abs(device.id.uuidString.hashValue)
        let dx = CGFloat(seed % 640) - 320

        let proposed = CGPoint(x: 520 + dx, y: 120)
        let resolved = resolveInitialPlacement(for: nodeId, proposed: proposed)
        tab.graph?.tileLayouts[nodeId] = TileGraphLayout(position: resolved)
    }
}

/// Derive a stable, non-colliding graph node id for an external device id.
/// (We avoid using `device.id` directly to reduce the chance of colliding with a tile UUID.)
private func graphNodeId(forExternalDeviceId id: UUID) -> UUID {
    let data = Data(id.uuidString.utf8)
    let digest = SHA256.hash(data: data)
    // Use first 16 bytes as UUID bytes.
    let byteArray = Array(digest.prefix(16))
    var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

    withUnsafeMutableBytes(of: &uuidBytes) { buf in
        buf.copyBytes(from: byteArray)
    }

    return UUID(uuid: uuidBytes)
}

private func stableUUID(for seed: String) -> UUID {
    if let cached = stableUUIDByKey[seed] { return cached }
    let result = Self.stableUUIDStatic(for: seed)
    stableUUIDByKey[seed] = result
    return result
}
// (pcoPositionLabel(forFullName:) removed)
// MARK: - Graph init / layout helpers

private func ensureGraphInitialized(canvasSize: CGSize) {
    if tab.graph == nil {
        tab.graph = DashboardGraph()
    }
    guard tab.graph != nil else { return }
    // Ensure expensive caches are primed early so canvas-backed nodes (especially People)
    // have members available immediately. Without this, `canvasPeopleMembers` can be empty
    // until a later graph mutation (e.g., adding a graph-only node) triggers a refresh.
    if cachedModuleGroups.isEmpty {
        // Caches not yet primed — skip layout; .task will call us again after priming.
        return
    }
    // Ensure layouts for module-group nodes.
    let groups = computedModuleGroups()
    for g in groups {
        let nodeId = groupNodeId(for: g.key)
        ensureLayoutForModuleGroupNode(nodeId, groupKey: g.key)
    }

    // Ensure layouts for graph-only module-group node instances
    let instances = tab.graph?.moduleGroupNodeInstances ?? []
    for inst in instances {
        ensureLayoutForModuleGroupNode(inst.id, groupKey: inst.groupKey)
    }

    // Prune console nodes that no longer have a configured device.
    if let instances = tab.graph?.moduleGroupNodeInstances, !instances.isEmpty {
        let staleIds = instances.compactMap { inst -> UUID? in
            guard inst.groupKey == "destination.console" else { return nil }
            return consoleDevice(forNodeId: inst.id) == nil ? inst.id : nil
        }
        if !staleIds.isEmpty {
            for nodeId in staleIds {
                removeGraphOnlyModuleGroupNodeInstance(nodeId: nodeId)
            }
        }
    }

    for nodeId in consoleNodeIds {
        if let device = consoleDevice(forNodeId: nodeId) {
            ensureLayoutForConsoleNode(nodeId, device: device)
        }
    }
}

// MARK: - People label resolving
/// Available team names from the PCO tab (best-effort).
/// Available team names from the PCO tab (cached; avoid recomputing during SwiftUI graph updates).
private var pcoTeamOptionsFromTab: [String] {
    cachedPeopleTeamOptionsFromTab
}

private var pcoTabSelectionRefreshSignature: String {
    [
        tab.serviceTypeID ?? "",
        tab.serviceTypeName ?? "",
        tab.planID ?? "",
        tab.planTitle ?? "",
        tab.planDateLabel ?? "",
        tab.serviceTimeName ?? "",
        tab.teamName ?? ""
    ].joined(separator: "|")
}

private var pcoTeamRefreshSignature: String {
    let teamMap = (tab.pcoPositionToTeamName ?? [:])
        .sorted { lhs, rhs in
            lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "||")
    return "\(tab.pcoSnapshotKey ?? "")|\(teamMap)"
}

private var pcoPeopleRefreshSignature: String {
    let assignments = (pcoAssignmentsDict() ?? [:])
        .sorted { lhs, rhs in
            lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "||")
    return "\(tab.pcoSnapshotKey ?? "")|\(assignments)"
}

private var pcoRundownRefreshSignature: String {
    "\(tab.pcoSnapshotKey ?? "")|\(tab.pcoRundownSnapshotTitles.joined(separator: "||"))"
}

/// Teams explicitly selected in the PCO tab settings (parsed from `tab.teamName`).
/// Used as the default filter for People nodes that have no node-specific team selection saved.
private var tabTeamFilter: Set<String> {
    let raw = (tab.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty, raw.lowercased() != "all" else { return [] }
    return Set(raw.components(separatedBy: "||")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty })
}

/// Recompute the PCO team options from tab state.
private func recomputePCOTeamOptionsFromTab() -> [String] {
    // Primary: the per-position team map (built from time-filtered assignments)
    let fromMap = Array(Set((tab.pcoPositionToTeamName ?? [:]).values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }))

    // Secondary: teamName can be a single team or comma-separated list
    let fromTeamName: [String] = {
        let raw = (tab.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        if raw.lowercased() == "all" { return [] }
        if raw.contains(",") {
            return raw.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return [raw]
    }()

    return Array(Set(fromMap + fromTeamName)).sorted()
}
/// Build people members from PCO assignments when there are no person tiles.
/// Each member title is "Position — Name" so the console assignment UI works unchanged.
/// Prefer the filtered assignment map (team-selected) when available.
private func synthesizedPeopleMembersFromPCO() -> [ModuleMember] {
    let dict: [String: String]
    if let filtered = tab.pcoPositionAssignments, !filtered.isEmpty {
        dict = filtered
    } else if let all = tab.pcoAllPositionAssignments, !all.isEmpty {
        dict = all
    } else {
        dict = [:]
    }
    guard !dict.isEmpty else { return [] }

    let teamMap = tab.pcoPositionToTeamName ?? [:]
    let positions = dict.keys.sorted()

    return positions.compactMap { posRaw in
        let pos = posRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pos.isEmpty else { return nil }

        let name = (dict[posRaw] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let team = teamMap[pos] ?? teamMap[posRaw] ?? teamMap[pos.trimmingCharacters(in: .whitespacesAndNewlines)]
        return ModuleMember(
            tileId: tab.id,
            moduleId: stableUUID(for: "pcoPerson|\(pos)|\(name)"),
            title: "\(pos) — \(name)",
            teamName: team
        )
    }
}
private func pcoAssignmentsDict() -> [String: String]? {
    tab.pcoAllPositionAssignments ?? tab.pcoPositionAssignments
}
/// All available PCO position labels for this tab (across teams), used for console default rules.
private var allPCOPositions: [String] {
    let dict = pcoAssignmentsDict() ?? [:]
    return dict.keys
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .sorted()
}
/// Resolve a human display name for a person module.
/// If the module's name is empty or a placeholder ("Person"), and it has a PCO position name,
/// look up the assigned name from the tab's PCO assignment dictionaries.
private func resolvedPersonDisplayName(_ person: PersonTileModel, tileFallback: String) -> String {
    let trimmed = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, trimmed.lowercased() != "person" {
        return trimmed
    }

    if let pos = person.pcoPositionName?.trimmingCharacters(in: .whitespacesAndNewlines), !pos.isEmpty,
       let dict = pcoAssignmentsDict() {
        // Most common: position -> name
        if let name = dict[pos], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        // Fallback: name -> position (reverse)
        if let match = dict.first(where: { $0.value == pos })?.key, !match.isEmpty {
            return match
        }
    }

    return tileFallback
}

private func resolvedPersonPositionLabel(_ person: PersonTileModel) -> String {
    let pos = person.pcoPositionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !pos.isEmpty { return pos }
    return person.role.trimmingCharacters(in: .whitespacesAndNewlines)
}
// MARK: - Graph cache refresh (perf)
/// Schedules a refreshGraphCaches() call, coalescing multiple same-cycle requests into one.
private func scheduleGraphCacheRefresh() {
    pendingCacheRefreshWorkItem?.cancel()
    let item = DispatchWorkItem { refreshGraphCaches() }
    pendingCacheRefreshWorkItem = item
    DispatchQueue.main.async(execute: item)
}

private func cachedRundownItem(for packed: String) -> VistaPCORundownItem? {
    if let cached = rundownItemCache[packed] { return cached }
    let item = VistaPCORundownPayloadCodec.decode(from: packed)
    rundownItemCache[packed] = item
    return item
}

private func captureModuleGroupInputs() -> ModuleGroupInputs {
    let titles = resolvedPCORundownSnapshotTitles
    return ModuleGroupInputs(
        tilesSnapshot: tilesSnapshot,
        pcoPositionToTeamName: tab.pcoPositionToTeamName,
        pcoAssignmentsDict: pcoAssignmentsDict(),
        resolvedRundownTitles: titles,
        resolvedRundownItems: titles.map { cachedRundownItem(for: $0) },
        hasPCORundownModuleOnCanvas: hasPCORundownModuleOnCanvas,
        tabId: tab.id
    )
}

/// Rebuild expensive derived lists once, then reuse during view updates.
private func refreshGraphCaches() {
    let startedAt = CFAbsoluteTimeGetCurrent()
    // Module groups can be expensive (walk all tiles/modules, sort, de-dup).
    let groups = buildModuleGroups()
    cachedModuleGroups = groups

    cachedSynthesizedPeopleMembersFromPCO = synthesizedPeopleMembersFromPCO()
    // Team options are derived from tab mappings and can be large.
    cachedPeopleTeamOptionsFromTab = recomputePCOTeamOptionsFromTab()
    RelayDiagnosticsStore.shared.updateActiveGraphComposition(
        tabName: tab.name,
        canvasGroups: groups.filter(\.isCanvasBacked).map(\.key),
        graphNodeKeys: tab.graph?.moduleGroupNodeInstances.map(\.groupKey) ?? [],
        consoleNodeCount: consoleNodeIds.count,
        vistaNodeCount: isVistaIntegrationEnabled
            ? (tab.graph?.moduleGroupNodeInstances.filter { $0.groupKey == "destination.vista" }.count ?? 0)
            : 0,
        linkCount: tab.graph?.links.count ?? 0
    )
    let duration = CFAbsoluteTimeGetCurrent() - startedAt
    let graphNodeCount = tab.graph?.moduleGroupNodeInstances.count ?? 0
    let details = "groups=\(groups.count) pcoPeople=\(cachedSynthesizedPeopleMembersFromPCO.count) teamOptions=\(cachedPeopleTeamOptionsFromTab.count) graphOnlyNodes=\(graphNodeCount)"
    recordGraphPerfMetric(
        "graph.caches.refresh",
        duration: duration,
        details: details,
        slowThreshold: 0.020
    )
    incrementGraphCounter("graph.caches.refresh.calls")
}
// MARK: - Module grouping
/// Returns the packed rundown strings for the console node (supports "Title\n__KEY__:A").
/// Priority:
/// 1) If the console is linked from a Planning Center node, use that node's members (preserves keys).
/// 2) Otherwise fall back to the tab-level cached titles (`tab.pcoRundownSnapshotTitles`).
private func packedRundownSnapshotTitles(forConsoleNodeId consoleNodeId: UUID, currentGroups: [ModuleGroup]) -> [String] {
    // 1) Linked from Planning Center node?
    guard let graph = tab.graph else {
        return []
    }

    // Strict: only expose titles when a PCO node is linked to this console.
    guard isPCORundownLinked(toConsoleNodeId: consoleNodeId) else {
        return []
    }

    let toPort = "node:\(consoleNodeId.uuidString)"

    // Find a source node id that links into this console.
    // We accept either fromTileId or fromPortId because older links used tile ids.
    let inbound = graph.links.first(where: { link in
        link.isEnabled &&
        (link.toPortId == toPort || link.toTileId == consoleNodeId)
    })

    if let inbound {
        // If the source is a module group node, try to map it to a group and return its members.
        // Links always carry both `fromTileId` and `fromPortId` in our graph model.
        let fromId: UUID? = {
            // Prefer the explicit UUID on the link.
            let from = inbound.fromTileId
            if from != UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
                return from
            }

            // Fallback: parse fromPortId (format "node:<UUID>")
            let pid = inbound.fromPortId
            if pid.hasPrefix("node:") {
                let raw = String(pid.dropFirst("node:".count))
                return UUID(uuidString: raw)
            }
            return nil
        }()

        if let fromId {
            // Canvas-backed Planning Center group id
            let pcoCanvasId = groupNodeId(for: "moduleGroup.pco")
            if fromId == pcoCanvasId {
                // Use the group members (these should already be packed if available).
                if let g = currentGroups.first(where: { $0.key == "moduleGroup.pco" }) {
                    let titles = g.members.map { $0.payload ?? $0.title }
                    return titles
                }
            }

            // Graph-only instances: match against moduleGroupNodeInstances
            if let inst = graph.moduleGroupNodeInstances.first(where: { $0.id == fromId && $0.groupKey == "moduleGroup.pco" }) {
                if let g = currentGroups.first(where: { $0.key == inst.groupKey }) {
                    return g.members.map { $0.payload ?? $0.title }
                }
            }
        }
    }

    // 2) Fallback: use the latest captured rundown titles when linked (even if link points to canvas PCO).
    return resolvedPCORundownSnapshotTitles
}
/// True if the current canvas snapshot contains at least one PCO rundown module.
/// Used to avoid showing stale cached rundown titles after the PCO module is removed from the canvas.
private var hasPCORundownModuleOnCanvas: Bool {
    for tile in tilesSnapshot {
        // Prefer modules list; fall back to legacy tile.kind.
        if let ms = tile.modules, !ms.isEmpty {
            if ms.contains(where: { module in
                if case .pcoRundown = module.kind { return true }
                return false
            }) {
                return true
            }
        } else {
            // legacy fallback
            if case .pcoPlaceholder = tile.kind { return true }
        }
    }
    return false
}

struct ModuleMember: Identifiable, Equatable {
    var id: UUID { moduleId }
    let tileId: UUID
    let moduleId: UUID
    let title: String
    let payload: String?
    /// Optional PCO team name (used for People node filtering)
    let teamName: String?

    init(tileId: UUID, moduleId: UUID, title: String, payload: String? = nil, teamName: String? = nil) {
        self.tileId = tileId
        self.moduleId = moduleId
        self.title = title
        self.payload = payload
        let t = teamName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teamName = (t?.isEmpty ?? true) ? nil : t
    }
}

struct ModuleGroup: Identifiable, Equatable {
var id: String { key }
/// Stable key for this group (used to derive a stable node id).
let key: String
let title: String
let members: [ModuleMember]
/// True when this group is derived from the dashboard canvas (tile/module snapshot).
/// False when the node is graph-only (added/enabled in graph mode with no backing canvas modules).
let isCanvasBacked: Bool
}

private struct GroupBucket {
    var title: String
    var members: [ModuleMember]
    var isCanvasBacked: Bool
}

/// Replaces the anonymous (key:title:memberTitle:) return tuple from describeModuleForGrouping.
/// Named struct eliminates Swift runtime TupleCacheEntry metadata lookups on both main and background threads.
private struct ModuleDescription {
    let key: String
    let title: String
    let memberTitle: String
}

/// Pre-computed sort key paired with its member — avoids anonymous tuple TupleCacheEntry pressure in buildGroups.
private struct KeyedMember {
    let sortKey: String
    let member: ModuleMember
}

/// Replaces (title: String, key: String?) return tuple from unpackLegacyRundownTitleAndKey.
private struct LegacyRundownUnpack {
    let title: String
    let key: String?
}

/// Value-typed snapshot of inputs needed to build module groups off the main thread.
private struct ModuleGroupInputs {
    let tilesSnapshot: [DashboardTileModel]
    let pcoPositionToTeamName: [String: String]?
    let pcoAssignmentsDict: [String: String]?
    let resolvedRundownTitles: [String]
    /// Pre-decoded rundown items parallel to resolvedRundownTitles.
    /// Populated by captureModuleGroupInputs() using rundownItemCache so buildGroups()
    /// never allocates a JSONDecoder or NSMutableDictionary in the hot path.
    let resolvedRundownItems: [VistaPCORundownItem?]
    let hasPCORundownModuleOnCanvas: Bool
    let tabId: UUID
}

/// Builds group nodes from all modules in this tab, grouped by module kind.
/// MVP grouping:
/// - Person modules: all `.person` modules across all tiles
/// - Shure: all `.shureWireless`
/// - Sennheiser: all `.sennheiserWireless`
/// - PCO: all `.pcoRundown`
/// - Time/Text/Separator/Other likewise
private func buildModuleGroups() -> [ModuleGroup] {
    let startedAt = CFAbsoluteTimeGetCurrent()
    let groups = Self.buildGroups(from: captureModuleGroupInputs())
    let duration = CFAbsoluteTimeGetCurrent() - startedAt
    let memberCount = groups.reduce(0) { $0 + $1.members.count }
    let details = "tiles=\(tilesSnapshot.count) groups=\(groups.count) members=\(memberCount)"
    recordGraphPerfMetric("graph.moduleGroups.build", duration: duration, details: details, slowThreshold: 0.020)
    incrementGraphCounter("graph.moduleGroups.build.calls")
    return groups
}

nonisolated private static func stableUUIDStatic(for seed: String) -> UUID {
    let digest = SHA256.hash(data: Data(seed.utf8))
    let byteArray = Array(digest.prefix(16))
    var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    withUnsafeMutableBytes(of: &uuidBytes) { buf in buf.copyBytes(from: byteArray) }
    return UUID(uuid: uuidBytes)
}

private static func unpackLegacyRundownTitleAndKeyStatic(from raw: String) -> LegacyRundownUnpack {
    if let payload = VistaPCORundownPayloadCodec.decode(from: raw) {
        return LegacyRundownUnpack(title: payload.title, key: payload.keyName)
    }
    return LegacyRundownUnpack(title: raw.trimmingCharacters(in: .whitespacesAndNewlines), key: nil)
}

nonisolated private static func resolvedPersonDisplayNameStatic(_ person: PersonTileModel, tileFallback: String, pcoAssignmentsDict: [String: String]?) -> String {
    let trimmed = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, trimmed.lowercased() != "person" {
        return trimmed
    }
    if let pos = person.pcoPositionName?.trimmingCharacters(in: .whitespacesAndNewlines), !pos.isEmpty,
       let dict = pcoAssignmentsDict {
        if let name = dict[pos], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let match = dict.first(where: { $0.value == pos })?.key, !match.isEmpty {
            return match
        }
    }
    return tileFallback
}

nonisolated private static func resolvedPersonPositionLabelStatic(_ person: PersonTileModel) -> String {
    let pos = person.pcoPositionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !pos.isEmpty { return pos }
    return person.role.trimmingCharacters(in: .whitespacesAndNewlines)
}

nonisolated private static func resolvedPersonTeamNameStatic(_ person: PersonTileModel, pcoPositionToTeamName: [String: String]?) -> String {
    if let pos = person.pcoPositionName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !pos.isEmpty,
       let mapped = pcoPositionToTeamName?[pos] {
        let t = mapped.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
    }
    return person.pcoTeamName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private static func describeModuleForGroupingStatic(module: DashboardModuleModel, tileName: String, pcoAssignmentsDict: [String: String]?, pcoPositionToTeamName: [String: String]?) -> ModuleDescription {
    switch module.kind {
    case .person(let personModel):
        let fullName = resolvedPersonDisplayNameStatic(personModel, tileFallback: tileName, pcoAssignmentsDict: pcoAssignmentsDict)
        let position = resolvedPersonPositionLabelStatic(personModel)
        let label = position.isEmpty ? fullName : "\(position) — \(fullName)"
        let team = resolvedPersonTeamNameStatic(personModel, pcoPositionToTeamName: pcoPositionToTeamName)
        let packed = team.isEmpty ? label : (label + "\n__TEAM__:" + team)
        return ModuleDescription(key: "moduleGroup.person", title: "People", memberTitle: packed)
    case .shureWireless:
        return ModuleDescription(key: "moduleGroup.shure", title: "Shure Wireless", memberTitle: tileName)
    case .shureOverview:
        return ModuleDescription(key: "moduleGroup.shure", title: "Shure Overview", memberTitle: tileName)
    case .sennheiserWireless:
        return ModuleDescription(key: "moduleGroup.sennheiser", title: "Sennheiser Wireless", memberTitle: tileName)
    case .youtubeStreamMonitor:
        return ModuleDescription(key: "moduleGroup.youtube", title: "YouTube Stream Monitor", memberTitle: tileName)
    case .pcoRundown:
        return ModuleDescription(key: "moduleGroup.pco", title: "Planning Center", memberTitle: "Rundown")
    case .pcoTeamAssignments:
        return ModuleDescription(key: "moduleGroup.pco", title: "Planning Center", memberTitle: "Team Assignments")
    case .rosterTeamAssignments:
        return ModuleDescription(key: "moduleGroup.roster", title: "Roster Team Assignments", memberTitle: tileName)
    case .time:
        return ModuleDescription(key: "moduleGroup.time", title: "Time", memberTitle: tileName)
    case .timecode:
        return ModuleDescription(key: "moduleGroup.time", title: "Timecode", memberTitle: tileName)
    case .dawTransport:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    case .rosterPicker:
        return ModuleDescription(key: "moduleGroup.rosterPicker", title: "Picker", memberTitle: tileName)
    case .text:
        return ModuleDescription(key: "moduleGroup.text", title: "Text", memberTitle: tileName)
    case .image:
        return ModuleDescription(key: "moduleGroup.image", title: "Image", memberTitle: tileName)
    case .document:
        return ModuleDescription(key: "moduleGroup.document", title: "Document", memberTitle: tileName)
    case .ndi:
        return ModuleDescription(key: "moduleGroup.ndi", title: "NDI Feed", memberTitle: tileName)
    case .webpage:
        return ModuleDescription(key: "moduleGroup.webpage", title: "Webpage", memberTitle: tileName)
    case .separator:
        return ModuleDescription(key: "moduleGroup.separator", title: "Separators", memberTitle: tileName)
    case .proPresenter:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    case .resolume:
        return ModuleDescription(key: "moduleGroup.resolume", title: "Resolume", memberTitle: tileName)
    case .dbReader:
        return ModuleDescription(key: "moduleGroup.dbThreshold", title: "dB Threshold", memberTitle: tileName)
    case .liveTranscription:
        return ModuleDescription(key: "moduleGroup.transcription", title: "Word Trigger", memberTitle: tileName)
    case .button:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    case .rta:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    case .spectrograph:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    }
}

private static func buildGroups(from inputs: ModuleGroupInputs) -> [ModuleGroup] {
    var buckets: [String: GroupBucket] = [:]
    for tile in inputs.tilesSnapshot {
        let tileDisplay = tile.name.isEmpty ? "Tile" : tile.name
        let modules: [DashboardModuleModel]
        if let ms = tile.modules, !ms.isEmpty {
            modules = ms
        } else {
            switch tile.kind {
            case .person(let personModel):
                modules = [DashboardModuleModel(kind: .person(personModel), order: 0)]
            case .time:
                modules = [DashboardModuleModel(kind: .time, order: 0, timeConfig: TimeModuleConfig.default())]
            case .pcoPlaceholder:
                modules = [DashboardModuleModel(kind: .pcoRundown, order: 0)]
            default:
                modules = []
            }
        }
        for module in modules {
            let desc = describeModuleForGroupingStatic(
                module: module,
                tileName: tileDisplay,
                pcoAssignmentsDict: inputs.pcoAssignmentsDict,
                pcoPositionToTeamName: inputs.pcoPositionToTeamName
            )
            let key = desc.key
            let title = desc.title
            let memberTitle = desc.memberTitle
            guard !key.isEmpty else { continue }
            var titleText = memberTitle
            var teamName: String? = nil
            if let range = memberTitle.range(of: "\n__TEAM__:") {
                titleText = String(memberTitle[..<range.lowerBound])
                let teamPart = String(memberTitle[range.upperBound...])
                let t = teamPart.trimmingCharacters(in: .whitespacesAndNewlines)
                teamName = t.isEmpty ? nil : t
            }
            if key == "moduleGroup.person" {
                let pos = titleText.components(separatedBy: " — ").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !pos.isEmpty, let mapped = inputs.pcoPositionToTeamName?[pos] {
                    let t = mapped.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { teamName = t }
                }
            }
            let member = ModuleMember(tileId: tile.id, moduleId: module.id, title: titleText, teamName: teamName)
            if buckets[key] == nil {
                // Any group discovered from the frozen tile snapshot is canvas-backed.
                buckets[key] = GroupBucket(title: title, members: [], isCanvasBacked: true)
            } else {
                buckets[key]!.isCanvasBacked = true
            }
            buckets[key]!.members.append(member)
        }
    }
    if !inputs.resolvedRundownTitles.isEmpty {
        // resolvedRundownItems is pre-decoded by captureModuleGroupInputs() — zero JSONDecoder allocations here.
        let members: [ModuleMember] = zip(inputs.resolvedRundownTitles, inputs.resolvedRundownItems).map { (packed, preDecoded) in
            let uuid = stableUUIDStatic(for: "pcoRundownTitle|\(packed)")
            let title = preDecoded?.title ?? unpackLegacyRundownTitleAndKeyStatic(from: packed).title
            return ModuleMember(
                tileId: inputs.tabId,
                moduleId: uuid,
                title: title,
                payload: packed
            )
        }
        buckets["moduleGroup.pco"] = GroupBucket(
            title: "Planning Center",
            members: members,
            isCanvasBacked: inputs.hasPCORundownModuleOnCanvas
        )
    }
    var groups: [ModuleGroup] = buckets.map { (key, value) in
        var members = value.members
        if key != "moduleGroup.pco" {
            // Pre-compute sort keys once per member (O(N)) using named struct to avoid TupleCacheEntry pressure.
            // \u{0000} separator is safe because member titles never contain null bytes.
            let keyed = members.map { m in
                KeyedMember(sortKey: m.title + "\u{0000}" + m.moduleId.uuidString, member: m)
            }
            members = keyed.sorted { $0.sortKey < $1.sortKey }.map(\.member)
            var seen = Set<String>()
            members = members.filter { seen.insert($0.title).inserted }
        }
        return ModuleGroup(key: key, title: value.title, members: members, isCanvasBacked: value.isCanvasBacked)
    }
    groups.sort { $0.title < $1.title }
    return groups
}

private func describeModuleForGrouping(module: DashboardModuleModel, tileName: String) -> ModuleDescription {
    switch module.kind {
    case .person(let personModel):
        let fullName = resolvedPersonDisplayName(personModel, tileFallback: tileName)
        let position = resolvedPersonPositionLabel(personModel)
        let label = position.isEmpty ? fullName : "\(position) — \(fullName)"
        let team = resolvedPersonTeamName(personModel)
        let packed = team.isEmpty ? label : (label + "\n__TEAM__:" + team)
        return ModuleDescription(key: "moduleGroup.person", title: "People", memberTitle: packed)
    case .shureWireless:
        return ModuleDescription(key: "moduleGroup.shure", title: "Shure Wireless", memberTitle: tileName)
    case .shureOverview:
        return ModuleDescription(key: "moduleGroup.shure", title: "Shure Overview", memberTitle: tileName)
    case .sennheiserWireless:
        return ModuleDescription(key: "moduleGroup.sennheiser", title: "Sennheiser Wireless", memberTitle: tileName)
    case .youtubeStreamMonitor:
        return ModuleDescription(key: "moduleGroup.youtube", title: "YouTube Stream Monitor", memberTitle: tileName)
    case .pcoRundown:
        return ModuleDescription(key: "moduleGroup.pco", title: "Planning Center", memberTitle: "Rundown")
    case .pcoTeamAssignments:
        return ModuleDescription(key: "moduleGroup.pco", title: "Planning Center", memberTitle: "Team Assignments")
    case .rosterTeamAssignments:
        return ModuleDescription(key: "moduleGroup.roster", title: "Roster Team Assignments", memberTitle: tileName)
    case .time:
        return ModuleDescription(key: "moduleGroup.time", title: "Time", memberTitle: tileName)
    case .timecode:
        return ModuleDescription(key: "moduleGroup.time", title: "Timecode", memberTitle: tileName)
    case .dawTransport:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    case .rosterPicker:
        return ModuleDescription(key: "moduleGroup.rosterPicker", title: "Picker", memberTitle: tileName)
    case .text:
        return ModuleDescription(key: "moduleGroup.text", title: "Text", memberTitle: tileName)
    case .image:
        return ModuleDescription(key: "moduleGroup.image", title: "Image", memberTitle: tileName)
    case .document:
        return ModuleDescription(key: "moduleGroup.document", title: "Document", memberTitle: tileName)
    case .ndi:
        return ModuleDescription(key: "moduleGroup.ndi", title: "NDI Feed", memberTitle: tileName)
    case .webpage:
        return ModuleDescription(key: "moduleGroup.webpage", title: "Webpage", memberTitle: tileName)
    case .separator:
        return ModuleDescription(key: "moduleGroup.separator", title: "Separators", memberTitle: tileName)
    case .proPresenter:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    case .resolume:
        return ModuleDescription(key: "moduleGroup.resolume", title: "Resolume", memberTitle: tileName)
    case .dbReader:
        return ModuleDescription(key: "moduleGroup.dbThreshold", title: "dB Threshold", memberTitle: tileName)
    case .liveTranscription:
        return ModuleDescription(key: "moduleGroup.transcription", title: "Word Trigger", memberTitle: tileName)
    case .button:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    case .rta:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    case .spectrograph:
        return ModuleDescription(key: "", title: "", memberTitle: "")
    }
}

private func unpackLegacyRundownTitleAndKey(from raw: String) -> LegacyRundownUnpack {
    if let payload = VistaPCORundownPayloadCodec.decode(from: raw) {
        return LegacyRundownUnpack(title: payload.title, key: payload.keyName)
    }
    return LegacyRundownUnpack(title: raw.trimmingCharacters(in: .whitespacesAndNewlines), key: nil)
}

private func resolvedPersonTeamName(_ person: PersonTileModel) -> String {
    // Prefer authoritative mapping: position -> team.
    if let pos = person.pcoPositionName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !pos.isEmpty,
       let mapped = tab.pcoPositionToTeamName?[pos] {
        let t = mapped.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
    }

    // Fallback: whatever is currently stored on the person model.
    return person.pcoTeamName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func ensureLayoutForModuleGroupNode(_ nodeId: UUID, groupKey: String) {
    if tab.graph == nil { tab.graph = DashboardGraph() }
    if tab.graph?.tileLayouts[nodeId] == nil {
        let seed = abs(groupKey.hashValue)
        let dy = CGFloat(seed % 520) - 260

        let proposed = CGPoint(x: 220, y: 320 + dy)
        let resolved = resolveInitialPlacement(for: nodeId, proposed: proposed)
        tab.graph?.tileLayouts[nodeId] = TileGraphLayout(position: resolved)
    }
}

/// Stable node id for a module group key (derived from tab id + group key).
private func groupNodeId(for groupKey: String) -> UUID {
    let data = Data((tab.id.uuidString + "|" + groupKey).utf8)
    let digest = SHA256.hash(data: data)
    let byteArray = Array(digest.prefix(16))
    var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    withUnsafeMutableBytes(of: &uuidBytes) { buf in
        buf.copyBytes(from: byteArray)
    }
    return UUID(uuid: uuidBytes)
}

private func nodePosition(for tileId: UUID) -> CGPoint {
    if let transient = transientNodePositions[tileId] { return transient }
    if tab.graph == nil { tab.graph = DashboardGraph() }
    return tab.graph?.tileLayouts[tileId]?.position.cgPoint ?? .zero
}

private func setNodePosition(_ p: CGPoint, for tileId: UUID) {
    if tab.graph == nil { tab.graph = DashboardGraph() }
    var layout = tab.graph?.tileLayouts[tileId] ?? TileGraphLayout(position: .zero)
    layout.position = CGPointCodable(p)
    tab.graph?.tileLayouts[tileId] = layout
    transientNodePositions.removeValue(forKey: tileId)
}

private func dottedGridLayer(in size: CGSize, zoom: CGFloat) -> some View {
    let pad = canvasDrawPadding
    return Canvas { context, canvasSize in
        context.blendMode = .plusLighter

        let step: CGFloat = 40
        let majorEvery: Int = 4
        let minorDot: CGFloat = 2.0
        let majorDot: CGFloat = 3.0
        let cols = Int(canvasSize.width / step) + 2
        let rows = Int(canvasSize.height / step) + 2
        let minorColor = Color.white.opacity(0.10)
        let majorColor = Color.white.opacity(0.16)

        for row in 0...rows {
            for col in 0...cols {
                let x = CGFloat(col) * step
                let y = CGFloat(row) * step
                let isMajor = row % majorEvery == 0 && col % majorEvery == 0
                let size = isMajor ? majorDot : minorDot
                let color = isMajor ? majorColor : minorColor
                let rect = CGRect(x: x, y: y, width: size, height: size)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
    .frame(width: size.width + pad * 2, height: size.height + pad * 2)
    .offset(x: -pad, y: -pad)
    .allowsHitTesting(false)
    .blendMode(.plusLighter)
}

// MARK: - Collision avoidance (prevent nodes overlapping)

private var allVisibleGraphNodeIds: [UUID] {
    var ids: [UUID] = []

    // Canvas-backed module group nodes
    let groups = computedModuleGroups()
    ids.append(contentsOf: groups.map { groupNodeId(for: $0.key) })

    // Graph-only module group node instances
    if let graph = tab.graph {
        ids.append(contentsOf: graph.moduleGroupNodeInstances
            .filter { isVistaIntegrationEnabled || $0.groupKey != "destination.vista" }
            .map { $0.id })
    }

    // Console nodes
    ids.append(contentsOf: consoleNodeIds)

    let hidden = hiddenGraphNodeIds

    // De-dup
    var seen = Set<UUID>()
    return ids.filter { seen.insert($0).inserted && !hidden.contains($0) }
}

/// Size used for hit-testing (marquee selection + "started over a node" checks).
private func nodeHitTestSize(for nodeId: UUID) -> CGSize {
    if let measured = measuredNodeSizes[nodeId], measured.width > 1, measured.height > 1 {
        return CGSize(width: measured.width + 8, height: measured.height + 8)
    }

    let consoleIds = Set(consoleNodeIds)
    if consoleIds.contains(nodeId) {
        return CGSize(width: consoleNodeWidth, height: 320)
    }
    return CGSize(width: senderNodeWidth, height: 300)
}

/// Size used for collision avoidance only ("nodes can’t sit on top of each other").
/// Slightly smaller than hit-testing so layout feels less conservative.
private func nodeCollisionSize(for nodeId: UUID) -> CGSize {
    if let measured = measuredNodeSizes[nodeId], measured.width > 1, measured.height > 1 {
        return CGSize(width: max(1, measured.width - 8),
                      height: max(1, measured.height - 8))
    }

    // fallback until first measurement arrives
    let consoleIds = Set(consoleNodeIds)
    if consoleIds.contains(nodeId) {
        return CGSize(width: max(1, consoleNodeWidth - 24), height: 280)
    }
    return CGSize(width: max(1, senderNodeWidth - 32), height: 260)
}

private func nodeRect(center: CGPoint, size: CGSize) -> CGRect {
    CGRect(
        x: center.x - size.width / 2.0,
        y: center.y - size.height / 2.0,
        width: size.width,
        height: size.height
    )
}

private func marqueeRectInGraphSpace() -> CGRect? {
    guard let rectView = marqueeRectInViewSpace() else { return nil }
    let startGraph = graphPoint(fromViewPoint: CGPoint(x: rectView.minX, y: rectView.minY))
    let endGraph = graphPoint(fromViewPoint: CGPoint(x: rectView.maxX, y: rectView.maxY))
    return CGRect(
        x: min(startGraph.x, endGraph.x),
        y: min(startGraph.y, endGraph.y),
        width: max(1, abs(endGraph.x - startGraph.x)),
        height: max(1, abs(endGraph.y - startGraph.y))
    )
}

private func marqueeRectInViewSpace() -> CGRect? {
    guard let s = marqueeStart, let c = marqueeCurrent else { return nil }
    let x0 = min(s.x, c.x)
    let y0 = min(s.y, c.y)
    let x1 = max(s.x, c.x)
    let y1 = max(s.y, c.y)
    return CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
}

private func nodesIntersectingMarquee(_ rect: CGRect) -> Set<UUID> {
    var hits = Set<UUID>()
    for id in allVisibleGraphNodeIds {
        let center = nodePosition(for: id)
        let r = nodeRect(center: center, size: nodeHitTestSize(for: id))
        if r.intersects(rect) {
            hits.insert(id)
        }
    }
    return hits
}

private func clearMarquee() {
    isMarqueeSelecting = false
    marqueeStart = nil
    marqueeCurrent = nil
}
/// When spawning a node for the first time, nudge it away from existing nodes so we don't start overlapped.
private func resolveInitialPlacement(for nodeId: UUID, proposed: CGPoint) -> CGPoint {
    let padding: CGFloat = 4
    var p = proposed
    let size = nodeCollisionSize(for: nodeId)

    // Try a few nudges; prefer moving down.
    for _ in 0..<40 {
        let rect = nodeRect(center: p, size: size)

        var collided = false
        for otherId in allVisibleGraphNodeIds where otherId != nodeId {
            let otherCenter = nodePosition(for: otherId)
            let otherSize = nodeCollisionSize(for: otherId)
            let otherRect = nodeRect(center: otherCenter, size: otherSize)
                .insetBy(dx: -padding, dy: -padding)

            if rect.intersects(otherRect) {
                collided = true
                p.y += max(18, otherSize.height * 0.22)
                break
            }
        }

        if !collided { break }
    }

    return p
}
/// Push `movedNodeId` out of overlaps with all other nodes.
/// We only move the dragged node (not all nodes), which keeps the layout stable.
private func resolveCollisionsForMovedNode(_ movedNodeId: UUID, startingAt start: CGPoint) -> CGPoint {
    let padding: CGFloat = 4
    var p = start

    let movedSize = nodeCollisionSize(for: movedNodeId)

    // Iterate a few times in case we collide with multiple nodes.
    for _ in 0..<12 {
        var moved = false
        let movedRect = nodeRect(center: p, size: movedSize)

        for otherId in allVisibleGraphNodeIds where otherId != movedNodeId {
            let otherCenter = nodePosition(for: otherId)
            let otherSize = nodeCollisionSize(for: otherId)
            let otherRect = nodeRect(center: otherCenter, size: otherSize)

            // If rectangles overlap (with padding), push out along the axis of least penetration.
            let expandedOther = otherRect.insetBy(dx: -padding, dy: -padding)
            if movedRect.intersects(expandedOther) {
                let ix = min(movedRect.maxX, expandedOther.maxX) - max(movedRect.minX, expandedOther.minX)
                let iy = min(movedRect.maxY, expandedOther.maxY) - max(movedRect.minY, expandedOther.minY)

                if ix > 0, iy > 0 {
                    // Move away from other, choosing the smallest correction axis.
                    let dx = (p.x >= otherCenter.x) ? (ix + 0.5) : -(ix + 0.5)
                    let dy = (p.y >= otherCenter.y) ? (iy + 0.5) : -(iy + 0.5)

                    if ix < iy {
                        p.x += dx
                    } else {
                        p.y += dy
                    }
                    moved = true
                    break
                }
            }
        }

        if !moved { break }
    }

    return p
}

// MARK: - Dragging

private func nodeDragGesture(tileId: UUID) -> some Gesture {
    // Use GraphSpace so drag math stays consistent with our stored graph positions.
    DragGesture(minimumDistance: 1, coordinateSpace: .named("GraphSceneSpace"))
        .onChanged { value in
            #if os(macOS)
            if NSEvent.modifierFlags.contains(.option) { return }
            #endif
            if linkingFromNodeId != nil { return }
            if !isNodeDragging {
                isNodeDragging = true
                if isMarqueeSelecting {
                    clearMarquee()
                }
            }
            // If the previous marquee somehow got stuck, reset it.
            if isMarqueeSelecting && marqueeStart == nil {
                clearMarquee()
            }
            // Base position in graph-space
            let start = dragStartByTileId[tileId] ?? nodePosition(for: tileId)
            if dragStartByTileId[tileId] == nil {
                dragStartByTileId[tileId] = start
            }

            let safeZoom = max(0.0001, zoom)
            let startViewPoint = CGPoint(
                x: (start.x * safeZoom) + pan.width,
                y: (start.y * safeZoom) + pan.height
            )

            if dragGrabOffsetByTileId[tileId] == nil {
                dragGrabOffsetByTileId[tileId] = CGPoint(
                    x: value.startLocation.x - startViewPoint.x,
                    y: value.startLocation.y - startViewPoint.y
                )
            }

            let grab = dragGrabOffsetByTileId[tileId] ?? .zero
            let desiredViewPoint = CGPoint(
                x: value.location.x - grab.x,
                y: value.location.y - grab.y
            )
            let newPos = graphPoint(fromViewPoint: desiredViewPoint)

            transientNodePositions[tileId] = newPos
        }
        .onEnded { _ in
            if isNodeDragging {
                isNodeDragging = false
            }
            let finalPos = transientNodePositions[tileId] ?? nodePosition(for: tileId)
            setNodePosition(finalPos, for: tileId)

            dragStartByTileId[tileId] = nil
            dragGrabOffsetByTileId[tileId] = nil
            transientNodePositions.removeValue(forKey: tileId)
        }
}

// MARK: - Viewport transforms

private func applyViewport(to graphPoint: CGPoint) -> CGPoint {
    graphPoint
}

private func graphPoint(fromViewPoint viewPoint: CGPoint) -> CGPoint {
    let safeZoom = zoom == 0 ? 1.0 : zoom
    return CGPoint(
        x: (viewPoint.x - pan.width) / safeZoom,
        y: (viewPoint.y - pan.height) / safeZoom
    )
}

private func visibleGraphRect(viewSize: CGSize) -> CGRect {
    let safeZoom = max(0.0001, zoom)
    // Convert the on-screen view rect into graph-space by reversing the current pan/zoom.
    let x0 = (0 - pan.width) / safeZoom
    let y0 = (0 - pan.height) / safeZoom
    let x1 = (viewSize.width - pan.width) / safeZoom
    let y1 = (viewSize.height - pan.height) / safeZoom
    return CGRect(
        x: min(x0, x1),
        y: min(y0, y1),
        width: abs(x1 - x0),
        height: abs(y1 - y0)
    )
}

private func clampZoom(_ z: CGFloat) -> CGFloat {
    // Keep conservative bounds; tweak to match your gesture limits if different.
    min(max(z, 0.25), 2.5)
}

private func graphContentBounds() -> CGRect? {
    let nodeRects = allVisibleGraphNodeIds.map { nodeId in
        nodeRect(center: nodePosition(for: nodeId), size: nodeHitTestSize(for: nodeId))
    }

    guard let firstRect = nodeRects.first else { return nil }

    return nodeRects.dropFirst().reduce(firstRect) { partialResult, rect in
        partialResult.union(rect)
    }
}

private func centerGraphBounds(in viewSize: CGSize, zoomLevel: CGFloat) {
    let targetZoom = clampZoom(zoomLevel)

    guard let bounds = graphContentBounds(),
          viewSize.width > 0,
          viewSize.height > 0
    else {
        withAnimation(.easeInOut(duration: 0.25)) {
            zoom = targetZoom
            pan = .zero
        }
        return
    }

    let screenCenter = CGPoint(x: viewSize.width / 2.0, y: viewSize.height / 2.0)
    let graphCenter = CGPoint(x: bounds.midX, y: bounds.midY)
    let targetPan = CGSize(
        width: screenCenter.x - (graphCenter.x * targetZoom),
        height: screenCenter.y - (graphCenter.y * targetZoom)
    )

    withAnimation(.easeInOut(duration: 0.25)) {
        zoom = targetZoom
        pan = targetPan
    }
}

private func fitGraphToViewport(_ viewSize: CGSize) {
    guard let bounds = graphContentBounds(),
          bounds.width > 0,
          bounds.height > 0,
          viewSize.width > 0,
          viewSize.height > 0
    else {
        centerGraphBounds(in: viewSize, zoomLevel: 1.0)
        return
    }

    let paddedBounds = bounds.insetBy(dx: -48, dy: -48)
    let scaleX = viewSize.width / max(1, paddedBounds.width)
    let scaleY = viewSize.height / max(1, paddedBounds.height)
    let targetZoom = clampZoom(min(scaleX, scaleY))
    let screenCenter = CGPoint(x: viewSize.width / 2.0, y: viewSize.height / 2.0)
    let graphCenter = CGPoint(x: paddedBounds.midX, y: paddedBounds.midY)
    let targetPan = CGSize(
        width: screenCenter.x - (graphCenter.x * targetZoom),
        height: screenCenter.y - (graphCenter.y * targetZoom)
    )

    withAnimation(.easeInOut(duration: 0.25)) {
        zoom = targetZoom
        pan = targetPan
    }
}

private func revealNodeIfNeeded(nodeId: UUID, viewSize: CGSize) {
    let nodeCenter = nodePosition(for: nodeId)
    let size = nodeHitTestSize(for: nodeId)

    // Give the node a little breathing room so it isn't edge-clipped.
    let nodeRect = nodeRect(center: nodeCenter, size: size).insetBy(dx: -24, dy: -24)

    let visible = visibleGraphRect(viewSize: viewSize)

    // Already visible? nothing to do.
    if visible.contains(nodeRect) { return }

    // Target is union of current view + new node.
    let target = visible.union(nodeRect)

    let scaleX = viewSize.width / max(1, target.width)
    let scaleY = viewSize.height / max(1, target.height)
    let targetZoom = clampZoom(min(scaleX, scaleY) * 0.95) // margin

    let targetCenter = CGPoint(x: target.midX, y: target.midY)
    let screenCenter = CGPoint(x: viewSize.width / 2.0, y: viewSize.height / 2.0)

    // pan is applied after scale: screen = graph*zoom + pan
    let newPan = CGSize(
        width: screenCenter.x - (targetCenter.x * targetZoom),
        height: screenCenter.y - (targetCenter.y * targetZoom)
    )

    withAnimation(.easeInOut(duration: 0.25)) {
        zoom = targetZoom
        pan = newPan
    }
}
private func pruneGraphStateForRemovedCanvasNodes(currentGroups: [ModuleGroup]) {
    guard tab.graph != nil else { return }

    // During Graph <-> Canvas transitions, group building can be transiently empty.
    // Never treat empty as "everything removed" or we'll wipe links/layouts.
    guard !currentGroups.isEmpty else { return }

    // Only prune canvas-backed nodes.
    let visibleCanvasKeys = Set(currentGroups.filter { $0.isCanvasBacked }.map { $0.key })
    guard !visibleCanvasKeys.isEmpty else { return }

    // Candidate keys: visible keys + known addable keys
    let candidateKeys = Set(currentGroups.map { $0.key }).union(Set(addableGroups.map { $0.id }))

    for key in candidateKeys {
        if visibleCanvasKeys.contains(key) { continue }

        let nodeId = groupNodeId(for: key)
        let port = "node:\(nodeId.uuidString)"

        let hasLayout = tab.graph?.tileLayouts[nodeId] != nil
        let hasLinks = tab.graph?.links.contains(where: { link in
            link.fromTileId == nodeId || link.toTileId == nodeId ||
            link.fromPortId == port || link.toPortId == port
        }) ?? false

        guard hasLayout || hasLinks else { continue }

        tab.graph?.tileLayouts.removeValue(forKey: nodeId)
        tab.graph?.links.removeAll(where: { link in
            link.fromTileId == nodeId || link.toTileId == nodeId ||
            link.fromPortId == port || link.toPortId == port
        })

        if linkingFromNodeId == nodeId {
            linkingFromNodeId = nil
            linkingFromPoint = nil
            linkingCurrentPoint = nil
            clearLinkHoverState()
        }
    }
}

private func isPeopleLinked(toConsoleNodeId consoleNodeId: UUID) -> Bool {
    guard let graph = tab.graph else { return false }
    let toPort = "node:\(consoleNodeId.uuidString)"

    // Canvas-backed People node
    let canvasId = groupNodeId(for: "moduleGroup.person")
    let canvasFrom = "node:\(canvasId.uuidString)"
    if graph.links.contains(where: { link in
        link.isEnabled &&
        (link.fromPortId == canvasFrom || link.fromTileId == canvasId) &&
        (link.toPortId == toPort || link.toTileId == consoleNodeId)
    }) {
        return true
    }

    // Graph-only People instances
    for inst in graph.moduleGroupNodeInstances where inst.groupKey == "moduleGroup.person" {
        let from = "node:\(inst.id.uuidString)"
        if graph.links.contains(where: { link in
            link.isEnabled &&
            (link.fromPortId == from || link.fromTileId == inst.id) &&
            (link.toPortId == toPort || link.toTileId == consoleNodeId)
        }) {
            return true
        }
    }
    return false
}

/// Convert a console graph nodeId back to the underlying ExternalDeviceConfig.id
private func externalDeviceId(forConsoleNodeId nodeId: UUID) -> UUID? {
    // New nodes: look up via the explicit mapping stored in the graph.
    if let deviceId = tab.graph?.consoleDeviceIdByNodeId[nodeId.uuidString] {
        return deviceId
    }
    // Backward compat: nodes created before consoleDeviceIdByNodeId existed have
    // SHA-256-derived UUIDs. Recover the device by reversing the hash.
    let consoles = externalDevicesSnapshot.filter { $0.kind == .audioConsole }
    return consoles.first(where: { graphNodeId(forExternalDeviceId: $0.id) == nodeId })?.id
}

/// Returns the first graph node instance (in insertion order) for the given console device.
/// Used by send-all paths that need a representative node position or rundown link status.
private func firstConsoleNodeId(forDeviceId deviceId: UUID) -> UUID? {
    (tab.graph?.moduleGroupNodeInstances ?? [])
        .filter { $0.groupKey == "destination.console" }
        .first { externalDeviceId(forConsoleNodeId: $0.id) == deviceId }
        .map { $0.id }
}

private func vistaDevice(forNodeId nodeId: UUID) -> ExternalDeviceConfig? {
    guard let deviceId = externalDeviceId(forVistaNodeId: nodeId) else { return nil }
    return externalDevicesSnapshot.first(where: { $0.id == deviceId })
}

private func externalDeviceId(forVistaNodeId nodeId: UUID) -> UUID? {
    let devices = externalDevicesSnapshot.filter { $0.kind == .vistaConsole }
    return devices.first(where: { graphNodeId(forExternalDeviceId: $0.id) == nodeId })?.id
}
// MARK: - Graph: Send All to Consoles (ordering + stagger)

private func orderedConsoleExternalDeviceIdsForSendAll() -> [UUID] {
    let mapped: [(id: UUID, p: CGPoint)] = consoleExternalDeviceIds.map { deviceId in
        let nodeId = firstConsoleNodeId(forDeviceId: deviceId)
            ?? graphNodeId(forExternalDeviceId: deviceId)
        let p = nodePosition(for: nodeId)
        return (deviceId, p)
    }

    let sorted = mapped.sorted { a, b in
        if a.p.y != b.p.y { return a.p.y < b.p.y }     // top -> bottom
        if a.p.x != b.p.x { return a.p.x < b.p.x }     // left -> right
        return a.id.uuidString < b.id.uuidString       // stable tie-break
    }

    return sorted.map { $0.id }
}
// MARK: - Send All Availability

private func computeSendAllAvailability() -> Bool {
    // If no console nodes exist, Send All should be disabled
    return !consoleExternalDeviceIds.isEmpty
}

/// True if at least one target console has any channel assignments/defaults configured.
private func hasAnyAssignmentsToSend(consoleIds: [UUID]) -> Bool {
    guard !consoleIds.isEmpty else { return false }
    let snapshot = ExternalDevicesStore.shared.currentSnapshot()

    for dev in snapshot.devices {
        guard let id = GraphReflectionAdapter.extractId(from: dev), consoleIds.contains(id) else { continue }
        if GraphReflectionAdapter.extractAssignmentsCount(from: dev) > 0 { return true }
    }
    return false
}

/// True if we have any Planning Center rundown snapshot titles available to send.
private func hasAnySnapshotsToSend() -> Bool {
    let titles = tab.pcoRundownSnapshotTitles
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return !titles.isEmpty
}
// MARK: - Graph: Send All to Consoles

private func fireSendAllToConsoles(
    staggerMs: Double = 180,
    includeAssignments: Bool = true,
    includeSnapshots: Bool = true
) {
    // If there are no console nodes, there's nothing to do.
    let orderedIds = orderedConsoleExternalDeviceIdsForSendAll()
    guard !orderedIds.isEmpty else { return }

    // If the caller disabled both categories, do nothing.
    guard includeAssignments || includeSnapshots else { return }

    // Only send what actually exists.
    let willSendAssignments = includeAssignments && hasAnyAssignmentsToSend(consoleIds: orderedIds)
    let willSendSnapshots = includeSnapshots && hasAnySnapshotsToSend()

    // Guard against "fake" sends (nothing configured, no rundown titles, etc.)
    guard willSendAssignments || willSendSnapshots else { return }

    NotificationCenter.default.post(
        name: .prodlinkGraphSendAllToConsoles,
        object: orderedIds,
        userInfo: [
            "delayMs": max(0, staggerMs),
            "includeAssignments": willSendAssignments,
            "includeSnapshots": willSendSnapshots
        ]
    )
}
// MARK: - Trigger -> Action execution (executor wired)

private func runActionsDownstream(of triggerNodeId: UUID, userInfo: [AnyHashable: Any]) {
    guard var graph = tab.graph else { return }

    let sourcePortId: String? = {
        guard let configId = userInfo["buttonConfigId"] as? UUID else { return nil }
        return GraphAutomationTraversal.buttonOutputPortId(nodeId: triggerNodeId, buttonConfigId: configId)
    }()

    let variableNodeIds = GraphAutomationTraversal.downstreamNodeIds(
        graph: graph,
        triggerNodeId: triggerNodeId,
        matchingGroupKeys: ["utility.variable"],
        sourcePortId: sourcePortId,
        resolveNodeIdFromPortId: { nodeIdFromPortId($0) }
    )

    if !variableNodeIds.isEmpty {
        let payloadText = userInfo[TriggerNodeUserInfoKeys.payloadText] as? String
        let payloadNumber = userInfo[TriggerNodeUserInfoKeys.payloadNumber] as? Double
        let payloadBoolean = userInfo[TriggerNodeUserInfoKeys.payloadBoolean] as? Bool
        for variableNodeId in variableNodeIds {
            GraphRuntime.updateVariableNodeValue(
                graph: &graph,
                nodeId: variableNodeId,
                payloadText: payloadText,
                payloadNumber: payloadNumber,
                payloadBoolean: payloadBoolean,
                sourceNodeId: triggerNodeId
            )
        }
        tab.graph = graph
    }

    let downstream = GraphAutomationTraversal.downstreamActionInstances(
        graph: graph,
        triggerNodeId: triggerNodeId,
        sourcePortId: sourcePortId,
        resolveNodeIdFromPortId: { nodeIdFromPortId($0) }
    )

    for action in downstream {
        runActionNode(nodeId: action.nodeId, key: action.key)
    }

    GraphAutomationRuntime.shared.runQuConsoleActionsFromTrigger(graph: graph, triggerNodeId: triggerNodeId)
    GraphAutomationRuntime.shared.runDigiCoConsoleActionsFromTrigger(graph: graph, triggerNodeId: triggerNodeId)
    GraphAutomationRuntime.shared.runStandardConsoleActionsFromTrigger(graph: graph, triggerNodeId: triggerNodeId)

    let repeaterNodes = downstreamRepeaterNodeIds(graph: graph, triggerNodeId: triggerNodeId, sourcePortId: sourcePortId)
    for repeaterNodeId in repeaterNodes {
        runRepeaterNode(nodeId: repeaterNodeId)
    }

    let delayNodes = downstreamDelayNodeIds(graph: graph, triggerNodeId: triggerNodeId, sourcePortId: sourcePortId)
    for delayNodeId in delayNodes {
        runDelayNode(nodeId: delayNodeId)
    }
}

private func shouldHandleTrigger(nodeId: UUID) -> Bool {
    let now = Date().timeIntervalSince1970
    let last = lastTriggerFireAtByNodeId[nodeId] ?? 0
    if (now - last) < 0.15 {
        return false
    }
    lastTriggerFireAtByNodeId[nodeId] = now
    return true
}

private func runActionNode(nodeId: UUID, key: String) {
    guard let graph = tab.graph else { return }

    // Build an execution context from current graph/tab state.
    // This allows background/Canvas-triggered runs to execute consistently.
    let snapshotDevices = ExternalDevicesStore.shared.currentSnapshot().devices

    let ctx = GraphActionExecutor.ExecutionContext(
        consoleExternalDeviceIds: consoleExternalDeviceIds,
        consolePosition: { consoleId in
            let consoleNodeId = firstConsoleNodeId(forDeviceId: consoleId)
                ?? graphNodeId(forExternalDeviceId: consoleId)
            return nodePosition(for: consoleNodeId)
        },
        pcoRundownSnapshotTitles: { tab.pcoRundownSnapshotTitles },
        externalSnapshotDevices: snapshotDevices,
        linkedSourceTextForDestinationNode: { destinationNodeId, graph in
            for link in graph.links where link.isEnabled && link.kind == .patch {
                let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
                guard toId == destinationNodeId else { continue }
                let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
                if let value = GraphRuntime.resolveTextValue(nodeId: fromId, portId: link.fromPortId, tab: tab)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
            return nil
        },
        linkedSourceTextsForDestinationNode: { destinationNodeId, graph in
            for link in graph.links where link.isEnabled && link.kind == .patch {
                let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
                guard toId == destinationNodeId else { continue }
                let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
                return GraphRuntime.resolveTextValues(nodeId: fromId, portId: link.fromPortId, tab: tab)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            return []
        },
        renderVariableText: { GraphRuntime.interpolateSharedValues(in: $0) },
        renderVariableJSON: { GraphRuntime.interpolateSharedValuesInJSON($0) },
        log: { _ in }
    )


    GraphActionExecutor.execute(actionKey: key, nodeId: nodeId, graph: graph, context: ctx)
}

private func downstreamRepeaterNodeIds(graph: DashboardGraph, triggerNodeId: UUID, sourcePortId: String? = nil) -> [UUID] {
    let repeaterIds = Set(graph.moduleGroupNodeInstances
        .filter { $0.groupKey == "utility.repeater" }
        .map { $0.id }
    )

    guard !repeaterIds.isEmpty else { return [] }

    var results: [UUID] = []
    for link in graph.links where link.isEnabled {
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        guard fromId == triggerNodeId else { continue }
        if let sourcePortId, link.fromPortId != sourcePortId { continue }
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        if repeaterIds.contains(toId) {
            results.append(toId)
        }
    }
    return results
}

private func downstreamDelayNodeIds(graph: DashboardGraph, triggerNodeId: UUID, sourcePortId: String? = nil) -> [UUID] {
    let delayIds = Set(graph.moduleGroupNodeInstances
        .filter { $0.groupKey == "utility.delay" }
        .map { $0.id }
    )

    guard !delayIds.isEmpty else { return [] }

    var results: [UUID] = []
    for link in graph.links where link.isEnabled {
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        guard fromId == triggerNodeId else { continue }
        if let sourcePortId, link.fromPortId != sourcePortId { continue }
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        if delayIds.contains(toId) {
            results.append(toId)
        }
    }
    return results
}

private func actionsDownstream(ofRepeater repeaterNodeId: UUID, graph: DashboardGraph) -> [(nodeId: UUID, key: String)] {
    let actionInstances = graph.moduleGroupNodeInstances.filter { $0.groupKey.hasPrefix("action.") }
    guard !actionInstances.isEmpty else { return [] }

    var actionById: [UUID: String] = [:]
    actionById.reserveCapacity(actionInstances.count)
    for inst in actionInstances {
        actionById[inst.id] = inst.groupKey
    }

    var results: [(UUID, String)] = []
    for link in graph.links where link.isEnabled {
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        guard fromId == repeaterNodeId else { continue }
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        if let key = actionById[toId] {
            results.append((toId, key))
        }
    }
    return results
}

private func actionsDownstream(ofDelay delayNodeId: UUID, graph: DashboardGraph) -> [(nodeId: UUID, key: String)] {
    let actionInstances = graph.moduleGroupNodeInstances.filter { $0.groupKey.hasPrefix("action.") }
    guard !actionInstances.isEmpty else { return [] }

    var actionById: [UUID: String] = [:]
    actionById.reserveCapacity(actionInstances.count)
    for inst in actionInstances {
        actionById[inst.id] = inst.groupKey
    }

    var results: [(UUID, String)] = []
    for link in graph.links where link.isEnabled {
        let fromId = nodeIdFromPortId(link.fromPortId) ?? link.fromTileId
        guard fromId == delayNodeId else { continue }
        let toId = nodeIdFromPortId(link.toPortId) ?? link.toTileId
        if let key = actionById[toId] {
            results.append((toId, key))
        }
    }
    return results
}

private func runRepeaterNode(nodeId: UUID) {
    guard let graph = tab.graph else { return }

    let cfg = graph.repeaterActionConfigByNodeId[nodeId.uuidString]
        ?? DashboardGraph.RepeaterActionConfig()

    let actions = actionsDownstream(ofRepeater: nodeId, graph: graph)
    guard !actions.isEmpty else { return }

    let repeatCount = max(1, cfg.repeatCount)
    let delayMs = max(0, cfg.delayMs)
    let delaySeconds = Double(delayMs) / 1000.0

    var offset: Double = 0
    for _ in 0..<repeatCount {
        for action in actions {
            let run = { runActionNode(nodeId: action.nodeId, key: action.key) }
            if offset <= 0 {
                run()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + offset, execute: run)
            }
            offset += delaySeconds
        }
    }
}

private func runDelayNode(nodeId: UUID) {
    guard let graph = tab.graph else { return }

    let cfg = graph.delayActionConfigByNodeId[nodeId.uuidString]
        ?? DashboardGraph.DelayActionConfig()

    let actions = actionsDownstream(ofDelay: nodeId, graph: graph)
    guard !actions.isEmpty else { return }

    let delayMs = max(0, cfg.delayMs)
    let delaySeconds = Double(delayMs) / 1000.0

    for action in actions {
        let run = { runActionNode(nodeId: action.nodeId, key: action.key) }
        if delaySeconds <= 0 {
            run()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: run)
        }
    }
}
}
