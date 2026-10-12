//
//  WingConsoleService.swift
//  Relay
//
//  Behringer WING OSC integration (WING / WING Compact / WING Rack).
//  Protocol verified against the production bitfocus/companion-module-behringer-wing
//  source (src/commands/channel.ts, src/commands/control.ts,
//  src/handlers/connection-handler.ts): OSC over UDP, port 2223.
//

import Foundation
import Network
import Combine

@MainActor
final class WingConsoleService: ObservableObject {
    enum ConnectionStatus: String {
        case disconnected
        case ready
    }

    static let oscPort: UInt16 = 2223

    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected

    private let externalDeviceId: UUID
    private var host: String

    private var oscConnection: NWConnection?
    private var currentHost: String = ""

    init(host: String, externalDeviceId: UUID) {
        self.host = host
        self.externalDeviceId = externalDeviceId
    }

    func updateFromDevice(_ device: ExternalDeviceConfig) {
        host = device.host
    }

    /// /ch/{n}/mute — int 1=mute, 0=unmute.
    func setChannelMute(channel: Int, muted: Bool) {
        guard channel >= 1 else { return }
        sendOSC(address: "/ch/\(channel)/mute", args: [.int32(muted ? 1 : 0)])
    }

    /// /ch/{n}/fdr — float, dB directly (no fader-curve conversion, unlike X32/Yamaha).
    func setChannelLevel(channel: Int, db: Double) {
        guard channel >= 1 else { return }
        let clamped = Self.wingLevelDb(from: db)
        sendOSC(address: "/ch/\(channel)/fdr", args: [.float32(Float(clamped))])
    }

    /// /ch/{n}/pan — int, -100 (full left) ... 100 (full right).
    func setChannelPan(channel: Int, value: Double) {
        guard channel >= 1 else { return }
        let panInt = Self.wingPanValue(from: value)
        sendOSC(address: "/ch/\(channel)/pan", args: [.int32(Int32(panInt))])
    }

    /// Scene recall is two sequential sends: set the selection index, then trigger "GO".
    func recallScene(number: Int) {
        guard number >= 1 else { return }
        sendOSC(address: "/$ctl/lib/$actionidx", args: [.int32(Int32(number))])
        sendOSC(address: "/$ctl/lib/$action", args: [.string("GO")])
    }

    func stop() {
        oscConnection?.cancel()
        oscConnection = nil
        connectionStatus = .disconnected
    }

    // MARK: - OSC

    private func sendOSC(address: String, args: [OSCValue]) {
        configureOSCIfNeeded()
        guard let oscConnection else { return }
        let payload = OSCCodec.encode(message: OSCMessage(address: address, args: args))
        oscConnection.send(content: payload, completion: .contentProcessed { _ in })
    }

    private func configureOSCIfNeeded() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }

        if oscConnection != nil, trimmedHost == currentHost { return }
        currentHost = trimmedHost

        oscConnection?.cancel()
        let nwHost = NWEndpoint.Host(trimmedHost)
        let nwPort = NWEndpoint.Port(rawValue: Self.oscPort)!
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

    // MARK: - Value conversion

    /// Normalized pan (-1.0 full left ... 1.0 full right) to WING's -100...100 int range.
    /// `nonisolated` because this is a pure function that touches no actor-isolated state,
    /// and tests need to call it synchronously without hopping onto the main actor.
    nonisolated static func wingPanValue(from normalized: Double) -> Int {
        let clamped = max(-1.0, min(1.0, normalized))
        return Int((clamped * 100.0).rounded())
    }

    /// Clamp a dB value to WING's fader range. WING accepts dB directly over OSC (no
    /// nonlinear curve/int-table encoding, unlike X32/Yamaha), so this is a pure clamp.
    /// `nonisolated` for the same reason as `wingPanValue(from:)` above.
    nonisolated static func wingLevelDb(from db: Double) -> Double {
        max(-144.0, min(10.0, db))
    }
}

@MainActor
final class WingConsoleServiceRegistry: ObservableObject {
    static let shared = WingConsoleServiceRegistry()

    private var services: [UUID: WingConsoleService] = [:]
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = ExternalDevicesStore.shared.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.syncDevices(devices)
            }
    }

    func service(for device: ExternalDeviceConfig) -> WingConsoleService? {
        guard device.consoleModelIdentifier == AudioConsoleModel.behringerWing.rawValue else { return nil }
        if let existing = services[device.id] {
            existing.updateFromDevice(device)
            return existing
        }

        let service = WingConsoleService(host: device.host, externalDeviceId: device.id)
        services[device.id] = service
        return service
    }

    private func syncDevices(_ devices: [ExternalDeviceConfig]) {
        let wingDevices = devices.filter { $0.consoleModelIdentifier == AudioConsoleModel.behringerWing.rawValue }
        let activeIds = Set(wingDevices.map { $0.id })

        for device in wingDevices {
            _ = service(for: device)
        }

        let toRemove = services.keys.filter { !activeIds.contains($0) }
        for id in toRemove {
            services[id]?.stop()
            services[id] = nil
        }
    }
}
