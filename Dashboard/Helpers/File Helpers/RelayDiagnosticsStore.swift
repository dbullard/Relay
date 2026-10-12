//
//  RelayDiagnosticsStore.swift
//  Relay
//
//  Created by David Bullard on 2/11/26.
//

import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
final class RelayDiagnosticsStore: ObservableObject {
    static let shared = RelayDiagnosticsStore()
    private static let timestampFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    struct Snapshot: Equatable {
        var tabCount: Int = 0
        var tileCount: Int = 0
        var moduleCount: Int = 0
        var largestTabTileCount: Int = 0
        var moduleKindCounts: [String: Int] = [:]
        var lastUpdated: Date = Date()
    }

    struct PerformanceMetric: Equatable {
        var sampleCount: Int = 0
        var totalDuration: TimeInterval = 0
        var maxDuration: TimeInterval = 0
        var lastDuration: TimeInterval = 0
        var lastDetails: String = ""

        var averageDuration: TimeInterval {
            guard sampleCount > 0 else { return 0 }
            return totalDuration / Double(sampleCount)
        }
    }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var lastErrorDescription: String? = nil
    @Published private(set) var lastErrorAt: Date? = nil
    private var lastSnapshotLoggedAt: Date? = nil
    private var lastLoggedSnapshot: Snapshot? = nil
    private var recentErrors: [(Date, String)] = []
    private var shureTrace: [(Date, String)] = []
    private var sennheiserTrace: [(Date, String)] = []
    private var networkScannerTrace: [(Date, String)] = []
    private var canvasMountTrace: [(Date, String)] = []
    private var lastErrorAtByKey: [String: Date] = [:]
    private var lastTraceAtByKey: [String: Date] = [:]
    private var performanceMetrics: [String: PerformanceMetric] = [:]
    private var eventCounters: [String: Int] = [:]
    private var activeCanvasCompositionSummary: String = "None"
    private var activeGraphCompositionSummary: String = "None"

    private init() {}

    private func timestampString(for date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    func update(tabs: [DashboardTab]) {
        var tileCount = 0
        var moduleCount = 0
        var largestTabTileCount = 0
        var moduleCounts: [String: Int] = [:]

        for tab in tabs {
            let tabTileCount = tab.tiles.count
            tileCount += tabTileCount
            largestTabTileCount = max(largestTabTileCount, tabTileCount)

            for tile in tab.tiles {
                if let modules = tile.modules, !modules.isEmpty {
                    moduleCount += modules.count
                    for module in modules {
                        let name = moduleKindName(module.kind)
                        moduleCounts[name, default: 0] += 1
                    }
                } else {
                    moduleCount += 1
                    let name = tileKindName(tile.kind)
                    moduleCounts[name, default: 0] += 1
                }
            }
        }

        snapshot = Snapshot(
            tabCount: tabs.count,
            tileCount: tileCount,
            moduleCount: moduleCount,
            largestTabTileCount: largestTabTileCount,
            moduleKindCounts: moduleCounts,
            lastUpdated: Date()
        )

        logSnapshotIfNeeded(reason: "tabs changed")
    }

    func recordError(_ description: String, tag: String? = nil) {
        let now = Date()
        if let tag, !tag.isEmpty {
            lastErrorDescription = "[\(tag)] \(description)"
        } else {
            lastErrorDescription = description
        }
        lastErrorAt = now
        let timestamp = timestampString(for: now)
        print("❌ [Error] \(lastErrorDescription ?? description) @ \(timestamp)")
        recentErrors.append((now, lastErrorDescription ?? description))
        if recentErrors.count > 50 {
            recentErrors.removeFirst(recentErrors.count - 50)
        }
    }

    func recordThrottledError(_ description: String, tag: String? = nil, key: String, minInterval: TimeInterval = 60) {
        let now = Date()
        if let lastAt = lastErrorAtByKey[key], now.timeIntervalSince(lastAt) < minInterval {
            return
        }
        lastErrorAtByKey[key] = now
        recordError(description, tag: tag)
    }

    func recordShureTrace(_ description: String) {
        guard WirelessLoggingPreferences.shureMasterVerbose else { return }
        let now = Date()
        let timestamp = timestampString(for: now)
        print("[ShureTrace] \(description) @ \(timestamp)")
        shureTrace.append((now, description))
        if shureTrace.count > 400 {
            shureTrace.removeFirst(shureTrace.count - 400)
        }
    }

    func shureTraceSummary(limit: Int = 400) -> String {
        let items = shureTrace.suffix(limit)
        guard !items.isEmpty else { return "None" }
        return items.map { entry in
            let timestamp = timestampString(for: entry.0)
            return "\(timestamp) — \(entry.1)"
        }.joined(separator: "\n")
    }

    func recordSennheiserTrace(_ description: String) {
        let now = Date()
        let timestamp = timestampString(for: now)
        print("[SennheiserTrace] \(description) @ \(timestamp)")
        sennheiserTrace.append((now, description))
        if sennheiserTrace.count > 400 {
            sennheiserTrace.removeFirst(sennheiserTrace.count - 400)
        }
    }

    func recordNetworkScannerTrace(
        _ description: String,
        key: String? = nil,
        minInterval: TimeInterval = 120,
        level: String = "info"
    ) {
        let now = Date()
        if let key, let lastAt = lastTraceAtByKey[key], now.timeIntervalSince(lastAt) < minInterval {
            return
        }
        if let key {
            lastTraceAtByKey[key] = now
        }

        let timestamp = timestampString(for: now)
        print("[NetworkScanner] \(description) @ \(timestamp)")
        networkScannerTrace.append((now, description))
        if networkScannerTrace.count > 100 {
            networkScannerTrace.removeFirst(networkScannerTrace.count - 100)
        }
    }

    /// Timestamped record of an individual canvas module mount (a module's
    /// `.onAppear` firing). Complements `ui.canvas.moduleMount*` in
    /// `incrementCounter` -- those only ever surface a session-long total in
    /// exported logs, which can't distinguish "mounted once at launch" from
    /// "remounted 40 times" or show when/which tile a remount happened on.
    func recordCanvasMount(_ description: String) {
        let now = Date()
        let timestamp = timestampString(for: now)
        print("[CanvasMount] \(description) @ \(timestamp)")
        canvasMountTrace.append((now, description))
        if canvasMountTrace.count > 500 {
            canvasMountTrace.removeFirst(canvasMountTrace.count - 500)
        }
    }

    func canvasMountTraceSummary(limit: Int = 500) -> String {
        let items = canvasMountTrace.suffix(limit)
        guard !items.isEmpty else { return "None" }
        return items.map { entry in
            let timestamp = timestampString(for: entry.0)
            return "\(timestamp) — \(entry.1)"
        }.joined(separator: "\n")
    }

    func incrementCounter(_ key: String, by amount: Int = 1) {
        guard amount != 0 else { return }
        eventCounters[key, default: 0] += amount
    }

    func recordPerformanceMetric(
        _ key: String,
        duration: TimeInterval,
        details: String? = nil,
        slowThreshold: TimeInterval? = nil
    ) {
        let normalizedDuration = max(0, duration)
        var metric = performanceMetrics[key] ?? PerformanceMetric()
        metric.sampleCount += 1
        metric.totalDuration += normalizedDuration
        metric.maxDuration = max(metric.maxDuration, normalizedDuration)
        metric.lastDuration = normalizedDuration
        if let details, !details.isEmpty {
            metric.lastDetails = details
        }
        performanceMetrics[key] = metric

        if let slowThreshold, normalizedDuration >= slowThreshold {
            let ms = Int((normalizedDuration * 1000).rounded())
            let suffix = metric.lastDetails.isEmpty ? "" : " • \(metric.lastDetails)"
            let message = "[Perf] \(key) slow \(ms)ms\(suffix)"
            print("🟨 \(message)")
        }
    }

    func updateActiveCanvasComposition(tab: DashboardTab?) {
        guard let tab else {
            activeCanvasCompositionSummary = "None"
            return
        }

        var moduleCount = 0
        var kindCounts: [String: Int] = [:]

        for tile in tab.tiles where !tile.isHidden {
            if let modules = tile.modules, !modules.isEmpty {
                moduleCount += modules.count
                for module in modules {
                    kindCounts[moduleKindName(module.kind), default: 0] += 1
                }
            } else {
                moduleCount += 1
                kindCounts[tileKindName(tile.kind), default: 1] += 1
            }
        }

        let breakdown = compositionBreakdown(kindCounts)
        activeCanvasCompositionSummary = "tab=\(tab.name.nilIfEmpty ?? "Untitled") visibleTiles=\(tab.tiles.filter { !$0.isHidden }.count) modules=\(moduleCount) breakdown=\(breakdown)"
    }

    func updateActiveGraphComposition(
        tabName: String,
        canvasGroups: [String],
        graphNodeKeys: [String],
        consoleNodeCount: Int,
        vistaNodeCount: Int,
        linkCount: Int
    ) {
        var kindCounts: [String: Int] = [:]
        for key in canvasGroups {
            kindCounts[graphNodeKindName(key), default: 0] += 1
        }
        for key in graphNodeKeys {
            kindCounts[graphNodeKindName(key), default: 0] += 1
        }
        if consoleNodeCount > 0 {
            kindCounts["Console Destination", default: 0] += consoleNodeCount
        }
        if vistaNodeCount > 0 {
            kindCounts["Vista Destination", default: 0] += vistaNodeCount
        }

        let totalNodes = canvasGroups.count + graphNodeKeys.count + consoleNodeCount + vistaNodeCount
        let breakdown = compositionBreakdown(kindCounts)
        activeGraphCompositionSummary = "tab=\(tabName.nilIfEmpty ?? "Untitled") nodes=\(totalNodes) links=\(linkCount) breakdown=\(breakdown)"
    }

    func runtimeContextExtras() -> [String: Any] {
        let snapshot = snapshot
        let moduleBreakdown = snapshot.moduleKindCounts
            .sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")

        let lastErrorTimestamp = lastErrorAt.map { timestampString(for: $0) } ?? "N/A"
        let lastShure = shureTrace.last.map { "\(timestampString(for: $0.0)) — \($0.1)" } ?? "None"
        let lastSennheiser = sennheiserTrace.last.map { "\(timestampString(for: $0.0)) — \($0.1)" } ?? "None"
        let lastNetworkScan = networkScannerTrace.last.map { "\(timestampString(for: $0.0)) — \($0.1)" } ?? "None"
        let perfSummary = performanceSummary(limit: 8)
        let counterSummary = eventCountersSummary(limit: 12)
        let accountSnapshot = RelayAccountCoordinator.shared.diagnosticsSnapshot()
        let accountEmail = accountSnapshot.currentEmail ?? "None"
        let accountSourceSubscription = accountSnapshot.sourceSubscription ? "true" : "false"
        let accountSourceLicense = accountSnapshot.sourceLicense ? "true" : "false"
        let accountLastRefresh = accountSnapshot.lastRefreshAt.map { timestampString(for: $0) } ?? "N/A"
        let accountLastErrorCode = accountSnapshot.lastErrorCode.map(String.init) ?? "None"
        let accountLastErrorMessage = accountSnapshot.lastErrorMessage ?? "None"

        return [
            "runtime_tab_count": snapshot.tabCount,
            "runtime_tile_count": snapshot.tileCount,
            "runtime_module_count": snapshot.moduleCount,
            "runtime_largest_tab_tile_count": snapshot.largestTabTileCount,
            "runtime_module_breakdown": moduleBreakdown.isEmpty ? "None" : moduleBreakdown,
            "runtime_last_error": lastErrorDescription ?? "None",
            "runtime_last_error_at": lastErrorTimestamp,
            "runtime_last_shure_trace": lastShure,
            "runtime_last_sennheiser_trace": lastSennheiser,
            "runtime_last_network_scan_trace": lastNetworkScan,
            "runtime_account_auth_enabled": accountSnapshot.authEnabled,
            "runtime_account_signed_in": accountSnapshot.signedIn,
            "runtime_account_email": accountEmail,
            "runtime_account_pro": accountSnapshot.relayAccountPro,
            "runtime_account_source_subscription": accountSourceSubscription,
            "runtime_account_source_license": accountSourceLicense,
            "runtime_account_last_refresh_at": accountLastRefresh,
            "runtime_account_last_error_code": accountLastErrorCode,
            "runtime_account_last_error_message": accountLastErrorMessage,
            "runtime_perf_summary": perfSummary,
            "runtime_event_counters": counterSummary,
            "runtime_active_canvas_composition": activeCanvasCompositionSummary,
            "runtime_active_graph_composition": activeGraphCompositionSummary
        ]
    }

    func sennheiserTraceSummary(limit: Int = 400) -> String {
        let items = sennheiserTrace.suffix(limit)
        guard !items.isEmpty else { return "None" }
        return items.map { entry in
            let timestamp = timestampString(for: entry.0)
            return "\(timestamp) — \(entry.1)"
        }.joined(separator: "\n")
    }

    func networkScannerTraceSummary(limit: Int = 100) -> String {
        let items = networkScannerTrace.suffix(limit)
        guard !items.isEmpty else { return "None" }
        return items.map { entry in
            let timestamp = timestampString(for: entry.0)
            return "\(timestamp) — \(entry.1)"
        }.joined(separator: "\n")
    }

    func performanceSummary(limit: Int = 12) -> String {
        let items = performanceMetrics
            .sorted { lhs, rhs in
                if lhs.value.maxDuration != rhs.value.maxDuration {
                    return lhs.value.maxDuration > rhs.value.maxDuration
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .prefix(limit)
        guard !items.isEmpty else { return "None" }
        return items.map { key, value in
            let avgMs = Int((value.averageDuration * 1000).rounded())
            let maxMs = Int((value.maxDuration * 1000).rounded())
            let lastMs = Int((value.lastDuration * 1000).rounded())
            let details = value.lastDetails.isEmpty ? "" : " [\(value.lastDetails)]"
            return "\(key): samples=\(value.sampleCount) avg=\(avgMs)ms max=\(maxMs)ms last=\(lastMs)ms\(details)"
        }.joined(separator: "\n")
    }

    func eventCountersSummary(limit: Int = 20) -> String {
        let items = eventCounters
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .prefix(limit)
        guard !items.isEmpty else { return "None" }
        return items.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }

    private func logSnapshotIfNeeded(reason: String) {
        let now = Date()
        let minInterval: TimeInterval = 60.0
        let tileDeltaThreshold = 50
        let moduleDeltaThreshold = 50

        if let lastAt = lastSnapshotLoggedAt, now.timeIntervalSince(lastAt) < minInterval {
            if let last = lastLoggedSnapshot {
                let tileDelta = abs(snapshot.tileCount - last.tileCount)
                let moduleDelta = abs(snapshot.moduleCount - last.moduleCount)
                if tileDelta < tileDeltaThreshold && moduleDelta < moduleDeltaThreshold {
                    return
                }
            } else {
                return
            }
        }

        lastSnapshotLoggedAt = now
        lastLoggedSnapshot = snapshot
        print("🧩 [Dashboard] \(reason): tabs=\(snapshot.tabCount) tiles=\(snapshot.tileCount) modules=\(snapshot.moduleCount) largestTab=\(snapshot.largestTabTileCount)")
    }

    func recentErrorsSummary(limit: Int = 50) -> String {
        let items = recentErrors.suffix(limit)
        guard !items.isEmpty else { return "None" }
        return items.map { entry in
            let timestamp = timestampString(for: entry.0)
            return "\(timestamp) — \(entry.1)"
        }.joined(separator: "\n")
    }

    func diagnosticSummary() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let appName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? "Relay"
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info["CFBundleVersion"] as? String ?? "Unknown"
        let distributionChannel = (info["RELAY_DISTRIBUTION_CHANNEL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty ?? "release"
        let purchaseMode = (info["RELAY_PURCHASE_MODE"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty ?? "direct"

        #if os(iOS)
        let device = UIDevice.current
        let osVersion = "\(device.systemName) \(device.systemVersion)"
        let model = device.model
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let model = Host.current().localizedName ?? "Mac"
        #endif

        let timestamp = timestampString(for: Date())

        let defaults = UserDefaults.standard
        let oscEnabled = defaults.bool(forKey: "osc.global.enabled")
        let oscPortRaw = defaults.integer(forKey: "osc.global.port")
        let oscPort = oscPortRaw == 0 ? 8000 : oscPortRaw

        let lanSharingEnabled = defaults.bool(forKey: "lan_sharing_enabled")
        let lanAllowUnpairedRead = defaults.bool(forKey: "lan_allow_unpaired_read")
        let pairedDevices = DevicePairingStore.load(from: defaults)
        let lanPairedDeviceCount = pairedDevices.values.filter { $0.isEnabled }.count
        let lanBlockedDeviceCount = pairedDevices.values.filter { !$0.isEnabled }.count

        let pcoConnected = defaults.bool(forKey: "dashboard_pco_connected")
        let pcoAccountName = defaults.string(forKey: "dashboard_pco_account_name") ?? ""
        let pcoSummary = pcoConnected ? (pcoAccountName.isEmpty ? "Connected" : "Connected (\(pcoAccountName))") : "Not connected"

        let proPresenterProfiles = ProPresenterProfilesStore.loadProfiles(from: defaults)
        let activeProPresenter = ProPresenterProfilesStore.activeProfile(from: defaults)?.name ?? ""
        let proPresenterSummary = activeProPresenter.isEmpty ? "\(proPresenterProfiles.count)" : "\(proPresenterProfiles.count) (Active: \(activeProPresenter))"

        let resolumeProfiles = ResolumeProfilesStore.shared.profiles
        let resolumeEnabledCount = resolumeProfiles.filter { $0.isEnabled }.count

        let externalDevicesCount = ExternalDevicesStore.shared.devices.count
        let snapshot = snapshot
        let moduleCounts = snapshot.moduleKindCounts
            .sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let lastError = lastErrorDescription ?? "None"
        let lastErrorAt = lastErrorAt.map { timestampString(for: $0) } ?? "N/A"
        let perfSummary = performanceSummary(limit: 10)
        let counterSummary = eventCountersSummary(limit: 16)
        let accountSnapshot = RelayAccountCoordinator.shared.diagnosticsSnapshot()
        let accountEmail = accountSnapshot.currentEmail ?? "None"
        let accountSourceSubscription = accountSnapshot.sourceSubscription ? "Yes" : "No"
        let accountSourceLicense = accountSnapshot.sourceLicense ? "Yes" : "No"
        let accountLastRefresh = accountSnapshot.lastRefreshAt.map { timestampString(for: $0) } ?? "N/A"
        let accountLastErrorCode = accountSnapshot.lastErrorCode.map(String.init) ?? "None"
        let accountLastErrorMessage = accountSnapshot.lastErrorMessage ?? "None"

        let oscManager = OSCManager.shared
        let oscRX = oscManager.lastReceiveAt.map { timestampString(for: $0) } ?? "N/A"
        let oscTX = oscManager.lastSendAt.map { timestampString(for: $0) } ?? "N/A"
        let oscLastRemote = oscManager.lastReceiveRemote ?? oscManager.lastSendRemote ?? "N/A"

        let lanPairingLine = "LAN Paired Devices: \(lanPairedDeviceCount) paired, \(lanBlockedDeviceCount) blocked"

        return """
        App: \(appName)
        Version: \(version) (\(build))
        Distribution Channel: \(distributionChannel)
        Purchase Mode: \(purchaseMode)
        Device: \(model)
        OS: \(osVersion)
        Timestamp: \(timestamp)
        Tabs: \(snapshot.tabCount)
        Tiles: \(snapshot.tileCount) (Largest tab: \(snapshot.largestTabTileCount))
        Modules: \(snapshot.moduleCount)
        Module Breakdown: \(moduleCounts.isEmpty ? "None" : moduleCounts)
        External Devices: \(externalDevicesCount)
        PCO: \(pcoSummary)
        ProPresenter Profiles: \(proPresenterSummary)
        Resolume Profiles: \(resolumeProfiles.count) (Enabled: \(resolumeEnabledCount))
        OSC: \(oscEnabled ? "On" : "Off") (Port \(oscPort))
        OSC Last Activity: RX \(oscRX) / TX \(oscTX) (Remote \(oscLastRemote))
        LAN Sharing: \(lanSharingEnabled ? "On" : "Off")
        \(lanPairingLine)
        LAN Allow Unpaired Read: \(lanAllowUnpairedRead ? "On" : "Off")
        Relay Account Auth: \(accountSnapshot.authEnabled ? "Enabled" : "Disabled")
        Relay Account Signed In: \(accountSnapshot.signedIn ? "Yes" : "No")
        Relay Account Email: \(accountEmail)
        Relay Account Pro: \(accountSnapshot.relayAccountPro ? "Yes" : "No")
        Relay Account Source Subscription: \(accountSourceSubscription)
        Relay Account Source License: \(accountSourceLicense)
        Relay Account Last Refresh: \(accountLastRefresh)
        Relay Account Last Error Code: \(accountLastErrorCode)
        Relay Account Last Error: \(accountLastErrorMessage)
        Active Canvas Composition: \(activeCanvasCompositionSummary)
        Active Graph Composition: \(activeGraphCompositionSummary)
        Perf Summary: \(perfSummary.isEmpty ? "None" : perfSummary)
        Event Counters: \(counterSummary)
        Last Error: \(lastError)
        Last Error At: \(lastErrorAt)
        """
    }

    private func compositionBreakdown(_ counts: [String: Int]) -> String {
        let items = counts
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            .prefix(12)
        guard !items.isEmpty else { return "None" }
        return items.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }

    private func moduleKindName(_ kind: DashboardModuleKind) -> String {
        switch kind {
        case .person:
            return "Person"
        case .pcoRundown:
            return "PCO Rundown"
        case .pcoTeamAssignments:
            return "PCO Team Assignments"
        case .rosterTeamAssignments:
            return "Roster Team Assignments"
        case .shureWireless:
            return "Shure Wireless"
        case .shureOverview:
            return "Shure Overview"
        case .sennheiserWireless:
            return "Sennheiser Wireless"
        case .proPresenter:
            return "ProPresenter"
        case .resolume:
            return "Resolume"
        case .time:
            return "Time"
        case .timecode:
            return "Timecode"
        case .dawTransport:
            return "DAW Transport"
        case .rosterPicker:
            return "Picker"
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .document:
            return "Document"
        case .ndi:
            return "NDI Feed"
        case .webpage:
            return "Webpage"
        case .youtubeStreamMonitor:
            return "YouTube Stream Monitor"
        case .separator:
            return "Separator"
        case .dbReader:
            return "SPL Meter"
        case .liveTranscription:
            return "Live Transcription"
        case .button:
            return "Button"
        case .rta:
            return "RTA"
        case .spectrograph:
            return "Spectrograph"
        }
    }

    private func tileKindName(_ kind: DashboardTileKind) -> String {
        switch kind {
        case .empty:
            return "Empty"
        case .person:
            return "Person"
        case .pcoPlaceholder:
            return "Planning Center"
        case .time:
            return "Time"
        }
    }

    private func graphNodeKindName(_ key: String) -> String {
        switch key {
        case "moduleGroup.person":
            return "People Source"
        case "moduleGroup.pco":
            return "Planning Center Source"
        case "moduleGroup.transcription":
            return "Transcription Trigger"
        case "moduleGroup.dbThreshold":
            return "SPL Trigger"
        case "moduleGroup.shure":
            return "Shure Source"
        case "moduleGroup.sennheiser":
            return "Sennheiser Source"
        case DashboardGraph.buttonTriggerGroupKey:
            return "Canvas Button Trigger"
        case "destination.console":
            return "Console Destination"
        case "destination.vista":
            return "Vista Destination"
        case "utility.condition":
            return "Condition"
        case "utility.repeater":
            return "Repeater"
        case "utility.delay":
            return "Delay"
        case "utility.variable":
            return "Variable"
        case "action.appControl":
            return "App Control Action"
        case "source.roster":
            return "Roster Source"
        case "source.consoleImport":
            return "Console Import Source"
        case "source.wirelessImport":
            return "Wireless Import Source"
        case "source.staticLabel":
            return "Static Label Source"
        default:
            if key.hasPrefix("action.") {
                return "Action (\(key.replacingOccurrences(of: "action.", with: "")))"
            }
            if key.hasPrefix("moduleGroup.") {
                return "Group (\(key.replacingOccurrences(of: "moduleGroup.", with: "")))"
            }
            if key.hasPrefix("source.") {
                return "Source (\(key.replacingOccurrences(of: "source.", with: "")))"
            }
            return key
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
