//
//  PCOTeamAssignmentsModule.swift
//  Relay
//
//  Hosts the dedicated PCO Team Assignments module. The runtime/data
//  pipeline is shared with `PCOTileView` (Rundown); this file only adds
//  the team-only plugin, settings inspector, and the supporting types
//  used to enrich each assignment with avatars and wireless picks.
//

import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif

#if os(iOS)
private struct ProminentGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            configuration.content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
#endif

// MARK: - Per-assignment extras

/// Manual placement of a person image inside its circular avatar.
struct PersonImagePlacement: Codable, Equatable {
    var scale: Double
    var offsetX: Double
    var offsetY: Double

    init(scale: Double = 1.0, offsetX: Double = 0, offsetY: Double = 0) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    static let identity = PersonImagePlacement()
}

/// Identifies the wireless brand whose cache an assignment refers to.
/// Stored as a stable string so adding new vendors in the future does
/// not break existing saved configs.
enum PCOWirelessVendor: String, Codable, Equatable, CaseIterable {
    case shure
    case sennheiser
}

/// Stable reference to a wireless channel in `ExternalDevicesStore`.
/// Display strings are kept only as a hint so we can show "(offline)"
/// without re-resolving the device every render; the source of truth is
/// `(vendor, deviceID, channelIndex)`.
struct PCOAssignmentWirelessRef: Codable, Equatable {
    var vendor: PCOWirelessVendor
    var deviceID: UUID
    var channelIndex: Int
    /// Last known device name (cosmetic fallback when the cached device
    /// is no longer in the store).
    var deviceName: String?
    /// Last known channel name (cosmetic fallback).
    var channelName: String?
}

enum PCOAssignmentTypeID {
    static let mic = "mic"
    static let iem = "iem"
}

enum PCOEquipmentItemRef: Codable, Equatable {
    case wireless(PCOAssignmentWirelessRef)
    case rosterColumn(columnID: UUID, columnTitle: String?, rowID: UUID?, value: String?)
    case text(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case wireless
        case columnID
        case columnTitle
        case rowID
        case text
    }

    private enum Kind: String, Codable {
        case wireless
        case rosterColumn
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .wireless:
            self = .wireless(try container.decode(PCOAssignmentWirelessRef.self, forKey: .wireless))
        case .rosterColumn:
            self = .rosterColumn(
                columnID: try container.decode(UUID.self, forKey: .columnID),
                columnTitle: try container.decodeIfPresent(String.self, forKey: .columnTitle),
                rowID: try container.decodeIfPresent(UUID.self, forKey: .rowID),
                value: try container.decodeIfPresent(String.self, forKey: .text)
            )
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .wireless(let ref):
            try container.encode(Kind.wireless, forKey: .kind)
            try container.encode(ref, forKey: .wireless)
        case .rosterColumn(let columnID, let columnTitle, let rowID, let value):
            try container.encode(Kind.rosterColumn, forKey: .kind)
            try container.encode(columnID, forKey: .columnID)
            try container.encodeIfPresent(columnTitle, forKey: .columnTitle)
            try container.encodeIfPresent(rowID, forKey: .rowID)
            try container.encodeIfPresent(value, forKey: .text)
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        }
    }
}

struct PCOEquipmentAssignment: Codable, Equatable, Identifiable {
    var id: UUID
    var assignmentTypeID: String
    var itemRef: PCOEquipmentItemRef?

    init(
        id: UUID = UUID(),
        assignmentTypeID: String,
        itemRef: PCOEquipmentItemRef? = nil
    ) {
        self.id = id
        self.assignmentTypeID = assignmentTypeID
        self.itemRef = itemRef
    }

    var wirelessRef: PCOAssignmentWirelessRef? {
        guard case .wireless(let ref)? = itemRef else { return nil }
        return ref
    }

    var isConfigured: Bool {
        guard let itemRef else { return false }
        switch itemRef {
        case .wireless, .rosterColumn:
            return true
        case .text(let value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// Per-assignment metadata stored on the Team Assignments module.
struct PCOAssignmentMetadata: Codable, Equatable {
    var personID: String?
    var imagePlacement: PersonImagePlacement
    var assignments: [PCOEquipmentAssignment]

    init(
        personID: String? = nil,
        imagePlacement: PersonImagePlacement = .identity,
        assignments: [PCOEquipmentAssignment] = []
    ) {
        self.personID = personID
        self.imagePlacement = imagePlacement
        self.assignments = assignments
    }

    private enum CodingKeys: String, CodingKey {
        case personID
        case imagePlacement
        case assignments
        case mic
        case iem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.personID = try container.decodeIfPresent(String.self, forKey: .personID)
        self.imagePlacement = try container.decodeIfPresent(PersonImagePlacement.self, forKey: .imagePlacement) ?? .identity
        let decodedAssignments = try container.decodeIfPresent([PCOEquipmentAssignment].self, forKey: .assignments) ?? []
        let mic = try container.decodeIfPresent(PCOAssignmentWirelessRef.self, forKey: .mic)
        let iem = try container.decodeIfPresent(PCOAssignmentWirelessRef.self, forKey: .iem)
        self.assignments = migratedAssignments(from: decodedAssignments, mic: mic, iem: iem)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(personID, forKey: .personID)
        try container.encode(imagePlacement, forKey: .imagePlacement)
        try container.encode(assignments, forKey: .assignments)
    }

    func assignment(for assignmentTypeID: String) -> PCOEquipmentAssignment? {
        assignments.first(where: { $0.assignmentTypeID == assignmentTypeID })
    }

    mutating func setAssignment(_ assignment: PCOEquipmentAssignment) {
        assignments.removeAll { $0.assignmentTypeID == assignment.assignmentTypeID }
        assignments.append(assignment)
    }

    mutating func removeAssignment(for assignmentTypeID: String) {
        assignments.removeAll { $0.assignmentTypeID == assignmentTypeID }
    }
}

/// Default wireless assignments keyed by Planning Center role / position.
/// These act as automatic fallbacks for people in matching positions unless a
/// per-person override is configured.
struct PCORoleWirelessRule: Codable, Equatable {
    var assignments: [PCOEquipmentAssignment]

    init(
        assignments: [PCOEquipmentAssignment] = []
    ) {
        self.assignments = assignments
    }

    private enum CodingKeys: String, CodingKey {
        case assignments
        case mic
        case iem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAssignments = try container.decodeIfPresent([PCOEquipmentAssignment].self, forKey: .assignments) ?? []
        let mic = try container.decodeIfPresent(PCOAssignmentWirelessRef.self, forKey: .mic)
        let iem = try container.decodeIfPresent(PCOAssignmentWirelessRef.self, forKey: .iem)
        self.assignments = migratedAssignments(from: decodedAssignments, mic: mic, iem: iem)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assignments, forKey: .assignments)
    }

    func assignment(for assignmentTypeID: String) -> PCOEquipmentAssignment? {
        assignments.first(where: { $0.assignmentTypeID == assignmentTypeID })
    }

    mutating func setAssignment(_ assignment: PCOEquipmentAssignment) {
        assignments.removeAll { $0.assignmentTypeID == assignment.assignmentTypeID }
        assignments.append(assignment)
    }

    mutating func removeAssignment(for assignmentTypeID: String) {
        assignments.removeAll { $0.assignmentTypeID == assignmentTypeID }
    }
}

private func migratedAssignments(
    from assignments: [PCOEquipmentAssignment],
    mic: PCOAssignmentWirelessRef?,
    iem: PCOAssignmentWirelessRef?
) -> [PCOEquipmentAssignment] {
    var merged = assignments

    func upsertLegacyWireless(_ ref: PCOAssignmentWirelessRef?, typeID: String) {
        guard let ref else { return }
        guard !merged.contains(where: { $0.assignmentTypeID == typeID && $0.isConfigured }) else { return }
        merged.append(
            PCOEquipmentAssignment(
                assignmentTypeID: typeID,
                itemRef: .wireless(ref)
            )
        )
    }

    upsertLegacyWireless(mic, typeID: PCOAssignmentTypeID.mic)
    upsertLegacyWireless(iem, typeID: PCOAssignmentTypeID.iem)
    return merged
}

/// Container for all team-assignment-only configuration that is meaningful
/// only on a dedicated PCO Team Assignments module.
struct PCOTeamAssignmentsExtras: Codable, Equatable {
    /// Map of assignment match key -> metadata.
    var byKey: [String: PCOAssignmentMetadata]
    /// Map of normalized position name -> automatic wireless defaults.
    var roleRulesByPosition: [String: PCORoleWirelessRule]
    /// Whether to draw a circular avatar leading the pill.
    var showPersonAvatars: Bool

    init(
        byKey: [String: PCOAssignmentMetadata] = [:],
        roleRulesByPosition: [String: PCORoleWirelessRule] = [:],
        showPersonAvatars: Bool = true
    ) {
        self.byKey = byKey
        self.roleRulesByPosition = roleRulesByPosition
        self.showPersonAvatars = showPersonAvatars
    }

    private enum CodingKeys: String, CodingKey {
        case byKey
        case roleRulesByPosition
        case showPersonAvatars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.byKey = try container.decodeIfPresent([String: PCOAssignmentMetadata].self, forKey: .byKey) ?? [:]
        self.roleRulesByPosition = try container.decodeIfPresent([String: PCORoleWirelessRule].self, forKey: .roleRulesByPosition) ?? [:]
        self.showPersonAvatars = try container.decodeIfPresent(Bool.self, forKey: .showPersonAvatars) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(byKey, forKey: .byKey)
        try container.encode(roleRulesByPosition, forKey: .roleRulesByPosition)
        try container.encode(showPersonAvatars, forKey: .showPersonAvatars)
    }

    func normalizedForPersistence() -> PCOTeamAssignmentsExtras {
        PCOTeamAssignmentsExtras(
            byKey: byKey.reduce(into: [:]) { result, entry in
                let normalized = entry.value.normalizedForPersistence()
                if normalized.personID != nil || normalized.imagePlacement != .identity || !normalized.assignments.isEmpty {
                    result[entry.key] = normalized
                }
            },
            roleRulesByPosition: roleRulesByPosition.reduce(into: [:]) { result, entry in
                let normalized = entry.value.normalizedForPersistence()
                if !normalized.assignments.isEmpty {
                    result[entry.key] = normalized
                }
            },
            showPersonAvatars: showPersonAvatars
        )
    }
}

extension PCOAssignmentMetadata {
    func normalizedForPersistence() -> PCOAssignmentMetadata {
        var copy = self
        copy.assignments = assignments.filter(\.isConfigured)
        return copy
    }
}

extension PCORoleWirelessRule {
    func normalizedForPersistence() -> PCORoleWirelessRule {
        var copy = self
        copy.assignments = assignments.filter(\.isConfigured)
        return copy
    }
}

private enum PCOAssignmentValueKind {
    case wirelessMic
    case wirelessIEM
    case text
    case rosterChoice
}

private struct PCORosterValueOption: Identifiable, Hashable {
    let rowID: UUID
    let value: String

    var id: String { "\(rowID.uuidString)|\(value)" }
}

private struct PCOAssignmentTypeDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let valueKind: PCOAssignmentValueKind
    let placeholder: String
    let rosterColumnID: UUID?
    let rosterOptions: [PCORosterValueOption]
}

private enum PCOAssignmentCatalog {
    private static let fixedDefinitions: [PCOAssignmentTypeDefinition] = [
        PCOAssignmentTypeDefinition(
            id: PCOAssignmentTypeID.mic,
            title: "Microphone",
            valueKind: .wirelessMic,
            placeholder: "Choose mic",
            rosterColumnID: nil,
            rosterOptions: []
        ),
        PCOAssignmentTypeDefinition(
            id: PCOAssignmentTypeID.iem,
            title: "IEM",
            valueKind: .wirelessIEM,
            placeholder: "Choose IEM",
            rosterColumnID: nil,
            rosterOptions: []
        )
    ]

    private static let trailingDefinitions: [PCOAssignmentTypeDefinition] = [
        PCOAssignmentTypeDefinition(
            id: "notes",
            title: "Notes",
            valueKind: .text,
            placeholder: "Enter assignment note",
            rosterColumnID: nil,
            rosterOptions: []
        )
    ]

    static func definitions(equipmentRoster: DashboardRoster?) -> [PCOAssignmentTypeDefinition] {
        fixedDefinitions + rosterDefinitions(from: equipmentRoster) + trailingDefinitions
    }

    static func definition(
        for assignmentTypeID: String,
        equipmentRoster: DashboardRoster?
    ) -> PCOAssignmentTypeDefinition {
        definitions(equipmentRoster: equipmentRoster).first(where: { $0.id == assignmentTypeID }) ??
            PCOAssignmentTypeDefinition(
                id: assignmentTypeID,
                title: assignmentTypeID.replacingOccurrences(of: "_", with: " ").capitalized,
                valueKind: .text,
                placeholder: "Enter value",
                rosterColumnID: nil,
                rosterOptions: []
            )
    }

    static func title(for assignmentTypeID: String, equipmentRoster: DashboardRoster?) -> String {
        definition(for: assignmentTypeID, equipmentRoster: equipmentRoster).title
    }

    static func sortedAssignments(
        _ assignments: [PCOEquipmentAssignment],
        equipmentRoster: DashboardRoster?
    ) -> [PCOEquipmentAssignment] {
        let definitions = definitions(equipmentRoster: equipmentRoster)
        let sortIndex = Dictionary(uniqueKeysWithValues: definitions.enumerated().map { ($0.element.id, $0.offset) })
        return assignments.sorted { lhs, rhs in
            let lhsOrder = sortIndex[lhs.assignmentTypeID] ?? Int.max
            let rhsOrder = sortIndex[rhs.assignmentTypeID] ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return title(for: lhs.assignmentTypeID, equipmentRoster: equipmentRoster)
                .localizedCaseInsensitiveCompare(title(for: rhs.assignmentTypeID, equipmentRoster: equipmentRoster)) == .orderedAscending
        }
    }

    private static func rosterDefinitions(from equipmentRoster: DashboardRoster?) -> [PCOAssignmentTypeDefinition] {
        guard let equipmentRoster else { return [] }
        return equipmentRoster.columns.map { column in
            PCOAssignmentTypeDefinition(
                id: rosterAssignmentTypeID(for: column.id),
                title: column.title,
                valueKind: .rosterChoice,
                placeholder: "Choose \(column.title)",
                rosterColumnID: column.id,
                rosterOptions: rosterOptions(for: column, in: equipmentRoster)
            )
        }
    }

    private static func rosterOptions(
        for column: DashboardRosterColumn,
        in equipmentRoster: DashboardRoster
    ) -> [PCORosterValueOption] {
        var seen: Set<String> = []
        var options: [PCORosterValueOption] = []
        for row in equipmentRoster.rows {
            let rawValue = row.value(for: column.id).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawValue.isEmpty else { continue }
            let normalized = rawValue.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            options.append(PCORosterValueOption(rowID: row.id, value: rawValue))
        }
        return options
    }

    static func rosterAssignmentTypeID(for columnID: UUID) -> String {
        "roster.\(columnID.uuidString)"
    }
}

// MARK: - Match key resolver

/// Builds a stable identifier used to look up `PCOAssignmentMetadata` for a
/// row. Prefers the PCO person ID when available so assignments survive
/// renames and disambiguate duplicate names; falls back to a normalized
/// person name. Kept isolated so the matching strategy can be improved
/// later without touching call sites.
enum PCOAssignmentMatchKey {
    static func key(for row: PCOTeamAssignmentRow) -> String {
        if let pid = row.personID?.trimmingCharacters(in: .whitespacesAndNewlines), !pid.isEmpty {
            return "pid:\(pid)"
        }
        return "name:\(normalizedName(row.personName))"
    }

    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum PCORoleMatchKey {
    static func key(for positionName: String) -> String {
        PCOAssignmentMatchKey.normalizedName(positionName)
    }
}

// MARK: - Wireless cache helpers

/// A single channel option presented in the mic / IEM picker. Pulled from
/// `ExternalDevicesStore` and kept lightweight on purpose: the source of
/// truth is the store; this struct is just a render snapshot.
struct PCOWirelessChannelOption: Identifiable, Hashable {
    enum Category: Hashable {
        case mic
        case iem
    }

    let vendor: PCOWirelessVendor
    let deviceID: UUID
    let deviceName: String
    let channelIndex: Int
    let channelName: String?
    let category: Category

    var id: String { "\(vendor.rawValue)|\(deviceID.uuidString)|\(channelIndex)" }

    var displayName: String {
        if let channelName, !channelName.isEmpty {
            return "\(channelName) — \(deviceName) — CH \(channelIndex)"
        }
        return "\(deviceName) — CH \(channelIndex)"
    }

    var compactDisplayName: String {
        if let channelName, !channelName.isEmpty {
            return channelName
        }
        return "\(deviceName) CH \(channelIndex)"
    }
}

enum PCOWirelessOptions {
    /// Build a flat list of available channels from the shared
    /// `ExternalDevicesStore`. Vendors are interleaved by display name so
    /// the picker presents them in a familiar order.
    static func availableChannels() -> [PCOWirelessChannelOption] {
        let store = ExternalDevicesStore.shared
        var options: [PCOWirelessChannelOption] = []

        for device in store.devices(ofKind: .shureWireless) {
            let count = shureChannelCount(for: device)
            let category = shureCategory(for: device)
            for ch in 1...max(1, count) {
                options.append(
                    PCOWirelessChannelOption(
                        vendor: .shure,
                        deviceID: device.id,
                        deviceName: device.name,
                        channelIndex: ch,
                        channelName: shureChannelName(for: device, channelIndex: ch, store: store),
                        category: category
                    )
                )
            }
        }

        for device in store.devices(ofKind: .sennheiserWireless) {
            let count = sennheiserChannelCount(for: device)
            let category = sennheiserCategory(for: device)
            for ch in 1...max(1, count) {
                options.append(
                    PCOWirelessChannelOption(
                        vendor: .sennheiser,
                        deviceID: device.id,
                        deviceName: device.name,
                        channelIndex: ch,
                        channelName: store.cachedSennheiserChannelName(deviceID: device.id, channelIndex: ch),
                        category: category
                    )
                )
            }
        }

        return options.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func availableChannels(for category: PCOWirelessChannelOption.Category) -> [PCOWirelessChannelOption] {
        availableChannels().filter { $0.category == category }
    }

    static func emptyMessage(for category: PCOWirelessChannelOption.Category) -> String {
        switch category {
        case .mic:
            return "No wireless mic channels configured"
        case .iem:
            return "No IEM channels configured"
        }
    }

    /// Resolve the most up-to-date display label for an existing reference,
    /// using the live store if the device is still present. Returns nil when
    /// the cached device is no longer reachable so the UI can show a stale
    /// indicator.
    static func liveDisplay(for ref: PCOAssignmentWirelessRef) -> String? {
        let store = ExternalDevicesStore.shared
        let kind: ExternalDeviceKind
        switch ref.vendor {
        case .shure: kind = .shureWireless
        case .sennheiser: kind = .sennheiserWireless
        }
        guard let device = store.devices(ofKind: kind).first(where: { $0.id == ref.deviceID }) else {
            return nil
        }
        switch ref.vendor {
        case .shure:
            return store.shureChannelDisplayLabel(device: device, channelIndex: ref.channelIndex)
        case .sennheiser:
            return store.sennheiserChannelDisplayLabel(device: device, channelIndex: ref.channelIndex)
        }
    }

    private static func shureChannelCount(for device: ExternalDeviceConfig) -> Int {
        device.effectiveShureChannelCount
    }

    private static func sennheiserChannelCount(for device: ExternalDeviceConfig) -> Int {
        // Sennheiser raw values are case-sensitive (e.g. "EW-DX EM 2"),
        // so don't uppercase like we do for Shure.
        if let raw = device.sennheiserModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let model = SennheiserNetworkModel(rawValue: raw) {
            return model.channelCount
        }
        return 2
    }

    private static func shureCategory(for device: ExternalDeviceConfig) -> PCOWirelessChannelOption.Category {
        if let raw = device.shureModelIdentifier?.uppercased(),
           let model = ShureNetworkModel(rawValue: raw) {
            switch model {
            case .adtd, .adtq, .p10t, .psm900:
                return .iem
            default:
                return .mic
            }
        }

        let name = device.name.uppercased()
        if name.contains("PSM") || name.contains("P10T") || name.contains("IEM") {
            return .iem
        }
        return .mic
    }

    private static func sennheiserCategory(for device: ExternalDeviceConfig) -> PCOWirelessChannelOption.Category {
        if let raw = device.sennheiserModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let model = SennheiserNetworkModel(rawValue: raw) {
            return model.category == .iem ? .iem : .mic
        }

        let name = device.name.uppercased()
        if name.contains("IEM") {
            return .iem
        }
        return .mic
    }

    private static func shureChannelName(
        for device: ExternalDeviceConfig,
        channelIndex: Int,
        store: ExternalDevicesStore
    ) -> String? {
        let model = (device.shureModelIdentifier ?? "").uppercased()
        let upperName = device.name.uppercased()
        let isP10T = (model == "P10T") || upperName.contains("P10T")
        let isPSM900 = model.contains("PSM900") || upperName.contains("PSM 900") || upperName.contains("PSM900")

        if isP10T || isPSM900 {
            if channelIndex == 1,
               let name = device.psmChannel1Name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
            if channelIndex == 2,
               let name = device.psmChannel2Name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
        }

        if let cached = store.cachedShureChannelName(deviceID: device.id, channelIndex: channelIndex),
           !cached.isEmpty {
            return cached
        }

        if let stored = device.shureChannelNames[channelIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return stored
        }

        return nil
    }
}

// MARK: - Image resolver

/// Resolves a person image from Relay's configured "person background image"
/// folder. Mirrors the lookup strategy used by `PersonTileView` so the same
/// folder/bookmark works for both. Kept as a small helper so the matching
/// strategy can evolve without touching the team-assignments view.
///
/// All methods are `nonisolated` so they can run on a detached background
/// task (we never want to touch the disk on the main actor).
enum PCOPersonImageResolver {
    #if os(macOS)
    typealias PlatformImage = NSImage
    #else
    typealias PlatformImage = UIImage
    #endif

    private nonisolated(unsafe) static let cache = NSCache<NSString, PlatformImage>()

    nonisolated static func image(
        forName name: String?,
        personID: String?,
        folderPath: String,
        folderBookmarkData: Data?,
        targetMaxPixel: Int
    ) -> PlatformImage? {
        guard targetMaxPixel > 0 else { return nil }

        var bases = baseNames(name: name, personID: personID)
        bases = bases.filter { !$0.isEmpty }
        guard !bases.isEmpty else { return nil }

        let exts = ["png", "jpg", "jpeg", "heic"]
        let candidates: [String] = bases.flatMap { base in exts.map { "\(base).\($0)" } }

        let fm = FileManager.default

        #if os(macOS)
        if let bookmarkData = folderBookmarkData {
            var isStale = false
            if let baseURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let scoped = baseURL.startAccessingSecurityScopedResource()
                defer { if scoped { baseURL.stopAccessingSecurityScopedResource() } }

                if let image = lookupImage(in: baseURL, candidates: candidates, targetMaxPixel: targetMaxPixel, fm: fm) {
                    return image
                }
            }
        }
        if !folderPath.isEmpty {
            let baseURL = URL(fileURLWithPath: folderPath, isDirectory: true)
            if let image = lookupImage(in: baseURL, candidates: candidates, targetMaxPixel: targetMaxPixel, fm: fm) {
                return image
            }
        }
        #else
        if let bookmarkData = folderBookmarkData {
            var isStale = false
            if let baseURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let scoped = baseURL.startAccessingSecurityScopedResource()
                defer { if scoped { baseURL.stopAccessingSecurityScopedResource() } }
                if let image = lookupImage(in: baseURL, candidates: candidates, targetMaxPixel: targetMaxPixel, fm: fm) {
                    return image
                }
            }
        }
        #endif

        return nil
    }

    nonisolated private static func lookupImage(
        in baseURL: URL,
        candidates: [String],
        targetMaxPixel: Int,
        fm: FileManager
    ) -> PlatformImage? {
        for fileName in candidates {
            let url = baseURL.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: url.path) else { continue }
            if let image = downsampledImage(from: url, targetMaxPixel: targetMaxPixel) {
                return image
            }
        }
        return nil
    }

    nonisolated private static func downsampledImage(from url: URL, targetMaxPixel: Int) -> PlatformImage? {
        let cacheKey = "\(url.path)|\(targetMaxPixel)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, targetMaxPixel),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        #if os(macOS)
        let image = NSImage(cgImage: cgImage, size: .zero)
        #else
        let image = UIImage(cgImage: cgImage)
        #endif
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    nonisolated private static func baseNames(name: String?, personID: String?) -> [String] {
        var list: [String] = []
        if let id = personID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            list.append(id)
        }
        if let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            list.append(raw)
            let normalized = normalizedFileBaseName(raw)
            if !normalized.isEmpty, !list.contains(normalized) {
                list.append(normalized)
            }
            let titleCased = normalized.capitalized
            if !titleCased.isEmpty, !list.contains(titleCased) {
                list.append(titleCased)
            }
        }
        return list
    }

    nonisolated private static func normalizedFileBaseName(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: " -_"))
        let scrubbed = String(lowered.unicodeScalars.filter { allowed.contains($0) })
        return scrubbed
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Person avatar view

/// Circular avatar used in the team-assignments pill. Resolves images from
/// the shared person-image folder and renders them with a simple centered crop.
struct PCOPersonAvatarView: View {
    let row: PCOTeamAssignmentRow
    var placement: PersonImagePlacement = .identity
    var diameter: CGFloat = 36
    var fallbackTint: Color = .gray.opacity(0.4)

    @AppStorage("dashboard_personImageFolder") private var personImageFolder: String = ""
    @AppStorage("dashboard_personImageFolderBookmark") private var personImageFolderBookmarkData: Data?
    @Environment(\.displayScale) private var displayScale

    @State private var resolved: Image?

    var body: some View {
        ZStack {
            Circle()
                .fill(fallbackTint)
            if let resolved {
                resolved
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
            } else {
                Text(initials(for: row.personName))
                    .font(.system(size: diameter * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .task(id: lookupKey) {
            await resolve()
        }
    }

    private var lookupKey: String {
        [
            row.personID ?? "",
            PCOAssignmentMatchKey.normalizedName(row.personName),
            personImageFolder,
            String(personImageFolderBookmarkData?.count ?? 0),
            String(Int(targetMaxPixel))
        ].joined(separator: "|")
    }

    private var targetMaxPixel: CGFloat {
        let scale = max(displayScale, 1)
        return max(64, diameter * scale * 1.5)
    }

    private func resolve() async {
        let name = row.personName
        let personID = row.personID
        let folder = personImageFolder
        let bookmark = personImageFolderBookmarkData
        let target = Int(targetMaxPixel.rounded(.up))
        let resolvedImage = await Task.detached(priority: .utility) {
            return PCOPersonImageResolver.image(
                forName: name,
                personID: personID,
                folderPath: folder,
                folderBookmarkData: bookmark,
                targetMaxPixel: target
            )
        }.value
        await MainActor.run {
            if let resolvedImage {
                #if os(macOS)
                self.resolved = Image(nsImage: resolvedImage)
                #else
                self.resolved = Image(uiImage: resolvedImage)
                #endif
            } else {
                self.resolved = nil
            }
        }
    }

    private func initials(for name: String) -> String {
        let parts = name
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let chars = parts.prefix(2).compactMap { $0.first }
        if chars.isEmpty { return "?" }
        return String(chars).uppercased()
    }
}

// MARK: - Wireless picker

/// Reusable picker that selects a Shure/Sennheiser channel into a
/// `PCOAssignmentWirelessRef` binding. The binding is nil when no
/// assignment is active.
struct PCOWirelessChannelPicker: View {
    enum SelectionMode {
        case mic
        case iem
    }

    let label: String
    let mode: SelectionMode
    @Binding var selection: PCOAssignmentWirelessRef?

    @ObservedObject private var store = ExternalDevicesStore.shared
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }

            Divider()

            let options = availableOptions
            if options.isEmpty {
                Text(emptyStateMessage).foregroundStyle(.secondary)
            } else {
                ForEach(options) { option in
                    Button {
                        selection = PCOAssignmentWirelessRef(
                            vendor: option.vendor,
                            deviceID: option.deviceID,
                            channelIndex: option.channelIndex,
                            deviceName: option.deviceName,
                            channelName: option.channelName
                        )
                    } label: {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(currentColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var currentLabel: String {
        guard let selection else { return "Unassigned" }
        if let option = availableOptions.first(where: {
            $0.vendor == selection.vendor &&
            $0.deviceID == selection.deviceID &&
            $0.channelIndex == selection.channelIndex
        }) {
            return option.compactDisplayName
        }
        if let channel = selection.channelName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !channel.isEmpty {
            return channel
        }
        let device = selection.deviceName ?? "Device"
        return "\(device) CH \(selection.channelIndex)"
    }

    private var currentColor: Color {
        guard let selection else { return .secondary }
        return PCOWirelessOptions.liveDisplay(for: selection) == nil ? .orange : .primary
    }

    private var availableOptions: [PCOWirelessChannelOption] {
        switch mode {
        case .mic:
            return PCOWirelessOptions.availableChannels(for: .mic)
        case .iem:
            return PCOWirelessOptions.availableChannels(for: .iem)
        }
    }

    private var emptyStateMessage: String {
        switch mode {
        case .mic:
            return "No wireless mic channels configured"
        case .iem:
            return "No IEM channels configured"
        }
    }
}

private struct PCORosterAssignmentPicker: View {
    let label: String
    let options: [PCORosterValueOption]
    @Binding var selection: PCORosterValueOption?

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }

            Divider()

            if options.isEmpty {
                Text("No roster values available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        if selection == option {
                            Label(option.value, systemImage: "checkmark")
                        } else {
                            Text(option.value)
                        }
                    }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection?.value ?? "Unassigned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

// MARK: - Plugin

enum PCOTeamAssignmentsModulePlugin {}

extension PCOTeamAssignmentsModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .pcoTeamAssignments }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        // Reuse PCOTileView with a config forced to team-only rendering so
        // we share the existing data fetching and caching pipeline.
        let configBinding = Binding<PCOModuleConfig>(
            get: {
                var cfg = module.wrappedValue.pcoConfig ?? PCOModuleConfig.teamAssignmentsDefault()
                // Ensure required flags stay in team-only mode regardless of
                // legacy values that may have been migrated in.
                cfg.showServiceRundown = false
                cfg.showLiveView = false
                cfg.showTeamAssignments = true
                if cfg.teamExtras == nil {
                    cfg.teamExtras = PCOTeamAssignmentsExtras()
                }
                return cfg
            },
            set: { newValue in
                var updated = module.wrappedValue
                updated.pcoConfig = newValue
                module.wrappedValue = updated
            }
        )

        return AnyView(
            PCOTileView(
                tab: tab,
                moduleConfig: configBinding.wrappedValue,
                moduleConfigBinding: configBinding
            )
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        let cfg = Binding<PCOModuleConfig>(
            get: {
                var c = PCOModuleConfig.teamAssignmentsDefault()
                c.showHeader = showsHeader.wrappedValue
                return c
            },
            set: { newValue in
                showsHeader.wrappedValue = newValue.showHeader
                onPersist()
            }
        )
        return AnyView(
            PCOTeamAssignmentsSettingsInspector(
                config: cfg,
                tab: DashboardTab(name: "", tiles: []),
                sharedRosters: [],
                cachedAssignments: [],
                onPersist: onPersist,
                onOpenTabSettings: {}
            )
        )
    }
}

// MARK: - Settings inspector

/// Module-scoped settings UI for the dedicated PCO Team Assignments tile.
/// Shows team-only options plus per-assignment editing controls.
struct PCOTeamAssignmentsSettingsInspector: View {
    @Binding var config: PCOModuleConfig
    let tab: DashboardTab
    let sharedRosters: [DashboardRoster]
    /// The currently cached team assignment rows (filtered by the tab's
    /// service time / team selection). Used to enumerate per-assignment
    /// editor entries without re-fetching from PCO.
    let cachedAssignments: [PCOTeamAssignmentRow]
    var onPersist: () -> Void
    var onOpenTabSettings: () -> Void

    private var equipmentRoster: DashboardRoster? {
        tab.sharedRoster(for: .equipment, from: sharedRosters)
    }

    @AppStorage("dashboard_pco_connected") private var isConnected: Bool = false
    @State private var roleSearchText: String = ""
    @State private var personSearchText: String = ""
    @State private var isAssignmentsEditorPresented: Bool = false

    private var hasPlanningCenterLogin: Bool { isConnected }

    private var hasPlanningCenterTabConfiguration: Bool {
        let hasServiceType = !(tab.serviceTypeID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPlan = !(tab.planID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTimes = (tab.serviceTimeName ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
        return hasServiceType && hasPlan && hasTimes
    }

    private var availableModuleTeamNames: [String] {
        let tabSelected = (tab.teamName ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !tabSelected.isEmpty {
            return Array(Set(tabSelected)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        if let positionsByTeamName = tab.pcoTeamPositionsByTeamName, !positionsByTeamName.isEmpty {
            return positionsByTeamName.keys
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        let cachedNames = Set(
            cachedAssignments.compactMap { row in
                let trimmed = row.teamName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        )
        return Array(cachedNames).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var selectedModuleTeamNames: Set<String> {
        Set(
            (config.teamName ?? "")
                .components(separatedBy: "||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private var availableTeamPositionsByTeamName: [String: [String]] {
        let rawPositions = tab.pcoTeamPositionsByTeamName ?? [:]
        let selectedTeams = selectedModuleTeamNames

        return rawPositions.reduce(into: [:]) { result, entry in
            let teamName = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !teamName.isEmpty else { return }
            if !selectedTeams.isEmpty && !selectedTeams.contains(teamName) { return }

            var seen = Set<String>()
            let positions = entry.value.compactMap { rawPosition -> String? in
                let trimmed = rawPosition.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let key = PCORoleMatchKey.key(for: trimmed)
                guard seen.insert(key).inserted else { return nil }
                return trimmed
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            guard !positions.isEmpty else { return }
            result[teamName] = positions
        }
    }

    private func updateModuleTeamSelection(_ selected: Set<String>) {
        let normalized = Array(selected)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        config.teamName = normalized.isEmpty ? nil : normalized.joined(separator: "||")
        onPersist()
    }

    private func persistedBinding<Value>(
        for keyPath: WritableKeyPath<PCOModuleConfig, Value>
    ) -> Binding<Value> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { newValue in
                config[keyPath: keyPath] = newValue
                onPersist()
            }
        )
    }

    private func extras() -> PCOTeamAssignmentsExtras {
        config.teamExtras ?? PCOTeamAssignmentsExtras()
    }

    private func mutateExtras(_ update: (inout PCOTeamAssignmentsExtras) -> Void) {
        var current = extras()
        update(&current)
        config.teamExtras = current
        onPersist()
    }

    private func metadataBinding(forKey key: String) -> Binding<PCOAssignmentMetadata> {
        Binding(
            get: { extras().byKey[key] ?? PCOAssignmentMetadata() },
            set: { newValue in
                mutateExtras { $0.byKey[key] = newValue }
            }
        )
    }

    private func roleRuleBinding(for positionName: String) -> Binding<PCORoleWirelessRule> {
        let key = PCORoleMatchKey.key(for: positionName)
        return Binding(
            get: { extras().roleRulesByPosition[key] ?? PCORoleWirelessRule() },
            set: { newValue in
                mutateExtras { extras in
                    let normalized = newValue.normalizedForPersistence()
                    if normalized.assignments.isEmpty {
                        extras.roleRulesByPosition.removeValue(forKey: key)
                    } else {
                        extras.roleRulesByPosition[key] = normalized
                    }
                }
            }
        )
    }

    private var availableRoleNames: [String] {
        if !availableTeamPositionsByTeamName.isEmpty {
            var seen = Set<String>()
            var result: [String] = []
            for positions in availableTeamPositionsByTeamName.values {
                for position in positions {
                    let key = PCORoleMatchKey.key(for: position)
                    guard seen.insert(key).inserted else { continue }
                    result.append(position)
                }
            }
            return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        var seen = Set<String>()
        var result: [String] = []
        for row in cachedAssignments {
            let trimmed = row.positionName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = PCORoleMatchKey.key(for: trimmed)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func roleRule(for row: PCOTeamAssignmentRow) -> PCORoleWirelessRule? {
        extras().roleRulesByPosition[PCORoleMatchKey.key(for: row.positionName)]
    }

    private var filteredRoleNames: [String] {
        let query = roleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableRoleNames }
        return availableRoleNames.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredPeople: [PCOTeamAssignmentRow] {
        let query = personSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return cachedAssignments }
        return cachedAssignments.filter { row in
            row.personName.localizedCaseInsensitiveContains(query) ||
            row.positionName.localizedCaseInsensitiveContains(query) ||
            (row.teamName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var visiblePeople: [PCOTeamAssignmentRow] { filteredPeople }

    private var configuredRoleNames: [String] {
        let configuredKeys = Set(extras().roleRulesByPosition.keys)
        return availableRoleNames.filter { configuredKeys.contains(PCORoleMatchKey.key(for: $0)) }
    }

    private var configuredPeople: [PCOTeamAssignmentRow] {
        cachedAssignments.filter { row in
            let metadata = extras().byKey[PCOAssignmentMatchKey.key(for: row)]
            return !(metadata?.normalizedForPersistence().assignments.isEmpty ?? true)
        }
    }

    private struct TeamRoleSection: Identifiable {
        let teamName: String
        let roles: [String]
        var id: String { teamName }
    }

    private struct TeamPeopleSection: Identifiable {
        let teamName: String
        let rows: [PCOTeamAssignmentRow]
        var id: String { teamName }
    }

    private var visibleRoleSections: [TeamRoleSection] {
        let query = roleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !availableTeamPositionsByTeamName.isEmpty {
            return availableTeamPositionsByTeamName.keys
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .compactMap { teamName in
                    let filteredRoles = (availableTeamPositionsByTeamName[teamName] ?? []).filter { roleName in
                        query.isEmpty || roleName.localizedCaseInsensitiveContains(query)
                    }
                    guard !filteredRoles.isEmpty else { return nil }
                    return TeamRoleSection(teamName: teamName, roles: filteredRoles)
                }
        }

        var grouped: [String: [String]] = [:]

        for row in cachedAssignments {
            let roleName = row.positionName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !roleName.isEmpty else { continue }
            if !query.isEmpty && !roleName.localizedCaseInsensitiveContains(query) {
                continue
            }
            let teamName = normalizedTeamName(for: row.teamName)
            var roles = grouped[teamName] ?? []
            if !roles.contains(where: { $0.compare(roleName, options: .caseInsensitive) == .orderedSame }) {
                roles.append(roleName)
            }
            grouped[teamName] = roles
        }

        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { teamName in
                TeamRoleSection(
                    teamName: teamName,
                    roles: (grouped[teamName] ?? []).sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    }
                )
            }
    }

    private var visiblePeopleSections: [TeamPeopleSection] {
        let grouped = Dictionary(grouping: visiblePeople) { row in
            normalizedTeamName(for: row.teamName)
        }

        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { teamName in
                TeamPeopleSection(
                    teamName: teamName,
                    rows: (grouped[teamName] ?? []).sorted {
                        let positionOrder = $0.positionName.localizedCaseInsensitiveCompare($1.positionName)
                        if positionOrder != .orderedSame { return positionOrder == .orderedAscending }
                        return $0.personName.localizedCaseInsensitiveCompare($1.personName) == .orderedAscending
                    }
                )
            }
    }

    private func normalizedTeamName(for rawTeamName: String?) -> String {
        let trimmed = rawTeamName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unassigned Team" : trimmed
    }

    private func clearAllWirelessAssignments() {
        mutateExtras { extras in
            extras.roleRulesByPosition = [:]
            extras.byKey = extras.byKey.reduce(into: [:]) { partialResult, entry in
                var value = entry.value
                value.assignments = []
                if value.personID != nil || value.imagePlacement != .identity {
                    partialResult[entry.key] = value
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasPlanningCenterLogin {
                infoBanner(
                    title: "Planning Center Login Required",
                    systemImage: "link.badge.plus",
                    message: "Log into Planning Center in App Settings before configuring this module."
                )
            } else if !hasPlanningCenterTabConfiguration {
                infoBanner(
                    title: "Planning Center Tab Setup Required",
                    systemImage: "exclamationmark.triangle",
                    message: "Configure a service, plan, and time in Tab Settings before using this Team Assignments module.",
                    actionLabel: "Open Tab Settings",
                    action: onOpenTabSettings
                )
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show header (Team Assignments)", isOn: persistedBinding(for: \.showHeader))
                    Toggle("Show team member status", isOn: persistedBinding(for: \.showTeamMemberStatus))
                    Toggle("Use simplified status styling", isOn: persistedBinding(for: \.useStatusStyledAssignmentCards))
                    Toggle("Hide declined positions", isOn: persistedBinding(for: \.hideDeclinedAssignments))
                    Toggle(
                        "Show person avatars",
                        isOn: Binding(
                            get: { extras().showPersonAvatars },
                            set: { newValue in mutateExtras { $0.showPersonAvatars = newValue } }
                        )
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sort assignments by").font(.headline)
                        Picker("Sort assignments by", selection: persistedBinding(for: \.teamAssignmentSortMode)) {
                            ForEach(PCOTeamAssignmentSortMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use 2 columns at").font(.headline)
                        HStack(spacing: 10) {
                            Text("Split dense teams into two columns")
                                .font(.subheadline)
                            Spacer()
                            Text("\(config.assignmentTwoColumnThreshold)+")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Stepper(
                                "",
                                value: persistedBinding(for: \.assignmentTwoColumnThreshold),
                                in: 1...50
                            )
                            .labelsHidden()
                        }
                    }
                }
            } label: {
                Text("Display")
            }
            #if os(iOS)
            .groupBoxStyle(ProminentGroupBoxStyle())
            #endif

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if availableModuleTeamNames.isEmpty {
                        Text("No cached team list is available yet. Refresh Planning Center data or open the tab settings to load teams.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Limit which teams this tile renders. If none are selected, the tile inherits the tab's team selection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(availableModuleTeamNames, id: \.self) { team in
                                let isSelected = selectedModuleTeamNames.contains(team)
                                Button {
                                    var updated = selectedModuleTeamNames
                                    if isSelected { updated.remove(team) } else { updated.insert(team) }
                                    updateModuleTeamSelection(updated)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .imageScale(.small)
                                        Text(team).lineLimit(1)
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } label: {
                Text("Teams")
            }
            #if os(iOS)
            .groupBoxStyle(ProminentGroupBoxStyle())
            #endif

            if !cachedAssignments.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Auto role rules are primary. Person-level mic / IEM assignments are secondary fallbacks, and role rules always render first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button {
                                isAssignmentsEditorPresented = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "music.mic.circle.fill")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Equipment Assignments")
                                        Text("\(availableRoleNames.count) roles • \(cachedAssignments.count) people")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Clear All Assignments", role: .destructive) {
                            clearAllWirelessAssignments()
                        }
                        .font(.caption)
                    }
                } label: {
                    Text("Assignments")
                }
                #if os(iOS)
                .groupBoxStyle(ProminentGroupBoxStyle())
                #endif
            }
        }
        .sheet(isPresented: $isAssignmentsEditorPresented) {
            PCOMicIEMAssignmentsEditorSheet(
                initialExtras: extras(),
                equipmentRoster: equipmentRoster,
                positionsByTeamName: availableTeamPositionsByTeamName,
                cachedAssignments: cachedAssignments,
                onSave: { updatedExtras in
                    config.teamExtras = updatedExtras
                    onPersist()
                    isAssignmentsEditorPresented = false
                },
                onCancel: {
                    isAssignmentsEditorPresented = false
                }
            )
        }
    }

    @ViewBuilder
    private func assignmentListSheet<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }
        }
        .padding(18)
#if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 680)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
    }

    @ViewBuilder
    private func infoBanner(
        title: String,
        systemImage: String,
        message: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel, let action {
                Button(actionLabel, action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct PCOEditorTeamTabs: View {
    let teams: [String]
    @Binding var selectedTeam: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                teamTab(title: "All Teams", team: nil)
                ForEach(teams, id: \.self) { team in
                    teamTab(title: team, team: team)
                }
            }
            .padding(.vertical, 2)
        }
        // `axes:` defaults to `.vertical`; explicit here since this is a
        // `ScrollView(.horizontal)`.
        .scrollIndicators(.hidden, axes: .horizontal)
    }

    @ViewBuilder
    private func teamTab(title: String, team: String?) -> some View {
        let isSelected = selectedTeam == team
        Button {
            selectedTeam = team
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct PCOMicIEMAssignmentsEditorSheet: View {
    private enum AssignmentMode: String, CaseIterable, Identifiable {
        case auto
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: return "Auto Assign"
            case .manual: return "Manual Assign"
            }
        }
    }

    @State private var draftExtras: PCOTeamAssignmentsExtras
    @State private var searchText: String = ""
    @State private var selectedTeam: String? = nil
    @State private var mode: AssignmentMode = .auto
    @FocusState private var isSearchFocused: Bool

    let equipmentRoster: DashboardRoster?
    let positionsByTeamName: [String: [String]]
    let cachedAssignments: [PCOTeamAssignmentRow]
    let onSave: (PCOTeamAssignmentsExtras) -> Void
    let onCancel: () -> Void

    init(
        initialExtras: PCOTeamAssignmentsExtras,
        equipmentRoster: DashboardRoster?,
        positionsByTeamName: [String: [String]],
        cachedAssignments: [PCOTeamAssignmentRow],
        onSave: @escaping (PCOTeamAssignmentsExtras) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draftExtras = State(initialValue: initialExtras)
        self.equipmentRoster = equipmentRoster
        self.positionsByTeamName = positionsByTeamName
        self.cachedAssignments = cachedAssignments
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var teamNames: [String] {
        let assignedTeams = Set(cachedAssignments.map { normalizedTeamName($0.teamName) })
        let catalogTeams = Set(
            positionsByTeamName.keys
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return Array(assignedTeams.union(catalogTeams))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var roleSections: [(teamName: String, roles: [String])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !positionsByTeamName.isEmpty {
            return positionsByTeamName.keys
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .compactMap { rawTeamName in
                    let teamName = normalizedTeamName(rawTeamName)
                    if let selectedTeam, selectedTeam != teamName { return nil }

                    let roles = deduplicatedPositions(positionsByTeamName[rawTeamName] ?? [])
                        .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
                    guard !roles.isEmpty else { return nil }
                    return (teamName, roles)
                }
        }

        var grouped: [String: [String]] = [:]

        for row in cachedAssignments {
            let teamName = normalizedTeamName(row.teamName)
            if let selectedTeam, selectedTeam != teamName { continue }

            let roleName = row.positionName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !roleName.isEmpty else { continue }
            if !query.isEmpty && !roleName.localizedCaseInsensitiveContains(query) { continue }

            var roles = grouped[teamName] ?? []
            if !roles.contains(where: { $0.localizedCaseInsensitiveCompare(roleName) == .orderedSame }) {
                roles.append(roleName)
            }
            grouped[teamName] = roles
        }

        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { teamName in
                (
                    teamName,
                    (grouped[teamName] ?? []).sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    }
                )
            }
    }

    private var personSections: [(teamName: String, rows: [PCOTeamAssignmentRow])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = cachedAssignments.filter { row in
            let teamName = normalizedTeamName(row.teamName)
            if let selectedTeam, selectedTeam != teamName { return false }
            if query.isEmpty { return true }
            return row.personName.localizedCaseInsensitiveContains(query) ||
                row.positionName.localizedCaseInsensitiveContains(query) ||
                teamName.localizedCaseInsensitiveContains(query)
        }

        let grouped = Dictionary(grouping: filtered) { normalizedTeamName($0.teamName) }
        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { teamName in
                (
                    teamName,
                    (grouped[teamName] ?? []).sorted {
                        let positionOrder = $0.positionName.localizedCaseInsensitiveCompare($1.positionName)
                        if positionOrder != .orderedSame { return positionOrder == .orderedAscending }
                        return $0.personName.localizedCaseInsensitiveCompare($1.personName) == .orderedAscending
                    }
                )
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(
                title: "Equipment Assignments",
                subtitle: "Role-based auto assignments are primary. Manual person assignments are fallbacks used only when no matching role rule exists."
            )

            assignmentModeTabs

            PCOEditorTeamTabs(teams: teamNames, selectedTeam: $selectedTeam)

            TextField(searchPrompt, text: $searchText)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch mode {
                    case .auto:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Auto Assign by Role")
                                .font(.headline)
                            Text("These always take precedence over manual person assignments of the same assignment type.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(roleSections, id: \.teamName) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.teamName)
                                    .font(.headline)
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)],
                                    alignment: .leading,
                                    spacing: 12
                                ) {
                                    ForEach(section.roles, id: \.self) { roleName in
                                        PCORoleRuleEditorCard(
                                            roleName: roleName,
                                            equipmentRoster: equipmentRoster,
                                            extras: $draftExtras
                                        )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if roleSections.isEmpty {
                            Text("No roles match the current filters.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                    case .manual:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Manual Person Assignments")
                                .font(.headline)
                            Text("Use these to fill in exceptions, extra equipment, or people without a matching role rule.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(personSections, id: \.teamName) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.teamName)
                                .font(.headline)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)],
                                alignment: .leading,
                                spacing: 12
                            ) {
                                ForEach(section.rows) { row in
                                    PCOPersonAssignmentEditorCard(
                                        row: row,
                                        equipmentRoster: equipmentRoster,
                                        extras: $draftExtras
                                    )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if personSections.isEmpty {
                            Text("No people match the current filters.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            footer
        }
        .padding(18)
        .onAppear { isSearchFocused = false }
#if os(macOS)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 760)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
    }

    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
            Spacer()
            Button("Save") { onSave(draftExtras.normalizedForPersistence()) }
                .buttonStyle(.borderedProminent)
        }
    }

    private func normalizedTeamName(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unassigned Team" : trimmed
    }

    private func deduplicatedPositions(_ rawPositions: [String]) -> [String] {
        var seen = Set<String>()
        return rawPositions.compactMap { rawPosition in
            let trimmed = rawPosition.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = PCORoleMatchKey.key(for: trimmed)
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var searchPrompt: String {
        switch mode {
        case .auto: return "Search roles…"
        case .manual: return "Search people…"
        }
    }

    private var assignmentModeTabs: some View {
        HStack(spacing: 0) {
            ForEach(Array(AssignmentMode.allCases.enumerated()), id: \.element.id) { index, tab in
                let isSelected = mode == tab
                Button {
                    mode = tab
                } label: {
                    Text(tab.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if index < AssignmentMode.allCases.count - 1 {
                    Color.clear
                        .frame(width: 6)
                }
            }
        }
        .frame(height: 40)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct PCORoleRuleEditorCard: View {
    let roleName: String
    let equipmentRoster: DashboardRoster?
    @Binding var extras: PCOTeamAssignmentsExtras

    var body: some View {
        let rule = ruleBinding
        VStack(alignment: .leading, spacing: 6) {
            Text(roleName)
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sortedAssignments(from: rule.wrappedValue)) { assignment in
                    PCOAssignmentEditorRow(
                        assignment: assignmentBinding(for: assignment.id, from: rule),
                        equipmentRoster: equipmentRoster,
                        inheritedAssignment: nil,
                        onRemove: { removeAssignment(id: assignment.id, from: rule) }
                    )
                }

                Menu {
                    addAssignmentMenuContent(
                        definitions: PCOAssignmentCatalog.definitions(equipmentRoster: equipmentRoster),
                        addTextAssignment: { typeID in addAssignment(typeID: typeID, to: rule) },
                        addRosterAssignment: { typeID, itemRef in
                            addAssignment(typeID: typeID, itemRef: itemRef, to: rule)
                        },
                        addWirelessAssignment: { typeID, ref in
                            addAssignment(typeID: typeID, itemRef: .wireless(ref), to: rule)
                        }
                    )
                } label: {
                    Label("Add Assignment", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var ruleBinding: Binding<PCORoleWirelessRule> {
        let key = PCORoleMatchKey.key(for: roleName)
        return Binding(
            get: { extras.roleRulesByPosition[key] ?? PCORoleWirelessRule() },
            set: { newValue in
                let normalized = newValue.normalizedForPersistence()
                if normalized.assignments.isEmpty {
                    extras.roleRulesByPosition.removeValue(forKey: key)
                } else {
                    extras.roleRulesByPosition[key] = normalized
                }
            }
        )
    }

    private func sortedAssignments(from rule: PCORoleWirelessRule) -> [PCOEquipmentAssignment] {
        PCOAssignmentCatalog.sortedAssignments(rule.assignments, equipmentRoster: equipmentRoster)
    }

    private func assignmentBinding(
        for id: UUID,
        from rule: Binding<PCORoleWirelessRule>
    ) -> Binding<PCOEquipmentAssignment> {
        Binding(
            get: {
                rule.wrappedValue.assignments.first(where: { $0.id == id }) ??
                    PCOEquipmentAssignment(id: id, assignmentTypeID: PCOAssignmentTypeID.mic)
            },
            set: { assignment in
                var updated = rule.wrappedValue
                if let index = updated.assignments.firstIndex(where: { $0.id == id }) {
                    updated.assignments[index] = assignment
                } else {
                    updated.assignments.append(assignment)
                }
                rule.wrappedValue = updated
            }
        )
    }

    @ViewBuilder
    private func addAssignmentMenuContent(
        definitions: [PCOAssignmentTypeDefinition],
        addTextAssignment: @escaping (String) -> Void,
        addRosterAssignment: @escaping (String, PCOEquipmentItemRef) -> Void,
        addWirelessAssignment: @escaping (String, PCOAssignmentWirelessRef) -> Void
    ) -> some View {
        ForEach(definitions) { definition in
            switch definition.valueKind {
            case .wirelessMic:
                wirelessAssignmentSubmenu(
                    title: definition.title,
                    typeID: definition.id,
                    category: .mic,
                    addWirelessAssignment: addWirelessAssignment
                )
            case .wirelessIEM:
                wirelessAssignmentSubmenu(
                    title: definition.title,
                    typeID: definition.id,
                    category: .iem,
                    addWirelessAssignment: addWirelessAssignment
                )
            case .text:
                Button(definition.title) {
                    addTextAssignment(definition.id)
                }
            case .rosterChoice:
                rosterAssignmentSubmenu(definition: definition, addRosterAssignment: addRosterAssignment)
            }
        }
    }

    @ViewBuilder
    private func wirelessAssignmentSubmenu(
        title: String,
        typeID: String,
        category: PCOWirelessChannelOption.Category,
        addWirelessAssignment: @escaping (String, PCOAssignmentWirelessRef) -> Void
    ) -> some View {
        let options = PCOWirelessOptions.availableChannels(for: category)
        Menu(title) {
            if options.isEmpty {
                Text(PCOWirelessOptions.emptyMessage(for: category))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options) { option in
                    Button(option.displayName) {
                        addWirelessAssignment(
                            typeID,
                            PCOAssignmentWirelessRef(
                                vendor: option.vendor,
                                deviceID: option.deviceID,
                                channelIndex: option.channelIndex,
                                deviceName: option.deviceName,
                                channelName: option.channelName
                            )
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rosterAssignmentSubmenu(
        definition: PCOAssignmentTypeDefinition,
        addRosterAssignment: @escaping (String, PCOEquipmentItemRef) -> Void
    ) -> some View {
        let options = definition.rosterOptions
        Menu(definition.title) {
            if options.isEmpty || definition.rosterColumnID == nil {
                Text("No roster values available")
                    .foregroundStyle(.secondary)
            } else if let columnID = definition.rosterColumnID {
                ForEach(options) { option in
                    Button(option.value) {
                        addRosterAssignment(
                            definition.id,
                            .rosterColumn(
                                columnID: columnID,
                                columnTitle: definition.title,
                                rowID: option.rowID,
                                value: option.value
                            )
                        )
                    }
                }
            }
        }
    }

    private func addAssignment(typeID: String, itemRef: PCOEquipmentItemRef? = nil, to rule: Binding<PCORoleWirelessRule>) {
        var updated = rule.wrappedValue
        updated.assignments.append(PCOEquipmentAssignment(assignmentTypeID: typeID, itemRef: itemRef))
        rule.wrappedValue = updated
    }

    private func removeAssignment(id: UUID, from rule: Binding<PCORoleWirelessRule>) {
        var updated = rule.wrappedValue
        updated.assignments.removeAll { $0.id == id }
        rule.wrappedValue = updated
    }
}

private struct PCOPersonAssignmentEditorCard: View {
    let row: PCOTeamAssignmentRow
    let equipmentRoster: DashboardRoster?
    @Binding var extras: PCOTeamAssignmentsExtras

    var body: some View {
        let metadata = metadataBinding
        let inheritedRule = extras.roleRulesByPosition[PCORoleMatchKey.key(for: row.positionName)]

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                PCOPersonAvatarView(row: row, diameter: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.personName).font(.subheadline.weight(.semibold))
                    Text(row.positionName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sortedAssignments(from: metadata.wrappedValue)) { assignment in
                    PCOAssignmentEditorRow(
                        assignment: assignmentBinding(for: assignment.id, from: metadata),
                        equipmentRoster: equipmentRoster,
                        inheritedAssignment: inheritedRule?.assignment(for: assignment.assignmentTypeID),
                        onRemove: { removeAssignment(id: assignment.id, from: metadata) }
                    )
                }

                Menu {
                    addAssignmentMenuContent(
                        definitions: PCOAssignmentCatalog.definitions(equipmentRoster: equipmentRoster),
                        addTextAssignment: { typeID in addAssignment(typeID: typeID, to: metadata) },
                        addRosterAssignment: { typeID, itemRef in
                            addAssignment(typeID: typeID, itemRef: itemRef, to: metadata)
                        },
                        addWirelessAssignment: { typeID, ref in
                            addAssignment(typeID: typeID, itemRef: .wireless(ref), to: metadata)
                        }
                    )
                } label: {
                    Label("Add Assignment", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
            }

            let inheritedAssignments = PCOAssignmentCatalog.sortedAssignments(
                (inheritedRule?.assignments ?? []).filter(\.isConfigured),
                equipmentRoster: equipmentRoster
            )
            if !inheritedAssignments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(inheritedAssignments) { assignment in
                        PCOInheritedAssignmentTag(
                            assignment: assignment,
                            equipmentRoster: equipmentRoster,
                            prefix: "Auto"
                        )
                    }
                }
                Text("Matching role assignments render first when they use the same assignment type.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var metadataBinding: Binding<PCOAssignmentMetadata> {
        let key = PCOAssignmentMatchKey.key(for: row)
        return Binding(
            get: { extras.byKey[key] ?? PCOAssignmentMetadata() },
            set: { newValue in
                let normalized = newValue.normalizedForPersistence()
                if normalized.personID == nil, normalized.imagePlacement == .identity, normalized.assignments.isEmpty {
                    extras.byKey.removeValue(forKey: key)
                } else {
                    extras.byKey[key] = normalized
                }
            }
        )
    }

    private func sortedAssignments(from metadata: PCOAssignmentMetadata) -> [PCOEquipmentAssignment] {
        PCOAssignmentCatalog.sortedAssignments(metadata.assignments, equipmentRoster: equipmentRoster)
    }

    private func assignmentBinding(
        for id: UUID,
        from metadata: Binding<PCOAssignmentMetadata>
    ) -> Binding<PCOEquipmentAssignment> {
        Binding(
            get: {
                metadata.wrappedValue.assignments.first(where: { $0.id == id }) ??
                    PCOEquipmentAssignment(id: id, assignmentTypeID: PCOAssignmentTypeID.mic)
            },
            set: { assignment in
                var updated = metadata.wrappedValue
                if let index = updated.assignments.firstIndex(where: { $0.id == id }) {
                    updated.assignments[index] = assignment
                } else {
                    updated.assignments.append(assignment)
                }
                metadata.wrappedValue = updated
            }
        )
    }

    @ViewBuilder
    private func addAssignmentMenuContent(
        definitions: [PCOAssignmentTypeDefinition],
        addTextAssignment: @escaping (String) -> Void,
        addRosterAssignment: @escaping (String, PCOEquipmentItemRef) -> Void,
        addWirelessAssignment: @escaping (String, PCOAssignmentWirelessRef) -> Void
    ) -> some View {
        ForEach(definitions) { definition in
            switch definition.valueKind {
            case .wirelessMic:
                wirelessAssignmentSubmenu(
                    title: definition.title,
                    typeID: definition.id,
                    category: .mic,
                    addWirelessAssignment: addWirelessAssignment
                )
            case .wirelessIEM:
                wirelessAssignmentSubmenu(
                    title: definition.title,
                    typeID: definition.id,
                    category: .iem,
                    addWirelessAssignment: addWirelessAssignment
                )
            case .text:
                Button(definition.title) {
                    addTextAssignment(definition.id)
                }
            case .rosterChoice:
                rosterAssignmentSubmenu(definition: definition, addRosterAssignment: addRosterAssignment)
            }
        }
    }

    @ViewBuilder
    private func wirelessAssignmentSubmenu(
        title: String,
        typeID: String,
        category: PCOWirelessChannelOption.Category,
        addWirelessAssignment: @escaping (String, PCOAssignmentWirelessRef) -> Void
    ) -> some View {
        let options = PCOWirelessOptions.availableChannels(for: category)
        Menu(title) {
            if options.isEmpty {
                Text(PCOWirelessOptions.emptyMessage(for: category))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options) { option in
                    Button(option.displayName) {
                        addWirelessAssignment(
                            typeID,
                            PCOAssignmentWirelessRef(
                                vendor: option.vendor,
                                deviceID: option.deviceID,
                                channelIndex: option.channelIndex,
                                deviceName: option.deviceName,
                                channelName: option.channelName
                            )
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rosterAssignmentSubmenu(
        definition: PCOAssignmentTypeDefinition,
        addRosterAssignment: @escaping (String, PCOEquipmentItemRef) -> Void
    ) -> some View {
        let options = definition.rosterOptions
        Menu(definition.title) {
            if options.isEmpty || definition.rosterColumnID == nil {
                Text("No roster values available")
                    .foregroundStyle(.secondary)
            } else if let columnID = definition.rosterColumnID {
                ForEach(options) { option in
                    Button(option.value) {
                        addRosterAssignment(
                            definition.id,
                            .rosterColumn(
                                columnID: columnID,
                                columnTitle: definition.title,
                                rowID: option.rowID,
                                value: option.value
                            )
                        )
                    }
                }
            }
        }
    }

    private func addAssignment(typeID: String, itemRef: PCOEquipmentItemRef? = nil, to metadata: Binding<PCOAssignmentMetadata>) {
        var updated = metadata.wrappedValue
        updated.assignments.append(PCOEquipmentAssignment(assignmentTypeID: typeID, itemRef: itemRef))
        metadata.wrappedValue = updated
    }

    private func removeAssignment(id: UUID, from metadata: Binding<PCOAssignmentMetadata>) {
        var updated = metadata.wrappedValue
        updated.assignments.removeAll { $0.id == id }
        metadata.wrappedValue = updated
    }
}

private struct PCOAssignmentEditorRow: View {
    @Binding var assignment: PCOEquipmentAssignment
    let equipmentRoster: DashboardRoster?
    let inheritedAssignment: PCOEquipmentAssignment?
    let onRemove: () -> Void

    var body: some View {
        let definition = PCOAssignmentCatalog.definition(
            for: assignment.assignmentTypeID,
            equipmentRoster: equipmentRoster
        )
        let isInherited = inheritedAssignment?.isConfigured == true

        VStack(alignment: .leading, spacing: 6) {
            // Assignment type label — always visible as a plain text above the
            // value picker on iOS where Menu button labels may not render.
            #if os(iOS)
            HStack(spacing: 4) {
                Menu {
                    ForEach(availableDefinitions(currentID: assignment.assignmentTypeID)) { definition in
                        Button(definition.title) {
                            assignment = switchedAssignment(to: definition)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(definition.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Group {
                switch definition.valueKind {
                case .wirelessMic:
                    PCOWirelessChannelPicker(
                        label: definition.title,
                        mode: .mic,
                        selection: wirelessBinding
                    )
                case .wirelessIEM:
                    PCOWirelessChannelPicker(
                        label: definition.title,
                        mode: .iem,
                        selection: wirelessBinding
                    )
                case .text:
                    TextField(
                        definition.placeholder,
                        text: textBinding,
                        prompt: Text("Unassigned")
                    )
                    .textFieldStyle(.roundedBorder)
                case .rosterChoice:
                    PCORosterAssignmentPicker(
                        label: definition.title,
                        options: definition.rosterOptions,
                        selection: rosterValueBinding(for: definition)
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(isInherited)
            #else
            HStack(alignment: .top, spacing: 8) {
                Menu {
                    ForEach(availableDefinitions(currentID: assignment.assignmentTypeID)) { definition in
                        Button(definition.title) {
                            assignment = switchedAssignment(to: definition)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(definition.title)
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Group {
                    switch definition.valueKind {
                    case .wirelessMic:
                        PCOWirelessChannelPicker(
                            label: definition.title,
                            mode: .mic,
                            selection: wirelessBinding
                        )
                    case .wirelessIEM:
                        PCOWirelessChannelPicker(
                            label: definition.title,
                            mode: .iem,
                            selection: wirelessBinding
                        )
                    case .text:
                        TextField(
                            definition.placeholder,
                            text: textBinding,
                            prompt: Text("Unassigned")
                        )
                        .textFieldStyle(.roundedBorder)
                    case .rosterChoice:
                        PCORosterAssignmentPicker(
                            label: definition.title,
                            options: definition.rosterOptions,
                            selection: rosterValueBinding(for: definition)
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(isInherited)

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            #endif

            if let inheritedAssignment, inheritedAssignment.isConfigured {
                PCOInheritedAssignmentTag(
                    assignment: inheritedAssignment,
                    equipmentRoster: equipmentRoster,
                    prefix: "Auto"
                )
            }
        }
    }

    private var wirelessBinding: Binding<PCOAssignmentWirelessRef?> {
        Binding(
            get: {
                guard case .wireless(let ref)? = assignment.itemRef else { return nil }
                return ref
            },
            set: { newValue in
                assignment.itemRef = newValue.map { .wireless($0) }
            }
        )
    }

    private var textBinding: Binding<String> {
        Binding(
            get: {
                guard case .text(let value)? = assignment.itemRef else { return "" }
                return value
            },
            set: { newValue in
                assignment.itemRef = newValue.isEmpty ? nil : .text(newValue)
            }
        )
    }

    private func availableDefinitions(currentID: String) -> [PCOAssignmentTypeDefinition] {
        PCOAssignmentCatalog.definitions(equipmentRoster: equipmentRoster)
    }

    private func switchedAssignment(to definition: PCOAssignmentTypeDefinition) -> PCOEquipmentAssignment {
        let existingText: String? = {
            guard case .text(let value)? = assignment.itemRef else { return nil }
            return value
        }()

        let nextItemRef: PCOEquipmentItemRef? = switch definition.valueKind {
        case .wirelessMic, .wirelessIEM:
            nil
        case .text:
            existingText.map(PCOEquipmentItemRef.text)
        case .rosterChoice:
            if let option = definition.rosterOptions.first,
               let columnID = definition.rosterColumnID {
                .rosterColumn(
                    columnID: columnID,
                    columnTitle: definition.title,
                    rowID: option.rowID,
                    value: option.value
                )
            } else {
                nil
            }
        }

        return PCOEquipmentAssignment(
            id: assignment.id,
            assignmentTypeID: definition.id,
            itemRef: nextItemRef
        )
    }

    private func rosterValueBinding(for definition: PCOAssignmentTypeDefinition) -> Binding<PCORosterValueOption?> {
        Binding(
            get: {
                guard case .rosterColumn(let columnID, _, let rowID, let value)? = assignment.itemRef,
                      columnID == definition.rosterColumnID else {
                    return nil
                }
                if let rowID,
                   let option = definition.rosterOptions.first(where: { $0.rowID == rowID }) {
                    return option
                }
                guard let value else { return nil }
                return definition.rosterOptions.first(where: {
                    $0.value.localizedCaseInsensitiveCompare(value) == .orderedSame
                })
            },
            set: { newValue in
                guard let columnID = definition.rosterColumnID else {
                    assignment.itemRef = nil
                    return
                }
                assignment.itemRef = newValue.map {
                    .rosterColumn(
                        columnID: columnID,
                        columnTitle: definition.title,
                        rowID: $0.rowID,
                        value: $0.value
                    )
                }
            }
        )
    }
}

private struct PCOInheritedAssignmentTag: View {
    let assignment: PCOEquipmentAssignment
    let equipmentRoster: DashboardRoster?
    let prefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(prefix) \(PCOAssignmentCatalog.title(for: assignment.assignmentTypeID, equipmentRoster: equipmentRoster))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(displayValue)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var displayValue: String {
        switch assignment.itemRef {
        case .wireless(let reference):
            if let channel = reference.channelName?.trimmingCharacters(in: .whitespacesAndNewlines), !channel.isEmpty {
                return channel
            }
            if let device = reference.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !device.isEmpty {
                return "\(device) CH \(reference.channelIndex)"
            }
            return "CH \(reference.channelIndex)"
        case .rosterColumn(_, let columnTitle, _, let value):
            return value ?? columnTitle ?? "Roster value"
        case .text(let value):
            return value
        case nil:
            return "Unassigned"
        }
    }
}
