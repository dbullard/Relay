import SwiftUI
import Combine

struct ShureOverviewModuleConfig: Codable, Equatable {
    enum DefaultTab: String, Codable, CaseIterable, Identifiable {
        case auto
        case mics
        case iems
        var id: String { rawValue }
    }

    enum SortOrder: String, Codable, CaseIterable, Identifiable {
        case severity
        case deviceChannel
        case name
        case battery
        case rf
        var id: String { rawValue }
    }

    enum DeviceScope: String, Codable, CaseIterable, Identifiable {
        case allShureDevices
        case selectedDevices
        var id: String { rawValue }
    }

    enum CardSize: String, Codable, CaseIterable, Identifiable {
        case small; case medium; case large
        var id: String { rawValue }
    }

    enum DisplayStyle: String, Codable, CaseIterable, Identifiable {
        case list; case cards
        var id: String { rawValue }
    }

    var deviceScope: DeviceScope = .allShureDevices
    var selectedDeviceIDs: Set<UUID> = []
    var defaultTab: DefaultTab = .auto
    var lowBatteryWarningPercent: Int = 30
    var criticalBatteryPercent: Int = 15
    var lowRFWarningThreshold: Int = 2
    var criticalRFThreshold: Int = 1
    var staleTelemetryTimeoutSeconds: Double = 8
    var hideOfflineChannels: Bool = false
    var showFrequency: Bool = true
    var showDeviceName: Bool = true
    var audioActivityMode: ShureOverviewAudioActivityMode = .signalLight
    var showSummaryStatusChips: Bool = true
    var showChannelStatusPill: Bool = true
    var showLastUpdatedTimestamp: Bool = false
    var sortOrder: SortOrder = .severity
    var cardSize: CardSize = .medium
    var displayStyle: DisplayStyle = .list
    var channelPersonAssignments: [String: String] = [:]
    var customChannelNames: [String: String] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case deviceScope, selectedDeviceIDs, defaultTab, lowBatteryWarningPercent, criticalBatteryPercent
        case lowRFWarningThreshold, criticalRFThreshold, staleTelemetryTimeoutSeconds, hideOfflineChannels
        case showFrequency, showDeviceName, audioActivityMode, showSummaryStatusChips
        case showChannelStatusPill, sortOrder, cardSize, displayStyle, channelPersonAssignments, customChannelNames
        case showLastUpdatedTimestamp
    }

    /// Kept separate from `CodingKeys` so the automatically synthesized `encode(to:)`
    /// (which requires every `CodingKeys` case to map to a stored property) still works —
    /// `showAudioMeter` no longer has a corresponding property, it only exists for decoding
    /// legacy saved dashboards.
    private enum LegacyCodingKeys: String, CodingKey {
        case showAudioMeter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceScope = try container.decodeIfPresent(DeviceScope.self, forKey: .deviceScope) ?? .allShureDevices
        selectedDeviceIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .selectedDeviceIDs) ?? []
        defaultTab = try container.decodeIfPresent(DefaultTab.self, forKey: .defaultTab) ?? .auto
        lowBatteryWarningPercent = try container.decodeIfPresent(Int.self, forKey: .lowBatteryWarningPercent) ?? 30
        criticalBatteryPercent = try container.decodeIfPresent(Int.self, forKey: .criticalBatteryPercent) ?? 15
        lowRFWarningThreshold = try container.decodeIfPresent(Int.self, forKey: .lowRFWarningThreshold) ?? 2
        criticalRFThreshold = try container.decodeIfPresent(Int.self, forKey: .criticalRFThreshold) ?? 1
        staleTelemetryTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .staleTelemetryTimeoutSeconds) ?? 8
        hideOfflineChannels = try container.decodeIfPresent(Bool.self, forKey: .hideOfflineChannels) ?? false
        showFrequency = try container.decodeIfPresent(Bool.self, forKey: .showFrequency) ?? true
        showDeviceName = try container.decodeIfPresent(Bool.self, forKey: .showDeviceName) ?? true
        if let mode = try container.decodeIfPresent(ShureOverviewAudioActivityMode.self, forKey: .audioActivityMode) {
            audioActivityMode = mode
        } else {
            let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
            if let legacyShowAudioMeter = try legacyContainer.decodeIfPresent(Bool.self, forKey: .showAudioMeter) {
                audioActivityMode = legacyShowAudioMeter ? .signalLight : .off
            } else {
                audioActivityMode = .signalLight
            }
        }
        showSummaryStatusChips = try container.decodeIfPresent(Bool.self, forKey: .showSummaryStatusChips) ?? true
        showChannelStatusPill = try container.decodeIfPresent(Bool.self, forKey: .showChannelStatusPill) ?? true
        showLastUpdatedTimestamp = try container.decodeIfPresent(Bool.self, forKey: .showLastUpdatedTimestamp) ?? false
        sortOrder = try container.decodeIfPresent(SortOrder.self, forKey: .sortOrder) ?? .severity
        cardSize = try container.decodeIfPresent(CardSize.self, forKey: .cardSize) ?? .medium
        displayStyle = try container.decodeIfPresent(DisplayStyle.self, forKey: .displayStyle) ?? .list
        channelPersonAssignments = try container.decodeIfPresent([String: String].self, forKey: .channelPersonAssignments) ?? [:]
        customChannelNames = try container.decodeIfPresent([String: String].self, forKey: .customChannelNames) ?? [:]
    }

    static func `default`() -> ShureOverviewModuleConfig {
        ShureOverviewModuleConfig()
    }
}

enum ShureOverviewSeverity: Int {
    case healthy = 0
    case warning = 1
    case critical = 2
}

struct ShureOverviewChannelSnapshot: Identifiable, Equatable {
    let stableID: String
    let deviceID: UUID
    let deviceSortIndex: Int
    let deviceName: String
    let channelIndex: Int
    let userAssignedName: String?
    let discoveredName: String?
    let fallbackName: String
    let displayName: String
    let normalizedSortName: String
    let kind: ShureOverviewChannelKind
    let frequency: String?
    let batteryPercent: Int?
    let rfBars: Int?
    let audioBucket: Int
    let audioOverload: Bool
    let transmitterState: ShureTelemetryTransmitterState
    let transmitterPresent: Bool?
    let isConnected: Bool
    let isReconnecting: Bool
    let lastTelemetry: Date?
    let isSyncing: Bool
    let isStale: Bool
    let isOffline: Bool
    let warningReasons: [String]
    let severity: ShureOverviewSeverity
    let assignedPersonName: String?

    var id: String { stableID }
}

private func shureOverviewAssignmentKey(deviceName: String, channelIndex: Int) -> String {
    let normalizedDevice = deviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return "device:\(normalizedDevice):channel:\(channelIndex)"
}

/// Per-`ShureOverviewModuleView` instance derivation layer. Subscribes to
/// `ShureOverviewHub.shared.rawChannels` and applies this tile's
/// `ShureOverviewModuleConfig` (device scope/selection, thresholds, sort
/// order, hide-offline) to produce the final `[ShureOverviewChannelSnapshot]`
/// the view renders. This work is O(channels) (~20-30 elements) and runs at
/// most once per hub recompute.
@MainActor
final class ShureOverviewViewModel: ObservableObject {
    @Published private(set) var channels: [ShureOverviewChannelSnapshot] = []
    @Published private(set) var mics: [ShureOverviewChannelSnapshot] = []
    @Published private(set) var iems: [ShureOverviewChannelSnapshot] = []
    @Published private(set) var onlineCount: Int = 0
    @Published private(set) var warningCount: Int = 0
    @Published private(set) var criticalCount: Int = 0
    @Published private(set) var staleCount: Int = 0
    @Published private(set) var lastUpdated: Date?

    private let hub: ShureOverviewHub
    private var token: AnyCancellable?
    private var config: ShureOverviewModuleConfig = .default()

    init(hub: ShureOverviewHub? = nil) {
        self.hub = hub ?? .shared
        token = self.hub.$rawChannels.sink { [weak self] rawChannels in
            self?.recompute(rawChannels: rawChannels)
        }
    }

    func updateConfig(_ newConfig: ShureOverviewModuleConfig) {
        guard config != newConfig else { return }
        config = newConfig
        recompute(rawChannels: hub.rawChannels)
    }

    private func recompute(rawChannels: [ShureOverviewRawChannel]) {
        let now = Date()
        let store = ExternalDevicesStore.shared
        let devices = store.devices.filter { $0.kind == .shureWireless }
        let selectedDevices: [ExternalDeviceConfig]
        if config.deviceScope == .selectedDevices {
            selectedDevices = devices.filter { config.selectedDeviceIDs.contains($0.id) }
        } else {
            selectedDevices = devices
        }
        let deviceSortIndices = Dictionary(
            uniqueKeysWithValues: selectedDevices.enumerated().map { ($0.element.id, $0.offset) }
        )
        let selectedDeviceIDs = Set(selectedDevices.map(\.id))

        var built: [ShureOverviewChannelSnapshot] = []
        for raw in rawChannels where selectedDeviceIDs.contains(raw.deviceID) {
            let transmitterOff = raw.isTransmitterOff
            let lastTelemetry = raw.lastTelemetry
            let baseWarmupActive = raw.isWarmupActive
            let stale = transmitterOff
                ? false
                : (baseWarmupActive
                    ? false
                    : (lastTelemetry.map { now.timeIntervalSince($0) > config.staleTelemetryTimeoutSeconds } ?? true))
            let battery = raw.batteryPercent
            let rf = raw.rfBars
            let hasLiveTelemetryEvidence =
                battery != nil
                || rf != nil
                || raw.audioBucket > 0
                || raw.transmitterState != .unknown
                || lastTelemetry != nil

            var reasons: [String] = []
            var severity: ShureOverviewSeverity = .healthy
            let offline = !raw.isConnected
            let warmupActive = baseWarmupActive || (!offline && !transmitterOff && !hasLiveTelemetryEvidence)
            // Presence resolution takes time (up to the full 12s Axient
            // positive-evidence hold) to positively conclude a transmitter
            // is .off, but its RF signal collapses almost immediately when
            // it's powered down. In that gap, transmitterState sits at
            // .unknown -- not yet .off -- so gating these checks on "not
            // confirmed off" let a normal power-off read as a genuine RF
            // critical warning for a few seconds before presence caught
            // up. Requiring a positive .on confirmation instead means a
            // mic that's ambiguous (possibly powering off, possibly just
            // hasn't reported yet) doesn't get flagged as critical until
            // we're actually confident it's on.
            let transmitterConfirmedOn = raw.transmitterState == .on

            if offline { reasons.append("Offline") }
            if stale, !transmitterOff { reasons.append("Stale") }
            if !warmupActive, transmitterConfirmedOn, !offline, let battery, battery <= config.criticalBatteryPercent {
                reasons.append("Battery critical")
            } else if !warmupActive, transmitterConfirmedOn, !offline, let battery, battery <= config.lowBatteryWarningPercent {
                reasons.append("Battery low")
            }
            if !warmupActive, transmitterConfirmedOn, !offline, let rf, rf <= config.criticalRFThreshold {
                reasons.append("RF critical")
            } else if !warmupActive, transmitterConfirmedOn, !offline, let rf, rf <= config.lowRFWarningThreshold {
                reasons.append("RF low")
            }

            if offline {
                severity = .critical
            } else if transmitterOff {
                severity = .healthy
            } else if reasons.contains(where: { $0 == "Battery critical" || $0 == "RF critical" }) {
                severity = .critical
            } else if !reasons.isEmpty {
                severity = .warning
            }

            if config.hideOfflineChannels && offline { continue }

            let assignmentKey = shureOverviewAssignmentKey(deviceName: raw.deviceName, channelIndex: raw.channelIndex)
            let assignment = config.channelPersonAssignments[assignmentKey]
                ?? config.channelPersonAssignments[raw.id]
            let assignedPersonName = assignment == "__custom__"
                ? (config.customChannelNames[assignmentKey] ?? config.customChannelNames[raw.id])
                : assignment
            let resolvedDisplayName: String
            if let person = assignedPersonName {
                resolvedDisplayName = person
            } else {
                resolvedDisplayName = raw.displayName
            }
            let resolvedNormalizedSortName = resolvedDisplayName
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            built.append(
                ShureOverviewChannelSnapshot(
                    stableID: raw.id,
                    deviceID: raw.deviceID,
                    deviceSortIndex: deviceSortIndices[raw.deviceID] ?? Int.max,
                    deviceName: raw.deviceName,
                    channelIndex: raw.channelIndex,
                    userAssignedName: raw.userAssignedName,
                    discoveredName: raw.discoveredName,
                    fallbackName: raw.fallbackName,
                    displayName: resolvedDisplayName,
                    normalizedSortName: resolvedNormalizedSortName,
                    kind: raw.kind,
                    frequency: raw.frequency,
                    batteryPercent: battery,
                    rfBars: rf,
                    audioBucket: raw.audioBucket,
                    audioOverload: raw.audioOverload,
                    transmitterState: raw.transmitterState,
                    transmitterPresent: raw.transmitterPresent,
                    isConnected: raw.isConnected,
                    isReconnecting: raw.isReconnecting,
                    lastTelemetry: lastTelemetry,
                    isSyncing: warmupActive && !offline && !transmitterOff,
                    isStale: stale,
                    isOffline: offline,
                    warningReasons: reasons,
                    severity: severity,
                    assignedPersonName: assignedPersonName
                )
            )
        }

        let sorted = sort(channels: built, order: config.sortOrder)
        channels = sorted
        // Derive the per-tab partitions and summary counts once here, off the
        // render path. Computing these in the view's `body` meant six O(n)
        // filters re-ran on every body pass (including the 1Hz blink clock).
        mics = sorted.filter { $0.kind == .mic }
        iems = sorted.filter { $0.kind == .iem }
        onlineCount = sorted.filter { !$0.isOffline }.count
        warningCount = sorted.filter { $0.severity == .warning }.count
        criticalCount = sorted.filter { $0.severity == .critical }.count
        staleCount = sorted.filter { ($0.isOffline || $0.isStale) && $0.transmitterState != .off }.count
        lastUpdated = hub.lastUpdated
    }

    private func naturalNameAscending(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func stableTieBreakKey(for channel: ShureOverviewChannelSnapshot) -> (Int, Int, String) {
        (channel.deviceSortIndex, channel.channelIndex, channel.deviceID.uuidString)
    }

    private func severitySortRank(for channel: ShureOverviewChannelSnapshot) -> Int {
        if channel.transmitterState == .off {
            return 4
        }
        if channel.severity == .critical {
            return 0
        }
        if channel.severity == .warning, !channel.isStale, !channel.isOffline {
            return 1
        }
        if channel.isOffline || channel.isStale {
            return 2
        }
        return 3
    }

    private func sort(channels: [ShureOverviewChannelSnapshot], order: ShureOverviewModuleConfig.SortOrder) -> [ShureOverviewChannelSnapshot] {
        switch order {
        case .severity:
            return channels.sorted {
                let lhsRank = severitySortRank(for: $0)
                let rhsRank = severitySortRank(for: $1)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if $0.normalizedSortName != $1.normalizedSortName {
                    return naturalNameAscending($0.normalizedSortName, $1.normalizedSortName)
                }
                return stableTieBreakKey(for: $0) < stableTieBreakKey(for: $1)
            }
        case .deviceChannel:
            return channels.sorted {
                if $0.deviceSortIndex != $1.deviceSortIndex {
                    return $0.deviceSortIndex < $1.deviceSortIndex
                }
                if $0.channelIndex != $1.channelIndex {
                    return $0.channelIndex < $1.channelIndex
                }
                return $0.deviceID.uuidString < $1.deviceID.uuidString
            }
        case .name:
            return channels.sorted {
                if $0.normalizedSortName != $1.normalizedSortName {
                    return naturalNameAscending($0.normalizedSortName, $1.normalizedSortName)
                }
                return stableTieBreakKey(for: $0) < stableTieBreakKey(for: $1)
            }
        case .battery:
            return channels.sorted {
                let lhsRank = severitySortRank(for: $0)
                let rhsRank = severitySortRank(for: $1)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                let lhsValue = $0.batteryPercent ?? Int.max
                let rhsValue = $1.batteryPercent ?? Int.max
                if lhsValue != rhsValue {
                    return lhsValue < rhsValue
                }
                return stableTieBreakKey(for: $0) < stableTieBreakKey(for: $1)
            }
        case .rf:
            return channels.sorted {
                let lhsRank = severitySortRank(for: $0)
                let rhsRank = severitySortRank(for: $1)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                let lhsValue = $0.rfBars ?? Int.max
                let rhsValue = $1.rfBars ?? Int.max
                if lhsValue != rhsValue {
                    return lhsValue < rhsValue
                }
                return stableTieBreakKey(for: $0) < stableTieBreakKey(for: $1)
            }
        }
    }
}

struct ShureOverviewModuleView: View {
    private let cardSpacing: CGFloat = 8

    private var compactCardHeight: CGFloat {
        switch config.cardSize {
        case .small:  return 144
        case .medium: return 160
        case .large:  return 200
        }
    }

    private var compactCardWidthRange: ClosedRange<CGFloat> {
        switch config.cardSize {
        case .small:  return 140...180
        case .medium: return 180...240
        case .large:  return 240...320
        }
    }

    @Binding var config: ShureOverviewModuleConfig
    var isLiveMode: Bool = false
    @StateObject private var viewModel = ShureOverviewViewModel()
    // Deliberately NOT an @ObservedObject: observing the hub here re-rendered
    // the entire module body (six filters + every card) on every hub change,
    // including the 1Hz blink toggle. The view model drives data updates; the
    // blink border observes the hub in its own tiny subview instead.
    private let hub = ShureOverviewHub.shared
    @State private var instanceID = UUID()
    @State private var selectedTab: ShureOverviewChannelKind = .mic
    @AppStorage("dashboard_live_mode_enabled") private var liveModeEnabled: Bool = false
    @Environment(\.tileTextFormatting) private var tileTextFormatting

    private var effectiveLiveMode: Bool {
        isLiveMode || liveModeEnabled
    }

    private var channels: [ShureOverviewChannelSnapshot] { viewModel.channels }
    private var mics: [ShureOverviewChannelSnapshot] { viewModel.mics }
    private var iems: [ShureOverviewChannelSnapshot] { viewModel.iems }
    private var onlineCount: Int { viewModel.onlineCount }
    private var warningCount: Int { viewModel.warningCount }
    private var criticalCount: Int { viewModel.criticalCount }
    private var staleCount: Int { viewModel.staleCount }

    var body: some View {
        Group {
            if config.displayStyle == .cards {
                VStack(alignment: .leading, spacing: 8) {
                    ShureOverviewStrainBanner(hub: hub, mode: config.audioActivityMode) {
                        config.audioActivityMode = .signalLight
                    }
                    controlsColumn
                    if selectedRows.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        GeometryReader { proxy in
                            ScrollView {
                                LazyVGrid(
                                    columns: horizontalGridColumns(for: proxy.size.width),
                                    alignment: .leading,
                                    spacing: cardSpacing
                                ) {
                                    ForEach(selectedRows) { row in
                                        channelRow(row: row, compact: true)
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ShureOverviewStrainBanner(hub: hub, mode: config.audioActivityMode) {
                        config.audioActivityMode = .signalLight
                    }
                    controlsColumn

                    if selectedRows.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: cardSpacing) {
                                ForEach(selectedRows) { row in
                                    channelRow(row: row, compact: false)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .allowsHitTesting(effectiveLiveMode)
        .onAppear {
            selectedTab = resolveDefaultTab()
            hub.registerInstance(instanceID)
            viewModel.updateConfig(config)
            hub.setInstanceLiveMode(instanceID, enabled: effectiveLiveMode)
            hub.setInstanceAudioMode(instanceID, mode: config.audioActivityMode)
        }
        .onDisappear {
            hub.unregisterInstance(instanceID)
        }
        .onChange(of: config, initial: false) { _, newValue in
            viewModel.updateConfig(newValue)
            hub.setInstanceAudioMode(instanceID, mode: newValue.audioActivityMode)
        }
        .onChange(of: isLiveMode, initial: true) { _, newValue in
            hub.setInstanceLiveMode(instanceID, enabled: newValue || liveModeEnabled)
        }
        .onChange(of: liveModeEnabled, initial: false) { _, newValue in
            hub.setInstanceLiveMode(instanceID, enabled: newValue || isLiveMode)
        }
    }

    private var selectedRows: [ShureOverviewChannelSnapshot] {
        selectedTab == .mic ? mics : iems
    }

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryBar
            HStack(spacing: 8) {
                tabButton(kind: .mic, label: "Mics", systemImage: "mic.fill", count: mics.count)
                tabButton(kind: .iem, label: "IEMs", systemImage: "wave.3.right", count: iems.count)
            }
            .padding(4)
            .background(primaryTextColor.opacity(0.06), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(primaryTextColor.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func resolveDefaultTab() -> ShureOverviewChannelKind {
        switch config.defaultTab {
        case .mics: return .mic
        case .iems: return .iem
        case .auto:
            if !mics.isEmpty { return .mic }
            if !iems.isEmpty { return .iem }
            return .mic
        }
    }

    private var summaryBar: some View {
        return Group {
            if !effectiveLiveMode {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle")
                    Text("Live data paused")
                    Spacer(minLength: 0)
                }
                .font(detailFont)
                .foregroundStyle(secondaryTextColor)
            } else if config.displayStyle == .cards {
                HStack(spacing: 8) {
                    if config.showSummaryStatusChips {
                        statusChip(label: "Online", count: onlineCount, tint: .green)
                        statusChip(label: "Warn", count: warningCount, tint: .yellow)
                        statusChip(label: "Critical", count: criticalCount, tint: .red)
                        if staleCount > 0 {
                            statusChip(label: "Stale", count: staleCount, tint: .orange)
                        }
                    }
                    Spacer(minLength: 0)
                    if config.showLastUpdatedTimestamp, let last = viewModel.lastUpdated {
                        HStack(spacing: 4) {
                            Image(systemName: staleCount > 0 ? "clock.badge.exclamationmark" : "clock")
                            Text(last, style: .relative)
                        }
                        .font(detailFont)
                        .foregroundStyle(secondaryTextColor)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    if config.showSummaryStatusChips {
                        statusChip(label: "Online", count: onlineCount, tint: .green)
                        statusChip(label: "Warn", count: warningCount, tint: .yellow)
                        statusChip(label: "Critical", count: criticalCount, tint: .red)
                        if staleCount > 0 {
                            statusChip(label: "Stale", count: staleCount, tint: .orange)
                        }
                    }
                    Spacer()
                    if config.showLastUpdatedTimestamp, let last = viewModel.lastUpdated {
                        HStack(spacing: 4) {
                            Image(systemName: staleCount > 0 ? "clock.badge.exclamationmark" : "clock")
                            Text(last, style: .relative)
                        }
                            .font(detailFont)
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if channels.isEmpty {
            Text("No Shure devices configured")
                .font(summaryFont)
                .foregroundStyle(secondaryTextColor)
        } else if selectedTab == .iem {
            Text("No Shure IEM transmitters found in External Devices.")
                .font(summaryFont)
                .foregroundStyle(secondaryTextColor)
        } else {
            Text("Waiting for telemetry")
                .font(summaryFont)
                .foregroundStyle(secondaryTextColor)
        }
    }

    private func channelRow(row: ShureOverviewChannelSnapshot, compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName)
                            .font(titleFont.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)
                        if row.assignedPersonName != nil {
                            let channelLabel = row.discoveredName ?? row.userAssignedName
                            let parts = [channelLabel, config.showDeviceName ? row.deviceName : nil]
                                .compactMap { $0 }
                            if !parts.isEmpty {
                                Text(parts.joined(separator: " · "))
                                    .font(detailFont)
                                    .foregroundStyle(secondaryTextColor)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if config.showDeviceName {
                            Text(row.deviceName)
                                .font(detailFont)
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minHeight: 34, alignment: .topLeading)

                    if config.showFrequency {
                        metricLabel(value: displayedFrequency(for: row) ?? "—")
                            .font(detailFont.monospacedDigit())
                            .foregroundStyle(primaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 16, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        metricChip(
                            title: "Battery",
                            value: displayedBattery(for: row) ?? "—",
                            tint: batteryTint(for: row)
                        )
                        metricChip(
                            icon: "antenna.radiowaves.left.and.right",
                            value: displayedRF(for: row) ?? "—",
                            tint: rfTint(for: row)
                        )
                        Spacer(minLength: 0)
                    }
                    .frame(height: 18, alignment: .leading)

                    if config.audioActivityMode != .off {
                        audioMeter(for: row, compact: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 8, alignment: .leading)
                    }

                    if config.showChannelStatusPill {
                        HStack {
                            statusPill(row)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 18, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                            .frame(height: 18, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: compactCardHeight, maxHeight: compactCardHeight, alignment: .topLeading)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName)
                            .font(titleFont.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(1)
                        if row.assignedPersonName != nil {
                            let parts = [row.discoveredName ?? row.userAssignedName, config.showDeviceName ? row.deviceName : nil]
                                .compactMap { $0 }
                            if !parts.isEmpty {
                                Text(parts.joined(separator: " · "))
                                    .font(detailFont)
                                    .foregroundStyle(secondaryTextColor)
                                    .lineLimit(1)
                            }
                        } else if config.showDeviceName {
                            Text(row.deviceName)
                                .font(detailFont)
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if config.showFrequency, let freq = row.frequency {
                        Text(displayedFrequency(for: row, preferPlaceholderWhenNil: false) ?? freq)
                            .font(detailFont.monospacedDigit())
                            .foregroundStyle(primaryTextColor)
                    }
                    Text(displayedBattery(for: row, preferPlaceholderWhenNil: false) ?? "—")
                        .font(detailFont)
                        .foregroundStyle(batteryTint(for: row))
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(displayedRF(for: row, preferPlaceholderWhenNil: false) ?? "—")
                    }
                    .font(detailFont)
                    .foregroundStyle(rfTint(for: row))
                    if config.audioActivityMode != .off {
                        audioMeter(for: row, compact: false)
                    }
                    if config.showChannelStatusPill {
                        statusPill(row)
                    }
                }
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alertOverlay(for: row))
    }

    private func statusPill(_ row: ShureOverviewChannelSnapshot) -> some View {
        if !effectiveLiveMode {
            return Text("Paused")
                .font(detailFont.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(secondaryTextColor.opacity(0.2), in: Capsule())
        }

        let label: String
        let color: Color
        let useSolidFill: Bool
        if row.isOffline, row.isReconnecting { label = "Reconnecting"; color = .orange }
        else if row.isOffline { label = "Offline"; color = .red }
        else if row.transmitterState == .off { label = "Off"; color = secondaryTextColor }
        else if row.isSyncing { label = "Syncing"; color = .blue }
        else if row.isStale { label = "Stale"; color = .orange }
        else if row.warningReasons.contains("Battery critical") || row.warningReasons.contains("RF critical") { label = "Critical"; color = .red }
        else if row.warningReasons.contains("Battery low") || row.warningReasons.contains("RF low") { label = "Warning"; color = .yellow }
        else if row.transmitterState == .on { label = "On"; color = .green }
        else { label = "Live"; color = .green }

        useSolidFill =
            row.warningReasons.contains("Battery critical")
            || row.warningReasons.contains("RF critical")
            || row.transmitterState == .on

        return Text(label)
            .font(detailFont.weight(.semibold))
            .foregroundStyle(useSolidFill ? Color.white : primaryTextColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((useSolidFill ? color : color.opacity(0.2)), in: Capsule())
    }

    private func tabButton(kind: ShureOverviewChannelKind, label: String, systemImage: String, count: Int) -> some View {
        let isSelected = selectedTab == kind
        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedTab = kind
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(detailFont.weight(.semibold))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(primaryTextColor.opacity(isSelected ? 0.16 : 0.08), in: Capsule())
            }
            .foregroundStyle(isSelected ? primaryTextColor : secondaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                Capsule()
                    .fill(isSelected ? primaryTextColor.opacity(0.12) : primaryTextColor.opacity(0.0001))
            )
            .overlay(
                Capsule()
                    .strokeBorder(primaryTextColor.opacity(isSelected ? 0.22 : 0.08), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }

    private func statusChip(label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tint.opacity(0.18), in: Capsule())
        }
        .font(detailFont.weight(.semibold))
        .foregroundStyle(count > 0 ? tint : secondaryTextColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(primaryTextColor.opacity(0.05), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(primaryTextColor.opacity(0.1), lineWidth: 1)
        )
    }

    private func metricChip(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .foregroundStyle(tint)
        }
        .font(detailFont.weight(.semibold))
    }

    private func metricChip(icon: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .foregroundStyle(tint)
        }
        .font(detailFont.weight(.semibold))
    }

    private func metricLabel(value: String) -> some View {
        Text(value)
            .lineLimit(1)
    }

    private static let audioMeterSegmentCount = ShureOverviewAudioBucket.segmentCount

    @ViewBuilder
    private func audioMeter(for row: ShureOverviewChannelSnapshot, compact: Bool) -> some View {
        switch ShureOverviewAudioIndicator.indicator(
            mode: config.audioActivityMode,
            audioBucket: row.transmitterState == .off ? 0 : row.audioBucket,
            effectiveLiveMode: effectiveLiveMode
        ) {
        case .hidden:
            EmptyView()
        case .signalLight(let isLive):
            Circle()
                .fill(isLive ? Color.green.opacity(0.85) : primaryTextColor.opacity(0.15))
                .frame(width: compact ? 8 : 7, height: compact ? 8 : 7)
        case .meter(let filledSegments):
            // Last segment is a true clip/overage alert, not just "the
            // meter happens to be fully pegged": it's driven by the
            // receiver's own AUDIO_LED_BITMAP bit 7 ("LED 8 - Red" per
            // Shure's Axient Digital reference), the same way the RF
            // meter's dedicated overload segment is driven by
            // RSSI_LED_BITMAP bit 5, not by rfBars alone. Only lights up
            // when that real bit says so -- not derived from our own
            // level/bar-count math, which can reach 8/8 at a different
            // threshold than the receiver's own clip detection.
            let audioOverload = row.transmitterState == .off ? false : row.audioOverload
            HStack(spacing: 2) {
                ForEach(0..<Self.audioMeterSegmentCount, id: \.self) { index in
                    let isOverageSegment = index == Self.audioMeterSegmentCount - 1
                    let isLit = isOverageSegment ? audioOverload : (index < filledSegments)
                    let fillColor: Color = {
                        guard isLit else { return primaryTextColor.opacity(0.08) }
                        return isOverageSegment ? Color.red.opacity(0.85) : Color.green.opacity(0.55)
                    }()
                    Capsule()
                        .fill(fillColor)
                        .frame(height: compact ? 7 : 6)
                }
            }
        }
    }

    private func displayedFrequency(for row: ShureOverviewChannelSnapshot, preferPlaceholderWhenNil: Bool = true) -> String? {
        if effectiveLiveMode, let frequency = row.frequency, !frequency.isEmpty {
            return frequency
        }
        guard preferPlaceholderWhenNil || !effectiveLiveMode else { return nil }
        return effectiveLiveMode ? "—" : "Waiting"
    }

    private func displayedBattery(for row: ShureOverviewChannelSnapshot, preferPlaceholderWhenNil: Bool = true) -> String? {
        guard effectiveLiveMode else {
            guard preferPlaceholderWhenNil else { return nil }
            return "--%"
        }
        if row.transmitterState == .off {
            guard preferPlaceholderWhenNil else { return nil }
            return "—"
        }
        if let battery = row.batteryPercent {
            return "\(battery)%"
        }
        guard preferPlaceholderWhenNil else { return nil }
        return "—"
    }

    private func displayedRF(for row: ShureOverviewChannelSnapshot, preferPlaceholderWhenNil: Bool = true) -> String? {
        if row.transmitterState == .off {
            guard preferPlaceholderWhenNil else { return nil }
            return effectiveLiveMode ? "—" : "--"
        }
        if effectiveLiveMode, let rfBars = row.rfBars {
            return "\(rfBars)"
        }
        guard preferPlaceholderWhenNil || !effectiveLiveMode else { return nil }
        return effectiveLiveMode ? "—" : "--"
    }

    private func horizontalGridColumns(for availableWidth: CGFloat) -> [GridItem] {
        let usableWidth = max(availableWidth, compactCardWidthRange.lowerBound)
        let targetCardWidth: CGFloat = 250
        let computedCount = Int((usableWidth + cardSpacing) / (targetCardWidth + cardSpacing))
        let columnCount = max(2, min(6, computedCount))
        return Array(
            repeating: GridItem(.flexible(minimum: compactCardWidthRange.lowerBound, maximum: compactCardWidthRange.upperBound), spacing: cardSpacing, alignment: .top),
            count: columnCount
        )
    }

    private func batteryTint(for row: ShureOverviewChannelSnapshot) -> Color {
        guard effectiveLiveMode else { return secondaryTextColor }
        if row.transmitterState == .off {
            return secondaryTextColor
        }
        guard let battery = row.batteryPercent else { return secondaryTextColor }
        if battery <= config.criticalBatteryPercent { return .red }
        if battery <= config.lowBatteryWarningPercent { return .yellow }
        return secondaryTextColor
    }

    private func rfTint(for row: ShureOverviewChannelSnapshot) -> Color {
        guard effectiveLiveMode else { return secondaryTextColor }
        if row.transmitterState == .off {
            return secondaryTextColor
        }
        guard let rf = row.rfBars else { return secondaryTextColor }
        if rf <= config.criticalRFThreshold { return .red }
        if rf <= config.lowRFWarningThreshold { return .yellow }
        return secondaryTextColor
    }

    private func alertTint(for row: ShureOverviewChannelSnapshot) -> Color? {
        if row.isSyncing || row.transmitterState == .off || row.isOffline {
            return row.isOffline ? .red : nil
        } else if row.warningReasons.contains("Battery critical") || row.warningReasons.contains("RF critical") {
            return .red
        } else if row.isStale {
            return .orange
        }
        return nil
    }

    // Mirrors the precedence chain in `statusPill` so this only lights up
    // for the same cards the pill labels "On" in solid green -- not the
    // looser "Live" fallback, and never at the same time as a red/orange
    // alertTint or a yellow warning.
    private func isPoweredOnWithoutAlert(_ row: ShureOverviewChannelSnapshot) -> Bool {
        guard row.transmitterState == .on, alertTint(for: row) == nil else { return false }
        if row.warningReasons.contains("Battery critical") || row.warningReasons.contains("RF critical") { return false }
        if row.warningReasons.contains("Battery low") || row.warningReasons.contains("RF low") { return false }
        return true
    }

    // Same "Warning" condition the pill labels in yellow -- steady, not
    // blinking, since only Critical/Offline/Stale warrant the attention-
    // grabbing blink.
    private func isWarningWithoutAlert(_ row: ShureOverviewChannelSnapshot) -> Bool {
        guard alertTint(for: row) == nil else { return false }
        return row.warningReasons.contains("Battery low") || row.warningReasons.contains("RF low")
    }

    @ViewBuilder
    private func alertOverlay(for row: ShureOverviewChannelSnapshot) -> some View {
        if let tint = alertTint(for: row), effectiveLiveMode {
            // The blink clock lives in its own subview so the 1Hz toggle only
            // re-renders this border, not the whole string-heavy card/module.
            ShureOverviewAlertBorder(hub: hub, tint: tint)
        } else if effectiveLiveMode, isWarningWithoutAlert(row) {
            ShureOverviewStatusBorder(tint: .yellow)
        } else if effectiveLiveMode, isPoweredOnWithoutAlert(row) {
            ShureOverviewStatusBorder(tint: .green)
        }
    }

    private var summaryFont: Font {
        .system(size: CGFloat((tileTextFormatting?.fontSize ?? 20) * 0.48), weight: .regular)
    }

    private var titleFont: Font {
        .system(size: CGFloat((tileTextFormatting?.fontSize ?? 20) * 0.62), weight: (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight)
    }

    private var detailFont: Font {
        .system(size: CGFloat((tileTextFormatting?.fontSize ?? 20) * 0.46), weight: .regular)
    }

    private var primaryTextColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? .white
    }

    private var secondaryTextColor: Color {
        primaryTextColor.opacity(0.72)
    }
}

enum ShureOverviewAudioIndicator: Equatable {
    case hidden
    case signalLight(isLive: Bool)
    case meter(filledSegments: Int)

    static func indicator(
        mode: ShureOverviewAudioActivityMode,
        audioBucket: Int,
        effectiveLiveMode: Bool
    ) -> ShureOverviewAudioIndicator {
        switch mode {
        case .off:
            return .hidden
        case .signalLight:
            return .signalLight(isLive: effectiveLiveMode && audioBucket > 0)
        case .meter:
            return .meter(filledSegments: effectiveLiveMode ? audioBucket : 0)
        }
    }
}

/// Renders a single card's blinking alert border. Isolated into its own view
/// so the hub's 1Hz `blinkPhase` toggle invalidates only this lightweight
/// border — not the parent module body and its string-heavy channel cards.
private struct ShureOverviewAlertBorder: View {
    @ObservedObject var hub: ShureOverviewHub
    let tint: Color

    var body: some View {
        let blinkOn = hub.blinkPhase
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(tint.opacity(blinkOn ? 0.9 : 0.35), lineWidth: blinkOn ? 1.8 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(blinkOn ? 0.08 : 0.03))
            )
            .animation(.easeInOut(duration: 0.3), value: blinkOn)
    }
}

/// Renders a steady (non-blinking) highlight border for a card that's
/// powered on with no active alert. Deliberately not an `ObservedObject` on
/// the hub, unlike `ShureOverviewAlertBorder` — this doesn't blink, so it
/// has no reason to redraw on the hub's 1Hz clock.
private struct ShureOverviewStatusBorder: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(tint.opacity(0.55), lineWidth: 1.2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.05))
            )
    }
}

/// Isolated into its own view, observing the hub directly, so the strain
/// flag's changes don't re-render the parent module body — the same
/// reasoning as `ShureOverviewAlertBorder` above and the same reason
/// `ShureOverviewModuleView.hub` is deliberately not an `@ObservedObject`.
private struct ShureOverviewStrainBanner: View {
    @ObservedObject var hub: ShureOverviewHub
    let mode: ShureOverviewAudioActivityMode
    let onSwitchToSignalLight: () -> Void
    @State private var isDismissed = false

    var body: some View {
        Group {
            if mode == .meter && hub.isPerformanceStrained && !isDismissed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Meter mode may be affecting performance on this rig.")
                        .font(.caption)
                    Spacer(minLength: 8)
                    Button("Switch to Signal light", action: onSwitchToSignalLight)
                        .font(.caption.weight(.semibold))
                    Button {
                        isDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                    .help("Dismiss — accepting lower performance in Meter mode")
                }
                .padding(8)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        // hub.isPerformanceStrained now latches for the whole Live Mode
        // session (see updatePerformanceStrain) rather than clearing itself
        // the moment one check comes back clean, so this only actually
        // fires on a fresh Live Mode activation -- which is exactly the
        // right moment to let a dismiss from the previous session lapse, so
        // a new strain episode surfaces the banner again instead of staying
        // silently hidden forever.
        .onChange(of: hub.isPerformanceStrained) { _, isStrained in
            if !isStrained { isDismissed = false }
        }
        .onChange(of: mode) { _, newMode in
            if newMode != .meter { isDismissed = false }
        }
    }
}

struct ShureOverviewModuleSettingsInspector: View {
    @Binding var config: ShureOverviewModuleConfig
    var allPersonNames: [String]
    var onPersist: () -> Void
    @ObservedObject private var externalStore = ExternalDevicesStore.shared
    @ObservedObject private var hub = ShureOverviewHub.shared
    @State private var showChannelNames: Bool = false

    var body: some View {
        GroupBox("Shure Overview") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Devices", selection: $config.deviceScope) {
                    Text("All Shure devices").tag(ShureOverviewModuleConfig.DeviceScope.allShureDevices)
                    Text("Selected devices").tag(ShureOverviewModuleConfig.DeviceScope.selectedDevices)
                }
                .pickerStyle(.segmented)

                if config.deviceScope == .selectedDevices {
                    ForEach(externalStore.devices.filter { $0.kind == .shureWireless }) { device in
                        Toggle(device.name, isOn: Binding(
                            get: { config.selectedDeviceIDs.contains(device.id) },
                            set: { enabled in
                                if enabled { config.selectedDeviceIDs.insert(device.id) } else { config.selectedDeviceIDs.remove(device.id) }
                                onPersist()
                            }
                        ))
                    }
                }

                Picker("Default tab", selection: $config.defaultTab) {
                    Text("Auto").tag(ShureOverviewModuleConfig.DefaultTab.auto)
                    Text("Mics").tag(ShureOverviewModuleConfig.DefaultTab.mics)
                    Text("IEMs").tag(ShureOverviewModuleConfig.DefaultTab.iems)
                }

                Picker("Sort", selection: $config.sortOrder) {
                    Text("By severity").tag(ShureOverviewModuleConfig.SortOrder.severity)
                    Text("By device/channel").tag(ShureOverviewModuleConfig.SortOrder.deviceChannel)
                    Text("By name").tag(ShureOverviewModuleConfig.SortOrder.name)
                    Text("By battery").tag(ShureOverviewModuleConfig.SortOrder.battery)
                    Text("By RF").tag(ShureOverviewModuleConfig.SortOrder.rf)
                }

                Picker("Display style", selection: $config.displayStyle) {
                    Text("List").tag(ShureOverviewModuleConfig.DisplayStyle.list)
                    Text("Cards").tag(ShureOverviewModuleConfig.DisplayStyle.cards)
                }

                if config.displayStyle == .cards {
                    Picker("Card size", selection: $config.cardSize) {
                        Text("Small").tag(ShureOverviewModuleConfig.CardSize.small)
                        Text("Medium").tag(ShureOverviewModuleConfig.CardSize.medium)
                        Text("Large").tag(ShureOverviewModuleConfig.CardSize.large)
                    }
                    .pickerStyle(.segmented)
                }

                if !hub.rawChannels.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showChannelNames.toggle()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: showChannelNames ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)
                                Text("Channel Names")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showChannelNames {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(hub.rawChannels.filter { raw in
                                    if config.deviceScope == .selectedDevices {
                                        return config.selectedDeviceIDs.contains(raw.deviceID)
                                    }
                                    return true
                                }) { raw in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(raw.displayName)
                                                .font(.caption.weight(.semibold))
                                            Text(raw.deviceName)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 4) {
                                            let assignmentKey = shureOverviewAssignmentKey(deviceName: raw.deviceName, channelIndex: raw.channelIndex)
                                            Picker("", selection: Binding(
                                                get: {
                                                    let current = config.channelPersonAssignments[assignmentKey] ?? config.channelPersonAssignments[raw.id] ?? ""
                                                    return current.isEmpty || current == "__custom__" || !allPersonNames.contains(current)
                                                        ? (current.isEmpty ? "" : "__custom__")
                                                        : current
                                                },
                                                set: { selection in
                                                    config.channelPersonAssignments[assignmentKey] = selection
                                                    config.channelPersonAssignments.removeValue(forKey: raw.id)
                                                    if selection != "__custom__" { config.customChannelNames.removeValue(forKey: assignmentKey) }
                                                    onPersist()
                                                }
                                            )) {
                                                Text("Channel name").tag("")
                                                ForEach(allPersonNames, id: \.self) { name in Text(name).tag(name) }
                                                Text("Custom").tag("__custom__")
                                            }
                                            .labelsHidden()
                                            .frame(maxWidth: 160)
                                            let currentAssignment = config.channelPersonAssignments[assignmentKey] ?? config.channelPersonAssignments[raw.id]
                                            if currentAssignment == "__custom__"
                                                || (currentAssignment.map { !$0.isEmpty && !allPersonNames.contains($0) } ?? false) {
                                                TextField("Custom name", text: Binding(
                                                    get: { config.customChannelNames[assignmentKey] ?? currentAssignment.flatMap { allPersonNames.contains($0) || $0 == "__custom__" ? nil : $0 } ?? "" },
                                                    set: { value in
                                                        config.channelPersonAssignments[assignmentKey] = "__custom__"
                                                        config.customChannelNames[assignmentKey] = value
                                                        onPersist()
                                                    }
                                                ))
                                                .textFieldStyle(.roundedBorder)
                                                .frame(maxWidth: 160)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 10)
                            .padding(.leading, 22)
                        }
                    }
                }

                Toggle("Hide offline channels", isOn: $config.hideOfflineChannels)
                Toggle("Show frequency", isOn: $config.showFrequency)
                Toggle("Show device name", isOn: $config.showDeviceName)
                Picker("Audio activity", selection: $config.audioActivityMode) {
                    ForEach(ShureOverviewAudioActivityMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if config.audioActivityMode == .meter {
                    Text("Meter mode refreshes faster and can affect performance on larger rigs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show summary status chips", isOn: $config.showSummaryStatusChips)
                Toggle("Show channel status pill", isOn: $config.showChannelStatusPill)
                Toggle("Show last updated timestamp", isOn: $config.showLastUpdatedTimestamp)
                Stepper("Low battery warning: \(config.lowBatteryWarningPercent)%", value: $config.lowBatteryWarningPercent, in: 1...99)
                Stepper("Critical battery: \(config.criticalBatteryPercent)%", value: $config.criticalBatteryPercent, in: 1...99)
                Stepper("Low RF warning: \(config.lowRFWarningThreshold)", value: $config.lowRFWarningThreshold, in: 0...5)
                Stepper("Critical RF: \(config.criticalRFThreshold)", value: $config.criticalRFThreshold, in: 0...5)
                Stepper("Stale timeout: \(Int(config.staleTelemetryTimeoutSeconds))s", value: $config.staleTelemetryTimeoutSeconds, in: 2...90, step: 1)
            }
            .onChange(of: config, initial: false) { _, _ in onPersist() }
        }
    }
}
