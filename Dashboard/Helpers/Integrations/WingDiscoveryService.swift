//
//  WingDiscoveryService.swift
//  Relay
//
//  UDP broadcast discovery for Behringer WING consoles.
//  Probe: OSC "/?" (no args) broadcast to 255.255.255.255:2223.
//  Reply: one string arg, comma-separated "<?>,ip,name,model,serial,version"
//  (verified against the production bitfocus/companion-module-behringer-wing
//  device-detector source). Mirrors X32M32DiscoveryService's socket handling.
//

import Foundation
import Combine

#if canImport(Darwin)
import Darwin
#endif

struct WingDiscoveredConsole: Identifiable, Hashable {
    let id: UUID
    let ipAddress: String
    let name: String
    let model: String?

    nonisolated init(ipAddress: String, name: String, model: String?) {
        self.id = UUID()
        self.ipAddress = ipAddress
        self.name = name
        self.model = model
    }
}

@MainActor
final class WingDiscoveryService: ObservableObject {
    @Published private(set) var devices: [WingDiscoveredConsole] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var didActivity: Bool = false
    var debugLoggingEnabled: Bool = false

    private let port: UInt16 = 2223
    private let socketQueue = DispatchQueue(label: "WingDiscovery.socket", qos: .utility)

    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var probeTimer: DispatchSourceTimer?
    private var devicesByIP: [String: WingDiscoveredConsole] = [:]

    private func markActivity() {
        DispatchQueue.main.async { [weak self] in
            self?.didActivity = true
            self?.didActivity = false
        }
    }

    func startScan() {
        guard !isRunning else { return }
        guard openSocket() else {
            #if DEBUG
            if debugLoggingEnabled {
                print("[WingDiscovery] Failed to open socket")
            }
            #endif
            return
        }

        devices.removeAll()
        devicesByIP.removeAll()
        isRunning = true

        #if DEBUG
        if debugLoggingEnabled {
            print("[WingDiscovery] Started scan on UDP \(port)")
        }
        #endif

        socketQueue.async {
            Task { @MainActor [weak self] in
                self?.sendProbeBroadcast()
            }
        }

        let timer = DispatchSource.makeTimerSource(queue: socketQueue)
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
        timer.setEventHandler {
            Task { @MainActor [weak self] in
                self?.sendProbeBroadcast()
            }
        }
        timer.resume()
        probeTimer = timer
    }

    func stopScan() {
        probeTimer?.cancel()
        probeTimer = nil
        // The socket is closed exclusively by the read source's cancel handler (on
        // socketQueue, capturing the exact fd it owns) — never here. Closing it directly
        // from this (main-actor) call site would race a concurrently-executing
        // readPackets() invocation on socketQueue.
        readSource?.cancel()
        readSource = nil

        isRunning = false
    }

    private func openSocket() -> Bool {
        #if canImport(Darwin)
        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return false }
        NetworkUtils.makeSocketNonBlocking(socketFD)

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(socketFD)
            socketFD = -1
            return false
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: socketQueue)
        let fdToClose = socketFD
        source.setEventHandler { [weak self] in
            self?.readPackets()
        }
        source.setCancelHandler { [weak self] in
            close(fdToClose)
            guard let self else { return }
            if self.socketFD == fdToClose {
                self.socketFD = -1
            }
        }
        readSource = source
        source.resume()
        return true
        #else
        return false
        #endif
    }

    private func sendProbeBroadcast() {
        #if canImport(Darwin)
        let probe = OSCCodec.encode(message: OSCMessage(address: "/?"))
        markActivity()
        sendProbe(probe, to: "255.255.255.255")
        #endif
    }

    private func sendProbe(_ probe: Data, to ip: String) {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr(ip))

        probe.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    _ = sendto(socketFD, base, probe.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func readPackets() {
        #if canImport(Darwin)
        var buffer = [UInt8](repeating: 0, count: 4096)
        var addr = sockaddr_in()
        var addrLen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)

        while true {
            let received = withUnsafeMutablePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    recvfrom(socketFD, &buffer, buffer.count, 0, saPtr, &addrLen)
                }
            }

            if received <= 0 { break }

            let ip = ipString(from: addr)
            let payload = Data(buffer.prefix(received))
            markActivity()
            let messages = OSCCodec.decode(packet: payload)

            for message in messages {
                guard let discovered = WingDiscoveryService.parseWingInfo(message: message, sourceIP: ip) else { continue }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let existing = self.devicesByIP[discovered.ipAddress] {
                        if existing != discovered {
                            self.devicesByIP[discovered.ipAddress] = discovered
                            if let idx = self.devices.firstIndex(where: { $0.ipAddress == discovered.ipAddress }) {
                                self.devices[idx] = discovered
                            }
                        }
                    } else {
                        self.devicesByIP[discovered.ipAddress] = discovered
                        self.devices.append(discovered)
                    }
                }
            }
        }
        #endif
    }

    /// Parses a WING "/?" discovery reply: one string arg, comma-separated
    /// "<?>,ip,name,model,serial,version".
    nonisolated static func parseWingInfo(message: OSCMessage, sourceIP: String) -> WingDiscoveredConsole? {
        guard let first = message.args.first, case let .string(value) = first else { return nil }
        let fields = value.components(separatedBy: ",")
        guard fields.count >= 4 else { return nil }
        let name = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let model = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return WingDiscoveredConsole(ipAddress: sourceIP, name: name, model: model.isEmpty ? nil : model)
    }

    private func ipString(from addr: sockaddr_in) -> String {
        var addr = addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let ipCString = withUnsafePointer(to: &addr.sin_addr) { ptr in
            inet_ntop(AF_INET, ptr, &buffer, socklen_t(INET_ADDRSTRLEN))
        }
        if let ipCString {
            return String(cString: ipCString)
        }
        return ""
    }
}
