import Foundation
import SwiftUI
//
//  DashboardModuleCatalog.swift
//  Relay
//
//  Created by David Bullard on 12/31/25.
//

enum DashboardModuleCategory: String, CaseIterable, Identifiable, Hashable {
    case peoplePlanning = "People & Planning"
    case wireless = "Wireless"
    case audio = "Audio"
    case videoPlayback = "Video & Playback"
    case utility = "Utility"
    case systems = "Systems"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .peoplePlanning: return 0
        case .wireless: return 1
        case .audio: return 2
        case .videoPlayback: return 3
        case .utility: return 4
        case .systems: return 5
        }
    }

    var systemImage: String {
        switch self {
        case .peoplePlanning: return "person.2"
        case .wireless: return "dot.radiowaves.left.and.right"
        case .audio: return "waveform"
        case .videoPlayback: return "play.rectangle"
        case .utility: return "wrench.and.screwdriver"
        case .systems: return "slider.horizontal.3"
        }
    }
}
struct DashboardModuleCatalogItem: Identifiable {
    let id: String                 // stable identifier ("shure", "pco", etc.)
    let title: String
    let subtitle: String
    let systemImage: String
    let category: DashboardModuleCategory
    let kind: DashboardModuleKind
    let isBeta: Bool
    var capacityMessage: String?   // non-nil → item is at capacity

    var isAtCapacity: Bool { capacityMessage != nil }

        init(
            id: String,
            title: String,
            subtitle: String,
            systemImage: String,
            category: DashboardModuleCategory,
            kind: DashboardModuleKind,
            isBeta: Bool = false
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.systemImage = systemImage
            self.category = category
            self.kind = kind
            self.isBeta = isBeta
            self.capacityMessage = nil
        }
}
enum DashboardModuleCatalog {
    enum PresentationStyle {
        case sheet
        case floating
    }

    static func all(
        initialPerson: PersonTileModel?,
        tileID: UUID,
        ndiModuleCount: Int = 0
    ) -> [DashboardModuleCatalogItem] {
        let basePerson = initialPerson ?? PersonTileModel(name: "Person", role: "Role", initials: "P")

        var defaultText = AttributedString("New text module")
        defaultText.foregroundColor = .white
        defaultText.font = .system(size: 16)

        var items: [DashboardModuleCatalogItem] = [
            .init(id: "pcoRundown", title: "PCO Rundown", subtitle: "Service rundown, summary, and Live view", systemImage: "list.bullet.rectangle.portrait", category: .peoplePlanning, kind: .pcoRundown, isBeta: false),
            .init(id: "pcoTeamAssignments", title: "PCO Team Assignments", subtitle: "Assigned positions with avatars and wireless picks", systemImage: "person.2.crop.square.stack", category: .peoplePlanning, kind: .pcoTeamAssignments, isBeta: false),
            .init(id: "rosterTeamAssignments", title: "Roster Team Assignments", subtitle: "People-roster positions with avatars and equipment picks", systemImage: "person.2.crop.square.stack.fill", category: .peoplePlanning, kind: .rosterTeamAssignments, isBeta: false),
            .init(id: "person", title: "Person", subtitle: "Team member tile with role and badge", systemImage: "person.crop.square", category: .peoplePlanning, kind: .person(basePerson), isBeta: false),

            .init(id: "shure", title: "Shure", subtitle: "Wireless mics + IEMs", systemImage: "dot.radiowaves.left.and.right", category: .wireless, kind: .shureWireless, isBeta: false),
            .init(id: "sennheiser", title: "Sennheiser", subtitle: "Wireless mics + IEMs", systemImage: "dot.radiowaves.left.and.right", category: .wireless, kind: .sennheiserWireless, isBeta: true),

            .init(id: "propresenter", title: "ProPresenter", subtitle: "Current slide + presentation status", systemImage: "play.rectangle.on.rectangle", category: .videoPlayback, kind: .proPresenter, isBeta: false),

            .init(id: "text", title: "Text", subtitle: "Custom note or label", systemImage: "text.alignleft", category: .utility, kind: .text(TextModuleModel(header: nil, content: defaultText)), isBeta: false),
            .init(id: "image", title: "Image", subtitle: "Custom logo or image, imported and downsized", systemImage: "photo", category: .utility, kind: .image(ImageModuleModel()), isBeta: false),
            .init(id: "rosterPicker", title: "Picker", subtitle: "Choose a value based on Roster list, setup in tab settings.", systemImage: "list.bullet.below.rectangle", category: .utility, kind: .rosterPicker(RosterPickerModuleModel()), isBeta: false),
            .init(id: "document", title: "Document", subtitle: "PDF or Word document", systemImage: "doc.richtext", category: .utility, kind: .document(DocumentModuleModel()), isBeta: false),
            .init(id: "webpage", title: "Webpage", subtitle: "Single webpage view with optional auto-refresh", systemImage: "globe", category: .utility, kind: .webpage(WebpageModuleModel()), isBeta: false),
            .init(id: "time", title: "Time", subtitle: "Clock/date, timers", systemImage: "clock", category: .utility, kind: .time, isBeta: false),
            .init(id: "separator", title: "Separator", subtitle: "Visual divider between modules", systemImage: "line.horizontal.3", category: .utility, kind: .separator(SeparatorModuleModel()), isBeta: false),
            .init(id: "button", title: "Button", subtitle: "Trigger OSC, MIDI, or internal commands", systemImage: "button.programmable", category: .utility, kind: .button(ButtonModuleModel()), isBeta: false),
            .init(id: "dbReader", title: "SPL Meter", subtitle: "SPL-style meter with A/C/Z weighting", systemImage: "speaker.wave.2.fill", category: .audio, kind: .dbReader(DbReaderModuleModel()), isBeta: false),
            .init(id: "rta", title: "RTA", subtitle: "Real-time octave-band frequency analyzer (1-oct to 1/48-oct)", systemImage: "waveform.badge.magnifyingglass", category: .audio, kind: .rta(RTAModuleModel()), isBeta: false),
            .init(id: "spectrograph", title: "Spectrograph", subtitle: "Scrolling waterfall frequency display", systemImage: "waveform", category: .audio, kind: .spectrograph(SpectrogramModuleModel()), isBeta: false),
            .init(id: "dawTransport", title: "DAW Transport", subtitle: "Pro Tools HUI and generic HUI transport control", systemImage: "playpause", category: .audio, kind: .dawTransport, isBeta: false),
            .init(id: "timecode", title: "Timecode", subtitle: "MIDI timecode display", systemImage: "timer", category: .utility, kind: .timecode, isBeta: false),
            .init(id: "transcription", title: "Live Transcription", subtitle: "Single-input speech-to-text with triggers", systemImage: "text.bubble.fill", category: .audio, kind: .liveTranscription(LiveTranscriptionModuleModel()), isBeta: false)

        ]
#if DEBUG || BETA
        items.append(
            .init(id: "shureOverview", title: "Shure Overview", subtitle: "Multi-device wireless status overview for mics and IEMs", systemImage: "list.bullet.rectangle", category: .wireless, kind: .shureOverview, isBeta: true)
        )
#endif
        if LiveStreamFeatureFlags.isEnabled {
            items.append(
                .init(
                    id: "youtubeStreamMonitor",
                    title: "YouTube Stream Monitor",
                    subtitle: "Live status, viewers, and stream health",
                    systemImage: "play.rectangle.fill",
                    category: .videoPlayback,
                    kind: .youtubeStreamMonitor(YouTubeStreamMonitorModuleModel()),
                    isBeta: true
                )
            )
        }
        var ndiItem = DashboardModuleCatalogItem(
            id: "ndi",
            title: "NDI® Feed",
            subtitle: ndiModuleCount >= 2
                ? "Limit reached — 2 NDI modules per tab"
                : "Network video feed with NIC-aware routing",
            systemImage: "play.tv",
            category: .videoPlayback,
            kind: .ndi(NDIModuleModel()),
            isBeta: true
        )
        if ndiModuleCount >= 2 {
            ndiItem.capacityMessage = "Add more NDI modules on a different tab, or remove an existing one."
        }
        items.insert(ndiItem, at: 3)
        return items
    }

    static func groupedAlphabetical(_ items: [DashboardModuleCatalogItem]) -> [(DashboardModuleCategory, [DashboardModuleCatalogItem])] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return DashboardModuleCategory.allCases
            .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
            .compactMap { cat in
                guard let arr = grouped[cat] else { return nil }
                return (cat, arr.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
            }
    }

    @ViewBuilder
    static func modalView(
        title: String = "Add Module",
        initialPerson: PersonTileModel?,
        tileID: UUID,
        style: PresentationStyle = .sheet,
        transcriptionAlreadyPresent: Bool = false,
        ndiModuleCount: Int = 0,
        onSelect: @escaping (DashboardModuleCatalogItem) -> Void
    ) -> some View {
        let items = DashboardModuleCatalog.all(
            initialPerson: initialPerson,
            tileID: tileID,
            ndiModuleCount: ndiModuleCount
        )
        #if os(macOS)
        switch style {
        case .sheet:
            DashboardModuleCatalogModalView(title: title, items: items, style: style, transcriptionAlreadyPresent: transcriptionAlreadyPresent, onSelect: onSelect)
                .frame(minWidth: 720, idealWidth: 860, maxWidth: .infinity,
                       minHeight: 520, idealHeight: 600, maxHeight: .infinity)
        case .floating:
            DashboardModuleCatalogModalView(title: title, items: items, style: style, transcriptionAlreadyPresent: transcriptionAlreadyPresent, onSelect: onSelect)
                .frame(minWidth: 520, idealWidth: 600, maxWidth: 720,
                       minHeight: 420, idealHeight: 520, maxHeight: 640)
        }
        #else
        DashboardModuleCatalogModalView(title: title, items: items, style: .sheet, transcriptionAlreadyPresent: transcriptionAlreadyPresent, onSelect: onSelect)
        #endif
    }
}

// MARK: - Reusable Modal (Storefront) UI

struct DashboardModuleCatalogModalView: View {
    let title: String
    let items: [DashboardModuleCatalogItem]
    let style: DashboardModuleCatalog.PresentationStyle
    let transcriptionAlreadyPresent: Bool
    let onSelect: (DashboardModuleCatalogItem) -> Void

    @Environment(\.dismiss) private var dismiss

    #if os(macOS)
    @State private var selectedCategory: DashboardModuleCategory? = nil
    @State private var searchText: String = ""
    @State private var hasSelectedAnyModule: Bool = false
    @State private var showsCategorySidebar: Bool = true
    @FocusState private var isSearchFocused: Bool
#else
    @State private var selectedCategory: DashboardModuleCategory? = nil
    @State private var searchText: String = ""
    @State private var hasSelectedAnyModule: Bool = false
#endif

#if os(macOS)
    private var panelFrame: (minW: CGFloat, idealW: CGFloat, maxW: CGFloat?, minH: CGFloat, idealH: CGFloat, maxH: CGFloat?) {
        switch style {
        case .sheet:
            return (minW: 720, idealW: 860, maxW: nil, minH: 520, idealH: 600, maxH: nil)
        case .floating:
            return (minW: 560, idealW: 720, maxW: 860, minH: 460, idealH: 560, maxH: 680)
        }
    }
#endif

    private var filteredItems: [DashboardModuleCatalogItem] {
        let base: [DashboardModuleCatalogItem]
        if let selectedCategory {
            base = items.filter { $0.category == selectedCategory }
        } else {
            base = items
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var groupedFiltered: [(DashboardModuleCategory, [DashboardModuleCatalogItem])] {
        DashboardModuleCatalog.groupedAlphabetical(filteredItems)
    }

    private var sortedFilteredItems: [DashboardModuleCatalogItem] {
        filteredItems.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var nonEmptyCategories: [DashboardModuleCategory] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return DashboardModuleCategory.allCases
            .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
            .filter { (grouped[$0]?.isEmpty == false) }
    }

    private var showsSectionHeadersInDetail: Bool {
        // If a category is explicitly selected, headers are redundant.
        selectedCategory == nil
    }

    private func isTranscriptionDisabled(_ entry: DashboardModuleCatalogItem) -> Bool {
        transcriptionAlreadyPresent && entry.id == "transcription"
    }

    private func catalogRow(_ entry: DashboardModuleCatalogItem) -> some View {
        let isAtCapacity = entry.isAtCapacity
        let isDisabledByTranscription = isTranscriptionDisabled(entry)
        let isDisabled = isAtCapacity || isDisabledByTranscription
        let subtitle: String = {
            if isAtCapacity { return entry.subtitle }
            if isDisabledByTranscription { return "Tile already contains Live Transcription." }
            return entry.subtitle
        }()

        return CatalogPillRow(
            title: entry.title,
            subtitle: subtitle,
            systemImage: entry.systemImage,
            isBeta: entry.isBeta,
            isDisabled: isDisabled
        ) {
            if isDisabled { return }
            hasSelectedAnyModule = true
            onSelect(entry)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .listRowBackground(Color.clear)
    }

#if os(macOS)
    private var categorySidebarList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // All
                Button {
                    selectedCategory = nil
                } label: {
                    HStack {
                        Text("All")
                        Spacer(minLength: 0)
                        if selectedCategory == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedCategory == nil ? Color.primary.opacity(0.10) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Categories header
                Text("Categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // Categories
                ForEach(nonEmptyCategories) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        HStack(spacing: 10) {
                            DashboardSymbolImage(cat.systemImage)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            Text(cat.rawValue)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            if selectedCategory == cat {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedCategory == cat ? Color.primary.opacity(0.10) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
    }

    private var moduleDetailList: some View {
        List {
            if showsSectionHeadersInDetail {
                ForEach(groupedFiltered, id: \.0.id) { category, entries in
                    Section {
                        ForEach(entries, id: \.id) { entry in
                            catalogRow(entry)
                        }
                    } header: {
                        DashboardSymbolLabel(category.rawValue, preferred: category.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(filteredItems.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }, id: \.id) { entry in
                    catalogRow(entry)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
#endif
    private struct CatalogPillRow: View {
        let title: String
        let subtitle: String
        let systemImage: String
        let isBeta: Bool
        let isDisabled: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    DashboardSymbolImage(systemImage)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if isBeta {
                        BetaBadgeView()
                    }
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
    }

    var body: some View {
        #if os(macOS)
        let frame = panelFrame

        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Header (drag handle for floating)
                HStack(spacing: 12) {
                    // Fixed-position sidebar toggle (stays put during sidebar animations)
                    SidebarToggleButton {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsCategorySidebar.toggle()
                        }
                    }

                    // Inline search field so the toolbar doesn't reflow when the sidebar is toggled
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search modules", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onTapGesture { isSearchFocused = true }
                    .dashboardGlassControl(cornerRadius: 10)
                    .frame(maxWidth: 520)

                    Spacer(minLength: 0)

                    if hasSelectedAnyModule {
                        Button("Done") { dismiss() }
                            .keyboardShortcut(.defaultAction)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, style == .floating ? 10 : 12)
                .contentShape(Rectangle())

                Divider()

                // Stable animated sidebar collapse (avoids HSplitView divider jitter)
                let sidebarWidth: CGFloat = showsCategorySidebar ? 260 : 0

                HStack(spacing: 0) {
                    // Sidebar column: animate width only (no opacity fade), hard mask to prevent List painting over detail.
                    categorySidebarList
                        .transaction { txn in
                            txn.animation = nil
                        }
                        .frame(width: sidebarWidth)
                        .clipped()
                        .allowsHitTesting(showsCategorySidebar)

                    // Divider between columns: animate width to 0 instead of fading.
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: showsCategorySidebar ? 1 : 0)

                    // Detail column
                    moduleDetailList
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Prevent List from trying to animate row/layout during sidebar changes.
                        .transaction { txn in
                            txn.animation = nil
                        }
                }
                // Animate only the sidebar width and divider width.
                .animation(.easeInOut(duration: 0.20), value: sidebarWidth)
            }
            .frame(minWidth: frame.minW, idealWidth: frame.idealW, maxWidth: frame.maxW,
                minHeight: frame.minH, idealHeight: frame.idealH, maxHeight: frame.maxH)
            .dashboardGlassPanel(cornerRadius: 16)
            .onAppear {
                if style == .floating {
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                }
            }
        }

        #else

        NavigationStack {
            List {
                if showsSectionHeadersInDetail {
                    ForEach(groupedFiltered, id: \.0.id) { category, entries in
                        Section {
                            ForEach(entries, id: \.id) { entry in
                                catalogRow(entry)
                            }
                        } header: {
                            DashboardSymbolLabel(category.rawValue, preferred: category.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(sortedFilteredItems, id: \.id) { entry in
                        catalogRow(entry)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: "Search modules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if hasSelectedAnyModule {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }

        #endif
    }
}


#if os(macOS)

/// A stable sidebar toggle button that doesn't shift with layout changes.
/// Uses SwiftUI state to toggle the NavigationSplitView sidebar.
private struct SidebarToggleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DashboardSymbolImage("sidebar.leading")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle Sidebar")
    }
}

#endif
