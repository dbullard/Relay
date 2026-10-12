//
//  QuDiscoveryService.swift
//  Relay
//
//  Created by Relay on 4/2026.
//

import Foundation
import Combine
import Network

#if canImport(Darwin)
import Darwin
#endif

struct QuDiscoveredConsole: Identifiable, Hashable {
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

final class QuDiscoveryService: ObservableObject {
    @Published private(set) var devices: [QuDiscoveredConsole] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var didActivity: Bool = false
    var debugLoggingEnabled: Bool = false
    var preferredTargetIP: String? = nil

    private let port: UInt16 = 51325
    private let queue = DispatchQueue(label: "QuDiscovery.queue", qos: .utility, attributes: .concurrent)
    private let stateQueue = DispatchQueue(label: "QuDiscovery.state")
    private let maxConcurrentProbes = 8
    private let probeTimeout: TimeInterval = 2.0
    private let responseTimeout: TimeInterval = 5.0
    private let probeThrottle: TimeInterval = 0.005
    private let diagnosticsMinInterval: TimeInterval = 60
    private let progressHeartbeatInterval: TimeInterval = 1.0

    private var devicesByIP: [String: QuDiscoveredConsole] = [:]
    private var activeConnections: [String: NWConnection] = [:]
    private var timeoutWorkItems: [String: DispatchWorkItem] = [:]
    private var isCancelled: Bool = false
    private var progressHeartbeatWorkItem: DispatchWorkItem?
    private var outstandingProbeCount: Int = 0
    private var didScheduleAllTargets: Bool = false
    /// Diagnostic counters are incremented from `NWConnection` callbacks that can run
    /// concurrently on `queue` (up to `maxConcurrentProbes` at once) and are read back
    /// from `stopScan()`. Plain `Int` fields raced under concurrent probing; this box
    /// serializes access instead.
    private let counters = DiscoveryScanCounters()

    private var isTargetedScan: Bool {
        guard let override = preferredTargetIP?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !override.isEmpty
    }

    private func logDiagnosticError(_ message: String, keySuffix: String) {
        Task { @MainActor in
            RelayDiagnosticsStore.shared.recordThrottledError(message, tag: "Qu", key: "qu_\(keySuffix)", minInterval: diagnosticsMinInterval)
        }
    }

    private func logProbeFailureIfNeeded(_ message: String, keySuffix: String) {
        guard isTargetedScan else {
            log(message)
            return
        }
        logDiagnosticError(message, keySuffix: keySuffix)
    }

    func startScan() {
        guard !isRunning else { return }
        devices.removeAll()
        devicesByIP.removeAll()
        isCancelled = false
        isRunning = true
        counters.reset()
        stateQueue.sync {
            outstandingProbeCount = 0
            didScheduleAllTargets = false
        }

        log("Started scan on TCP \(port)")
        startProgressHeartbeat()

        queue.async { [weak self] in
            self?.probeSubnets()
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        if debugLoggingEnabled {
            print("[QuDiscovery] \(message)")
        }
        #endif
    }

    private func markActivity() {
        DispatchQueue.main.async { [weak self] in
            self?.didActivity = true
            self?.didActivity = false
        }
    }

    func stopScan() {
        isCancelled = true
        log("Stopping scan")
        progressHeartbeatWorkItem?.cancel()
        progressHeartbeatWorkItem = nil

        let workItems = stateQueue.sync { timeoutWorkItems }
        for (_, workItem) in workItems {
            workItem.cancel()
        }
        stateQueue.sync { timeoutWorkItems.removeAll() }

        let connections = stateQueue.sync { activeConnections }
        for (_, connection) in connections {
            connection.cancel()
        }
        stateQueue.sync { activeConnections.removeAll() }

        isRunning = false
        let probes = counters.value("probeAttempt")
        let connected = counters.value("connectedHost")
        let identified = counters.value("identifiedHost")
        let timeouts = counters.value("timeout")
        let connectFailures = counters.value("connectFailure")
        let receiveErrors = counters.value("receiveError")
        Task { @MainActor in
            RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
                "qu scan probes=\(probes) connected=\(connected) identified=\(identified) timeouts=\(timeouts) connect_failures=\(connectFailures) receive_errors=\(receiveErrors)",
                key: "network_scan_qu_summary",
                minInterval: 30
            )
        }
    }

    private func probeSubnets() {
        let targets = candidateIPv4Targets()
        if targets.isEmpty {
            log("No private subnet targets found")
            logDiagnosticError("No private subnet targets found for discovery", keySuffix: "no_targets")
            return
        }
        log("Probing \(targets.count) targets")
        Task { @MainActor in
            RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
                "qu targets=\(targets.count) preferred_target=\(preferredTargetIP?.isEmpty == false ? preferredTargetIP! : "none")",
                key: "network_scan_qu_targets",
                minInterval: 15
            )
        }

        let semaphore = DispatchSemaphore(value: maxConcurrentProbes)

        for (index, ip) in targets.enumerated() {
            if isCancelled { break }
            semaphore.wait()
            stateQueue.sync {
                outstandingProbeCount += 1
            }
            let delay = probeThrottle * Double(index)
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                // self can be nil if the owning service was deallocated (e.g. the
                // wizard step was popped) while this probe was still staggered/pending.
                // The signal() must still fire to balance this probe's semaphore.wait()
                // above — skipping it leaves the semaphore under-signaled and crashes
                // libdispatch when its last reference is released.
                guard let self else {
                    semaphore.signal()
                    return
                }
                self.probeHost(ip) {
                    semaphore.signal()
                }
            }
        }
        stateQueue.sync {
            didScheduleAllTargets = true
        }
        checkForScanCompletion()
    }

    private func probeHost(_ ip: String, completion: @escaping () -> Void) {
        guard !isCancelled else {
            completion()
            return
        }

        let completionGate = ProbeCompletionGate { [weak self] in
            completion()
            self?.stateQueue.sync {
                self?.outstandingProbeCount = max(0, (self?.outstandingProbeCount ?? 1) - 1)
            }
            self?.checkForScanCompletion()
        }
        let finish = {
            completionGate.fire()
        }

        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(rawValue: self.port) ?? 0
        let connection = NWConnection(host: host, port: port, using: .tcp)
        counters.increment("probeAttempt")
        stateQueue.sync {
            activeConnections[ip] = connection
        }
        log("Probing \(ip):\(self.port)")
        markActivity()

        let timeoutWorkItem = DispatchWorkItem { [weak self, weak connection] in
            connection?.cancel()
            self?.stateQueue.sync {
                self?.activeConnections.removeValue(forKey: ip)
                self?.timeoutWorkItems.removeValue(forKey: ip)
            }
            self?.counters.increment("timeout")
            self?.markActivity()
            self?.logProbeFailureIfNeeded("Discovery timed out for \(ip):\(self?.port ?? 0)", keySuffix: "timeout_\(ip)")
            finish()
        }
        stateQueue.sync {
            timeoutWorkItems[ip] = timeoutWorkItem
        }
        queue.asyncAfter(deadline: .now() + probeTimeout, execute: timeoutWorkItem)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Only reachable while self is alive: a connection that outlives
                // QuDiscoveryService has already been through stopScan()'s cancel(),
                // and .ready never follows a cancel.
                guard let self else { return }
                self.counters.increment("connectedHost")
                self.markActivity()
                self.log("Connected \(ip):\(self.port)")
                self.rescheduleTimeout(for: ip, seconds: self.responseTimeout, completion: completion)
                let request = self.buildIdentityRequest()
                self.log("Sending Qu identity request to \(ip)")
                connection.send(content: request, completion: .contentProcessed({ _ in }))
                self.receiveIdentity(on: connection, ip: ip, completion: finish)
            case .failed(let error):
                // finish() must run even if self has been deallocated (e.g. the owning
                // view was torn down right after stopScan()) — it's what balances this
                // probe's semaphore.wait() in probeSubnets() with a signal(). Skipping it
                // leaves the semaphore under-signaled and crashes when its last
                // reference is released ("Semaphore object deallocated while in use").
                if let self {
                    self.counters.increment("connectFailure")
                    self.markActivity()
                    self.log("Failed \(ip):\(self.port) error=\(error)")
                    self.logProbeFailureIfNeeded("Connection failed to \(ip):\(self.port) — \(error.localizedDescription)", keySuffix: "connect_failed_\(ip)")
                    self.cleanupConnection(for: ip)
                }
                finish()
            case .cancelled:
                // Same reasoning as .failed above — must fire unconditionally.
                if let self {
                    self.markActivity()
                    self.cleanupConnection(for: ip)
                }
                finish()
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveIdentity(on connection: NWConnection, ip: String, completion: @escaping () -> Void) {
        var buffer = Data()
        var didLogPreview = false
        var receivedAnyData = false

        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, _, error in
                guard let self else { return }

                if let data, !data.isEmpty {
                    receivedAnyData = true
                    buffer.append(data)
                    if !didLogPreview {
                        self.log("RX preview from \(ip): \(self.hexPreview(buffer))")
                        didLogPreview = true
                    }
                    self.markActivity()
                    if let discovered = self.parseIdentity(from: buffer, ipAddress: ip) {
                        self.counters.increment("identifiedHost")
                        self.markActivity()
                        self.log("Identified \(ip) as \(discovered.name)")
                        Task { @MainActor [weak self] in
                            self?.addDiscovered(discovered)
                        }
                        self.cleanupConnection(for: ip)
                        completion()
                        return
                    }
                }

                if let error {
                    if let fallback = self.parseFallbackIdentity(from: buffer, ipAddress: ip, receivedAnyData: receivedAnyData) {
                        self.counters.increment("fallbackIdentification")
                        self.markActivity()
                        self.log("Fallback-identified \(ip) as \(fallback.name)")
                        Task { @MainActor [weak self] in
                            self?.addDiscovered(fallback)
                        }
                        self.cleanupConnection(for: ip)
                        completion()
                        return
                    }
                    self.counters.increment("receiveError")
                    self.log("Receive error from \(ip): \(error)")
                    self.logProbeFailureIfNeeded("Receive error from \(ip):\(self.port) — \(error.localizedDescription)", keySuffix: "receive_error_\(ip)")
                    self.cleanupConnection(for: ip)
                    completion()
                    return
                }

                receiveNext()
            }
        }

        receiveNext()
    }

    private func hexPreview(_ data: Data, max: Int = 32) -> String {
        let slice = data.prefix(max)
        return slice.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    @MainActor
    private func addDiscovered(_ discovered: QuDiscoveredConsole) {
        if let existing = devicesByIP[discovered.ipAddress] {
            if existing != discovered {
                devicesByIP[discovered.ipAddress] = discovered
                if let idx = devices.firstIndex(where: { $0.ipAddress == discovered.ipAddress }) {
                    devices[idx] = discovered
                }
            }
        } else {
            devicesByIP[discovered.ipAddress] = discovered
            devices.append(discovered)
        }
    }

    private func cleanupConnection(for ip: String) {
        let workItem = stateQueue.sync { timeoutWorkItems[ip] }
        workItem?.cancel()
        _ = stateQueue.sync {
            timeoutWorkItems.removeValue(forKey: ip)
        }
        let connection = stateQueue.sync { activeConnections[ip] }
        connection?.cancel()
        _ = stateQueue.sync {
            activeConnections.removeValue(forKey: ip)
        }
    }

    private func rescheduleTimeout(for ip: String, seconds: TimeInterval, completion: @escaping () -> Void) {
        stateQueue.sync {
            if let existing = timeoutWorkItems[ip] {
                existing.cancel()
            }

            let workItem = DispatchWorkItem { [weak self] in
                self?.cleanupConnection(for: ip)
                completion()
            }
            timeoutWorkItems[ip] = workItem
            queue.asyncAfter(deadline: .now() + seconds, execute: workItem)
        }
    }

    private func startProgressHeartbeat() {
        progressHeartbeatWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            let shouldContinue = self.stateQueue.sync {
                !(self.didScheduleAllTargets && self.outstandingProbeCount == 0)
            }
            guard shouldContinue else { return }
            self.markActivity()
            self.startProgressHeartbeat()
        }
        progressHeartbeatWorkItem = workItem
        queue.asyncAfter(deadline: .now() + progressHeartbeatInterval, execute: workItem)
    }

    private func checkForScanCompletion() {
        let isComplete = stateQueue.sync {
            didScheduleAllTargets && outstandingProbeCount == 0
        }
        guard isComplete else { return }
        progressHeartbeatWorkItem?.cancel()
        progressHeartbeatWorkItem = nil
        let probes = counters.value("probeAttempt")
        let connected = counters.value("connectedHost")
        let identified = counters.value("identifiedHost")
        Task { @MainActor in
            RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
                "qu complete probes=\(probes) connected=\(connected) identified=\(identified) outstanding=0",
                key: "network_scan_qu_complete",
                minInterval: 15
            )
        }
    }

    private func buildIdentityRequest() -> Data {
        // Qu SysEx request: Query All System State (iPad flag = 0)
        let bytes: [UInt8] = [
            0xF0, 0x00, 0x00, 0x1A, 0x50, 0x11, 0x01, 0x00,
            0x7F, 0x10, 0x00, 0xF7
        ]
        return Data(bytes)
    }

    private func parseIdentity(from data: Data, ipAddress: String) -> QuDiscoveredConsole? {
        let sysexMessages = extractSysExMessages(from: data)
        for message in sysexMessages {
            if let identity = parseSysExIdentity(message, ipAddress: ipAddress) {
                return identity
            }
        }
        return nil
    }

    private func parseFallbackIdentity(from data: Data, ipAddress: String, receivedAnyData: Bool) -> QuDiscoveredConsole? {
        let bytes = [UInt8](data)
        let quHeader: [UInt8] = [0xF0, 0x00, 0x00, 0x1A, 0x50, 0x11, 0x01, 0x00]
        let hasQuHeader = bytes.count >= quHeader.count && bytes.indices.contains { start in
            let remaining = bytes.count - start
            guard remaining >= quHeader.count else { return false }
            return Array(bytes[start..<(start + quHeader.count)]) == quHeader
        }

        guard receivedAnyData || hasQuHeader else { return nil }
        return QuDiscoveredConsole(
            ipAddress: ipAddress,
            name: "Qu Console",
            model: nil,
            consoleModelIdentifier: AudioConsoleModel.allenHeathQu.rawValue
        )
    }

    private func parseSysExIdentity(_ message: Data, ipAddress: String) -> QuDiscoveredConsole? {
        let bytes = [UInt8](message)
        guard bytes.count >= 11 else { return nil }

        let header: [UInt8] = [0xF0, 0x00, 0x00, 0x1A, 0x50, 0x11, 0x01, 0x00]
        guard bytes.starts(with: header) else { return nil }

        let metadataEnd = min(bytes.count, 16)
        let metadataSlice = bytes[9..<metadataEnd]
        let model = metadataSlice.compactMap(modelName(for:)).first
        let displayName = model ?? "Qu Console"
        return QuDiscoveredConsole(
            ipAddress: ipAddress,
            name: displayName,
            model: model,
            consoleModelIdentifier: AudioConsoleModel.allenHeathQu.rawValue
        )
    }

    private func modelName(for boxId: UInt8) -> String? {
        switch boxId {
        case 0x01: return "Qu-16"
        case 0x02: return "Qu-24"
        case 0x03: return "Qu-32"
        case 0x04: return "Qu-Pac"
        case 0x05: return "Qu-SB"
        default: return nil
        }
    }

    private func extractSysExMessages(from data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var messages: [Data] = []
        var startIndex: Int? = nil

        for (idx, byte) in bytes.enumerated() {
            if byte == 0xF0 {
                startIndex = idx
            } else if byte == 0xF7, let start = startIndex, start <= idx {
                let msg = Data(bytes[start...idx])
                messages.append(msg)
                startIndex = nil
            }
        }

        return messages
    }

    private struct IPv4Subnet: Hashable {
        let network: UInt32
        let netmask: UInt32
        let address: UInt32
    }

    private func candidateIPv4Targets() -> [String] {
        if let override = preferredTargetIP?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            log("Using preferred target IP: \(override)")
            return [override]
        }

        guard let currentIP = currentIPv4(preferWiFi: true),
              let subnet = localSubnetAroundCurrentIP(currentIP) else {
            log("No current IPv4 subnet available")
            return []
        }

        let targets = candidateHosts(for: subnet).map { ipv4String(from: $0) }
        log("target count=\(targets.count) current_ip=\(currentIP) strategy=current_interface_/24")
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
                if netmask != 0, netmask != UInt32.max, isPrivateIPv4(ip) {
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

    private func localSubnetAroundCurrentIP(_ ipString: String) -> IPv4Subnet? {
        let parts = ipString.split(separator: ".")
        guard parts.count == 4,
              let a = UInt32(parts[0]),
              let b = UInt32(parts[1]),
              let c = UInt32(parts[2]),
              let d = UInt32(parts[3]) else { return nil }
        let ip = (a << 24) | (b << 16) | (c << 8) | d
        let netmask: UInt32 = 0xFFFFFF00
        let network = ip & netmask
        return IPv4Subnet(network: network, netmask: netmask, address: ip)
    }

    private func currentIPv4(preferWiFi: Bool) -> String? {
        #if canImport(Darwin)
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var wifiCandidate: String?
        var firstPrivate: String?

        var ptr = first
        while true {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET else {
                if let next = ifa.ifa_next { ptr = next } else { break }
                continue
            }

            guard let cName = ifa.ifa_name else {
                if let next = ifa.ifa_next { ptr = next } else { break }
                continue
            }
            let name = String(cString: cName)

            var addrIn = unsafeBitCast(addr.pointee, to: sockaddr_in.self)
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let addrPtr = withUnsafePointer(to: &addrIn.sin_addr) {
                $0.withMemoryRebound(to: in_addr.self, capacity: 1) { $0 }
            }
            inet_ntop(AF_INET, addrPtr, &buf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: buf)

            if isPrivateIPv4String(ip) {
                if preferWiFi, (name == "en0" || name == "en1" || name == "en8") {
                    wifiCandidate = ip
                }
                if firstPrivate == nil {
                    firstPrivate = ip
                }
            }

            if let next = ifa.ifa_next { ptr = next } else { break }
        }

        return wifiCandidate ?? firstPrivate
        #else
        return nil
        #endif
    }

    private func candidateHosts(for subnet: IPv4Subnet) -> [UInt32] {
        let hostCount = hostCountFor(subnet: subnet)
        let maxHosts = 254

        if hostCount <= 0 { return [] }

        let (start, end): (UInt32, UInt32)

        if hostCount <= maxHosts {
            start = subnet.network + 1
            end = subnet.network + UInt32(hostCount)
        } else {
            // For /23 and larger networks, scan only the /24 that contains the local interface first.
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

    private func isPrivateIPv4String(_ ip: String) -> Bool {
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let comps = ip.split(separator: ".")
            if comps.count >= 2, let second = Int(comps[1]), (16...31).contains(second) {
                return true
            }
        }
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("169.254.") { return true }
        return false
    }
}

private final class ProbeCompletionGate {
    private let lock = NSLock()
    private var hasFired = false
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func fire() {
        lock.lock()
        defer { lock.unlock() }
        guard !hasFired else { return }
        hasFired = true
        action()
    }
}
