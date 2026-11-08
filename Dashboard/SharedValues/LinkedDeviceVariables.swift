import Foundation
import Observation

enum LinkedDeviceVariableKind: String, Codable, CaseIterable, Sendable {
    case clock, computers, integrations, planningCenter, consoles, proPresenter, transcription, rosters
    case wireless, osc, automation, computed, manual, people, other

    init(binding: SharedValueBinding) {
        switch binding {
        case .manual: self = .manual
        case .computed: self = .computed
        case .shure, .sennheiser: self = .wireless
        case .osc: self = .osc
        case .triggerPayload: self = .automation
        case let .system(key):
            switch key.split(separator: ":").first {
            case "clock": self = .clock
            case "computer": self = .computers
            case "integration": self = .integrations
            case "planningcenter": self = .planningCenter
            case "console": self = .consoles
            case "propresenter": self = .proPresenter
            case "transcription": self = .transcription
            case "roster": self = .rosters
            default: self = .other
            }
        }
    }

    static func legacyKind(for name: String, among names: Set<String>) -> Self {
        let prefixes: [(String, Self)] = [
            ("clock_", .clock), ("computer_", .computers), ("integration_", .integrations),
            ("planning_center_", .planningCenter),
            ("console_", .consoles), ("propresenter_", .proPresenter),
            ("transcription_", .transcription), ("roster_", .rosters),
            ("person_", .people), ("osc_", .osc), ("trigger_", .automation)
        ]
        if let match = prefixes.first(where: { name.hasPrefix($0.0) }) { return match.1 }
        if name.hasSuffix("_battery") || name.hasSuffix("_rf") { return .wireless }
        for suffix in ["_audio", "_connected"] where name.hasSuffix(suffix) {
            let channel = String(name.dropLast(suffix.count))
            if names.contains(channel + "_battery") || names.contains(channel + "_rf") ||
                names.contains(channel + (suffix == "_audio" ? "_connected" : "_audio")) {
                return .wireless
            }
        }
        return .other
    }

    var title: String {
        switch self {
        case .clock: "Clock"
        case .computers: "Computers"
        case .integrations: "Integrations"
        case .planningCenter: "Planning Center"
        case .consoles: "Consoles"
        case .proPresenter: "ProPresenter"
        case .transcription: "Transcription"
        case .rosters: "Rosters"
        case .wireless: "Wireless"
        case .osc: "OSC"
        case .automation: "Automation"
        case .computed: "Computed"
        case .manual: "Manual"
        case .people: "People"
        case .other: "Other"
        }
    }
}

/// A value-only wire format. Bindings, credentials, and values received from peers never leave this device.
struct LinkedDeviceVariable: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let payload: SharedValuePayload?
    let status: SharedValueStatus
    let updatedAt: Date?
    /// A display category only. The source binding stays on the owning computer.
    let kind: LinkedDeviceVariableKind?

    init(id: UUID, name: String, payload: SharedValuePayload?, status: SharedValueStatus, updatedAt: Date?, kind: LinkedDeviceVariableKind? = nil) {
        self.id = id
        self.name = name
        self.payload = payload
        self.status = status
        self.updatedAt = updatedAt
        self.kind = kind
    }

    init(_ value: SharedValue) {
        id = value.id
        name = value.name
        payload = value.payload
        status = value.status
        updatedAt = value.lastUpdatedAt
        kind = LinkedDeviceVariableKind(binding: value.binding)
    }

    static func categorized(_ values: [Self]) -> [Self] {
        let names = Set(values.map(\.name))
        return values.map { value in
            guard value.kind == nil else { return value }
            return Self(id: value.id, name: value.name, payload: value.payload, status: value.status,
                        updatedAt: value.updatedAt, kind: .legacyKind(for: value.name, among: names))
        }
    }
}

enum LinkedDeviceVariableSnapshot {
    static func outbound(from values: [SharedValue], localTabIDs: Set<UUID>, people: [LinkedDeviceVariable] = []) -> [LinkedDeviceVariable] {
        (values.compactMap { value in
            if case let .system(key) = value.binding {
                if key.hasPrefix("computer:") { return nil }
                if key.hasPrefix("roster:") || key.hasPrefix("planningcenter:") {
                    let parts = key.split(separator: ":")
                    guard parts.count > 1, let tabID = UUID(uuidString: String(parts[1])), localTabIDs.contains(tabID) else { return nil }
                }
            }
            return LinkedDeviceVariable(value)
        } + people)
        .filter { $0.name.utf8.count <= 128 && ($0.payload?.displayValue.utf8.count ?? 0) <= 16_384 }
        .prefix(2_000)
        .map { $0 }
    }

    static func localPeople(in tabs: [DashboardTab]) -> [LinkedDeviceVariable] {
        var found: [UUID: LinkedDeviceVariable] = [:]
        for tab in tabs where tab.syncGroupID == nil || tab.syncIsOwner {
            for tile in tab.tiles {
                let modules: [DashboardModuleModel]
                if let existing = tile.modules { modules = existing }
                else if case .person(let model) = tile.kind { modules = [DashboardModuleModel(kind: .person(model), order: 0, id: tile.id)] }
                else { modules = [] }
                for module in modules {
                    guard case .person(let person) = module.kind else { continue }
                    let name = tab.resolvedPersonModel(person).name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, name.lowercased() != "person" else { continue }
                    found[module.id] = LinkedDeviceVariable(
                        id: module.id,
                        name: normalizeSharedValueName("person_\(name)_\(module.id.uuidString.prefix(8))"),
                        payload: .text(name), status: .live, updatedAt: nil, kind: .people
                    )
                }
            }
        }
        return Array(found.values)
    }
}

enum SyncedTabVariableSnapshot {
    static func referenced(in exportedTabJSON: Data, values: [SharedValue]) -> [LinkedDeviceVariable] {
        guard let text = String(data: exportedTabJSON, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"#\{(?:shared:)?([a-zA-Z0-9_]+)(?:\.[^}]*)?\}"#) else { return [] }
        let byName = Dictionary(values.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var names = Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return normalizeSharedValueName(String(text[range]))
        })
        var pending = Array(names)
        while let name = pending.popLast() {
            guard let value = byName[name], case let .computed(expression, _) = value.binding else { continue }
            for match in regex.matches(in: expression, range: NSRange(expression.startIndex..., in: expression)) {
                guard let range = Range(match.range(at: 1), in: expression) else { continue }
                let dependency = normalizeSharedValueName(String(expression[range]))
                if names.insert(dependency).inserted { pending.append(dependency) }
            }
        }
        return names.compactMap { byName[$0].map(LinkedDeviceVariable.init) }
            .filter { $0.name.utf8.count <= 128 && ($0.payload?.displayValue.utf8.count ?? 0) <= 16_384 }
            .sorted { $0.name < $1.name }
            .prefix(500).map { $0 }
    }
}

struct LinkedDeviceVariableEntry: Identifiable, Equatable {
    let deviceID: String
    let deviceName: String
    let value: LinkedDeviceVariable
    var isDisconnected: Bool

    var id: String { "\(deviceID):\(value.id.uuidString)" }
    var tokenName: String { "linked_\(normalizeSharedValueName(deviceID))_\(value.name)" }
    var status: SharedValueStatus { isDisconnected ? .disconnected : value.status }
}

@MainActor @Observable
final class LinkedDeviceVariableStore {
    static let shared = LinkedDeviceVariableStore()
    private(set) var entries: [LinkedDeviceVariableEntry] = []

    func receive(_ values: [LinkedDeviceVariable], deviceID: String, deviceName: String) {
        entries.removeAll { $0.deviceID == deviceID }
        entries.append(contentsOf: LinkedDeviceVariable.categorized(values).map {
            LinkedDeviceVariableEntry(deviceID: deviceID, deviceName: deviceName, value: $0, isDisconnected: false)
        })
        entries.sort { $0.tokenName < $1.tokenName }
    }

    func disconnected(deviceID: String) {
        for index in entries.indices where entries[index].deviceID == deviceID {
            entries[index].isDisconnected = true
        }
    }

    func clear(deviceID: String) { entries.removeAll { $0.deviceID == deviceID } }
    func clearAll() { entries.removeAll() }

    func payload(named name: String) -> SharedValuePayload? {
        return entries.first { $0.tokenName == normalizeSharedValueName(name) }?.value.payload
    }
}

struct SyncedTabVariableEntry: Identifiable, Equatable {
    let groupID: String
    let tabName: String
    let deviceName: String
    let value: LinkedDeviceVariable
    var isDisconnected: Bool

    var id: String { "\(groupID):\(value.id.uuidString)" }
    var tokenName: String { "synced_\(normalizeSharedValueName(groupID))_\(value.name)" }
    var status: SharedValueStatus { isDisconnected ? .disconnected : value.status }
}

@MainActor @Observable
final class SyncedTabVariableStore {
    static let shared = SyncedTabVariableStore()
    private(set) var entries: [SyncedTabVariableEntry] = []

    func receive(_ values: [LinkedDeviceVariable], groupID: String, tabName: String, deviceName: String) {
        entries.removeAll { $0.groupID == groupID }
        entries.append(contentsOf: LinkedDeviceVariable.categorized(values).map {
            SyncedTabVariableEntry(groupID: groupID, tabName: tabName, deviceName: deviceName, value: $0, isDisconnected: false)
        })
        entries.sort { $0.tokenName < $1.tokenName }
    }

    func disconnected(groupID: String) {
        for index in entries.indices where entries[index].groupID == groupID { entries[index].isDisconnected = true }
    }

    func clear(groupID: String) { entries.removeAll { $0.groupID == groupID } }

    func payload(named name: String) -> SharedValuePayload? {
        return entries.first { $0.tokenName == normalizeSharedValueName(name) }?.value.payload
    }

    func values(for groupID: String) -> [String: String] {
        return entries.filter { $0.groupID == groupID }.reduce(into: [:]) { result, entry in
            guard let payload = entry.value.payload else { return }
            result[entry.value.name] = payload.displayValue
            result["shared:\(entry.value.name)"] = payload.displayValue
        }
    }
}
