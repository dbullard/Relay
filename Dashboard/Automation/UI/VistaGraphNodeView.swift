import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct VistaGraphNodeView: View {
    let nodeId: UUID
    @Binding var config: DashboardGraph.VistaNodeConfig
    let device: ExternalDeviceConfig?
    let linkedItems: [VistaPCORundownItem]
    let showTriggerControls: Bool
    let isSelected: Bool

    @AppStorage("relay.vistaImportInstructionsSuppressed")
    private var suppressImportInstructions = false
    @State private var isExporting = false
    @State private var exportDocument = VistaCSVDocument(csvText: "")
    @State private var exportErrorMessage: String?
    @State private var showImportInstructions = false

    private var destinationCategory: GraphNodeCategory { .destinations }

    private var cues: [VistaCSVBuilder.Cue] {
        VistaCSVBuilder.cues(from: linkedItems)
    }

    private var selectedTargetName: String {
        let trimmed = device?.vistaConsoleTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? config.externalDeviceConfig.consoleTarget : trimmed
    }

    private var normalizedTargetPath: String {
        let raw = selectedTargetName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if raw.hasPrefix("EX") {
            let suffix = raw.dropFirst(2)
            if !suffix.isEmpty {
                return "EX/\(suffix)"
            }
        }
        return raw.isEmpty ? "EX/1" : raw
    }

    private var commandPreviewAddress: String {
        let target = normalizedTargetPath
        switch config.commandKind {
        case .play:
            return "/V3/console/\(target)/spbPlay true"
        case .back:
            return "/V3/console/\(target)/spbPlayBack true"
        case .skipForward:
            return "/V3/console/\(target)/spbSkipForward true"
        case .skipBack:
            return "/V3/console/\(target)/spbSkipBack true"
        case .gmFader:
            return String(format: "/V3/console/%@/gmFader %.2f", target, config.gmFaderValue)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "light.beacon.max")
                    .imageScale(.medium)
                    .opacity(0.9)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                    Text(device?.name.isEmpty == false ? (device?.name ?? "Vista") : "Vista")
                        .font(.headline)
                            .lineLimit(1)

                        Text("DESTINATION")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(destinationCategory.badgeColor))
                            .foregroundStyle(.secondary)

                        if isVistaIntegrationEnabled {
                            Text("BETA")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.22)))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(deviceSummaryText)
                        .font(.caption)
                        .opacity(0.7)
                        .lineLimit(1)
                }

                Spacer()
            }

            Divider().opacity(0.25)

            if linkedItems.isEmpty {
                Text("Connect a Planning Center rundown node to export Vista cues.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Cue List")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Cue List #")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("900", text: $config.cuelistID)
                    .textFieldStyle(.roundedBorder)

                Text("Cuelist Label")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField(VistaCSVBuilder.defaultCuelistLabel(from: linkedItems), text: $config.cuelistLabel)
                    .textFieldStyle(.roundedBorder)
            }

            if showTriggerControls {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("OSC Control")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Run") {
                            runCurrentCommand()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(device == nil)
                    }

                    if let device {
                        Text("\(device.host):\(device.port) • \(normalizedTargetPath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Vista device configuration is missing.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Command", selection: $config.commandKind) {
                        ForEach(DashboardGraph.VistaNodeConfig.CommandKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if config.commandKind == .gmFader {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("GM Fader")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f", config.gmFaderValue))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Slider(value: $config.gmFaderValue, in: 0...1)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Example OSC")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(commandPreviewAddress)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
            } else {
                Text("Connect a trigger node to this Vista destination to enable OSC commands.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Export CSV") {
                exportCSV()
            }
            .buttonStyle(.borderedProminent)
            .disabled(linkedItems.isEmpty)

            if let exportErrorMessage, !exportErrorMessage.isEmpty {
                Text(exportErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !cues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(cues.prefix(8)) { cue in
                        Text("\(cue.id). \(cue.label)")
                            .font(.subheadline)
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                    if cues.count > 8 {
                        Text("+ \(cues.count - 8) more…")
                            .font(.caption)
                            .opacity(0.6)
                    }
                }
            }

            Text("CSV export works without device configuration. OSC control appears when a trigger is linked to this Vista destination.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(receiverTintBackground)
        .overlay(
            receiverTintBorder
        )
        .sheet(isPresented: $showImportInstructions) {
            VistaImportInstructionsSheet(
                suppressImportInstructions: $suppressImportInstructions
            )
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: VistaCSVBuilder.defaultFilename(config: config, items: linkedItems)
        ) { result in
            switch result {
            case .success:
                presentImportInstructionsIfNeeded()
            case .failure(let error):
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private var receiverTintBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(Color.white.opacity(isSelected ? 0.09 : 0.08))
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(destinationCategory.tintColor)
                .blendMode(.screen)
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                .fill(Color.white.opacity(GraphNodeStyleTokens.highlightFillOpacity))
        }
    }

    private var receiverTintBorder: some View {
        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
            .stroke(destinationCategory.borderColor, lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
    }

    private func exportCSV() {
        exportErrorMessage = nil
        let csvText = VistaCSVBuilder.csvString(config: config, items: linkedItems)

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = VistaCSVBuilder.defaultFilename(config: config, items: linkedItems)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csvText.write(to: url, atomically: true, encoding: .utf8)
                presentImportInstructionsIfNeeded()
            } catch {
                exportErrorMessage = error.localizedDescription
            }
        }
        #else
        exportDocument = VistaCSVDocument(csvText: csvText)
        isExporting = true
        #endif
    }

    private func presentImportInstructionsIfNeeded() {
        guard !suppressImportInstructions else { return }
        showImportInstructions = true
    }

    private var deviceSummaryText: String {
        let cueSummary = "\(cues.count) cue\(cues.count == 1 ? "" : "s") ready"
        guard let device else { return cueSummary }
        return "\(cueSummary) • \(device.host):\(device.port)"
    }

    private func runCurrentCommand() {
        VistaOSCCommandSender.send(
            config: config,
            source: "manual_test",
            nodeId: nodeId
        )
    }
}

private struct VistaImportInstructionsSheet: View {
    @Binding var suppressImportInstructions: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var doNotShowAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Into Vista")
                .font(.title3)
                .fontWeight(.semibold)

            Text("In Vista, import the CSV with File > Import, then confirm these settings before starting the import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("1. Set Import to Cuelist to From Data unless you intentionally want to overwrite the currently selected cuelist.")
                Text("2. Match Cuelists by ID.")
                Text("3. Leave Create missing Cuelists checked.")
                Text("4. Match Cues by ID.")
            }
            .font(.subheadline)

            Toggle("Do not show this again", isOn: $doNotShowAgain)
#if os(macOS)
                .toggleStyle(.checkbox)
#endif

            HStack {
                Spacer()
                Button("Close") {
                    if doNotShowAgain {
                        suppressImportInstructions = true
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
