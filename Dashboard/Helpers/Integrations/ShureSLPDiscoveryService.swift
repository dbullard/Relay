//
//  ShureSLPDiscoveryService.swift
//  Relay
//
//  Created by Relay on 4/2026.
//

import Foundation
import Combine

#if canImport(Darwin)
import Darwin
#endif

struct ShureSLPDiscoveredDevice: Identifiable, Hashable {
    let id: UUID
    let ipAddress: String
    let model: String?
    let name: String?
    let attributes: [String: String]
    let cid: UUID?
    let sdtHost: String?
    let sdtPort: UInt16?
    let ddlURL: String?

    init(
        ipAddress: String,
        model: String?,
        name: String?,
        attributes: [String: String],
        cid: UUID?,
        sdtHost: String?,
        sdtPort: UInt16?,
        ddlURL: String?
    ) {
        self.id = UUID()
        self.ipAddress = ipAddress
        self.model = model
        self.name = name
        self.attributes = attributes
        self.cid = cid
        self.sdtHost = sdtHost
        self.sdtPort = sdtPort
        self.ddlURL = ddlURL
    }
}

/// Shure SLP-style discovery listener for UDP multicast 239.255.254.253:8427.
///
/// - Joins the multicast group (IGMP via IP_ADD_MEMBERSHIP)
/// - Listens for SLPv2 SrvReg packets
/// - Extracts attribute pairs and exposes discovered devices
///
/// This is a discovery subsystem only (no UI / integration yet).
@MainActor
final class ShureSLPDiscoveryService: ObservableObject {
    @Published private(set) var devices: [ShureSLPDiscoveredDevice] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var didActivity: Bool = false
    var debugLoggingEnabled: Bool = false

    private let multicastGroup = "239.255.254.253"
    private let port: UInt16 = 8427

    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let socketQueue = DispatchQueue(label: "ShureSLPDiscovery.socket")

    private var devicesByIP: [String: ShureSLPDiscoveredDevice] = [:]
    private var idleStopWorkItem: DispatchWorkItem?
    var autoStopOnIdle: Bool = true
    var idleStopSeconds: TimeInterval = 2.0
    /// `readPackets()`/`parseSLPAdvertisement()` run synchronously on `socketQueue`
    /// even though this class is `@MainActor` — the DispatchSource event handler is
    /// invoked directly by libdispatch and never actually hops onto the main actor's
    /// executor. Plain `Int` fields touched there raced against `stop()` reading them
    /// on the main actor; this box serializes access instead. `discoveredDeviceCount`
    /// stays a plain field since it's only ever mutated inside the `DispatchQueue.main.async`
    /// block below, which is genuinely main-actor-safe.
    private nonisolated(unsafe) let counters = DiscoveryScanCounters()
    private var discoveredDeviceCount: Int = 0

    func start(probeData: Data? = nil) {
        guard !isRunning else { return }
        guard openSocket() else {
            #if DEBUG
            if debugLoggingEnabled {
                print("[ShureSLPDiscovery] Failed to open socket")
            }
            #endif
            return
        }

        devices.removeAll()
        devicesByIP.removeAll()
        isRunning = true
        counters.reset()
        discoveredDeviceCount = 0

        #if DEBUG
        if debugLoggingEnabled {
            print("[ShureSLPDiscovery] Started on \(multicastGroup):\(port)")
        }
        #endif

        scheduleIdleStop()

        sendProbe(probeData ?? buildServiceAgentDiscoveryRequest())
    }

    func stop() {
        idleStopWorkItem?.cancel()
        idleStopWorkItem = nil
        // The socket is closed exclusively by the read source's cancel handler (on
        // socketQueue, capturing the exact fd it owns) — never here. Closing it directly
        // from this (main-actor) call site would race a concurrently-executing
        // readPackets() invocation on socketQueue.
        readSource?.cancel()
        readSource = nil

        isRunning = false
        RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
            "shure_slp scan packets=\(counters.value("packet")) srvreg=\(counters.value("srvRegPacket")) discovered=\(discoveredDeviceCount)",
            key: "network_scan_shure_slp_summary",
            minInterval: 30
        )
    }

    private func scheduleIdleStop() {
        guard autoStopOnIdle else { return }
        idleStopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.stop()
        }
        idleStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + idleStopSeconds, execute: workItem)
    }

    private func markActivity() {
        DispatchQueue.main.async { [weak self] in
            self?.didActivity = true
            self?.didActivity = false
        }
    }

    private func openSocket() -> Bool {
        #if canImport(Darwin)
        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return false }
        NetworkUtils.makeSocketNonBlocking(socketFD)

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindResult == 0 else {
            close(socketFD)
            socketFD = -1
            return false
        }

        if !joinMulticastOnAllInterfaces() {
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
            counters.increment("packet")
            markActivity()
            DispatchQueue.main.async { [weak self] in
                self?.scheduleIdleStop()
            }

            #if DEBUG
            if debugLoggingEnabled {
                print("[ShureSLPDiscovery] packet from \(ip) len=\(received)")
            }
            #endif

            if let device = parseSLPAdvertisement(payload: payload, sourceIP: ip) {
                ShureDiscoveryEndpointCache.store(
                    host: device.ipAddress,
                    cid: device.cid,
                    sdtHost: device.sdtHost,
                    sdtPort: device.sdtPort
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.devicesByIP[device.ipAddress] == nil {
                        self.devicesByIP[device.ipAddress] = device
                        self.discoveredDeviceCount += 1
                        self.devices.append(device)
                    } else {
                        self.devicesByIP[device.ipAddress] = device
                        if let idx = self.devices.firstIndex(where: { $0.ipAddress == device.ipAddress }) {
                            self.devices[idx] = device
                        }
                    }
                    // DDL fetch removed; SLP data is sufficient for device naming.
                }
            }
        }
        #endif
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

    /// Parse Shure SLP traffic and extract attribute pairs from either a standard
    /// SAAdvert or the looser vendor packets some units emit on the same port.
    private func parseSLPAdvertisement(payload: Data, sourceIP: String) -> ShureSLPDiscoveredDevice? {
        guard payload.count >= 16 else { return nil }

        let bytes = [UInt8](payload)
        let version = bytes[0]
        let function = bytes[1]
        #if DEBUG
        if debugLoggingEnabled {
            print("[ShureSLPDiscovery] header v=\(version) fn=\(function)")
        }
        #endif
        guard version == 0x02 else { return nil }
        guard function == 0x0B || function == 0x07 || function == 0x03 else { return nil }
        counters.increment("srvRegPacket")

        let attributes: [String: String]
        switch function {
        case 0x0B:
            attributes = parseSAAdvertAttributes(from: payload)
        case 0x03:
            attributes = parseSLPSrvRegAttributes(from: payload)
        default:
            attributes = parseVendorAttributePayload(from: payload)
        }

        var resolvedAttributes = attributes
        if resolvedAttributes.isEmpty {
            let ascii = asciiPayloadString(bytes)
            #if DEBUG
            if debugLoggingEnabled {
                print("[ShureSLPDiscovery] no attributes parsed; ascii=\(ascii)")
            }
            #endif
            resolvedAttributes = parseAttributePairs(from: ascii)
            if resolvedAttributes.isEmpty {
                let segments = ascii.split(separator: ",")
                for segment in segments {
                    if let pair = splitPair(String(segment)) {
                        resolvedAttributes[pair.0] = pair.1
                    }
                }
            }
        }

        let ascii = asciiPayloadString(bytes)
        let discovery = ShureDiscoveryParser.parse(
            attributes: resolvedAttributes,
            asciiFallback: ascii,
            sourceIP: sourceIP
        )
        let model = discovery.fctn ?? resolvedAttributes["acn-fctn"] ?? extractValue(forKey: "acn-fctn", in: ascii)
        let name = discovery.uacn ?? resolvedAttributes["acn-uacn"] ?? extractValue(forKey: "acn-uacn", in: ascii)
        #if DEBUG
        if debugLoggingEnabled {
            print("[ShureSLPDiscovery] extracted model=\(model ?? "nil") name=\(name ?? "nil")")
        }
        #endif

        return ShureSLPDiscoveredDevice(
            ipAddress: sourceIP,
            model: model,
            name: name,
            attributes: resolvedAttributes,
            cid: discovery.cid,
            sdtHost: discovery.sdtHost,
            sdtPort: discovery.sdtPort,
            ddlURL: discovery.ddlURL
        )
    }

    private func asciiPayloadString(_ bytes: [UInt8]) -> String {
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(bytes.count)
        for b in bytes {
            if (b >= 0x20 && b <= 0x7E) || b == 0x0A || b == 0x0D {
                scalars.append(UnicodeScalar(b))
            } else {
                scalars.append(" ")
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func parseAttributePairs(from text: String) -> [String: String] {
        var out: [String: String] = [:]
        var current: String = ""
        var inside = false
        for ch in text {
            if ch == "(" {
                inside = true
                current.removeAll(keepingCapacity: true)
                continue
            }
            if ch == ")" {
                inside = false
                if let (k, v) = splitPair(current) {
                    out[k] = v
                }
                continue
            }
            if inside {
                current.append(ch)
            }
        }
        return out
    }

    private func splitPair(_ text: String) -> (String, String)? {
        let parts = text.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private func extractValue(forKey key: String, in text: String) -> String? {
        guard let range = text.range(of: "\(key)=") else { return nil }
        let start = range.upperBound
        var end = start
        while end < text.endIndex {
            let ch = text[end]
            if ch == "," || ch == ")" {
                break
            }
            end = text.index(after: end)
        }
        let value = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func parseSLPSrvRegAttributes(from payload: Data) -> [String: String] {
        var offset = 0
        func readUInt8() -> UInt8? {
            guard offset + 1 <= payload.count else { return nil }
            defer { offset += 1 }
            return payload[offset]
        }
        func readUInt16() -> UInt16? {
            guard offset + 2 <= payload.count else { return nil }
            let value = UInt16(payload[offset]) << 8 | UInt16(payload[offset + 1])
            offset += 2
            return value
        }
        func readUInt24() -> UInt32? {
            guard offset + 3 <= payload.count else { return nil }
            let value = UInt32(payload[offset]) << 16 | UInt32(payload[offset + 1]) << 8 | UInt32(payload[offset + 2])
            offset += 3
            return value
        }
        func readString(_ length: Int) -> String? {
            guard length >= 0, offset + length <= payload.count else { return nil }
            let data = payload.subdata(in: offset..<(offset + length))
            offset += length
            return String(data: data, encoding: .utf8)
        }

        // Header
        _ = readUInt8() // version
        _ = readUInt8() // function
        _ = readUInt24() // length
        _ = readUInt16() // flags
        _ = readUInt24() // ext offset
        _ = readUInt16() // xid
        guard let langLen = readUInt16(), let _ = readString(Int(langLen)) else { return [:] }

        // SrvReg body
        _ = readUInt8() // reserved
        _ = readUInt16() // lifetime
        guard let urlLen = readUInt16(), let _ = readString(Int(urlLen)) else { return [:] }
        guard let serviceTypeLen = readUInt16(), let _ = readString(Int(serviceTypeLen)) else { return [:] }
        guard let scopeLen = readUInt16(), let _ = readString(Int(scopeLen)) else { return [:] }
        guard let attrLen = readUInt16(), let attrString = readString(Int(attrLen)) else { return [:] }
        _ = readUInt8() // auth blocks

        #if DEBUG
        if debugLoggingEnabled {
            print("[ShureSLPDiscovery] attrString=\(attrString)")
        }
        #endif

        var attributes = parseAttributePairs(from: attrString)
        if attributes.isEmpty {
            // Fallback: parse comma-delimited key=value pairs without parentheses.
            let segments = attrString.split(separator: ",")
            for segment in segments {
                if let pair = splitPair(String(segment)) {
                    attributes[pair.0] = pair.1
                }
            }
        }
        return attributes
    }

    private func parseSAAdvertAttributes(from payload: Data) -> [String: String] {
        var offset = 0
        func readUInt8() -> UInt8? {
            guard offset + 1 <= payload.count else { return nil }
            defer { offset += 1 }
            return payload[offset]
        }
        func readUInt16() -> UInt16? {
            guard offset + 2 <= payload.count else { return nil }
            let value = UInt16(payload[offset]) << 8 | UInt16(payload[offset + 1])
            offset += 2
            return value
        }
        func readUInt24() -> UInt32? {
            guard offset + 3 <= payload.count else { return nil }
            let value = UInt32(payload[offset]) << 16 | UInt32(payload[offset + 1]) << 8 | UInt32(payload[offset + 2])
            offset += 3
            return value
        }
        func readString(_ length: Int) -> String? {
            guard length >= 0, offset + length <= payload.count else { return nil }
            let data = payload.subdata(in: offset..<(offset + length))
            offset += length
            return String(data: data, encoding: .utf8)
        }

        _ = readUInt8() // version
        _ = readUInt8() // function
        _ = readUInt24() // length
        _ = readUInt16() // flags
        _ = readUInt24() // ext offset
        _ = readUInt16() // xid
        guard let langLen = readUInt16(), let _ = readString(Int(langLen)) else { return [:] }
        guard let urlLen = readUInt16(), let _ = readString(Int(urlLen)) else { return [:] }
        guard let scopeLen = readUInt16(), let _ = readString(Int(scopeLen)) else { return [:] }
        guard let attrLen = readUInt16(), let attrString = readString(Int(attrLen)) else { return [:] }
        _ = readUInt8() // auth blocks

        var attributes = parseAttributePairs(from: attrString)
        if attributes.isEmpty {
            let segments = attrString.split(separator: ",")
            for segment in segments {
                if let pair = splitPair(String(segment)) {
                    attributes[pair.0] = pair.1
                }
            }
        }
        return attributes
    }

    private func parseVendorAttributePayload(from payload: Data) -> [String: String] {
        var attributes = parseSLPSrvRegAttributes(from: payload)
        if !attributes.isEmpty {
            return attributes
        }

        let ascii = asciiPayloadString([UInt8](payload))
        attributes = parseAttributePairs(from: ascii)
        if attributes.isEmpty {
            let segments = ascii.split(separator: ",")
            for segment in segments {
                if let pair = splitPair(String(segment)) {
                    attributes[pair.0] = pair.1
                }
            }
        }
        return attributes
    }

    private func sendProbe(_ data: Data) {
        #if canImport(Darwin)
        guard socketFD >= 0 else { return }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr(multicastGroup))

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    _ = sendto(socketFD, base, data.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        #if DEBUG
        if debugLoggingEnabled {
            print("[ShureSLPDiscovery] probe sent len=\(data.count)")
        }
        #endif
        #endif
    }

    private func buildServiceAgentDiscoveryRequest() -> Data {
        let language = "en"
        let serviceType = "service:service-agent"
        let prList = ""
        let scopeList = ""
        let predicate = ""
        let spi = ""

        var body = Data()
        append(lengthPrefixed: prList, to: &body)
        append(lengthPrefixed: serviceType, to: &body)
        append(lengthPrefixed: scopeList, to: &body)
        append(lengthPrefixed: predicate, to: &body)
        append(lengthPrefixed: spi, to: &body)

        let headerLength = 14 + language.utf8.count
        let totalLength = headerLength + body.count
        let xid = UInt16.random(in: 1...UInt16.max)

        var packet = Data()
        packet.append(0x02) // SLPv2
        packet.append(0x01) // SrvRqst
        packet.append(contentsOf: [
            UInt8((totalLength >> 16) & 0xFF),
            UInt8((totalLength >> 8) & 0xFF),
            UInt8(totalLength & 0xFF)
        ])
        packet.append(0x20) // REQUEST MCAST
        packet.append(0x00) // reserved
        packet.append(contentsOf: [0x00, 0x00, 0x00]) // next extension offset
        packet.append(contentsOf: [UInt8((xid >> 8) & 0xFF), UInt8(xid & 0xFF)])
        packet.append(contentsOf: [0x00, UInt8(language.utf8.count)])
        packet.append(language.data(using: .utf8) ?? Data())
        packet.append(body)
        return packet
    }

    private func append(lengthPrefixed string: String, to data: inout Data) {
        let payload = string.data(using: .utf8) ?? Data()
        let length = UInt16(payload.count)
        data.append(contentsOf: [UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
        data.append(payload)
    }

    private func joinMulticastOnAllInterfaces() -> Bool {
        #if canImport(Darwin)
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return false
        }

        defer { freeifaddrs(ifaddr) }

        var joinedAny = false
        var ptr = first
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
               let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) {
                var interfaceAddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }.sin_addr
                var mreq = ip_mreq()
                mreq.imr_multiaddr.s_addr = inet_addr(multicastGroup)
                mreq.imr_interface = interfaceAddr
                let result = setsockopt(socketFD, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout.size(ofValue: mreq)))
                if result == 0 {
                    joinedAny = true
                    #if DEBUG
                    if debugLoggingEnabled {
                        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        let ipCString = inet_ntop(AF_INET, &interfaceAddr, &buf, socklen_t(INET_ADDRSTRLEN))
                        let ipString = ipCString == nil ? "unknown" : String(cString: ipCString!)
                        print("[ShureSLPDiscovery] joined multicast on \(ipString)")
                    }
                    #endif
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return joinedAny
        #else
        return false
        #endif
    }
}
