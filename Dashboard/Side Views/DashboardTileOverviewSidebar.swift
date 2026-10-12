import SwiftUI
#if os(macOS)
import AppKit
#endif

private struct SizeEditorTile: Identifiable, Equatable {
    let id: UUID
}

// MARK: - Shared helpers (used by multiple Dashboard views)

/// Returns true if running on iOS/macOS 26 or newer.
@inline(__always)
internal var isOS26OrNewer: Bool {
    if #available(iOS 26.0, macOS 26.0, *) { return true }
    return false
}

// MARK: - Sidebar Collapse Button Helper
@ViewBuilder
internal func sidebarCollapseButton(
    action: @escaping () -> Void,
    iconSize: CGFloat = 13,
    innerDiameter: CGFloat = 28,
    hitPadding: CGFloat = 8
) -> some View {
    Button(action: action) {
        Image(systemName: "chevron.left")
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: innerDiameter, height: innerDiameter)
            // Give the control a larger, more Apple-like tap target.
            .padding(hitPadding)
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .dashboardGlassCircleButton()
    .accessibilityLabel("Hide Sidebar")
}


struct DashboardTileOverviewSidebar: View {
    let tab: DashboardTab
    @Binding var selectedTileIDs: Set<UUID>
    let onSelectionChanged: (Set<UUID>) -> Void
    let onRenameTile: (UUID, String) -> Void
    let onUpdateTileSize: (UUID, CGSize) -> Void
    /// Toggle per-tile visibility on the dashboard.
    /// The second parameter is the new `isHidden` state for the tile.
    let onToggleTileVisibility: (UUID, Bool) -> Void
    /// Reorder tiles in the tab to change their z-space order.
    /// Matches SwiftUI's `.onMove` signature.
    let onReorderTiles: (IndexSet, Int) -> Void

    /// Edit an existing tile group.
    let onEditGroup: (DashboardTileGroup) -> Void
    /// Delete a tile group.
    let onDeleteGroup: (DashboardTileGroup) -> Void
    /// Highlight group selection on the canvas.
    let onGroupSelected: (DashboardTileGroup) -> Void

    /// Collapse / hide the overview sidebar (used by the OS 26 floating back button and pre-26 inline button).
    let onCollapseSidebar: () -> Void

    @State private var editingTileID: UUID?
    @State private var editingTitle: String = ""
    @FocusState private var focusedTileID: UUID?

    @State private var sizeEditorTile: SizeEditorTile?
    @State private var sizeEditorWidth: String = ""
    @State private var sizeEditorHeight: String = ""
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var lastClickedTileID: UUID? = nil

    var body: some View {
        List(selection: $selectedTileIDs) {
            // Sidebar header: expandable search + collapse
            Section {
                HStack(spacing: 10) {
                    Group {
                        if isSearchExpanded {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)

                                TextField("Search tiles", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .focused($isSearchFieldFocused)
                                    .onSubmit {
                                        // If they submit with an empty query, collapse.
                                        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            isSearchExpanded = false
                                        }
                                    }

                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Clear search")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .dashboardGlassControl(cornerRadius: 10)
                        } else {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    isSearchExpanded = true
                                }
                                // Focus next run loop so layout is updated.
                                DispatchQueue.main.async {
                                    isSearchFieldFocused = true
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                    Text("Search tiles")
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .dashboardGlassControl(cornerRadius: 10)
                            .accessibilityLabel("Search tiles")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    sidebarCollapseButton(
                        action: { onCollapseSidebar() },
                        iconSize: 12,
                        innerDiameter: 22,
                        hitPadding: 6
                    )
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            Section {
                ForEach(filteredTilesWithIndex, id: \.tile.id) { index, tile in
                    tileRow(index: index, tile: tile)
                }
                // Reordering is only enabled when not filtering; otherwise indices don't map cleanly.
                .onMove { indices, newOffset in
                    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onReorderTiles(indices, newOffset)
                }
            } header: {
                HStack {
                    Text("Tiles")
                    Spacer()
                    Text("\(tab.tiles.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            if !tab.tileGroups.isEmpty {
                Section {
                    ForEach(groupsSorted) { group in
                        groupRow(group)
                    }
                } header: {
                    HStack {
                        Text("Groups")
                        Spacer()
                        Text("\(tab.tileGroups.count)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
        }
        .sidebarListStyleForOS26()
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .dashboardGlassPanel(cornerRadius: 18, appliesScrollContentBackground: true)
        .contentShape(Rectangle())
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .zIndex(50_000)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTileIDs.removeAll()
                    onSelectionChanged(selectedTileIDs)
                }
        )
        .onChange(of: selectedTileIDs, initial: false) { _, newValue in
            onSelectionChanged(newValue)
        }
        .onChange(of: isSearchFieldFocused, initial: false) { _, focused in
            if !focused && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSearchExpanded = false
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 44)
        .sheet(item: $sizeEditorTile) { sizeEditorTile in
            let tileID = sizeEditorTile.id

            VStack(alignment: .leading, spacing: 12) {
                let affectedCount = selectedTileIDs.contains(tileID) ? selectedTileIDs.count : 1
                Text(affectedCount > 1 ? "Edit sizes" : "Edit size")
                    .font(.headline)

                HStack {
                    Text("Width")
                        .frame(width: 60, alignment: .leading)
                    TextField("Width", text: $sizeEditorWidth)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("px")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if selectedTileIDs.count > 1 {
                        let sizes = tab.tiles.filter { selectedTileIDs.contains($0.id) }.compactMap { $0.size }
                        let minW = Int(sizes.map { $0.width }.min() ?? 0)
                        let maxW = Int(sizes.map { $0.width }.max() ?? 0)
                        Text("(\(minW)–\(maxW) px)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Height")
                        .frame(width: 60, alignment: .leading)
                    TextField("Height", text: $sizeEditorHeight)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("px")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if selectedTileIDs.count > 1 {
                        let sizes = tab.tiles.filter { selectedTileIDs.contains($0.id) }.compactMap { $0.size }
                        let minH = Int(sizes.map { $0.height }.min() ?? 0)
                        let maxH = Int(sizes.map { $0.height }.max() ?? 0)
                        Text("(\(minH)–\(maxH) px)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        self.sizeEditorTile = nil
                    }
                    Button("Apply") {
                        let trimmedWidth = sizeEditorWidth.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedHeight = sizeEditorHeight.trimmingCharacters(in: .whitespacesAndNewlines)

                        let widthInput = trimmedWidth.isEmpty ? nil : Double(trimmedWidth)
                        let heightInput = trimmedHeight.isEmpty ? nil : Double(trimmedHeight)

                        // If nothing valid was entered, do nothing.
                        if widthInput == nil && heightInput == nil {
                            self.sizeEditorTile = nil
                            return
                        }

                        // Decide which tiles to affect:
                        // - If this tile is in a multi-selection, apply to all selected.
                        // - Otherwise, just this one tile.
                        let targetIDs: [UUID]
                        if selectedTileIDs.contains(tileID), selectedTileIDs.count > 1 {
                            targetIDs = Array(selectedTileIDs)
                        } else {
                            targetIDs = [tileID]
                        }

                        for id in targetIDs {
                            // Look up THIS tile’s current size so we can preserve its own dimension
                            // when that axis was left blank.
                            let currentSize = tab.tiles.first(where: { $0.id == id })?.size
                                ?? CGSize(width: 260, height: 200)

                            let rawWidth = widthInput ?? Double(currentSize.width)
                            let rawHeight = heightInput ?? Double(currentSize.height)

                            let clampedWidth = max(44, rawWidth)
                            let clampedHeight = max(44, rawHeight)

                            onUpdateTileSize(id, CGSize(width: clampedWidth, height: clampedHeight))
                        }

                        self.sizeEditorTile = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(minWidth: 260)
        }
    }

    private func displayTitle(for tile: DashboardTileModel) -> String {
        let trimmed = tile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty,
           let idx = tab.tiles.firstIndex(where: { $0.id == tile.id }) {
            return "Tile \(idx + 1)"
        } else if trimmed.isEmpty {
            return "Tile"
        } else {
            return trimmed
        }
    }

    private var filteredTilesWithIndex: [(index: Int, tile: DashboardTileModel)] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return Array(tab.tiles.enumerated()).map { ($0.offset, $0.element) }
        }

        return Array(tab.tiles.enumerated()).filter { _, tile in
            let title = displayTitle(for: tile).lowercased()
            let summary = tileSummaryStatic(for: tile, in: tab).lowercased()
            return title.contains(q) || summary.contains(q)
        }.map { ($0.offset, $0.element) }
    }

    private var groupsSorted: [DashboardTileGroup] {
        tab.tileGroups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func handleTileSelection(tileID: UUID) {
        var newSelection: Set<UUID> = []
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        let isCommand = flags.contains(.command)
        let isShift = flags.contains(.shift)
        let ids = filteredTilesWithIndex.map { $0.tile.id }
        newSelection = selectedTileIDs

        if isShift,
           let anchor = lastClickedTileID,
           let anchorIndex = ids.firstIndex(of: anchor),
           let tappedIndex = ids.firstIndex(of: tileID) {
            let lower = min(anchorIndex, tappedIndex)
            let upper = max(anchorIndex, tappedIndex)
            let rangeIDs = Set(ids[lower...upper])
            if isCommand {
                newSelection.formUnion(rangeIDs)
            } else {
                newSelection = rangeIDs
            }
        } else if isCommand {
            if newSelection.contains(tileID) {
                newSelection.remove(tileID)
            } else {
                newSelection.insert(tileID)
            }
        } else {
            newSelection = [tileID]
        }
        #else
        newSelection = [tileID]
        #endif

        selectedTileIDs = newSelection
        onSelectionChanged(newSelection)
        lastClickedTileID = tileID
    }

    private func toggleVisibilityFromOverviewControl(for tile: DashboardTileModel) {
        let targetIDs: [UUID]
        if selectedTileIDs.contains(tile.id), selectedTileIDs.count > 1 {
            targetIDs = tab.tiles.map(\.id).filter { selectedTileIDs.contains($0) }
        } else {
            targetIDs = [tile.id]
        }

        let newHiddenState = !tile.isHidden
        for id in targetIDs {
            onToggleTileVisibility(id, newHiddenState)
        }
    }

    private func groupTileIds(_ group: DashboardTileGroup) -> Set<UUID> {
        let existingIds = Set(tab.tiles.map { $0.id })
        return Set(group.tileIds).intersection(existingIds)
    }

    private func selectGroup(_ group: DashboardTileGroup, tileIds: Set<UUID>) {
        guard !tileIds.isEmpty else { return }
        selectedTileIDs = tileIds
        onSelectionChanged(selectedTileIDs)
        onGroupSelected(group)
        lastClickedTileID = tileIds.first
    }

    private func beginRenamingTile(_ tile: DashboardTileModel) {
        editingTileID = tile.id
        editingTitle = displayTitle(for: tile)
        focusedTileID = tile.id
    }

    private func beginEditingSize(for tile: DashboardTileModel) {
        let selectedIDs = selectedTileIDs.contains(tile.id) ? selectedTileIDs : [tile.id]
        let selectedSizes: [CGSize] = tab.tiles
            .filter { selectedIDs.contains($0.id) }
            .map { tile in
                DashboardTileSnappingHelper.effectiveSize(
                    for: tile,
                    defaultTileSize: CGSize(width: 260, height: 200)
                )
            }

        if selectedSizes.count > 1 {
            let widths = Set(selectedSizes.map { Int($0.width.rounded()) })
            let heights = Set(selectedSizes.map { Int($0.height.rounded()) })

            sizeEditorWidth = widths.count == 1 ? String(widths.first ?? 0) : ""
            sizeEditorHeight = heights.count == 1 ? String(heights.first ?? 0) : ""
        } else if let onlySize = selectedSizes.first {
            sizeEditorWidth = String(Int(onlySize.width.rounded()))
            sizeEditorHeight = String(Int(onlySize.height.rounded()))
        } else {
            sizeEditorWidth = ""
            sizeEditorHeight = ""
        }

        sizeEditorTile = SizeEditorTile(id: tile.id)
    }

    @ViewBuilder
    private func groupRow(_ group: DashboardTileGroup) -> some View {
        let tileIds = groupTileIds(group)
        let isSelected = !tileIds.isEmpty && tileIds.isSubset(of: selectedTileIDs)

        HStack(spacing: 10) {
            Circle()
                .fill(group.color.swiftUIColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(tileIds.count) tile\(tileIds.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear
        )
        .onTapGesture {
            selectGroup(group, tileIds: tileIds)
        }
        .onTapGesture(count: 2) {
            onEditGroup(group)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(group.name))
        .accessibilityValue(Text("\(tileIds.count) tile\(tileIds.count == 1 ? "" : "s")\(isSelected ? ", selected" : "")"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text("Select Group")) {
            selectGroup(group, tileIds: tileIds)
        }
        .accessibilityAction(named: Text("Edit Group")) {
            onEditGroup(group)
        }
        .accessibilityAction(named: Text("Delete Group")) {
            onDeleteGroup(group)
        }
        .contextMenu {
            Button("Edit Group") {
                onEditGroup(group)
            }

            Divider()

            Button("Delete Group") {
                onDeleteGroup(group)
            }
        }
    }

    @ViewBuilder
    private func tileRow(index: Int, tile: DashboardTileModel) -> some View {
        let isSelected = selectedTileIDs.contains(tile.id)

        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(sidebarAccentColor(for: tile))
                .frame(width: 3)
                .opacity(tile.isHidden ? 0.30 : 0.95)

            VStack(alignment: .leading, spacing: 2) {
                if editingTileID == tile.id {
                    TextField("Tile name", text: $editingTitle, onCommit: {
                        let newName = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newName.isEmpty {
                            onRenameTile(tile.id, newName)
                        }
                        editingTileID = nil
                        focusedTileID = nil
                    })
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .focused($focusedTileID, equals: tile.id)
                } else {
                    Text(displayTitle(for: tile))
                        .font(.subheadline)
                        .foregroundStyle(tile.isHidden ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(2)
                }

                Text(tileSummaryStatic(for: tile, in: tab))
                    .font(.caption2)
                    .foregroundStyle(tile.isHidden ? .tertiary : .secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }

            Spacer(minLength: 0)

            Button(
                tile.isHidden ? "Show Tile" : "Hide Tile",
                systemImage: tile.isHidden ? "eye.slash" : "eye"
            ) {
                toggleVisibilityFromOverviewControl(for: tile)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(tile.isHidden ? .secondary : .tertiary)
            .frame(minWidth: DashboardTileMetrics.minWidth, minHeight: DashboardTileMetrics.minHeight)
            .contentShape(Rectangle())
            .help(tile.isHidden ? "Show tile on dashboard" : "Hide tile from dashboard")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear
        )
        .opacity(tile.isHidden ? 0.80 : 1.0)
#if os(iOS)
        .onTapGesture {
            handleTileSelection(tileID: tile.id)
        }
#else
        .onTapGesture {
            handleTileSelection(tileID: tile.id)
        }
        .tag(tile.id)
#endif
        .onTapGesture(count: 2) {
            beginRenamingTile(tile)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(displayTitle(for: tile)))
        .accessibilityValue(Text("\(tileSummaryStatic(for: tile, in: tab))\(tile.isHidden ? ", hidden" : "")\(isSelected ? ", selected" : "")"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text("Select Tile")) {
            handleTileSelection(tileID: tile.id)
        }
        .accessibilityAction(named: Text("Rename Tile")) {
            beginRenamingTile(tile)
        }
        .accessibilityAction(named: Text("Edit Size")) {
            beginEditingSize(for: tile)
        }
        .accessibilityAction(named: Text(tile.isHidden ? "Show Tile" : "Hide Tile")) {
            toggleVisibilityFromOverviewControl(for: tile)
        }
        .accessibilityAction(named: Text("Move Up")) {
            guard index > 0 else { return }
            onReorderTiles(IndexSet(integer: index), index - 1)
        }
        .accessibilityAction(named: Text("Move Down")) {
            guard index < tab.tiles.count - 1 else { return }
            onReorderTiles(IndexSet(integer: index), index + 2)
        }
        .contextMenu {
            Button("Rename Tile") {
                beginRenamingTile(tile)
            }

            Divider()

            Button(
                selectedTileIDs.contains(tile.id) && selectedTileIDs.count > 1
                    ? "Edit Sizes…"
                    : "Edit Size…"
            ) {
                beginEditingSize(for: tile)
            }

            Divider()

            Button {
                toggleVisibilityFromOverviewControl(for: tile)
            } label: {
                Label(tile.isHidden ? "Show Tile" : "Hide Tile", systemImage: tile.isHidden ? "eye" : "eye.slash")
            }

            Divider()

            Button {
                guard index > 0 else { return }
                onReorderTiles(IndexSet(integer: index), index - 1)
            } label: {
                Label("Move Up", systemImage: "chevron.up")
            }
            .disabled(index == 0)

            Button {
                guard index < tab.tiles.count - 1 else { return }
                onReorderTiles(IndexSet(integer: index), index + 2)
            } label: {
                Label("Move Down", systemImage: "chevron.down")
            }
            .disabled(index == tab.tiles.count - 1)
        }
    }
}

func tileSummaryStatic(for tile: DashboardTileModel, in tab: DashboardTab) -> String {
    // If the tile has modules, summarize based on the first few modules.
    if let modules = tile.modules, !modules.isEmpty {
        let sorted = modules.sorted { $0.order < $1.order }

        let parts: [String] = sorted.prefix(3).map { module in
            switch module.kind {
            case .person(let model):
                let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? "Person" : "Person: \(name)"
            case .pcoRundown:
                return "PCO Rundown"
            case .pcoTeamAssignments:
                return "PCO Team Assignments"
            case .rosterTeamAssignments:
                return "Roster Team Assignments"
            case .shureWireless:
                return "Shure Wireless"
            case .shureOverview:
                return "Shure Overview"
            case .sennheiserWireless:
                return "Sennheiser Wireless"
            case .youtubeStreamMonitor:
                return "YouTube Stream Monitor"
            case .webpage:
                return "Webpage"
            case .time:
                return "Time"
            case .timecode:
                return "Timecode"
            case .dawTransport:
                return "DAW Transport"
            case .rosterPicker:
                return "Picker"
            case .text:
                return "Text"
            case .image:
                return "Image"
            case .document:
                return "Document"
            case .ndi:
                return "NDI Feed"
            case .separator:
                return "Separator"
            case .proPresenter:
                return "ProPresenter"
            case .resolume:
                return "Resolume"
            case .dbReader:
                return "SPL Meter"
            case .liveTranscription:
                return "Live Transcription"
            case .button:
                return "Button"
            case .rta:
                return "RTA"
            case .spectrograph:
                return "Spectrograph"
            }

        }

        let summary = parts.joined(separator: ", ")
        return summary + tileSizeSummarySuffix(for: tile)
    }

    // Fallback summary based on the tile's primary kind when there are no modules.
    var summary: String
    switch tile.kind {
    case .empty:
        summary = "Empty Tile"
    case .person(let model):
        let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        summary = name.isEmpty ? "Person Tile" : "Person: \(name)"
    case .pcoPlaceholder:
        summary = "PCO Placeholder"
    case .time:
        summary = "Time Tile"
    }
    
    return summary + tileSizeSummarySuffix(for: tile)
}

private func tileSizeSummarySuffix(for tile: DashboardTileModel) -> String {
    // If the tile has no explicit size, omit the size suffix.
    guard let size = tile.size else { return "" }
    
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    return " · \(width)×\(height) px"
}

private func sidebarAccentColor(for tile: DashboardTileModel) -> Color {
    // Prefer a custom background color when present; otherwise use the style color.
    let baseColor: Color
    if let custom = tile.backgroundCustomColor {
        baseColor = custom.swiftUIColor
    } else {
        baseColor = tile.backgroundStyle.color
    }

    // Match the tile’s background opacity so it feels connected but not too loud.
    return baseColor.opacity(tile.backgroundOpacity)
}

// MARK: - Liquid Glass helpers

private extension View {
    @ViewBuilder
    func sidebarListStyleForOS26() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // Avoid the system sidebar background slab behind our custom glass container.
            self.listStyle(.plain)
        } else {
            self.listStyle(.sidebar)
        }
    }

}
