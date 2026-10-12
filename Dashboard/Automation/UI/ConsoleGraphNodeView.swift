//
//  ConsoleGraphNodeView.swift
//  Relay
//
//  Extracted from GraphDashboardView.swift
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Trigger node reference (used in trigger binding UI)

struct ConsoleTriggerNodeRef: Identifiable, Equatable {
    let id: UUID
    let name: String
}

// MARK: - Console node view

struct ConsoleGraphNodeView: View {
    private static let intFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximumFractionDigits = 0
        formatter.allowsFloats = false
        return formatter
    }()
    private enum QuActionMenu: String, CaseIterable, Identifiable {
        case level
        case mute
        case softKey
        case sceneRecall
        case raw

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .level: return "Level"
            case .mute: return "Mute"
            case .softKey: return "Soft Key"
            case .sceneRecall: return "Scene Recall"
            case .raw: return "Advanced (Raw)"
            }
        }
    }

    private static let quDbFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = -80
        formatter.maximum = 10
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.allowsFloats = true
        return formatter
    }()

    private var destinationCategory: GraphNodeCategory { .destinations }

    private var nameFormatBinding: Binding<String> {
        Binding<String>(
            get: { nameFormatSelection },
            set: { newValue in
                let normalized = normalizedNameFormat(newValue)
                guard nameFormatSelection != normalized else { return }
                nameFormatSelection = normalized
                rebuildAssignmentCaches()
                onSetNameFormat(normalized)
            }
        )
    }

    private var nameCasingBinding: Binding<String> {
        Binding<String>(
            get: { nameCasingSelection },
            set: { newValue in
                let normalized = normalizedNameCasing(newValue)
                guard nameCasingSelection != normalized else { return }
                nameCasingSelection = normalized
                rebuildAssignmentCaches()
                onSetNameCasing(normalized)
            }
        )
    }

    private func channelAssignmentBinding(for personLabel: String) -> Binding<Int?> {
        Binding<Int?>(
            get: { localConsoleChannelAssignments[personLabel] },
            set: { setChannelAssignment(for: personLabel, channel: $0) }
        )
    }

    private func syncLocalConsoleChannelAssignments() {
        localConsoleChannelAssignments = device.consoleChannelAssignments
    }

    private func setChannelAssignment(for personLabel: String, channel: Int?) {
        if let channel {
            localConsoleChannelAssignments[personLabel] = channel
        } else {
            localConsoleChannelAssignments.removeValue(forKey: personLabel)
        }
        rebuildAssignmentCaches()
        onAssign(personLabel, channel)
    }

    private func clearAllAssignments() {
        localConsoleChannelAssignments.removeAll()
        rebuildAssignmentCaches()
        onClearAssignments()
    }

    private func autoAssignChannels() {
        localConsoleChannelAssignments = onAutoAssign()
        rebuildAssignmentCaches()
    }

    private func snapshotNameBinding(seq: Int, fallback: String) -> Binding<String> {
        Binding<String>(
            get: { snapshotNameEdits[seq] ?? fallback },
            set: { snapshotNameEdits[seq] = $0 }
        )
    }

    @ViewBuilder
    private var deviceHeaderRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "hifispeaker.fill")
                .imageScale(.medium)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name.isEmpty ? "Audio Console" : device.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text("DESTINATION")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(destinationCategory.badgeColor)
                        )
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Destination node")
                }

                let modelId = (device.consoleModelIdentifier ?? "")
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

                let modelTextRaw: String = {
                    // Prefer the enum's user-friendly display name if we can resolve it.
                    if let model = AudioConsoleModel(rawValue: modelId) {
                        return model.displayName
                    }
                    // Fallback to the identifier.
                    return modelId
                }()

                let modelText = modelTextRaw
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

                Text(modelText.isEmpty ? "Console" : modelText)
                    .font(.caption)
                    .opacity(0.7)
                    .lineLimit(1)
            }

            Spacer()

            let portString = String(format: "%d", Int(device.port))
            Text("\(device.host):\(portString)")
                .font(.caption2)
                .opacity(0.6)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func triggerBindingControl(selection: Binding<UUID?>) -> some View {
        if !linkedTriggerNodes.isEmpty {
            if linkedTriggerNodes.count == 1 {
                let trigger = linkedTriggerNodes[0]
                let isEnabled = selection.wrappedValue == trigger.id
                Button {
                    selection.wrappedValue = isEnabled ? nil : trigger.id
                } label: {
                    Label(
                        isEnabled ? "→ \(trigger.name)" : "No trigger",
                        systemImage: isEnabled ? "bolt.fill" : "bolt.slash"
                    )
                    .font(.caption2)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Picker("Trigger", selection: selection) {
                    Text("No trigger").tag(UUID?.none)
                    ForEach(linkedTriggerNodes, id: \.id) { trigger in
                        Text("→ \(trigger.name)").tag(Optional(trigger.id))
                    }
                }
                .labelsHidden()
                .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private var snapshotsHeaderRow: some View {
        HStack {
            let snapshotCount = effectiveRundownTitles.count
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSnapshotsCollapsed.toggle()
                }
                persistCollapseState()
            } label: {
                Text("Snapshots" + (snapshotCount > 0 ? " (\(snapshotCount))" : ""))
                    .font(.caption)
                    .opacity(0.75)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSnapshotsCollapsed ? "Expand Snapshots" : "Collapse Snapshots")

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSnapshotsCollapsed.toggle()
                }
                persistCollapseState()
            } label: {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .opacity(0.85)
                    .rotationEffect(.degrees(isSnapshotsCollapsed ? -90 : 0))
                    .animation(.easeInOut(duration: 0.18), value: isSnapshotsCollapsed)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSnapshotsCollapsed ? "Expand Snapshots" : "Collapse Snapshots")

            // Trigger binding control
            triggerBindingControl(selection: triggerSendConfig.snapshotsTriggerNodeId)

            Button {
                let rawCount = rundownSnapshotTitles.count
                let effCount = effectiveRundownTitles.count
                let workCount = buildSnapshotWorkItems().count
                print("[ConsoleGraphNodeView] Snapshots Send tapped: deviceId=\(device.id) model=\(device.consoleModelIdentifier ?? "") rawTitles=\(rawCount) effectiveTitles=\(effCount) workItems=\(workCount)")
                if rawCount > 0 {
                    print("[ConsoleGraphNodeView] Snapshots raw preview: \(rundownSnapshotTitles.prefix(5))")
                }
                postCreateRenameSnapshotsRequest()
            } label: {
                Label("Test", systemImage: "paperplane.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .opacity(buildSnapshotWorkItems().isEmpty ? 0.35 : 1.0)
            .disabled(buildSnapshotWorkItems().isEmpty)
        }
    }

    let device: ExternalDeviceConfig
    let nodeId: UUID
    var linkedTriggerNodes: [ConsoleTriggerNodeRef] = []
    var triggerSendConfig: Binding<DashboardGraph.ConsoleTriggerSendConfig> = .constant(DashboardGraph.ConsoleTriggerSendConfig())
    let showAssignments: Bool
    let showSnapshots: Bool
    let showQuActions: Bool
    let showStandardActions: Bool
    let quActions: Binding<[DashboardGraph.QuConsoleAction]>
    let standardActions: Binding<[DashboardGraph.StandardConsoleAction]>
    let rundownSnapshotTitles: [String]
    let people: [GraphDashboardView.ModuleMember]
    let availablePositions: [String]
    let onAssign: (_ personLabel: String, _ channel: Int?) -> Void
    let onAutoAssign: () -> [String: Int]
    let onClearAssignments: () -> Void
    let onSetNameFormat: (_ format: String) -> Void
    let onSetNameCasing: (_ casing: String) -> Void
    let onSetSnapshotCasing: (_ casing: String) -> Void
    let onSetSnapshotShortenEnabled: (_ enabled: Bool) -> Void
    let onSetSnapshotShortenLimit: (_ limit: Int) -> Void
    let onSetPositionDefault: (_ position: String, _ channel: Int?) -> Void
    let onTestQuActions: () -> Void
    let onTestStandardActions: () -> Void
    let showDigiCoActions: Bool
    let digicoActions: Binding<[DashboardGraph.DiGiCoConsoleAction]>
    let onTestDigiCoActions: () -> Void
    let capabilityMismatchedSources: [String]
    let consoleActionWarningText: String?
    let consoleActionWarningStyle: ActionNodeWarningStyle
    let isTestingConsoleAction: Bool
    let onDismissConsoleActionWarning: (() -> Void)?

    @ViewBuilder
    private func consoleActionWarningPill(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: consoleActionWarningStyle == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.caption)
                .foregroundStyle(consoleActionWarningStyle == .error ? Color.red.opacity(0.95) : Color.orange.opacity(0.95))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            if let onDismissConsoleActionWarning {
                Button(action: onDismissConsoleActionWarning) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .stroke(
                    consoleActionWarningStyle == .error ? Color.red.opacity(0.20) : Color.orange.opacity(0.18),
                    lineWidth: GraphNodeStyleTokens.borderStrokeWidth
                )
        )
    }

    private func positionDefaultBinding(for pos: String) -> Binding<Int?> {
        Binding<Int?>(
            get: {
                let v = localPositionChannelDefaults[pos] ?? 0
                return v == 0 ? nil : v
            },
            set: { newValue in
                if let newValue {
                    setPositionDefault(pos, channel: newValue)
                } else {
                    // Keep row but mark as unassigned
                    setPositionDefault(pos, channel: 0)
                }
            }
        )
    }

    private func syncLocalPositionDefaults() {
        localPositionChannelDefaults = device.consolePositionChannelDefaults
    }

    private func setPositionDefault(_ position: String, channel: Int?) {
        if let channel {
            localPositionChannelDefaults[position] = channel
        } else {
            localPositionChannelDefaults.removeValue(forKey: position)
        }
        onSetPositionDefault(position, channel)
    }

    private var channelOptions: [(label: String, channel: Int)] {
        cachedChannelOptions
    }

    private var isX32OrM32Console: Bool {
        let modelId = (device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return modelId == "Behringer_X32" || modelId == "Midas_M32"
    }

    private var isAllenHeathQuConsole: Bool {
        let modelId = (device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return modelId.hasPrefix("AH_Qu")
    }

    private var allenHeathChannelLimit: Int? {
        guard let modelId = device.consoleModelIdentifier,
              let model = AudioConsoleModel.from(identifier: modelId.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        switch model {
        case .allenHeathDlive:
            return 128
        case .allenHeathAvantis, .allenHeathSq:
            return 64
        default:
            return nil
        }
    }


    /// Pull the per-device synced channel-name map gathered in External Devices settings.
    /// Primary source: UserDefaults (persisted by ExternalDevicesSettingsView).
    /// Fallback: reflection on `ExternalDeviceConfig` in case the map is stored directly on the model.
    private var syncedChannelNamesByChannel: [Int: String] {
        ConsoleDeviceDataAdapter.syncedChannelNamesByChannel(for: device)
    }

    @State private var showSnapshotSettings = false
    @State private var showAssignmentSettings = false
    @State private var showAddPositionPopover = false
    @State private var showRawInfo = false
    @Binding var graph: DashboardGraph?
    @State private var isAssignmentsCollapsed: Bool = false
    @State private var isSnapshotsCollapsed: Bool = false
    @State private var positionSearchText: String = ""
    @State private var snapshotNameEdits: [Int: String] = [:]
    @State private var nameFormatSelection: String = "first"
    @State private var nameCasingSelection: String = "title"
    @State private var snapshotCasingSelection: String = "title"
    @State private var snapshotShortenEnabledSelection: Bool = false
    @State private var snapshotShortenLimitSelection: Int = 12
    @State private var snapshotAppendKeySelection: Bool = false
    @State private var localConsoleChannelAssignments: [String: Int] = [:]
    @State private var localPositionChannelDefaults: [String: Int] = [:]
    @State private var showAllAssignments: Bool = false
    @State private var snapshotEditsDebounceWork: DispatchWorkItem?

    struct AssignmentRowModel: Identifiable, Equatable {
        let id: UUID
        let title: String
        let position: String
        let fullName: String
        let formattedName: String
        let assignedChannel: Int?

        init(member: GraphDashboardView.ModuleMember,
             position: String,
             fullName: String,
             formattedName: String,
             assignedChannel: Int?) {
            self.id = member.id
            self.title = member.title
            self.position = position
            self.fullName = fullName
            self.formattedName = formattedName
            self.assignedChannel = assignedChannel
        }
    }

    @State private var cachedPeopleSorted: [GraphDashboardView.ModuleMember] = []
    @State private var cachedAssignmentRows: [AssignmentRowModel] = []
    @State private var cachedAssignmentWorkItems: [(channel: Int, name: String)] = []
    @State private var cachedChannelOptions: [(label: String, channel: Int)] = []

    private var peopleSorted: [GraphDashboardView.ModuleMember] {
        cachedPeopleSorted
    }

    private func rebuildPeopleCaches() {
        let sorted = people.sorted { a, b in
            let pa = splitLabel(a.title).position.lowercased()
            let pb = splitLabel(b.title).position.lowercased()
            if pa != pb {
                if pa.isEmpty { return false }
                if pb.isEmpty { return true }
                return pa < pb
            }
            return a.title.lowercased() < b.title.lowercased()
        }
        cachedPeopleSorted = sorted
        rebuildAssignmentCaches()
    }

    private func rebuildAssignmentCaches() {
        cachedAssignmentRows = buildAssignmentRows(from: cachedPeopleSorted)
        cachedAssignmentWorkItems = buildAssignmentWorkItems(from: cachedPeopleSorted)
    }

    private func buildAssignmentRows(from sortedPeople: [GraphDashboardView.ModuleMember]) -> [AssignmentRowModel] {
        sortedPeople.map { member in
            let parts = splitLabel(member.title)
            let formatted = formattedName(position: parts.position, fullName: parts.fullName)
            let assigned = localConsoleChannelAssignments[member.title]
            return AssignmentRowModel(
                member: member,
                position: parts.position,
                fullName: parts.fullName,
                formattedName: formatted,
                assignedChannel: assigned
            )
        }
    }

    private func rebuildChannelOptions() {
        // DiGiCo uses imported channel lists (RTF).
        if !device.digicoInputChannels.isEmpty {
            cachedChannelOptions = device.digicoInputChannels.map { ch in
                ("#\(ch.channel) — \(ch.name)", ch.channel)
            }
            return
        }

        // X32/M32: limit to 32 input channels, and prefer showing the synced channel names (if available).
        if isX32OrM32Console {
            let synced = syncedChannelNamesByChannel
            cachedChannelOptions = (1...32).map { ch in
                if let name = synced[ch]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    return ("#\(ch) — \(name)", ch)
                }
                return ("#\(ch)", ch)
            }
            return
        }

        // Allen & Heath Qu: fixed input channels 1-32 (Ip1..Ip32).
        if isAllenHeathQuConsole {
            cachedChannelOptions = (1...32).map { ch in
                ("#\(ch) — Ip\(ch)", ch)
            }
            return
        }

        if let channelLimit = allenHeathChannelLimit {
            let synced = syncedChannelNamesByChannel
            cachedChannelOptions = (1...channelLimit).map { ch in
                if let name = synced[ch]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    return ("#\(ch) — \(name)", ch)
                }
                return ("#\(ch)", ch)
            }
            return
        }

        // Default: generic 1...128
        cachedChannelOptions = (1...128).map { ("#\($0)", $0) }
    }

    private func digicoChannelOptions(
        for channelType: DashboardGraph.DiGiCoChannelType
    ) -> [(label: String, channel: Int)] {
        switch channelType {
        case .inputChannel:
            guard !device.digicoInputChannels.isEmpty else { return [] }
            return device.digicoInputChannels
                .sorted { $0.channel < $1.channel }
                .map { ("#\($0.channel) — \($0.name)", $0.channel) }

        default:
            let channels = device.digicoDiscoveredChannels
                .filter { $0.channelType == channelType }
                .sorted { $0.index < $1.index }
            guard !channels.isEmpty else { return [] }
            return channels.map { ("#\($0.index) — \($0.name)", $0.index) }
        }
    }

    // Extracted subview for snapshot settings popover (rendered as an in-node overlay so it scales with zoom)
    @ViewBuilder
    private var snapshotSettingsPopover: some View {
        // Break up bindings into locals to help the compiler.
        let casingBinding = Binding<String>(
            get: { snapshotCasingSelection },
            set: {
                snapshotCasingSelection = $0
                onSetSnapshotCasing($0)
            }
        )
        let shortenBinding = Binding<Bool>(
            get: { snapshotShortenEnabledSelection },
            set: {
                snapshotShortenEnabledSelection = $0
                onSetSnapshotShortenEnabled($0)
            }
        )
        let limitBinding = Binding<Int>(
            get: { max(6, snapshotShortenLimitSelection) },
            set: {
                snapshotShortenLimitSelection = $0
                onSetSnapshotShortenLimit($0)
            }
        )
        let appendKeyBinding = Binding<Bool>(
            get: { snapshotAppendKeySelection },
            set: { newValue in
                snapshotAppendKeySelection = newValue
                // Update the visible snapshot names immediately.
                if snapshotNameEdits.isEmpty {
                    resetSnapshotEditsFromRundown()
                } else {
                    reformatExistingSnapshotEdits()
                }
            }
        )

        ZStack(alignment: .topTrailing) {
            Button {
                showSnapshotSettings = false
            } label: {
                Color.black.opacity(0.001)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss snapshot settings")

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Snapshot Settings")
                        .font(.headline)
                    Spacer()
                    Button {
                        showSnapshotSettings = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Casing").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: casingBinding) {
                        Text("Title Case").tag("title")
                        Text("ALL CAPS").tag("upper")
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                Toggle(isOn: shortenBinding) {
                    Text("Smart shorten")
                }

                Toggle(isOn: appendKeyBinding) {
                    Text("Append key")
                }
                .disabled(effectiveRundownTitles.isEmpty)
                .opacity(effectiveRundownTitles.isEmpty ? 0.45 : 1.0)

                HStack {
                    Text("Max Length")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Stepper(value: limitBinding, in: 6...32) {
                        Text("\(max(6, snapshotShortenLimitSelection))")
                            .font(.caption)
                    }
                    .labelsHidden()
                }
                .opacity(snapshotShortenEnabledSelection ? 1.0 : 0.45)
                .disabled(!snapshotShortenEnabledSelection)

                Divider()

                Button {
                    resetSnapshotEditsFromRundown()
                } label: {
                    Label("Reset from Rundown", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .opacity(effectiveRundownTitles.isEmpty ? 0.35 : 1.0)
                .disabled(effectiveRundownTitles.isEmpty)
            }
            .padding(14)
            .frame(width: 320)
            .background {
                #if os(macOS)
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                #else
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                    .fill(Color(.systemBackground).opacity(0.95))
                #endif
            }
            .overlay(
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                    .stroke(Color.white.opacity(GraphNodeStyleTokens.secondaryBorderOpacity), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .shadow(radius: 18)
            // Push it below the node header so it doesn't cover the title row.
            .offset(y: 34)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        ))
    }

    // Extracted subview for assignment settings popover (standard popover anchored to Settings button)
    @ViewBuilder
    private var assignmentSettingsPopover: some View {
        let channelOptions = self.channelOptions
        let configuredDefaultPositions = self.configuredDefaultPositions

        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Assignment Settings")
                        .font(.headline)
                    Spacer()
                    Button {
                        showAssignmentSettings = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Name format
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name Format").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: nameFormatBinding) {
                        Text("First Name").tag("first")
                        Text("Last Name").tag("last")
                        Text("Position").tag("position")
                    }
                    .pickerStyle(.segmented)
                }

                // Casing
                VStack(alignment: .leading, spacing: 6) {
                    Text("Casing").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: nameCasingBinding) {
                        Text("Title Case").tag("title")
                        Text("UPPERCASE").tag("upper")
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                HStack {
                    Text("Auto Assign Defaults (by Position)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showAddPositionPopover.toggle()
                    } label: {
                        Image(systemName: "plus")
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showAddPositionPopover, arrowEdge: .trailing) {
                        addPositionPopoverContent
                    }
                }

                if configuredDefaultPositions.isEmpty {
                    Text("Add positions with +, then pick a channel. These rules are saved per console.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(configuredDefaultPositions, id: \.self) { pos in
                        HStack {
                            Text(pos)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Picker("", selection: positionDefaultBinding(for: pos)) {
                                Text("—").tag(Int?.none)
                                ForEach(channelOptions, id: \.channel) { opt in
                                    Text(opt.label).tag(Optional(opt.channel))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)

                            Button(role: .destructive) {
                                // Remove the rule entirely.
                                setPositionDefault(pos, channel: nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .imageScale(.small)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 340)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                #if os(macOS)
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                #else
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                    .fill(Color(.systemBackground).opacity(0.95))
                #endif
            }
            .overlay(
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                    .stroke(Color.white.opacity(GraphNodeStyleTokens.secondaryBorderOpacity), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .shadow(radius: 18)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
            ))
    }

    private var addPositionPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Add Position")
                    .font(.headline)
                Spacer()
                Button {
                    showAddPositionPopover = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("Search positions…", text: $positionSearchText)
                .textFieldStyle(.roundedBorder)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if filteredAddablePositions.isEmpty {
                        Text(addablePositions.isEmpty ? "No more positions" : "No matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(filteredAddablePositions.prefix(200), id: \.self) { pos in
                            Button(pos) {
                                setPositionDefault(pos, channel: 0)
                                positionSearchText = ""
                                showAddPositionPopover = false
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }

                        if filteredAddablePositions.count > 200 {
                            Text("Showing first 200 results. Refine search to see more.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(14)
        .frame(width: 360)
        .background {
            #if os(macOS)
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
            #else
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                .fill(Color(.systemBackground).opacity(0.95))
            #endif
        }
        .overlay(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.popupCornerRadius)
                .stroke(Color.white.opacity(GraphNodeStyleTokens.secondaryBorderOpacity), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
        )
        .shadow(radius: 18)
    }

    private var snapshotBaseOffset: Int {
        // Offset is used to avoid overwriting existing console snapshots.
        // If the console already has snapshots, start after the existing count.
        if device.consoleExistingSnapshots {
            return max(0, device.consoleExistingSnapshotCount)
        }
        return 0
    }

    // MARK: - X32/M32 index display helpers

    /// X32/M32 Show Control uses cue numbers like 1.0.1 .. 1.0.9, then 1.1, 1.1.1, etc.
    /// Internally this maps cleanly to integers 101..109, 110, 111...
    private func x32ShowControlDisplayLabel(forLinearIndex linear: Int) -> String {
        let n = 101 + max(0, linear)
        let a = n / 100
        let b = (n / 10) % 10
        let c = n % 10

        // The X32 UI collapses trailing .0 (e.g. 110 shows as 1.1, not 1.1.0)
        if c == 0 {
            return "\(a).\(b)"
        }
        return "\(a).\(b).\(c)"
    }

    private func unpackTitleAndKey(_ raw: String) -> (title: String, key: String?) {
        if let payload = VistaPCORundownPayloadCodec.decode(from: raw) {
            return (payload.title, payload.keyName)
        }
        return (raw.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    private var effectiveRundownItems: [(title: String, key: String?)] {
        // Clean up empty titles and keep order stable.
        // Also de-dup adjacent duplicates (PCO sometimes repeats headings).
        let cleaned = rundownSnapshotTitles
            .map { unpackTitleAndKey($0) }
            .map { (title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), key: $0.key?.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.title.isEmpty }

        guard !cleaned.isEmpty else { return [] }

        var result: [(title: String, key: String?)] = []
        result.reserveCapacity(cleaned.count)
        for item in cleaned {
            if let last = result.last, last.title == item.title, last.key == item.key {
                continue
            }
            result.append(item)
        }
        return result
    }

    private var effectiveRundownTitles: [String] {
        effectiveRundownItems.map { $0.title }
    }

    private var effectiveRundownKeys: [String?] {
        effectiveRundownItems.map { $0.key }
    }

    private func snapshotIndex(forSeq seq: Int) -> Int {
        // seq is 1-based, index is 0-based (DiGiCo uses 0-based snapshot indexes over OSC).
        (seq - 1) + snapshotBaseOffset
    }

    private func buildSnapshotWorkItems() -> [(seq: Int, index: Int, name: String)] {
        let titles = formattedRundownTitles
        guard !titles.isEmpty else { return [] }
        return titles.enumerated().map { (offset, title) in
            let seq = offset + 1
            let idx = snapshotIndex(forSeq: seq)
            let name = snapshotNameEdits[seq] ?? title
            return (seq: seq, index: idx, name: name)
        }
    }

    private func resetSnapshotEditsFromRundown() {
        snapshotNameEdits.removeAll()
        let titles = formattedRundownTitles
        for (i, t) in titles.enumerated() {
            snapshotNameEdits[i + 1] = t
        }
    }

    private func postCreateRenameSnapshotsRequest() {
        GraphActionExecutor.sendConsoleSnapshots(
            externalDeviceId: device.id,
            deviceAny: device,
            rundownSnapshotTitles: rundownSnapshotTitles,
            snapshotNameEdits: snapshotNameEdits
        )
    }

    // MARK: - Assignment send (channel naming)

    private var assignmentWorkItems: [(channel: Int, name: String)] {
        cachedAssignmentWorkItems
    }

    private func buildAssignmentWorkItems(from sortedPeople: [GraphDashboardView.ModuleMember]) -> [(channel: Int, name: String)] {
        // Build (channel -> name) pairs from current people + assignment map.
        // De-dup by channel (last one wins) but keep output stable sorted by channel.
        var byChannel: [Int: String] = [:]
        for m in sortedPeople {
            guard let ch = localConsoleChannelAssignments[m.title], ch > 0 else { continue }
            if isX32OrM32Console, ch > 32 { continue }
            let parts = splitLabel(m.title)
            let name = formattedName(position: parts.position, fullName: parts.fullName)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            byChannel[ch] = trimmed
        }
        return byChannel.keys.sorted().map { ($0, byChannel[$0] ?? "") }
            .filter { !$0.name.isEmpty }
    }

    private func postSendChannelAssignmentsRequest() {
        GraphActionExecutor.sendConsoleChannelAssignments(
            externalDeviceId: device.id,
            deviceAny: device,
            peopleLabelsInOrder: peopleSorted.map { $0.title }
        )
    }

    private func splitLabel(_ label: String) -> (position: String, fullName: String) {
        let parts = label.components(separatedBy: " — ")
        if parts.count >= 2 {
            return (parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ("", label.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func normalizedNameFormat(_ rawValue: String) -> String {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw == "position" || raw == "last" || raw == "first" {
            return raw
        }
        return "first"
    }

    private func normalizedNameCasing(_ rawValue: String) -> String {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return raw == "upper" ? "upper" : "title"
    }

    private func formattedName(position: String, fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let comps = trimmed.split(separator: " ").map(String.init)
        let first = comps.first ?? trimmed
        let last = comps.last ?? trimmed

        let base: String
        switch nameFormatSelection {
        case "last":
            base = last
        case "position":
            base = position.isEmpty ? first : position
        case "full":
            base = first
        default:
            base = first
        }

        switch nameCasingSelection {
        case "upper":
            return base.uppercased()
        default:
            return titleCased(base)
        }
    }

    // MARK: - Snapshot formatting

    private func titleCased(_ s: String) -> String {
        s.lowercased().localizedCapitalized
    }

    private func applySnapshotCasing(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        switch snapshotCasingSelection {
        case "upper":
            return trimmed.uppercased()
        default:
            return titleCased(trimmed)
        }
    }

    private func applySnapshotFormatting(to items: [(title: String, key: String?)]) -> [String] {
        // Format the base titles first (casing + optional shorten).
        let baseTitles = items.map { $0.title }
        let cased = baseTitles.map { applySnapshotCasing($0) }

        let formattedBase: [String] = {
            guard snapshotShortenEnabledSelection else { return cased }
            let limit = max(6, snapshotShortenLimitSelection)
            return NameShortener.uniqueShorten(cased, limit: limit)
        }()

        // Append keys after shortening so the key suffix never gets truncated.
        guard snapshotAppendKeySelection else { return formattedBase }

        return formattedBase.enumerated().map { (i, title) in
            let key = items.indices.contains(i) ? (items[i].key?.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
            guard let key, !key.isEmpty else { return title }
            return title + " - " + key
        }
    }

    private var formattedRundownTitles: [String] {
        applySnapshotFormatting(to: effectiveRundownItems)
    }

    private func reformatExistingSnapshotEdits() {
        let seqs = snapshotNameEdits.keys.sorted()
        guard !seqs.isEmpty else { return }

        // Preserve key metadata by borrowing keys from the current effective rundown ordering.
        // This lets the “Append key” toggle work even after the user has edited names.
        let rundown = effectiveRundownItems

        let items: [(title: String, key: String?)] = seqs.enumerated().map { (i, seq) in
            var title = (snapshotNameEdits[seq] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = rundown.indices.contains(i) ? rundown[i].key?.trimmingCharacters(in: .whitespacesAndNewlines) : nil

            // If the current title already ends with the key suffix, strip it before reformatting,
            // so we don’t double-append (e.g. "TITLE - Bb - Bb").
            if let key, !key.isEmpty {
                let suffix = " - " + key
                if title.hasSuffix(suffix) {
                    title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            return (title: title, key: key)
        }

        let formatted = applySnapshotFormatting(to: items)

        for (i, seq) in seqs.enumerated() {
            snapshotNameEdits[seq] = formatted.indices.contains(i) ? formatted[i] : (snapshotNameEdits[seq] ?? "")
        }
    }

    private var configuredDefaultPositions: [String] {
        localPositionChannelDefaults.keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var addablePositions: [String] {
        let existing = Set(configuredDefaultPositions)
        return availablePositions.filter { !existing.contains($0) }
    }

    private var filteredAddablePositions: [String] {
        let base = addablePositions
        let q = positionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.lowercased().contains(q) }
    }

    

    private struct AssignmentRow: View, Equatable {
        let row: AssignmentRowModel
        let channelOptions: [(label: String, channel: Int)]
        let onAssign: (String, Int?) -> Void

        static func == (lhs: AssignmentRow, rhs: AssignmentRow) -> Bool {
            lhs.row == rhs.row && lhs.channelOptions.count == rhs.channelOptions.count
        }

        var body: some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.position.isEmpty ? row.title : row.position)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !row.position.isEmpty {
                        Text(row.fullName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                Text(row.formattedName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 90, alignment: .trailing)

                Picker("", selection: Binding<Int?>(
                    get: { row.assignedChannel },
                    set: { onAssign(row.title, $0) }
                )) {
                    Text("—").tag(Int?.none)
                    ForEach(channelOptions, id: \.channel) { opt in
                        Text(opt.label).tag(Optional(opt.channel))
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }

    @ViewBuilder
    private var assignmentsSection: some View {
        Divider().opacity(0.25)

        HStack {
            let assignedCount = assignmentWorkItems.count

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isAssignmentsCollapsed.toggle()
                }
                persistCollapseState()
            } label: {
                Text("Assignments" + (assignedCount > 0 ? " (\(assignedCount))" : ""))
                    .font(.caption)
                    .opacity(0.75)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAssignmentsCollapsed ? "Expand Assignments" : "Collapse Assignments")

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isAssignmentsCollapsed.toggle()
                }
                persistCollapseState()
            } label: {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .opacity(0.85)
                    .rotationEffect(.degrees(isAssignmentsCollapsed ? -90 : 0))
                    .animation(.easeInOut(duration: 0.18), value: isAssignmentsCollapsed)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAssignmentsCollapsed ? "Expand Assignments" : "Collapse Assignments")

            // Trigger binding control
            triggerBindingControl(selection: triggerSendConfig.assignmentsTriggerNodeId)

            Button {
                print("[ConsoleGraphNodeView] Assignments Send tapped: deviceId=\(device.id) assignedCount=\(assignmentWorkItems.count)")
                postSendChannelAssignmentsRequest()
            } label: {
                Label("Test", systemImage: "paperplane.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .opacity(assignedCount == 0 ? 0.35 : 1.0)
            .disabled(assignedCount == 0)
        }

        if !isAssignmentsCollapsed {
            HStack {
                Spacer()

                Button {
                    showAssignmentSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showAssignmentSettings, arrowEdge: .top) {
                    assignmentSettingsPopover
                }

                Button("Auto") { autoAssignChannels() }
                    .font(.caption2)

                Button("Clear") { clearAllAssignments() }
                    .font(.caption2)
            }
        }

        if !isAssignmentsCollapsed {
            // Keep the default light, but allow expanding to all.
            let all = cachedAssignmentRows
            let shown = showAllAssignments ? all : Array(all.prefix(24))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(shown) { row in
                        AssignmentRow(
                            row: row,
                            channelOptions: channelOptions,
                            onAssign: setChannelAssignment
                        )
                    }

                    if all.count > shown.count {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showAllAssignments = true
                            }
                        } label: {
                            Text("Show all \(all.count)…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }

                    if showAllAssignments, all.count > 24 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showAllAssignments = false
                            }
                        } label: {
                            Text("Show less")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: showAllAssignments ? 420 : 260)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
            ))
        }
    }

    @ViewBuilder
    private var snapshotsSection: some View {
        Divider().opacity(0.25)

        VStack(alignment: .leading, spacing: 10) {
            snapshotsHeaderRow

            if !isSnapshotsCollapsed {
                HStack {
                    Spacer()

                    Button {
                        showSnapshotSettings.toggle()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSnapshotSettings, arrowEdge: .top) {
                        snapshotSettingsPopover
                    }

                    Button {
                        resetSnapshotEditsFromRundown()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .opacity(buildSnapshotWorkItems().isEmpty ? 0.35 : 1.0)
                    .disabled(buildSnapshotWorkItems().isEmpty)
                }
            }

            if !isSnapshotsCollapsed {
                Group {
                    if effectiveRundownTitles.isEmpty {
                        Text("Link a Planning Center node and enter Graph mode with a captured rundown to generate snapshot names.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        // Header row
                        HStack(spacing: 10) {
                            Text("Seq")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)

                            Text("Target")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)

                            Text("Name")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)
                        }

                        // Work items
                        ForEach(buildSnapshotWorkItems(), id: \.seq) { item in
                            HStack(spacing: 10) {
                                Text("\(item.seq)")
                                    .font(.caption)
                                    .frame(width: 34, alignment: .leading)

                                // Show target index. For X32/M32, show Show Control label (1.0.1 .. 1.1 ..).
                                Group {
                                    if isX32OrM32Console {
                                        let label = x32ShowControlDisplayLabel(forLinearIndex: item.index)
                                        Text(label)
                                    } else {
                                        Text("#\(item.index)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)

                                TextField("Snapshot name", text: snapshotNameBinding(seq: item.seq, fallback: item.name))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                            }
                        }

                        if snapshotBaseOffset > 0 {
                            if isX32OrM32Console {
                                let label = x32ShowControlDisplayLabel(forLinearIndex: snapshotBaseOffset)
                                Text("Offset: starting at \(label) (#\(snapshotBaseOffset)).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Offset: starting at #\(snapshotBaseOffset).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .onAppear {
            // Seed edits once per appearance.
            if snapshotNameEdits.isEmpty {
                resetSnapshotEditsFromRundown()
            }
        }
    }

    private var nodeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !capabilityMismatchedSources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .imageScale(.small)
                        Text("Incompatible links")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Text("\(capabilityMismatchedSources.joined(separator: ", ")) \(capabilityMismatchedSources.count == 1 ? "is" : "are") linked but this console does not support the data sent. Remove the link to clear this warning.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider().opacity(0.25)
            }

            deviceHeaderRow

            if showAssignments {
                assignmentsSection
            }

            if showSnapshots {
                snapshotsSection
            }

            if showQuActions {
                quActionsSection
            }

            if showStandardActions {
                standardConsoleActionsSection
            }

            if showDigiCoActions {
                digicoActionsSection
            }
        }
    }

    @ViewBuilder
    private var quActionsSection: some View {
        Divider().opacity(0.25)

        if let consoleActionWarningText, !consoleActionWarningText.isEmpty {
            consoleActionWarningPill(text: consoleActionWarningText)
        }

        let actionsBinding = quActions

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Qu Actions")
                    .font(.caption)
                    .opacity(0.75)

                Spacer()

                Text("TRIGGER LINKED")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.22))
                    )
                    .foregroundStyle(.secondary)

                Button {
                    onTestQuActions()
                } label: {
                    if isTestingConsoleAction {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        }
                        .font(.caption2)
                    } else {
                        Label("Test", systemImage: "paperplane")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .opacity(actionsBinding.wrappedValue.isEmpty ? 0.35 : 1.0)
                .disabled(actionsBinding.wrappedValue.isEmpty || isTestingConsoleAction)

                Button {
                    addQuAction()
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Qu action")
            }

            Text("Add one or more actions to run when a Trigger node is linked to this console.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if actionsBinding.wrappedValue.isEmpty {
                Text("No actions configured yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(actionsBinding.wrappedValue.enumerated()), id: \.element.id) { index, _ in
                        quActionRow(at: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var standardConsoleActionsSection: some View {
        Divider().opacity(0.25)

        if let consoleActionWarningText, !consoleActionWarningText.isEmpty {
            consoleActionWarningPill(text: consoleActionWarningText)
        }

        let actionsBinding = standardActions

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Console Actions")
                    .font(.caption)
                    .opacity(0.75)

                Spacer()

                Text("TRIGGER LINKED")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.22))
                    )
                    .foregroundStyle(.secondary)

                Button {
                    onTestStandardActions()
                } label: {
                    if isTestingConsoleAction {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        }
                        .font(.caption2)
                    } else {
                        Label("Test", systemImage: "paperplane")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .opacity(actionsBinding.wrappedValue.isEmpty ? 0.35 : 1.0)
                .disabled(actionsBinding.wrappedValue.isEmpty || isTestingConsoleAction)

                Button {
                    addStandardAction()
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add console action")
            }

            Text("Add one or more actions to run when a Trigger node is linked to this console.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if actionsBinding.wrappedValue.isEmpty {
                Text("No actions configured yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(actionsBinding.wrappedValue.enumerated()), id: \.element.id) { index, _ in
                        standardActionRow(at: index)
                    }
                }
            }
        }
    }

    private func addStandardAction() {
        standardActions.wrappedValue.append(DashboardGraph.StandardConsoleAction())
    }

    private func removeStandardAction(at index: Int) {
        guard standardActions.wrappedValue.indices.contains(index) else { return }
        standardActions.wrappedValue.remove(at: index)
    }

    private func bindingForStandardAction(at index: Int) -> Binding<DashboardGraph.StandardConsoleAction> {
        Binding<DashboardGraph.StandardConsoleAction>(
            get: {
                guard standardActions.wrappedValue.indices.contains(index) else {
                    return DashboardGraph.StandardConsoleAction()
                }
                return standardActions.wrappedValue[index]
            },
            set: { newValue in
                guard standardActions.wrappedValue.indices.contains(index) else { return }
                standardActions.wrappedValue[index] = newValue
            }
        )
    }

    private func standardActionRow(at index: Int) -> some View {
        let actionBinding = bindingForStandardAction(at: index)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: actionBinding.kind) {
                    ForEach(DashboardGraph.StandardActionKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)

                Spacer()

                Toggle("", isOn: actionBinding.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button {
                    removeStandardAction(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove action")
            }

            switch actionBinding.wrappedValue.kind {
            case .sceneRecall:
                HStack {
                    Text("Scene").font(.caption2).foregroundStyle(.secondary)
                    TextField(scenePlaceholder, text: actionBinding.sceneNumber)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                }

            case .mute:
                HStack {
                    Text("Ch").font(.caption2).foregroundStyle(.secondary)
                    Stepper(value: actionBinding.channelIndex, in: 1...128) {
                        Text("\(actionBinding.wrappedValue.channelIndex)").font(.caption2)
                    }
                    .frame(maxWidth: 90)

                    Picker("", selection: actionBinding.muteMode) {
                        Text("On").tag(DashboardGraph.StandardMuteMode.on)
                        Text("Off").tag(DashboardGraph.StandardMuteMode.off)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 100)
                }

            case .level:
                HStack {
                    Text("Ch").font(.caption2).foregroundStyle(.secondary)
                    Stepper(value: actionBinding.channelIndex, in: 1...128) {
                        Text("\(actionBinding.wrappedValue.channelIndex)").font(.caption2)
                    }
                    .frame(maxWidth: 90)

                    Text("dB").font(.caption2).foregroundStyle(.secondary)
                    TextField("0.0", value: actionBinding.levelDb, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 70)
                }

            case .pan:
                HStack {
                    Text("Ch").font(.caption2).foregroundStyle(.secondary)
                    Stepper(value: actionBinding.channelIndex, in: 1...128) {
                        Text("\(actionBinding.wrappedValue.channelIndex)").font(.caption2)
                    }
                    .frame(maxWidth: 90)

                    Slider(value: actionBinding.panValue, in: -1.0...1.0)
                        .frame(maxWidth: 140)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Scene number format differs by console family: Yamaha uses "x.xx" (e.g. "1.00"),
    /// X32/M32 uses a plain integer. Show a console-appropriate placeholder so users
    /// don't leave the field at a format the linked console's connector will silently
    /// reject (X32's fireSnapshot handler parses this as Int and no-ops on non-numeric
    /// strings like the default "1.00").
    private var scenePlaceholder: String {
        switch device.audioConsoleModel {
        case .behringerX32, .midasM32:
            return "12"
        default:
            return "1.00"
        }
    }

    @ViewBuilder
    private var digicoActionsSection: some View {
        Divider().opacity(0.25)

        if let consoleActionWarningText, !consoleActionWarningText.isEmpty {
            consoleActionWarningPill(text: consoleActionWarningText)
        }

        let actionsBinding = digicoActions

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DiGiCo Actions")
                    .font(.caption)
                    .opacity(0.75)

                Spacer()

                Text("TRIGGER LINKED")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.22))
                    )
                    .foregroundStyle(.secondary)

                Button {
                    onTestDigiCoActions()
                } label: {
                    if isTestingConsoleAction {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        }
                        .font(.caption2)
                    } else {
                        Label("Test", systemImage: "paperplane")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .opacity(actionsBinding.wrappedValue.isEmpty ? 0.35 : 1.0)
                .disabled(actionsBinding.wrappedValue.isEmpty || isTestingConsoleAction)

                Button {
                    addDigiCoAction()
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add DiGiCo action")
            }

            Text("Add one or more actions to run when a Trigger node is linked to this console.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if actionsBinding.wrappedValue.isEmpty {
                Text("No actions configured yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(actionsBinding.wrappedValue.enumerated()), id: \.element.id) { index, _ in
                        digicoActionRow(at: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func digicoActionRow(at index: Int) -> some View {
        let actionBinding = bindingForDigiCoAction(at: index)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: actionBinding.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                if actionBinding.wrappedValue.kind != .macro {
                    Picker("Type", selection: actionBinding.channelType) {
                        ForEach(DashboardGraph.DiGiCoChannelType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .font(.caption)
                }

                Picker("Action", selection: actionBinding.kind) {
                    ForEach(DashboardGraph.DiGiCoActionKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption)

                Spacer()

                Button(role: .destructive) {
                    removeDigiCoAction(at: index)
                } label: {
                    Image(systemName: "trash")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                let isMacro = actionBinding.wrappedValue.kind == .macro
                Text(isMacro ? "Macro #:" : "Ch:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isMacro {
                    Stepper(
                        value: actionBinding.channelIndex,
                        in: 0...255
                    ) {
                        Text("\(actionBinding.wrappedValue.channelIndex)")
                            .monospacedDigit()
                            .font(.caption)
                    }
                    .controlSize(.mini)
                } else {
                    let options = digicoChannelOptions(for: actionBinding.wrappedValue.channelType)
                    if !options.isEmpty {
                        Picker("Channel", selection: actionBinding.channelIndex) {
                            ForEach(options, id: \.channel) { option in
                                Text(option.label).tag(option.channel)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .font(.caption)
                    } else {
                        Stepper(
                            value: actionBinding.channelIndex,
                            in: 1...256
                        ) {
                            Text("\(actionBinding.wrappedValue.channelIndex)")
                                .monospacedDigit()
                                .font(.caption)
                        }
                        .controlSize(.mini)
                        Text("Sync from DiGiCo to see names")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if !isMacro {
                    if actionBinding.wrappedValue.kind == .fader {
                        HStack(spacing: 4) {
                            Text("dB:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0.0", value: actionBinding.faderDb, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                                .multilineTextAlignment(.trailing)
                                .font(.caption)
                        }
                    } else {
                        Toggle(
                            actionBinding.wrappedValue.kind == .mute ? "Mute On" : "Solo On",
                            isOn: actionBinding.boolValue
                        )
                        .toggleStyle(.switch)
                        .font(.caption)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func addDigiCoAction() {
        var actions = digicoActions.wrappedValue
        actions.append(DashboardGraph.DiGiCoConsoleAction())
        digicoActions.wrappedValue = actions
    }

    private func removeDigiCoAction(at index: Int) {
        var actions = digicoActions.wrappedValue
        guard actions.indices.contains(index) else { return }
        actions.remove(at: index)
        digicoActions.wrappedValue = actions
    }

    private func bindingForDigiCoAction(at index: Int) -> Binding<DashboardGraph.DiGiCoConsoleAction> {
        Binding(
            get: {
                let actions = digicoActions.wrappedValue
                if actions.indices.contains(index) {
                    return actions[index]
                }
                return DashboardGraph.DiGiCoConsoleAction()
            },
            set: { newValue in
                var actions = digicoActions.wrappedValue
                guard actions.indices.contains(index) else { return }
                actions[index] = newValue
                digicoActions.wrappedValue = actions
            }
        )
    }

    private func addQuAction() {
        var actions = quActions.wrappedValue
        actions.append(DashboardGraph.QuConsoleAction())
        quActions.wrappedValue = actions
    }

    private func removeQuAction(at index: Int) {
        var actions = quActions.wrappedValue
        guard actions.indices.contains(index) else { return }
        actions.remove(at: index)
        quActions.wrappedValue = actions
    }

    private func bindingForQuAction(at index: Int) -> Binding<DashboardGraph.QuConsoleAction> {
        Binding(
            get: {
                let actions = quActions.wrappedValue
                if actions.indices.contains(index) {
                    return actions[index]
                }
                return DashboardGraph.QuConsoleAction()
            },
            set: { newValue in
                var actions = quActions.wrappedValue
                guard actions.indices.contains(index) else { return }
                actions[index] = newValue
                quActions.wrappedValue = actions
            }
        )
    }

    private func quMenuSelection(for action: DashboardGraph.QuConsoleAction) -> QuActionMenu {
        if action.useManualParameter {
            return .raw
        }
        switch action.kind {
        case .softKey:
            return .softKey
        case .sceneRecall:
            return .sceneRecall
        case .channelMute, .groupMute, .mixAssign:
            return .mute
        case .channelLevel, .sendLevel, .groupLevel, .fxSendLevel, .fxReturnLevel, .channelPan:
            return .level
        }
    }

    private func quDbFromValue(_ value: Int) -> Double {
        let clamped = max(0, min(16383, value))
        return quAudioTaperDb(fromValue: clamped)
    }

    private func quDbDisplay(_ value: Int) -> String {
        let db = quDbFromValue(value)
        if db <= -80.0 {
            return "-inf"
        }
        return String(format: "%.1f", db)
    }

    private func quValueFromDb(_ db: Double) -> Int {
        let clamped = max(-80.0, min(10.0, db))
        return quAudioTaperValue(fromDb: clamped)
    }

    private func quSceneBankProgram(fromScene scene: Int) -> (bank: Int, program: Int) {
        let clamped = max(1, min(300, scene))
        let bank = ((clamped - 1) / 128) + 1
        let program = ((clamped - 1) % 128) + 1
        return (bank, program)
    }

    private func quAudioTaperValue(fromDb db: Double) -> Int {
        let points = Self.quAudioTaperPoints
        guard let first = points.first, let last = points.last else { return 0 }
        if db <= -80.0 { return 0 }
        if db <= first.db { return first.value }
        if db >= last.db { return last.value }

        var lower = first
        var upper = last
        for point in points {
            if point.db <= db { lower = point }
            if point.db >= db {
                upper = point
                break
            }
        }

        if upper.db == lower.db { return lower.value }
        let t = (db - lower.db) / (upper.db - lower.db)
        let interp = Double(lower.value) + (Double(upper.value - lower.value) * t)
        return Int(round(interp))
    }

    private func quAudioTaperDb(fromValue value: Int) -> Double {
        let points = Self.quAudioTaperPoints
        guard let first = points.first, let last = points.last else { return -60.0 }
        if value <= 0 { return -80.0 }
        if value <= first.value { return first.db }
        if value >= last.value { return last.db }

        var lower = first
        var upper = last
        for point in points {
            if point.value <= value { lower = point }
            if point.value >= value {
                upper = point
                break
            }
        }

        if upper.value == lower.value { return lower.db }
        let t = Double(value - lower.value) / Double(upper.value - lower.value)
        return lower.db + (upper.db - lower.db) * t
    }

    private static let quAudioTaperPoints: [(db: Double, value: Int)] = {
        func val(_ vc: Int, _ vf: Int) -> Int { (vc << 7) + vf }
        let raw: [(Double, Int, Int)] = [
            (-80, 0x02, 0x40),
            (-75, 0x03, 0x40),
            (-70, 0x04, 0x00),
            (-65, 0x05, 0x00),
            (-60, 0x06, 0x00),
            (-55, 0x07, 0x00),
            (-50, 0x08, 0x00),
            (-45, 0x0C, 0x00),
            (-40, 0x0F, 0x40),
            (-38, 0x12, 0x40),
            (-36, 0x15, 0x40),
            (-35, 0x17, 0x00),
            (-34, 0x19, 0x00),
            (-33, 0x1A, 0x40),
            (-32, 0x1C, 0x00),
            (-31, 0x1D, 0x40),
            (-30, 0x1F, 0x00),
            (-29, 0x20, 0x40),
            (-28, 0x22, 0x00),
            (-27, 0x23, 0x40),
            (-26, 0x25, 0x00),
            (-25, 0x26, 0x40),
            (-24, 0x28, 0x40),
            (-23, 0x2A, 0x00),
            (-22, 0x2B, 0x40),
            (-21, 0x2D, 0x00),
            (-20, 0x2E, 0x40),
            (-19, 0x30, 0x40),
            (-18, 0x31, 0x40),
            (-17, 0x33, 0x40),
            (-16, 0x34, 0x40),
            (-15, 0x36, 0x40),
            (-14, 0x38, 0x40),
            (-13, 0x39, 0x40),
            (-12, 0x3B, 0x40),
            (-11, 0x3C, 0x40),
            (-10, 0x3E, 0x40),
            (-9, 0x41, 0x40),
            (-8, 0x44, 0x40),
            (-7, 0x48, 0x00),
            (-6, 0x4B, 0x00),
            (-5, 0x4E, 0x40),
            (-4, 0x52, 0x40),
            (-3, 0x56, 0x40),
            (-2, 0x5A, 0x00),
            (-1, 0x5E, 0x00),
            (0, 0x62, 0x00),
            (1, 0x65, 0x40),
            (2, 0x69, 0x00),
            (3, 0x6C, 0x40),
            (4, 0x70, 0x40),
            (5, 0x73, 0x00),
            (6, 0x75, 0x40),
            (7, 0x78, 0x00),
            (8, 0x7A, 0x40),
            (9, 0x7D, 0x00),
            (10, 0x7F, 0x40)
        ]
        return raw.map { (db, vc, vf) in (db: db, value: val(vc, vf)) }
            .sorted { $0.db < $1.db }
    }()

    private func sourceIndexRange(for kind: DashboardGraph.QuSourceKind) -> ClosedRange<Int> {
        switch kind {
        case .input:
            return 1...32
        case .fxReturn:
            return 1...6
        case .group:
            return 1...12
        case .mix:
            return 1...12
        case .dca:
            return 1...8
        case .muteGroup:
            return 1...8
        case .st1, .st2, .usb, .lr:
            return 1...1
        }
    }

    private func destinationIndexRange(for kind: DashboardGraph.QuDestinationKind) -> ClosedRange<Int> {
        switch kind {
        case .lr:
            return 1...1
        case .mix:
            return 1...12
        case .fxSend:
            return 1...4
        }
    }

    private func optionalIntBinding(_ get: @escaping () -> Int?, _ set: @escaping (Int?) -> Void) -> Binding<String> {
        Binding<String>(
            get: {
                if let v = get() { return String(v) }
                return ""
            },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    set(nil)
                    return
                }
                if let v = Int(trimmed) { set(v) }
            }
        )
    }

    @ViewBuilder
    private func quActionRow(at index: Int) -> some View {
        let actionBinding = bindingForQuAction(at: index)
        let action = actionBinding.wrappedValue

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let actionMenuBinding = Binding<QuActionMenu>(
                    get: { quMenuSelection(for: actionBinding.wrappedValue) },
                    set: { newValue in
                        switch newValue {
                        case .level:
                            actionBinding.wrappedValue.useManualParameter = false
                            actionBinding.wrappedValue.kind = .channelLevel
                        case .mute:
                            actionBinding.wrappedValue.useManualParameter = false
                            actionBinding.wrappedValue.kind = .channelMute
                        case .softKey:
                            actionBinding.wrappedValue.useManualParameter = false
                            actionBinding.wrappedValue.kind = .softKey
                        case .sceneRecall:
                            actionBinding.wrappedValue.useManualParameter = false
                            actionBinding.wrappedValue.kind = .sceneRecall
                        case .raw:
                            actionBinding.wrappedValue.useManualParameter = true
                            actionBinding.wrappedValue.kind = .channelLevel
                        }
                    }
                )

                Picker("Action", selection: actionMenuBinding) {
                    ForEach(QuActionMenu.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)

                Toggle("Enabled", isOn: actionBinding.isEnabled)
                    .toggleStyle(.switch)

                Spacer()

                Button(role: .destructive) {
                    removeQuAction(at: index)
                } label: {
                    Image(systemName: "trash")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
            }

            let isRaw = actionBinding.wrappedValue.useManualParameter

            switch action.kind {
            case .sceneRecall:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Mode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: actionBinding.sceneRecallMode) {
                            ForEach(DashboardGraph.QuSceneRecallMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    if actionBinding.wrappedValue.sceneRecallMode == .custom {
                        let bankBinding = Binding<String>(
                            get: { actionBinding.wrappedValue.bank.map { String($0) } ?? "" },
                            set: { raw in
                                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    actionBinding.wrappedValue.bank = nil
                                    return
                                }
                                if let value = Int(trimmed) {
                                    actionBinding.wrappedValue.bank = max(1, min(3, value))
                                }
                            }
                        )
                        let programBinding = Binding<String>(
                            get: { actionBinding.wrappedValue.program.map { String($0) } ?? "" },
                            set: { raw in
                                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    actionBinding.wrappedValue.program = nil
                                    return
                                }
                                if let value = Int(trimmed) {
                                    let (bank, program) = quSceneBankProgram(fromScene: value)
                                    actionBinding.wrappedValue.bank = bank
                                    actionBinding.wrappedValue.program = program
                                }
                            }
                        )
                        HStack(spacing: 10) {
                            Text("Bank")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("1", text: bankBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)

                            Text("Program")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("1", text: programBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                    }
                }

            case .softKey:
                HStack {
                    Text("Soft Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("", value: actionBinding.softKey, in: 1...16)
                        .labelsHidden()

                    Text("#\(actionBinding.wrappedValue.softKey)")
                        .font(.caption)
                }

            default:
                if isRaw {
                    HStack(spacing: 10) {
                        Text("MSB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper("", value: actionBinding.manualMSB, in: 0...127)
                            .labelsHidden()

                        Text("\(actionBinding.wrappedValue.manualMSB)")
                            .font(.caption)

                        Text("LSB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper("", value: actionBinding.manualLSB, in: 0...127)
                            .labelsHidden()

                        Text("\(actionBinding.wrappedValue.manualLSB)")
                            .font(.caption)

                        Spacer()

                        Button {
                            showRawInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .imageScale(.small)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showRawInfo, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Raw (Advanced)")
                                    .font(.headline)
                                Text("Enter the Qu NRPN parameter MSB/LSB directly. Use this when a control is not mapped by the source/destination dropdowns.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(width: 260)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Picker("Source", selection: actionBinding.sourceKind) {
                            ForEach(DashboardGraph.QuSourceKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .labelsHidden()

                        if actionBinding.wrappedValue.sourceKind != .st1 &&
                            actionBinding.wrappedValue.sourceKind != .st2 &&
                            actionBinding.wrappedValue.sourceKind != .usb &&
                            actionBinding.wrappedValue.sourceKind != .lr {
                            let sourceIndexBinding = Binding<Int>(
                                get: { actionBinding.wrappedValue.sourceIndex },
                                set: { newValue in
                                    let range = sourceIndexRange(for: actionBinding.wrappedValue.sourceKind)
                                    actionBinding.wrappedValue.sourceIndex = max(range.lowerBound, min(range.upperBound, newValue))
                                }
                            )
                            TextField("1", value: sourceIndexBinding, formatter: Self.intFormatter)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 48)
                        }
                    }

                    if action.kind != .channelMute && action.kind != .groupMute {
                        HStack(spacing: 10) {
                            Picker("Destination", selection: actionBinding.destinationKind) {
                                ForEach(DashboardGraph.QuDestinationKind.allCases, id: \.self) { kind in
                                    Text(kind.displayName).tag(kind)
                                }
                            }
                            .labelsHidden()

                            if actionBinding.wrappedValue.destinationKind != .lr {
                                let destinationIndexBinding = Binding<Int>(
                                    get: { actionBinding.wrappedValue.destinationIndex },
                                    set: { newValue in
                                        let range = destinationIndexRange(for: actionBinding.wrappedValue.destinationKind)
                                        actionBinding.wrappedValue.destinationIndex = max(range.lowerBound, min(range.upperBound, newValue))
                                    }
                                )
                                TextField("1", value: destinationIndexBinding, formatter: Self.intFormatter)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 48)
                            }
                        }
                    }
                }

                if isRaw {
                    HStack {
                        Text("Value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let rawValueBinding = Binding<Int>(
                            get: { actionBinding.wrappedValue.value },
                            set: { actionBinding.wrappedValue.value = max(0, min(16383, $0)) }
                        )
                        TextField("0-16383", value: rawValueBinding, formatter: Self.intFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)

                        Text("\(actionBinding.wrappedValue.value)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if action.kind == .channelMute || action.kind == .groupMute {
                    HStack {
                        Text("Mute")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: actionBinding.muteMode) {
                            ForEach(DashboardGraph.QuMuteMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                } else if action.kind == .mixAssign {
                    Toggle("On", isOn: actionBinding.boolValue)
                        .font(.caption)
                } else {
                    let dbBinding = Binding<Double>(
                        get: { quDbFromValue(actionBinding.wrappedValue.value) },
                        set: { actionBinding.wrappedValue.value = quValueFromDb($0) }
                    )
                    HStack {
                        Text("Level (dB)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("-inf to 10", value: dbBinding, formatter: Self.quDbFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)

                        Text(quDbDisplay(actionBinding.wrappedValue.value))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(actionBinding.wrappedValue.value)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .fill(Color.white.opacity(GraphNodeStyleTokens.subtleFillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .stroke(Color.white.opacity(GraphNodeStyleTokens.subtleBorderOpacity), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
        )
    }

    @ViewBuilder
    private func applyNodeGesture<Content: View>(_ content: Content) -> some View {
    #if os(macOS)
        content
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        // Use the current NSEvent clickCount so we don't delay/consume single-click selection.
                        // This keeps tap-to-select and tap-off-to-unselect behavior intact.
                        if let event = NSApp.currentEvent, event.clickCount == 2 {
                            NotificationCenter.default.post(name: .prodlinkOpenExternalDeviceSettings, object: device.id)
                        }
                    }
            )
    #else
        content
    #endif
    }

    private var nodeView: some View {
        let base = GraphNodeChromeContainer(
            contentPadding: 12,
            tint: destinationCategory.tintColor,
            border: destinationCategory.borderColor,
            isSelected: false,
            isHoverReceiver: false
        ) {
            nodeContent
        }
        .contentShape(RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius))

        let gestured = applyNodeGesture(base)

        return applyNodeLifecycle(gestured)
    }

    private func applyNodeLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                    // Keep local UI state in sync with the incoming device config.
                    nameFormatSelection = normalizedNameFormat(device.consoleNameFormat)
                    nameCasingSelection = normalizedNameCasing(device.consoleNameCasing)
                    snapshotCasingSelection = device.consoleSnapshotNameCasing
                    snapshotShortenEnabledSelection = device.consoleSnapshotShortenEnabled
                    snapshotShortenLimitSelection = max(6, device.consoleSnapshotShortenLimit)
                    // No persisted device field yet; default off.
                    snapshotAppendKeySelection = false
                    syncLocalConsoleChannelAssignments()
                    syncLocalPositionDefaults()
                    showSnapshotSettings = false
                    showAssignmentSettings = false
                    showAddPositionPopover = false
                    rebuildPeopleCaches()
                    rebuildChannelOptions()
                }
            .onChange(of: device.consoleSnapshotNameCasing, initial: false) { _, newValue in
                snapshotCasingSelection = newValue
            }
            .onChange(of: device.consoleSnapshotShortenEnabled, initial: false) { _, newValue in
                snapshotShortenEnabledSelection = newValue
            }
            .onChange(of: device.consoleSnapshotShortenLimit, initial: false) { _, newValue in
                snapshotShortenLimitSelection = max(6, newValue)
            }
            .onChange(of: people, initial: false) { _, _ in
                rebuildPeopleCaches()
            }
            .onChange(of: device.consoleChannelAssignments, initial: false) { _, _ in
                syncLocalConsoleChannelAssignments()
                rebuildAssignmentCaches()
            }
            .onChange(of: device.consoleNameFormat, initial: false) { _, _ in
                nameFormatSelection = normalizedNameFormat(device.consoleNameFormat)
                rebuildAssignmentCaches()
            }
            .onChange(of: device.consoleNameCasing, initial: false) { _, _ in
                nameCasingSelection = normalizedNameCasing(device.consoleNameCasing)
                rebuildAssignmentCaches()
            }
            .onChange(of: device.digicoInputChannels, initial: false) { _, _ in
                rebuildChannelOptions()
            }
            .onChange(of: device.digicoDiscoveredChannels, initial: false) { _, _ in
                // digicoChannelOptions is computed on demand — no cache to invalidate
            }
            .onChange(of: device.consoleModelIdentifier, initial: false) { _, _ in
                rebuildChannelOptions()
            }
            .onChange(of: device.consolePositionChannelDefaults, initial: false) { _, _ in
                syncLocalPositionDefaults()
            }
            .onChange(of: snapshotCasingSelection, initial: false) { _, _ in
                if snapshotNameEdits.isEmpty {
                    resetSnapshotEditsFromRundown()
                } else {
                    reformatExistingSnapshotEdits()
                }
            }
            .onChange(of: snapshotShortenEnabledSelection, initial: false) { _, newValue in
                if newValue == false {
                    resetSnapshotEditsFromRundown()
                } else {
                    if snapshotNameEdits.isEmpty {
                        resetSnapshotEditsFromRundown()
                    } else {
                        reformatExistingSnapshotEdits()
                    }
                }
            }
            .onChange(of: snapshotShortenLimitSelection, initial: false) { _, _ in
                if snapshotNameEdits.isEmpty {
                    resetSnapshotEditsFromRundown()
                } else {
                    reformatExistingSnapshotEdits()
                }
            }
            .onChange(of: snapshotAppendKeySelection, initial: false) { _, _ in
                if snapshotNameEdits.isEmpty {
                    resetSnapshotEditsFromRundown()
                } else {
                    reformatExistingSnapshotEdits()
                }
            }
            .onChange(of: snapshotNameEdits, initial: false) { _, newValue in
                    snapshotEditsDebounceWork?.cancel()
                    let work = DispatchWorkItem {
                        // Broadcast per-console snapshot name edits so Send-All can match the destination node list
                        // even when running from Canvas mode.
                        NotificationCenter.default.post(
                            name: .prodlinkConsoleSnapshotEditsDidChange,
                            object: nil,
                            userInfo: [
                                ConsoleSnapshotEditsUserInfoKeys.deviceId: device.id,
                                ConsoleSnapshotEditsUserInfoKeys.edits: newValue
                            ]
                        )
                    }
                    snapshotEditsDebounceWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                }
    }

    var body: some View {
        nodeView
            .onAppear {
                // Restore collapse states from the graph layout model so they survive mode switches.
                if let layout = graph?.tileLayouts[nodeId] {
                    isAssignmentsCollapsed = layout.collapsed
                    isSnapshotsCollapsed = layout.collapsedSnapshots
                }
            }
    }

    private func persistCollapseState() {
        if var g = graph {
            if g.tileLayouts[nodeId] != nil {
                g.tileLayouts[nodeId]!.collapsed = isAssignmentsCollapsed
                g.tileLayouts[nodeId]!.collapsedSnapshots = isSnapshotsCollapsed
            } else {
                g.tileLayouts[nodeId] = TileGraphLayout(
                    collapsed: isAssignmentsCollapsed,
                    collapsedSnapshots: isSnapshotsCollapsed
                )
            }
            graph = g
        }
    }
}

// MARK: - Allowed source group keys for console links

/// Allowed source group keys for linking to Console destination nodes.
let allowedSourceGroupKeysForConsoleDestinations: Set<String> = [
    "moduleGroup.person",
    "moduleGroup.pco",
    "moduleGroup.transcription",
    "moduleGroup.oscSend",
    "moduleGroup.oscReceive",
    "moduleGroup.midiReceive",
    "moduleGroup.time",
    "moduleGroup.shure",
    "moduleGroup.sennheiser"
]

// Back-compat alias (other files may still refer to the old constant name)
let allowedSenderGroupKeysForConsole = allowedSourceGroupKeysForConsoleDestinations
