//
//  VenueConsoleService.swift
//  Relay
//
//  Avid VENUE | S6L OSC integration (software 8.2+). VENUE's OSC is event/trigger-routed —
//  there is no fixed, Avid-published address space like X32/WING — so this service sends
//  raw address+value messages built from per-device address templates the operator
//  configures to match Events they've built in VENUE's own Events editor. See
//  docs/superpowers/specs/2026-07-30-avid-venue-s6l-integration-design.md.
//

import Foundation
import Network
import Combine

@MainActor
final class VenueConsoleService: ObservableObject {
    enum ConnectionStatus: String {
        case disconnected
        case ready
    }

    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected

    private let externalDeviceId: UUID
    private var host: String
    private var port: UInt16
    private var transportMode: VenueOSCTransportMode

    private var oscConnection: NWConnection?
    private var currentHost: String = ""
    private var currentPort: UInt16 = 0
    private var currentTransportMode: VenueOSCTransportMode = .tcp

    init(host: String, port: UInt16, transportMode: VenueOSCTransportMode, externalDeviceId: UUID) {
        self.host = host
        self.port = port
        self.transportMode = transportMode
        self.externalDeviceId = externalDeviceId
    }

    func updateFromDevice(_ device: ExternalDeviceConfig) {
        host = device.host
        port = device.port
        transportMode = device.venueTransportMode ?? .tcp
    }

    /// Sends a raw OSC message built from an operator-configured address template.
    func send(address: String, value: OSCValue) {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return }
        sendOSC(address: trimmedAddress, args: [value])
    }

    func stop() {
        oscConnection?.cancel()
        oscConnection = nil
        connectionStatus = .disconnected
    }

    // MARK: - OSC

    private func sendOSC(address: String, args: [OSCValue]) {
        configureConnectionIfNeeded()
        guard let oscConnection else { return }
        let payload = OSCCodec.encode(message: OSCMessage(address: address, args: args))
        oscConnection.send(content: payload, completion: .contentProcessed { _ in })
    }

    private func configureConnectionIfNeeded() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, port != 0 else { return }

        if oscConnection != nil, trimmedHost == currentHost, port == currentPort, transportMode == currentTransportMode {
            return
        }
        currentHost = trimmedHost
        currentPort = port
        currentTransportMode = transportMode

        oscConnection?.cancel()
        let nwHost = NWEndpoint.Host(trimmedHost)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let params: NWParameters = transportMode == .tcp ? .tcp : .udp
        if transportMode == .udp {
            params.allowFastOpen = true
        }
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

    // MARK: - Address template substitution

    /// Substitutes `{channel}` in a template with the 1-based channel index.
    /// `nonisolated` because this is a pure function that touches no actor-isolated state,
    /// and tests need to call it synchronously without hopping onto the main actor.
    nonisolated static func filledAddress(template: String, channel: Int) -> String {
        template.replacingOccurrences(of: "{channel}", with: String(channel))
    }

    /// Substitutes `{scene}` in a template with the trimmed scene identifier.
    /// `nonisolated` for the same reason as `filledAddress(template:channel:)` above.
    nonisolated static func filledAddress(template: String, scene: String) -> String {
        template.replacingOccurrences(of: "{scene}", with: scene)
    }
}

@MainActor
final class VenueConsoleServiceRegistry: ObservableObject {
    static let shared = VenueConsoleServiceRegistry()

    private var services: [UUID: VenueConsoleService] = [:]
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = ExternalDevicesStore.shared.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.syncDevices(devices)
            }
    }

    func service(for device: ExternalDeviceConfig) -> VenueConsoleService? {
        guard device.consoleModelIdentifier == AudioConsoleModel.avidVenueS6L.rawValue else { return nil }
        if let existing = services[device.id] {
            existing.updateFromDevice(device)
            return existing
        }

        let service = VenueConsoleService(
            host: device.host,
            port: device.port,
            transportMode: device.venueTransportMode ?? .tcp,
            externalDeviceId: device.id
        )
        services[device.id] = service
        return service
    }

    private func syncDevices(_ devices: [ExternalDeviceConfig]) {
        let venueDevices = devices.filter { $0.consoleModelIdentifier == AudioConsoleModel.avidVenueS6L.rawValue }
        let activeIds = Set(venueDevices.map { $0.id })

        for device in venueDevices {
            _ = service(for: device)
        }

        let toRemove = services.keys.filter { !activeIds.contains($0) }
        for id in toRemove {
            services[id]?.stop()
            services[id] = nil
        }
    }
}
