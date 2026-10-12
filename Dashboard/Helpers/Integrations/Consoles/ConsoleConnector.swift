//
//  ConsoleConnector.swift
//  Relay Dashboard
//
//  Console connector abstractions.
//  Implementations translate ConsoleCommand into OSC/TCP/vendor API calls.
//

@preconcurrency import Foundation
import Combine
import Network

/// Synchronous one-shot gate for `NWConnection` completion handlers.
///
/// The `TransportEventState` actor (`Dashboard/Helpers/Integrations/TransportEventState.swift`)
/// is preferred for new one-shot/receive-buffer code and has replaced this type at the two
/// call sites that were flagged under `SWIFT_STRICT_CONCURRENCY=targeted`
/// (`AllenHeathTCPService.waitForDLIVEAuthConfirmation`, `.receiveMatchedSysEx`). `OneShotGate`
/// itself remains in use at two more call sites (`AllenHeathTCPService.connect()`,
/// `QuMidiTCPService.connectInternal()`) where the gate is checked *synchronously* inside a
/// `stateUpdateHandler` closure, gating a decision (attempt TLS auth vs. resume immediately)
/// made on the very next line -- switching those to the actor would mean spawning a `Task` to
/// await the gate, which reorders that decision relative to the state-update callback for a
/// live TLS handshake against touring consoles. Neither remaining call site is flagged by the
/// strict-concurrency checker, and `hasFired` is correctly protected by `NSLock` (the
/// `@unchecked Sendable` here documents a manually-verified invariant, not an unexamined
/// escape hatch), so this was left as-is rather than risking that reordering for no
/// diagnostic benefit.
final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var hasFired = false

    /// Explicit and `nonisolated` so callers outside this file (e.g. `DiGiCoOSCClient`,
    /// an actor) can construct a gate without a main-actor hop -- the compiler-synthesized
    /// default `init()` would otherwise be implicitly main-actor-isolated under this
    /// module's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
    nonisolated init() {}

    nonisolated func tryFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasFired { return false }
        hasFired = true
        return true
    }
}

/// `Sendable` because commands are dispatched to a connector from `ConsoleConnectorRegistry`
/// (`@MainActor`) via `await connector.execute(...)`, which can suspend and resume on a
/// different executor. Every conforming type below is `@unchecked Sendable`: each one's own
/// stored properties are `let`-bound and safe to share, but they hold a reference to a
/// backing transport service (`OSCClient`, `AllenHeathTCPService`, or one of the `@MainActor`
/// `ObservableObject` console services shared with SwiftUI, e.g. `YamahaConsoleService`)
/// that is not itself formally `Sendable`. Making these connectors "real" `Sendable` without
/// `@unchecked` would require converting the backing `ObservableObject` services into actors,
/// which would break their use as `@Published`/`@MainActor` state for SwiftUI settings screens
/// elsewhere -- a materially larger, separate change out of scope for this task.
protocol ConsoleConnector: Sendable {
    var externalDeviceId: UUID { get }
    var deviceName: String { get }

    /// Execute a batch of commands. Implementations should coalesce calls when possible.
    func execute(_ commands: [ConsoleCommand]) async
}

/// Resolves ExternalDeviceConfig (audioConsole) into a connector implementation.
///
/// Note: ExternalDeviceConfig now stores `consoleModelIdentifier` to identify console models.
/// This is used to route to the appropriate connector implementation.
@MainActor
final class ConsoleConnectorRegistry: ObservableObject {
    static let shared = ConsoleConnectorRegistry()

    // ObservableObject conformance (we don't currently expose @Published state,
    // but some views may still observe this registry).
    let objectWillChange = ObservableObjectPublisher()

    private var connectors: [UUID: ConsoleConnector] = [:]

    private func postSendAllDebug(_ message: String) {
        NotificationCenter.default.post(
            name: .prodlinkGraphSendAllDebug,
            object: nil,
            userInfo: ["message": message]
        )
    }

    func connector(for externalDeviceId: UUID) -> ConsoleConnector? {
        connectors[externalDeviceId]
    }

    /// Creates (or returns existing) connector for a device.
    func connector(for device: ExternalDeviceConfig) -> ConsoleConnector? {
        if let existing = connectors[device.id] { return existing }
        guard device.kind == .audioConsole else { return nil }

        // Select implementation by stored model identifier.
        // `consoleModelIdentifier` is optional; if nil/unknown we can't route yet.
        let modelIdRaw = device.consoleModelIdentifier ?? ""
        let modelId = modelIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else {
            #if DEBUG
            print("[ConsoleConnectorRegistry] connector(for:): missing modelId for device=\(device.name) id=\(device.id) host=\(device.host):\(device.port)")
            #endif
            return nil
        }

        let connector: ConsoleConnector?
        switch modelId {
        // DiGiCo families
        case "DiGiCo",
             "DiGiCo_Q338", "DiGiCo_Quantum338", "DiGiCo_Quantum225", "DiGiCo_Quantum7",
             "DiGiCo_SD7", "DiGiCo_SD8", "DiGiCo_SD9", "DiGiCo_SD10", "DiGiCo_SD12":
            connector = DiGiCoConsoleConnector(device: device)

        // Behringer/Midas X32/M32 (accept legacy identifiers too)
        case "Behringer_X32", "Midas_M32",
             "Behringer X32", "Midas M32",
             "X32", "M32":
            connector = X32ConsoleConnector(device: device)

        // Allen & Heath families
        case "AH_dLive", "AH_Avantis", "AH_SQ":
            connector = AllenHeathConsoleConnector(device: device)

        case "AH_Qu", "AH_Qu5", "AH_Qu6", "AH_Qu7", "AH_Qu5D", "AH_Qu6D", "AH_Qu7D":
            connector = QuMidiTCPConsoleConnector(device: device)

        // Yamaha families
        case "Yamaha_DM7", "Yamaha_Rivage", "Yamaha_CL_QL":
            connector = YamahaConsoleConnector(device: device)

        // Behringer WING
        case "Behringer_Wing":
            connector = WingConsoleConnector(device: device)

        // Avid VENUE S6L
        case "Avid_VenueS6L":
            connector = VenueConsoleConnector(device: device)

        default:
            connector = nil
        }

        if let connector {
            connectors[device.id] = connector
        }
        return connector
    }

    /// Convenience: execute commands, grouping by console.
    func execute(_ commands: [GraphCommand]) async {
        let consoleCommands = commands.compactMap { cmd -> ConsoleCommand? in
            if case let .console(c) = cmd { return c }
            return nil
        }

        // group by device id
        let groups = Dictionary(grouping: consoleCommands) { c -> UUID in
            switch c {
            case .setChannelName(let id, _, _): return id
            case .fireSnapshot(let id, _): return id
            case .createSnapshot(let id, _): return id
            case .renameSnapshot(let id, _, _): return id
            case .sendMidi(let id, _): return id
            case .createCue(let id, _, _): return id
            case .createSnippet(let id, _, _): return id
            case .renameSnippet(let id, _, _): return id
            case .digicoOSC(let id, _, _): return id
            case .digicoOSCInt32(let id, _, _): return id
            case .venueOSC(let id, _, _): return id
            case .setChannelParameter(let id, _, _, _): return id
            @unknown default:
                // If new ConsoleCommand cases are added later, route them by device id when possible.
                // Today we don't have a safe way to extract an id here without knowing the case shape.
                return UUID()
            }
        }

        for (deviceId, cmds) in groups {
            guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceId }) else {
                #if DEBUG
                print("[ConsoleConnectorRegistry] execute: device not found id=\(deviceId) cmds=\(cmds.count)")
                #endif
                postSendAllDebug("Registry: device not found • id=\(deviceId.uuidString.prefix(6)) cmds=\(cmds.count)")
                continue
            }

            if device.isEnabled == false {
                #if DEBUG
                print("[ConsoleConnectorRegistry] execute: device disabled id=\(deviceId) name=\(device.name) model=\((device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) cmds=\(cmds.count)")
                #endif
                postSendAllDebug("Registry: device disabled • id=\(deviceId.uuidString.prefix(6)) name=\(device.name)")
                continue
            }

            guard let connector = connector(for: device) else {
                #if DEBUG
                print("[ConsoleConnectorRegistry] execute: NO CONNECTOR id=\(deviceId) name=\(device.name) kind=\(device.kind) model=\((device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) host=\(device.host):\(device.port) cmds=\(cmds.count)")
                #endif
                postSendAllDebug("Registry: no connector • id=\(deviceId.uuidString.prefix(6)) model=\((device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines))")
                continue
            }

            let model = (device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            let shownPort: UInt16 = (model == "Behringer_X32" || model == "Midas_M32" || model == "Behringer X32" || model == "Midas M32" || model == "X32" || model == "M32") ? 10023 : device.port
            print("[ConsoleConnectorRegistry] execute: routed \(cmds.count) cmds -> \(type(of: connector)) for id=\(deviceId) model=\(model) host=\(device.host):\(shownPort)")
            #endif

            postSendAllDebug("Registry: routed • cmds=\(cmds.count) model=\(model) id=\(deviceId.uuidString.prefix(6))")

            await connector.execute(cmds)
        }
    }

    /// X32/M32: Sync channel names from the console (reads the active show).
    /// Returns a map of channelIndex -> channelName.
    func syncX32ChannelNames(externalDeviceId: UUID,
                             channelCount: Int = 32,
                             timeout: TimeInterval = 2.0) async -> [Int: String] {
        guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId }) else {
            #if DEBUG
            print("[ConsoleConnectorRegistry] syncX32ChannelNames: device not found id=\(externalDeviceId)")
            #endif
            return [:]
        }
        guard device.kind == .audioConsole else { return [:] }
        let model = (device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isX32 = (model == "Behringer_X32" || model == "Midas_M32" || model == "Behringer X32" || model == "Midas M32" || model == "X32" || model == "M32")
        guard isX32 else {
            #if DEBUG
            print("[ConsoleConnectorRegistry] syncX32ChannelNames: not an X32/M32 model=\(model)")
            #endif
            return [:]
        }

        // Ensure a connector exists.
        guard let c = connector(for: device) as? X32ConsoleConnector else {
            #if DEBUG
            print("[ConsoleConnectorRegistry] syncX32ChannelNames: missing X32ConsoleConnector")
            #endif
            return [:]
        }

        return await c.syncChannelNames(channelCount: channelCount, timeout: timeout)
    }

    /// Allen & Heath dLive / Avantis / SQ: Sync channel names from the console via MIDI-over-TCP.
    func syncAllenHeathChannelNames(externalDeviceId: UUID,
                                    channelCount: Int = 128,
                                    timeout: TimeInterval = 1.0) async -> [Int: String] {
        guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId }) else {
            #if DEBUG
            print("[ConsoleConnectorRegistry] syncAllenHeathChannelNames: device not found id=\(externalDeviceId)")
            #endif
            return [:]
        }
        guard device.kind == .audioConsole else { return [:] }
        guard let model = device.audioConsoleModel else { return [:] }

        switch model {
        case .allenHeathDlive, .allenHeathAvantis, .allenHeathSq:
            break
        default:
            #if DEBUG
            print("[ConsoleConnectorRegistry] syncAllenHeathChannelNames: unsupported model=\(model.rawValue)")
            #endif
            return [:]
        }

        guard let connector = connector(for: device) as? AllenHeathConsoleConnector else {
            #if DEBUG
            print("[ConsoleConnectorRegistry] syncAllenHeathChannelNames: missing AllenHeathConsoleConnector")
            #endif
            return [:]
        }

        return await connector.syncChannelNames(channelCount: channelCount, timeout: timeout)
    }
}

// MARK: - Real Connectors (OSC/TCP)
// These implementations are adapted from the legacy Relay (PCODiGiCoApp) services,
// but shaped to the new ConsoleConnector + ConsoleCommand API.

/// Lightweight OSC sender over UDP (Network.framework).
/// Builds proper OSC packets: address + ",<typetags>" + 32-bit big-endian args, 4-byte aligned.
final class OSCClient {
    private let queue = DispatchQueue(label: "Relay.OSCClient", qos: .userInitiated)
    private var connection: NWConnection?
    private var currentHost: String = ""
    private var currentPort: UInt16 = 0
    private var isReady = false
    private var didFail = false
    private var pendingPayloads: [Data] = []

    enum OSCArgument: CustomStringConvertible {
        case int32(Int32)
        case string(String)
        case float32(Float)

        var description: String {
            switch self {
            case .int32(let v): return "i(\(v))"
            case .string(let s): return "s(\(s))"
            case .float32(let v): return "f(\(v))"
            }
        }
    }

    init() {}

    /// Prepare (or re-prepare) the UDP connection if host/port changed.
    func configure(host: String, port: UInt16) {
        queue.async {
            let needsRebuild = host != self.currentHost ||
                port != self.currentPort ||
                self.connection == nil ||
                self.didFail

            guard needsRebuild else { return }
            self.currentHost = host
            self.currentPort = port
            self.rebuildConnection(host: host, port: port)
        }
    }

    func send(address: String, _ args: [OSCArgument]) {
        let payload = buildOSCMessage(address: address, args: args)
        queue.async {
            guard !self.currentHost.isEmpty, self.currentPort > 0 else {
                print("OSC: send() called without configured connection")
                return
            }

            if self.connection == nil || self.didFail {
                self.rebuildConnection(host: self.currentHost, port: self.currentPort)
            }

            if self.isReady {
                self.sendPayload(payload)
            } else {
                self.pendingPayloads.append(payload)
            }
        }
    }

    private func rebuildConnection(host: String, port: UInt16) {
        connection?.cancel()
        connection = nil
        isReady = false
        didFail = false

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            print("OSC: invalid port \(port)")
            return
        }
        let params = NWParameters.udp
        params.allowFastOpen = true
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                switch state {
                case .ready:
                    self.isReady = true
                    self.didFail = false
                    self.flushPendingPayloads()
                case .failed(let error):
                    self.isReady = false
                    self.didFail = true
                    print("OSC: connection failed: \(error)")
                case .cancelled:
                    self.isReady = false
                default:
                    break
                }
            }
        }
        connection = conn
        conn.start(queue: queue)
    }

    private func flushPendingPayloads() {
        guard isReady, !pendingPayloads.isEmpty else { return }
        let payloads = pendingPayloads
        pendingPayloads.removeAll(keepingCapacity: true)
        for payload in payloads {
            sendPayload(payload)
        }
    }

    private func sendPayload(_ payload: Data) {
        guard let connection else {
            pendingPayloads.append(payload)
            return
        }
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.queue.async {
                self.isReady = false
                self.didFail = true
                self.pendingPayloads.insert(payload, at: 0)
                print("OSC: send error: \(error)")
            }
        })
    }

    private func buildOSCMessage(address: String, args: [OSCArgument]) -> Data {
        var data = Data()
        data.append(paddedCString(address))

        var types = ","
        for a in args {
            switch a {
            case .int32: types.append("i")
            case .string: types.append("s")
            case .float32: types.append("f")
            }
        }
        data.append(paddedCString(types))

        for a in args {
            switch a {
            case .int32(let v):
                var be = v.bigEndian
                withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
            case .string(let s):
                data.append(paddedCString(s))
            case .float32(let v):
                var big = v.bitPattern.bigEndian
                withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
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
}

// MARK: DiGiCo

/// DiGiCo OSC connector: channel naming + snapshot create/rename.
/// Naming path follows the legacy app’s “canonical” pattern:
///   /Input_Channels/{index}/Channel_Input/name  (string)
final class DiGiCoConsoleConnector: ConsoleConnector, @unchecked Sendable {
    let externalDeviceId: UUID
    let deviceName: String

    private let osc = OSCClient()

    /// DiGiCo can get a little unhappy if we blast snapshot OSC too quickly.
    /// Throttle snapshot-related OSC calls with a tiny delay.
    private let snapshotSendDelayNs: UInt64 = 120_000_000 // 120ms

    private func throttleSnapshotSend() async {
        // Task.sleep throws on cancellation; ignore so we don't crash.
        try? await Task.sleep(nanoseconds: snapshotSendDelayNs)
    }

    init(device: ExternalDeviceConfig) {
        self.externalDeviceId = device.id
        self.deviceName = device.name
        // Use the configured device port, not a hardcoded value.
        osc.configure(host: device.host, port: device.port)
    }

    private func latestDevice() -> ExternalDeviceConfig? {
        ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId })
    }

    private func effectiveSnapshotIndex(requested: Int, device: ExternalDeviceConfig) -> Int {
        let base = max(0, requested)
        guard device.consoleExistingSnapshots else { return base }

        // If the caller is already providing an absolute snapshot index (common in the new Graph workflow
        // where a user chooses a starting index like 3), do NOT add the existing snapshot count again.
        // We only apply the existing snapshot offset when the caller sends a small relative index (0/1).
        // This preserves the legacy "append after existing snapshots" behavior while preventing double offsets.
        if base > 1 {
            return base
        }

        return base + max(0, device.consoleExistingSnapshotCount)
    }

    func execute(_ commands: [ConsoleCommand]) async {
        guard let device = latestDevice() else { return }
        guard device.isEnabled else { return }

        // Configure each time in case host/port changed in settings.
        osc.configure(host: device.host, port: device.port)

        for cmd in commands {
            switch cmd {
            case .setChannelName(_, let channelIndex, let name):
                let safe = name.replacingOccurrences(of: "\"", with: "'")
                let addr = "/Input_Channels/\(max(1, channelIndex))/Channel_Input/name"
                osc.send(address: addr, [.string(safe)])

            case .createSnapshot(_, let index):
                let eff = effectiveSnapshotIndex(requested: index, device: device)
                osc.sendNewSnapshot(index: eff)
                await throttleSnapshotSend()

            case .renameSnapshot(_, let index, let name):
                let eff = effectiveSnapshotIndex(requested: index, device: device)
                osc.sendRenameSnapshot(index: eff, name: name)
                await throttleSnapshotSend()

            case .createCue(_, let index, let name):
                #if DEBUG
                print("[DiGiCoConnector] createCue not supported (index=\(index) name=\(name))")
                #endif

            case .createSnippet(_, let index, let name):
                #if DEBUG
                print("[DiGiCoConnector] createSnippet not supported (index=\(index) name=\(name))")
                #endif

            case .renameSnippet(_, let slot, let name):
                #if DEBUG
                print("[DiGiCoConnector] renameSnippet not supported (slot=\(slot) name=\(name))")
                #endif

            case .sendMidi:
                #if DEBUG
                print("[DiGiCoConnector] sendMidi not supported")
                #endif

            case .digicoOSC(_, let address, let floatValue):
                osc.send(address: address, [.float32(floatValue)])

            case .digicoOSCInt32(_, let address, let intValue):
                osc.send(address: address, [.int32(intValue)])

            case .fireSnapshot(_, let snapshot):
                // Legacy behavior for DiGiCo: create + rename snapshots (no "fire/recall").
                // We interpret `snapshot` as either:
                //   - "12:Snapshot Name" or "12|Snapshot Name" (index + name)
                //   - "12" (index only; name will default to "Snapshot 12")
                let trimmed: String
                switch snapshot {
                case .index(let i):
                    trimmed = String(i)
                case .name(let s):
                    trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let parts: [String]
                if trimmed.contains("|") {
                    parts = trimmed.split(separator: "|", maxSplits: 1).map { String($0) }
                } else if trimmed.contains(":") {
                    parts = trimmed.split(separator: ":", maxSplits: 1).map { String($0) }
                } else {
                    parts = [trimmed]
                }

                guard let idx = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    print("[DiGiCoConnector] snapshot create/rename ignored (missing numeric index): \(snapshot)")
                    continue
                }

                let name: String
                if parts.count > 1 {
                    name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    name = "Snapshot \(idx)"
                }

                let eff = effectiveSnapshotIndex(requested: idx, device: device)
                osc.sendNewSnapshot(index: eff)
                await throttleSnapshotSend()
                osc.sendRenameSnapshot(index: eff, name: name)
                await throttleSnapshotSend()

            case .setChannelParameter:
                #if DEBUG
                print("[DiGiCoConnector] setChannelParameter not supported")
                #endif

            case .venueOSC:
                #if DEBUG
                print("[DiGiCoConnector] venueOSC not supported")
                #endif

            @unknown default:
                #if DEBUG
                print("[DiGiCoConnector] command ignored (unknown/not supported)")
                #endif
            }
        }
    }
}

// MARK: X32 / M32

/// Minimal X32/M32 OSC UDP client (adapted from legacy X32Service).
/// Supports channel name set and scene load.
final class X32OSCClient {
    // X32/M32 commonly uses 10024 as the client's local UDP port (optional but improves reliability)
    private var localPort: UInt16 = 10024

    private let queue = DispatchQueue(label: "Relay.X32OSCClient")
    private var connection: NWConnection?
    private var endpointHost: String = ""
    private var endpointPort: UInt16 = 0

    /// Prevent overlapping configure() calls / rapid rebinds
    private var isConfiguring = false
    /// Simple send throttle to space back-to-back sends
    private var lastSendAt = Date.distantPast
    /// True once NWConnection enters .ready
    private var isReady: Bool = false
    /// Queue of packets to send once .ready
    private var pendingSends: [Data] = []

    #if DEBUG
    private func dbg(_ msg: String) { print(msg) }
    #else
    private func dbg(_ msg: String) {}
    #endif

    init() {}

    /// X32/M32 fader value curve: piecewise-linear approximation of the console's
    /// pseudo-log taper. Verified against documented anchor points (0.75=0dB, 0.825=+3dB)
    /// in Patrick-Gilles Maillot's Unofficial X32/M32 OSC Remote Protocol; segment
    /// boundaries are self-consistent (each pair of adjacent formulas agrees exactly
    /// at the boundary dB value).
    static func faderValue(fromDb db: Double) -> Float {
        let clamped = max(-90.0, min(10.0, db))
        let value: Double
        switch clamped {
        case -10.0...10.0:
            value = (clamped + 30.0) / 40.0
        case -30.0..<(-10.0):
            value = (clamped + 50.0) / 80.0
        case -60.0..<(-30.0):
            value = (clamped + 70.0) / 160.0
        default: // -90.0..<(-60.0)
            value = (clamped + 90.0) / 480.0
        }
        return Float(max(0.0, min(1.0, value)))
    }

    /// Normalized pan (-1.0 full left ... 1.0 full right) to X32's linear 0.0...1.0 range.
    static func panValue(from normalized: Double) -> Float {
        let clamped = max(-1.0, min(1.0, normalized))
        return Float((clamped + 1.0) / 2.0)
    }

    /// Optionally bind the local UDP port used for sending.
    func setLocalReceivePort(_ port: UInt16) {
        guard port != localPort else { return }
        localPort = port
        // Rebind on the new local port while keeping the current remote endpoint
        configure(host: endpointHost, port: endpointPort)
    }

    /// Tear down the UDP connection so a fresh bind can occur on the next configure.
    func resetConnection() {
        queue.async {
            if let conn = self.connection {
                conn.stateUpdateHandler = nil
                conn.cancel()
            }
            self.connection = nil
            self.isReady = false
            self.pendingSends.removeAll()
        }
    }

    func configure(host: String, port: UInt16) {
        guard !isConfiguring else {
            dbg("[X32OSCClient] configure skipped (already configuring)")
            return
        }
        isConfiguring = true

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, port > 0 else {
            isConfiguring = false
            return
        }

        if trimmedHost == endpointHost, port == endpointPort, connection != nil {
            isConfiguring = false
            return
        }

        endpointHost = trimmedHost
        endpointPort = port
        isReady = false
        pendingSends.removeAll()

        if let conn = connection {
            conn.cancel()
            connection = nil
        }

        func makeParams(bindToLocal: Bool) -> NWParameters {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            if bindToLocal, let localNWPort = NWEndpoint.Port(rawValue: localPort) {
                params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("0.0.0.0"), port: localNWPort)
            }
            return params
        }

        let remoteHost = NWEndpoint.Host(trimmedHost)
        let remotePort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 10023)!

        func startConnection(bindToLocal: Bool) {
            let conn = NWConnection(host: remoteHost, port: remotePort, using: makeParams(bindToLocal: bindToLocal))
            self.connection = conn

            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.dbg("[X32OSCClient] UDP ready (bind=\(bindToLocal)). Local=\(String(describing: conn.currentPath?.localEndpoint)) Remote=\(String(describing: conn.currentPath?.remoteEndpoint))")
                    self.isReady = true
                    if !self.pendingSends.isEmpty {
                        let toSend = self.pendingSends
                        self.pendingSends.removeAll()

                        // Pace any queued sends to avoid overwhelming X32/M32 show-control writes.
                        // 10ms spacing is conservative but reliable.
                        for (i, pkt) in toSend.enumerated() {
                            self.queue.asyncAfter(deadline: .now() + (Double(i) * 0.010)) {
                                conn.send(content: pkt, completion: .contentProcessed({ _ in }))
                            }
                        }
                    }

                case .waiting(let error):
                    self.dbg("[X32OSCClient] UDP waiting (bind=\(bindToLocal)): \(error)")
                    if bindToLocal, case .posix(let code) = error, (code == .EADDRINUSE || code == .EEXIST) {
                        self.dbg("[X32OSCClient] local port \(self.localPort) in use, retrying with ephemeral port")
                        conn.cancel()
                        self.queue.asyncAfter(deadline: .now() + 0.05) {
                            startConnection(bindToLocal: false)
                        }
                    }

                case .failed(let error):
                    self.dbg("[X32OSCClient] UDP failed (bind=\(bindToLocal)): \(error)")
                    if self.connection === conn {
                        // Drop the dead connection and clear isReady so the next configure()
                        // call rebuilds it instead of silently sending into a socket that
                        // will never deliver again (isReady otherwise stays stuck at true).
                        self.isReady = false
                        self.connection = nil
                    }
                    if bindToLocal, case .posix(let code) = error, code == .EADDRINUSE {
                        self.dbg("[X32OSCClient] local port \(self.localPort) in use, retrying with ephemeral port")
                        startConnection(bindToLocal: false)
                    }

                default:
                    break
                }
            }

            conn.start(queue: queue)
        }

        // Try fixed local port first; fallback to ephemeral if in use.
        queue.asyncAfter(deadline: .now() + 0.15) {
            startConnection(bindToLocal: true)
            self.isConfiguring = false
        }
    }

    private enum OSCArg { case string(String), int32(Int32), float32(Float) }

    /// Send immediately if connection is .ready; else enqueue until ready.
    private func sendNowOrQueue(_ packet: Data, label: String) {
        // Space bursts by ~8ms to reduce contention on some stacks.
        let delta = Date().timeIntervalSince(lastSendAt)
        if delta < 0.008 {
            let delay = 0.008 - delta
            queue.asyncAfter(deadline: .now() + delay) {
                self.sendNowOrQueue(packet, label: label)
            }
            return
        }
        lastSendAt = Date()

        if isReady, let conn = connection {
            conn.send(content: packet, completion: .contentProcessed({ _ in }))
        } else {
            pendingSends.append(packet)
        }
    }

    private func paddedCString(_ s: String) -> Data {
        var data = s.data(using: .utf8) ?? Data()
        data.append(0)
        while data.count % 4 != 0 { data.append(0) }
        return data
    }

    private func sendOSC(address: String, args: [OSCArg]) {
        guard !endpointHost.isEmpty, endpointPort > 0 else { return }
        var packet = Data()
        packet.append(paddedCString(address))

        var typeTags = ","
        for arg in args {
            switch arg {
            case .string: typeTags.append("s")
            case .int32:  typeTags.append("i")
            case .float32: typeTags.append("f")
            }
        }
        packet.append(paddedCString(typeTags))

        for arg in args {
            switch arg {
            case .string(let s):
                packet.append(paddedCString(s))
            case .int32(let i):
                var be = i.bigEndian
                packet.append(Data(bytes: &be, count: 4))
            case .float32(let f):
                var be = f.bitPattern.bigEndian
                packet.append(Data(bytes: &be, count: 4))
            }
        }

        sendNowOrQueue(packet, label: address)
    }

    /// Send an OSC message consisting of ONLY the address (no typetag string).
    /// Some X32 firmware responds more reliably to address-only GETs.
    fileprivate func sendOSCGetOnly(address: String) {
        guard !endpointHost.isEmpty, endpointPort > 0 else { return }
        var packet = Data()
        packet.append(paddedCString(address))
        sendNowOrQueue(packet, label: "GET \(address)")
    }

    /// X32/M32 keepalive. Many OSC features require the client to periodically send /xremote.
    func xremote() {
        sendOSC(address: "/xremote", args: [])
    }

    /// Await the UDP connection entering `.ready` so we can start a paced command burst.
    func waitUntilReady(timeout: TimeInterval = 1.0) async -> Bool {
        let deadline = Date().addingTimeInterval(max(0.05, timeout))
        while Date() < deadline {
            let ready: Bool = queue.sync { self.isReady }
            if ready { return true }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        return false
    }

    func setChannelName(channel: Int, name: String) {
        let ch = max(1, min(channel, 32))
        let path = String(format: "/ch/%02d/config/name", ch)
        let safe = String(name.prefix(12)) // X32 channel names are 12 chars
        sendOSC(address: path, args: [.string(safe)])
    }

    /// X32 "on" is 1=unmuted, 0=muted — inverted from the muted:Bool argument here.
    func setChannelMute(channel: Int, muted: Bool) {
        let ch = max(1, min(channel, 32))
        let path = String(format: "/ch/%02d/mix/on", ch)
        sendOSC(address: path, args: [.int32(muted ? 0 : 1)])
    }

    func setChannelLevel(channel: Int, db: Double) {
        let ch = max(1, min(channel, 32))
        let path = String(format: "/ch/%02d/mix/fader", ch)
        sendOSC(address: path, args: [.float32(Self.faderValue(fromDb: db))])
    }

    func setChannelPan(channel: Int, value: Double) {
        let ch = max(1, min(channel, 32))
        let path = String(format: "/ch/%02d/mix/pan", ch)
        sendOSC(address: path, args: [.float32(Self.panValue(from: value))])
    }
    // MARK: - X32/M32 Show Control (Cues / Snippets)

    /// X32/M32 cue numbers are encoded as Ints that mirror the UI numbering.
    /// Examples:
    ///   1.0.1 -> 101
    ///   1.0.9 -> 109
    ///   1.1.0 -> 110
    ///   1.1.1 -> 111
    private func cueNumber(fromLinearIndex index: Int) -> Int {
        // We intentionally start at 1.0.1 (101) because that's what users expect in the cue list.
        // index=0 -> 101, index=1 -> 102, ... index=9 -> 110
        return 101 + max(0, index)
    }

    /// Mirrors legacy Relay behavior (corrected for X32 cue numbering):
    /// /add ,s "cue" ,i <cueNumber> ,s <name>
    func createCue(index: Int, name: String) {
        let cueNum = cueNumber(fromLinearIndex: index)
        sendOSC(address: "/add", args: [.string("cue"), .int32(Int32(cueNum)), .string(name)])
    }

    /// /-show/showfile/cue/###/name ,s <name>
    func renameCue(slot: Int, name: String) {
        let slotStr = String(format: "%03d", max(0, slot))
        sendOSC(address: "/-show/showfile/cue/\(slotStr)/name", args: [.string(name)])
    }

    /// /add ,s "snippet" ,i <index> ,s <name>
    func createSnippet(index: Int, name: String) {
        let idx = max(0, index)
        sendOSC(address: "/add", args: [.string("snippet"), .int32(Int32(idx)), .string(name)])
    }

    /// /-show/showfile/snippet/###/name ,s <name>
    func renameSnippet(slot: Int, name: String) {
        let slotStr = String(format: "%03d", max(0, slot))
        sendOSC(address: "/-show/showfile/snippet/\(slotStr)/name", args: [.string(name)])
    }

    /// Recall/load a scene by index [0...99] using `/load "scene", <index>`.
    func loadScene(index: Int) {
        let i = max(0, min(index, 99))
        sendOSC(address: "/load", args: [.string("scene"), .int32(Int32(i))])
    }

    // MARK: - Minimal OSC parsing for channel-name replies (legacy behavior)

    private static func parseOSCChannelName(from data: Data) -> (ch: Int, name: String)? {
        func readPaddedString(_ bytes: inout ArraySlice<UInt8>) -> String? {
            guard let zeroIndex = bytes.firstIndex(of: 0) else { return nil }
            let strSlice = bytes[..<zeroIndex]
            let strArray = Array(strSlice)
            let d = Data(strArray)
            let s = String(data: d, encoding: .utf8)
                ?? String(data: d, encoding: .ascii)
                ?? String(decoding: strArray, as: UTF8.self)

            let consumedFromStart = bytes.distance(from: bytes.startIndex, to: zeroIndex) + 1
            let pad = (4 - (consumedFromStart % 4)) % 4
            bytes = bytes.dropFirst(consumedFromStart + pad)
            return s
        }

        var slice: ArraySlice<UInt8> = Array(data)[...]
        guard let addr = readPaddedString(&slice) else { return nil }

        // typetags (often ",s") — tolerate missing
        _ = readPaddedString(&slice) ?? ",s"

        // first argument is the name (may be empty)
        let name = readPaddedString(&slice) ?? ""

        // Extract channel number from the address components: /ch/09/config/name
        let comps = addr.split(separator: "/").map(String.init)
        var chText: String?
        if let chIndex = comps.firstIndex(where: { $0 == "ch" }), comps.count > chIndex + 1 {
            chText = comps[chIndex + 1]
        }
        guard let chStr = chText else { return nil }

        if let ch = Int(chStr) { return (max(1, ch), name) }
        let trimmedZeros = chStr.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        if let ch = Int(trimmedZeros) { return (max(1, ch), name) }
        return nil
    }

    /// Start a receive loop on the existing NWConnection. Non-blocking; caller controls how long to wait.
    private func startListeningForChannelNameReplies(until deadline: Date,
                                                     onName: @escaping (_ ch: Int, _ name: String) -> Void) {
        guard let conn = self.connection else { return }

        func receiveOnce() {
            conn.receiveMessage { (data, _, _, error) in
                if let data, !data.isEmpty {
                    if let (ch, name) = Self.parseOSCChannelName(from: data) {
                        onName(ch, name)
                    }
                }

                // Keep receiving until the deadline (and no hard error).
                if error == nil, Date() < deadline {
                    receiveOnce()
                }
            }
        }

        receiveOnce()
    }

    /// Sync channel names by sending GET-only requests and listening for replies.
    func syncChannelNames(count: Int = 32, timeout: TimeInterval = 2.0) async -> [Int: String] {
        let n = max(1, min(count, 64))

        // Wait briefly for connection readiness.
        let readyDeadline = Date().addingTimeInterval(1.0)
        while Date() < readyDeadline {
            let ready: Bool = queue.sync { self.isReady }
            if ready { break }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        // Collect replies. This runs on the receive callback thread; keep it lightweight.
        actor ChannelNameAccumulator {
            private var out: [Int: String] = [:]

            func set(_ ch: Int, _ name: String) {
                out[ch] = name
            }

            func snapshot() -> [Int: String] {
                out
            }
        }

        let accumulator = ChannelNameAccumulator()

        let deadline = Date().addingTimeInterval(max(0.1, timeout))

        // Start listening first so we don't miss early replies.
        startListeningForChannelNameReplies(until: deadline) { ch, name in
            guard ch >= 1 && ch <= n else { return }
            Task {
                await accumulator.set(ch, name)
            }
        }

        // Kick keepalive and send GET-only requests.
        xremote()
        for ch in 1...n {
            let path = String(format: "/ch/%02d/config/name", ch)
            sendOSCGetOnly(address: path)
        }

        // Wait for replies until timeout.
        let waitNs = UInt64(max(0.1, timeout) * 1_000_000_000.0)
        try? await Task.sleep(nanoseconds: waitNs)

        return await accumulator.snapshot()
    }
    // MARK: - Cues & Snippets (Show control)

    /// Add a cue: /add "cue" <index> <name>
    func addCue(indexInt: Int, name: String) {
        let i = max(0, min(indexInt, 999))
        sendOSC(address: "/add", args: [.string("cue"), .int32(Int32(i)), .string(name)])
    }

    /// Rename cue slot: /-show/showfile/cue/XYZ/name <name>
    func setCueName(slot: Int, name: String) {
        let s = max(0, min(slot, 999))
        let slotStr = String(format: "%03d", s)
        sendOSC(address: "/-show/showfile/cue/\(slotStr)/name", args: [.string(name)])
    }

    /// Add a snippet: /add "snippet" <index> <name>
    func addSnippet(indexInt: Int, name: String) {
        let i = max(0, min(indexInt, 999))
        sendOSC(address: "/add", args: [.string("snippet"), .int32(Int32(i)), .string(name)])
    }

    /// Rename snippet slot: /-show/showfile/snippet/XYZ/name <name>
    func setSnippetName(slot: Int, name: String) {
        let s = max(0, min(slot, 999))
        let slotStr = String(format: "%03d", s)
        sendOSC(address: "/-show/showfile/snippet/\(slotStr)/name", args: [.string(name)])
    }
}

final class X32ConsoleConnector: ConsoleConnector, @unchecked Sendable {
    let externalDeviceId: UUID
    let deviceName: String

    private let osc = X32OSCClient()

    init(device: ExternalDeviceConfig) {
        self.externalDeviceId = device.id
        self.deviceName = device.name
        // IMPORTANT: do not configure here.
        // device.port may represent the listen port (8000). We configure to 10023 in execute().
    }

    private func latestDevice() -> ExternalDeviceConfig? {
        ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId })
    }

    func execute(_ commands: [ConsoleCommand]) async {
        guard let device = latestDevice() else { return }
        guard device.isEnabled else { return }
        // X32/M32 destination (send) port is always 10023.
        osc.configure(host: device.host, port: 10023)
        osc.xremote()

        // Ensure the UDP socket is actually ready before we start sending a paced batch.
        // This prevents a large burst being queued and then flushed all-at-once at `.ready`.
        _ = await osc.waitUntilReady(timeout: 1.0)

        for (i, cmd) in commands.enumerated() {
            switch cmd {
            case .setChannelName(_, let channelIndex, let name):
                #if DEBUG
                let ch = max(1, channelIndex)
                let path = String(format: "/ch/%02d/config/name", ch)
                print("[X32Connector] setChannelName -> \(device.host):10023 \(path) name=\(String(name.prefix(12)))")
                #endif
                osc.setChannelName(channel: channelIndex, name: name)

            case .createSnapshot(_, _):
                // X32 does not support snapshot create via OSC; no-op
                print("[X32Connector] createSnapshot not supported")

            case .renameSnapshot(_, _, _):
                // X32 does not support snapshot rename via OSC; no-op
                print("[X32Connector] renameSnapshot not supported")

            case .fireSnapshot(_, let snapshot):
                let idx: Int?
                switch snapshot {
                case .index(let i):
                    idx = i
                case .name(let s):
                    idx = Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                guard let idx else {
                    print("[X32Connector] fireSnapshot ignored (non-numeric): \(snapshot)")
                    continue
                }
                osc.loadScene(index: idx)

            case .setChannelParameter(_, let channel, let parameter, let value):
                switch parameter {
                case .mute:
                    osc.setChannelMute(channel: channel, muted: value >= 0.5)
                case .level:
                    osc.setChannelLevel(channel: channel, db: value)
                case .pan:
                    osc.setChannelPan(channel: channel, value: value)
                }

            case .createCue(_, let index, let name):
                #if DEBUG
                print("[X32Connector] createCue -> \(device.host):10023 index=\(index) name=\(name)")
                #endif
                osc.createCue(index: index, name: name)

            case .createSnippet(_, let index, let name):
                #if DEBUG
                print("[X32Connector] createSnippet -> \(device.host):10023 index=\(index) name=\(name)")
                #endif
                osc.createSnippet(index: index, name: name)

            case .renameSnippet(_, let slot, let name):
                #if DEBUG
                print("[X32Connector] renameSnippet -> \(device.host):10023 slot=\(slot) name=\(name)")
                #endif
                osc.renameSnippet(slot: slot, name: name)

            case .sendMidi:
                #if DEBUG
                print("[X32Connector] sendMidi not supported")
                #endif

            default:
                #if DEBUG
                print("[X32Connector] command ignored (unknown/not supported)")
                #endif
            }

            // Keep the X32/M32 session alive during bursts.
            if i > 0 && i % 10 == 0 {
                osc.xremote()
            }

            // Pace OSC slightly for X32/M32 stability (prevents show-control commands being dropped).
            if i < commands.count - 1 {
                try? await Task.sleep(nanoseconds: 35_000_000) // 35ms
            }
        }
    }

    /// Sync channel names from the console by issuing GET-only requests and listening for replies.
    func syncChannelNames(channelCount: Int = 32, timeout: TimeInterval = 2.0) async -> [Int: String] {
        guard let device = latestDevice() else { return [:] }
        guard device.isEnabled else { return [:] }
        defer { osc.resetConnection() }

        // Ensure we are configured to the X32/M32 destination port.
        osc.configure(host: device.host, port: 10023)
        osc.xremote()

        let map = await osc.syncChannelNames(count: channelCount, timeout: timeout)

        #if DEBUG
        if map.isEmpty {
            print("[X32Connector] syncChannelNames returned EMPTY (host=\(device.host):10023)")
        } else {
            let sample = map.keys.sorted().prefix(8).map { ch in "\(ch)=\(map[ch] ?? "")" }.joined(separator: ", ")
            print("[X32Connector] syncChannelNames ok count=\(map.count) sample: \(sample)")
        }
        #endif

        return map
    }
}

// MARK: Allen & Heath (External Control TCP SysEx)

/// Minimal A&H external control TCP service (adapted from legacy AllenHeathTCPService).
/// Implements input name set via SysEx over TCP.
final class AllenHeathTCPService {
    enum Model {
        case dLiveMixRack          // ports: 51325 (plain), 51327 (TLS)
        case dLiveSurface          // ports: 51328 (plain), 51329 (TLS)
        case avantis               // port: 51325 (plain)
        case sq                    // uses same external-control doc; port typically 51325
    }

    struct Config {
        var host: String
        var model: Model
        var useTLS: Bool
        var dLiveTLSUserProfile: UInt8? = nil
        var dLiveTLSPassword: String? = nil
        var baseMidiChannelN: UInt8 = 0x0B

        init(host: String, model: Model, useTLS: Bool = false) {
            self.host = host
            self.model = model
            self.useTLS = useTLS
        }
    }

    enum StripKind { case input }

    private var cfg: Config
    private var connection: NWConnection?

    init(config: Config) {
        self.cfg = config
    }

    func updateHost(_ host: String) {
        cfg.host = host
    }

    func updateConfig(host: String,
                      model: Model,
                      useTLS: Bool,
                      tlsUserProfile: UInt8?,
                      tlsPassword: String?,
                      baseMidiChannelN: UInt8?) {
        let needsReconnect = (cfg.host != host) || (cfg.model != model) || (cfg.useTLS != useTLS)
        cfg.host = host
        cfg.model = model
        cfg.useTLS = useTLS
        cfg.dLiveTLSUserProfile = tlsUserProfile
        cfg.dLiveTLSPassword = tlsPassword
        if let baseMidiChannelN { cfg.baseMidiChannelN = baseMidiChannelN }
        if needsReconnect {
            disconnect()
        }
    }

    private func portAndTLS() -> (UInt16, Bool) {
        switch cfg.model {
        case .avantis:
            return (51325, false)
        case .sq:
            return (51325, false)
        case .dLiveMixRack:
            return (cfg.useTLS ? 51327 : 51325, cfg.useTLS)
        case .dLiveSurface:
            return (cfg.useTLS ? 51329 : 51328, cfg.useTLS)
        }
    }

    private var resolvedDLiveTLSUserProfile: UInt8? {
        guard cfg.useTLS else { return cfg.dLiveTLSUserProfile }
        switch cfg.model {
        case .dLiveMixRack, .dLiveSurface:
            return cfg.dLiveTLSUserProfile ?? 1
        case .avantis, .sq:
            return cfg.dLiveTLSUserProfile
        }
    }

    func connect() async throws {
        if let connection, case .ready = connection.state { return }

        let (port, tls) = portAndTLS()
        if tls, resolvedDLiveTLSUserProfile == nil {
            throw NSError(
                domain: "AllenHeathTCPService",
                code: -23,
                userInfo: [NSLocalizedDescriptionKey: "TLS authentication requires a dLive user profile"]
            )
        }
        let params = NWParameters.tcp
        if tls {
            params.defaultProtocolStack.applicationProtocols.insert(NWProtocolTLS.Options(), at: 0)
        }

        let endpoint = NWEndpoint.Host(cfg.host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let conn = NWConnection(host: endpoint, port: nwPort, using: params)
        connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumeGate = OneShotGate()
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard resumeGate.tryFire() else { return }
                    // dLive TLS requires immediate "UserProfile,UserPassword" and an AuthOK response.
                    if tls, let self {
                        Task {
                            do {
                                try await self.sendDLIVEAuthAndWaitForConfirmation()
                                cont.resume()
                            } catch {
                                cont.resume(throwing: error)
                            }
                        }
                    } else {
                        cont.resume()
                    }
                case .failed(let err):
                    guard resumeGate.tryFire() else { return }
                    cont.resume(throwing: err)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func setInputName(index: Int, name: String) async throws {
        let msg = try buildSetNameMessage(kind: .input, index: index, name: name)
        try await send(bytes: msg)
    }

    func getInputName(index: Int, timeout: TimeInterval = 1.0) async throws -> String? {
        let channelNote = try chNote(kind: .input, index: index)
        let msg = buildGetNameMessage(channelNote: channelNote)
        try await send(bytes: msg)
        // Snapshot the base-channel byte once, before the wait starts, and thread that
        // same snapshot through both the match closure below and `parseNameReply` at the
        // end -- rather than each re-deriving it via a fresh `byte0N()` call at whatever
        // moment it happens to run. `byte0N()` reads live `cfg.baseMidiChannelN`, which
        // `updateConfig()` can change while this call is in flight; using one snapshot for
        // the whole request/match/parse path keeps it self-consistent with the base-channel
        // byte the outgoing GET request on line 1357 was actually built with (also captured
        // at this same call time via `chNote`/`byte0N()`), instead of validating the reply
        // against whatever `cfg` says *now*. A closure over `self` is also not needed here,
        // which is what lets the match closure run as a pure function of Sendable value data
        // from the receive callback's nonisolated context.
        let baseChannelByte = byte0N()
        let expectedPrefix = buildSysExHeader() + [baseChannelByte, 0x02, channelNote]
        let reply = try await receiveMatchedSysEx(timeout: timeout) { message in
            guard message.count >= 12 else { return false }
            return Array(message.prefix(expectedPrefix.count)) == expectedPrefix
        }
        return parseNameReply(reply, expectedChannel: channelNote, baseChannelByte: baseChannelByte)
    }

    func recallScene(index: Int) async throws {
        let commands = try buildSceneRecallMessages(index: index)
        for command in commands {
            try await send(bytes: command)
        }
    }

    private func sendDLIVEAuthIfNeeded() async throws {
        guard cfg.useTLS else { return }
        guard let conn = connection else { return }
        guard let profile = resolvedDLiveTLSUserProfile else {
            throw NSError(
                domain: "AllenHeathTCPService",
                code: -23,
                userInfo: [NSLocalizedDescriptionKey: "TLS authentication requires a dLive user profile"]
            )
        }
        let pass = cfg.dLiveTLSPassword ?? ""
        let payload = "\(String(format: "%02X", profile)),\(pass)"
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: payload.data(using: .ascii), completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func sendDLIVEAuthAndWaitForConfirmation(timeout: TimeInterval = 3.0) async throws {
        try await sendDLIVEAuthIfNeeded()
        try await waitForDLIVEAuthConfirmation(timeout: timeout)
    }

    private func waitForDLIVEAuthConfirmation(timeout: TimeInterval) async throws {
        guard cfg.useTLS else { return }
        guard let conn = connection else {
            throw NSError(domain: "AllenHeathTCPService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Owns both the accumulated reply bytes and the one-shot "already resumed?"
            // flag. The receive completion below is a @Sendable closure invoked on
            // NWConnection's callback queue, racing the timeout's DispatchWorkItem, so
            // both pieces of state need to live behind an actor rather than captured vars.
            let state = TransportEventState()
            let timeoutWorkItem = DispatchWorkItem {
                Task {
                    guard await state.finishIfNeeded() else { return }
                    cont.resume(throwing: NSError(
                        domain: "AllenHeathTCPService",
                        code: -24,
                        userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for dLive TLS authentication confirmation"]
                    ))
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            @Sendable func receiveNext() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, isComplete, error in
                    Task {
                        if let data, !data.isEmpty {
                            await state.append(data)
                            let buffer = await state.bufferedData()
                            if let text = String(data: buffer, encoding: .ascii) {
                                if text.contains("AuthOK") {
                                    timeoutWorkItem.cancel()
                                    guard await state.finishIfNeeded() else { return }
                                    cont.resume()
                                    return
                                }

                                if text.localizedCaseInsensitiveContains("AuthFail") {
                                    timeoutWorkItem.cancel()
                                    guard await state.finishIfNeeded() else { return }
                                    cont.resume(throwing: NSError(
                                        domain: "AllenHeathTCPService",
                                        code: -25,
                                        userInfo: [NSLocalizedDescriptionKey: "dLive TLS authentication failed"]
                                    ))
                                    return
                                }
                            }
                        }

                        if let error {
                            timeoutWorkItem.cancel()
                            guard await state.finishIfNeeded() else { return }
                            cont.resume(throwing: error)
                            return
                        }

                        if isComplete {
                            timeoutWorkItem.cancel()
                            guard await state.finishIfNeeded() else { return }
                            cont.resume(throwing: NSError(
                                domain: "AllenHeathTCPService",
                                code: -26,
                                userInfo: [NSLocalizedDescriptionKey: "Connection closed before dLive TLS authentication completed"]
                            ))
                            return
                        }

                        receiveNext()
                    }
                }
            }

            receiveNext()
        }
    }

    private func send(bytes: [UInt8]) async throws {
        guard let conn = connection else {
            throw NSError(domain: "AllenHeathTCPService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    private func receiveMatchedSysEx(timeout: TimeInterval,
                                     match: @escaping @Sendable ([UInt8]) -> Bool) async throws -> [UInt8] {
        guard let conn = connection else {
            throw NSError(domain: "AllenHeathTCPService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            // Owns both the accumulated reply bytes and the one-shot "already resumed?"
            // flag -- see the identical rationale on `waitForDLIVEAuthConfirmation` above.
            let state = TransportEventState()
            let timeoutWorkItem = DispatchWorkItem {
                Task {
                    guard await state.finishIfNeeded() else { return }
                    cont.resume(throwing: NSError(
                        domain: "AllenHeathTCPService",
                        code: -20,
                        userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for SysEx reply"]
                    ))
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            @Sendable func receiveNext() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, isComplete, error in
                    Task {
                        if let data, !data.isEmpty {
                            await state.append(data)
                            let buffer = await state.bufferedData()
                            for message in Self.extractSysExMessages(from: buffer) {
                                if match(message) {
                                    timeoutWorkItem.cancel()
                                    guard await state.finishIfNeeded() else { return }
                                    cont.resume(returning: message)
                                    return
                                }
                            }
                        }

                        if let error {
                            timeoutWorkItem.cancel()
                            guard await state.finishIfNeeded() else { return }
                            cont.resume(throwing: error)
                            return
                        }

                        if isComplete {
                            timeoutWorkItem.cancel()
                            guard await state.finishIfNeeded() else { return }
                            cont.resume(throwing: NSError(
                                domain: "AllenHeathTCPService",
                                code: -21,
                                userInfo: [NSLocalizedDescriptionKey: "Connection closed while waiting for SysEx reply"]
                            ))
                            return
                        }

                        receiveNext()
                    }
                }
            }

            receiveNext()
        }
    }

    private func buildSysExHeader() -> [UInt8] {
        [0xF0, 0x00, 0x00, 0x1A, 0x50, 0x10, 0x01, 0x00]
    }

    private func byte0N() -> UInt8 { cfg.baseMidiChannelN & 0x0F }

    private func chNote(kind: StripKind, index: Int) throws -> UInt8 {
        guard index >= 1 else {
            throw NSError(domain: "AllenHeathTCPService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Index must be >= 1"])
        }
        switch (cfg.model, kind) {
        case (.dLiveMixRack, .input), (.dLiveSurface, .input):
            let i = index - 1
            guard i <= 0x7F else {
                throw NSError(domain: "AllenHeathTCPService", code: -11, userInfo: [NSLocalizedDescriptionKey: "dLive input out of range (1..128)"])
            }
            return UInt8(i)
        case (.avantis, .input):
            let i = index - 1
            guard i <= 0x3F else {
                throw NSError(domain: "AllenHeathTCPService", code: -12, userInfo: [NSLocalizedDescriptionKey: "Avantis input out of range (1..64)"])
            }
            return UInt8(i)
        case (.sq, .input):
            let i = index - 1
            guard i <= 0x3F else {
                throw NSError(domain: "AllenHeathTCPService", code: -13, userInfo: [NSLocalizedDescriptionKey: "SQ input out of range (1..64)"])
            }
            return UInt8(i)
        }
    }

    private func buildSetNameMessage(kind: StripKind, index: Int, name: String) throws -> [UInt8] {
        let safeName: Substring
        switch cfg.model {
        case .avantis, .sq:
            safeName = name.prefix(8)
        default:
            safeName = name.prefix(16)
        }
        let nameBytes = Array(safeName.utf8)
        let header = buildSysExHeader()
        let ch = try chNote(kind: kind, index: index)
        return header + [byte0N(), 0x03, ch] + nameBytes + [0xF7]
    }

    private func buildGetNameMessage(channelNote: UInt8) -> [UInt8] {
        buildSysExHeader() + [byte0N(), 0x01, channelNote, 0xF7]
    }

    /// `baseChannelByte` is passed in rather than re-derived via `byte0N()` so that callers
    /// validating a reply against a request they built earlier (e.g. `getInputName`) can
    /// pass the exact same snapshot used to build that request, instead of this method
    /// silently re-reading whatever `cfg.baseMidiChannelN` is live *now*.
    private func isNameReply(_ message: [UInt8], expectedChannel: UInt8, baseChannelByte: UInt8) -> Bool {
        guard message.count >= 12 else { return false }
        let prefix = buildSysExHeader()
        guard Array(message.prefix(prefix.count)) == prefix else { return false }
        guard message[prefix.count] == baseChannelByte else { return false }
        guard message[prefix.count + 1] == 0x02 else { return false }
        return message[prefix.count + 2] == expectedChannel
    }

    private func parseNameReply(_ message: [UInt8], expectedChannel: UInt8, baseChannelByte: UInt8) -> String? {
        guard isNameReply(message, expectedChannel: expectedChannel, baseChannelByte: baseChannelByte) else { return nil }
        let nameStart = buildSysExHeader().count + 3
        let nameEnd = max(nameStart, message.count - 1)
        let nameBytes = Array(message[nameStart..<nameEnd])
        return String(bytes: nameBytes, encoding: .utf8) ?? ""
    }

    private func buildSceneRecallMessages(index: Int) throws -> [[UInt8]] {
        guard index >= 1, index <= 500 else {
            throw NSError(
                domain: "AllenHeathTCPService",
                code: -22,
                userInfo: [NSLocalizedDescriptionKey: "Scene index out of range (1...500)"]
            )
        }

        let zeroBased = index - 1
        let bank = UInt8(zeroBased / 128)
        let scene = UInt8(zeroBased % 128)
        let bankStatus = 0xB0 | (byte0N() & 0x0F)
        let programStatus = 0xC0 | (byte0N() & 0x0F)
        return [
            [bankStatus, 0x00, bank],
            [programStatus, scene]
        ]
    }

    /// Pure byte-stream parser (touches no instance state), so it is safe to call from
    /// the `@Sendable` receive-completion closure in `receiveMatchedSysEx` without
    /// hopping back onto this (implicitly `@MainActor`) service's isolation.
    private nonisolated static func extractSysExMessages(from data: Data) -> [[UInt8]] {
        let bytes = [UInt8](data)
        var results: [[UInt8]] = []
        var startIndex: Int? = nil

        for (idx, byte) in bytes.enumerated() {
            if byte == 0xF0 {
                startIndex = idx
            } else if byte == 0xF7, let start = startIndex, start <= idx {
                results.append(Array(bytes[start...idx]))
                startIndex = nil
            }
        }

        return results
    }
}

final class AllenHeathConsoleConnector: ConsoleConnector, @unchecked Sendable {
    let externalDeviceId: UUID
    let deviceName: String

    private let service: AllenHeathTCPService

    init(device: ExternalDeviceConfig) {
        self.externalDeviceId = device.id
        self.deviceName = device.name

        // Choose an A&H model family from the stored identifier when possible.
        // Port is driven by the A&H external control spec (not the UI "port" field).
        let model = Self.resolvedModel(from: device)

        var config = AllenHeathTCPService.Config(host: device.host, model: model, useTLS: device.consoleUseTLS)
        config.dLiveTLSUserProfile = device.consoleTLSUserProfile
        config.dLiveTLSPassword = device.consoleTLSPassword
        if let baseMidi = device.consoleBaseMidiChannel {
            config.baseMidiChannelN = baseMidi
        }
        self.service = AllenHeathTCPService(config: config)
    }

    private func latestDevice() -> ExternalDeviceConfig? {
        ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId })
    }

    private func recordIntegrationError(_ message: String,
                                        key: String,
                                        minInterval: TimeInterval = 90) {
        RelayDiagnosticsStore.shared.recordThrottledError(
            message,
            tag: "AllenHeath",
            key: key,
            minInterval: minInterval
        )
    }

    private func describe(model: AllenHeathTCPService.Model) -> String {
        switch model {
        case .dLiveMixRack:
            return "dLive MixRack"
        case .dLiveSurface:
            return "dLive Surface"
        case .avantis:
            return "Avantis"
        case .sq:
            return "SQ"
        }
    }

    private func commandSummary(for commands: [ConsoleCommand]) -> String {
        var renameCount = 0
        var sceneRecallCount = 0
        var unsupportedCount = 0

        for command in commands {
            switch command {
            case .setChannelName:
                renameCount += 1
            case .fireSnapshot:
                sceneRecallCount += 1
            default:
                unsupportedCount += 1
            }
        }

        var parts: [String] = []
        if renameCount > 0 { parts.append("rename=\(renameCount)") }
        if sceneRecallCount > 0 { parts.append("scene=\(sceneRecallCount)") }
        if unsupportedCount > 0 { parts.append("unsupported=\(unsupportedCount)") }
        return parts.isEmpty ? "none" : parts.joined(separator: " ")
    }

    private static func resolvedModel(from device: ExternalDeviceConfig) -> AllenHeathTCPService.Model {
        switch device.consoleModelIdentifier {
        case "AH_Avantis":
            return .avantis
        case "AH_SQ":
            return .sq
        default:
            let submodel = (device.consoleSubmodelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if submodel == "dlive_surface" || submodel == "surface" || submodel.contains("surface") {
                return .dLiveSurface
            }
            return .dLiveMixRack
        }
    }

    func execute(_ commands: [ConsoleCommand]) async {
        guard let device = latestDevice() else { return }
        guard device.isEnabled else { return }
        let model = Self.resolvedModel(from: device)
        let modelDescription = describe(model: model)
        service.updateConfig(host: device.host,
                             model: model,
                             useTLS: device.consoleUseTLS,
                             tlsUserProfile: device.consoleTLSUserProfile,
                             tlsPassword: device.consoleTLSPassword,
                             baseMidiChannelN: device.consoleBaseMidiChannel)
        do {
            try await service.connect()
        } catch {
            let message = "connect failed model=\(modelDescription) host=\(device.host) tls=\(device.consoleUseTLS) error=\(error.localizedDescription)"
            print("[AllenHeathConnector] \(message)")
            recordIntegrationError(message, key: "ah_connect_failed_\(externalDeviceId.uuidString)")
            return
        }

        for cmd in commands {
            switch cmd {
            case .setChannelName(_, let channelIndex, let name):
                do {
                    try await service.setInputName(index: channelIndex, name: name)
                } catch {
                    let message = "setChannelName failed model=\(modelDescription) ch=\(channelIndex) error=\(error.localizedDescription)"
                    print("[AllenHeathConnector] \(message)")
                    recordIntegrationError(message, key: "ah_set_name_failed_\(externalDeviceId.uuidString)")
                }

            case .createSnapshot(_, _):
                // Not implemented for Allen & Heath yet
                print("[AllenHeathConnector] createSnapshot not implemented yet")

            case .renameSnapshot(_, _, _):
                // Not implemented for Allen & Heath yet
                print("[AllenHeathConnector] renameSnapshot not implemented yet")

            case .fireSnapshot(_, let snapshot):
                guard let sceneIndex = sceneIndex(from: snapshot) else {
                    continue
                }
                guard model != .dLiveSurface else {
                    continue
                }
                do {
                    try await service.recallScene(index: sceneIndex)
                } catch {
                    let message = "scene recall failed model=\(modelDescription) scene=\(sceneIndex) error=\(error.localizedDescription)"
                    print("[AllenHeathConnector] \(message)")
                    recordIntegrationError(message, key: "ah_scene_failed_\(externalDeviceId.uuidString)")
                }

            case .createCue(_, let index, let name):
                print("[AllenHeathConnector] createCue not implemented (index=\(index) name=\(name))")

            case .createSnippet(_, let index, let name):
                print("[AllenHeathConnector] createSnippet not implemented (index=\(index) name=\(name))")

            case .renameSnippet(_, let slot, let name):
                print("[AllenHeathConnector] renameSnippet not implemented (slot=\(slot) name=\(name))")
            case .sendMidi:
                print("[AllenHeathConnector] sendMidi not supported")
            default:
                #if DEBUG
                print("[AllenHeathConnector] command ignored (unknown/not supported)")
                #endif
            }
        }
    }

    func syncChannelNames(channelCount: Int, timeout: TimeInterval) async -> [Int: String] {
        guard let device = latestDevice() else { return [:] }
        guard device.isEnabled else { return [:] }

        let model = Self.resolvedModel(from: device)
        let modelDescription = describe(model: model)
        service.updateConfig(host: device.host,
                             model: model,
                             useTLS: device.consoleUseTLS,
                             tlsUserProfile: device.consoleTLSUserProfile,
                             tlsPassword: device.consoleTLSPassword,
                             baseMidiChannelN: device.consoleBaseMidiChannel)

        do {
            try await service.connect()
        } catch {
            let message = "sync connect failed model=\(modelDescription) host=\(device.host) tls=\(device.consoleUseTLS) error=\(error.localizedDescription)"
            print("[AllenHeathConnector] \(message)")
            recordIntegrationError(message, key: "ah_sync_connect_failed_\(externalDeviceId.uuidString)")
            return [:]
        }

        let limitedChannelCount: Int
        switch model {
        case .dLiveMixRack, .dLiveSurface:
            limitedChannelCount = min(max(0, channelCount), 128)
        case .avantis, .sq:
            limitedChannelCount = min(max(0, channelCount), 64)
        }

        guard limitedChannelCount > 0 else { return [:] }

        var names: [Int: String] = [:]
        for channelIndex in 1...limitedChannelCount {
            do {
                let trimmed = try await service.getInputName(index: channelIndex, timeout: timeout)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmed.isEmpty {
                    names[channelIndex] = trimmed
                }
            } catch {
                continue
            }
        }

        return names
    }

    private func sceneIndex(from snapshot: ConsoleSnapshotSelector) -> Int? {
        switch snapshot {
        case .index(let i):
            return i
        case .name(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let token: String
            if trimmed.contains("|") {
                token = trimmed.split(separator: "|", maxSplits: 1).first.map(String.init) ?? trimmed
            } else if trimmed.contains(":") {
                token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            } else {
                token = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
            }

            return Int(token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

final class QuMidiTCPConsoleConnector: ConsoleConnector, @unchecked Sendable {
    let externalDeviceId: UUID
    let deviceName: String

    private let service: QuMidiTCPService

    init(device: ExternalDeviceConfig) {
        self.externalDeviceId = device.id
        self.deviceName = device.name
        self.service = QuMidiTCPService(host: device.host, port: device.port)
    }

    private func latestDevice() -> ExternalDeviceConfig? {
        ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId })
    }

    func execute(_ commands: [ConsoleCommand]) async {
        guard let device = latestDevice() else { return }
        guard device.isEnabled else { return }

        service.updateHost(device.host, port: device.port)
        do {
            try await service.connect()
        } catch {
            print("[QuMIDIConnector] connect failed: \(error)")
            return
        }

        let channel = (device.consoleBaseMidiChannel ?? 0) & 0x0F

        for cmd in commands {
            switch cmd {
            case .fireSnapshot(_, let snapshot):
                guard let sceneIndex = Self.sceneIndex(from: snapshot) else {
                    print("[QuMIDIConnector] fireSnapshot ignored (non-numeric): \(snapshot)")
                    continue
                }
                await sendSceneRecall(index: sceneIndex, channel: channel)
            case .setChannelName(_, _, _):
                print("[QuMIDIConnector] setChannelName not implemented")
            case .createSnapshot(_, _):
                print("[QuMIDIConnector] createSnapshot not implemented")
            case .renameSnapshot(_, _, _):
                print("[QuMIDIConnector] renameSnapshot not implemented")
            case .createCue(_, let index, let name):
                print("[QuMIDIConnector] createCue not implemented (index=\(index) name=\(name))")
            case .createSnippet(_, let index, let name):
                print("[QuMIDIConnector] createSnippet not implemented (index=\(index) name=\(name))")
            case .renameSnippet(_, let slot, let name):
                print("[QuMIDIConnector] renameSnippet not implemented (slot=\(slot) name=\(name))")
            case .sendMidi(_, let bytes):
                await service.send(bytes: bytes)
            default:
                #if DEBUG
                print("[QuMIDIConnector] command ignored (unknown/not supported)")
                #endif
            }
        }

        // Close after each batch to avoid stale sessions on the console.
        service.disconnect()
    }

    /// Qu scene recall: Bank Select (CC#0) + Program Change, matching Allen & Heath's
    /// documented Qu MIDI Protocol (Bank Select value = index / 128, PC value = index % 128,
    /// with a -1 offset since Qu numbers scenes 1...N but MIDI counts 0...127 per bank).
    private func sendSceneRecall(index: Int, channel: UInt8) async {
        let clamped = max(1, min(500, index))
        let zeroBased = clamped - 1
        let bank = UInt8(zeroBased / 128)
        let scene = UInt8(zeroBased % 128)
        let bankStatus: UInt8 = 0xB0 | channel
        let programStatus: UInt8 = 0xC0 | channel
        await service.send(bytes: [bankStatus, 0x00, bank, programStatus, scene])
    }

    private static func sceneIndex(from snapshot: ConsoleSnapshotSelector) -> Int? {
        switch snapshot {
        case .index(let i):
            return i
        case .name(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let token: String
            if trimmed.contains("|") {
                token = trimmed.split(separator: "|", maxSplits: 1).first.map(String.init) ?? trimmed
            } else if trimmed.contains(":") {
                token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            } else {
                token = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
            }

            return Int(token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

final class QuMidiTCPService {
    private var host: String
    private var port: UInt16
    private var connection: NWConnection?
    private var connectTask: Task<Void, Error>?

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func updateHost(_ host: String, port: UInt16) {
        if self.host != host || self.port != port {
            disconnect()
        }
        self.host = host
        self.port = port
    }

    func connect() async throws {
        if let connection, case .ready = connection.state { return }

        if let task = connectTask {
            try await task.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            try await self.connectInternal()
        }
        connectTask = task
        defer { connectTask = nil }
        try await task.value
    }

    private func connectInternal() async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "QuMidiTCPService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = conn

        let resumeGate = OneShotGate()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGate.tryFire() else { return }
                    conn.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error):
                    guard resumeGate.tryFire() else { return }
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                case .cancelled:
                    guard resumeGate.tryFire() else { return }
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: NSError(domain: "QuMidiTCPService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Connection cancelled"]))
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(bytes: [UInt8]) async {
        guard let connection else { return }
        guard !bytes.isEmpty else { return }
        let data = Data(bytes)

        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}

final class YamahaConsoleConnector: ConsoleConnector, @unchecked Sendable {
    let externalDeviceId: UUID
    let deviceName: String

    private let service: YamahaConsoleService

    init(device: ExternalDeviceConfig) {
        self.externalDeviceId = device.id
        self.deviceName = device.name

        if let existing = YamahaConsoleServiceRegistry.shared.service(for: device) {
            self.service = existing
        } else {
            let family = Self.family(from: device)
            let endpoint = YamahaEndpoint(ip: device.host, family: family, oscPort: device.port)
            self.service = YamahaConsoleService(endpoint: endpoint, externalDeviceId: device.id)
        }
    }

    private func latestDevice() -> ExternalDeviceConfig? {
        ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId })
    }

    private static func family(from device: ExternalDeviceConfig) -> YamahaConsoleFamily {
        switch device.consoleModelIdentifier {
        case AudioConsoleModel.yamahaDm7.rawValue:
            return .dm7
        case AudioConsoleModel.yamahaRivage.rawValue:
            return .rivage
        default:
            return .clql
        }
    }

    func execute(_ commands: [ConsoleCommand]) async {
        guard let device = latestDevice() else { return }
        guard device.isEnabled else { return }

        let family = Self.family(from: device)
        service.updateFamily(family)
        service.updateFromDevice(device)
        service.startListeningForSceneRecallViaMIDI()

        for cmd in commands {
            switch cmd {
            case .setChannelName(_, let channelIndex, let name):
                if family == .clql { continue }
                service.setInputLabel(channel: channelIndex, name: name)

            case .fireSnapshot(_, let snapshot):
                guard let scene = sceneRef(from: snapshot, device: device) else { continue }
                service.recallScene(scene, fallbackBank: device.yamahaDm7SceneBank)

            case .setChannelParameter(_, let channel, let parameter, let value):
                if family == .clql { continue } // CL/QL has no OSC; not supported in this phase
                switch parameter {
                case .mute:
                    service.setChannelMute(channel: channel, muted: value >= 0.5)
                case .level:
                    service.setChannelLevel(channel: channel, db: value)
                case .pan:
                    service.setChannelPan(channel: channel, value: value)
                }

            case .createSnapshot(_, _):
                print("[YamahaConnector] createSnapshot not supported")

            case .renameSnapshot(_, _, _):
                print("[YamahaConnector] renameSnapshot not supported")

            case .createCue(_, let index, let name):
                print("[YamahaConnector] createCue not supported (index=\(index) name=\(name))")

            case .createSnippet(_, let index, let name):
                print("[YamahaConnector] createSnippet not supported (index=\(index) name=\(name))")

            case .renameSnippet(_, let slot, let name):
                print("[YamahaConnector] renameSnippet not supported (slot=\(slot) name=\(name))")
            case .sendMidi:
                print("[YamahaConnector] sendMidi not supported")
            default:
                #if DEBUG
                print("[YamahaConnector] command ignored (unknown/not supported)")
                #endif
            }
        }
    }

    private func sceneRef(from snapshot: ConsoleSnapshotSelector, device: ExternalDeviceConfig) -> YamahaSceneRef? {
        switch snapshot {
        case .index(let i):
            return YamahaSceneRef(numberString: String(i), bank: nil)
        case .name(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let token: String
            if trimmed.contains("|") {
                token = trimmed.split(separator: "|", maxSplits: 1).first.map(String.init) ?? trimmed
            } else if trimmed.contains(":") {
                token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            } else {
                token = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
            }

            return YamahaSceneRef(numberString: token, bank: nil)
        }
    }
}

final class WingConsoleConnector: ConsoleConnector, @unchecked Sendable {
    let externalDeviceId: UUID
    let deviceName: String

    private let service: WingConsoleService

    init(device: ExternalDeviceConfig) {
        self.externalDeviceId = device.id
        self.deviceName = device.name

        if let existing = WingConsoleServiceRegistry.shared.service(for: device) {
            self.service = existing
        } else {
            self.service = WingConsoleService(host: device.host, externalDeviceId: device.id)
        }
    }

    private func latestDevice() -> ExternalDeviceConfig? {
        ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId })
    }

    func execute(_ commands: [ConsoleCommand]) async {
        guard let device = latestDevice() else { return }
        guard device.isEnabled else { return }
        service.updateFromDevice(device)

        for cmd in commands {
            switch cmd {
            case .fireSnapshot(_, let snapshot):
                let sceneNumber: Int?
                switch snapshot {
                case .index(let i):
                    sceneNumber = i
                case .name(let s):
                    sceneNumber = Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                guard let sceneNumber else {
                    print("[WingConnector] fireSnapshot ignored (non-numeric): \(snapshot)")
                    continue
                }
                service.recallScene(number: sceneNumber)

            case .setChannelParameter(_, let channel, let parameter, let value):
                switch parameter {
                case .mute:
                    service.setChannelMute(channel: channel, muted: value >= 0.5)
                case .level:
                    service.setChannelLevel(channel: channel, db: value)
                case .pan:
                    service.setChannelPan(channel: channel, value: value)
                }

            case .setChannelName(_, _, _):
                print("[WingConnector] setChannelName not supported")

            case .createSnapshot(_, _):
                print("[WingConnector] createSnapshot not supported")

            case .renameSnapshot(_, _, _):
                print("[WingConnector] renameSnapshot not supported")

            case .sendMidi:
                print("[WingConnector] sendMidi not supported")

            default:
                #if DEBUG
                print("[WingConnector] command ignored (unknown/not supported)")
                #endif
            }
        }
    }
}

final class VenueConsoleConnector: ConsoleConnector, @unchecked Sendable {
    let externalDeviceId: UUID
    let deviceName: String

    private let service: VenueConsoleService

    init(device: ExternalDeviceConfig) {
        self.externalDeviceId = device.id
        self.deviceName = device.name

        if let existing = VenueConsoleServiceRegistry.shared.service(for: device) {
            self.service = existing
        } else {
            self.service = VenueConsoleService(
                host: device.host,
                port: device.port,
                transportMode: device.venueTransportMode ?? .tcp,
                externalDeviceId: device.id
            )
        }
    }

    private func latestDevice() -> ExternalDeviceConfig? {
        ExternalDevicesStore.shared.devices.first(where: { $0.id == externalDeviceId })
    }

    func execute(_ commands: [ConsoleCommand]) async {
        guard let device = latestDevice() else { return }
        guard device.isEnabled else { return }
        service.updateFromDevice(device)

        for cmd in commands {
            switch cmd {
            case .venueOSC(_, let address, let value):
                service.send(address: address, value: value)

            default:
                #if DEBUG
                print("[VenueConnector] command ignored (unknown/not supported)")
                #endif
            }
        }
    }
}

// MARK: - DiGiCo Snapshot Helpers (legacy)
/// Create a new snapshot at the given index.
/// Legacy pattern: /Snapshots/New_Snapshot/{index} with int 0.
extension OSCClient {
    func sendNewSnapshot(index: Int) {
        let addr = "/Snapshots/New_Snapshot/\(max(0, index))"
        send(address: addr, [.int32(0)])
    }

    /// Rename an existing snapshot at the given index.
    /// Legacy pattern: /Snapshots/Rename_Snapshot/{index} with string name.
    func sendRenameSnapshot(index: Int, name: String) {
        let safe = name.replacingOccurrences(of: "\"", with: "'")
        let addr = "/Snapshots/Rename_Snapshot/\(max(0, index))"
        send(address: addr, [.string(safe)])
    }
}
