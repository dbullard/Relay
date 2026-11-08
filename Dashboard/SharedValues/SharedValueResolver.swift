import Foundation
import CoreFoundation

enum SharedValueCompletionGroup: String, Equatable {
    case manual
    case system
    case computed
    case wireless
    case osc
    case trigger
}

struct SharedValueCompletionCandidate: Identifiable, Equatable {
    let value: SharedValue

    var id: UUID { value.id }
    var name: String { value.name }
    var token: String { value.token }
    var displayValue: String { value.displayValue }
    var status: SharedValueStatus { value.status }

    var group: SharedValueCompletionGroup {
        switch value.binding {
        case .manual: .manual
        case .system: .system
        case .computed: .computed
        case .shure, .sennheiser: .wireless
        case .osc: .osc
        case .triggerPayload: .trigger
        }
    }

    var sourceDescription: String {
        switch value.binding {
        case .manual: "Manual value"
        case .system: "Relay state"
        case .computed: "Computed value"
        case let .shure(_, channel, field): "Shure • CH \(channel) • \(field.rawValue)"
        case let .sennheiser(_, channel, field): "Sennheiser • CH \(channel) • \(field.rawValue)"
        case let .osc(address, _): "OSC • \(address)"
        case let .triggerPayload(_, field, _): "Automation • \(field)"
        }
    }
}

@MainActor
struct SharedValueResolver {
    let store: SharedValueStore

    init(store: SharedValueStore = .shared) {
        self.store = store
    }

    func resolveText(token: String) -> String? {
        resolvePayload(token: token)?.displayValue
    }

    func resolvePayload(token: String) -> SharedValuePayload? {
        let raw = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^#?\\{?(?:shared:)?", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "}"))
        if raw.hasPrefix("person:"),
           let person = LinkedComputerPersonVariableStore.shared.value(named: String(raw.dropFirst("person:".count))) {
            return .text(person)
        }
        let segments = raw.split(separator: ".").map(String.init)
        let name = normalizeSharedValueName(segments.first ?? "")
        guard !name.isEmpty else { return nil }
        let values = store.snapshot.values
        guard let payload = values.first(where: { $0.name == name })?.payload
            ?? LinkedDeviceVariableStore.shared.payload(named: name)
            ?? SyncedTabVariableStore.shared.payload(named: name)
            ?? LinkedComputerPersonVariableStore.shared.value(named: name).map(SharedValuePayload.text) else { return nil }
        guard segments.count > 1 else { return payload }
        guard case let .payload(json) = payload,
              let data = json.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        for segment in segments.dropFirst() {
            if let dictionary = object as? [String: Any], let next = dictionary[segment] { object = next }
            else if let array = object as? [Any], let index = Int(segment), array.indices.contains(index) { object = array[index] }
            else { return nil }
        }
        if let text = object as? String { return .text(text) }
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            return .number(number.doubleValue)
        }
        guard let nested = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys]),
              let text = String(data: nested, encoding: .utf8) else { return nil }
        return .payload(text)
    }

    func completionCandidates(query: String) -> [SharedValueCompletionCandidate] {
        let normalizedQuery = normalizeSharedValueName(query)
        return store.snapshot.values
            .filter { normalizedQuery.isEmpty || $0.name.hasPrefix(normalizedQuery) }
            .map(SharedValueCompletionCandidate.init)
            .sorted { $0.name < $1.name }
    }

    private func normalizedTokenName(_ token: String) -> String {
        var name = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("#") { name.removeFirst() }
        if name.hasPrefix("{") && name.hasSuffix("}") {
            name.removeFirst()
            name.removeLast()
        }
        if name.lowercased().hasPrefix("shared:") {
            name.removeFirst("shared:".count)
        }
        return normalizeSharedValueName(name)
    }
}

enum SharedValueTextInterpolation {
    static func render(_ text: String, resolve: (String) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"#\{([^}]+)\}|#([A-Za-z0-9_]+)"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let nameRange = match.range(at: 1).location == NSNotFound ? match.range(at: 2) : match.range(at: 1)
            guard let fullRange = Range(match.range, in: result),
                  let nameRange = Range(nameRange, in: text) else { continue }
            result.replaceSubrange(fullRange, with: resolve(String(text[nameRange])) ?? "")
        }
        return result
    }

    static func renderJSON(_ text: String, resolve: (String) -> String?) -> String {
        guard text.contains("#"), let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return render(text, resolve: resolve)
        }
        func replacingStrings(_ value: Any) -> Any {
            if let string = value as? String { return render(string, resolve: resolve) }
            if let array = value as? [Any] { return array.map(replacingStrings) }
            if let dictionary = value as? [String: Any] {
                return dictionary.mapValues(replacingStrings)
            }
            return value
        }
        guard let rendered = try? JSONSerialization.data(withJSONObject: replacingStrings(object), options: [.fragmentsAllowed, .sortedKeys]),
              let result = String(data: rendered, encoding: .utf8) else { return render(text, resolve: resolve) }
        return result
    }
}
