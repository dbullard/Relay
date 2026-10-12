//
//  PCOTilePlaceholderView.swift
//  Relay
//
//  Created by David Bullard on 11/16/25.
//


import SwiftUI
import OSLog
import UniformTypeIdentifiers

enum PCOSummaryField: String, CaseIterable, Codable, Identifiable {
    case serviceType
    case planTitle
    case planDate
    case serviceTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .serviceType:
            return "Service"
        case .planTitle:
            return "Plan"
        case .planDate:
            return "Date"
        case .serviceTime:
            return "Time"
        }
    }

    static var defaultOrder: [PCOSummaryField] {
        [.serviceType, .planTitle, .planDate, .serviceTime]
    }
}

enum PCOTeamAssignmentSortMode: String, CaseIterable, Codable, Identifiable {
    case positionName
    case personName
    case scheduleTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .positionName:
            return "Position"
        case .personName:
            return "Person"
        case .scheduleTime:
            return "Schedule Time"
        }
    }
}

private enum PCORundownColumnWidthKey: String, CaseIterable, Hashable {
    case time
    case item
    case key
    case type
    case length
    case arrangement
    case bpm
    case ccli
    case sequence
    case notes

    var defaultWidth: Double {
        switch self {
        case .time: return 80
        case .item: return 320
        case .key: return 50
        case .type: return 70
        case .length: return 60
        case .arrangement: return 110
        case .bpm: return 56
        case .ccli: return 72
        case .sequence: return 120
        case .notes: return 180
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .time: return 56
        case .item: return 160
        case .key: return 40
        case .type: return 54
        case .length: return 50
        case .arrangement: return 80
        case .bpm: return 44
        case .ccli: return 56
        case .sequence: return 80
        case .notes: return 100
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .time: return 180
        case .item: return 700
        case .key: return 120
        case .type: return 160
        case .length: return 120
        case .arrangement: return 260
        case .bpm: return 120
        case .ccli: return 160
        case .sequence: return 280
        case .notes: return 420
        }
    }

    var hardMinWidth: CGFloat {
        switch self {
        case .time: return 40
        case .item: return 120
        case .key: return 28
        case .type: return 40
        case .length: return 36
        case .arrangement: return 56
        case .bpm: return 32
        case .ccli: return 42
        case .sequence: return 56
        case .notes: return 84
        }
    }
}

#if os(macOS)
private struct PCORundownResizeHandle: NSViewRepresentable {
    let onDragBegan: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ResizeHandleNSView()
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ResizeHandleNSView else { return }
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }

    private final class ResizeHandleNSView: NSView {
        var onDragBegan: (() -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: (() -> Void)?

        private var startLocationInWindow: NSPoint?
        private var isDraggingHandle = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseDown(with event: NSEvent) {
            startLocationInWindow = event.locationInWindow
            isDraggingHandle = true
            onDragBegan?()
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDraggingHandle, let startLocationInWindow else { return }
            let deltaX = event.locationInWindow.x - startLocationInWindow.x
            onDragChanged?(deltaX)
        }

        override func mouseUp(with event: NSEvent) {
            guard isDraggingHandle else { return }
            isDraggingHandle = false
            startLocationInWindow = nil
            onDragEnded?()
        }
    }
}
#endif

/// Per-module configuration for a PCO rundown module. This allows multiple
/// PCO modules on the same dashboard tab to present the same plan/service
/// in different ways (e.g., different teams, rundown vs team-only, etc.).
/// Per-module configuration for a PCO rundown module. This allows multiple
/// PCO modules on the same dashboard tab to present the same plan/service
/// in different ways (e.g., different teams, rundown vs team-only, etc.).
struct PCOModuleConfig: Codable, Equatable {
    /// Whether this module shows its header/title.
    var showHeader: Bool = true
    /// Whether this module shows the order-of-service rundown.
    var showServiceRundown: Bool
    /// Whether this module shows team assignments.
    var showTeamAssignments: Bool
    /// Optional team name(s) for the assignments list (e.g. "Media", "Worship Band"),
    /// stored as a "name1||name2" string when multiple are selected.
    var teamName: String?

    /// Optional override for which service time labels this module should include
    /// when building the rundown, stored as "label1||label2".
    /// When nil or empty, the module inherits all service times configured for the tab.
    var serviceTimeNames: String?

    /// Column visibility options for the rundown view.
    /// When `showServiceRundown` is false, these flags are ignored.
    var showRundownServiceTimeColumn: Bool
    var showRundownKeyColumn: Bool
    var showRundownTypeColumn: Bool
    var showRundownLengthColumn: Bool
    var showRundownArrangementColumn: Bool
    var showRundownBPMColumn: Bool
    var showRundownCCLIColumn: Bool
    var showRundownSequenceColumn: Bool
    var showRundownNotesColumn: Bool
    var rundownVisibleNoteCategories: String?
    var rundownTimeColumnWidth: Double
    var rundownItemColumnWidth: Double
    var rundownKeyColumnWidth: Double
    var rundownTypeColumnWidth: Double
    var rundownLengthColumnWidth: Double
    var rundownArrangementColumnWidth: Double
    var rundownBPMColumnWidth: Double
    var rundownCCLIColumnWidth: Double
    var rundownSequenceColumnWidth: Double
    var rundownNotesColumnWidth: Double
    var showSummaryLine: Bool
    var summaryLineOrder: [PCOSummaryField]
    var summaryLineHidden: [PCOSummaryField]
    var showTeamMemberStatus: Bool
    var useStatusStyledAssignmentCards: Bool
    var teamAssignmentSortMode: PCOTeamAssignmentSortMode
    var hideDeclinedAssignments: Bool
    var assignmentTwoColumnThreshold: Int
    /// Whether this module should show the Planning Center Services Live web view.
    var showLiveView: Bool
    /// Optional URL override for the Services Live page to display.
    var liveURLOverride: String?
    /// When enabled, use the custom Live URL override.
    var liveUseCustomURL: Bool

    /// Per-assignment metadata used by the dedicated PCO Team Assignments
    /// module (avatars, mic/IEM picks, image placement). Nil for legacy
    /// rundown modules that only render team assignments inline.
    var teamExtras: PCOTeamAssignmentsExtras?

    static func `default`() -> PCOModuleConfig {
        PCOModuleConfig(
            showHeader: true,
            showServiceRundown: false,
            showTeamAssignments: false,
            teamName: nil,
            serviceTimeNames: nil,
            showRundownServiceTimeColumn: true,
            showRundownKeyColumn: true,
            showRundownTypeColumn: true,
            showRundownLengthColumn: true,
            showRundownArrangementColumn: false,
            showRundownBPMColumn: false,
            showRundownCCLIColumn: false,
            showRundownSequenceColumn: false,
            showRundownNotesColumn: false,
            rundownVisibleNoteCategories: nil,
            rundownTimeColumnWidth: PCORundownColumnWidthKey.time.defaultWidth,
            rundownItemColumnWidth: PCORundownColumnWidthKey.item.defaultWidth,
            rundownKeyColumnWidth: PCORundownColumnWidthKey.key.defaultWidth,
            rundownTypeColumnWidth: PCORundownColumnWidthKey.type.defaultWidth,
            rundownLengthColumnWidth: PCORundownColumnWidthKey.length.defaultWidth,
            rundownArrangementColumnWidth: PCORundownColumnWidthKey.arrangement.defaultWidth,
            rundownBPMColumnWidth: PCORundownColumnWidthKey.bpm.defaultWidth,
            rundownCCLIColumnWidth: PCORundownColumnWidthKey.ccli.defaultWidth,
            rundownSequenceColumnWidth: PCORundownColumnWidthKey.sequence.defaultWidth,
            rundownNotesColumnWidth: PCORundownColumnWidthKey.notes.defaultWidth,
            showSummaryLine: true,
            summaryLineOrder: PCOSummaryField.defaultOrder,
            summaryLineHidden: [],
            showTeamMemberStatus: true,
            useStatusStyledAssignmentCards: false,
            teamAssignmentSortMode: .positionName,
            hideDeclinedAssignments: false,
            assignmentTwoColumnThreshold: 15,
            showLiveView: false,
            liveURLOverride: nil,
            liveUseCustomURL: false,
            teamExtras: nil
        )
    }

    /// Default configuration for the dedicated PCO Team Assignments module:
    /// team assignments enabled, rundown/Live disabled, header off (the tile
    /// already provides its own labelling), and `teamExtras` initialized so
    /// the row renderer knows to use the avatar/mic/IEM treatment.
    static func teamAssignmentsDefault() -> PCOModuleConfig {
        var config = PCOModuleConfig.default()
        config.showHeader = false
        config.showServiceRundown = false
        config.showTeamAssignments = true
        config.showLiveView = false
        config.showSummaryLine = false
        config.teamExtras = PCOTeamAssignmentsExtras()
        return config
    }

    /// Default configuration for the dedicated PCO Rundown module:
    /// the rundown is always enabled, the legacy team-assignment surface is
    /// off, and summary/header controls stay available.
    static func rundownDefault() -> PCOModuleConfig {
        var config = PCOModuleConfig.default()
        config.showServiceRundown = true
        config.showTeamAssignments = false
        return config
    }

    private enum CodingKeys: String, CodingKey {
        case showHeader
        case showServiceRundown
        case showTeamAssignments
        case teamName
        case serviceTimeNames
        case showRundownServiceTimeColumn
        case showRundownKeyColumn
        case showRundownTypeColumn
        case showRundownLengthColumn
        case showRundownArrangementColumn
        case showRundownBPMColumn
        case showRundownCCLIColumn
        case showRundownSequenceColumn
        case showRundownNotesColumn
        case rundownVisibleNoteCategories
        case rundownTimeColumnWidth
        case rundownItemColumnWidth
        case rundownKeyColumnWidth
        case rundownTypeColumnWidth
        case rundownLengthColumnWidth
        case rundownArrangementColumnWidth
        case rundownBPMColumnWidth
        case rundownCCLIColumnWidth
        case rundownSequenceColumnWidth
        case rundownNotesColumnWidth
        case showSummaryLine
        case summaryLineOrder
        case summaryLineHidden
        case showTeamMemberStatus
        case useStatusStyledAssignmentCards
        case teamAssignmentSortMode
        case hideDeclinedAssignments
        case assignmentTwoColumnThreshold
        case showLiveView
        case liveURLOverride
        case liveUseCustomURL
        case teamExtras
    }

    init(
        showHeader: Bool = true,
        showServiceRundown: Bool,
        showTeamAssignments: Bool,
        teamName: String?,
        serviceTimeNames: String?,
        showRundownServiceTimeColumn: Bool,
        showRundownKeyColumn: Bool,
        showRundownTypeColumn: Bool,
        showRundownLengthColumn: Bool,
        showRundownArrangementColumn: Bool,
        showRundownBPMColumn: Bool,
        showRundownCCLIColumn: Bool,
        showRundownSequenceColumn: Bool,
        showRundownNotesColumn: Bool,
        rundownVisibleNoteCategories: String?,
        rundownTimeColumnWidth: Double,
        rundownItemColumnWidth: Double,
        rundownKeyColumnWidth: Double,
        rundownTypeColumnWidth: Double,
        rundownLengthColumnWidth: Double,
        rundownArrangementColumnWidth: Double,
        rundownBPMColumnWidth: Double,
        rundownCCLIColumnWidth: Double,
        rundownSequenceColumnWidth: Double,
        rundownNotesColumnWidth: Double,
        showSummaryLine: Bool,
        summaryLineOrder: [PCOSummaryField] = PCOSummaryField.defaultOrder,
        summaryLineHidden: [PCOSummaryField] = [],
        showTeamMemberStatus: Bool,
        useStatusStyledAssignmentCards: Bool,
        teamAssignmentSortMode: PCOTeamAssignmentSortMode,
        hideDeclinedAssignments: Bool,
        assignmentTwoColumnThreshold: Int,
        showLiveView: Bool,
        liveURLOverride: String?,
        liveUseCustomURL: Bool,
        teamExtras: PCOTeamAssignmentsExtras? = nil
    ) {
        self.showHeader = showHeader
        self.showServiceRundown = showServiceRundown
        self.showTeamAssignments = showTeamAssignments
        self.teamName = teamName
        self.serviceTimeNames = serviceTimeNames
        self.showRundownServiceTimeColumn = showRundownServiceTimeColumn
        self.showRundownKeyColumn = showRundownKeyColumn
        self.showRundownTypeColumn = showRundownTypeColumn
        self.showRundownLengthColumn = showRundownLengthColumn
        self.showRundownArrangementColumn = showRundownArrangementColumn
        self.showRundownBPMColumn = showRundownBPMColumn
        self.showRundownCCLIColumn = showRundownCCLIColumn
        self.showRundownSequenceColumn = showRundownSequenceColumn
        self.showRundownNotesColumn = showRundownNotesColumn
        self.rundownVisibleNoteCategories = rundownVisibleNoteCategories
        self.rundownTimeColumnWidth = rundownTimeColumnWidth
        self.rundownItemColumnWidth = rundownItemColumnWidth
        self.rundownKeyColumnWidth = rundownKeyColumnWidth
        self.rundownTypeColumnWidth = rundownTypeColumnWidth
        self.rundownLengthColumnWidth = rundownLengthColumnWidth
        self.rundownArrangementColumnWidth = rundownArrangementColumnWidth
        self.rundownBPMColumnWidth = rundownBPMColumnWidth
        self.rundownCCLIColumnWidth = rundownCCLIColumnWidth
        self.rundownSequenceColumnWidth = rundownSequenceColumnWidth
        self.rundownNotesColumnWidth = rundownNotesColumnWidth
        self.showSummaryLine = showSummaryLine
        self.summaryLineOrder = summaryLineOrder
        self.summaryLineHidden = summaryLineHidden
        self.showTeamMemberStatus = showTeamMemberStatus
        self.useStatusStyledAssignmentCards = useStatusStyledAssignmentCards
        self.teamAssignmentSortMode = teamAssignmentSortMode
        self.hideDeclinedAssignments = hideDeclinedAssignments
        self.assignmentTwoColumnThreshold = assignmentTwoColumnThreshold
        self.showLiveView = showLiveView
        self.liveURLOverride = liveURLOverride
        self.liveUseCustomURL = liveUseCustomURL
        self.teamExtras = teamExtras
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showHeader = try container.decodeIfPresent(Bool.self, forKey: .showHeader) ?? true
        self.showServiceRundown = try container.decodeIfPresent(Bool.self, forKey: .showServiceRundown) ?? true
        self.showTeamAssignments = try container.decodeIfPresent(Bool.self, forKey: .showTeamAssignments) ?? false
        self.teamName = try container.decodeIfPresent(String.self, forKey: .teamName)

        // New property, defaults to nil (inherit all times) if missing.
        self.serviceTimeNames = try container.decodeIfPresent(String.self, forKey: .serviceTimeNames)

        // Column flags default to `true` so existing saved configs behave as before.
        self.showRundownServiceTimeColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownServiceTimeColumn) ?? true
        self.showRundownKeyColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownKeyColumn) ?? true
        self.showRundownTypeColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownTypeColumn) ?? true
        self.showRundownLengthColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownLengthColumn) ?? true
        self.showRundownArrangementColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownArrangementColumn) ?? false
        self.showRundownBPMColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownBPMColumn) ?? false
        self.showRundownCCLIColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownCCLIColumn) ?? false
        self.showRundownSequenceColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownSequenceColumn) ?? false
        self.showRundownNotesColumn = try container.decodeIfPresent(Bool.self, forKey: .showRundownNotesColumn) ?? false
        self.rundownVisibleNoteCategories = try container.decodeIfPresent(String.self, forKey: .rundownVisibleNoteCategories)
        self.rundownTimeColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownTimeColumnWidth) ?? PCORundownColumnWidthKey.time.defaultWidth
        self.rundownItemColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownItemColumnWidth) ?? PCORundownColumnWidthKey.item.defaultWidth
        self.rundownKeyColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownKeyColumnWidth) ?? PCORundownColumnWidthKey.key.defaultWidth
        self.rundownTypeColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownTypeColumnWidth) ?? PCORundownColumnWidthKey.type.defaultWidth
        self.rundownLengthColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownLengthColumnWidth) ?? PCORundownColumnWidthKey.length.defaultWidth
        self.rundownArrangementColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownArrangementColumnWidth) ?? PCORundownColumnWidthKey.arrangement.defaultWidth
        self.rundownBPMColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownBPMColumnWidth) ?? PCORundownColumnWidthKey.bpm.defaultWidth
        self.rundownCCLIColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownCCLIColumnWidth) ?? PCORundownColumnWidthKey.ccli.defaultWidth
        self.rundownSequenceColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownSequenceColumnWidth) ?? PCORundownColumnWidthKey.sequence.defaultWidth
        self.rundownNotesColumnWidth = try container.decodeIfPresent(Double.self, forKey: .rundownNotesColumnWidth) ?? PCORundownColumnWidthKey.notes.defaultWidth
        self.showSummaryLine = try container.decodeIfPresent(Bool.self, forKey: .showSummaryLine) ?? true
        self.summaryLineOrder = try container.decodeIfPresent([PCOSummaryField].self, forKey: .summaryLineOrder) ?? PCOSummaryField.defaultOrder
        self.summaryLineHidden = try container.decodeIfPresent([PCOSummaryField].self, forKey: .summaryLineHidden) ?? []
        self.showTeamMemberStatus = try container.decodeIfPresent(Bool.self, forKey: .showTeamMemberStatus) ?? true
        self.useStatusStyledAssignmentCards = try container.decodeIfPresent(Bool.self, forKey: .useStatusStyledAssignmentCards) ?? false
        self.teamAssignmentSortMode = try container.decodeIfPresent(PCOTeamAssignmentSortMode.self, forKey: .teamAssignmentSortMode) ?? .positionName
        self.hideDeclinedAssignments = try container.decodeIfPresent(Bool.self, forKey: .hideDeclinedAssignments) ?? false
        self.assignmentTwoColumnThreshold = max(1, try container.decodeIfPresent(Int.self, forKey: .assignmentTwoColumnThreshold) ?? 15)
        self.showLiveView = try container.decodeIfPresent(Bool.self, forKey: .showLiveView) ?? false
        self.liveURLOverride = try container.decodeIfPresent(String.self, forKey: .liveURLOverride)
        self.liveUseCustomURL = try container.decodeIfPresent(Bool.self, forKey: .liveUseCustomURL) ?? false
        self.teamExtras = try container.decodeIfPresent(PCOTeamAssignmentsExtras.self, forKey: .teamExtras)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showHeader, forKey: .showHeader)
        try container.encode(showServiceRundown, forKey: .showServiceRundown)
        try container.encode(showTeamAssignments, forKey: .showTeamAssignments)
        try container.encodeIfPresent(teamName, forKey: .teamName)
        try container.encodeIfPresent(serviceTimeNames, forKey: .serviceTimeNames)
        try container.encode(showRundownServiceTimeColumn, forKey: .showRundownServiceTimeColumn)
        try container.encode(showRundownKeyColumn, forKey: .showRundownKeyColumn)
        try container.encode(showRundownTypeColumn, forKey: .showRundownTypeColumn)
        try container.encode(showRundownLengthColumn, forKey: .showRundownLengthColumn)
        try container.encode(showRundownArrangementColumn, forKey: .showRundownArrangementColumn)
        try container.encode(showRundownBPMColumn, forKey: .showRundownBPMColumn)
        try container.encode(showRundownCCLIColumn, forKey: .showRundownCCLIColumn)
        try container.encode(showRundownSequenceColumn, forKey: .showRundownSequenceColumn)
        try container.encode(showRundownNotesColumn, forKey: .showRundownNotesColumn)
        try container.encodeIfPresent(rundownVisibleNoteCategories, forKey: .rundownVisibleNoteCategories)
        try container.encode(rundownTimeColumnWidth, forKey: .rundownTimeColumnWidth)
        try container.encode(rundownItemColumnWidth, forKey: .rundownItemColumnWidth)
        try container.encode(rundownKeyColumnWidth, forKey: .rundownKeyColumnWidth)
        try container.encode(rundownTypeColumnWidth, forKey: .rundownTypeColumnWidth)
        try container.encode(rundownLengthColumnWidth, forKey: .rundownLengthColumnWidth)
        try container.encode(rundownArrangementColumnWidth, forKey: .rundownArrangementColumnWidth)
        try container.encode(rundownBPMColumnWidth, forKey: .rundownBPMColumnWidth)
        try container.encode(rundownCCLIColumnWidth, forKey: .rundownCCLIColumnWidth)
        try container.encode(rundownSequenceColumnWidth, forKey: .rundownSequenceColumnWidth)
        try container.encode(rundownNotesColumnWidth, forKey: .rundownNotesColumnWidth)
        try container.encode(showSummaryLine, forKey: .showSummaryLine)
        try container.encode(summaryLineOrder, forKey: .summaryLineOrder)
        try container.encode(summaryLineHidden, forKey: .summaryLineHidden)
        try container.encode(showTeamMemberStatus, forKey: .showTeamMemberStatus)
        try container.encode(useStatusStyledAssignmentCards, forKey: .useStatusStyledAssignmentCards)
        try container.encode(teamAssignmentSortMode, forKey: .teamAssignmentSortMode)
        try container.encode(hideDeclinedAssignments, forKey: .hideDeclinedAssignments)
        try container.encode(assignmentTwoColumnThreshold, forKey: .assignmentTwoColumnThreshold)
        try container.encode(showLiveView, forKey: .showLiveView)
        try container.encodeIfPresent(liveURLOverride, forKey: .liveURLOverride)
        try container.encode(liveUseCustomURL, forKey: .liveUseCustomURL)
        try container.encodeIfPresent(teamExtras, forKey: .teamExtras)
    }
}
struct PCORundownRow: Identifiable, Codable, Equatable {
    let id: String
    /// Display order for non-header items. Headers are not numbered.
    let order: Int?
    let title: String
    /// Musical key for the item (e.g. "G", "Bb"). Empty for headers or items
    /// without a key.
    let keyText: String
    let type: String
    let lengthText: String
    let arrangementText: String
    let bpmText: String
    let ccliText: String
    let sequenceText: String
    let notesText: String
    let noteTextsByCategory: [String: [String]]
    /// Map of service-time label -> localized time string for that service
    /// (e.g. ["9:00 AM": "9:00 AM", "10:30 AM": "10:30 AM"]). Headers
    /// typically have an empty dictionary here.
    let timeTextsByLabel: [String: String]
    let isHeader: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case order
        case title
        case keyText
        case type
        case lengthText
        case arrangementText
        case bpmText
        case ccliText
        case sequenceText
        case notesText
        case noteTextsByCategory
        case timeTextsByLabel
        case isHeader
    }

    init(
        id: String,
        order: Int?,
        title: String,
        keyText: String,
        type: String,
        lengthText: String,
        arrangementText: String,
        bpmText: String,
        ccliText: String,
        sequenceText: String,
        notesText: String,
        noteTextsByCategory: [String: [String]],
        timeTextsByLabel: [String: String],
        isHeader: Bool
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.keyText = keyText
        self.type = type
        self.lengthText = lengthText
        self.arrangementText = arrangementText
        self.bpmText = bpmText
        self.ccliText = ccliText
        self.sequenceText = sequenceText
        self.notesText = notesText
        self.noteTextsByCategory = noteTextsByCategory
        self.timeTextsByLabel = timeTextsByLabel
        self.isHeader = isHeader
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        order = try container.decodeIfPresent(Int.self, forKey: .order)
        title = try container.decode(String.self, forKey: .title)
        keyText = try container.decodeIfPresent(String.self, forKey: .keyText) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        lengthText = try container.decodeIfPresent(String.self, forKey: .lengthText) ?? ""
        arrangementText = try container.decodeIfPresent(String.self, forKey: .arrangementText) ?? ""
        bpmText = try container.decodeIfPresent(String.self, forKey: .bpmText) ?? ""
        ccliText = try container.decodeIfPresent(String.self, forKey: .ccliText) ?? ""
        sequenceText = try container.decodeIfPresent(String.self, forKey: .sequenceText) ?? ""
        notesText = try container.decodeIfPresent(String.self, forKey: .notesText) ?? ""
        noteTextsByCategory = try container.decodeIfPresent([String: [String]].self, forKey: .noteTextsByCategory) ?? [:]
        timeTextsByLabel = try container.decodeIfPresent([String: String].self, forKey: .timeTextsByLabel) ?? [:]
        isHeader = try container.decodeIfPresent(Bool.self, forKey: .isHeader) ?? false
    }

    func filteredNotesText(visibleCategories: Set<String>?) -> String {
        guard !noteTextsByCategory.isEmpty else { return notesText }

        let orderedCategories = noteTextsByCategory.keys.sorted { lhs, rhs in
            if lhs == "General" { return true }
            if rhs == "General" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        let selected = visibleCategories?.isEmpty == false ? visibleCategories : nil
        let parts = orderedCategories.compactMap { category -> String? in
            if let selected, !selected.contains(category) {
                return nil
            }
            let values = noteTextsByCategory[category]?
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            guard !values.isEmpty else { return nil }
            if category == "General" {
                return values.joined(separator: " • ")
            }
            return "\(category): \(values.joined(separator: " / "))"
        }

        if parts.isEmpty, selected != nil {
            return ""
        }
        return parts.isEmpty ? notesText : parts.joined(separator: " • ")
    }
}

private struct PCORundownSupplementalData {
    let arrangementText: String
    let bpmText: String
    let ccliText: String
    let sequenceText: String
    let notesText: String
    let noteTextsByCategory: [String: [String]]

    static let empty = PCORundownSupplementalData(
        arrangementText: "",
        bpmText: "",
        ccliText: "",
        sequenceText: "",
        notesText: "",
        noteTextsByCategory: [:]
    )
}

// MARK: - PCO Module Settings Inspector

/// Module-scoped settings UI for the Planning Center (PCO) rundown module.
/// This is owned by the PCO module plugin so `DashboardTileEditView` does not
/// need any PCO-specific inspector code.
struct PCOModuleSettingsInspector: View {
    @Binding var config: PCOModuleConfig
    let tab: DashboardTab
    var onPersist: () -> Void
    var onOpenTabSettings: () -> Void
    @AppStorage("dashboard_pco_connected") private var isConnected: Bool = false
    @AppStorage("dashboard_pco_live_warning_shown") private var liveWarningShown = false
    @State private var showLiveWarning = false
    @State private var draggingSummaryField: PCOSummaryField?
    @State private var dropIndicatorField: PCOSummaryField?
    @State private var dropIndicatorAfter: Bool = false

    private var summaryLineOrderNormalized: [PCOSummaryField] {
        let stored = config.summaryLineOrder
        var order = stored.isEmpty ? PCOSummaryField.defaultOrder : stored
        for field in PCOSummaryField.allCases where !order.contains(field) {
            order.append(field)
        }
        return order
    }

    private var summaryLineHiddenSet: Set<PCOSummaryField> {
        Set(config.summaryLineHidden)
    }

    private var summaryLineOrderBinding: Binding<[PCOSummaryField]> {
        Binding(
            get: { summaryLineOrderNormalized },
            set: { newValue in
                config.summaryLineOrder = newValue
                onPersist()
            }
        )
    }

    private var hasPlanningCenterLogin: Bool {
        isConnected
    }

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
        let tabSelectedNames = Set(
            (tab.teamName ?? "")
                .components(separatedBy: "||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        if !tabSelectedNames.isEmpty {
            return Array(tabSelectedNames)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        let cachedNames = Set(
            tab.pcoCachedTeamAssignments.compactMap { row in
                let trimmed = row.teamName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        )

        return Array(cachedNames)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var selectedModuleTeamNames: Set<String> {
        Set(
            (config.teamName ?? "")
                .components(separatedBy: "||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private var inheritedTabTeamSummary: String? {
        let labels = (tab.teamName ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !labels.isEmpty else { return nil }
        return labels.joined(separator: ", ")
    }

    private var availableRundownNoteCategories: [String] {
        let categories = Set(
            tab.pcoCachedRundownRows
                .flatMap { row in row.noteTextsByCategory.keys }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return categories.sorted { lhs, rhs in
            if lhs == "General" { return true }
            if rhs == "General" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var selectedRundownNoteCategories: Set<String> {
        Set(
            (config.rundownVisibleNoteCategories ?? "")
                .components(separatedBy: "||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private var usesDefaultRundownNoteCategorySelection: Bool {
        config.rundownVisibleNoteCategories == nil
    }

    private func updateModuleTeamSelection(_ selectedNames: Set<String>) {
        let normalized = Array(selectedNames)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        config.teamName = normalized.isEmpty ? nil : normalized.joined(separator: "||")
        onPersist()
    }

    private func updateRundownNoteCategorySelection(_ selectedNames: Set<String>) {
        let normalized = Array(selectedNames)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        config.rundownVisibleNoteCategories = normalized.joined(separator: "||")
        onPersist()
    }

    private func toggleRundownColumn(_ keyPath: WritableKeyPath<PCOModuleConfig, Bool>) {
        config[keyPath: keyPath].toggle()
        onPersist()
    }

    @ViewBuilder
    private func optionChip(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.small)
                Text(title)
                    .lineLimit(1)
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
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasPlanningCenterLogin {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Planning Center Login Required", systemImage: "link.badge.plus")
                        .font(.headline)

                    Text("Log into Planning Center in App Settings before configuring this module.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            } else if !hasPlanningCenterTabConfiguration {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Planning Center Tab Setup Required", systemImage: "exclamationmark.triangle")
                        .font(.headline)

                    Text("Configure a service, plan, and time in Tab Settings before using this Planning Center module.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Tab Settings") {
                        onOpenTabSettings()
                    }
                    .buttonStyle(.borderedProminent)
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

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show header (Planning Center)", isOn: persistedBinding(for: \.showHeader))

                    Toggle("Show summary line", isOn: persistedBinding(for: \.showSummaryLine))

                    if config.showSummaryLine {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Summary line fields")
                                .font(.headline)

                            Text("Drag to reorder. Tap the eye to hide a field.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 4) {
                                ForEach(summaryLineOrderNormalized) { field in
                                    let isHidden = summaryLineHiddenSet.contains(field)

                                    HStack(spacing: 6) {
                                        Text(field.title)
                                            .font(.callout)

                                        Button {
                                            var updated = summaryLineHiddenSet
                                            if isHidden {
                                                updated.remove(field)
                                            } else {
                                                updated.insert(field)
                                            }
                                            config.summaryLineHidden = Array(updated)
                                            onPersist()
                                        } label: {
                                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 16, height: 16)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 4)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(.rect(cornerRadius: 12))
                                    .opacity(isHidden ? 0.45 : 1)
                                    .overlay(alignment: dropIndicatorAfter ? .trailing : .leading) {
                                        if dropIndicatorField == field {
                                            Rectangle()
                                                .fill(Color.accentColor.opacity(0.9))
                                                .frame(width: 2)
                                                .padding(.vertical, 2)
                                        }
                                    }
                                    .onDrag {
                                        draggingSummaryField = field
                                        return NSItemProvider(object: field.id as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: SummaryFieldDropDelegate(
                                            target: field,
                                            order: summaryLineOrderBinding,
                                            dragging: $draggingSummaryField,
                                            indicatorField: $dropIndicatorField,
                                            indicatorAfter: $dropIndicatorAfter
                                        )
                                    )
                                }
                            }
                            .padding(.top, 2)
                        }
                        .padding(.top, 4)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Rundown columns")
                                .font(.headline)
                            Spacer()
                            Button("Reset widths") {
                                config.rundownTimeColumnWidth = PCORundownColumnWidthKey.time.defaultWidth
                                config.rundownKeyColumnWidth = PCORundownColumnWidthKey.key.defaultWidth
                                config.rundownTypeColumnWidth = PCORundownColumnWidthKey.type.defaultWidth
                                config.rundownLengthColumnWidth = PCORundownColumnWidthKey.length.defaultWidth
                                config.rundownArrangementColumnWidth = PCORundownColumnWidthKey.arrangement.defaultWidth
                                config.rundownBPMColumnWidth = PCORundownColumnWidthKey.bpm.defaultWidth
                                config.rundownCCLIColumnWidth = PCORundownColumnWidthKey.ccli.defaultWidth
                                config.rundownSequenceColumnWidth = PCORundownColumnWidthKey.sequence.defaultWidth
                                config.rundownNotesColumnWidth = PCORundownColumnWidthKey.notes.defaultWidth
                                onPersist()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }

                        Text("Choose which columns this module renders. Drag a column edge in the rundown header to resize it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                            optionChip("Service times", isSelected: config.showRundownServiceTimeColumn) {
                                toggleRundownColumn(\.showRundownServiceTimeColumn)
                            }
                            optionChip("Key", isSelected: config.showRundownKeyColumn) {
                                toggleRundownColumn(\.showRundownKeyColumn)
                            }
                            optionChip("Type", isSelected: config.showRundownTypeColumn) {
                                toggleRundownColumn(\.showRundownTypeColumn)
                            }
                            optionChip("Length", isSelected: config.showRundownLengthColumn) {
                                toggleRundownColumn(\.showRundownLengthColumn)
                            }
                            optionChip("Arrangement", isSelected: config.showRundownArrangementColumn) {
                                toggleRundownColumn(\.showRundownArrangementColumn)
                            }
                            optionChip("BPM", isSelected: config.showRundownBPMColumn) {
                                toggleRundownColumn(\.showRundownBPMColumn)
                            }
                            optionChip("CCLI", isSelected: config.showRundownCCLIColumn) {
                                toggleRundownColumn(\.showRundownCCLIColumn)
                            }
                            optionChip("Sequence", isSelected: config.showRundownSequenceColumn) {
                                toggleRundownColumn(\.showRundownSequenceColumn)
                            }
                            optionChip("Notes", isSelected: config.showRundownNotesColumn) {
                                toggleRundownColumn(\.showRundownNotesColumn)
                            }
                        }

                        if config.showRundownNotesColumn {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Visible note categories")
                                        .font(.headline)
                                    Spacer()
                                    if !usesDefaultRundownNoteCategorySelection {
                                        Button("Show All") {
                                            config.rundownVisibleNoteCategories = nil
                                            onPersist()
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                    }
                                }

                                if availableRundownNoteCategories.isEmpty {
                                    Text("Refresh the rundown to load available note categories.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(usesDefaultRundownNoteCategorySelection
                                         ? "All note categories are currently visible."
                                         : "Only the selected note categories will appear in the Notes column. Clear all to show none.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                                        ForEach(availableRundownNoteCategories, id: \.self) { category in
                                            let isSelected = usesDefaultRundownNoteCategorySelection || selectedRundownNoteCategories.contains(category)
                                            optionChip(category, isSelected: isSelected) {
                                                var updated = selectedRundownNoteCategories
                                                if usesDefaultRundownNoteCategorySelection {
                                                    updated = Set(availableRundownNoteCategories)
                                                }
                                                if updated.contains(category) {
                                                    updated.remove(category)
                                                } else {
                                                    updated.insert(category)
                                                }
                                                updateRundownNoteCategorySelection(updated)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.top, 6)

                    Divider()

                    Toggle("Show Services Live (web)", isOn: Binding(
                        get: { config.showLiveView },
                        set: { newValue in
                            config.showLiveView = newValue
                            if newValue, liveWarningShown == false {
                                liveWarningShown = true
                                showLiveWarning = true
                            }
                            onPersist()
                        }
                    ))

                    if config.showLiveView {
                        Toggle("Use custom Live URL", isOn: persistedBinding(for: \.liveUseCustomURL))

                        if config.liveUseCustomURL {
                            TextField("Services Live URL", text: Binding(
                                get: { config.liveURLOverride ?? "" },
                                set: { newValue in
                                    config.liveURLOverride = newValue
                                    onPersist()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        Text(config.liveUseCustomURL
                             ? "Paste a Services Live link from Planning Center."
                             : "Uses the selected plan Live link automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                }
                .toggleStyle(.switch)
            } label: {
                HStack(spacing: 8) {
                    Text("Planning Center")
                    Spacer()
                    Image(systemName: hasPlanningCenterLogin ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hasPlanningCenterLogin ? .green : .yellow)
                        .imageScale(.small)
                        .accessibilityLabel(hasPlanningCenterLogin ? "Connected" : "Not connected")
                }
            }
        }
        .alert("Services Live Login", isPresented: $showLiveWarning) {
            Button("OK") {}
        } message: {
            Text("You’ll need to log in to Planning Center Live inside the embedded view the first time.")
        }
    }
}

enum AssignmentStatus: String, Codable {
    case unknown
    case pending
    case confirmed
    case declined

    var label: String {
        switch self {
        case .unknown:  return ""
        case .pending:  return "Pending"
        case .confirmed:return "Confirmed"
        case .declined: return "Declined"
        }
    }

    var color: Color {
        switch self {
        case .unknown:
            return .gray.opacity(0.5)
        case .pending:
            return .yellow
        case .confirmed:
            return .green
        case .declined:
            return .red
        }
    }

    var symbolName: String {
        switch self {
        case .unknown:
            return "circle.fill"
        case .pending:
            return "questionmark"
        case .confirmed:
            return "checkmark"
        case .declined:
            return "xmark"
        }
    }
}

struct PCOTeamAssignmentRow: Identifiable, Codable, Equatable {
    let id: UUID
    let positionName: String
    let personName: String
    let teamName: String?
    let status: AssignmentStatus
    let serviceTimeLabels: [String]
    fileprivate let serviceTimeSortKey: PCOTeamAssignmentTimeSortKey
    /// Stable Planning Center person identifier when available. Used by
    /// Team Assignments tiles to key per-assignment metadata (avatar
    /// placement, mic/IEM picks) so we can survive renames or duplicate
    /// names in the same plan.
    let personID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case positionName
        case personName
        case teamName
        case status
        case serviceTimeLabels
        case personID
    }

    init(
        id: UUID = UUID(),
        positionName: String,
        personName: String,
        teamName: String?,
        status: AssignmentStatus,
        serviceTimeLabels: [String] = [],
        personID: String? = nil
    ) {
        self.id = id
        self.positionName = positionName
        self.personName = personName
        self.teamName = teamName
        self.status = status
        self.serviceTimeLabels = serviceTimeLabels
        self.serviceTimeSortKey = PCOTeamAssignmentTimeSortKey(labels: serviceTimeLabels)
        self.personID = personID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        positionName = try container.decode(String.self, forKey: .positionName)
        personName = try container.decode(String.self, forKey: .personName)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName)
        status = try container.decode(AssignmentStatus.self, forKey: .status)
        serviceTimeLabels = try container.decodeIfPresent([String].self, forKey: .serviceTimeLabels) ?? []
        serviceTimeSortKey = PCOTeamAssignmentTimeSortKey(labels: serviceTimeLabels)
        personID = try container.decodeIfPresent(String.self, forKey: .personID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(positionName, forKey: .positionName)
        try container.encode(personName, forKey: .personName)
        try container.encodeIfPresent(teamName, forKey: .teamName)
        try container.encode(status, forKey: .status)
        try container.encode(serviceTimeLabels, forKey: .serviceTimeLabels)
        try container.encodeIfPresent(personID, forKey: .personID)
    }
}

fileprivate struct PCOTeamAssignmentTimeSortKey: Equatable {
    let firstMinutes: Int
    let labelCount: Int
    let joined: String

    init(labels: [String]) {
        let normalizedLabels = labels.filter { !$0.isEmpty }
        firstMinutes = normalizedLabels.compactMap(Self.parseMinutes).min() ?? Int.max
        labelCount = normalizedLabels.count
        joined = normalizedLabels.joined(separator: " | ")
    }

    nonisolated private static func parseMinutes(from label: String) -> Int? {
        let parts = label
            .components(separatedBy: "—")
            .flatMap { $0.components(separatedBy: "-") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for part in parts {
            if let minutes = parseTimePart(part) {
                return minutes
            }
        }

        return nil
    }

    nonisolated private static func parseTimePart(_ part: String) -> Int? {
        var normalized = part
            .uppercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        let suffix: String?
        if normalized.hasSuffix("AM") {
            suffix = "AM"
            normalized.removeLast(2)
        } else if normalized.hasSuffix("PM") {
            suffix = "PM"
            normalized.removeLast(2)
        } else {
            suffix = nil
        }

        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let components = normalized.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count <= 2,
              let rawHour = Int(components[0]),
              rawHour >= 0 else {
            return nil
        }

        let rawMinute: Int
        if components.count == 2 {
            guard components[1].count == 2,
                  let minute = Int(components[1]),
                  (0..<60).contains(minute) else {
                return nil
            }
            rawMinute = minute
        } else {
            rawMinute = 0
        }

        let hour: Int
        switch suffix {
        case "AM":
            guard (1...12).contains(rawHour) else { return nil }
            hour = rawHour == 12 ? 0 : rawHour
        case "PM":
            guard (1...12).contains(rawHour) else { return nil }
            hour = rawHour == 12 ? 12 : rawHour + 12
        default:
            guard (0..<24).contains(rawHour), components.count == 2 else { return nil }
            hour = rawHour
        }

        return (hour * 60) + rawMinute
    }
}

private struct SummaryFieldDropDelegate: DropDelegate {
    let target: PCOSummaryField
    @Binding var order: [PCOSummaryField]
    @Binding var dragging: PCOSummaryField?
    @Binding var indicatorField: PCOSummaryField?
    @Binding var indicatorAfter: Bool

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator()
        return DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        updateIndicator()
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            indicatorField = nil
        }
        guard let dragging, dragging != target else { return false }
        guard let fromIndex = order.firstIndex(of: dragging),
              let targetIndex = order.firstIndex(of: target) else { return false }

        var updated = order
        updated.remove(at: fromIndex)

        let insertAfter = fromIndex < targetIndex
        var destinationIndex = insertAfter ? (targetIndex + 1) : targetIndex
        if fromIndex < destinationIndex {
            destinationIndex -= 1
        }
        destinationIndex = max(0, min(updated.count, destinationIndex))
        updated.insert(dragging, at: destinationIndex)
        order = updated
        return true
    }

    func dropExited(info: DropInfo) {
        indicatorField = nil
    }

    private func updateIndicator() {
        guard let dragging, dragging != target else { return }
        guard let fromIndex = order.firstIndex(of: dragging),
              let targetIndex = order.firstIndex(of: target) else { return }
        indicatorField = target
        indicatorAfter = fromIndex < targetIndex
    }
}

private struct TeamAssignmentsContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct RundownViewportWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PCOTileView: View {
    private static let log = Logger(subsystem: "Relay", category: "PCO")
    private static let tabSnapshotSchemaVersion = "pco-rundown-v2"

    static func makeTabSnapshotKey(
        serviceTypeID: String?,
        planID: String?,
        serviceTimeName: String?
    ) -> String {
        [
            tabSnapshotSchemaVersion,
            serviceTypeID ?? "",
            planID ?? "",
            serviceTimeName ?? ""
        ].joined(separator: "|")
    }
    private struct CachedPCOState {
        let key: String
        let rundownRows: [PCORundownRow]
        let teamAssignments: [PCOTeamAssignmentRow]
        let rundownError: String?
        let teamError: String?
    }
    private struct RuntimePlanContext {
        let itemsAndTimes: PCOClient.ItemsAndTimes
        let members: [PCOClient.TeamMemberSummary]
    }
    private static var cachedStateByTabId: [UUID: CachedPCOState] = [:]
    private static let runtimeCacheTTL: TimeInterval = 30
    private static var runtimeItemsAndTimesCache: [String: (value: PCOClient.ItemsAndTimes, fetchedAt: Date)] = [:]
    private static var runtimeItemsAndTimesTasks: [String: Task<PCOClient.ItemsAndTimes, Error>] = [:]
    private static var runtimeTeamMembersCache: [String: (value: [PCOClient.TeamMemberSummary], fetchedAt: Date)] = [:]
    private static var runtimeTeamMembersTasks: [String: Task<[PCOClient.TeamMemberSummary], Error>] = [:]
    private static var runtimeServiceTypeTeamsCache: [String: (value: [String], fetchedAt: Date)] = [:]
    private static var runtimeServiceTypeTeamsTasks: [String: Task<[String], Error>] = [:]
    private static var runtimeTeamPositionsCache: [String: (value: [String: [String]], fetchedAt: Date)] = [:]
    private static var runtimeTeamPositionsTasks: [String: Task<[String: [String]], Error>] = [:]
    private static let liveModeRefreshInterval: TimeInterval = 120
    private static var lastLiveSnapshotRefreshAtByKey: [String: Date] = [:]
    private static let startupWarmRefreshInterval: TimeInterval = 30
    private static var lastStartupWarmRefreshAtByKey: [String: Date] = [:]

    static func invalidateCachedData(serviceTypeID: String, planID: String, tabID: UUID) {
        let cacheKey = "\(serviceTypeID)|\(planID)"
        runtimeItemsAndTimesCache[cacheKey] = nil
        runtimeItemsAndTimesTasks[cacheKey]?.cancel()
        runtimeItemsAndTimesTasks[cacheKey] = nil
        runtimeTeamMembersCache[cacheKey] = nil
        runtimeTeamMembersTasks[cacheKey]?.cancel()
        runtimeTeamMembersTasks[cacheKey] = nil
        cachedStateByTabId[tabID] = nil
    }

    static func invalidateRuntimeFetchCaches(serviceTypeID: String, planID: String) {
        let cacheKey = "\(serviceTypeID)|\(planID)"
        runtimeItemsAndTimesCache[cacheKey] = nil
        runtimeItemsAndTimesTasks[cacheKey]?.cancel()
        runtimeItemsAndTimesTasks[cacheKey] = nil
        runtimeTeamMembersCache[cacheKey] = nil
        runtimeTeamMembersTasks[cacheKey]?.cancel()
        runtimeTeamMembersTasks[cacheKey] = nil
    }
    private let orderColumnWidth: CGFloat = 30
    private let rundownColumnGapWidth: CGFloat = 10

    @Binding var tab: DashboardTab
    /// Optional per-module configuration. When nil, we treat it as
    /// `PCOModuleConfig.default()` so the tile behaves consistently and is
    /// ready for the module-plugin pipeline.
    var moduleConfig: PCOModuleConfig?
    var moduleConfigBinding: Binding<PCOModuleConfig>?
    var onRundownColumnResizeActiveChanged: ((Bool) -> Void)?
    init(
        tab: Binding<DashboardTab>,
        moduleConfig: PCOModuleConfig? = nil,
        moduleConfigBinding: Binding<PCOModuleConfig>? = nil,
        onRundownColumnResizeActiveChanged: ((Bool) -> Void)? = nil
    ) {
        self._tab = tab
        self.moduleConfig = moduleConfig
        self.moduleConfigBinding = moduleConfigBinding
        self.onRundownColumnResizeActiveChanged = onRundownColumnResizeActiveChanged
    }

    @AppStorage("dashboard_pco_connected") private var isConnected: Bool = false
    @AppStorage("dashboard_live_mode_enabled") private var isLiveMode: Bool = false
    @AppStorage("dashboard_view_mode") private var dashboardViewMode: String = "canvas"
    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    @Environment(\.dashboardIsPCOConfigOpen) private var isPCOConfigOpen

    // Rundown state
    @State private var rundownRows: [PCORundownRow] = []
    @State private var isLoadingRundown = false
    @State private var rundownError: String?
    @State private var lastAppliedSettingsKey: String?

    /// Tracks which service/plan the last successful rundown load came from.
    /// This lets us distinguish between a legitimate "no items" change (e.g.,
    /// switching to a different plan with no items) and a spurious empty
    /// refresh for the same plan that would otherwise wipe out data.
    @State private var lastLoadedServiceTypeID: String?
    @State private var lastLoadedPlanID: String?


    // Team assignments state
    @State private var teamAssignments: [PCOTeamAssignmentRow] = []
    @State private var sortedTeamAssignments: [PCOTeamAssignmentRow] = []
    @State private var activeRundownResizeColumn: PCORundownColumnWidthKey?
    @State private var activeRundownResizeStartWidth: CGFloat = 0
    @State private var activeRundownResizeStartX: CGFloat = 0
    @State private var rundownViewportWidth: CGFloat = 0
    @State private var isLoadingTeams = false
    @State private var teamError: String?
    @State private var activeTeamTabName: String?
    @State private var cachedServiceTimeLabelsForColumns: [String] = []
    @State private var cachedSortedServiceTimesSummaryLabel: String?

    private var cachedStateForKey: CachedPCOState? {
        guard let cached = Self.cachedStateByTabId[tab.id],
              cached.key == settingsRefreshKey else {
            return nil
        }
        return cached
    }

    private var displayedRundownRows: [PCORundownRow] {
        if !tabSnapshotRundownRows.isEmpty { return tabSnapshotRundownRows }
        if !rundownRows.isEmpty { return rundownRows }
        return cachedStateForKey?.rundownRows ?? []
    }

    private func filteredAssignmentRows(_ rows: [PCOTeamAssignmentRow]) -> [PCOTeamAssignmentRow] {
        guard effectiveConfig.hideDeclinedAssignments else { return rows }
        return rows.filter { $0.status != .declined }
    }

    private var displayedTeamAssignments: [PCOTeamAssignmentRow] {
        let rows: [PCOTeamAssignmentRow]
        if !tabSnapshotTeamAssignments.isEmpty {
            rows = tabSnapshotTeamAssignments
        } else if !teamAssignments.isEmpty {
            rows = teamAssignments
        } else {
            rows = cachedStateForKey?.teamAssignments ?? []
        }

        return filteredAssignmentRows(rows)
    }

    private var displayedSortedTeamAssignments: [PCOTeamAssignmentRow] {
        let filteredLocalSortedRows = filteredAssignmentRows(sortedTeamAssignments)
        if !filteredLocalSortedRows.isEmpty { return filteredLocalSortedRows }

        if !tabSnapshotTeamAssignments.isEmpty {
            return Self.sortTeamAssignmentRows(
                filteredAssignmentRows(tabSnapshotTeamAssignments),
                mode: effectiveConfig.teamAssignmentSortMode
            )
        }

        return Self.sortTeamAssignmentRows(
            filteredAssignmentRows(cachedStateForKey?.teamAssignments ?? []),
            mode: effectiveConfig.teamAssignmentSortMode
        )
    }

    private var availableAssignmentTeamTabs: [String] {
        let teamsFromRows = displayedSortedTeamAssignments.reduce(into: [String]()) { result, row in
            let teamName = (row.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !teamName.isEmpty, !result.contains(teamName) else { return }
            result.append(teamName)
        }

        if !effectiveTeamNames.isEmpty {
            let rowSet = Set(teamsFromRows)
            let configured = effectiveTeamNames.filter { rowSet.contains($0) }
            return configured.isEmpty ? effectiveTeamNames : configured
        }

        return teamsFromRows
    }

    private var visibleTeamAssignments: [PCOTeamAssignmentRow] {
        let rows = displayedSortedTeamAssignments
        guard let activeTeamTabName,
              availableAssignmentTeamTabs.count > 1 else {
            return rows
        }

        return rows.filter { row in
            let teamName = (row.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return teamName.caseInsensitiveCompare(activeTeamTabName) == .orderedSame
        }
    }

    private var availableAssignmentTeamTabsKey: String {
        availableAssignmentTeamTabs.joined(separator: "||")
    }

    private var displayedRundownError: String? {
        rundownError ?? cachedStateForKey?.rundownError
    }

    private var displayedTeamError: String? {
        teamError ?? cachedStateForKey?.teamError
    }
    @State private var liveFallbackActive = false

    // MARK: - Text Formatting Helpers

    /// Base font size for this tile; other sizes are scaled from here.
    private var baseFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    private var primaryFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    private var resolvedPrimaryColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
    }

    private var resolvedSecondaryColor: Color {
        resolvedPrimaryColor.opacity(0.7)
    }

    /// Resolved text alignment based on the tile's justification setting.
    private var resolvedTextAlignment: TextAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Resolved horizontal alignment for frames based on justification.
    private var resolvedHorizontalAlignment: Alignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Font for the main header ("Planning Center").
    private var headerFont: Font {
        .system(size: baseFontSize * 0.9, weight: primaryFontWeight)
    }

    /// Font for the service summary line.
    private var summaryFont: Font {
        .system(size: baseFontSize * 0.75, weight: primaryFontWeight)
    }

    /// Font for regular content rows (titles, names).
    private var contentFont: Font {
        .system(size: baseFontSize * 0.7, weight: primaryFontWeight)
    }

    /// Font for small caption-like text (statuses, errors).
    private var captionFont: Font {
        .system(size: baseFontSize * 0.6, weight: primaryFontWeight)
    }

    /// Font for monospaced numeric details (order numbers, lengths).
    private var numericFont: Font {
        .system(size: baseFontSize * 0.6, weight: primaryFontWeight, design: .monospaced)
    }

    private func applyCapitalization(_ string: String) -> String {
        Self.applyCapitalization(string, style: tileTextFormatting?.capitalization ?? .normal)
    }

    fileprivate static func applyCapitalization(_ string: String, style: TextCapitalizationStyle) -> String {
        switch style {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }

    // MARK: - Effective configuration

    /// Effective module configuration. If no per-module config exists yet,
    /// use defaults so newly added PCO modules behave predictably.
    private var effectiveConfig: PCOModuleConfig {
        moduleConfigBinding?.wrappedValue ?? moduleConfig ?? PCOModuleConfig.rundownDefault()
    }

    private var showServiceRundown: Bool {
        effectiveConfig.showServiceRundown
    }

    private var showTeamAssignments: Bool {
        effectiveConfig.showTeamAssignments
    }

    private var showLiveView: Bool {
        effectiveConfig.showLiveView
    }

    private var shouldRenderPCODataSections: Bool {
        showServiceRundown || showTeamAssignments
    }

    private var showRundownServiceTimeColumn: Bool {
        effectiveConfig.showRundownServiceTimeColumn
    }

    private var showRundownKeyColumn: Bool {
        effectiveConfig.showRundownKeyColumn
    }

    private var showRundownTypeColumn: Bool {
        effectiveConfig.showRundownTypeColumn
    }

    private var showRundownLengthColumn: Bool {
        effectiveConfig.showRundownLengthColumn
    }

    private var showRundownArrangementColumn: Bool {
        effectiveConfig.showRundownArrangementColumn
    }

    private var showRundownBPMColumn: Bool {
        effectiveConfig.showRundownBPMColumn
    }

    private var showRundownCCLIColumn: Bool {
        effectiveConfig.showRundownCCLIColumn
    }

    private var showRundownSequenceColumn: Bool {
        effectiveConfig.showRundownSequenceColumn
    }

    private var showRundownNotesColumn: Bool {
        effectiveConfig.showRundownNotesColumn
    }

    private var timeColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownTimeColumnWidth)
    }

    private var itemColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownItemColumnWidth)
    }

    private var keyColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownKeyColumnWidth)
    }

    private var typeColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownTypeColumnWidth)
    }

    private var lengthColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownLengthColumnWidth)
    }

    private var arrangementColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownArrangementColumnWidth)
    }

    private var bpmColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownBPMColumnWidth)
    }

    private var ccliColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownCCLIColumnWidth)
    }

    private var sequenceColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownSequenceColumnWidth)
    }

    private var notesColumnWidth: CGFloat {
        CGFloat(effectiveConfig.rundownNotesColumnWidth)
    }

    private var visibleRundownTrailingColumns: [PCORundownColumnWidthKey] {
        var columns: [PCORundownColumnWidthKey] = []
        if showRundownKeyColumn { columns.append(.key) }
        if showRundownTypeColumn { columns.append(.type) }
        if showRundownLengthColumn { columns.append(.length) }
        if showRundownArrangementColumn { columns.append(.arrangement) }
        if showRundownBPMColumn { columns.append(.bpm) }
        if showRundownCCLIColumn { columns.append(.ccli) }
        if showRundownSequenceColumn { columns.append(.sequence) }
        if showRundownNotesColumn { columns.append(.notes) }
        return columns
    }

    private var hasVisibleRundownTrailingColumns: Bool {
        !visibleRundownTrailingColumns.isEmpty
    }

    private var resolvedRundownWidths: [PCORundownColumnWidthKey: CGFloat] {
        guard rundownViewportWidth > 0 else {
            return Dictionary(uniqueKeysWithValues: PCORundownColumnWidthKey.allCases.map { ($0, width(for: $0)) })
        }

        let timeColumnCount = showRundownServiceTimeColumn ? serviceTimeLabelsForColumns.count : 0
        let trailingColumns = visibleRundownTrailingColumns
        let gapCount = 1 + timeColumnCount + (hasVisibleRundownTrailingColumns ? 1 : 0) + trailingColumns.count
        let availableForColumns = max(
            0,
            rundownViewportWidth - orderColumnWidth - CGFloat(gapCount) * rundownColumnGapWidth
        )

        let preferred: [PCORundownColumnWidthKey: CGFloat] = Dictionary(
            uniqueKeysWithValues: PCORundownColumnWidthKey.allCases.map { ($0, width(for: $0)) }
        )

        let minimums = Dictionary(
            uniqueKeysWithValues: PCORundownColumnWidthKey.allCases.map { ($0, $0.minWidth) }
        )
        let hardMinimums = Dictionary(
            uniqueKeysWithValues: PCORundownColumnWidthKey.allCases.map { ($0, $0.hardMinWidth) }
        )

        let preferredTotal =
            CGFloat(timeColumnCount) * preferred[.time, default: 0] +
            preferred[.item, default: 0] +
            trailingColumns.reduce(CGFloat.zero) { $0 + preferred[$1, default: 0] }

        let minimumTotal =
            CGFloat(timeColumnCount) * minimums[.time, default: 0] +
            minimums[.item, default: 0] +
            trailingColumns.reduce(CGFloat.zero) { $0 + minimums[$1, default: 0] }

        func compress(
            from upper: [PCORundownColumnWidthKey: CGFloat],
            to lower: [PCORundownColumnWidthKey: CGFloat],
            totalUpper: CGFloat,
            totalLower: CGFloat,
            available: CGFloat
        ) -> [PCORundownColumnWidthKey: CGFloat] {
            let deficit = totalUpper - available
            let capacities: [PCORundownColumnWidthKey: CGFloat] = Dictionary(
                uniqueKeysWithValues: PCORundownColumnWidthKey.allCases.map { key in
                    let multiplier: CGFloat = key == .time ? CGFloat(timeColumnCount) : 1
                    return (key, max(0, (upper[key, default: 0] - lower[key, default: 0]) * multiplier))
                }
            )
            let totalCapacity = max(totalUpper - totalLower, capacities.values.reduce(CGFloat.zero, +))
            guard totalCapacity > 0 else { return lower }

            var resolved = upper
            for key in PCORundownColumnWidthKey.allCases {
                let capacity = capacities[key, default: 0]
                guard capacity > 0 else { continue }
                let weightedReduction = deficit * (capacity / totalCapacity)
                let perColumnReduction = key == .time
                    ? weightedReduction / max(CGFloat(timeColumnCount), 1)
                    : weightedReduction
                resolved[key] = max(lower[key, default: 0], upper[key, default: 0] - perColumnReduction)
            }
            return resolved
        }

        guard preferredTotal > availableForColumns else { return preferred }
        if minimumTotal < preferredTotal, availableForColumns >= minimumTotal {
            return compress(
                from: preferred,
                to: minimums,
                totalUpper: preferredTotal,
                totalLower: minimumTotal,
                available: availableForColumns
            )
        }

        let hardMinimumTotal =
            CGFloat(timeColumnCount) * hardMinimums[.time, default: 0] +
            hardMinimums[.item, default: 0] +
            trailingColumns.reduce(CGFloat.zero) { $0 + hardMinimums[$1, default: 0] }

        if hardMinimumTotal < minimumTotal, availableForColumns >= hardMinimumTotal {
            return compress(
                from: minimums,
                to: hardMinimums,
                totalUpper: minimumTotal,
                totalLower: hardMinimumTotal,
                available: availableForColumns
            )
        }

        let scale = max(0.35, min(1, availableForColumns / max(hardMinimumTotal, 1)))
        return Dictionary(
            uniqueKeysWithValues: PCORundownColumnWidthKey.allCases.map { key in
                (key, max(18, hardMinimums[key, default: 0] * scale))
            }
        )
    }

    private var displayedTimeColumnWidth: CGFloat { resolvedRundownWidths[.time] ?? timeColumnWidth }
    private var displayedItemColumnWidth: CGFloat { resolvedRundownWidths[.item] ?? itemColumnWidth }
    private var displayedKeyColumnWidth: CGFloat { resolvedRundownWidths[.key] ?? keyColumnWidth }
    private var displayedTypeColumnWidth: CGFloat { resolvedRundownWidths[.type] ?? typeColumnWidth }
    private var displayedLengthColumnWidth: CGFloat { resolvedRundownWidths[.length] ?? lengthColumnWidth }
    private var displayedArrangementColumnWidth: CGFloat { resolvedRundownWidths[.arrangement] ?? arrangementColumnWidth }
    private var displayedBPMColumnWidth: CGFloat { resolvedRundownWidths[.bpm] ?? bpmColumnWidth }
    private var displayedCCLIColumnWidth: CGFloat { resolvedRundownWidths[.ccli] ?? ccliColumnWidth }
    private var displayedSequenceColumnWidth: CGFloat { resolvedRundownWidths[.sequence] ?? sequenceColumnWidth }
    private var displayedNotesColumnWidth: CGFloat { resolvedRundownWidths[.notes] ?? notesColumnWidth }

    private func mutateModuleConfig(_ update: (inout PCOModuleConfig) -> Void) {
        guard let moduleConfigBinding else { return }
        var updated = moduleConfigBinding.wrappedValue
        update(&updated)
        moduleConfigBinding.wrappedValue = updated
    }

    private func width(for column: PCORundownColumnWidthKey) -> CGFloat {
        switch column {
        case .time: return timeColumnWidth
        case .item: return itemColumnWidth
        case .key: return keyColumnWidth
        case .type: return typeColumnWidth
        case .length: return lengthColumnWidth
        case .arrangement: return arrangementColumnWidth
        case .bpm: return bpmColumnWidth
        case .ccli: return ccliColumnWidth
        case .sequence: return sequenceColumnWidth
        case .notes: return notesColumnWidth
        }
    }

    private func setWidth(_ width: CGFloat, for column: PCORundownColumnWidthKey) {
        let clamped = min(max(width, column.minWidth), column.maxWidth)
        mutateModuleConfig { config in
            switch column {
            case .time: config.rundownTimeColumnWidth = Double(clamped)
            case .item: config.rundownItemColumnWidth = Double(clamped)
            case .key: config.rundownKeyColumnWidth = Double(clamped)
            case .type: config.rundownTypeColumnWidth = Double(clamped)
            case .length: config.rundownLengthColumnWidth = Double(clamped)
            case .arrangement: config.rundownArrangementColumnWidth = Double(clamped)
            case .bpm: config.rundownBPMColumnWidth = Double(clamped)
            case .ccli: config.rundownCCLIColumnWidth = Double(clamped)
            case .sequence: config.rundownSequenceColumnWidth = Double(clamped)
            case .notes: config.rundownNotesColumnWidth = Double(clamped)
            }
        }
    }

    private func resetRundownColumnWidths() {
        mutateModuleConfig { config in
            config.rundownTimeColumnWidth = PCORundownColumnWidthKey.time.defaultWidth
            config.rundownItemColumnWidth = PCORundownColumnWidthKey.item.defaultWidth
            config.rundownKeyColumnWidth = PCORundownColumnWidthKey.key.defaultWidth
            config.rundownTypeColumnWidth = PCORundownColumnWidthKey.type.defaultWidth
            config.rundownLengthColumnWidth = PCORundownColumnWidthKey.length.defaultWidth
            config.rundownArrangementColumnWidth = PCORundownColumnWidthKey.arrangement.defaultWidth
            config.rundownBPMColumnWidth = PCORundownColumnWidthKey.bpm.defaultWidth
            config.rundownCCLIColumnWidth = PCORundownColumnWidthKey.ccli.defaultWidth
            config.rundownSequenceColumnWidth = PCORundownColumnWidthKey.sequence.defaultWidth
            config.rundownNotesColumnWidth = PCORundownColumnWidthKey.notes.defaultWidth
        }
    }

    private func rundownResizeGesture(for column: PCORundownColumnWidthKey) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("pcoRundownResizeSpace"))
            .onChanged { value in
                if activeRundownResizeColumn != column {
                    activeRundownResizeColumn = column
                    activeRundownResizeStartWidth = width(for: column)
                    activeRundownResizeStartX = value.startLocation.x
                    onRundownColumnResizeActiveChanged?(true)
                }
                let deltaX = value.location.x - activeRundownResizeStartX
                setWidth(activeRundownResizeStartWidth + deltaX, for: column)
            }
            .onEnded { _ in
                activeRundownResizeColumn = nil
                activeRundownResizeStartX = 0
                onRundownColumnResizeActiveChanged?(false)
            }
    }

    private func beginRundownResize(for column: PCORundownColumnWidthKey) {
        guard activeRundownResizeColumn != column else { return }
        activeRundownResizeColumn = column
        activeRundownResizeStartWidth = width(for: column)
        onRundownColumnResizeActiveChanged?(true)
    }

    private func updateRundownResize(for column: PCORundownColumnWidthKey, deltaX: CGFloat) {
        if activeRundownResizeColumn != column {
            beginRundownResize(for: column)
        }
        setWidth(activeRundownResizeStartWidth + deltaX, for: column)
    }

    private func endRundownResize() {
        activeRundownResizeColumn = nil
        activeRundownResizeStartX = 0
        onRundownColumnResizeActiveChanged?(false)
    }

    private func resizableRundownHeaderCell(
        _ title: String,
        width: CGFloat,
        alignment: Alignment,
        column: PCORundownColumnWidthKey
    ) -> some View {
        Text(title)
            .font(captionFont)
            .foregroundStyle(resolvedSecondaryColor)
            .frame(width: width, alignment: alignment)
            .lineLimit(1)
    }

    @ViewBuilder
    private func rundownHeaderDivider(
        for column: PCORundownColumnWidthKey,
        title: String
    ) -> some View {
        if moduleConfigBinding != nil {
            ZStack {
                Color.clear
                Rectangle()
                    .fill(activeRundownResizeColumn == column ? Color.accentColor : resolvedSecondaryColor.opacity(0.45))
                    .frame(width: 2, height: 14)
            }
            .frame(width: rundownColumnGapWidth)
            .contentShape(Rectangle())
            .help("Drag to resize \(title)")
            #if os(macOS)
            .overlay {
                PCORundownResizeHandle(
                    onDragBegan: {
                        beginRundownResize(for: column)
                    },
                    onDragChanged: { deltaX in
                        updateRundownResize(for: column, deltaX: deltaX)
                    },
                    onDragEnded: {
                        endRundownResize()
                    }
                )
            }
            #else
            .highPriorityGesture(rundownResizeGesture(for: column))
            #endif
        } else {
            Color.clear.frame(width: rundownColumnGapWidth)
        }
    }

    private func rundownColumnGap() -> some View {
        Color.clear.frame(width: rundownColumnGapWidth)
    }

    private var visibleRundownNoteCategories: Set<String>? {
        let categories = (effectiveConfig.rundownVisibleNoteCategories ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return categories.isEmpty ? nil : Set(categories)
    }

    private var effectiveShowsHeader: Bool {
        effectiveConfig.showHeader
    }

    private var liveURLKey: String {
        [
            tab.serviceTypeID ?? "",
            tab.planID ?? "",
            effectiveConfig.liveUseCustomURL ? "custom" : "auto",
            effectiveConfig.liveURLOverride ?? ""
        ].joined(separator: "|")
    }

    private var livePrimaryURL: URL? {
        let raw = (effectiveConfig.liveURLOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if effectiveConfig.liveUseCustomURL, !raw.isEmpty {
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                return URL(string: raw)
            }
            return URL(string: "https://\(raw)")
        }

        guard let serviceTypeID = tab.serviceTypeID, !serviceTypeID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "services.planningcenteronline.com"
        if let planID = tab.planID, !planID.isEmpty {
            components.path = "/live/\(planID)"
        } else {
            components.path = "/service_types/\(serviceTypeID)/plans/after/today/live"
        }
        return components.url
    }

    private var liveFallbackURL: URL? {
        let raw = (effectiveConfig.liveURLOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty else { return nil }
        guard let serviceTypeID = tab.serviceTypeID, !serviceTypeID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "services.planningcenteronline.com"
        components.path = "/service_types/\(serviceTypeID)/plans/after/today/live"
        return components.url
    }

    private var liveURL: URL? {
        if liveFallbackActive, let fallback = liveFallbackURL {
            return fallback
        }
        return livePrimaryURL
    }

    private var effectiveServiceTimeNamesRaw: String {
        if let override = effectiveConfig.serviceTimeNames, !override.isEmpty {
            return override
        }
        return tab.serviceTimeName ?? ""
    }
    /// Ordered list of service-time labels that should appear as columns
    /// in the rundown (e.g., ["9:00 AM", "10:30 AM"]).
    private var serviceTimeLabelsForColumns: [String] {
        cachedServiceTimeLabelsForColumns
    }

    /// Human-readable summary of the selected service times, sorted
    /// chronologically, for use in the header line.
    private var sortedServiceTimesSummaryLabel: String? {
        cachedSortedServiceTimesSummaryLabel
    }

    private var tabSelectedTeamNames: [String] {
        splitSelectedLabels(tab.teamName)
    }

    private var moduleSelectedTeamNames: [String] {
        splitSelectedLabels(effectiveConfig.teamName)
    }

    private var effectiveTeamNames: [String] {
        let tabTeams = tabSelectedTeamNames
        let moduleTeams = moduleSelectedTeamNames

        if !tabTeams.isEmpty && !moduleTeams.isEmpty {
            let allowedTeams = Set(tabTeams)
            return moduleTeams.filter { allowedTeams.contains($0) }
        } else if !moduleTeams.isEmpty {
            return moduleTeams
        } else {
            return tabTeams
        }
    }

    /// Effective team selection for this tile.
    /// Module-level team choices can narrow the tab-level selection, but they
    /// should not expand beyond the teams selected in tab settings.
    private var effectiveTeamName: String? {
        guard !effectiveTeamNames.isEmpty else { return nil }
        return effectiveTeamNames.joined(separator: "||")
    }

    private var currentTabSnapshotKey: String {
        Self.makeTabSnapshotKey(
            serviceTypeID: tab.serviceTypeID,
            planID: tab.planID,
            serviceTimeName: tab.serviceTimeName
        )
    }

    private var tabSnapshotMatchesCurrentSelection: Bool {
        tab.pcoSnapshotKey == currentTabSnapshotKey
    }

    private var tabSnapshotRundownRows: [PCORundownRow] {
        guard tabSnapshotMatchesCurrentSelection else { return [] }
        return tab.pcoCachedRundownRows
    }

    private var tabSnapshotTeamAssignments: [PCOTeamAssignmentRow] {
        guard tabSnapshotMatchesCurrentSelection else { return [] }
        let selectedTeams = splitSelectedLabels(effectiveTeamName)
        guard !selectedTeams.isEmpty else { return [] }
        return tab.pcoCachedTeamAssignments.filter { row in
            guard let teamName = row.teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !teamName.isEmpty else { return false }
            return selectedTeams.contains(teamName)
        }
    }

    private static func sortTeamAssignmentRows(
        _ rows: [PCOTeamAssignmentRow],
        mode: PCOTeamAssignmentSortMode
    ) -> [PCOTeamAssignmentRow] {
        struct DecoratedRow {
            let row: PCOTeamAssignmentRow
            let normalizedTeamName: String
            let normalizedPositionName: String
            let normalizedPersonName: String
            let timeKey: PCOTeamAssignmentTimeSortKey
        }

        func compareTimeKeys(
            _ lhs: PCOTeamAssignmentTimeSortKey,
            _ rhs: PCOTeamAssignmentTimeSortKey
        ) -> ComparisonResult {
            if lhs.firstMinutes != rhs.firstMinutes {
                return lhs.firstMinutes < rhs.firstMinutes ? .orderedAscending : .orderedDescending
            }

            if lhs.labelCount != rhs.labelCount {
                return lhs.labelCount < rhs.labelCount ? .orderedAscending : .orderedDescending
            }

            let joinedCompare = lhs.joined.localizedCaseInsensitiveCompare(rhs.joined)
            if joinedCompare != .orderedSame {
                return joinedCompare
            }

            if lhs.joined.isEmpty && rhs.joined.isEmpty { return .orderedSame }
            if lhs.joined.isEmpty { return .orderedDescending }
            if rhs.joined.isEmpty { return .orderedAscending }
            return .orderedSame
        }

        let decoratedRows = rows.map { row in
            DecoratedRow(
                row: row,
                normalizedTeamName: (row.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                normalizedPositionName: row.positionName.trimmingCharacters(in: .whitespacesAndNewlines),
                normalizedPersonName: row.personName.trimmingCharacters(in: .whitespacesAndNewlines),
                timeKey: row.serviceTimeSortKey
            )
        }

        return decoratedRows.sorted { lhs, rhs in
            let teamCompare = lhs.normalizedTeamName.localizedCaseInsensitiveCompare(rhs.normalizedTeamName)
            guard teamCompare == .orderedSame else {
                return teamCompare == .orderedAscending
            }

            func comparePosition() -> ComparisonResult {
                lhs.normalizedPositionName.localizedCaseInsensitiveCompare(rhs.normalizedPositionName)
            }

            func comparePerson() -> ComparisonResult {
                lhs.normalizedPersonName.localizedCaseInsensitiveCompare(rhs.normalizedPersonName)
            }

            let primaryCompare: ComparisonResult
            let secondaryCompare: ComparisonResult

            switch mode {
            case .positionName:
                primaryCompare = comparePosition()
                secondaryCompare = compareTimeKeys(lhs.timeKey, rhs.timeKey)
            case .personName:
                primaryCompare = comparePerson()
                secondaryCompare = comparePosition()
            case .scheduleTime:
                primaryCompare = compareTimeKeys(lhs.timeKey, rhs.timeKey)
                secondaryCompare = comparePosition()
            }

            if primaryCompare != .orderedSame {
                return primaryCompare == .orderedAscending
            }

            if secondaryCompare != .orderedSame {
                return secondaryCompare == .orderedAscending
            }

            let tertiaryCompare = comparePerson()
            if tertiaryCompare != .orderedSame {
                return tertiaryCompare == .orderedAscending
            }

            return lhs.row.id.uuidString < rhs.row.id.uuidString
        }
        .map(\.row)
    }

    @MainActor
    private func setRundownRowsIfChanged(_ newRows: [PCORundownRow]) {
        if rundownRows != newRows {
            rundownRows = newRows
        }
    }

    @MainActor
    private func setTeamAssignmentsIfChanged(_ newRows: [PCOTeamAssignmentRow]) {
        if teamAssignments != newRows {
            teamAssignments = newRows
        }

        refreshSortedTeamAssignments(using: newRows)
    }

    @MainActor
    private func refreshSortedTeamAssignments(using rows: [PCOTeamAssignmentRow]? = nil) {
        let sourceRows = rows ?? teamAssignments
        let newSortedRows = Self.sortTeamAssignmentRows(sourceRows, mode: effectiveConfig.teamAssignmentSortMode)
        if sortedTeamAssignments != newSortedRows {
            sortedTeamAssignments = newSortedRows
        }
    }

    @MainActor
    private func refreshServiceTimeCaches() {
        let labels = effectiveServiceTimeNamesRaw
            .components(separatedBy: "||")
            .filter { !$0.isEmpty }
        let sorted = sortServiceTimeLabelsChronologically(labels)
        if cachedServiceTimeLabelsForColumns != sorted {
            cachedServiceTimeLabelsForColumns = sorted
        }
        let summary = sorted.isEmpty ? nil : sorted.joined(separator: " & ")
        if cachedSortedServiceTimesSummaryLabel != summary {
            cachedSortedServiceTimesSummaryLabel = summary
        }
    }

    @MainActor
    private func applyTabSnapshotToLocalState(serviceTypeID: String, planID: String) {
        setRundownRowsIfChanged(tabSnapshotRundownRows)
        setTeamAssignmentsIfChanged(tabSnapshotTeamAssignments)
        rundownError = nil
        teamError = nil
        isLoadingRundown = false
        isLoadingTeams = false
        lastLoadedServiceTypeID = serviceTypeID
        lastLoadedPlanID = planID
    }

    @MainActor
    @discardableResult
    private func adoptCurrentTabSnapshotIfAvailable(serviceTypeID: String, planID: String) -> Bool {
        guard tabSnapshotMatchesCurrentSelection else { return false }

        let hasRundownSnapshot = showServiceRundown && !tabSnapshotRundownRows.isEmpty
        let hasTeamSnapshot = showTeamAssignments && !tabSnapshotTeamAssignments.isEmpty
        guard hasRundownSnapshot || hasTeamSnapshot else { return false }

        applyTabSnapshotToLocalState(serviceTypeID: serviceTypeID, planID: planID)
        cacheCurrentState()
        return true
    }

    private var settingsRefreshKey: String {
        [
            tab.serviceTypeID ?? "",
            tab.planID ?? "",
            effectiveServiceTimeNamesRaw,
            effectiveTeamName ?? "",
            showServiceRundown ? "1" : "0",
            showTeamAssignments ? "1" : "0",
            effectiveConfig.showTeamMemberStatus ? "1" : "0",
            effectiveConfig.useStatusStyledAssignmentCards ? "1" : "0",
            effectiveConfig.teamAssignmentSortMode.rawValue,
            effectiveConfig.hideDeclinedAssignments ? "1" : "0",
            "\(effectiveConfig.assignmentTwoColumnThreshold)",
            effectiveConfig.showRundownServiceTimeColumn ? "1" : "0",
            effectiveConfig.showRundownKeyColumn ? "1" : "0",
            effectiveConfig.showRundownTypeColumn ? "1" : "0",
            effectiveConfig.showRundownLengthColumn ? "1" : "0",
            effectiveConfig.showRundownArrangementColumn ? "1" : "0",
            effectiveConfig.showRundownBPMColumn ? "1" : "0",
            effectiveConfig.showRundownCCLIColumn ? "1" : "0",
            effectiveConfig.showRundownSequenceColumn ? "1" : "0",
            effectiveConfig.showRundownNotesColumn ? "1" : "0",
            effectiveConfig.rundownVisibleNoteCategories ?? ""
        ].joined(separator: "|")
    }

    private func restoreCachedStateIfAvailable() -> Bool {
        if let cached = Self.cachedStateByTabId[tab.id],
           cached.key == settingsRefreshKey {
            setRundownRowsIfChanged(cached.rundownRows)
            setTeamAssignmentsIfChanged(cached.teamAssignments)
            rundownError = cached.rundownError
            teamError = cached.teamError
            isLoadingRundown = false
            isLoadingTeams = false
            lastAppliedSettingsKey = cached.key
            return true
        }
        return false
    }

    private func cacheCurrentState() {
        let cached = CachedPCOState(
            key: settingsRefreshKey,
            rundownRows: rundownRows,
            teamAssignments: teamAssignments,
            rundownError: rundownError,
            teamError: teamError
        )
        Self.cachedStateByTabId[tab.id] = cached
        lastAppliedSettingsKey = settingsRefreshKey
    }

    private func shouldRefreshLiveSnapshot(force: Bool = false) -> Bool {
        guard !currentTabSnapshotKey.isEmpty else { return false }
        if force { return true }
        guard let lastRefresh = Self.lastLiveSnapshotRefreshAtByKey[currentTabSnapshotKey] else {
            return true
        }
        return Date().timeIntervalSince(lastRefresh) >= Self.liveModeRefreshInterval
    }

    private func shouldRunStartupWarmRefresh(force: Bool = false) -> Bool {
        guard !currentTabSnapshotKey.isEmpty else { return false }
        if force { return true }
        guard let lastRefresh = Self.lastStartupWarmRefreshAtByKey[currentTabSnapshotKey] else {
            return true
        }
        return Date().timeIntervalSince(lastRefresh) >= Self.startupWarmRefreshInterval
    }

    private func refreshSnapshotInBackgroundAfterCacheRestoreIfNeeded(force: Bool = false) async {
        guard !isLANSnapshotRendering,
              !isPCOConfigOpen,
              dashboardViewMode == "canvas",
              shouldRenderPCODataSections,
              let serviceTypeID = tab.serviceTypeID,
              let planID = tab.planID,
              shouldRunStartupWarmRefresh(force: force) else { return }

        Self.lastStartupWarmRefreshAtByKey[currentTabSnapshotKey] = Date()
        Self.invalidateRuntimeFetchCaches(serviceTypeID: serviceTypeID, planID: planID)
        await refreshTabPCOAssignments()
        await MainActor.run {
            applyTabSnapshotToLocalState(serviceTypeID: serviceTypeID, planID: planID)
            cacheCurrentState()
        }
    }

    private func refreshLiveSnapshotInBackgroundIfNeeded(force: Bool = false) async {
        guard isLiveMode,
              !isLANSnapshotRendering,
              !isPCOConfigOpen,
              dashboardViewMode == "canvas",
              shouldRenderPCODataSections,
              let serviceTypeID = tab.serviceTypeID,
              let planID = tab.planID,
              shouldRefreshLiveSnapshot(force: force) else { return }

        Self.invalidateRuntimeFetchCaches(serviceTypeID: serviceTypeID, planID: planID)
        await refreshTabPCOAssignments()
        await MainActor.run {
            applyTabSnapshotToLocalState(serviceTypeID: serviceTypeID, planID: planID)
            cacheCurrentState()
        }
        Self.lastLiveSnapshotRefreshAtByKey[currentTabSnapshotKey] = Date()
    }

    private var summaryLineOrder: [PCOSummaryField] {
        let stored = effectiveConfig.summaryLineOrder
        var order = stored.isEmpty ? PCOSummaryField.defaultOrder : stored
        for field in PCOSummaryField.allCases where !order.contains(field) {
            order.append(field)
        }
        return order
    }

    private var summaryLineHiddenSet: Set<PCOSummaryField> {
        Set(effectiveConfig.summaryLineHidden)
    }

    private var hasPlanningCenterLogin: Bool {
        isConnected
    }

    private var hasPlanningCenterTabConfiguration: Bool {
        let hasServiceType = !(tab.serviceTypeID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPlan = !(tab.planID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTimes = (tab.serviceTimeName ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
        return hasServiceType && hasPlan && hasTimes
    }

    private var hasCustomLiveURLOverride: Bool {
        guard effectiveConfig.showLiveView, effectiveConfig.liveUseCustomURL else { return false }
        return !(effectiveConfig.liveURLOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var planningCenterModuleGuidanceText: String {
        if !hasPlanningCenterLogin {
            return "Log into Planning Center in App Settings."
        }
        return "Configure service in Tab Settings."
    }

    private var serviceSummary: String {
        let hiddenSet = summaryLineHiddenSet
        if hiddenSet.count >= PCOSummaryField.allCases.count {
            return ""
        }

        guard hasPlanningCenterLogin else {
            return "Log into Planning Center in App Settings"
        }

        guard let type = tab.serviceTypeName, !type.isEmpty else {
            return hasCustomLiveURLOverride ? "" : "Configure service in Tab Settings"
        }

        var parts: [String] = []
        for field in summaryLineOrder {
            guard !hiddenSet.contains(field) else { continue }
            switch field {
            case .serviceType:
                parts.append(type)
            case .planTitle:
                if let plan = tab.planTitle, !plan.isEmpty {
                    parts.append(plan)
                }
            case .planDate:
                if let planDate = tab.planDateLabel, !planDate.isEmpty {
                    parts.append(planDate)
                }
            case .serviceTime:
                if let timeLabel = sortedServiceTimesSummaryLabel {
                    parts.append(timeLabel)
                }
            }
        }

        return parts.joined(separator: " · ")
    }

    /// Team assignments grouped by team name, sorted alphabetically by team name,
    /// with rows within each group sorted by position name.
    private var teamAssignmentsByTeam: [(name: String, rows: [PCOTeamAssignmentRow])] {
        let grouped = Dictionary(grouping: displayedTeamAssignments) { (row: PCOTeamAssignmentRow) in
            (row.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let sortedNames = grouped.keys.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return sortedNames.map { name in
            let rows = (grouped[name] ?? []).sorted {
                $0.positionName.localizedCaseInsensitiveCompare($1.positionName) == .orderedAscending
            }
            return (name: name, rows: rows)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if effectiveShowsHeader {
                Text(applyCapitalization("Planning Center"))
                    .font(headerFont)
                    .foregroundStyle(resolvedPrimaryColor)
            }

            let summary = serviceSummary
            if effectiveConfig.showSummaryLine, !summary.isEmpty {
                Text(summary)
                    .font(summaryFont)
                    .foregroundStyle(resolvedSecondaryColor)
                    .multilineTextAlignment(resolvedTextAlignment)
                    .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
            }

            if showLiveView {
                if let url = liveURL {
                    PCOLiveWebView(url: url, scrollInputEnabled: isLiveMode) { failedURL in
                        if failedURL == livePrimaryURL, liveFallbackActive == false, liveFallbackURL != nil {
                            liveFallbackActive = true
                        }
                    }
                    .id(url.absoluteString)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .layoutPriority(2)
                        .allowsHitTesting(true)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Text(applyCapitalization(
                        hasPlanningCenterLogin
                        ? "Configure a service in Tab Settings or paste a Services Live URL in the module settings."
                        : "Log into Planning Center in App Settings or paste a Services Live URL in the module settings."
                    ))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                }
            } else if showServiceRundown {
                let showLoading = isLoadingRundown && dashboardViewMode == "canvas"
                if !hasPlanningCenterLogin || !hasPlanningCenterTabConfiguration {
                    Text(applyCapitalization(planningCenterModuleGuidanceText))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                } else if showLoading {
                    ProgressView("Loading rundown…")
                        .font(captionFont)
                } else if let err = displayedRundownError {
                    Text(applyCapitalization("Rundown error: \(err)"))
                        .font(captionFont)
                        .foregroundStyle(.red)
                } else if displayedRundownRows.isEmpty {
                    Text(applyCapitalization("No items found for this plan."))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        // Column header row
                        HStack(spacing: 0) {
                            // Placeholder to keep alignment with removed order column
                            Color.clear
                                .frame(width: orderColumnWidth)
                            rundownColumnGap()

                            // Time column headers (one per selected service time)
                            if showRundownServiceTimeColumn, !serviceTimeLabelsForColumns.isEmpty {
                                ForEach(Array(serviceTimeLabelsForColumns.enumerated()), id: \.offset) { _, label in
                                    resizableRundownHeaderCell(
                                        label,
                                        width: displayedTimeColumnWidth,
                                        alignment: .leading,
                                        column: .time
                                    )
                                    rundownHeaderDivider(for: .time, title: label)
                                }
                            }

                            // Title header (fills remaining space)
                            Text(applyCapitalization("Item"))
                                .font(captionFont)
                                .foregroundStyle(resolvedSecondaryColor)
                                .lineLimit(1)
                                .frame(width: displayedItemColumnWidth, alignment: resolvedHorizontalAlignment)
                            if showRundownKeyColumn
                                || showRundownTypeColumn
                                || showRundownLengthColumn
                                || showRundownArrangementColumn
                                || showRundownBPMColumn
                                || showRundownCCLIColumn
                                || showRundownSequenceColumn
                                || showRundownNotesColumn {
                                rundownHeaderDivider(for: .item, title: "Item")
                            }

                            // Key header (only when key column is enabled)
                            if showRundownKeyColumn {
                                resizableRundownHeaderCell("Key", width: displayedKeyColumnWidth, alignment: .center, column: .key)
                                rundownHeaderDivider(for: .key, title: "Key")
                            }

                            // Type header (only when type column is enabled)
                            if showRundownTypeColumn {
                                resizableRundownHeaderCell("Type", width: displayedTypeColumnWidth, alignment: .trailing, column: .type)
                                rundownHeaderDivider(for: .type, title: "Type")
                            }

                            // Length header (only when length column is enabled)
                            if showRundownLengthColumn {
                                resizableRundownHeaderCell("Length", width: displayedLengthColumnWidth, alignment: .trailing, column: .length)
                                rundownHeaderDivider(for: .length, title: "Length")
                            }

                            if showRundownArrangementColumn {
                                resizableRundownHeaderCell("Arrangement", width: displayedArrangementColumnWidth, alignment: .leading, column: .arrangement)
                                rundownHeaderDivider(for: .arrangement, title: "Arrangement")
                            }

                            if showRundownBPMColumn {
                                resizableRundownHeaderCell("BPM", width: displayedBPMColumnWidth, alignment: .trailing, column: .bpm)
                                rundownHeaderDivider(for: .bpm, title: "BPM")
                            }

                            if showRundownCCLIColumn {
                                resizableRundownHeaderCell("CCLI", width: displayedCCLIColumnWidth, alignment: .trailing, column: .ccli)
                                rundownHeaderDivider(for: .ccli, title: "CCLI")
                            }

                            if showRundownSequenceColumn {
                                resizableRundownHeaderCell("Sequence", width: displayedSequenceColumnWidth, alignment: .leading, column: .sequence)
                                rundownHeaderDivider(for: .sequence, title: "Sequence")
                            }

                            if showRundownNotesColumn {
                                resizableRundownHeaderCell("Notes", width: displayedNotesColumnWidth, alignment: .leading, column: .notes)
                                rundownHeaderDivider(for: .notes, title: "Notes")
                            }
                        }
                        .padding(.bottom, 2)
                        .coordinateSpace(.named("pcoRundownResizeSpace"))

                        ForEach(displayedRundownRows) { row in
                            if row.isHeader {
                                // Section header similar to PCO headers.
                                Text(applyCapitalization(row.title))
                                    .font(contentFont)
                                    .foregroundStyle(resolvedPrimaryColor)
                                    .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 6)
                                    .background(resolvedPrimaryColor.opacity(0.18))
                                    .clipShape(.rect(cornerRadius: 6))
                                    .padding(.top, 4)
                            } else {
                                HStack(spacing: 0) {
                                    // Removed order column
                                    Color.clear
                                        .frame(width: orderColumnWidth)
                                    rundownColumnGap()

                                    // Time columns (one per selected service time)
                                    if showRundownServiceTimeColumn, !serviceTimeLabelsForColumns.isEmpty {
                                        ForEach(Array(serviceTimeLabelsForColumns.enumerated()), id: \.offset) { _, label in
                                            Text(row.timeTextsByLabel[label] ?? "")
                                                .font(numericFont)
                                                .foregroundStyle(resolvedSecondaryColor)
                                                .frame(width: displayedTimeColumnWidth, alignment: .leading)
                                                .lineLimit(1)
                                            rundownColumnGap()
                                        }
                                    }

                                    // Title (fills remaining space)
                                    Text(applyCapitalization(row.title))
                                        .font(contentFont)
                                        .foregroundStyle(resolvedPrimaryColor)
                                        .lineLimit(1)
                                        .frame(width: displayedItemColumnWidth, alignment: resolvedHorizontalAlignment)
                                    if showRundownKeyColumn
                                        || showRundownTypeColumn
                                        || showRundownLengthColumn
                                        || showRundownArrangementColumn
                                        || showRundownBPMColumn
                                        || showRundownCCLIColumn
                                        || showRundownSequenceColumn
                                        || showRundownNotesColumn {
                                        rundownColumnGap()
                                    }

                                    // Musical key (if available and enabled).
                                    if showRundownKeyColumn {
                                        Text(row.keyText)
                                            .font(captionFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                            .frame(width: displayedKeyColumnWidth, alignment: .center)
                                            .lineLimit(1)
                                        rundownColumnGap()
                                    }

                                    // Type / length on the right (optional)
                                    if showRundownTypeColumn {
                                        Text(applyCapitalization(row.type))
                                            .font(captionFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                            .frame(width: displayedTypeColumnWidth, alignment: .trailing)
                                            .lineLimit(1)
                                        rundownColumnGap()
                                    }

                                    if showRundownLengthColumn {
                                        Text(row.lengthText)
                                            .font(numericFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                            .frame(width: displayedLengthColumnWidth, alignment: .trailing)
                                            .lineLimit(1)
                                        rundownColumnGap()
                                    }

                                    if showRundownArrangementColumn {
                                        Text(applyCapitalization(row.arrangementText))
                                            .font(captionFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                            .frame(width: displayedArrangementColumnWidth, alignment: .leading)
                                            .lineLimit(1)
                                        rundownColumnGap()
                                    }

                                    if showRundownBPMColumn {
                                        Text(row.bpmText)
                                            .font(numericFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                            .frame(width: displayedBPMColumnWidth, alignment: .trailing)
                                            .lineLimit(1)
                                        rundownColumnGap()
                                    }

                                    if showRundownCCLIColumn {
                                        Text(row.ccliText)
                                            .font(numericFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                            .frame(width: displayedCCLIColumnWidth, alignment: .trailing)
                                            .lineLimit(1)
                                        rundownColumnGap()
                                    }

                                    if showRundownSequenceColumn {
                                        Text(applyCapitalization(row.sequenceText))
                                            .font(captionFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                            .frame(width: displayedSequenceColumnWidth, alignment: .leading)
                                            .lineLimit(1)
                                        rundownColumnGap()
                                    }

                                    if showRundownNotesColumn {
                                        Text(applyCapitalization(row.filteredNotesText(visibleCategories: visibleRundownNoteCategories)))
                                            .font(captionFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                            .frame(width: displayedNotesColumnWidth, alignment: .leading)
                                            .lineLimit(1)
                                        rundownColumnGap()
                                    }
                                }
                            }
                        }
                    }
                    // Keep a little space for the resize handle so it doesn't
                    // sit directly on top of the last line of text.
                    .padding(.bottom, 8)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: RundownViewportWidthPreferenceKey.self, value: geometry.size.width)
                        }
                    )
                    .onPreferenceChange(RundownViewportWidthPreferenceKey.self) { rundownViewportWidth = $0 }
                }
            }

            if showTeamAssignments {
                VStack(alignment: .leading, spacing: 8) {
                    if availableAssignmentTeamTabs.count > 1 {
                        Text(applyCapitalization("Team assignments"))
                            .font(contentFont)
                            .foregroundStyle(resolvedPrimaryColor)
                            .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
                    } else if let rawTeam = effectiveTeamName, !rawTeam.isEmpty {
                        Text(applyCapitalization(teamHeaderLabel(from: rawTeam)))
                            .font(contentFont)
                            .foregroundStyle(resolvedPrimaryColor)
                            .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
                    } else {
                        Text(applyCapitalization("Team assignments"))
                            .font(contentFont)
                            .foregroundStyle(resolvedPrimaryColor)
                            .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
                    }

                    let showLoadingTeams = isLoadingTeams && dashboardViewMode == "canvas"
                    if !hasPlanningCenterLogin || !hasPlanningCenterTabConfiguration {
                        Text(applyCapitalization(planningCenterModuleGuidanceText))
                            .font(captionFont)
                            .foregroundStyle(resolvedSecondaryColor)
                    } else if showLoadingTeams {
                        ProgressView("Loading team…")
                            .font(captionFont)
                    } else if let err = displayedTeamError {
                        Text(applyCapitalization("Team error: \(err)"))
                            .font(captionFont)
                            .foregroundStyle(.red)
                    } else if displayedTeamAssignments.isEmpty {
                        Text(applyCapitalization("No team data loaded."))
                            .font(captionFont)
                            .foregroundStyle(resolvedSecondaryColor)
                    } else {
                        let sortedRows = visibleTeamAssignments
                        let teamCounts = Dictionary(grouping: sortedRows) { row in
                            let teamName = (row.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            return teamName.isEmpty ? "Team" : teamName
                        }.mapValues(\.count)

                        VStack(alignment: .leading, spacing: 8) {
                            if availableAssignmentTeamTabs.count > 1 {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 6) {
                                        ForEach(availableAssignmentTeamTabs, id: \.self) { team in
                                            let isActive = team == activeTeamTabName
                                            Button {
                                                activeTeamTabName = team
                                            } label: {
                                                Text(applyCapitalization(team))
                                                    .font(.system(size: max(10, baseFontSize * 0.44), weight: .semibold, design: .rounded))
                                                    .foregroundStyle(isActive ? .white : resolvedPrimaryColor)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(
                                                        Capsule()
                                                            .fill(isActive ? Color.accentColor.opacity(0.95) : resolvedPrimaryColor.opacity(0.10))
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                // `axes:` defaults to `.vertical`; explicit here since this is a
                                // `ScrollView(.horizontal)`.
                                .scrollIndicators(.hidden, axes: .horizontal)
                            }

                            PCOScaledTeamAssignmentsContent(
                                sortedRows: sortedRows,
                                teamCounts: teamCounts,
                                assignmentTwoColumnThreshold: effectiveConfig.assignmentTwoColumnThreshold,
                                teamExtras: effectiveConfig.teamExtras,
                                showsStatus: effectiveConfig.showTeamMemberStatus,
                                usesSimplifiedStatusStyling: effectiveConfig.useStatusStyledAssignmentCards,
                                capitalizationStyle: tileTextFormatting?.capitalization ?? .normal,
                                baseFontSize: baseFontSize,
                                contentFont: contentFont,
                                captionFont: captionFont,
                                primaryColor: resolvedPrimaryColor,
                                secondaryColor: resolvedSecondaryColor,
                                horizontalAlignment: resolvedHorizontalAlignment
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await MainActor.run {
                refreshServiceTimeCaches()
                refreshSortedTeamAssignments()
            }
        }
        .onChange(of: effectiveServiceTimeNamesRaw) { _, _ in
            refreshServiceTimeCaches()
        }
        .onChange(of: effectiveConfig.teamAssignmentSortMode) { _, _ in
            refreshSortedTeamAssignments()
        }
        // Whenever the key service/plan/time/team inputs change,
        // automatically refresh rundown + team data. This also runs once when
        // the module is first added, since `settingsRefreshKey` will be evaluated then.
        .task(id: settingsRefreshKey) {
            let isGraphMode = dashboardViewMode != "canvas"
            guard !isLANSnapshotRendering, !isPCOConfigOpen, !isGraphMode else { return }
            guard shouldRenderPCODataSections else { return }
            if restoreCachedStateIfAvailable() {
                if let serviceTypeID = tab.serviceTypeID,
                   let planID = tab.planID {
                    await MainActor.run {
                        _ = adoptCurrentTabSnapshotIfAvailable(serviceTypeID: serviceTypeID, planID: planID)
                    }
                }
                await refreshSnapshotInBackgroundAfterCacheRestoreIfNeeded()
                return
            }
            if (!rundownRows.isEmpty || !teamAssignments.isEmpty) {
                // If we already have data for this key (or have never cached yet),
                // avoid a refresh just because the view remounted.
                if lastAppliedSettingsKey == nil || lastAppliedSettingsKey == settingsRefreshKey {
                    lastAppliedSettingsKey = settingsRefreshKey
                    cacheCurrentState()
                    return
                }
            }
            if lastAppliedSettingsKey == settingsRefreshKey,
               (!rundownRows.isEmpty || !teamAssignments.isEmpty) {
                return
            }
            await refreshRundownIfNeeded()
            await refreshTeamsIfNeeded()
            cacheCurrentState()
        }
        .onAppear {
            if !restoreCachedStateIfAvailable(),
               (!rundownRows.isEmpty || !teamAssignments.isEmpty) {
                lastAppliedSettingsKey = settingsRefreshKey
                cacheCurrentState()
            }
        }
        .onChange(of: isLiveMode, initial: false) { _, newValue in
            if newValue {
                guard shouldRenderPCODataSections else { return }
                cacheCurrentState()
                if restoreCachedStateIfAvailable() {
                    Task {
                        await refreshLiveSnapshotInBackgroundIfNeeded(force: true)
                    }
                    return
                }
                Task {
                    await refreshRundownIfNeeded()
                    await refreshTeamsIfNeeded()
                    cacheCurrentState()
                    await refreshLiveSnapshotInBackgroundIfNeeded(force: true)
                }
            } else {
                if restoreCachedStateIfAvailable() {
                    return
                }
            }
        }
        .task(id: "pcoLiveRefresh|\(isLiveMode ? "1" : "0")|\(currentTabSnapshotKey)") {
            guard isLiveMode, !isLANSnapshotRendering, !isPCOConfigOpen else { return }
            guard shouldRenderPCODataSections else { return }
            while isLiveMode && !Task.isCancelled {
                await refreshLiveSnapshotInBackgroundIfNeeded()
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.liveModeRefreshInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
        .onChange(of: liveURLKey, initial: false) { _, _ in
            liveFallbackActive = false
            if let url = liveURL {
                print("[PCO Live] Resolved URL: \(url.absoluteString)")
            } else {
                print("[PCO Live] Resolved URL: <nil>")
            }
        }
        .onChange(of: dashboardViewMode, initial: true) { _, newValue in
            if newValue != "canvas" {
                isLoadingRundown = false
                isLoadingTeams = false
            } else {
                if restoreCachedStateIfAvailable() {
                    return
                }
            }
        }
        .onChange(of: availableAssignmentTeamTabsKey, initial: true) { _, _ in
            let availableTeams = availableAssignmentTeamTabs
            if let activeTeamTabName,
               availableTeams.contains(activeTeamTabName) {
                return
            }
            activeTeamTabName = availableTeams.first
        }
    }
    
    // MARK: - Mapping helpers

    /// Map normalized status strings from PCOClient.TeamMemberSummary into the
    /// internal AssignmentStatus enum used by the tile UI.
    fileprivate static func assignmentStatus(from raw: String?) -> AssignmentStatus {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return .unknown
        }

        switch raw.lowercased() {
        case "confirmed":
            return .confirmed
        case "declined":
            return .declined
        case "pending":
            return .pending
        default:
            return .unknown
        }
    }

    static func buildTeamAssignmentRows(
        members: [PCOClient.TeamMemberSummary],
        itemsAndTimes: PCOClient.ItemsAndTimes,
        client: PCOClient,
        rawSelectedLabels: String?
    ) -> [PCOTeamAssignmentRow] {
        struct AssignmentAggregateKey: Hashable {
            let positionName: String
            let personName: String
            let teamName: String
            let status: AssignmentStatus
        }

        let planTimeLabelMap = Dictionary(
            uniqueKeysWithValues: client.buildPlanTimeLabels(from: itemsAndTimes.planTimes).map { ($0.id, $0.label) }
        )
        let selectedLabels: [String] = {
            let labels = (rawSelectedLabels ?? "")
                .components(separatedBy: "||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !labels.isEmpty { return labels }
            return client.buildPlanTimeLabels(from: itemsAndTimes.planTimes).map(\.label)
        }()
        let selectedPlanTimeIDs: Set<String> = {
            guard !selectedLabels.isEmpty else {
                return Set(client.planTimeIDs(forSelectedLabel: nil, in: itemsAndTimes.planTimes))
            }

            var ids = Set<String>()
            for label in selectedLabels {
                ids.formUnion(client.planTimeIDs(forSelectedLabel: label, in: itemsAndTimes.planTimes))
            }
            return ids
        }()

        var grouped: [AssignmentAggregateKey: [String]] = [:]
        var orderedKeys: [AssignmentAggregateKey] = []

        for member in members {
            guard let rawPositionName = member.positionName,
                  let rawPersonName = member.personName else { continue }

            let positionName = rawPositionName.trimmingCharacters(in: .whitespacesAndNewlines)
            let personName = rawPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !positionName.isEmpty, !personName.isEmpty else { continue }

            let teamName = member.teamName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status = Self.assignmentStatus(from: member.status)
            let key = AssignmentAggregateKey(
                positionName: positionName,
                personName: personName,
                teamName: teamName,
                status: status
            )

            if grouped[key] == nil {
                grouped[key] = []
                orderedKeys.append(key)
            }

            let memberPlanTimeIDs = member.planTimeIDs + (member.planTimeID.map { [$0] } ?? [])
            if !memberPlanTimeIDs.isEmpty {
                for planTimeID in memberPlanTimeIDs {
                    guard selectedPlanTimeIDs.isEmpty || selectedPlanTimeIDs.contains(planTimeID) else { continue }
                    guard let label = planTimeLabelMap[planTimeID],
                          !grouped[key, default: []].contains(label) else { continue }
                    grouped[key, default: []].append(label)
                }
            } else if selectedLabels.count == 1, let label = selectedLabels.first {
                if !grouped[key, default: []].contains(label) {
                    grouped[key, default: []].append(label)
                }
            }
        }

        return orderedKeys.map { key in
            PCOTeamAssignmentRow(
                positionName: key.positionName,
                personName: key.personName,
                teamName: key.teamName.isEmpty ? nil : key.teamName,
                status: key.status,
                serviceTimeLabels: grouped[key] ?? []
            )
        }
    }

    /// Build a human-friendly header label for the team assignments section,
    /// supporting multiple selected teams via "||" separator.
    private func teamHeaderLabel(from rawTeam: String) -> String {
        let teams = rawTeam.components(separatedBy: "||").filter { !$0.isEmpty }
        if teams.count <= 1 {
            return "Team: \(teams.first ?? "")"
        } else {
            return "Teams: \(teams.joined(separator: ", "))"
        }
    }

    /// Row-building and layout for the team-assignments list now live on
    /// `PCOScaledTeamAssignmentsContent` (below), which also owns the
    /// scale-to-fit measurement. Kept here as `fileprivate static` so that
    /// struct can reach them without needing a `PCOTileView` instance.
    fileprivate static func resolvedAssignments(
        roleRule: PCORoleWirelessRule?,
        metadata: PCOAssignmentMetadata?
    ) -> [PCOEquipmentAssignment] {
        let roleAssignments = (roleRule?.assignments ?? []).filter(\.isConfigured)
        let roleTypes = Set(roleAssignments.map(\.assignmentTypeID))
        let manualAssignments = (metadata?.assignments ?? []).filter { assignment in
            assignment.isConfigured && !roleTypes.contains(assignment.assignmentTypeID)
        }
        return sortAssignments(roleAssignments + manualAssignments)
    }

    fileprivate static func sortAssignments(_ assignments: [PCOEquipmentAssignment]) -> [PCOEquipmentAssignment] {
        let preferredOrder: [String] = [PCOAssignmentTypeID.mic, PCOAssignmentTypeID.iem, "notes"]
        let sortIndex = Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { ($0.element, $0.offset) })
        return assignments.sorted { lhs, rhs in
            let lhsOrder = sortIndex[lhs.assignmentTypeID] ?? Int.max
            let rhsOrder = sortIndex[rhs.assignmentTypeID] ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return Self.assignmentDisplayTitle(for: lhs).localizedCaseInsensitiveCompare(
                Self.assignmentDisplayTitle(for: rhs)
            ) == .orderedAscending
        }
    }

    /// Static: pure functions of the assignment only (no tile state), so the
    /// standalone chip view below can call them without needing a reference
    /// back to this instance.
    fileprivate static func assignmentDisplayTitle(for assignment: PCOEquipmentAssignment) -> String {
        switch assignment.assignmentTypeID {
        case PCOAssignmentTypeID.mic:
            return "Mic"
        case PCOAssignmentTypeID.iem:
            return "IEM"
        case "notes":
            return "Notes"
        default:
            if case .rosterColumn(_, let columnTitle, _, _)? = assignment.itemRef,
               let columnTitle,
               !columnTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return columnTitle
            }
            return assignment.assignmentTypeID.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    fileprivate static func assignmentDisplayPayload(for assignment: PCOEquipmentAssignment) -> (text: String, isStale: Bool) {
        switch assignment.itemRef {
        case .wireless(let reference):
            let liveLabel = PCOWirelessOptions.liveDisplay(for: reference)
            let isStale = liveLabel == nil
            if let channel = reference.channelName?.trimmingCharacters(in: .whitespacesAndNewlines), !channel.isEmpty {
                return (isStale ? "\(channel) (offline)" : channel, isStale)
            }
            if let liveLabel {
                return (liveLabel, false)
            }
            if let cosmetic = reference.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !cosmetic.isEmpty {
                return ("\(cosmetic) CH \(reference.channelIndex) (offline)", true)
            }
            return ("CH \(reference.channelIndex) (offline)", true)
        case .rosterColumn(_, let columnTitle, _, let value):
            return (value ?? columnTitle ?? "Roster value", false)
        case .text(let value):
            return (value, false)
        case nil:
            return ("Unassigned", false)
        }
    }

    fileprivate static func assignmentTintColor(for assignment: PCOEquipmentAssignment, isStale: Bool) -> Color {
        if isStale {
            return .orange
        }
        switch assignment.itemRef {
        case .wireless:
            return Color.white.opacity(0.9)
        case .rosterColumn:
            return Color(red: 0.87, green: 0.78, blue: 0.55)
        case .text:
            return assignment.assignmentTypeID == "notes"
                ? Color.secondary.opacity(0.92)
                : Color(red: 0.82, green: 0.72, blue: 0.58)
        case nil:
            return Color.secondary
        }
    }

    fileprivate static func assignmentBackgroundColor(for assignment: PCOEquipmentAssignment, isStale: Bool, primaryColor: Color) -> Color {
        if isStale {
            return Color.orange.opacity(0.12)
        }
        switch assignment.itemRef {
        case .wireless:
            return Color.black.opacity(0.16)
        case .rosterColumn:
            return Color.black.opacity(0.14)
        case .text:
            return assignment.assignmentTypeID == "notes"
                ? primaryColor.opacity(0.06)
                : Color.black.opacity(0.12)
        case nil:
            return primaryColor.opacity(0.05)
        }
    }

    // MARK: - Team assignment row views
    //
    // Each of these is a standalone `View` struct (not a `@ViewBuilder`
    // method) so SwiftUI gets a real diffing boundary per row/chip -- an
    // unaffected row can skip re-evaluating its body when unrelated tile
    // state changes -- and so the runtime generic type of one row's view
    // tree doesn't inline into `PCOTileView`'s own `Body` type. With up to
    // ~70+ rows across several side-by-side Team Assignments modules, the
    // previous all-in-one-method version produced a view tree deep and wide
    // enough to both feel sluggish (every row re-diffed on any state change)
    // and crash Instruments when it tried to demangle the resulting type at
    // the end of a profiling session.

    /// Owns the "shrink the whole team-assignments list to fit the tile"
    /// behavior. This measures its full, unscaled content via a nested
    /// `GeometryReader` + `PreferenceKey` (there's no scroll/clip container
    /// here, so every row -- not just the visible ones -- has to be laid out
    /// to know the natural height), then applies a `scaleEffect` to fit.
    ///
    /// That measurement pass is real layout work across every row, so it
    /// needs to run only when this view's OWN inputs change -- not on every
    /// re-render of the surrounding tile. Before this was extracted, the
    /// measurement `GeometryReader` sat directly in `PCOTileView.body`, so
    /// *any* unrelated state change anywhere in the tile (an `@AppStorage`
    /// read, another module's state, a window resize) re-triggered a full
    /// unscaled layout of every row to re-measure -- confirmed via Time
    /// Profiler: the recorded hangs were ~90% main-thread CPU with no user
    /// code on the sampled stacks at all, just SwiftUI's own layout/graph
    /// propagation (`AG::Graph::propagate_dirty`, display-list construction)
    /// working through the always-fully-built row tree.
    private struct PCOScaledTeamAssignmentsContent: View {
        let sortedRows: [PCOTeamAssignmentRow]
        let teamCounts: [String: Int]
        let assignmentTwoColumnThreshold: Int
        let teamExtras: PCOTeamAssignmentsExtras?
        let showsStatus: Bool
        let usesSimplifiedStatusStyling: Bool
        let capitalizationStyle: TextCapitalizationStyle
        let baseFontSize: CGFloat
        let contentFont: Font
        let captionFont: Font
        let primaryColor: Color
        let secondaryColor: Color
        let horizontalAlignment: Alignment

        @State private var measuredHeight: CGFloat = 0

        private func scaleFactor(availableHeight: CGFloat) -> CGFloat {
            guard availableHeight > 0, measuredHeight > 0 else { return 1 }
            let scale = availableHeight / measuredHeight
            return min(1, max(0.58, scale))
        }

        var body: some View {
            GeometryReader { geometry in
                let scale = scaleFactor(availableHeight: geometry.size.height)
                content
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear
                                .preference(
                                    key: TeamAssignmentsContentHeightPreferenceKey.self,
                                    value: contentGeometry.size.height
                                )
                        }
                    )
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: geometry.size.width / max(scale, 0.001), alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .onPreferenceChange(TeamAssignmentsContentHeightPreferenceKey.self) { newHeight in
                guard newHeight > 0 else { return }
                measuredHeight = newHeight
            }
        }

        @ViewBuilder
        private var content: some View {
            let groupedRows = Dictionary(grouping: sortedRows) { row in
                let teamName = (row.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return teamName.isEmpty ? "Team" : teamName
            }
            let orderedTeamNames = sortedRows.reduce(into: [String]()) { result, row in
                let teamName = (row.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = teamName.isEmpty ? "Team" : teamName
                guard !result.contains(normalized) else { return }
                result.append(normalized)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(orderedTeamNames.enumerated()), id: \.element) { index, teamLabel in
                    let rows = groupedRows[teamLabel] ?? []
                    let useTwoColumns = rows.count >= max(1, assignmentTwoColumnThreshold)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(PCOTileView.applyCapitalization(teamLabel, style: capitalizationStyle))
                            .font(contentFont.weight(.semibold))
                            .foregroundStyle(primaryColor)

                        Text("\(teamCounts[teamLabel] ?? rows.count)")
                            .font(captionFont)
                            .foregroundStyle(secondaryColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(primaryColor.opacity(0.12))
                            .clipShape(Capsule())

                        Rectangle()
                            .fill(primaryColor.opacity(0.12))
                            .frame(maxWidth: .infinity, maxHeight: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: horizontalAlignment)
                    .padding(.top, index == 0 ? 2 : 7)

                    if useTwoColumns {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8, alignment: .top),
                                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8, alignment: .top)
                            ],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(rows) { row in
                                rowCard(row, useTwoColumns: true)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(rows) { row in
                                rowCard(row, useTwoColumns: false)
                            }
                        }
                    }
                }
            }
        }

        private func rowCard(_ row: PCOTeamAssignmentRow, useTwoColumns: Bool) -> PCOAssignmentRowCard {
            let metadata: PCOAssignmentMetadata? = teamExtras.flatMap { $0.byKey[PCOAssignmentMatchKey.key(for: row)] }
            let roleRule: PCORoleWirelessRule? = teamExtras?.roleRulesByPosition[PCORoleMatchKey.key(for: row.positionName)]

            return PCOAssignmentRowCard(
                row: row,
                useTwoColumns: useTwoColumns,
                resolvedAssignments: PCOTileView.resolvedAssignments(roleRule: roleRule, metadata: metadata),
                showsAvatar: teamExtras?.showPersonAvatars ?? false,
                showsStatus: showsStatus,
                usesSimplifiedStatusStyling: usesSimplifiedStatusStyling,
                baseFontSize: baseFontSize,
                contentFont: contentFont,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                capitalizedPositionName: PCOTileView.applyCapitalization(row.positionName, style: capitalizationStyle),
                capitalizedPersonName: PCOTileView.applyCapitalization(row.personName, style: capitalizationStyle)
            )
        }
    }

    private struct PCOAssignmentRowCard: View {
        let row: PCOTeamAssignmentRow
        let useTwoColumns: Bool
        let resolvedAssignments: [PCOEquipmentAssignment]
        let showsAvatar: Bool
        let showsStatus: Bool
        let usesSimplifiedStatusStyling: Bool
        let baseFontSize: CGFloat
        let contentFont: Font
        let primaryColor: Color
        let secondaryColor: Color
        let capitalizedPositionName: String
        let capitalizedPersonName: String

        private var cardFillColor: Color {
            usesSimplifiedStatusStyling
                ? primaryColor.opacity(0.08)
                : row.status.color.opacity(row.status == .unknown ? 0.08 : 0.14)
        }

        private var avatarDiameter: CGFloat { max(42, baseFontSize * 1.95) }
        private var statusLabelFontSize: CGFloat { min(max(9.5, baseFontSize * 0.46), 12.5) }
        private var statusIconFontSize: CGFloat { min(max(11.5, baseFontSize * 0.56), 14.5) }
        private var statusBadgeDiameter: CGFloat { max(26, statusIconFontSize + 12) }

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                if showsAvatar {
                    PCOPersonAvatarView(
                        row: row,
                        diameter: avatarDiameter,
                        fallbackTint: row.status.color.opacity(0.35)
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    PCOPositionBadge(
                        title: capitalizedPositionName,
                        baseFontSize: baseFontSize,
                        primaryColor: primaryColor
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(capitalizedPersonName)
                            .font(contentFont)
                            .foregroundStyle(primaryColor)
                            .lineLimit(1)

                        PCOAssignmentMetadataSection(
                            serviceTimeLabels: row.serviceTimeLabels,
                            assignments: resolvedAssignments,
                            useTwoColumns: useTwoColumns,
                            baseFontSize: baseFontSize,
                            primaryColor: primaryColor,
                            secondaryColor: secondaryColor
                        )
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: useTwoColumns ? 8 : 10) {
                    if !useTwoColumns {
                        PCOAssignmentChipsRow(
                            assignments: resolvedAssignments,
                            useTwoColumns: false,
                            baseFontSize: baseFontSize,
                            primaryColor: primaryColor
                        )
                    }

                    if showsStatus {
                        PCOStatusBadge(
                            status: row.status,
                            usesSimplifiedStatusStyling: usesSimplifiedStatusStyling,
                            labelFontSize: statusLabelFontSize,
                            iconFontSize: statusIconFontSize,
                            badgeDiameter: statusBadgeDiameter
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFillColor)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private struct PCOPositionBadge: View {
        let title: String
        let baseFontSize: CGFloat
        let primaryColor: Color

        var body: some View {
            Text(title)
                .font(.system(size: max(9.5, baseFontSize * 0.4), weight: .bold, design: .rounded))
                .foregroundStyle(primaryColor.opacity(0.9))
                .textCase(.uppercase)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(primaryColor.opacity(0.09))
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
    }

    private struct PCOAssignmentMetadataSection: View {
        let serviceTimeLabels: [String]
        let assignments: [PCOEquipmentAssignment]
        let useTwoColumns: Bool
        let baseFontSize: CGFloat
        let primaryColor: Color
        let secondaryColor: Color

        var body: some View {
            if useTwoColumns {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 6) {
                        PCOServiceTimeChips(labels: serviceTimeLabels, baseFontSize: baseFontSize, primaryColor: primaryColor, secondaryColor: secondaryColor)
                        Spacer(minLength: 0)
                        PCOAssignmentChipsRow(assignments: assignments, useTwoColumns: true, baseFontSize: baseFontSize, primaryColor: primaryColor)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        PCOServiceTimeChips(labels: serviceTimeLabels, baseFontSize: baseFontSize, primaryColor: primaryColor, secondaryColor: secondaryColor)
                        PCOAssignmentChipsRow(assignments: assignments, useTwoColumns: true, baseFontSize: baseFontSize, primaryColor: primaryColor)
                    }
                }
                .frame(minHeight: max(26, baseFontSize * 1.2), alignment: .leading)
            } else {
                PCOServiceTimeChips(labels: serviceTimeLabels, baseFontSize: baseFontSize, primaryColor: primaryColor, secondaryColor: secondaryColor)
                    .frame(minHeight: max(26, baseFontSize * 1.2), alignment: .leading)
            }
        }
    }

    private struct PCOServiceTimeChips: View {
        let labels: [String]
        let baseFontSize: CGFloat
        let primaryColor: Color
        let secondaryColor: Color

        var body: some View {
            if !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: max(8, baseFontSize * 0.34), weight: .medium, design: .rounded))
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(primaryColor.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private struct PCOAssignmentChipsRow: View {
        let assignments: [PCOEquipmentAssignment]
        let useTwoColumns: Bool
        let baseFontSize: CGFloat
        let primaryColor: Color

        var body: some View {
            if !assignments.isEmpty {
                HStack(spacing: useTwoColumns ? 6 : 8) {
                    ForEach(assignments) { assignment in
                        PCOAssignmentChip(assignment: assignment, useTwoColumns: useTwoColumns, baseFontSize: baseFontSize, primaryColor: primaryColor)
                    }
                }
                .layoutPriority(1)
            }
        }
    }

    private struct PCOAssignmentChip: View {
        let assignment: PCOEquipmentAssignment
        let useTwoColumns: Bool
        let baseFontSize: CGFloat
        let primaryColor: Color

        private var label: String { PCOTileView.assignmentDisplayTitle(for: assignment) }
        private var payload: (text: String, isStale: Bool) { PCOTileView.assignmentDisplayPayload(for: assignment) }
        private var tintColor: Color { PCOTileView.assignmentTintColor(for: assignment, isStale: payload.isStale) }

        private var labelFontSize: CGFloat { useTwoColumns ? max(7.5, baseFontSize * 0.28) : max(8.5, baseFontSize * 0.32) }
        private var valueFontSize: CGFloat { useTwoColumns ? max(8.5, baseFontSize * 0.36) : max(10.5, baseFontSize * 0.44) }
        private var chipMinHeight: CGFloat { useTwoColumns ? max(22, baseFontSize * 1.02) : max(30, baseFontSize * 1.24) }
        private var chipHorizontalPadding: CGFloat { useTwoColumns ? 6 : 9 }
        private var chipVerticalPadding: CGFloat { useTwoColumns ? 2 : 4 }
        private var chipMinWidth: CGFloat { useTwoColumns ? 0 : max(98, baseFontSize * 4.1) }

        var body: some View {
            HStack(alignment: .center, spacing: 4) {
                Text(label)
                    .font(.system(size: labelFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(tintColor.opacity(0.92))
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(payload.text)
                    .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(payload.isStale ? .orange.opacity(0.95) : primaryColor.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: chipMinWidth, minHeight: chipMinHeight, alignment: .leading)
            .padding(.horizontal, chipHorizontalPadding)
            .padding(.vertical, chipVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PCOTileView.assignmentBackgroundColor(for: assignment, isStale: payload.isStale, primaryColor: primaryColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tintColor.opacity(payload.isStale ? 0.32 : 0.18), lineWidth: 1)
            )
        }
    }

    private struct PCOStatusBadge: View {
        let status: AssignmentStatus
        let usesSimplifiedStatusStyling: Bool
        let labelFontSize: CGFloat
        let iconFontSize: CGFloat
        let badgeDiameter: CGFloat

        var body: some View {
            if usesSimplifiedStatusStyling {
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                    if !status.label.isEmpty {
                        Text(status.label)
                            .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(status.color.opacity(0.95))
                .padding(.vertical, 2)
                .padding(.horizontal, 7)
                .background(status.label.isEmpty ? status.color.opacity(0.08) : status.color.opacity(0.16))
                .clipShape(Capsule())
            } else {
                Image(systemName: status.symbolName)
                    .font(.system(size: iconFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(status.color.opacity(0.98))
                    .frame(width: badgeDiameter, height: badgeDiameter, alignment: .center)
                    .background(status.color.opacity(status == .unknown ? 0.12 : 0.24))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Team assignments loading

    private func refreshTeamsIfNeeded() async {
        guard showTeamAssignments else {
            await MainActor.run {
                setTeamAssignmentsIfChanged([])
                teamError = nil
                isLoadingTeams = false
            }
            return
        }
        guard !isPCOConfigOpen else { return }
        guard dashboardViewMode == "canvas" else { return }
        guard let serviceTypeID = tab.serviceTypeID,
              let planID = tab.planID
        else {
            await MainActor.run {
                setTeamAssignmentsIfChanged([])
                teamError = nil
                isLoadingTeams = false
                tab.pcoSnapshotKey = nil
                tab.pcoCachedTeamAssignments = []
                // tab.pcoTeamPositionsByTeamName = nil // Removed to prevent crash during tab creation
            }
            return
        }

        await MainActor.run {
            isLoadingTeams = true
            teamError = nil
        }

        if !tabSnapshotMatchesCurrentSelection {
            await refreshTabPCOAssignments()
        }
        await MainActor.run {
            applyTabSnapshotToLocalState(serviceTypeID: serviceTypeID, planID: planID)
        }
    }

    // MARK: - Tab-level PCO assignments refresh

    /// Refreshes tab-level PCO assignment maps so Person tiles can update even
    /// when there is no PCO rundown tile on the dashboard.
    private func refreshTabPCOAssignments() async {
        // If we don't have a service & plan, clear any existing assignments.
        guard let serviceTypeID = tab.serviceTypeID,
              let planID = tab.planID
        else {
            await MainActor.run {
                tab.pcoAllPositionAssignments = [:]
                tab.pcoPositionAssignmentCandidates = nil
                tab.pcoPositionToTeamName = nil
                tab.pcoRundownSnapshotTitles = []
                tab.pcoSnapshotKey = nil
                tab.pcoCachedRundownRows = []
                tab.pcoCachedTeamAssignments = []
                tab.pcoTeamPositionsByTeamName = nil
            }
            return
        }

        let client = makeClient()

        do {
            let context = try await getRuntimePlanContext(
                client: client,
                serviceTypeID: serviceTypeID,
                planID: planID
            )
            let members = context.members

            // Resolve which plan_time IDs are selected for this tab.
            let selectedPlanTimeIDs = selectedPlanTimeIDs(
                client: client,
                itemsAndTimes: context.itemsAndTimes,
                rawSelectedLabels: tab.serviceTimeName
            )

            // Filter members by selected plan times (all teams)
            let timeFiltered = members.filter { m in
                let memberPlanTimeIDs = Set(m.planTimeIDs + (m.planTimeID.map { [$0] } ?? []))
                if !memberPlanTimeIDs.isEmpty,
                   memberPlanTimeIDs.isDisjoint(with: selectedPlanTimeIDs) {
                    return false
                }
                return true
            }

            // Build a position -> team map for the selected plan times.
            var positionToTeam: [String: String] = [:]
            for m in timeFiltered {
                let pos = (m.positionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let team = (m.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pos.isEmpty, !team.isEmpty else { continue }
                if positionToTeam[pos] == nil {
                    positionToTeam[pos] = team
                }
            }

            // Build a position -> person map for ALL teams at the selected times, plus a
            // per-position (and per-team||position) candidate list. Person tiles resolve
            // against the candidate map first (see `resolvedPersonModel`), so it must be
            // refreshed here too -- otherwise a position that's removed from this week's
            // plan keeps resolving against whatever candidates were last cached the last
            // time Tab Settings was opened, showing a stale prior assignment.
            var allMap: [String: String] = [:]
            var assignmentCandidates: [String: [String]] = [:]
            for m in timeFiltered {
                guard let pos = m.positionName, let person = m.personName else { continue }
                let trimmedPos = pos.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedPerson = person.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedPos.isEmpty, !trimmedPerson.isEmpty else { continue }

                if allMap[trimmedPos] == nil {
                    allMap[trimmedPos] = trimmedPerson
                }

                let team = (m.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let keys = team.isEmpty ? [trimmedPos] : ["\(team)||\(trimmedPos)", trimmedPos]
                for key in keys {
                    var names = assignmentCandidates[key] ?? []
                    if !names.contains(where: { $0.compare(trimmedPerson, options: .caseInsensitive) == .orderedSame }) {
                        names.append(trimmedPerson)
                    }
                    assignmentCandidates[key] = names
                }
            }

            // Load the full position catalog for teams at this tab's selected service time(s)
            // so Person tile pickers can include unassigned positions.
            let teamNames = try await buildRuntimeTeamNames(
                client: client,
                serviceTypeID: serviceTypeID,
                itemsAndTimes: context.itemsAndTimes,
                members: members,
                rawSelectedLabels: tab.serviceTimeName
            )

            let positionsByTeamName = try await getRuntimeTeamPositionsByTeamName(
                client: client,
                serviceTypeID: serviceTypeID,
                teamNames: teamNames
            )

            let cachedRundownRows = Self.makeTabSnapshotRundownRows(
                itemsAndTimes: context.itemsAndTimes,
                rawSelectedLabels: tab.serviceTimeName
            )
            let cachedTeamAssignments = Self.buildTeamAssignmentRows(
                members: timeFiltered,
                itemsAndTimes: context.itemsAndTimes,
                client: client,
                rawSelectedLabels: tab.serviceTimeName
            )
            let packedTitles = Self.snapshotTitles(from: cachedRundownRows)

            await MainActor.run {
                tab.pcoAllPositionAssignments = allMap
                tab.pcoPositionAssignmentCandidates = assignmentCandidates.isEmpty ? nil : assignmentCandidates
                tab.pcoPositionToTeamName = positionToTeam.isEmpty ? nil : positionToTeam
                tab.pcoRundownSnapshotTitles = packedTitles
                tab.pcoSnapshotKey = PCOTileView.makeTabSnapshotKey(
                    serviceTypeID: tab.serviceTypeID,
                    planID: tab.planID,
                    serviceTimeName: tab.serviceTimeName
                )
                tab.pcoCachedRundownRows = cachedRundownRows
                tab.pcoCachedTeamAssignments = cachedTeamAssignments
                tab.pcoTeamPositionsByTeamName = positionsByTeamName.isEmpty ? nil : positionsByTeamName
            }
        } catch is CancellationError {
            return
        } catch {
            // On failure, keep existing data (avoid wiping tiles due to a transient error).
            return
        }
    }

    // MARK: - Rundown loading

    private func makeClient() -> PCOClient {
        let tokenStore = KeychainTokenStore()
        let oauth = OAuthService(
            clientID: "740fe16ab8a3025b6920a7290b5f244f4416d5bfb0ea88826521dc10101e8d9d",
            tokenStore: tokenStore
        )
        return PCOClient(oauthService: oauth, tokenStore: tokenStore)
    }

    private static func runtimePlanCacheKey(serviceTypeID: String, planID: String) -> String {
        "\(serviceTypeID)|\(planID)"
    }

    private static func runtimeTeamPositionsCacheKey(serviceTypeID: String, teamNames: [String]) -> String {
        let normalized = teamNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return "\(serviceTypeID)|\(normalized.joined(separator: "||"))"
    }

    private func splitSelectedLabels(_ raw: String?) -> [String] {
        (raw ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func selectedPlanTimeIDs(
        client: PCOClient,
        itemsAndTimes: PCOClient.ItemsAndTimes,
        rawSelectedLabels: String?
    ) -> Set<String> {
        let labels = splitSelectedLabels(rawSelectedLabels)
        guard !labels.isEmpty else {
            return Set(client.planTimeIDs(forSelectedLabel: nil, in: itemsAndTimes.planTimes))
        }

        var ids = Set<String>()
        for label in labels {
            ids.formUnion(client.planTimeIDs(forSelectedLabel: label, in: itemsAndTimes.planTimes))
        }
        return ids
    }

    private func getRuntimeItemsAndTimes(
        client: PCOClient,
        serviceTypeID: String,
        planID: String
    ) async throws -> PCOClient.ItemsAndTimes {
        let cacheKey = Self.runtimePlanCacheKey(serviceTypeID: serviceTypeID, planID: planID)
        let cached = await MainActor.run { () -> (PCOClient.ItemsAndTimes?, Task<PCOClient.ItemsAndTimes, Error>?) in
            if let entry = Self.runtimeItemsAndTimesCache[cacheKey],
               Date().timeIntervalSince(entry.fetchedAt) < Self.runtimeCacheTTL {
                return (entry.value, nil)
            }
            return (nil, Self.runtimeItemsAndTimesTasks[cacheKey])
        }
        if let value = cached.0 {
            return value
        }
        if let task = cached.1 {
            return try await task.value
        }

        let task = Task {
            try await client.fetchItemsAndTimes(serviceTypeID: serviceTypeID, planID: planID)
        }
        await MainActor.run {
            Self.runtimeItemsAndTimesTasks[cacheKey] = task
        }

        do {
            let value = try await task.value
            await MainActor.run {
                Self.runtimeItemsAndTimesCache[cacheKey] = (value, Date())
                Self.runtimeItemsAndTimesTasks[cacheKey] = nil
            }
            return value
        } catch {
            await MainActor.run {
                Self.runtimeItemsAndTimesTasks[cacheKey] = nil
            }
            throw error
        }
    }

    private func getRuntimeTeamMembers(
        client: PCOClient,
        serviceTypeID: String,
        planID: String
    ) async throws -> [PCOClient.TeamMemberSummary] {
        let cacheKey = Self.runtimePlanCacheKey(serviceTypeID: serviceTypeID, planID: planID)
        let cached = await MainActor.run { () -> ([PCOClient.TeamMemberSummary]?, Task<[PCOClient.TeamMemberSummary], Error>?) in
            if let entry = Self.runtimeTeamMembersCache[cacheKey],
               Date().timeIntervalSince(entry.fetchedAt) < Self.runtimeCacheTTL {
                return (entry.value, nil)
            }
            return (nil, Self.runtimeTeamMembersTasks[cacheKey])
        }
        if let value = cached.0 {
            return value
        }
        if let task = cached.1 {
            return try await task.value
        }

        let task = Task {
            try await client.fetchPlanTeamMemberSummaries(serviceTypeID: serviceTypeID, planID: planID)
        }
        await MainActor.run {
            Self.runtimeTeamMembersTasks[cacheKey] = task
        }

        do {
            let value = try await task.value
            await MainActor.run {
                Self.runtimeTeamMembersCache[cacheKey] = (value, Date())
                Self.runtimeTeamMembersTasks[cacheKey] = nil
            }
            return value
        } catch {
            await MainActor.run {
                Self.runtimeTeamMembersTasks[cacheKey] = nil
            }
            throw error
        }
    }

    private func getRuntimeServiceTypeTeamNames(
        client: PCOClient,
        serviceTypeID: String
    ) async throws -> [String] {
        let cached = await MainActor.run { () -> ([String]?, Task<[String], Error>?) in
            if let entry = Self.runtimeServiceTypeTeamsCache[serviceTypeID],
               Date().timeIntervalSince(entry.fetchedAt) < Self.runtimeCacheTTL {
                return (entry.value, nil)
            }
            return (nil, Self.runtimeServiceTypeTeamsTasks[serviceTypeID])
        }
        if let value = cached.0 {
            return value
        }
        if let task = cached.1 {
            return try await task.value
        }

        let task = Task {
            try await client.fetchServiceTypeTeamNames(serviceTypeID: serviceTypeID)
        }
        await MainActor.run {
            Self.runtimeServiceTypeTeamsTasks[serviceTypeID] = task
        }

        do {
            let value = try await task.value
            await MainActor.run {
                Self.runtimeServiceTypeTeamsCache[serviceTypeID] = (value, Date())
                Self.runtimeServiceTypeTeamsTasks[serviceTypeID] = nil
            }
            return value
        } catch {
            await MainActor.run {
                Self.runtimeServiceTypeTeamsTasks[serviceTypeID] = nil
            }
            throw error
        }
    }

    private func getRuntimeTeamPositionsByTeamName(
        client: PCOClient,
        serviceTypeID: String,
        teamNames: [String]
    ) async throws -> [String: [String]] {
        let cacheKey = Self.runtimeTeamPositionsCacheKey(serviceTypeID: serviceTypeID, teamNames: teamNames)
        let cached = await MainActor.run { () -> ([String: [String]]?, Task<[String: [String]], Error>?) in
            if let entry = Self.runtimeTeamPositionsCache[cacheKey],
               Date().timeIntervalSince(entry.fetchedAt) < Self.runtimeCacheTTL {
                return (entry.value, nil)
            }
            return (nil, Self.runtimeTeamPositionsTasks[cacheKey])
        }
        if let value = cached.0 {
            return value
        }
        if let task = cached.1 {
            return try await task.value
        }

        let task = Task {
            try await client.fetchTeamPositionsByTeamName(serviceTypeID: serviceTypeID, teamNames: teamNames)
        }
        await MainActor.run {
            Self.runtimeTeamPositionsTasks[cacheKey] = task
        }

        do {
            let value = try await task.value
            await MainActor.run {
                Self.runtimeTeamPositionsCache[cacheKey] = (value, Date())
                Self.runtimeTeamPositionsTasks[cacheKey] = nil
            }
            return value
        } catch {
            await MainActor.run {
                Self.runtimeTeamPositionsTasks[cacheKey] = nil
            }
            throw error
        }
    }

    private func getRuntimePlanContext(
        client: PCOClient,
        serviceTypeID: String,
        planID: String
    ) async throws -> RuntimePlanContext {
        async let itemsAndTimes = getRuntimeItemsAndTimes(client: client, serviceTypeID: serviceTypeID, planID: planID)
        async let members = getRuntimeTeamMembers(client: client, serviceTypeID: serviceTypeID, planID: planID)
        return try await RuntimePlanContext(itemsAndTimes: itemsAndTimes, members: members)
    }

    private func buildRuntimeTeamNames(
        client: PCOClient,
        serviceTypeID: String,
        itemsAndTimes: PCOClient.ItemsAndTimes,
        members: [PCOClient.TeamMemberSummary],
        rawSelectedLabels: String?
    ) async throws -> [String] {
        let selectedPlanTimeIDs = selectedPlanTimeIDs(
            client: client,
            itemsAndTimes: itemsAndTimes,
            rawSelectedLabels: rawSelectedLabels
        )

        var names = Set<String>()
        for member in members {
            let memberPlanTimeIDs = Set(member.planTimeIDs + (member.planTimeID.map { [$0] } ?? []))
            if !selectedPlanTimeIDs.isEmpty,
               !memberPlanTimeIDs.isEmpty,
               memberPlanTimeIDs.isDisjoint(with: selectedPlanTimeIDs) {
                continue
            }
            if let team = member.teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !team.isEmpty {
                names.insert(team)
            }
        }

        if names.isEmpty {
            for member in members {
                if let team = member.teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !team.isEmpty {
                    names.insert(team)
                }
            }
        }

        let serviceTypeTeams = try await getRuntimeServiceTypeTeamNames(
            client: client,
            serviceTypeID: serviceTypeID
        )
        names.formUnion(serviceTypeTeams)

        return Array(names).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func snapshotFormatLength(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static func rundownIncludedLookup(from included: [PCOIncluded]) -> [String: PCOIncluded] {
        Dictionary(uniqueKeysWithValues: included.map { ("\($0.type)|\($0.id)", $0) })
    }

    private static func rundownDynamicString(_ value: PCODynamic?) -> String? {
        switch value {
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .int(let number):
            return String(number)
        case .double(let number):
            if number.rounded() == number {
                return String(Int(number))
            }
            return String(format: "%.1f", number)
        case .bool(let flag):
            return flag ? "True" : "False"
        case .arr(let values):
            let joined = values.compactMap { rundownDynamicString($0) }.joined(separator: " ")
            return joined.isEmpty ? nil : joined
        default:
            return nil
        }
    }

    private static func rundownDynamicStringArray(_ value: PCODynamic?) -> [String] {
        guard case .arr(let values)? = value else { return [] }
        return values.compactMap { rundownDynamicString($0) }
    }

    private static func rundownItemNotesByItemID(from included: [PCOIncluded]) -> [String: [String: [String]]] {
        var result: [String: [String: [String]]] = [:]

        for includedItem in included where includedItem.type == "ItemNote" {
            guard let itemRelationship = includedItem.relationships?["item"]?.data,
                  case .single(let ref) = itemRelationship else {
                continue
            }

            let content = rundownDynamicString(includedItem.attributes["content"])
            let category = rundownDynamicString(includedItem.attributes["category_name"]) ?? "General"

            guard let content else { continue }
            var existing = result[ref.id] ?? [:]
            var entries = existing[category] ?? []
            entries.append(content)
            existing[category] = entries
            result[ref.id] = existing
        }

        return result
    }

    private static func rundownSequenceText(
        for attributes: ItemAttr,
        arrangement: PCOIncluded?
    ) -> String {
        let customSequence = [
            attributes.custom_arrangement_sequence_short,
            attributes.custom_arrangement_sequence_full,
            attributes.custom_arrangement_sequence
        ]
        .compactMap { sequence -> String? in
            guard let sequence else { return nil }
            let joined = sequence
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }
        .first

        if let customSequence {
            return customSequence
        }

        if let arrangement {
            let arrangementSequence = [
                rundownDynamicStringArray(arrangement.attributes["sequence_short"]),
                rundownDynamicStringArray(arrangement.attributes["sequence_full"]),
                rundownDynamicStringArray(arrangement.attributes["sequence"])
            ]
            .compactMap { sequence -> String? in
                let joined = sequence.joined(separator: " ")
                return joined.isEmpty ? nil : joined
            }
            .first

            if let arrangementSequence {
                return arrangementSequence
            }
        }

        if let itemSequence = attributes.sequence {
            return String(itemSequence)
        }

        return ""
    }

    private static func rundownSupplementalData(
        for item: PCOResource<ItemAttr>,
        includedByKey: [String: PCOIncluded],
        itemNotesByItemID: [String: [String: [String]]]
    ) -> PCORundownSupplementalData {
        let rawType = (item.attributes.item_type ?? "").lowercased()
        if rawType == "header" {
            return .empty
        }

        let arrangement = singleIDStatic(item.relationships?["arrangement"]).flatMap { includedByKey["Arrangement|\($0)"] }
        let song = singleIDStatic(item.relationships?["song"]).flatMap { includedByKey["Song|\($0)"] }

        let arrangementText = arrangement.flatMap {
            rundownDynamicString($0.attributes["name"]) ?? rundownDynamicString($0.attributes["title"])
        } ?? ""

        let bpmText = arrangement.flatMap { rundownDynamicString($0.attributes["bpm"]) } ?? ""
        let ccliText = song.flatMap { rundownDynamicString($0.attributes["ccli_number"]) } ?? ""
        let sequenceText = rundownSequenceText(for: item.attributes, arrangement: arrangement)

        var noteTextsByCategory = itemNotesByItemID[item.id] ?? [:]
        if let description = item.attributes.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            var general = noteTextsByCategory["General"] ?? []
            if !general.contains(description) {
                general.insert(description, at: 0)
            }
            noteTextsByCategory["General"] = general
        }

        let noteParts = noteTextsByCategory.keys.sorted { lhs, rhs in
            if lhs == "General" { return true }
            if rhs == "General" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }.compactMap { category -> String? in
            let values = noteTextsByCategory[category] ?? []
            guard !values.isEmpty else { return nil }
            if category == "General" {
                return values.joined(separator: " • ")
            }
            return "\(category): \(values.joined(separator: " / "))"
        }

        return PCORundownSupplementalData(
            arrangementText: arrangementText,
            bpmText: bpmText,
            ccliText: ccliText,
            sequenceText: sequenceText,
            notesText: noteParts.joined(separator: " • "),
            noteTextsByCategory: noteTextsByCategory
        )
    }

    private static func singleIDStatic(_ rel: PCORelationship?) -> String? {
        guard let relData = rel?.data else { return nil }
        switch relData {
        case .single(let ref):
            return ref.id
        case .multiple(let refs):
            return refs.first?.id
        case .none:
            return nil
        }
    }

    private static func snapshotPlanTimeTuples(from planTimes: PCOCollection<PlanTimeAttr>) -> [(id: String, label: String, startsAt: Date?)] {
        planTimes.data.enumerated().map { index, resource in
            let attr = resource.attributes
            let startsAt = attr.starts_at.flatMap { snapshotParseISOZ($0) }
            let localHM = snapshotToLocalHM(startsAt)
            var parts: [String] = []
            if let name = attr.name, !name.isEmpty { parts.append(name) }
            if let localHM, !localHM.isEmpty { parts.append(localHM) }
            let label = parts.isEmpty ? "Time \(index + 1)" : parts.joined(separator: " — ")
            return (id: resource.id, label: label, startsAt: startsAt)
        }
    }

    static func makeTabSnapshotRundownRows(
        itemsAndTimes: PCOClient.ItemsAndTimes,
        rawSelectedLabels: String?
    ) -> [PCORundownRow] {
        let selectedLabels = (rawSelectedLabels ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let planTimeTuples = snapshotPlanTimeTuples(from: itemsAndTimes.planTimes)
        let activePlanTimes = selectedLabels.isEmpty
            ? planTimeTuples
            : planTimeTuples.filter { selectedLabels.contains($0.label) }
        let activePlanTimeIDs = Set(activePlanTimes.map(\.id))
        let included = itemsAndTimes.items.included ?? []
        let includedByKey = rundownIncludedLookup(from: included)
        let itemNotesByItemID = rundownItemNotesByItemID(from: included)

        var itemTimesByItemID: [String: [String: Date?]] = [:]
        for includedItem in included where includedItem.type == "ItemTime" {
            let planTimeID: String? = {
                guard let rel = includedItem.relationships?["plan_time"]?.data else { return nil }
                switch rel {
                case .single(let ref): return ref.id
                case .multiple(let refs): return refs.first?.id
                case .none: return nil
                }
            }()
            let itemID: String? = {
                guard let rel = includedItem.relationships?["item"]?.data else { return nil }
                switch rel {
                case .single(let ref): return ref.id
                case .multiple(let refs): return refs.first?.id
                case .none: return nil
                }
            }()
            guard let planTimeID, let itemID else { continue }
            if case let .bool(excluded)? = includedItem.attributes["exclude"], excluded {
                continue
            }

            let timeDate = Self.snapshotSortDate(from: includedItem.attributes)
            var existing = itemTimesByItemID[itemID] ?? [:]
            existing[planTimeID] = timeDate
            itemTimesByItemID[itemID] = existing
        }

        var rows: [PCORundownRow] = []
        var displayOrder = 1
        for item in itemsAndTimes.items.data {
            let attr = item.attributes
            let rawType = (attr.item_type ?? "").lowercased()
            let isHeader = rawType == "header"

            if !isHeader && !activePlanTimeIDs.isEmpty {
                let itemPlanTimes = Set(itemTimesByItemID[item.id].map { Array($0.keys) } ?? [])
                if itemPlanTimes.isDisjoint(with: activePlanTimeIDs) {
                    continue
                }
            }

            let title = (attr.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
            let keyText = rawType == "song" ? (attr.key_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let order: Int? = isHeader ? nil : displayOrder
            if !isHeader { displayOrder += 1 }
            let supplemental = rundownSupplementalData(
                for: item,
                includedByKey: includedByKey,
                itemNotesByItemID: itemNotesByItemID
            )

            var timeTextsByLabel: [String: String] = [:]
            if !isHeader {
                let itemPlanTimes = itemTimesByItemID[item.id] ?? [:]
                for tuple in activePlanTimes {
                    guard itemPlanTimes.keys.contains(tuple.id) else { continue }
                    let rawDate = itemPlanTimes[tuple.id] ?? tuple.startsAt
                    timeTextsByLabel[tuple.label] = snapshotToLocalHM(rawDate) ?? tuple.label
                }
            }

            rows.append(
                PCORundownRow(
                    id: item.id,
                    order: order,
                    title: title,
                    keyText: keyText,
                    type: attr.item_type ?? "",
                    lengthText: snapshotFormatLength(seconds: attr.length),
                    arrangementText: supplemental.arrangementText,
                    bpmText: supplemental.bpmText,
                    ccliText: supplemental.ccliText,
                    sequenceText: supplemental.sequenceText,
                    notesText: supplemental.notesText,
                    noteTextsByCategory: supplemental.noteTextsByCategory,
                    timeTextsByLabel: timeTextsByLabel,
                    isHeader: isHeader
                )
            )
        }

        return rows
    }

    static func snapshotTitles(from rows: [PCORundownRow]) -> [String] {
        rows
            .filter { !$0.isHeader }
            .compactMap { row in
                let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let key = row.keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                return key.isEmpty ? title : (title + "\n__KEY__:" + key)
            }
    }

    private static func snapshotParseISOZ(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private static func snapshotToLocalHM(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func snapshotSortDate(from attributes: [String: PCODynamic]) -> Date? {
        if case let .string(raw)? = attributes["live_start_at"],
           let parsed = snapshotParseISOZ(raw) {
            return parsed
        }
        if case let .string(raw)? = attributes["starts_at"],
           let parsed = snapshotParseISOZ(raw) {
            return parsed
        }
        if case let .string(raw)? = attributes["actual_time"],
           let parsed = snapshotParseISOZ(raw) {
            return parsed
        }
        return nil
    }

    private func formatLength(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func buildRundownRows(from items: [FilteredRundownItem]) -> [PCORundownRow] {
        var rows: [PCORundownRow] = []
        var displayOrder = 1
        let included: [PCOIncluded] = []
        let includedByKey = Self.rundownIncludedLookup(from: included)
        let itemNotesByItemID = Self.rundownItemNotesByItemID(from: included)

        for entry in items {
            let item = entry.item
            let attr = item.attributes
            let title = (attr.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
            let rawType = attr.item_type ?? ""
            let isHeader = rawType.lowercased() == "header"
            let type = rawType
            let lengthText = formatLength(seconds: attr.length)

            let keyText: String
            if isHeader {
                keyText = ""
            } else if (attr.item_type ?? "").lowercased() == "song" {
                keyText = (attr.key_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                keyText = ""
            }

            let order: Int?
            if isHeader {
                order = nil          // headers are unnumbered
            } else {
                order = displayOrder // songs/items get sequential numbers
                displayOrder += 1
            }
            let supplemental = Self.rundownSupplementalData(
                for: item,
                includedByKey: includedByKey,
                itemNotesByItemID: itemNotesByItemID
            )

            rows.append(
                PCORundownRow(
                    id: item.id,
                    order: order,
                    title: title,
                    keyText: keyText,
                    type: type,
                    lengthText: lengthText,
                    arrangementText: supplemental.arrangementText,
                    bpmText: supplemental.bpmText,
                    ccliText: supplemental.ccliText,
                    sequenceText: supplemental.sequenceText,
                    notesText: supplemental.notesText,
                    noteTextsByCategory: supplemental.noteTextsByCategory,
                    timeTextsByLabel: isHeader ? [:] : entry.timeTextsByLabel,
                    isHeader: isHeader
                )
            )
        }

        return rows
    }

    private func refreshRundownIfNeeded() async {
        guard showServiceRundown else {
            await MainActor.run {
                setRundownRowsIfChanged([])
                rundownError = nil
                isLoadingRundown = false
            }
            return
        }
        guard !isPCOConfigOpen else { return }
        guard dashboardViewMode == "canvas" else { return }
        // We need at least a service + plan to do anything meaningful.
        guard let serviceTypeID = tab.serviceTypeID,
              let planID = tab.planID
        else {
            await MainActor.run {
                setRundownRowsIfChanged([])
                rundownError = "No service or plan selected."
                isLoadingRundown = false
                lastLoadedServiceTypeID = nil
                lastLoadedPlanID = nil
                tab.pcoSnapshotKey = nil
                tab.pcoRundownSnapshotTitles = []
                tab.pcoCachedRundownRows = []
            }
            return
        }

        await MainActor.run {
            isLoadingRundown = true
            rundownError = nil
        }

        if !tabSnapshotMatchesCurrentSelection {
            await refreshTabPCOAssignments()
        }
        await MainActor.run {
            applyTabSnapshotToLocalState(serviceTypeID: serviceTypeID, planID: planID)
        }
    }

    /// Internal helper for building rundown rows that preserves both the
    /// item resource and a per-service-time map of localized time strings.
    private struct FilteredRundownItem {
        let item: PCOResource<ItemAttr>
        /// Map of service-time label -> localized time string for that service.
        let timeTextsByLabel: [String: String]
    }

    private func filterItemsForSelectedTime(itemsAndTimes: PCOClient.ItemsAndTimes) -> [FilteredRundownItem] {
        let items = itemsAndTimes.items
        let included = items.included ?? []
        let planTimes = itemsAndTimes.planTimes

        // Build plan time labels the same way as in the config view
        var planTimeTuples: [(id: String, label: String, startsAt: Date?)] = []
        for (index, resource) in planTimes.data.enumerated() {
            let attr = resource.attributes

            let starts: Date?
            if let iso = attr.starts_at {
                starts = parseISOZ(iso)
            } else {
                starts = nil
            }

            let localHM = toLocalHM(starts)
            var parts: [String] = []
            if let name = attr.name, !name.isEmpty {
                parts.append(name)
            }
            if let localHM, !localHM.isEmpty {
                parts.append(localHM)
            }

            let label: String
            if parts.isEmpty {
                label = "Time \(index + 1)"
            } else {
                label = parts.joined(separator: " — ")
            }

            planTimeTuples.append((id: resource.id, label: label, startsAt: starts))
        }

        // Determine which labels are selected for this module (tab-level multi-select
        // optionally narrowed by a per-module override via "||").
        let raw = effectiveServiceTimeNamesRaw
        var selectedLabels: [String] = raw.isEmpty
            ? []
            : raw.components(separatedBy: "||").filter { !$0.isEmpty }

        // Normalize label order so we consistently treat service times
        // in chronological order (e.g. "9:00 AM", then "10:30 AM").
        selectedLabels = sortServiceTimeLabelsChronologically(selectedLabels)

        // Map label -> [plan_time IDs]
        var idsForLabel: [String: [String]] = [:]
        for pt in planTimeTuples {
            idsForLabel[pt.label, default: []].append(pt.id)
        }

        // Determine active plan_time IDs
        let selectedIDs: [String] = selectedLabels.isEmpty
            ? planTimeTuples.map { $0.id }
            : selectedLabels.flatMap { idsForLabel[$0] ?? [] }

        // Index items by ID
        let itemByID: [String: PCOResource<ItemAttr>] = Dictionary(
            uniqueKeysWithValues: items.data.map { ($0.id, $0) }
        )

        // Group ItemTimes by plan_time, limited to selectedIDs
        var byTime: [String: [[String: Any]]] = [:]
        for (idx, inc) in included.enumerated() where inc.type == "ItemTime" {
            guard let ptID = singleID(inc.relationships?["plan_time"]),
                  selectedIDs.contains(ptID) else { continue }

            var dict: [String: Any] = ["_idx": idx] // preserve original order as tiebreaker
            for (k, v) in inc.attributes {
                switch v {
                case .string(let s): dict[k] = s
                case .int(let i):    dict[k] = i
                case .bool(let b):   dict[k] = b
                default: break
                }
            }
            if let itemID = singleID(inc.relationships?["item"]) {
                dict["_itemID"] = itemID
            }

            byTime[ptID, default: []].append(dict)
        }

        // Sort each plan_time group chronologically (then by original index)
        for (key, arr) in byTime {
            let sorted = arr.sorted { a, b in
                let aDate = sortDate(from: a) ?? Date.distantFuture
                let bDate = sortDate(from: b) ?? Date.distantFuture
                if aDate != bDate { return aDate < bDate }
                let ai = a["_idx"] as? Int ?? Int.max
                let bi = b["_idx"] as? Int ?? Int.max
                return ai < bi
            }
            byTime[key] = sorted
        }

        // Build a per-item map of service-time label -> time string.
        var timesByItemID: [String: [String: String]] = [:]
        var selectedIDSet = Set<String>()

        for pt in planTimeTuples where selectedIDs.contains(pt.id) {
            let planTimeLabel = pt.label
            for it in byTime[pt.id] ?? [] {
                if (it["exclude"] as? Bool) == true { continue }
                guard let itemID = it["_itemID"] as? String,
                      let item = itemByID[itemID] else { continue }

                // Prefer an item-specific clock time when available, otherwise
                // fall back to the plan time's label (e.g. "9:00 AM").
                let itemTimeDate = sortDate(from: it)
                let itemTimeHM = toLocalHM(itemTimeDate)
                let timeText = itemTimeHM ?? planTimeLabel

                var map = timesByItemID[itemID] ?? [:]
                map[planTimeLabel] = timeText
                timesByItemID[itemID] = map
                selectedIDSet.insert(item.id)
            }
        }

        // If we somehow didn't match anything (e.g. no ItemTime data), fall back to all items
        if selectedIDSet.isEmpty {
            return items.data.map { item in
                FilteredRundownItem(item: item, timeTextsByLabel: [:])
            }
        }

        // Now walk the original items list in order so we can preserve
        // headers that apply to the selected items. We treat headers as
        // section markers and only include a header if at least one
        // selected item appears beneath it.
        var result: [FilteredRundownItem] = []
        var pendingHeader: PCOResource<ItemAttr>? = nil
        var headerHasSelection = false

        for item in items.data {
            let attr = item.attributes
            let isHeader = (attr.item_type ?? "").lowercased() == "header"

            if isHeader {
                // Start a new header group. We don't append it yet; we wait
                // to see if any selected items fall under this header.
                pendingHeader = item
                headerHasSelection = false
                continue
            }

            // Non-header item: only include if it belongs to one of the selected times.
            guard selectedIDSet.contains(item.id) else { continue }

            let timeMap = timesByItemID[item.id] ?? [:]

            // If this is the first selected item under the current header,
            // append the header first, with no time data.
            if let header = pendingHeader, !headerHasSelection {
                result.append(FilteredRundownItem(item: header, timeTextsByLabel: [:]))
                headerHasSelection = true
            }

            result.append(FilteredRundownItem(item: item, timeTextsByLabel: timeMap))
        }

        // If, for some reason, we didn't manage to build any rows with the
        // header-preserving pass, fall back to a simple flat list using the
        // per-item time maps.
        if result.isEmpty {
            return items.data.compactMap { item in
                guard selectedIDSet.contains(item.id) else { return nil }
                let map = timesByItemID[item.id] ?? [:]
                return FilteredRundownItem(item: item, timeTextsByLabel: map)
            }
        }

        return result
    }
    /// Sort a list of service-time labels like "9:00 AM", "10:30 AM" into
    /// chronological order. If parsing fails for any label, we fall back
    /// to a simple string comparison for those entries.
    private func sortServiceTimeLabelsChronologically(_ labels: [String]) -> [String] {
        guard !labels.isEmpty else { return labels }

        // DateFormatter is relatively expensive to create, so build it once.
        struct Formatter {
            static let shared: DateFormatter = {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "h:mm a"
                return df
            }()
        }

        return labels.sorted { lhs, rhs in
            let f = Formatter.shared
            let lDate = f.date(from: lhs)
            let rDate = f.date(from: rhs)

            switch (lDate, rDate) {
            case let (l?, r?):
                return l < r
            case (nil, nil):
                // If neither parses, fall back to lexicographic so the sort is stable.
                return lhs < rhs
            case (nil, _?):
                // Put unparseable labels after valid times.
                return false
            case (_?, nil):
                return true
            }
        }
    }
    // MARK: - ItemTime helpers (mirroring logic from SnapshotBuilder)

    private func parseISOZ(_ iso: String) -> Date? {
        // Prefer the fractional-seconds formatter, then fall back to a simpler one.
        if let d = DateFormatters.iso8601WithFractional.date(from: iso) {
            return d
        }
        return DateFormatters.iso8601Basic.date(from: iso)
    }

    private func toLocalHM(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatters.timeHM
        return formatter.string(from: date)
    }

    /// Shared date/time formatters for this view to avoid recreating
    /// ISO8601DateFormatter / DateFormatter instances on every call.
    private enum DateFormatters {
        static let iso8601WithFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        static let iso8601Basic: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        static let timeHM: DateFormatter = {
            let df = DateFormatter()
            df.dateStyle = .none
            df.timeStyle = .short
            return df
        }()
    }

    private func singleID(_ rel: PCORelationship?) -> String? {
        guard let data = rel?.data else { return nil }
        switch data {
        case .single(let ref):       return ref.id
        case .multiple(let refs):    return refs.first?.id
        case .none:                  return nil
        }
    }

    private func sortDate(from dict: [String: Any]) -> Date? {
        if let s = dict["live_start_at"] as? String, let d = parseISOZ(s) { return d }
        if let s = dict["starts_at"] as? String, let d = parseISOZ(s) { return d }
        return nil
    }
}


/// Configuration UI for per-tab service selection backed by Planning Center.
/// This view reuses PCOClient to fetch service types, plans, and plan times.
struct PCOTabServiceConfigView: View {
    private static let log = Logger(subsystem: "Relay", category: "PCO")
    @Binding var tab: DashboardTab
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dashboard_pco_connected") private var isConnected: Bool = false

    @State private var availableServiceTypes: [PCOResource<ServiceTypeAttr>] = []
    @State private var cachedServiceTypes: [PCOResource<ServiceTypeAttr>] = []
    @State private var cachedServiceTypesFetchedAt: Date?
    @State private var isLoadingServiceTypes: Bool = false
    @State private var serviceTypeFolderNamesByID: [String: String] = [:]
    @State private var availablePlans: [PCOResource<PlanAttr>] = []
    @State private var availableTimes: [String] = []
    @State private var cachedItemsAndTimes: PCOClient.ItemsAndTimes?
    @State private var cachedItemsServiceTypeID: String?
    @State private var cachedItemsPlanID: String?
    @State private var cachedItemsTask: Task<PCOClient.ItemsAndTimes, Error>?
    @State private var cachedItemsTaskServiceTypeID: String?
    @State private var cachedItemsTaskPlanID: String?

    @State private var cachedTeamMembers: [PCOClient.TeamMemberSummary] = []
    @State private var cachedTeamMembersServiceTypeID: String?
    @State private var cachedTeamMembersPlanID: String?

    @State private var cachedPlans: [PCOResource<PlanAttr>] = []
    @State private var cachedPlansServiceTypeID: String?
    @State private var cachedPlansFetchedAt: Date?
    @State private var isLoadingPlans: Bool = false
    @State private var didLoadInitialData: Bool = false
    @State private var lastServiceTypesAttemptAt: Date?
    @State private var isLoadingTimes: Bool = false

    @State private var debouncedPlansTask: Task<Void, Never>?
    @State private var debouncedTimesTask: Task<Void, Never>?
    @State private var debouncedTeamsTask: Task<Void, Never>?
    @State private var suppressChangeHandlers: Bool = false

    @State private var selectedServiceTypeID: String = ""
    @State private var selectedPlanID: String = ""
    @State private var selectedTimeName: String = ""
    @State private var selectedTeamName: String = ""

    @State private var availableTeams: [String] = []
    @State private var isLoadingTeams: Bool = false
    /// Multi-select support for service times (stored as a set of labels).
    @State private var selectedTimeNames: Set<String> = []
    /// Multi-select support for teams (stored as a set of names).
    @State private var selectedTeamNames: Set<String> = []
    @State private var isBusy: Bool = false
    @State private var errorMessage: String?
    @State private var autoAdvanceEnabled: Bool = false
    @State private var autoAdvanceCheckWeekday: Int = 2
    @State private var autoAdvanceCheckTimeMinutes: Int = 15 * 60
    private let clientID = "740fe16ab8a3025b6920a7290b5f244f4416d5bfb0ea88826521dc10101e8d9d"
    private let labelWidth: CGFloat = 110
    private let unfiledServiceTypeName: String = "Other"
    private var selectionDisabled: Bool {
        isBusy || isLoadingServiceTypes || isLoadingPlans || isLoadingTimes || isLoadingTeams
    }
    private var hasPlanningCenterLogin: Bool {
        isConnected
    }

    private var autoAdvanceWeekdays: [(value: Int, name: String)] {
        [
            (1, "Sunday"),
            (2, "Monday"),
            (3, "Tuesday"),
            (4, "Wednesday"),
            (5, "Thursday"),
            (6, "Friday"),
            (7, "Saturday")
        ]
    }

    private var autoAdvanceCheckTimeBinding: Binding<Date> {
        Binding(
            get: { dateForAutoAdvanceTime(minutes: autoAdvanceCheckTimeMinutes) },
            set: { autoAdvanceCheckTimeMinutes = minutesForAutoAdvanceTime($0) }
        )
    }

    private func dateForAutoAdvanceTime(minutes: Int) -> Date {
        let clamped = clampedAutoAdvanceTimeMinutes(minutes)
        let components = DateComponents(hour: clamped / 60, minute: clamped % 60)
        return Calendar.current.date(from: components) ?? .now
    }

    private func minutesForAutoAdvanceTime(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return clampedAutoAdvanceTimeMinutes(((components.hour ?? 0) * 60) + (components.minute ?? 0))
    }

    private func clampedAutoAdvanceWeekday(_ weekday: Int) -> Int {
        (1...7).contains(weekday) ? weekday : 2
    }

    private func clampedAutoAdvanceTimeMinutes(_ minutes: Int) -> Int {
        max(0, min(minutes, (24 * 60) - 1))
    }

    private struct ServiceTypeGroup: Identifiable {
        let id: String
        let title: String
        let types: [PCOResource<ServiceTypeAttr>]
    }

    private struct ConfigDraft {
        let serviceTypeID: String
        let planID: String
        let selectedTimeNames: Set<String>
        let selectedTeamNames: Set<String>
        let autoAdvanceEnabled: Bool
        let autoAdvanceCheckWeekday: Int
        let autoAdvanceCheckTimeMinutes: Int
    }

    private static var draftCache: [UUID: ConfigDraft] = [:]
    private static var serviceTypesCache: (
        types: [PCOResource<ServiceTypeAttr>],
        foldersByID: [String: String],
        fetchedAt: Date
    )?
    private static var plansCache: [String: (plans: [PCOResource<PlanAttr>], fetchedAt: Date)] = [:]
    private static var itemsAndTimesCache: [String: PCOClient.ItemsAndTimes] = [:]
    private static var teamMembersCache: [String: [PCOClient.TeamMemberSummary]] = [:]

    private func loadDraft(for tabID: UUID) -> ConfigDraft? {
        Self.draftCache[tabID]
    }

    private func saveDraft(for tabID: UUID) {
        Self.draftCache[tabID] = ConfigDraft(
            serviceTypeID: selectedServiceTypeID,
            planID: selectedPlanID,
            selectedTimeNames: selectedTimeNames,
            selectedTeamNames: selectedTeamNames,
            autoAdvanceEnabled: autoAdvanceEnabled,
            autoAdvanceCheckWeekday: autoAdvanceCheckWeekday,
            autoAdvanceCheckTimeMinutes: autoAdvanceCheckTimeMinutes
        )
    }

    private func clearDraft(for tabID: UUID) {
        Self.draftCache.removeValue(forKey: tabID)
    }

    private func applySelectionsToTab() {
        // availableServiceTypes/availablePlans/availableTimes come from a live PCO fetch that
        // requires this device to be authenticated. A synced/joined tab arrives with real
        // selections already set (e.g. from the host), but on a device that isn't logged into
        // Planning Center (or hasn't finished loading these lists yet) those lists are empty —
        // that must not be read as "the user cleared the selection." Only treat it as an
        // explicit clear when the corresponding @State was actively emptied (e.g. "Select…").
        if let serviceType = availableServiceTypes.first(where: { $0.id == selectedServiceTypeID }) {
            tab.serviceTypeID = serviceType.id
            tab.serviceTypeName = serviceType.attributes.name
        } else if selectedServiceTypeID.isEmpty {
            tab.serviceTypeID = nil
            tab.serviceTypeName = nil
        }

        if let plan = availablePlans.first(where: { $0.id == selectedPlanID }) {
            tab.planID = plan.id
            tab.planTitle = plan.attributes.title
            tab.planDateLabel = PCOTileView.formatPlanDateLabel(for: plan)
        } else if selectedPlanID.isEmpty {
            tab.planID = nil
            tab.planTitle = nil
            tab.planDateLabel = nil
        }

        if selectedTimeNames.isEmpty {
            tab.serviceTimeName = nil
        } else if !availableTimes.isEmpty {
            let orderedTimes = availableTimes.filter { selectedTimeNames.contains($0) }
            tab.serviceTimeName = orderedTimes.isEmpty ? nil : orderedTimes.joined(separator: "||")
        }

        let joinedTeams = selectedTeamNames.isEmpty
            ? nil
            : selectedTeamNames.sorted().joined(separator: "||")
        tab.teamName = joinedTeams
        tab.pcoAutoAdvanceEnabled = autoAdvanceEnabled
        tab.pcoAutoAdvanceCheckWeekday = clampedAutoAdvanceWeekday(autoAdvanceCheckWeekday)
        tab.pcoAutoAdvanceCheckTimeMinutes = clampedAutoAdvanceTimeMinutes(autoAdvanceCheckTimeMinutes)
    }

    private func invalidateCurrentSelectionDataCaches() {
        let serviceTypeID = selectedServiceTypeID
        let planID = selectedPlanID

        if !serviceTypeID.isEmpty, !planID.isEmpty {
            let cacheKey = "\(serviceTypeID)|\(planID)"
            Self.itemsAndTimesCache[cacheKey] = nil
            Self.teamMembersCache[cacheKey] = nil
            PCOTileView.invalidateCachedData(serviceTypeID: serviceTypeID, planID: planID, tabID: tab.id)
        }

        cachedItemsAndTimes = nil
        cachedItemsServiceTypeID = nil
        cachedItemsPlanID = nil
        cachedItemsTask?.cancel()
        cachedItemsTask = nil
        cachedItemsTaskServiceTypeID = nil
        cachedItemsTaskPlanID = nil
        cachedTeamMembers = []
        cachedTeamMembersServiceTypeID = nil
        cachedTeamMembersPlanID = nil
        tab.pcoSnapshotKey = nil
        tab.pcoCachedRundownRows = []
        tab.pcoCachedTeamAssignments = []
        tab.pcoRundownSnapshotTitles = []
    }

    private func refreshCurrentTabSelection() async {
        guard hasPlanningCenterLogin,
              !selectedServiceTypeID.isEmpty,
              !selectedPlanID.isEmpty,
              !selectedTimeNames.isEmpty else { return }

        await MainActor.run {
            errorMessage = nil
            isBusy = true
            applySelectionsToTab()
            invalidateCurrentSelectionDataCaches()
        }

        await refreshTabPCOAssignments()

        await MainActor.run {
            isBusy = false
        }
    }

    private var serviceTypeGroups: [ServiceTypeGroup] {
        var grouped: [String: [PCOResource<ServiceTypeAttr>]] = [:]
        for type in availableServiceTypes {
            let folderName = serviceTypeFolderNamesByID[type.id] ?? unfiledServiceTypeName
            grouped[folderName, default: []].append(type)
        }
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return sortedKeys.map { key in
            let types = (grouped[key] ?? []).sorted { lhs, rhs in
                lhs.attributes.name.localizedCaseInsensitiveCompare(rhs.attributes.name) == .orderedAscending
            }
            return ServiceTypeGroup(id: key, title: key, types: types)
        }
    }

    private var footerButtons: some View {
        HStack {
            Spacer()
            Button("Refresh Data") {
                Task {
                    await refreshCurrentTabSelection()
                }
            }
            .disabled(
                isBusy ||
                selectedServiceTypeID.isEmpty ||
                selectedPlanID.isEmpty ||
                selectedTimeNames.isEmpty
            )
            Button("Cancel") {
                dismiss()
            }
            Button("Save") {
                applySelectionsToTab()
                clearDraft(for: tab.id)
                // After saving, refresh the tab-level PCO assignments so that
                // person tiles can update even if there is no PCO rundown tile.
                Task {
                    await refreshTabPCOAssignments()
                }

                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                selectedServiceTypeID.isEmpty ||
                selectedPlanID.isEmpty ||
                selectedTimeNames.isEmpty
            )
        }
    }

    private var loginRequiredState: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Planning Center Login Required", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.headline)

                Text("Log into Planning Center in app settings before configuring tab-specific Planning Center selections.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            )
    }

    private func selectionChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(selectionDisabled)
    }

    private func ensureSelectedPlanVisible(
        _ plans: [PCOResource<PlanAttr>]
    ) -> [PCOResource<PlanAttr>] {
        guard !selectedPlanID.isEmpty else { return plans }
        if plans.contains(where: { $0.id == selectedPlanID }) {
            return plans
        }
        let placeholderTitle = (tab.planTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Saved plan"
        let placeholder = PCOResource(
            id: selectedPlanID,
            attributes: PlanAttr(title: placeholderTitle, sort_date: nil),
            relationships: nil
        )
        return [placeholder] + plans
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Planning Center")
                            .font(.title3.bold())

                        Text("These Planning Center values apply only to this dashboard tab. Other tiles on this tab can read the selected service type, plan, and time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ProgressView("Loading from Planning Center…")
                        .progressViewStyle(.linear)
                        .opacity(isBusy ? 1 : 0)
                        .frame(height: 18)
                    if hasPlanningCenterLogin {
                        sectionHeader("Service")
                        sectionCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Service type")
                                        .frame(width: labelWidth, alignment: .trailing)

                                    HStack(spacing: 8) {
                                        Picker("", selection: $selectedServiceTypeID) {
                                            Text("Select…").tag("")
                                            ForEach(serviceTypeGroups) { group in
                                                Section(group.title) {
                                                    ForEach(group.types) { type in
                                                        Text(type.attributes.name)
                                                            .tag(type.id)
                                                    }
                                                }
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .disabled(isLoadingServiceTypes)

                                        if isLoadingServiceTypes {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                HStack {
                                    Text("Plan")
                                        .frame(width: labelWidth, alignment: .trailing)

                                    HStack(spacing: 8) {
                                        Picker("", selection: $selectedPlanID) {
                                            Text("Select…").tag("")
                                            ForEach(availablePlans) { plan in
                                                Text(Self.displayPlanTitle(for: plan))
                                                    .tag(plan.id)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .disabled(
                                            selectedServiceTypeID.isEmpty || availablePlans.isEmpty || isLoadingPlans
                                        )

                                        if isLoadingPlans {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        sectionHeader("Filters")
                        sectionCard {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Service times")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    if isLoadingTimes {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Loading service times…")
                                                .foregroundStyle(.secondary)
                                                .font(.footnote)
                                        }
                                        .frame(minHeight: 22, alignment: .leading)
                                    } else if selectedPlanID.isEmpty || availableTimes.isEmpty {
                                        Text("Select a plan to load service times")
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                            .frame(minHeight: 22, alignment: .leading)
                                    } else {
                                        ScrollView {
                                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                                                ForEach(availableTimes, id: \.self) { time in
                                                    selectionChip(
                                                        title: time,
                                                        isSelected: selectedTimeNames.contains(time)
                                                    ) {
                                                        var set = selectedTimeNames
                                                        if set.contains(time) {
                                                            set.remove(time)
                                                        } else {
                                                            set.insert(time)
                                                        }
                                                        selectedTimeNames = set
                                                        selectedTimeName = selectedTimeNames.first ?? ""
                                                    }
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(maxHeight: 200)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Teams")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    if isLoadingTeams {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Loading teams…")
                                                .foregroundStyle(.secondary)
                                                .font(.footnote)
                                        }
                                        .frame(minHeight: 22, alignment: .leading)
                                    } else if availableTeams.isEmpty {
                                        Text("No teams available for this selection")
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                            .frame(minHeight: 22, alignment: .leading)
                                    } else {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                                            ForEach(availableTeams, id: \.self) { team in
                                                selectionChip(
                                                    title: team,
                                                    isSelected: selectedTeamNames.contains(team)
                                                ) {
                                                    var set = selectedTeamNames
                                                    if set.contains(team) {
                                                        set.remove(team)
                                                    } else {
                                                        set.insert(team)
                                                    }
                                                    selectedTeamNames = set
                                                    selectedTeamName = selectedTeamNames.first ?? ""
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .disabled(selectionDisabled)

                        sectionHeader("Auto refresh")
                        sectionCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Auto-advance to next plan", isOn: $autoAdvanceEnabled)

                                if autoAdvanceEnabled {
                                    HStack {
                                        Text("Check")
                                            .frame(width: labelWidth, alignment: .trailing)

                                        Picker("", selection: $autoAdvanceCheckWeekday) {
                                            ForEach(autoAdvanceWeekdays, id: \.value) { day in
                                                Text(day.name).tag(day.value)
                                            }
                                        }
                                        .pickerStyle(.menu)

                                        DatePicker(
                                            "",
                                            selection: autoAdvanceCheckTimeBinding,
                                            displayedComponents: .hourAndMinute
                                        )
                                        .labelsHidden()

                                        Spacer(minLength: 0)
                                    }

                                    Text("Relay checks Planning Center once each week at this day and time. If the selected service is behind that checkpoint, Relay switches to the next upcoming plan.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } else {
                        loginRequiredState
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
#if os(iOS)
                // Extra space so the last toggles can scroll above the bottom bar on iPad.
                .padding(.bottom, 80)
#endif
            }
#if os(iOS)
            .scrollDismissesKeyboard(.immediately)
#endif
#if os(macOS)
            footerButtons
                .padding(.top, 8)
#endif
        }
#if os(iOS)
        .safeAreaInset(edge: .bottom) {
            footerButtons
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
#endif
#if os(macOS)
        .frame(minWidth: 520, minHeight: 320)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
        .task {
            if didLoadInitialData {
                return
            }
            didLoadInitialData = true
            guard hasPlanningCenterLogin else {
                return
            }
            print("[PCO] Config: initial load")
            PCOTabServiceConfigView.log.info("Config: initial load")
            await loadInitialData()
        }
        .onDisappear {
            debouncedPlansTask?.cancel()
            debouncedTimesTask?.cancel()
            debouncedTeamsTask?.cancel()
        }
        .onChange(of: selectedServiceTypeID, initial: false) { oldValue, newValue in
            guard !suppressChangeHandlers, oldValue != newValue else { return }
            selectedPlanID = ""
            selectedTimeNames = []
            selectedTimeName = ""
            selectedTeamNames = []
            selectedTeamName = ""
            availableTeams = []
            saveDraft(for: tab.id)
            scheduleLoadPlans()
        }
        .onChange(of: selectedPlanID, initial: false) { oldValue, newValue in
            guard !suppressChangeHandlers, oldValue != newValue else { return }
            saveDraft(for: tab.id)
            scheduleLoadTimes()
            scheduleLoadTeams()
        }
        .onChange(of: selectedTimeNames, initial: false) { oldValue, newValue in
            guard !suppressChangeHandlers, oldValue != newValue else { return }
            saveDraft(for: tab.id)
            updateTeamsFromCache()
        }
        .onChange(of: selectedTeamNames, initial: false) { oldValue, newValue in
            guard !suppressChangeHandlers, oldValue != newValue else { return }
            saveDraft(for: tab.id)
        }
        .onChange(of: autoAdvanceEnabled, initial: false) { oldValue, newValue in
            guard !suppressChangeHandlers, oldValue != newValue else { return }
            saveDraft(for: tab.id)
        }
        .onChange(of: autoAdvanceCheckWeekday, initial: false) { oldValue, newValue in
            guard !suppressChangeHandlers, oldValue != newValue else { return }
            autoAdvanceCheckWeekday = clampedAutoAdvanceWeekday(newValue)
            saveDraft(for: tab.id)
        }
        .onChange(of: autoAdvanceCheckTimeMinutes, initial: false) { oldValue, newValue in
            guard !suppressChangeHandlers, oldValue != newValue else { return }
            autoAdvanceCheckTimeMinutes = clampedAutoAdvanceTimeMinutes(newValue)
            saveDraft(for: tab.id)
        }
    }
    // MARK: - Tab-level PCO assignments refresh

    /// Refreshes `tab.pcoAllPositionAssignments` for the current tab.
    /// This lets person tiles that use PCO positions update even when
    /// there is no PCO rundown tile on the dashboard.
    private func refreshTabPCOAssignments() async {
        // If we don't have a service & plan, clear any existing assignments.
        guard let serviceTypeID = tab.serviceTypeID,
              let planID = tab.planID
        else {
            await MainActor.run {
                tab.pcoAllPositionAssignments = [:]
                tab.pcoPositionToTeamName = nil
                tab.pcoRundownSnapshotTitles = []
                tab.pcoSnapshotKey = nil
                tab.pcoCachedRundownRows = []
                tab.pcoCachedTeamAssignments = []
                tab.pcoTeamPositionsByTeamName = nil
            }
            return
        }

        let client = makeClient()

        do {
            // Fetch team member summaries for this plan
            let members = try await client.fetchPlanTeamMemberSummaries(
                serviceTypeID: serviceTypeID,
                planID: planID
            )

            // Fetch items/times so we can filter members by selected service times
            let itemsAndTimes = try await client.fetchItemsAndTimes(
                serviceTypeID: serviceTypeID,
                planID: planID
            )

            // Also build a tab-level rundown snapshot title list for Graph mode.
            // This is used by the node graph even if there is no PCO rundown tile on the canvas.
            // Pack key metadata as: "Title\n__KEY__:A" so the Console node can optionally append the key.

            let items = itemsAndTimes.items
            let included = items.included ?? []

            // Resolve which plan_time IDs are selected for this tab.
            let selectedPlanTimeIDs = Set(
                client.planTimeIDs(
                    forSelectedLabel: tab.serviceTimeName,
                    in: itemsAndTimes.planTimes
                )
            )

            // Load the full position catalog for teams at this tab's selected service time(s)
            // so Person tile pickers can include unassigned positions.
            let timeLabels = (tab.serviceTimeName ?? "")
                .components(separatedBy: "||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var teamNameSet = Set<String>()
            if timeLabels.isEmpty {
                let names = try await client.fetchTeamNamesForServiceTime(
                    serviceTypeID: serviceTypeID,
                    planID: planID,
                    serviceTimeLabel: nil
                )
                teamNameSet.formUnion(names)
            } else {
                for label in timeLabels {
                    let names = try await client.fetchTeamNamesForServiceTime(
                        serviceTypeID: serviceTypeID,
                        planID: planID,
                        serviceTimeLabel: label
                    )
                    teamNameSet.formUnion(names)
                }
            }

            let teamNames = Array(teamNameSet).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            let positionsByTeamName = try await client.fetchTeamPositionsByTeamName(
                serviceTypeID: serviceTypeID,
                teamNames: teamNames
            )

            let cachedRundownRows = PCOTileView.makeTabSnapshotRundownRows(
                itemsAndTimes: itemsAndTimes,
                rawSelectedLabels: tab.serviceTimeName
            )

            // Build a set of item IDs that occur in the selected plan times.
            var selectedItemIDs = Set<String>()
            if !selectedPlanTimeIDs.isEmpty {
                for inc in included where inc.type == "ItemTime" {
                    // Find plan_time relationship
                    let ptID: String? = {
                        guard let rel = inc.relationships?["plan_time"]?.data else { return nil }
                        switch rel {
                        case .single(let ref): return ref.id
                        case .multiple(let refs): return refs.first?.id
                        case .none: return nil
                        }
                    }()
                    guard let ptID, selectedPlanTimeIDs.contains(ptID) else { continue }

                    // Find item relationship
                    let itemID: String? = {
                        guard let rel = inc.relationships?["item"]?.data else { return nil }
                        switch rel {
                        case .single(let ref): return ref.id
                        case .multiple(let refs): return refs.first?.id
                        case .none: return nil
                        }
                    }()
                    if let itemID {
                        selectedItemIDs.insert(itemID)
                    }
                }
            }

            // If we couldn't resolve any selected items, fall back to all items.
            let useAllItems = selectedItemIDs.isEmpty

            let includedByKey: [String: PCOIncluded] = Dictionary(
                uniqueKeysWithValues: included.map { ("\($0.type)|\($0.id)", $0) }
            )

            func includedString(type: String, id: String?, keys: [String]) -> String? {
                guard let id, let included = includedByKey["\(type)|\(id)"] else { return nil }
                for key in keys {
                    if case let .string(value)? = included.attributes[key] {
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                    }
                }
                return nil
            }

            func relationshipID(for key: String, in item: PCOResource<ItemAttr>) -> String? {
                guard let relationship = item.relationships?[key]?.data else { return nil }
                switch relationship {
                case .single(let ref):
                    return ref.id
                case .multiple(let refs):
                    return refs.first?.id
                case .none:
                    return nil
                }
            }

            let packedTitles: [String] = items.data.compactMap { item in
                let attr = item.attributes
                let rawType = (attr.item_type ?? "").lowercased()
                if rawType == "header" { return nil }

                if !useAllItems, !selectedItemIDs.contains(item.id) { return nil }

                let title = (attr.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }

                let keyText: String = {
                    if rawType == "song" {
                        return (attr.key_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return ""
                }()

                let arrangementTitle = includedString(
                    type: "Arrangement",
                    id: relationshipID(for: "arrangement", in: item),
                    keys: ["name", "title"]
                )
                let songTitle = includedString(
                    type: "Song",
                    id: relationshipID(for: "song", in: item),
                    keys: ["title", "name"]
                )
                let itemNotes = includedString(
                    type: "Item",
                    id: item.id,
                    keys: ["description", "notes"]
                )

                return VistaPCORundownPayloadCodec.encode(
                    VistaPCORundownItem(
                        title: title,
                        itemType: attr.item_type,
                        keyName: keyText.isEmpty ? nil : keyText,
                        arrangementTitle: arrangementTitle,
                        songTitle: songTitle,
                        itemNotes: itemNotes,
                        serviceTypeName: tab.serviceTypeName,
                        planTitle: tab.planTitle,
                        serviceDateLabel: tab.planDateLabel,
                        serviceTimeName: tab.serviceTimeName,
                        timecode: nil
                    )
                )
            }

            // Filter members by selected plan times (all teams)
            let timeFiltered = members.filter { m in
                let memberPlanTimeIDs = Set(m.planTimeIDs + (m.planTimeID.map { [$0] } ?? []))
                if !memberPlanTimeIDs.isEmpty,
                   memberPlanTimeIDs.isDisjoint(with: selectedPlanTimeIDs) {
                    return false
                }
                return true
            }
            let cachedTeamAssignments = PCOTileView.buildTeamAssignmentRows(
                members: timeFiltered,
                itemsAndTimes: itemsAndTimes,
                client: client,
                rawSelectedLabels: tab.serviceTimeName
            )
            // Build a per-position team map for the selected plan times (across all teams).
            // Used by Person tiles to show the team for a specific position.
            var positionToTeam: [String: String] = [:]
            for m in timeFiltered {
                let pos = (m.positionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let team = (m.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pos.isEmpty, !team.isEmpty else { continue }
                if positionToTeam[pos] == nil {
                    positionToTeam[pos] = team
                }
            }
            // Build a position -> person map for ALL teams at the selected times.
            // Person tiles can then bind to any PCO position, regardless of team.
            var allMap: [String: String] = [:]
            var assignmentCandidates: [String: [String]] = [:]
            for m in timeFiltered {
                let pos = (m.positionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let person = (m.personName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let team = (m.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pos.isEmpty, !person.isEmpty else { continue }

                if allMap[pos] == nil {
                    allMap[pos] = person
                }

                let keys = team.isEmpty ? [pos] : ["\(team)||\(pos)", pos]
                for key in keys {
                    var names = assignmentCandidates[key] ?? []
                    if !names.contains(where: { $0.compare(person, options: .caseInsensitive) == .orderedSame }) {
                        names.append(person)
                    }
                    assignmentCandidates[key] = names
                }
            }

            await MainActor.run {
                tab.pcoAllPositionAssignments = allMap
                tab.pcoPositionAssignmentCandidates = assignmentCandidates.isEmpty ? nil : assignmentCandidates
                tab.pcoPositionToTeamName = positionToTeam.isEmpty ? nil : positionToTeam
                tab.pcoRundownSnapshotTitles = packedTitles
                tab.pcoSnapshotKey = PCOTileView.makeTabSnapshotKey(
                    serviceTypeID: tab.serviceTypeID,
                    planID: tab.planID,
                    serviceTimeName: tab.serviceTimeName
                )
                tab.pcoCachedRundownRows = cachedRundownRows
                tab.pcoCachedTeamAssignments = cachedTeamAssignments
                tab.pcoTeamPositionsByTeamName = positionsByTeamName.isEmpty ? nil : positionsByTeamName
            }
        } catch {
            // On error, clear assignments so person tiles don't spin forever
            await MainActor.run {
                tab.pcoAllPositionAssignments = [:]
                tab.pcoPositionAssignmentCandidates = nil
                tab.pcoPositionToTeamName = nil
                tab.pcoRundownSnapshotTitles = []
                tab.pcoSnapshotKey = nil
                tab.pcoCachedRundownRows = []
                tab.pcoCachedTeamAssignments = []
                tab.pcoTeamPositionsByTeamName = nil
            }
        }
    }
    
    // MARK: - Time formatting helpers

    private static func parseISOZ(_ iso: String) -> Date? {
        if let d = Formatters.iso8601WithFractional.date(from: iso) {
            return d
        }
        return Formatters.iso8601Basic.date(from: iso)
    }

    private static func toLocalHM(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = Formatters.timeHM
        return formatter.string(from: date)
    }

    /// Shared formatters for PCOTabServiceConfigView to avoid recreating
    /// ISO8601DateFormatter / DateFormatter instances on every call.
    private enum Formatters {
        static let iso8601WithFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        static let iso8601Basic: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        static let timeHM: DateFormatter = {
            let df = DateFormatter()
            df.dateStyle = .none
            df.timeStyle = .short
            return df
        }()
    }
    private static let planDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private static func displayPlanTitle(for plan: PCOResource<PlanAttr>) -> String {
        let rawTitle = plan.attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        let dateString = formatPlanDateLabel(for: plan)

        // If we have a real title, always append the date when available
        if let rawTitle, !rawTitle.isEmpty, rawTitle.lowercased() != "(untitled plan)" {
            if let dateString {
                return "\(rawTitle) – \(dateString)"
            } else {
                return rawTitle
            }
        }

        // Fallback: no usable title
        if let dateString {
            return dateString
        }

        return "Service Plan"
    }

    private static func formatPlanDateLabel(for plan: PCOResource<PlanAttr>) -> String? {
        guard let sortDate = plan.attributes.sort_date,
              let date = Self.parseISOZ(sortDate) else { return nil }
        return Self.planDateFormatter.string(from: date)
    }

    // MARK: - Loading helpers

    private func makeClient() -> PCOClient {
        let tokenStore = KeychainTokenStore()
        let oauth = OAuthService(clientID: clientID, tokenStore: tokenStore)
        return PCOClient(oauthService: oauth, tokenStore: tokenStore)
    }

    private func loadInitialData() async {
        suppressChangeHandlers = true
        let tabID = tab.id
        if let draft = loadDraft(for: tabID) {
            selectedServiceTypeID = draft.serviceTypeID
            selectedPlanID = draft.planID
            selectedTimeNames = draft.selectedTimeNames
            selectedTeamNames = draft.selectedTeamNames
            autoAdvanceEnabled = draft.autoAdvanceEnabled
            autoAdvanceCheckWeekday = clampedAutoAdvanceWeekday(draft.autoAdvanceCheckWeekday)
            autoAdvanceCheckTimeMinutes = clampedAutoAdvanceTimeMinutes(draft.autoAdvanceCheckTimeMinutes)
        } else {
            selectedServiceTypeID = tab.serviceTypeID ?? ""
            selectedPlanID = tab.planID ?? ""
            selectedTimeName = tab.serviceTimeName ?? ""
            selectedTeamName = tab.teamName ?? ""
            autoAdvanceEnabled = tab.pcoAutoAdvanceEnabled
            autoAdvanceCheckWeekday = clampedAutoAdvanceWeekday(tab.pcoAutoAdvanceCheckWeekday)
            autoAdvanceCheckTimeMinutes = clampedAutoAdvanceTimeMinutes(tab.pcoAutoAdvanceCheckTimeMinutes)
            // Initialize multi-select sets from the tab's stored "||"-joined strings.
            if let rawTimes = tab.serviceTimeName, !rawTimes.isEmpty {
                selectedTimeNames = Set(
                    rawTimes.components(separatedBy: "||").filter { !$0.isEmpty }
                )
                selectedTimeName = selectedTimeNames.first ?? selectedTimeName
            } else {
                selectedTimeNames = []
            }

            if let rawTeams = tab.teamName, !rawTeams.isEmpty {
                selectedTeamNames = Set(
                    rawTeams.components(separatedBy: "||").filter { !$0.isEmpty }
                )
                selectedTeamName = selectedTeamNames.first ?? selectedTeamName
            } else {
                selectedTeamNames = []
            }
        }

        selectedTimeName = selectedTimeNames.first ?? ""
        selectedTeamName = selectedTeamNames.first ?? ""
        suppressChangeHandlers = false

        var hasServiceTypes = false
        if let staticCache = Self.serviceTypesCache,
           Date().timeIntervalSince(staticCache.fetchedAt) < 300,
           !staticCache.types.isEmpty {
            availableServiceTypes = staticCache.types
            cachedServiceTypes = staticCache.types
            cachedServiceTypesFetchedAt = staticCache.fetchedAt
            serviceTypeFolderNamesByID = staticCache.foldersByID
            hasServiceTypes = true
        }

        if !hasServiceTypes {
            await loadServiceTypes()
        }

        if !selectedServiceTypeID.isEmpty {
            await loadPlans()
        }
        if !selectedServiceTypeID.isEmpty, !selectedPlanID.isEmpty {
            await loadTimes()
            await loadTeams()
        }
    }
    private func loadServiceTypes() async {
        isBusy = true
        errorMessage = nil

        print("[PCO] Config: load service types requested")
        PCOTabServiceConfigView.log.info("Config: load service types requested")

        let cached = await MainActor.run {
            (
                self.cachedServiceTypes,
                self.cachedServiceTypesFetchedAt,
                self.isLoadingServiceTypes,
                self.lastServiceTypesAttemptAt,
                self.serviceTypeFolderNamesByID
            )
        }

        if let staticCache = Self.serviceTypesCache,
           Date().timeIntervalSince(staticCache.fetchedAt) < 300,
           !staticCache.types.isEmpty {
            await MainActor.run {
                self.availableServiceTypes = staticCache.types
                self.cachedServiceTypes = staticCache.types
                self.cachedServiceTypesFetchedAt = staticCache.fetchedAt
                self.serviceTypeFolderNamesByID = staticCache.foldersByID
                self.isBusy = false

                if selectedServiceTypeID.isEmpty,
                   let existingID = tab.serviceTypeID,
                   staticCache.types.contains(where: { $0.id == existingID }) {
                    selectedServiceTypeID = existingID
                }
            }
            return
        }
        if let lastAttempt = cached.3,
           Date().timeIntervalSince(lastAttempt) < 5 {
            print("[PCO] Config: load service types throttled")
            PCOTabServiceConfigView.log.info("Config: load service types throttled")
            await MainActor.run {
                self.isBusy = false
            }
            return
        }
        if !cached.0.isEmpty,
           let fetchedAt = cached.1,
           Date().timeIntervalSince(fetchedAt) < 30 {
            await MainActor.run {
                self.availableServiceTypes = cached.0
                self.serviceTypeFolderNamesByID = cached.4
                self.isBusy = false

                if selectedServiceTypeID.isEmpty,
                   let existingID = tab.serviceTypeID,
                   cached.0.contains(where: { $0.id == existingID }) {
                    selectedServiceTypeID = existingID
                }
            }
            return
        }

        if cached.2 {
            return
        }

        let client = makeClient()
        await MainActor.run {
            self.isLoadingServiceTypes = true
            self.lastServiceTypesAttemptAt = Date()
        }

        do {
            let response = try await client.fetchServiceTypesWithFolders()
            await MainActor.run {
                self.cachedServiceTypes = response.types
                self.cachedServiceTypesFetchedAt = Date()
                self.isLoadingServiceTypes = false
                self.availableServiceTypes = response.types
                self.serviceTypeFolderNamesByID = response.foldersByServiceTypeID
                self.isBusy = false
                Self.serviceTypesCache = (
                    types: response.types,
                    foldersByID: response.foldersByServiceTypeID,
                    fetchedAt: Date()
                )

                if selectedServiceTypeID.isEmpty,
                   let existingID = tab.serviceTypeID,
                   response.types.contains(where: { $0.id == existingID }) {
                    selectedServiceTypeID = existingID
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.code == 429 || nsError.localizedDescription.contains("HTTP 429") {
                let message = "Config: HTTP 429 while loading service types. \(nsError.localizedDescription)"
                print("[PCO] \(message)")
                PCOTabServiceConfigView.log.error("\(message, privacy: .public)")
            } else {
                let message = "Config: load service types failed. \(nsError.localizedDescription)"
                print("[PCO] \(message)")
                PCOTabServiceConfigView.log.error("\(message, privacy: .public)")
            }
            await MainActor.run {
                self.isLoadingServiceTypes = false
                self.errorMessage = "Failed to load service types: \(error.localizedDescription)"
                self.isBusy = false
            }
        }
    }

    private func scheduleLoadPlans() {
        debouncedPlansTask?.cancel()
        debouncedPlansTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await loadPlans()
        }
    }

    private func scheduleLoadTimes() {
        debouncedTimesTask?.cancel()
        debouncedTimesTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await loadTimes()
        }
    }

    private func scheduleLoadTeams() {
        debouncedTeamsTask?.cancel()
        debouncedTeamsTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await loadTeams()
        }
    }

    private func loadPlans() async {
        await MainActor.run {
            let serviceTypeChanged = self.cachedPlansServiceTypeID != selectedServiceTypeID
            if serviceTypeChanged {
                self.cachedItemsAndTimes = nil
                self.cachedItemsServiceTypeID = nil
                self.cachedItemsPlanID = nil
                self.cachedItemsTask = nil
                self.cachedItemsTaskServiceTypeID = nil
                self.cachedItemsTaskPlanID = nil
                self.cachedTeamMembers = []
                self.cachedTeamMembersServiceTypeID = nil
                self.cachedTeamMembersPlanID = nil
                self.cachedPlans = []
                self.cachedPlansServiceTypeID = nil
                self.cachedPlansFetchedAt = nil
            }
        }
        guard !selectedServiceTypeID.isEmpty else {
            await MainActor.run {
                self.availablePlans = []
                self.selectedPlanID = ""
                self.availableTimes = []
                self.selectedTimeName = ""
            }
            return
        }

        let alreadyLoading = await MainActor.run {
            self.isLoadingPlans
        }
        if alreadyLoading {
            return
        }

        if let staticPlans = Self.plansCache[selectedServiceTypeID],
           Date().timeIntervalSince(staticPlans.fetchedAt) < 300,
           !staticPlans.plans.isEmpty {
            await MainActor.run {
                if selectedPlanID.isEmpty, let existingID = tab.planID, !existingID.isEmpty {
                    selectedPlanID = existingID
                }
                let resolvedPlans = ensureSelectedPlanVisible(staticPlans.plans)
                self.availablePlans = resolvedPlans
                self.cachedPlans = resolvedPlans
                self.cachedPlansServiceTypeID = selectedServiceTypeID
                self.cachedPlansFetchedAt = staticPlans.fetchedAt
                self.isBusy = false
            }
            return
        }

        let cached = await MainActor.run {
            (self.cachedPlans, self.cachedPlansServiceTypeID, self.cachedPlansFetchedAt)
        }
        if cached.1 == selectedServiceTypeID,
           let fetchedAt = cached.2,
           Date().timeIntervalSince(fetchedAt) < 30,
           !cached.0.isEmpty {
            await MainActor.run {
                if selectedPlanID.isEmpty, let existingID = tab.planID, !existingID.isEmpty {
                    selectedPlanID = existingID
                }
                let resolvedPlans = ensureSelectedPlanVisible(cached.0)
                self.availablePlans = resolvedPlans
                self.isBusy = false
            }
            return
        }

        isBusy = true
        errorMessage = nil
        await MainActor.run {
            self.isLoadingPlans = true
        }

        let client = makeClient()
        do {
            let plans = try await client.fetchPlans(serviceTypeID: selectedServiceTypeID, perPage: 20)
            await MainActor.run {
                if selectedPlanID.isEmpty, let existingID = tab.planID, !existingID.isEmpty {
                    selectedPlanID = existingID
                }
                let resolvedPlans = ensureSelectedPlanVisible(plans)
                self.cachedPlans = resolvedPlans
                self.cachedPlansServiceTypeID = selectedServiceTypeID
                self.cachedPlansFetchedAt = Date()
                self.availablePlans = resolvedPlans
                self.isLoadingPlans = false
                self.isBusy = false
                Self.plansCache[selectedServiceTypeID] = (plans: resolvedPlans, fetchedAt: Date())

                // Keep existing selection if still valid; otherwise default to first plan
            }
        } catch {
            await MainActor.run {
                self.isLoadingPlans = false
                self.errorMessage = "Failed to load plans: \(error.localizedDescription)"
                self.isBusy = false
            }
        }
    }

    private func getItemsAndTimes(
        client: PCOClient,
        serviceTypeID: String,
        planID: String
    ) async throws -> PCOClient.ItemsAndTimes {
        let cacheKey = "\(serviceTypeID)|\(planID)"
        if let staticItems = Self.itemsAndTimesCache[cacheKey] {
            await MainActor.run {
                self.cachedItemsAndTimes = staticItems
                self.cachedItemsServiceTypeID = serviceTypeID
                self.cachedItemsPlanID = planID
            }
            return staticItems
        }

        let cached = await MainActor.run {
            (
                self.cachedItemsAndTimes,
                self.cachedItemsServiceTypeID,
                self.cachedItemsPlanID,
                self.cachedItemsTask,
                self.cachedItemsTaskServiceTypeID,
                self.cachedItemsTaskPlanID
            )
        }
        if let itemsAndTimes = cached.0,
           cached.1 == serviceTypeID,
           cached.2 == planID {
            return itemsAndTimes
        }

        if let task = cached.3,
           cached.4 == serviceTypeID,
           cached.5 == planID {
            return try await task.value
        }

        let task = Task {
            try await client.fetchItemsAndTimes(
                serviceTypeID: serviceTypeID,
                planID: planID
            )
        }
        await MainActor.run {
            self.cachedItemsTask = task
            self.cachedItemsTaskServiceTypeID = serviceTypeID
            self.cachedItemsTaskPlanID = planID
        }

        do {
            let fresh = try await task.value
            await MainActor.run {
                self.cachedItemsAndTimes = fresh
                self.cachedItemsServiceTypeID = serviceTypeID
                self.cachedItemsPlanID = planID
                self.cachedItemsTask = nil
                self.cachedItemsTaskServiceTypeID = nil
                self.cachedItemsTaskPlanID = nil
                Self.itemsAndTimesCache[cacheKey] = fresh
            }
            return fresh
        } catch {
            await MainActor.run {
                if self.cachedItemsTaskServiceTypeID == serviceTypeID,
                   self.cachedItemsTaskPlanID == planID {
                    self.cachedItemsTask = nil
                    self.cachedItemsTaskServiceTypeID = nil
                    self.cachedItemsTaskPlanID = nil
                }
            }
            throw error
        }
    }

    private func loadTimes() async {
        guard !selectedServiceTypeID.isEmpty, !selectedPlanID.isEmpty else {
            await MainActor.run {
                self.availableTimes = []
                self.selectedTimeName = ""
                self.isLoadingTimes = false
            }
            return
        }

        let cacheKey = "\(selectedServiceTypeID)|\(selectedPlanID)"
        let hasLocalItems = cachedItemsServiceTypeID == selectedServiceTypeID
            && cachedItemsPlanID == selectedPlanID
            && cachedItemsAndTimes != nil
        let hasStaticItems = Self.itemsAndTimesCache[cacheKey] != nil

        let alreadyLoading = await MainActor.run {
            self.isLoadingTimes
        }
        if alreadyLoading {
            return
        }

        if !(hasLocalItems || hasStaticItems) {
            await MainActor.run {
                self.isLoadingTimes = true
            }
            isBusy = true
        }
        errorMessage = nil

        let client = makeClient()
        do {
            let itemsAndTimes = try await getItemsAndTimes(
                client: client,
                serviceTypeID: selectedServiceTypeID,
                planID: selectedPlanID
            )

            let planTimes = itemsAndTimes.planTimes.data

            // Build labels similar to the main app:
            // "Cafe – Special Shift — 7:00 AM" or "9:00 AM" when name is nil.
            var labels: [String] = []

            for (index, resource) in planTimes.enumerated() {
                let attr = resource.attributes

                let starts: Date?
                if let iso = attr.starts_at {
                    starts = Self.parseISOZ(iso)
                } else {
                    starts = nil
                }

                let localHM = Self.toLocalHM(starts)

                let parts: [String] = [attr.name, localHM].compactMap { part in
                    guard let v = part, !v.isEmpty else { return nil }
                    return v
                }

                if parts.isEmpty {
                    labels.append("Time \(index + 1)")
                } else {
                    labels.append(parts.joined(separator: " — "))
                }
            }

            // Dedupe labels while preserving their original (chronological) order.
            var seen = Set<String>()
            var unique: [String] = []
            for label in labels {
                if !seen.contains(label) {
                    seen.insert(label)
                    unique.append(label)
                }
            }

            await MainActor.run {
                self.availableTimes = unique
                self.isLoadingTimes = false
                self.isBusy = false

                if self.selectedTimeNames.isEmpty,
                   let rawTimes = tab.serviceTimeName,
                   !rawTimes.isEmpty {
                    self.selectedTimeNames = Set(
                        rawTimes.components(separatedBy: "||").filter { !$0.isEmpty }
                    )
                }

                // Ensure selectedTimeNames are a subset of available times.
                self.selectedTimeNames = self.selectedTimeNames.filter { unique.contains($0) }

                self.selectedTimeName = self.selectedTimeNames.first ?? ""
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load service times: \(error.localizedDescription)"
                self.isLoadingTimes = false
                self.isBusy = false
            }
        }
    }
    private func loadTeams() async {
        let alreadyLoading = await MainActor.run {
            self.isLoadingTeams
        }
        if alreadyLoading {
            return
        }
        if selectedTimeNames.isEmpty {
            await MainActor.run {
                self.availableTeams = []
                self.selectedTeamName = ""
                self.isLoadingTeams = false
            }
            return
        }
        guard !selectedServiceTypeID.isEmpty,
              !selectedPlanID.isEmpty else {
            await MainActor.run {
                self.availableTeams = []
                self.selectedTeamName = ""
                self.isLoadingTeams = false
            }
            return
        }

        let cacheKey = "\(selectedServiceTypeID)|\(selectedPlanID)"
        let hasLocalMembers = cachedTeamMembersServiceTypeID == selectedServiceTypeID
            && cachedTeamMembersPlanID == selectedPlanID
            && !cachedTeamMembers.isEmpty
        let hasStaticMembers = Self.teamMembersCache[cacheKey] != nil

        if !(hasLocalMembers || hasStaticMembers) {
            await MainActor.run {
                self.isLoadingTeams = true
            }
        }

        let client = makeClient()
        do {
            let labels = selectedTimeNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let itemsAndTimes = try await getItemsAndTimes(
                client: client,
                serviceTypeID: selectedServiceTypeID,
                planID: selectedPlanID
            )

            let members: [PCOClient.TeamMemberSummary]
            let cached = await MainActor.run {
                (self.cachedTeamMembers, self.cachedTeamMembersServiceTypeID, self.cachedTeamMembersPlanID)
            }
            if cached.1 == selectedServiceTypeID,
               cached.2 == selectedPlanID,
               !cached.0.isEmpty {
                members = cached.0
            } else if let staticMembers = Self.teamMembersCache[cacheKey],
                      !staticMembers.isEmpty {
                await MainActor.run {
                    self.cachedTeamMembers = staticMembers
                    self.cachedTeamMembersServiceTypeID = selectedServiceTypeID
                    self.cachedTeamMembersPlanID = selectedPlanID
                }
                members = staticMembers
            } else {
                let fresh = try await client.fetchPlanTeamMemberSummaries(
                    serviceTypeID: selectedServiceTypeID,
                    planID: selectedPlanID
                )
                await MainActor.run {
                    self.cachedTeamMembers = fresh
                    self.cachedTeamMembersServiceTypeID = selectedServiceTypeID
                    self.cachedTeamMembersPlanID = selectedPlanID
                    Self.teamMembersCache[cacheKey] = fresh
                }
                members = fresh
            }

            let names = buildTeamNames(
                client: client,
                itemsAndTimes: itemsAndTimes,
                members: members,
                selectedLabels: labels
            )


            await MainActor.run {
                self.availableTeams = names
                self.isLoadingTeams = false

                if self.selectedTeamNames.isEmpty,
                   let rawTeams = tab.teamName,
                   !rawTeams.isEmpty {
                    self.selectedTeamNames = Set(
                        rawTeams.components(separatedBy: "||").filter { !$0.isEmpty }
                    )
                }

                // Ensure selectedTeamNames are a subset of available teams.
                self.selectedTeamNames = self.selectedTeamNames.filter { names.contains($0) }
                self.selectedTeamName = self.selectedTeamNames.first ?? ""
            }
        } catch {
            await MainActor.run {
                self.availableTeams = []
                self.selectedTeamName = ""
                self.isLoadingTeams = false
                // Surface a lightweight error; we already have errorMessage.
                self.errorMessage = "Failed to load teams: \(error.localizedDescription)"
            }
        }
    }

    private func updateTeamsFromCache() {
        guard !selectedServiceTypeID.isEmpty,
              !selectedPlanID.isEmpty else {
            return
        }

        let cacheKey = "\(selectedServiceTypeID)|\(selectedPlanID)"
        let cached = (cachedTeamMembers, cachedTeamMembersServiceTypeID, cachedTeamMembersPlanID)
        let itemsAndTimes: PCOClient.ItemsAndTimes? = {
            if cachedItemsServiceTypeID == selectedServiceTypeID,
               cachedItemsPlanID == selectedPlanID,
               let cachedItemsAndTimes {
                return cachedItemsAndTimes
            }
            return Self.itemsAndTimesCache[cacheKey]
        }()
        let members: [PCOClient.TeamMemberSummary] = {
            if cached.1 == selectedServiceTypeID,
               cached.2 == selectedPlanID,
               !cached.0.isEmpty {
                return cached.0
            }
            return Self.teamMembersCache[cacheKey] ?? []
        }()

        if let itemsAndTimes, !members.isEmpty {
            let labels = selectedTimeNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let names = buildTeamNames(
                client: makeClient(),
                itemsAndTimes: itemsAndTimes,
                members: members,
                selectedLabels: labels
            )
            availableTeams = names

            selectedTeamNames = selectedTeamNames.filter { names.contains($0) }
            selectedTeamName = selectedTeamNames.first ?? ""
        } else {
            scheduleLoadTeams()
        }
    }

    private func buildTeamNames(
        client: PCOClient,
        itemsAndTimes: PCOClient.ItemsAndTimes,
        members: [PCOClient.TeamMemberSummary],
        selectedLabels: [String]
    ) -> [String] {
        if selectedLabels.isEmpty {
            return []
        }

        var ids = Set<String>()
        for label in selectedLabels {
            let labelIDs = client.planTimeIDs(
                forSelectedLabel: label,
                in: itemsAndTimes.planTimes
            )
            ids.formUnion(labelIDs)
        }
        let selectedPlanTimeIDs = ids

        var set = Set<String>()
        for member in members {
            let memberPlanTimeIDs = Set(member.planTimeIDs + (member.planTimeID.map { [$0] } ?? []))
            if !memberPlanTimeIDs.isEmpty,
               memberPlanTimeIDs.isDisjoint(with: selectedPlanTimeIDs) {
                continue
            }
            if let team = member.teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !team.isEmpty {
                set.insert(team)
            }
        }

        return Array(set).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
// MARK: - PCO Module Plugin

enum PCOModulePlugin {}

extension PCOModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .pcoRundown }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        AnyView(
            PCOTileView(
                tab: tab,
                moduleConfig: module.wrappedValue.pcoConfig,
                moduleConfigBinding: Binding(
                    get: { module.wrappedValue.pcoConfig ?? PCOModuleConfig.rundownDefault() },
                    set: { newValue in
                        var updated = module.wrappedValue
                        updated.pcoConfig = newValue
                        module.wrappedValue = updated
                    }
                )
            )
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        let cfg = Binding<PCOModuleConfig>(
            get: {
                var c = PCOModuleConfig.rundownDefault()
                c.showHeader = showsHeader.wrappedValue
                return c
            },
            set: { newValue in
                showsHeader.wrappedValue = newValue.showHeader
                onPersist()
            }
        )

        return AnyView(
            PCOModuleSettingsInspector(
                config: cfg,
                tab: DashboardTab(name: "", tiles: []),
                onPersist: onPersist,
                onOpenTabSettings: {}
            )
        )
    }
}

extension PCOTileView {
    private static let planDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISOZ(_ iso: String) -> Date? {
        if let d = iso8601WithFractional.date(from: iso) {
            return d
        }
        return iso8601Basic.date(from: iso)
    }

    static func formatPlanDateLabel(for plan: PCOResource<PlanAttr>) -> String? {
        guard let sortDate = plan.attributes.sort_date,
              let date = parseISOZ(sortDate) else { return nil }
        return planDateFormatter.string(from: date)
    }
}
