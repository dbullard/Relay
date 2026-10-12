//
//  MIDIProcessing.swift
//  Relay
//
//  Shared MIDI parsing/sending helpers (Yamaha + timecode)
//

import Foundation
import CoreMIDI

extension Notification.Name {
    static let midiReceiveMessageDidArrive = Notification.Name("midiReceiveMessageDidArrive")
    static let midiReceiveProgramChangeDidArrive = Notification.Name("midiReceiveProgramChangeDidArrive")
}

enum MIDIMessageKind: String, Codable, CaseIterable {
    case noteOn
    case noteOff
    case programChange
    case controlChange
    case sysex
}

struct MIDIMessageEvent {
    var kind: MIDIMessageKind
    var channel: Int?
    var program: Int?
    var note: Int?
    var velocity: Int?
    var control: Int?
    var value: Int?
    var sysex: [UInt8]?
    var rawBytes: [UInt8]
    var sourceID: Int32?
}

struct MIDIProgramChangeEvent {
    var program: Int
    var channel: Int
    var sourceID: Int32?
}

struct MIDIDestinationOption: Identifiable, Hashable {
    var id: Int32
    var name: String
}

enum MIDIDestinationDiscovery {
    static func currentDestinations() -> [MIDIDestinationOption] {
        let count = MIDIGetNumberOfDestinations()
        var result: [MIDIDestinationOption] = []

        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            guard endpoint != 0 else { continue }

            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            var nameRef: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameRef)
            let name = (nameRef?.takeRetainedValue() as String?) ?? "MIDI Destination \(i)"

            result.append(MIDIDestinationOption(id: uniqueID, name: name))
        }

        return result
    }
}

final class MIDISendManager {
    static let shared = MIDISendManager()

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()

    private var destinationsByID: [Int32: MIDIEndpointRef] = [:]
    private var destinationOrder: [Int32] = []
    private struct RecentSend {
        let timestamp: TimeInterval
        let destinationID: Int32?
    }
    private var recentSignatures: [String: RecentSend] = [:]
    private let signatureWindow: TimeInterval = 2.0
    private let signatureQueue = DispatchQueue(label: "Relay.MIDISendManager.Signatures")

    private init() {
        MIDIClientCreate("RelayMIDISend" as CFString, nil, nil, &client)
        MIDIOutputPortCreate(client, "RelayMIDISendOut" as CFString, &outputPort)
        refreshDestinations()
    }

    func refreshDestinations() {
        destinationsByID.removeAll()
        destinationOrder.removeAll()

        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            guard endpoint != 0 else { continue }

            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            destinationsByID[uniqueID] = endpoint
            destinationOrder.append(uniqueID)
        }
    }

    func destination(for uniqueID: Int32?) -> MIDIEndpointRef? {
        if destinationsByID.isEmpty {
            refreshDestinations()
        }

        if let uniqueID {
            return destinationsByID[uniqueID]
        }

        if let firstId = destinationOrder.first {
            return destinationsByID[firstId]
        }

        return nil
    }

    @discardableResult
    func send(bytes: [UInt8], to uniqueID: Int32?) -> Bool {
        guard !bytes.isEmpty else { return false }
        guard let destination = destination(for: uniqueID) else { return false }

        registerOutgoing(bytes, destinationID: uniqueID)

        let listSize = MemoryLayout<MIDIPacketList>.size + bytes.count
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { rawPtr.deallocate() }

        let packetListPtr = rawPtr.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(packetListPtr)

        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = MIDIPacketListAdd(packetListPtr, listSize, packet, 0, buffer.count, base)
        }

        let status = MIDISend(outputPort, destination, packetListPtr)
        return status == noErr
    }

    func shouldSuppressIncoming(_ bytes: [UInt8], sourceID: Int32? = nil) -> Bool {
        let signature = midiSignature(bytes)
        let now = Date().timeIntervalSince1970
        return signatureQueue.sync {
            if let last = recentSignatures[signature], (now - last.timestamp) <= signatureWindow {
                return true
            }
            if let sourceID {
                if recentSignatures.values.contains(where: { send in
                    send.destinationID == sourceID && (now - send.timestamp) <= signatureWindow
                }) {
                    return true
                }
            }
            return false
        }
    }

    private func registerOutgoing(_ bytes: [UInt8], destinationID: Int32?) {
        let signature = midiSignature(bytes)
        let now = Date().timeIntervalSince1970
        signatureQueue.async {
            self.recentSignatures[signature] = RecentSend(timestamp: now, destinationID: destinationID)
            self.recentSignatures = self.recentSignatures.filter { (_, send) in
                (now - send.timestamp) <= self.signatureWindow
            }
        }
    }

    private func midiSignature(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

final class YamahaMIDIBridge {
    var onProgramChange: ((MIDIProgramChangeEvent) -> Void)?

    private var programChangeMappings: [Int: YamahaSceneRef] = [:]
    private var preferredMIDISourceID: Int32?
    private var preferredMIDIDestinationID: Int32?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []
    private var outputDestination: MIDIEndpointRef?

    init() {
        setupMIDI()
    }

    func updateMappings(_ mappings: [Int: YamahaSceneRef]) {
        programChangeMappings = mappings
    }

    func updatePreferredSource(_ uniqueID: Int32?) {
        preferredMIDISourceID = uniqueID
        refreshConnections()
    }

    func updatePreferredDestination(_ uniqueID: Int32?) {
        preferredMIDIDestinationID = uniqueID
        refreshDestination()
    }

    func refreshConnections() {
        guard inputPort != 0 else { return }
        disconnectSources()

        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }

            if let preferred = preferredMIDISourceID {
                var uniqueID: Int32 = 0
                MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID)
                if uniqueID != preferred { continue }
            }

            MIDIPortConnectSource(inputPort, source, nil)
            connectedSources.append(source)
        }
    }

    func refreshDestination() {
        guard outputPort != 0 else { return }
        outputDestination = nil

        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            let dest = MIDIGetDestination(i)
            guard dest != 0 else { continue }

            if let preferred = preferredMIDIDestinationID {
                var uniqueID: Int32 = 0
                MIDIObjectGetIntegerProperty(dest, kMIDIPropertyUniqueID, &uniqueID)
                if uniqueID != preferred { continue }
            }

            outputDestination = dest
            break
        }
    }

    func sendProgramChange(_ program: Int) {
        guard let destination = outputDestination else { return }

        let pc = UInt8(max(0, min(127, program)))
        let status: UInt8 = 0xC0
        var packetList = MIDIPacketList()
        let bytes: [UInt8] = [status, pc]
        withUnsafeMutablePointer(to: &packetList) { pktListPtr in
            var packet = MIDIPacketListInit(pktListPtr)
            bytes.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    packet = MIDIPacketListAdd(pktListPtr, 1024, packet, 0, buffer.count, base)
                }
            }
            MIDISend(outputPort, destination, pktListPtr)
        }
    }

    func resolvedScene(for program: Int) -> YamahaSceneRef? {
        programChangeMappings[program]
    }

    func disconnectSources() {
        guard inputPort != 0 else { return }
        for src in connectedSources {
            MIDIPortDisconnectSource(inputPort, src)
        }
        connectedSources.removeAll()
    }

    private func setupMIDI() {
        MIDIClientCreate("RelayYamahaClient" as CFString, nil, nil, &client)
        MIDIInputPortCreate(client, "YamahaIn" as CFString, yamahaMidiReadProc, Unmanaged.passUnretained(self).toOpaque(), &inputPort)
        MIDIOutputPortCreate(client, "YamahaOut" as CFString, &outputPort)
    }

    fileprivate func handlePacketList(_ pktList: UnsafePointer<MIDIPacketList>) {
        MIDIPacketListParser.forEachPacket(in: pktList) { packet in
            let length = Int(packet.pointee.length)
            if length > 0 {
                let bytes = MIDIPacketListParser.extractBytes(packet: packet.pointee)
                MIDIMessageParser.parseMessages(bytes: bytes) { event in
                    if event.kind == .programChange, let program = event.program, let channel = event.channel {
                        onProgramChange?(MIDIProgramChangeEvent(program: program, channel: channel, sourceID: nil))
                    }
                }
            }
        }
    }
}

private let yamahaMidiReadProc: MIDIReadProc = { pktList, readProcRefCon, srcConnRefCon in
    guard let readProcRefCon else { return }
    let bridge = Unmanaged<YamahaMIDIBridge>.fromOpaque(readProcRefCon).takeUnretainedValue()
    bridge.handlePacketList(pktList)
}

final class MIDIGlobalReceiveManager {
    static let shared = MIDIGlobalReceiveManager()

    /// All CoreMIDI calls (client/port setup, connect/disconnect) happen on this serial
    /// queue. CoreMIDI calls can block for tens of seconds if a third-party CoreMIDI
    /// driver/agent is misbehaving, so keeping them off the main thread prevents that
    /// from freezing the UI (setGlobalListening is called while applying a document's
    /// settings snapshot during file open).
    private let midiQueue = DispatchQueue(label: "Relay.MIDIGlobalReceiveManager")

    private var isEnabled: Bool = false
    private var preferredSourceID: Int32?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []

    private init() {
        midiQueue.async { [self] in
            setupMIDI()
        }
    }

    func setGlobalListening(enabled: Bool, preferredSourceID: Int32?) {
        midiQueue.async { [self] in
            isEnabled = enabled
            self.preferredSourceID = preferredSourceID
            refreshConnections()
        }
    }

    private func setupMIDI() {
        MIDIClientCreate("RelayGlobalMIDI" as CFString, nil, nil, &client)
        MIDIInputPortCreate(client, "RelayGlobalIn" as CFString, midiGlobalReadProc, Unmanaged.passUnretained(self).toOpaque(), &inputPort)
    }

    private func refreshConnections() {
        disconnectSources()
        guard isEnabled, inputPort != 0 else { return }

        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }

            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID)

            if let preferred = preferredSourceID, uniqueID != preferred { continue }

            let refCon = UnsafeMutableRawPointer(bitPattern: Int(uniqueID))
            MIDIPortConnectSource(inputPort, source, refCon)
            connectedSources.append(source)
        }
    }

    private func disconnectSources() {
        guard inputPort != 0 else { return }
        for src in connectedSources {
            MIDIPortDisconnectSource(inputPort, src)
        }
        connectedSources.removeAll()
    }

    fileprivate func handlePacketList(_ pktList: UnsafePointer<MIDIPacketList>, sourceID: Int32?) {
        MIDIPacketListParser.forEachPacket(in: pktList) { packet in
            let length = Int(packet.pointee.length)
            if length > 0 {
                let bytes = MIDIPacketListParser.extractBytes(packet: packet.pointee)
                MIDIMessageParser.parseMessages(bytes: bytes) { event in
                    var info: [AnyHashable: Any] = [
                        "kind": event.kind.rawValue,
                        "rawBytes": event.rawBytes,
                        "sourceID": event.sourceID ?? (sourceID ?? -1)
                    ]
                    if let channel = event.channel { info["channel"] = channel }
                    if let program = event.program { info["program"] = program }
                    if let note = event.note { info["note"] = note }
                    if let velocity = event.velocity { info["velocity"] = velocity }
                    if let control = event.control { info["control"] = control }
                    if let value = event.value { info["value"] = value }
                    if let sysex = event.sysex { info["sysex"] = sysex }

                    if !MIDISendManager.shared.shouldSuppressIncoming(event.rawBytes, sourceID: event.sourceID ?? sourceID) {
                        NotificationCenter.default.post(
                            name: .midiReceiveMessageDidArrive,
                            object: nil,
                            userInfo: info
                        )
                    }

                    if event.kind == .programChange,
                       let program = event.program,
                       let channel = event.channel {
                        NotificationCenter.default.post(
                            name: .midiReceiveProgramChangeDidArrive,
                            object: nil,
                            userInfo: [
                                "program": program,
                                "channel": channel,
                                "sourceID": event.sourceID ?? (sourceID ?? -1)
                            ]
                        )
                    }
                }
            }
        }
    }
}

private let midiGlobalReadProc: MIDIReadProc = { pktList, readProcRefCon, srcConnRefCon in
    guard let readProcRefCon else { return }
    let manager = Unmanaged<MIDIGlobalReceiveManager>.fromOpaque(readProcRefCon).takeUnretainedValue()
    let sourceID: Int32? = {
        guard let srcConnRefCon else { return nil }
        let raw = Int(bitPattern: srcConnRefCon)
        return Int32(raw)
    }()
    manager.handlePacketList(pktList, sourceID: sourceID)
}

struct MIDITimecodeUpdate {
    var formatted: String
    var frameRateLabel: String?
}

final class MIDITimecodeParser {
    private var lastFrame: Int = 0
    private var lastSecond: Int = 0
    private var lastMinute: Int = 0
    private var lastHour: Int = 0

    var onUpdate: ((MIDITimecodeUpdate) -> Void)?

    func handlePacketList(_ pktList: UnsafePointer<MIDIPacketList>) {
        MIDIPacketListParser.forEachPacket(in: pktList) { packet in
            let length = Int(packet.pointee.length)
            if length > 0 {
                let bytes = MIDIPacketListParser.extractBytes(packet: packet.pointee)
                var index = 0
                while index < bytes.count {
                    let status = bytes[index]
                    if status == 0xF1, index + 1 < bytes.count {
                        let dataByte = bytes[index + 1]
                        handleQuarterFrame(dataByte)
                        index += 2
                    } else {
                        index += 1
                    }
                }
            }
        }
    }

    private func handleQuarterFrame(_ dataByte: UInt8) {
        let messageType = (dataByte & 0x70) >> 4
        let valueNibble = Int(dataByte & 0x0F)

        var newFrameRateLabel: String? = nil

        switch messageType {
        case 0:
            lastFrame = (lastFrame & 0xF0) | valueNibble
        case 1:
            lastFrame = (lastFrame & 0x0F) | ((valueNibble & 0x1) << 4)
        case 2:
            lastSecond = (lastSecond & 0xF0) | valueNibble
        case 3:
            lastSecond = (lastSecond & 0x0F) | ((valueNibble & 0x3) << 4)
        case 4:
            lastMinute = (lastMinute & 0xF0) | valueNibble
        case 5:
            lastMinute = (lastMinute & 0x0F) | ((valueNibble & 0x3) << 4)
        case 6:
            lastHour = (lastHour & 0xF0) | valueNibble
        case 7:
            let hourLowBit = valueNibble & 0x1
            let rateBits = (valueNibble & 0x6) >> 1

            lastHour = (lastHour & 0x0F) | (hourLowBit << 4)

            switch rateBits {
            case 0: newFrameRateLabel = "24"
            case 1: newFrameRateLabel = "25"
            case 2: newFrameRateLabel = "29.97"
            case 3: newFrameRateLabel = "30"
            default: break
            }
        default:
            break
        }

        let hours = lastHour & 0x1F
        let minutes = lastMinute & 0x3F
        let seconds = lastSecond & 0x3F
        let frames = lastFrame & 0x1F

        let formatted = String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
        onUpdate?(MIDITimecodeUpdate(formatted: formatted, frameRateLabel: newFrameRateLabel))
    }
}

enum MIDIPacketListParser {
    static func forEachPacket(in packetList: UnsafePointer<MIDIPacketList>, _ body: (UnsafeMutablePointer<MIDIPacket>) -> Void) {
        let packetCount = Int(packetList.pointee.numPackets)
        guard packetCount > 0 else { return }

        let firstPacketPointer = UnsafeMutablePointer<MIDIPacket>(
            mutating: UnsafeRawPointer(packetList)
                .advanced(by: MemoryLayout<UInt32>.size)
                .assumingMemoryBound(to: MIDIPacket.self)
        )

        var packetPointer = firstPacketPointer
        for packetIndex in 0..<packetCount {
            body(packetPointer)
            if packetIndex + 1 < packetCount {
                packetPointer = MIDIPacketNext(packetPointer)
            }
        }
    }

    static func extractBytes(packet: MIDIPacket) -> [UInt8] {
        let length = Int(packet.length)
        guard length > 0 else { return [] }
        let children = Mirror(reflecting: packet.data).children
        let allBytes = children.compactMap { $0.value as? UInt8 }
        return Array(allBytes.prefix(length))
    }
}

enum MIDIMessageParser {
    static func parseProgramChanges(bytes: [UInt8], handle: (_ program: Int, _ channel: Int) -> Void) {
        var index = 0
        while index < bytes.count - 1 {
            let status = bytes[index]
            if status >= 0xC0 && status <= 0xCF {
                let program = Int(bytes[index + 1] & 0x7F)
                let channel = Int(status & 0x0F) + 1
                handle(program, channel)
                index += 2
            } else {
                index += 1
            }
        }
    }

    static func parseMessages(bytes: [UInt8], handle: (_ event: MIDIMessageEvent) -> Void) {
        var index = 0
        var runningStatus: UInt8? = nil

        func emit(status: UInt8, data1: UInt8, data2: UInt8?) {
            let high = status & 0xF0
            let channel = Int(status & 0x0F) + 1
            let raw: [UInt8] = {
                if let data2 {
                    return [status, data1, data2]
                }
                return [status, data1]
            }()

            switch high {
            case 0x80:
                handle(MIDIMessageEvent(
                    kind: .noteOff,
                    channel: channel,
                    program: nil,
                    note: Int(data1 & 0x7F),
                    velocity: data2.map { Int($0 & 0x7F) },
                    control: nil,
                    value: nil,
                    sysex: nil,
                    rawBytes: raw,
                    sourceID: nil
                ))
            case 0x90:
                let vel = data2.map { Int($0 & 0x7F) } ?? 0
                let kind: MIDIMessageKind = (vel == 0) ? .noteOff : .noteOn
                handle(MIDIMessageEvent(
                    kind: kind,
                    channel: channel,
                    program: nil,
                    note: Int(data1 & 0x7F),
                    velocity: vel,
                    control: nil,
                    value: nil,
                    sysex: nil,
                    rawBytes: raw,
                    sourceID: nil
                ))
            case 0xB0:
                handle(MIDIMessageEvent(
                    kind: .controlChange,
                    channel: channel,
                    program: nil,
                    note: nil,
                    velocity: nil,
                    control: Int(data1 & 0x7F),
                    value: data2.map { Int($0 & 0x7F) },
                    sysex: nil,
                    rawBytes: raw,
                    sourceID: nil
                ))
            case 0xC0:
                handle(MIDIMessageEvent(
                    kind: .programChange,
                    channel: channel,
                    program: Int(data1 & 0x7F),
                    note: nil,
                    velocity: nil,
                    control: nil,
                    value: nil,
                    sysex: nil,
                    rawBytes: raw,
                    sourceID: nil
                ))
            default:
                break
            }
        }

        while index < bytes.count {
            let b = bytes[index]

            if b >= 0x80 {
                let status = b
                index += 1

                if status == 0xF0 {
                    var sysex: [UInt8] = [0xF0]
                    while index < bytes.count {
                        let v = bytes[index]
                        sysex.append(v)
                        index += 1
                        if v == 0xF7 { break }
                    }
                    handle(MIDIMessageEvent(
                        kind: .sysex,
                        channel: nil,
                        program: nil,
                        note: nil,
                        velocity: nil,
                        control: nil,
                        value: nil,
                        sysex: sysex,
                        rawBytes: sysex,
                        sourceID: nil
                    ))
                    runningStatus = nil
                    continue
                }

                if status >= 0x80 && status <= 0xEF {
                    runningStatus = status
                    let high = status & 0xF0
                    let dataLen = (high == 0xC0 || high == 0xD0) ? 1 : 2
                    guard index + dataLen - 1 < bytes.count else { break }
                    let data1 = bytes[index]
                    let data2 = dataLen == 2 ? bytes[index + 1] : nil
                    index += dataLen
                    emit(status: status, data1: data1, data2: data2)
                    continue
                }

                continue
            }

            if let status = runningStatus {
                let high = status & 0xF0
                let dataLen = (high == 0xC0 || high == 0xD0) ? 1 : 2
                guard index + dataLen - 1 < bytes.count else { break }
                let data1 = bytes[index]
                let data2 = dataLen == 2 ? bytes[index + 1] : nil
                index += dataLen
                emit(status: status, data1: data1, data2: data2)
            } else {
                index += 1
            }
        }
    }
}
