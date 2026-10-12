//
//  DashboardModulePlugin.swift
//  Relay
//
//  Created by David Bullard on 1/2/26.
//


//
//  DashboardCoreModels.swift
//  Relay
//
//  Core dashboard models + formatting + plugin registry.
//  (Intentionally kept out of DashboardRootView.swift.)
//

import SwiftUI
import Combine
import WebKit
#if canImport(CryptoKit)
import CryptoKit
#endif

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

enum ImageModuleContentMode: String, CaseIterable, Identifiable, Codable {
    case fit
    case fill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit:
            return "Fit"
        case .fill:
            return "Fill"
        }
    }

    var swiftUIContentMode: ContentMode {
        switch self {
        case .fit:
            return .fit
        case .fill:
            return .fill
        }
    }
}

struct ImageModuleModel: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var displayName: String? = nil
    var cachedFilePath: String? = nil
    var relayFileHash: String? = nil
    var contentMode: ImageModuleContentMode = .fit
    var backgroundColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 0)
}

struct WebpageModuleModel: Identifiable, Equatable, Codable {
    enum SessionMode: String, CaseIterable, Identifiable, Codable {
        case rememberLogin
        case privateSession

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rememberLogin:
                return "Remember Login"
            case .privateSession:
                return "Private Session"
            }
        }
    }

    enum RenderMode: String, CaseIterable, Identifiable, Codable {
        case automatic
        case desktop
        case mobile

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic:
                return "Automatic"
            case .desktop:
                return "Desktop"
            case .mobile:
                return "Mobile"
            }
        }

        var preferredContentMode: WKWebpagePreferences.ContentMode {
            switch self {
            case .automatic:
                return .recommended
            case .desktop:
                return .desktop
            case .mobile:
                return .mobile
            }
        }
    }

    var id: UUID = UUID()
    var urlString: String = ""
    var refreshIntervalSeconds: Double = 0
    var sessionMode: SessionMode = .rememberLogin
    var renderMode: RenderMode = .automatic
    var allowInteractionInLiveMode: Bool = false

    var trimmedURLString: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedURL: URL? {
        let raw = trimmedURLString
        guard !raw.isEmpty else { return nil }

        if let url = URL(string: raw),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return url
        }

        if raw.contains("://") {
            return nil
        }

        let prefixed = "https://\(raw)"
        guard let url = URL(string: prefixed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    var clampedRefreshIntervalSeconds: Double {
        let interval = refreshIntervalSeconds.isFinite ? refreshIntervalSeconds : 0
        return min(max(interval, 15), 3600)
    }

    var effectiveRefreshIntervalSeconds: Double? {
        guard refreshIntervalSeconds.isFinite, refreshIntervalSeconds >= 15 else {
            return nil
        }

        return clampedRefreshIntervalSeconds
    }
}

struct YouTubeStreamMonitorModuleModel: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var selectedBroadcastID: String? = nil
    var selectedBroadcastTitle: String? = nil
    var selectedStreamID: String? = nil
    var pollIntervalSeconds: Double = 15
    var showHealthDetails: Bool = true
    var allowInteractionInLiveMode: Bool = false

    var clampedPollIntervalSeconds: Double {
        let interval = pollIntervalSeconds.isFinite ? pollIntervalSeconds : 15
        return min(max(interval, 10), 60)
    }
}

// MARK: - Dashboard Tab Model
// MARK: - Dashboard Tab + Save State
struct DashboardTabScheduleRule: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Calendar weekday values using the Gregorian convention: 1 = Sunday ... 7 = Saturday.
    var weekdays: [Int]
    /// Minutes from midnight in the current timezone.
    var startMinutes: Int
    /// Minutes from midnight in the current timezone.
    var endMinutes: Int
    var isAllDay: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        weekdays: [Int] = Array(2...6),
        startMinutes: Int = 0,
        endMinutes: Int = 24 * 60,
        isAllDay: Bool = true
    ) {
        self.id = id
        self.name = name
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.isAllDay = isAllDay
    }
}

struct DashboardTab: Identifiable, Codable, Equatable {
    enum AutomationMode: String, Codable, Equatable {
        case perTab
        case universal
    }

    var id: UUID = UUID()
    var name: String
    var tiles: [DashboardTileModel]
    var guides: [CanvasGuide] = []
    var tileGroups: [DashboardTileGroup] = []

    // Per-tab Planning Center scope (option 1)
    var serviceTypeID: String?
    var serviceTypeName: String?
    var planID: String?
    var planTitle: String?
    var planDateLabel: String?
    var serviceTimeName: String?
    var showServiceRundown: Bool = false
    var showTeamAssignments: Bool = false
    var teamName: String? = nil
    var pcoPositionAssignments: [String: String]? = nil
    var pcoAllPositionAssignments: [String: String]? = nil
    /// Cached Planning Center assignee lists keyed by team+position when available,
    /// plus position-only fallback keys.
    /// This lets Person tiles disambiguate when multiple people share one assignment.
    var pcoPositionAssignmentCandidates: [String: [String]]? = nil
    /// Full catalog of PCO team positions, grouped by team name.
    /// Includes positions that may be unassigned in the current plan.
    /// Optional for backward compatibility with older dashboard files.
    var pcoTeamPositionsByTeamName: [String: [String]]? = nil
    /// Map of PCO position name -> team name for the currently cached assignment set.
    /// This allows Person tiles to show the team for a specific position (e.g. "Soprano 1" -> "Worship Singers").
    /// Optional for backward compatibility with older dashboard files.
    var pcoPositionToTeamName: [String: String]? = nil
    /// Cached Planning Center rundown item titles for this tab.
    /// Populated by `PCOTileView` after a successful rundown fetch so Graph mode can build snapshots
    /// without needing live tile data or additional network calls.
    var pcoRundownSnapshotTitles: [String] = []
    /// Cache key describing the tab-scoped PCO snapshot that modules can render from.
    var pcoSnapshotKey: String? = nil
    /// Cached tab-scoped rundown rows for the selected service/plan/time combination.
    var pcoCachedRundownRows: [PCORundownRow] = []
    /// Cached tab-scoped team assignments for the selected service/plan/time combination.
    /// This stores all teams for the tab selection; individual modules can filter locally.
    var pcoCachedTeamAssignments: [PCOTeamAssignmentRow] = []
    /// When enabled, checks PCO at the configured weekly checkpoint and advances
    /// this tab to the next upcoming plan when the selected plan is behind it.
    var pcoAutoAdvanceEnabled: Bool = false

    /// Weekly check weekday for auto-advance: 1 = Sunday ... 7 = Saturday.
    var pcoAutoAdvanceCheckWeekday: Int = 2
    /// Weekly check time in minutes after midnight.
    var pcoAutoAdvanceCheckTimeMinutes: Int = 15 * 60
    /// Shared tab-wide roster columns that picker modules can reference.
    var rosterColumns: [DashboardRosterColumn] = []
    /// Shared tab-wide roster rows that picker modules can reference.
    var rosterRows: [DashboardRosterRow] = []
    /// Shared roster library attachments for this tab.
    var attachedRosterIDs: [UUID] = []
    /// Preferred shared general roster for legacy roster modules and graph sources.
    var defaultGeneralRosterID: UUID? = nil
    /// Preferred equipment roster for additive assignment categories.
    var defaultEquipmentRosterID: UUID? = nil
    /// Preferred people roster for future manual team-assignment flows.
    var defaultPeopleRosterID: UUID? = nil
    /// When enabled, this tab can become the active tab based on matching schedule rules.
    var tabScheduleEnabled: Bool = false
    /// Rules are evaluated in order; the first match wins for this tab.
    var tabScheduleRules: [DashboardTabScheduleRule] = []
    // MARK: - Graph View (tile-as-nodes)
    /// Optional graph state for this tab (node positions + links). Tiles remain the source of truth.
    var graph: DashboardGraph? = nil
    
    // MARK: - LAN Mirroring
    var lanMirrorShareId: String? = nil
    var lanMirrorDeviceName: String? = nil

    /// Per-tab canvas size override. nil means use the document-level default.
    var canvasSize: CGSize? = nil

    // MARK: - Synced Tabs
    /// Non-nil means this tab is linked to a LAN-wide sync group (see SyncedTabManifest/Snapshot).
    var syncGroupID: String? = nil
    /// true = this device created the sync group (host); false = this device joined from a peer.
    /// Persisted so joiners don't re-announce the tab as hosted after an app restart.
    var syncIsOwner: Bool = false
    /// Opt-in: when true, device-targeting fields (Shure channel, ProPresenter profile, etc.) are
    /// included in sync instead of staying local-only. Plan 2 implements the strip/preserve logic.
    var syncDeviceTargetsEnabled: Bool = false
    /// Incremented on every local edit to this tab; dominates LWW comparisons.
    var syncRevision: Int = 0
    var syncLastEditedAt: TimeInterval = 0
    var syncLastEditedByDeviceID: String = ""
    var syncLastEditedByDeviceName: String = ""

    /// The device ID that created this sync group (set by makeSyncedTab, never changed by edits).
    /// Used to detect foreign ownership on file import. nil for joined/subscriber tabs and old files.
    var syncOwnerDeviceID: String? = nil
    /// Stable display name of the computer that created this sync group.
    /// Persisted so linked-variable labels remain useful when the host is offline.
    var syncOwnerDeviceName: String = ""
    /// Whether this tab uses the dashboard-level universal automation graph or its own per-tab graph.
    var automationMode: AutomationMode = .universal

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case tiles
        case guides
        case tileGroups

        case serviceTypeID
        case serviceTypeName
        case planID
        case planTitle
        case planDateLabel
        case serviceTimeName
        case showServiceRundown
        case showTeamAssignments
        case teamName
        case pcoPositionAssignments
        case pcoAllPositionAssignments
        case pcoPositionAssignmentCandidates
        case pcoTeamPositionsByTeamName
        case pcoPositionToTeamName
        case pcoRundownSnapshotTitles
        case pcoSnapshotKey
        case pcoCachedRundownRows
        case pcoCachedTeamAssignments
        case pcoAutoAdvanceEnabled
        case pcoAutoAdvanceCheckWeekday
        case pcoAutoAdvanceCheckTimeMinutes
        case rosterColumns
        case rosterRows
        case attachedRosterIDs
        case defaultGeneralRosterID
        case defaultEquipmentRosterID
        case defaultPeopleRosterID
        case tabScheduleEnabled
        case tabScheduleRules
        
        case graph

        case lanMirrorShareId
        case lanMirrorDeviceName
        case canvasSize

        case syncGroupID
        case syncIsOwner
        case syncOwnerDeviceID
        case syncOwnerDeviceName
        case syncDeviceTargetsEnabled
        case syncRevision
        case syncLastEditedAt
        case syncLastEditedByDeviceID
        case syncLastEditedByDeviceName
        case automationMode
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case pcoAutoAdvanceRefreshWeekday
    }
    

    init(
        id: UUID = UUID(),
        name: String,
        tiles: [DashboardTileModel],
        guides: [CanvasGuide] = [],
        tileGroups: [DashboardTileGroup] = [],
        serviceTypeID: String? = nil,
        serviceTypeName: String? = nil,
        planID: String? = nil,
        planTitle: String? = nil,
        planDateLabel: String? = nil,
        serviceTimeName: String? = nil,
        showServiceRundown: Bool = false,
        showTeamAssignments: Bool = false,
        teamName: String? = nil,
        pcoPositionAssignments: [String: String]? = nil,
        pcoAllPositionAssignments: [String: String]? = nil,
        pcoPositionAssignmentCandidates: [String: [String]]? = nil,
        pcoTeamPositionsByTeamName: [String: [String]]? = nil,
        pcoPositionToTeamName: [String: String]? = nil,
        pcoRundownSnapshotTitles: [String] = [],
        pcoSnapshotKey: String? = nil,
        pcoCachedRundownRows: [PCORundownRow] = [],
        pcoCachedTeamAssignments: [PCOTeamAssignmentRow] = [],
        pcoAutoAdvanceEnabled: Bool = false,
        pcoAutoAdvanceCheckWeekday: Int = 2,
        pcoAutoAdvanceCheckTimeMinutes: Int = 15 * 60,
        rosterColumns: [DashboardRosterColumn] = [],
        rosterRows: [DashboardRosterRow] = [],
        attachedRosterIDs: [UUID] = [],
        defaultGeneralRosterID: UUID? = nil,
        defaultEquipmentRosterID: UUID? = nil,
        defaultPeopleRosterID: UUID? = nil,
        tabScheduleEnabled: Bool = false,
        tabScheduleRules: [DashboardTabScheduleRule] = [],
        graph: DashboardGraph? = nil,
        lanMirrorShareId: String? = nil,
        lanMirrorDeviceName: String? = nil,
        canvasSize: CGSize? = nil,
        syncGroupID: String? = nil,
        syncIsOwner: Bool = false,
        syncOwnerDeviceID: String? = nil,
        syncOwnerDeviceName: String = "",
        syncDeviceTargetsEnabled: Bool = false,
        syncRevision: Int = 0,
        syncLastEditedAt: TimeInterval = 0,
        syncLastEditedByDeviceID: String = "",
        syncLastEditedByDeviceName: String = "",
        automationMode: AutomationMode = .universal
    ) {
        self.id = id
        self.name = name
        self.tiles = tiles
        self.guides = guides
        self.tileGroups = tileGroups

        self.serviceTypeID = serviceTypeID
        self.serviceTypeName = serviceTypeName
        self.planID = planID
        self.planTitle = planTitle
        self.planDateLabel = planDateLabel
        self.serviceTimeName = serviceTimeName
        self.showServiceRundown = showServiceRundown
        self.showTeamAssignments = showTeamAssignments
        self.teamName = teamName
        self.pcoPositionAssignments = pcoPositionAssignments
        self.pcoAllPositionAssignments = pcoAllPositionAssignments
        self.pcoPositionAssignmentCandidates = pcoPositionAssignmentCandidates
        self.pcoTeamPositionsByTeamName = pcoTeamPositionsByTeamName
        self.pcoPositionToTeamName = pcoPositionToTeamName
        self.pcoRundownSnapshotTitles = pcoRundownSnapshotTitles
        self.pcoSnapshotKey = pcoSnapshotKey
        self.pcoCachedRundownRows = pcoCachedRundownRows
        self.pcoCachedTeamAssignments = pcoCachedTeamAssignments
        self.pcoAutoAdvanceEnabled = pcoAutoAdvanceEnabled
        self.pcoAutoAdvanceCheckWeekday = Self.clampedPCOAutoAdvanceWeekday(pcoAutoAdvanceCheckWeekday)
        self.pcoAutoAdvanceCheckTimeMinutes = Self.clampedPCOAutoAdvanceTimeMinutes(pcoAutoAdvanceCheckTimeMinutes)
        self.rosterColumns = rosterColumns
        self.rosterRows = rosterRows
        self.attachedRosterIDs = attachedRosterIDs
        self.defaultGeneralRosterID = defaultGeneralRosterID
        self.defaultEquipmentRosterID = defaultEquipmentRosterID
        self.defaultPeopleRosterID = defaultPeopleRosterID
        self.tabScheduleEnabled = tabScheduleEnabled
        self.tabScheduleRules = tabScheduleRules

        self.graph = graph
        self.lanMirrorShareId = lanMirrorShareId
        self.lanMirrorDeviceName = lanMirrorDeviceName
        self.canvasSize = canvasSize
        self.syncGroupID = syncGroupID
        self.syncIsOwner = syncIsOwner
        self.syncOwnerDeviceID = syncOwnerDeviceID
        self.syncOwnerDeviceName = syncOwnerDeviceName
        self.syncDeviceTargetsEnabled = syncDeviceTargetsEnabled
        self.syncRevision = syncRevision
        self.syncLastEditedAt = syncLastEditedAt
        self.syncLastEditedByDeviceID = syncLastEditedByDeviceID
        self.syncLastEditedByDeviceName = syncLastEditedByDeviceName
        self.automationMode = automationMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Required / core fields
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.tiles = try c.decodeIfPresent([DashboardTileModel].self, forKey: .tiles) ?? []
        self.guides = try c.decodeIfPresent([CanvasGuide].self, forKey: .guides) ?? []
        self.tileGroups = try c.decodeIfPresent([DashboardTileGroup].self, forKey: .tileGroups) ?? []

        // PCO scope (decode with defaults for backwards compatibility)
        self.serviceTypeID = try c.decodeIfPresent(String.self, forKey: .serviceTypeID)
        self.serviceTypeName = try c.decodeIfPresent(String.self, forKey: .serviceTypeName)
        self.planID = try c.decodeIfPresent(String.self, forKey: .planID)
        self.planTitle = try c.decodeIfPresent(String.self, forKey: .planTitle)
        self.planDateLabel = try c.decodeIfPresent(String.self, forKey: .planDateLabel)
        self.serviceTimeName = try c.decodeIfPresent(String.self, forKey: .serviceTimeName)

        self.showServiceRundown = try c.decodeIfPresent(Bool.self, forKey: .showServiceRundown) ?? false
        self.showTeamAssignments = try c.decodeIfPresent(Bool.self, forKey: .showTeamAssignments) ?? false
        self.teamName = try c.decodeIfPresent(String.self, forKey: .teamName)

        self.pcoPositionAssignments = try c.decodeIfPresent([String: String].self, forKey: .pcoPositionAssignments)
        self.pcoAllPositionAssignments = try c.decodeIfPresent([String: String].self, forKey: .pcoAllPositionAssignments)
        self.pcoPositionAssignmentCandidates = try c.decodeIfPresent([String: [String]].self, forKey: .pcoPositionAssignmentCandidates)
        self.pcoTeamPositionsByTeamName = try c.decodeIfPresent([String: [String]].self, forKey: .pcoTeamPositionsByTeamName)
        self.pcoPositionToTeamName = try c.decodeIfPresent([String: String].self, forKey: .pcoPositionToTeamName)

        // Newer field: must not throw on older files
        self.pcoRundownSnapshotTitles = try c.decodeIfPresent([String].self, forKey: .pcoRundownSnapshotTitles) ?? []
        self.pcoSnapshotKey = try c.decodeIfPresent(String.self, forKey: .pcoSnapshotKey)
        self.pcoCachedRundownRows = try c.decodeIfPresent([PCORundownRow].self, forKey: .pcoCachedRundownRows) ?? []
        self.pcoCachedTeamAssignments = try c.decodeIfPresent([PCOTeamAssignmentRow].self, forKey: .pcoCachedTeamAssignments) ?? []
        self.pcoAutoAdvanceEnabled = try c.decodeIfPresent(Bool.self, forKey: .pcoAutoAdvanceEnabled) ?? false
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyRefreshWeekday = try legacy.decodeIfPresent(Int.self, forKey: .pcoAutoAdvanceRefreshWeekday)
        let decodedCheckWeekday = try c.decodeIfPresent(Int.self, forKey: .pcoAutoAdvanceCheckWeekday)
            ?? legacyRefreshWeekday
            ?? 2
        let decodedCheckTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .pcoAutoAdvanceCheckTimeMinutes) ?? (15 * 60)
        self.pcoAutoAdvanceCheckWeekday = Self.clampedPCOAutoAdvanceWeekday(decodedCheckWeekday)
        self.pcoAutoAdvanceCheckTimeMinutes = Self.clampedPCOAutoAdvanceTimeMinutes(decodedCheckTimeMinutes)
        self.rosterColumns = try c.decodeIfPresent([DashboardRosterColumn].self, forKey: .rosterColumns) ?? []
        self.rosterRows = try c.decodeIfPresent([DashboardRosterRow].self, forKey: .rosterRows) ?? []
        self.attachedRosterIDs = try c.decodeIfPresent([UUID].self, forKey: .attachedRosterIDs) ?? []
        self.defaultGeneralRosterID = try c.decodeIfPresent(UUID.self, forKey: .defaultGeneralRosterID)
        self.defaultEquipmentRosterID = try c.decodeIfPresent(UUID.self, forKey: .defaultEquipmentRosterID)
        self.defaultPeopleRosterID = try c.decodeIfPresent(UUID.self, forKey: .defaultPeopleRosterID)
        self.tabScheduleEnabled = try c.decodeIfPresent(Bool.self, forKey: .tabScheduleEnabled) ?? false
        self.tabScheduleRules = try c.decodeIfPresent([DashboardTabScheduleRule].self, forKey: .tabScheduleRules) ?? []

        // Graph state (newer)
        self.graph = try c.decodeIfPresent(DashboardGraph.self, forKey: .graph)

        // LAN mirroring (newer)
        self.lanMirrorShareId = try c.decodeIfPresent(String.self, forKey: .lanMirrorShareId)
        self.lanMirrorDeviceName = try c.decodeIfPresent(String.self, forKey: .lanMirrorDeviceName)

        // Per-tab canvas override (nil for all existing files — backward compatible)
        self.canvasSize = try c.decodeIfPresent(CGSize.self, forKey: .canvasSize)

        // Synced Tabs (newer; defaults preserve backward compatibility with older files)
        self.syncGroupID = try c.decodeIfPresent(String.self, forKey: .syncGroupID)
        self.syncIsOwner = try c.decodeIfPresent(Bool.self, forKey: .syncIsOwner) ?? false
        self.syncOwnerDeviceID = try c.decodeIfPresent(String.self, forKey: .syncOwnerDeviceID)
        self.syncOwnerDeviceName = try c.decodeIfPresent(String.self, forKey: .syncOwnerDeviceName) ?? ""
        self.syncDeviceTargetsEnabled = try c.decodeIfPresent(Bool.self, forKey: .syncDeviceTargetsEnabled) ?? false
        self.syncRevision = try c.decodeIfPresent(Int.self, forKey: .syncRevision) ?? 0
        self.syncLastEditedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .syncLastEditedAt) ?? 0
        self.syncLastEditedByDeviceID = try c.decodeIfPresent(String.self, forKey: .syncLastEditedByDeviceID) ?? ""
        self.syncLastEditedByDeviceName = try c.decodeIfPresent(String.self, forKey: .syncLastEditedByDeviceName) ?? ""

        // Universal Automation Graph (newer; defaults preserve backward compatibility)
        self.automationMode = try c.decodeIfPresent(AutomationMode.self, forKey: .automationMode) ?? .perTab

        // One-shot upgrade: legacy PCO Rundown modules that had
        // `showTeamAssignments == true` get split into a dedicated
        // `pcoTeamAssignments` sibling module (or converted in place when the
        // rundown wasn't displaying anything else). Idempotent — after the
        // split the rundown's `showTeamAssignments` is cleared, so reopening
        // a migrated document is a no-op.
        self.tiles = Self.migrateLegacyTilesToModules(in: self.tiles)
        self.tiles = Self.migrateLegacyPCOTeamAssignments(in: self.tiles)
        self.tiles = Self.migrateLegacyPCORundownVisibility(in: self.tiles)
    }

    private static func clampedPCOAutoAdvanceWeekday(_ weekday: Int) -> Int {
        (1...7).contains(weekday) ? weekday : 2
    }

    private static func clampedPCOAutoAdvanceTimeMinutes(_ minutes: Int) -> Int {
        max(0, min(minutes, (24 * 60) - 1))
    }

    /// Reconstructs module-first tiles from older tile-first documents at decode time.
    /// This keeps canvas and automation views consistent immediately after load rather
    /// than depending on a later UI-driven migration or save cycle.
    private static func migrateLegacyTilesToModules(in tiles: [DashboardTileModel]) -> [DashboardTileModel] {
        var result = tiles
        for tileIndex in result.indices {
            var tile = result[tileIndex]
            let existingModules = tile.modules ?? []
            guard existingModules.isEmpty else { continue }

            var reconstructed: [DashboardModuleModel] = []

            if let legacySelection = tile.shureChannelSelection {
                var cfg = ShureModuleConfig.default()
                cfg.selectedChannel = legacySelection
                reconstructed.append(
                    DashboardModuleModel(
                        kind: .shureWireless,
                        order: 0,
                        shureConfig: cfg
                    )
                )
            } else {
                switch tile.kind {
                case .empty:
                    break
                case .person(let personModel):
                    reconstructed.append(DashboardModuleModel(kind: .person(personModel), order: 0))
                case .time:
                    reconstructed.append(
                        DashboardModuleModel(
                            kind: .time,
                            order: 0,
                            timeConfig: TimeModuleConfig.default()
                        )
                    )
                case .pcoPlaceholder:
                    reconstructed.append(
                        DashboardModuleModel(
                            kind: .pcoRundown,
                            order: 0,
                            pcoConfig: PCOModuleConfig.rundownDefault()
                        )
                    )
                }
            }

            guard !reconstructed.isEmpty else { continue }
            tile.modules = reconstructed
            tile.kind = .empty
            result[tileIndex] = tile
        }
        return result
    }

    /// Splits any legacy `pcoRundown` module that has `showTeamAssignments`
    /// turned on into a sibling `pcoTeamAssignments` module. Settings the
    /// user previously configured for team assignments (team names, sort
    /// order, density threshold, etc.) are carried over to the new module.
    private static func migrateLegacyPCOTeamAssignments(
        in tiles: [DashboardTileModel]
    ) -> [DashboardTileModel] {
        var result = tiles
        for tileIdx in result.indices {
            guard let originalModules = result[tileIdx].modules else { continue }

            var didChange = false
            var migrated: [DashboardModuleModel] = []
            migrated.reserveCapacity(originalModules.count + 1)

            for module in originalModules {
                guard case .pcoRundown = module.kind,
                      let oldCfg = module.pcoConfig,
                      oldCfg.showTeamAssignments
                else {
                    migrated.append(module)
                    continue
                }

                didChange = true

                var teamCfg = PCOModuleConfig.teamAssignmentsDefault()
                teamCfg.teamName = oldCfg.teamName
                teamCfg.serviceTimeNames = oldCfg.serviceTimeNames
                teamCfg.showTeamMemberStatus = oldCfg.showTeamMemberStatus
                teamCfg.useStatusStyledAssignmentCards = oldCfg.useStatusStyledAssignmentCards
                teamCfg.teamAssignmentSortMode = oldCfg.teamAssignmentSortMode
                teamCfg.hideDeclinedAssignments = oldCfg.hideDeclinedAssignments
                teamCfg.assignmentTwoColumnThreshold = oldCfg.assignmentTwoColumnThreshold
                if let extras = oldCfg.teamExtras { teamCfg.teamExtras = extras }

                let hasRundownContent = oldCfg.showServiceRundown || oldCfg.showLiveView

                if hasRundownContent {
                    var rundownCfg = oldCfg
                    rundownCfg.showTeamAssignments = false
                    var rundown = module
                    rundown.pcoConfig = rundownCfg
                    migrated.append(rundown)

                    let teamModule = DashboardModuleModel(
                        kind: .pcoTeamAssignments,
                        order: rundown.order + 1,
                        pcoConfig: teamCfg,
                        paddingTop: module.paddingTop,
                        paddingBottom: module.paddingBottom,
                        moduleScale: module.moduleScale,
                        moduleHeightPoints: module.moduleHeightPoints
                    )
                    migrated.append(teamModule)
                } else {
                    // The rundown module was acting purely as a team-only
                    // surface — replace it in place to keep the tile compact.
                    let teamModule = DashboardModuleModel(
                        kind: .pcoTeamAssignments,
                        order: module.order,
                        id: module.id,
                        pcoConfig: teamCfg,
                        paddingTop: module.paddingTop,
                        paddingBottom: module.paddingBottom,
                        moduleScale: module.moduleScale,
                        moduleHeightPoints: module.moduleHeightPoints
                    )
                    migrated.append(teamModule)
                }
            }

            if didChange {
                for idx in migrated.indices { migrated[idx].order = idx }
                result[tileIdx].modules = migrated
            }
        }
        return result
    }

    /// Ensures dedicated `pcoRundown` modules always render their rundown
    /// content. Older builds could persist this toggle as off even though the
    /// module itself was the rundown surface.
    private static func migrateLegacyPCORundownVisibility(
        in tiles: [DashboardTileModel]
    ) -> [DashboardTileModel] {
        var result = tiles
        for tileIdx in result.indices {
            guard let originalModules = result[tileIdx].modules else { continue }

            var didChange = false
            var migrated: [DashboardModuleModel] = []
            migrated.reserveCapacity(originalModules.count)

            for module in originalModules {
                guard case .pcoRundown = module.kind else {
                    migrated.append(module)
                    continue
                }

                var updatedModule = module
                var updatedConfig = module.pcoConfig ?? PCOModuleConfig.rundownDefault()

                if !updatedConfig.showServiceRundown || module.pcoConfig == nil {
                    updatedConfig.showServiceRundown = true
                    updatedModule.pcoConfig = updatedConfig
                    didChange = true
                }

                migrated.append(updatedModule)
            }

            if didChange {
                result[tileIdx].modules = migrated
            }
        }
        return result
    }
}

extension DashboardTab {
    /// Returns a copy of this tab with all sync-bookkeeping fields zeroed out, so two
    /// otherwise-identical tabs hash the same regardless of revision/device metadata.
    func strippedForSyncContentHash() -> DashboardTab {
        var copy = self
        copy.syncGroupID = nil
        copy.syncIsOwner = false
        copy.syncOwnerDeviceID = nil
        copy.syncOwnerDeviceName = ""
        copy.canvasSize = nil
        copy.syncDeviceTargetsEnabled = false
        copy.syncRevision = 0
        copy.syncLastEditedAt = 0
        copy.syncLastEditedByDeviceID = ""
        copy.syncLastEditedByDeviceName = ""
        return copy
    }

    /// Stable content hash (ignoring sync metadata), used to detect local edits that
    /// should bump `syncRevision` and to detect whether an incoming snapshot actually
    /// differs from the local copy.
    func syncContentHash() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(strippedForSyncContentHash())) ?? Data()
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return data.base64EncodedString()
        #endif
    }

    func defaultRosterID(for kind: DashboardRosterKind) -> UUID? {
        switch kind {
        case .general:
            return defaultGeneralRosterID
        case .equipment:
            return defaultEquipmentRosterID
        case .people:
            return defaultPeopleRosterID
        }
    }

    func sharedRoster(for kind: DashboardRosterKind, from rosters: [DashboardRoster]) -> DashboardRoster? {
        if let rosterID = defaultRosterID(for: kind),
           let preferred = rosters.first(where: { $0.id == rosterID && $0.kind == kind }) {
            return preferred
        }

        return rosters.first(where: { roster in
            roster.kind == kind && attachedRosterIDs.contains(roster.id)
        })
    }

    private func pcoAssignmentLookupKey(teamName: String?, positionName: String) -> String {
        let position = positionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = (teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !team.isEmpty else { return position }
        return "\(team)||\(position)"
    }

    /// Returns a copy of the person model with its name overridden by the
    /// current PCO assignment, if this tile is configured to follow a PCO team
    /// position and we have data for that position.
    func resolvedPersonModel(_ model: PersonTileModel) -> PersonTileModel {
        // Only resolve in PCO-driven mode
        guard model.source == .pcoTeam,
              let position = model.pcoPositionName
        else {
            return model
        }

        let trimmedPosition = position.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPosition.isEmpty else { return model }

        let candidateAssignments = pcoPositionAssignmentCandidates?[pcoAssignmentLookupKey(teamName: model.pcoTeamName, positionName: trimmedPosition)]
            ?? pcoPositionAssignmentCandidates?[trimmedPosition]

        if let candidateAssignments, !candidateAssignments.isEmpty {
            var copy = model
            let selectedIndex: Int = {
                if let slot = copy.pcoAssignmentSlot, candidateAssignments.indices.contains(slot) {
                    return slot
                }
                let existingName = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !existingName.isEmpty,
                   let matchedIndex = candidateAssignments.firstIndex(where: {
                       $0.compare(existingName, options: .caseInsensitive) == .orderedSame
                   }) {
                    return matchedIndex
                }
                return 0
            }()

            copy.name = candidateAssignments[selectedIndex]
            copy.pcoAssignmentSlot = selectedIndex

            if (copy.pcoTeamName ?? "").isEmpty {
                if let map = pcoPositionToTeamName,
                   let team = map[trimmedPosition]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !team.isEmpty {
                    copy.pcoTeamName = team
                }
            }

            return copy
        }

        // Prefer the all-teams assignment map if available, fall back to
        // the single-team map used by the PCO tile.
        let assignments = pcoAllPositionAssignments ?? pcoPositionAssignments

        guard let personName = assignments?[trimmedPosition] else {
            return model
        }

        var copy = model
        copy.name = personName    // keep role as-is (usually the position label)

        // Populate the team name for this specific position when available.
        // Avoid using the tab's team selector when it represents multiple/all teams.
        if (copy.pcoTeamName ?? "").isEmpty {
            if let map = pcoPositionToTeamName,
               let team = map[trimmedPosition]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !team.isEmpty {
                copy.pcoTeamName = team
            } else {
                // Fallback: only use the tab teamName if it looks like a single team.
                let t = (teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, !t.contains(","), t.lowercased() != "all" {
                    copy.pcoTeamName = t
                }
            }
        }

        return copy
    }

    var hasRosterData: Bool {
        !rosterColumns.isEmpty && !rosterRows.isEmpty
    }

    func rosterColumn(id: String?) -> DashboardRosterColumn? {
        guard let id, !id.isEmpty else { return nil }
        return rosterColumns.first(where: { $0.id.uuidString == id })
    }

    func rosterRow(id: UUID?) -> DashboardRosterRow? {
        guard let id else { return nil }
        return rosterRows.first(where: { $0.id == id })
    }

    func rosterValue(rowID: UUID?, columnID: String?) -> String? {
        guard let row = rosterRow(id: rowID),
              let column = rosterColumn(id: columnID)
        else {
            return nil
        }
        let value = row.values[column.id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

enum DashboardRosterKind: String, Codable, CaseIterable, Identifiable {
    case general
    case equipment
    case people

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .equipment:
            return "Equipment"
        case .people:
            return "People"
        }
    }
}

struct DashboardRoster: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var kind: DashboardRosterKind = .general
    var columns: [DashboardRosterColumn] = []
    var rows: [DashboardRosterRow] = []

    init(
        id: UUID = UUID(),
        name: String,
        kind: DashboardRosterKind = .general,
        columns: [DashboardRosterColumn] = [],
        rows: [DashboardRosterRow] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.columns = columns
        self.rows = rows
    }

    var hasData: Bool {
        !columns.isEmpty && !rows.isEmpty
    }
}

struct DashboardRosterColumn: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

struct DashboardRosterRow: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var values: [String: String] = [:]

    init(id: UUID = UUID(), values: [String: String] = [:]) {
        self.id = id
        self.values = values
    }

    func value(for columnID: UUID) -> String {
        values[columnID.uuidString] ?? ""
    }
}

struct RosterPickerModuleModel: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var selectedRosterID: UUID? = nil
    var cachedRosterColumns: [DashboardRosterColumn]? = nil
    var cachedRosterRows: [DashboardRosterRow]? = nil
    var header: String? = "Picker"
    var selectedColumnID: String? = nil
    var selectedRowID: UUID? = nil
    var showsHeaderBackground: Bool = true
    var showsColumnName: Bool = true
    var showsRowNumber: Bool = false

    init(
        id: UUID = UUID(),
        selectedRosterID: UUID? = nil,
        cachedRosterColumns: [DashboardRosterColumn]? = nil,
        cachedRosterRows: [DashboardRosterRow]? = nil,
        header: String? = "Picker",
        selectedColumnID: String? = nil,
        selectedRowID: UUID? = nil,
        showsHeaderBackground: Bool = true,
        showsColumnName: Bool = true,
        showsRowNumber: Bool = false
    ) {
        self.id = id
        self.selectedRosterID = selectedRosterID
        self.cachedRosterColumns = cachedRosterColumns
        self.cachedRosterRows = cachedRosterRows
        self.header = header
        self.selectedColumnID = selectedColumnID
        self.selectedRowID = selectedRowID
        self.showsHeaderBackground = showsHeaderBackground
        self.showsColumnName = showsColumnName
        self.showsRowNumber = showsRowNumber
    }
}
final class DashboardSaveState: ObservableObject {
    // Use a manual publisher so we can avoid emitting changes when the value is unchanged.
    // `@Published` emits in `willSet` even when assigning the same value, which can
    // cascade into expensive SwiftUI invalidations and window title updates.
    let objectWillChange = ObservableObjectPublisher()

    private var _currentFileName: String = "Untitled"
    var currentFileName: String {
        get { _currentFileName }
        set {
            guard _currentFileName != newValue else { return }
            _currentFileName = newValue
            publishChange()
        }
    }

    private var _hasUnsavedChanges: Bool = false
    var hasUnsavedChanges: Bool {
        get { _hasUnsavedChanges }
        set {
            guard _hasUnsavedChanges != newValue else { return }
            _hasUnsavedChanges = newValue
            publishChange()
        }
    }

    private var _hasAssociatedFile: Bool = false
    var hasAssociatedFile: Bool {
        get { _hasAssociatedFile }
        set {
            guard _hasAssociatedFile != newValue else { return }
            _hasAssociatedFile = newValue
            publishChange()
        }
    }

    private var _currentFileURL: URL?
    var currentFileURL: URL? {
        get { _currentFileURL }
        set {
            guard _currentFileURL != newValue else { return }
            _currentFileURL = newValue
            publishChange()
        }
    }

    private var _isSaving: Bool = false
    var isSaving: Bool {
        get { _isSaving }
        set {
            guard _isSaving != newValue else { return }
            _isSaving = newValue
            publishChange()
        }
    }

    private var _lastSavedAt: Date? = nil
    var lastSavedAt: Date? {
        get { _lastSavedAt }
        set {
            guard _lastSavedAt != newValue else { return }
            _lastSavedAt = newValue
            publishChange()
        }
    }

    /// Sticky once true: set when the current document stops being the pristine
    /// auto-generated blank dashboard from a fresh launch — i.e. the user explicitly
    /// created a new dashboard, opened/loaded a file, or saved the current one to disk.
    /// Never reset to false except by relaunching the app. Drives whether Home can be
    /// dismissed back to a real dashboard rather than the launch-time dummy one.
    private var _hasRealDocument: Bool = false
    var hasRealDocument: Bool {
        get { _hasRealDocument }
        set {
            guard newValue, !_hasRealDocument else { return }
            _hasRealDocument = true
            publishChange()
        }
    }

    var displayFileName: String {
        let trimmed = _currentFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var canSaveCurrentDocument: Bool {
        _hasUnsavedChanges || !_hasAssociatedFile
    }

    private func publishChange() {
        if Thread.isMainThread {
            objectWillChange.send()
            NotificationCenter.default.post(name: .dashboardSaveStateDidChange, object: self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                NotificationCenter.default.post(name: .dashboardSaveStateDidChange, object: self)
            }
        }
    }

    static let shared = DashboardSaveState()
}

extension Notification.Name {
    static let dashboardSaveStateDidChange = Notification.Name("Relay.DashboardSaveStateDidChange")
}

/// Tracks whether the home/launch screen sheet is currently presented.
/// `RelayDashboardApp` owns the actual `launchScreenDismissed` state (it's private
/// to that view struct); this singleton mirrors it so `DashboardRootView` can also
/// read/dismiss it when deciding whether it's safe to show a save-prompt alert.
final class DashboardHomeScreenState: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private var _isPresented: Bool = false
    var isPresented: Bool {
        get { _isPresented }
        set {
            guard _isPresented != newValue else { return }
            _isPresented = newValue
            if Thread.isMainThread {
                objectWillChange.send()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            }
        }
    }

    /// Set when the home screen's "Open File" button dismisses the launch sheet and hands off
    /// to the file picker. If the picker comes back cancelled, this tells `DashboardRootView`
    /// to bring the home screen back instead of leaving the blank dashboard exposed underneath.
    var openPickerLaunchedFromHome: Bool = false

    static let shared = DashboardHomeScreenState()
}

extension Notification.Name {
    /// Posted when the app needs every open modal sheet dismissed immediately
    /// (used before showing the Quit/Close-Window save-changes alert, since a
    /// SwiftUI `.alert()` cannot be displayed on top of an active `.sheet()` on macOS).
    static let dashboardDismissBlockingModalsRequested = Notification.Name("Relay.DismissBlockingModalsRequested")
}

// MARK: - Module Plugin Protocol + Registry
protocol DashboardModulePlugin {
    static var kind: DashboardModuleKind { get }

    // Tile rendering (RootView has bindings, keep this)
    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView

    // Settings rendering (EditView can provide this)
    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView
}

/// Central registry to resolve a module kind -> plugin implementation.
/// Keeps RootView clean.
enum DashboardModuleRegistry {
    static func plugin(for kind: DashboardModuleKind) -> DashboardModulePlugin.Type? {
        switch kind {
        case .person:
            return PersonModulePlugin.self
        case .separator:
            return SeparatorModulePlugin.self
        case .pcoRundown:
            return PCOModulePlugin.self
        case .pcoTeamAssignments:
            return PCOTeamAssignmentsModulePlugin.self
        case .rosterTeamAssignments:
            return RosterTeamAssignmentsModulePlugin.self
        case .time:
            return TimeModulePlugin.self
        case .timecode:
            return TimecodeModulePlugin.self
        case .dawTransport:
            return DAWTransportModulePlugin.self
        case .rosterPicker:
            return RosterPickerModulePlugin.self
        case .text:
            return TextModulePlugin.self
        case .image:
            return ImageModulePlugin.self
        case .document:
            return DocumentModulePlugin.self
        case .ndi:
            return NDIModulePlugin.self
        case .webpage:
            return WebpageModulePlugin.self
        case .youtubeStreamMonitor:
            return YouTubeStreamMonitorModulePlugin.self
        case .shureWireless:
            return ShureWirelessModulePlugin.self
        case .shureOverview:
            return nil
        case .sennheiserWireless:
            return SennheiserWirelessModulePlugin.self
        case .proPresenter:
            return ProPresenterModulePlugin.self
        case .resolume:
            return ResolumeModulePlugin.self
        case .liveTranscription:
            return LiveTranscriptionModulePlugin.self
        case .dbReader:
            return DbReaderModulePlugin.self
        case .button:
            return ButtonModulePlugin.self
        case .rta:
            return RTAModulePlugin.self
        case .spectrograph:
            return SpectrogramModulePlugin.self
        }
    }
}

// MARK: - Legacy Kind Envelope for Backwards-Compatible Decoding

private struct LegacyKindEnvelope: Decodable {
    let type: String
}

// MARK: - Helper for tolerant decoding of arrays (skip bad elements)
private struct DiscardableDecodable: Decodable {}

// MARK: - Shared Text Formatting Types

/// Supported font weights for person tiles.
enum PersonFontWeight: String, CaseIterable, Identifiable, Codable {
    case thin, light, regular, medium, semibold, bold, heavy, black

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thin:     return "Thin"
        case .light:    return "Light"
        case .regular:  return "Regular"
        case .medium:   return "Medium"
        case .semibold: return "Semibold"
        case .bold:     return "Bold"
        case .heavy:    return "Heavy"
        case .black:    return "Black"
        }
    }

    var swiftUIFontWeight: Font.Weight {
        switch self {
        case .thin:     return .thin
        case .light:    return .light
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        case .heavy:    return .heavy
        case .black:    return .black
        }
    }
}

/// Capitalization options for person tile text.
enum TextCapitalizationStyle: String, CaseIterable, Identifiable, Codable {
    case normal, uppercase, lowercase, titlecase

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal:    return "Normal"
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titlecase: return "Title Case"
        }
    }
}

enum TextVerticalAlignmentStyle: String, CaseIterable, Identifiable, Codable, Equatable, Hashable {
    case top
    case center
    case bottom

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .center: return "arrow.up.and.down"
        case .bottom: return "arrow.down.to.line"
        }
    }
}

/// Codable wrapper around an sRGB color so we can persist user-selected text colors.
nonisolated struct CodableColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        #if os(macOS)
        let nsColor = NSColor(color)
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
        #elseif os(iOS)
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.red = Double(r)
            self.green = Double(g)
            self.blue = Double(b)
            self.alpha = Double(a)
        } else {
            // Fallback for non-RGB colors (e.g. grayscale / dynamic system colors)
            let cg = uiColor.cgColor
            let comps = cg.components ?? [1, 1, 1, 1]
            if comps.count >= 3 {
                self.red = Double(comps[0])
                self.green = Double(comps[1])
                self.blue = Double(comps[2])
                self.alpha = Double(comps.count >= 4 ? comps[3] : cg.alpha)
            } else if comps.count == 2 {
                self.red = Double(comps[0])
                self.green = Double(comps[0])
                self.blue = Double(comps[0])
                self.alpha = Double(comps[1])
            } else {
                self.red = 1.0
                self.green = 1.0
                self.blue = 1.0
                self.alpha = 1.0
            }
        }
        #else
        self.red = 1.0
        self.green = 1.0
        self.blue = 1.0
        self.alpha = 1.0
        #endif
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Tile-Level Text Formatting Environment

/// Where a module's title/header block is positioned within its tile.
enum TileHeaderPosition: String, CaseIterable, Identifiable, Codable {
    case top
    case bottom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}

/// Formatting applied to all text inside a dashboard tile.
struct TileTextFormatting {
    var fontSize: Double?
    var fontWeight: PersonFontWeight?
    var textColor: CodableColor?
    var capitalization: TextCapitalizationStyle?
    var justification: TextJustificationStyle?
    var verticalAlignment: TextVerticalAlignmentStyle?
    var headerPosition: TileHeaderPosition?
}

// Environment key to propagate the tile's corner radius down into module views.
private struct TileCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = 12
}

extension EnvironmentValues {
    var tileCornerRadius: CGFloat {
        get { self[TileCornerRadiusKey.self] }
        set { self[TileCornerRadiusKey.self] = newValue }
    }
}

private struct TileTextFormattingKey: EnvironmentKey {
    static let defaultValue: TileTextFormatting? = nil
}

extension EnvironmentValues {
    var tileTextFormatting: TileTextFormatting? {
        get { self[TileTextFormattingKey.self] }
        set { self[TileTextFormattingKey.self] = newValue }
    }
}

// MARK: - Tile Models

enum TileBackgroundStyle: String, CaseIterable, Identifiable, Codable {
    case system, blue, green, orange, red, purple, gray

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .blue:   return "Blue"
        case .green:  return "Green"
        case .orange: return "Orange"
        case .red:    return "Red"
        case .purple: return "Purple"
        case .gray:   return "Gray"
        }
    }

    var color: Color {
        switch self {
        case .system: return Color.black
        case .blue:   return Color.blue
        case .green:  return Color.green
        case .orange: return Color.orange
        case .red:    return Color.red
        case .purple: return Color.purple
        case .gray:   return Color.gray
        }
    }
}

/// Per-tile vertical (top → bottom) gradient background. When set on a tile,
/// it replaces the flat background color in the renderer.
struct TileGradientBackground: Codable, Equatable, Hashable {
    var startColor: CodableColor
    var endColor: CodableColor

    /// Default matches the dark blue → black look used by the NDI module.
    static let defaultGradient = TileGradientBackground(
        startColor: CodableColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
        endColor: CodableColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.28)
    )
}

enum TileModuleLayout: String, CaseIterable, Identifiable, Codable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vertical:
            return "Vertical"
        case .horizontal:
            return "Horizontal"
        }
    }
}

struct DashboardTileGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var color: CodableColor
    var tileIds: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        color: CodableColor,
        tileIds: [UUID]
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.tileIds = tileIds
    }
}

// MARK: - Dashboard Modules

enum DashboardModuleKind: Codable, Equatable {
    case person(PersonTileModel)
    case pcoRundown
    case pcoTeamAssignments
    case rosterTeamAssignments
    case shureWireless
    case shureOverview
    case sennheiserWireless
    case proPresenter
    case resolume(ResolumeModuleModel)
    case time
    case timecode
    case dawTransport
    case rosterPicker(RosterPickerModuleModel)
    case text(TextModuleModel)
    case image(ImageModuleModel)
    case document(DocumentModuleModel)
    case ndi(NDIModuleModel)
    case webpage(WebpageModuleModel)
    case youtubeStreamMonitor(YouTubeStreamMonitorModuleModel)
    case separator(SeparatorModuleModel)
    case liveTranscription(LiveTranscriptionModuleModel)
    case dbReader(DbReaderModuleModel)
    case button(ButtonModuleModel)
    case rta(RTAModuleModel)
    case spectrograph(SpectrogramModuleModel)
}

extension DashboardModuleKind {
    func duplicatedForCanvasCopy() -> DashboardModuleKind {
        switch self {
        case .button(var model):
            model.id = UUID()
            model.buttons = model.buttons.map { config in
                var updated = config
                updated.id = UUID()
                updated.actions = updated.actions.map { entry in
                    var newEntry = entry
                    newEntry.id = UUID()
                    return newEntry
                }
                return updated
            }
            return .button(model)
        default:
            return self
        }
    }

    var requiresPro: Bool {
        switch self {
        case .person, .text, .image, .document, .webpage, .time, .timecode, .separator, .pcoRundown, .pcoTeamAssignments, .rosterTeamAssignments, .rosterPicker:
            return false
        case .youtubeStreamMonitor:
            return true
        case .button:
            return true
        default:
            return true
        }
    }

    var isAvailableInCurrentBuild: Bool {
        switch self {
        case .shureOverview:
            #if DEBUG
            return true
            #else
            // Temporarily exposed in beta (optimized) builds to evaluate the
            // module's real-world cost after the persist/KVO + view-layer perf
            // fixes. Debug builds inflated its apparent cost ~3x. Revert this to
            // `false` if beta profiling shows it's still too heavy to ship.
            return WirelessLoggingPreferences.isBetaOrDebugBuild
            #endif
        default:
            return true
        }
    }

    var unavailableInCurrentBuildMessage: String {
        switch self {
        case .shureOverview:
            return "Shure Overview is available in debug and beta builds while its performance is being finalized."
        default:
            return "This module isn't available in this build."
        }
    }
}

extension DashboardModuleModel {
    var allowsInteractionLiveMode: Bool {
        switch kind {
        case .liveTranscription, .dbReader, .time, .dawTransport, .shureOverview:
            return true
        case .pcoRundown:
            return pcoConfig?.showLiveView == true || pcoConfig?.showTeamAssignments == true
        case .pcoTeamAssignments:
            return true
        case .rosterTeamAssignments:
            return true
        case .webpage(let model):
            return model.allowInteractionInLiveMode
        case .youtubeStreamMonitor(let model):
            return model.allowInteractionInLiveMode
        case .button:
            return true
        case .rta:
            return true
        case .spectrograph:
            return true
        default:
            return false
        }
    }
}

extension DashboardModuleKind {
    private enum CodingKeys: String, CodingKey {
        case type
        case person
        case rosterPicker
        case text
        case image
        case document
        case ndi
        case webpage
        case youtubeStreamMonitor
        case separator
        case resolume
        case liveTranscription
        case dbReader
        case button
        case rta
        case spectrograph
    }

    private enum KindType: String, Codable {
        case person
        case pcoRundown
        case pcoTeamAssignments
        case rosterTeamAssignments
        case shureWireless
        case shureOverview
        case sennheiserWireless
        case proPresenter
        case resolume
        case time
        case timecode
        case dawTransport
        case legacyProToolsTransport = "proToolsTransport"
        case rosterPicker
        case text
        case image
        case document
        case ndi
        case webpage
        case youtubeStreamMonitor
        case separator
        case liveTranscription
        case dbReader
        case button
        case rta
        case spectrograph
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)

        switch type {
        case .person:
            let person = try container.decode(PersonTileModel.self, forKey: .person)
            self = .person(person)
        case .pcoRundown:
            self = .pcoRundown
        case .pcoTeamAssignments:
            self = .pcoTeamAssignments
        case .rosterTeamAssignments:
            self = .rosterTeamAssignments
        case .shureWireless:
            self = .shureWireless
        case .shureOverview:
            self = .shureOverview
        case .sennheiserWireless:
            self = .sennheiserWireless
        case .proPresenter:
            self = .proPresenter
        case .resolume:
            let model = try container.decode(ResolumeModuleModel.self, forKey: .resolume)
            self = .resolume(model)
        case .time:
            self = .time
        case .timecode:
            self = .timecode
        case .dawTransport, .legacyProToolsTransport:
            self = .dawTransport
        case .rosterPicker:
            let pickerModel = try container.decode(RosterPickerModuleModel.self, forKey: .rosterPicker)
            self = .rosterPicker(pickerModel)
        case .text:
            let textModel = try container.decode(TextModuleModel.self, forKey: .text)
            self = .text(textModel)
        case .image:
            let imageModel = try container.decode(ImageModuleModel.self, forKey: .image)
            self = .image(imageModel)
        case .document:
            let documentModel = try container.decode(DocumentModuleModel.self, forKey: .document)
            self = .document(documentModel)
        case .ndi:
            let ndiModel = try container.decode(NDIModuleModel.self, forKey: .ndi)
            self = .ndi(ndiModel)
        case .webpage:
            let webpageModel = try container.decode(WebpageModuleModel.self, forKey: .webpage)
            self = .webpage(webpageModel)
        case .youtubeStreamMonitor:
            let model = try container.decode(YouTubeStreamMonitorModuleModel.self, forKey: .youtubeStreamMonitor)
            self = .youtubeStreamMonitor(model)
        case .separator:
            let model = try container.decode(SeparatorModuleModel.self, forKey: .separator)
            self = .separator(model)
        case .liveTranscription:
            let model = try container.decode(LiveTranscriptionModuleModel.self, forKey: .liveTranscription)
            self = .liveTranscription(model)
        case .dbReader:
            let model = try container.decode(DbReaderModuleModel.self, forKey: .dbReader)
            self = .dbReader(model)
        case .button:
            let model = try container.decode(ButtonModuleModel.self, forKey: .button)
            self = .button(model)
        case .rta:
            let model = try container.decode(RTAModuleModel.self, forKey: .rta)
            self = .rta(model)
        case .spectrograph:
            let model = try container.decode(SpectrogramModuleModel.self, forKey: .spectrograph)
            self = .spectrograph(model)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .person(let model):
            try container.encode(KindType.person, forKey: .type)
            try container.encode(model, forKey: .person)
        case .pcoRundown:
            try container.encode(KindType.pcoRundown, forKey: .type)
        case .pcoTeamAssignments:
            try container.encode(KindType.pcoTeamAssignments, forKey: .type)
        case .rosterTeamAssignments:
            try container.encode(KindType.rosterTeamAssignments, forKey: .type)
        case .shureWireless:
            try container.encode(KindType.shureWireless, forKey: .type)
        case .shureOverview:
            try container.encode(KindType.shureOverview, forKey: .type)
        case .sennheiserWireless:
            try container.encode(KindType.sennheiserWireless, forKey: .type)
        case .proPresenter:
            try container.encode(KindType.proPresenter, forKey: .type)
        case .time:
            try container.encode(KindType.time, forKey: .type)
        case .timecode:
            try container.encode(KindType.timecode, forKey: .type)
        case .dawTransport:
            try container.encode(KindType.dawTransport, forKey: .type)
        case .rosterPicker(let model):
            try container.encode(KindType.rosterPicker, forKey: .type)
            try container.encode(model, forKey: .rosterPicker)
        case .text(let model):
            try container.encode(KindType.text, forKey: .type)
            try container.encode(model, forKey: .text)
        case .image(let model):
            try container.encode(KindType.image, forKey: .type)
            try container.encode(model, forKey: .image)
        case .document(let model):
            try container.encode(KindType.document, forKey: .type)
            try container.encode(model, forKey: .document)
        case .ndi(let model):
            try container.encode(KindType.ndi, forKey: .type)
            try container.encode(model, forKey: .ndi)
        case .webpage(let model):
            try container.encode(KindType.webpage, forKey: .type)
            try container.encode(model, forKey: .webpage)
        case .youtubeStreamMonitor(let model):
            try container.encode(KindType.youtubeStreamMonitor, forKey: .type)
            try container.encode(model, forKey: .youtubeStreamMonitor)
        case .separator(let model):
            try container.encode(KindType.separator, forKey: .type)
            try container.encode(model, forKey: .separator)
        case .resolume(let model):
            try container.encode(KindType.resolume, forKey: .type)
            try container.encode(model, forKey: .resolume)
        case .liveTranscription(let model):
            try container.encode(KindType.liveTranscription, forKey: .type)
            try container.encode(model, forKey: .liveTranscription)
        case .dbReader(let model):
            try container.encode(KindType.dbReader, forKey: .type)
            try container.encode(model, forKey: .dbReader)
        case .button(let model):
            try container.encode(KindType.button, forKey: .type)
            try container.encode(model, forKey: .button)
        case .rta(let model):
            try container.encode(KindType.rta, forKey: .type)
            try container.encode(model, forKey: .rta)
        case .spectrograph(let model):
            try container.encode(KindType.spectrograph, forKey: .type)
            try container.encode(model, forKey: .spectrograph)
        }
    }
}

struct TimeModuleConfig: Codable, Equatable {
    var modeRaw: String = "clock"
    var countdownSeconds: Int = 300
    var autoStartCountdownInLiveMode: Bool = false
    var autoStartTimerInLiveMode: Bool = false
    var timerElapsedAlertThresholdSeconds: Int? = nil
    var timerElapsedAlertColor: CodableColor = CodableColor(red: 1, green: 0, blue: 0)
    var clockShowsDate: Bool = true
    var clockDateFormat: String = "EEE, MMM d"
    var clockTimeFormat: String = ""
    var showHeader: Bool = true

    private enum CodingKeys: String, CodingKey {
        case modeRaw
        case countdownSeconds
        case autoStartCountdownInLiveMode
        case autoStartTimerInLiveMode
        case timerElapsedAlertThresholdSeconds
        case timerElapsedAlertColor
        case clockShowsDate
        case clockDateFormat
        case clockTimeFormat
        case showHeader
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modeRaw = try container.decodeIfPresent(String.self, forKey: .modeRaw) ?? "clock"
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? 300
        autoStartCountdownInLiveMode = try container.decodeIfPresent(Bool.self, forKey: .autoStartCountdownInLiveMode) ?? false
        autoStartTimerInLiveMode = try container.decodeIfPresent(Bool.self, forKey: .autoStartTimerInLiveMode) ?? false
        timerElapsedAlertThresholdSeconds = try container.decodeIfPresent(Int.self, forKey: .timerElapsedAlertThresholdSeconds)
        timerElapsedAlertColor = try container.decodeIfPresent(CodableColor.self, forKey: .timerElapsedAlertColor) ?? CodableColor(red: 1, green: 0, blue: 0)
        clockShowsDate = try container.decodeIfPresent(Bool.self, forKey: .clockShowsDate) ?? true
        clockDateFormat = try container.decodeIfPresent(String.self, forKey: .clockDateFormat) ?? "EEE, MMM d"
        clockTimeFormat = try container.decodeIfPresent(String.self, forKey: .clockTimeFormat) ?? ""
        showHeader = try container.decodeIfPresent(Bool.self, forKey: .showHeader) ?? true
    }

    static func `default`() -> TimeModuleConfig {
        var config = TimeModuleConfig()
        let defaults = UserDefaults.standard

        if let mode = defaults.string(forKey: "time_module_mode"), mode != "timecode" {
            config.modeRaw = mode
        }
        if defaults.object(forKey: "time_module_countdown_seconds") != nil {
            config.countdownSeconds = defaults.integer(forKey: "time_module_countdown_seconds")
        }
        if defaults.object(forKey: "time_module_auto_start_countdown_live_mode") != nil {
            config.autoStartCountdownInLiveMode = defaults.bool(forKey: "time_module_auto_start_countdown_live_mode")
        }
        if defaults.object(forKey: "time_module_auto_start_timer_live_mode") != nil {
            config.autoStartTimerInLiveMode = defaults.bool(forKey: "time_module_auto_start_timer_live_mode")
        }
        if defaults.object(forKey: "time_module_timer_elapsed_alert_threshold_seconds") != nil {
            config.timerElapsedAlertThresholdSeconds = defaults.integer(forKey: "time_module_timer_elapsed_alert_threshold_seconds")
        }
        if defaults.object(forKey: "time_module_clock_show_date") != nil {
            config.clockShowsDate = defaults.bool(forKey: "time_module_clock_show_date")
        }
        if let dateFormat = defaults.string(forKey: "time_module_clock_date_format") {
            config.clockDateFormat = dateFormat
        }
        if let timeFormat = defaults.string(forKey: "time_module_clock_time_format") {
            config.clockTimeFormat = timeFormat
        }
        if defaults.object(forKey: "time_module_show_header") != nil {
            config.showHeader = defaults.bool(forKey: "time_module_show_header")
        }

        return config
    }
}

struct TimecodeModuleConfig: Codable, Equatable {
    var timecodeMIDISourceID: Int = -1
    var showHeader: Bool = true

    static func `default`() -> TimecodeModuleConfig {
        var config = TimecodeModuleConfig()
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "timecode_module_midi_source_id") != nil {
            config.timecodeMIDISourceID = defaults.integer(forKey: "timecode_module_midi_source_id")
        } else if defaults.object(forKey: "time_module_timecode_midi_source_id") != nil {
            config.timecodeMIDISourceID = defaults.integer(forKey: "time_module_timecode_midi_source_id")
        }

        if defaults.object(forKey: "timecode_module_show_header") != nil {
            config.showHeader = defaults.bool(forKey: "timecode_module_show_header")
        } else if defaults.object(forKey: "time_module_show_header") != nil {
            config.showHeader = defaults.bool(forKey: "time_module_show_header")
        }

        return config
    }
}

struct DashboardModuleModel: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: DashboardModuleKind
    /// Vertical ordering inside a tile (lower comes first).
    var order: Int

    /// Optional per-module configuration used by specific kinds (currently PCO).
    var pcoConfig: PCOModuleConfig? = nil
    var shureConfig: ShureModuleConfig? = nil
    var shureOverviewConfig: ShureOverviewModuleConfig? = nil
    var sennheiserConfig: SennheiserWirelessModuleConfig? = nil
    var proPresenterConfig: ProPresenterModuleConfig? = nil
    var resolumeConfig: ResolumeModuleConfig? = nil
    var timeConfig: TimeModuleConfig? = nil
    var timecodeConfig: TimecodeModuleConfig? = nil
    var dawTransportConfig: DAWTransportModuleConfiguration? = nil
    var rosterTeamAssignmentsConfig: RosterTeamAssignmentsConfig? = nil

    var paddingTop: CGFloat
    var paddingBottom: CGFloat
    var moduleScale: CGFloat? = nil // 1.0 = normal (nil treated as 1.0)
    var moduleHeightPoints: CGFloat? = nil // nil = Auto (uses flexible allocation)

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case order
        case pcoConfig
        case shureConfig
        case shureOverviewConfig
        case sennheiserConfig
        case proPresenterConfig
        case resolumeConfig
        case timeConfig
        case timecodeConfig
        case dawTransportConfig
        case legacyProToolsTransportConfig = "proToolsTransportConfig"
        case rosterTeamAssignmentsConfig
        case paddingTop
        case paddingBottom
        case moduleScale
        case moduleHeightPoints
    }

    init(
        kind: DashboardModuleKind,
        order: Int,
        id: UUID = UUID(),
        pcoConfig: PCOModuleConfig? = nil,
        shureConfig: ShureModuleConfig? = nil,
        shureOverviewConfig: ShureOverviewModuleConfig? = nil,
        sennheiserConfig: SennheiserWirelessModuleConfig? = nil,
        proPresenterConfig: ProPresenterModuleConfig? = nil,
        resolumeConfig: ResolumeModuleConfig? = nil,
        timeConfig: TimeModuleConfig? = nil,
        timecodeConfig: TimecodeModuleConfig? = nil,
        dawTransportConfig: DAWTransportModuleConfiguration? = nil,
        rosterTeamAssignmentsConfig: RosterTeamAssignmentsConfig? = nil,
        paddingTop: CGFloat = 0,
        paddingBottom: CGFloat = 0,
        moduleScale: CGFloat? = nil,
        moduleHeightPoints: CGFloat? = nil
    ) {
        self.id = id
        self.kind = kind
        self.order = order
        self.pcoConfig = pcoConfig
        self.shureConfig = shureConfig
        self.shureOverviewConfig = shureOverviewConfig
        self.sennheiserConfig = sennheiserConfig
        self.proPresenterConfig = proPresenterConfig
        self.resolumeConfig = resolumeConfig
        self.timeConfig = timeConfig
        self.timecodeConfig = timecodeConfig
        self.dawTransportConfig = dawTransportConfig
        self.rosterTeamAssignmentsConfig = rosterTeamAssignmentsConfig
        self.paddingTop = paddingTop
        self.paddingBottom = paddingBottom
        self.moduleScale = moduleScale
        self.moduleHeightPoints = moduleHeightPoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.kind = (try? container.decode(DashboardModuleKind.self, forKey: .kind)) ?? .time
        self.order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0

        self.pcoConfig = try container.decodeIfPresent(PCOModuleConfig.self, forKey: .pcoConfig)
        self.shureConfig = try container.decodeIfPresent(ShureModuleConfig.self, forKey: .shureConfig)
        self.shureOverviewConfig = try container.decodeIfPresent(ShureOverviewModuleConfig.self, forKey: .shureOverviewConfig)
        self.sennheiserConfig = try container.decodeIfPresent(SennheiserWirelessModuleConfig.self, forKey: .sennheiserConfig)
        self.proPresenterConfig = try container.decodeIfPresent(ProPresenterModuleConfig.self, forKey: .proPresenterConfig)
        self.resolumeConfig = try container.decodeIfPresent(ResolumeModuleConfig.self, forKey: .resolumeConfig)
        self.timeConfig = try container.decodeIfPresent(TimeModuleConfig.self, forKey: .timeConfig)
        self.timecodeConfig = try container.decodeIfPresent(TimecodeModuleConfig.self, forKey: .timecodeConfig)
        self.dawTransportConfig =
            try container.decodeIfPresent(DAWTransportModuleConfiguration.self, forKey: .dawTransportConfig)
            ?? container.decodeIfPresent(DAWTransportModuleConfiguration.self, forKey: .legacyProToolsTransportConfig)
        self.rosterTeamAssignmentsConfig = try container.decodeIfPresent(RosterTeamAssignmentsConfig.self, forKey: .rosterTeamAssignmentsConfig)

        self.paddingTop = try container.decodeIfPresent(CGFloat.self, forKey: .paddingTop) ?? 0
        self.paddingBottom = try container.decodeIfPresent(CGFloat.self, forKey: .paddingBottom) ?? 0
        self.moduleScale = try container.decodeIfPresent(CGFloat.self, forKey: .moduleScale)
        self.moduleHeightPoints = try container.decodeIfPresent(CGFloat.self, forKey: .moduleHeightPoints)

        if case .time = self.kind,
           let timeConfig = self.timeConfig,
           timeConfig.modeRaw == "timecode" {
            self.kind = .timecode
            var migrated = TimecodeModuleConfig.default()
            migrated.showHeader = timeConfig.showHeader
            self.timecodeConfig = migrated
            self.timeConfig = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(order, forKey: .order)
        try container.encodeIfPresent(pcoConfig, forKey: .pcoConfig)
        try container.encodeIfPresent(shureConfig, forKey: .shureConfig)
        try container.encodeIfPresent(shureOverviewConfig, forKey: .shureOverviewConfig)
        try container.encodeIfPresent(sennheiserConfig, forKey: .sennheiserConfig)
        try container.encodeIfPresent(proPresenterConfig, forKey: .proPresenterConfig)
        try container.encodeIfPresent(resolumeConfig, forKey: .resolumeConfig)
        try container.encodeIfPresent(timeConfig, forKey: .timeConfig)
        try container.encodeIfPresent(timecodeConfig, forKey: .timecodeConfig)
        try container.encodeIfPresent(dawTransportConfig, forKey: .dawTransportConfig)
        try container.encodeIfPresent(rosterTeamAssignmentsConfig, forKey: .rosterTeamAssignmentsConfig)
        try container.encode(paddingTop, forKey: .paddingTop)
        try container.encode(paddingBottom, forKey: .paddingBottom)
        try container.encodeIfPresent(moduleScale, forKey: .moduleScale)
        try container.encodeIfPresent(moduleHeightPoints, forKey: .moduleHeightPoints)
    }

    static func == (lhs: DashboardModuleModel, rhs: DashboardModuleModel) -> Bool {
        lhs.id == rhs.id
        && lhs.kind == rhs.kind
        && lhs.order == rhs.order
        && lhs.pcoConfig == rhs.pcoConfig
        && lhs.shureConfig == rhs.shureConfig
        && lhs.shureOverviewConfig == rhs.shureOverviewConfig
        && lhs.sennheiserConfig == rhs.sennheiserConfig
        && lhs.proPresenterConfig == rhs.proPresenterConfig
        && lhs.resolumeConfig == rhs.resolumeConfig
        && lhs.timeConfig == rhs.timeConfig
        && lhs.timecodeConfig == rhs.timecodeConfig
        && lhs.dawTransportConfig == rhs.dawTransportConfig
        && lhs.rosterTeamAssignmentsConfig == rhs.rosterTeamAssignmentsConfig
        && lhs.paddingTop == rhs.paddingTop
        && lhs.paddingBottom == rhs.paddingBottom
        && lhs.moduleScale == rhs.moduleScale
        && lhs.moduleHeightPoints == rhs.moduleHeightPoints
    }
}

extension DashboardModuleModel {
    mutating func updateLiveTranscriptionSource(at index: Int, transInputID: UUID) {
        guard case .liveTranscription(var model) = kind,
              model.sources.indices.contains(index) else { return }
        model.sources[index].transInputID = transInputID
        kind = .liveTranscription(model)
    }
}

// MARK: - Dashboard Tile Kind

enum DashboardTileKind: Codable, Equatable {
    case empty
    case person(PersonTileModel)
    case pcoPlaceholder
    case time
}

extension DashboardTileKind {
    private enum CodingKeys: String, CodingKey {
        case type
        case person
    }

    private enum KindType: String, Codable {
        case empty
        case person
        case pcoPlaceholder
        case time
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let type = try? container.decode(KindType.self, forKey: .type) {
            switch type {
            case .empty: self = .empty
            case .person:
                let person = try container.decode(PersonTileModel.self, forKey: .person)
                self = .person(person)
            case .pcoPlaceholder: self = .pcoPlaceholder
            case .time: self = .time
            }
            return
        }

        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            switch raw.lowercased() {
            case "empty": self = .empty
            case "time": self = .time
            case "pcoplaceholder", "pcorundown": self = .pcoPlaceholder
            default: self = .empty
            }
            return
        }

        let env = try LegacyKindEnvelope(from: decoder)
        switch env.type.lowercased() {
        case "empty": self = .empty
        case "time": self = .time
        case "pcoplaceholder", "pcorundown": self = .pcoPlaceholder
        default: self = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty:
            try container.encode(KindType.empty, forKey: .type)
        case .person(let model):
            try container.encode(KindType.person, forKey: .type)
            try container.encode(model, forKey: .person)
        case .pcoPlaceholder:
            try container.encode(KindType.pcoPlaceholder, forKey: .type)
        case .time:
            try container.encode(KindType.time, forKey: .type)
        }
    }
}

// MARK: - Dashboard Tile Model

struct DashboardTileModel: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String = ""
    var kind: DashboardTileKind

    /// Optional list of modules that make up this tile. When present and non-empty,
    /// the tile will render these modules instead of using the legacy `kind` switch.
    var modules: [DashboardModuleModel]? = nil

    /// Layout direction for modules inside this tile.
    var moduleLayout: TileModuleLayout = .vertical

    /// Offset from the center of the canvas, used for free-floating layout.
    var offset: CGSize

    /// Optional explicit size for the tile.
    var size: CGSize? = nil

    // Per-tile appearance
    var backgroundStyle: TileBackgroundStyle = .system
    var backgroundOpacity: Double = 1.0
    var cornerRadius: CGFloat = 12
    var backgroundCustomColor: CodableColor? = nil
    /// When non-nil, draws a top → bottom gradient instead of the flat
    /// background color/style. Opacity still applies on top of the gradient.
    var backgroundGradient: TileGradientBackground? = nil

    // Per-tile Shure Wireless channel selection
    var shureChannelSelection: ExternalDevicesStore.ShureSelectedChannel? = nil

    var shureShowDeviceName: Bool = true
    var shureShowChannelName: Bool = true
    var shureShowIPPort: Bool = true
    var shureShowFrequency: Bool = true
    var shureShowBattery: Bool = true
    var shureShowRFStrength: Bool = true

    var shureSelectedChannel: ExternalDevicesStore.ShureSelectedChannel? {
        get { shureChannelSelection }
        set { shureChannelSelection = newValue }
    }

    // Per-tile text formatting (applies to all modules in this tile)
    var textFontSize: Double? = nil
    var textFontWeight: PersonFontWeight? = nil
    var textColor: CodableColor? = nil
    var textCapitalization: TextCapitalizationStyle? = nil
    var textJustification: TextJustificationStyle? = nil
    var textVerticalAlignment: TextVerticalAlignmentStyle? = nil

    var showsTitle: Bool = false
    var isHidden: Bool
    var contentPadding: CGFloat?

    init(
        id: UUID = UUID(),
        name: String = "",
        kind: DashboardTileKind,
        modules: [DashboardModuleModel]? = nil,
        moduleLayout: TileModuleLayout = .vertical,
        offset: CGSize,
        size: CGSize? = nil,
        backgroundStyle: TileBackgroundStyle = .system,
        backgroundOpacity: Double = 1.0,
        cornerRadius: CGFloat = 12,
        backgroundCustomColor: CodableColor? = nil,
        backgroundGradient: TileGradientBackground? = nil,
        shureChannelSelection: ExternalDevicesStore.ShureSelectedChannel? = nil,
        shureShowDeviceName: Bool = true,
        shureShowChannelName: Bool = true,
        shureShowIPPort: Bool = true,
        shureShowFrequency: Bool = true,
        shureShowBattery: Bool = true,
        shureShowRFStrength: Bool = true,
        textFontSize: Double? = nil,
        textFontWeight: PersonFontWeight? = nil,
        textColor: CodableColor? = nil,
        textCapitalization: TextCapitalizationStyle? = nil,
        textJustification: TextJustificationStyle? = nil,
        textVerticalAlignment: TextVerticalAlignmentStyle? = nil,
        showsTitle: Bool = false,
        contentPadding: CGFloat? = 0,
        isHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.modules = modules
        self.moduleLayout = moduleLayout
        self.offset = offset
        self.size = size
        self.backgroundStyle = backgroundStyle
        self.backgroundOpacity = backgroundOpacity
        self.cornerRadius = cornerRadius
        self.backgroundCustomColor = backgroundCustomColor
        self.backgroundGradient = backgroundGradient
        self.shureChannelSelection = shureChannelSelection
        self.shureShowDeviceName = shureShowDeviceName
        self.shureShowChannelName = shureShowChannelName
        self.shureShowIPPort = shureShowIPPort
        self.shureShowFrequency = shureShowFrequency
        self.shureShowBattery = shureShowBattery
        self.shureShowRFStrength = shureShowRFStrength
        self.textFontSize = textFontSize
        self.textFontWeight = textFontWeight
        self.textColor = textColor
        self.textCapitalization = textCapitalization
        self.textJustification = textJustification
        self.textVerticalAlignment = textVerticalAlignment
        self.showsTitle = showsTitle
        self.contentPadding = contentPadding
        self.isHidden = isHidden
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case modules
        case moduleLayout
        case offset
        case size
        case backgroundStyle
        case backgroundOpacity
        case cornerRadius
        case backgroundCustomColor
        case backgroundGradient
        case shureChannelSelection
        case textFontSize
        case textFontWeight
        case textColor
        case textCapitalization
        case textJustification
        case textVerticalAlignment
        case showsTitle
        case contentPadding
        case isHidden
    }

    private static func decodeCGSize(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> CGSize {
        if let s = try? container.decode(CGSize.self, forKey: key) {
            return s
        }
        if let arr = try? container.decode([CGFloat].self, forKey: key), arr.count >= 2 {
            return CGSize(width: arr[0], height: arr[1])
        }
        if let arrD = try? container.decode([Double].self, forKey: key), arrD.count >= 2 {
            return CGSize(width: arrD[0], height: arrD[1])
        }
        return .zero
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.kind = try container.decode(DashboardTileKind.self, forKey: .kind)

        if let decodedModules = try? container.decodeIfPresent([DashboardModuleModel].self, forKey: .modules) {
            self.modules = decodedModules
        } else if container.contains(.modules) {
            if var modulesContainer = try? container.nestedUnkeyedContainer(forKey: .modules) {
                var recovered: [DashboardModuleModel] = []
                while !modulesContainer.isAtEnd {
                    if let m = try? modulesContainer.decode(DashboardModuleModel.self) {
                        recovered.append(m)
                    } else {
                        _ = try? modulesContainer.decode(DiscardableDecodable.self)
                    }
                }
                self.modules = recovered.isEmpty ? nil : recovered
            } else {
                self.modules = nil
            }
        } else {
            self.modules = nil
        }

        self.moduleLayout = try container.decodeIfPresent(TileModuleLayout.self, forKey: .moduleLayout) ?? .vertical

        self.offset = Self.decodeCGSize(container, forKey: .offset)

        if container.contains(.size) {
            let decoded = Self.decodeCGSize(container, forKey: .size)
            self.size = (decoded == .zero) ? nil : decoded
        } else {
            self.size = nil
        }

        self.backgroundStyle = try container.decodeIfPresent(TileBackgroundStyle.self, forKey: .backgroundStyle) ?? .system
        self.backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 1.0
        self.cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 12
        self.backgroundCustomColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundCustomColor)
        self.backgroundGradient = try container.decodeIfPresent(TileGradientBackground.self, forKey: .backgroundGradient)
        self.shureChannelSelection = try container.decodeIfPresent(ExternalDevicesStore.ShureSelectedChannel.self, forKey: .shureChannelSelection)

        self.textFontSize = try container.decodeIfPresent(Double.self, forKey: .textFontSize)
        self.textFontWeight = try container.decodeIfPresent(PersonFontWeight.self, forKey: .textFontWeight)
        self.textColor = try container.decodeIfPresent(CodableColor.self, forKey: .textColor)
        self.textCapitalization = try container.decodeIfPresent(TextCapitalizationStyle.self, forKey: .textCapitalization)
        self.textJustification = try container.decodeIfPresent(TextJustificationStyle.self, forKey: .textJustification)
        self.textVerticalAlignment = try container.decodeIfPresent(TextVerticalAlignmentStyle.self, forKey: .textVerticalAlignment)

        self.showsTitle = try container.decodeIfPresent(Bool.self, forKey: .showsTitle) ?? false
        self.contentPadding = try container.decodeIfPresent(CGFloat.self, forKey: .contentPadding)
        self.isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)

        var modulesToEncode = modules
        if (modulesToEncode?.isEmpty ?? true) {
            if case .person(let personModel) = kind {
                modulesToEncode = [DashboardModuleModel(kind: .person(personModel), order: 0)]
            }
        }
        try container.encodeIfPresent(modulesToEncode, forKey: .modules)
        try container.encode(moduleLayout, forKey: .moduleLayout)

        try container.encode(offset, forKey: .offset)
        try container.encodeIfPresent(size, forKey: .size)

        try container.encode(backgroundStyle, forKey: .backgroundStyle)
        try container.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(backgroundCustomColor, forKey: .backgroundCustomColor)
        try container.encodeIfPresent(backgroundGradient, forKey: .backgroundGradient)
        try container.encodeIfPresent(shureChannelSelection, forKey: .shureChannelSelection)

        try container.encodeIfPresent(textFontSize, forKey: .textFontSize)
        try container.encodeIfPresent(textFontWeight, forKey: .textFontWeight)
        try container.encodeIfPresent(textColor, forKey: .textColor)
        try container.encodeIfPresent(textCapitalization, forKey: .textCapitalization)
        try container.encodeIfPresent(textJustification, forKey: .textJustification)
        try container.encodeIfPresent(textVerticalAlignment, forKey: .textVerticalAlignment)

        try container.encode(showsTitle, forKey: .showsTitle)
        try container.encodeIfPresent(contentPadding, forKey: .contentPadding)
        try container.encode(isHidden, forKey: .isHidden)
    }
}

// MARK: - Button Trigger Auto-Mirroring

extension DashboardGraph {
    /// Group key used by canvas-backed Button trigger nodes.
    static let buttonTriggerGroupKey = "moduleGroup.button"

    /// True when the graph has meaningful user-built automation content.
    /// Tile layout positions alone don't count — only explicit links or added nodes.
    var hasAutomationContent: Bool {
        !links.isEmpty || !moduleGroupNodeInstances.isEmpty
    }
}

extension DashboardTab {
    @discardableResult
    mutating func ensureUniqueButtonModuleIDs() -> Bool {
        var seenButtonIDs: Set<UUID> = []
        var didChange = false

        tiles = tiles.map { tile in
            var updatedTile = tile
            guard let modules = tile.modules else { return updatedTile }

            updatedTile.modules = modules.map { module in
                var updatedModule = module
                guard case .button(var buttonModel) = updatedModule.kind else { return updatedModule }

                if seenButtonIDs.contains(buttonModel.id) {
                    buttonModel.id = UUID()
                    buttonModel.buttons = buttonModel.buttons.map { config in
                        var updatedConfig = config
                        updatedConfig.id = UUID()
                        updatedConfig.actions = updatedConfig.actions.map { entry in
                            var e = entry; e.id = UUID(); return e
                        }
                        return updatedConfig
                    }
                    didChange = true
                }

                seenButtonIDs.insert(buttonModel.id)
                updatedModule.kind = .button(buttonModel)
                return updatedModule
            }

            return updatedTile
        }

        return didChange
    }

    /// Auto-mirrors canvas Button modules into the per-tab graph as trigger nodes.
    /// Each Button module's wrapper id becomes a `ModuleGroupNodeInstance` with the same
    /// id and groupKey == "moduleGroup.button". Orphans (nodes whose source module no
    /// longer exists, or whose module kind changed away from `.button`) are removed.
    @discardableResult
    mutating func reconcileButtonTriggerNodes() -> Bool {
        let normalizedDuplicateIDs = ensureUniqueButtonModuleIDs()
        let buttonModuleIds = currentButtonModuleIds()

        if buttonModuleIds.isEmpty {
            guard var g = graph else { return false }
            let beforeCount = g.moduleGroupNodeInstances.count
            g.moduleGroupNodeInstances.removeAll { $0.groupKey == DashboardGraph.buttonTriggerGroupKey }
            let changed = g.moduleGroupNodeInstances.count != beforeCount
            if changed { graph = g }
            return normalizedDuplicateIDs || changed
        }

        if graph == nil { graph = DashboardGraph() }
        guard var g = graph else { return false }

        var changed = false

        let beforeCount = g.moduleGroupNodeInstances.count
        g.moduleGroupNodeInstances.removeAll { node in
            node.groupKey == DashboardGraph.buttonTriggerGroupKey && !buttonModuleIds.contains(node.id)
        }
        if g.moduleGroupNodeInstances.count != beforeCount { changed = true }

        let existingButtonNodeIds = Set(
            g.moduleGroupNodeInstances
                .filter { $0.groupKey == DashboardGraph.buttonTriggerGroupKey }
                .map(\.id)
        )

        for moduleId in buttonModuleIds where !existingButtonNodeIds.contains(moduleId) {
            g.moduleGroupNodeInstances.append(
                DashboardGraph.ModuleGroupNodeInstance(id: moduleId, groupKey: DashboardGraph.buttonTriggerGroupKey)
            )
            if g.tileLayouts[moduleId] == nil {
                let seed = abs(moduleId.hashValue)
                let dy = CGFloat(seed % 520) - 260
                let position = CGPoint(x: -200, y: 200 + dy)
                g.tileLayouts[moduleId] = TileGraphLayout(position: position)
            }
            changed = true
        }

        if changed { graph = g }
        return normalizedDuplicateIDs || changed
    }

    private func currentButtonModuleIds() -> Set<UUID> {
        var ids: Set<UUID> = []
        for tile in tiles {
            guard let modules = tile.modules else { continue }
            for module in modules {
                if case .button(let buttonModel) = module.kind {
                    ids.insert(buttonModel.id)
                }
            }
        }
        return ids
    }
}
