import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SharedValuesWindow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = SharedValueStore.shared
    @State private var linkedVariables = LinkedDeviceVariableStore.shared
    @State private var syncedVariables = SyncedTabVariableStore.shared
    @State private var query = ""
    @State private var copiedName: String?
    @State private var showingCreateSheet = false
    @State private var editingManualValue: SharedValue?
    @State private var formattingClockValue: SharedValue?
    @State private var expandedConsoleIDs: Set<String> = []
    @State private var expandedPlanningCenterIDs: Set<String> = []
    @State private var planningCenterFilter: PlanningCenterVariableFilter = .all
    @State private var expandedRemoteGroups: Set<String> = []
    @ObservedObject private var devices = ExternalDevicesStore.shared
    @ObservedObject private var linkedPeople = LinkedComputerPersonVariableStore.shared
    private let picker = SharedValuePickerCoordinator.shared

    @State private var selectedCategory: SharedValueCategory?
    #if os(macOS)
    @State private var showsCategorySidebar = true
    @FocusState private var searchFocused: Bool
    #endif

    private var matchingValues: [SharedValue] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.snapshot.values.filter { value in
            q.isEmpty || value.name.localizedCaseInsensitiveContains(q) ||
                sourceDescription(for: value.binding).localizedCaseInsensitiveContains(q)
        }
    }

    private func category(for value: SharedValue) -> SharedValueCategory {
        switch value.binding {
        case .manual: return .manual
        case .computed: return .computed
        case .shure, .sennheiser: return .wireless
        case .osc: return .osc
        case .triggerPayload: return .automation
        case let .system(key):
            if key.hasPrefix("clock:") { return .clock }
            if key.hasPrefix("computer:") { return .syncedData }
            if key.hasPrefix("planningcenter:") { return .planningCenter }
            if key.hasPrefix("console:") { return .consoles }
            if key.hasPrefix("propresenter:") { return .proPresenter }
            if key.hasPrefix("transcription:") { return .transcription }
            if key.hasPrefix("roster:") { return .rosters }
            return .integrations
        }
    }

    private var visibleCategories: [SharedValueCategory] {
        SharedValueCategory.allCases.filter { category in
            if category == .syncedData || category == .computers { return true }
            return matchingValues.contains(where: { self.category(for: $0) == category }) ||
                (category == .computers && !linkedVariables.entries.isEmpty) ||
                (category == .osc && !store.snapshot.recentOSCAddresses.isEmpty) ||
                (category == .automation && !store.snapshot.recentTriggerValues.isEmpty)
        }
    }

    private var matchingPeople: [LinkedComputerPersonVariable] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return linkedPeople.variables.filter { person in
            q.isEmpty || person.name.localizedCaseInsensitiveContains(q) ||
                person.variableName.localizedCaseInsensitiveContains(q) ||
                person.sourceComputerName.localizedCaseInsensitiveContains(q)
        }
    }

    private var matchingLinkedVariables: [LinkedDeviceVariableEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return linkedVariables.entries.filter { entry in
            q.isEmpty || entry.value.name.localizedCaseInsensitiveContains(q) ||
                entry.deviceName.localizedCaseInsensitiveContains(q) || entry.tokenName.localizedCaseInsensitiveContains(q) ||
                (entry.value.kind?.title.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var matchingSyncedVariables: [SyncedTabVariableEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return syncedVariables.entries.filter { entry in
            q.isEmpty || entry.value.name.localizedCaseInsensitiveContains(q) ||
                entry.tabName.localizedCaseInsensitiveContains(q) || entry.deviceName.localizedCaseInsensitiveContains(q) ||
                entry.tokenName.localizedCaseInsensitiveContains(q) || (entry.value.kind?.title.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var matchingOSC: [OSCAddressObservation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.snapshot.recentOSCAddresses.filter { q.isEmpty || $0.address.localizedCaseInsensitiveContains(q) }
    }

    private var matchingTriggers: [TriggerValueObservation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.snapshot.recentTriggerValues.filter {
            q.isEmpty || "Trigger \($0.triggerID.uuidString.prefix(8)) \($0.field)".localizedCaseInsensitiveContains(q)
        }
    }

    private var resultCount: Int {
        matchingValues.filter { category(for: $0) != .planningCenter }.count + allMatchingPlanningCenterGroups.reduce(0) { $0 + $1.count } +
            matchingPeople.count + matchingLinkedVariables.count + matchingSyncedVariables.count + matchingOSC.count + matchingTriggers.count
    }

    private var visibleResultCount: Int {
        guard let selectedCategory else { return resultCount }
        if selectedCategory == .planningCenter { return matchingPlanningCenterGroups.reduce(0) { $0 + $1.count } }
        return categoryCount(selectedCategory)
    }

    private var categorySidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                categoryButton(nil, title: "All Variables", icon: "square.grid.2x2", count: resultCount)
                Text("Categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                ForEach(visibleCategories) { category in
                    categoryButton(category, title: category.title, icon: category.icon, count: categoryCount(category))
                }
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
    }

    private func categoryCount(_ category: SharedValueCategory) -> Int {
        if category == .syncedData {
            return matchingValues.filter { self.category(for: $0) == .syncedData || SharedValueSourceCoordinator.shared.syncedTabName(for: $0) != nil }.count + matchingPeople.count + matchingSyncedVariables.count
        }
        if category == .planningCenter { return allMatchingPlanningCenterGroups.reduce(0) { $0 + $1.count } }
        return matchingValues.filter { self.category(for: $0) == category }.count +
            (category == .computers ? matchingLinkedVariables.count : 0) +
            (category == .osc ? matchingOSC.count : 0) +
            (category == .automation ? matchingTriggers.count : 0)
    }

    private func categoryButton(_ category: SharedValueCategory?, title: String, icon: String, count: Int) -> some View {
        Button {
            selectedCategory = category
            if category == .planningCenter { expandPlanningCenterSections() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(selectedCategory == category ? Color.primary.opacity(0.10) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var matchingConsoleGroups: [ConsoleVariableGroup] {
        let grouped = Dictionary(grouping: matchingValues.filter { category(for: $0) == .consoles }) { value -> String in
            guard case let .system(key) = value.binding else { return "unknown" }
            return String(key.split(separator: ":").dropFirst().first ?? "unknown")
        }
        return grouped.map { id, values in
            let name = UUID(uuidString: id).flatMap { deviceID in
                devices.devices.first(where: { $0.id == deviceID })?.name
            } ?? "Console \(id.prefix(8))"
            return ConsoleVariableGroup(id: id, name: name, values: values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingPlanningCenterGroups: [PlanningCenterVariableTabGroup] {
        planningCenterGroups(filter: selectedCategory == .planningCenter ? planningCenterFilter : .all)
    }

    private var allMatchingPlanningCenterGroups: [PlanningCenterVariableTabGroup] {
        planningCenterGroups(filter: .all)
    }

    private func planningCenterGroups(filter: PlanningCenterVariableFilter) -> [PlanningCenterVariableTabGroup] {
        let values = matchingValues.filter { category(for: $0) == .planningCenter }
        let ids = Set(values.compactMap(PlanningCenterVariableOrganizer.tabID))
        let names = Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            SharedValueSourceCoordinator.shared.tabName(for: id).map { (id, $0) }
        })
        return PlanningCenterVariableOrganizer.organize(values, tabNames: names, query: query, filter: filter)
    }

    private func planningCenterExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedPlanningCenterIDs.contains(id) },
            set: { expanded in
                if expanded { expandedPlanningCenterIDs.insert(id) }
                else { expandedPlanningCenterIDs.remove(id) }
            }
        )
    }

    private func expandPlanningCenterSections() {
        for tab in matchingPlanningCenterGroups {
            expandedPlanningCenterIDs.insert("tab:\(tab.id)")
            expandedPlanningCenterIDs.formUnion(tab.sections.map { "section:\(tab.id):\($0.id)" })
        }
    }

    private var linkedComputerGroups: [RemoteComputerGroup] {
        remoteComputerGroups(matchingLinkedVariables.map { .linked($0) })
    }

    private var syncedComputerGroups: [RemoteComputerGroup] {
        let local = matchingValues.filter {
            category(for: $0) == .syncedData || SharedValueSourceCoordinator.shared.syncedTabName(for: $0) != nil
        }.map(RemoteVariableItem.local)
        return remoteComputerGroups(local + matchingPeople.map(RemoteVariableItem.person) +
            matchingSyncedVariables.map(RemoteVariableItem.synced))
    }

    private func remoteComputerGroups(_ items: [RemoteVariableItem]) -> [RemoteComputerGroup] {
        Dictionary(grouping: items, by: \.computerID).map { id, computerItems in
            let types = Dictionary(grouping: computerItems, by: \.kind).map { kind, typeItems in
                RemoteTypeGroup(kind: kind, items: typeItems.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                })
            }.sorted { $0.kind.title.localizedStandardCompare($1.kind.title) == .orderedAscending }
            return RemoteComputerGroup(id: id, name: computerItems[0].computerName, types: types)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func remoteGroup(_ group: RemoteComputerGroup, scope: String) -> some View {
        DisclosureGroup(isExpanded: remoteGroupExpanded("\(scope):\(group.id)")) {
            ForEach(group.types) { type in
                DisclosureGroup(isExpanded: remoteGroupExpanded("\(scope):\(group.id):\(type.id)")) {
                    ForEach(type.items) { item in
                        switch item {
                        case let .local(value): variableRow(value)
                        case let .person(person): personRow(person)
                        case let .linked(entry): linkedVariableRow(entry)
                        case let .synced(entry): syncedVariableRow(entry)
                        }
                    }
                } label: {
                    Label("\(type.kind.title) (\(type.items.count))", systemImage: type.kind.icon)
                }
                .listRowBackground(Color.clear)
            }
        } label: {
            Label("\(group.name) (\(group.count))", systemImage: "desktopcomputer")
                .font(.headline)
        }
        .listRowBackground(Color.clear)
    }

    private func remoteGroupExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedRemoteGroups.contains(id) },
            set: { expanded in
                if expanded { expandedRemoteGroups.insert(id) }
                else { expandedRemoteGroups.remove(id) }
            }
        )
    }

    private func variableRow(_ value: SharedValue, displayName: String? = nil) -> some View {
        let syncedTabName = SharedValueSourceCoordinator.shared.syncedTabName(for: value)
        return SharedValueRow(
            value: value,
            displayName: displayName,
            sourceDescription: sourceDescription(for: value.binding),
            syncedTabName: syncedTabName,
            copy: copy,
            edit: value.binding == .manual ? { editingManualValue = value } : nil,
            formatClock: isFormatableClockValue(value) ? { formattingClockValue = value } : nil,
            delete: value.isSuggested ? nil : { delete(value) }
        )
        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private func isFormatableClockValue(_ value: SharedValue) -> Bool {
        guard case let .system(key) = value.binding else { return false }
        return key == "clock:date" || key == "clock:time"
    }

    private var variableList: some View {
        List {
            ForEach(selectedCategory.map { [$0] } ?? visibleCategories.filter { $0 != .syncedData }) { category in
                Section {
                    if category == .computers {
                        ForEach(linkedComputerGroups) { group in remoteGroup(group, scope: "linked") }
                    } else if category == .syncedData {
                        ForEach(syncedComputerGroups) { group in remoteGroup(group, scope: "synced") }
                    } else if category == .planningCenter {
                        if selectedCategory == .planningCenter {
                            Picker("Planning Center variables", selection: $planningCenterFilter) {
                                ForEach(PlanningCenterVariableFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .listRowBackground(Color.clear)
                        }
                        ForEach(matchingPlanningCenterGroups) { group in
                            DisclosureGroup(isExpanded: planningCenterExpanded("tab:\(group.id)")) {
                                ForEach(group.sections) { section in
                                    DisclosureGroup(isExpanded: planningCenterExpanded("section:\(group.id):\(section.id)")) {
                                        ForEach(section.fields) { field in
                                            variableRow(field.value, displayName: field.label)
                                        }
                                        ForEach(section.items) { item in
                                            DisclosureGroup(isExpanded: planningCenterExpanded("item:\(group.id):\(section.id):\(item.id)")) {
                                                ForEach(item.fields) { field in
                                                    variableRow(field.value, displayName: field.label)
                                                }
                                            } label: {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Label("\(item.sortOrder.map { "\($0). " } ?? "")\(item.title) (\(item.fields.count))", systemImage: section.kind.icon)
                                                    if let teamName = item.teamName {
                                                        Text(teamName).font(.caption).foregroundStyle(.secondary)
                                                            .padding(.leading, 25)
                                                    }
                                                }
                                                .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .listRowBackground(Color.clear)
                                        }
                                    } label: {
                                        Label("\(section.kind.title) (\(section.count))", systemImage: section.kind.icon)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .listRowBackground(Color.clear)
                                }
                            } label: {
                                Label("\(group.name) (\(group.count))", systemImage: "calendar")
                                    .font(.headline)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } else if category == .consoles {
                        ForEach(matchingConsoleGroups) { group in
                            DisclosureGroup(isExpanded: Binding(
                                get: { expandedConsoleIDs.contains(group.id) },
                                set: { expanded in
                                    if expanded { expandedConsoleIDs.insert(group.id) }
                                    else { expandedConsoleIDs.remove(group.id) }
                                }
                            )) {
                                ForEach(group.values) { value in variableRow(value) }
                            } label: {
                                Label("\(group.name) (\(group.values.count))", systemImage: "slider.horizontal.3")
                                    .font(.headline)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(matchingValues.filter { self.category(for: $0) == category ||
                            (category == .syncedData && SharedValueSourceCoordinator.shared.syncedTabName(for: $0) != nil)
                        }) { value in variableRow(value) }
                    }
                    if category == .syncedData {
                        Text("These values come from synced tabs. Other variables are stored on this computer.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if category == .osc {
                        ForEach(matchingOSC) { observation in recentOSCRow(observation) }
                    }
                    if category == .automation {
                        ForEach(matchingTriggers) { observation in recentTriggerRow(observation) }
                    }
                } header: {
                    if selectedCategory == nil {
                        Label(category.title, systemImage: category.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if visibleResultCount == 0 {
                ContentUnavailableView(
                    selectedCategory == .syncedData ? "No Synced Tab Variables" :
                        selectedCategory == .computers ? "No Linked Computer Variables" :
                        selectedCategory == .planningCenter ? "No Planning Center Variables" : "No Variables",
                    systemImage: selectedCategory == .syncedData ? "arrow.triangle.2.circlepath" :
                        selectedCategory == .computers ? "desktopcomputer" :
                        selectedCategory == .planningCenter ? "calendar" : "number.square",
                    description: Text(selectedCategory == .syncedData
                        ? "Subscribe to a synced tab to see its variables here."
                        : selectedCategory == .computers
                            ? "Link a computer, turn on Share variables across devices for that link, and update Relay on both computers."
                            : selectedCategory == .planningCenter
                                ? "Try another search or filter, or refresh the Planning Center plan for this tab."
                            : "Try another search or choose a different category.")
                )
            }
        }
    }

    private func personRow(_ person: LinkedComputerPersonVariable) -> some View {
        Button {
            if picker.insertOrCopy(name: "person:\(person.variableName)") == .copied { copiedName = person.variableName }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: person.isDisconnected ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle")
                    .frame(width: 24).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name).font(.headline).foregroundStyle(.primary)
                    Label("Synced tab • \(person.sourceComputerName)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(Color.accentColor)
                    Text(person.availabilityDescription)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "plus").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private func linkedVariableRow(_ entry: LinkedDeviceVariableEntry) -> some View {
        Button {
            if picker.insertOrCopy(name: entry.tokenName) == .copied { copiedName = entry.value.name }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer").frame(width: 24).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.value.name).font(.headline).foregroundStyle(.primary)
                    Text("\(entry.deviceName) • \(entry.status == .disconnected ? "Disconnected" : "\(entry.status.rawValue.capitalized)")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(entry.value.payload?.displayValue ?? "—")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Image(systemName: "plus").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private func syncedVariableRow(_ entry: SyncedTabVariableEntry) -> some View {
        Button {
            if picker.insertOrCopy(name: entry.tokenName) == .copied { copiedName = entry.value.name }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath").frame(width: 24).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.value.name).font(.headline).foregroundStyle(.primary)
                    Text("\(entry.tabName) • \(entry.deviceName) • \(entry.status.rawValue.capitalized)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(entry.value.payload?.displayValue ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Image(systemName: "plus").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private func recentOSCRow(_ observation: OSCAddressObservation) -> some View {
        Button { pin(observation) } label: {
            recentRow(title: observation.address, subtitle: "Recent OSC • \(observation.payload.displayValue)", icon: "waveform.path")
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private func recentTriggerRow(_ observation: TriggerValueObservation) -> some View {
        Button { pin(observation) } label: {
            recentRow(title: "Trigger \(observation.triggerID.uuidString.prefix(8)) • \(observation.field)",
                      subtitle: "Recent automation • \(observation.payload.displayValue)", icon: "bolt")
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private func recentRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "plus").foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
    }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsCategorySidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left").frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle categories")

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search variables", text: $query)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .dashboardGlassControl(cornerRadius: 10)
                    Spacer(minLength: 0)
                    Button { showingCreateSheet = true } label: {
                        Label("New Variable", systemImage: "plus")
                    }
                }
                .padding(14)
                Divider()
                HStack(spacing: 0) {
                    categorySidebar
                        .frame(width: showsCategorySidebar ? 220 : 0)
                        .clipped()
                        .allowsHitTesting(showsCategorySidebar)
                    Rectangle().fill(Color.primary.opacity(0.12))
                        .frame(width: showsCategorySidebar ? 1 : 0)
                    variableList.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsCategorySidebar)
            }
            .frame(minWidth: 580, idealWidth: 760, minHeight: 500, idealHeight: 620)
            #else
            NavigationStack {
                variableList
                    .navigationTitle("Variables")
                    .searchable(text: $query, prompt: "Search variables")
                    .toolbar {
                        ToolbarItem { Button("New Variable", systemImage: "plus") { showingCreateSheet = true } }
                    }
            }
            #endif
        }
        .task { await store.load() }
        .onChange(of: query) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                expandedConsoleIDs.formUnion(matchingConsoleGroups.map(\.id))
                expandPlanningCenterSections()
                for tab in matchingPlanningCenterGroups {
                    for section in tab.sections {
                        expandedPlanningCenterIDs.formUnion(section.items.map { "item:\(tab.id):\(section.id):\($0.id)" })
                    }
                }
                for (scope, groups) in [("linked", linkedComputerGroups), ("synced", syncedComputerGroups)] {
                    for group in groups {
                        expandedRemoteGroups.insert("\(scope):\(group.id)")
                        expandedRemoteGroups.formUnion(group.types.map { "\(scope):\(group.id):\($0.id)" })
                    }
                }
            }
        }
        .onChange(of: planningCenterFilter) { _, _ in
            expandPlanningCenterSections()
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                for tab in matchingPlanningCenterGroups {
                    for section in tab.sections {
                        expandedPlanningCenterIDs.formUnion(section.items.map { "item:\(tab.id):\(section.id):\($0.id)" })
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            SharedValueCreationSheet(store: store)
        }
        .sheet(item: $editingManualValue) { value in
            ManualSharedValueEditSheet(value: value, store: store)
        }
        .sheet(item: $formattingClockValue) { value in
            ClockFormatSheet(value: value)
        }
        .alert("Variable Copied", isPresented: Binding(
            get: { copiedName != nil },
            set: { if !$0 { copiedName = nil } }
        )) {
            Button("OK", role: .cancel) { copiedName = nil }
        } message: {
            Text("\(copiedName ?? "Variable") copied — paste it where needed.")
        }
        #if os(macOS)
        .background(VariablesWindowActivationBehavior())
        #endif
    }

    private func sourceDescription(for binding: SharedValueBinding) -> String {
        switch binding {
        case .manual: return "Manual"
        case let .system(key):
            if key.hasPrefix("planningcenter:"),
               let tabPart = key.split(separator: ":").dropFirst().first,
               let tabID = UUID(uuidString: String(tabPart)) {
                let tabName = SharedValueSourceCoordinator.shared.tabName(for: tabID) ?? "Tab"
                return "Planning Center • \(tabName)"
            }
            if key.hasPrefix("console:"),
               let idPart = key.split(separator: ":").dropFirst().first,
               let deviceID = UUID(uuidString: String(idPart)),
               let device = devices.devices.first(where: { $0.id == deviceID }) {
                return "Console • \(device.name)"
            }
            let source = key.split(separator: ":").first.map(String.init) ?? "Relay"
            return "Relay • \(source.capitalized)"
        case let .computed(expression, _): return "Computed • \(expression)"
        case let .shure(deviceID, channel, field):
            let device = devices.devices.first(where: { $0.id == deviceID })
            let deviceName = device?.name ?? "Shure"
            let channelName = displayChannelName(channel: channel, cachedName: device?.shureChannelNames[channel] ?? devices.shureChannelNameCache[deviceID]?[channel])
            return "\(deviceName) • \(channelName) • \(field.label)"
        case let .sennheiser(deviceID, channel, field):
            let deviceName = devices.devices.first(where: { $0.id == deviceID })?.name ?? "Sennheiser"
            let channelName = displayChannelName(channel: channel, cachedName: devices.sennheiserChannelNameCache[deviceID]?[channel])
            return "\(deviceName) • \(channelName) • \(field.label)"
        case let .osc(address, _): return "OSC • \(address)"
        case let .triggerPayload(_, field, _): return "Automation • \(field)"
        }
    }

    private func displayChannelName(channel: Int, cachedName: String?) -> String {
        let name = (cachedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "CH \(channel)" : name
    }

    private func copy(_ value: SharedValue) {
        if picker.insertOrCopy(name: "shared:\(value.name)") == .copied {
            copiedName = value.name
        }
    }

    private func pin(_ observation: OSCAddressObservation) {
        let name = "osc_\(observation.address)"
        Task {
            _ = await store.createSuggested(
                baseName: name,
                binding: .osc(address: observation.address, payloadType: observation.payload.valueType)
            )
        }
    }

    private func pin(_ observation: TriggerValueObservation) {
        Task {
            let value = await store.createSuggested(
                baseName: "trigger_\(observation.triggerID.uuidString.prefix(8))_\(observation.field)",
                binding: .triggerPayload(
                    triggerID: observation.triggerID,
                    field: observation.field,
                    payloadType: observation.payload.valueType
                )
            )
            _ = await store.update(id: value.id, payload: observation.payload, at: observation.receivedAt)
        }
    }

    private func delete(_ value: SharedValue) {
        Task { await store.delete(id: value.id) }
    }
}

#if os(macOS)
private struct VariablesWindowActivationBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.hidesOnDeactivate = true }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.hidesOnDeactivate = true
    }
}
#endif

private struct ConsoleVariableGroup: Identifiable {
    let id: String
    let name: String
    let values: [SharedValue]
}

enum PlanningCenterVariableFilter: String, CaseIterable, Identifiable {
    case all, plan, rundown, assignments
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .plan: "Plan"
        case .rundown: "Rundown"
        case .assignments: "Teams"
        }
    }
}

enum PlanningCenterVariableSectionKind: String, CaseIterable, Identifiable {
    case plan, rundown, assignments
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plan: "Plan Details"
        case .rundown: "Rundown Items"
        case .assignments: "Team Assignments"
        }
    }
    var icon: String {
        switch self {
        case .plan: "calendar"
        case .rundown: "list.number"
        case .assignments: "person.3"
        }
    }
}

struct PlanningCenterVariableField: Identifiable {
    let value: SharedValue
    let label: String
    var id: UUID { value.id }
}

struct PlanningCenterVariableItemGroup: Identifiable {
    let id: String
    let title: String
    let sortOrder: Int?
    let teamName: String?
    let fields: [PlanningCenterVariableField]
}

struct PlanningCenterVariableSectionGroup: Identifiable {
    let kind: PlanningCenterVariableSectionKind
    let fields: [PlanningCenterVariableField]
    let items: [PlanningCenterVariableItemGroup]
    var id: String { kind.id }
    var count: Int { fields.count + items.reduce(0) { $0 + $1.fields.count } }
}

struct PlanningCenterVariableTabGroup: Identifiable {
    let id: UUID
    let name: String
    let sections: [PlanningCenterVariableSectionGroup]
    var count: Int { sections.reduce(0) { $0 + $1.count } }
}

enum PlanningCenterVariableOrganizer {
    private struct Entry {
        let value: SharedValue
        let kind: PlanningCenterVariableSectionKind
        let itemID: String?
        let field: String
    }

    static func tabID(for value: SharedValue) -> UUID? {
        guard case let .system(key) = value.binding else { return nil }
        let parts = key.split(separator: ":")
        guard parts.count >= 3, parts[0] == "planningcenter" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    static func organize(_ values: [SharedValue], tabNames: [UUID: String], query: String,
                         filter: PlanningCenterVariableFilter) -> [PlanningCenterVariableTabGroup] {
        let grouped = Dictionary(grouping: values.compactMap { value -> (UUID, Entry)? in
            guard let tabID = tabID(for: value), case let .system(key) = value.binding else { return nil }
            let parts = key.split(separator: ":").map(String.init)
            let kind: PlanningCenterVariableSectionKind
            let itemID: String?
            let field: String
            switch parts[2] {
            case "rundown" where parts.count >= 5:
                kind = .rundown; itemID = parts[3]; field = parts[4]
            case "assignment" where parts.count >= 6:
                kind = .assignments; itemID = parts[3] + ":" + parts[4]; field = parts[5]
            default:
                kind = .plan; itemID = nil; field = parts[2]
            }
            return (tabID, Entry(value: value, kind: kind, itemID: itemID, field: field))
        }, by: { $0.0 })
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceMatches = search.localizedCaseInsensitiveCompare("Planning Center") == .orderedSame ||
            search.localizedCaseInsensitiveCompare("PCO") == .orderedSame
        return grouped.compactMap { tabID, pairs -> PlanningCenterVariableTabGroup? in
            let name = tabNames[tabID] ?? "Tab \(tabID.uuidString.prefix(8))"
            let tabMatches = sourceMatches || (!search.isEmpty && name.localizedCaseInsensitiveContains(search))
            let entries = pairs.map(\.1)
            let sections = PlanningCenterVariableSectionKind.allCases.compactMap { kind -> PlanningCenterVariableSectionGroup? in
                guard filter == .all || filter.rawValue == kind.rawValue else { return nil }
                let sectionEntries = entries.filter { $0.kind == kind }
                let sectionMatches = !search.isEmpty && kind.title.localizedCaseInsensitiveContains(search)
                let fields: [PlanningCenterVariableField]
                let items: [PlanningCenterVariableItemGroup]
                if kind == .plan {
                    fields = sectionEntries.filter { tabMatches || sectionMatches || search.isEmpty || matches($0, search) }
                        .sorted { fieldRank($0.field) < fieldRank($1.field) }
                        .map { .init(value: $0.value, label: label(for: $0.field)) }
                    items = []
                } else {
                    fields = []
                    items = Dictionary(grouping: sectionEntries, by: { $0.itemID ?? "unknown" }).compactMap { itemID, itemEntries in
                        let title = itemTitle(kind: kind, entries: itemEntries, fallback: itemID)
                        guard search.isEmpty || tabMatches || sectionMatches ||
                                title.localizedCaseInsensitiveContains(search) || itemEntries.contains(where: { matches($0, search) }) else { return nil }
                        let order: Int? = itemEntries.first(where: { $0.field == "order" }).flatMap { entry in
                            if case let .number(number)? = entry.value.payload { return Int(number) }
                            return nil
                        }
                        let team = itemEntries.first(where: { $0.field == "team" })?.value.payload?.displayValue
                        return PlanningCenterVariableItemGroup(id: itemID, title: title, sortOrder: order, teamName: team,
                            fields: itemEntries.sorted { fieldRank($0.field) < fieldRank($1.field) }
                                .map { .init(value: $0.value, label: label(for: $0.field)) })
                    }.sorted { lhs, rhs in
                        if kind == .rundown, lhs.sortOrder != rhs.sortOrder {
                            return (lhs.sortOrder ?? Int.max) < (rhs.sortOrder ?? Int.max)
                        }
                        if kind == .assignments, lhs.teamName != rhs.teamName {
                            return (lhs.teamName ?? "").localizedStandardCompare(rhs.teamName ?? "") == .orderedAscending
                        }
                        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                    }
                }
                guard !fields.isEmpty || !items.isEmpty else { return nil }
                return .init(kind: kind, fields: fields, items: items)
            }
            guard !sections.isEmpty else { return nil }
            return .init(id: tabID, name: name, sections: sections)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func matches(_ entry: Entry, _ search: String) -> Bool {
        entry.value.name.localizedCaseInsensitiveContains(search) ||
            entry.value.payload?.displayValue.localizedCaseInsensitiveContains(search) == true ||
            label(for: entry.field).localizedCaseInsensitiveContains(search)
    }

    private static func itemTitle(kind: PlanningCenterVariableSectionKind, entries: [Entry], fallback: String) -> String {
        func text(_ field: String) -> String? {
            entries.first(where: { $0.field == field })?.value.payload?.displayValue
        }
        if kind == .rundown { return text("title") ?? "Item \(fallback)" }
        let position = text("position") ?? "Position"
        let person = text("person") ?? "Unassigned"
        return "\(position) • \(person)"
    }

    private static func label(for field: String) -> String {
        switch field {
        case "bpm": "BPM"
        case "ccli": "CCLI"
        case "is_header": "Header"
        default: field.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }

    private static func fieldRank(_ field: String) -> Int {
        let order = ["service_type_name", "plan_title", "plan_date", "service_time", "team_name",
                     "service_type_id", "plan_id", "order", "title", "time", "type", "key",
                     "length", "arrangement", "bpm", "ccli", "sequence", "notes", "is_header",
                     "person", "position", "team", "status", "service_times"]
        return order.firstIndex(of: field) ?? order.count
    }
}

@MainActor
private enum RemoteVariableItem: Identifiable {
    case local(SharedValue)
    case person(LinkedComputerPersonVariable)
    case linked(LinkedDeviceVariableEntry)
    case synced(SyncedTabVariableEntry)

    var id: String {
        switch self {
        case let .local(value): "local:\(value.id)"
        case let .person(person): "person:\(person.id)"
        case let .linked(entry): "linked:\(entry.id)"
        case let .synced(entry): "synced:\(entry.id)"
        }
    }

    var name: String {
        switch self {
        case let .local(value): value.name
        case let .person(person): person.name
        case let .linked(entry): entry.value.name
        case let .synced(entry): entry.value.name
        }
    }

    var computerName: String {
        switch self {
        case let .local(value): SharedValueSourceCoordinator.shared.syncedComputerName(for: value) ?? "Unknown computer"
        case let .person(person): person.sourceComputerName
        case let .linked(entry): entry.deviceName
        case let .synced(entry): entry.deviceName
        }
    }

    var computerID: String {
        switch self {
        case let .linked(entry): "device:\(entry.deviceID)"
        default: "name:\(computerName)"
        }
    }

    var kind: LinkedDeviceVariableKind {
        switch self {
        case let .local(value): LinkedDeviceVariableKind(binding: value.binding)
        case .person: .people
        case let .linked(entry): entry.value.kind ?? .other
        case let .synced(entry): entry.value.kind ?? .other
        }
    }
}

@MainActor
private struct RemoteTypeGroup: Identifiable {
    let kind: LinkedDeviceVariableKind
    let items: [RemoteVariableItem]
    var id: String { kind.rawValue }
}

@MainActor
private struct RemoteComputerGroup: Identifiable {
    let id: String
    let name: String
    let types: [RemoteTypeGroup]
    var count: Int { types.reduce(0) { $0 + $1.items.count } }
}

private extension LinkedDeviceVariableKind {
    var icon: String {
        switch self {
        case .clock: "clock"
        case .computers: "desktopcomputer"
        case .integrations: "puzzlepiece.extension"
        case .planningCenter: "calendar"
        case .consoles: "slider.horizontal.3"
        case .proPresenter: "play.rectangle"
        case .transcription: "waveform"
        case .rosters: "person.2"
        case .wireless: "antenna.radiowaves.left.and.right"
        case .osc: "waveform.path"
        case .automation: "bolt"
        case .computed: "function"
        case .manual: "pencil"
        case .people: "person.crop.circle"
        case .other: "number.square"
        }
    }
}

private enum SharedValueCategory: String, CaseIterable, Identifiable {
    case syncedData, clock, computers, integrations, planningCenter, consoles, proPresenter, transcription, rosters
    case wireless, osc, automation, computed, manual

    var id: String { rawValue }
    var title: String {
        switch self {
        case .syncedData: "From Synced Tabs"
        case .clock: "Clock"
        case .computers: "From Linked Computers"
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
        }
    }
    var icon: String {
        switch self {
        case .syncedData: "arrow.triangle.2.circlepath"
        case .clock: "clock"
        case .computers: "desktopcomputer"
        case .integrations: "puzzlepiece.extension"
        case .planningCenter: "calendar"
        case .consoles: "slider.horizontal.3"
        case .proPresenter: "play.rectangle"
        case .transcription: "waveform"
        case .rosters: "person.2"
        case .wireless: "antenna.radiowaves.left.and.right"
        case .osc: "waveform.path"
        case .automation: "bolt"
        case .computed: "function"
        case .manual: "pencil"
        }
    }
}

private enum ClockTimeZoneChoice: String, CaseIterable {
    case local = "Device local"
    case utc = "UTC"
    case custom = "Other time zone"
}

private struct ClockFormatPreset: Identifiable {
    let title: String
    let pattern: String
    var id: String { pattern }
}

private struct ClockFormatSheet: View {
    @Environment(\.dismiss) private var dismiss
    let value: SharedValue
    let key: String
    @State private var pattern: String
    @State private var selectedPreset: String
    @State private var timeZoneChoice: ClockTimeZoneChoice
    @State private var customTimeZone: String

    init(value: SharedValue) {
        self.value = value
        if case let .system(key) = value.binding { self.key = key }
        else { self.key = "clock:date" }
        let defaultPattern = key == "clock:date" ? "yyyy-MM-dd" : "HH:mm:ss"
        let preference = ClockFormatPreferences.load()[key]
        let savedPattern = preference?.pattern ?? defaultPattern
        _pattern = State(initialValue: savedPattern)
        let presetPatterns = key == "clock:date"
            ? ["yyyy-MM-dd", "MMM d, yyyy", "EEEE, MMMM d, yyyy", "M/d/yy"]
            : ["HH:mm:ss", "h:mm a", "h:mm:ss a", "HH:mm"]
        _selectedPreset = State(initialValue: presetPatterns.contains(savedPattern) ? savedPattern : "custom")
        let zone = preference?.timeZoneIdentifier
        _timeZoneChoice = State(initialValue: zone == nil ? .local : (zone == "UTC" ? .utc : .custom))
        _customTimeZone = State(initialValue: zone == "UTC" ? "" : (zone ?? ""))
    }

    private var presets: [ClockFormatPreset] {
        key == "clock:date"
            ? [.init(title: "ISO date", pattern: "yyyy-MM-dd"), .init(title: "Short date", pattern: "MMM d, yyyy"), .init(title: "Full date", pattern: "EEEE, MMMM d, yyyy"), .init(title: "Numeric date", pattern: "M/d/yy")]
            : [.init(title: "24-hour with seconds", pattern: "HH:mm:ss"), .init(title: "12-hour", pattern: "h:mm a"), .init(title: "12-hour with seconds", pattern: "h:mm:ss a"), .init(title: "24-hour", pattern: "HH:mm")]
    }

    private var selectedTimeZoneID: String? {
        switch timeZoneChoice {
        case .local: nil
        case .utc: "UTC"
        case .custom: customTimeZone.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var canSave: Bool {
        !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pattern.count <= 120 &&
            (selectedTimeZoneID == nil || TimeZone(identifier: selectedTimeZoneID!) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(value.name).font(.headline)
                Picker("Style", selection: $selectedPreset) {
                    ForEach(presets) { preset in Text(preset.title).tag(preset.pattern) }
                    Text("Custom").tag("custom")
                }
                .onChange(of: selectedPreset) { _, newValue in
                    if newValue != "custom" { pattern = newValue }
                }
                TextField("Date and time format", text: $pattern)
                    .onChange(of: pattern) { _, newValue in
                        if selectedPreset != "custom" && selectedPreset != newValue { selectedPreset = "custom" }
                    }
                Text("Use yyyy for year, MMMM for month, dd for day, HH or h for hour, mm for minute, ss for second, and a for AM/PM.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Time zone", selection: $timeZoneChoice) {
                    ForEach(ClockTimeZoneChoice.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                if timeZoneChoice == .custom {
                    TextField("Time zone, such as America/Chicago", text: $customTimeZone)
                }
                LabeledContent("Preview") {
                    Text(ClockFormatPreference(pattern: pattern, timeZoneIdentifier: selectedTimeZoneID)
                        .formatted(Date(), defaultTimeZone: .current))
                        .monospacedDigit()
                }
            }
            .navigationTitle(key == "clock:date" ? "Format Date" : "Format Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ClockFormatPreferences.save(
                            ClockFormatPreference(pattern: pattern, timeZoneIdentifier: selectedTimeZoneID), for: key
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 430, minHeight: 360)
    }
}

private enum SharedValueCreationSource: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case shure = "Shure Wireless"
    case sennheiser = "Sennheiser Wireless"
    case osc = "OSC Address"
    case computed = "Computed"

    var id: String { rawValue }
}

private struct SharedValueCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var devices = ExternalDevicesStore.shared
    let store: SharedValueStore

    @State private var name = ""
    @State private var source: SharedValueCreationSource = .manual
    @State private var deviceID: UUID?
    @State private var channel = 1
    @State private var field: WirelessSharedValueField = .batteryPercent
    @State private var oscAddress = ""
    @State private var oscType: SharedValueType = .number
    @State private var manualType: SharedValueType = .text
    @State private var manualText = ""
    @State private var manualNumber = 0.0
    @State private var manualBoolean = false
    @State private var expression = ""
    @State private var computedType: SharedValueType = .number

    private var wirelessDevices: [ExternalDeviceConfig] {
        let kind: ExternalDeviceKind = source == .shure ? .shureWireless : .sennheiserWireless
        return devices.devices.filter { $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Variable name", text: $name)

                Picker("Source", selection: $source) {
                    ForEach(SharedValueCreationSource.allCases) { Text($0.rawValue).tag($0) }
                }

                if source == .manual {
                    Picker("Value type", selection: $manualType) {
                        ForEach(SharedValueType.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    switch manualType {
                    case .text: TextField("Value", text: $manualText)
                    case .number: TextField("Value", value: $manualNumber, format: .number)
                    case .boolean: Toggle("Value", isOn: $manualBoolean)
                    case .payload: TextField("JSON payload", text: $manualText)
                    }
                }

                if source == .osc {
                    TextField("OSC address", text: $oscAddress)
                    Picker("Value type", selection: $oscType) {
                        ForEach(SharedValueType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }

                if source == .computed {
                    TextField("Expression, such as #{count} * 2", text: $expression)
                    Picker("Result type", selection: $computedType) {
                        ForEach([SharedValueType.text, .number, .boolean], id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                }

                if source == .shure || source == .sennheiser {
                    if wirelessDevices.isEmpty {
                        Text("Add a \(source.rawValue) device in Settings before pinning telemetry.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Device", selection: $deviceID) {
                            Text("Choose device").tag(UUID?.none)
                            ForEach(wirelessDevices) { device in
                                Text(device.name).tag(Optional(device.id))
                            }
                        }
                        Stepper("Channel \(channel)", value: $channel, in: 1...128)
                        Picker("Field", selection: $field) {
                            ForEach(WirelessSharedValueField.allCases, id: \.self) { field in
                                Text(field.label).tag(field)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Variable")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(!canAdd)
                }
            }
            .onChange(of: source) { _, _ in deviceID = wirelessDevices.first?.id }
            .onAppear { deviceID = wirelessDevices.first?.id }
        }
        .frame(minWidth: 360, minHeight: 300)
    }

    private var canAdd: Bool {
        !normalizeSharedValueName(name).isEmpty && (source != .osc || !oscAddress.isEmpty) &&
            (source != .computed || !expression.isEmpty) &&
            (source != .manual || manualType != .payload || validJSON(manualText)) &&
            (source != .shure && source != .sennheiser || deviceID != nil)
    }

    private func add() {
        let binding: SharedValueBinding
        switch source {
        case .manual: binding = .manual
        case .computed: binding = .computed(expression: expression, payloadType: computedType)
        case .osc: binding = .osc(address: oscAddress, payloadType: oscType)
        case .shure: binding = .shure(deviceID: deviceID!, channel: channel, field: field)
        case .sennheiser: binding = .sennheiser(deviceID: deviceID!, channel: channel, field: field)
        }
        Task {
            guard let value = try? await store.create(name: name, binding: binding) else { return }
            if source == .manual {
                let payload: SharedValuePayload = switch manualType {
                case .text: .text(manualText)
                case .number: .number(manualNumber)
                case .boolean: .boolean(manualBoolean)
                case .payload: .payload(manualText)
                }
                _ = await store.setManualValue(id: value.id, payload: payload)
            }
            if source == .computed { await store.recomputeComputedValues() }
            dismiss()
        }
    }

    private func validJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }
}

private struct ManualSharedValueEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let value: SharedValue
    let store: SharedValueStore
    @State private var type: SharedValueType
    @State private var textValue: String
    @State private var numberValue: Double
    @State private var booleanValue: Bool

    init(value: SharedValue, store: SharedValueStore) {
        self.value = value
        self.store = store
        _type = State(initialValue: value.payload?.valueType ?? .text)
        _textValue = State(initialValue: value.payload?.displayValue ?? "")
        if case let .number(number) = value.payload {
            _numberValue = State(initialValue: number)
        } else {
            _numberValue = State(initialValue: 0)
        }
        if case let .boolean(boolean) = value.payload {
            _booleanValue = State(initialValue: boolean)
        } else {
            _booleanValue = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(value.name).font(.headline)
                Picker("Value type", selection: $type) {
                    ForEach(SharedValueType.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                switch type {
                case .text: TextField("Value", text: $textValue)
                case .number: TextField("Value", value: $numberValue, format: .number)
                case .boolean: Toggle("Value", isOn: $booleanValue)
                case .payload: TextField("JSON payload", text: $textValue)
                }
            }
            .navigationTitle("Edit Variable")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let payload: SharedValuePayload = switch type {
                        case .text: .text(textValue)
                        case .number: .number(numberValue)
                        case .boolean: .boolean(booleanValue)
                        case .payload: .payload(textValue)
                        }
                        Task {
                            _ = await store.setManualValue(id: value.id, payload: payload)
                            dismiss()
                        }
                    }
                    .disabled(type == .payload && !validJSON(textValue))
                }
            }
        }
        .frame(minWidth: 320, minHeight: 220)
    }

    private func validJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }
}

private extension WirelessSharedValueField {
    var label: String {
        switch self {
        case .batteryPercent: "Battery %"
        case .rf: "RF"
        case .audio: "Audio"
        case .connected: "Connected"
        }
    }

}

private struct SharedValueRow: View {
    let value: SharedValue
    var displayName: String? = nil
    let sourceDescription: String
    let syncedTabName: String?
    let copy: (SharedValue) -> Void
    var edit: (() -> Void)? = nil
    var formatClock: (() -> Void)? = nil
    var delete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Button { copy(value) } label: {
                HStack(spacing: 12) {
                    Image(systemName: value.isSuggested ? "number.square" : "number.square.fill")
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(displayName ?? value.name).font(.headline).foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(value.displayValue.isEmpty ? "—" : value.displayValue)
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 160, alignment: .trailing)
                            Image(systemName: "plus").foregroundStyle(.secondary)
                        }
                        if displayName != nil {
                            Text("#{shared:\(value.name)}")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let syncedTabName {
                            Label("Synced tab • \(syncedTabName)", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption).foregroundStyle(Color.accentColor)
                        }
                        Text("\(value.isSuggested ? "Suggested" : "Custom") • \(sourceDescription) • \(statusDescription)")
                            .font(.caption).foregroundStyle(value.status == .live ? Color.secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Insert #{shared:\(value.name)}")
            if edit != nil || formatClock != nil || delete != nil {
                Menu {
                    if let edit { Button("Edit Value", action: edit) }
                    if let formatClock { Button("Format Date and Time", action: formatClock) }
                    if let delete { Button("Delete Variable", role: .destructive, action: delete) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 22, height: 24)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More options for \(value.name)")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .contextMenu {
            Button("Copy Token") { copy(value) }
            if let edit { Button("Edit Value") { edit() } }
            if let formatClock { Button("Format Date and Time") { formatClock() } }
            if let delete {
                Divider()
                Button("Delete Variable", role: .destructive) { delete() }
            }
        }
    }

    private var statusDescription: String {
        if case let .system(key) = value.binding, key.hasPrefix("clock:") {
            return value.status.rawValue.capitalized
        }
        guard let date = value.lastUpdatedAt else { return "Never received" }
        return "\(value.status.rawValue.capitalized) • Updated \(date.formatted(.relative(presentation: .named)))"
    }
}
