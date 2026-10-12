import Foundation

enum SharedValueType: String, Codable, CaseIterable, Sendable {
    case text
    case number
    case boolean
    case payload
}

enum SharedValuePayload: Codable, Equatable, Sendable {
    case text(String)
    case number(Double)
    case boolean(Bool)
    case payload(String)

    var valueType: SharedValueType {
        switch self {
        case .text: .text
        case .number: .number
        case .boolean: .boolean
        case .payload: .payload
        }
    }

    var displayValue: String {
        switch self {
        case let .text(value), let .payload(value): value
        case let .number(value):
            if value.isFinite && value.rounded() == value && value >= Double(Int.min) && value < Double(Int.max) {
                String(Int(value))
            } else {
                String(value)
            }
        case let .boolean(value): value ? "true" : "false"
        }
    }

    private enum CodingKeys: String, CodingKey { case type, text, number, boolean, payload }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(SharedValueType.self, forKey: .type) {
        case .text: self = .text(try container.decode(String.self, forKey: .text))
        case .number: self = .number(try container.decode(Double.self, forKey: .number))
        case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .payload: self = .payload(try container.decode(String.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode(SharedValueType.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case let .number(value):
            try container.encode(SharedValueType.number, forKey: .type)
            try container.encode(value, forKey: .number)
        case let .boolean(value):
            try container.encode(SharedValueType.boolean, forKey: .type)
            try container.encode(value, forKey: .boolean)
        case let .payload(value):
            try container.encode(SharedValueType.payload, forKey: .type)
            try container.encode(value, forKey: .payload)
        }
    }
}

enum WirelessSharedValueField: String, Codable, CaseIterable, Sendable {
    case batteryPercent
    case rf
    case audio
    case connected
}

enum SharedValueBinding: Codable, Equatable, Sendable {
    case manual
    case system(key: String)
    case computed(expression: String, payloadType: SharedValueType)
    case shure(deviceID: UUID, channel: Int, field: WirelessSharedValueField)
    case sennheiser(deviceID: UUID, channel: Int, field: WirelessSharedValueField)
    case osc(address: String, payloadType: SharedValueType)
    case triggerPayload(triggerID: UUID, field: String, payloadType: SharedValueType)

    private enum CodingKeys: String, CodingKey { case kind, deviceID, channel, field, address, payloadType, triggerID, key, expression }
    private enum Kind: String, Codable { case manual, system, computed, shure, sennheiser, osc, triggerPayload }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .manual: self = .manual
        case .system: self = .system(key: try container.decode(String.self, forKey: .key))
        case .computed: self = .computed(expression: try container.decode(String.self, forKey: .expression), payloadType: try container.decode(SharedValueType.self, forKey: .payloadType))
        case .shure:
            self = .shure(deviceID: try container.decode(UUID.self, forKey: .deviceID), channel: try container.decode(Int.self, forKey: .channel), field: try container.decode(WirelessSharedValueField.self, forKey: .field))
        case .sennheiser:
            self = .sennheiser(deviceID: try container.decode(UUID.self, forKey: .deviceID), channel: try container.decode(Int.self, forKey: .channel), field: try container.decode(WirelessSharedValueField.self, forKey: .field))
        case .osc:
            self = .osc(address: try container.decode(String.self, forKey: .address), payloadType: try container.decode(SharedValueType.self, forKey: .payloadType))
        case .triggerPayload:
            self = .triggerPayload(triggerID: try container.decode(UUID.self, forKey: .triggerID), field: try container.decode(String.self, forKey: .field), payloadType: try container.decode(SharedValueType.self, forKey: .payloadType))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual:
            try container.encode(Kind.manual, forKey: .kind)
        case let .system(key):
            try container.encode(Kind.system, forKey: .kind); try container.encode(key, forKey: .key)
        case let .computed(expression, payloadType):
            try container.encode(Kind.computed, forKey: .kind); try container.encode(expression, forKey: .expression); try container.encode(payloadType, forKey: .payloadType)
        case let .shure(deviceID, channel, field):
            try container.encode(Kind.shure, forKey: .kind); try container.encode(deviceID, forKey: .deviceID); try container.encode(channel, forKey: .channel); try container.encode(field, forKey: .field)
        case let .sennheiser(deviceID, channel, field):
            try container.encode(Kind.sennheiser, forKey: .kind); try container.encode(deviceID, forKey: .deviceID); try container.encode(channel, forKey: .channel); try container.encode(field, forKey: .field)
        case let .osc(address, payloadType):
            try container.encode(Kind.osc, forKey: .kind); try container.encode(address, forKey: .address); try container.encode(payloadType, forKey: .payloadType)
        case let .triggerPayload(triggerID, field, payloadType):
            try container.encode(Kind.triggerPayload, forKey: .kind); try container.encode(triggerID, forKey: .triggerID); try container.encode(field, forKey: .field); try container.encode(payloadType, forKey: .payloadType)
        }
    }
}

enum SharedValueStatus: String, Codable, Equatable, Sendable {
    case live
    case stale
    case disconnected
    case neverReceived
}

enum SharedValueOrigin: String, Codable, Sendable {
    case suggested
    case custom
}

struct OSCAddressObservation: Identifiable, Equatable, Sendable {
    var address: String
    var payload: SharedValuePayload
    var receivedAt: Date

    var id: String { address }
}

struct TriggerValueObservation: Identifiable, Equatable, Sendable {
    var triggerID: UUID
    var field: String
    var payload: SharedValuePayload
    var receivedAt: Date

    var id: String { "\(triggerID.uuidString):\(field)" }
}

struct SharedValue: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var binding: SharedValueBinding
    var payload: SharedValuePayload?
    var lastUpdatedAt: Date?
    var status: SharedValueStatus
    /// Nil preserves values written before origins were introduced and means custom.
    var origin: SharedValueOrigin? = nil

    init(id: UUID = UUID(), name: String, binding: SharedValueBinding, payload: SharedValuePayload? = nil, lastUpdatedAt: Date? = nil, status: SharedValueStatus = .neverReceived, origin: SharedValueOrigin? = nil) {
        self.id = id
        self.name = normalizeSharedValueName(name)
        self.binding = binding
        self.payload = payload
        self.lastUpdatedAt = lastUpdatedAt
        self.status = payload == nil ? .neverReceived : status
        self.origin = origin
    }

    var token: String { "#{\(name)}" }
    var displayValue: String { payload?.displayValue ?? "" }
    var isSuggested: Bool { origin == .suggested }

    @discardableResult
    mutating func apply(payload newPayload: SharedValuePayload, at date: Date) -> Bool {
        guard payload != newPayload || status != .live || lastUpdatedAt.map({ date.timeIntervalSince($0) >= 1 }) != false else { return false }
        payload = newPayload
        lastUpdatedAt = date
        status = .live
        return true
    }

    mutating func markDisconnected() {
        status = payload == nil ? .neverReceived : .disconnected
    }

    mutating func markStale() {
        status = payload == nil ? .neverReceived : .stale
    }
}

func normalizeSharedValueName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let pieces = trimmed.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    return pieces.joined(separator: "_")
}

/// Keeps persisted Pro values intact on downgrade while excluding them from every consumer.
enum SharedValueAccessPolicy {
    static func visible(_ values: [SharedValue], hasPro: Bool, syncedTabIDs: Set<UUID> = []) -> [SharedValue] {
        guard !hasPro else { return values }
        let byName = Dictionary(values.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return values.filter { allows($0, byName: byName, visiting: [], syncedTabIDs: syncedTabIDs) }
    }

    private static func allows(_ value: SharedValue, byName: [String: SharedValue], visiting: Set<String>, syncedTabIDs: Set<UUID>) -> Bool {
        switch value.binding {
        case .manual: return true
        case let .system(key):
            let parts = key.split(separator: ":")
            if parts.count > 1, let tabID = UUID(uuidString: String(parts[1])), syncedTabIDs.contains(tabID) { return false }
            return ["clock:", "planningcenter:", "roster:"].contains { key.hasPrefix($0) }
        case let .computed(expression, _):
            guard !visiting.contains(value.name) else { return false }
            let pattern = #"#\{([^}]+)\}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let nextVisiting = visiting.union([value.name])
            return regex.matches(in: expression, range: NSRange(expression.startIndex..., in: expression)).allSatisfy { match in
                guard let range = Range(match.range(at: 1), in: expression) else { return false }
                let name = String(expression[range]).replacingOccurrences(of: "shared:", with: "")
                guard let dependency = byName[normalizeSharedValueName(name)] else { return false }
                return allows(dependency, byName: byName, visiting: nextVisiting, syncedTabIDs: syncedTabIDs)
            }
        case .shure, .sennheiser, .osc, .triggerPayload: return false
        }
    }
}
