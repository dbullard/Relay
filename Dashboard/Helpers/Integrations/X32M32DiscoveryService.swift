//
//  X32M32DiscoveryService.swift
//  Relay
//
//  Created by Relay on 4/2026.
//

import Foundation
import Combine

#if canImport(Darwin)
import Darwin
#endif

struct X32M32DiscoveredConsole: Identifiable, Hashable {
    let id: UUID
    let ipAddress: String
    let name: String
    let model: String?
    let consoleModelIdentifier: String?

    init(ipAddress: String, name: String, model: String?, consoleModelIdentifier: String?) {
        self.id = UUID()
        self.ipAddress = ipAddress
        self.name = name
        self.model = model
        self.consoleModelIdentifier = consoleModelIdentifier
    }
}

@MainActor
final class X32M32DiscoveryService: ObservableObject {
    @Published private(set) var devices: [X32M32DiscoveredConsole] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var didActivity: Bool = false
    var debugLoggingEnabled: Bool = false

    private let port: UInt16 = 10023
    private let socketQueue = DispatchQueue(label: "X32M32Discovery.socket", qos: .utility)

    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var devicesByIP: [String: X32M32DiscoveredConsole] = [:]
    private let diagnosticsMinInterval: TimeInterval = 60
    private var probeCount: Int = 0
    /// `readPackets()` runs synchronously on `socketQueue` even though this class is
    /// `@MainActor` — the DispatchSource event handler is invoked directly by libdispatch
    /// and never actually hops onto the main actor's executor. Plain `Int` fields touched
    /// there raced against `stopScan()` reading them on the main actor; this box
    /// serializes access instead. `probeCount` stays a plain field since `probeSubnets()`
    /// genuinely runs on the main actor (see `startScan()`'s `Task { @MainActor in }`).
    private nonisolated(unsafe) let counters = DiscoveryScanCounters()

    private func logDiagnosticError(_ message: String, keySuffix: String) {
        RelayDiagnosticsStore.shared.recordThrottledError(message, tag: "X32/M32", key: "x32m32_\(keySuffix)", minInterval: diagnosticsMinInterval)
    }

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
                print("[X32M32Discovery] Failed to open socket")
            }
            #endif
            logDiagnosticError("Failed to open UDP socket for discovery", keySuffix: "socket_open_failed")
            return
        }

        devices.removeAll()
        devicesByIP.removeAll()
        isRunning = true
        probeCount = 0
        counters.reset()

        #if DEBUG
        if debugLoggingEnabled {
            print("[X32M32Discovery] Started scan on UDP \(port)")
        }
        #endif

        socketQueue.async {
            Task { @MainActor [weak self] in
                self?.probeSubnets()
            }
        }
    }

    func stopScan() {
        // The socket is closed exclusively by the read source's cancel handler (on
        // socketQueue, capturing the exact fd it owns) — never here. Closing it directly
        // from this (main-actor) call site would race a concurrently-executing
        // readPackets() invocation on socketQueue.
        readSource?.cancel()
        readSource = nil

        isRunning = false
        RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
            "x32 scan probes=\(probeCount) replies=\(counters.value("replyPacket")) identified=\(counters.value("identifiedDevice"))",
            key: "network_scan_x32_summary",
            minInterval: 30
        )
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

    private func probeSubnets() {
        #if canImport(Darwin)
        let subnets = candidateIPv4Subnets()
        let targets = candidateIPv4Targets(from: subnets)
        guard !subnets.isEmpty || !targets.isEmpty else { return }

        let probe = OSCCodec.encode(message: OSCMessage(address: "/xinfo"))

        for broadcastIP in broadcastTargets(for: subnets) {
            probeCount += 1
            markActivity()
            sendProbe(probe, to: broadcastIP)
        }

        for ip in targets {
            probeCount += 1
            markActivity()
            sendProbe(probe, to: ip)
        }
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
            counters.increment("replyPacket")
            markActivity()
            let messages = OSCCodec.decode(packet: payload)

            for message in messages {
                guard let discovered = parseX32Info(message: message, sourceIP: ip) else { continue }
                counters.increment("identifiedDevice")
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

    private func parseX32Info(message: OSCMessage, sourceIP: String) -> X32M32DiscoveredConsole? {
        let address = message.address.lowercased()
        let stringArgs = message.args.compactMap { arg -> String? in
            if case let .string(value) = arg { return value }
            return nil
        }

        var model: String?
        var name: String?

        if address == "/xinfo" {
            if stringArgs.count >= 4 {
                let networkName = stringArgs[1].trimmingCharacters(in: .whitespacesAndNewlines)
                model = stringArgs[2].trimmingCharacters(in: .whitespacesAndNewlines)
                name = networkName.isEmpty ? nil : networkName
            }
        } else if address == "/info" {
            if stringArgs.count >= 4 {
                let serverName = stringArgs[1].trimmingCharacters(in: .whitespacesAndNewlines)
                model = stringArgs[2].trimmingCharacters(in: .whitespacesAndNewlines)
                if !serverName.isEmpty, serverName.lowercased() != "osc-server" {
                    name = serverName
                }
            }
        } else {
            return nil
        }

        guard let model, isX32FamilyModel(model) else { return nil }

        let consoleModelIdentifier = consoleModelIdentifier(for: model)
        let displayModel = consoleModelIdentifier.flatMap { AudioConsoleModel.from(identifier: $0)?.displayName } ?? model
        let displayName = name ?? displayModel

        return X32M32DiscoveredConsole(
            ipAddress: sourceIP,
            name: displayName,
            model: displayModel,
            consoleModelIdentifier: consoleModelIdentifier
        )
    }

    private func isX32FamilyModel(_ model: String) -> Bool {
        let upper = model.uppercased()
        return upper.contains("X32") || upper.contains("M32")
    }

    private func consoleModelIdentifier(for model: String) -> String? {
        let upper = model.uppercased()
        if upper.contains("M32") { return AudioConsoleModel.midasM32.rawValue }
        if upper.contains("X32") { return AudioConsoleModel.behringerX32.rawValue }
        return nil
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

    private struct IPv4Subnet: Hashable {
        let network: UInt32
        let netmask: UInt32
        let address: UInt32
    }

    private func candidateIPv4Targets(from subnets: [IPv4Subnet]? = nil) -> [String] {
        let subnets = subnets ?? candidateIPv4Subnets()
        var targets: [String] = []
        var seen = Set<String>()

        for subnet in subnets {
            for ip in candidateHosts(for: subnet) {
                let ipString = ipv4String(from: ip)
                if seen.insert(ipString).inserted {
                    targets.append(ipString)
                }
            }
        }

        #if DEBUG
        if debugLoggingEnabled {
            print("[X32M32Discovery] target count=\(targets.count)")
        }
        #endif

        return targets
    }

    private func broadcastTargets(for subnets: [IPv4Subnet]) -> [String] {
        var targets: [String] = []
        var seen = Set<String>()

        for subnet in subnets {
            let broadcast = subnet.network | ~subnet.netmask
            guard broadcast > subnet.network else { continue }
            let ipString = ipv4String(from: broadcast)
            if seen.insert(ipString).inserted {
                targets.append(ipString)
            }
        }

        if seen.insert("255.255.255.255").inserted {
            targets.append("255.255.255.255")
        }

        #if DEBUG
        if debugLoggingEnabled {
            print("[X32M32Discovery] broadcast targets=\(targets)")
        }
        #endif

        return targets
    }

    private func candidateIPv4Subnets() -> [IPv4Subnet] {
        #if canImport(Darwin)
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var subnets = Set<IPv4Subnet>()
        var ptr = first

        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
               let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
               let mask = ptr.pointee.ifa_netmask, mask.pointee.sa_family == sa_family_t(AF_INET) {

                let addrIn = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                let maskIn = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }

                let ip = UInt32(bigEndian: addrIn.sin_addr.s_addr)
                let netmask = UInt32(bigEndian: maskIn.sin_addr.s_addr)

                if netmask != 0 && netmask != UInt32.max, isPrivateIPv4(ip) {
                    let network = ip & netmask
                    subnets.insert(IPv4Subnet(network: network, netmask: netmask, address: ip))
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return Array(subnets)
        #else
        return []
        #endif
    }

    private func candidateHosts(for subnet: IPv4Subnet) -> [UInt32] {
        let hostCount = hostCountFor(subnet: subnet)
        let maxHosts = 512

        if hostCount <= 0 { return [] }

        let (start, end): (UInt32, UInt32)

        if hostCount <= maxHosts {
            start = subnet.network + 1
            end = subnet.network + UInt32(hostCount)
        } else {
            // For very large subnets (e.g. /16 or /8), probe only the /24 that contains the interface address.
            let base = subnet.address & 0xFFFFFF00
            start = base + 1
            end = base + 254
        }

        if end < start { return [] }

        return (start...end).map { $0 }
    }

    private func hostCountFor(subnet: IPv4Subnet) -> Int {
        let broadcast = subnet.network | ~subnet.netmask
        if broadcast <= subnet.network { return 0 }
        let count = broadcast - subnet.network - 1
        return Int(count)
    }

    private func ipv4String(from value: UInt32) -> String {
        var addr = in_addr(s_addr: value.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        _ = inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }

    private func isPrivateIPv4(_ value: UInt32) -> Bool {
        if (value & 0xFF000000) == 0x0A000000 { return true }
        if (value & 0xFFF00000) == 0xAC100000 { return true }
        if (value & 0xFFFF0000) == 0xC0A80000 { return true }
        if (value & 0xFFFF0000) == 0xA9FE0000 { return true } // 169.254.0.0/16 link-local
        return false
    }

}
