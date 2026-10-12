import Foundation

struct ClockFormatPreference: Codable, Equatable {
    var pattern: String
    /// Nil follows the device's current time zone.
    var timeZoneIdentifier: String? = nil

    func formatted(_ date: Date, defaultTimeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? defaultTimeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

enum ClockFormatPreferences {
    private static let storageKey = "relay_clock_variable_formats_v1"

    static func load() -> [String: ClockFormatPreference] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let preferences = try? JSONDecoder().decode([String: ClockFormatPreference].self, from: data) else { return [:] }
        return preferences
    }

    static func save(_ preference: ClockFormatPreference, for key: String) {
        var preferences = load()
        preferences[key] = preference
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

struct SharedValueCatalogObservation: Equatable {
    let key: String
    let name: String
    let payload: SharedValuePayload
    let status: SharedValueStatus

    init(key: String, name: String, payload: SharedValuePayload, status: SharedValueStatus = .live) {
        self.key = key
        self.name = name
        self.payload = payload
        self.status = status
    }
}

/// Builds the app-wide, read-only variables from state Relay already holds locally.
/// Keys contain persisted source identities; names are labels and can change safely.
enum SharedValueCatalog {
    static func observations(
        now: Date,
        timeZone: TimeZone = .current,
        clockFormats: [String: ClockFormatPreference] = [:],
        tabs: [DashboardTab],
        devices: [ExternalDeviceConfig] = [],
        proPresenterStatuses: [UUID: ProPresenterSlideStatus] = [:],
        disconnectedGroupIDs: Set<String> = [],
        transcriptionPayloads: [UUID: TranscriptOutputPayload] = [:]
    ) -> [SharedValueCatalogObservation] {
        var result: [SharedValueCatalogObservation] = []
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm:ss"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEEE"
        let formattedDate = clockFormats["clock:date"]?.formatted(now, defaultTimeZone: timeZone) ?? dateFormatter.string(from: now)
        let formattedTime = clockFormats["clock:time"]?.formatted(now, defaultTimeZone: timeZone) ?? timeFormatter.string(from: now)
        result.append(.init(key: "clock:date", name: "clock_local_date", payload: .text(formattedDate)))
        result.append(.init(key: "clock:time", name: "clock_local_time", payload: .text(formattedTime)))
        result.append(.init(key: "clock:weekday", name: "clock_weekday", payload: .text(weekdayFormatter.string(from: now))))
        result.append(.init(key: "clock:unix", name: "clock_unix_timestamp", payload: .number(now.timeIntervalSince1970.rounded(.towardZero))))
        result.append(.init(key: "clock:timezone", name: "clock_timezone", payload: .text(timeZone.identifier)))

        for tab in tabs {
            if let groupID = tab.syncGroupID, !tab.syncIsOwner {
                let label = tab.syncOwnerDeviceName.isEmpty ? tab.name : tab.syncOwnerDeviceName
                result.append(.init(
                    key: "computer:\(groupID):connected",
                    name: "computer_\(label)_connected",
                    payload: .boolean(!disconnectedGroupIDs.contains(groupID))
                ))
            }
            for (rowIndex, row) in tab.rosterRows.enumerated() {
                let rowStatus: SharedValueStatus = tab.syncGroupID.map(disconnectedGroupIDs.contains) == true && !tab.syncIsOwner ? .disconnected : .live
                var structuredRow: [String: String] = [:]
                for column in tab.rosterColumns {
                    let text = row.values[column.id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !text.isEmpty else { continue }
                    structuredRow[column.title] = text
                    result.append(.init(
                        key: "roster:\(tab.id):\(row.id):\(column.id)",
                        name: "roster_\(tab.name)_row_\(rowIndex + 1)_\(column.title)",
                        payload: .text(text), status: rowStatus
                    ))
                }
                if let json = canonicalJSON(structuredRow), !structuredRow.isEmpty {
                    result.append(.init(
                        key: "roster:\(tab.id):\(row.id):json",
                        name: "roster_\(tab.name)_row_\(rowIndex + 1)_data",
                        payload: .payload(json), status: rowStatus
                    ))
                }
            }
            result.append(contentsOf: planningCenterObservations(for: tab))
        }

        for (moduleID, status) in proPresenterStatuses {
            let prefix = "propresenter_\(moduleID.uuidString.prefix(8))"
            let base = "propresenter:\(moduleID):"
            result.append(.init(key: base + "connected", name: prefix + "_connected", payload: .boolean(status.isConnected)))
            let dataStatus: SharedValueStatus = status.isConnected ? .live : .disconnected
            if let name = status.presentationName, !name.isEmpty {
                result.append(.init(key: base + "presentation", name: prefix + "_presentation", payload: .text(name), status: dataStatus))
            }
            if let index = status.slideIndex {
                result.append(.init(key: base + "slide_number", name: prefix + "_slide_number", payload: .number(Double(index + 1)), status: dataStatus))
            }
            if let total = status.slideTotal {
                result.append(.init(key: base + "slide_total", name: prefix + "_slide_total", payload: .number(Double(total)), status: dataStatus))
            }
            if let text = status.slideText, !text.isEmpty {
                result.append(.init(key: base + "slide_text", name: prefix + "_slide_text", payload: .text(text), status: dataStatus))
            }
            if let group = status.groupName, !group.isEmpty {
                result.append(.init(key: base + "group", name: prefix + "_group", payload: .text(group), status: dataStatus))
            }
        }

        for device in devices {
            result.append(.init(
                key: "integration:\(device.id):enabled",
                name: "integration_\(device.name)_enabled",
                payload: .boolean(device.isEnabled)
            ))
        }

        for device in devices where device.kind == .audioConsole {
            for channel in device.digicoInputChannels {
                let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                result.append(.init(
                    key: "console:\(device.id):input:\(channel.channel):name",
                    name: "console_\(device.name)_input_\(channel.channel)_name",
                    payload: .text(name)
                ))
            }
            for channel in device.digicoDiscoveredChannels {
                let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                result.append(.init(
                    key: "console:\(device.id):\(channel.channelType.rawValue):\(channel.index):name",
                    name: "console_\(device.name)_\(channel.channelType.rawValue)_\(channel.index)_name",
                    payload: .text(name)
                ))
            }
        }

        for (tileID, payload) in transcriptionPayloads {
            let prefix = "transcription_\(tileID.uuidString.prefix(8))"
            if let entry = payload.latestEntry {
                result.append(.init(key: "transcription:\(tileID):text", name: prefix + "_latest_text", payload: .text(entry.displayText)))
                result.append(.init(key: "transcription:\(tileID):source", name: prefix + "_source", payload: .text(entry.sourceDisplayName)))
                result.append(.init(key: "transcription:\(tileID):final", name: prefix + "_is_final", payload: .boolean(entry.isFinal)))
            }
            result.append(.init(key: "transcription:\(tileID):input_level", name: prefix + "_input_level", payload: .number(payload.inputLevel)))
        }
        return result
    }

    private static func planningCenterObservations(for tab: DashboardTab) -> [SharedValueCatalogObservation] {
        guard tab.serviceTypeID != nil || tab.planID != nil else { return [] }
        var result: [SharedValueCatalogObservation] = []
        let keyPrefix = "planningcenter:\(tab.id):"
        let namePrefix = "planning_center_\(tab.name)"

        func add(_ field: String, _ label: String, _ text: String?) {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            result.append(.init(key: keyPrefix + field, name: namePrefix + "_" + label, payload: .text(text)))
        }

        add("service_type_id", "service_type_id", tab.serviceTypeID)
        add("service_type_name", "service_type_name", tab.serviceTypeName)
        add("plan_id", "plan_id", tab.planID)
        add("plan_title", "plan_title", tab.planTitle)
        add("plan_date", "plan_date", tab.planDateLabel)
        add("service_time", "service_time", tab.serviceTimeName)
        add("team_name", "team_name", tab.teamName)

        let currentSnapshotKey = PCOTileView.makeTabSnapshotKey(
            serviceTypeID: tab.serviceTypeID, planID: tab.planID, serviceTimeName: tab.serviceTimeName
        )
        guard tab.pcoSnapshotKey == currentSnapshotKey else { return result }

        for (index, row) in tab.pcoCachedRundownRows.enumerated() {
            let key = "rundown:\(row.id):"
            let label = "rundown_\(row.order ?? index + 1)"
            add(key + "title", label + "_title", row.title)
            add(key + "key", label + "_key", row.keyText)
            add(key + "type", label + "_type", row.type)
            add(key + "length", label + "_length", row.lengthText)
            add(key + "arrangement", label + "_arrangement", row.arrangementText)
            add(key + "bpm", label + "_bpm", row.bpmText)
            add(key + "ccli", label + "_ccli", row.ccliText)
            add(key + "sequence", label + "_sequence", row.sequenceText)
            add(key + "notes", label + "_notes", row.notesText)
            let selectedTime = tab.serviceTimeName.flatMap { row.timeTextsByLabel[$0] }
                ?? row.timeTextsByLabel.sorted(by: { $0.key < $1.key }).first?.value
            add(key + "time", label + "_time", selectedTime)
            if let order = row.order {
                result.append(.init(key: keyPrefix + key + "order", name: namePrefix + "_" + label + "_order", payload: .number(Double(order))))
            }
            result.append(.init(key: keyPrefix + key + "is_header", name: namePrefix + "_" + label + "_is_header", payload: .boolean(row.isHeader)))
        }

        var assignmentOccurrences: [String: Int] = [:]
        for row in tab.pcoCachedTeamAssignments {
            let identity = row.personID.map { "\($0)|\(row.positionName)" }
                ?? "\(row.teamName ?? "")|\(row.positionName)|\(row.personName)"
            let slug = normalizeSharedValueName(identity)
            let occurrence = assignmentOccurrences[slug, default: 0] + 1
            assignmentOccurrences[slug] = occurrence
            let key = "assignment:\(slug):\(occurrence):"
            let label = "assignment_\(row.positionName)_\(row.personName)_\(occurrence)"
            add(key + "person", label + "_person", row.personName)
            add(key + "position", label + "_position", row.positionName)
            add(key + "team", label + "_team", row.teamName)
            add(key + "status", label + "_status", row.status.rawValue)
            add(key + "service_times", label + "_service_times", row.serviceTimeLabels.joined(separator: ", "))
        }
        return result
    }

    private static func canonicalJSON(_ object: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum SharedValueExpression {
    static func evaluate(_ expression: String, type: SharedValueType, resolve: (String) -> SharedValuePayload?) -> SharedValuePayload? {
        let pattern = #"#\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(expression.startIndex..., in: expression)
        let matches = regex.matches(in: expression, range: range)
        var expanded = expression
        for match in matches.reversed() {
            guard let full = Range(match.range, in: expanded),
                  let keyRange = Range(match.range(at: 1), in: expression) else { return nil }
            let name = String(expression[keyRange]).replacingOccurrences(of: "shared:", with: "")
            guard let value = resolve(name) else { return nil }
            expanded.replaceSubrange(full, with: value.displayValue)
        }
        switch type {
        case .text: return .text(expanded)
        case .number:
            guard let number = ArithmeticParser.parse(expanded), number.isFinite else { return nil }
            return .number(number)
        case .boolean:
            return evaluateBoolean(expanded).map(SharedValuePayload.boolean)
        case .payload: return nil
        }
    }

    private static func evaluateBoolean(_ expression: String) -> Bool? {
            let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = trimmed.range(of: "||") {
                guard let lhs = evaluateBoolean(String(trimmed[..<range.lowerBound])),
                      let rhs = evaluateBoolean(String(trimmed[range.upperBound...])) else { return nil }
                return lhs || rhs
            }
            if let range = trimmed.range(of: "&&") {
                guard let lhs = evaluateBoolean(String(trimmed[..<range.lowerBound])),
                      let rhs = evaluateBoolean(String(trimmed[range.upperBound...])) else { return nil }
                return lhs && rhs
            }
            if trimmed.hasPrefix("!") { return evaluateBoolean(String(trimmed.dropFirst())).map { !$0 } }
            if trimmed == "true" { return true }
            if trimmed == "false" { return false }
            for op in [">=", "<=", "==", "!=", ">", "<"] {
                if let range = trimmed.range(of: op) {
                    let left = String(trimmed[..<range.lowerBound])
                    let right = String(trimmed[range.upperBound...])
                    guard let lhs = ArithmeticParser.parse(left), let rhs = ArithmeticParser.parse(right) else { return nil }
                    let result: Bool = switch op {
                    case ">=": lhs >= rhs
                    case "<=": lhs <= rhs
                    case "==": lhs == rhs
                    case "!=": lhs != rhs
                    case ">": lhs > rhs
                    default: lhs < rhs
                    }
                    return result
                }
            }
            return nil
    }
}

private struct ArithmeticParser {
    private let input: [Character]
    private var index = 0
    init(_ text: String) { input = Array(text.filter { !$0.isWhitespace }) }
    static func parse(_ text: String) -> Double? {
        var parser = ArithmeticParser(text)
        return parser.parse()
    }
    mutating func parse() -> Double? {
        guard let result = sum(), index == input.count else { return nil }
        return result
    }
    private mutating func sum() -> Double? {
        guard var result = product() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            index += 1
            guard let rhs = product() else { return nil }
            result = op == "+" ? result + rhs : result - rhs
        }
        return result
    }
    private mutating func product() -> Double? {
        guard var result = factor() else { return nil }
        while let op = peek(), op == "*" || op == "/" {
            index += 1
            guard let rhs = factor(), op != "/" || rhs != 0 else { return nil }
            result = op == "*" ? result * rhs : result / rhs
        }
        return result
    }
    private mutating func factor() -> Double? {
        if peek() == "-" { index += 1; return factor().map { -$0 } }
        if peek() == "(" {
            index += 1
            guard let value = sum(), peek() == ")" else { return nil }
            index += 1
            return value
        }
        let start = index
        while let c = peek(), c.isNumber || c == "." { index += 1 }
        guard index > start else { return nil }
        return Double(String(input[start..<index]))
    }
    private func peek() -> Character? { index < input.count ? input[index] : nil }
}
