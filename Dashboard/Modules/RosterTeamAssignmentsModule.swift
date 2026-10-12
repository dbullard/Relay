//
//  RosterTeamAssignmentsModule.swift
//  Relay
//
//  Mirrors the PCO Team Assignments module but uses a People roster as
//  the data source. First pass: roster + column mapping, sort/group,
//  optional avatars, and per-row metadata storage keyed by roster row UUID.
//

import SwiftUI

// MARK: - Sort Modes

enum RosterTeamAssignmentSortMode: String, Codable, CaseIterable, Identifiable {
    case rosterOrder
    case position
    case personName
    case teamName

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rosterOrder: return "Roster Order"
        case .position:    return "Position"
        case .personName:  return "Person"
        case .teamName:    return "Team"
        }
    }
}

// MARK: - Equipment Item Ref (per-person notes / picks)

/// A single equipment slot pinned to a person in the roster. For first
/// pass we support a free-text note; equipment-roster column references
/// can be added later once we wire the picker UI.
struct RosterEquipmentItemRef: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var label: String = ""
    var text: String = ""

    init(id: UUID = UUID(), label: String = "", text: String = "") {
        self.id = id
        self.label = label
        self.text = text
    }
}

// MARK: - Per-row Metadata

struct RosterAssignmentMetadata: Codable, Equatable {
    var imagePlacement: PersonImagePlacement
    var equipmentItems: [RosterEquipmentItemRef]

    init(
        imagePlacement: PersonImagePlacement = .identity,
        equipmentItems: [RosterEquipmentItemRef] = []
    ) {
        self.imagePlacement = imagePlacement
        self.equipmentItems = equipmentItems
    }

    var isEmpty: Bool {
        imagePlacement == .identity
            && equipmentItems.allSatisfy { $0.text.isEmpty && $0.label.isEmpty }
    }
}

// MARK: - Extras (config-stored side data)

struct RosterTeamAssignmentsExtras: Codable, Equatable {
    /// Per-row metadata keyed by roster row UUID string for stable JSON.
    var byRowID: [String: RosterAssignmentMetadata]
    var showPersonAvatars: Bool

    init(
        byRowID: [String: RosterAssignmentMetadata] = [:],
        showPersonAvatars: Bool = false
    ) {
        self.byRowID = byRowID
        self.showPersonAvatars = showPersonAvatars
    }

    func metadata(for rowID: UUID) -> RosterAssignmentMetadata? {
        byRowID[rowID.uuidString]
    }

    mutating func setMetadata(_ metadata: RosterAssignmentMetadata?, for rowID: UUID) {
        let key = rowID.uuidString
        if let metadata, !metadata.isEmpty {
            byRowID[key] = metadata
        } else {
            byRowID.removeValue(forKey: key)
        }
    }
}

// MARK: - Module Configuration

struct RosterTeamAssignmentsConfig: Codable, Equatable {
    var selectedRosterID: UUID?
    var nameColumnID: UUID?
    var positionColumnID: UUID?
    var teamColumnID: UUID?
    var notesColumnID: UUID?
    var sortMode: RosterTeamAssignmentSortMode
    var groupByTeam: Bool
    var showHeader: Bool
    var extras: RosterTeamAssignmentsExtras

    init(
        selectedRosterID: UUID? = nil,
        nameColumnID: UUID? = nil,
        positionColumnID: UUID? = nil,
        teamColumnID: UUID? = nil,
        notesColumnID: UUID? = nil,
        sortMode: RosterTeamAssignmentSortMode = .rosterOrder,
        groupByTeam: Bool = false,
        showHeader: Bool = true,
        extras: RosterTeamAssignmentsExtras = RosterTeamAssignmentsExtras()
    ) {
        self.selectedRosterID = selectedRosterID
        self.nameColumnID = nameColumnID
        self.positionColumnID = positionColumnID
        self.teamColumnID = teamColumnID
        self.notesColumnID = notesColumnID
        self.sortMode = sortMode
        self.groupByTeam = groupByTeam
        self.showHeader = showHeader
        self.extras = extras
    }

    static func defaults() -> RosterTeamAssignmentsConfig {
        RosterTeamAssignmentsConfig()
    }
}

// MARK: - Derived Display Row

struct RosterTeamAssignmentDisplayRow: Identifiable, Equatable {
    let id: UUID            // roster row UUID
    let name: String
    let position: String
    let team: String?
    let notes: String?
}

// MARK: - Resolution Helpers

private enum RosterTeamAssignmentsResolver {

    static func resolveRoster(
        config: RosterTeamAssignmentsConfig,
        tab: DashboardTab,
        sharedRosters: [DashboardRoster]
    ) -> DashboardRoster? {
        if let id = config.selectedRosterID,
           let match = sharedRosters.first(where: { $0.id == id && $0.kind == .people }) {
            return match
        }
        return tab.sharedRoster(for: .people, from: sharedRosters)
            ?? sharedRosters.first(where: { $0.kind == .people })
    }

    /// Picks a column ID from config, falling back to a column whose title
    /// matches the requested label (case-insensitive).
    static func resolveColumnID(
        explicit: UUID?,
        titleHint: String,
        in roster: DashboardRoster
    ) -> UUID? {
        if let explicit, roster.columns.contains(where: { $0.id == explicit }) {
            return explicit
        }
        return roster.columns.first(where: {
            $0.title.localizedCaseInsensitiveCompare(titleHint) == .orderedSame
        })?.id
    }

    static func displayRows(
        config: RosterTeamAssignmentsConfig,
        roster: DashboardRoster
    ) -> [RosterTeamAssignmentDisplayRow] {
        let nameID = resolveColumnID(explicit: config.nameColumnID, titleHint: "Name", in: roster)
        let positionID = resolveColumnID(explicit: config.positionColumnID, titleHint: "Position", in: roster)
        let teamID = resolveColumnID(explicit: config.teamColumnID, titleHint: "Team", in: roster)
        let notesID = resolveColumnID(explicit: config.notesColumnID, titleHint: "Notes", in: roster)

        let rows: [RosterTeamAssignmentDisplayRow] = roster.rows.map { row in
            let name = nameID.flatMap { row.values[$0.uuidString] }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let position = positionID.flatMap { row.values[$0.uuidString] }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let team = teamID.flatMap { row.values[$0.uuidString] }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = notesID.flatMap { row.values[$0.uuidString] }?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return RosterTeamAssignmentDisplayRow(
                id: row.id,
                name: name,
                position: position,
                team: (team?.isEmpty ?? true) ? nil : team,
                notes: (notes?.isEmpty ?? true) ? nil : notes
            )
        }

        return sort(rows, mode: config.sortMode, roster: roster)
    }

    private static func sort(
        _ rows: [RosterTeamAssignmentDisplayRow],
        mode: RosterTeamAssignmentSortMode,
        roster: DashboardRoster
    ) -> [RosterTeamAssignmentDisplayRow] {
        switch mode {
        case .rosterOrder:
            return rows
        case .position:
            return rows.sorted {
                $0.position.localizedCaseInsensitiveCompare($1.position) == .orderedAscending
            }
        case .personName:
            return rows.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .teamName:
            return rows.sorted {
                ($0.team ?? "").localizedCaseInsensitiveCompare($1.team ?? "") == .orderedAscending
            }
        }
    }
}

// MARK: - Avatar (uses shared person-image folder, like PCO)

struct RosterPersonAvatarView: View {
    let name: String
    var placement: PersonImagePlacement = .identity
    var diameter: CGFloat = 44

    @AppStorage("dashboard_personImageFolder") private var personImageFolder: String = ""
    @AppStorage("dashboard_personImageFolderBookmark") private var personImageFolderBookmarkData: Data?
    @Environment(\.displayScale) private var displayScale

    @State private var resolved: Image?

    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.12))
            if let resolved {
                resolved
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(CGFloat(placement.scale))
                    .offset(
                        x: CGFloat(placement.offsetX) * diameter,
                        y: CGFloat(placement.offsetY) * diameter
                    )
            } else {
                Text(initials)
                    .font(.system(size: diameter * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: lookupKey) {
            await resolve()
        }
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        let parts = trimmed.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return chars.joined().uppercased()
    }

    private var targetMaxPixel: CGFloat {
        max(64, diameter * max(displayScale, 1) * 1.5)
    }

    private var lookupKey: String {
        [
            name,
            personImageFolder,
            String(personImageFolderBookmarkData?.count ?? 0),
            String(Int(targetMaxPixel))
        ].joined(separator: "|")
    }

    private func resolve() async {
        let lookupName = name
        let folder = personImageFolder
        let bookmark = personImageFolderBookmarkData
        let target = Int(targetMaxPixel.rounded(.up))
        let resolvedImage = await Task.detached(priority: .utility) {
            return PCOPersonImageResolver.image(
                forName: lookupName,
                personID: nil,
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
}

// MARK: - Tile View

struct RosterTeamAssignmentsModuleView: View {
    @Binding var config: RosterTeamAssignmentsConfig
    let tab: DashboardTab
    let sharedRosters: [DashboardRoster]

    private var resolvedRoster: DashboardRoster? {
        RosterTeamAssignmentsResolver.resolveRoster(
            config: config,
            tab: tab,
            sharedRosters: sharedRosters
        )
    }

    private var displayRows: [RosterTeamAssignmentDisplayRow] {
        guard let roster = resolvedRoster else { return [] }
        return RosterTeamAssignmentsResolver.displayRows(config: config, roster: roster)
    }

    private var groupedRows: [(team: String?, rows: [RosterTeamAssignmentDisplayRow])] {
        if !config.groupByTeam {
            return [(nil, displayRows)]
        }
        let grouped = Dictionary(grouping: displayRows) { $0.team ?? "" }
        return grouped
            .sorted { lhs, rhs in
                lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { (team: $0.key.isEmpty ? nil : $0.key, rows: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if resolvedRoster == nil {
                emptyState
            } else if displayRows.isEmpty {
                noRowsState
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        ForEach(Array(groupedRows.enumerated()), id: \.offset) { _, group in
            if let team = group.team, config.groupByTeam {
                Text(team.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(group.rows) { row in
                    rowCard(row)
                }
            }
        }
    }

    @ViewBuilder
    private func rowCard(_ row: RosterTeamAssignmentDisplayRow) -> some View {
        let metadata = config.extras.metadata(for: row.id)
        let showsAvatar = config.extras.showPersonAvatars

        HStack(alignment: .center, spacing: 10) {
            if showsAvatar {
                RosterPersonAvatarView(
                    name: row.name,
                    placement: metadata?.imagePlacement ?? .identity,
                    diameter: 44
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                if !row.position.isEmpty {
                    Text(row.position.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.09))
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }

                Text(row.name.isEmpty ? "—" : row.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let notes = row.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if let team = row.team, !config.groupByTeam {
                Text(team)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No People roster")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open Rosters and create a People roster to populate this module.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var noRowsState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Roster is empty")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add rows to the selected People roster to see them here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings Inspector

struct RosterTeamAssignmentsSettingsInspector: View {
    @Binding var config: RosterTeamAssignmentsConfig
    let tab: DashboardTab
    let sharedRosters: [DashboardRoster]
    var onPersist: () -> Void

    private var availablePeopleRosters: [DashboardRoster] {
        sharedRosters.filter { $0.kind == .people }
    }

    private var resolvedRoster: DashboardRoster? {
        RosterTeamAssignmentsResolver.resolveRoster(
            config: config,
            tab: tab,
            sharedRosters: sharedRosters
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            rosterPickerSection
            if let roster = resolvedRoster {
                columnMappingSection(roster: roster)
            } else {
                Text("Create a People roster in the Rosters manager to configure this module.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            displaySection
        }
    }

    // MARK: Roster picker

    @ViewBuilder
    private var rosterPickerSection: some View {
        GroupBox("People Roster") {
            VStack(alignment: .leading, spacing: 8) {
                if availablePeopleRosters.isEmpty {
                    Text("No People rosters exist. Create one from the Rosters manager.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("Roster", selection: Binding(
                        get: { config.selectedRosterID?.uuidString ?? "" },
                        set: { newValue in
                            config.selectedRosterID = UUID(uuidString: newValue)
                            // Reset column mapping when roster changes so titles re-resolve.
                            config.nameColumnID = nil
                            config.positionColumnID = nil
                            config.teamColumnID = nil
                            config.notesColumnID = nil
                            persistDeferred()
                        }
                    )) {
                        Text("Default People roster").tag("")
                        ForEach(availablePeopleRosters) { roster in
                            Text(roster.name).tag(roster.id.uuidString)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: Column mapping

    @ViewBuilder
    private func columnMappingSection(roster: DashboardRoster) -> some View {
        GroupBox("Column Mapping") {
            VStack(alignment: .leading, spacing: 8) {
                columnPicker(
                    label: "Name",
                    titleHint: "Name",
                    selection: Binding(
                        get: { config.nameColumnID },
                        set: { newValue in
                            config.nameColumnID = newValue
                            persistDeferred()
                        }
                    ),
                    columns: roster.columns
                )

                columnPicker(
                    label: "Position",
                    titleHint: "Position",
                    selection: Binding(
                        get: { config.positionColumnID },
                        set: { newValue in
                            config.positionColumnID = newValue
                            persistDeferred()
                        }
                    ),
                    columns: roster.columns
                )

                columnPicker(
                    label: "Team",
                    titleHint: "Team",
                    selection: Binding(
                        get: { config.teamColumnID },
                        set: { newValue in
                            config.teamColumnID = newValue
                            persistDeferred()
                        }
                    ),
                    columns: roster.columns,
                    allowsNone: true
                )

                columnPicker(
                    label: "Notes",
                    titleHint: "Notes",
                    selection: Binding(
                        get: { config.notesColumnID },
                        set: { newValue in
                            config.notesColumnID = newValue
                            persistDeferred()
                        }
                    ),
                    columns: roster.columns,
                    allowsNone: true
                )

                Text("Avatars are loaded from the People Images folder configured in Dashboard Settings, matched against each row's Name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func columnPicker(
        label: String,
        titleHint: String,
        selection: Binding<UUID?>,
        columns: [DashboardRosterColumn],
        allowsNone: Bool = false
    ) -> some View {
        let resolved = selection.wrappedValue ?? columns.first(where: {
            $0.title.localizedCaseInsensitiveCompare(titleHint) == .orderedSame
        })?.id

        let pickerContent = Picker(label, selection: Binding(
            get: { resolved?.uuidString ?? "" },
            set: { newValue in
                selection.wrappedValue = UUID(uuidString: newValue)
            }
        )) {
            if allowsNone {
                Text("None").tag("")
            } else if resolved == nil {
                Text("Select…").tag("")
            }
            ForEach(columns) { column in
                Text(column.title).tag(column.id.uuidString)
            }
        }
        .pickerStyle(.menu)

#if os(iOS)
        // On iOS .menu pickers only show the selected value — the label is invisible.
        // Show the field name explicitly so users understand what each picker maps.
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            pickerContent
        }
#else
        pickerContent
#endif
    }

    // MARK: Display options

    @ViewBuilder
    private var displaySection: some View {
        GroupBox("Display") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Sort by", selection: Binding(
                    get: { config.sortMode },
                    set: { newValue in
                        config.sortMode = newValue
                        persistDeferred()
                    }
                )) {
                    ForEach(RosterTeamAssignmentSortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Group by team", isOn: Binding(
                    get: { config.groupByTeam },
                    set: { newValue in
                        config.groupByTeam = newValue
                        persistDeferred()
                    }
                ))
                .toggleStyle(.switch)

                Toggle("Show person avatars", isOn: Binding(
                    get: { config.extras.showPersonAvatars },
                    set: { newValue in
                        config.extras.showPersonAvatars = newValue
                        persistDeferred()
                    }
                ))
                .toggleStyle(.switch)
            }
        }
    }

    // MARK: Helpers

    private func persistDeferred() {
        DispatchQueue.main.async {
            onPersist()
        }
    }
}

// MARK: - Plugin

enum RosterTeamAssignmentsModulePlugin {}

extension RosterTeamAssignmentsModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .rosterTeamAssignments }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let configBinding = Binding<RosterTeamAssignmentsConfig>(
            get: {
                module.wrappedValue.rosterTeamAssignmentsConfig ?? RosterTeamAssignmentsConfig.defaults()
            },
            set: { newValue in
                var updated = module.wrappedValue
                updated.rosterTeamAssignmentsConfig = newValue
                module.wrappedValue = updated
            }
        )

        return AnyView(
            RosterTeamAssignmentsModuleView(
                config: configBinding,
                tab: tab.wrappedValue,
                sharedRosters: []
            )
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        // The real inspector is wired in DashboardTileEditView with full
        // tab + roster context. Plugin-level settings stay empty.
        AnyView(EmptyView())
    }
}
