//
//  YamahaConsoleService.swift
//  Relay
//
//  Yamaha OSC + MIDI integration (DM7 / RIVAGE / CL-QL)
//

import Foundation
import Network
import Combine

extension Notification.Name {
    static let yamahaConsoleSceneRecallDidArrive = Notification.Name("yamahaConsoleSceneRecallDidArrive")
}

enum YamahaConsoleFamily: String, Codable, CaseIterable {
    case dm7
    case rivage
    case clql
}

struct YamahaEndpoint: Codable, Hashable {
    var ip: String
    var family: YamahaConsoleFamily
    var oscPort: UInt16 = 49900
}

struct YamahaSceneRef: Codable, Hashable {
    var numberString: String
    var bank: String?
}

struct YamahaProgramChangeMapping: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var program: Int
    var sceneNumber: String
    var bank: String?

    init(id: UUID = UUID(), program: Int, sceneNumber: String, bank: String? = nil) {
        self.id = id
        self.program = program
        self.sceneNumber = sceneNumber
        self.bank = bank
    }
}

@MainActor
final class YamahaConsoleService: ObservableObject {
    enum ConnectionStatus: String {
        case disconnected
        case ready
    }

    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected
    @Published private(set) var lastRecalledScene: YamahaSceneRef?
    @Published private(set) var lastRecalledSceneTimestamp: Date?
    @Published private(set) var lastSentLabelUpdates: [Int: String] = [:]

    private let externalDeviceId: UUID
    private var endpoint: YamahaEndpoint

    private var oscConnection: NWConnection?
    private var currentHost: String = ""
    private var currentPort: UInt16 = 0

    private var labelDebounceTask: Task<Void, Never>?
    private var pendingLabelUpdates: [Int: String] = [:]

    private var programChangeMappings: [Int: YamahaSceneRef] = [:]
    private var preferredMIDISourceID: Int32?
    private var preferredMIDIDestinationID: Int32?
    private let midiBridge = YamahaMIDIBridge()

    init(endpoint: YamahaEndpoint, externalDeviceId: UUID) {
        self.endpoint = endpoint
        self.externalDeviceId = externalDeviceId

        midiBridge.onProgramChange = { [weak self] event in
            self?.handleProgramChange(event.program)
        }
        refreshMIDIBridge()
    }

    func updateFromDevice(_ device: ExternalDeviceConfig) {
        endpoint = YamahaEndpoint(ip: device.host, family: endpoint.family, oscPort: device.port)
        preferredMIDISourceID = device.yamahaMidiInputSourceID
        preferredMIDIDestinationID = device.yamahaMidiOutputDestinationID
        programChangeMappings = YamahaConsoleService.buildProgramMap(device.yamahaProgramChangeMappings)
        refreshMIDIBridge()
    }

    func updateFamily(_ family: YamahaConsoleFamily) {
        endpoint.family = family
    }

    func setInputLabel(channel: Int, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard channel >= 1, !trimmed.isEmpty else { return }
        let safeName = String(trimmed.prefix(8))
        pendingLabelUpdates[channel] = safeName
        scheduleLabelFlush()
    }

    /// Mute is only meaningful for DM7/Rivage (OSC). CL/QL has no equivalent in this
    /// service and must not call these — enforced by the caller (YamahaConsoleConnector).
    func setChannelMute(channel: Int, muted: Bool) {
        guard channel >= 1 else { return }
        sendOSC(address: "/yosc:req/set/MIXER:Current/InCh/Fader/On/\(channel)", args: [.string(muted ? "0" : "1")])
    }

    func setChannelLevel(channel: Int, db: Double) {
        guard channel >= 1 else { return }
        let value = Self.levelValue(fromDb: db)
        sendOSC(address: "/yosc:req/set/MIXER:Current/InCh/Fader/Level/\(channel)", args: [.string(String(value))])
    }

    func setChannelPan(channel: Int, value: Double) {
        guard channel >= 1 else { return }
        let panInt = Self.panValue(from: value)
        sendOSC(address: "/yosc:req/set/MIXER:Current/InCh/ToSt/Pan/\(channel)", args: [.string(String(panInt))])
    }

    func recallScene(_ scene: YamahaSceneRef, fallbackBank: String? = nil) {
        guard let sceneString = YamahaConsoleService.normalizedSceneNumber(scene.numberString) else { return }

        switch endpoint.family {
        case .dm7, .rivage:
            let bank = Self.resolvedSceneBank(family: endpoint.family, explicitBank: scene.bank, fallbackBank: fallbackBank)
            sendOSC(address: "/yosc:req/ssrecallt_ex", args: [.string(bank), .string(sceneString)])
        case .clql:
            guard let pc = programChangeForScene(sceneString, bank: scene.bank) else {
                #if DEBUG
                print("[YamahaConsoleService] No PC mapping for scene \(sceneString)")
                #endif
                return
            }
            midiBridge.sendProgramChange(pc)
        }
    }

    func startListeningForSceneRecallViaMIDI() {
        refreshMIDIBridge()
    }

    func stop() {
        midiBridge.disconnectSources()
        oscConnection?.cancel()
        oscConnection = nil
        connectionStatus = .disconnected
    }

    // MARK: - Label Debounce

    private func scheduleLabelFlush() {
        labelDebounceTask?.cancel()
        labelDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            flushLabelUpdates()
        }
    }

    private func flushLabelUpdates() {
        guard !pendingLabelUpdates.isEmpty else { return }
        let updates = pendingLabelUpdates
        pendingLabelUpdates.removeAll()

        for (channel, name) in updates {
            if lastSentLabelUpdates[channel] == name { continue }
            let addr = "/yosc:req/set/MIXER:Current/InCh/Label/Name/\(channel)"
            sendOSC(address: addr, args: [.string(name)])
            lastSentLabelUpdates[channel] = name
        }
    }

    // MARK: - OSC

    private enum OSCArgument {
        case string(String)

        var typeTag: String { "s" }
    }

    private func sendOSC(address: String, args: [OSCArgument]) {
        configureOSCIfNeeded()
        guard let oscConnection else { return }
        let payload = buildOSCMessage(address: address, args: args)
        oscConnection.send(content: payload, completion: .contentProcessed { _ in })
    }

    private func configureOSCIfNeeded() {
        let host = endpoint.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = endpoint.oscPort
        guard !host.isEmpty, port > 0 else { return }

        if oscConnection != nil, host == currentHost, port == currentPort { return }
        currentHost = host
        currentPort = port

        oscConnection?.cancel()
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 49900)!
        let params = NWParameters.udp
        params.allowFastOpen = true
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn else { return }
            DispatchQueue.main.async {
                // Ignore stale callbacks from a connection that's already been superseded/replaced.
                guard self.oscConnection === conn else { return }
                switch state {
                case .ready:
                    self.connectionStatus = .ready
                case .failed, .cancelled:
                    // Drop the dead connection so the next send rebuilds it instead of
                    // silently writing into a socket that will never deliver again.
                    self.oscConnection = nil
                    self.connectionStatus = .disconnected
                default:
                    break
                }
            }
        }
        oscConnection = conn
        conn.start(queue: .global(qos: .userInitiated))
    }

    private func buildOSCMessage(address: String, args: [OSCArgument]) -> Data {
        var data = Data()
        data.append(paddedCString(address))

        var typeTags = ","
        for arg in args { typeTags.append(arg.typeTag) }
        data.append(paddedCString(typeTags))

        for arg in args {
            switch arg {
            case .string(let s):
                data.append(paddedCString(s))
            }
        }
        return data
    }

    private func paddedCString(_ s: String) -> Data {
        var bytes = Array(s.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        return Data(bytes)
    }

    // MARK: - MIDI

    private func refreshMIDIBridge() {
        midiBridge.updateMappings(programChangeMappings)
        midiBridge.updatePreferredSource(preferredMIDISourceID)
        midiBridge.updatePreferredDestination(preferredMIDIDestinationID)
    }

    private func handleProgramChange(_ program: Int) {
        guard let scene = programChangeMappings[program] else { return }
        lastRecalledScene = scene
        lastRecalledSceneTimestamp = Date()

        NotificationCenter.default.post(
            name: .yamahaConsoleSceneRecallDidArrive,
            object: nil,
            userInfo: [
                "externalDeviceId": externalDeviceId,
                "program": program,
                "scene": scene,
                "timestamp": lastRecalledSceneTimestamp as Any
            ]
        )
    }

    // MARK: - Mapping

    private func programChangeForScene(_ sceneNumber: String, bank: String?) -> Int? {
        let normalized = YamahaConsoleService.normalizedSceneNumber(sceneNumber) ?? sceneNumber
        for (pc, scene) in programChangeMappings {
            let sceneNorm = YamahaConsoleService.normalizedSceneNumber(scene.numberString) ?? scene.numberString
            if sceneNorm == normalized {
                if let bank, let sceneBank = scene.bank, bank != sceneBank { continue }
                return pc
            }
        }
        return nil
    }

    private static func buildProgramMap(_ mappings: [YamahaProgramChangeMapping]) -> [Int: YamahaSceneRef] {
        var map: [Int: YamahaSceneRef] = [:]
        for mapping in mappings {
            let pc = max(0, min(127, mapping.program))
            let scene = YamahaSceneRef(numberString: mapping.sceneNumber, bank: mapping.bank)
            map[pc] = scene
        }
        return map
    }

    static func normalizedSceneNumber(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let decimal = Decimal(string: trimmed) {
            let number = NSDecimalNumber(decimal: decimal)
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.decimalSeparator = "."
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            formatter.minimumIntegerDigits = 1
            return formatter.string(from: number)
        }
        return nil
    }

    /// DM7 and Rivage PM share the same yosc:req OSC namespace and both use "scene_a"/"scene_b"
    /// as the bank parameter for /yosc:req/ssrecallt_ex — confirmed by the official DM7 Series
    /// OSC Specifications v1.1.0. (Previously Rivage incorrectly sent "MIXER:Lib/Scene".)
    static func resolvedSceneBank(family: YamahaConsoleFamily, explicitBank: String?, fallbackBank: String?) -> String {
        explicitBank ?? fallbackBank ?? "scene_a"
    }

    /// dB to DM7/Rivage Fader/Level integer encoding: value = dB * 100, range [-32768, 1000].
    /// -32768 represents -inf and is used as the floor for any dB at or below -90 (matches
    /// the Table 1 "min" entry in the official DM7 OSC Specification).
    static func levelValue(fromDb db: Double) -> Int {
        if db <= -90.0 { return -32768 }
        let scaled = Int((db * 100.0).rounded())
        return max(-32768, min(1000, scaled))
    }

    /// Normalized pan (-1.0 full left ... 1.0 full right) to DM7/Rivage's -63...63 int range.
    static func panValue(from normalized: Double) -> Int {
        let clamped = max(-1.0, min(1.0, normalized))
        return Int((clamped * 63.0).rounded())
    }
}

@MainActor
final class YamahaConsoleServiceRegistry: ObservableObject {
    static let shared = YamahaConsoleServiceRegistry()

    private var services: [UUID: YamahaConsoleService] = [:]
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = ExternalDevicesStore.shared.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.syncDevices(devices)
            }
    }

    func service(for device: ExternalDeviceConfig) -> YamahaConsoleService? {
        guard let family = YamahaConsoleServiceRegistry.family(for: device) else { return nil }
        if let existing = services[device.id] {
            existing.updateFamily(family)
            existing.updateFromDevice(device)
            return existing
        }

        let endpoint = YamahaEndpoint(ip: device.host, family: family, oscPort: device.port)
        let service = YamahaConsoleService(endpoint: endpoint, externalDeviceId: device.id)
        service.updateFromDevice(device)
        service.startListeningForSceneRecallViaMIDI()
        services[device.id] = service
        return service
    }

    private func syncDevices(_ devices: [ExternalDeviceConfig]) {
        let yamahaDevices = devices.filter { YamahaConsoleServiceRegistry.family(for: $0) != nil }
        let activeIds = Set(yamahaDevices.map { $0.id })

        for device in yamahaDevices {
            _ = service(for: device)
        }

        let toRemove = services.keys.filter { !activeIds.contains($0) }
        for id in toRemove {
            services[id]?.stop()
            services[id] = nil
        }
    }

    private static func family(for device: ExternalDeviceConfig) -> YamahaConsoleFamily? {
        guard device.kind == .audioConsole else { return nil }
        guard let modelId = device.consoleModelIdentifier else { return nil }
        switch modelId {
        case AudioConsoleModel.yamahaDm7.rawValue:
            return .dm7
        case AudioConsoleModel.yamahaRivage.rawValue:
            return .rivage
        case AudioConsoleModel.yamahaClQl.rawValue:
            return .clql
        default:
            return nil
        }
    }
}
