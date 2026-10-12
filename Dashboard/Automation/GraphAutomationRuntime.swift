//
//  GraphAutomationRuntime.swift
//  Relay
//
//  Created by David Bullard on 1/18/26.
//

import Foundation
import Combine
import CoreGraphics
import CryptoKit
#if os(macOS)
import AppKit
#endif

final class GraphAutomationRuntime: ObservableObject {
    static let shared = GraphAutomationRuntime()

    #if DEBUG
    static func makeForTesting() -> GraphAutomationRuntime {
        GraphAutomationRuntime()
    }
    #endif

    private var cancellables: Set<AnyCancellable> = []
    private let queue = DispatchQueue(label: "prodlink.automation.runtime")
    private var hasStarted: Bool = false
    #if os(macOS)
    private var localKeyMonitor: Any?
    #endif

    // Provide access to the currently-active tab graphs.
    // You can inject from DashboardRootView (recommended),
    // or fetch via some shared store if you have one.
    @Published var activeTabs: [DashboardTab] = []
    /// When false, the runtime will not synthesize OSC->trigger fires or execute downstream actions.
    @Published var isEnabled: Bool = true

    // Prefer pulling the live selected tab from the owning view (avoids stale copies of DashboardTab/graph).
    private var activeTabProvider: (() -> DashboardTab?)?
    private var activeTabGraphUpdater: ((UUID, DashboardGraph) -> Void)?
    private let tabSnapshotLock = NSLock()
    private var cachedActiveTabs: [DashboardTab] = []
    private var cachedSelectedTabId: UUID?

    /// Fallback cache: if a SwiftUI-captured provider temporarily returns nil, keep the last known tab.
    private var lastKnownActiveTab: DashboardTab?

    private var cachedUniversalGraph: DashboardGraph? = nil

    func setUniversalGraph(_ graph: DashboardGraph?) {
        tabSnapshotLock.lock()
        cachedUniversalGraph = graph
        tabSnapshotLock.unlock()
    }

    func effectiveGraph(for tab: DashboardTab) -> DashboardGraph? {
        switch tab.automationMode {
        case .universal:
            tabSnapshotLock.lock()
            defer { tabSnapshotLock.unlock() }
            return cachedUniversalGraph
        case .perTab:
            return tab.graph
        }
    }

    private func readLastKnownActiveTab() -> DashboardTab? {
        tabSnapshotLock.lock()
        defer { tabSnapshotLock.unlock() }
        return lastKnownActiveTab
    }

    private func readActiveTabs() -> [DashboardTab] {
        tabSnapshotLock.lock()
        defer { tabSnapshotLock.unlock() }
        return cachedActiveTabs
    }

    private func readSelectedTabId() -> UUID? {
        tabSnapshotLock.lock()
        defer { tabSnapshotLock.unlock() }
        return cachedSelectedTabId
    }

    @MainActor
    func setActiveTabsSnapshot(_ tabs: [DashboardTab], selectedTabId: UUID?) {
        activeTabs = tabs
        let selectedTab = selectedTabId.flatMap { id in
            tabs.first(where: { $0.id == id })
        }
        tabSnapshotLock.lock()
        cachedActiveTabs = tabs
        cachedSelectedTabId = selectedTabId
        if let selectedTab {
            lastKnownActiveTab = selectedTab
        } else if let lastKnownActiveTab,
                  tabs.contains(where: { $0.id == lastKnownActiveTab.id }) {
            self.lastKnownActiveTab = lastKnownActiveTab
        } else {
            lastKnownActiveTab = nil
        }
        tabSnapshotLock.unlock()
    }

    /// Explicitly set the current active tab value (recommended from owning views).
    @MainActor
    func setActiveTabSnapshot(_ tab: DashboardTab) {
        if let tabIndex = activeTabs.firstIndex(where: { $0.id == tab.id }) {
            activeTabs[tabIndex] = tab
        }
        tabSnapshotLock.lock()
        if let tabIndex = cachedActiveTabs.firstIndex(where: { $0.id == tab.id }) {
            cachedActiveTabs[tabIndex] = tab
        }
        cachedSelectedTabId = tab.id
        lastKnownActiveTab = tab
        tabSnapshotLock.unlock()
    }

    func setActiveTabProvider(_ provider: @escaping () -> DashboardTab?) {
        // Set from UI on main; runtime reads from a background queue.
        DispatchQueue.main.async {
            self.activeTabProvider = provider
            // Prime/update fallback cache if the provider can resolve a tab right now.
            if let t = provider() {
                self.setActiveTabSnapshot(t)
            }
        }
    }

    func setActiveTabGraphUpdater(_ updater: @escaping (UUID, DashboardGraph) -> Void) {
        DispatchQueue.main.async {
            self.activeTabGraphUpdater = updater
        }
    }

    private func currentTabFromProvider() -> DashboardTab? {
        if Thread.isMainThread {
            let tab = activeTabProvider?()
            if let tab {
                setActiveTabSnapshot(tab)
            }
            return tab
        }
        return nil
    }

    private func tabsToProcess() -> [DashboardTab] {
        if Thread.isMainThread, let tab = currentTabFromProvider() {
            return [tab]
        }
        let activeTabs = readActiveTabs()
        if let selectedTabId = readSelectedTabId(),
           let selectedTab = activeTabs.first(where: { $0.id == selectedTabId }) {
            return [selectedTab]
        }
        if let cached = readLastKnownActiveTab() {
            return [cached]
        }
        return activeTabs
    }

    private func latestTabSnapshot(for tabId: UUID, fallback: DashboardTab) -> DashboardTab {
        if Thread.isMainThread, let provided = currentTabFromProvider(), provided.id == tabId {
            return provided
        }
        if let active = readActiveTabs().first(where: { $0.id == tabId }) {
            return active
        }
        if let cached = readLastKnownActiveTab(), cached.id == tabId {
            return cached
        }
        return fallback
    }

    private func mergedGraphPreservingEditorState(_ runtimeGraph: DashboardGraph, for tabId: UUID) -> DashboardGraph {
        let currentGraph: DashboardGraph? = {
            if let providedTab = activeTabProvider?(), providedTab.id == tabId {
                return effectiveGraph(for: providedTab)
            }
            if let activeTab = activeTabs.first(where: { $0.id == tabId }) {
                return effectiveGraph(for: activeTab)
            }
            if let cachedTab = lastKnownActiveTab, cachedTab.id == tabId {
                return effectiveGraph(for: cachedTab)
            }
            return nil
        }()

        guard var mergedGraph = currentGraph else {
            return runtimeGraph
        }

        for (nodeId, runtimeConfig) in runtimeGraph.variableNodeConfigByNodeId {
            guard let currentConfig = mergedGraph.variableNodeConfigByNodeId[nodeId] else {
                mergedGraph.variableNodeConfigByNodeId[nodeId] = runtimeConfig
                continue
            }

            var mergedConfig = currentConfig
            mergedConfig.currentTextValue = runtimeConfig.currentTextValue
            mergedConfig.currentNumberValue = runtimeConfig.currentNumberValue
            mergedConfig.currentBooleanValue = runtimeConfig.currentBooleanValue
            mergedConfig.lastUpdatedAt = runtimeConfig.lastUpdatedAt
            mergedConfig.sourceNodeId = runtimeConfig.sourceNodeId
            mergedGraph.variableNodeConfigByNodeId[nodeId] = mergedConfig
        }

        for (nodeId, runtimeConfig) in runtimeGraph.conditionNodeConfigByNodeId {
            guard let currentConfig = mergedGraph.conditionNodeConfigByNodeId[nodeId] else {
                mergedGraph.conditionNodeConfigByNodeId[nodeId] = runtimeConfig
                continue
            }

            var mergedConfig = currentConfig
            mergedConfig.lastPayloadText = runtimeConfig.lastPayloadText
            mergedConfig.lastPayloadNumber = runtimeConfig.lastPayloadNumber
            mergedConfig.lastPayloadBoolean = runtimeConfig.lastPayloadBoolean
            mergedConfig.lastResolvedValueSummary = runtimeConfig.lastResolvedValueSummary
            mergedConfig.lastEvaluationDebugSummary = runtimeConfig.lastEvaluationDebugSummary
            mergedConfig.lastEvaluationResult = runtimeConfig.lastEvaluationResult
            mergedConfig.lastEvaluatedAt = runtimeConfig.lastEvaluatedAt
            mergedGraph.conditionNodeConfigByNodeId[nodeId] = mergedConfig
        }

        return mergedGraph
    }

    private func persistUpdatedGraph(_ graph: DashboardGraph, for tabId: UUID) {
        let applyUpdate = {
            let mergedGraph = self.mergedGraphPreservingEditorState(graph, for: tabId)
            self.activeTabGraphUpdater?(tabId, mergedGraph)
            if let tabIndex = self.activeTabs.firstIndex(where: { $0.id == tabId }) {
                self.activeTabs[tabIndex].graph = mergedGraph
            }
            if self.lastKnownActiveTab?.id == tabId {
                self.lastKnownActiveTab?.graph = mergedGraph
            }
        }

        if Thread.isMainThread {
            applyUpdate()
        } else {
            DispatchQueue.main.async(execute: applyUpdate)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func debugRunConditionNode(nodeId: UUID) {
        guard let tab = tabsToProcess().first, let graph = effectiveGraph(for: tab) else { return }
        Task { @MainActor in
            var liveGraph = effectiveGraph(for: tab) ?? graph
            let context = makeExecutionContext(tab: tab, graph: liveGraph)
            let payload = GraphTriggerPayload(sourceNodeId: nodeId, eventKind: "condition.debug")
            let branch = evaluateCondition(nodeId: nodeId, payload: payload, graph: &liveGraph, tab: tab)
                ? GraphAutomationTraversal.UtilityBranch.`true`
                : GraphAutomationTraversal.UtilityBranch.`false`
            await executeGraphFlow(
                from: nodeId,
                sourcePortId: GraphAutomationTraversal.conditionOutputPortId(nodeId: nodeId, branch: branch),
                payload: payload,
                graph: &liveGraph,
                tab: tab,
                context: context,
                visited: []
            )
            persistUpdatedGraph(liveGraph, for: tab.id)
        }
    }

    // De-dupe synthesized trigger fires (e.g., when multiple OSC packets arrive quickly or both view+runtime fire).
    private var lastSynthesizedFireByTriggerId: [UUID: TimeInterval] = [:]
    private let synthFireMinInterval: TimeInterval = 0.20

    // De-dupe *all* trigger-fired events (covers view-posted + runtime-posted duplicates).
    private var lastTriggerFireById: [UUID: TimeInterval] = [:]
    // Per-rule dedup key: "nodeId:ruleId" — prevents node-level dedup from blocking independent rules.
    private var lastTriggerFireByRuleKey: [String: TimeInterval] = [:]
    private let triggerFireMinInterval: TimeInterval = 0.20
    private var lastDebugBannerTime: TimeInterval = 0
    private var lastWordTriggerFireByRuleId: [UUID: TimeInterval] = [:]
    private var lastWordTriggerMatchByRuleId: [UUID: TimeInterval] = [:]
    private var lastWordTriggerEntryIdByRuleId: [UUID: UUID] = [:]
    private var lastWordTriggerMatchCountByRuleId: [UUID: Int] = [:]
    private var lastDbThresholdFireByNodeId: [UUID: TimeInterval] = [:]
    private var wordTriggerRegexCache: [UUID: (pattern: String, regex: NSRegularExpression)] = [:]
    private var recentMidiSendBySignature: [String: TimeInterval] = [:]
    private let midiEchoSuppressWindow: TimeInterval = 2.0

    private init() {
        #if DEBUG
        print("[AutomationRuntime] init")
        #endif
        // Ensure the automation runtime is always listening, regardless of whether Graph or Canvas UI is mounted.
        start()
    }

    private func recordRuntimeCounter(_ key: String, by amount: Int = 1) {
        Task { @MainActor in
            RelayDiagnosticsStore.shared.incrementCounter(key, by: amount)
        }
    }

    private func recordRuntimePerf(
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

    private func postDebugBanner(title: String, message: String) {
        let now = Date().timeIntervalSince1970
        if (now - lastDebugBannerTime) < 0.8 { return }
        lastDebugBannerTime = now
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: ActionNodeNotifications.notify,
                object: nil,
                userInfo: [
                    ActionNodeUserInfoKeys.title: title,
                    ActionNodeUserInfoKeys.message: message,
                    ActionNodeUserInfoKeys.durationSeconds: 3.0
                ]
            )
        }
    }

    // MARK: - Send-All toggle resolution (separate from Direct-to-Console)

    /// Resolve the Send-All action node's toggles from the graph model.
    /// IMPORTANT: This must NOT read any OSC Receive (direct-to-console) toggle state.
    private func resolvedSendAllFlags(actionNodeId: UUID, graph: DashboardGraph) -> (includeAssignments: Bool, includeSnapshots: Bool, delayMs: Double) {
        // Defaults match historical behavior.
        var includeAssignments: Bool = true
        var includeSnapshots: Bool = true
        var delayMs: Double = 0

        let gm = Mirror(reflecting: graph)
        let possibleKeys = [
            "sendAllActionConfigByNodeId",
            "sendAllConsolesActionConfigByNodeId",
            "sendAllToConsolesActionConfigByNodeId"
        ]

        for dictKey in possibleKeys {
            guard let child = gm.children.first(where: { $0.label == dictKey }) else { continue }

            // UUID-keyed dictionary
            if let dict = child.value as? [UUID: Any], let cfg = dict[actionNodeId] {
                let cm = Mirror(reflecting: cfg)
                if let a = cm.children.first(where: { $0.label == "includeAssignments" })?.value as? Bool { includeAssignments = a }
                if let s = cm.children.first(where: { $0.label == "includeSnapshots" })?.value as? Bool { includeSnapshots = s }

                if let d = cm.children.first(where: { $0.label == "delayMs" })?.value as? Double { delayMs = d }
                if let d = cm.children.first(where: { $0.label == "staggerMs" })?.value as? Double { delayMs = d }
                if let i = cm.children.first(where: { $0.label == "delayMs" })?.value as? Int { delayMs = Double(i) }
                if let i = cm.children.first(where: { $0.label == "staggerMs" })?.value as? Int { delayMs = Double(i) }

                return (includeAssignments, includeSnapshots, max(0, delayMs))
            }

            // String-keyed dictionary
            if let dict = child.value as? [String: Any], let cfg = dict[actionNodeId.uuidString] {
                let cm = Mirror(reflecting: cfg)
                if let a = cm.children.first(where: { $0.label == "includeAssignments" })?.value as? Bool { includeAssignments = a }
                if let s = cm.children.first(where: { $0.label == "includeSnapshots" })?.value as? Bool { includeSnapshots = s }

                if let d = cm.children.first(where: { $0.label == "delayMs" })?.value as? Double { delayMs = d }
                if let d = cm.children.first(where: { $0.label == "staggerMs" })?.value as? Double { delayMs = d }
                if let i = cm.children.first(where: { $0.label == "delayMs" })?.value as? Int { delayMs = Double(i) }
                if let i = cm.children.first(where: { $0.label == "staggerMs" })?.value as? Int { delayMs = Double(i) }

                return (includeAssignments, includeSnapshots, max(0, delayMs))
            }
        }

        return (includeAssignments, includeSnapshots, max(0, delayMs))
    }

    func start(center: NotificationCenter = .default) {
        // Idempotent: avoid double subscriptions (prevents duplicate sends).
        if hasStarted {
            #if DEBUG
            print("[AutomationRuntime] start: already started")
            #endif
            return
        }
        #if DEBUG
        print("[AutomationRuntime] start: installing observers")
        #endif
        hasStarted = true
#if os(macOS)
        installLocalKeyMonitorIfNeeded()
#endif

        // Raw OSC packet stream (used to raise trigger fires when trigger node views are not mounted).
        center.publisher(for: .oscReceivePacketDidArrive)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.recordRuntimeCounter("runtime.event.oscPacket.received")
                #if DEBUG
                print("[AutomationRuntime] received .oscReceivePacketDidArrive")
                #endif
                self?.handleOSCPacket(note)
            }
            .store(in: &cancellables)

        // Raw MIDI message stream (used to raise trigger fires when trigger node views are not mounted).
        center.publisher(for: .midiReceiveMessageDidArrive)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.recordRuntimeCounter("runtime.event.midiMessage.received")
                #if DEBUG
                print("[AutomationRuntime] received .midiReceiveMessageDidArrive")
                #endif
                self?.handleMIDIMessage(note)
            }
            .store(in: &cancellables)

        center.publisher(for: ActionNodeNotifications.midiSend)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.handleMIDISendEchoGuard(note)
            }
            .store(in: &cancellables)

        center.publisher(for: ActionNodeNotifications.smartLightSucceeded)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.handleSmartLightCompletion(note, outcome: "success")
                self?.handleSmartLightCompletion(note, outcome: "currentState")
            }
            .store(in: &cancellables)

        center.publisher(for: ActionNodeNotifications.smartLightFailed)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.handleSmartLightCompletion(note, outcome: "failure")
            }
            .store(in: &cancellables)

        // Back-compat: program change only.
        center.publisher(for: .midiReceiveProgramChangeDidArrive)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.recordRuntimeCounter("runtime.event.midiProgramChange.received")
                #if DEBUG
                print("[AutomationRuntime] received .midiReceiveProgramChangeDidArrive")
                #endif
                self?.handleMIDIPacket(note)
            }
            .store(in: &cancellables)

        center.publisher(for: .liveTranscriptionDidPublish)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.recordRuntimeCounter("runtime.event.transcription.received")
                self?.handleLiveTranscriptionPublish(note)
            }
            .store(in: &cancellables)

        center.publisher(for: .dbReaderDidPublish)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.recordRuntimeCounter("runtime.event.dbReader.received")
                self?.handleDbReaderPublish(note)
            }
            .store(in: &cancellables)

        // Wireless + time trigger polling.
        SharedSecondTicker.shared.publisher
            .receive(on: queue)
            .sink { [weak self] now in
                self?.recordRuntimeCounter("runtime.event.secondTicker.received")
                self?.handleTriggerPoll(now)
            }
            .store(in: &cancellables)

        center.publisher(for: .relayPCOItemDidChange)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.handlePCOItemChanged(note)
            }
            .store(in: &cancellables)

        center.publisher(for: .relayProPresenterStateDidChange)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.handleProPresenterStateChanged(note)
            }
            .store(in: &cancellables)

        center.publisher(for: .relayLiveModeDidChange)
            .receive(on: queue)
            .sink { [weak self] note in self?.handleAppStateEvent(.enterLiveMode, note: note) }
            .store(in: &cancellables)

        center.publisher(for: .relayTabDidChange)
            .receive(on: queue)
            .sink { [weak self] note in self?.handleAppStateEvent(.tabSwitch, note: note) }
            .store(in: &cancellables)

        center.publisher(for: .relayAutomationDidLaunch)
            .receive(on: queue)
            .sink { [weak self] note in self?.handleAppStateEvent(.appLaunch, note: note) }
            .store(in: &cancellables)

        center.publisher(for: .relayAutomationDidLaunch)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resetLaunchResetNodes() }
            .store(in: &cancellables)

        center.publisher(for: Notification.Name("Relay.SetVariableActionFired"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.handleSetVariableActionFired(note)
            }
            .store(in: &cancellables)

        // Unified trigger bus (preferred) -> run downstream actions.
        center.publisher(for: TriggerNodeNotifications.fired)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.recordRuntimeCounter("runtime.event.triggerFired.received")
                self?.handleTriggerFired(note)
            }
            .store(in: &cancellables)

        // Back-compat trigger bus.
        center.publisher(for: .triggerNodeDidFire)
            .receive(on: queue)
            .sink { [weak self] note in
                self?.recordRuntimeCounter("runtime.event.triggerLegacy.received")
                self?.handleTriggerFiredLegacy(note)
            }
            .store(in: &cancellables)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .relayAutomationDidLaunch, object: nil)
        }
    }

    #if os(macOS)
    private func installLocalKeyMonitorIfNeeded() {
        DispatchQueue.main.async {
            guard self.localKeyMonitor == nil else { return }
            self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleLocalKeyEvent(event)
                return event
            }
        }
    }

    private func handleLocalKeyEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        guard NSApp.isActive else { return }

        let tabs = tabsToProcess()
        guard !tabs.isEmpty else { return }

        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            for (nodeKey, cfg) in graph.keystrokeTriggerConfigByNodeId {
                guard keystrokeConfigMatches(cfg, event: event) else { continue }
                guard let nodeId = UUID(uuidString: nodeKey) else { continue }
                let now = Date()
                let last = lastSynthesizedFireByTriggerId[nodeId] ?? 0
                guard now.timeIntervalSince1970 - last >= max(synthFireMinInterval, cfg.cooldownSeconds) else { continue }
                lastSynthesizedFireByTriggerId[nodeId] = now.timeIntervalSince1970

                NotificationCenter.default.post(
                    name: TriggerNodeNotifications.fired,
                    object: nil,
                    userInfo: [
                        TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                        TriggerNodeUserInfoKeys.payloadText: formattedShortcutLabel(cfg),
                        TriggerNodeUserInfoKeys.payloadBoolean: true,
                        "source": "runtime.keystroke",
                        "timestamp": now,
                        "eventKind": "keystroke.trigger"
                    ]
                )
            }
        }
    }

    private func keystrokeConfigMatches(_ cfg: DashboardGraph.KeystrokeTriggerConfig, event: NSEvent) -> Bool {
        let key = cfg.keyEquivalent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return false }
        guard cfg.allowsRepeat || !event.isARepeat else { return false }
        guard event.modifierFlags.contains(.command) == cfg.requiresCommand else { return false }
        guard event.modifierFlags.contains(.shift) == cfg.requiresShift else { return false }
        guard event.modifierFlags.contains(.option) == cfg.requiresOption else { return false }
        guard event.modifierFlags.contains(.control) == cfg.requiresControl else { return false }
        let characters = (event.charactersIgnoringModifiers ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return characters == key
    }

    private func formattedShortcutLabel(_ cfg: DashboardGraph.KeystrokeTriggerConfig) -> String {
        var parts: [String] = []
        if cfg.requiresCommand { parts.append("Cmd") }
        if cfg.requiresShift { parts.append("Shift") }
        if cfg.requiresOption { parts.append("Option") }
        if cfg.requiresControl { parts.append("Control") }
        let key = cfg.keyEquivalent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { parts.append(key.uppercased()) }
        return parts.joined(separator: "+")
    }
    #endif

    private func handleOSCPacket(_ note: Notification) {
        guard isEnabled else {
            #if DEBUG
            print("[AutomationRuntime] handleOSCPacket: ignored because isEnabled=false")
            #endif
            return
        }
        let ui = note.userInfo ?? [:]
        #if DEBUG
        print("[AutomationRuntime] handleOSCPacket: userInfo keys=\(Array(ui.keys))")
        #endif

        // Best-effort extraction: support multiple key spellings.
        let port: Int? =
            (ui["port"] as? Int)
            ?? (ui["localPort"] as? Int)
            ?? (ui["listenPort"] as? Int)
            ?? (ui["udpPort"] as? Int)
            ?? ((ui["port"] as? NSNumber)?.intValue)
            ?? ((ui["localPort"] as? NSNumber)?.intValue)

        let address: String? =
            (ui["address"] as? String)
            ?? (ui["oscAddress"] as? String)
            ?? (ui["path"] as? String)
        let payloadText = ui[TriggerNodeUserInfoKeys.payloadText] as? String
        let payloadNumber = ui[TriggerNodeUserInfoKeys.payloadNumber] as? Double
        let payloadBoolean = ui[TriggerNodeUserInfoKeys.payloadBoolean] as? Bool

        guard let port = port, let address = address, !address.isEmpty else {
            #if DEBUG
            print("[AutomationRuntime] handleOSCPacket: missing fields port=\(String(describing: port)) address=\(String(describing: address))")
            #endif
            return
        }

        #if DEBUG
        print("[AutomationRuntime] OSC packet observed port=\(port) address=\(address)")
        #endif

        // When graph trigger views are not mounted (Canvas mode), raise trigger fires here.
        let tabs = tabsToProcess()
        #if DEBUG
        let providerState = (activeTabProvider == nil) ? "nil" : "set"
        let providerReturned = (currentTabFromProvider() == nil) ? "nil" : "value"
        let cachedState = (readLastKnownActiveTab() == nil) ? "nil" : "value"
        print("[AutomationRuntime] tabsToProcess=\(tabs.count) activeTabProvider=\(providerState) providerReturned=\(providerReturned) cachedTab=\(cachedState) activeTabs=\(readActiveTabs().count)")
        #endif
        guard !tabs.isEmpty else {
            #if DEBUG
            print("[AutomationRuntime] OSC received but no tabs to process (provider returned nil and activeTabs empty).")
            #endif
            return
        }

        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else {
                #if DEBUG
                print("[AutomationRuntime] tab=\(tab.name) has no graph; skipping")
                #endif
                continue
            }

            var matchedCount = 0
            for (key, cfg) in graph.oscReceiveConfigByNodeId {
                let nodeId = resolveTriggerNodeId(key: key, cfgAny: cfg, graph: graph)
                guard oscReceiveConfigMatches(cfg: cfg, port: port, address: address) else { continue }
                guard shouldEmitOSCTrigger(nodeId: nodeId, graph: graph) else { continue }

                let now = Date().timeIntervalSince1970
                let last = lastSynthesizedFireByTriggerId[nodeId] ?? 0
                guard (now - last) >= synthFireMinInterval else { continue }
                lastSynthesizedFireByTriggerId[nodeId] = now

                matchedCount += 1
                postMatchedOSCTrigger(
                    nodeId: nodeId,
                    address: address,
                    port: port,
                    payloadText: payloadText,
                    payloadNumber: payloadNumber,
                    payloadBoolean: payloadBoolean
                )
            }

            #if DEBUG
            print("[AutomationRuntime] OSC matched \(matchedCount) trigger(s) on tab=\(tab.name) port=\(port) address=\(address)")
            #endif
        }
    }

    private func handleMIDIMessage(_ note: Notification) {
        guard isEnabled else { return }
        let ui = note.userInfo ?? [:]

        let kindRaw = (ui["kind"] as? String) ?? "programChange"
        let kind = MIDIMessageKind(rawValue: kindRaw) ?? .programChange

        let channel: Int? =
            (ui["channel"] as? Int)
            ?? ((ui["channel"] as? NSNumber)?.intValue)

        let program: Int? =
            (ui["program"] as? Int)
            ?? ((ui["program"] as? NSNumber)?.intValue)

        let noteNumber: Int? =
            (ui["note"] as? Int)
            ?? ((ui["note"] as? NSNumber)?.intValue)

        let velocity: Int? =
            (ui["velocity"] as? Int)
            ?? ((ui["velocity"] as? NSNumber)?.intValue)

        let control: Int? =
            (ui["control"] as? Int)
            ?? ((ui["control"] as? NSNumber)?.intValue)

        let value: Int? =
            (ui["value"] as? Int)
            ?? ((ui["value"] as? NSNumber)?.intValue)

        let sysex: [UInt8]? = ui["sysex"] as? [UInt8]

        let now = Date().timeIntervalSince1970
        var signature: String? = nil

        if let rawBytes = ui["rawBytes"] as? [UInt8] {
            signature = midiSignature(rawBytes)
        } else {
            signature = midiSignature(
                kind: kind,
                channel: channel,
                program: program,
                note: noteNumber,
                velocity: velocity,
                control: control,
                value: value,
                sysex: sysex
            )
        }

        if let signature {
            if let last = recentMidiSendBySignature[signature], (now - last) <= midiEchoSuppressWindow {
                return
            }
            pruneRecentMidiSends(now: now)
        }

        let tabs = tabsToProcess()
        guard !tabs.isEmpty else { return }

        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }

            var matchedCount = 0
            let mirror = Mirror(reflecting: graph)
            guard let dictChild = mirror.children.first(where: { $0.label == "midiReceiveConfigByNodeId" }) else {
                continue
            }
            let hasMidiReceiveNodes: Bool = {
                if let dict = dictChild.value as? [String: DashboardGraph.MIDIReceiveConfig] {
                    return !dict.isEmpty
                }
                if let dict = dictChild.value as? [UUID: DashboardGraph.MIDIReceiveConfig] {
                    return !dict.isEmpty
                }
                return !graph.moduleGroupNodeInstances.filter { $0.groupKey.contains("midiReceive") }.isEmpty
            }()
            guard hasMidiReceiveNodes else { continue }

            if let dict = dictChild.value as? [String: DashboardGraph.MIDIReceiveConfig] {
                for (k, cfg) in dict {
                    let nodeId = resolveTriggerNodeId(key: k, cfgAny: cfg, graph: graph)
                    if midiReceiveConfigMatches(
                        cfgAny: cfg,
                        kind: kind,
                        program: program,
                        channel: channel,
                        note: noteNumber,
                        control: control,
                        value: value,
                        sysex: sysex
                    ) {
                        let directConsoleIds = directLinkedConsoleExternalDeviceIds(graph: graph, triggerNodeId: nodeId)
                        guard hasExecutableDownstreamNodes(graph: graph, triggerNodeId: nodeId) || !directConsoleIds.isEmpty else { continue }

                        let now = Date().timeIntervalSince1970
                        let last = lastSynthesizedFireByTriggerId[nodeId] ?? 0
                        guard (now - last) >= synthFireMinInterval else { continue }
                        lastSynthesizedFireByTriggerId[nodeId] = now

                        matchedCount += 1
                        NotificationCenter.default.post(
                            name: TriggerNodeNotifications.fired,
                            object: nil,
                            userInfo: [
                                TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                                "source": "runtime.midi",
                                "timestamp": Date()
                            ]
                        )
                    }
                }
            }

            if let dict = dictChild.value as? [UUID: DashboardGraph.MIDIReceiveConfig] {
                for (k, cfg) in dict {
                    let nodeId = resolveTriggerNodeId(key: k.uuidString, cfgAny: cfg, graph: graph)
                    if midiReceiveConfigMatches(
                        cfgAny: cfg,
                        kind: kind,
                        program: program,
                        channel: channel,
                        note: noteNumber,
                        control: control,
                        value: value,
                        sysex: sysex
                    ) {
                        let directConsoleIds = directLinkedConsoleExternalDeviceIds(graph: graph, triggerNodeId: nodeId)
                        guard hasExecutableDownstreamNodes(graph: graph, triggerNodeId: nodeId) || !directConsoleIds.isEmpty else { continue }

                        let now = Date().timeIntervalSince1970
                        let last = lastSynthesizedFireByTriggerId[nodeId] ?? 0
                        guard (now - last) >= synthFireMinInterval else { continue }
                        lastSynthesizedFireByTriggerId[nodeId] = now

                        matchedCount += 1
                        NotificationCenter.default.post(
                            name: TriggerNodeNotifications.fired,
                            object: nil,
                            userInfo: [
                                TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                                "source": "runtime.midi",
                                "timestamp": Date()
                            ]
                        )
                    }
                }
            }

            #if DEBUG
            print("[AutomationRuntime] MIDI matched \(matchedCount) trigger(s) on tab=\(tab.name) kind=\(kind.rawValue)")
            #endif

        }
    }

    private func handleMIDIPacket(_ note: Notification) {
        var info = note.userInfo ?? [:]
        info["kind"] = "programChange"
        let wrapped = Notification(
            name: .midiReceiveMessageDidArrive,
            object: note.object,
            userInfo: info
        )
        handleMIDIMessage(wrapped)
    }

    private func handleMIDISendEchoGuard(_ note: Notification) {
        let ui = note.userInfo ?? [:]
        guard let rawBytes = ui[ActionNodeUserInfoKeys.midiBytes] as? [UInt8] else { return }
        let signature = midiSignature(rawBytes)
        recentMidiSendBySignature[signature] = Date().timeIntervalSince1970
    }

    private func midiSignature(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func midiSignature(
        kind: MIDIMessageKind,
        channel: Int?,
        program: Int?,
        note: Int?,
        velocity: Int?,
        control: Int?,
        value: Int?,
        sysex: [UInt8]?
    ) -> String {
        switch kind {
        case .noteOn:
            return "noteOn:\(channel ?? -1):\(note ?? -1):\(velocity ?? -1)"
        case .noteOff:
            return "noteOff:\(channel ?? -1):\(note ?? -1):\(velocity ?? -1)"
        case .programChange:
            return "program:\(channel ?? -1):\(program ?? -1)"
        case .controlChange:
            return "cc:\(channel ?? -1):\(control ?? -1):\(value ?? -1)"
        case .sysex:
            if let sysex {
                return "sysex:\(midiSignature(sysex))"
            }
            return "sysex:"
        }
    }

    private func pruneRecentMidiSends(now: TimeInterval) {
        recentMidiSendBySignature = recentMidiSendBySignature.filter { (_, ts) in
            (now - ts) <= midiEchoSuppressWindow
        }
    }

    private func handleLiveTranscriptionPublish(_ note: Notification) {
        guard isEnabled else { return }
        guard let ui = note.userInfo,
              let tileId = ui["tileId"] as? UUID,
              let payload = ui["payload"] as? TranscriptOutputPayload,
              let latest = payload.latestEntry else { return }

        let tabs = tabsToProcess()
        guard !tabs.isEmpty else { return }

        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            var candidateNodeIds: [UUID] = graph.wordTriggerConfigByNodeId.keys.compactMap(UUID.init(uuidString:))

            // Include canvas-backed transcription node (if present on this tab)
            let transcriptionNodeId: UUID? = tab.tiles.contains(where: { tile in
                (tile.modules ?? []).contains { module in
                    if case .liveTranscription = module.kind { return true }
                    return false
                }
            }) ? groupNodeId(for: tab.id, groupKey: "moduleGroup.transcription") : nil
            if let transcriptionNodeId {
                candidateNodeIds.append(transcriptionNodeId)
            }

            candidateNodeIds = Array(Set(candidateNodeIds))
            guard !candidateNodeIds.isEmpty else { continue }

            var sourceNodeIds: [UUID] = [tileId]
            if let transcriptionNodeId { sourceNodeIds.append(transcriptionNodeId) }

            let isUniversal = (tab.automationMode == .universal)
            // Per-entry phrase dedup: prevents two configs with the same phrase (e.g. a
            // standalone word trigger node + the canvas transcription node both having "hello")
            // from firing the same action twice for a single transcript entry.
            var firedPhrases: Set<String> = []
            for nodeId in candidateNodeIds {
                if nodeId != transcriptionNodeId && !isUniversal {
                    // Per-tab graphs keep the explicit tile-link requirement.
                    guard isLinked(fromNodeIds: sourceNodeIds, toNodeId: nodeId, graph: graph) else { continue }
                }
                let cfg = graph.wordTriggerConfigByNodeId[nodeId.uuidString] ?? DashboardGraph.WordTriggerConfig()
                for rule in cfg.rules {
                    guard shouldFireWordRule(rule, entry: latest) else { continue }
                    let phraseKey = rule.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard firedPhrases.insert(phraseKey).inserted else { continue }
                    postWordTrigger(nodeId: nodeId, rule: rule, entry: latest)
                }
            }
        }
    }

    private func handleDbReaderPublish(_ note: Notification) {
        guard isEnabled else { return }
        guard let ui = note.userInfo,
              let tileId = ui["tileId"] as? UUID,
              let payload = ui["payload"] as? DbReaderOutputPayload else { return }

        if payload.isStale { return }

        let tabs = tabsToProcess()
        guard !tabs.isEmpty else { return }

        func value(for metric: DashboardGraph.DbThresholdMetric, payload: DbReaderOutputPayload) -> Double {
            switch metric {
            case .spl:
                return payload.spl
            case .peak:
                return payload.peak
            case .rawDbFS:
                return payload.rawDbFS
            case .rawPeakDbFS:
                return payload.rawPeakDbFS
            }
        }

        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            let dbNodes = graph.moduleGroupNodeInstances.filter { $0.groupKey.contains("dbThreshold") }
            var candidateNodeIds: [UUID] = dbNodes.map { $0.id }

            let dbReaderTileIds: [UUID] = tab.tiles.compactMap { tile in
                let hasDbReader = (tile.modules ?? []).contains { module in
                    if case .dbReader = module.kind { return true }
                    return false
                }
                return hasDbReader ? tile.id : nil
            }
            let hasDbReader = !dbReaderTileIds.isEmpty
            let hasSingleDbReader = dbReaderTileIds.count == 1

            if hasDbReader {
                candidateNodeIds.append(groupNodeId(for: tab.id, groupKey: "moduleGroup.dbThreshold"))
            }

            candidateNodeIds = Array(Set(candidateNodeIds))
            guard !candidateNodeIds.isEmpty else { continue }

            let sourceNodeIds: [UUID] = [tileId]

            let isUniversal = (tab.automationMode == .universal)
            for nodeId in candidateNodeIds {
                let isExplicitlyLinked = isLinked(fromNodeIds: sourceNodeIds, toNodeId: nodeId, graph: graph)
                if !isUniversal && !isExplicitlyLinked && !hasSingleDbReader { continue }

                let cfg = graph.dbThresholdConfigByNodeId[nodeId.uuidString] ?? DashboardGraph.DbThresholdTriggerConfig()
                let metricValue = value(for: cfg.metric, payload: payload)
                let shouldFire: Bool = {
                    switch cfg.comparison {
                    case .above:
                        return metricValue >= cfg.threshold
                    case .below:
                        return metricValue <= cfg.threshold
                    }
                }()

                guard shouldFire else { continue }

                let now = Date().timeIntervalSince1970
                let cooldown = max(0, cfg.cooldownSeconds)
                if let last = lastDbThresholdFireByNodeId[nodeId], (now - last) < cooldown { continue }
                lastDbThresholdFireByNodeId[nodeId] = now

                let info: [AnyHashable: Any] = [
                    TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                    "source": "runtime.dbReader",
                    "timestamp": Date(),
                    "metric": cfg.metric.rawValue,
                    "comparison": cfg.comparison.rawValue,
                    "threshold": cfg.threshold,
                    "value": metricValue,
                    "tileId": tileId
                ]

                NotificationCenter.default.post(name: TriggerNodeNotifications.fired, object: nil, userInfo: info)
            }
        }
    }

    // NOTE: This currently fires when `pcoRundownSnapshotTitles` changes (plan loaded/refreshed),
    // not when the live-service current item advances. PCO Live integration (subscribe to PCO's
    // Live API WebSocket to track the current item in real time) is the planned future path.
    private func handlePCOItemChanged(_ note: Notification) {
        guard isEnabled else { return }
        let titles = (note.userInfo?["titles"] as? [String]) ?? []
        let cleanTitles = titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let firstTitle = cleanTitles.first ?? ""

        let tabs = tabsToProcess()
        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            for (key, cfg) in graph.pcoItemChangedConfigByNodeId {
                let nodeId = resolveTriggerNodeId(key: key, cfgAny: cfg, graph: graph)

                let filter = cfg.titleFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                if !filter.isEmpty {
                    // Exact match against any item in the new titles list (case-insensitive).
                    // The UI picker sets the filter to a full title string, so use equality not contains.
                    let matched = cleanTitles.contains { $0.caseInsensitiveCompare(filter) == .orderedSame }
                    guard matched else { continue }
                }

                let now = Date().timeIntervalSince1970
                let last = lastSynthesizedFireByTriggerId[nodeId] ?? 0
                guard (now - last) >= max(synthFireMinInterval, cfg.cooldownSeconds) else { continue }
                lastSynthesizedFireByTriggerId[nodeId] = now

                guard hasExecutableDownstreamNodes(graph: graph, triggerNodeId: nodeId)
                      || !directLinkedConsoleExternalDeviceIds(graph: graph, triggerNodeId: nodeId).isEmpty
                else { continue }

                NotificationCenter.default.post(
                    name: TriggerNodeNotifications.fired,
                    object: nil,
                    userInfo: [
                        TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                        TriggerNodeUserInfoKeys.payloadText: firstTitle,
                        "source": "runtime.pcoItemChanged",
                        "timestamp": Date()
                    ]
                )
            }
        }
    }

    private func handleProPresenterStateChanged(_ note: Notification) {
        guard isEnabled else { return }
        guard let eventRaw = note.userInfo?["event"] as? String,
              let event = DashboardGraph.ProPresenterTriggerEvent(rawValue: eventRaw) else { return }
        let notificationResolvedProfileId = note.userInfo?["resolvedProfileId"] as? UUID
        let value = note.userInfo?["value"] as? String
        let numberValue = note.userInfo?["numberValue"] as? Double

        let tabs = tabsToProcess()
        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            for (key, cfg) in graph.proPresenterTriggerConfigByNodeId {
                let cfgResolvedProfileId = ProPresenterProfilesStore.resolvedProfileIdentity(configuredProfileId: cfg.profileId)

                guard proPresenterTriggerShouldFire(
                    cfg: cfg,
                    cfgResolvedProfileId: cfgResolvedProfileId,
                    notificationResolvedProfileId: notificationResolvedProfileId,
                    notificationEvent: event,
                    notificationValue: value
                ) else { continue }

                let nodeId = resolveTriggerNodeId(key: key, cfgAny: cfg, graph: graph)

                let now = Date().timeIntervalSince1970
                let last = lastSynthesizedFireByTriggerId[nodeId] ?? 0
                guard (now - last) >= max(synthFireMinInterval, cfg.cooldownSeconds) else { continue }
                lastSynthesizedFireByTriggerId[nodeId] = now

                guard hasExecutableDownstreamNodes(graph: graph, triggerNodeId: nodeId)
                      || !directLinkedConsoleExternalDeviceIds(graph: graph, triggerNodeId: nodeId).isEmpty
                else { continue }

                NotificationCenter.default.post(
                    name: TriggerNodeNotifications.fired,
                    object: nil,
                    userInfo: [
                        TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                        TriggerNodeUserInfoKeys.payloadText: value ?? "",
                        TriggerNodeUserInfoKeys.payloadNumber: numberValue as Any,
                        "source": "runtime.proPresenterStateChanged",
                        "timestamp": Date()
                    ]
                )
            }
        }
    }

    private func handleAppStateEvent(
        _ eventKind: DashboardGraph.AppStateTriggerConfig.EventKind,
        note: Notification
    ) {
        guard isEnabled else { return }

        if eventKind == .enterLiveMode || eventKind == .exitLiveMode {
            let isLive = (note.userInfo?["isLiveMode"] as? Bool) ?? false
            let wantEnter = (eventKind == .enterLiveMode)
            guard isLive == wantEnter else { return }
        }

        let tabs = tabsToProcess()
        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            for (key, cfg) in graph.appStateTriggerConfigByNodeId where cfg.eventKind == eventKind {
                let nodeId = resolveTriggerNodeId(key: key, cfgAny: cfg, graph: graph)
                let now = Date().timeIntervalSince1970
                let last = lastSynthesizedFireByTriggerId[nodeId] ?? 0
                guard (now - last) >= max(synthFireMinInterval, cfg.cooldownSeconds) else { continue }
                lastSynthesizedFireByTriggerId[nodeId] = now

                guard hasExecutableDownstreamNodes(graph: graph, triggerNodeId: nodeId)
                      || !directLinkedConsoleExternalDeviceIds(graph: graph, triggerNodeId: nodeId).isEmpty
                else { continue }

                NotificationCenter.default.post(
                    name: TriggerNodeNotifications.fired,
                    object: nil,
                    userInfo: [
                        TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                        "source": "runtime.appState.\(eventKind.rawValue)",
                        "timestamp": Date()
                    ]
                )
            }
        }
    }

    @MainActor
    private func handleSetVariableActionFired(_ note: Notification) {
        guard let cfg = note.userInfo?["config"] as? DashboardGraph.SetVariableActionConfig,
              let targetId = cfg.targetVariableNodeId else { return }

        let tabs = tabsToProcess()
        for tab in tabs {
            guard var graph = effectiveGraph(for: tab),
                  var varCfg = graph.variableNodeConfigByNodeId[targetId.uuidString]
            else { continue }

            GraphRuntime.applySetVariableAction(cfg, to: &varCfg)
            graph.variableNodeConfigByNodeId[targetId.uuidString] = varCfg
            persistUpdatedGraph(graph, for: tab.id)
        }
    }

    private func resetLaunchResetNodes() {
        let tabs = tabsToProcess()
        for tab in tabs {
            guard var graph = effectiveGraph(for: tab) else { continue }
            var mutated = false

            for (key, var cfg) in graph.toggleNodeConfigByNodeId where cfg.resetOnLaunch {
                cfg.currentState = false
                graph.toggleNodeConfigByNodeId[key] = cfg
                mutated = true
            }
            for (key, var cfg) in graph.counterNodeConfigByNodeId where cfg.resetOnLaunch {
                cfg.currentCount = 0
                graph.counterNodeConfigByNodeId[key] = cfg
                mutated = true
            }
            for (key, var cfg) in graph.sequenceNodeConfigByNodeId where cfg.resetOnLaunch {
                cfg.currentStep = 0
                graph.sequenceNodeConfigByNodeId[key] = cfg
                mutated = true
            }
            for (key, var cfg) in graph.latchNodeConfigByNodeId where cfg.resetOnLaunch {
                cfg.isEnabled = true
                graph.latchNodeConfigByNodeId[key] = cfg
                mutated = true
            }

            if mutated {
                persistUpdatedGraph(graph, for: tab.id)
            }
        }
    }

    private func groupNodeId(for tabId: UUID, groupKey: String) -> UUID {
        let data = Data((tabId.uuidString + "|" + groupKey).utf8)
        let digest = SHA256.hash(data: data)
        let byteArray = Array(digest.prefix(16))
        var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuidBytes) { buf in
            buf.copyBytes(from: byteArray)
        }
        return UUID(uuid: uuidBytes)
    }

    private func shouldFireWordRule(_ rule: DashboardGraph.WordTriggerRule, entry: TranscriptEntry) -> Bool {
        let now = Date().timeIntervalSince1970

        if rule.finalOnly && !entry.isFinal { return false }
        if let minConfidence = rule.minimumConfidence, let confidence = entry.confidence, confidence < minConfidence { return false }
        if !rule.sourceIds.isEmpty && !rule.sourceIds.contains(entry.sourceId) { return false }

        // Always add 0.5s to the user-configured cooldown so that interim (non-final)
        // transcript results don't double-fire when the confirmed final result arrives
        // shortly after. A user setting of 0 gives an effective cooldown of 0.5s.
        let cooldown = rule.cooldownSeconds + 0.5
        if let last = lastWordTriggerFireByRuleId[rule.id], (now - last) < cooldown { return false }

        let debounce = max(0, rule.debounceSeconds)
        if debounce > 0 {
            if let lastMatch = lastWordTriggerMatchByRuleId[rule.id], (now - lastMatch) < debounce { return false }
        }

        let haystack = entry.rawText
        let needle = rule.phrase.lowercased()
        let text = haystack.lowercased()
        guard !needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        _ = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let matchCount: Int
        switch rule.matchMode {
        case .contains:
            matchCount = countOccurrences(of: needle, in: text)
        case .wholeWord:
            matchCount = matchWholeWordCount(needle: needle, in: text, ruleId: rule.id)
        }

        guard matchCount > 0 else { return false }

        if let lastEntryId = lastWordTriggerEntryIdByRuleId[rule.id], lastEntryId == entry.id {
            let previousCount = lastWordTriggerMatchCountByRuleId[rule.id] ?? 0
            guard matchCount > previousCount else { return false }
        }

        lastWordTriggerMatchByRuleId[rule.id] = now
        lastWordTriggerFireByRuleId[rule.id] = now
        lastWordTriggerEntryIdByRuleId[rule.id] = entry.id
        lastWordTriggerMatchCountByRuleId[rule.id] = matchCount
        return true
    }

    private func countOccurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty, !text.isEmpty else { return 0 }
        var count = 0
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: needle, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private func matchWholeWordCount(needle: String, in text: String, ruleId: UUID) -> Int {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
        return matchRegexCount(pattern: pattern, in: text, ruleId: ruleId)
    }

    private func matchRegexCount(pattern: String, in text: String, ruleId: UUID) -> Int {
        let regex: NSRegularExpression
        if let cached = wordTriggerRegexCache[ruleId], cached.pattern == pattern {
            regex = cached.regex
        } else {
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: []) else { return 0 }
            wordTriggerRegexCache[ruleId] = (pattern: pattern, regex: compiled)
            regex = compiled
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    private func matchWholeWord(needle: String, in text: String, ruleId: UUID) -> Bool {
        matchWholeWordCount(needle: needle, in: text, ruleId: ruleId) > 0
    }

    private func matchRegex(pattern: String, in text: String, ruleId: UUID) -> Bool {
        matchRegexCount(pattern: pattern, in: text, ruleId: ruleId) > 0
    }

    private func postWordTrigger(nodeId: UUID, rule: DashboardGraph.WordTriggerRule, entry: TranscriptEntry) {
        let info: [AnyHashable: Any] = [
            TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
            "matchPhrase": rule.phrase,
            "matchedRuleId": rule.id,
            "sourceId": entry.sourceId.uuidString,
            "sourceName": entry.sourceDisplayName,
            "matchedText": entry.displayText,
            "timestamp": entry.timestamp
        ]
        NotificationCenter.default.post(name: TriggerNodeNotifications.fired, object: nil, userInfo: info)
    }

    private func isLinked(fromNodeIds: [UUID], toNodeId: UUID, graph: DashboardGraph) -> Bool {
        let sourceIds = Set(fromNodeIds)
        for link in graph.links where link.isEnabled {
            if !sourceIds.contains(link.fromTileId) {
                if let resolvedFrom = resolveNodeId(fromPortId: link.fromPortId, graph: graph),
                   sourceIds.contains(resolvedFrom) {
                    // ok
                } else {
                    continue
                }
            }
            let resolved = graph.nodeIdByPortId[link.toPortId] ?? link.toTileId
            if resolved == toNodeId { return true }
        }
        return false
    }

    /// Pure decision: should a ProPresenterTriggerConfig fire, given the resolved profile
    /// identities of both the trigger's configuration and the poll that produced this
    /// notification, plus what actually changed. No NotificationCenter/cooldown/graph
    /// lookup involved -- those are handleProPresenterStateChanged's job below.
    func proPresenterTriggerShouldFire(
        cfg: DashboardGraph.ProPresenterTriggerConfig,
        cfgResolvedProfileId: UUID?,
        notificationResolvedProfileId: UUID?,
        notificationEvent: DashboardGraph.ProPresenterTriggerEvent,
        notificationValue: String?
    ) -> Bool {
        guard cfg.event == notificationEvent else { return false }
        guard cfgResolvedProfileId == notificationResolvedProfileId else { return false }

        let filter = cfg.filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return true }

        guard let value = notificationValue else { return false }
        return value.caseInsensitiveCompare(filter) == .orderedSame
    }

    private func resolveTriggerNodeId(key: String, cfgAny: Any, graph: DashboardGraph) -> UUID {
        // Prefer the dictionary key if it is a UUID AND exists as a node instance.
        if let kId = UUID(uuidString: key), graph.moduleGroupNodeInstances.contains(where: { $0.id == kId }) {
            return kId
        }

        // If the config has an explicit nodeId, prefer it.
        let m = Mirror(reflecting: cfgAny)
        if let nodeId = m.children.first(where: { $0.label == "nodeId" })?.value as? UUID {
            return nodeId
        }

        // Many configs store their own id. Use it if it exists as a node instance.
        if let cfgId = m.children.first(where: { $0.label == "id" })?.value as? UUID,
           graph.moduleGroupNodeInstances.contains(where: { $0.id == cfgId }) {
            return cfgId
        }

        // Fallback to UUID(key) or cfg.id.
        if let kId = UUID(uuidString: key) { return kId }
        if let cfgId = m.children.first(where: { $0.label == "id" })?.value as? UUID { return cfgId }
        return UUID()
    }

    // MARK: - Trigger -> Action execution

    private func handleTriggerPoll(_ now: Date) {
        guard isEnabled else { return }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let tabs = tabsToProcess()
        guard !tabs.isEmpty else { return }

        var emittedEvents = 0
        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            let pollResult = GraphTriggerPoller.poll(graph: graph, now: now)
            let events = pollResult.events
            for metric in pollResult.familyMetrics where metric.configCount > 0 {
                let details = "tabs=\(tabs.count) configs=\(metric.configCount) events=\(metric.emittedCount)"
                recordRuntimePerf(
                    "runtime.triggerPoll.\(metric.name)",
                    duration: metric.duration,
                    details: details,
                    slowThreshold: 0.010
                )
            }
            guard !events.isEmpty else { continue }
            emittedEvents += events.count

            for event in events {
                let triggerId = event.sourceNodeId
                let directConsoleIds = directLinkedConsoleExternalDeviceIds(graph: graph, triggerNodeId: triggerId)
                guard hasExecutableDownstreamNodes(graph: graph, triggerNodeId: triggerId) || !directConsoleIds.isEmpty else { continue }

                NotificationCenter.default.post(
                    name: TriggerNodeNotifications.fired,
                    object: nil,
                    userInfo: [
                        TriggerNodeUserInfoKeys.triggerNodeId: triggerId,
                        "source": "runtime.wireless",
                        "timestamp": now
                    ]
                )
            }
        }
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        let details = "tabs=\(tabs.count) events=\(emittedEvents)"
        recordRuntimePerf(
            "runtime.triggerPoll",
            duration: duration,
            details: details,
            slowThreshold: 0.020
        )
        if emittedEvents > 0 {
            recordRuntimeCounter("runtime.triggerPoll.eventsEmitted", by: emittedEvents)
        }

        // Update Current Time source node values every tick.
        for tab in tabs {
            guard var graph = effectiveGraph(for: tab) else { continue }
            var timeMutated = false
            for (key, cfg) in graph.currentTimeSourceConfigByNodeId {
                guard UUID(uuidString: key) != nil else { continue }
                let value = currentTimeValue(format: cfg.format, date: now)
                if var varCfg = graph.variableNodeConfigByNodeId[key] {
                    varCfg.currentTextValue = value
                    graph.variableNodeConfigByNodeId[key] = varCfg
                    timeMutated = true
                }
            }
            if timeMutated {
                persistUpdatedGraph(graph, for: tab.id)
            }
        }
    }

    private func currentTimeValue(format: DashboardGraph.CurrentTimeSourceConfig.Format, date: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        switch format {
        case .timeOfDay:
            return String(format: "%02d:%02d:%02d", h, m, s)
        case .timeOfDayShort:
            return String(format: "%02d:%02d", h, m)
        case .secondsSinceMidnight:
            return String(h * 3600 + m * 60 + s)
        case .unixTimestamp:
            return String(Int(date.timeIntervalSince1970))
        }
    }

    private func handleTriggerFired(_ note: Notification) {
        guard isEnabled else { return }
        let ui = note.userInfo ?? [:]

        let triggerId: UUID? =
            (ui[TriggerNodeUserInfoKeys.triggerNodeId] as? UUID)
            ?? ({
                if let s = ui[TriggerNodeUserInfoKeys.triggerNodeId] as? String { return UUID(uuidString: s) }
                return nil
            })()
            ?? (note.object as? UUID)
            ?? ({
                if let s = note.object as? String { return UUID(uuidString: s) }
                return nil
            })()

        guard let id = triggerId else { return }

        let now = Date().timeIntervalSince1970

        // Route via rule-scoped port when available; fall back to legacy node port.
        if let ruleId = ui["matchedRuleId"] as? UUID {
            // Per-rule dedup: allows independent rules on the same node to fire concurrently.
            let ruleKey = "\(id.uuidString):\(ruleId.uuidString)"
            let lastRule = lastTriggerFireByRuleKey[ruleKey] ?? 0
            if (now - lastRule) < triggerFireMinInterval {
                #if DEBUG
                print("[AutomationRuntime] Word trigger rule duplicate ignored nodeId=\(id) ruleId=\(ruleId)")
                #endif
                return
            }
            lastTriggerFireByRuleKey[ruleKey] = now

            #if DEBUG
            print("[AutomationRuntime] Word trigger rule fired nodeId=\(id) ruleId=\(ruleId)")
            #endif

            let rulePortId = GraphAutomationTraversal.wordTriggerRulePortId(nodeId: id, ruleId: ruleId)
            let tabs = tabsToProcess()
            let hasRuleLinks = tabs.contains { tab in
                (effectiveGraph(for: tab)?.links ?? []).contains {
                    $0.isEnabled && $0.fromPortId == rulePortId
                }
            }
            if hasRuleLinks {
                runDownstreamActions(from: id, sourcePortId: rulePortId, userInfo: ui)
            } else {
                // Legacy back-compat: fall through to node-level dedup and dispatch.
                let last = lastTriggerFireById[id] ?? 0
                if (now - last) < triggerFireMinInterval { return }
                lastTriggerFireById[id] = now
                runDownstreamActions(from: id, userInfo: ui)
            }
            return
        }

        // Global de-dupe for non-rule triggers: if both Trigger view and runtime post fired, execute once.
        let last = lastTriggerFireById[id] ?? 0
        if (now - last) < triggerFireMinInterval {
            #if DEBUG
            print("[AutomationRuntime] Trigger fired duplicate ignored id=\(id)")
            #endif
            return
        }
        lastTriggerFireById[id] = now

        #if DEBUG
        print("[AutomationRuntime] Trigger fired id=\(id)")
        #endif

        // Multi-button: route to specific output port
        if let buttonConfigId = ui["buttonConfigId"] as? UUID {
            let portId = GraphAutomationTraversal.buttonOutputPortId(nodeId: id, buttonConfigId: buttonConfigId)
            runDownstreamActions(from: id, sourcePortId: portId, userInfo: ui)
            return
        }

        runDownstreamActions(from: id, userInfo: ui)
    }

    private func handleTriggerFiredLegacy(_ note: Notification) {
        guard isEnabled else { return }
        let ui = note.userInfo ?? [:]
        func accept(_ id: UUID) -> Bool {
            let now = Date().timeIntervalSince1970
            let last = lastTriggerFireById[id] ?? 0
            if (now - last) < triggerFireMinInterval {
                #if DEBUG
                print("[AutomationRuntime] Legacy trigger duplicate ignored id=\(id)")
                #endif
                return false
            }
            lastTriggerFireById[id] = now
            return true
        }
        if let id = ui["nodeId"] as? UUID {
            guard accept(id) else { return }
            runDownstreamActions(from: id, userInfo: ui)
            return
        }
        if let s = ui["nodeId"] as? String, let id = UUID(uuidString: s) {
            guard accept(id) else { return }
            runDownstreamActions(from: id, userInfo: ui)
            return
        }
        if let s = ui["nodeIdString"] as? String, let id = UUID(uuidString: s) {
            guard accept(id) else { return }
            runDownstreamActions(from: id, userInfo: ui)
            return
        }
    }

    private func runDownstreamActions(from triggerNodeId: UUID, userInfo: [AnyHashable: Any]) {
        recordRuntimeCounter("runtime.downstreamActions.started")
        let tabs = tabsToProcess()
        guard !tabs.isEmpty else { return }
        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            let payload = graphTriggerPayload(from: userInfo, sourceNodeId: triggerNodeId)

            Task { @MainActor in
                let startedAt = CFAbsoluteTimeGetCurrent()
                let latestTab = latestTabSnapshot(for: tab.id, fallback: tab)
                let baselineGraph = effectiveGraph(for: latestTab) ?? graph
                var liveGraph = baselineGraph
                let context = makeExecutionContext(tab: latestTab, graph: liveGraph)
                await executeGraphFlow(
                    from: triggerNodeId,
                    payload: payload,
                    graph: &liveGraph,
                    tab: latestTab,
                    context: context,
                    visited: []
                )
                if liveGraph != baselineGraph {
                    persistUpdatedGraph(liveGraph, for: latestTab.id)
                }
                let duration = CFAbsoluteTimeGetCurrent() - startedAt
                let details = "tab=\(latestTab.id.uuidString.prefix(6)) links=\(liveGraph.links.count) mutated=\(liveGraph != baselineGraph)"
                self.recordRuntimePerf(
                    "runtime.downstreamActions.executeGraphFlow",
                    duration: duration,
                    details: details,
                    slowThreshold: 0.020
                )
            }
        }
    }

    private func graphTriggerPayload(from userInfo: [AnyHashable: Any], sourceNodeId: UUID) -> GraphTriggerPayload {
        GraphTriggerPayload(
            sourceNodeId: sourceNodeId,
            eventKind: userInfo["eventKind"] as? String,
            text: (userInfo[TriggerNodeUserInfoKeys.payloadText] as? String) ?? (userInfo[SmartLightActionUserInfoKeys.message] as? String),
            number: userInfo[TriggerNodeUserInfoKeys.payloadNumber] as? Double,
            boolean: userInfo[TriggerNodeUserInfoKeys.payloadBoolean] as? Bool,
            address: userInfo[TriggerNodeUserInfoKeys.address] as? String,
            localPort: userInfo[TriggerNodeUserInfoKeys.localPort] as? Int,
            dataJSON: userInfo[SmartLightActionUserInfoKeys.stateJSON] as? String
        )
    }

    private func handleSmartLightCompletion(_ note: Notification, outcome: String) {
        guard let nodeId = note.userInfo?[SmartLightActionUserInfoKeys.nodeId] as? UUID else { return }
        let userInfo = note.userInfo ?? [:]
        let portId = GraphAutomationTraversal.smartLightOutputPortId(nodeId: nodeId, kind: outcome)
        runDownstreamActions(from: nodeId, sourcePortId: portId, userInfo: userInfo)
    }

    private func runDownstreamActions(from triggerNodeId: UUID, sourcePortId: String, userInfo: [AnyHashable: Any]) {
        recordRuntimeCounter("runtime.downstreamActions.started")
        let tabs = tabsToProcess()
        guard !tabs.isEmpty else { return }
        for tab in tabs {
            guard let graph = effectiveGraph(for: tab) else { continue }
            let payload = graphTriggerPayload(from: userInfo, sourceNodeId: triggerNodeId)
            Task { @MainActor in
                let latestTab = latestTabSnapshot(for: tab.id, fallback: tab)
                let baselineGraph = effectiveGraph(for: latestTab) ?? graph
                var liveGraph = baselineGraph
                let context = makeExecutionContext(tab: latestTab, graph: liveGraph)
                await executeGraphFlow(
                    from: triggerNodeId,
                    sourcePortId: sourcePortId,
                    payload: payload,
                    graph: &liveGraph,
                    tab: latestTab,
                    context: context,
                    visited: []
                )
                if liveGraph != baselineGraph {
                    persistUpdatedGraph(liveGraph, for: latestTab.id)
                }
            }
        }
    }

    @MainActor
    private func makeExecutionContext(tab: DashboardTab, graph: DashboardGraph) -> GraphActionExecutor.ExecutionContext {
        let snapshotDevices = ExternalDevicesStore.shared.currentSnapshot().devices
        let allIds = extractExternalDeviceIds(from: snapshotDevices)

        return GraphActionExecutor.ExecutionContext(
            consoleExternalDeviceIds: allIds,
            consolePosition: nil,
            pcoRundownSnapshotTitles: { tab.pcoRundownSnapshotTitles },
            externalSnapshotDevices: snapshotDevices,
            linkedSourceTextForDestinationNode: { destinationNodeId, graph in
                for link in graph.links where link.isEnabled && link.kind == .patch {
                    let toId = self.resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId
                    guard toId == destinationNodeId else { continue }
                    let fromId = self.resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
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
                    let toId = self.resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId
                    guard toId == destinationNodeId else { continue }
                    let fromId = self.resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
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
    }

    @MainActor
    private func executeGraphFlow(
        from sourceNodeId: UUID,
        sourcePortId: String? = nil,
        payload: GraphTriggerPayload,
        graph: inout DashboardGraph,
        tab: DashboardTab,
        context: GraphActionExecutor.ExecutionContext,
        visited: Set<String>
    ) async {
        let visitKey = "\(sourceNodeId.uuidString)|\(sourcePortId ?? "*")"
        guard !visited.contains(visitKey) else { return }
        let nextVisited = visited.union([visitKey])

        // Check each directly linked console node for a binding to this trigger.
        let linkedNodeIds = directLinkedConsoleNodeIds(graph: graph, sourceNodeId: sourceNodeId, sourcePortId: sourcePortId)
        for consoleNodeId in linkedNodeIds {
            let config = graph.consoleTriggerSendConfigByNodeId[consoleNodeId.uuidString]
                ?? DashboardGraph.ConsoleTriggerSendConfig()
            let sendAssignments = config.assignmentsTriggerNodeId == sourceNodeId
            let sendSnapshots = config.snapshotsTriggerNodeId == sourceNodeId
            guard sendAssignments || sendSnapshots else { continue }
            guard let deviceId = externalDeviceIdForConsoleNode(graph: graph, nodeId: consoleNodeId) else { continue }
            NotificationCenter.default.post(
                name: .prodlinkGraphSendAllToConsoles,
                object: [deviceId],
                userInfo: [
                    GraphSendAllUserInfoKeys.delayMs: 0.0,
                    GraphSendAllUserInfoKeys.includeAssignments: sendAssignments,
                    GraphSendAllUserInfoKeys.includeSnapshots: sendSnapshots,
                    GraphSendAllUserInfoKeys.bypassPCOLinkFilter: true
                ]
            )
        }

        runQuConsoleActionsIfConfigured(graph: graph, sourceNodeId: sourceNodeId)
        runDigiCoConsoleActionsIfConfigured(graph: graph, sourceNodeId: sourceNodeId)
        runStandardConsoleActionsIfConfigured(graph: graph, sourceNodeId: sourceNodeId)

        let downstream = GraphAutomationTraversal.downstreamConnections(
            graph: graph,
            sourceNodeId: sourceNodeId,
            sourcePortId: sourcePortId,
            resolveNodeIdFromPortId: { self.resolveNodeId(fromPortId: $0, graph: graph) }
        )
        guard !downstream.isEmpty else { return }

        for connection in downstream where connection.targetGroupKey == "utility.variable" {
            GraphRuntime.updateVariableNodeValue(
                graph: &graph,
                nodeId: connection.targetNodeId,
                payloadText: payload.text,
                payloadNumber: payload.number,
                payloadBoolean: payload.boolean,
                sourceNodeId: payload.sourceNodeId
            )
        }

        for connection in downstream {
            guard let key = connection.targetGroupKey else { continue }

            if key.hasPrefix("action.") {
                executeActionNode(
                    nodeId: connection.targetNodeId,
                    key: key,
                    graph: graph,
                    context: context
                )
                continue
            }

            if key == "destination.vista" {
                executeVistaDestinationNode(
                    nodeId: connection.targetNodeId,
                    payload: payload,
                    graph: graph,
                    context: context
                )
                continue
            }

            if key == "utility.delay" {
                let delayMs = max(0, graph.delayActionConfigByNodeId[connection.targetNodeId.uuidString]?.delayMs ?? 0)
                if delayMs > 0 {
                    let delayNanoseconds = UInt64(delayMs) * 1_000_000
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                }
                await executeGraphFlow(
                    from: connection.targetNodeId,
                    payload: payload,
                    graph: &graph,
                    tab: tab,
                    context: context,
                    visited: nextVisited
                )
                continue
            }

            if key == "utility.repeater" {
                let cfg = graph.repeaterActionConfigByNodeId[connection.targetNodeId.uuidString] ?? DashboardGraph.RepeaterActionConfig()
                let repeatCount = max(1, cfg.repeatCount)
                let delayNanoseconds = UInt64(max(0, cfg.delayMs)) * 1_000_000
                let repeaterDownstream = GraphAutomationTraversal.downstreamConnections(
                    graph: graph,
                    sourceNodeId: connection.targetNodeId,
                    resolveNodeIdFromPortId: { self.resolveNodeId(fromPortId: $0, graph: graph) }
                )
                var orderedOutputPortIds: [String] = []
                var seenOutputPortIds = Set<String>()
                for downstreamConnection in repeaterDownstream {
                    if seenOutputPortIds.insert(downstreamConnection.sourcePortId).inserted {
                        orderedOutputPortIds.append(downstreamConnection.sourcePortId)
                    }
                }

                var isFirstOutputExecution = true
                for _ in 0..<repeatCount {
                    for outputPortId in orderedOutputPortIds {
                        if !isFirstOutputExecution, delayNanoseconds > 0 {
                            try? await Task.sleep(nanoseconds: delayNanoseconds)
                        }
                        isFirstOutputExecution = false
                        await executeGraphFlow(
                            from: connection.targetNodeId,
                            sourcePortId: outputPortId,
                            payload: payload,
                            graph: &graph,
                            tab: tab,
                            context: context,
                            visited: nextVisited
                        )
                    }
                }
                continue
            }

            if key == "utility.condition" {
                guard isGraphConditionalsFeatureEnabled else { continue }
                let result = evaluateCondition(nodeId: connection.targetNodeId, payload: payload, graph: &graph, tab: tab)
                let branch: GraphAutomationTraversal.UtilityBranch = result ? .`true` : .`false`
                await executeGraphFlow(
                    from: connection.targetNodeId,
                    sourcePortId: GraphAutomationTraversal.conditionOutputPortId(nodeId: connection.targetNodeId, branch: branch),
                    payload: payload,
                    graph: &graph,
                    tab: tab,
                    context: context,
                    visited: nextVisited
                )
                continue
            }

            if key == "utility.merge" {
                await executeGraphFlow(
                    from: connection.targetNodeId,
                    payload: payload,
                    graph: &graph,
                    tab: tab,
                    context: context,
                    visited: nextVisited
                )
                continue
            }

            if key == "utility.toggle" {
                var cfg = graph.toggleNodeConfigByNodeId[connection.targetNodeId.uuidString]
                    ?? DashboardGraph.ToggleNodeConfig(id: connection.targetNodeId)
                cfg.currentState.toggle()
                graph.toggleNodeConfigByNodeId[connection.targetNodeId.uuidString] = cfg

                let activePortId = GraphAutomationTraversal.toggleOutputPortId(
                    nodeId: connection.targetNodeId,
                    isOn: cfg.currentState
                )
                await executeGraphFlow(
                    from: connection.targetNodeId,
                    sourcePortId: activePortId,
                    payload: payload,
                    graph: &graph,
                    tab: tab,
                    context: context,
                    visited: nextVisited
                )
                continue
            }

            if key == "utility.counter" {
                var cfg = graph.counterNodeConfigByNodeId[connection.targetNodeId.uuidString]
                    ?? DashboardGraph.CounterNodeConfig(id: connection.targetNodeId)
                cfg.currentCount += 1
                graph.counterNodeConfigByNodeId[connection.targetNodeId.uuidString] = cfg

                guard cfg.currentCount >= max(1, cfg.threshold) else { continue }

                if cfg.resetAfterFire {
                    cfg.currentCount = 0
                    graph.counterNodeConfigByNodeId[connection.targetNodeId.uuidString] = cfg
                }

                await executeGraphFlow(
                    from: connection.targetNodeId,
                    payload: payload,
                    graph: &graph,
                    tab: tab,
                    context: context,
                    visited: nextVisited
                )
                continue
            }

            if key == "utility.sequence" {
                var cfg = graph.sequenceNodeConfigByNodeId[connection.targetNodeId.uuidString]
                    ?? DashboardGraph.SequenceNodeConfig(id: connection.targetNodeId)
                let step = cfg.currentStep
                cfg.currentStep = (step + 1) % max(1, cfg.stepCount)
                graph.sequenceNodeConfigByNodeId[connection.targetNodeId.uuidString] = cfg

                let stepPortId = GraphAutomationTraversal.sequenceOutputPortId(
                    nodeId: connection.targetNodeId, step: step
                )
                await executeGraphFlow(
                    from: connection.targetNodeId,
                    sourcePortId: stepPortId,
                    payload: payload,
                    graph: &graph,
                    tab: tab,
                    context: context,
                    visited: nextVisited
                )
                continue
            }

            if key == "utility.latch" {
                var cfg = graph.latchNodeConfigByNodeId[connection.targetNodeId.uuidString]
                    ?? DashboardGraph.LatchNodeConfig(id: connection.targetNodeId)

                let sourceId = connection.sourceNodeId
                if cfg.enableTriggerNodeId == sourceId {
                    cfg.isEnabled = true
                    graph.latchNodeConfigByNodeId[connection.targetNodeId.uuidString] = cfg
                    continue
                }
                if cfg.disableTriggerNodeId == sourceId {
                    cfg.isEnabled = false
                    graph.latchNodeConfigByNodeId[connection.targetNodeId.uuidString] = cfg
                    continue
                }

                guard cfg.isEnabled else { continue }

                await executeGraphFlow(
                    from: connection.targetNodeId,
                    payload: payload,
                    graph: &graph,
                    tab: tab,
                    context: context,
                    visited: nextVisited
                )
                continue
            }
        }
    }

    @MainActor
    private func executeActionNode(
        nodeId: UUID,
        key: String,
        graph: DashboardGraph,
        context: GraphActionExecutor.ExecutionContext
    ) {
        if key == "action.sendAllConsoles" || key.lowercased().contains("sendall") {
            let flags = resolvedSendAllFlags(actionNodeId: nodeId, graph: graph)
            guard flags.includeAssignments || flags.includeSnapshots else { return }
            let linkedConsoleIds = linkedConsoleExternalDeviceIdsForSendAll(graph: graph, actionNodeId: nodeId)
            guard !linkedConsoleIds.isEmpty else { return }
            NotificationCenter.default.post(
                name: .prodlinkGraphSendAllToConsoles,
                object: linkedConsoleIds,
                userInfo: [
                    GraphSendAllUserInfoKeys.delayMs: flags.delayMs,
                    GraphSendAllUserInfoKeys.includeAssignments: flags.includeAssignments,
                    GraphSendAllUserInfoKeys.includeSnapshots: flags.includeSnapshots
                ]
            )
            return
        }

        GraphActionExecutor.execute(
            actionKey: key,
            nodeId: nodeId,
            graph: graph,
            context: context
        )
    }

    private func executeVistaDestinationNode(
        nodeId: UUID,
        payload: GraphTriggerPayload,
        graph: DashboardGraph,
        context: GraphActionExecutor.ExecutionContext
    ) {
        guard let cfg = graph.vistaNodeConfigByNodeId[nodeId.uuidString] else { return }
        context.log("[GraphAutomationRuntime] Vista send requested nodeId=\(nodeId) command=\(cfg.commandKind.rawValue)")
        Task { @MainActor in
            VistaOSCCommandSender.send(
                config: cfg,
                payload: payload,
                source: "runtime",
                nodeId: nodeId
            )
        }
    }

    func evaluateCondition(nodeId: UUID, payload: GraphTriggerPayload, graph: inout DashboardGraph, tab: DashboardTab) -> Bool {
        guard isGraphConditionalsFeatureEnabled else { return false }
        guard var cfg = graph.conditionNodeConfigByNodeId[nodeId.uuidString] else { return false }

        cfg.lastPayloadText = payload.text
        cfg.lastPayloadNumber = payload.number
        cfg.lastPayloadBoolean = payload.boolean
        cfg.lastEvaluatedAt = Date()
        var resolvedComparison = cfg
        resolvedComparison.comparisonText = GraphRuntime.interpolateSharedValues(in: cfg.comparisonText)

        let evaluationOutcome: Bool?
        let evaluatedValueKind: String
        let resolvedSummary: String

        switch cfg.sourceKind {
        case .payloadText:
            guard let value = payload.text else {
                cfg.lastResolvedValueSummary = "Payload text: <missing>"
                cfg.lastEvaluationDebugSummary = "lhs=<missing> op=\(cfg.operator.displayName) rhs=\(normalizedConditionText(resolvedComparison.comparisonText))"
                cfg.lastEvaluationResult = false
                graph.conditionNodeConfigByNodeId[nodeId.uuidString] = cfg
                postConditionEvaluationResolved(nodeId: nodeId)
                return false
            }
            resolvedSummary = "Payload text: \(value)"
            evaluatedValueKind = "text"
            evaluationOutcome = evaluateConditionText(value, config: resolvedComparison)
        case .payloadNumber:
            guard let value = payload.number else {
                cfg.lastResolvedValueSummary = "Payload number: <missing>"
                cfg.lastEvaluationDebugSummary = "lhs=<missing> op=\(cfg.operator.displayName) rhs=\(cfg.comparisonNumber)"
                cfg.lastEvaluationResult = false
                graph.conditionNodeConfigByNodeId[nodeId.uuidString] = cfg
                postConditionEvaluationResolved(nodeId: nodeId)
                return false
            }
            resolvedSummary = "Payload number: \(value)"
            evaluatedValueKind = "number"
            evaluationOutcome = evaluateConditionNumber(value, config: cfg)
        case .payloadBoolean:
            guard let value = payload.boolean else {
                cfg.lastResolvedValueSummary = "Payload boolean: <missing>"
                cfg.lastEvaluationDebugSummary = "lhs=<missing> op=\(cfg.operator.displayName) rhs=\(cfg.comparisonBoolean ? "true" : "false")"
                cfg.lastEvaluationResult = false
                graph.conditionNodeConfigByNodeId[nodeId.uuidString] = cfg
                postConditionEvaluationResolved(nodeId: nodeId)
                return false
            }
            resolvedSummary = "Payload boolean: \(value ? "true" : "false")"
            evaluatedValueKind = "boolean"
            evaluationOutcome = evaluateConditionBoolean(value, config: cfg)
        case .variable:
            guard let variableNodeId = cfg.variableNodeId,
                  let variable = graph.variableNodeConfigByNodeId[variableNodeId.uuidString] else {
                cfg.lastResolvedValueSummary = "Variable: <not selected>"
                cfg.lastEvaluationDebugSummary = "lhs=<missing> op=\(cfg.operator.displayName) rhs=\(normalizedConditionText(resolvedComparison.comparisonText))"
                cfg.lastEvaluationResult = false
                graph.conditionNodeConfigByNodeId[nodeId.uuidString] = cfg
                postConditionEvaluationResolved(nodeId: nodeId)
                return false
            }
            var resolvedTab = tab
            resolvedTab.graph = graph
            let resolvedValue = GraphRuntime.resolvedVariableCurrentValue(nodeId: variableNodeId, tab: resolvedTab)
            switch variable.valueType {
            case .text:
                let value = resolvedValue
                resolvedSummary = "Variable text: \(value)"
                evaluatedValueKind = "text"
                evaluationOutcome = evaluateConditionText(value, config: resolvedComparison)
            case .number, .float:
                let value = Double(resolvedValue) ?? variable.manualNumberValue
                resolvedSummary = "Variable number: \(value)"
                evaluatedValueKind = "number"
                evaluationOutcome = evaluateConditionNumber(value, config: cfg)
            case .boolean:
                let value = resolvedValue == "true"
                resolvedSummary = "Variable boolean: \(value ? "true" : "false")"
                evaluatedValueKind = "boolean"
                evaluationOutcome = evaluateConditionBoolean(value, config: cfg)
            }
        }

        let result: Bool
        if let evaluationOutcome {
            result = evaluationOutcome
            postConditionEvaluationResolved(nodeId: nodeId)
        } else {
            result = false
            postConditionEvaluationMismatch(
                nodeId: nodeId,
                message: "'\(cfg.operator.displayName)' doesn't apply to \(evaluatedValueKind) values"
            )
        }

        cfg.lastResolvedValueSummary = resolvedSummary
        cfg.lastEvaluationDebugSummary = conditionDebugSummary(for: resolvedComparison, resolvedSummary: resolvedSummary)
        cfg.lastEvaluationResult = result
        graph.conditionNodeConfigByNodeId[nodeId.uuidString] = cfg
        return result
    }

    func evaluateConditionText(_ value: String, config: DashboardGraph.ConditionNodeConfig) -> Bool? {
        let lhs = normalizedConditionText(value)
        let rhs = normalizedConditionText(config.comparisonText)
        switch config.operator {
        case .equals:
            return lhs == rhs
        case .notEquals:
            return lhs != rhs
        case .contains:
            return lhs.localizedCaseInsensitiveContains(rhs)
        case .isEmpty:
            return lhs.isEmpty
        case .isNotEmpty:
            return !lhs.isEmpty
        default:
            return nil
        }
    }

    private func normalizedConditionText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func conditionDebugSummary(for config: DashboardGraph.ConditionNodeConfig, resolvedSummary: String) -> String {
        let rhs: String
        switch config.sourceKind {
        case .payloadNumber:
            rhs = String(config.comparisonNumber)
        case .payloadBoolean:
            rhs = config.comparisonBoolean ? "true" : "false"
        case .payloadText, .variable:
            rhs = normalizedConditionText(config.comparisonText)
        }
        return "lhs=\(resolvedSummary) op=\(config.operator.displayName) rhs=\(rhs)"
    }

    func evaluateConditionNumber(_ value: Double, config: DashboardGraph.ConditionNodeConfig) -> Bool? {
        switch config.operator {
        case .equals:
            return value == config.comparisonNumber
        case .notEquals:
            return value != config.comparisonNumber
        case .greaterThan:
            return value > config.comparisonNumber
        case .lessThan:
            return value < config.comparisonNumber
        default:
            return nil
        }
    }

    func evaluateConditionBoolean(_ value: Bool, config: DashboardGraph.ConditionNodeConfig) -> Bool? {
        switch config.operator {
        case .equals:
            return value == config.comparisonBoolean
        case .notEquals:
            return value != config.comparisonBoolean
        case .isTrue:
            return value
        case .isFalse:
            return !value
        default:
            return nil
        }
    }

    /// If a trigger node is directly linked to one or more console nodes, return those console external device ids.
    /// This allows OSC Receive -> Console wiring without an intermediate action node.
    private func directLinkedConsoleExternalDeviceIds(graph: DashboardGraph, triggerNodeId: UUID) -> [UUID] {
        directLinkedConsoleExternalDeviceIds(graph: graph, sourceNodeId: triggerNodeId)
    }

    private func directLinkedConsoleExternalDeviceIds(graph: DashboardGraph, sourceNodeId: UUID) -> [UUID] {
        directLinkedConsoleExternalDeviceIds(graph: graph, sourceNodeId: sourceNodeId, sourcePortId: nil)
    }

    private func directLinkedConsoleExternalDeviceIds(
        graph: DashboardGraph,
        sourceNodeId: UUID,
        sourcePortId: String?
    ) -> [UUID] {
        let neighborNodeIds = directLinkedConsoleNodeIds(graph: graph, sourceNodeId: sourceNodeId, sourcePortId: sourcePortId)
        if neighborNodeIds.isEmpty { return [] }

        // Map neighbor node ids -> externalDeviceId (best-effort from graph config dictionaries).
        var out: [UUID] = []
        var seen = Set<UUID>()
        for nodeId in neighborNodeIds {
            if let ext = externalDeviceIdForConsoleNode(graph: graph, nodeId: nodeId), !seen.contains(ext) {
                seen.insert(ext)
                out.append(ext)
            }
        }

        return out
    }

    private func directLinkedConsoleNodeIds(graph: DashboardGraph, triggerNodeId: UUID) -> [UUID] {
        directLinkedConsoleNodeIds(graph: graph, sourceNodeId: triggerNodeId)
    }

    private func directLinkedConsoleNodeIds(graph: DashboardGraph, sourceNodeId: UUID) -> [UUID] {
        directLinkedConsoleNodeIds(graph: graph, sourceNodeId: sourceNodeId, sourcePortId: nil)
    }

    private func directLinkedConsoleNodeIds(
        graph: DashboardGraph,
        sourceNodeId: UUID,
        sourcePortId: String?
    ) -> [UUID] {
        var neighborNodeIds = Set<UUID>()
        for link in graph.links where link.isEnabled {
            let fromId = resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
            let toId = resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId

            if fromId == sourceNodeId {
                if let sourcePortId, link.fromPortId != sourcePortId {
                    continue
                }
                neighborNodeIds.insert(toId)
            }
            if toId == sourceNodeId { neighborNodeIds.insert(fromId) }
        }
        return Array(neighborNodeIds)
    }

    func postConsoleActionStarted(nodeId: UUID) {
        NotificationCenter.default.post(
            name: ActionNodeNotifications.consoleActionStarted,
            object: nil,
            userInfo: [ActionNodeUserInfoKeys.nodeId: nodeId]
        )
    }

    func postConsoleActionSucceeded(nodeId: UUID) {
        NotificationCenter.default.post(
            name: ActionNodeNotifications.consoleActionSucceeded,
            object: nil,
            userInfo: [ActionNodeUserInfoKeys.nodeId: nodeId]
        )
    }

    func postConsoleActionFailed(nodeId: UUID, message: String) {
        NotificationCenter.default.post(
            name: ActionNodeNotifications.consoleActionFailed,
            object: nil,
            userInfo: [
                ActionNodeUserInfoKeys.nodeId: nodeId,
                ActionNodeUserInfoKeys.errorMessage: message
            ]
        )
    }

    func postConditionEvaluationResolved(nodeId: UUID) {
        NotificationCenter.default.post(
            name: ActionNodeNotifications.conditionEvaluationResolved,
            object: nil,
            userInfo: [ActionNodeUserInfoKeys.nodeId: nodeId]
        )
    }

    func postConditionEvaluationMismatch(nodeId: UUID, message: String) {
        NotificationCenter.default.post(
            name: ActionNodeNotifications.conditionEvaluationMismatch,
            object: nil,
            userInfo: [
                ActionNodeUserInfoKeys.nodeId: nodeId,
                ActionNodeUserInfoKeys.errorMessage: message
            ]
        )
    }

    private func runQuConsoleActionsIfConfigured(graph: DashboardGraph, triggerNodeId: UUID) {
        runQuConsoleActionsIfConfigured(graph: graph, sourceNodeId: triggerNodeId)
    }

    private func runQuConsoleActionsIfConfigured(graph: DashboardGraph, sourceNodeId: UUID) {
        let consoleNodeIds = directLinkedConsoleNodeIds(graph: graph, sourceNodeId: sourceNodeId)
        guard !consoleNodeIds.isEmpty else { return }

        Task { @MainActor in
            let devices = ExternalDevicesStore.shared.devices
            for nodeId in consoleNodeIds {
                guard let actions = graph.quConsoleActionsByNodeId[nodeId.uuidString], !actions.isEmpty else { continue }
                guard let externalId = externalDeviceIdForConsoleNode(graph: graph, nodeId: nodeId) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "Not linked to a console device")
                    continue
                }
                guard let device = devices.first(where: { $0.id == externalId }) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "Linked console device was removed")
                    continue
                }
                guard isQuConsole(device) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "This node's actions don't apply to the linked console")
                    continue
                }

                let commands = buildQuConsoleCommands(actions: actions, device: device)
                guard !commands.isEmpty else {
                    postConsoleActionFailed(nodeId: nodeId, message: "No valid commands could be built for the configured actions")
                    continue
                }
                await ConsoleConnectorRegistry.shared.execute(commands)
                postConsoleActionSucceeded(nodeId: nodeId)
            }
        }
    }

    private func runDigiCoConsoleActionsIfConfigured(graph: DashboardGraph, sourceNodeId: UUID) {
        let consoleNodeIds = directLinkedConsoleNodeIds(graph: graph, sourceNodeId: sourceNodeId)
        guard !consoleNodeIds.isEmpty else { return }

        Task { @MainActor in
            let devices = ExternalDevicesStore.shared.devices
            for nodeId in consoleNodeIds {
                guard let actions = graph.digicoConsoleActionsByNodeId[nodeId.uuidString], !actions.isEmpty else { continue }
                guard let externalId = externalDeviceIdForConsoleNode(graph: graph, nodeId: nodeId) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "Not linked to a console device")
                    continue
                }
                guard let device = devices.first(where: { $0.id == externalId }) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "Linked console device was removed")
                    continue
                }
                guard isDigiCoConsole(device) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "This node's actions don't apply to the linked console")
                    continue
                }

                let commands = buildDigiCoOSCCommands(actions: actions, device: device)
                guard !commands.isEmpty else {
                    postConsoleActionFailed(nodeId: nodeId, message: "No valid commands could be built for the configured actions")
                    continue
                }
                await ConsoleConnectorRegistry.shared.execute(commands)
                postConsoleActionSucceeded(nodeId: nodeId)
            }
        }
    }

    func runQuConsoleActionsFromTrigger(graph: DashboardGraph, triggerNodeId: UUID) {
        runQuConsoleActionsIfConfigured(graph: graph, triggerNodeId: triggerNodeId)
    }

    func runDigiCoConsoleActionsFromTrigger(graph: DashboardGraph, triggerNodeId: UUID) {
        runDigiCoConsoleActionsIfConfigured(graph: graph, sourceNodeId: triggerNodeId)
    }

    func testQuConsoleActions(graph: DashboardGraph, consoleNodeId: UUID) {
        Task { @MainActor in
            postConsoleActionStarted(nodeId: consoleNodeId)
            guard let actions = graph.quConsoleActionsByNodeId[consoleNodeId.uuidString],
                  !actions.isEmpty else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "No Qu actions configured on this node")
                return
            }
            guard let externalId = externalDeviceIdForConsoleNode(graph: graph, nodeId: consoleNodeId) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "Not linked to a console device")
                return
            }
            guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == externalId }) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "Linked console device was removed")
                return
            }
            guard isQuConsole(device) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "This node's actions don't apply to the linked console")
                return
            }

            let commands = buildQuConsoleCommands(actions: actions, device: device)
            guard !commands.isEmpty else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "No valid commands could be built for the configured actions")
                return
            }
            await ConsoleConnectorRegistry.shared.execute(commands)
            postConsoleActionSucceeded(nodeId: consoleNodeId)
        }
    }

    func testDigiCoConsoleActions(graph: DashboardGraph, consoleNodeId: UUID) {
        Task { @MainActor in
            postConsoleActionStarted(nodeId: consoleNodeId)
            guard let actions = graph.digicoConsoleActionsByNodeId[consoleNodeId.uuidString],
                  !actions.isEmpty else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "No DiGiCo actions configured on this node")
                return
            }
            guard let externalId = externalDeviceIdForConsoleNode(graph: graph, nodeId: consoleNodeId) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "Not linked to a console device")
                return
            }
            guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == externalId }) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "Linked console device was removed")
                return
            }
            guard isDigiCoConsole(device) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "This node's actions don't apply to the linked console")
                return
            }

            let commands = buildDigiCoOSCCommands(actions: actions, device: device)
            guard !commands.isEmpty else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "No valid commands could be built for the configured actions")
                return
            }
            await ConsoleConnectorRegistry.shared.execute(commands)
            postConsoleActionSucceeded(nodeId: consoleNodeId)
        }
    }

    private func runStandardConsoleActionsIfConfigured(graph: DashboardGraph, sourceNodeId: UUID) {
        let consoleNodeIds = directLinkedConsoleNodeIds(graph: graph, sourceNodeId: sourceNodeId)
        guard !consoleNodeIds.isEmpty else { return }

        Task { @MainActor in
            let devices = ExternalDevicesStore.shared.devices
            for nodeId in consoleNodeIds {
                guard let actions = graph.standardConsoleActionsByNodeId[nodeId.uuidString], !actions.isEmpty else { continue }
                guard let externalId = externalDeviceIdForConsoleNode(graph: graph, nodeId: nodeId) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "Not linked to a console device")
                    continue
                }
                guard let device = devices.first(where: { $0.id == externalId }) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "Linked console device was removed")
                    continue
                }
                guard isStandardActionConsole(device) else {
                    postConsoleActionFailed(nodeId: nodeId, message: "This node's actions don't apply to the linked console")
                    continue
                }

                let commands = buildStandardConsoleCommands(actions: actions, device: device)
                guard !commands.isEmpty else {
                    postConsoleActionFailed(nodeId: nodeId, message: "No valid commands could be built for the configured actions")
                    continue
                }
                await ConsoleConnectorRegistry.shared.execute(commands)
                postConsoleActionSucceeded(nodeId: nodeId)
            }
        }
    }

    func runStandardConsoleActionsFromTrigger(graph: DashboardGraph, triggerNodeId: UUID) {
        runStandardConsoleActionsIfConfigured(graph: graph, sourceNodeId: triggerNodeId)
    }

    func testStandardConsoleActions(graph: DashboardGraph, consoleNodeId: UUID) {
        Task { @MainActor in
            postConsoleActionStarted(nodeId: consoleNodeId)
            guard let actions = graph.standardConsoleActionsByNodeId[consoleNodeId.uuidString],
                  !actions.isEmpty else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "No actions configured on this node")
                return
            }
            guard let externalId = externalDeviceIdForConsoleNode(graph: graph, nodeId: consoleNodeId) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "Not linked to a console device")
                return
            }
            guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == externalId }) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "Linked console device was removed")
                return
            }
            guard isStandardActionConsole(device) else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "This node's actions don't apply to the linked console")
                return
            }

            let commands = buildStandardConsoleCommands(actions: actions, device: device)
            guard !commands.isEmpty else {
                postConsoleActionFailed(nodeId: consoleNodeId, message: "No valid commands could be built for the configured actions")
                return
            }
            await ConsoleConnectorRegistry.shared.execute(commands)
            postConsoleActionSucceeded(nodeId: consoleNodeId)
        }
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

    private func buildQuConsoleCommands(actions: [DashboardGraph.QuConsoleAction], device: ExternalDeviceConfig) -> [GraphCommand] {
        var out: [GraphCommand] = []
        for action in actions where action.isEnabled {
            if let bytes = buildQuMidiBytes(action: action, device: device), !bytes.isEmpty {
                out.append(.console(.sendMidi(externalDeviceId: device.id, bytes: bytes)))
            }
        }
        return out
    }

    private func buildDigiCoOSCCommands(actions: [DashboardGraph.DiGiCoConsoleAction], device: ExternalDeviceConfig) -> [GraphCommand] {
        actions.filter(\.isEnabled).compactMap { action in
            switch action.kind {
            case .macro:
                let index = max(0, action.channelIndex)
                let address = "/Macros/Recall_Macro/\(index)"
                return .console(.digicoOSCInt32(externalDeviceId: device.id, address: address, intValue: Int32(index)))
            case .mute, .solo, .fader:
                let address = "\(action.channelType.oscPrefix)/\(max(1, action.channelIndex))/\(action.kind.rawValue)"
                let value: Float = action.kind == .fader ? Float(action.faderDb) : (action.boolValue ? 1.0 : 0.0)
                return .console(.digicoOSC(externalDeviceId: device.id, address: address, floatValue: value))
            }
        }
    }

    private func buildStandardConsoleCommands(actions: [DashboardGraph.StandardConsoleAction], device: ExternalDeviceConfig) -> [GraphCommand] {
        actions.filter(\.isEnabled).compactMap { action in
            standardActionCommand(for: action, device: device)
        }
    }

    private func venueCommand(for action: DashboardGraph.StandardConsoleAction, device: ExternalDeviceConfig) -> GraphCommand? {
        switch action.kind {
        case .sceneRecall:
            let trimmedScene = action.sceneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedScene.isEmpty else { return nil }
            guard let template = device.venueSceneRecallAddressTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !template.isEmpty else { return nil }
            let address = VenueConsoleService.filledAddress(template: template, scene: trimmedScene)
            return .console(.venueOSC(externalDeviceId: device.id, address: address, value: .bool(true)))

        case .mute:
            guard action.muteMode != .toggle else { return nil }
            guard let template = device.venueMuteAddressTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !template.isEmpty else { return nil }
            let address = VenueConsoleService.filledAddress(template: template, channel: action.channelIndex)
            return .console(.venueOSC(externalDeviceId: device.id, address: address, value: .bool(action.muteMode == .on)))

        case .level:
            guard let template = device.venueLevelAddressTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !template.isEmpty else { return nil }
            let address = VenueConsoleService.filledAddress(template: template, channel: action.channelIndex)
            return .console(.venueOSC(externalDeviceId: device.id, address: address, value: .float32(Float(action.levelDb))))

        case .pan:
            guard let template = device.venuePanAddressTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !template.isEmpty else { return nil }
            let address = VenueConsoleService.filledAddress(template: template, channel: action.channelIndex)
            return .console(.venueOSC(externalDeviceId: device.id, address: address, value: .float32(Float(action.panValue))))
        }
    }

    private func standardActionCommand(for action: DashboardGraph.StandardConsoleAction, device: ExternalDeviceConfig) -> GraphCommand? {
        if device.audioConsoleModel == .avidVenueS6L {
            return venueCommand(for: action, device: device)
        }

        switch action.kind {
        case .sceneRecall:
            let trimmed = action.sceneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .console(.fireSnapshot(externalDeviceId: device.id, snapshot: .name(trimmed)))
        case .mute:
            guard device.consoleCapabilities.channelMute == .supported else { return nil }
            guard action.muteMode != .toggle else { return nil }
            let value = action.muteMode == .on ? 1.0 : 0.0
            return .console(.setChannelParameter(externalDeviceId: device.id, channel: action.channelIndex, parameter: .mute, value: value))
        case .level:
            guard device.consoleCapabilities.channelLevel == .supported else { return nil }
            return .console(.setChannelParameter(externalDeviceId: device.id, channel: action.channelIndex, parameter: .level, value: action.levelDb))
        case .pan:
            guard device.consoleCapabilities.channelPan == .supported else { return nil }
            return .console(.setChannelParameter(externalDeviceId: device.id, channel: action.channelIndex, parameter: .pan, value: action.panValue))
        }
    }

    private func buildQuMidiBytes(action: DashboardGraph.QuConsoleAction, device: ExternalDeviceConfig) -> [UInt8]? {
        let channel = normalizedMidiChannel(action.midiChannel, device: device)

        switch action.kind {
        case .sceneRecall:
            var bytes: [UInt8] = []
            let bankValue = max(1, action.bank ?? 1)
            let baseProgram = max(1, action.program ?? 1)
            let programValue: Int
            switch action.sceneRecallMode {
            case .custom:
                programValue = baseProgram
            case .next:
                programValue = min(128, baseProgram + 1)
            case .previous:
                programValue = max(1, baseProgram - 1)
            }
            bytes += midiCC(channel: channel, controller: 0x00, value: clamp7(bankValue - 1))
            bytes += midiProgramChange(channel: channel, program: clamp7(programValue - 1))
            return bytes.isEmpty ? nil : bytes

        case .softKey:
            let key = max(1, min(16, action.softKey))
            let note = UInt8(0x30 + (key - 1))
            return midiNoteOn(channel: channel, note: note, velocity: 0x7F) +
                   midiNoteOff(channel: channel, note: note, velocity: 0x00)

        case .channelMute, .groupMute:
            guard let param = quParameterNumber(action: action) else { return nil }
            switch action.muteMode {
            case .on:
                return quNRPNSet(channel: channel, msb: param.msb, lsb: param.lsb, value: 1)
            case .off:
                return quNRPNSet(channel: channel, msb: param.msb, lsb: param.lsb, value: 0)
            case .toggle:
                return quNRPNIncrement(channel: channel, msb: param.msb, lsb: param.lsb)
            }

        case .mixAssign:
            guard let param = quParameterNumber(action: action) else { return nil }
            return quNRPNSet(channel: channel, msb: param.msb, lsb: param.lsb, value: action.boolValue ? 1 : 0)

        case .channelLevel, .sendLevel, .groupLevel, .fxSendLevel, .fxReturnLevel, .channelPan:
            guard let param = quParameterNumber(action: action) else { return nil }
            let value = clamp14(action.value)
            return quNRPNSet(channel: channel, msb: param.msb, lsb: param.lsb, value: value)
        }
    }

    private func normalizedMidiChannel(_ raw: Int, device: ExternalDeviceConfig) -> Int {
        if let base = device.consoleBaseMidiChannel {
            return Int(base) + 1
        }
        if raw >= 1 && raw <= 16 { return raw }
        return 1
    }

    private func clamp7(_ value: Int) -> Int {
        max(0, min(127, value))
    }

    private func clamp14(_ value: Int) -> Int {
        max(0, min(16383, value))
    }

    private func midiStatus(base: UInt8, channel: Int) -> UInt8 {
        let ch = UInt8(max(1, min(16, channel)) - 1)
        return base | ch
    }

    private func midiCC(channel: Int, controller: Int, value: Int) -> [UInt8] {
        let status = midiStatus(base: 0xB0, channel: channel)
        return [status, UInt8(clamp7(controller)), UInt8(clamp7(value))]
    }

    private func midiProgramChange(channel: Int, program: Int) -> [UInt8] {
        let status = midiStatus(base: 0xC0, channel: channel)
        return [status, UInt8(clamp7(program))]
    }

    private func midiNoteOn(channel: Int, note: UInt8, velocity: UInt8) -> [UInt8] {
        let status = midiStatus(base: 0x90, channel: channel)
        return [status, note, velocity]
    }

    private func midiNoteOff(channel: Int, note: UInt8, velocity: UInt8) -> [UInt8] {
        let status = midiStatus(base: 0x80, channel: channel)
        return [status, note, velocity]
    }

    private func quNRPNSet(channel: Int, msb: UInt8, lsb: UInt8, value: Int) -> [UInt8] {
        let coarse = UInt8((value >> 7) & 0x7F)
        let fine = UInt8(value & 0x7F)
        return midiCC(channel: channel, controller: 0x63, value: Int(msb)) +
               midiCC(channel: channel, controller: 0x62, value: Int(lsb)) +
               midiCC(channel: channel, controller: 0x06, value: Int(coarse)) +
               midiCC(channel: channel, controller: 0x26, value: Int(fine))
    }

    private func quNRPNIncrement(channel: Int, msb: UInt8, lsb: UInt8) -> [UInt8] {
        midiCC(channel: channel, controller: 0x63, value: Int(msb)) +
        midiCC(channel: channel, controller: 0x62, value: Int(lsb)) +
        midiCC(channel: channel, controller: 0x60, value: 0x00)
    }

    private func quParameterNumber(action: DashboardGraph.QuConsoleAction) -> (msb: UInt8, lsb: UInt8)? {
        if action.useManualParameter {
            return (UInt8(clamp7(action.manualMSB)), UInt8(clamp7(action.manualLSB)))
        }

        switch action.kind {
        case .channelMute, .groupMute:
            return quMuteParameter(action: action)
        case .channelLevel, .channelPan, .sendLevel, .groupLevel, .fxSendLevel, .fxReturnLevel:
            return quLevelParameter(action: action)
        case .mixAssign:
            return quAssignParameter(action: action)
        case .sceneRecall, .softKey:
            return nil
        }
    }

    private func quMuteParameter(action: DashboardGraph.QuConsoleAction) -> (msb: UInt8, lsb: UInt8)? {
        switch action.sourceKind {
        case .input:
            return (0x00, UInt8(clamp7(action.sourceIndex - 1)))
        case .st1:
            return (0x00, 0x20)
        case .st2:
            return (0x00, 0x22)
        case .usb:
            return (0x00, 0x24)
        case .fxReturn:
            return (0x00, UInt8(0x3C + max(0, min(5, action.sourceIndex - 1))))
        case .lr:
            return (0x00, 0x44)
        case .mix:
            return (0x00, UInt8(0x45 + max(0, min(11, action.sourceIndex - 1))))
        case .dca:
            return (0x02, UInt8(max(0, min(7, action.sourceIndex - 1))))
        case .muteGroup:
            return (0x04, UInt8(max(0, min(7, action.sourceIndex - 1))))
        case .group:
            return nil
        }
    }

    private func quLevelParameter(action: DashboardGraph.QuConsoleAction) -> (msb: UInt8, lsb: UInt8)? {
        guard let dest = quDestinationFor(action: action) else { return nil }

        switch action.sourceKind {
        case .input:
            return quInputToDestinationParameter(sourceIndex: action.sourceIndex, destination: dest)
        case .st1:
            if dest.kind == .lr { return (0x40, 0x20) }
            return nil
        case .st2:
            if dest.kind == .lr { return (0x40, 0x22) }
            return nil
        case .usb:
            if dest.kind == .lr { return (0x40, 0x24) }
            return nil
        case .group:
            if dest.kind == .lr {
                return (0x40, UInt8(0x30 + max(0, min(11, action.sourceIndex - 1))))
            }
            return nil
        case .fxReturn:
            if dest.kind == .lr {
                return (0x40, UInt8(0x3C + max(0, min(5, action.sourceIndex - 1))))
            }
            return nil
        case .mix:
            if dest.kind == .lr {
                return (0x40, UInt8(0x45 + max(0, min(11, action.sourceIndex - 1))))
            }
            if dest.kind == .mix {
                return (0x4F, UInt8(max(1, min(12, action.sourceIndex))))
            }
            return nil
        case .lr:
            // Output control for LR master fader.
            return (0x4F, 0x00)
        default:
            return nil
        }
    }

    private func quAssignParameter(action: DashboardGraph.QuConsoleAction) -> (msb: UInt8, lsb: UInt8)? {
        // Assignment tables are extensive; allow manual parameter entry for now.
        return nil
    }

    private struct QuDestinationRef {
        var kind: DashboardGraph.QuDestinationKind
        var index: Int
    }

    private func quDestinationFor(action: DashboardGraph.QuConsoleAction) -> QuDestinationRef? {
        switch action.destinationKind {
        case .lr:
            return QuDestinationRef(kind: .lr, index: 1)
        case .mix:
            return QuDestinationRef(kind: .mix, index: max(1, min(12, action.destinationIndex)))
        case .fxSend:
            return QuDestinationRef(kind: .fxSend, index: max(1, min(4, action.destinationIndex)))
        }
    }

    private func quInputToDestinationParameter(sourceIndex: Int, destination: QuDestinationRef) -> (msb: UInt8, lsb: UInt8)? {
        let idx = max(1, min(32, sourceIndex)) - 1
        switch destination.kind {
        case .lr:
            return (0x40, UInt8(idx))
        case .mix:
            let base = 0x44 + (destination.index - 1)
            let raw = base + (idx * 0x0C)
            let msb = 0x40 + (raw / 0x80)
            let lsb = raw % 0x80
            return (UInt8(msb), UInt8(lsb))
        case .fxSend:
            let base = 0x14 + (destination.index - 1)
            let raw = base + (idx * 0x04)
            let msb = 0x4C + (raw / 0x80)
            let lsb = raw % 0x80
            return (UInt8(msb), UInt8(lsb))
        }
    }

    /// Best-effort lookup of a console node's external device id from the graph model.
    /// Supports common dictionary storage forms.
    private func externalDeviceIdForConsoleNode(graph: DashboardGraph, nodeId: UUID) -> UUID? {
        let gm = Mirror(reflecting: graph)
        let dictKeys = [
            "consoleDeviceIdByNodeId",
            "consoleExternalDeviceIdByNodeId",
            "consoleExternalDeviceIDByNodeId",
            "externalDeviceIdByNodeId",
            "externalDeviceIDByNodeId",
            "consoleNodeExternalDeviceIdByNodeId",
            "audioConsoleExternalDeviceIdByNodeId"
        ]

        for key in dictKeys {
            guard let child = gm.children.first(where: { $0.label == key }) else { continue }

            if let dict = child.value as? [UUID: UUID], let v = dict[nodeId] {
                return v
            }
            if let dict = child.value as? [String: UUID], let v = dict[nodeId.uuidString] {
                return v
            }
            if let dict = child.value as? [UUID: Any] {
                if let any = dict[nodeId] {
                    if let u = any as? UUID { return u }
                    if let s = any as? String, let u = UUID(uuidString: s) { return u }
                }
            }
            if let dict = child.value as? [String: Any] {
                if let any = dict[nodeId.uuidString] {
                    if let u = any as? UUID { return u }
                    if let s = any as? String, let u = UUID(uuidString: s) { return u }
                }
            }
        }

        // Fallback: try to find a console node instance with matching id that stores externalDeviceId.
        if let inst = graph.moduleGroupNodeInstances.first(where: { $0.id == nodeId }) {
            let im = Mirror(reflecting: inst)
            if let v = im.children.first(where: { $0.label == "externalDeviceId" || $0.label == "externalDeviceID" || $0.label == "deviceId" || $0.label == "deviceID" })?.value {
                if let u = v as? UUID { return u }
                let om = Mirror(reflecting: v)
                if om.displayStyle == .optional, let child = om.children.first {
                    if let u = child.value as? UUID { return u }
                    if let s = child.value as? String, let u = UUID(uuidString: s) { return u }
                }
            }
        }

        // Fallback: console nodes are auto-created and their nodeId is derived from the external device id.
        // If a neighbor nodeId matches a derived console nodeId, return the underlying externalDeviceId.
        let live = ExternalDevicesStore.shared.devices
        for dev in live {
            // Heuristic: only treat audio consoles as candidates.
            if !String(describing: dev.kind).lowercased().contains("console") { continue }
            if derivedGraphNodeId(forExternalDeviceId: dev.id) == nodeId {
                return dev.id
            }
        }

        return nil
    }

    /// One-hop traversal: trigger -> connected action nodes.
    private func downstreamActionInstances(graph: DashboardGraph, triggerNodeId: UUID) -> [(nodeId: UUID, key: String)] {
        let actionInstances = graph.moduleGroupNodeInstances.filter { $0.groupKey.hasPrefix("action.") }
        guard !actionInstances.isEmpty else { return [] }

        var actionById: [UUID: String] = [:]
        actionById.reserveCapacity(actionInstances.count)
        for inst in actionInstances {
            actionById[inst.id] = inst.groupKey
        }

        var results: [(UUID, String)] = []
        results.reserveCapacity(2)

        for link in graph.links where link.isEnabled {
            let fromId = resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
            guard fromId == triggerNodeId else { continue }

            let toId = resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId
            if let key = actionById[toId] {
                results.append((toId, key))
            }
        }

        return results
    }

    private func downstreamVariableNodeIds(graph: DashboardGraph, triggerNodeId: UUID) -> [UUID] {
        guard isGraphVariablesFeatureEnabled else { return [] }
        return GraphAutomationTraversal.downstreamNodeIds(
            graph: graph,
            triggerNodeId: triggerNodeId,
            matchingGroupKeys: ["utility.variable"],
            resolveNodeIdFromPortId: { resolveNodeId(fromPortId: $0, graph: graph) }
        )
    }

    private func downstreamRepeaterNodeIds(graph: DashboardGraph, triggerNodeId: UUID) -> [UUID] {
        let repeaterIds = Set(graph.moduleGroupNodeInstances
            .filter { $0.groupKey == "utility.repeater" }
            .map { $0.id }
        )
        guard !repeaterIds.isEmpty else { return [] }

        var results: [UUID] = []
        for link in graph.links where link.isEnabled {
            let fromId = resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
            guard fromId == triggerNodeId else { continue }
            let toId = resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId
            if repeaterIds.contains(toId) {
                results.append(toId)
            }
        }
        return results
    }

    private func downstreamDelayNodeIds(graph: DashboardGraph, triggerNodeId: UUID) -> [UUID] {
        let delayIds = Set(graph.moduleGroupNodeInstances
            .filter { $0.groupKey == "utility.delay" }
            .map { $0.id }
        )
        guard !delayIds.isEmpty else { return [] }

        var results: [UUID] = []
        for link in graph.links where link.isEnabled {
            let fromId = resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
            guard fromId == triggerNodeId else { continue }
            let toId = resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId
            if delayIds.contains(toId) {
                results.append(toId)
            }
        }
        return results
    }

    private func hasExecutableDownstreamNodes(graph: DashboardGraph, triggerNodeId: UUID) -> Bool {
        !GraphAutomationTraversal.downstreamConnections(
            graph: graph,
            sourceNodeId: triggerNodeId,
            resolveNodeIdFromPortId: { resolveNodeId(fromPortId: $0, graph: graph) }
        ).isEmpty
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
            let fromId = resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
            guard fromId == repeaterNodeId else { continue }
            let toId = resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId
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
            let fromId = resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
            guard fromId == delayNodeId else { continue }
            let toId = resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId
            if let key = actionById[toId] {
                results.append((toId, key))
            }
        }
        return results
    }

    private func resolveNodeId(fromPortId portId: String, graph: DashboardGraph) -> UUID? {
        // Prefer persisted reverse index
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

    /// Derive the same stable graph node id used by GraphDashboardView for an external device id.
    private func derivedGraphNodeId(forExternalDeviceId id: UUID) -> UUID {
        let data = Data(id.uuidString.utf8)
        let digest = SHA256.hash(data: data)
        let byteArray = Array(digest.prefix(16))
        var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

        withUnsafeMutableBytes(of: &uuidBytes) { buf in
            buf.copyBytes(from: byteArray)
        }

        return UUID(uuid: uuidBytes)
    }

    private func extractExternalDeviceIds(from devices: [Any]) -> [UUID] {
        func extractId(_ dev: Any) -> UUID? {
            (Mirror(reflecting: dev).children.first { $0.label == "id" }?.value as? UUID)
        }

        var ids: [UUID] = []
        ids.reserveCapacity(devices.count)
        for dev in devices {
            if let id = extractId(dev) { ids.append(id) }
        }
        return ids
    }

    private func oscReceiveConfigMatches(cfg: DashboardGraph.OSCReceiveConfig, port: Int, address: String) -> Bool {
        let globalListenPort: Int = {
            let configured = UserDefaults.standard.integer(forKey: "osc.global.port")
            return max(1, min(65535, configured == 0 ? 8000 : configured))
        }()

        let effectivePort = cfg.useCustomPort ? Int(cfg.customListenPort) : globalListenPort
        if effectivePort != port {
            return false
        }

        let wantedAddress = (cfg.addressFilter ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !wantedAddress.isEmpty {
            return wantedAddress == address.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return true
    }

    private func shouldEmitOSCTrigger(nodeId: UUID, graph: DashboardGraph) -> Bool {
        let directConsoleIds = directLinkedConsoleExternalDeviceIds(graph: graph, triggerNodeId: nodeId)
        let isWired = hasExecutableDownstreamNodes(graph: graph, triggerNodeId: nodeId) || !directConsoleIds.isEmpty

        #if DEBUG
        if !isWired {
            print("[AutomationRuntime] OSC matched trigger=\(nodeId) but it is not wired (downstream=0 directConsoles=0); skipping")
        }
        #endif

        return isWired
    }

    private func postMatchedOSCTrigger(
        nodeId: UUID,
        address: String,
        port: Int,
        payloadText: String?,
        payloadNumber: Double?,
        payloadBoolean: Bool?
    ) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: TriggerNodeNotifications.fired,
                object: nil,
                userInfo: [
                    TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                    "source": "runtime.osc",
                    "timestamp": Date(),
                    TriggerNodeUserInfoKeys.address: address,
                    TriggerNodeUserInfoKeys.localPort: port,
                    TriggerNodeUserInfoKeys.payloadText: payloadText as Any,
                    TriggerNodeUserInfoKeys.payloadNumber: payloadNumber as Any,
                    TriggerNodeUserInfoKeys.payloadBoolean: payloadBoolean as Any
                ]
            )
        }
    }

    private func parseHexBytes(_ text: String) -> [UInt8]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .split { $0 == " " || $0 == "\t" || $0 == "," || $0 == "-" }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(tokens.count)

        for t in tokens {
            let token = String(t)
            guard let v = UInt8(token, radix: 16) else { return nil }
            bytes.append(v)
        }

        return bytes.isEmpty ? nil : bytes
    }

    private func midiReceiveConfigMatches(
        cfgAny: Any,
        kind: MIDIMessageKind,
        program: Int?,
        channel: Int?,
        note: Int?,
        control: Int?,
        value: Int?,
        sysex: [UInt8]?
    ) -> Bool {
        let m = Mirror(reflecting: cfgAny)

        func intField(_ name: String) -> Int? {
            if let v = m.children.first(where: { $0.label == name })?.value as? Int { return v }
            return nil
        }

        func optionalIntField(_ name: String) -> Int? {
            guard let raw = m.children.first(where: { $0.label == name })?.value else { return nil }
            if let v = raw as? Int { return v }
            let om = Mirror(reflecting: raw)
            if om.displayStyle == .optional, let child = om.children.first {
                return child.value as? Int
            }
            return nil
        }

        func stringField(_ name: String) -> String? {
            if let v = m.children.first(where: { $0.label == name })?.value as? String { return v }
            return nil
        }

        func optionalStringField(_ name: String) -> String? {
            guard let raw = m.children.first(where: { $0.label == name })?.value else { return nil }
            if let v = raw as? String { return v }
            let om = Mirror(reflecting: raw)
            if om.displayStyle == .optional, let child = om.children.first {
                return child.value as? String
            }
            return nil
        }

        let messageType: DashboardGraph.MIDIMessageType = {
            if let v = m.children.first(where: { $0.label == "messageType" })?.value as? DashboardGraph.MIDIMessageType {
                return v
            }
            let raw = stringField("messageType") ?? stringField("type") ?? "programChange"
            return DashboardGraph.MIDIMessageType(rawValue: raw) ?? .programChange
        }()

        switch messageType {
        case .any:
            let channelFilter = optionalIntField("channelFilter") ?? intField("channel")
            if let c = channelFilter {
                guard let channel, c == channel else { return false }
            }
            let programFilter = optionalIntField("programFilter") ?? intField("program")
            if let p = programFilter {
                guard let program, p == program else { return false }
            }
            let noteFilter = optionalIntField("noteFilter")
            if let n = noteFilter {
                guard let note, n == note else { return false }
            }
            let ccNumber = optionalIntField("ccNumberFilter") ?? intField("ccNumber")
            if let n = ccNumber {
                guard let control, n == control else { return false }
            }
            let ccValue = optionalIntField("ccValueFilter") ?? intField("ccValue")
            if let v = ccValue {
                guard let value, v == value else { return false }
            }
            if let prefix = optionalStringField("sysexPrefixHex") ?? stringField("sysexPrefixHex") {
                if let prefixBytes = parseHexBytes(prefix) {
                    guard let sysex, sysex.starts(with: prefixBytes) else { return false }
                }
            }
            return true

        case .programChange:
            guard kind == .programChange else { return false }
            let programFilter = optionalIntField("programFilter") ?? intField("program")
            if let p = programFilter, p != program { return false }
            let channelFilter = optionalIntField("channelFilter") ?? intField("channel")
            if let c = channelFilter, c != channel { return false }
            return true

        case .noteOn:
            guard kind == .noteOn else { return false }
            let noteFilter = optionalIntField("noteFilter")
            if let n = noteFilter, n != note { return false }
            let channelFilter = optionalIntField("channelFilter") ?? intField("channel")
            if let c = channelFilter, c != channel { return false }
            return true

        case .noteOff:
            guard kind == .noteOff else { return false }
            let noteFilter = optionalIntField("noteFilter")
            if let n = noteFilter, n != note { return false }
            let channelFilter = optionalIntField("channelFilter") ?? intField("channel")
            if let c = channelFilter, c != channel { return false }
            return true

        case .controlChange:
            guard kind == .controlChange else { return false }
            let ccNumber = optionalIntField("ccNumberFilter") ?? intField("ccNumber")
            if let n = ccNumber, n != control { return false }
            let ccValue = optionalIntField("ccValueFilter") ?? intField("ccValue")
            if let v = ccValue, v != value { return false }
            let channelFilter = optionalIntField("channelFilter") ?? intField("channel")
            if let c = channelFilter, c != channel { return false }
            return true

        case .sysex:
            guard kind == .sysex else { return false }
            if let prefix = optionalStringField("sysexPrefixHex") ?? stringField("sysexPrefixHex") {
                if let prefixBytes = parseHexBytes(prefix) {
                    guard let sysex, sysex.starts(with: prefixBytes) else { return false }
                }
            }
            return true
        }
    }

    // MARK: - Send-All linked consoles

    /// If a Send-All action node is linked to one or more console nodes, return those console external device ids.
    /// This enforces "linked-only" send-all behavior.
    private func linkedConsoleExternalDeviceIdsForSendAll(graph: DashboardGraph, actionNodeId: UUID) -> [UUID] {
        var neighborNodeIds = Set<UUID>()
        for link in graph.links where link.isEnabled {
            let fromId = resolveNodeId(fromPortId: link.fromPortId, graph: graph) ?? link.fromTileId
            let toId = resolveNodeId(fromPortId: link.toPortId, graph: graph) ?? link.toTileId

            if fromId == actionNodeId { neighborNodeIds.insert(toId) }
        }

        if neighborNodeIds.isEmpty { return [] }

        var out: [UUID] = []
        out.reserveCapacity(neighborNodeIds.count)
        var seen = Set<UUID>()

        for nodeId in neighborNodeIds {
            guard let ext = externalDeviceIdForConsoleNode(graph: graph, nodeId: nodeId) else { continue }
            if !seen.contains(ext) {
                seen.insert(ext)
                out.append(ext)
            }
        }

        return out
    }
}
