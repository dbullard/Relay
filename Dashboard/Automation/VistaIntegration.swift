import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct VistaPCORundownItem: Codable, Equatable {
    var title: String
    var itemType: String?
    var keyName: String?
    var arrangementTitle: String?
    var songTitle: String?
    var itemNotes: String?
    var serviceTypeName: String?
    var planTitle: String?
    var serviceDateLabel: String?
    var serviceTimeName: String?
    var timecode: String?
}

enum VistaPCORundownPayloadCodec {
    private static let marker = "__RELAY_PCO_VISTA__:"

    static func encode(_ item: VistaPCORundownItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = try? JSONEncoder().encode(item) else { return title }
        return title + "\n" + marker + data.base64EncodedString()
    }

    static func decode(from raw: String) -> VistaPCORundownItem? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let markerRange = trimmed.range(of: "\n" + marker) {
            let title = String(trimmed[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let encoded = String(trimmed[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: encoded),
               var payload = try? JSONDecoder().decode(VistaPCORundownItem.self, from: data) {
                if payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    payload.title = title
                }
                return payload
            }
            return VistaPCORundownItem(title: title)
        }

        if let keyRange = trimmed.range(of: "\n__KEY__:") {
            let title = String(trimmed[..<keyRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = String(trimmed[keyRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return VistaPCORundownItem(
                title: title,
                itemType: nil,
                keyName: key.isEmpty ? nil : key,
                arrangementTitle: nil,
                songTitle: nil,
                itemNotes: nil,
                serviceTypeName: nil,
                planTitle: nil,
                serviceDateLabel: nil,
                serviceTimeName: nil,
                timecode: nil
            )
        }

        return VistaPCORundownItem(title: trimmed)
    }
}

struct VistaCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var csvText: String

    init(csvText: String) {
        self.csvText = csvText
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            self.csvText = string
        } else {
            self.csvText = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csvText.utf8))
    }
}

enum VistaCSVBuilder {
    static let headers = [
        "Cuelist ID",
        "Cuelist Label",
        "ID",
        "Label",
        "Notes",
        "Timecode"
    ]

    struct Cue: Identifiable, Equatable {
        let id: Int
        let label: String
        let notes: String
        let timecode: String
    }

    static func defaultCuelistLabel(from items: [VistaPCORundownItem]) -> String {
        let first = items.first
        let serviceType = first?.serviceTypeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let serviceDate = first?.serviceDateLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !serviceType.isEmpty && !serviceDate.isEmpty {
            return "\(serviceType) - \(serviceDate)"
        }
        if !serviceType.isEmpty {
            return serviceType
        }
        if !serviceDate.isEmpty {
            return serviceDate
        }
        return "Relay Generated Service"
    }

    static func cues(from items: [VistaPCORundownItem]) -> [Cue] {
        items.enumerated().map { index, item in
            Cue(
                id: index + 1,
                label: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Cue" : item.title,
                notes: buildNotes(for: item),
                timecode: item.timecode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
    }

    static func csvString(config: DashboardGraph.VistaNodeConfig, items: [VistaPCORundownItem]) -> String {
        let cuelistID = normalizedCuelistID(from: config.cuelistID)
        let cuelistLabel = normalizedCuelistLabel(from: config.cuelistLabel, items: items)

        var lines = [headers.joined(separator: ",")]
        for cue in cues(from: items) {
            let values = [
                cuelistID,
                cuelistLabel,
                String(cue.id),
                cue.label,
                cue.notes,
                cue.timecode
            ]
            lines.append(values.map(escapeCSVField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func defaultFilename(config: DashboardGraph.VistaNodeConfig, items: [VistaPCORundownItem]) -> String {
        let label = normalizedCuelistLabel(from: config.cuelistLabel, items: items)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "Vista-\(label).csv"
    }

    private static func normalizedCuelistID(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "900" : trimmed
    }

    private static func normalizedCuelistLabel(from raw: String, items: [VistaPCORundownItem]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultCuelistLabel(from: items) : trimmed
    }

    private static func buildNotes(for item: VistaPCORundownItem) -> String {
        var parts: [String] = []

        if let itemType = item.itemType?.trimmingCharacters(in: .whitespacesAndNewlines), !itemType.isEmpty {
            parts.append(itemType.capitalized)
        }
        if let arrangement = item.arrangementTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !arrangement.isEmpty {
            parts.append(arrangement)
        } else if let song = item.songTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !song.isEmpty {
            parts.append(song)
        }
        if let notes = item.itemNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(notes)
        }
        if let key = item.keyName?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            parts.append("Key: \(key)")
        }

        return parts.isEmpty ? "Generated by Relay" : parts.joined(separator: " • ")
    }

    private nonisolated static func escapeCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

enum VistaOSCCommandSender {
    private static let buttonPulseDurationNanoseconds: UInt64 = 120_000_000

    static func normalizedTargetPath(_ rawTarget: String) -> String {
        let raw = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if raw.hasPrefix("EX") {
            let suffix = raw.dropFirst(2)
            if !suffix.isEmpty {
                return "EX/\(suffix)"
            }
        }
        return raw.isEmpty ? "EX/1" : raw
    }

    @MainActor
    static func resolvedDevice(
        for config: DashboardGraph.VistaNodeConfig,
        devices: [ExternalDeviceConfig]? = nil
    ) -> ExternalDeviceConfig? {
        guard let selectedDeviceID = config.selectedDeviceID else { return nil }
        let resolvedDevices = devices ?? ExternalDevicesStore.shared.devices
        return resolvedDevices.first(where: { $0.id == selectedDeviceID && $0.kind == .vistaConsole })
    }

    static func address(
        for command: DashboardGraph.VistaNodeConfig.CommandKind,
        targetPath: String
    ) -> String {
        switch command {
        case .play:
            return "/V3/console/\(targetPath)/spbPlay"
        case .back:
            return "/V3/console/\(targetPath)/spbPlayBack"
        case .skipForward:
            return "/V3/console/\(targetPath)/spbSkipForward"
        case .skipBack:
            return "/V3/console/\(targetPath)/spbSkipBack"
        case .gmFader:
            return "/V3/console/\(targetPath)/gmFader"
        }
    }

    static func args(
        for config: DashboardGraph.VistaNodeConfig,
        payload: GraphTriggerPayload? = nil
    ) -> [OSCValue] {
        switch config.commandKind {
        case .play, .back, .skipForward, .skipBack:
            return [.bool(true)]
        case .gmFader:
            let payloadValue = payload?.number
                ?? payload?.text.flatMap(Double.init)
            let value = min(1.0, max(0.0, payloadValue ?? config.gmFaderValue))
            return [.float32(Float(value))]
        }
    }

    static func isMomentaryCommand(_ command: DashboardGraph.VistaNodeConfig.CommandKind) -> Bool {
        switch command {
        case .play, .back, .skipForward, .skipBack:
            return true
        case .gmFader:
            return false
        }
    }

    @MainActor
    static func send(
        config: DashboardGraph.VistaNodeConfig,
        payload: GraphTriggerPayload? = nil,
        source: String,
        nodeId: UUID? = nil
    ) {
        let device = resolvedDevice(for: config)
        let host = (device?.host ?? config.externalDeviceConfig.host)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let port = device?.port ?? config.externalDeviceConfig.oscPort
        let rawTarget = (device?.vistaConsoleTarget ?? config.externalDeviceConfig.consoleTarget)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPath = normalizedTargetPath(rawTarget)

        guard !host.isEmpty, port != 0 else {
            print("[Vista] send skipped source=\(source) nodeId=\(nodeId?.uuidString ?? "nil") reason=invalid_endpoint host=\(host) port=\(port)")
            return
        }

        let address = address(for: config.commandKind, targetPath: targetPath)
        let args = args(for: config, payload: payload)
        let argsSummary = args.map(\.debugDescription).joined(separator: ",")
        print("[Vista] send source=\(source) nodeId=\(nodeId?.uuidString ?? "nil") host=\(host) port=\(port) address=\(address) args=[\(argsSummary)]")
        let endpoint = OSCEndpoint(host: host, port: port)
        OSCManager.shared.send(
            to: endpoint,
            message: OSCMessage(address: address, args: args)
        )

        guard isMomentaryCommand(config.commandKind) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: buttonPulseDurationNanoseconds)
            let releaseArgs: [OSCValue] = [.bool(false)]
            let releaseSummary = releaseArgs.map(\.debugDescription).joined(separator: ",")
            print("[Vista] send source=\(source)_release nodeId=\(nodeId?.uuidString ?? "nil") host=\(host) port=\(port) address=\(address) args=[\(releaseSummary)]")
            OSCManager.shared.send(
                to: endpoint,
                message: OSCMessage(address: address, args: releaseArgs)
            )
        }
    }
}
