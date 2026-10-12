//
//  TriggerGraphNodeView.swift
//  Relay
//
//  Created by David Bullard on 1/11/26.
//



import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    /// Posted when a Trigger node fires (Time/Wireless/OSC Receive, etc.).
    /// Consumer should read `userInfo` for nodeId/eventKind and act accordingly.
    static let triggerNodeDidFire = Notification.Name("prodlink.triggerNodeDidFire")
}

private enum TriggerNodeFocusField: Hashable {
    case oscPort
    case oscAddress
}

#if os(macOS)
private struct KeystrokeShortcutRecorder: NSViewRepresentable {
    let isRecording: Bool
    let onCapture: (NSEvent) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onKeyDown = handleKeyDown
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onKeyDown = handleKeyDown
        guard isRecording else { return }
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            onCapture(event)
        }
    }

    final class RecorderView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }
    }
}
#endif

/// Graph-only Trigger node UI (Time, Wireless, OSC Receive, etc.). Emits events that drive Actions.
/// Backed by per-node configs stored in `DashboardGraph`.
struct TriggerGraphNodeView: View {
    let nodeId: UUID
    let group: GraphDashboardView.ModuleGroup
    @Binding var graph: DashboardGraph?
    let isSelected: Bool
    let performGraphEdit: ((_ actionName: String, _ mutation: @escaping () -> Void) -> Void)?
    var pcoRundownSnapshotTitles: [String] = []
    /// When set, word trigger config reads/writes use this key instead of the node's own ID.
    /// Used to sync standalone word trigger nodes with the canvas-backed transcription node.
    var wordTriggerSharedConfigKey: String? = nil

    @State private var lastOSCPacketAt: Date? = nil
    @State private var oscPacketCount: Int = 0
    @State private var oscDebugLastReceived: String = "—"
    @State private var oscDebugLastDecision: String = "—"
    @State private var lastMIDIPacketAt: Date? = nil
    @State private var midiPacketCount: Int = 0
    @State private var midiDebugLastReceived: String = "—"
    @State private var midiDebugLastDecision: String = "—"
    @State private var manualFireCount: Int = 0
    @State private var manualLastFiredAt: Date? = nil
    @State private var isPulseActive: Bool = false
    @State private var pulseWorkItem: DispatchWorkItem? = nil
    @AppStorage("osc.global.enabled") private var oscGlobalEnabled: Bool = false
    @AppStorage("osc.global.port") private var oscGlobalPort: Int = 8000
    @AppStorage("midi.global.enabled") private var midiGlobalEnabled: Bool = false
    // Keep text entry stable while graph updates are happening.
    @State private var oscPortText: String = ""
    @State private var oscAddressText: String = ""
    @State private var midiProgramText: String = ""
    @State private var midiChannelText: String = ""
    @State private var midiNoteText: String = ""
    @State private var midiCCNumberText: String = ""
    @State private var midiCCValueText: String = ""
    @State private var midiSysexPrefixText: String = ""
    @State private var isRecordingKeystrokeShortcut: Bool = false

    @FocusState private var focusedField: TriggerNodeFocusField?

    @StateObject private var focusRegistry = TriggerNodeFocusRegistry.shared

    // Mirror the shared TriggerFireTracker stats into local @State so ForEach-hosted
    // graph nodes reliably re-render on every fire. @ObservedObject on a singleton
    // can miss updates when the parent ForEach data hasn't changed.
    @State private var firePressCount: Int = 0
    @State private var fireLastAt: Date? = nil

    private var nodeKey: String { nodeId.uuidString }

    private func applyGraphEdit(actionName: String = "Edit Node", _ mutation: @escaping () -> Void) {
        if let performGraphEdit {
            performGraphEdit(actionName, mutation)
        } else {
            mutation()
        }
    }

    private var triggerTitle: String {
        return group.title
    }

    private var triggerIcon: String {
        let key = group.key
        if key.contains("time") { return "clock.fill" }
        if key.contains("shure") { return "music.microphone" }
        if key.contains("sennheiser") { return "music.microphone" }
        if key.contains("oscReceive") { return "dot.radiowaves.left.and.right" }
        if key.contains("midiReceive") { return "pianokeys" }
        if key.contains("keystrokeTrigger") { return "keyboard" }
        if key.contains("wordTrigger") { return "text.bubble.fill" }
        if key.contains("transcription") { return "text.bubble.fill" }
        if key.contains("dbThreshold") { return "speaker.wave.2.fill" }
        if key.contains("manualTrigger") { return "hand.tap" }
        if key.contains("button") { return "button.programmable" }
        if key.contains("pcoItemChanged") { return "arrow.triangle.2.circlepath" }
        if key.contains("appState") { return "app.badge" }
        if key.contains("proPresenterTrigger") { return "tv" }
        return "bolt.circle.fill"
    }

    private var triggerSubtitle: String {
        let key = group.key
        if key.contains("time") { return "Emit events on a schedule or at specific times." }
        if key.contains("shure") { return "Emit events from Shure wireless state (battery/RF/audio) to drive actions." }
        if key.contains("sennheiser") { return "Emit events from Sennheiser wireless state (battery/RF/audio) to drive actions." }
        if key.contains("oscReceive") { return "Emit events when OSC messages are received to drive actions." }
        if key.contains("midiReceive") { return "Emit events when MIDI messages are received." }
        if key.contains("keystrokeTrigger") { return "Emit events when a Relay keyboard shortcut is pressed." }
        if key.contains("wordTrigger") { return "Emit events when specific words are spoken." }
        if key.contains("dbThreshold") { return "Emit events when a SPL Meter crosses the selected threshold." }
        if key.contains("manualTrigger") { return "Manually fire a trigger event for testing." }
        if key.contains("pcoItemChanged") { return "Fires when the Planning Center service plan is loaded or refreshed in Relay." }
        if key.contains("appState") { return "Emit events on app launch, live mode changes, or tab switches." }
        if key.contains("proPresenterTrigger") { return "Emit events when the ProPresenter slide, presentation, message, or timer changes." }
        if key == DashboardGraph.buttonTriggerGroupKey { return "Fires when this canvas button is pressed." }
        return "Emit events that drive actions and destinations."
    }

    private var triggerCategory: GraphNodeCategory { .triggers }
    private var triggerBorder: Color { triggerCategory.borderColor }
    private var triggerPillFill: Color { triggerCategory.badgeColor }

    /// Nil when this trigger has at least one enabled, non-identity link leaving it --
    /// mirrors the same "any downstream connection" check GraphAutomationRuntime already
    /// runs before firing a trigger (see hasExecutableDownstreamNodes in
    /// GraphAutomationRuntime.swift), just computed here so the gap is visible on the
    /// node itself instead of only silently skipping execution at runtime.
    private var unwiredTriggerWarningText: String? {
        guard let graph else { return nil }
        let connections = GraphAutomationTraversal.downstreamConnections(
            graph: graph,
            sourceNodeId: nodeId,
            resolveNodeIdFromPortId: { GraphAutomationTraversal.resolveNodeId(fromPortId: $0, graph: graph) }
        )
        guard connections.isEmpty, !isDirectlyLinkedToConsoleNode else { return nil }
        return "This trigger isn't connected to anything, so firing it won't do anything. Connect it to an action or destination node."
    }

    private func warningPill(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color.orange.opacity(0.95))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .stroke(Color.orange.opacity(0.18), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
        )
    }

    private var baseBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(Color.white.opacity(GraphNodeStyleTokens.elevatedFillOpacity))
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(triggerCategory.tintColor)
                .blendMode(.screen)
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(Color.white.opacity(GraphNodeStyleTokens.highlightFillOpacity))
        }
    }

    private var baseBorder: some View {
        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
            .stroke(triggerBorder, lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
    }

    private var pulseOverlay: some View {
        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
            .stroke(triggerBorder.opacity(0.75), lineWidth: GraphNodeStyleTokens.selectionStrokeWidth)
            .scaleEffect(isPulseActive ? 1.03 : 1.0)
            .opacity(isPulseActive ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.18), value: isPulseActive)
    }

    // MARK: - Config bindings

    private func ensureDefaults() {
        guard graph != nil else { return }

        if group.key.contains("shure") {
            if graph?.shureTriggerConfigByNodeId[nodeKey] == nil {
                graph?.shureTriggerConfigByNodeId[nodeKey] = DashboardGraph.WirelessTriggerConfig()
            }
        }

        if group.key.contains("sennheiser") {
            if graph?.sennheiserTriggerConfigByNodeId[nodeKey] == nil {
                graph?.sennheiserTriggerConfigByNodeId[nodeKey] = DashboardGraph.WirelessTriggerConfig()
            }
        }

        if group.key.contains("time") {
            if graph?.timeTriggerConfigByNodeId[nodeKey] == nil {
                graph?.timeTriggerConfigByNodeId[nodeKey] = DashboardGraph.TimeTriggerConfig()
            }
        }

        if group.key.contains("dbThreshold") {
            if graph?.dbThresholdConfigByNodeId[nodeKey] == nil {
                graph?.dbThresholdConfigByNodeId[nodeKey] = DashboardGraph.DbThresholdTriggerConfig()
            }
        }

        if group.key.contains("pcoItemChanged") {
            if graph?.pcoItemChangedConfigByNodeId[nodeKey] == nil {
                graph?.pcoItemChangedConfigByNodeId[nodeKey] = DashboardGraph.PCOItemChangedTriggerConfig()
            }
        }

        if group.key.contains("proPresenterTrigger") {
            if graph?.proPresenterTriggerConfigByNodeId[nodeKey] == nil {
                graph?.proPresenterTriggerConfigByNodeId[nodeKey] = DashboardGraph.ProPresenterTriggerConfig()
            }
        }

        if group.key.contains("appState") {
            if graph?.appStateTriggerConfigByNodeId[nodeKey] == nil {
                graph?.appStateTriggerConfigByNodeId[nodeKey] = DashboardGraph.AppStateTriggerConfig()
            }
        }

        if group.key.contains("oscReceive") {
            if graph?.oscReceiveConfigByNodeId[nodeKey] == nil {
                graph?.oscReceiveConfigByNodeId[nodeKey] = DashboardGraph.OSCReceiveConfig()
            }
        }

        if group.key.contains("midiReceive") {
            if graph?.midiReceiveConfigByNodeId[nodeKey] == nil {
                graph?.midiReceiveConfigByNodeId[nodeKey] = DashboardGraph.MIDIReceiveConfig()
            }
        }

        if group.key.contains("keystrokeTrigger") {
            if graph?.keystrokeTriggerConfigByNodeId[nodeKey] == nil {
                graph?.keystrokeTriggerConfigByNodeId[nodeKey] = DashboardGraph.KeystrokeTriggerConfig()
            }
        }

        if group.key.contains("wordTrigger") {
            if graph?.wordTriggerConfigByNodeId[nodeKey] == nil {
                graph?.wordTriggerConfigByNodeId[nodeKey] = DashboardGraph.WordTriggerConfig()
            }
        }

        if group.key.contains("transcription") {
            if graph?.wordTriggerConfigByNodeId[nodeKey] == nil {
                graph?.wordTriggerConfigByNodeId[nodeKey] = DashboardGraph.WordTriggerConfig()
            }
        }
    }

    private var shureCfg: Binding<DashboardGraph.WirelessTriggerConfig> {
        Binding(
            get: { graph?.shureTriggerConfigByNodeId[nodeKey] ?? DashboardGraph.WirelessTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.shureTriggerConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var sennCfg: Binding<DashboardGraph.WirelessTriggerConfig> {
        Binding(
            get: { graph?.sennheiserTriggerConfigByNodeId[nodeKey] ?? DashboardGraph.WirelessTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.sennheiserTriggerConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var timeCfg: Binding<DashboardGraph.TimeTriggerConfig> {
        Binding(
            get: { graph?.timeTriggerConfigByNodeId[nodeKey] ?? DashboardGraph.TimeTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.timeTriggerConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var dbThresholdCfg: Binding<DashboardGraph.DbThresholdTriggerConfig> {
        Binding(
            get: { graph?.dbThresholdConfigByNodeId[nodeKey] ?? DashboardGraph.DbThresholdTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.dbThresholdConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var oscReceiveCfg: Binding<DashboardGraph.OSCReceiveConfig> {
        Binding(
            get: { graph?.oscReceiveConfigByNodeId[nodeKey] ?? DashboardGraph.OSCReceiveConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.oscReceiveConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var midiReceiveCfg: Binding<DashboardGraph.MIDIReceiveConfig> {
        Binding(
            get: { graph?.midiReceiveConfigByNodeId[nodeKey] ?? DashboardGraph.MIDIReceiveConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.midiReceiveConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var keystrokeTriggerCfg: Binding<DashboardGraph.KeystrokeTriggerConfig> {
        Binding(
            get: { graph?.keystrokeTriggerConfigByNodeId[nodeKey] ?? DashboardGraph.KeystrokeTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.keystrokeTriggerConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    /// The config dictionary key to use for word trigger rules.
    /// Falls back to the node's own key when no shared key is provided.
    private var wordTriggerConfigKey: String { wordTriggerSharedConfigKey ?? nodeKey }

    private var wordTriggerCfg: Binding<DashboardGraph.WordTriggerConfig> {
        Binding(
            get: { graph?.wordTriggerConfigByNodeId[wordTriggerConfigKey] ?? DashboardGraph.WordTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.wordTriggerConfigByNodeId[wordTriggerConfigKey] = newValue
                }
            }
        )
    }

    private var pcoItemChangedCfg: Binding<DashboardGraph.PCOItemChangedTriggerConfig> {
        Binding(
            get: { graph?.pcoItemChangedConfigByNodeId[nodeKey] ?? DashboardGraph.PCOItemChangedTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.pcoItemChangedConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var proPresenterTriggerCfg: Binding<DashboardGraph.ProPresenterTriggerConfig> {
        Binding(
            get: { graph?.proPresenterTriggerConfigByNodeId[nodeKey] ?? DashboardGraph.ProPresenterTriggerConfig() },
            set: { newValue in
                applyGraphEdit {
                    graph?.proPresenterTriggerConfigByNodeId[nodeKey] = newValue
                }
            }
        )
    }

    private var appStateCfg: Binding<DashboardGraph.AppStateTriggerConfig> {
        let nodeKey = nodeId.uuidString
        return Binding(
            get: { graph?.appStateTriggerConfigByNodeId[nodeKey] ?? DashboardGraph.AppStateTriggerConfig() },
            set: { newValue in
                if graph == nil { graph = DashboardGraph() }
                graph?.appStateTriggerConfigByNodeId[nodeKey] = newValue
            }
        )
    }

    private func commitOscReceivePort(_ cfg: Binding<DashboardGraph.OSCReceiveConfig>) {
        let filtered = oscPortText.filter { $0.isNumber }
        let value = Int(filtered) ?? 0
        let clamped = max(1, min(65535, value))
        let newPort = UInt16(clamped)

        var v = cfg.wrappedValue

        // Only persist the port when this node is overriding the global listen port.
        if v.useCustomPort {
            if v.customListenPort != newPort {
                v.customListenPort = newPort
                // Keep legacy field in sync for older code paths.
                v.listenPort = newPort
                cfg.wrappedValue = v
            }
        }

        oscPortText = String(clamped)
    }

    private func commitOscReceiveAddress(_ cfg: Binding<DashboardGraph.OSCReceiveConfig>) {
        let trimmed = oscAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let next: String? = trimmed.isEmpty ? nil : trimmed
        var v = cfg.wrappedValue
        if v.addressFilter != next {
            v.addressFilter = next
            cfg.wrappedValue = v
        }
        oscAddressText = next ?? ""
    }

    private func commitMidiProgram(_ cfg: Binding<DashboardGraph.MIDIReceiveConfig>) {
        let trimmed = midiProgramText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var v = cfg.wrappedValue
            v.programFilter = nil
            cfg.wrappedValue = v
            midiProgramText = ""
            return
        }

        let digits = trimmed.filter { $0.isNumber }
        let value = Int(digits) ?? 0
        let clamped = max(0, min(127, value))

        var v = cfg.wrappedValue
        v.programFilter = clamped
        cfg.wrappedValue = v
        midiProgramText = String(clamped)
    }

    private func commitMidiChannel(_ cfg: Binding<DashboardGraph.MIDIReceiveConfig>) {
        let trimmed = midiChannelText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var v = cfg.wrappedValue
            v.channelFilter = nil
            cfg.wrappedValue = v
            midiChannelText = ""
            return
        }

        let digits = trimmed.filter { $0.isNumber }
        let value = Int(digits) ?? 1
        let clamped = max(1, min(16, value))

        var v = cfg.wrappedValue
        v.channelFilter = clamped
        cfg.wrappedValue = v
        midiChannelText = String(clamped)
    }

    private func commitMidiNote(_ cfg: Binding<DashboardGraph.MIDIReceiveConfig>) {
        let trimmed = midiNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var v = cfg.wrappedValue
            v.noteFilter = nil
            cfg.wrappedValue = v
            midiNoteText = ""
            return
        }

        let digits = trimmed.filter { $0.isNumber }
        let value = Int(digits) ?? 0
        let clamped = max(0, min(127, value))

        var v = cfg.wrappedValue
        v.noteFilter = clamped
        cfg.wrappedValue = v
        midiNoteText = String(clamped)
    }

    private func commitMidiCCNumber(_ cfg: Binding<DashboardGraph.MIDIReceiveConfig>) {
        let trimmed = midiCCNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var v = cfg.wrappedValue
            v.ccNumberFilter = nil
            cfg.wrappedValue = v
            midiCCNumberText = ""
            return
        }

        let digits = trimmed.filter { $0.isNumber }
        let value = Int(digits) ?? 0
        let clamped = max(0, min(127, value))

        var v = cfg.wrappedValue
        v.ccNumberFilter = clamped
        cfg.wrappedValue = v
        midiCCNumberText = String(clamped)
    }

    private func commitMidiCCValue(_ cfg: Binding<DashboardGraph.MIDIReceiveConfig>) {
        let trimmed = midiCCValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var v = cfg.wrappedValue
            v.ccValueFilter = nil
            cfg.wrappedValue = v
            midiCCValueText = ""
            return
        }

        let digits = trimmed.filter { $0.isNumber }
        let value = Int(digits) ?? 0
        let clamped = max(0, min(127, value))

        var v = cfg.wrappedValue
        v.ccValueFilter = clamped
        cfg.wrappedValue = v
        midiCCValueText = String(clamped)
    }

    private func commitMidiSysexPrefix(_ cfg: Binding<DashboardGraph.MIDIReceiveConfig>) {
        let trimmed = midiSysexPrefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = trimmed.isEmpty ? nil : trimmed
        var v = cfg.wrappedValue
        v.sysexPrefixHex = next
        cfg.wrappedValue = v
        midiSysexPrefixText = next ?? ""
    }

    private func parseHexBytes(_ text: String) -> [UInt8]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .split { $0 == " " || $0 == "\t" || $0 == "," || $0 == "-" }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(tokens.count)

        for t in tokens {
            let token = String(t)
            guard let v = UInt8(token, radix: 16) else { return nil }
            bytes.append(v)
        }

        return bytes.isEmpty ? nil : bytes
    }

    private func midiTypeLabel(_ type: DashboardGraph.MIDIMessageType) -> String {
        switch type {
        case .any: return "Any"
        case .programChange: return "Program Change"
        case .noteOn: return "Note On"
        case .noteOff: return "Note Off"
        case .controlChange: return "Control Change"
        case .sysex: return "SysEx"
        }
    }

    // MARK: - Console node linkage helpers

    private var isDirectlyLinkedToConsoleNode: Bool {
        TriggerGraphLinkInspector.isDirectlyLinkedToConsoleNode(graph: graph, nodeId: nodeId)
    }

    private func directLinkedConsoleExternalDeviceIds() -> [UUID] {
        TriggerGraphLinkInspector.directLinkedConsoleExternalDeviceIds(graph: graph, nodeId: nodeId)
    }
    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: triggerIcon)
                    .imageScale(.medium)
                    .opacity(0.9)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(triggerTitle)
                            .font(.headline)
                            .lineLimit(1)

                        if group.isCanvasBacked {
                            Image(systemName: "square.grid.2x2")
                                .imageScale(.small)
                                .opacity(0.75)
                                .accessibilityLabel("Canvas-backed node")
                        }

                        Text("TRIGGER")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(triggerPillFill))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }

                    Text(triggerSubtitle)
                        .font(.caption)
                        .opacity(0.70)
                        .lineLimit(2)
                }

                Spacer()
            }

            Divider().opacity(0.25)

            if let unwiredTriggerWarningText {
                warningPill(text: unwiredTriggerWarningText)
            }

            if graph == nil {
                Text("Trigger settings unavailable (graph missing).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if group.key.contains("shure") {
                    ShureWirelessTriggerSettings(config: shureCfg)
                } else if group.key.contains("sennheiser") {
                    SennheiserWirelessTriggerSettings(config: sennCfg)
                } else if group.key.contains("time") {
                    timeSettings
                } else if group.key.contains("dbThreshold") {
                    dbThresholdSettings
                } else if group.key.contains("manualTrigger") {
                    manualTriggerSettings
                } else if group.key.contains("button") {
                    buttonTriggerSettings
                } else if group.key.contains("keystrokeTrigger") {
                    keystrokeTriggerSettings
                } else if group.key.contains("oscReceive") {
                    oscReceiveSettings
                } else if group.key.contains("midiReceive") {
                    midiReceiveSettings
                } else if group.key.contains("wordTrigger") {
                    wordTriggerSettings
                } else if group.key.contains("transcription") {
                    wordTriggerSettings
                } else if group.key.contains("pcoItemChanged") {
                    pcoItemChangedSettings
                } else if group.key.contains("appState") {
                    appStateSettings
                } else if group.key.contains("proPresenterTrigger") {
                    proPresenterTriggerSettings
                } else {
                    Text("No settings available for this trigger yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(baseBackground)
        .overlay(baseBorder)
        .overlay(pulseOverlay)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 2)
        )
        .onAppear {
            ensureDefaults()
            // Seed local press stats from the singleton so the count survives view re-mounts.
            firePressCount = TriggerFireTracker.shared.count(for: nodeId)
            fireLastAt = TriggerFireTracker.shared.lastFired(for: nodeId)
        }
        .onReceive(NotificationCenter.default.publisher(for: TriggerNodeNotifications.fired)) { note in
            guard let firedId = note.userInfo?[TriggerNodeUserInfoKeys.triggerNodeId] as? UUID else { return }
            guard firedId == nodeId else { return }
            Task { @MainActor in
                RelayDiagnosticsStore.shared.incrementCounter("graph.triggerView.fired.received")
            }
            triggerPulse()
            // Bump local @State directly so SwiftUI re-renders this node immediately,
            // independent of when the shared TriggerFireTracker observer runs (their
            // delivery order isn't guaranteed). The tracker is still the source of
            // truth across view re-mounts via the seed in onAppear.
            firePressCount += 1
            fireLastAt = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .oscReceivePacketDidArrive)) { n in
            // Only relevant for OSC Receive nodes
            guard group.key.contains("oscReceive") else { return }

            // Prefer localPort, fallback to port for backward compatibility
            let portAny = n.userInfo?["localPort"] ?? n.userInfo?["port"]
            let port: UInt16? = {
                if let p = portAny as? UInt16 { return p }
                if let p = portAny as? Int { return UInt16(clamping: p) }
                if let p = portAny as? NSNumber { return UInt16(truncating: p) }
                return nil
            }()
            let address = (n.userInfo?["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let payloadText = n.userInfo?[TriggerNodeUserInfoKeys.payloadText] as? String
            let payloadNumber = n.userInfo?[TriggerNodeUserInfoKeys.payloadNumber] as? Double
            let payloadBoolean = n.userInfo?[TriggerNodeUserInfoKeys.payloadBoolean] as? Bool

            // Match the current node config
            let cfg = oscReceiveCfg.wrappedValue
            let globalPort = UInt16(max(1, min(65535, oscGlobalPort)))
            let matchPort: UInt16 = cfg.useCustomPort ? cfg.customListenPort : globalPort
            let addrDisplay = (address?.isEmpty == false) ? address! : "-"
            oscDebugLastReceived = "port=\(port.map { String($0) } ?? "-") addr=\(addrDisplay)"

            guard let port, port == matchPort else {
                oscDebugLastDecision = "Filtered: Port mismatch"
                return
            }
            if let filter = cfg.addressFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !filter.isEmpty {
                if let address, !address.isEmpty {
                    guard address == filter else {
                        oscDebugLastDecision = "Filtered: Address mismatch"
                        return
                    }
                } else {
                    oscDebugLastDecision = "Filtered: Address missing"
                    // If we have a filter but the notification didn't provide an address, don't count it.
                    return
                }
            }

            // Fire the trigger event (ONLY after port + address filter passes)
            let info: [AnyHashable: Any] = [
                "nodeId": nodeId,                       // UUID (preferred)
                "nodeIdString": nodeId.uuidString,      // legacy convenience
                "eventKind": cfg.emitEventKind,
                "address": address ?? "",
                "localPort": Int(port),
                TriggerNodeUserInfoKeys.payloadText: payloadText as Any,
                TriggerNodeUserInfoKeys.payloadNumber: payloadNumber as Any,
                TriggerNodeUserInfoKeys.payloadBoolean: payloadBoolean as Any
            ]

            // Legacy notification (used by older code paths)
            NotificationCenter.default.post(
                name: .triggerNodeDidFire,
                object: nil,
                userInfo: info
            )

            let firedInfo: [AnyHashable: Any] = [
                TriggerNodeUserInfoKeys.triggerNodeId: nodeId,
                TriggerNodeUserInfoKeys.address: address ?? "",
                TriggerNodeUserInfoKeys.localPort: Int(port),
                TriggerNodeUserInfoKeys.payloadText: payloadText as Any,
                TriggerNodeUserInfoKeys.payloadNumber: payloadNumber as Any,
                TriggerNodeUserInfoKeys.payloadBoolean: payloadBoolean as Any
            ]

            NotificationCenter.default.post(
                name: TriggerNodeNotifications.fired,
                object: nil,
                userInfo: firedInfo
            )

            oscDebugLastDecision = "Triggered"

            // Update indicator
            lastOSCPacketAt = Date()
            oscPacketCount += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .midiReceiveMessageDidArrive)) { n in
            guard group.key.contains("midiReceive") else { return }

            let ui = n.userInfo ?? [:]
            let kindRaw = (ui["kind"] as? String) ?? "programChange"
            let kind = MIDIMessageKind(rawValue: kindRaw) ?? .programChange

            let channel: Int? = {
                if let v = ui["channel"] as? Int { return v }
                if let v = ui["channel"] as? NSNumber { return v.intValue }
                return nil
            }()
            let program: Int? = {
                if let v = ui["program"] as? Int { return v }
                if let v = ui["program"] as? NSNumber { return v.intValue }
                return nil
            }()
            let note: Int? = {
                if let v = ui["note"] as? Int { return v }
                if let v = ui["note"] as? NSNumber { return v.intValue }
                return nil
            }()
            let velocity: Int? = {
                if let v = ui["velocity"] as? Int { return v }
                if let v = ui["velocity"] as? NSNumber { return v.intValue }
                return nil
            }()
            let control: Int? = {
                if let v = ui["control"] as? Int { return v }
                if let v = ui["control"] as? NSNumber { return v.intValue }
                return nil
            }()
            let value: Int? = {
                if let v = ui["value"] as? Int { return v }
                if let v = ui["value"] as? NSNumber { return v.intValue }
                return nil
            }()
            let sysex: [UInt8]? = ui["sysex"] as? [UInt8]

            let cfg = midiReceiveCfg.wrappedValue
            let channelText = channel.map(String.init) ?? "-"
            let programText = program.map(String.init) ?? "-"
            let noteText = note.map(String.init) ?? "-"
            let controlText = control.map(String.init) ?? "-"
            let valueText = value.map(String.init) ?? "-"
            let summaryParts = [
                "kind=\(kind.rawValue)",
                "ch=\(channelText)",
                "prog=\(programText)",
                "note=\(noteText)",
                "cc=\(controlText)",
                "val=\(valueText)",
                "sysex=\(sysex?.count ?? 0)"
            ]
            midiDebugLastReceived = summaryParts.joined(separator: " ")

            var didMatch = true
            var rejectReason: String? = nil

            switch cfg.messageType {
            case .any:
                if let filter = cfg.channelFilter, filter != channel {
                    didMatch = false
                    rejectReason = "Channel filter"
                }
                if didMatch, let filter = cfg.programFilter, filter != program {
                    didMatch = false
                    rejectReason = "Program filter"
                }
                if didMatch, let filter = cfg.noteFilter, filter != note {
                    didMatch = false
                    rejectReason = "Note filter"
                }
                if didMatch, let filter = cfg.ccNumberFilter, filter != control {
                    didMatch = false
                    rejectReason = "CC number filter"
                }
                if didMatch, let filter = cfg.ccValueFilter, filter != value {
                    didMatch = false
                    rejectReason = "CC value filter"
                }
                if didMatch, let prefix = cfg.sysexPrefixHex,
                   let prefixBytes = parseHexBytes(prefix) {
                    if let sysex, !sysex.starts(with: prefixBytes) {
                        didMatch = false
                        rejectReason = "SysEx prefix"
                    } else if sysex == nil {
                        didMatch = false
                        rejectReason = "SysEx missing"
                    }
                }

            case .programChange:
                if kind != .programChange {
                    didMatch = false
                    rejectReason = "Type mismatch"
                }
                if didMatch, let filter = cfg.programFilter, filter != program {
                    didMatch = false
                    rejectReason = "Program filter"
                }
                if didMatch, let filter = cfg.channelFilter, filter != channel {
                    didMatch = false
                    rejectReason = "Channel filter"
                }

            case .noteOn:
                if kind != .noteOn {
                    didMatch = false
                    rejectReason = "Type mismatch"
                }
                if didMatch, let filter = cfg.noteFilter, filter != note {
                    didMatch = false
                    rejectReason = "Note filter"
                }
                if didMatch, let filter = cfg.channelFilter, filter != channel {
                    didMatch = false
                    rejectReason = "Channel filter"
                }

            case .noteOff:
                if kind != .noteOff {
                    didMatch = false
                    rejectReason = "Type mismatch"
                }
                if didMatch, let filter = cfg.noteFilter, filter != note {
                    didMatch = false
                    rejectReason = "Note filter"
                }
                if didMatch, let filter = cfg.channelFilter, filter != channel {
                    didMatch = false
                    rejectReason = "Channel filter"
                }

            case .controlChange:
                if kind != .controlChange {
                    didMatch = false
                    rejectReason = "Type mismatch"
                }
                if didMatch, let filter = cfg.ccNumberFilter, filter != control {
                    didMatch = false
                    rejectReason = "CC number filter"
                }
                if didMatch, let filter = cfg.ccValueFilter, filter != value {
                    didMatch = false
                    rejectReason = "CC value filter"
                }
                if didMatch, let filter = cfg.channelFilter, filter != channel {
                    didMatch = false
                    rejectReason = "Channel filter"
                }

            case .sysex:
                if kind != .sysex {
                    didMatch = false
                    rejectReason = "Type mismatch"
                }
                if didMatch, let prefix = cfg.sysexPrefixHex,
                   let prefixBytes = parseHexBytes(prefix) {
                    if let sysex, !sysex.starts(with: prefixBytes) {
                        didMatch = false
                        rejectReason = "SysEx prefix"
                    } else if sysex == nil {
                        didMatch = false
                        rejectReason = "SysEx missing"
                    }
                }
            }

            if !didMatch {
                let reason = rejectReason ?? "No match"
                midiDebugLastDecision = "Filtered: \(reason)"
                return
            }

            var info: [AnyHashable: Any] = [
                "nodeId": nodeId,
                "nodeIdString": nodeId.uuidString,
                "eventKind": cfg.emitEventKind,
                "messageType": cfg.messageType.rawValue
            ]
            if let channel { info["channel"] = channel }
            if let program { info["program"] = program }
            if let note { info["note"] = note }
            if let velocity { info["velocity"] = velocity }
            if let control { info["control"] = control }
            if let value { info["value"] = value }
            if let sysex { info["sysex"] = sysex }

            NotificationCenter.default.post(
                name: .triggerNodeDidFire,
                object: nil,
                userInfo: info
            )

            let firedInfo: [AnyHashable: Any] = [
                TriggerNodeUserInfoKeys.triggerNodeId: nodeId
            ]

            NotificationCenter.default.post(
                name: TriggerNodeNotifications.fired,
                object: nil,
                userInfo: firedInfo
            )

            midiDebugLastDecision = "Triggered"

            lastMIDIPacketAt = Date()
            midiPacketCount += 1
        }
    }

    // MARK: - Button trigger settings

    private var buttonTriggerSettings: some View {
        let firedText: String = {
            guard let lastFired = fireLastAt else { return "—" }
            return lastFired.formatted(date: .omitted, time: .standard)
        }()

        return Text("Pressed: \(firePressCount) • Last: \(firedText)")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Manual trigger settings

    private var manualTriggerSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manual Trigger")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                fireManualTrigger()
            } label: {
                Label("Fire Trigger", systemImage: "bolt.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)

            let firedText: String = {
                guard let manualLastFiredAt else { return "—" }
                return manualLastFiredAt.formatted(date: .omitted, time: .standard)
            }()

            Text("Fired: \(manualFireCount) • Last: \(firedText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var keystrokeTriggerSettings: some View {
        let cfg = keystrokeTriggerCfg
        let shortcutSummary = formattedKeystrokeShortcut(cfg.wrappedValue)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Shortcut")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(shortcutSummary)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(isRecordingKeystrokeShortcut ? 0.16 : 0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(isRecordingKeystrokeShortcut ? 0.28 : 0.12), lineWidth: 1)
                    )

                Button {
                    isRecordingKeystrokeShortcut.toggle()
                } label: {
                    Label(isRecordingKeystrokeShortcut ? "Cancel" : "Record", systemImage: isRecordingKeystrokeShortcut ? "xmark" : "record.circle")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption)
                .buttonStyle(.bordered)

                Button {
                    clearKeystrokeShortcut(cfg)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(cfg.wrappedValue.keyEquivalent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Clear shortcut")
            }

#if os(macOS)
            if isRecordingKeystrokeShortcut {
                Text("Press the shortcut to assign it. Esc cancels.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                KeystrokeShortcutRecorder(
                    isRecording: isRecordingKeystrokeShortcut,
                    onCapture: { event in
                        applyKeystrokeShortcut(event, to: cfg)
                    },
                    onCancel: {
                        isRecordingKeystrokeShortcut = false
                    }
                )
                .frame(width: 0, height: 0)
            }
#else
            TextField("Key", text: Binding(
                get: { cfg.wrappedValue.keyEquivalent },
                set: { newValue in
                    var v = cfg.wrappedValue
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    v.keyEquivalent = String(trimmed.prefix(1)).lowercased()
                    cfg.wrappedValue = v
                }
            ))
            .textFieldStyle(.roundedBorder)
#endif

            Toggle("Command", isOn: Binding(
                get: { cfg.wrappedValue.requiresCommand },
                set: {
                    var v = cfg.wrappedValue
                    v.requiresCommand = $0
                    cfg.wrappedValue = v
                }
            ))
#if os(macOS)
            .toggleStyle(.checkbox)
#endif

            Toggle("Shift", isOn: Binding(
                get: { cfg.wrappedValue.requiresShift },
                set: {
                    var v = cfg.wrappedValue
                    v.requiresShift = $0
                    cfg.wrappedValue = v
                }
            ))
#if os(macOS)
            .toggleStyle(.checkbox)
#endif

            Toggle("Option", isOn: Binding(
                get: { cfg.wrappedValue.requiresOption },
                set: {
                    var v = cfg.wrappedValue
                    v.requiresOption = $0
                    cfg.wrappedValue = v
                }
            ))
#if os(macOS)
            .toggleStyle(.checkbox)
#endif

            Toggle("Control", isOn: Binding(
                get: { cfg.wrappedValue.requiresControl },
                set: {
                    var v = cfg.wrappedValue
                    v.requiresControl = $0
                    cfg.wrappedValue = v
                }
            ))
#if os(macOS)
            .toggleStyle(.checkbox)
#endif

            Toggle("Allow Key Repeat", isOn: Binding(
                get: { cfg.wrappedValue.allowsRepeat },
                set: {
                    var v = cfg.wrappedValue
                    v.allowsRepeat = $0
                    cfg.wrappedValue = v
                }
            ))
            .toggleStyle(.switch)

            HStack(spacing: 8) {
                Text("Cooldown")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("0", value: Binding(
                    get: { cfg.wrappedValue.cooldownSeconds },
                    set: {
                        var v = cfg.wrappedValue
                        v.cooldownSeconds = max(0, min(30, $0))
                        cfg.wrappedValue = v
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
            }

            Text("Current: \(shortcutSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func clearKeystrokeShortcut(_ cfg: Binding<DashboardGraph.KeystrokeTriggerConfig>) {
        var v = cfg.wrappedValue
        v.keyEquivalent = ""
        cfg.wrappedValue = v
        isRecordingKeystrokeShortcut = false
    }

#if os(macOS)
    private func applyKeystrokeShortcut(_ event: NSEvent, to cfg: Binding<DashboardGraph.KeystrokeTriggerConfig>) {
        let rawKey = (event.charactersIgnoringModifiers ?? event.characters ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstKey = rawKey.first else { return }

        var v = cfg.wrappedValue
        v.keyEquivalent = String(firstKey).lowercased()
        v.requiresCommand = event.modifierFlags.contains(.command)
        v.requiresShift = event.modifierFlags.contains(.shift)
        v.requiresOption = event.modifierFlags.contains(.option)
        v.requiresControl = event.modifierFlags.contains(.control)
        cfg.wrappedValue = v
        isRecordingKeystrokeShortcut = false
    }
#endif

    private func formattedKeystrokeShortcut(_ cfg: DashboardGraph.KeystrokeTriggerConfig) -> String {
        var parts: [String] = []
        if cfg.requiresCommand { parts.append("Cmd") }
        if cfg.requiresShift { parts.append("Shift") }
        if cfg.requiresOption { parts.append("Option") }
        if cfg.requiresControl { parts.append("Control") }
        let key = cfg.keyEquivalent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            parts.append(key.uppercased())
        }
        return parts.isEmpty ? "Not Set" : parts.joined(separator: "+")
    }

    private func fireManualTrigger() {
        triggerPulse()
        let info: [AnyHashable: Any] = [
            "nodeId": nodeId,
            "nodeIdString": nodeId.uuidString,
            "eventKind": "manual.trigger"
        ]

        NotificationCenter.default.post(
            name: .triggerNodeDidFire,
            object: nil,
            userInfo: info
        )

        let firedInfo: [AnyHashable: Any] = [
            TriggerNodeUserInfoKeys.triggerNodeId: nodeId
        ]

        NotificationCenter.default.post(
            name: TriggerNodeNotifications.fired,
            object: nil,
            userInfo: firedInfo
        )

        manualFireCount += 1
        manualLastFiredAt = Date()
    }

    private func triggerPulse() {
        pulseWorkItem?.cancel()
        pulseWorkItem = nil

        withAnimation(.easeOut(duration: 0.12)) {
            isPulseActive = true
        }

        let work = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.18)) {
                isPulseActive = false
            }
        }
        pulseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    // MARK: - Time settings (simple, but usable)

    private var timeSettings: some View {
        let cfg = timeCfg
        return VStack(alignment: .leading, spacing: 10) {
            Text("Time Trigger")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Mode", selection: cfg.mode) {
                ForEach(DashboardGraph.TimeTriggerConfig.Mode.allCases, id: \.self) { mode in
                    Text(mode == .interval ? "Interval" : "At Time").tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if cfg.wrappedValue.mode == .interval {
                HStack(spacing: 10) {
                    Text("Every")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("Seconds", value: cfg.intervalSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                    Text("sec")
                        .font(.caption)
                        .opacity(0.8)

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 10) {
                    Text("Time")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("HH:mm", text: cfg.timeOfDay)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 10) {
                Text("Cooldown")
                    .font(.caption)
                    .opacity(0.8)

                TextField("Seconds", value: cfg.cooldownSeconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Text("sec")
                    .font(.caption)
                    .opacity(0.8)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - dB Threshold settings

    private var dbThresholdSettings: some View {
        let cfg = dbThresholdCfg
        return VStack(alignment: .leading, spacing: 10) {
            Text("dB Threshold")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Metric", selection: cfg.metric) {
                Text("SPL").tag(DashboardGraph.DbThresholdMetric.spl)
                Text("Peak").tag(DashboardGraph.DbThresholdMetric.peak)
                Text("Raw dBFS").tag(DashboardGraph.DbThresholdMetric.rawDbFS)
                Text("Raw Peak dBFS").tag(DashboardGraph.DbThresholdMetric.rawPeakDbFS)
            }
            .pickerStyle(.menu)

            Picker("Comparison", selection: cfg.comparison) {
                Text("Above").tag(DashboardGraph.DbThresholdComparison.above)
                Text("Below").tag(DashboardGraph.DbThresholdComparison.below)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Text("Threshold")
                    .font(.caption)
                    .opacity(0.8)

                TextField("dB", value: cfg.threshold, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Text("dB")
                    .font(.caption)
                    .opacity(0.8)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("Cooldown")
                    .font(.caption)
                    .opacity(0.8)

                TextField("Seconds", value: cfg.cooldownSeconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Text("sec")
                    .font(.caption)
                    .opacity(0.8)

                Spacer(minLength: 0)
            }

            Text("Requires a link from a SPL Meter tile to this trigger.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Word Trigger settings

    private var wordTriggerSettings: some View {
        let cfg = wordTriggerCfg
        let linkedSources = linkedTranscriptionSources()
        let rules = cfg.wrappedValue.rules
        let isTranscriptionTrigger = group.key.contains("transcription")

        return VStack(alignment: .leading, spacing: 12) {
            Text(isTranscriptionTrigger ? "Transcription Triggers" : "Word Trigger")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(rules) { rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Phrase", text: Binding(
                            get: { rule.phrase },
                            set: { newValue in
                                updateRule(rule.id) { $0.phrase = newValue }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button {
                            removeRule(rule.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("Match", selection: Binding(
                        get: { rule.matchMode },
                        set: { newValue in
                            updateRule(rule.id) { $0.matchMode = newValue }
                        }
                    )) {
                        Text("Contains").tag(DashboardGraph.WordTriggerRule.MatchMode.contains)
                        Text("Whole word").tag(DashboardGraph.WordTriggerRule.MatchMode.wholeWord)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Final only", isOn: Binding(
                        get: { rule.finalOnly },
                        set: { newValue in
                            updateRule(rule.id) { $0.finalOnly = newValue }
                        }
                    ))


                    HStack(spacing: 10) {
                        Text("Cooldown")
                            .font(.caption)
                            .opacity(0.8)
                        TextField("Seconds", value: Binding(
                            get: { rule.cooldownSeconds },
                            set: { newValue in
                                updateRule(rule.id) { $0.cooldownSeconds = newValue }
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                        Text("sec")
                            .font(.caption)
                            .opacity(0.8)
                    }

                    if !linkedSources.isEmpty {
                        Text("Sources")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ForEach(linkedSources) { source in
                            Toggle(source.displayName, isOn: Binding(
                                get: { rule.sourceIds.isEmpty ? true : rule.sourceIds.contains(source.id) },
                                set: { isOn in
                                    updateRule(rule.id) { draft in
                                        var set = Set(draft.sourceIds)
                                        if isOn {
                                            set.insert(source.id)
                                        } else {
                                            set.remove(source.id)
                                        }
                                        draft.sourceIds = Array(set)
                                    }
                                }
                            ))
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                        .fill(Color.white.opacity(GraphNodeStyleTokens.subtleFillOpacity))
                )
            }

            Button {
                var v = cfg.wrappedValue
                var rule = DashboardGraph.WordTriggerRule()
                if isTranscriptionTrigger {
                    rule.finalOnly = false
                }
                v.rules.append(rule)
                cfg.wrappedValue = v
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.plain)
        }
    }

    private func updateRule(_ id: UUID, _ update: (inout DashboardGraph.WordTriggerRule) -> Void) {
        var v = wordTriggerCfg.wrappedValue
        guard let idx = v.rules.firstIndex(where: { $0.id == id }) else { return }
        var rule = v.rules[idx]
        update(&rule)
        v.rules[idx] = rule
        wordTriggerCfg.wrappedValue = v
    }

    private func removeRule(_ id: UUID) {
        // Use the shared config key's node ID for port cleanup (may differ from nodeKey when synced).
        guard let nodeId = UUID(uuidString: wordTriggerConfigKey) else {
            var v = wordTriggerCfg.wrappedValue
            v.rules.removeAll { $0.id == id }
            if v.rules.isEmpty { v.rules = [DashboardGraph.WordTriggerRule()] }
            wordTriggerCfg.wrappedValue = v
            return
        }

        let rulePortId = GraphAutomationTraversal.wordTriggerRulePortId(nodeId: nodeId, ruleId: id)

        var v = wordTriggerCfg.wrappedValue
        v.rules.removeAll { $0.id == id }
        if v.rules.isEmpty { v.rules = [DashboardGraph.WordTriggerRule()] }
        wordTriggerCfg.wrappedValue = v

        graph?.links.removeAll { $0.fromPortId == rulePortId }
        graph?.nodeIdByPortId.removeValue(forKey: rulePortId)
    }

    private func linkedTranscriptionSources() -> [LiveTranscriptionSourceDescriptor] {
        guard let graph else { return [] }
        let incoming = graph.links.filter { link in
            if !link.isEnabled { return false }
            let resolved = graph.nodeIdByPortId[link.toPortId] ?? link.toTileId
            return resolved == nodeId
        }
        let sourceNodeIds = Set(incoming.map { graph.nodeIdByPortId[$0.fromPortId] ?? $0.fromTileId })
        var sources: [LiveTranscriptionSourceDescriptor] = []
        for sourceNodeId in sourceNodeIds {
            sources.append(contentsOf: LiveTranscriptionSourceRegistry.shared.sources(for: sourceNodeId))
        }

        var seen: Set<UUID> = []
        return sources.filter { seen.insert($0.id).inserted }
    }

    // MARK: - OSC Receive settings (simple)

    private var oscReceiveSettings: some View {
        let cfg = oscReceiveCfg
        return VStack(alignment: .leading, spacing: 10) {
            Text("OSC Receive")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Listening is controlled globally in Settings → OSC. These fields only define what this node matches.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(0.85)

            Toggle("Override global listen port", isOn: Binding(
                get: { cfg.wrappedValue.useCustomPort },
                set: { newValue in
                    var v = cfg.wrappedValue
                    v.useCustomPort = newValue

                    let g = UInt16(max(1, min(65535, oscGlobalPort)))

                    if newValue {
                        // Enabling override: seed custom port if needed, and show it.
                        if v.customListenPort == 0 {
                            v.customListenPort = g
                        }
                        v.listenPort = v.customListenPort
                        oscPortText = String(v.customListenPort)
                    } else {
                        // Disabling override: show the global port in the field.
                        oscPortText = String(g)
                    }

                    cfg.wrappedValue = v
                }
            ))
            .toggleStyle(.switch)

            HStack(spacing: 10) {
                Text("Listen")
                    .font(.caption)
                    .opacity(0.8)

                TextField("Port", text: $oscPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .disabled(!cfg.wrappedValue.useCustomPort)
                    .opacity(cfg.wrappedValue.useCustomPort ? 1.0 : 0.55)
                    .focused($focusedField, equals: .oscPort)
                    .onChange(of: focusedField, initial: false) { _, newValue in
                        guard newValue == .oscPort else { return }
                        focusRegistry.setDesiredField(.oscPort, for: nodeId)
                    }
                    .onAppear {
                        // Initialize draft from config
                        if oscPortText.isEmpty {
                            let v = cfg.wrappedValue
                            if v.useCustomPort {
                                oscPortText = String(v.customListenPort)
                            } else {
                                let g = UInt16(max(1, min(65535, oscGlobalPort)))
                                oscPortText = String(g)
                            }
                        }
                        if focusRegistry.desiredField(for: nodeId) == .oscPort {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                self.focusedField = .oscPort
                            }
                        }
                    }
                    .onChange(of: cfg.wrappedValue.customListenPort, initial: false) { _, newPort in
                        guard cfg.wrappedValue.useCustomPort else { return }
                        // If LAN/graph updates change the config while we're not editing, reflect it.
                        guard focusedField != .oscPort, focusRegistry.desiredField(for: nodeId) != .oscPort else {
                            // If LAN poll / graph updates caused a rebuild, re-assert focus.
                            if focusRegistry.desiredField(for: nodeId) == .oscPort {
                                DispatchQueue.main.async { self.focusedField = .oscPort }
                            }
                            return
                        }
                        let s = String(newPort)
                        if oscPortText != s {
                            oscPortText = s
                        }
                    }
                    .onSubmit {
                        if cfg.wrappedValue.useCustomPort {
                            commitOscReceivePort(cfg)
                        }
                        focusRegistry.clearDesiredField(for: nodeId)
                    }

                if !cfg.wrappedValue.useCustomPort {
                    Text("Global: \(oscGlobalPort)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("Address")
                    .font(.caption)
                    .opacity(0.8)

                TextField("/path (optional)", text: $oscAddressText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .oscAddress)
                    .onChange(of: focusedField, initial: false) { _, newValue in
                        guard newValue == .oscAddress else { return }
                        focusRegistry.setDesiredField(.oscAddress, for: nodeId)
                    }
                    .onAppear {
                        if oscAddressText.isEmpty {
                            oscAddressText = cfg.wrappedValue.addressFilter ?? ""
                        }
                    }
                    .onChange(of: cfg.wrappedValue.addressFilter, initial: false) { _, newValue in
                        // If updates happen while we are not editing, keep draft in sync.
                        guard focusedField != .oscAddress else { return }
                        oscAddressText = newValue ?? ""
                    }
                    .onSubmit {
                        commitOscReceiveAddress(cfg)
                        focusRegistry.clearDesiredField(for: nodeId)
                    }

                Spacer(minLength: 0)
            }

            Divider().opacity(0.25)
            // Live receive indicator
            VStack(alignment: .leading, spacing: 6) {
                let isRecent: Bool = {
                    guard let last = lastOSCPacketAt else { return false }
                    return Date().timeIntervalSince(last) < 2.0
                }()

                HStack(spacing: 8) {
                    Circle()
                        .fill(isRecent ? Color.green.opacity(0.85) : Color.white.opacity(0.25))
                        .frame(width: 8, height: 8)

                    Text(isRecent ? "Receiving" : "No recent packets")
                        .font(.caption)
                        .opacity(0.85)

                    Spacer(minLength: 0)

                    Text("Packets: \(oscPacketCount)")
                        .font(.caption)
                        .opacity(0.7)
                }

                Text(lastOSCPacketAt != nil ? "Last: \(lastOSCPacketAt!.formatted(date: .omitted, time: .standard))" : "Last: —")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: focusedField, initial: false) { _, newFocus in
            // If focus left a field we were editing, commit its draft.
            if newFocus != .oscPort, focusRegistry.desiredField(for: nodeId) == .oscPort {
                if cfg.wrappedValue.useCustomPort {
                    commitOscReceivePort(cfg)
                } else {
                    // If not overriding, keep the draft showing the global port.
                    let g = UInt16(max(1, min(65535, oscGlobalPort)))
                    oscPortText = String(g)
                }
                focusRegistry.clearDesiredField(for: nodeId)
            }
            if newFocus != .oscAddress, focusRegistry.desiredField(for: nodeId) == .oscAddress {
                commitOscReceiveAddress(cfg)
                focusRegistry.clearDesiredField(for: nodeId)
            }
        }
    }

    // MARK: - MIDI Receive settings

    private var midiReceiveSettings: some View {
        let cfg = midiReceiveCfg
        return VStack(alignment: .leading, spacing: 10) {
            Text("MIDI Receive")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Listening is controlled globally in Settings → MIDI. These fields only define what this node matches.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(0.85)

            if !midiGlobalEnabled {
                Text("MIDI is currently disabled globally.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("Type")
                    .font(.caption)
                    .opacity(0.8)

                Picker("Type", selection: Binding(
                    get: { cfg.wrappedValue.messageType },
                    set: { newValue in
                        var v = cfg.wrappedValue
                        v.messageType = newValue
                        cfg.wrappedValue = v
                    }
                )) {
                    ForEach(DashboardGraph.MIDIMessageType.allCases, id: \.self) { t in
                        Text(midiTypeLabel(t)).tag(t)
                    }
                }
                .pickerStyle(.menu)

                Spacer(minLength: 0)
            }

            if cfg.wrappedValue.messageType == .programChange {
                HStack(spacing: 10) {
                    Text("Program")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("Any", text: $midiProgramText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .onAppear {
                            if midiProgramText.isEmpty {
                                midiProgramText = cfg.wrappedValue.programFilter.map { String($0) } ?? ""
                            }
                        }
                        .onChange(of: cfg.wrappedValue.programFilter, initial: false) { _, newValue in
                            let next = newValue.map { String($0) } ?? ""
                            if midiProgramText != next { midiProgramText = next }
                        }
                        .onSubmit {
                            commitMidiProgram(cfg)
                        }

                    Spacer(minLength: 0)
                }
            }

            if cfg.wrappedValue.messageType == .noteOn || cfg.wrappedValue.messageType == .noteOff {
                HStack(spacing: 10) {
                    Text("Note")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("Any", text: $midiNoteText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .onAppear {
                            if midiNoteText.isEmpty {
                                midiNoteText = cfg.wrappedValue.noteFilter.map { String($0) } ?? ""
                            }
                        }
                        .onChange(of: cfg.wrappedValue.noteFilter, initial: false) { _, newValue in
                            let next = newValue.map { String($0) } ?? ""
                            if midiNoteText != next { midiNoteText = next }
                        }
                        .onSubmit {
                            commitMidiNote(cfg)
                        }

                    Spacer(minLength: 0)
                }
            }

            if cfg.wrappedValue.messageType == .controlChange {
                HStack(spacing: 10) {
                    Text("CC")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("Number", text: $midiCCNumberText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .onAppear {
                            if midiCCNumberText.isEmpty {
                                midiCCNumberText = cfg.wrappedValue.ccNumberFilter.map { String($0) } ?? ""
                            }
                        }
                        .onChange(of: cfg.wrappedValue.ccNumberFilter, initial: false) { _, newValue in
                            let next = newValue.map { String($0) } ?? ""
                            if midiCCNumberText != next { midiCCNumberText = next }
                        }
                        .onSubmit {
                            commitMidiCCNumber(cfg)
                        }

                    Text("Val")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("Any", text: $midiCCValueText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onAppear {
                            if midiCCValueText.isEmpty {
                                midiCCValueText = cfg.wrappedValue.ccValueFilter.map { String($0) } ?? ""
                            }
                        }
                        .onChange(of: cfg.wrappedValue.ccValueFilter, initial: false) { _, newValue in
                            let next = newValue.map { String($0) } ?? ""
                            if midiCCValueText != next { midiCCValueText = next }
                        }
                        .onSubmit {
                            commitMidiCCValue(cfg)
                        }

                    Spacer(minLength: 0)
                }
            }

            if cfg.wrappedValue.messageType == .sysex {
                HStack(spacing: 10) {
                    Text("SysEx")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("Hex prefix (optional)", text: $midiSysexPrefixText)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            if midiSysexPrefixText.isEmpty {
                                midiSysexPrefixText = cfg.wrappedValue.sysexPrefixHex ?? ""
                            }
                        }
                        .onChange(of: cfg.wrappedValue.sysexPrefixHex, initial: false) { _, newValue in
                            let next = newValue ?? ""
                            if midiSysexPrefixText != next { midiSysexPrefixText = next }
                        }
                        .onSubmit {
                            commitMidiSysexPrefix(cfg)
                        }

                    Spacer(minLength: 0)
                }
            }

            if cfg.wrappedValue.messageType != .sysex {
                HStack(spacing: 10) {
                    Text("Channel")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("Any", text: $midiChannelText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .onAppear {
                            if midiChannelText.isEmpty {
                                midiChannelText = cfg.wrappedValue.channelFilter.map { String($0) } ?? ""
                            }
                        }
                        .onChange(of: cfg.wrappedValue.channelFilter, initial: false) { _, newValue in
                            let next = newValue.map { String($0) } ?? ""
                            if midiChannelText != next { midiChannelText = next }
                        }
                        .onSubmit {
                            commitMidiChannel(cfg)
                        }

                    Spacer(minLength: 0)
                }
            }

            Divider().opacity(0.25)

            VStack(alignment: .leading, spacing: 6) {
                let isRecent: Bool = {
                    guard let last = lastMIDIPacketAt else { return false }
                    return Date().timeIntervalSince(last) < 2.0
                }()

                HStack(spacing: 8) {
                    Circle()
                        .fill(isRecent ? Color.green.opacity(0.85) : Color.white.opacity(0.25))
                        .frame(width: 8, height: 8)

                    Text(isRecent ? "Receiving" : "No recent messages")
                        .font(.caption)
                        .opacity(0.85)

                    Spacer(minLength: 0)

                    Text("Messages: \(midiPacketCount)")
                        .font(.caption)
                        .opacity(0.7)
                }

                Text(lastMIDIPacketAt != nil ? "Last: \(lastMIDIPacketAt!.formatted(date: .omitted, time: .standard))" : "Last: —")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pcoItemChangedSettings: some View {
        let cfg = pcoItemChangedCfg
        let cleanTitles = pcoRundownSnapshotTitles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let selectedFilter = cfg.wrappedValue.titleFilter.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Only fire when plan includes")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if cleanTitles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("No Planning Center plan loaded yet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !selectedFilter.isEmpty {
                        Text("Saved filter: \"\(selectedFilter)\"")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Button("Clear filter") {
                            var v = cfg.wrappedValue
                            v.titleFilter = ""
                            cfg.wrappedValue = v
                        }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    } else {
                        Text("Will fire on any plan update once a plan is loaded.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Picker("", selection: Binding<String>(
                    get: { selectedFilter },
                    set: { var v = cfg.wrappedValue; v.titleFilter = $0; cfg.wrappedValue = v }
                )) {
                    Text("Any plan update").tag("")
                    Divider()
                    ForEach(cleanTitles, id: \.self) { title in
                        Text(title).tag(title)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if !selectedFilter.isEmpty {
                    Text("Fires only when the loaded plan contains \"\(selectedFilter)\".")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Fires whenever the plan is loaded or refreshed in Relay.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Cooldown (s)")
                Spacer()
                TextField("", value: Binding(
                    get: { cfg.wrappedValue.cooldownSeconds },
                    set: { var v = cfg.wrappedValue; v.cooldownSeconds = max(0, $0); cfg.wrappedValue = v }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            }
        }
    }

    private var proPresenterTriggerSettings: some View {
        let cfg = proPresenterTriggerCfg
        let profiles = ProPresenterProfilesStore.loadProfiles()
        let proPresenterGlobal = ProPresenterGlobalConnectionSettings.loadFromAppStorage()
        let showMissingProfilesWarning = profiles.isEmpty && !proPresenterGlobal.isValid

        return VStack(alignment: .leading, spacing: 10) {
            if showMissingProfilesWarning {
                warningPill(text: "No ProPresenter connections configured. Add one in Settings before this trigger can fire.")
            }

            HStack(spacing: 10) {
                Text("Event")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                Picker("", selection: Binding<DashboardGraph.ProPresenterTriggerEvent>(
                    get: { cfg.wrappedValue.event },
                    set: { var v = cfg.wrappedValue; v.event = $0; cfg.wrappedValue = v }
                )) {
                    ForEach(DashboardGraph.ProPresenterTriggerEvent.allCases, id: \.self) { event in
                        Text(event.displayName).tag(event)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Text("Profile")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                Picker("", selection: Binding<UUID?>(
                    get: { cfg.wrappedValue.profileId },
                    set: { var v = cfg.wrappedValue; v.profileId = $0; cfg.wrappedValue = v }
                )) {
                    Text("Active / Global").tag(UUID?.none)
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Text("Filter")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                StableGraphTextField(
                    "Any change",
                    text: Binding<String>(
                        get: { cfg.wrappedValue.filter },
                        set: { var v = cfg.wrappedValue; v.filter = $0; cfg.wrappedValue = v }
                    )
                )
            }

            HStack {
                Text("Cooldown (s)")
                Spacer()
                TextField("", value: Binding(
                    get: { cfg.wrappedValue.cooldownSeconds },
                    set: { var v = cfg.wrappedValue; v.cooldownSeconds = max(0, $0); cfg.wrappedValue = v }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            }

            Text("Leave Filter empty to fire on any change for the selected event, or enter an exact value (slide label, presentation name, message name, or timer name) to only fire for that specific one.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var appStateSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Event", selection: Binding(
                get: { appStateCfg.wrappedValue.eventKind },
                set: { var v = appStateCfg.wrappedValue; v.eventKind = $0; appStateCfg.wrappedValue = v }
            )) {
                ForEach(DashboardGraph.AppStateTriggerConfig.EventKind.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Cooldown (s)")
                Spacer()
                TextField("", value: Binding(
                    get: { appStateCfg.wrappedValue.cooldownSeconds },
                    set: { var v = appStateCfg.wrappedValue; v.cooldownSeconds = max(0, $0); appStateCfg.wrappedValue = v }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            }
        }
    }
}



/// Shared focus registry so fields keep focus even if the node view is recreated by LAN polling.
private final class TriggerNodeFocusRegistry: ObservableObject {
    static let shared = TriggerNodeFocusRegistry()

    @Published private var desiredByNodeId: [UUID: TriggerNodeFocusField] = [:]

    func desiredField(for nodeId: UUID) -> TriggerNodeFocusField? {
        desiredByNodeId[nodeId]
    }

    func setDesiredField(_ field: TriggerNodeFocusField, for nodeId: UUID) {
        desiredByNodeId[nodeId] = field
    }

    func clearDesiredField(for nodeId: UUID) {
        desiredByNodeId.removeValue(forKey: nodeId)
    }
}

// MARK: - Shure trigger settings

private struct ShureWirelessTriggerSettings: View {
    @Binding var config: DashboardGraph.WirelessTriggerConfig

    private var service: ShureWirelessService {
        ShureWirelessService.shared(for: config.deviceID)
    }

    private var availableChannels: [Int] {
        let channels = service.standardReportChannelIndices()
        let s = Set(channels)
        if s.isEmpty {
            return Array(1...16)
        }
        return s.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shure Wireless")
                .font(.caption2)
                .foregroundStyle(.secondary)

            devicePicker
            channelPicker

            Divider().opacity(0.25)

            liveReadouts

            Divider().opacity(0.25)

            triggerControls(isShure: true)
        }
    }

    private var devicePicker: some View {
        HStack(spacing: 10) {
            Text("Device")
                .font(.caption)
                .opacity(0.8)

            let devices = ExternalDevicesStore.shared.devices.filter { $0.kind == .shureWireless }

            Picker("Device", selection: Binding<UUID?>(
                get: { config.deviceID },
                set: { newValue in
                    config.deviceID = newValue
                    // Reset channel when device changes.
                    config.channelIndex = nil
                }
            )) {
                Text("Select…").tag(UUID?.none)
                // `devices` is a `let` snapshot filtered fresh above, read-only for
                // the rest of this render pass — index identity can't drift mid-render.
                ForEach(devices.indices, id: \.self) { idx in
                    let d = devices[idx]
                    Text(d.name).tag(UUID?.some(d.id))
                }
            }
            .pickerStyle(.menu)

            Spacer(minLength: 0)
        }
    }

    private var channelPicker: some View {
        HStack(spacing: 10) {
            Text("Channel")
                .font(.caption)
                .opacity(0.8)

            Picker("Channel", selection: Binding<Int?>(
                get: { config.channelIndex },
                set: { config.channelIndex = $0 }
            )) {
                Text("Select…").tag(Int?.none)
                ForEach(availableChannels, id: \.self) { ch in
                    let label = service.standardReportChannelName(for: ch) ?? "CH \(ch)"
                    Text(label).tag(Int?.some(ch))
                }
            }
            .pickerStyle(.menu)

            Spacer(minLength: 0)
        }
    }

    private var liveReadouts: some View {
        Group {
            let ch = config.channelIndex
            let connected = service.isConnected

            let batteryPct = ch.flatMap { service.standardReportBatteryPercentage(for: $0) }
            let rfBars = ch.flatMap { service.standardReportRfBarCount(for: $0) }
            let audio = ch.flatMap { service.liveAudioLevel(for: $0) }

            VStack(alignment: .leading, spacing: 6) {
                metricRow(label: "Connected", value: connected ? "Yes" : "No")
                metricRow(label: "Battery", value: batteryPct != nil ? "\(batteryPct!)%" : (ch.flatMap { service.standardReportBatteryLabel(for: $0) } ?? "—"))
                metricRow(label: "RF", value: rfBars != nil ? "\(rfBars!)/5" : "—")
                metricRow(label: "Audio", value: audio != nil ? String(format: "%.2f", audio!) : "—")
            }
        }
    }

    @ViewBuilder
    private func triggerControls(isShure: Bool) -> some View {
        HStack(spacing: 10) {
            Text("Trigger")
                .font(.caption)
                .opacity(0.8)

            Picker("Trigger", selection: $config.triggerKind) {
                ForEach(DashboardGraph.WirelessTriggerConfig.TriggerKind.allCases, id: \.self) { k in
                    Text(displayName(for: k)).tag(k)
                }
            }
            .pickerStyle(.menu)

            Spacer(minLength: 0)
        }

        if needsThreshold(config.triggerKind) {
            thresholdRow(isShure: isShure)
        } else {
            Text(config.triggerKind == .audioClip ? "Fires when a clip is detected." : "Fires when device disconnects.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 10) {
            Text("Cooldown")
                .font(.caption)
                .opacity(0.8)

            TextField("Seconds", value: $config.cooldownSeconds, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Text("sec")
                .font(.caption)
                .opacity(0.8)

            Spacer(minLength: 0)
        }
    }

    private func thresholdRow(isShure: Bool) -> some View {
        HStack(spacing: 10) {
            Text("Threshold")
                .font(.caption)
                .opacity(0.8)

            switch config.triggerKind {
            case .batteryBelow:
                Stepper(value: $config.threshold, in: 0...100, step: 1) {
                    Text("\(Int(config.threshold))%")
                        .font(.caption)
                        .opacity(0.85)
                }

            case .rfBelow:
                // Shure uses 0-5 bars.
                Stepper(value: $config.threshold, in: 0...5, step: 1) {
                    Text("\(Int(config.threshold))/5")
                        .font(.caption)
                        .opacity(0.85)
                }

            case .audioClip:
                TextField("Value", value: $config.threshold, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Text("level")
                    .font(.caption)
                    .opacity(0.8)

            case .disconnected:
                EmptyView()
            }

            Spacer(minLength: 0)
        }
    }

    private func displayName(for kind: DashboardGraph.WirelessTriggerConfig.TriggerKind) -> String {
        switch kind {
        case .batteryBelow: return "Battery below"
        case .rfBelow: return "RF below"
        case .audioClip: return "Audio clip"
        case .disconnected: return "Disconnected"
        }
    }

    private func needsThreshold(_ kind: DashboardGraph.WirelessTriggerConfig.TriggerKind) -> Bool {
        switch kind {
        case .batteryBelow, .rfBelow:
            return true
        case .audioClip, .disconnected:
            return false
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .opacity(0.8)
                .frame(width: 90, alignment: .leading)

            Text(value)
                .font(.caption)
                .opacity(0.85)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sennheiser trigger settings

private struct SennheiserWirelessTriggerSettings: View {
    @Binding var config: DashboardGraph.WirelessTriggerConfig

    @ObservedObject private var service = SennheiserWirelessService.shared

    private var availableChannels: [Int] {
        guard let did = config.deviceID else { return Array(1...16) }
        let chans = service.channelsByDevice[did]?.map { $0.channelIndex } ?? []
        return chans.isEmpty ? Array(1...16) : chans.sorted()
    }

    private var snapshot: SennheiserChannelSnapshot? {
        guard let did = config.deviceID, let ch = config.channelIndex else { return nil }
        return service.channelsByDevice[did]?.first(where: { $0.channelIndex == ch })
    }

    private var isConnected: Bool {
        guard let did = config.deviceID else { return false }
        return service.connectionStateByDevice[did] == .connected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sennheiser Wireless")
                .font(.caption2)
                .foregroundStyle(.secondary)

            devicePicker
            channelPicker

            Divider().opacity(0.25)

            liveReadouts

            Divider().opacity(0.25)

            triggerControls
        }
    }

    private var devicePicker: some View {
        HStack(spacing: 10) {
            Text("Device")
                .font(.caption)
                .opacity(0.8)

            let devices = ExternalDevicesStore.shared.devices.filter { $0.kind == .sennheiserWireless }

            Picker("Device", selection: Binding<UUID?>(
                get: { config.deviceID },
                set: { newValue in
                    config.deviceID = newValue
                    config.channelIndex = nil
                }
            )) {
                Text("Select…").tag(UUID?.none)
                // `devices` is a `let` snapshot filtered fresh above, read-only for
                // the rest of this render pass — index identity can't drift mid-render.
                ForEach(devices.indices, id: \.self) { idx in
                    let d = devices[idx]
                    Text(d.name).tag(UUID?.some(d.id))
                }
            }
            .pickerStyle(.menu)

            Spacer(minLength: 0)
        }
    }

    private var channelPicker: some View {
        HStack(spacing: 10) {
            Text("Channel")
                .font(.caption)
                .opacity(0.8)

            Picker("Channel", selection: Binding<Int?>(
                get: { config.channelIndex },
                set: { config.channelIndex = $0 }
            )) {
                Text("Select…").tag(Int?.none)
                ForEach(availableChannels, id: \.self) { ch in
                    let did = config.deviceID
                    let name = did.flatMap { service.channelsByDevice[$0]?.first(where: { $0.channelIndex == ch })?.channelName }
                    Text(name ?? "CH \(ch)").tag(Int?.some(ch))
                }
            }
            .pickerStyle(.menu)

            Spacer(minLength: 0)
        }
    }

    private var liveReadouts: some View {
        VStack(alignment: .leading, spacing: 6) {
            metricRow(label: "Connected", value: isConnected ? "Yes" : "No")
            metricRow(label: "Battery", value: snapshot?.batteryPercent != nil ? "\(snapshot!.batteryPercent!)%" : "—")
            metricRow(label: "RF", value: snapshot?.rfLevel01 != nil ? String(format: "%.2f", snapshot!.rfLevel01!) : "—")
            metricRow(label: "Audio", value: snapshot?.audioLevel01 != nil ? String(format: "%.2f", snapshot!.audioLevel01!) : "—")
        }
    }

    private var triggerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Trigger")
                    .font(.caption)
                    .opacity(0.8)

                Picker("Trigger", selection: $config.triggerKind) {
                    ForEach(DashboardGraph.WirelessTriggerConfig.TriggerKind.allCases, id: \.self) { k in
                        Text(displayName(for: k)).tag(k)
                    }
                }
                .pickerStyle(.menu)

                Spacer(minLength: 0)
            }

            if needsThreshold(config.triggerKind) {
                thresholdRow
            } else {
                Text(config.triggerKind == .audioClip ? "Fires when a clip is detected." : "Fires when device disconnects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("Cooldown")
                    .font(.caption)
                    .opacity(0.8)

                TextField("Seconds", value: $config.cooldownSeconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Text("sec")
                    .font(.caption)
                    .opacity(0.8)

                Spacer(minLength: 0)
            }
        }
    }

    private var thresholdRow: some View {
        HStack(spacing: 10) {
            Text("Threshold")
                .font(.caption)
                .opacity(0.8)

            switch config.triggerKind {
            case .batteryBelow:
                Stepper(value: $config.threshold, in: 0...100, step: 1) {
                    Text("\(Int(config.threshold))%")
                        .font(.caption)
                        .opacity(0.85)
                }

            case .rfBelow:
                // Sennheiser RF is normalized 0..1.
                Stepper(value: $config.threshold, in: 0...1, step: 0.05) {
                    Text(String(format: "%.2f", config.threshold))
                        .font(.caption)
                        .opacity(0.85)
                }

            case .audioClip:
                Stepper(value: $config.threshold, in: 0...1, step: 0.05) {
                    Text(String(format: "%.2f", config.threshold))
                        .font(.caption)
                        .opacity(0.85)
                }

            case .disconnected:
                EmptyView()
            }

            Spacer(minLength: 0)
        }
    }

    private func displayName(for kind: DashboardGraph.WirelessTriggerConfig.TriggerKind) -> String {
        switch kind {
        case .batteryBelow: return "Battery below"
        case .rfBelow: return "RF below"
        case .audioClip: return "Audio clip"
        case .disconnected: return "Disconnected"
        }
    }

    private func needsThreshold(_ kind: DashboardGraph.WirelessTriggerConfig.TriggerKind) -> Bool {
        switch kind {
        case .batteryBelow, .rfBelow, .audioClip:
            return true
        case .disconnected:
            return false
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .opacity(0.8)
                .frame(width: 90, alignment: .leading)

            Text(value)
                .font(.caption)
                .opacity(0.85)

            Spacer(minLength: 0)
        }
    }
}
