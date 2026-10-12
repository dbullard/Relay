//
//  ShureProtocol.swift
//  Relay
//
//  Created by Relay on 4/2026.
//

import Foundation

struct ShureDiscoveredSdtEndpoint: Hashable {
    let host: String
    let port: UInt16
    let cid: UUID?
    let updatedAt: Date
}

enum ShureDiscoveryEndpointCache {
    private static let lock = NSLock()
    private static var endpointsByHost: [String: ShureDiscoveredSdtEndpoint] = [:]
    private static var endpointsByCID: [UUID: ShureDiscoveredSdtEndpoint] = [:]

    static func store(host: String, cid: UUID?, sdtHost: String?, sdtPort: UInt16?) {
        guard let sdtPort else { return }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedHost = (sdtHost?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? sdtHost! : host)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, !resolvedHost.isEmpty else { return }

        let endpoint = ShureDiscoveredSdtEndpoint(
            host: resolvedHost,
            port: sdtPort,
            cid: cid,
            updatedAt: Date()
        )

        lock.lock()
        endpointsByHost[trimmedHost] = endpoint
        if let cid {
            endpointsByCID[cid] = endpoint
        }
        lock.unlock()
    }

    static func endpoint(host: String, cid: UUID?) -> ShureDiscoveredSdtEndpoint? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        defer { lock.unlock() }
        if let cid, let endpoint = endpointsByCID[cid] {
            return endpoint
        }
        return endpointsByHost[trimmedHost]
    }
}

struct ShureDiscoveryInfo: Hashable {
    let cid: UUID?
    let uacn: String?
    let fctn: String?
    let sdtHost: String?
    let sdtPort: UInt16?
    let ddlURL: String?
    let attributes: [String: String]
}

enum ShureDiscoveryParser {
    static func parse(attributes: [String: String], asciiFallback: String?, sourceIP: String) -> ShureDiscoveryInfo {
        let uacn = cleaned(attributes["acn-uacn"] ?? extractValue(forKey: "acn-uacn", in: asciiFallback))
        let fctn = cleaned(attributes["acn-fctn"] ?? extractValue(forKey: "acn-fctn", in: asciiFallback))
        let cid = parseCID(attributes["cid"] ?? extractValue(forKey: "cid", in: asciiFallback))

        let sdtRaw = attributes["csl-esta.dmp"] ?? extractValue(forKey: "csl-esta.dmp", in: asciiFallback)
        let (sdtHost, sdtPort) = parseSdtEndpoint(from: sdtRaw, fallbackHost: sourceIP)

        let ddlRaw = attributes["device-description"] ?? extractValue(forKey: "device-description", in: asciiFallback)
        let ddlURL = parseDdlURL(from: ddlRaw)

        return ShureDiscoveryInfo(
            cid: cid,
            uacn: uacn,
            fctn: fctn,
            sdtHost: sdtHost,
            sdtPort: sdtPort,
            ddlURL: ddlURL,
            attributes: attributes
        )
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseCID(_ value: String?) -> UUID? {
        guard let value = cleaned(value) else { return nil }
        let stripped = value.trimmingCharacters(in: CharacterSet(charactersIn: "{}()"))
        return UUID(uuidString: stripped)
    }

    private static func parseSdtEndpoint(from value: String?, fallbackHost: String) -> (String?, UInt16?) {
        guard let value = cleaned(value) else { return (nil, nil) }
        guard let range = value.range(of: "esta.sdt/") else { return (nil, nil) }
        let tail = value[range.upperBound...]
        let stopChars = CharacterSet(charactersIn: ";, )\n\r\t")
        let endpoint = tail.prefix { ch in
            guard let scalar = ch.unicodeScalars.first else { return false }
            return !stopChars.contains(scalar)
        }
        let parts = endpoint.split(separator: ":")
        if parts.count >= 2, let port = UInt16(parts[1]) {
            let host = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (host.isEmpty ? fallbackHost : host, port)
        }
        return (fallbackHost, nil)
    }

    private static func parseDdlURL(from value: String?) -> String? {
        guard let value = cleaned(value) else { return nil }
        if let range = value.range(of: "tftp://") {
            return String(value[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func extractValue(forKey key: String, in text: String?) -> String? {
        guard let text, let range = text.range(of: "\(key)=") else { return nil }
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
}

struct ShureSessionContext: Hashable {
    let deviceCID: UUID
    let sessionHost: String
    let sessionPort: UInt16
    let senderCID: UUID
    var sequence: UInt32
    var transaction: UInt32
}

struct ShureSessionPacket {
    let rootVector: UInt32
    let senderCID: UUID
    let framingVector: UInt8
    let framingTargetCID: UUID?
    let payload: Data
}

enum ShureSessionFramer {
    private static let packetId = "ASC-E1.17"
    private static let preambleSize: UInt16 = 0x0010

    static func frame(packet: ShureSessionPacket) -> Data {
        var data = Data()
        data.append(contentsOf: [UInt8(preambleSize >> 8), UInt8(preambleSize & 0xFF)])
        data.append(contentsOf: [0x00, 0x00]) // postamble size
        data.append(packetId.data(using: .ascii) ?? Data())
        data.append(contentsOf: [0x00, 0x00, 0x00])

        let framingPdu = buildFramingPdu(
            framingVector: packet.framingVector,
            targetCID: packet.framingTargetCID,
            payload: packet.payload
        )
        let rootPdu = buildRootPdu(
            vector: packet.rootVector,
            senderCID: packet.senderCID,
            payload: framingPdu
        )
        data.append(rootPdu)
        return data
    }

    struct ParsedPacket: Hashable {
        let rootVector: UInt32
        let senderCID: UUID
        let framingVector: UInt8
        let framingTargetCID: UUID?
        let payload: Data
    }

    static func parse(_ data: Data) -> ParsedPacket? {
        guard data.count >= 16 + 2 + 4 + 16 else { return nil }
        let bytes = [UInt8](data)
        guard data.count >= Int(preambleSize) else { return nil }
        let headerSlice = bytes[4..<14]
        let headerBytes = headerSlice.prefix { $0 != 0x00 }
        let header = String(bytes: headerBytes, encoding: .ascii)
        guard header == packetId else { return nil }

        let offset = 16
        let rootFlagsLen = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        let rootLen = Int(rootFlagsLen & 0x0FFF)
        guard rootLen >= 2 + 4 + 16, offset + rootLen <= bytes.count else { return nil }
        let rootVector = UInt32(bytes[offset + 2]) << 24 | UInt32(bytes[offset + 3]) << 16 | UInt32(bytes[offset + 4]) << 8 | UInt32(bytes[offset + 5])
        let senderCID = uuidFrom(bytes: bytes, offset: offset + 6)

        let framingOffset = offset + 22
        let framingFlagsLen = UInt16(bytes[framingOffset]) << 8 | UInt16(bytes[framingOffset + 1])
        let framingLen = Int(framingFlagsLen & 0x0FFF)
        guard framingLen >= 3, framingOffset + framingLen <= bytes.count else { return nil }
        let framingVector = bytes[framingOffset + 2]

        var framingTargetCID: UUID? = nil
        var payloadStart = framingOffset + 3
        let hasTargetCID = framingLen >= 19 && framingVector != 0x02 && framingVector != 0x01
        if hasTargetCID {
            framingTargetCID = uuidFrom(bytes: bytes, offset: framingOffset + 3)
            payloadStart = framingOffset + 19
        }

        let payloadEnd = framingOffset + framingLen
        let payload = Data(bytes[payloadStart..<payloadEnd])

        return ParsedPacket(
            rootVector: rootVector,
            senderCID: senderCID,
            framingVector: framingVector,
            framingTargetCID: framingTargetCID,
            payload: payload
        )
    }

    private static func buildRootPdu(vector: UInt32, senderCID: UUID, payload: Data) -> Data {
        var body = Data()
        body.append(contentsOf: [UInt8((vector >> 24) & 0xFF), UInt8((vector >> 16) & 0xFF), UInt8((vector >> 8) & 0xFF), UInt8(vector & 0xFF)])
        body.append(contentsOf: senderCID.uuidBytes)
        body.append(payload)
        let flagsLen = pduFlagsLength(body.count + 2)
        var data = Data()
        data.append(contentsOf: [UInt8(flagsLen >> 8), UInt8(flagsLen & 0xFF)])
        data.append(body)
        return data
    }

    private static func buildFramingPdu(framingVector: UInt8, targetCID: UUID?, payload: Data) -> Data {
        var body = Data()
        body.append(framingVector)
        if let targetCID {
            body.append(contentsOf: targetCID.uuidBytes)
        }
        body.append(payload)
        let flagsLen = pduFlagsLength(body.count + 2)
        var data = Data()
        data.append(contentsOf: [UInt8(flagsLen >> 8), UInt8(flagsLen & 0xFF)])
        data.append(body)
        return data
    }

    private static func pduFlagsLength(_ length: Int) -> UInt16 {
        let clamped = max(0, min(length, 0x0FFF))
        return UInt16(0x7000 | clamped)
    }

    private static func uuidFrom(bytes: [UInt8], offset: Int) -> UUID {
        var buffer: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &buffer) { raw in
            raw.copyBytes(from: bytes[offset..<(offset + 16)])
        }
        return UUID(uuid: buffer)
    }
}

enum ShurePropertyRequestBuilder {
    static func sessionInit(context: inout ShureSessionContext, sessionSelector: UInt16) -> Data {
        context.sequence &+= 1
        context.transaction &+= 1
        let payload = Data([
            0x00, 0x20,
            0x00, 0x01,
            UInt8((context.transaction >> 24) & 0xFF),
            UInt8((context.transaction >> 16) & 0xFF),
            UInt8((context.transaction >> 8) & 0xFF),
            UInt8(context.transaction & 0xFF),
            UInt8((sessionSelector >> 8) & 0xFF),
            UInt8(sessionSelector & 0xFF)
        ])
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: context.senderCID,
                framingVector: 0x06,
                framingTargetCID: context.deviceCID,
                payload: payload
            )
        )
    }

    static func subscribe(
        context: inout ShureSessionContext,
        sessionSelector: UInt16,
        subscribeSelector: UInt16,
        channelCount: UInt16
    ) -> Data {
        context.transaction &+= 1
        var payload = Data()
        payload.append(contentsOf: [0x00, 0x01])
        payload.append(contentsOf: [UInt8((sessionSelector >> 8) & 0xFF), UInt8(sessionSelector & 0xFF)])
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        payload.append(contentsOf: [UInt8((subscribeSelector >> 8) & 0xFF), UInt8(subscribeSelector & 0xFF)])
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: [UInt8((subscribeSelector >> 8) & 0xFF), UInt8(subscribeSelector & 0xFF)])
        payload.append(contentsOf: [0x00, 0x05, 0x00, 0x00])
        payload.append(contentsOf: [UInt8((channelCount >> 8) & 0xFF), UInt8(channelCount & 0xFF)])
        payload.append(contentsOf: [0x00, 0x32, 0x00, 0x14, 0xFF])
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: context.senderCID,
                framingVector: 0x04,
                framingTargetCID: context.deviceCID,
                payload: payload
            )
        )
    }

    static func labelQuery(
        context: inout ShureSessionContext,
        sessionSelector: UInt16,
        querySelectorA: UInt16,
        querySelectorB: UInt16,
        channel: UInt16,
        queryType: UInt8 = 0x0E,
        sessionToken: UInt16? = nil,
        includeTargetCID: Bool = false
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: [UInt8((sessionSelector >> 8) & 0xFF), UInt8(sessionSelector & 0xFF)])
        let token = sessionToken ?? 0
        payload.append(contentsOf: [UInt8((token >> 8) & 0xFF), UInt8(token & 0xFF)])
        payload.append(contentsOf: [UInt8((querySelectorA >> 8) & 0xFF), UInt8(querySelectorA & 0xFF)])
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: [UInt8((querySelectorB >> 8) & 0xFF), UInt8(querySelectorB & 0xFF)])
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: [UInt8((querySelectorB >> 8) & 0xFF), UInt8(querySelectorB & 0xFF)])
        payload.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        payload.append(contentsOf: [UInt8((token >> 8) & 0xFF), UInt8(token & 0xFF)])
        payload.append(subPdu(payload: [
            0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x20,
            0x70, 0x07, queryType, 0x00, 0x00,
            UInt8((channel >> 8) & 0xFF), UInt8(channel & 0xFF)
        ]))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: context.senderCID,
                framingVector: 0x02,
                framingTargetCID: includeTargetCID ? context.deviceCID : nil,
                payload: payload
            )
        )
    }

    static func extendedQuery(
        context: inout ShureSessionContext,
        sessionSelector: UInt16,
        querySelectorC: UInt16,
        querySelectorD: UInt16,
        querySelectorE: UInt16,
        sessionToken: UInt16? = nil,
        includeTargetCID: Bool = false
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: [UInt8((sessionSelector >> 8) & 0xFF), UInt8(sessionSelector & 0xFF)])
        let token = sessionToken ?? 0
        payload.append(contentsOf: [UInt8((token >> 8) & 0xFF), UInt8(token & 0xFF)])
        payload.append(contentsOf: [UInt8((querySelectorC >> 8) & 0xFF), UInt8(querySelectorC & 0xFF)])
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: [UInt8((querySelectorD >> 8) & 0xFF), UInt8(querySelectorD & 0xFF)])
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: [UInt8((querySelectorE >> 8) & 0xFF), UInt8(querySelectorE & 0xFF)])
        payload.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        payload.append(contentsOf: [UInt8((token >> 8) & 0xFF), UInt8(token & 0xFF)])
        payload.append(subPdu(payload: [
            0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00,
            0x70, 0x08, 0x07, 0x02, 0x01, 0x20, 0x00, 0x10,
            0x10, 0x06, 0x01, 0x20, 0x00, 0x11
        ]))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: context.senderCID,
                framingVector: 0x01,
                framingTargetCID: includeTargetCID ? context.deviceCID : nil,
                payload: payload
            )
        )
    }

    private static func subPdu(payload: [UInt8]) -> Data {
        let length = payload.count + 2
        let flagsLen = UInt16(0x7000 | max(0, min(length, 0x0FFF)))
        var data = Data()
        data.append(contentsOf: [UInt8((flagsLen >> 8) & 0xFF), UInt8(flagsLen & 0xFF)])
        data.append(contentsOf: payload)
        return data
    }
}

enum ShurePropertyResponseParser {
    struct ParsedLabel: Hashable {
        let channel: Int
        let label: String
    }

    static func parseLabels(from data: Data) -> [ParsedLabel] {
        let payload = ShureSessionFramer.parse(data)?.payload ?? data
        let bytes = [UInt8](payload)
        let asciiStrings = asciiRuns(bytes)
        let utf16Strings = utf16LERuns(bytes)
        var matches: [ParsedLabel] = []
        for str in asciiStrings + utf16Strings {
            if str.contains("ASC-") { continue }
            guard let channel = channelFromLabelPrefix(str) ?? channelFromLabelToken(str) else { continue }
            matches.append(ParsedLabel(channel: channel, label: str))
        }
        return matches
    }

    static func extractAsciiRuns(from data: Data) -> [String] {
        let payload = ShureSessionFramer.parse(data)?.payload ?? data
        return asciiRuns([UInt8](payload))
    }

    private static func asciiRuns(_ bytes: [UInt8]) -> [String] {
        var runs: [String] = []
        var current: [UInt8] = []
        for b in bytes {
            if b >= 0x20 && b <= 0x7E {
                current.append(b)
            } else {
                if current.count >= 4, let str = String(bytes: current, encoding: .utf8) {
                    runs.append(str)
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= 4, let str = String(bytes: current, encoding: .utf8) {
            runs.append(str)
        }
        return runs
    }

    private static func utf16LERuns(_ bytes: [UInt8]) -> [String] {
        var runs: [String] = []
        var current: [UInt8] = []
        var index = 0
        while index + 1 < bytes.count {
            let lo = bytes[index]
            let hi = bytes[index + 1]
            if lo >= 0x20 && lo <= 0x7E && hi == 0x00 {
                current.append(lo)
            } else {
                if current.count >= 4, let str = String(bytes: current, encoding: .utf8) {
                    runs.append(str)
                }
                current.removeAll(keepingCapacity: true)
            }
            index += 2
        }
        if current.count >= 4, let str = String(bytes: current, encoding: .utf8) {
            runs.append(str)
        }
        return runs
    }

    private static func channelFromLabelPrefix(_ label: String) -> Int? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        let parts = trimmed.split(whereSeparator: { $0 == "-" || $0 == " " })
        guard let first = parts.first, first.count <= 2, let ch = Int(first), ch >= 1 && ch <= 32 else {
            return nil
        }
        return ch
    }

    private static func channelFromLabelToken(_ label: String) -> Int? {
        let upper = label.uppercased()
        guard let range = upper.range(of: "CH") else { return nil }
        let after = upper[range.upperBound...]
        let digits = after.drop(while: { $0 == " " }).prefix(2)
        guard let ch = Int(digits), ch >= 1 && ch <= 32 else { return nil }
        return ch
    }
}

private extension UUID {
    var uuidBytes: [UInt8] {
        var uuid = self.uuid
        return withUnsafeBytes(of: &uuid) { Array($0) }
    }
}
