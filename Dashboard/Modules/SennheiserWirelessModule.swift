//
//  SennheiserWirelessModuleConfig.swift
//  Relay
//
//  Created by David Bullard on 12/30/25.
//


import Foundation
import SwiftUI
import Combine
import Network
// MARK: - Dashboard Module Plugin

struct SennheiserWirelessModulePlugin: DashboardModulePlugin {
    static let kind: DashboardModuleKind = .sennheiserWireless

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {

        let config = Binding<SennheiserWirelessModuleConfig>(
            get: {
                module.wrappedValue.sennheiserConfig ?? SennheiserWirelessModuleConfig()
            },
            set: {
                module.wrappedValue.sennheiserConfig = $0
            }
        )

        return AnyView(
            SennheiserWirelessTileView(
                config: config.wrappedValue,
                isLiveMode: isLiveMode,
                showsHeader: true
            )
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        // No standalone settings panel — everything lives in the inspector
        AnyView(EmptyView())
    }
}
// MARK: - Module Config

/// Tile-stored settings for the Sennheiser module.
struct SennheiserWirelessModuleConfig: Codable, Equatable {
    /// ExternalDevicesStore device ID (kind == .sennheiserWireless)
    var externalDeviceID: UUID? = nil

    /// Channel index for the device (1-based, consistent with typical receiver UX)
    var channelIndex: Int = 1

    /// Optional stable identifier from the Sennheiser network API for the selected channel.
    /// This allows us to keep assignments stable if the device's channel ordering changes.
    var channelRemoteID: String? = nil

    /// UI toggles (limited to values we can realistically obtain from Sennheiser 3rd‑party APIs)
    var showDeviceName: Bool = true
    var showChannelName: Bool = true
    /// Show the configured host/IP (helpful for multi-receiver environments)
    var showHost: Bool = false

    var showFrequency: Bool = true
    var showBattery: Bool = true
    /// RF strength / quality (depending on device/API)
    var showRF: Bool = true
    /// Audio / AF level (depending on device/API)
    var showAudio: Bool = true

    /// Polling (mostly for debugging / performance testing)
    var pollIntervalSeconds: Double = 2.0

    // Demo (debug-only UI uses these fields)
    var demoEnabled: Bool = false
    var demoIsIem: Bool = false
    var demoMicName: String = "Lead Mic"
    var demoDeviceName: String = "Sennheiser Demo Rack"
    var demoBatteryPercent: Int = 82
    var demoFrequencyMHz: Double = 550.125

    init(
        externalDeviceID: UUID? = nil,
        channelIndex: Int = 1,
        channelRemoteID: String? = nil,
        showDeviceName: Bool = true,
        showChannelName: Bool = true,
        showHost: Bool = false,
        showFrequency: Bool = true,
        showBattery: Bool = true,
        showRF: Bool = true,
        showAudio: Bool = true,
        pollIntervalSeconds: Double = 2.0,
        demoEnabled: Bool = false,
        demoIsIem: Bool = false,
        demoMicName: String = "Lead Mic",
        demoDeviceName: String = "Sennheiser Demo Rack",
        demoBatteryPercent: Int = 82,
        demoFrequencyMHz: Double = 550.125
    ) {
        self.externalDeviceID = externalDeviceID
        self.channelIndex = channelIndex
        self.channelRemoteID = channelRemoteID
        self.showDeviceName = showDeviceName
        self.showChannelName = showChannelName
        self.showHost = showHost
        self.showFrequency = showFrequency
        self.showBattery = showBattery
        self.showRF = showRF
        self.showAudio = showAudio
        self.pollIntervalSeconds = pollIntervalSeconds
        self.demoEnabled = demoEnabled
        self.demoIsIem = demoIsIem
        self.demoMicName = demoMicName
        self.demoDeviceName = demoDeviceName
        self.demoBatteryPercent = demoBatteryPercent
        self.demoFrequencyMHz = demoFrequencyMHz
    }

    private enum CodingKeys: String, CodingKey {
        case externalDeviceID
        case channelIndex
        case channelRemoteID
        case showDeviceName
        case showChannelName
        case showHost
        case showFrequency
        case showBattery
        case showRF
        case showAudio
        case pollIntervalSeconds
        case demoEnabled
        case demoIsIem
        case demoMicName
        case demoDeviceName
        case demoBatteryPercent
        case demoFrequencyMHz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalDeviceID = try container.decodeIfPresent(UUID.self, forKey: .externalDeviceID)
        channelIndex = try container.decodeIfPresent(Int.self, forKey: .channelIndex) ?? 1
        channelRemoteID = try container.decodeIfPresent(String.self, forKey: .channelRemoteID)
        showDeviceName = try container.decodeIfPresent(Bool.self, forKey: .showDeviceName) ?? true
        showChannelName = try container.decodeIfPresent(Bool.self, forKey: .showChannelName) ?? true
        showHost = try container.decodeIfPresent(Bool.self, forKey: .showHost) ?? false
        showFrequency = try container.decodeIfPresent(Bool.self, forKey: .showFrequency) ?? true
        showBattery = try container.decodeIfPresent(Bool.self, forKey: .showBattery) ?? true
        showRF = try container.decodeIfPresent(Bool.self, forKey: .showRF) ?? true
        showAudio = try container.decodeIfPresent(Bool.self, forKey: .showAudio) ?? true
        pollIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds) ?? 2.0

        demoEnabled = try container.decodeIfPresent(Bool.self, forKey: .demoEnabled) ?? false
        demoIsIem = try container.decodeIfPresent(Bool.self, forKey: .demoIsIem) ?? false
        demoMicName = try container.decodeIfPresent(String.self, forKey: .demoMicName) ?? "Lead Mic"
        demoDeviceName = try container.decodeIfPresent(String.self, forKey: .demoDeviceName) ?? "Sennheiser Demo Rack"
        demoBatteryPercent = try container.decodeIfPresent(Int.self, forKey: .demoBatteryPercent) ?? 82
        demoFrequencyMHz = try container.decodeIfPresent(Double.self, forKey: .demoFrequencyMHz) ?? 550.125
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(externalDeviceID, forKey: .externalDeviceID)
        try container.encode(channelIndex, forKey: .channelIndex)
        try container.encodeIfPresent(channelRemoteID, forKey: .channelRemoteID)
        try container.encode(showDeviceName, forKey: .showDeviceName)
        try container.encode(showChannelName, forKey: .showChannelName)
        try container.encode(showHost, forKey: .showHost)
        try container.encode(showFrequency, forKey: .showFrequency)
        try container.encode(showBattery, forKey: .showBattery)
        try container.encode(showRF, forKey: .showRF)
        try container.encode(showAudio, forKey: .showAudio)
        try container.encode(pollIntervalSeconds, forKey: .pollIntervalSeconds)
        try container.encode(demoEnabled, forKey: .demoEnabled)
        try container.encode(demoIsIem, forKey: .demoIsIem)
        try container.encode(demoMicName, forKey: .demoMicName)
        try container.encode(demoDeviceName, forKey: .demoDeviceName)
        try container.encode(demoBatteryPercent, forKey: .demoBatteryPercent)
        try container.encode(demoFrequencyMHz, forKey: .demoFrequencyMHz)
    }
}

// MARK: - Normalized Snapshot Model

enum SennheiserConnectionState: String, Codable {
    case disconnected
    case connecting
    case connected
    case error
}

enum SennheiserWarning: String, Codable, CaseIterable {
    case lowBattery
    case rfLow
    case audioClip
    case muted
    case offline
}

struct SennheiserChannelSnapshot: Identifiable, Codable, Equatable {
    /// Stable ID (synthesized if no native channel id exists)
    var id: String

    var deviceID: UUID
    var deviceName: String
    var channelIndex: Int

    /// Optional stable identifier from the Sennheiser network API (when available).
    var channelRemoteID: String? = nil

    var channelName: String?
    var frequencyMHz: Double?

    /// Normalized 0...1 meters (UI friendly)
    var rfLevel01: Double?
    var audioLevel01: Double?

    var batteryPercent: Int?
    var warnings: [SennheiserWarning] = []

    var updatedAt: Date = Date()
}

// MARK: - Service (Polling / Connection)

@MainActor
final class SennheiserWirelessService: ObservableObject {
    private var liveModeEnabled: Bool = false

    func setLiveModeEnabled(_ enabled: Bool) {
        // Avoid redundant churn when the value doesn't change.
        guard liveModeEnabled != enabled else { return }
        liveModeEnabled = enabled

        if enabled {
            // Start background tasks when entering Live Mode.
            reconcile()
        } else {
            // Stop background tasks in Edit Mode to eliminate network + CPU churn.
            stopAllTasks()
        }
    }

    private func stopAllTasks() {
        for (id, t) in pollTasks {
            t.cancel()
            pollTasks[id] = nil
        }
        for (_, client) in ewdxClients {
            client.stop()
        }
        for (_, client) in digital6000Clients {
            client.stop()
        }
        for (_, client) in mcpClients {
            client.stop()
        }
        for (_, client) in specteraClients {
            client.stop()
        }
        specteraClients.removeAll()

        // Mark all devices as disconnected while paused.
        // Keep snapshots + names so UI doesn't jump.
        for id in connectionStateByDevice.keys {
            connectionStateByDevice[id] = .disconnected
        }
    }
    static let shared = SennheiserWirelessService()

    @Published private(set) var connectionStateByDevice: [UUID: SennheiserConnectionState] = [:]
    @Published private(set) var lastErrorByDevice: [UUID: String] = [:]
    @Published private(set) var channelsByDevice: [UUID: [SennheiserChannelSnapshot]] = [:]

    struct ChannelNameRecord: Codable, Equatable {
        var remoteID: String?
        var name: String
    }

    /// Cached channel names discovered from the network (deviceID -> channelIndex -> record)
    @Published private(set) var channelNamesByDevice: [UUID: [Int: ChannelNameRecord]] = [:]

    /// Optional per-device polling interval override set by the module inspector.
    /// If not set, the service uses a conservative default.
    private var pollIntervalByDevice: [UUID: Double] = [:]

    private var ewdxClients: [UUID: SennheiserEWDXClient] = [:]
    private var digital6000Clients: [UUID: SennheiserDigital6000Client] = [:]
    private var mcpClients: [UUID: SennheiserMCPClient] = [:]
    private var specteraClients: [UUID: SpecteraClient] = [:]

    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Auto-reconcile whenever external devices change.
        ExternalDevicesStore.shared.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.liveModeEnabled {
                    self.reconcile()
                }
            }
            .store(in: &cancellables)

        reconcile()
    }

    /// Ensure pollers are running for each configured Sennheiser device.
    func reconcile() {
        guard liveModeEnabled else {
            stopAllTasks()
            return
        }
        let store = ExternalDevicesStore.shared
        let sennDevices = store.devices(ofKind: .sennheiserWireless)

        // Stop tasks for removed devices
        let existingIDs = Set(pollTasks.keys)
        let desiredIDs = Set(sennDevices.map { $0.id })

        for removed in existingIDs.subtracting(desiredIDs) {
            pollTasks[removed]?.cancel()
            pollTasks[removed] = nil
            pollIntervalByDevice[removed] = nil
            connectionStateByDevice[removed] = .disconnected
            lastErrorByDevice[removed] = nil
            channelsByDevice[removed] = nil
            channelNamesByDevice[removed] = nil
            if let client = ewdxClients.removeValue(forKey: removed) {
                client.stop()
            }
            if let client = digital6000Clients.removeValue(forKey: removed) {
                client.stop()
            }
            if let client = mcpClients.removeValue(forKey: removed) {
                client.stop()
            }
            if let client = specteraClients.removeValue(forKey: removed) {
                client.stop()
            }
        }

        // Start tasks for new devices
        for d in sennDevices where pollTasks[d.id] == nil {
            connectionStateByDevice[d.id] = .connecting
            pollTasks[d.id] = Task { [weak self] in
                await self?.pollLoop(for: d.id)
            }
        }
    }

    func setPollIntervalSeconds(_ seconds: Double, for deviceID: UUID) {
        // Clamp to a reasonable range so users can't accidentally hammer the network.
        let clamped = min(max(seconds, 0.5), 10.0)
        pollIntervalByDevice[deviceID] = clamped
    }

    /// Public helper: return latest snapshot for a specific device+channel.
    func snapshot(deviceID: UUID, channelIndex: Int) -> SennheiserChannelSnapshot? {
        channelsByDevice[deviceID]?.first(where: { $0.channelIndex == channelIndex })
    }

    /// Returns the best-available display name for a given device/channel, if discovered.
    func channelDisplayName(deviceID: UUID, channelIndex: Int) -> String? {
        channelNamesByDevice[deviceID]?[channelIndex]?.name
    }

    func channelRemoteID(deviceID: UUID, channelIndex: Int) -> String? {
        channelNamesByDevice[deviceID]?[channelIndex]?.remoteID
    }

    private func cacheChannelNames(deviceID: UUID, snapshots: [SennheiserChannelSnapshot]) {
        guard !snapshots.isEmpty else { return }
        var map = channelNamesByDevice[deviceID] ?? [:]
        for snap in snapshots {
            guard let name = snap.channelName, !name.isEmpty else { continue }
            map[snap.channelIndex] = ChannelNameRecord(remoteID: snap.channelRemoteID, name: name)
            ExternalDevicesStore.shared.cacheSennheiserChannelName(deviceID: deviceID, channelIndex: snap.channelIndex, name: name)
        }
        if !map.isEmpty {
            channelNamesByDevice[deviceID] = map
        }
    }

    /// Poll loop for a given device id. It re-reads config from the store each pass
    /// so edits update quickly without restarting tasks.
    private func pollLoop(for deviceID: UUID) async {
        while !Task.isCancelled {
            guard let device = ExternalDevicesStore.shared.device(withID: deviceID),
                  device.kind == .sennheiserWireless else {
                connectionStateByDevice[deviceID] = .disconnected
                break
            }

            // Spectera maintains an SSCv2 event stream. Its polling is only a fallback
            // in case that stream is disconnected; the other models use normal polling.
            let interval: Double
            if device.sennheiserNetworkModel?.protocolKind == .sscv2Spectera {
                interval = max(60, pollIntervalByDevice[deviceID] ?? 60)
            } else {
                interval = pollIntervalByDevice[deviceID] ?? 2.0
            }

            if liveModeEnabled {
                await pollDevice(device)
                let nanos = UInt64(max(0.5, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            } else {
                // Avoid background polling when not live.
                connectionStateByDevice[deviceID] = .disconnected
                try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            }
        }
    }

    private func pollDevice(_ device: ExternalDeviceConfig) async {
        connectionStateByDevice[device.id] = .connecting

        guard let model = device.sennheiserNetworkModel else {
            connectionStateByDevice[device.id] = .error
            lastErrorByDevice[device.id] = "Unknown Sennheiser model"
            return
        }

        let port = device.port > 0 ? Int(device.port) : model.defaultPort

        switch model.protocolKind {
        case .sscv2Spectera:
            guard let password = SpecteraKeychainStore.shared.password(for: device.id), !password.isEmpty else {
                connectionStateByDevice[device.id] = .error
                lastErrorByDevice[device.id] = "Spectera password missing"
                return
            }
            let client = specteraClients[device.id] ?? SpecteraClient()
            specteraClients[device.id] = client
            do {
                let snapshots = try await client.refresh(
                    deviceID: device.id,
                    deviceName: device.name,
                    host: device.host,
                    password: password
                )
                channelsByDevice[device.id] = snapshots
                cacheChannelNames(deviceID: device.id, snapshots: snapshots)
                connectionStateByDevice[device.id] = .connected
                lastErrorByDevice[device.id] = nil
                client.startSubscription(
                    deviceID: device.id,
                    host: device.host,
                    password: password,
                    onUpdate: { [weak self] in
                        guard let self,
                              let currentDevice = ExternalDevicesStore.shared.device(withID: device.id) else { return }
                        await self.pollDevice(currentDevice)
                    },
                    onFailure: { [weak self] message in
                        self?.connectionStateByDevice[device.id] = .error
                        self?.lastErrorByDevice[device.id] = message
                    }
                )
            } catch {
                connectionStateByDevice[device.id] = .error
                lastErrorByDevice[device.id] = error.localizedDescription
            }
        case .sscV1Udp:
            let client = ewdxClients[device.id] ?? SennheiserEWDXClient(deviceID: device.id)
            ewdxClients[device.id] = client
            client.updateEndpoint(host: device.host, port: port, channelCount: model.channelCount, deviceName: device.name)
            client.start()
            connectionStateByDevice[device.id] = client.isConnected ? .connected : .connecting
            lastErrorByDevice[device.id] = client.lastError
            let snapshots = client.currentSnapshots(deviceID: device.id, deviceName: device.name)
            channelsByDevice[device.id] = snapshots
            cacheChannelNames(deviceID: device.id, snapshots: snapshots)
        case .d6000Udp:
            let client = digital6000Clients[device.id] ?? SennheiserDigital6000Client(deviceID: device.id)
            digital6000Clients[device.id] = client
            client.updateEndpoint(host: device.host, port: port, channelCount: model.channelCount, deviceName: device.name)
            client.start()
            connectionStateByDevice[device.id] = client.isConnected ? .connected : .connecting
            lastErrorByDevice[device.id] = client.lastError
            let snapshots = client.currentSnapshots(deviceID: device.id, deviceName: device.name)
            channelsByDevice[device.id] = snapshots
            cacheChannelNames(deviceID: device.id, snapshots: snapshots)
        case .mcpV1:
            switch model {
            case .ewG4_300, .ewG4_500, .ewG3, .ewIemG4, .srIemG4:
                let client = mcpClients[device.id] ?? SennheiserMCPClient(deviceID: device.id)
                mcpClients[device.id] = client
                client.updateEndpoint(host: device.host, port: port, channelCount: model.channelCount, deviceName: device.name)
                client.start()
                connectionStateByDevice[device.id] = client.isConnected ? .connected : .connecting
                lastErrorByDevice[device.id] = client.lastError
                let snapshots = client.currentSnapshots(deviceID: device.id, deviceName: device.name)
                channelsByDevice[device.id] = snapshots
                cacheChannelNames(deviceID: device.id, snapshots: snapshots)
            default:
                connectionStateByDevice[device.id] = .error
                lastErrorByDevice[device.id] = "Sennheiser MCP not implemented for this model"
            }
        case .unknown:
            connectionStateByDevice[device.id] = .error
            lastErrorByDevice[device.id] = "Unsupported Sennheiser protocol"
        }
    }
}

// MARK: - EW-DX (SSC v1 UDP) Client

private final class SennheiserEWDXClient {
    private struct ChannelState {
        var name: String?
        var frequencyMHz: Double?
        var rfLevel01: Double?
        var batteryPercent: Int?
        var updatedAt: Date = Date()
    }

    private let deviceID: UUID
    private let queue = DispatchQueue(label: "SennheiserEWDXClient", qos: .utility)
    private var connection: NWConnection?
    private var isRunning = false
    private var subscriptionTask: Task<Void, Never>?

    private var host: String = ""
    private var port: Int = 45
    private var channelCount: Int = 2
    private var deviceName: String = ""
    private var channelStates: [Int: ChannelState] = [:]

    private(set) var isConnected: Bool = false
    private(set) var lastError: String? = nil

    init(deviceID: UUID) {
        self.deviceID = deviceID
    }

    func updateEndpoint(host: String, port: Int, channelCount: Int, deviceName: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPort = port > 0 ? port : 45
        let needsRestart = trimmedHost != self.host || resolvedPort != self.port
        self.host = trimmedHost
        self.port = resolvedPort
        self.channelCount = max(1, channelCount)
        self.deviceName = deviceName
        if needsRestart, isRunning {
            stop()
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        guard !host.isEmpty else {
            lastError = "Host missing"
            return
        }

        isRunning = true
        isConnected = false
        lastError = nil

        let portValue = NWEndpoint.Port(rawValue: UInt16(port)) ?? NWEndpoint.Port(rawValue: 45)!
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: portValue,
                                using: .udp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.lastError = nil
                self.sendSubscriptions()
            case .failed(let error):
                self.isConnected = false
                self.lastError = error.localizedDescription
            case .cancelled:
                self.isConnected = false
            default:
                break
            }
        }

        conn.start(queue: queue)
        receiveLoop()
        startSubscriptionLoop()
    }

    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        connection?.cancel()
        connection = nil
        isRunning = false
        isConnected = false
    }

    func currentSnapshots(deviceID: UUID, deviceName: String) -> [SennheiserChannelSnapshot] {
        let now = Date()
        return (1...channelCount).map { ch in
            let state = channelStates[ch]
            return SennheiserChannelSnapshot(
                id: "\(deviceID.uuidString)-\(ch)",
                deviceID: deviceID,
                deviceName: deviceName,
                channelIndex: ch,
                channelRemoteID: nil,
                channelName: state?.name,
                frequencyMHz: state?.frequencyMHz,
                rfLevel01: state?.rfLevel01,
                audioLevel01: nil,
                batteryPercent: state?.batteryPercent,
                warnings: [],
                updatedAt: state?.updatedAt ?? now
            )
        }
    }

    private func startSubscriptionLoop() {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 9 * 1_000_000_000)
                self.sendSubscriptions()
            }
        }
    }

    private func sendSubscriptions() {
        guard let connection else { return }
        let rxSettings: [String: Any] = [
            "name": NSNull(),
            "frequency": NSNull(),
            "mute": NSNull(),
            "warnings": NSNull()
        ]
        let meterSettings: [String: Any] = [
            "rsqi": NSNull(),
            "divi": NSNull()
        ]
        let txSettings: [String: Any] = [
            "name": NSNull(),
            "battery": [
                "gauge": NSNull(),
                "lifetime": NSNull()
            ],
            "mute": NSNull()
        ]

        var rxMap: [String: Any] = [:]
        var meterMap: [String: Any] = [:]
        var matesMap: [String: Any] = [:]

        for ch in 1...channelCount {
            rxMap["rx\(ch)"] = rxSettings
            meterMap["rx\(ch)"] = meterSettings
            matesMap["tx\(ch)"] = txSettings
        }

        let meterSubscribe: [String: Any] = [
            "#": ["lifetime": 10],
            "m": meterMap
        ]
        var rxSubscribe: [String: Any] = ["#": ["lifetime": 60]]
        for (key, value) in rxMap {
            rxSubscribe[key] = value
        }
        let matesSubscribe: [String: Any] = [
            "#": ["lifetime": 60],
            "mates": matesMap
        ]

        let payloads: [[String: Any]] = [
            ["osc": ["state": ["subscribe": [meterSubscribe]]]],
            ["osc": ["state": ["subscribe": [rxSubscribe]]]],
            ["osc": ["state": ["subscribe": [matesSubscribe]]]]
        ]

        for payload in payloads {
            sendJSON(payload, via: connection)
        }
    }

    private func receiveLoop() {
        guard let connection else { return }
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.lastError = error.localizedDescription
                self.isConnected = false
                return
            }
            if let data, let json = SennheiserJSON.parseObject(data) {
                self.handleMessage(json)
            }
            if self.isRunning {
                self.receiveLoop()
            }
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        let payload = SennheiserJSON.unwrapOSC(json)

        if let m = payload["m"] as? [String: Any] {
            for ch in 1...channelCount {
                guard let rx = m["rx\(ch)"] as? [String: Any] else { continue }
                if let rsqi = SennheiserJSON.double(rx["rsqi"]) {
                    var state = channelStates[ch] ?? ChannelState()
                    let normalized = max(0.0, min(1.0, rsqi / 100.0))
                    state.rfLevel01 = normalized
                    state.updatedAt = Date()
                    channelStates[ch] = state
                }
            }
        }

        if let mates = payload["mates"] as? [String: Any] {
            for ch in 1...channelCount {
                guard let tx = mates["tx\(ch)"] as? [String: Any] else { continue }
                if let battery = tx["battery"] as? [String: Any],
                   let gauge = SennheiserJSON.int(battery["gauge"]) {
                    var state = channelStates[ch] ?? ChannelState()
                    state.batteryPercent = gauge
                    state.updatedAt = Date()
                    channelStates[ch] = state
                }
            }
        }

        for ch in 1...channelCount {
            guard let rx = payload["rx\(ch)"] as? [String: Any] else { continue }
            var state = channelStates[ch] ?? ChannelState()
            if let name = SennheiserJSON.string(rx["name"]) {
                state.name = name
            }
            if let freq = SennheiserJSON.double(rx["frequency"]) {
                state.frequencyMHz = freq > 1000 ? (freq / 1000.0) : freq
            }
            state.updatedAt = Date()
            channelStates[ch] = state
        }
    }

    private func sendJSON(_ payload: [String: Any], via connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        connection.send(content: data, completion: .contentProcessed({ _ in }))
    }
}

// MARK: - Digital 6000 UDP Client (EM 6000)

private final class SennheiserDigital6000Client {
    private struct ChannelState {
        var name: String?
        var frequencyMHz: Double?
        var rfLevel01: Double?
        var audioLevel01: Double?
        var batteryPercent: Int?
        var updatedAt: Date = Date()
    }

    private let deviceID: UUID
    private let queue = DispatchQueue(label: "SennheiserDigital6000Client", qos: .utility)
    private var connection: NWConnection?
    private var isRunning = false
    private var subscriptionTask: Task<Void, Never>?

    private var host: String = ""
    private var port: Int = 6970
    private var channelCount: Int = 2
    private var deviceName: String = ""
    private var channelStates: [Int: ChannelState] = [:]

    private(set) var isConnected: Bool = false
    private(set) var lastError: String? = nil

    init(deviceID: UUID) {
        self.deviceID = deviceID
    }

    func updateEndpoint(host: String, port: Int, channelCount: Int, deviceName: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPort = port > 0 ? port : 6970
        let needsRestart = trimmedHost != self.host || resolvedPort != self.port
        self.host = trimmedHost
        self.port = resolvedPort
        self.channelCount = max(1, channelCount)
        self.deviceName = deviceName
        if needsRestart, isRunning {
            stop()
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        guard !host.isEmpty else {
            lastError = "Host missing"
            return
        }

        isRunning = true
        isConnected = false
        lastError = nil

        let portValue = NWEndpoint.Port(rawValue: UInt16(port)) ?? NWEndpoint.Port(rawValue: 6970)!
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: portValue,
                                using: .udp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.lastError = nil
                self.sendSubscriptions()
            case .failed(let error):
                self.isConnected = false
                self.lastError = error.localizedDescription
            case .cancelled:
                self.isConnected = false
            default:
                break
            }
        }

        conn.start(queue: queue)
        receiveLoop()
        startSubscriptionLoop()
    }

    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        connection?.cancel()
        connection = nil
        isRunning = false
        isConnected = false
    }

    func currentSnapshots(deviceID: UUID, deviceName: String) -> [SennheiserChannelSnapshot] {
        let now = Date()
        return (1...channelCount).map { ch in
            let state = channelStates[ch]
            return SennheiserChannelSnapshot(
                id: "\(deviceID.uuidString)-\(ch)",
                deviceID: deviceID,
                deviceName: deviceName,
                channelIndex: ch,
                channelRemoteID: nil,
                channelName: state?.name,
                frequencyMHz: state?.frequencyMHz,
                rfLevel01: state?.rfLevel01,
                audioLevel01: state?.audioLevel01,
                batteryPercent: state?.batteryPercent,
                warnings: [],
                updatedAt: state?.updatedAt ?? now
            )
        }
    }

    private func startSubscriptionLoop() {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 19 * 1_000_000_000)
                self.sendSubscriptions()
            }
        }
    }

    private func sendSubscriptions() {
        guard let connection else { return }
        let generalSub: [String: Any] = ["min": 50, "max": 10000, "lifetime": 20, "count": 1000]
        let meterSub: [String: Any] = ["min": 50, "max": 50, "lifetime": 20, "count": 1000]

        let meteringPayload: [String: Any] = [
            "osc": [
                "state": [
                    "subscribe": [
                        [
                            "#": meterSub,
                            "mm": NSNull()
                        ]
                    ]
                ]
            ]
        ]
        sendJSON(meteringPayload, via: connection)

        let audioPayload: [String: Any] = [
            "osc": [
                "state": [
                    "subscribe": [
                        [
                            "#": generalSub,
                            "audio": [
                                "out1": ["level_db": NSNull()],
                                "out2": ["level_db": NSNull()]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        sendJSON(audioPayload, via: connection)

        for ch in 1...min(2, channelCount) {
            let rxPayload: [String: Any] = [
                "osc": [
                    "state": [
                        "subscribe": [
                            [
                                "#": generalSub,
                                "rx\(ch)": [
                                    "audio_mute": NSNull(),
                                    "name": NSNull(),
                                    "encryption": NSNull(),
                                    "active_warnings": NSNull(),
                                    "active_status": NSNull()
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            sendJSON(rxPayload, via: connection)

            let skxPayload: [String: Any] = [
                "osc": [
                    "state": [
                        "subscribe": [
                            [
                                "#": generalSub,
                                "rx\(ch)": [
                                    "skx": [
                                        "type": NSNull(),
                                        "name": NSNull(),
                                        "lowcut": NSNull(),
                                        "gain": NSNull(),
                                        "display": NSNull(),
                                        "capsule": NSNull(),
                                        "cable_emulation": NSNull(),
                                        "battery": NSNull(),
                                        "autolock": NSNull()
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            sendJSON(skxPayload, via: connection)

            let carrierPayload: [String: Any] = [
                "rx\(ch)": [
                    "carrier": NSNull(),
                    "active_bank_channel": NSNull(),
                    "testtone": NSNull()
                ]
            ]
            sendJSON(carrierPayload, via: connection)
        }
    }

    private func receiveLoop() {
        guard let connection else { return }
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.lastError = error.localizedDescription
                self.isConnected = false
                return
            }
            if let data, let json = SennheiserJSON.parseObject(data) {
                self.handleMessage(json)
            }
            if self.isRunning {
                self.receiveLoop()
            }
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        let payload = SennheiserJSON.unwrapOSC(json)

        if let mm = payload["mm"] as? [Any] {
            for (idx, rowAny) in mm.enumerated() {
                let channel = idx + 1
                guard channel <= channelCount else { continue }
                guard let row = rowAny as? [Any] else { continue }
                let rf1 = SennheiserJSON.double(row[safe: 0])
                let rf2 = SennheiserJSON.double(row[safe: 1])
                let lqi = SennheiserJSON.double(row[safe: 6])
                let af = SennheiserJSON.double(row[safe: 7])

                var state = channelStates[channel] ?? ChannelState()
                if let lqi {
                    let percent = convertLQIToPercent(lqi)
                    state.rfLevel01 = max(0.0, min(1.0, percent / 100.0))
                } else if let rf1, let rf2 {
                    let avg = (rf1 + rf2) / 2.0
                    let dbm = convertRFToDbm(avg)
                    state.rfLevel01 = mapDbmTo01(dbm)
                }
                if let af {
                    let dbfs = convertAFToDbfs(af)
                    state.audioLevel01 = mapDbfsTo01(dbfs)
                }
                state.updatedAt = Date()
                channelStates[channel] = state
            }
        }

        for ch in 1...min(2, channelCount) {
            if let rx = payload["rx\(ch)"] as? [String: Any] {
                var state = channelStates[ch] ?? ChannelState()
                if let name = SennheiserJSON.string(rx["name"]) {
                    state.name = name
                }
                if let carrier = SennheiserJSON.double(rx["carrier"]) {
                    state.frequencyMHz = carrier / 1000.0
                }
                if let skx = rx["skx"] as? [String: Any] {
                    if let skxName = SennheiserJSON.string(skx["name"]) {
                        state.name = skxName
                    }
                    if let battery = skx["battery"] as? [Any],
                       let percent = SennheiserJSON.int(battery.first) {
                        state.batteryPercent = percent
                    }
                }
                state.updatedAt = Date()
                channelStates[ch] = state
            }
        }
    }

    private func sendJSON(_ payload: [String: Any], via connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        connection.send(content: data, completion: .contentProcessed({ _ in }))
    }

    private func convertRFToDbm(_ level: Double) -> Double {
        (level - 255.0) / 2.0
    }

    private func convertAFToDbfs(_ level: Double) -> Double {
        (level + 1.0) / 2.0 - 128.0
    }

    private func convertLQIToPercent(_ lqi: Double) -> Double {
        (lqi / 255.0) * 100.0
    }

    private func mapDbmTo01(_ dbm: Double) -> Double {
        let minDbm = -120.0
        let maxDbm = -30.0
        return max(0.0, min(1.0, (dbm - minDbm) / (maxDbm - minDbm)))
    }

    private func mapDbfsTo01(_ dbfs: Double) -> Double {
        let minDb = -60.0
        let maxDb = 0.0
        return max(0.0, min(1.0, (dbfs - minDb) / (maxDb - minDb)))
    }
}

// MARK: - MCP Client (EW 300/500 G4)

private final class SennheiserMCPClient {
    private struct ChannelState {
        var name: String?
        var frequencyMHz: Double?
        var rfLevel01: Double?
        var audioLevel01: Double?
        var batteryPercent: Int?
        var muted: Bool = false
        var updatedAt: Date = Date()
    }

    private let deviceID: UUID
    private let queue = DispatchQueue(label: "SennheiserMCPClient", qos: .utility)
    private var connection: NWConnection?
    private var isRunning = false
    private var subscriptionTask: Task<Void, Never>?
    private var infoTask: Task<Void, Never>?

    private var host: String = ""
    private var port: Int = 53212
    private var channelCount: Int = 1
    private var deviceName: String = ""
    private var channelStates: [Int: ChannelState] = [:]

    private(set) var isConnected: Bool = false
    private(set) var lastError: String? = nil

    init(deviceID: UUID) {
        self.deviceID = deviceID
    }

    func updateEndpoint(host: String, port: Int, channelCount: Int, deviceName: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPort = port > 0 ? port : 53212
        let needsRestart = trimmedHost != self.host || resolvedPort != self.port
        self.host = trimmedHost
        self.port = resolvedPort
        self.channelCount = max(1, channelCount)
        self.deviceName = deviceName
        if needsRestart, isRunning {
            stop()
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        guard !host.isEmpty else {
            lastError = "Host missing"
            return
        }

        isRunning = true
        isConnected = false
        lastError = nil

        let portValue = NWEndpoint.Port(rawValue: UInt16(port)) ?? NWEndpoint.Port(rawValue: 53212)!
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: portValue,
                                using: .udp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.lastError = nil
                self.sendSubscriptions()
                self.sendInfoRequests()
            case .failed(let error):
                self.isConnected = false
                self.lastError = error.localizedDescription
            case .cancelled:
                self.isConnected = false
            default:
                break
            }
        }

        conn.start(queue: queue)
        receiveLoop()
        startSubscriptionLoop()
        startInfoLoop()
    }

    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        infoTask?.cancel()
        infoTask = nil
        connection?.cancel()
        connection = nil
        isRunning = false
        isConnected = false
    }

    func currentSnapshots(deviceID: UUID, deviceName: String) -> [SennheiserChannelSnapshot] {
        let now = Date()
        return (1...channelCount).map { ch in
            let state = channelStates[ch]
            var warnings: [SennheiserWarning] = []
            if let battery = state?.batteryPercent, battery <= 30 {
                warnings.append(.lowBattery)
            }
            if state?.muted == true {
                warnings.append(.muted)
            }
            return SennheiserChannelSnapshot(
                id: "\(deviceID.uuidString)-\(ch)",
                deviceID: deviceID,
                deviceName: deviceName,
                channelIndex: ch,
                channelRemoteID: nil,
                channelName: state?.name,
                frequencyMHz: state?.frequencyMHz,
                rfLevel01: state?.rfLevel01,
                audioLevel01: state?.audioLevel01,
                batteryPercent: state?.batteryPercent,
                warnings: warnings,
                updatedAt: state?.updatedAt ?? now
            )
        }
    }

    private func startSubscriptionLoop() {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
                self.sendSubscriptions()
            }
        }
    }

    private func startInfoLoop() {
        infoTask?.cancel()
        infoTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12 * 1_000_000_000)
                self.sendInfoRequests()
            }
        }
    }

    private func sendSubscriptions() {
        guard let connection else { return }
        // Push <timeoutSeconds> <cycleMs> <configFlag>
        // configFlag 1 enables config change notifications (name/frequency).
        sendLine("Push 5 400 1", via: connection)
    }

    private func sendInfoRequests() {
        guard let connection else { return }
        sendLine("Name", via: connection)
        sendLine("Frequency", via: connection)
    }

    private func receiveLoop() {
        guard let connection else { return }
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.lastError = error.localizedDescription
                self.isConnected = false
                return
            }
            if let data, let text = String(data: data, encoding: .utf8) {
                self.handleMessage(text)
            }
            if self.isRunning {
                self.receiveLoop()
            }
        }
    }

    private func handleMessage(_ text: String) {
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let tokens = line.split(separator: " ")
            guard let command = tokens.first else { continue }

            switch command.uppercased() {
            case "RF":
                // RF <current> <ant> <pilot>
                if tokens.count >= 2, let level = Double(tokens[1]) {
                    var state = channelStates[1] ?? ChannelState()
                    state.rfLevel01 = clamp01(level / 100.0)
                    state.updatedAt = Date()
                    channelStates[1] = state
                }
            case "AF":
                // AF <current> <peak> <mute>
                if tokens.count >= 2, let level = Double(tokens[1]) {
                    var state = channelStates[1] ?? ChannelState()
                    state.audioLevel01 = clamp01(level / 100.0)
                    if tokens.count >= 4, let muteVal = Int(tokens[3]) {
                        state.muted = muteVal != 0
                    }
                    state.updatedAt = Date()
                    channelStates[1] = state
                }
            case "BAT":
                if tokens.count >= 2, let level = Int(tokens[1]) {
                    var state = channelStates[1] ?? ChannelState()
                    state.batteryPercent = clampPercent(level)
                    state.updatedAt = Date()
                    channelStates[1] = state
                }
            case "NAME":
                let name = line.dropFirst(command.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    var state = channelStates[1] ?? ChannelState()
                    state.name = name
                    state.updatedAt = Date()
                    channelStates[1] = state
                }
            case "FREQUENCY":
                if tokens.count >= 2, let freq = Double(tokens[1]) {
                    var state = channelStates[1] ?? ChannelState()
                    state.frequencyMHz = freq / 1000.0
                    state.updatedAt = Date()
                    channelStates[1] = state
                }
            default:
                break
            }
        }
    }

    private func sendLine(_ line: String, via connection: NWConnection) {
        let payload = line.hasSuffix("\r") ? line : (line + "\r")
        connection.send(content: payload.data(using: .utf8), completion: .contentProcessed({ _ in }))
    }

    private func clamp01(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }

    private func clampPercent(_ value: Int) -> Int {
        max(0, min(100, value))
    }
}

// MARK: - JSON Helpers

private enum SennheiserJSON {
    static func parseObject(_ data: Data) -> [String: Any]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            return nil
        }
        return dict
    }

    static func unwrapOSC(_ dict: [String: Any]) -> [String: Any] {
        if let osc = dict["osc"] as? [String: Any] {
            if let state = osc["state"] as? [String: Any] {
                return state
            }
            return osc
        }
        return dict
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
}

private extension Array where Element == Any {
    subscript(safe index: Int) -> Any? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

// MARK: - Tile View

struct SennheiserWirelessTileView: View {
    let config: SennheiserWirelessModuleConfig
    let isLiveMode: Bool
    var showsHeader: Bool = true
    @AppStorage("dashboard_live_mode_enabled") private var liveModeEnabled: Bool = false

    @ObservedObject private var store = ExternalDevicesStore.shared
    @ObservedObject private var service = SennheiserWirelessService.shared

    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    @Environment(\.tileCornerRadius) private var tileCornerRadius
#if DEBUG || BETA
    private let demoTick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    @State private var demoPhase: Double = 0
#endif

    private var effectiveLiveMode: Bool {
        isLiveMode || liveModeEnabled
    }

    /// Base font size for this tile; other sizes are scaled from here.
    private var baseFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    /// Primary font weight for important labels in this tile.
    private var primaryFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    /// Primary text color derived from tile formatting, defaulting to white.
    private var resolvedPrimaryColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
    }

    /// Secondary, de-emphasized text color.
    private var resolvedSecondaryColor: Color {
        resolvedPrimaryColor.opacity(0.7)
    }

    /// Resolved text alignment based on the tile's justification setting.
    private var resolvedTextAlignment: TextAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Resolved horizontal alignment for frames based on justification.
    private var resolvedHorizontalAlignment: Alignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Sennheiser brand blue used for the Mic / IEM capsule
    private var sennheiserBlue: Color {
        Color(red: 3.0/255.0, green: 124.0/255.0, blue: 194.0/255.0)
    }

    /// Font for the section header ("Sennheiser Wireless").
    private var headerFont: Font {
        .system(size: baseFontSize * 0.85, weight: primaryFontWeight)
    }

    /// Extra bottom padding that scales with the tile's corner radius.
    private var bottomPadding: CGFloat {
        let scaled = tileCornerRadius * 0.65
        let minimum: CGFloat = 8
        return max(minimum, scaled)
    }

    /// Font for labels and content rows (device name, status labels).
    private var contentFont: Font {
        .system(size: baseFontSize * 0.7, weight: .regular)
    }

    /// Font for smaller caption-style text (hints, host:port, row labels).
    private var captionFont: Font {
        .system(size: baseFontSize * 0.6, weight: .regular)
    }

    private func applyCapitalization(_ string: String) -> String {
        switch tileTextFormatting?.capitalization ?? .normal {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }

    private var isDemoModeActive: Bool {
#if DEBUG || BETA
        return config.demoEnabled
#else
        return false
#endif
    }

    private var device: ExternalDeviceConfig? {
#if DEBUG || BETA
        if isDemoModeActive {
            return demoDevice
        }
#endif
        guard let id = config.externalDeviceID else { return nil }
        return store.device(withID: id)
    }

    private var connectionState: SennheiserConnectionState {
#if DEBUG || BETA
        if isDemoModeActive {
            return .connected
        }
#endif
        guard let id = config.externalDeviceID else { return .disconnected }
        return service.connectionStateByDevice[id] ?? .disconnected
    }

    private var snapshot: SennheiserChannelSnapshot? {
#if DEBUG || BETA
        if isDemoModeActive {
            return demoSnapshot
        }
#endif
        guard let id = config.externalDeviceID else { return nil }
        return service.snapshot(deviceID: id, channelIndex: config.channelIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                header
                Divider()
            }

            content
        }
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .padding(.bottom, bottomPadding)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .onAppear {
            guard !isLANSnapshotRendering, !isDemoModeActive else { return }
            service.setLiveModeEnabled(effectiveLiveMode)
            service.reconcile()
        }
        .onChange(of: isLiveMode, initial: false) { _, newValue in
            guard !isLANSnapshotRendering, !isDemoModeActive else { return }
            service.setLiveModeEnabled(newValue || liveModeEnabled)
        }
        .onChange(of: liveModeEnabled, initial: false) { _, newValue in
            guard !isLANSnapshotRendering, !isDemoModeActive else { return }
            service.setLiveModeEnabled(newValue || isLiveMode)
        }
#if DEBUG || BETA
        .onReceive(demoTick) { _ in
            guard isDemoModeActive else { return }
            demoPhase += 0.15
        }
#endif
    }

    // MARK: - Shure-style Layout

    private var header: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(resolvedPrimaryColor)

            Text(applyCapitalization("Sennheiser Wireless"))
                .font(headerFont)
                .foregroundStyle(resolvedPrimaryColor)

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        if device == nil {
            VStack(alignment: .leading, spacing: 4) {
                Text(applyCapitalization("No Sennheiser device configured."))
                    .font(contentFont)
                    .foregroundStyle(resolvedPrimaryColor)
                Text(applyCapitalization("Add a Sennheiser Wireless device in Settings → External Devices."))
                    .font(captionFont)
                    .foregroundStyle(resolvedSecondaryColor)
            }
        } else {
            channelSelectorSection
            Divider()
            channelReportsSection
        }
    }

    private var channelSelectorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            channelHeaderPill

            if config.showDeviceName || config.showHost {
                deviceInfoCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func channelStatusColor() -> Color {
        // Shure uses a status tint behind the pill. For parity, tint by connection state.
        switch connectionState {
        case .connected:
            return Color.white.opacity(0.10)
        case .connecting:
            return Color.white.opacity(0.07)
        case .disconnected:
            return Color.white.opacity(0.06)
        case .error:
            return Color.white.opacity(0.06)
        }
    }

    private var channelHeaderPill: some View {
        HStack(spacing: 8) {
            Text(applyCapitalization(headerTitle))
                .font(.system(size: baseFontSize * 1.15, weight: primaryFontWeight))
                .foregroundStyle(resolvedPrimaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Text(applyCapitalization(pillText))
                .font(captionFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(sennheiserBlue.opacity(0.95))
                )
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(channelStatusColor())
        )
    }

    private var headerTitle: String {
        // Prefer cached channel name (works even when snapshot polling returns empty).
        if config.showChannelName,
           let id = config.externalDeviceID,
           let cached = service.channelDisplayName(deviceID: id, channelIndex: config.channelIndex) {
            let name = cached.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }

        // Fall back to snapshot-provided name when present.
        if config.showChannelName, let snap = snapshot {
            let name = (snap.channelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            if !name.isEmpty { return name }
        }

        return "CH \(config.channelIndex)"
    }

    private var pillText: String {
        // Derive Mic/IEM from the external device model selection.
        guard let model = device?.sennheiserModelIdentifier?.uppercased() else { return "Mic" }
        // Any IEM family should surface as IEM.
        if model.contains("IEM") { return "IEM" }
        // Common Sennheiser transmitter/receiver naming hints
        if model.contains("SR") && model.contains("IEM") { return "IEM" }
        if model.contains("EK") && model.contains("IEM") { return "IEM" }
        if model.contains("XSW") && model.contains("IEM") { return "IEM" }
        return "Mic"
    }

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if config.showDeviceName {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                    Text(applyCapitalization(device?.name ?? "Sennheiser"))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                        .lineLimit(1)
                }
            }

            if config.showHost, let host = device?.host, !host.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                    Text(applyCapitalization("\(host):\(device?.port ?? 0)"))
                        .font(captionFont.monospacedDigit())
                        .foregroundStyle(resolvedSecondaryColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resolvedSecondaryColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var channelReportsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let shouldShowHeader = config.showFrequency || config.showBattery || config.showRF || config.showAudio
            if shouldShowHeader {
                Text(applyCapitalization("Channel Status"))
                    .font(contentFont.weight(.semibold))
                    .foregroundStyle(resolvedPrimaryColor)
            }

            if !effectiveLiveMode {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle")
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                    Text(applyCapitalization("Live data paused — enter Live Mode to update."))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(resolvedSecondaryColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if device == nil {
                Text(applyCapitalization("Select a Sennheiser device in the inspector."))
                    .font(captionFont)
                    .foregroundStyle(resolvedSecondaryColor)
            } else {
                switch connectionState {
                case .connected:
                    connectedStatusBody
                case .connecting:
                    Text(applyCapitalization("Connecting…"))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                case .disconnected:
                    Text(applyCapitalization("Disconnected"))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                case .error:
                    Text(applyCapitalization("Connection Error"))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)

                    if let id = config.externalDeviceID,
                       let err = service.lastErrorByDevice[id], !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(resolvedSecondaryColor)
                            .lineLimit(3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var connectedStatusBody: some View {
        if let snap = snapshot, isRecentSnapshot(snap.updatedAt) {
            let rfBars = barCount(from: snap.rfLevel01, maxBars: 5)
            let audioBars = barCount(from: snap.audioLevel01, maxBars: 8)

            VStack(alignment: .leading, spacing: 6) {
                if config.showFrequency {
                    statusRow(icon: "waveform.path.ecg", label: "Frequency", trailing: snap.frequencyMHz.map { String(format: "%.3f MHz", $0) } ?? "—")
                }
                if config.showBattery {
                    statusRow(icon: "battery.100", label: "Battery", trailing: snap.batteryPercent.map { "\($0)%" } ?? "—")
                }

                if config.showRF || config.showAudio {
                    VStack(alignment: .leading, spacing: 6) {
                        if config.showRF {
                            meterRow(icon: "antenna.radiowaves.left.and.right", label: "RF", bars: rfBars, total: 5)
                        }
                        if config.showAudio {
                            meterRow(icon: "speaker.wave.2.fill", label: "Audio", bars: audioBars, total: 8)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(resolvedSecondaryColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if !snap.warnings.isEmpty {
                    Text(snap.warnings.map { $0.rawValue }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(resolvedSecondaryColor)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(applyCapitalization("No recent data for \(device?.name ?? "Sennheiser") — CH \(config.channelIndex)."))
                .font(captionFont)
                .foregroundStyle(resolvedSecondaryColor)
        }
    }

    private func statusRow(icon: String, label: String, trailing: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(captionFont)
                .foregroundStyle(resolvedSecondaryColor)

            Text(applyCapitalization(label))
                .font(captionFont)
                .foregroundStyle(resolvedSecondaryColor)

            Spacer(minLength: 8)

            Text(trailing)
                .font(captionFont)
                .foregroundStyle(resolvedPrimaryColor)
        }
    }

#if DEBUG || BETA
    private var demoDevice: ExternalDeviceConfig {
        ExternalDeviceConfig(
            id: UUID(uuidString: "9D7845A2-44CF-4C61-9C36-0E4B6D8A0D7A") ?? UUID(),
            name: config.demoDeviceName,
            kind: .sennheiserWireless,
            host: "192.168.1.140",
            port: 8080,
            sennheiserModelIdentifier: config.demoIsIem ? "EW IEM G4" : "EW-DX EM 2"
        )
    }

    private var demoSnapshot: SennheiserChannelSnapshot {
        let rf = (sin(demoPhase * 0.7) + 1.0) * 0.5
        let audio = (sin(demoPhase * 1.2 + 0.6) + 1.0) * 0.5
        let frequencyBase = max(400.000, min(700.000, config.demoFrequencyMHz))
        return SennheiserChannelSnapshot(
            id: "demo-channel-1",
            deviceID: demoDevice.id,
            deviceName: demoDevice.name,
            channelIndex: config.channelIndex,
            channelRemoteID: "demo-remote-1",
            channelName: config.demoMicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Demo Mic" : config.demoMicName,
            frequencyMHz: frequencyBase,
            rfLevel01: rf,
            audioLevel01: audio,
            batteryPercent: max(0, min(100, config.demoBatteryPercent)),
            warnings: [],
            updatedAt: Date()
        )
    }
#endif
    private func meterRow(icon: String, label: String, bars: Int, total: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(captionFont)
                .foregroundStyle(resolvedSecondaryColor)

            Text(applyCapitalization(label))
                .font(captionFont)
                .foregroundStyle(resolvedSecondaryColor)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                ForEach(0..<total, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(idx < bars ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 10, height: 6)
                }
            }
        }
    }

    private func barCount(from level01: Double?, maxBars: Int) -> Int {
        guard let level = level01, level.isFinite else { return 0 }
        let clamped = min(max(level, 0.0), 1.0)
        let bars = Int(round(clamped * Double(maxBars)))
        return max(0, min(bars, maxBars))
    }

    private func isRecentSnapshot(_ date: Date) -> Bool {
        let threshold = max(6.0, config.pollIntervalSeconds * 3.0)
        return Date().timeIntervalSince(date) < threshold
    }


}

// MARK: - Inspector / Settings UI

/// This is intended to be used inside your tile EditView inspector.
/// You pass a Binding to the tile's stored SennheiserWirelessModuleConfig.
struct SennheiserWirelessModuleInspector: View {
    @Binding var config: SennheiserWirelessModuleConfig

    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    @ObservedObject private var store = ExternalDevicesStore.shared
    @ObservedObject private var service = SennheiserWirelessService.shared

    private var sennDevices: [ExternalDeviceConfig] {
        store.devices(ofKind: .sennheiserWireless)
    }

    private let moduleTitle: String = "Sennheiser Wireless Module"

    // Match Shure inspector: use switch-style toggles on macOS (instead of checkbox).
    private func switchToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
    }

    private struct ChannelOption: Identifiable, Hashable {
        let deviceID: UUID
        let channelIndex: Int
        var id: String { "\(deviceID.uuidString)-\(channelIndex)" }
    }

    private var channelOptions: [ChannelOption] {
        var out: [ChannelOption] = []
        for d in sennDevices {
            let maxCh = max(1, inferredChannelCount(for: d))
            for ch in 1...maxCh {
                out.append(ChannelOption(deviceID: d.id, channelIndex: ch))
            }
        }
        return out
    }

    private var selectedChannelOption: ChannelOption? {
        guard let id = config.externalDeviceID else { return nil }

        // If we have a stored remote ID, try to find the channelIndex whose cached record matches.
        if let wantedRemote = config.channelRemoteID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !wantedRemote.isEmpty,
           let per = service.channelNamesByDevice[id] {
            if let match = per.first(where: { $0.value.remoteID == wantedRemote }) {
                return ChannelOption(deviceID: id, channelIndex: match.key)
            }
        }

        // Fall back to the stored channelIndex.
        return ChannelOption(deviceID: id, channelIndex: config.channelIndex)
    }

    private func label(for option: ChannelOption) -> String {
        let deviceName = store.device(withID: option.deviceID)?.name ?? "Sennheiser"

        if let cached = service.channelDisplayName(deviceID: option.deviceID, channelIndex: option.channelIndex) {
            let trimmed = cached.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return "\(deviceName) — \(trimmed)"
            }
        }

        return "\(deviceName) — CH \(option.channelIndex)"
    }

    private func inferredChannelCount(for device: ExternalDeviceConfig) -> Int {
        guard let code = device.sennheiserModelIdentifier?.uppercased() else {
            return 1
        }

        if code.contains("EW-DX") {
            if code.contains("EM 4") { return 4 }
            if code.contains("EM 2") { return 2 }
        }
        if code.contains("EM 6000") || code.contains("DIGITAL 6000") { return 2 }
        if code.contains("IEM") { return 1 }

        return 1
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header (match Shure inspector feel)
                Text(moduleTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)

                // Channel
                VStack(alignment: .leading, spacing: 8) {
                    Text("Channel")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)

                    HStack(alignment: .center, spacing: 10) {
                        Text("Channel")
                            .frame(minWidth: 60, alignment: .leading)
                        Spacer(minLength: 8)
                        Picker("", selection: Binding<ChannelOption?>(
                            get: { selectedChannelOption },
                            set: { newValue in
                                guard let opt = newValue else {
                                    config.externalDeviceID = nil
                                    config.channelRemoteID = nil
                                    return
                                }
                                config.externalDeviceID = opt.deviceID
                                config.channelIndex = opt.channelIndex
                                config.channelRemoteID = service.channelRemoteID(deviceID: opt.deviceID, channelIndex: opt.channelIndex)

                                // Apply per-device interval and ensure pollers exist.
                                SennheiserWirelessService.shared.setPollIntervalSeconds(config.pollIntervalSeconds, for: opt.deviceID)
                                SennheiserWirelessService.shared.reconcile()
                            }
                        )) {
                            Text("None").tag(Optional<ChannelOption>.none)
                            ForEach(channelOptions) { opt in
                                Text(label(for: opt)).tag(Optional(opt))
                            }
                        }
                        .controlSize(.small)
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(statusText)
                            .opacity(0.75)
                    }
                    .font(.callout)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Display Options
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Options")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)

                    switchToggle("Show channel name", isOn: $config.showChannelName)
                    switchToggle("Show device name", isOn: $config.showDeviceName)
                    switchToggle("Show IP:Port", isOn: $config.showHost)
                    switchToggle("Show frequency", isOn: $config.showFrequency)
                    switchToggle("Show battery level", isOn: $config.showBattery)
                    switchToggle("Show RF strength", isOn: $config.showRF)
                    switchToggle("Show audio meter", isOn: $config.showAudio)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

#if DEBUG || BETA
                VStack(alignment: .leading, spacing: 8) {
                    Text("Demo Mode (Debug/Beta)")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)

                    switchToggle("Use Demo Data for Wireless Modules", isOn: $config.demoEnabled)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Device Name")
                            TextField("", text: $config.demoDeviceName)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Mic / Channel Name")
                            TextField("", text: $config.demoMicName)
                                .textFieldStyle(.roundedBorder)
                        }

                        switchToggle("IEM Mode", isOn: $config.demoIsIem)

                        HStack {
                            Text("Battery")
                            Spacer()
                            Stepper(value: $config.demoBatteryPercent, in: 0...100, step: 1) {
                                Text("\(config.demoBatteryPercent)%")
                                    .frame(minWidth: 48, alignment: .trailing)
                            }
                        }

                        HStack {
                            Text("Frequency")
                            Spacer()
                            Stepper(value: $config.demoFrequencyMHz, in: 400.0...700.0, step: 0.025) {
                                Text(String(format: "%.3f MHz", config.demoFrequencyMHz))
                                    .frame(minWidth: 110, alignment: .trailing)
                            }
                        }
                    }
                    .disabled(!config.demoEnabled)
                    .opacity(config.demoEnabled ? 1.0 : 0.5)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
#endif

                // Polling
                VStack(alignment: .leading, spacing: 8) {
                    Text("Polling")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)

                    Stepper(value: Binding(
                        get: { config.pollIntervalSeconds },
                        set: { newValue in
                            config.pollIntervalSeconds = newValue
                            if let deviceID = config.externalDeviceID {
                                SennheiserWirelessService.shared.setPollIntervalSeconds(newValue, for: deviceID)
                            }
                        }
                    ), in: 0.5...10.0, step: 0.5) {
                        Text(String(format: "Interval: %.1fs", config.pollIntervalSeconds))
                    }
                    .controlSize(.small)

                    Text("Polling interval applies per configured Sennheiser device.")
                        .font(.caption2)
                        .opacity(0.65)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Bottom padding so the last section isn't clipped.
                Spacer(minLength: 6)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            guard !isLANSnapshotRendering else { return }
            SennheiserWirelessService.shared.reconcile()
            if let deviceID = config.externalDeviceID {
                SennheiserWirelessService.shared.setPollIntervalSeconds(config.pollIntervalSeconds, for: deviceID)
            }
        }
    }


    private var statusText: String {
        guard let id = config.externalDeviceID else { return "—" }
        let state = service.connectionStateByDevice[id] ?? .disconnected
        return state.rawValue.capitalized
    }
}
