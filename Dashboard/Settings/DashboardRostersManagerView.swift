//
//  DashboardRostersManagerView.swift
//  Relay
//
//  Created by OpenAI Codex on 5/6/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DashboardRostersManagerView: View {
    @Binding private var sourceRosters: [DashboardRoster]
    @Binding private var sourceTabs: [DashboardTab]
    @Binding private var selectedTabIndex: Int

    @Environment(\.dismiss) private var dismiss

    @State private var draftRosters: [DashboardRoster]
    @State private var draftTabs: [DashboardTab]
    @State private var selectedRosterID: UUID?
    @State private var isImportPickerPresented = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var importedWorkbook: RosterImportWorkbook?
    @State private var showsImportReview = false
    @State private var importTargetRosterID: UUID?
    @FocusState private var focusedField: RosterManagerFocusedField?

    private let columnWidth: CGFloat = 180
    private let rowLabelWidth: CGFloat = 54
    private let spreadsheetRowHeight: CGFloat = 40
    private let spreadsheetHeaderHeight: CGFloat = 44

    private static let maxRosterColumns = 12
    private static let maxRosterRows = 250
    private static let protectedPeopleColumnTitles: Set<String> = ["name", "position", "team"]

    private enum RosterManagerFocusedField: Hashable {
        case rosterName
    }

    init(
        rosters: Binding<[DashboardRoster]>,
        tabs: Binding<[DashboardTab]>,
        selectedTabIndex: Binding<Int>,
        // Test-only seam: production call sites rely on `.onAppear` to select
        // the first roster. Assigning `@State` after `init()` doesn't reliably
        // stick outside a live SwiftUI view graph, so RelayTests seeds the
        // initial selection through the same `State(initialValue:)` path
        // `draftRosters`/`draftTabs` already use below.
        initialSelectedRosterID: UUID? = nil
    ) {
        self._sourceRosters = rosters
        self._sourceTabs = tabs
        self._selectedTabIndex = selectedTabIndex
        self._draftRosters = State(initialValue: rosters.wrappedValue)
        self._draftTabs = State(initialValue: tabs.wrappedValue)
        self._selectedRosterID = State(initialValue: initialSelectedRosterID)
    }

    private var selectedRosterIndex: Int? {
        guard let selectedRosterID else { return nil }
        return draftRosters.firstIndex(where: { $0.id == selectedRosterID })
    }

    private var selectedRoster: DashboardRoster? {
        guard let selectedRosterIndex else { return nil }
        return draftRosters[selectedRosterIndex]
    }

    private var hasChanges: Bool {
        draftRosters != sourceRosters || draftTabs != sourceTabs
    }

    private var selectedTabName: String {
        guard draftTabs.indices.contains(selectedTabIndex) else { return "Current Tab" }
        return draftTabs[selectedTabIndex].name
    }

    private var attachedTabCount: Int {
        guard let selectedRosterID else { return 0 }
        return draftTabs.reduce(into: 0) { result, tab in
            if tab.attachedRosterIDs.contains(selectedRosterID) {
                result += 1
            }
        }
    }

    private var rosterNameBinding: Binding<String> {
        Binding(
            get: { selectedRoster?.name ?? "" },
            set: { newValue in
                updateSelectedRoster { $0.name = newValue }
            }
        )
    }

    private var rosterKindBinding: Binding<DashboardRosterKind> {
        Binding(
            get: { selectedRoster?.kind ?? .general },
            set: { newValue in
                updateSelectedRoster { $0.kind = newValue }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPane
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 640, idealHeight: 720)
        .onAppear {
            normalizeRosterRows()
            normalizeRosterNames()
            if selectedRosterID == nil {
                selectedRosterID = draftRosters.first?.id
            }
            clearInitialTextFocus()
        }
        .onChange(of: selectedRosterID, initial: false) { oldValue, _ in
            normalizeRosterName(for: oldValue)
        }
        .onChange(of: focusedField, initial: false) { oldValue, newValue in
            if oldValue == .rosterName && newValue != .rosterName {
                normalizeRosterName(for: selectedRosterID)
            }
        }
        .fileImporter(
            isPresented: $isImportPickerPresented,
            allowedContentTypes: RosterImportParser.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                beginImport(from: url)
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsImportReview) {
            if let importedWorkbook {
                RosterImportReviewView(
                    workbook: importedWorkbook,
                    onCancel: {
                        showsImportReview = false
                        self.importedWorkbook = nil
                        importTargetRosterID = nil
                    },
                    onImport: { mode, columns, rows in
                        applyImportedRoster(mode: mode, columns: columns, rows: rows)
                        showsImportReview = false
                        self.importedWorkbook = nil
                        importTargetRosterID = nil
                    }
                )
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rosters")
                    .font(.title2.bold())
                Spacer()
                Menu {
                    Button("New General Roster") {
                        createRoster(kind: .general)
                    }
                    Button("New Equipment Roster") {
                        createRoster(kind: .equipment)
                    }
                    Button("New People Roster") {
                        createRoster(kind: .people)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Shared rosters live at the document level and can be attached to multiple tabs.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selectedRosterID) {
                ForEach(DashboardRosterKind.allCases) { kind in
                    let items = draftRosters.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Section(kind.title) {
                            ForEach(items) { roster in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(roster.name)
                                    Text("\(roster.columns.count) cols • \(roster.rows.count) rows")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(roster.id)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Delete Roster", role: .destructive) {
                                        selectedRosterID = roster.id
                                        deleteSelectedRoster()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isImporting)

                Spacer()

                Button("Done") {
                    commitChanges()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!hasChanges || isImporting)
            }
        }
        .padding(18)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var detailPane: some View {
        Group {
            if selectedRoster != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        rosterHeader
                        rosterAttachmentCard
                        rosterSpreadsheetCard
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(24)
            } else {
                ContentUnavailableView(
                    "No Roster Selected",
                    systemImage: "list.dash.badge.ellipsis",
                    description: Text("Create a shared roster to start building General, Equipment, or People data.")
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rosterHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Roster Name", text: rosterNameBinding)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .rosterName)
                .onSubmit {
                    normalizeRosterName(for: selectedRosterID)
                }

            Picker("Roster Type", selection: rosterKindBinding) {
                ForEach(DashboardRosterKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(rosterDescriptionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rosterAttachmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tab Usage")
                .font(.headline)

            Text("Shared rosters apply to every tab by default. Deselect any tabs that should not see this roster. General rosters keep legacy roster modules working today. Equipment and People rosters feed the newer assignment flows.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                attachedTabCount == draftTabs.count && !draftTabs.isEmpty
                    ? "Attached to all \(draftTabs.count) tabs"
                    : "Attached to \(attachedTabCount) of \(draftTabs.count) tabs",
                systemImage: attachedTabCount == draftTabs.count && !draftTabs.isEmpty ? "checkmark.circle.fill" : "square.stack.3d.up"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(attachedTabCount == draftTabs.count && !draftTabs.isEmpty ? .green : .secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(draftTabs) { tab in
                    // Identity is the tab's stable UUID; index is re-resolved per
                    // tab.id so a delete/reorder elsewhere in the list can't
                    // misattach this toggle to the wrong tab's attachment state.
                    // `tab` always comes from `draftTabs` in this same synchronous
                    // render pass, so the lookup provably can't fail; force-unwrap
                    // so a future refactor that breaks that invariant crashes loudly
                    // instead of silently retargeting tab 0.
                    let index = draftTabs.firstIndex(where: { $0.id == tab.id })!
                    Toggle(tab.name, isOn: Binding(
                        get: { isSelectedRosterAttached(toTabAt: index) },
                        set: { isOn in
                            setSelectedRosterAttachment(isOn, forTabAt: index)
                        }
                    ))
                }
            }

            Divider()

            Text("Default on \(selectedTabName)")
                .font(.subheadline.weight(.semibold))

            if !isSelectedRosterAttachedToCurrentTab {
                Text("Attach this roster to \(selectedTabName) to use it as that tab’s default roster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch selectedRoster?.kind {
            case .general:
                Toggle("Use as Default General Roster for This Tab", isOn: Binding(
                    get: { isSelectedRosterCurrentTabDefaultGeneral },
                    set: { isOn in
                        if isOn {
                            setSelectedRosterAsDefaultForCurrentTab(kind: .general)
                        } else if draftTabs.indices.contains(selectedTabIndex) {
                            draftTabs[selectedTabIndex].defaultGeneralRosterID = nil
                        }
                    }
                ))
            case .equipment:
                Toggle("Use as Default Equipment Roster for This Tab", isOn: Binding(
                    get: { isSelectedRosterCurrentTabDefaultEquipment },
                    set: { isOn in
                        if isOn {
                            setSelectedRosterAsDefaultForCurrentTab(kind: .equipment)
                        } else if draftTabs.indices.contains(selectedTabIndex) {
                            draftTabs[selectedTabIndex].defaultEquipmentRosterID = nil
                        }
                    }
                ))
            case .people:
                Toggle("Use as Default People Roster for This Tab", isOn: Binding(
                    get: { isSelectedRosterCurrentTabDefaultPeople },
                    set: { isOn in
                        if isOn {
                            setSelectedRosterAsDefaultForCurrentTab(kind: .people)
                        } else if draftTabs.indices.contains(selectedTabIndex) {
                            draftTabs[selectedTabIndex].defaultPeopleRosterID = nil
                        }
                    }
                ))
            case .none:
                EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var rosterSpreadsheetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spreadsheet")
                    .font(.headline)
                Spacer()
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Import") {
                    importTargetRosterID = selectedRosterID
                    isImportPickerPresented = true
                }
                .disabled(isImporting)
                Button("Add Column") {
                    addColumn()
                }
                .disabled((selectedRoster?.columns.count ?? 0) >= Self.maxRosterColumns)
                Button("Add Row") {
                    addRow()
                }
                .disabled((selectedRoster?.rows.count ?? 0) >= Self.maxRosterRows)
            }
            if let importErrorMessage, !importErrorMessage.isEmpty {
                Text(importErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selectedRoster?.columns.isEmpty != false || selectedRoster?.rows.isEmpty != false {
                Text("Use Add Column and Add Row to start building this roster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Color.clear
                                .frame(width: rowLabelWidth, height: 1)

                            ForEach(selectedRosterColumns, id: \.id) { column in
                                // Identity is the column's stable UUID; index is
                                // re-resolved per column.id so deleting one column
                                // mid-grid can't misattach this text field's edit
                                // state to a neighboring column. `column` always comes
                                // from `selectedRosterColumns` in this same synchronous
                                // render pass, so the lookup provably can't fail;
                                // force-unwrap so a future refactor that breaks that
                                // invariant crashes loudly instead of silently
                                // retargeting column 0.
                                let index = selectedRosterColumns.firstIndex(where: { $0.id == column.id })!
                                HStack(spacing: 6) {
                                    TextField("Column Name", text: columnTitleBinding(for: index))
                                        .textFieldStyle(.roundedBorder)
                                    if canDeleteColumn(at: index) {
                                        Button(role: .destructive) {
                                            deleteColumn(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        .help("Delete column")
                                    }
                                }
                                .frame(width: columnWidth)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Delete Column", role: .destructive) {
                                        deleteColumn(at: index)
                                    }
                                    .disabled(!canDeleteColumn(at: index))
                                }
                            }
                        }

                        Divider()

                        ForEach(selectedRosterRows, id: \.id) { row in
                            // Identity is the row's stable UUID; index is
                            // re-resolved per row.id so deleting a row above this
                            // one can't misattach this row's text-field edit
                            // state to a different row's data. `row` always comes
                            // from `selectedRosterRows` in this same synchronous
                            // render pass, so the lookup provably can't fail;
                            // force-unwrap so a future refactor that breaks that
                            // invariant crashes loudly instead of silently
                            // retargeting row 0.
                            let rowIndex = selectedRosterRows.firstIndex(where: { $0.id == row.id })!
                            HStack(alignment: .top, spacing: 8) {
                                HStack(spacing: 4) {
                                    if canDeleteRow(at: rowIndex) {
                                        Button(role: .destructive) {
                                            deleteRow(at: rowIndex)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        .help("Delete row")
                                    }
                                    Text("\(rowIndex + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: rowLabelWidth, alignment: .trailing)
                                .padding(.top, 10)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Delete Row", role: .destructive) {
                                        deleteRow(at: rowIndex)
                                    }
                                    .disabled(!canDeleteRow(at: rowIndex))
                                }

                                ForEach(selectedRosterColumns, id: \.id) { column in
                                    // Same reasoning as the header row above: `column`
                                    // always comes from `selectedRosterColumns` in this
                                    // same synchronous render pass, so force-unwrap
                                    // fails loudly instead of silently retargeting
                                    // column 0.
                                    let columnIndex = selectedRosterColumns.firstIndex(where: { $0.id == column.id })!
                                    TextField(
                                        "",
                                        text: cellBinding(rowIndex: rowIndex, columnIndex: columnIndex),
                                        axis: .vertical
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(1...3)
                                    .frame(width: columnWidth)
                                }
                            }
                        }
                    }
                    .padding(2)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 180,
                    maxHeight: 280
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var selectedRosterColumns: [DashboardRosterColumn] {
        selectedRoster?.columns ?? []
    }

    private var selectedRosterRows: [DashboardRosterRow] {
        selectedRoster?.rows ?? []
    }

    private var rosterDescriptionText: String {
        switch selectedRoster?.kind {
        case .general:
            return "General rosters power today’s picker and graph roster sources."
        case .equipment:
            return "Equipment rosters will expose column headers as assignment categories and the column values as available equipment options."
        case .people:
            return "People rosters are reserved for a future manual team-assignment flow."
        case .none:
            return ""
        }
    }

    private var isSelectedRosterAttachedToCurrentTab: Bool {
        guard let selectedRosterID, draftTabs.indices.contains(selectedTabIndex) else { return false }
        return draftTabs[selectedTabIndex].attachedRosterIDs.contains(selectedRosterID)
    }

    // Internal (not private) so RelayTests can verify roster/tab attachment
    // state directly.
    func isSelectedRosterAttached(toTabAt index: Int) -> Bool {
        guard let selectedRosterID, draftTabs.indices.contains(index) else { return false }
        return draftTabs[index].attachedRosterIDs.contains(selectedRosterID)
    }

    private var isSelectedRosterCurrentTabDefaultGeneral: Bool {
        guard let selectedRosterID, draftTabs.indices.contains(selectedTabIndex) else { return false }
        return draftTabs[selectedTabIndex].defaultGeneralRosterID == selectedRosterID
    }

    private var isSelectedRosterCurrentTabDefaultEquipment: Bool {
        guard let selectedRosterID, draftTabs.indices.contains(selectedTabIndex) else { return false }
        return draftTabs[selectedTabIndex].defaultEquipmentRosterID == selectedRosterID
    }

    private var isSelectedRosterCurrentTabDefaultPeople: Bool {
        guard let selectedRosterID, draftTabs.indices.contains(selectedTabIndex) else { return false }
        return draftTabs[selectedTabIndex].defaultPeopleRosterID == selectedRosterID
    }

    private func updateSelectedRoster(_ mutation: (inout DashboardRoster) -> Void) {
        guard let selectedRosterIndex else { return }
        mutation(&draftRosters[selectedRosterIndex])
    }

    private func beginImport(from url: URL) {
        Task {
            await MainActor.run {
                isImporting = true
                importErrorMessage = nil
            }

            let startedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if startedSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let workbook = try RosterImportParser.parse(url: url)
                await MainActor.run {
                    importedWorkbook = workbook
                    showsImportReview = true
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    private func applyImportedRoster(mode: RosterImportApplyMode, columns: [DashboardRosterColumn], rows: [DashboardRosterRow]) {
        guard let importTargetRosterID,
              let targetIndex = draftRosters.firstIndex(where: { $0.id == importTargetRosterID }) else {
            importErrorMessage = "The roster you imported into was deleted before the import finished. Nothing was changed."
            return
        }

        let merged = RosterImportMerge.apply(
            mode: mode,
            existingColumns: draftRosters[targetIndex].columns,
            existingRows: draftRosters[targetIndex].rows,
            importedColumns: columns,
            importedRows: rows
        )
        draftRosters[targetIndex].columns = merged.columns
        draftRosters[targetIndex].rows = merged.rows
    }

    private func clearInitialTextFocus() {
        focusedField = nil
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        #endif
    }

    private func normalizeRosterRows() {
        for rosterIndex in draftRosters.indices {
            var seen: Set<UUID> = []
            var didChange = false
            for rowIndex in draftRosters[rosterIndex].rows.indices {
                let rowID = draftRosters[rosterIndex].rows[rowIndex].id
                if seen.contains(rowID) {
                    draftRosters[rosterIndex].rows[rowIndex].id = UUID()
                    didChange = true
                }
                seen.insert(draftRosters[rosterIndex].rows[rowIndex].id)
            }
            if didChange == false {
                continue
            }
        }
    }

    private func normalizeRosterNames() {
        for roster in draftRosters {
            normalizeRosterName(for: roster.id)
        }
    }

    private func normalizeRosterName(for rosterID: UUID?) {
        guard let rosterID, let rosterIndex = draftRosters.firstIndex(where: { $0.id == rosterID }) else { return }
        let trimmedName = draftRosters[rosterIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            draftRosters[rosterIndex].name = uniqueRosterName(
                baseName: "\(draftRosters[rosterIndex].kind.title) Roster",
                excluding: rosterID
            )
        } else if trimmedName != draftRosters[rosterIndex].name {
            draftRosters[rosterIndex].name = uniqueRosterName(baseName: trimmedName, excluding: rosterID)
        }
    }

    private func uniqueRosterName(baseName: String, excluding rosterID: UUID? = nil) -> String {
        var nextName = baseName
        var suffix = 2
        let existingNames = Set(draftRosters.compactMap { roster -> String? in
            guard roster.id != rosterID else { return nil }
            let name = roster.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        })
        while existingNames.contains(nextName) {
            nextName = "\(baseName) \(suffix)"
            suffix += 1
        }
        return nextName
    }

    private func createRoster(kind: DashboardRosterKind) {
        let nextName = uniqueRosterName(baseName: "\(kind.title) Roster")

        let columns = defaultColumns(for: kind)
        let rows = defaultRows(for: kind)
        let roster = DashboardRoster(name: nextName, kind: kind, columns: columns, rows: rows)
        draftRosters.append(roster)
        for index in draftTabs.indices {
            draftTabs[index].attachedRosterIDs.append(roster.id)
        }
        selectedRosterID = roster.id
    }

    private func defaultColumns(for kind: DashboardRosterKind) -> [DashboardRosterColumn] {
        switch kind {
        case .people:
            return [
                DashboardRosterColumn(title: "Name"),
                DashboardRosterColumn(title: "Position"),
                DashboardRosterColumn(title: "Team"),
                DashboardRosterColumn(title: "Notes")
            ]
        case .general:
            return [DashboardRosterColumn(title: "Column 1")]
        case .equipment:
            return []
        }
    }

    private func defaultRows(for kind: DashboardRosterKind) -> [DashboardRosterRow] {
        switch kind {
        case .people:
            return [DashboardRosterRow()]
        case .general:
            return [DashboardRosterRow()]
        case .equipment:
            return []
        }
    }

    private func deleteSelectedRoster() {
        guard let selectedRosterID else { return }

        draftRosters.removeAll { $0.id == selectedRosterID }
        for index in draftTabs.indices {
            draftTabs[index].attachedRosterIDs.removeAll { $0 == selectedRosterID }
            if draftTabs[index].defaultGeneralRosterID == selectedRosterID {
                draftTabs[index].defaultGeneralRosterID = nil
            }
            if draftTabs[index].defaultEquipmentRosterID == selectedRosterID {
                draftTabs[index].defaultEquipmentRosterID = nil
            }
            if draftTabs[index].defaultPeopleRosterID == selectedRosterID {
                draftTabs[index].defaultPeopleRosterID = nil
            }
        }

        self.selectedRosterID = draftRosters.first?.id
    }

    private func attachSelectedRosterToCurrentTab() {
        guard let selectedRosterID, draftTabs.indices.contains(selectedTabIndex) else { return }
        if !draftTabs[selectedTabIndex].attachedRosterIDs.contains(selectedRosterID) {
            draftTabs[selectedTabIndex].attachedRosterIDs.append(selectedRosterID)
        }
    }

    private func detachSelectedRosterFromCurrentTab() {
        guard let selectedRosterID, draftTabs.indices.contains(selectedTabIndex) else { return }
        draftTabs[selectedTabIndex].attachedRosterIDs.removeAll { $0 == selectedRosterID }
        if draftTabs[selectedTabIndex].defaultGeneralRosterID == selectedRosterID {
            draftTabs[selectedTabIndex].defaultGeneralRosterID = nil
        }
        if draftTabs[selectedTabIndex].defaultEquipmentRosterID == selectedRosterID {
            draftTabs[selectedTabIndex].defaultEquipmentRosterID = nil
        }
        if draftTabs[selectedTabIndex].defaultPeopleRosterID == selectedRosterID {
            draftTabs[selectedTabIndex].defaultPeopleRosterID = nil
        }
    }

    private func setSelectedRosterAttachment(_ isAttached: Bool, forTabAt index: Int) {
        guard draftTabs.indices.contains(index) else { return }
        if isAttached {
            if !isSelectedRosterAttached(toTabAt: index), let selectedRosterID {
                draftTabs[index].attachedRosterIDs.append(selectedRosterID)
            }
            return
        }

        guard let selectedRosterID else { return }
        draftTabs[index].attachedRosterIDs.removeAll { $0 == selectedRosterID }
        if draftTabs[index].defaultGeneralRosterID == selectedRosterID {
            draftTabs[index].defaultGeneralRosterID = nil
        }
        if draftTabs[index].defaultEquipmentRosterID == selectedRosterID {
            draftTabs[index].defaultEquipmentRosterID = nil
        }
        if draftTabs[index].defaultPeopleRosterID == selectedRosterID {
            draftTabs[index].defaultPeopleRosterID = nil
        }
    }

    private func setSelectedRosterAsDefaultForCurrentTab(kind: DashboardRosterKind) {
        guard let selectedRosterID, draftTabs.indices.contains(selectedTabIndex) else { return }
        attachSelectedRosterToCurrentTab()
        switch kind {
        case .general:
            draftTabs[selectedTabIndex].defaultGeneralRosterID = selectedRosterID
        case .equipment:
            draftTabs[selectedTabIndex].defaultEquipmentRosterID = selectedRosterID
        case .people:
            draftTabs[selectedTabIndex].defaultPeopleRosterID = selectedRosterID
        }
    }

    private func commitChanges() {
        normalizeRosterName(for: selectedRosterID)
        normalizeRosterNames()
        normalizeRosterRows()
        sourceRosters = draftRosters
        sourceTabs = draftTabs
        dismiss()
    }

    private func addColumn() {
        updateSelectedRoster { roster in
            guard roster.columns.count < Self.maxRosterColumns else { return }
            roster.columns.append(DashboardRosterColumn(title: "Column \(roster.columns.count + 1)"))
        }
    }

    private func addRow() {
        updateSelectedRoster { roster in
            guard roster.rows.count < Self.maxRosterRows else { return }
            roster.rows.append(DashboardRosterRow())
        }
    }

    private func deleteRow(at rowIndex: Int) {
        guard canDeleteRow(at: rowIndex) else { return }
        updateSelectedRoster { roster in
            guard roster.rows.indices.contains(rowIndex) else { return }
            roster.rows.remove(at: rowIndex)
        }
    }

    // Internal (not private) so RelayTests can assert delete-eligibility
    // (e.g. row 0 can't be deleted) without duplicating this rule.
    func canDeleteRow(at rowIndex: Int) -> Bool {
        rowIndex > 0
    }

    private func canDeleteColumn(at columnIndex: Int) -> Bool {
        guard selectedRosterColumns.indices.contains(columnIndex), let selectedRoster else { return false }
        let title = selectedRosterColumns[columnIndex].title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if selectedRoster.kind == .people && Self.protectedPeopleColumnTitles.contains(title) {
            return false
        }
        return true
    }

    private func deleteColumn(at columnIndex: Int) {
        guard canDeleteColumn(at: columnIndex) else { return }
        updateSelectedRoster { roster in
            guard roster.columns.indices.contains(columnIndex) else { return }
            let removedColumnID = roster.columns[columnIndex].id.uuidString
            roster.columns.remove(at: columnIndex)
            for rowIndex in roster.rows.indices {
                roster.rows[rowIndex].values.removeValue(forKey: removedColumnID)
            }
        }
    }

    // Internal (not private) so RelayTests can verify column-title bindings
    // still resolve to the correct column after a mid-list deletion shifts
    // array positions — the exact scenario the ForEach identity-by-id fix
    // protects against.
    func columnTitleBinding(for columnIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard selectedRosterColumns.indices.contains(columnIndex) else { return "" }
                return selectedRosterColumns[columnIndex].title
            },
            set: { newValue in
                updateSelectedRoster { roster in
                    guard roster.columns.indices.contains(columnIndex) else { return }
                    roster.columns[columnIndex].title = newValue
                }
            }
        )
    }

    // Internal (not private) so RelayTests can verify cell bindings still
    // resolve to the correct row+column after a mid-list deletion shifts
    // array positions — the exact scenario the ForEach identity-by-id fix
    // protects against.
    func cellBinding(rowIndex: Int, columnIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard selectedRosterRows.indices.contains(rowIndex),
                      selectedRosterColumns.indices.contains(columnIndex) else {
                    return ""
                }
                let columnID = selectedRosterColumns[columnIndex].id.uuidString
                return selectedRosterRows[rowIndex].values[columnID] ?? ""
            },
            set: { newValue in
                updateSelectedRoster { roster in
                    guard roster.rows.indices.contains(rowIndex),
                          roster.columns.indices.contains(columnIndex) else {
                        return
                    }
                    let columnID = roster.columns[columnIndex].id.uuidString
                    roster.rows[rowIndex].values[columnID] = newValue
                }
            }
        )
    }
}
