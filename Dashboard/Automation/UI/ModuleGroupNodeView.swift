//
//  ModuleGroupNodeView.swift
//  Relay
//
//  Created by David Bullard on 1/7/26.
//
import SwiftUI
import Foundation
import CryptoKit
#if os(macOS)
import AppKit
#endif


// MARK: - Module group node view

struct ModuleGroupNodeView: View {
    let nodeId: UUID
    let group: GraphDashboardView.ModuleGroup
    let tab: DashboardTab
    let consoleDevices: [ExternalDeviceConfig]
    let shureDevices: [ExternalDeviceConfig]
    let sennheiserDevices: [ExternalDeviceConfig]
    let peopleTeamOptions: [String]
    @Binding var selectedPeopleTeams: Set<String>
    @Binding var customPeople: [DashboardGraph.CustomPeopleEntry]

    let isSelected: Bool
    @Binding var peopleSourceMode: String
    @Binding var graph: DashboardGraph?
    let performGraphEdit: ((_ actionName: String, _ mutation: @escaping () -> Void) -> Void)?
    @State private var newCustomPosition: String = ""
    @State private var newCustomName: String = ""
    @State private var isItemsCollapsed: Bool = false
    @State private var isTeamsCollapsed: Bool = true
    @State private var variableInsertionTarget = SharedValueBindingInsertionTarget()
    init(
        nodeId: UUID,
        group: GraphDashboardView.ModuleGroup,
        tab: DashboardTab,
        consoleDevices: [ExternalDeviceConfig] = [],
        shureDevices: [ExternalDeviceConfig] = [],
        sennheiserDevices: [ExternalDeviceConfig] = [],
        peopleTeamOptions: [String],
        selectedPeopleTeams: Binding<Set<String>>,
        customPeople: Binding<[DashboardGraph.CustomPeopleEntry]>,
        isSelected: Bool = false,
        peopleSourceMode: Binding<String> = .constant("pco"),
        graph: Binding<DashboardGraph?> = .constant(nil),
        performGraphEdit: ((_ actionName: String, _ mutation: @escaping () -> Void) -> Void)? = nil
    ) {
        self.nodeId = nodeId
        self.group = group
        self.tab = tab
        self.consoleDevices = consoleDevices
        self.shureDevices = shureDevices
        self.sennheiserDevices = sennheiserDevices
        self.peopleTeamOptions = peopleTeamOptions
        self.isSelected = isSelected
        self._selectedPeopleTeams = selectedPeopleTeams
        self._customPeople = customPeople
        self._peopleSourceMode = peopleSourceMode
        self._graph = graph
        self.performGraphEdit = performGraphEdit
        // Restore persisted collapse state from the graph layout model.
        self._isItemsCollapsed = State(initialValue: graph.wrappedValue?.tileLayouts[nodeId]?.collapsed ?? false)
    }
    private func applyGraphEdit(actionName: String = "Edit Node", _ mutation: @escaping () -> Void) {
        if let performGraphEdit {
            performGraphEdit(actionName, mutation)
        } else {
            mutation()
        }
    }
    private func isTeamSelected(_ team: String, allTeams: [String]) -> Bool {
        if !selectedPeopleTeams.isEmpty { return selectedPeopleTeams.contains(team) }
        let defaults = tabDefaultTeams
        if defaults.isEmpty { return true }
        return defaults.contains(team)
    }

    private func setTeamSelected(_ team: String, isOn: Bool, allTeams: [String]) {
        // When inheriting (empty), expand to the effective selection before modifying.
        if selectedPeopleTeams.isEmpty {
            let defaults = Set(tabDefaultTeams)
            selectedPeopleTeams = defaults.isEmpty ? Set(allTeams) : defaults
        }

        if isOn {
            selectedPeopleTeams.insert(team)
        } else {
            selectedPeopleTeams.remove(team)
        }

        // If every team is now selected and there's no tab default, collapse back to the “all” sentinel.
        let allSet = Set(allTeams)
        if !allSet.isEmpty, allSet.isSubset(of: selectedPeopleTeams), tabDefaultTeams.isEmpty {
            selectedPeopleTeams.removeAll()
        }
    }

    private func teamToggleBinding(team: String, allTeams: [String]) -> Binding<Bool> {
        Binding<Bool>(
            get: { isTeamSelected(team, allTeams: allTeams) },
            set: { setTeamSelected(team, isOn: $0, allTeams: allTeams) }
        )
    }

    private var isManualPeople: Bool {
        (group.key == "moduleGroup.person" && !group.isCanvasBacked)
    }

    private var isTranscriptionGroup: Bool {
        group.key == "moduleGroup.transcription"
    }

    private var isRosterSource: Bool {
        group.key == "source.roster"
    }

    private var isConsoleLabelSource: Bool {
        group.key == "source.consoleImport"
    }

    private var isWirelessLabelSource: Bool {
        group.key == "source.wirelessImport"
    }

    private var isStaticLabelSource: Bool {
        group.key == "source.staticLabel"
    }

    private var isVariableNode: Bool {
        isGraphVariablesFeatureEnabled && group.key == "utility.variable"
    }

    private var transcriptionWordTriggerCfg: Binding<DashboardGraph.WordTriggerConfig> {
        let nodeKey = nodeId.uuidString
        return Binding<DashboardGraph.WordTriggerConfig>(
            get: { graph?.wordTriggerConfigByNodeId[nodeKey] ?? DashboardGraph.WordTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    if graph == nil { graph = DashboardGraph() }
                    graph?.wordTriggerConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var rosterSourceConfig: Binding<DashboardGraph.RosterSourceConfig> {
        let nodeKey = nodeId.uuidString
        return Binding(
            get: { graph?.rosterSourceConfigByNodeId[nodeKey] ?? DashboardGraph.RosterSourceConfig() },
            set: { newValue in
                applyGraphEdit {
                    if graph == nil { graph = DashboardGraph() }
                    graph?.rosterSourceConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var consoleLabelSourceConfig: Binding<DashboardGraph.ConsoleLabelSourceConfig> {
        let nodeKey = nodeId.uuidString
        return Binding(
            get: { graph?.consoleLabelSourceConfigByNodeId[nodeKey] ?? DashboardGraph.ConsoleLabelSourceConfig() },
            set: { newValue in
                applyGraphEdit {
                    if graph == nil { graph = DashboardGraph() }
                    graph?.consoleLabelSourceConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var wirelessLabelSourceConfig: Binding<DashboardGraph.WirelessLabelSourceConfig> {
        let nodeKey = nodeId.uuidString
        return Binding(
            get: { graph?.wirelessLabelSourceConfigByNodeId[nodeKey] ?? DashboardGraph.WirelessLabelSourceConfig() },
            set: { newValue in
                applyGraphEdit {
                    if graph == nil { graph = DashboardGraph() }
                    graph?.wirelessLabelSourceConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var staticLabelSourceConfig: Binding<DashboardGraph.StaticLabelSourceConfig> {
        let nodeKey = nodeId.uuidString
        return Binding(
            get: { graph?.staticLabelSourceConfigByNodeId[nodeKey] ?? DashboardGraph.StaticLabelSourceConfig() },
            set: { newValue in
                applyGraphEdit {
                    if graph == nil { graph = DashboardGraph() }
                    graph?.staticLabelSourceConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var isCurrentTimeSource: Bool {
        group.key == "source.currentTime"
    }

    private var variableNodeConfig: Binding<DashboardGraph.VariableNodeConfig> {
        let nodeKey = nodeId.uuidString
        return Binding(
            get: {
                graph?.variableNodeConfigByNodeId[nodeKey]
                    ?? DashboardGraph.VariableNodeConfig(id: nodeId)
            },
            set: { newValue in
                applyGraphEdit {
                    if graph == nil { graph = DashboardGraph() }
                    graph?.variableNodeConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    /// For the canvas-backed People node, only show teams that actually exist in the current tile snapshot.
    private var canvasTeams: [String] {
        guard group.key == "moduleGroup.person", group.isCanvasBacked else { return [] }
        let teams = group.members.compactMap { $0.teamName?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(teams)).sorted()
    }

    private var teamOptionsForUI: [String] {
        if group.key == "moduleGroup.person", group.isCanvasBacked {
            return canvasTeams
        }
        return peopleTeamOptions
    }

    private var shouldShowTeamChecklist: Bool {
        group.key == "moduleGroup.person" &&
        !teamOptionsForUI.isEmpty &&
        !(isManualPeople && peopleSourceMode == "custom")
    }

    private var countText: String {
        if isVariableNode {
            return "1 value"
        }
        if isCurrentTimeSource {
            return "1 value"
        }
        if isRosterSource || isConsoleLabelSource || isWirelessLabelSource || isStaticLabelSource || isVariableNode {
            let count = group.members.count
            return "\(count) value\(count == 1 ? "" : "s")"
        }
        let count = (isManualPeople && peopleSourceMode == "custom") ? customPeople.count : group.members.count
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    private var itemSectionTitle: String {
        if isManualPeople && peopleSourceMode == "custom" {
            return "People"
        }
        if group.key == "moduleGroup.person" {
            return "People"
        }
        return "Items"
    }

    private var itemSectionSummary: String {
        countText
    }

    @ViewBuilder
    private func collapsibleItemsSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .opacity(0.85)
                .rotationEffect(.degrees(isItemsCollapsed ? -90 : 0))
                .animation(.easeInOut(duration: 0.18), value: isItemsCollapsed)
                .accessibilityLabel(isItemsCollapsed ? "Expand \(itemSectionTitle)" : "Collapse \(itemSectionTitle)")

            Text(itemSectionTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Text(itemSectionSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let next = !isItemsCollapsed
            withAnimation(.easeInOut(duration: 0.18)) {
                isItemsCollapsed = next
            }
            // Persist collapsed state so it survives mode switches.
            // Explicit write-back through the @Binding is required — chained optional assignment
            // (graph?.tileLayouts[nodeId]?.x = val) does not reliably propagate through @Binding.
            if var g = graph {
                if g.tileLayouts[nodeId] != nil {
                    g.tileLayouts[nodeId]!.collapsed = next
                } else {
                    g.tileLayouts[nodeId] = TileGraphLayout(collapsed: next)
                }
                graph = g
            }
        }

        if !isItemsCollapsed {
            content()
        }
    }

    private var rosterPreviewText: String {
        let cfg = rosterSourceConfig.wrappedValue
        if cfg.mode == .wholeColumn {
            let values = group.members.map(\.title)
            if values.isEmpty { return "Select a roster column." }
            return values.prefix(3).joined(separator: "\n")
        }
        if let value = tab.rosterValue(rowID: cfg.selectedRowID, columnID: cfg.selectedColumnID) {
            return value
        }
        return "Select a roster row and column."
    }

    private var consolePreviewText: String {
        let cfg = consoleLabelSourceConfig.wrappedValue
        guard let deviceId = cfg.deviceId,
              let device = consoleDevices.first(where: { $0.id == deviceId }) else {
            return "Select a console and channel."
        }
        if cfg.mode == .allChannels {
            let values = group.members.map(\.title)
            if values.isEmpty { return "No synced channel names found." }
            return values.prefix(3).joined(separator: "\n")
        }
        return resolvedConsoleChannelName(device: device, channelIndex: cfg.channelIndex) ?? "No synced channel name for CH \(cfg.channelIndex)."
    }

    private var wirelessPreviewText: String {
        let cfg = wirelessLabelSourceConfig.wrappedValue
        if cfg.mode == .allChannels {
            let values = group.members.map(\.title)
            if values.isEmpty { return "No cached channel names found." }
            return values.prefix(3).joined(separator: "\n")
        }
        switch cfg.deviceKind {
        case .shure:
            guard let deviceId = cfg.deviceId,
                  let device = shureDevices.first(where: { $0.id == deviceId }) else {
                return "Select a wireless device and channel."
            }
            return resolvedShureChannelName(device: device, channelIndex: cfg.channelIndex) ?? "No cached channel name for CH \(cfg.channelIndex)."
        case .sennheiser:
            guard let deviceId = cfg.deviceId,
                  let device = sennheiserDevices.first(where: { $0.id == deviceId }) else {
                return "Select a wireless device and channel."
            }
            return resolvedSennheiserChannelName(device: device, channelIndex: cfg.channelIndex) ?? "No cached channel name for CH \(cfg.channelIndex)."
        }
    }

    private var staticPreviewText: String {
        if staticLabelSourceConfig.wrappedValue.mode == .labelList {
            let values = group.members.map(\.title)
            if values.isEmpty { return "Enter one label per line." }
            return values.prefix(3).joined(separator: "\n")
        }
        let text = staticLabelSourceConfig.wrappedValue.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Enter a label." : text
    }

    private var hasLinkedVariableInput: Bool {
        guard isVariableNode, let graph else { return false }
        return graph.links.contains { link in
            guard link.isEnabled && link.kind == .patch else { return false }
            let resolved = graph.nodeIdByPortId[link.toPortId] ?? link.toTileId
            return resolved == nodeId
        }
    }

    private var variableResolvedValuePreview: String {
        GraphRuntime.resolvedVariableCurrentValue(nodeId: nodeId, tab: tab)
    }

    private var hasDuplicateVariableName: Bool {
        guard isVariableNode, let graph else { return false }
        let normalized = normalizeGraphVariableName(variableNodeConfig.wrappedValue.name)
        guard !normalized.isEmpty else { return false }
        return graph.variableNodeConfigByNodeId.contains { key, value in
            key != nodeId.uuidString && normalizeGraphVariableName(value.name) == normalized
        }
    }

    private var tabDefaultTeams: [String] {
        let raw = tab.teamName ?? ""
        let teams = raw.components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "all" }
        return teams.sorted()
    }

    private var teamFilterSummary: String {
        if !selectedPeopleTeams.isEmpty {
            let sorted = selectedPeopleTeams.sorted()
            if sorted.count == 1 { return sorted[0] }
            if sorted.count <= 2 { return sorted.joined(separator: ", ") }
            return "\(sorted.count) teams"
        }
        let defaults = tabDefaultTeams
        if defaults.isEmpty { return "All" }
        if defaults.count == 1 { return defaults[0] }
        if defaults.count <= 2 { return defaults.joined(separator: ", ") }
        return "\(defaults.count) teams (tab)"
    }

    // MARK: - Node kind (Source vs Trigger)

    private enum NodeKind {
        case source
        case trigger
        case utility

        var labelText: String {
            switch self {
            case .source: return "SOURCE"
            case .trigger: return "TRIGGER"
            case .utility: return "UTILITY"
            }
        }

        var iconOverride: String? {
            switch self {
            case .source:
                return nil
            case .trigger:
                return "bolt.circle.fill"
            case .utility:
                return nil
            }
        }
    }

    private var nodeKind: NodeKind {
        if isVariableNode { return .utility }
        if group.key == "utility.merge" { return .utility }
        if group.key == "utility.toggle" { return .utility }
        if group.key == "utility.counter" { return .utility }
        if group.key == "utility.sequence" { return .utility }
        if group.key == "utility.latch" { return .utility }
        // source.currentTime is a source node, not a trigger.
        if isCurrentTimeSource { return .source }
        // Only auto-classify non-console nodes here.
        // Source nodes: People + PCO + OSC Send.
        // Trigger nodes: Time + Wireless + OSC Receive.
        if group.key.contains("time") { return .trigger }
        if group.key.contains("shure") { return .trigger }
        if group.key.contains("sennheiser") { return .trigger }
        if group.key.contains("oscReceive") { return .trigger }
        if group.key.contains("midiReceive") { return .trigger }
        if group.key.contains("transcription") { return .trigger }
        if group.key.contains("wordTrigger") { return .trigger }
        if group.key.contains("dbThreshold") { return .trigger }
        if group.key.contains("manualTrigger") { return .trigger }
        if group.key.contains("button") { return .trigger }
        if group.key.contains("pcoItemChanged") { return .trigger }
        // Default everything else in this view to source for now.
        return .source
    }

    private var nodeCategory: GraphNodeCategory {
        switch nodeKind {
        case .source:
            return .sources
        case .trigger:
            return .triggers
        case .utility:
            return .utility
        }
    }

    private var nodeTintColor: Color {
        nodeCategory.tintColor
    }

    private var nodeTintBackground: some View {
        // Slight tint by node kind for quick scanning.
        ZStack {
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(Color.white.opacity(GraphNodeStyleTokens.elevatedFillOpacity))
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(nodeTintColor)
                .blendMode(.screen)
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(Color.white.opacity(GraphNodeStyleTokens.highlightFillOpacity))
        }
    }

    private var nodeTintBorder: some View {
        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
            .stroke(nodeCategory.borderColor, lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
    }

    var body: some View {
        Group {
            if nodeKind == .trigger {
                TriggerGraphNodeView(
                    nodeId: nodeId,
                    group: group,
                    graph: $graph,
                    isSelected: isSelected,
                    performGraphEdit: performGraphEdit
                )
            } else {
                sourceBody
            }
        }
    }

    // MARK: - Source node body (existing UI)

    private var sourceBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: nodeKind.iconOverride ?? iconName(for: group.key))
                    .imageScale(.medium)
                    .opacity(0.9)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.title)
                            .font(.headline)
                            .lineLimit(1)

                        // Indicator: this node is derived from the canvas (tile/module snapshot).
                        if group.isCanvasBacked {
                            Image(systemName: "square.grid.2x2")
                                .imageScale(.small)
                                .opacity(0.75)
                                .accessibilityLabel("Canvas-backed node")
                        }

                        Text(nodeKind.labelText)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(nodeCategory.badgeColor)
                            )
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(nodeKind.labelText.capitalized + " node")

                        Spacer(minLength: 0)
                    }

                    Text(countText)
                        .font(.caption)
                        .opacity(0.7)
                        .lineLimit(1)
                }

                Spacer()
            }

            // Manual People node: choose whether this node is driven by PCO or custom entries.
            if isManualPeople {
                Picker("", selection: $peopleSourceMode) {
                    Text("PCO").tag("pco")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
            }

            if isRosterSource {
                Divider().opacity(0.25)
                rosterSourceSettings
            }

            if isConsoleLabelSource {
                Divider().opacity(0.25)
                consoleLabelSourceSettings
            }

            if isWirelessLabelSource {
                Divider().opacity(0.25)
                wirelessLabelSourceSettings
            }

            if isStaticLabelSource {
                Divider().opacity(0.25)
                staticLabelSourceSettings
            }

            if group.key == "source.currentTime" {
                Divider().opacity(0.25)
                currentTimeSourceSettings
            }

            if isVariableNode {
                Divider().opacity(0.25)
                variableNodeSettings
            }

            if group.key == "utility.merge" {
                Divider().opacity(0.25)
                Text("Fires whenever any linked trigger fires.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            if group.key == "utility.toggle" {
                Divider().opacity(0.25)
                toggleNodeSettings
            }

            if group.key == "utility.counter" {
                Divider().opacity(0.25)
                counterNodeSettings
            }

            if group.key == "utility.sequence" {
                Divider().opacity(0.25)
                sequenceNodeSettings
            }

            if group.key == "utility.latch" {
                Divider().opacity(0.25)
                latchNodeSettings
            }

            // Member preview
            let isNewUtilityNode = group.key == "utility.merge" || group.key == "utility.toggle"
                || group.key == "utility.counter" || group.key == "utility.sequence"
                || group.key == "utility.latch"
            if isVariableNode {
                sourcePreview(text: variableResolvedValuePreview.isEmpty ? "Empty value" : variableResolvedValuePreview)
            } else if isCurrentTimeSource {
                // Settings view already shows the current value; no separate preview needed.
            } else if isNewUtilityNode {
                // No member preview for utility nodes.
            } else if isRosterSource || isConsoleLabelSource || isWirelessLabelSource || isStaticLabelSource {
                sourcePreview(text: isRosterSource ? rosterPreviewText : isConsoleLabelSource ? consolePreviewText : isWirelessLabelSource ? wirelessPreviewText : staticPreviewText)
            } else if isManualPeople && peopleSourceMode == "custom" {
                // Custom mode: show only custom preview (hide PCO-derived list)
                if customPeople.isEmpty {
                    Text("No custom people yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    collapsibleItemsSection {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(customPeople) { entry in
                                Text("\(entry.position) — \(entry.name)")
                                    .font(.subheadline)
                                    .opacity(0.85)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } else {
                // Default: show combined list (PCO + any custom that were merged into group.members)
                collapsibleItemsSection {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group.members) { m in
                            Text(m.title)
                                .font(.subheadline)
                                .opacity(0.85)
                                .lineLimit(1)
                    }
                }
                }

                if group.key == "moduleGroup.person", group.members.isEmpty {
                    Text("Using Planning Center assignments (no person tiles).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // People node: Team filter — compact collapsible row
            if shouldShowTeamChecklist {
                Divider().opacity(0.25)

                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .opacity(0.85)
                        .rotationEffect(.degrees(isTeamsCollapsed ? -90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isTeamsCollapsed)
                        .accessibilityLabel(isTeamsCollapsed ? "Expand Teams" : "Collapse Teams")

                    Text("Teams")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !selectedPeopleTeams.isEmpty {
                        Button("Reset") { selectedPeopleTeams.removeAll() }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }

                    Spacer()

                    Text(teamFilterSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isTeamsCollapsed.toggle()
                    }
                }

                if !isTeamsCollapsed {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(teamOptionsForUI.prefix(120), id: \.self) { team in
                                Toggle(isOn: teamToggleBinding(team: team, allTeams: teamOptionsForUI)) {
                                    Text(team)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                #if os(macOS)
                                .toggleStyle(.checkbox)
                                #endif
                            }

                            if teamOptionsForUI.count > 120 {
                                Text("Showing first 120 teams.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            if isTranscriptionGroup {
                Divider().opacity(0.25)
                transcriptionTriggerSettings
            }

            // Manual People node: Custom editor (only shown in Custom tab)
            if isManualPeople && peopleSourceMode == "custom" {
                Divider().opacity(0.25)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("Position", text: $newCustomPosition)
                            .textFieldStyle(.roundedBorder)

                        TextField("Name", text: $newCustomName)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            let pos = newCustomPosition.trimmingCharacters(in: .whitespacesAndNewlines)
                            let name = newCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !pos.isEmpty, !name.isEmpty else { return }

                            let entry = DashboardGraph.CustomPeopleEntry(position: pos, name: name)
                            customPeople = customPeople + [entry]
                            newCustomPosition = ""
                            newCustomName = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .imageScale(.medium)
                                .opacity(0.9)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add custom person")
                    }

                    if !customPeople.isEmpty {
                        ForEach(customPeople) { entry in
                            HStack(spacing: 8) {
                                Text(entry.position)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 120, alignment: .leading)

                                Text(entry.name)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Button(role: .destructive) {
                                    customPeople = customPeople.filter { $0.id != entry.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .imageScale(.small)
                                        .opacity(0.85)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(nodeTintBackground)
        .overlay(nodeTintBorder)
    }

    private var transcriptionTriggerSettings: some View {
        let cfg = transcriptionWordTriggerCfg
        let rules = cfg.wrappedValue.rules

        return VStack(alignment: .leading, spacing: 10) {
            Text("Trigger Words")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(rules) { rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Phrase", text: Binding(
                            get: { rule.phrase },
                            set: { newValue in
                                updateTranscriptionRule(rule.id) { $0.phrase = newValue }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button {
                            removeTranscriptionRule(rule.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("Match", selection: Binding(
                        get: { rule.matchMode },
                        set: { newValue in
                            updateTranscriptionRule(rule.id) { $0.matchMode = newValue }
                        }
                    )) {
                        Text("Contains").tag(DashboardGraph.WordTriggerRule.MatchMode.contains)
                        Text("Whole word").tag(DashboardGraph.WordTriggerRule.MatchMode.wholeWord)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Final only", isOn: Binding(
                        get: { rule.finalOnly },
                        set: { newValue in
                            updateTranscriptionRule(rule.id) { $0.finalOnly = newValue }
                        }
                    ))


                    HStack(spacing: 10) {
                        Text("Cooldown")
                            .font(.caption)
                            .opacity(0.8)
                        TextField("Seconds", value: Binding(
                            get: { rule.cooldownSeconds },
                            set: { newValue in
                                updateTranscriptionRule(rule.id) { $0.cooldownSeconds = newValue }
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                        Text("sec")
                            .font(.caption)
                            .opacity(0.8)
                    }

                    let linkedSources = linkedTranscriptionSources()
                    if !linkedSources.isEmpty {
                        Text("Sources")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ForEach(linkedSources) { source in
                            Toggle(source.displayName, isOn: Binding(
                                get: { rule.sourceIds.isEmpty ? true : rule.sourceIds.contains(source.id) },
                                set: { isOn in
                                    updateTranscriptionRule(rule.id) { draft in
                                        var set = Set(draft.sourceIds)
                                        if isOn {
                                            set.insert(source.id)
                                        } else {
                                            set.remove(source.id)
                                        }
                                        draft.sourceIds = Array(set)
                                    }
                                }
                            ))
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                        .fill(Color.white.opacity(GraphNodeStyleTokens.subtleFillOpacity))
                )
            }

            Button {
                var v = cfg.wrappedValue
                var rule = DashboardGraph.WordTriggerRule()
                // Make new transcription rules fire on in-progress text by default.
                rule.finalOnly = false
                v.rules.append(rule)
                cfg.wrappedValue = v
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.plain)
        }
    }

    private var rosterSourceSettings: some View {
        let cfg = rosterSourceConfig
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: Binding(
                get: { cfg.wrappedValue.mode },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.mode = newValue
                    cfg.wrappedValue = value
                }
            )) {
                Text("Single").tag(DashboardGraph.RosterSourceConfig.Mode.singleValue)
                Text("Whole Column").tag(DashboardGraph.RosterSourceConfig.Mode.wholeColumn)
            }
            .pickerStyle(.segmented)

            Picker("Column", selection: Binding<String?>(
                get: { cfg.wrappedValue.selectedColumnID },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.selectedColumnID = newValue
                    cfg.wrappedValue = value
                }
            )) {
                Text("Select column").tag(String?.none)
                ForEach(tab.rosterColumns) { column in
                    Text(column.title).tag(Optional(column.id.uuidString))
                }
            }
            .pickerStyle(.menu)

            if cfg.wrappedValue.mode == .singleValue {
                Picker("Row", selection: Binding<UUID?>(
                    get: { cfg.wrappedValue.selectedRowID },
                    set: { newValue in
                        var value = cfg.wrappedValue
                        value.selectedRowID = newValue
                        cfg.wrappedValue = value
                    }
                )) {
                    Text("Select row").tag(UUID?.none)
                    ForEach(Array(tab.rosterRows.enumerated()), id: \.element.id) { index, row in
                        Text(rosterRowLabel(row: row, index: index)).tag(Optional(row.id))
                    }
                }
                .pickerStyle(.menu)
            }

            if tab.rosterColumns.isEmpty || tab.rosterRows.isEmpty {
                Text("Add roster columns and rows in Rosters before using this source.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var consoleLabelSourceSettings: some View {
        let cfg = consoleLabelSourceConfig
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: Binding(
                get: { cfg.wrappedValue.mode },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.mode = newValue
                    cfg.wrappedValue = value
                }
            )) {
                Text("Single").tag(DashboardGraph.ConsoleLabelSourceConfig.Mode.singleChannel)
                Text("All Channels").tag(DashboardGraph.ConsoleLabelSourceConfig.Mode.allChannels)
            }
            .pickerStyle(.segmented)

            Picker("Console", selection: Binding<UUID?>(
                get: { cfg.wrappedValue.deviceId },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.deviceId = newValue
                    cfg.wrappedValue = value
                }
            )) {
                Text("Select console").tag(UUID?.none)
                ForEach(consoleDevices, id: \.id) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .pickerStyle(.menu)

            if cfg.wrappedValue.mode == .singleChannel {
                Picker("Channel", selection: Binding<Int>(
                    get: { max(1, cfg.wrappedValue.channelIndex) },
                    set: { newValue in
                        var value = cfg.wrappedValue
                        value.channelIndex = max(1, newValue)
                        cfg.wrappedValue = value
                    }
                )) {
                    ForEach(consoleChannelOptions(device: consoleDevices.first(where: { $0.id == cfg.wrappedValue.deviceId })), id: \.channel) { option in
                        Text(option.label).tag(option.channel)
                    }
                }
                .pickerStyle(.menu)
            }

            if consoleDevices.isEmpty {
                Text("No consoles are available.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var wirelessLabelSourceSettings: some View {
        let cfg = wirelessLabelSourceConfig
        let devices = cfg.wrappedValue.deviceKind == .shure ? shureDevices : sennheiserDevices
        let channelCount = max(1, selectedWirelessChannelCount(config: cfg.wrappedValue))
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: Binding(
                get: { cfg.wrappedValue.mode },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.mode = newValue
                    cfg.wrappedValue = value
                }
            )) {
                Text("Single").tag(DashboardGraph.WirelessLabelSourceConfig.Mode.singleChannel)
                Text("All Channels").tag(DashboardGraph.WirelessLabelSourceConfig.Mode.allChannels)
            }
            .pickerStyle(.segmented)

            Picker("Type", selection: Binding(
                get: { cfg.wrappedValue.deviceKind },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.deviceKind = newValue
                    value.deviceId = nil
                    value.channelIndex = 1
                    cfg.wrappedValue = value
                }
            )) {
                Text("Shure").tag(DashboardGraph.WirelessLabelSourceConfig.DeviceKind.shure)
                Text("Sennheiser").tag(DashboardGraph.WirelessLabelSourceConfig.DeviceKind.sennheiser)
            }
            .pickerStyle(.segmented)

            Picker("Device", selection: Binding<UUID?>(
                get: { cfg.wrappedValue.deviceId },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.deviceId = newValue
                    value.channelIndex = 1
                    cfg.wrappedValue = value
                }
            )) {
                Text("Select device").tag(UUID?.none)
                ForEach(devices, id: \.id) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .pickerStyle(.menu)

            if cfg.wrappedValue.mode == .singleChannel {
                Picker("Channel", selection: Binding<Int>(
                    get: { max(1, min(channelCount, cfg.wrappedValue.channelIndex)) },
                    set: { newValue in
                        var value = cfg.wrappedValue
                        value.channelIndex = max(1, min(channelCount, newValue))
                        cfg.wrappedValue = value
                    }
                )) {
                    ForEach(1...channelCount, id: \.self) { index in
                        Text("CH \(index)").tag(index)
                    }
                }
                .pickerStyle(.menu)
            }

            if devices.isEmpty {
                Text("No devices are available for the selected wireless type.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var staticLabelSourceSettings: some View {
        let cfg = staticLabelSourceConfig
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: Binding(
                get: { cfg.wrappedValue.mode },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.mode = newValue
                    cfg.wrappedValue = value
                }
            )) {
                Text("Single").tag(DashboardGraph.StaticLabelSourceConfig.Mode.singleValue)
                Text("List").tag(DashboardGraph.StaticLabelSourceConfig.Mode.labelList)
            }
            .pickerStyle(.segmented)

            if cfg.wrappedValue.mode == .labelList {
                AutomationVariableTokenField(title: "Labels", text: Binding(
                    get: { cfg.wrappedValue.label },
                    set: { newValue in
                        var value = cfg.wrappedValue
                        value.label = newValue
                        cfg.wrappedValue = value
                    }
                ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab), multiline: true)
                .frame(minHeight: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(GraphNodeStyleTokens.secondaryBorderOpacity), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
                )
            } else {
                AutomationVariableTokenField(title: "Label", text: Binding(
                    get: { cfg.wrappedValue.label },
                    set: { newValue in
                        var value = cfg.wrappedValue
                        value.label = newValue
                        cfg.wrappedValue = value
                    }
                ), variableValues: GraphRuntime.universalVariableValuesByName(tab: tab))
            }
        }
    }

    private var currentTimeSourceSettings: some View {
        let nodeKey = nodeId.uuidString
        let cfg = Binding<DashboardGraph.CurrentTimeSourceConfig>(
            get: { graph?.currentTimeSourceConfigByNodeId[nodeKey]
                ?? DashboardGraph.CurrentTimeSourceConfig(id: nodeId) },
            set: { graph?.currentTimeSourceConfigByNodeId[nodeKey] = $0 }
        )
        let currentValue = graph?.variableNodeConfigByNodeId[nodeKey]?.currentTextValue ?? "–"
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Format", selection: Binding(
                get: { cfg.wrappedValue.format },
                set: { var v = cfg.wrappedValue; v.format = $0; cfg.wrappedValue = v }
            )) {
                ForEach(DashboardGraph.CurrentTimeSourceConfig.Format.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.menu)
            Text("Current value: \(currentValue)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var variableNodeSettings: some View {
        let cfg = variableNodeConfig
        let normalizedName = normalizeGraphVariableName(cfg.wrappedValue.name)
        let isEmptyTextValue = cfg.wrappedValue.valueType == .text && variableResolvedValuePreview.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            Text("Variable")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField(
                "Variable name",
                text: Binding(
                    get: { cfg.wrappedValue.name },
                    set: { newValue in
                        var value = cfg.wrappedValue
                        value.name = newValue
                        cfg.wrappedValue = value
                    }
                )
            )
            .textFieldStyle(.roundedBorder)

            Picker("Type", selection: Binding(
                get: { cfg.wrappedValue.valueType },
                set: { newValue in
                    var value = cfg.wrappedValue
                    value.valueType = newValue
                    cfg.wrappedValue = value
                }
            )) {
                ForEach(GraphVariableValueType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if let token = cfg.wrappedValue.sharedValueToken {
                HStack(spacing: 8) {
                    Text("Source: \(token)")
                        .font(.caption)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    #if os(macOS)
                    Button("Change") { chooseSharedVariable(for: cfg) }
                    #endif
                    Button("Clear") {
                        var value = cfg.wrappedValue
                        value.sharedValueToken = nil
                        cfg.wrappedValue = value
                    }
                }
            } else {
                #if os(macOS)
                Button("Use Universal Variable", systemImage: "number.square") {
                    chooseSharedVariable(for: cfg)
                }
                .help("Choose a live variable from the Variables window")
                #endif
            }

            Group {
                switch cfg.wrappedValue.valueType {
                case .text:
                    TextField(
                        "Manual value",
                        text: Binding(
                            get: { cfg.wrappedValue.manualTextValue },
                            set: { newValue in
                                var value = cfg.wrappedValue
                                value.manualTextValue = newValue
                                cfg.wrappedValue = value
                            }
                        )
                    )
                case .number:
                    TextField(
                        "Manual value",
                        value: Binding(
                            get: { Int(cfg.wrappedValue.manualNumberValue.rounded(.towardZero)) },
                            set: { newValue in
                                var value = cfg.wrappedValue
                                value.manualNumberValue = Double(newValue)
                                cfg.wrappedValue = value
                            }
                        ),
                        format: .number
                    )
                case .float:
                    TextField(
                        "Manual value",
                        value: Binding(
                            get: { cfg.wrappedValue.manualNumberValue },
                            set: { newValue in
                                var value = cfg.wrappedValue
                                value.manualNumberValue = newValue
                                cfg.wrappedValue = value
                            }
                        ),
                        format: .number
                    )
                case .boolean:
                    Toggle(
                        "Manual value",
                        isOn: Binding(
                            get: { cfg.wrappedValue.manualBooleanValue },
                            set: { newValue in
                                var value = cfg.wrappedValue
                                value.manualBooleanValue = newValue
                                cfg.wrappedValue = value
                            }
                        )
                    )
                    .toggleStyle(.switch)
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(hasLinkedVariableInput || cfg.wrappedValue.sharedValueToken != nil)

            if hasLinkedVariableInput {
                Text("Manual value overridden by linked input.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if cfg.wrappedValue.sharedValueToken != nil {
                Text("Manual value is overridden by the selected universal variable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if normalizedName.isEmpty {
                Text("Variable name is required.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if hasDuplicateVariableName {
                Text("Variable name must be unique within this tab.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if isEmptyTextValue {
                Text("Current text value is empty.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text("Variables store values — they don't trigger actions when updated. Use a Condition node to act on a variable's value.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Current value")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(variableResolvedValuePreview.isEmpty ? "Empty value" : variableResolvedValuePreview)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                        .fill(Color.white.opacity(GraphNodeStyleTokens.cardFillOpacity))
                )
        }
    }

    private func chooseSharedVariable(for config: Binding<DashboardGraph.VariableNodeConfig>) {
        #if os(macOS)
        variableInsertionTarget.onInsert = { token in
            var value = config.wrappedValue
            value.sharedValueToken = token
            value.currentTextValue = nil
            value.currentNumberValue = nil
            value.currentBooleanValue = nil
            value.sourceNodeId = nil
            config.wrappedValue = value
            return true
        }
        SharedValuePickerCoordinator.shared.target = variableInsertionTarget
        NotificationCenter.default.post(name: .relayShowSharedValues, object: nil)
        #endif
    }

    private var toggleNodeSettings: some View {
        let nodeKey = nodeId.uuidString
        let cfg = Binding<DashboardGraph.ToggleNodeConfig>(
            get: { graph?.toggleNodeConfigByNodeId[nodeKey]
                ?? DashboardGraph.ToggleNodeConfig(id: nodeId) },
            set: { graph?.toggleNodeConfigByNodeId[nodeKey] = $0 }
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Current state")
                Spacer()
                Text(cfg.wrappedValue.currentState ? "On" : "Off")
                    .foregroundStyle(cfg.wrappedValue.currentState ? Color.green : Color.secondary)
            }
            Toggle("Reset to Off on launch", isOn: Binding(
                get: { cfg.wrappedValue.resetOnLaunch },
                set: { var v = cfg.wrappedValue; v.resetOnLaunch = $0; cfg.wrappedValue = v }
            ))
            Text("Each trigger fire alternates between the On and Off output ports.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var counterNodeSettings: some View {
        let nodeKey = nodeId.uuidString
        let cfg = Binding<DashboardGraph.CounterNodeConfig>(
            get: { graph?.counterNodeConfigByNodeId[nodeKey]
                ?? DashboardGraph.CounterNodeConfig(id: nodeId) },
            set: { graph?.counterNodeConfigByNodeId[nodeKey] = $0 }
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fire after")
                Spacer()
                TextField("", value: Binding(
                    get: { cfg.wrappedValue.threshold },
                    set: { var v = cfg.wrappedValue; v.threshold = max(1, $0); cfg.wrappedValue = v }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                Text("triggers")
            }
            HStack {
                Text("Count")
                Spacer()
                Text("\(cfg.wrappedValue.currentCount) / \(cfg.wrappedValue.threshold)")
                    .foregroundStyle(.secondary)
            }
            Toggle("Reset after firing", isOn: Binding(
                get: { cfg.wrappedValue.resetAfterFire },
                set: { var v = cfg.wrappedValue; v.resetAfterFire = $0; cfg.wrappedValue = v }
            ))
            Toggle("Reset to 0 on launch", isOn: Binding(
                get: { cfg.wrappedValue.resetOnLaunch },
                set: { var v = cfg.wrappedValue; v.resetOnLaunch = $0; cfg.wrappedValue = v }
            ))
            Button("Reset Count") {
                var v = cfg.wrappedValue
                v.currentCount = 0
                cfg.wrappedValue = v
            }
            .buttonStyle(.bordered)
        }
    }

    private var sequenceNodeSettings: some View {
        let nodeKey = nodeId.uuidString
        let cfg = Binding<DashboardGraph.SequenceNodeConfig>(
            get: { graph?.sequenceNodeConfigByNodeId[nodeKey]
                ?? DashboardGraph.SequenceNodeConfig(id: nodeId) },
            set: { graph?.sequenceNodeConfigByNodeId[nodeKey] = $0 }
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Steps")
                Spacer()
                Stepper(
                    "\(cfg.wrappedValue.stepCount)",
                    value: Binding(
                        get: { cfg.wrappedValue.stepCount },
                        set: { var v = cfg.wrappedValue; v.stepCount = max(2, min(8, $0)); cfg.wrappedValue = v }
                    ),
                    in: 2...8
                )
            }
            HStack {
                Text("Current step")
                Spacer()
                Text("\(cfg.wrappedValue.currentStep + 1) of \(cfg.wrappedValue.stepCount)")
                    .foregroundStyle(.secondary)
            }
            Toggle("Reset to step 1 on launch", isOn: Binding(
                get: { cfg.wrappedValue.resetOnLaunch },
                set: { var v = cfg.wrappedValue; v.resetOnLaunch = $0; cfg.wrappedValue = v }
            ))
            Button("Reset to Step 1") {
                var v = cfg.wrappedValue
                v.currentStep = 0
                cfg.wrappedValue = v
            }
            .buttonStyle(.bordered)
            Text("Wire output 1 to the first action, output 2 to the second, etc.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var latchNodeSettings: some View {
        let nodeKey = nodeId.uuidString
        let cfg = Binding<DashboardGraph.LatchNodeConfig>(
            get: { graph?.latchNodeConfigByNodeId[nodeKey]
                ?? DashboardGraph.LatchNodeConfig(id: nodeId) },
            set: { graph?.latchNodeConfigByNodeId[nodeKey] = $0 }
        )
        let linkedTriggerIds: [(UUID, String)] = {
            guard let g = graph else { return [] }
            return g.links
                .filter { $0.isEnabled }
                .compactMap { link -> (UUID, String)? in
                    let toId = g.nodeIdByPortId[link.toPortId] ?? link.toTileId
                    guard toId == nodeId else { return nil }
                    let fromId = g.nodeIdByPortId[link.fromPortId] ?? link.fromTileId
                    let label = triggerDisplayName(forNodeId: fromId, in: g)
                    return (fromId, label)
                }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("State")
                Spacer()
                Text(cfg.wrappedValue.isEnabled ? "Enabled (open)" : "Disabled (closed)")
                    .foregroundStyle(cfg.wrappedValue.isEnabled ? Color.green : Color.red)
            }
            Picker("Enable trigger", selection: Binding<UUID?>(
                get: { cfg.wrappedValue.enableTriggerNodeId },
                set: { var v = cfg.wrappedValue; v.enableTriggerNodeId = $0; cfg.wrappedValue = v }
            )) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(linkedTriggerIds, id: \.0) { Text($1).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            Picker("Disable trigger", selection: Binding<UUID?>(
                get: { cfg.wrappedValue.disableTriggerNodeId },
                set: { var v = cfg.wrappedValue; v.disableTriggerNodeId = $0; cfg.wrappedValue = v }
            )) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(linkedTriggerIds, id: \.0) { Text($1).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            Toggle("Reset to Enabled on launch", isOn: Binding(
                get: { cfg.wrappedValue.resetOnLaunch },
                set: { var v = cfg.wrappedValue; v.resetOnLaunch = $0; cfg.wrappedValue = v }
            ))
            Text("When disabled, all signal triggers are blocked.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourcePreview(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .opacity(0.9)
                .lineLimit(2)
        }
    }

    private func updateTranscriptionRule(_ id: UUID, _ update: (inout DashboardGraph.WordTriggerRule) -> Void) {
        var v = transcriptionWordTriggerCfg.wrappedValue
        guard let idx = v.rules.firstIndex(where: { $0.id == id }) else { return }
        var rule = v.rules[idx]
        update(&rule)
        v.rules[idx] = rule
        transcriptionWordTriggerCfg.wrappedValue = v
    }

    private func removeTranscriptionRule(_ id: UUID) {
        var v = transcriptionWordTriggerCfg.wrappedValue
        v.rules.removeAll { $0.id == id }
        if v.rules.isEmpty {
            v.rules = [DashboardGraph.WordTriggerRule()]
        }
        transcriptionWordTriggerCfg.wrappedValue = v
    }

    private func linkedTranscriptionSources() -> [LiveTranscriptionSourceDescriptor] {
        guard let graph else { return [] }
        let incoming = graph.links.filter { link in
            if !link.isEnabled { return false }
            let resolved = graph.nodeIdByPortId[link.toPortId] ?? link.toTileId
            return resolved == nodeId
        }
        let sourceNodeIds = Set(incoming.map { graph.nodeIdByPortId[$0.fromPortId] ?? $0.fromTileId })
        var sources: [LiveTranscriptionSourceDescriptor] = []
        for sourceNodeId in sourceNodeIds {
            sources.append(contentsOf: LiveTranscriptionSourceRegistry.shared.sources(for: sourceNodeId))
        }
        var seen: Set<UUID> = []
        return sources.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Trigger display name helpers (mirrors GraphDashboardView.triggerGroupKeyDisplayName)

    private func triggerDisplayName(forNodeId nodeId: UUID, in graph: DashboardGraph) -> String {
        // Graph-only module-group trigger instance
        if let inst = graph.moduleGroupNodeInstances.first(where: { $0.id == nodeId }) {
            return triggerGroupKeyToDisplayName(inst.groupKey)
        }
        // Canvas-backed tile trigger: use the tile's user-facing name
        for tile in tab.tiles {
            guard tile.id == nodeId else { continue }
            let trimmed = tile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Trigger"
    }

    private func triggerGroupKeyToDisplayName(_ key: String) -> String {
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
        case "moduleGroup.pcoItemChanged":   return "PCO Plan Updated"
        case "moduleGroup.appState":         return "App State"
        default:
            if key == DashboardGraph.buttonTriggerGroupKey { return "Canvas Button" }
            return "Trigger"
        }
    }

    private func iconName(for key: String) -> String {
        if key.contains("roster") { return "tablecells" }
        if key.contains("consoleImport") { return "slider.horizontal.3" }
        if key.contains("wirelessImport") { return "dot.radiowaves.left.and.right" }
        if key.contains("staticLabel") { return "tag.fill" }
        if key.contains("variable") { return "textformat.alt" }
        if key.contains("person") { return "person.3.fill" }
        if key.contains("shure") { return "dot.radiowaves.left.and.right" }
        if key.contains("sennheiser") { return "dot.radiowaves.left.and.right" }
        if key.contains("pco") { return "list.bullet.rectangle" }
        if key.contains("oscSend") { return "paperplane" }
        if key.contains("oscReceive") { return "dot.radiowaves.left.and.right" }
        if key.contains("midiReceive") { return "pianokeys" }
        if key.contains("time") { return "clock.fill" }
        if key.contains("wordTrigger") { return "text.bubble.fill" }
        if key.contains("transcription") { return "text.bubble.fill" }
        if key.contains("text") { return "text.alignleft" }
        if key.contains("separator") { return "minus" }
        if key.contains("propresenter") { return "rectangle.on.rectangle" }
        if key.contains("resolume") { return "sparkles" }
        return "cube"
    }

    private func rosterRowLabel(row: DashboardRosterRow, index: Int) -> String {
        for column in tab.rosterColumns {
            let value = row.value(for: column.id).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return "\(index + 1). \(value)"
            }
        }
        return "Row \(index + 1)"
    }

    private func consoleChannelOptions(device: ExternalDeviceConfig?) -> [(label: String, channel: Int)] {
        guard let device else {
            return [("CH 1", 1)]
        }

        if !device.digicoInputChannels.isEmpty {
            return device.digicoInputChannels.map { ("#\($0.channel) — \($0.name)", $0.channel) }
        }

        let synced = syncedConsoleChannelNamesByChannel(deviceId: device.id)
        let modelId = (device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if modelId == "Behringer_X32" || modelId == "Midas_M32" {
            return (1...32).map { channel in
                if let name = synced[channel]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    return ("#\(channel) — \(name)", channel)
                }
                return ("#\(channel)", channel)
            }
        }

        if modelId.hasPrefix("AH_Qu") {
            return (1...32).map { ("#\($0) — Ip\($0)", $0) }
        }

        if let limit = allenHeathChannelLimit(modelIdentifier: modelId) {
            return (1...limit).map { channel in
                if let name = synced[channel]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    return ("#\(channel) — \(name)", channel)
                }
                return ("#\(channel)", channel)
            }
        }

        return (1...32).map { ("#\($0)", $0) }
    }

    private func syncedConsoleChannelNamesByChannel(deviceId: UUID) -> [Int: String] {
        ConsoleDeviceDataAdapter.syncedChannelNamesByChannel(deviceId: deviceId)
    }

    private func allenHeathChannelLimit(modelIdentifier: String) -> Int? {
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

    private func selectedWirelessChannelCount(config: DashboardGraph.WirelessLabelSourceConfig) -> Int {
        switch config.deviceKind {
        case .shure:
            guard let deviceId = config.deviceId,
                  let device = shureDevices.first(where: { $0.id == deviceId }) else {
                return 1
            }
            return max(1, device.effectiveShureChannelCount)
        case .sennheiser:
            guard let deviceId = config.deviceId,
                  let device = sennheiserDevices.first(where: { $0.id == deviceId }) else {
                return 1
            }
            return max(1, device.sennheiserNetworkModel?.channelCount ?? 1)
        }
    }

    private func resolvedConsoleChannelName(device: ExternalDeviceConfig, channelIndex: Int) -> String? {
        if let digico = device.digicoInputChannels.first(where: { $0.channel == channelIndex }) {
            let name = digico.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let synced = syncedConsoleChannelNamesByChannel(deviceId: device.id)[channelIndex] {
            let name = synced.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return nil
    }

    private func resolvedShureChannelName(device: ExternalDeviceConfig, channelIndex: Int) -> String? {
        if let cached = ExternalDevicesStore.shared.cachedShureChannelName(deviceID: device.id, channelIndex: channelIndex) {
            let name = cached.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let stored = device.shureChannelNames[channelIndex] {
            let name = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if channelIndex == 1, let name = device.psmChannel1Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if channelIndex == 2, let name = device.psmChannel2Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return nil
    }

    private func resolvedSennheiserChannelName(device: ExternalDeviceConfig, channelIndex: Int) -> String? {
        if let cached = ExternalDevicesStore.shared.cachedSennheiserChannelName(deviceID: device.id, channelIndex: channelIndex) {
            let name = cached.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return nil
    }
}
