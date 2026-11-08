//
//  GraphRuntime.swift
//  Relay Dashboard
//
//  Evaluates DashboardGraph links (tile-backed) into executable commands.
//  This runtime is intentionally small; it can grow as we add node types.
//

import Foundation
import SwiftUI

struct GraphTriggerPollFamilyMetric: Equatable {
    let name: String
    let configCount: Int
    let emittedCount: Int
    let duration: TimeInterval
}

struct GraphTriggerPollResult: Equatable {
    var events: [TriggerEvent]
    var familyMetrics: [GraphTriggerPollFamilyMetric]
}

enum GraphTriggerPoller {
    private static var lastTriggerFireAtByNode: [String: Date] = [:]
    private static var lastTriggerConditionByNode: [String: Bool] = [:]

    private static func canFireTrigger(nodeKey: String, now: Date, cooldownSeconds: Double) -> Bool {
        guard cooldownSeconds > 0 else { return true }
        if let last = lastTriggerFireAtByNode[nodeKey], now.timeIntervalSince(last) < cooldownSeconds {
            return false
        }
        return true
    }

    private static func markFired(nodeKey: String, now: Date) {
        lastTriggerFireAtByNode[nodeKey] = now
    }

    static func poll(graph: DashboardGraph, now: Date = Date()) -> GraphTriggerPollResult {
        var out: [TriggerEvent] = []
        var metrics: [GraphTriggerPollFamilyMetric] = []

        let timeStartedAt = CFAbsoluteTimeGetCurrent()
        let timeStartCount = out.count
        for (nodeKey, cfg) in graph.timeTriggerConfigByNodeId {
            let nodeId = UUID(uuidString: nodeKey) ?? UUID()

            let condition: Bool = {
                switch cfg.mode {
                case .interval:
                    if let last = lastTriggerFireAtByNode[nodeKey] {
                        return now.timeIntervalSince(last) >= max(0.1, cfg.intervalSeconds)
                    }
                    return true

                case .atTime:
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
                    let cur = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
                    return cur == cfg.timeOfDay
                }
            }()

            let lastCondition = lastTriggerConditionByNode[nodeKey] ?? false
            lastTriggerConditionByNode[nodeKey] = condition

            let shouldFire: Bool
            if cfg.mode == .atTime {
                shouldFire = condition && !lastCondition
            } else {
                shouldFire = condition
            }

            if shouldFire, canFireTrigger(nodeKey: nodeKey, now: now, cooldownSeconds: cfg.cooldownSeconds) {
                markFired(nodeKey: nodeKey, now: now)
                out.append(
                    TriggerEvent(
                        kind: cfg.mode == .interval ? "time.interval" : "time.atTime",
                        sourceNodeId: nodeId,
                        fields: [
                            "timeOfDay": .string(cfg.timeOfDay),
                            "intervalSeconds": .float(cfg.intervalSeconds)
                        ]
                    )
                )
            }
        }
        metrics.append(
            GraphTriggerPollFamilyMetric(
                name: "time",
                configCount: graph.timeTriggerConfigByNodeId.count,
                emittedCount: out.count - timeStartCount,
                duration: CFAbsoluteTimeGetCurrent() - timeStartedAt
            )
        )

        let shureStartedAt = CFAbsoluteTimeGetCurrent()
        let shureStartCount = out.count
        for (nodeKey, cfg) in graph.shureTriggerConfigByNodeId {
            guard let deviceId = cfg.deviceID, let ch = cfg.channelIndex else { continue }
            let nodeId = UUID(uuidString: nodeKey) ?? UUID()

            let svc = ShureWirelessService.shared(for: deviceId)
            let connected = svc.isConnected

            let batteryPct = Double(svc.standardReportBatteryPercentage(for: ch) ?? -1)
            let rfBars = Double(svc.standardReportRfBarCount(for: ch) ?? -1)
            let audio = svc.liveAudioLevel(for: ch)

            let condition: Bool = {
                switch cfg.triggerKind {
                case .batteryBelow:
                    guard batteryPct >= 0 else { return false }
                    return batteryPct < cfg.threshold
                case .rfBelow:
                    guard rfBars >= 0 else { return false }
                    return rfBars < cfg.threshold
                case .audioClip:
                    guard let a = audio else { return false }
                    return a >= cfg.threshold
                case .disconnected:
                    return !connected
                }
            }()

            let lastCondition = lastTriggerConditionByNode[nodeKey] ?? false
            lastTriggerConditionByNode[nodeKey] = condition
            let shouldEdgeFire = (cfg.triggerKind == .disconnected) ? (condition && !lastCondition) : condition

            if shouldEdgeFire, canFireTrigger(nodeKey: nodeKey, now: now, cooldownSeconds: cfg.cooldownSeconds) {
                markFired(nodeKey: nodeKey, now: now)

                var fields: [String: TriggerEventValue] = [
                    "batteryPercent": .float(batteryPct),
                    "rfBars": .float(rfBars)
                ]
                if let a = audio { fields["audio"] = .float(a) }
                fields["connected"] = .bool(connected)

                let kind: String = {
                    switch cfg.triggerKind {
                    case .batteryBelow: return "wireless.shure.batteryBelow"
                    case .rfBelow: return "wireless.shure.rfBelow"
                    case .audioClip: return "wireless.shure.audioClip"
                    case .disconnected: return "wireless.shure.disconnected"
                    }
                }()

                out.append(
                    TriggerEvent(
                        kind: kind,
                        sourceNodeId: nodeId,
                        deviceId: deviceId,
                        channelIndex: ch,
                        fields: fields
                    )
                )
            }
        }
        metrics.append(
            GraphTriggerPollFamilyMetric(
                name: "shure",
                configCount: graph.shureTriggerConfigByNodeId.count,
                emittedCount: out.count - shureStartCount,
                duration: CFAbsoluteTimeGetCurrent() - shureStartedAt
            )
        )

        let sennStartedAt = CFAbsoluteTimeGetCurrent()
        let sennStartCount = out.count
        let senn = SennheiserWirelessService.shared
        for (nodeKey, cfg) in graph.sennheiserTriggerConfigByNodeId {
            guard let deviceId = cfg.deviceID, let ch = cfg.channelIndex else { continue }
            let nodeId = UUID(uuidString: nodeKey) ?? UUID()

            let connected = (senn.connectionStateByDevice[deviceId] == .connected)
            let snap = senn.channelsByDevice[deviceId]?.first(where: { $0.channelIndex == ch })

            let batteryPct = Double(snap?.batteryPercent ?? -1)
            let rf01 = snap?.rfLevel01
            let audio01 = snap?.audioLevel01

            let condition: Bool = {
                switch cfg.triggerKind {
                case .batteryBelow:
                    guard batteryPct >= 0 else { return false }
                    return batteryPct < cfg.threshold
                case .rfBelow:
                    guard let v = rf01 else { return false }
                    return v < cfg.threshold
                case .audioClip:
                    guard let v = audio01 else { return false }
                    return v >= cfg.threshold
                case .disconnected:
                    return !connected
                }
            }()

            let lastCondition = lastTriggerConditionByNode[nodeKey] ?? false
            lastTriggerConditionByNode[nodeKey] = condition
            let shouldEdgeFire = (cfg.triggerKind == .disconnected) ? (condition && !lastCondition) : condition

            if shouldEdgeFire, canFireTrigger(nodeKey: nodeKey, now: now, cooldownSeconds: cfg.cooldownSeconds) {
                markFired(nodeKey: nodeKey, now: now)

                var fields: [String: TriggerEventValue] = [
                    "batteryPercent": .float(batteryPct),
                    "connected": .bool(connected)
                ]
                if let v = rf01 { fields["rf01"] = .float(v) }
                if let v = audio01 { fields["audio01"] = .float(v) }

                let kind: String = {
                    switch cfg.triggerKind {
                    case .batteryBelow: return "wireless.sennheiser.batteryBelow"
                    case .rfBelow: return "wireless.sennheiser.rfBelow"
                    case .audioClip: return "wireless.sennheiser.audioClip"
                    case .disconnected: return "wireless.sennheiser.disconnected"
                    }
                }()

                out.append(
                    TriggerEvent(
                        kind: kind,
                        sourceNodeId: nodeId,
                        deviceId: deviceId,
                        channelIndex: ch,
                        fields: fields
                    )
                )
            }
        }
        metrics.append(
            GraphTriggerPollFamilyMetric(
                name: "sennheiser",
                configCount: graph.sennheiserTriggerConfigByNodeId.count,
                emittedCount: out.count - sennStartCount,
                duration: CFAbsoluteTimeGetCurrent() - sennStartedAt
            )
        )

        return GraphTriggerPollResult(events: out, familyMetrics: metrics)
    }
}

/// Evaluates a graph into device-facing commands.
///
/// Design goals:
/// - Tiles remain the nodes; we read current tile state at evaluation time.
/// - Links are the only stored connections.
/// - Produce commands in a deterministic order for repeatability.
@MainActor
struct GraphRuntime {
    struct TextInterpolationCompletionCandidate: Hashable {
        let display: String
        let replacement: String
    }


    /// Polls configured trigger nodes and emits trigger events when thresholds are met.
    /// Call this from a timer (e.g. every 0.5–1.0s) while the dashboard is visible.
    static func pollTriggerEvents(graph: DashboardGraph, tab: DashboardTab, now: Date = Date()) -> [TriggerEvent] {
        GraphTriggerPoller.poll(graph: graph, now: now).events
    }
    /// Evaluates a single trigger event by routing links originating from the trigger node.
    /// This is how graph-only trigger nodes can drive console automation links.
    static func evaluateTriggerEvent(graph: DashboardGraph, tab: DashboardTab, trigger: TriggerEvent) -> [GraphCommand] {
        let enabledLinks = graph.links.filter { $0.isEnabled && $0.fromTileId == trigger.sourceNodeId }

        let ordered = enabledLinks.sorted { a, b in
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            if a.toTileId != b.toTileId { return a.toTileId.uuidString < b.toTileId.uuidString }
            return a.id.uuidString < b.id.uuidString
        }

        var commands: [GraphCommand] = []

        for link in ordered {
            switch link.kind {
            case .patch:
                // Patch links require a text value; for trigger events, use a provided field.
                if let name = triggerTextValue(trigger: trigger, desiredPortId: link.fromPortId) {
                    if let c = buildPatchCommandFromName(name: name, toPortId: link.toPortId) {
                        commands.append(c)
                    }
                }

            case .identity:
                break

            case .automation:
                // Automation links can be run even without a source tile.
                let built = buildAutomationCommandsFromTrigger(link: link, trigger: trigger, tab: tab)
                commands.append(contentsOf: built)
            }
        }

        // Also surface the event itself for any listeners.
        commands.insert(.event(trigger), at: 0)
        return commands
    }

    /// Evaluates the given graph.
    /// - Parameters:
    ///   - graph: The stored graph.
    ///   - tab: The tab that owns the tiles.
    ///   - event: What triggered evaluation.
    /// - Returns: Commands that should be executed.
    static func evaluate(graph: DashboardGraph, tab: DashboardTab, event: GraphEvent = .apply) -> [GraphCommand] {
        // Future: filter based on event (e.g. applyForConsole).
        let enabledLinks = graph.links.filter { $0.isEnabled }

        // Deterministic ordering helps debugging and prevents random batches.
        let ordered = enabledLinks.sorted { a, b in
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            if a.fromTileId != b.fromTileId { return a.fromTileId.uuidString < b.fromTileId.uuidString }
            if a.toTileId != b.toTileId { return a.toTileId.uuidString < b.toTileId.uuidString }
            return a.id.uuidString < b.id.uuidString
        }

        var commands: [GraphCommand] = []

        for link in ordered {
            switch link.kind {
            case .patch:
                if let c = buildPatchCommand(link: link, tab: tab) {
                    // Event filtering: if applyForConsole, only include matching device.
                    if case let .applyForConsole(deviceId) = event {
                        switch c {
                        case .console(let cmd):
                            switch cmd {
                            case .setChannelName(let id, _, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            case .fireSnapshot(let id, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            case .createSnapshot(let id, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            case .renameSnapshot(let id, _, _):
                                guard id == deviceId else { break }
                                commands.append(c)

                            case .createCue(let id, _, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            case .createSnippet(let id, _, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            default:
                                break
                            }
                        default:
                            break
                        }
                    } else {
                        commands.append(c)
                    }
                }

            case .identity:
                // Identity links will drive “resolved person” mapping and auto-wiring.
                // MVP: no commands.
                break

            case .automation:
                // Automation links drive snapshot create/rename, etc.
                let built = buildAutomationCommands(link: link, tab: tab)
                guard !built.isEmpty else { break }

                for c in built {
                    if case let .applyForConsole(deviceId) = event {
                        switch c {
                        case .console(let cmd):
                            switch cmd {
                            case .setChannelName(let id, _, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            case .fireSnapshot(let id, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            case .createSnapshot(let id, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            case .renameSnapshot(let id, _, _):
                                guard id == deviceId else { break }
                                commands.append(c)

                            case .createCue(let id, _, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            case .createSnippet(let id, _, _):
                                guard id == deviceId else { break }
                                commands.append(c)
                            default:
                                break
                            }
                        default:
                            break
                        }
                    } else {
                        commands.append(c)
                    }
                }
            }
        }

        return commands
    }

    // MARK: - Patch building

    /// Interprets a patch link (channel naming). Snapshot create/rename is handled via automation links.
    /// Convention (MVP):
    /// - Source ports: person.name, shure.label, sennheiser.label
    /// - Dest ports: console.<externalDeviceId>.chname.<index>
    /// Example: console.550E0B06-...-A9E7.chname.12
    private static func buildPatchCommand(link: GraphLink, tab: DashboardTab) -> GraphCommand? {
        guard let name = resolveTextValue(nodeId: link.fromTileId, portId: link.fromPortId, tab: tab) else {
            return nil
        }

        // Destination parsing
        let parts = link.toPortId.split(separator: ".")
        guard parts.count >= 4 else { return nil }
        guard parts[0] == "console" else { return nil }

        // console.<uuid>.chname.<index>
        guard let deviceId = UUID(uuidString: String(parts[1])) else { return nil }
        let commandType = parts[2]
        if commandType == "chname" {
            let idxStr = String(parts[3])
            guard let ch = Int(idxStr) else { return nil }
            return .console(.setChannelName(externalDeviceId: deviceId, channel: ch, name: name))
        }

        return nil
    }

    private static func buildPatchCommandFromName(name: String, toPortId: String) -> GraphCommand? {
        let parts = toPortId.split(separator: ".")
        guard parts.count >= 4 else { return nil }
        guard parts[0] == "console" else { return nil }
        guard let deviceId = UUID(uuidString: String(parts[1])) else { return nil }
        let commandType = parts[2]
        if commandType == "chname" {
            let idxStr = String(parts[3])
            guard let ch = Int(idxStr) else { return nil }
            return .console(.setChannelName(externalDeviceId: deviceId, channel: ch, name: name))
        }
        return nil
    }

    private static func triggerTextValue(trigger: TriggerEvent, desiredPortId: String) -> String? {
        // If a trigger event provides a text-like field, use it.
        if let v = trigger.fields["text"] {
            if case let .string(s) = v { return s }
        }
        if let v = trigger.fields["name"] {
            if case let .string(s) = v { return s }
        }

        // Fallback: use kind + device/channel for debugging.
        switch desiredPortId {
        case "person.name", "pco.itemTitle", "shure.label", "sennheiser.label":
            var s = trigger.kind
            if let did = trigger.deviceId { s += " \(did.uuidString.prefix(6))" }
            if let ch = trigger.channelIndex { s += " CH\(ch)" }
            return s
        default:
            return nil
        }
    }

    // MARK: - Automation building

    /// Interprets an automation link.
    /// Convention (MVP):
    /// - Dest ports:
    ///     console.<externalDeviceId>.snapshot.create.<index>
    ///     console.<externalDeviceId>.snapshot.rename.<index>
    ///     console.<externalDeviceId>.snapshot.upsert.<index>   (create + rename; name from source)
    /// - Source ports for rename/upsert: any text port (e.g. person.name, shure.label, pco.itemTitle)
    private static func buildAutomationCommands(link: GraphLink, tab: DashboardTab) -> [GraphCommand] {
        let parts = link.toPortId.split(separator: ".")
        guard parts.count >= 5 else { return [] }
        guard parts[0] == "console" else { return [] }

        guard let deviceId = UUID(uuidString: String(parts[1])) else { return [] }
        guard parts[2] == "snapshot" else { return [] }

        let action = String(parts[3])
        let indexStr = String(parts[4])
        guard let index = Int(indexStr) else { return [] }

        switch action {
        case "create":
            return [.console(.createSnapshot(externalDeviceId: deviceId, index: index))]

        case "rename":
            guard let name = resolveTextValue(nodeId: link.fromTileId, portId: link.fromPortId, tab: tab),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            return [.console(.renameSnapshot(externalDeviceId: deviceId, index: index, name: name))]

        case "upsert":
            guard let name = resolveTextValue(nodeId: link.fromTileId, portId: link.fromPortId, tab: tab),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            return [
                .console(.createSnapshot(externalDeviceId: deviceId, index: index)),
                .console(.renameSnapshot(externalDeviceId: deviceId, index: index, name: name))
            ]

        default:
            return []
        }
    }

    private static func buildAutomationCommandsFromTrigger(link: GraphLink, trigger: TriggerEvent, tab: DashboardTab) -> [GraphCommand] {
        let parts = link.toPortId.split(separator: ".")
        guard parts.count >= 5 else { return [] }
        guard parts[0] == "console" else { return [] }

        guard let deviceId = UUID(uuidString: String(parts[1])) else { return [] }
        guard parts[2] == "snapshot" else { return [] }

        let action = String(parts[3])
        let indexStr = String(parts[4])
        guard let index = Int(indexStr) else { return [] }

        switch action {
        case "create":
            return [.console(.createSnapshot(externalDeviceId: deviceId, index: index))]

        case "rename":
            guard let name = triggerTextValue(trigger: trigger, desiredPortId: link.fromPortId),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            return [.console(.renameSnapshot(externalDeviceId: deviceId, index: index, name: name))]

        case "upsert":
            guard let name = triggerTextValue(trigger: trigger, desiredPortId: link.fromPortId),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            return [
                .console(.createSnapshot(externalDeviceId: deviceId, index: index)),
                .console(.renameSnapshot(externalDeviceId: deviceId, index: index, name: name))
            ]

        default:
            return []
        }
    }

    // MARK: - Value resolution

    static func resolveTextValue(nodeId: UUID, portId: String, tab: DashboardTab) -> String? {
        resolveTextValues(nodeId: nodeId, portId: portId, tab: tab).first
    }

    static func resolveTextValues(nodeId: UUID, portId: String, tab: DashboardTab) -> [String] {
        if let tile = tab.tiles.first(where: { $0.id == nodeId }) {
            if let value = resolveTileTextValue(tile: tile, portId: portId, tab: tab) {
                return [value]
            }
            return []
        }

        guard let instance = tab.graph?.moduleGroupNodeInstances.first(where: { $0.id == nodeId }) else {
            return []
        }

        switch instance.groupKey {
        case "source.roster":
            let cfg = tab.graph?.rosterSourceConfigByNodeId[nodeId.uuidString] ?? DashboardGraph.RosterSourceConfig()
            if cfg.mode == .wholeColumn {
                guard let column = tab.rosterColumn(id: cfg.selectedColumnID) else { return [] }
                return tab.rosterRows.compactMap { row in
                    let value = row.value(for: column.id).trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
            }
            if let value = tab.rosterValue(rowID: cfg.selectedRowID, columnID: cfg.selectedColumnID) {
                return [value]
            }
            return []

        case "source.consoleImport":
            let cfg = tab.graph?.consoleLabelSourceConfigByNodeId[nodeId.uuidString] ?? DashboardGraph.ConsoleLabelSourceConfig()
            return resolveConsoleChannelNames(deviceId: cfg.deviceId, mode: cfg.mode, channelIndex: cfg.channelIndex)

        case "source.wirelessImport":
            let cfg = tab.graph?.wirelessLabelSourceConfigByNodeId[nodeId.uuidString] ?? DashboardGraph.WirelessLabelSourceConfig()
            return resolveWirelessChannelNames(
                deviceKind: cfg.deviceKind,
                mode: cfg.mode,
                deviceId: cfg.deviceId,
                channelIndex: cfg.channelIndex
            )

        case "source.staticLabel":
            let cfg = tab.graph?.staticLabelSourceConfigByNodeId[nodeId.uuidString] ?? DashboardGraph.StaticLabelSourceConfig()
            if cfg.mode == .labelList {
                return interpolateSharedValues(in: cfg.label)
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            let text = interpolateSharedValues(in: cfg.label).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [text]

        case "utility.variable":
            guard isGraphVariablesFeatureEnabled else { return [] }
            guard let cfg = tab.graph?.variableNodeConfigByNodeId[nodeId.uuidString] else { return [] }
            if let linkedValue = resolvedLinkedVariableInputValue(nodeId: nodeId, config: cfg, tab: tab) {
                return linkedValue.isEmpty ? [] : [linkedValue]
            }
            if let sharedValue = resolvedSharedVariableValue(cfg) {
                return sharedValue.isEmpty ? [] : [sharedValue]
            }
            if let stored = resolvedVariableStoredValue(cfg), !stored.isEmpty {
                return [stored]
            }
            let manual = resolvedVariableManualValue(cfg)
            return manual.isEmpty ? [] : [manual]

        default:
            return []
        }
    }

    static func variableValuesByName(tab: DashboardTab) -> [String: String] {
        var values = universalVariableValuesByName(tab: tab)
        guard isGraphVariablesFeatureEnabled, let graph = tab.graph else { return values }
        for config in graph.variableNodeConfigByNodeId.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let normalized = normalizeGraphVariableName(config.name)
            guard !normalized.isEmpty else { continue }
            let resolved = resolvedVariableCurrentValue(nodeId: config.id, tab: tab)
            values[normalized] = resolved
            values["graph:\(normalized)"] = resolved
        }
        return values
    }

    static func universalVariableValuesByName(tab: DashboardTab) -> [String: String] {
        var values = SharedValueStore.shared.snapshot.values.reduce(into: [String: String]()) { partialResult, value in
            guard !value.displayValue.isEmpty else { return }
            partialResult[value.name] = value.displayValue
            partialResult["shared:\(value.name)"] = value.displayValue
        }
        for entry in LinkedDeviceVariableStore.shared.entries {
            guard let payload = entry.value.payload else { continue }
            values[entry.tokenName] = payload.displayValue
        }
        if let groupID = tab.syncGroupID, !tab.syncIsOwner {
            for (name, value) in SyncedTabVariableStore.shared.values(for: groupID) {
                values[name] = value
            }
        }
        for person in LinkedComputerPersonVariableStore.shared.variables.sorted(by: { $0.sourceID < $1.sourceID }) {
            let legacyName = normalizeSharedValueName("person_\(person.name)")
            if values[legacyName] == nil { values[legacyName] = person.name }
            values[person.variableName] = person.name
            values["person:\(person.variableName)"] = person.name
        }
        return values
    }

    static func resolveTextInterpolationToken(_ token: String, tab: DashboardTab) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let namedDeviceValue = resolveNamedDeviceTextInterpolationToken(trimmed) {
            return namedDeviceValue
        }

        if let consoleValue = resolveConsoleTextInterpolationToken(trimmed) {
            return consoleValue
        }

        if let wirelessValue = resolveWirelessTextInterpolationToken(trimmed) {
            return wirelessValue
        }

        if let graphVariable = variableValuesByName(tab: tab)[normalizeGraphVariableName(trimmed)] {
            return graphVariable
        }

        return SharedValueResolver().resolveText(token: trimmed)
    }

    static func textInterpolationCompletionCandidates(query rawQuery: String) -> [TextInterpolationCompletionCandidate] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return namedDeviceTextInterpolationCompletionCandidates(query: query)
        }

        let normalized = query.lowercased()
        if !normalized.contains(":") {
            return namedDeviceTextInterpolationCompletionCandidates(query: query)
        }

        if normalized.hasPrefix("console") {
            return consoleTextInterpolationCompletionCandidates(query: query)
        }

        if normalized.hasPrefix("mic") || normalized.hasPrefix("wireless") {
            return wirelessTextInterpolationCompletionCandidates(query: query)
        }

        if let namedDeviceCandidates = namedDeviceChannelCompletionCandidates(query: query),
           !namedDeviceCandidates.isEmpty {
            return namedDeviceCandidates
        }

        return []
    }

    private static func resolveNamedDeviceTextInterpolationToken(_ token: String) -> String? {
        let components = token
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        guard components.count >= 2 else { return nil }
        let deviceName = components.dropLast().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        let channelFragment = components.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !deviceName.isEmpty,
              let channelIndex = parseConsoleTextInterpolationChannel(channelFragment) else {
            return nil
        }

        if let console = consoleTextInterpolationDevices().first(where: {
            $0.device.name.caseInsensitiveCompare(deviceName) == .orderedSame
        })?.device {
            return resolveConsoleChannelName(device: console, channelIndex: channelIndex)
        }

        // DiGiCo non-input tokens use the form "{ConsoleName › TypeName:N}" (e.g. "{FOH Q338 › Aux Outputs:1}").
        // The device name contains " › " — split it, find the parent console, then resolve from digicoDiscoveredChannels.
        if let chevronRange = deviceName.range(of: " › ") {
            let consoleName = String(deviceName[..<chevronRange.lowerBound])
            let typeSuffix  = String(deviceName[chevronRange.upperBound...])
            if let console = consoleTextInterpolationDevices().first(where: {
                $0.device.name.caseInsensitiveCompare(consoleName) == .orderedSame
            })?.device {
                // Map "Aux Outputs" → .auxOutput, "Group Outputs" → .groupOutput, etc.
                // The token suffix is "\(channelType.displayName)s" per completionDevices().
                let channelType = DashboardGraph.DiGiCoChannelType.allCases.first {
                    "\($0.displayName)s".caseInsensitiveCompare(typeSuffix) == .orderedSame
                }
                if let channelType {
                    if let ch = console.digicoDiscoveredChannels.first(where: {
                        $0.channelType == channelType && $0.index == channelIndex
                    }) {
                        let name = ch.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { return name }
                    }
                }
            }
        }

        if let wireless = wirelessTextInterpolationDevices().first(where: {
            $0.device.name.caseInsensitiveCompare(deviceName) == .orderedSame
        })?.device {
            return resolveWirelessChannelName(device: wireless, channelIndex: channelIndex)
        }

        return nil
    }

    static func resolvedVariableCurrentValue(nodeId: UUID, tab: DashboardTab) -> String {
        guard isGraphVariablesFeatureEnabled else { return "" }
        guard let cfg = tab.graph?.variableNodeConfigByNodeId[nodeId.uuidString] else { return "" }
        if let linkedValue = resolvedLinkedVariableInputValue(nodeId: nodeId, config: cfg, tab: tab) {
            return linkedValue
        }
        if let sharedValue = resolvedSharedVariableValue(cfg) { return sharedValue }
        if let stored = resolvedVariableStoredValue(cfg) {
            return stored
        }
        return resolvedVariableManualValue(cfg)
    }

    static func interpolateSharedValues(in text: String) -> String {
        let resolver = SharedValueResolver()
        return SharedValueTextInterpolation.render(text) { resolver.resolveText(token: $0) }
    }

    static func interpolateSharedValuesInJSON(_ text: String) -> String {
        let resolver = SharedValueResolver()
        return SharedValueTextInterpolation.renderJSON(text) { resolver.resolveText(token: $0) }
    }

    private static func resolvedSharedVariableValue(_ config: DashboardGraph.VariableNodeConfig) -> String? {
        let resolver = SharedValueResolver()
        return resolvedSharedVariableValue(config) { resolver.resolveText(token: $0) }
    }

    static func resolvedSharedVariableValue(
        _ config: DashboardGraph.VariableNodeConfig,
        resolve: (String) -> String?
    ) -> String? {
        guard let token = config.sharedValueToken else { return nil }
        let resolved = resolve(token) ?? ""
        return coerceVariableValue(resolved, as: config.valueType)
    }

    private static func resolvedLinkedVariableInputValue(
        nodeId: UUID,
        config: DashboardGraph.VariableNodeConfig,
        tab: DashboardTab
    ) -> String? {
        guard let graph = tab.graph else { return nil }
        guard let inbound = graph.links.first(where: { link in
            guard link.isEnabled && link.kind == .patch else { return false }
            let toId = graph.nodeIdByPortId[link.toPortId] ?? link.toTileId
            return toId == nodeId
        }) else {
            return nil
        }

        let fromId = graph.nodeIdByPortId[inbound.fromPortId] ?? inbound.fromTileId
        let values = resolveTextValues(nodeId: fromId, portId: inbound.fromPortId, tab: tab)
        guard let first = values.first else { return nil }
        let coerced = coerceVariableValue(first, as: config.valueType)
        if config.valueType == .text {
            return first.isEmpty ? "" : coerced
        }
        return coerced.isEmpty ? nil : coerced
    }

    private static func resolvedVariableStoredValue(_ config: DashboardGraph.VariableNodeConfig) -> String? {
        switch config.valueType {
        case .text:
            return config.currentTextValue
        case .number:
            guard let value = config.currentNumberValue else { return nil }
            return formatIntegerVariableNumber(value)
        case .float:
            guard let value = config.currentNumberValue else { return nil }
            return formatVariableNumber(value)
        case .boolean:
            guard let value = config.currentBooleanValue else { return nil }
            return value ? "true" : "false"
        }
    }

    static func updateVariableNodeValue(
        graph: inout DashboardGraph,
        nodeId: UUID,
        payloadText: String?,
        payloadNumber: Double?,
        payloadBoolean: Bool?,
        sourceNodeId: UUID?
    ) {
        guard isGraphVariablesFeatureEnabled else { return }
        guard var cfg = graph.variableNodeConfigByNodeId[nodeId.uuidString] else { return }
        switch cfg.valueType {
        case .text:
            cfg.currentTextValue = payloadText ?? ""
        case .number:
            cfg.currentNumberValue = payloadNumber.map { $0.rounded(.towardZero) }
        case .float:
            cfg.currentNumberValue = payloadNumber
        case .boolean:
            cfg.currentBooleanValue = payloadBoolean
        }
        cfg.lastUpdatedAt = Date()
        cfg.sourceNodeId = sourceNodeId
        graph.variableNodeConfigByNodeId[nodeId.uuidString] = cfg
    }

    static func applySetVariableAction(
        _ action: DashboardGraph.SetVariableActionConfig,
        to variable: inout DashboardGraph.VariableNodeConfig
    ) {
        switch variable.valueType {
        case .text:
            variable.currentTextValue = action.textValue
        case .number:
            variable.currentNumberValue = action.numberValue.rounded(.towardZero)
        case .float:
            variable.currentNumberValue = action.numberValue
        case .boolean:
            variable.currentBooleanValue = action.booleanValue
        }
        variable.lastUpdatedAt = Date()
    }

    private static func resolvedVariableManualValue(_ config: DashboardGraph.VariableNodeConfig) -> String {
        switch config.valueType {
        case .text:
            return interpolateSharedValues(in: config.manualTextValue)
        case .number:
            return formatIntegerVariableNumber(config.manualNumberValue)
        case .float:
            return formatVariableNumber(config.manualNumberValue)
        case .boolean:
            return config.manualBooleanValue ? "true" : "false"
        }
    }

    private static func coerceVariableValue(_ raw: String, as type: GraphVariableValueType) -> String {
        switch type {
        case .text:
            return raw
        case .number:
            guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "" }
            return formatIntegerVariableNumber(value)
        case .float:
            guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "" }
            return formatVariableNumber(value)
        case .boolean:
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "true", "1", "yes", "on":
                return "true"
            case "false", "0", "no", "off":
                return "false"
            default:
                return ""
            }
        }
    }

    private static func formatIntegerVariableNumber(_ value: Double) -> String {
        let rounded = value.rounded(.towardZero)
        guard rounded.isFinite && rounded >= Double(Int.min) && rounded < Double(Int.max) else {
            return String(rounded)
        }
        return String(Int(rounded))
    }

    private static func formatVariableNumber(_ value: Double) -> String {
        if value.isFinite && value.rounded() == value && value >= Double(Int.min) && value < Double(Int.max) {
            return String(Int(value))
        }
        return String(value)
    }

    private static func resolveTileTextValue(tile: DashboardTileModel, portId: String, tab: DashboardTab) -> String? {
        switch portId {
        case "person.name":
            if case let .person(personModel) = tile.kind {
                let resolved = tab.resolvedPersonModel(personModel)
                return resolved.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil

        case "shure.label":
            // Shure label prefers cached channel name if selection present.
            if let sel = tile.shureChannelSelection,
               let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == sel.deviceID }) {
                // Try cached channel display label (includes name + device + CH)
                return ExternalDevicesStore.shared.shureChannelDisplayLabel(device: device, channelIndex: sel.channelIndex)
            }
            return nil

        case "sennheiser.label":
            // Placeholder; Sennheiser selection is stored per-module config right now.
            return nil

        default:
            return nil
        }
    }

    private static func resolveConsoleChannelNames(
        deviceId: UUID?,
        mode: DashboardGraph.ConsoleLabelSourceConfig.Mode,
        channelIndex: Int
    ) -> [String] {
        guard let deviceId,
              let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceId }) else {
            return []
        }

        if !device.digicoInputChannels.isEmpty {
            if mode == .allChannels {
                return device.digicoInputChannels.compactMap { channel in
                    let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? nil : name
                }
            }
            if let digico = device.digicoInputChannels.first(where: { $0.channel == channelIndex }) {
                let name = digico.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? [] : [name]
            }
        }

        let synced = syncedConsoleChannelNamesByChannel(deviceId: device.id)
        if mode == .allChannels {
            return synced.keys.sorted().compactMap { index in
                let name = synced[index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? nil : name
            }
        }

        if let syncedName = synced[channelIndex] {
            let name = syncedName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? [] : [name]
        }

        return []
    }

    private static func resolveConsoleTextInterpolationToken(_ token: String) -> String? {
        let components = token
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        guard components.count >= 2 else { return nil }
        guard components[0].caseInsensitiveCompare("console") == .orderedSame else { return nil }

        let consoleDevices = consoleTextInterpolationDevices()
        guard !consoleDevices.isEmpty else { return nil }

        let device: ExternalDeviceConfig?
        let channelFragment: String

        switch components.count {
        case 2:
            guard consoleDevices.count == 1 else { return nil }
            device = consoleDevices[0].device
            channelFragment = components[1]
        default:
            let alias = normalizeConsoleTextInterpolationAlias(components[1])
            guard !alias.isEmpty else { return nil }
            device = consoleDevices.first(where: { $0.alias == alias })?.device
            channelFragment = components.last ?? ""
        }

        guard let device,
              let channelIndex = parseConsoleTextInterpolationChannel(channelFragment) else {
            return nil
        }

        return resolveConsoleChannelName(device: device, channelIndex: channelIndex)
    }

    private static func resolveWirelessTextInterpolationToken(_ token: String) -> String? {
        let components = token
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        guard components.count >= 2 else { return nil }
        let tokenKind = components[0].lowercased()
        guard tokenKind == "mic" || tokenKind == "wireless" else { return nil }

        let wirelessDevices = wirelessTextInterpolationDevices()
        guard !wirelessDevices.isEmpty else { return nil }

        let device: ExternalDeviceConfig?
        let channelFragment: String

        switch components.count {
        case 2:
            guard wirelessDevices.count == 1 else { return nil }
            device = wirelessDevices[0].device
            channelFragment = components[1]
        default:
            let alias = normalizeConsoleTextInterpolationAlias(components[1])
            guard !alias.isEmpty else { return nil }
            device = wirelessDevices.first(where: { $0.alias == alias })?.device
            channelFragment = components.last ?? ""
        }

        guard let device,
              let channelIndex = parseConsoleTextInterpolationChannel(channelFragment) else {
            return nil
        }

        return resolveWirelessChannelName(device: device, channelIndex: channelIndex)
    }

    private static func resolveWirelessChannelNames(
        deviceKind: DashboardGraph.WirelessLabelSourceConfig.DeviceKind,
        mode: DashboardGraph.WirelessLabelSourceConfig.Mode,
        deviceId: UUID?,
        channelIndex: Int
    ) -> [String] {
        guard let deviceId,
              let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceId }) else {
            return []
        }

        switch deviceKind {
        case .shure:
            let channels: [Int]
            if mode == .allChannels {
                channels = Array(1...max(1, device.effectiveShureChannelCount))
            } else {
                channels = [channelIndex]
            }
            return channels.compactMap { currentChannel in
                if let cached = ExternalDevicesStore.shared.cachedShureChannelName(deviceID: deviceId, channelIndex: currentChannel) {
                    let name = cached.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { return name }
                }
                if let stored = device.shureChannelNames[currentChannel] {
                    let name = stored.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { return name }
                }
                if currentChannel == 1, let name = device.psmChannel1Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    return name
                }
                if currentChannel == 2, let name = device.psmChannel2Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    return name
                }
                return nil
            }

        case .sennheiser:
            let count = max(1, device.sennheiserNetworkModel?.channelCount ?? 1)
            let channels = mode == .allChannels ? Array(1...count) : [channelIndex]
            return channels.compactMap { currentChannel in
                if let cached = ExternalDevicesStore.shared.cachedSennheiserChannelName(deviceID: deviceId, channelIndex: currentChannel) {
                    let name = cached.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? nil : name
                }
                return nil
            }
        }
    }

    private static func syncedConsoleChannelNamesByChannel(deviceId: UUID) -> [Int: String] {
        if !Thread.isMainThread {
            var result: [Int: String] = [:]
            syncOnMain {
                result = syncedConsoleChannelNamesByChannelMainThread(deviceId: deviceId)
            }
            return result
        }

        return syncedConsoleChannelNamesByChannelMainThread(deviceId: deviceId)
    }

    private static func syncedConsoleChannelNamesByChannelMainThread(deviceId: UUID) -> [Int: String] {
        let defaultsKeys = [
            "prodlink.x32sync.map.\(deviceId.uuidString)",
            "prodlink.ah.sync.map.\(deviceId.uuidString)",
            "prodlink.dlive.sync.map.\(deviceId.uuidString)"
        ]
        for key in defaultsKeys {
            if let decoded = persistedConsoleSyncMap(forKey: key), !decoded.isEmpty {
                return decoded
            }
        }
        return [:]
    }

    private static func persistedConsoleSyncMap(forKey key: String) -> [Int: String]? {
        let defaults = UserDefaults.standard

        if let direct = defaults.object(forKey: key) as? [Int: String], !direct.isEmpty {
            return direct
        }

        if let stringKeyed = defaults.object(forKey: key) as? [String: String] {
            let normalized = normalizePersistedConsoleSyncMap(stringKeyed)
            if !normalized.isEmpty {
                return normalized
            }
        }

        guard let data = defaults.object(forKey: key) as? Data, !data.isEmpty else {
            return nil
        }

        if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let normalized = normalizePersistedConsoleSyncMap(decoded)
            if !normalized.isEmpty {
                return normalized
            }
        }

        if let decoded = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let normalized = normalizePersistedConsoleSyncMap(decoded)
            if !normalized.isEmpty {
                return normalized
            }
        }

        return nil
    }

    private static func normalizePersistedConsoleSyncMap(_ raw: [String: String]) -> [Int: String] {
        raw.reduce(into: [Int: String]()) { partialResult, item in
            guard let channel = Int(item.key) else { return }
            let name = item.value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            partialResult[channel] = name
        }
    }

    private static func normalizePersistedConsoleSyncMap(_ raw: [String: Any]) -> [Int: String] {
        raw.reduce(into: [Int: String]()) { partialResult, item in
            guard let channel = Int(item.key) else { return }

            if let value = item.value as? String {
                let name = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                partialResult[channel] = name
                return
            }

            if let number = item.value as? NSNumber {
                let name = number.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                partialResult[channel] = name
            }
        }
    }

    private static func resolveConsoleChannelName(device: ExternalDeviceConfig, channelIndex: Int) -> String? {
        if let digico = device.digicoInputChannels.first(where: { $0.channel == channelIndex }) {
            let name = digico.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
        }

        // Non-input channels (OSC sync only) — input channels above take priority
        if let discovered = device.digicoDiscoveredChannels.first(where: { $0.index == channelIndex }) {
            let name = discovered.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }

        if let syncedName = syncedConsoleChannelNamesByChannel(deviceId: device.id)[channelIndex] {
            let name = syncedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
        }

        return nil
    }

    private static func resolveWirelessChannelName(device: ExternalDeviceConfig, channelIndex: Int) -> String? {
        if !Thread.isMainThread {
            var result: String?
            syncOnMain {
                result = resolveWirelessChannelNameMainThread(device: device, channelIndex: channelIndex)
            }
            return result
        }

        return resolveWirelessChannelNameMainThread(device: device, channelIndex: channelIndex)
    }

    private static func resolveWirelessChannelNameMainThread(device: ExternalDeviceConfig, channelIndex: Int) -> String? {
        switch device.kind {
        case .shureWireless:
            if let cached = ExternalDevicesStore.shared.cachedShureChannelName(deviceID: device.id, channelIndex: channelIndex) {
                let name = cached.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return name
                }
            }

            if let stored = device.shureChannelNames[channelIndex] {
                let name = stored.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return name
                }
            }

            if channelIndex == 1,
               let name = device.psmChannel1Name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }

            if channelIndex == 2,
               let name = device.psmChannel2Name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }

            return nil

        case .sennheiserWireless:
            if let cached = ExternalDevicesStore.shared.cachedSennheiserChannelName(deviceID: device.id, channelIndex: channelIndex) {
                let name = cached.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return name
                }
            }

            return nil

        default:
            return nil
        }
    }

    private static func consoleTextInterpolationDevices() -> [(alias: String, device: ExternalDeviceConfig)] {
        if !Thread.isMainThread {
            var result: [(alias: String, device: ExternalDeviceConfig)] = []
            syncOnMain {
                result = consoleTextInterpolationDevicesMainThread()
            }
            return result
        }

        return consoleTextInterpolationDevicesMainThread()
    }

    private static func consoleTextInterpolationDevicesMainThread() -> [(alias: String, device: ExternalDeviceConfig)] {
        let devices = ExternalDevicesStore.shared.devices
            .filter { $0.kind == .audioConsole }
            .filter { device in
                if !device.digicoInputChannels.isEmpty {
                    return true
                }

                let modelId = (device.consoleModelIdentifier ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if modelId == "Behringer_X32" || modelId == "Midas_M32" {
                    return true
                }
                if modelId.hasPrefix("AH_Qu") {
                    return true
                }
                if allenHeathChannelLimit(modelIdentifier: modelId) != nil {
                    return true
                }
                return false
            }
            .sorted {
                if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                    return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        var usedAliases: [String: Int] = [:]
        return devices.map { device in
            let normalizedName = normalizeConsoleTextInterpolationAlias(device.name)
            let baseAlias = normalizedName.isEmpty ? "console" : normalizedName
            let nextCount = (usedAliases[baseAlias] ?? 0) + 1
            usedAliases[baseAlias] = nextCount
            let alias = nextCount == 1 ? baseAlias : "\(baseAlias)-\(nextCount)"
            return (alias, device)
        }
    }

    private static func wirelessTextInterpolationDevices() -> [(alias: String, device: ExternalDeviceConfig)] {
        if !Thread.isMainThread {
            var result: [(alias: String, device: ExternalDeviceConfig)] = []
            syncOnMain {
                result = wirelessTextInterpolationDevicesMainThread()
            }
            return result
        }

        return wirelessTextInterpolationDevicesMainThread()
    }

    private static func wirelessTextInterpolationDevicesMainThread() -> [(alias: String, device: ExternalDeviceConfig)] {
        let devices = ExternalDevicesStore.shared.devices
            .filter { $0.kind == .shureWireless || $0.kind == .sennheiserWireless }
            .filter { device in
                switch device.kind {
                case .shureWireless:
                    return hasAnyWirelessChannelName(device: device)
                case .sennheiserWireless:
                    return hasAnyWirelessChannelName(device: device)
                default:
                    return false
                }
            }
            .sorted {
                if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                    return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        var usedAliases: [String: Int] = [:]
        return devices.map { device in
            let normalizedName = normalizeConsoleTextInterpolationAlias(device.name)
            let baseAlias = normalizedName.isEmpty ? "mic" : normalizedName
            let nextCount = (usedAliases[baseAlias] ?? 0) + 1
            usedAliases[baseAlias] = nextCount
            let alias = nextCount == 1 ? baseAlias : "\(baseAlias)-\(nextCount)"
            return (alias, device)
        }
    }

    private static func hasAnyWirelessChannelName(device: ExternalDeviceConfig) -> Bool {
        if !Thread.isMainThread {
            var result = false
            syncOnMain {
                result = hasAnyWirelessChannelNameMainThread(device: device)
            }
            return result
        }

        return hasAnyWirelessChannelNameMainThread(device: device)
    }

    private static func hasAnyWirelessChannelNameMainThread(device: ExternalDeviceConfig) -> Bool {
        switch device.kind {
        case .shureWireless:
            if !ExternalDevicesStore.shared.shureChannelNameCache[device.id, default: [:]].isEmpty {
                return true
            }
            if device.shureChannelNames.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return true
            }
            if let name = device.psmChannel1Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return true
            }
            if let name = device.psmChannel2Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return true
            }
            return false

        case .sennheiserWireless:
            return !ExternalDevicesStore.shared.sennheiserChannelNameCache[device.id, default: [:]].isEmpty

        default:
            return false
        }
    }

    private static func consoleTextInterpolationCompletionCandidates(query: String) -> [TextInterpolationCompletionCandidate] {
        let devices = consoleTextInterpolationDevices()
        guard !devices.isEmpty else { return [] }

        let suffix = String(query.dropFirst("console:".count))
        if devices.count == 1 {
            return channelCompletionCandidates(
                prefix: "console",
                querySuffix: suffix,
                alias: nil,
                device: devices[0].device,
                nameResolver: resolveConsoleChannelName(device:channelIndex:)
            )
        }

        if let aliasChannelSplit = splitAliasAndChannelQuery(suffix) {
            guard let device = devices.first(where: { $0.alias == aliasChannelSplit.alias })?.device else { return [] }
            return channelCompletionCandidates(
                prefix: "console",
                querySuffix: aliasChannelSplit.channelQuery,
                alias: aliasChannelSplit.alias,
                device: device,
                nameResolver: resolveConsoleChannelName(device:channelIndex:)
            )
        }

        let normalizedSuffix = normalizeConsoleTextInterpolationAlias(suffix)
        return devices
            .filter { normalizedSuffix.isEmpty || $0.alias.hasPrefix(normalizedSuffix) }
            .map {
                TextInterpolationCompletionCandidate(
                    display: "\($0.alias) — \($0.device.name)",
                    replacement: "{console:\($0.alias):"
                )
            }
    }

    private static func wirelessTextInterpolationCompletionCandidates(query: String) -> [TextInterpolationCompletionCandidate] {
        let prefix = query.lowercased().hasPrefix("wireless:") ? "wireless" : "mic"
        let prefixLength = prefix.count + 1
        let devices = wirelessTextInterpolationDevices()
        guard !devices.isEmpty else { return [] }

        let suffix = String(query.dropFirst(prefixLength))
        if devices.count == 1 {
            return channelCompletionCandidates(
                prefix: prefix,
                querySuffix: suffix,
                alias: nil,
                device: devices[0].device,
                nameResolver: resolveWirelessChannelName(device:channelIndex:)
            )
        }

        if let aliasChannelSplit = splitAliasAndChannelQuery(suffix) {
            guard let device = devices.first(where: { $0.alias == aliasChannelSplit.alias })?.device else { return [] }
            return channelCompletionCandidates(
                prefix: prefix,
                querySuffix: aliasChannelSplit.channelQuery,
                alias: aliasChannelSplit.alias,
                device: device,
                nameResolver: resolveWirelessChannelName(device:channelIndex:)
            )
        }

        let normalizedSuffix = normalizeConsoleTextInterpolationAlias(suffix)
        return devices
            .filter { normalizedSuffix.isEmpty || $0.alias.hasPrefix(normalizedSuffix) }
            .map {
                TextInterpolationCompletionCandidate(
                    display: "\($0.alias) — \($0.device.name)",
                    replacement: "{\(prefix):\($0.alias):"
                )
            }
    }

    private static func namedDeviceTextInterpolationCompletionCandidates(query: String) -> [TextInterpolationCompletionCandidate] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (consoleTextInterpolationDevices() + wirelessTextInterpolationDevices())
            .sorted {
                if $0.device.kind == $1.device.kind {
                    return $0.device.name.localizedCaseInsensitiveCompare($1.device.name) == .orderedAscending
                }
                if $0.device.kind == .audioConsole {
                    return true
                }
                if $1.device.kind == .audioConsole {
                    return false
                }
                return $0.device.name.localizedCaseInsensitiveCompare($1.device.name) == .orderedAscending
            }
            .filter {
                normalizedQuery.isEmpty || $0.device.name.lowercased().hasPrefix(normalizedQuery)
            }
            .map { item in
                let kindLabel = item.device.kind == .audioConsole ? "Console" : "Mic"
                return TextInterpolationCompletionCandidate(
                    display: "\(item.device.name) — \(kindLabel)",
                    replacement: "{\(item.device.name):"
                )
            }
    }

    private static func namedDeviceChannelCompletionCandidates(query: String) -> [TextInterpolationCompletionCandidate]? {
        guard let separatorIndex = query.lastIndex(of: ":") else { return nil }
        let rawDeviceName = String(query[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let channelQuery = String(query[query.index(after: separatorIndex)...])
        guard !rawDeviceName.isEmpty else { return nil }

        if let console = consoleTextInterpolationDevices().first(where: {
            $0.device.name.caseInsensitiveCompare(rawDeviceName) == .orderedSame
        })?.device {
            return namedChannelCompletionCandidates(
                deviceName: console.name,
                channelQuery: channelQuery,
                device: console,
                nameResolver: resolveConsoleChannelName(device:channelIndex:)
            )
        }

        if let wireless = wirelessTextInterpolationDevices().first(where: {
            $0.device.name.caseInsensitiveCompare(rawDeviceName) == .orderedSame
        })?.device {
            return namedChannelCompletionCandidates(
                deviceName: wireless.name,
                channelQuery: channelQuery,
                device: wireless,
                nameResolver: resolveWirelessChannelName(device:channelIndex:)
            )
        }

        return nil
    }

    private static func namedChannelCompletionCandidates(
        deviceName: String,
        channelQuery: String,
        device: ExternalDeviceConfig,
        nameResolver: @escaping (ExternalDeviceConfig, Int) -> String?
    ) -> [TextInterpolationCompletionCandidate] {
        let trimmedQuery = channelQuery.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let requestedChannel = parseConsoleTextInterpolationChannel(trimmedQuery)
        let nameByChannel = availableChannelNamesByChannel(device: device, nameResolver: nameResolver)

        return nameByChannel
            .sorted { $0.key < $1.key }
            .compactMap { channel, rawName in
                let name = rawName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                let channelString = String(channel)
                if let requestedChannel, !channelString.hasPrefix(String(requestedChannel)) {
                    return nil
                }
                if requestedChannel == nil, !trimmedQuery.isEmpty, !channelString.hasPrefix(trimmedQuery) {
                    return nil
                }

                return TextInterpolationCompletionCandidate(
                    display: "#\(channel) — \(name)",
                    replacement: "{\(deviceName):\(channel)}"
                )
            }
    }

    private static func channelCompletionCandidates(
        prefix: String,
        querySuffix: String,
        alias: String?,
        device: ExternalDeviceConfig,
        nameResolver: @escaping (ExternalDeviceConfig, Int) -> String?
    ) -> [TextInterpolationCompletionCandidate] {
        let trimmedSuffix = querySuffix.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let requestedChannel = parseConsoleTextInterpolationChannel(trimmedSuffix)
        let nameByChannel = availableChannelNamesByChannel(device: device, nameResolver: nameResolver)

        let channels: [(Int, String)] = nameByChannel
            .sorted { $0.key < $1.key }
            .compactMap { channel, name in
                let trimmedName = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return nil }
                return (channel, trimmedName)
            }

        return channels.compactMap { channel, name in
            let channelString = String(channel)
            if let requestedChannel, !channelString.hasPrefix(String(requestedChannel)) {
                return nil
            }
            if requestedChannel == nil, !trimmedSuffix.isEmpty, !channelString.hasPrefix(trimmedSuffix) {
                return nil
            }

            let tokenCore: String
            if let alias, !alias.isEmpty {
                tokenCore = "\(prefix):\(alias):\(channel)"
            } else {
                tokenCore = "\(prefix):\(channel)"
            }

            return TextInterpolationCompletionCandidate(
                display: "#\(channel) — \(name)",
                replacement: "{\(tokenCore)}"
            )
        }
    }

    private static func availableChannelNamesByChannel(
        device: ExternalDeviceConfig,
        nameResolver: @escaping (ExternalDeviceConfig, Int) -> String?
    ) -> [Int: String] {
        if !Thread.isMainThread {
            var result: [Int: String] = [:]
            syncOnMain {
                result = availableChannelNamesByChannelMainThread(device: device, nameResolver: nameResolver)
            }
            return result
        }

        return availableChannelNamesByChannelMainThread(device: device, nameResolver: nameResolver)
    }

    private static func availableChannelNamesByChannelMainThread(
        device: ExternalDeviceConfig,
        nameResolver: @escaping (ExternalDeviceConfig, Int) -> String?
    ) -> [Int: String] {
        switch device.kind {
        case .audioConsole:
            if !device.digicoInputChannels.isEmpty {
                var namesByChannel = device.digicoInputChannels.reduce(into: [Int: String]()) { partialResult, channel in
                    let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        partialResult[channel.channel] = name
                    }
                }
                // Also include non-input discovered channels; input channels take priority on collision
                if !device.digicoDiscoveredChannels.isEmpty {
                    var discovered: [Int: String] = [:]
                    for ch in device.digicoDiscoveredChannels {
                        let name = ch.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            discovered[ch.index] = name
                        }
                    }
                    namesByChannel = discovered.merging(namesByChannel) { _, existing in existing }
                }
                return namesByChannel
            }

            let syncedNames = syncedConsoleChannelNamesByChannel(deviceId: device.id)
            if !syncedNames.isEmpty {
                return syncedNames.reduce(into: [Int: String]()) { partialResult, item in
                    let name = item.value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !name.isEmpty {
                        partialResult[item.key] = name
                    }
                }
            }

            let modelId = (device.consoleModelIdentifier ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if modelId == "Behringer_X32" || modelId == "Midas_M32" {
                return Dictionary(uniqueKeysWithValues: (1...32).map { ($0, "CH \($0)") })
            }
            if modelId.hasPrefix("AH_Qu") {
                return Dictionary(uniqueKeysWithValues: (1...32).map { ($0, "CH \($0)") })
            }
            if let limit = allenHeathChannelLimit(modelIdentifier: modelId) {
                return Dictionary(uniqueKeysWithValues: (1...limit).map { ($0, "CH \($0)") })
            }

            return [:]

        case .shureWireless:
            var result = ExternalDevicesStore.shared.shureChannelNameCache[device.id, default: [:]]
            for (channel, name) in device.shureChannelNames {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result[channel] = trimmed
                }
            }
            if let name = device.psmChannel1Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                result[1] = name
            }
            if let name = device.psmChannel2Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                result[2] = name
            }
            return result

        case .sennheiserWireless:
            return ExternalDevicesStore.shared.sennheiserChannelNameCache[device.id, default: [:]]

        default:
            return [:]
        }
    }

    private static func allenHeathChannelLimit(modelIdentifier: String) -> Int? {
        guard let model = AudioConsoleModel.from(identifier: modelIdentifier) else { return nil }
        switch model {
        case .allenHeathDlive:
            return 128
        case .allenHeathAvantis, .allenHeathSq:
            return 64
        default:
            return nil
        }
    }

    private static func syncOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            work()
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func splitAliasAndChannelQuery(_ suffix: String) -> (alias: String, channelQuery: String)? {
        guard let lastSeparator = suffix.lastIndex(of: ":") else { return nil }
        let alias = normalizeConsoleTextInterpolationAlias(String(suffix[..<lastSeparator]))
        let channelQuery = String(suffix[suffix.index(after: lastSeparator)...])
        guard !alias.isEmpty else { return nil }
        return (alias, channelQuery)
    }

    private static func normalizeConsoleTextInterpolationAlias(_ raw: String) -> String {
        let loweredScalars = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
        var result = ""
        var previousWasSeparator = false

        for scalar in loweredScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator, !result.isEmpty {
                result.append("-")
                previousWasSeparator = true
            }
        }

        while result.last == "-" {
            result.removeLast()
        }

        return result
    }

    private static func parseConsoleTextInterpolationChannel(_ raw: String) -> Int? {
        let digits = raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        guard !digits.isEmpty, let channel = Int(String(String.UnicodeScalarView(digits))) else {
            return nil
        }
        return channel
    }
}
