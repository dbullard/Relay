//
//  RosterPickerModule.swift
//  Relay
//
//  Created by OpenAI Codex on 4/14/26.
//

import SwiftUI

struct RosterPickerModuleView: View {
    let model: RosterPickerModuleModel
    let tab: DashboardTab

    private var resolvedRoster: (columns: [DashboardRosterColumn], rows: [DashboardRosterRow]) {
        if model.selectedRosterID != nil,
           let cols = model.cachedRosterColumns,
           let rows = model.cachedRosterRows {
            return (cols, rows)
        }
        return (tab.rosterColumns, tab.rosterRows)
    }

    private var selectedColumn: DashboardRosterColumn? {
        let columns = resolvedRoster.columns
        guard let id = model.selectedColumnID else { return nil }
        return columns.first(where: { $0.id.uuidString == id })
    }

    private var selectedRow: DashboardRosterRow? {
        let rows = resolvedRoster.rows
        guard let id = model.selectedRowID else { return nil }
        return rows.first(where: { $0.id == id })
    }

    private var selectedValue: String? {
        guard let row = selectedRow, let columnID = model.selectedColumnID else { return nil }
        return row.values[columnID]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? row.values[columnID]
            : nil
    }

    private var rowIndex: Int? {
        guard let row = selectedRow else { return nil }
        guard let index = resolvedRoster.rows.firstIndex(where: { $0.id == row.id }) else { return nil }
        return index + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = model.header?.trimmingCharacters(in: .whitespacesAndNewlines), !header.isEmpty {
                headerView(header)
            }

            if let selectedValue, !selectedValue.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Text(selectedValue)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)

                    if model.showsColumnName, let column = selectedColumn {
                        metaChip(column.title)
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func headerView(_ text: String) -> some View {
        if model.showsHeaderBackground {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
        } else {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(emptySubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyTitle: String {
        if resolvedRoster.columns.isEmpty {
            return "No roster columns"
        }
        if resolvedRoster.rows.isEmpty {
            return "No roster rows"
        }
        if selectedColumn == nil {
            return "Choose a column"
        }
        if selectedRow == nil {
            return "Choose a row"
        }
        return "No value"
    }

    private var emptySubtitle: String {
        if resolvedRoster.columns.isEmpty || resolvedRoster.rows.isEmpty {
            return "Open Rosters to add columns and data."
        }
        if selectedColumn == nil || selectedRow == nil {
            return "Open the module settings and select which roster column and row this picker should display."
        }
        return "The selected row does not contain data for this column."
    }
}

struct RosterPickerModuleSettingsView: View {
    @Binding var model: RosterPickerModuleModel
    @Binding var tab: DashboardTab
    var sharedRosters: [DashboardRoster] = []
    let onPersist: () -> Void

    private func persistDeferred() {
        DispatchQueue.main.async {
            onPersist()
        }
    }

    private var resolvedColumns: [DashboardRosterColumn] {
        if model.selectedRosterID != nil, let cols = model.cachedRosterColumns {
            return cols
        }
        return tab.rosterColumns
    }

    private var resolvedRows: [DashboardRosterRow] {
        if model.selectedRosterID != nil, let rows = model.cachedRosterRows {
            return rows
        }
        return tab.rosterRows
    }

    private var selectedColumn: DashboardRosterColumn? {
        guard let id = model.selectedColumnID else { return nil }
        return resolvedColumns.first(where: { $0.id.uuidString == id })
    }

    private var availableRows: [DashboardRosterRow] {
        guard let column = selectedColumn else { return resolvedRows }
        let key = column.id.uuidString
        return resolvedRows.filter { row in
            let value = row.values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !value.isEmpty
        }
    }

    private func rosterPickerLabel(_ roster: DashboardRoster) -> String {
        switch roster.kind {
        case .general:
            return roster.name
        case .people:
            return "\(roster.name) (People)"
        case .equipment:
            return "\(roster.name) (Equipment)"
        }
    }

    private func rowLabel(_ row: DashboardRosterRow, index: Int) -> String {
        if let column = selectedColumn {
            let value = row.values[column.id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return value
            }
        }

        for column in resolvedColumns {
            let value = row.values[column.id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return value
            }
        }

        return "Row \(index + 1)"
    }

    var body: some View {
        GroupBox("Picker Module") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Roster", selection: Binding(
                    get: { model.selectedRosterID?.uuidString ?? "" },
                    set: { newValue in
                        let newID = UUID(uuidString: newValue)
                        if model.selectedRosterID != newID {
                            model.selectedRosterID = newID
                            model.selectedColumnID = nil
                            model.selectedRowID = nil
                            // Cache the selected roster's data so the tile view can use it
                            if let id = newID, let roster = sharedRosters.first(where: { $0.id == id }) {
                                model.cachedRosterColumns = roster.columns
                                model.cachedRosterRows = roster.rows
                            } else {
                                model.cachedRosterColumns = nil
                                model.cachedRosterRows = nil
                            }
                        }
                        persistDeferred()
                    }
                )) {
                    Text("Tab default").tag("")
                    if sharedRosters.isEmpty {
                        Text("No shared rosters").tag("__none__")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sharedRosters) { roster in
                            Text(rosterPickerLabel(roster)).tag(roster.id.uuidString)
                        }
                    }
                }
                .pickerStyle(.menu)

                if sharedRosters.isEmpty {
                    Text("Create shared rosters in the Rosters panel to select them here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Header", text: Binding(
                    get: { model.header ?? "" },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.header = trimmed.isEmpty ? nil : newValue
                        persistDeferred()
                    }
                ))

                if resolvedColumns.isEmpty {
                    Text("Add roster columns and rows in Rosters before configuring this module.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Column", selection: Binding(
                        get: { model.selectedColumnID ?? "" },
                        set: { newValue in
                            model.selectedColumnID = newValue.isEmpty ? nil : newValue
                            if !availableRows.contains(where: { $0.id == model.selectedRowID }) {
                                model.selectedRowID = availableRows.first?.id
                            }
                            persistDeferred()
                        }
                    )) {
                        Text("Select…").tag("")
                        ForEach(resolvedColumns) { column in
                            Text(column.title).tag(column.id.uuidString)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Row", selection: Binding(
                        get: { model.selectedRowID?.uuidString ?? "" },
                        set: { newValue in
                            model.selectedRowID = UUID(uuidString: newValue)
                            persistDeferred()
                        }
                    )) {
                        Text("Select…").tag("")
                        ForEach(Array(availableRows.enumerated()), id: \.element.id) { index, row in
                            Text(rowLabel(row, index: index)).tag(row.id.uuidString)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(model.selectedColumnID == nil || availableRows.isEmpty)
                }

                Toggle("Show column name", isOn: Binding(
                    get: { model.showsColumnName },
                    set: { newValue in
                        model.showsColumnName = newValue
                        persistDeferred()
                    }
                ))
                .toggleStyle(.switch)

                Toggle("Show row number", isOn: Binding(
                    get: { model.showsRowNumber },
                    set: { newValue in
                        model.showsRowNumber = newValue
                        persistDeferred()
                    }
                ))
                .toggleStyle(.switch)

                Toggle("Show header background", isOn: Binding(
                    get: { model.showsHeaderBackground },
                    set: { newValue in
                        model.showsHeaderBackground = newValue
                        persistDeferred()
                    }
                ))
                .toggleStyle(.switch)
            }
        }
        .task(id: "\(model.selectedRosterID?.uuidString ?? "")|\(resolvedColumns.count)|\(resolvedRows.count)|\(model.selectedColumnID ?? "")|\(model.selectedRowID?.uuidString ?? "")") {
            guard model.selectedColumnID == nil, let firstColumn = resolvedColumns.first else { return }
            await Task.yield()
            await MainActor.run {
                model.selectedColumnID = firstColumn.id.uuidString
                if model.selectedRowID == nil {
                    model.selectedRowID = availableRows.first?.id
                }
            }
            persistDeferred()
        }
        .onAppear {
            guard let rosterID = model.selectedRosterID,
                  let roster = sharedRosters.first(where: { $0.id == rosterID }) else { return }
            model.cachedRosterColumns = roster.columns
            model.cachedRosterRows = roster.rows
            persistDeferred()
        }
    }
}

enum RosterPickerModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .rosterPicker(RosterPickerModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let model: RosterPickerModuleModel = {
            if case .rosterPicker(let model) = module.wrappedValue.kind {
                return model
            }
            return RosterPickerModuleModel()
        }()

        return AnyView(
            RosterPickerModuleView(model: model, tab: tab.wrappedValue)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }
}
