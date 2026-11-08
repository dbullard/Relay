//
//  MIDISettingsView.swift
//  Relay
//
//  Created by David Bullard on 5/11/26.
//

import Foundation
import SwiftUI
#if os(macOS)
import CoreMIDI
#endif

struct ControlInputsSettingsView: View {
    private enum InputProtocol: String, CaseIterable, Identifiable {
        case midi = "MIDI"
        case osc = "OSC"

        var id: String { rawValue }
    }

    @AppStorage("midi.global.enabled") private var midiEnabled: Bool = false
    @AppStorage("midi.global.sourceId") private var midiSourceId: Int = -1
    @AppStorage("osc.global.enabled") private var oscEnabled: Bool = false
    @AppStorage("osc.global.port") private var oscPort: Int = 8000

    @ObservedObject private var oscManager = OSCManager.shared

    @State private var selectedProtocol: InputProtocol = .midi
    @State private var portText: String = ""
    @State private var midiPacketCount: Int = 0
    @State private var oscPacketCount: Int = 0
    @State private var lastMIDIMessage: MIDIInputSnapshot?
    @State private var lastOSCMessage: OSCInputSnapshot?
#if os(macOS)
    @State private var midiSources: [ControlInputMIDISourceOption] = ControlInputMIDIEndpointDiscovery.currentSources()
#endif

    var body: some View {

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Picker("Input Type", selection: $selectedProtocol) {
                    ForEach(InputProtocol.allCases) { inputProtocol in
                        Text(inputProtocol.rawValue).tag(inputProtocol)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                switch selectedProtocol {
                case .midi:
                    midiMonitor
                case .osc:
                    oscMonitor
                }
            }
            .padding(24)
        }
        .onAppear {
            normalizePortIfNeeded()
            refreshMIDISources()
            applyMIDI()
            applyOSC()
        }
        .onChange(of: midiSourceId, initial: false) { _, _ in
            applyMIDI()
        }
        .onReceive(NotificationCenter.default.publisher(for: .midiReceiveMessageDidArrive)) { notification in
            lastMIDIMessage = MIDIInputSnapshot(userInfo: notification.userInfo, sourceName: midiSourceName(for: notification.userInfo))
            midiPacketCount += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .oscReceivePacketDidArrive)) { notification in
            oscPacketCount += 1
            if let snapshot = OSCInputSnapshot(userInfo: notification.userInfo, fallback: nil) {
                lastOSCMessage = snapshot
            }
        }
        .onReceive(oscManager.$lastReceived) { received in
            if let received {
                lastOSCMessage = OSCInputSnapshot(received: received)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("External Control")
                .font(.title2.bold())

            Text("Monitor incoming MIDI and OSC signals. Use receive nodes in Graph view to map messages to automations.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var midiMonitor: some View {
        VStack(alignment: .leading, spacing: 14) {
            monitorSection {
                Toggle("MIDI Input", isOn: $midiEnabled)
                    .onChange(of: midiEnabled, initial: false) { _, _ in
                        applyMIDI()
                    }

                statusRow(
                    title: "Status",
                    status: midiStatus,
                    isActive: midiEnabled && lastMIDIMessage?.isRecent == true
                )

                infoRow(title: "Messages", value: "\(midiPacketCount)")
                infoRow(title: "Last Seen", value: lastMIDIMessage?.summary ?? "No MIDI received")

#if os(macOS)
                Picker("Source", selection: $midiSourceId) {
                    Text("All Sources").tag(-1)
                    ForEach(midiSources) { option in
                        Text(option.name).tag(Int(option.id))
                    }
                }
                .disabled(!midiEnabled)

                HStack(spacing: 10) {
                    Button("Refresh Devices") {
                        refreshMIDISources()
                        applyMIDI()
                    }
                    .dashboardLinkButtonStyle()

                    Button("Clear Monitor") {
                        midiPacketCount = 0
                        lastMIDIMessage = nil
                    }
                    .dashboardLinkButtonStyle()
                }
#else
                Text("MIDI device selection is available on macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#endif
            }

            Text("Incoming MIDI is available to MIDI Receive trigger nodes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var oscMonitor: some View {
        VStack(alignment: .leading, spacing: 14) {
            monitorSection {
                Toggle("OSC Listener", isOn: $oscEnabled)
                    .onChange(of: oscEnabled, initial: false) { _, _ in
                        applyOSC()
                    }

                statusRow(
                    title: "Status",
                    status: oscStatus,
                    isActive: oscEnabled && oscManager.isListening
                )

                HStack {
                    Text("Listen Port")
                    Spacer()
                    TextField("8000", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .disabled(!oscEnabled)
                        .onChange(of: oscPort, initial: false) { _, newValue in
                            let value = String(newValue)
                            if portText != value { portText = value }
                        }
                        .onSubmit {
                            commitPort()
                        }
                }

                infoRow(title: "This Mac", value: NetworkUtils.currentIPv4() ?? "No local IPv4 address found")
                infoRow(title: "Messages", value: "\(oscPacketCount)")
                infoRow(title: "Last Seen", value: lastOSCMessage?.summary ?? "No OSC received")

                HStack(spacing: 10) {
                    Button("Restart Listener") {
                        commitPort()
                        applyOSC()
                    }
                    #if os(macOS)
                    .dashboardLinkButtonStyle()
                    #else
                    .buttonStyle(.borderless)
                    #endif
                    .disabled(!oscEnabled)

                    Button("Clear Monitor") {
                        oscPacketCount = 0
                        lastOSCMessage = nil
                    }
                    #if os(macOS)
                    .dashboardLinkButtonStyle()
                    #else
                    .buttonStyle(.borderless)
                    #endif
                }
            }

            Text("Incoming OSC is available to OSC Receive trigger nodes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var midiStatus: String {
        guard midiEnabled else { return "Disabled" }
#if os(macOS)
        if midiSources.isEmpty { return "No MIDI sources found" }
#endif
        if let lastMIDIMessage, lastMIDIMessage.isRecent {
            return "Receiving"
        }
        return "Listening"
    }

    private var oscStatus: String {
        guard oscEnabled else { return "Disabled" }
        if oscManager.isListening {
            return "Listening on UDP \(oscPort)"
        }
        return "Starting listener"
    }

    private func monitorSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusRow(title: String, status: String, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()
            Circle()
                .fill(isActive ? Color.green.opacity(0.9) : Color.white.opacity(0.25))
                .frame(width: 8, height: 8)
            Text(status)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func normalizePortIfNeeded() {
        let clamped = max(1, min(65535, oscPort))
        if clamped != oscPort { oscPort = clamped }
        if portText.isEmpty { portText = String(oscPort) }
    }

    private func commitPort() {
        let digits = portText.filter { $0.isNumber }
        let value = Int(digits) ?? oscPort
        let clamped = max(1, min(65535, value))
        oscPort = clamped
        portText = String(clamped)
        applyOSC()
    }

    private func applyMIDI() {
        let selectedID = midiSourceId >= 0 ? Int32(midiSourceId) : nil
        MIDIGlobalReceiveManager.shared.setGlobalListening(enabled: midiEnabled, preferredSourceID: selectedID)
    }

    private func applyOSC() {
        let port = UInt16(max(1, min(65535, oscPort)))
        OSCManager.shared.setGlobalListening(enabled: oscEnabled, port: port)
    }

    private func refreshMIDISources() {
#if os(macOS)
        midiSources = ControlInputMIDIEndpointDiscovery.currentSources()
#endif
    }

    private func midiSourceName(for userInfo: [AnyHashable: Any]?) -> String? {
        guard let sourceID = userInfo?["sourceID"] as? Int32, sourceID >= 0 else {
            return nil
        }
#if os(macOS)
        return midiSources.first(where: { $0.id == sourceID })?.name
#else
        return nil
#endif
    }
}

private struct MIDIInputSnapshot {
    let receivedAt: Date
    let sourceName: String?
    let kind: String
    let channel: Int?
    let program: Int?
    let note: Int?
    let velocity: Int?
    let control: Int?
    let value: Int?
    let rawBytes: [UInt8]

    init(userInfo: [AnyHashable: Any]?, sourceName: String?) {
        self.receivedAt = Date()
        self.sourceName = sourceName
        self.kind = userInfo?["kind"] as? String ?? "message"
        self.channel = userInfo?["channel"] as? Int
        self.program = userInfo?["program"] as? Int
        self.note = userInfo?["note"] as? Int
        self.velocity = userInfo?["velocity"] as? Int
        self.control = userInfo?["control"] as? Int
        self.value = userInfo?["value"] as? Int
        self.rawBytes = userInfo?["rawBytes"] as? [UInt8] ?? []
    }

    var isRecent: Bool {
        Date().timeIntervalSince(receivedAt) < 2.0
    }

    var summary: String {
        var parts: [String] = []
        if let sourceName { parts.append(sourceName) }
        parts.append(displayKind)
        if let channel { parts.append("Ch \(channel)") }
        if let program { parts.append("Program \(program)") }
        if let control { parts.append("CC \(control)") }
        if let note { parts.append("Note \(note)") }
        if let value { parts.append("Value \(value)") }
        if let velocity { parts.append("Velocity \(velocity)") }
        if !rawBytes.isEmpty { parts.append(rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ")) }
        parts.append(receivedAt.formatted(date: .omitted, time: .standard))
        return parts.joined(separator: " | ")
    }

    private var displayKind: String {
        switch kind {
        case "programChange": return "Program Change"
        case "controlChange": return "Control Change"
        case "noteOn": return "Note On"
        case "noteOff": return "Note Off"
        case "sysex": return "SysEx"
        default: return kind
        }
    }
}

private struct OSCInputSnapshot {
    let receivedAt: Date
    let remote: String?
    let address: String
    let argumentSummary: String

    init?(userInfo: [AnyHashable: Any]?, fallback: OSCReceivedMessage?) {
        if let fallback {
            self.receivedAt = fallback.receivedAt
            self.remote = "\(fallback.remoteHost):\(fallback.remotePort)"
            self.address = fallback.message.address
            self.argumentSummary = fallback.message.args.map(\.debugDescription).joined(separator: ", ")
            return
        }

        guard let address = userInfo?["address"] as? String else {
            return nil
        }

        let remoteHost = userInfo?["remoteHost"] as? String
        let remotePort = userInfo?["remotePort"] as? UInt16
        self.receivedAt = Date()
        self.remote = remoteHost.map { host in
            if let remotePort {
                return "\(host):\(remotePort)"
            }
            return host
        }
        self.address = address
        let argsCount = userInfo?["argsCount"] as? Int ?? 0
        self.argumentSummary = argsCount == 1 ? "1 arg" : "\(argsCount) args"
    }

    init(received: OSCReceivedMessage) {
        self.receivedAt = received.receivedAt
        self.remote = "\(received.remoteHost):\(received.remotePort)"
        self.address = received.message.address
        self.argumentSummary = received.message.args.map(\.debugDescription).joined(separator: ", ")
    }

    var summary: String {
        var parts: [String] = []
        if let remote { parts.append(remote) }
        parts.append(address)
        if !argumentSummary.isEmpty { parts.append(argumentSummary) }
        parts.append(receivedAt.formatted(date: .omitted, time: .standard))
        return parts.joined(separator: " | ")
    }
}

#if os(macOS)
private struct ControlInputMIDISourceOption: Identifiable, Hashable {
    let id: Int32
    let name: String
}

private enum ControlInputMIDIEndpointDiscovery {
    static func currentSources() -> [ControlInputMIDISourceOption] {
        let count = MIDIGetNumberOfSources()
        var result: [ControlInputMIDISourceOption] = []
        result.reserveCapacity(Int(count))

        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            guard endpoint != 0 else { continue }

            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            var nameRef: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameRef)
            let name = (nameRef?.takeRetainedValue() as String?) ?? "MIDI Source \(i)"

            result.append(ControlInputMIDISourceOption(id: uniqueID, name: name))
        }

        return result
    }
}
#endif
