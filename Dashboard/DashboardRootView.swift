//
//  DashboardRootView.swift
//  Relay
//
//  Created by David Bullard on 11/16/25.
//


import SwiftUI
import UniformTypeIdentifiers
import OSLog
import Combine
import CryptoKit
import ImageIO
import Network

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

// Breaks deep @ViewBuilder call chains on iOS (512KB stack limit).
private struct LazyView<Content: View>: View {
    let build: () -> Content
    var body: some View { build() }
}

enum LiveModeChromeAutoHidePolicy {
    static func shouldHide(isHovering: Bool, isInteracting: Bool, respectsHover: Bool) -> Bool {
        guard !isInteracting else { return false }
        guard !respectsHover || !isHovering else { return false }
        return true
    }

    static func shouldPauseScheduledHideForHover(respectsHover: Bool) -> Bool {
        respectsHover
    }
}

// MARK: - Root Dashboard View

struct DashboardRootView: View {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    private static let log = Logger(subsystem: "Relay", category: "PCO")
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    @AppStorage("Relay.iPadAutoHideToolbarEnabled") private var iPadAutoHideToolbarEnabled: Bool = false

    
#endif

   

    // MARK: - iPad sizing helpers
#if os(iOS)
    private var isIPadRegularWidth: Bool { isIPad && (horizontalSizeClass != .compact) }

    /// Slightly tighter on iPad so it feels closer to macOS density.
    private var iPadUIScale: CGFloat { isIPadRegularWidth ? 0.9 : 1.0 }

    /// Panel widths tuned for iPad.
    private var overviewPanelWidth: CGFloat { isIPadRegularWidth ? 220 : 240 }
    private var inspectorPanelWidth: CGFloat { isIPadRegularWidth ? 380 : 420 }

    /// Default tile size tuned for iPad.
    private var defaultTileSize: CGSize {
        let base = CGSize(width: 260, height: 200)
        return CGSize(width: base.width * iPadUIScale, height: base.height * iPadUIScale)
    }
#else
    private let overviewPanelWidth: CGFloat = 240
    private let inspectorPanelWidth: CGFloat = 380
    private let defaultTileSize: CGSize = CGSize(width: 260, height: 200)
#endif
    
    private var selectedTabGuides: [CanvasGuide] {
        guard tabs.indices.contains(selectedTabIndex) else { return [] }
        return tabs[selectedTabIndex].guides
    }

    private var selectedTabGuidesBindingSafe: Binding<[CanvasGuide]>? {
        guard tabs.indices.contains(selectedTabIndex) else { return nil }
        return $tabs[selectedTabIndex].guides
    }

    private func mutateSelectedTabGuides(_ mutation: (inout [CanvasGuide]) -> Void) {
        guard tabs.indices.contains(selectedTabIndex) else { return }
        mutation(&tabs[selectedTabIndex].guides)
    }
    @State private var draggingGuideID: UUID? = nil
    @StateObject private var canvasBoundsStore = DashboardCanvasBoundsStore()
    @StateObject private var tutorialController = DashboardTutorialController()
    @StateObject private var onboardingWizardController = OnboardingWizardController()
    @StateObject private var pcoAutoAdvanceCoordinator = PCOAutoAdvanceCoordinator()
    /// Owns tile drag/resize interaction state so both `DashboardTileCanvas` and
    /// the selection action toolbar can read it (the toolbar needs live drag
    /// deltas to track a tile in real time instead of only after it commits).
    ///
    /// `@State`, not `@StateObject`: `DashboardTileInteractionSession` is
    /// `@Observable`, not `ObservableObject`. `@State` is still the correct
    /// wrapper for the true owner of an `@Observable` reference type (it's
    /// what keeps the instance alive across this view's re-renders); it's
    /// only the *injection* sites downstream (`DashboardTileCanvas`,
    /// `DashboardTileContainer`, `DashboardSelectionActionToolbarHost`, ...)
    /// that take it as a plain `let`. This root body deliberately does not
    /// read any of the session's per-frame gesture properties directly --
    /// that read is isolated in `DashboardSelectionActionToolbarHost` below,
    /// so a drag frame does not invalidate this ~10k-line body.
    @State private var interactionSession = DashboardTileInteractionSession()
    /// Stable, reference-identity home for `DashboardTileCanvas`/`DashboardTileContainer`'s
    /// action closures. Plain `@State` (not `@StateObject`) because
    /// `DashboardCanvasActionCoordinator` isn't `ObservableObject` -- it only needs a
    /// stable reference across re-renders, which `@State` already guarantees for a
    /// reference type. Its closures are reassigned every render via `configureCanvasActions`.
    @State private var canvasActions = DashboardCanvasActionCoordinator()
    @AppStorage("dashboard_tutorial_seen") private var tutorialSeen: Bool = false
    @AppStorage("dashboard_automation_tutorial_seen") private var automationTutorialSeen: Bool = false
    @AppStorage("dashboard_automation_preview_seen") private var automationPreviewSeen: Bool = false
    @EnvironmentObject var saveState: DashboardSaveState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
#if os(macOS)
    @EnvironmentObject private var licenseCoordinator: LicenseCoordinator
#endif
    @State private var tabs: [DashboardTab]
    @State private var universalGraph: DashboardGraph? = nil
    @State private var sharedRosters: [DashboardRoster]
    @State private var selectedTabIndex: Int = 0
    @State private var needsInitialTileCentering: Bool
    @State private var draggingLocalTabID: UUID? = nil
    @State private var isDraggingTilesOnCanvas: Bool = false
    @State private var isPostTileDragViewportOverrideActive: Bool = false
    @State private var isWebpageViewportBypassActive: Bool = false
    @State private var webpageViewportBypassModuleID: UUID? = nil
    @State private var postTileDragViewportOverrideWorkItem: DispatchWorkItem? = nil
    @State private var didPushUndoForCurrentTileNudge: Bool = false
    @State private var tileNudgeResetTask: Task<Void, Never>? = nil
    @State private var pendingImportReferenceCanvasSize: CGSize? = nil
    @State private var didApplyImportDeviceFitScale: Bool = false
    @State private var isReplacingDocumentState: Bool = false
    @State private var isLoadingDashboardFile: Bool = false
    @State private var suppressUnsavedChangesUntil: Date = .distantPast
    @AppStorage("dashboard_live_mode_enabled")
    private var isLiveMode: Bool = false
    @AppStorage("dashboard_live_mode_canvas_behavior")
    private var liveModeCanvasBehaviorRaw: String = LiveModeCanvasBehavior.fitToScreen.rawValue
    @AppStorage("dashboard_live_mode_window_behavior")
    private var liveModeWindowBehaviorRaw: String = LiveModeWindowBehavior.keepCurrentSize.rawValue
    private var liveModeCanvasBehavior: LiveModeCanvasBehavior {
        LiveModeCanvasBehavior(rawValue: liveModeCanvasBehaviorRaw) ?? .fitToScreen
    }
    private var liveModeWindowBehavior: LiveModeWindowBehavior {
        LiveModeWindowBehavior(rawValue: liveModeWindowBehaviorRaw) ?? .keepCurrentSize
    }
    @State private var didEnterFullScreenForLiveMode: Bool = false
    @State private var liveModeReloadToken: UUID = UUID()
    @State private var isLiveModeChromeVisible: Bool = false
    @State private var isHoveringLiveModeChrome: Bool = false
    @State private var isLiveModeChromeInteracting: Bool = false
    @State private var liveModeChromeDragProgress: CGFloat = 1
    @State private var liveModeChromeRevealWorkItem: DispatchWorkItem? = nil
    @State private var liveModeChromeHideWorkItem: DispatchWorkItem? = nil
    @State private var liveModeChromeHideRespectsHover: Bool = true
    @AppStorage("dashboard_show_guides_enabled")
    private var showGuidesEnabled: Bool = true
    @AppStorage("dashboard_view_mode")
    private var dashboardViewMode: String = "canvas"
    @AppStorage("dashboard_show_system_usage")
    private var showSystemUsage: Bool = false
    @AppStorage("relay.graph.forceDetailedNodeRendering")
    private var forceDetailedNodeRendering: Bool = false
    @State private var showGraphPerformanceNoticeDetails: Bool = false
    @AppStorage("dashboard_file_autosave_enabled")
    private var fileAutosaveEnabled: Bool = true
    @State private var isTextInputActive: Bool = false
    @State private var modeBannerText: String? = nil
    @State private var modeBannerSubtitle: String? = nil
    @State private var modeBannerVisible: Bool = false
    @State private var activeNotificationBanner: DashboardNotificationBanner? = nil

    private var shouldBlockDelete: Bool {
        if isLiveMode { return true }
        if !isTextInputActive { return false }
        #if os(macOS)
        if let responder = NSApp.keyWindow?.firstResponder {
            if responder is NSTextView { return true }
            if responder is NSTextField { return true }
        }
        return false
        #else
        return true
        #endif
    }
    private var liveModeChromeHotZoneWidth: CGFloat {
        #if os(iOS)
        isIPad ? 260 : 0
        #else
        260
        #endif
    }
    private let liveModeChromeRevealDelay: Double = 0.12
    private let liveModeChromeAutoHideDelay: Double = 2.8
    private let liveModeChromeDragRevealDistance: CGFloat = 50
    @State private var notificationDismissWorkItem: DispatchWorkItem? = nil
    @State private var isPCORefreshing: Bool = false
    @State private var isShowingNewDashboardAlert = false
    @State private var isShowingNewDashboardSizePrompt: Bool = false
    @State private var dashboardCanvasSizePromptPurpose: DashboardCanvasBoundsStore.Purpose = .newDashboard
    @State private var pendingCanvasSizeTabIndex: Int? = nil
    @State private var isShowingCanvasResizeScaleAlert: Bool = false
    @State private var pendingCanvasResize: PendingCanvasResize? = nil
#if os(macOS)
    @State private var escapeKeyMonitor: Any? = nil
#endif
    /// Debounced work item for saving tabs to persistent storage.
    @State private var pendingTabsSaveWorkItem: DispatchWorkItem?
    @State private var autosaveEditGeneration: Int = 0
    private enum DashboardLayoutMode: String {
        case canvas
        case graph
    }

    private enum TileGroupSheetMode {
        case create
        case edit
    }

    private struct PendingCanvasResize: Equatable {
        let oldSize: CGSize
        let newSize: CGSize
        let purpose: DashboardCanvasBoundsStore.Purpose
    }

    private enum PendingDocumentContinuation: Equatable {
        case openPicker
        case openSpecific(URL)
        case newDashboard
        case closeWindow
        case quitApplication
    }

    @State private var showExternalDevicesSettingsSheet = false
    @State private var externalDevicesInitialSelection: ExternalDeviceConfig.ID? = nil
    @State private var externalDevicesEntryMode: ExternalDevicesSettingsView.EntryMode = .full
    @State private var layoutMode: DashboardLayoutMode = .canvas
    @State private var canvasViewportPan: CGSize = .zero
    @State private var canvasViewportZoom: CGFloat = 1.0
    @State private var isViewportGestureActive: Bool = false
    @State private var canvasViewportPanBeforeLive: CGSize = .zero
    @State private var canvasViewportZoomBeforeLive: CGFloat = 1.0
    @State private var isTabInteractionActive: Bool = false
    @State private var canvasViewportSize: CGSize = .zero
    @State private var needsInitialViewportFit: Bool = true
    @State private var lastObservedScheduleActivationKey: String? = nil
    
    init(
        initialTabs: [DashboardTab]? = nil,
        initialSelectedTabIndex: Int? = nil
    ) {
        // Start with an untitled dashboard unless the app was launched with
        // an explicit file open request.
        var loadedTabs: [DashboardTab]
        var loadedRosters: [DashboardRoster] = []
        var usedBuiltinDefault = false

        if initialTabs == nil {
            Self.clearLegacyDashboardRestorationState()
        }
        
        if let explicit = initialTabs {
            loadedTabs = explicit
        } else {
            usedBuiltinDefault = true
            loadedTabs = [
                DashboardTab(
                    name: "Tab 1",
                    tiles: [],
                    planID: nil,
                    planTitle: nil,
                    serviceTimeName: nil
                )
            ]
        }
        
        for i in loadedTabs.indices {
            loadedTabs[i].reconcileButtonTriggerNodes()
        }

        let migrationResult = Self.migrateLegacyRosters(tabs: loadedTabs, rosters: loadedRosters)
        loadedTabs = Self.migrateTranscriptionInputs(tabs: migrationResult.tabs)
        loadedRosters = migrationResult.rosters

        _tabs = State(initialValue: loadedTabs)
        _sharedRosters = State(initialValue: loadedRosters)
        _needsInitialTileCentering = State(initialValue: usedBuiltinDefault)
        _lastSavedURL = State(initialValue: nil)
        _restoredCanvasSizeFromDocument = State(initialValue: nil)
        _restoredWorkingDocumentCandidate = State(initialValue: nil)
        _dashboardFileErrorMessage = State(initialValue: nil)
        
        let restoredSelectedTabIndex: Int? = nil
        let initialIndex = initialSelectedTabIndex ?? restoredSelectedTabIndex ?? 0
        let clampedIndex = loadedTabs.isEmpty
        ? 0
        : min(max(initialIndex, 0), loadedTabs.count - 1)
        
        _selectedTabIndex = State(initialValue: clampedIndex)
    }
    /// True when graph layout is active (and not LAN mirroring).
    private var isGraphLayoutActive: Bool {
        layoutMode == .graph && selectedLANShareId == nil
    }
    /// Single source of truth for document size (Photoshop-style artboard).
    private var canvasSize: CGSize {
        guard tabs.indices.contains(selectedTabIndex) else { return canvasBoundsStore.size }
        return tabs[selectedTabIndex].canvasSize ?? canvasBoundsStore.size
    }


    private static let graphModeChangedNotification = Notification.Name("Relay.GraphModeChanged")
    @State private var showingSettings = false
    @State private var showingRosters = false
    @State private var showingKeyboardShortcuts = false
    @State private var showingPCOConfigForTab = false
    @State private var settingsInitialSelection: DashboardSettingsInitialSelection = .general
    @State private var renamingTabIndex: Int? = nil
    @State private var showingProUpgrade: Bool = false
    @State private var showingProUpgradePrompt: Bool = false
    @State private var showingProUpgradePromptTask: Task<Void, Never>? = nil

    @State private var isAddMenuOpen: Bool = false
    
#if os(iOS)
@State private var isCanvasMenuPresented: Bool = false
@State private var canvasMenuLocation: CGPoint = .zero
#endif
    
    @AppStorage("dashboard_snap_to_grid_enabled")
    private var snapToGridEnabled: Bool = false
    @AppStorage("dashboard_show_grid_enabled")
    private var showGridEnabled: Bool = true
    @AppStorage("dashboard_gridSize") private var gridSizeSetting: Double = 20.0
    @AppStorage("dashboard_allowTileOverlap") private var allowTileOverlap: Bool = true
    @AppStorage("dashboard_personImageFolder") private var personImageFolder: String = ""
    @State private var editingTileID: UUID? = nil
    @State private var lastEditedTileID: UUID?
    @State private var isInspectorVisible: Bool = false
    @State private var pendingModuleCatalogTileID: UUID? = nil
    @State private var pendingFirstModuleSelectTileID: UUID? = nil
    @State private var isTileOverviewVisible: Bool = false
    
    // Multi-selection support
    @State private var selectedTileIDs: Set<UUID> = []
    @State private var selectedGraphNodeCount: Int = 0
    @State private var overviewSelectionAnchorID: UUID?
    @State private var selectionStartPoint: CGPoint? = nil
    @State private var selectionCurrentPoint: CGPoint? = nil
    @State private var selectionSource: TileSelectionSource = .canvas
    @State private var groupSelectionColor: Color? = nil
    @State private var showingTileGroupSheet: Bool = false
    @State private var tileGroupSheetMode: TileGroupSheetMode = .create
    @State private var editingTileGroupID: UUID? = nil
    @State private var editingTileGroupTileIDs: Set<UUID> = []
    @State private var tileGroupName: String = ""
    @State private var tileGroupColor: Color = .blue
    
    @State private var isExportingDashboard = false
    @State private var isImportingDashboard = false
    @State private var isExportingLogs = false
    @State private var isPreparingLogExport = false
    @State private var logArchiveDocument = RelayLogArchiveDocument(data: Data())
    @State private var dashboardDocument = DashboardDocument(tabs: [], rosters: [], selectedTabIndex: 0)
    @State private var dashboardFileErrorMessage: String?
    @State private var logExportErrorMessage: String?
    @State private var freeImportWarningMessage: String?
    @StateObject private var documentController = DashboardDocumentController.shared
    
    // Tracks the last URL this dashboard was saved to or loaded from
    @State private var lastSavedURL: URL? = nil
    @State private var restoredCanvasSizeFromDocument: CGSize? = nil
    @State private var restoredWorkingDocumentCandidate: RestoredWorkingDocument? = nil
    @State private var didApplyRestoredDocumentState: Bool = false
    @State private var isDocumentWriteInProgress: Bool = false
    
    @AppStorage("autosave_announcement_shown_v1") private var autosaveAnnouncementShown: Bool = false
    @AppStorage("automationScopePrimerShown") private var automationScopePrimerShown: Bool = false
    @State private var showingAutosaveAnnouncement: Bool = false
    @State private var showSwitchToUniversalConfirmation: Bool = false
    @State private var pendingSharedSwitchTabID: UUID? = nil
    @State private var pendingSharedSwitchHasExistingShared: Bool = false
    @State private var showingOpenUnsavedAlert: Bool = false
    @State private var showingBookmarkRestoreFailedBanner: Bool = false
    @State private var showingCloseUnsavedAlert: Bool = false
    @State private var showingQuitUnsavedAlert: Bool = false
    @State private var pendingDocumentContinuation: PendingDocumentContinuation? = nil
    @StateObject private var windowCloseCoordinator = DashboardWindowCloseCoordinator()
    
    @Environment(\.undoManager) private var systemUndoManager
    @State private var undoBridge = DashboardUndoBridge()
    
    // MARK: - LAN Shared Tabs
    @StateObject private var lanService = LANSharedTabsService()
    // Debounced work for advertising shared tabs over LAN
    @State private var lanShareUpdateTask: Task<Void, Never>? = nil
    @State private var syncedTabPushTask: Task<Void, Never>? = nil
    @State private var syncedTabPushIsActive: Bool = false  // true while a push is in-flight
    @State private var lastSyncedContentHashByGroupID: [String: String] = [:]
    @State private var localEditCountsByGroupID: [String: Int] = [:]
    @State private var orphanedBannerGroupID: String? = nil
    @State private var pendingApprovalRequestId: String? = nil
    // Tracks a pairing request the user locally dismissed (Cancel, or swipe-to-dismiss
    // on iOS) while it's still in flight on the service side. activePairingRequest is
    // owned entirely by LANSharedTabsService and only cleared when the handshake
    // resolves (approved/denied/30s timeout), so dismissing the overlay needs its own
    // local flag rather than mutating service state.
    @State private var dismissedActivePairingRequest: LANSharedTabsService.OutgoingPairingRequest? = nil
    // MARK: Pairing sheet (unified)
    // A single device is routinely both a host (needs the approval sheet for an
    // incoming request) and a joiner (needs the waiting overlay for its own outgoing
    // request) at once — e.g. hosting a Synced Tab while importing someone else's
    // Mirror. Two independent .sheet(isPresented:) modifiers can't safely coexist
    // (SwiftUI only presents one at a time from a given chain, so the second one to
    // become "presented" would silently fail to show). This enum + one .sheet(item:)
    // makes presentation single-sourced: only one pairing sheet can ever be requested
    // at a time, and approval (needs a decision) takes priority over waiting (passive
    // status) when both are pending.
    private enum PairingSheetKind: Identifiable {
        case approval(PendingPairingRequest)
        case waiting(LANSharedTabsService.OutgoingPairingRequest)

        var id: String {
            switch self {
            case .approval(let request): return "approval-\(request.id)"
            case .waiting(let request): return "waiting-\(request.peerDeviceName)-\(request.reason)"
            }
        }
    }
    @State private var lastSyncedEditingTileID: UUID? = nil
    @State private var lastSyncedEditingGroupID: String? = nil
    @State private var presencePushTask: Task<Void, Never>? = nil
    @State private var lanMirrorRefreshTask: Task<Void, Never>? = nil
    @State private var lanRenderUpdateTask: Task<Void, Never>? = nil
    @State private var lanRenderCursor: Int = 0
    @State private var selectedLANShareId: String? = nil
    @State private var selectedLANDeviceName: String? = nil
    @State private var selectedLANPeerEndpointKey: String? = nil
    @State private var lanMirrorTab: DashboardTab = DashboardTab(name: "LAN", tiles: [])
    @State private var lanMirrorReferenceCanvasSize: CGSize? = nil
    @State private var lanMirrorScale: CGFloat = 1.0
    @State private var lanRenderImage: CGImage? = nil
    @State private var lanImportErrorMessage: String? = nil
    @State private var showLostLANAlert: Bool = false
    @State private var lostLANDeviceName: String = "LAN device"
    @State private var pendingImportScaleTabIDs: Set<UUID>? = nil
    // MARK: - LAN Import (Replace / Merge)

    private enum LANImportMode {
        case addNewTab
    }

    @State private var showingLANImportDialog: Bool = false
    @State private var pendingLANImportManifest: LANSharedTabManifest? = nil

    // MARK: - File Import External Devices (Replace / Merge)
    private enum ExternalDevicesImportMode {
        case replace
        case merge
        case skip
    }

    @State private var showingExternalDevicesImportDialog: Bool = false
    @State private var pendingImportedExternalDevicesSnapshot: ExternalDevicesStore.Snapshot? = nil
    @State private var pendingImportedSettingsSnapshot: DashboardSettingsSnapshot? = nil
    @State private var pendingImportedLANSettingsBundle: LANSharedTabImportBundle? = nil

    // MARK: - Graph Snapshots
    @State private var graphTilesSnapshot: [DashboardTileModel] = []
    @State private var rundownTitlesSnapshot: [String] = []
    
    // MARK: - Persistence Storage Key
    private static let storageKey = "dashboard_tabs_v1"
    private static let workingDocumentBookmarkKey = "dashboard_working_document_bookmark_v1"

    private struct RestoredWorkingDocument {
        let url: URL
        let payload: DashboardDocument.Payload
    }

    private static func clearLegacyDashboardRestorationState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: workingDocumentBookmarkKey)
    }

    private struct RosterMigrationResult {
        var tabs: [DashboardTab]
        var rosters: [DashboardRoster]
    }

    private static func syncLegacyRosterFields(
        tabs: [DashboardTab],
        rosters: [DashboardRoster]
    ) -> [DashboardTab] {
        tabs.map { tab in
            var copy = tab
            guard let rosterID = copy.defaultGeneralRosterID,
                  let roster = rosters.first(where: { $0.id == rosterID }) else {
                return copy
            }

            copy.rosterColumns = roster.columns
            copy.rosterRows = roster.rows
            return copy
        }
    }

    private static func uniqueMigratedRosterName(for tabName: String, existingNames: Set<String>) -> String {
        let trimmed = tabName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Roster" : "\(trimmed) Roster"
        guard existingNames.contains(base) else { return base }

        var suffix = 2
        while existingNames.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private static func migrateLegacyRosters(
        tabs: [DashboardTab],
        rosters: [DashboardRoster]
    ) -> RosterMigrationResult {
        var updatedTabs = tabs
        var updatedRosters = rosters

        for index in updatedTabs.indices {
            var tab = updatedTabs[index]
            var attachedIDs = Set(tab.attachedRosterIDs)

            if tab.defaultGeneralRosterID == nil, tab.hasRosterData {
                let migrated = DashboardRoster(
                    name: uniqueMigratedRosterName(
                        for: tab.name,
                        existingNames: Set(updatedRosters.map(\.name))
                    ),
                    kind: .general,
                    columns: tab.rosterColumns,
                    rows: tab.rosterRows
                )
                updatedRosters.append(migrated)
                tab.defaultGeneralRosterID = migrated.id
                attachedIDs.insert(migrated.id)
            }

            if let id = tab.defaultGeneralRosterID, updatedRosters.contains(where: { $0.id == id }) {
                attachedIDs.insert(id)
            }
            if let id = tab.defaultEquipmentRosterID, updatedRosters.contains(where: { $0.id == id }) {
                attachedIDs.insert(id)
            }
            if let id = tab.defaultPeopleRosterID, updatedRosters.contains(where: { $0.id == id }) {
                attachedIDs.insert(id)
            }

            tab.attachedRosterIDs = Array(attachedIDs)
            updatedTabs[index] = tab
        }

        updatedTabs = syncLegacyRosterFields(tabs: updatedTabs, rosters: updatedRosters)
        return RosterMigrationResult(tabs: updatedTabs, rosters: updatedRosters)
    }

    // MARK: - Transcription Inputs Migration

    private static let transcriptionMigrationFlagKey = "relay_transcription_inputs_migrated_v2"

    static func migrateTranscriptionInputs(tabs: [DashboardTab]) -> [DashboardTab] {
        guard !UserDefaults.standard.bool(forKey: transcriptionMigrationFlagKey) else {
            return tabs
        }
        UserDefaults.standard.set(true, forKey: transcriptionMigrationFlagKey)

        // Collect all LiveTranscriptionSourceConfig instances across all tiles
        var allSources: [(tabIndex: Int, tileIndex: Int, moduleIndex: Int, sourceIndex: Int, source: LiveTranscriptionSourceConfig)] = []
        for (ti, tab) in tabs.enumerated() {
            for (li, tile) in tab.tiles.enumerated() {
                guard let modules = tile.modules else { continue }
                for (mi, module) in modules.enumerated() {
                    guard case .liveTranscription(let model) = module.kind else { continue }
                    for (si, source) in model.sources.enumerated() {
                        allSources.append((ti, li, mi, si, source))
                    }
                }
            }
        }

        // Build deduplicated map: (deviceUID, channelIndex) -> TranscriptionInputConfig
        var configByKey: [String: TranscriptionInputConfig] = [:]
        for entry in allSources {
            let source = entry.source
            let key = "\(source.deviceUID ?? "default"):\(source.channelIndex)"
            if configByKey[key] == nil {
                let config = TranscriptionInputConfig(
                    name: source.displayName.isEmpty ? "Input \(configByKey.count + 1)" : source.displayName,
                    deviceUID: source.deviceUID,
                    channelIndex: source.channelIndex,
                    color: source.color
                )
                configByKey[key] = config
            }
        }

        // Register configs in the global store
        let store = TranscriptionInputsConfigStore.shared
        for config in configByKey.values {
            if store.input(for: config.id) == nil {
                store.inputs.append(config)
            }
        }
        store.forcePersist()

        // Write transInputID back into each source
        var updatedTabs = tabs
        for entry in allSources {
            let source = entry.source
            let key = "\(source.deviceUID ?? "default"):\(source.channelIndex)"
            guard let config = configByKey[key] else { continue }
            updatedTabs[entry.tabIndex].tiles[entry.tileIndex].modules?[entry.moduleIndex]
                .updateLiveTranscriptionSource(at: entry.sourceIndex, transInputID: config.id)
        }
        return updatedTabs
    }


var body: some View {
    GeometryReader { proxy in
        let base = rootBaseView(proxy: proxy)
        let upgradeAction = {
            if showingSettings {
                showingSettings = false
            }
            if showingRosters {
                showingRosters = false
            }
            if showExternalDevicesSettingsSheet {
                showExternalDevicesSettingsSheet = false
            }
            if showingPCOConfigForTab {
                showingPCOConfigForTab = false
            }
            // Note: this delayed presentation isn't covered by
            // dismissBlockingModalsForTermination()'s synchronous flag-clearing — if Cmd+Q
            // lands in the ~0.2s window between this dispatch and it firing, the upgrade
            // prompt can still appear after a save-prompt alert is already showing. Narrow,
            // pre-existing timing quirk of this upgrade flow, not fixed here.
            showingProUpgradePromptTask?.cancel()
            showingProUpgradePromptTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                showingProUpgradePrompt = true
            }
        }
        withRootHandlers(base, proxy: proxy)
            .environment(\.dashboardIsPCOConfigOpen, showingPCOConfigForTab)
            .environment(\.dashboardIsWebpageViewportBypassActive, isWebpageViewportBypassActive)
            .environment(\.dashboardSetWebpageViewportBypass, { moduleID, isActive in
                isWebpageViewportBypassActive = isActive
                webpageViewportBypassModuleID = isActive ? moduleID : nil
            })
            .environment(\.proUpgradeAction, upgradeAction)
            .environment(\.joinSyncedTabAction, { manifest in joinSyncedTab(manifest) })
            .environment(\.leaveSyncedTabAction, { groupID in
                guard let index = tabs.firstIndex(where: { $0.syncGroupID == groupID }) else { return }
                stopSyncingTab(at: index)
            })
            .coordinateSpace(.named("tutorialRoot"))
            .allowsHitTesting(!tutorialController.isPresented)
            .overlayPreferenceValue(TutorialAnchorPreferenceKey.self) { anchors in
                DashboardTutorialOverlay(
                    controller: tutorialController,
                    anchors: anchors,
                    lanSharingEnabled: lanHostingAllowed,
                    onUpgradeRequested: upgradeAction,
                    onOnboardingWizardRequested: { onboardingWizardController.start(hasPro: subscriptionManager.hasPro) }
                )
            }
            .alert("Connection Lost", isPresented: $showLostLANAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Lost connection to \(lostLANDeviceName)")
            }
            .sheet(isPresented: $showingProUpgrade) {
#if os(macOS)
                if RelayLicensingConfig.isDirectMacDistribution {
                    LicensingGateView(showsStatusView: false)
                } else {
                    ProUpgradeView()
                }
#else
                ProUpgradeView()
#endif
            }
            .sheet(isPresented: $showingProUpgradePrompt) {
                ZStack {
                    Color.black.ignoresSafeArea()
#if os(iOS)
                    ProUpgradePromptViewIOS(
                        buttonTitle: "Upgrade to Pro",
                        secondaryButtonTitle: "Continue with Free",
                        secondaryAction: {
                            showingProUpgradePrompt = false
                        },
                        animateOnAppear: true,
                        showPlanSelector: true,
                        showManageLinks: true
                    ) {
                        showingProUpgradePrompt = false
                    }
#else
                    if RelayLicensingConfig.isDirectMacDistribution {
                        LicensingGateView(showsStatusView: false)
                    } else {
                        ProUpgradePromptView(
                            buttonTitle: "Upgrade to Pro",
                            secondaryButtonTitle: "Continue with Free",
                            secondaryAction: {
                                showingProUpgradePrompt = false
                            },
                            animateOnAppear: true,
                            showPlanSelector: true,
                            showManageLinks: true
                        ) {
                            showingProUpgradePrompt = false
                        }
                    }
#endif
                }
            }
    }
    .onAppear {
        applyRestoredDocumentStateIfNeeded()
        reconcileJoinedSyncGroupIDs()
        centerInitialTileIfNeeded()
    }
    .onDisappear {
        showingProUpgradePromptTask?.cancel()
        tileNudgeResetTask?.cancel()
    }
    .onReceive(documentController.$pendingRequest.compactMap { $0 }) { request in
        handleDocumentControllerRequest(request)
    }
    .onReceive(NotificationCenter.default.publisher(for: .prodlinkStartTutorial)) { _ in
        let hasPro = subscriptionManager.hasPro
        if layoutMode == .graph {
            if hasPro {
                tutorialController.start(kind: .proAutomation, hasPro: true)
                automationTutorialSeen = true
            } else {
                tutorialController.start(kind: .lockedAutomationPreview, hasPro: false)
                automationPreviewSeen = true
            }
        } else {
            let kind: DashboardTutorialKind = hasPro ? .proCanvas : .freeCanvas
            tutorialController.start(kind: kind, hasPro: hasPro)
            tutorialSeen = true
        }
    }
#if os(macOS)
.onExitCommand {
    if tutorialController.isPresented {
        tutorialController.stop()
    }
}
.onChange(of: tutorialController.isPresented, initial: false) { _, isPresented in
    updateEscapeKeyMonitor(isActive: isPresented)
}
.background(
    DeleteKeyCatcher(
        isTutorialPresented: tutorialController.isPresented,
        onTutorialArrow: { direction in
            switch direction {
            case .left:
                tutorialController.back()
            case .right:
                tutorialController.next()
            default:
                break
            }
        },
        onTutorialEscape: {
            tutorialController.stop()
        },
        onDelete: {
            guard !shouldBlockDelete else { return }
            deleteSelectedTiles()
        },
        onSelectAll: {
            guard layoutMode == .canvas else { return }
            guard selectedLANShareId == nil else { return }
            selectAllTiles()
        },
        onArrowKey: { direction, modifiers in
            if tutorialController.isPresented {
                switch direction {
                case .left:
                    tutorialController.back()
                case .right:
                    tutorialController.next()
                default:
                    break
                }
                return
            }
            guard !isTextInputActive else { return }
            guard !isLiveMode else { return }
            guard !selectedTileIDs.isEmpty else { return }

            let step: CGFloat
            if modifiers.contains(.option) {
                let grid = CGFloat(gridSizeSetting)
                step = grid > 0 ? grid : 1
            } else if modifiers.contains(.shift) {
                step = 10
            } else {
                step = 1
            }

            let translation: CGSize
            switch direction {
            case .left:
                translation = CGSize(width: -step, height: 0)
            case .right:
                translation = CGSize(width: step, height: 0)
            case .up:
                translation = CGSize(width: 0, height: -step)
            case .down:
                translation = CGSize(width: 0, height: step)
            }

            let didMove = nudgeSelectedTiles(translation: translation) {
                if !didPushUndoForCurrentTileNudge {
                    pushUndoSnapshot("Nudge Tiles")
                    didPushUndoForCurrentTileNudge = true
                }
            }

            guard didMove else { return }

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()

            tileNudgeResetTask?.cancel()
            tileNudgeResetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                didPushUndoForCurrentTileNudge = false
            }
        },
        isTextInputActive: isTextInputActive
    )
    .frame(width: 0, height: 0)
)
.background(
    WindowCloseInterceptor(
        coordinator: windowCloseCoordinator,
        shouldInterceptClose: { saveState.hasUnsavedChanges && !isDefaultBlankDocument },
        onAttemptClose: { window in
            windowCloseCoordinator.markPendingClose(window: window)
            requestCloseWindow()
        }
    )
    .frame(width: 0, height: 0)
)
.background(
    WindowCloseButtonRetargeter(onCloseButtonClicked: { window in
        windowCloseCoordinator.markPendingClose(window: window)
        requestCloseWindow()
    })
    .frame(width: 0, height: 0)
)
#endif
}

    // MARK: - Root Body Extraction (compile-time type-check helper)

    @ViewBuilder
    private func rootBaseView(proxy: GeometryProxy) -> some View {
        let base = ZStack(alignment: .topLeading) {
            // Ensure any uncovered areas (e.g. behind rounded sidebar corners) are black,
            // not the default window background gray.
            Color.black
                .ignoresSafeArea()
            if isLoadingDashboardFile {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isReplacingDocumentState {
                // Base layout: left overview + main canvas
                HStack(spacing: 0) {
                    // Left-side tile overview sidebar
                    if isTileOverviewVisible,
                       let overviewTab = selectedTabSafe {
                        let overviewTabID = overviewTab.id
                        DashboardTileOverviewSidebar(
                            tab: overviewTab,
                            selectedTileIDs: $selectedTileIDs,
                            onSelectionChanged: { newSelection in
                                overviewSelectionAnchorID = newSelection.first
                                if newSelection.isEmpty {
                                    selectionSource = .canvas
                                    groupSelectionColor = nil
                                } else if selectionSource != .overviewGroup {
                                    selectionSource = .overviewTiles
                                    groupSelectionColor = nil
                                }

                                if isInspectorVisible {
                                    if newSelection.isEmpty {
                                        editingTileID = nil
                                        isInspectorVisible = false
                                    } else if let first = newSelection.first {
                                        editingTileID = first
                                    }
                                }
                            },
                            onRenameTile: { tileID, newName in
                                guard let tabIndex = DashboardTabIdentityMutation.index(of: overviewTabID, in: tabs),
                                      var tile = tabs[tabIndex].tiles.first(where: { $0.id == tileID }) else {
                                    RelayDiagnosticsStore.shared.incrementCounter("ui.overview.renameTile.rejected")
                                    return
                                }

                                pushUndoSnapshot("Rename Tile")
                                tile.name = newName
                                DashboardTabIdentityMutation.replaceTile(tile, tabID: overviewTabID, tileID: tileID, in: &tabs)
                                saveState.hasUnsavedChanges = true
                                scheduleTabsSaveDebounced()
                            },
                            onUpdateTileSize: { tileID, newSize in
                                pushUndoSnapshot("Resize Tile")
                                guard let tabIndex = DashboardTabIdentityMutation.index(of: overviewTabID, in: tabs),
                                      var tile = tabs[tabIndex].tiles.first(where: { $0.id == tileID }) else {
                                    RelayDiagnosticsStore.shared.incrementCounter("ui.overview.resizeTile.rejected")
                                    return
                                }

                                tile.size = newSize
                                DashboardTabIdentityMutation.replaceTile(tile, tabID: overviewTabID, tileID: tileID, in: &tabs)
                                saveState.hasUnsavedChanges = true
                                scheduleTabsSaveDebounced()
                            },
                            onToggleTileVisibility: { tileID, isHidden in
                                guard let tabIndex = DashboardTabIdentityMutation.index(of: overviewTabID, in: tabs),
                                      var tile = tabs[tabIndex].tiles.first(where: { $0.id == tileID }) else {
                                    RelayDiagnosticsStore.shared.incrementCounter("ui.overview.toggleTileVisibility.rejected")
                                    return
                                }

                                tile.isHidden = isHidden
                                DashboardTabIdentityMutation.replaceTile(tile, tabID: overviewTabID, tileID: tileID, in: &tabs)

                                if isHidden {
                                    selectedTileIDs.remove(tileID)
                                    if editingTileID == tileID {
                                        editingTileID = nil
                                        isInspectorVisible = false
                                    }
                                }

                                saveState.hasUnsavedChanges = true
                                scheduleTabsSaveDebounced()
                                updateHiddenTilesFlag()
                            },
                            onReorderTiles: { indices, newOffset in
                                guard let tabIndex = DashboardTabIdentityMutation.index(of: overviewTabID, in: tabs) else {
                                    RelayDiagnosticsStore.shared.incrementCounter("ui.overview.reorderTiles.rejected")
                                    return
                                }
                                tabs[tabIndex].tiles.move(fromOffsets: indices, toOffset: newOffset)
                                scheduleTabsSaveDebounced()
                            },
                            onEditGroup: { group in
                                beginEditTileGroup(group)
                            },
                            onDeleteGroup: { group in
                                deleteTileGroup(id: group.id)
                            },
                            onGroupSelected: { group in
                                selectionSource = .overviewGroup
                                groupSelectionColor = group.color.swiftUIColor
                            },
                            onCollapseSidebar: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    isTileOverviewVisible = false
                                }
                            }
                        )
                        .frame(width: overviewPanelWidth)
                        .background(Color.black)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    LazyView { self.mainCenterAndInspector(proxy: proxy) }
                }

                if !isLiveMode,
                   isInspectorVisible,
                   let tileBinding = bindingForEditingTile(),
                   tabs.indices.contains(selectedTabIndex) {

                    let inspectorTopInset: CGFloat = {
    #if os(iOS)
                        if isIPad {
                            return proxy.safeAreaInsets.top + 48
                        }
                        return 10
    #else
                        return 10
    #endif
                    }()

                    let inspectorBottomInset: CGFloat = {
    #if os(iOS)
                        return isIPad ? 6 : 10
    #else
                        return 10
    #endif
                    }()
                    let inspectorTrailingInset: CGFloat = {
    #if os(iOS)
                        return isIPad ? 2 : 14
    #else
                        return 14
    #endif
                    }()

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            inspectorView(for: tileBinding)
                                .frame(
                                    maxHeight: max(0, proxy.size.height - inspectorTopInset - inspectorBottomInset),
                                    alignment: .top
                                )
                                .padding(.trailing, inspectorTrailingInset)
                                .contentShape(Rectangle())
                                .allowsHitTesting(true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, inspectorTopInset)
                    .padding(.bottom, inspectorBottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .trailing))
                    #if os(iOS)
                    .preferredColorScheme(.dark)
                    #endif
                }
            }

        }
        .contentShape(Rectangle())

        base
    }

    private func withRootHandlers<Content: View>(_ content: Content, proxy: GeometryProxy) -> some View {
        let a = withLANHandlers(content)
        let b = withModeAndCanvasHandlers(a)
        let c = withSheets(b)
        let d = withPCOHandlers(c)
        let e = withLayoutModeHandlers(d)
        let f = withGraphSnapshotHandlers(e)
        return f
            .autoHideCursorInLiveMode(isLiveMode)
            .animation(.easeInOut(duration: 0.25), value: isInspectorVisible)
            .onAppear {
                let hasUnsavedBinding = Binding<Bool>(
                    get: { saveState.hasUnsavedChanges },
                    set: { saveState.hasUnsavedChanges = $0 }
                )
                undoBridge.bind(
                    tabs: $tabs,
                    selectedTabIndex: $selectedTabIndex,
                    hasUnsavedChanges: hasUnsavedBinding
                )

                logDashboardSummary(tabs, context: "App launch")
                updateShureModulePresence()
                refreshOSCListeningConfiguration()
            }
            .onChange(of: tabs, initial: false) { _, _ in
                updateShureModulePresence()
                refreshOSCListeningConfiguration()
            }
            .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.notify)) { note in
                let ui = note.userInfo ?? [:]
                let title = (ui[ActionNodeUserInfoKeys.title] as? String) ?? "Automation"
                let message = (ui[ActionNodeUserInfoKeys.message] as? String) ?? ""
                let duration = (ui[ActionNodeUserInfoKeys.durationSeconds] as? Double)
                    ?? (ui[ActionNodeUserInfoKeys.durationSeconds] as? NSNumber)?.doubleValue
                    ?? 3.0

                presentNotification(title: title, message: message, durationSeconds: duration)
            }
            .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.lanNotify)) { note in
                guard subscriptionManager.hasPro else { return }

                let ui = note.userInfo ?? [:]
                let title = (ui[ActionNodeUserInfoKeys.title] as? String) ?? "Automation"
                let message = (ui[ActionNodeUserInfoKeys.message] as? String) ?? ""
                let duration = (ui[ActionNodeUserInfoKeys.durationSeconds] as? Double)
                    ?? (ui[ActionNodeUserInfoKeys.durationSeconds] as? NSNumber)?.doubleValue
                    ?? 3.0
                let targetMode = (ui[ActionNodeUserInfoKeys.targetMode] as? String)
                    .flatMap(DashboardGraph.LANNotifyActionConfig.TargetMode.init(rawValue:))
                    ?? .allPeers
                let peerDeviceId = (ui[ActionNodeUserInfoKeys.peerDeviceId] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let peers: [LANSharedTabsService.Peer]
                switch targetMode {
                case .allPeers:
                    peers = lanService.peers.filter { lanService.isPeerEnabled($0) }
                case .specificPeer:
                    peers = lanService.peers.filter {
                        lanService.isPeerEnabled($0) && $0.matchesSavedTarget(peerDeviceId)
                    }
                case .allHTTPViewers:
                    peers = []
                case .allPeersAndHTTPViewers:
                    peers = lanService.peers.filter { lanService.isPeerEnabled($0) }
                }

                #if os(macOS)
                let sourceDeviceName = Host.current().localizedName ?? "Relay"
                #else
                let sourceDeviceName = UIDevice.current.name
                #endif

                let payload = LANPeerNotificationRequest(
                    title: title,
                    message: message,
                    durationSeconds: duration,
                    sourceDeviceId: UserDefaults.standard.string(forKey: "prodlink.deviceId") ?? "",
                    sourceDeviceName: sourceDeviceName
                )

                Task {
                    if targetMode == .allHTTPViewers || targetMode == .allPeersAndHTTPViewers {
                        await MainActor.run {
                            lanService.postBrowserViewerNotification(
                                title: title,
                                message: message,
                                durationSeconds: duration
                            )
                        }
                    }

                    for peer in peers {
                        do {
                            try await lanService.sendPeerNotification(payload, to: peer)
                        } catch {
                            #if DEBUG
                            print("❌ LAN notification failed for \(peer.endpointKey): \(error.localizedDescription)")
                            #endif
                        }
                    }
                }
            }
    }

    // MARK: - Root Handler Extraction (compile-time type-check helper)

    private func withLANHandlers<Content: View>(_ content: Content) -> some View {
        content
            .task {
                lanService.setHostingAllowed(lanHostingAllowed)
                lanService.setDiscoveryAllowed(lanDiscoveryAllowed)
                updateLANBrowserViewSelection()
                lanService.start()
                updateLANPollingState()
                updateLANSharedTabs()
                updateSyncedTabs()
                startLANRenderUpdateLoop()
                if layoutMode != .graph {
                    startLANMirrorRefreshLoop()
                }
            }
            .onChange(of: lanHostingAllowed, initial: false) { _, enabled in
                lanService.setHostingAllowed(enabled)
                lanService.start()
                updateLANPollingState()
                updateLANSharedTabs()
                updateSyncedTabs()
                startLANRenderUpdateLoop()
            }
            .onChange(of: lanBrowserServingAllowed, initial: false) { _, _ in
                updateLANBrowserViewSelection()
                lanService.start()
                updateLANSharedTabs()
                startLANRenderUpdateLoop()
            }
            .onChange(of: lanDiscoveryAllowed, initial: false) { _, enabled in
                lanService.setDiscoveryAllowed(enabled)
                updateLANPollingState()
            }
            .onChange(of: tabs, initial: false) { _, _ in
                reconcileJoinedSyncGroupIDs()
                processSyncedTabRevisions()
                updateSyncedTabs()

                saveState.hasUnsavedChanges = true

                RelayDiagnosticsStore.shared.update(tabs: tabs)
                updateLANBrowserViewSelection()

                // 🚫 Do NOT push LAN updates while user is interacting with tabs (rename, drag, etc.)
                guard !isDraggingTilesOnCanvas else { return }
                guard !isTabInteractionActive else { return }

                scheduleLANShareUpdateDebounced()
                scheduleSyncedTabPushDebounced()
            }
            .onChange(of: tabs.map(\.id), initial: false) {
                print("⚠️ tabs array replaced")
                updateLANBrowserViewSelection()
            }
            .onChange(of: selectedTabIndex, initial: false) { _, _ in
                updateLANBrowserViewSelection()
            }
            .onDisappear {
                lanShareUpdateTask?.cancel()
                lanShareUpdateTask = nil
                lanRenderUpdateTask?.cancel()
                lanRenderUpdateTask = nil
                lanService.stop()
                lanMirrorRefreshTask?.cancel()
                lanMirrorRefreshTask = nil
                draggingLocalTabID = nil
            }
            .onChange(of: canvasBoundsStore.size, initial: false) { _, newValue in
                recomputeLANMirrorScale()
            }
            .onChange(of: lanMirrorReferenceCanvasSize, initial: false) { _, newValue in
                recomputeLANMirrorScale()
            }
            .onChange(of: selectedLANShareId, initial: false) { _, newId in
                guard let newId else {
                    lanMirrorReferenceCanvasSize = nil
                    lanMirrorScale = 1.0
                    lanRenderImage = nil
                    lanRenderUpdateTask?.cancel()
                    lanRenderUpdateTask = nil
                    updateLANPollingState()
                    return
                }
                if let manifest = lanService.remoteTabs.first(where: { $0.shareId == newId }) {
                    lanMirrorReferenceCanvasSize = manifest.referenceCanvasSize
                } else {
                    lanMirrorReferenceCanvasSize = nil
                }
                recomputeLANMirrorScale()
                startLANRenderUpdateLoop()
                updateLANPollingState()
                if isLANMirrorTabActive {
                    Task { await refreshLANRenderOnce() }
                }
            }
            .onChange(of: lanService.pendingSyncedSnapshots.count, initial: false) { _, count in
                guard count > 0 else { return }
                applyIncomingSyncedSnapshots()
            }
            .onChange(of: lanService.hostStoppedGroupIDs, initial: false) { _, stopped in
                // Host explicitly stopped syncing — always show the banner so subscriber is aware,
                // even if they haven't made any local edits.
                for groupID in stopped {
                    guard orphanedBannerGroupID == nil else { continue }
                    guard tabs.contains(where: { $0.syncGroupID == groupID }) else { continue }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        orphanedBannerGroupID = groupID
                    }
                }
            }
            // Queueing relies on approvePairingRequest/denyPairingRequest removing their entry
            // from pendingPairingRequests — that mutation re-fires this onChange, and since
            // pendingApprovalRequestId is cleared in the same button action, the guard below
            // then passes and surfaces the next queued device's request automatically.
            //
            // A request can ALSO be resolved by a completely different path — the Settings
            // Devices-table toggle (setDeviceEnabled) — which removes it from
            // pendingPairingRequests without going through the sheet's own onApprove/onDeny.
            // If pendingApprovalRequestId still points at that now-vanished request, it must
            // be cleared here too, or it permanently blocks the guard below from ever
            // surfacing a future request.
            .onChange(of: lanService.pendingPairingRequests, initial: false) { _, newRequests in
                if let currentId = pendingApprovalRequestId, !newRequests.contains(where: { $0.id == currentId }) {
                    pendingApprovalRequestId = nil
                }
                guard pendingApprovalRequestId == nil, let first = newRequests.first else { return }
                pendingApprovalRequestId = first.id
            }
            .onChange(of: lanService.activePairingRequest, initial: false) { _, newValue in
                // Clear the local dismissal once the outstanding request resolves, so a
                // future request — even one that happens to equal the dismissed one
                // (same peer/reason) — isn't mistakenly hidden as already-dismissed.
                if newValue == nil {
                    dismissedActivePairingRequest = nil
                }
            }
            .onChange(of: lanService.orphanedSyncGroupIDs, initial: false) { old, newOrphaned in
                LinkedComputerPersonVariableStore.shared.update(
                    tabs: tabs,
                    disconnectedGroupIDs: newOrphaned.union(lanService.hostStoppedGroupIDs),
                    computerNamesByDeviceID: linkedComputerNamesByDeviceID
                )
                // Newly orphaned groups — always show banner so subscriber can decide to keep or remove.
                for groupID in newOrphaned.subtracting(old) {
                    guard orphanedBannerGroupID == nil else { continue }
                    // Skip if already handled by hostStopped observer.
                    guard !lanService.hostStoppedGroupIDs.contains(groupID) else { continue }
                    guard tabs.contains(where: { $0.syncGroupID == groupID }) else { continue }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        orphanedBannerGroupID = groupID
                    }
                }
            }
            .onChange(of: lanService.hostStoppedGroupIDs, initial: false) { _, stoppedGroups in
                LinkedComputerPersonVariableStore.shared.update(
                    tabs: tabs,
                    disconnectedGroupIDs: lanService.orphanedSyncGroupIDs.union(stoppedGroups),
                    computerNamesByDeviceID: linkedComputerNamesByDeviceID
                )
            }
            .onChange(of: lanService.peers, initial: false) { _, _ in
                LinkedComputerPersonVariableStore.shared.update(
                    tabs: tabs,
                    disconnectedGroupIDs: lanService.orphanedSyncGroupIDs.union(lanService.hostStoppedGroupIDs),
                    computerNamesByDeviceID: linkedComputerNamesByDeviceID
                )
            }
            // Missed-push recovery: if the host is advertising an older version than we have locally,
            // our last push didn't reach them (network blip). Re-schedule the push.
            .onChange(of: lanService.peerVersionsForJoinedGroups, initial: false) { _, hostVersions in
                var needsPush = false
                for (groupID, hostVersion) in hostVersions {
                    guard let tabIndex = tabs.firstIndex(where: { $0.syncGroupID == groupID && !$0.syncIsOwner }) else { continue }
                    let tab = tabs[tabIndex]
                    let localVersion = SyncedTabVersion(
                        revision: tab.syncRevision,
                        editedAt: tab.syncLastEditedAt,
                        editedByDeviceID: tab.syncLastEditedByDeviceID
                    )
                    if localVersion > hostVersion {
                        needsPush = true
                    }
                }
                if needsPush {
                    // Bypass the 0.6s debounce for retries — the poll already waited ~1s
                    // and we don't want to add another delay on top.
                    syncedTabPushTask?.cancel()
                    let tabsSnapshot = tabs
                    syncedTabPushTask = Task {
                        await pushSyncedTabs(tabsSnapshot)
                    }
                }
            }
            .onChange(of: lanService.reconnectedSyncGroupIDs, initial: false) { _, reconnected in
                for groupID in reconnected {
                    guard tabs.contains(where: { $0.syncGroupID == groupID && !$0.syncIsOwner }) else { continue }
                    lanService.clearReconnectSignal(for: groupID)
                    // Dismiss orphan banner if it was showing for this group.
                    if orphanedBannerGroupID == groupID {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            orphanedBannerGroupID = nil
                        }
                    }
                    // Force-fetch host's authoritative snapshot and apply it regardless of LWW.
                    Task { @MainActor in
                        guard let snapshot = await lanService.fetchSyncedTabSnapshot(groupID: groupID) else { return }
                        forceApplyHostSnapshot(snapshot)
                    }
                }
            }
            .onChange(of: lanService.remoteTabs.map(\.shareId), initial: false) { _, newIds in
                if let selected = selectedLANShareId, !newIds.contains(selected) {
                    lostLANDeviceName = selectedLANDeviceName ?? "LAN device"
                    showLostLANAlert = true
                    selectedLANShareId = nil
                    selectedLANDeviceName = nil
                }
                if tabs.indices.contains(selectedTabIndex),
                   let shareId = tabs[selectedTabIndex].lanMirrorShareId,
                   !newIds.contains(shareId) {
                    lostLANDeviceName = tabs[selectedTabIndex].lanMirrorDeviceName
                        ?? selectedLANDeviceName
                        ?? "LAN device"
                    showLostLANAlert = true
                    jumpToNearestLocalTab(from: selectedTabIndex)
                }
            }
        
    }

    private func withModeAndCanvasHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: subscriptionManager.hasPro, initial: false) { _, hasPro in
                guard !hasPro else { return }
                if layoutMode == .graph {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layoutMode = .canvas
                        dashboardViewMode = "canvas"
                    }
                }
            }
            .onChange(of: isLiveMode, initial: false) { _, newValue in
                NotificationCenter.default.post(
                    name: .relayLiveModeDidChange,
                    object: nil,
                    userInfo: ["isLiveMode": newValue]
                )
                liveModeChromeRevealWorkItem?.cancel()
                liveModeChromeRevealWorkItem = nil
                liveModeChromeHideWorkItem?.cancel()
                liveModeChromeHideWorkItem = nil
                isHoveringLiveModeChrome = false
                isLiveModeChromeInteracting = false
                isLiveModeChromeVisible = false
                liveModeReloadToken = UUID()
                lastObservedScheduleActivationKey = nil
                if newValue {
                    disableWebpageViewportBypass()
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    if newValue {
                        isInspectorVisible = false
                        isTileOverviewVisible = false
                        editingTileID = nil
                        overviewSelectionAnchorID = nil
                    }

                    let caption = newValue ? "Live Mode" : "Edit Mode"
                    modeBannerText = caption
                    modeBannerSubtitle = nil
                    modeBannerVisible = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if modeBannerText == caption {
                            modeBannerVisible = false
                        }
                    }
                }
                if newValue {
                    evaluateTabSchedule()
                }
            }
            .onChange(of: canvasBoundsStore.size, initial: false) { _, _ in
                clampGuidesToCanvasBounds()
            }
            .onChange(of: isInspectorVisible, initial: false) { _, newIsVisible in
                updateLANPollingState()
                // When inspector closes, push presence immediately so peers see the ring
                // even if tabs haven't changed since the last push (e.g. no module data).
                if !newIsVisible {
                    scheduleSyncedTabPushDebounced()
                }
            }
            .onChange(of: editingTileID, initial: false) { _, newID in
                syncWebpageViewportBypassSelectionState()
                let groupID = tabs.indices.contains(selectedTabIndex)
                    ? tabs[selectedTabIndex].syncGroupID : nil
                lanService.setLocalPresence(tileID: newID, groupID: groupID, selectedTileIDs: Array(selectedTileIDs))
                schedulePresencePushDebounced()
                if let tileID = newID, let gid = groupID {
                    lastSyncedEditingTileID = tileID
                    lastSyncedEditingGroupID = gid
                }
            }
            .onChange(of: isDraggingTilesOnCanvas, initial: false) { _, dragging in
                updateLANPollingState()
                if !dragging {
                    scheduleLANShareUpdateDebounced()
                    scheduleSyncedTabPushDebounced()
                }
            }
            .onChange(of: selectedTileIDs, initial: false) { _, newIDs in
                syncWebpageViewportBypassSelectionState()
                let groupID = tabs.indices.contains(selectedTabIndex)
                    ? tabs[selectedTabIndex].syncGroupID : nil
                if groupID != nil {
                    lanService.setLocalPresence(tileID: editingTileID, groupID: groupID, selectedTileIDs: Array(newIDs))
                    schedulePresencePushDebounced()
                }
            }
            .onChange(of: selectedTabIndex, initial: false) { _, _ in
                selectedTileIDs.removeAll()
                selectedGraphNodeCount = 0
                overviewSelectionAnchorID = nil
                editingTileID = nil
                selectionSource = .canvas
                groupSelectionColor = nil
                isInspectorVisible = false
                disableWebpageViewportBypass()
                updateLANPollingState()
                presentLiveModeTabChangeNotification()
                lanService.setLocalPresence(tileID: nil, groupID: nil, selectedTileIDs: [])
                schedulePresencePushDebounced()
                lastSyncedEditingTileID = nil
                lastSyncedEditingGroupID = nil
                if isLANMirrorTabActive {
                    Task { await refreshLANRenderOnce() }
                }
            }
            .onChange(of: sharedRosters, initial: false) { _, newValue in
                let syncedTabs = Self.syncLegacyRosterFields(tabs: tabs, rosters: newValue)
                if syncedTabs != tabs {
                    tabs = syncedTabs
                }
            }
            .onChange(of: tabs, initial: true) { _, newValue in
                lanService.setLinkedVariableSourceTabs(newValue)
                SharedValueSourceCoordinator.shared.updateTabs(
                    newValue,
                    disconnectedGroupIDs: lanService.orphanedSyncGroupIDs.union(lanService.hostStoppedGroupIDs)
                )
                LinkedComputerPersonVariableStore.shared.update(
                    tabs: newValue,
                    disconnectedGroupIDs: lanService.orphanedSyncGroupIDs.union(lanService.hostStoppedGroupIDs),
                    computerNamesByDeviceID: linkedComputerNamesByDeviceID
                )
                let syncedTabs = Self.syncLegacyRosterFields(tabs: newValue, rosters: sharedRosters)
                if syncedTabs != newValue {
                    tabs = syncedTabs
                    configurePCOAutoAdvanceCoordinator()
                } else {
                    configurePCOAutoAdvanceCoordinator()
                }
            }
            .onChange(of: showingPCOConfigForTab, initial: false) { _, isPresented in
                configurePCOAutoAdvanceCoordinator()
                guard !isPresented else { return }
                lastObservedScheduleActivationKey = nil
                evaluateTabSchedule()
            }
            .onChange(of: universalGraph, initial: false) { _, newGraph in
                graphAutomationRuntime.setUniversalGraph(newGraph)
            }
            .onReceive(SharedSecondTicker.shared.publisher) { _ in
                SharedValueSourceCoordinator.shared.updateTabs(
                    tabs,
                    disconnectedGroupIDs: lanService.orphanedSyncGroupIDs.union(lanService.hostStoppedGroupIDs)
                )
                evaluateTabSchedule()
            }
            .onAppear {
                configurePCOAutoAdvanceCoordinator()
                evaluateTabSchedule()
            }
            .onChange(of: isTextInputActive, initial: false) { _, active in
                if !active { scheduleSyncedTabPushDebounced() }
            }
    }

    private func withSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showingPCOConfigForTab) {
                if let configTabID = selectedTabSafe?.id, let configTabBinding = selectedTabBindingSafe {
                    DashboardTabSettingsView(
                        tab: configTabBinding,
                        onMakeSyncedTab: {
                            guard let index = DashboardTabIdentityMutation.index(of: configTabID, in: tabs) else {
                                RelayDiagnosticsStore.shared.incrementCounter("ui.pcoConfig.makeSyncedTab.rejected")
                                return
                            }
                            makeSyncedTab(at: index)
                        },
                        onStopSyncingTab: {
                            guard let index = DashboardTabIdentityMutation.index(of: configTabID, in: tabs) else {
                                RelayDiagnosticsStore.shared.incrementCounter("ui.pcoConfig.stopSyncingTab.rejected")
                                return
                            }
                            stopSyncingTab(at: index)
                        },
                        onResizeCanvas: { newSize in
                            pendingCanvasSizeTabIndex = nil
                            applyCanvasSizeChange(newSize, purpose: .resizeCurrent)
                        }
                    )
                        .environmentObject(lanService)
                        .onAppear {
                            lanService.setPollingOverrideDisabled(true)
                            print("[PCO] Config: sheet opened")
                            Self.log.info("Config: sheet opened")
                        }
                        .onDisappear {
                            lanService.setPollingOverrideDisabled(false)
                            print("[PCO] Config: sheet closed")
                            Self.log.info("Config: sheet closed")
                        }
                } else {
                    Text("No tab selected.")
                        .padding()
                        .onAppear {
                            lanService.setPollingOverrideDisabled(true)
                            print("[PCO] Config: sheet opened (no tab)")
                            Self.log.info("Config: sheet opened (no tab)")
                        }
                        .onDisappear {
                            lanService.setPollingOverrideDisabled(false)
                            print("[PCO] Config: sheet closed (no tab)")
                            Self.log.info("Config: sheet closed (no tab)")
                        }
                }
            }
            .sheet(isPresented: $showingRosters) {
                DashboardRostersManagerView(
                    rosters: $sharedRosters,
                    tabs: $tabs,
                    selectedTabIndex: $selectedTabIndex
                )
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                settingsInitialSelection = .general
            }) {
                DashboardSettingsView(initialSelection: settingsInitialSelection)
                    .environmentObject(lanService)
                    .sheet(item: Binding<PairingSheetKind?>(
                        get: {
                            if let requestId = pendingApprovalRequestId,
                               let request = lanService.pendingPairingRequests.first(where: { $0.id == requestId }) {
                                return .approval(request)
                            }
                            if let outgoing = lanService.activePairingRequest,
                               outgoing != dismissedActivePairingRequest {
                                return .waiting(outgoing)
                            }
                            return nil
                        },
                        set: { newValue in
                            guard newValue == nil else { return }
                            if let requestId = pendingApprovalRequestId,
                               lanService.pendingPairingRequests.contains(where: { $0.id == requestId }) {
                                pendingApprovalRequestId = nil
                            } else {
                                dismissedActivePairingRequest = lanService.activePairingRequest
                            }
                        }
                    )) { kind in
                        pairingSheetContent(for: kind)
                    }
            }
            .sheet(isPresented: $showingKeyboardShortcuts) {
                DashboardKeyboardShortcutsView()
            }
            .sheet(
                isPresented: $showExternalDevicesSettingsSheet,
                onDismiss: {
                    // Reset deep-link state so the next open behaves predictably.
                    externalDevicesInitialSelection = nil
                    externalDevicesEntryMode = .full
                }
            ) {
                ExternalDevicesSettingsView(
                    initialDeviceID: externalDevicesInitialSelection,
                    entryMode: externalDevicesEntryMode
                )
                .environmentObject(lanService)
            }
            .sheet(isPresented: $isShowingNewDashboardSizePrompt) {
                DashboardCanvasSizePromptView(
                    store: canvasBoundsStore,
                    isPresented: $isShowingNewDashboardSizePrompt,
                    purpose: dashboardCanvasSizePromptPurpose,
                    onResetToDocumentDefault: pendingCanvasSizeTabIndex.map { tabIdx in
                        {
                            if self.tabs.indices.contains(tabIdx) {
                                self.tabs[tabIdx].canvasSize = nil
                            }
                            self.pendingCanvasSizeTabIndex = nil
                            self.saveState.hasUnsavedChanges = true
                            self.scheduleTabsSaveDebounced()
                        }
                    }
                ) { newSize in
                    applyCanvasSizeChange(newSize, purpose: dashboardCanvasSizePromptPurpose)
                }
            }
            .sheet(isPresented: $onboardingWizardController.isPresented) {
                OnboardingWizardView(
                    controller: onboardingWizardController,
                    onCreateDashboard: handleOnboardingWizardCompletion
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .relayStartOnboardingWizard)) { _ in
                onboardingWizardController.start(hasPro: subscriptionManager.hasPro)
            }
            .sheet(isPresented: $showingTileGroupSheet, onDismiss: {
                tileGroupName = ""
                editingTileGroupID = nil
                editingTileGroupTileIDs.removeAll()
                tileGroupSheetMode = .create
                isTextInputActive = false
            }) {
                TileGroupCreateSheet(
                    name: $tileGroupName,
                    color: $tileGroupColor,
                    selectedCount: tileGroupSheetSelectedCount,
                    isEditing: tileGroupSheetMode == .edit,
                    tab: tileGroupSheetTab,
                    availableTiles: tileGroupAvailableTiles,
                    selectedTileIDs: $editingTileGroupTileIDs,
                    onCommit: {
                        switch tileGroupSheetMode {
                        case .create:
                            createTileGroup(name: tileGroupName, color: tileGroupColor)
                        case .edit:
                            if let groupId = editingTileGroupID {
                                updateTileGroup(
                                    id: groupId,
                                    name: tileGroupName,
                                    color: tileGroupColor,
                                    tileIDs: editingTileGroupTileIDs
                                )
                            }
                        }
                        tileGroupName = ""
                        editingTileGroupID = nil
                        editingTileGroupTileIDs.removeAll()
                        tileGroupSheetMode = .create
                        showingTileGroupSheet = false
                    },
                    onCancel: {
                        tileGroupName = ""
                        editingTileGroupID = nil
                        editingTileGroupTileIDs.removeAll()
                        tileGroupSheetMode = .create
                        isTextInputActive = false
                        showingTileGroupSheet = false
                    }
                )
            }
            .onChange(of: showingPCOConfigForTab, initial: false) { _, isPresented in
                updateLANPollingState()
                if !isPresented { scheduleSyncedTabPushDebounced() }
            }
            .onChange(of: showingSettings, initial: false) { _, _ in
                updateLANPollingState()
            }
            .onChange(of: showingKeyboardShortcuts, initial: false) { _, _ in
                updateLANPollingState()
            }
            .onChange(of: showExternalDevicesSettingsSheet, initial: false) { _, _ in
                updateLANPollingState()
            }
    }

    private func withPCOHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: selectedTabSafe?.serviceTypeID, initial: false) { _, newMode in
                if hasSelectedTab { startPCORefreshAnimation() }
            }
            .onChange(of: selectedTabSafe?.planID, initial: false) { _, newMode in
                if hasSelectedTab { startPCORefreshAnimation() }
            }
            .onChange(of: selectedTabSafe?.pcoAllPositionAssignments, initial: false) { _, newMode in
                if isPCORefreshing {
                    isPCORefreshing = false
                    refreshPCOModulesForSelectedTab()
                }
            }
            .onChange(of: selectedTabSafe?.pcoPositionAssignments, initial: false) { _, newMode in
                if isPCORefreshing {
                    isPCORefreshing = false
                    refreshPCOModulesForSelectedTab()
                }
            }
    }

    private func configurePCOAutoAdvanceCoordinator() {
        pcoAutoAdvanceCoordinator.configure(
            tabs: tabs,
            isPaused: showingPCOConfigForTab,
            onAdvance: { tabID, update in
                applyPCOAutoAdvance(update, to: tabID)
            }
        )
    }

    private func applyPCOAutoAdvance(_ update: PCOAutoAdvanceUpdate, to tabID: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard tabs[tabIndex].planID != update.planID else { return }

        tabs[tabIndex].planID = update.planID
        tabs[tabIndex].planTitle = update.planTitle
        tabs[tabIndex].planDateLabel = update.planDateLabel
        tabs[tabIndex].pcoAllPositionAssignments = update.allPositionAssignments
        tabs[tabIndex].pcoPositionAssignmentCandidates = update.positionAssignmentCandidates
        tabs[tabIndex].pcoPositionToTeamName = update.positionToTeamName
        tabs[tabIndex].pcoTeamPositionsByTeamName = update.teamPositionsByTeamName
        tabs[tabIndex].pcoRundownSnapshotTitles = update.rundownSnapshotTitles
        tabs[tabIndex].pcoSnapshotKey = update.snapshotKey
        tabs[tabIndex].pcoCachedRundownRows = update.cachedRundownRows
        tabs[tabIndex].pcoCachedTeamAssignments = update.cachedTeamAssignments

        saveTabs()

        if tabIndex == selectedTabIndex {
            startPCORefreshAnimation()
        }
    }

    private func applyAutomationMode(_ mode: DashboardTab.AutomationMode) {
        guard tabs.indices.contains(selectedTabIndex) else { return }
        tabs[selectedTabIndex].automationMode = mode
        scheduleTabsSaveDebounced()
    }

    /// The effective automation graph for a tab: shared `universalGraph` in universal mode,
    /// the tab's own graph in per-tab mode.
    private func effectiveGraphForTab(at idx: Int) -> DashboardGraph? {
        guard tabs.indices.contains(idx) else { return nil }
        return AutomationScopeResolver.effectiveGraph(tab: tabs[idx], universalGraph: universalGraph)
    }

    /// Read-modify-write the effective automation graph for a tab, writing back to the correct
    /// store (universalGraph in universal mode, tab.graph in per-tab mode). Mirrors resolvedGraphTabBinding
    /// so direct graph edits don't bypass universalGraph.
    private func mutateEffectiveGraph(forTabAt idx: Int, _ body: (inout DashboardGraph) -> Void) {
        guard tabs.indices.contains(idx) else { return }
        if tabs[idx].automationMode == .universal {
            guard var g = universalGraph else { return }
            body(&g)
            universalGraph = g
        } else {
            guard var g = tabs[idx].graph else { return }
            body(&g)
            tabs[idx].graph = g
        }
    }

    /// Tapping a scope segment for the *selected* tab.
    private func requestAutomationModeChange(to mode: DashboardTab.AutomationMode) {
        guard tabs.indices.contains(selectedTabIndex) else { return }
        let tab = tabs[selectedTabIndex]
        guard tab.automationMode != mode else { return }
        if mode == .perTab {
            // Shared -> private: seed a one-time fork from the current shared graph.
            if tabs[selectedTabIndex].graph == nil || tabs[selectedTabIndex].graph?.hasAutomationContent != true {
                tabs[selectedTabIndex].graph = universalGraph
            }
            applyAutomationMode(.perTab)
            return
        }
        // Private -> shared.
        switch AutomationScopeResolver.switchToShared(tab: tab, universalGraph: universalGraph) {
        case .switchImmediately:
            applyAutomationMode(.universal)
        case .confirmPromoteOrAdopt(let hasExistingShared):
            pendingSharedSwitchTabID = nil
            pendingSharedSwitchHasExistingShared = hasExistingShared
            showSwitchToUniversalConfirmation = true
        }
    }

    /// Tapping a row in the overview for a (possibly non-selected) tab toggles that tab.
    private func requestAutomationModeChangeForTab(_ tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let newMode: DashboardTab.AutomationMode = tabs[idx].automationMode == .universal ? .perTab : .universal
        if newMode == .perTab {
            if tabs[idx].graph == nil || tabs[idx].graph?.hasAutomationContent != true {
                tabs[idx].graph = universalGraph
            }
            tabs[idx].automationMode = .perTab
            scheduleTabsSaveDebounced()
            return
        }
        let outcome = AutomationScopeResolver.switchToShared(tab: tabs[idx], universalGraph: universalGraph)
        switch outcome {
        case .switchImmediately:
            tabs[idx].automationMode = .universal
            scheduleTabsSaveDebounced()
        case .confirmPromoteOrAdopt(let hasExistingShared):
            pendingSharedSwitchTabID = tabID
            pendingSharedSwitchHasExistingShared = hasExistingShared
            showSwitchToUniversalConfirmation = true
        }
    }

    /// The popover's single contextual action (promote-or-make-private for the selected tab).
    private func handleAutomationContextualAction() {
        guard tabs.indices.contains(selectedTabIndex) else { return }
        let mode = tabs[selectedTabIndex].automationMode
        requestAutomationModeChange(to: mode == .universal ? .perTab : .universal)
    }

    /// Promote the pending (or selected) tab's graph to become the shared graph, then set it shared.
    private func promoteSelectedOrPendingTabToShared() {
        let idx: Int
        if let id = pendingSharedSwitchTabID, let i = tabs.firstIndex(where: { $0.id == id }) {
            idx = i
        } else {
            idx = selectedTabIndex
        }
        guard tabs.indices.contains(idx), let graph = tabs[idx].graph else { return }
        universalGraph = graph
        tabs[idx].automationMode = .universal
        pendingSharedSwitchTabID = nil
        scheduleTabsSaveDebounced()
    }

    /// Discard the pending tab's private graph view and adopt the existing shared graph.
    private func adoptSharedForPendingTab() {
        guard universalGraph != nil else { return }
        let idx: Int
        if let id = pendingSharedSwitchTabID, let i = tabs.firstIndex(where: { $0.id == id }) {
            idx = i
        } else {
            idx = selectedTabIndex
        }
        guard tabs.indices.contains(idx) else { return }
        tabs[idx].automationMode = .universal
        pendingSharedSwitchTabID = nil
        scheduleTabsSaveDebounced()
    }

    private func withLayoutModeHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: layoutMode, initial: false) { _, newMode in
                let isGraph = (newMode == .graph)

                lanService.setPollingEnabled(!isGraph)

                if isGraph {
                    lanMirrorRefreshTask?.cancel()
                    lanMirrorRefreshTask = nil
                } else {
                    if selectedLANShareId != nil {
                        startLANMirrorRefreshLoop()
                    }
                }

                isAddMenuOpen = false
                if isGraph {
                    if tabs.indices.contains(selectedTabIndex) {
                        graphTilesSnapshot = tabs[selectedTabIndex].tiles
                        rundownTitlesSnapshot = snapshotRundownTitles(for: tabs[selectedTabIndex])
                    } else {
                        graphTilesSnapshot = []
                        rundownTitlesSnapshot = []
                    }
                } else {
                    graphTilesSnapshot = []
                    rundownTitlesSnapshot = []
                }

                NotificationCenter.default.post(
                    name: DashboardRootView.graphModeChangedNotification,
                    object: nil,
                    userInfo: ["isGraph": isGraph]
                )
            }
    }

    private func clearSelectionForViewSwitch() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #elseif os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        selectedTileIDs.removeAll()
        overviewSelectionAnchorID = nil
        editingTileID = nil
        isInspectorVisible = false
    }

    private func withGraphSnapshotHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: selectedTabIndex, initial: false) { _, _ in
                syncActiveCanvasDiagnostics()
                if layoutMode == .graph {
                    syncGraphSnapshotsForSelectedTab()
                }
                updateHiddenTilesFlag()
            }
            .onChange(of: selectedTabSafe?.tiles.map(\.id) ?? [], initial: false) { _, _ in
                syncActiveCanvasDiagnostics()
                guard layoutMode == .graph else { return }
                syncGraphSnapshotsForSelectedTab()
            }
            .onChange(of: selectedTabSafe?.serviceTypeID, initial: false) { _, _ in
                guard layoutMode == .graph else { return }
                syncGraphSnapshotsForSelectedTab()
            }
            .onChange(of: selectedTabSafe?.planID, initial: false) { _, _ in
                guard layoutMode == .graph else { return }
                syncGraphSnapshotsForSelectedTab()
            }
            .onChange(of: selectedTabSafe?.serviceTimeName, initial: false) { _, _ in
                guard layoutMode == .graph else { return }
                syncGraphSnapshotsForSelectedTab()
            }
            .onChange(of: selectedTabSafe?.teamName, initial: false) { _, _ in
                guard layoutMode == .graph else { return }
                syncGraphSnapshotsForSelectedTab()
            }
            .onChange(of: selectedTabSafe?.pcoSnapshotKey, initial: false) { _, _ in
                guard layoutMode == .graph else { return }
                syncGraphSnapshotsForSelectedTab()
            }
            .onChange(of: selectedTabSafe?.pcoRundownSnapshotTitles ?? [], initial: false) { _, newValue in
                guard layoutMode == .graph else { return }
                syncGraphSnapshotsForSelectedTab()
                NotificationCenter.default.post(
                    name: .relayPCOItemDidChange,
                    object: nil,
                    userInfo: ["titles": newValue]
                )
            }
            .onAppear {
                updateHiddenTilesFlag()
                syncActiveCanvasDiagnostics()
            }
    }

    private func syncGraphSnapshotsForSelectedTab() {
        guard tabs.indices.contains(selectedTabIndex) else {
            graphTilesSnapshot = []
            rundownTitlesSnapshot = []
            return
        }

        graphTilesSnapshot = tabs[selectedTabIndex].tiles
        rundownTitlesSnapshot = snapshotRundownTitles(for: tabs[selectedTabIndex])
    }
    
    // MARK: - Persisted Settings

    @AppStorage("gridBackgroundOpacity") private var gridBackgroundOpacity: Double = 0.35
    @AppStorage("lan_sharing_enabled") private var lanSharingEnabled: Bool = true
    @AppStorage("lan_browser_view_only_enabled") private var lanBrowserViewOnlyEnabled: Bool = false
    private var lanHostingAllowed: Bool { lanSharingEnabled && subscriptionManager.hasPro }
    private var lanBrowserServingAllowed: Bool { lanBrowserViewOnlyEnabled || lanHostingAllowed }
    private var lanDiscoveryAllowed: Bool { subscriptionManager.hasPro }
    // MARK: - Center Canvas Layers

    /// Full-screen background with context menu, selection gestures, and drag-to-select.
    @ViewBuilder
    private func canvasBackgroundView() -> some View {
        if isLiveMode {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isLiveModeChromeVisible else { return }
                    hideLiveModeChromeImmediately()
                }
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isLiveMode = false
                    }
                }
        } else {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle()) // ensure the whole canvas is clickable
                
                // Double-tap: in Live Mode -> return to Edit Mode. In Edit Mode -> clear selection/inspector and add a tile.
                .onTapGesture(count: 2) {
                    let isMirrorTabSelected = tabs.indices.contains(selectedTabIndex) && (tabs[selectedTabIndex].lanMirrorShareId != nil)

                    // Live Mode: double-tap anywhere to return to Edit Mode.
                    if isLiveMode {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isLiveMode = false
                        }
                        return
                    }

                    // Edit Mode: double-tap to add a tile.
                    guard !isMirrorTabSelected else { return }
                    selectedTileIDs.removeAll()
                    editingTileID = nil
                    isInspectorVisible = false
                    
                    addEmptyTile(openModuleCatalog: true)
                }
                // Single-click: just clear selection and close inspector
                .onTapGesture {
                    // Capture which tile was being edited so we can animate it back.
                    let tileIDToReset = editingTileID

                    editingTileID = nil
                    isInspectorVisible = false

                    if tileIDToReset != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                selectedTileIDs.removeAll()
                            }
                        } else {
                            selectedTileIDs.removeAll()
                        }
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isViewportGestureActive else { return }
                            if selectionStartPoint == nil {
                                // Check for a guide FIRST, before the resize-halo check below.
                                // Guides are commonly placed right at a tile's edge (that's the
                                // point of a guide) — exactly where a resize halo also sits — so
                                // checking the halo first was silently suppressing this hint any
                                // time a guide happened to coincide with a selected tile's resize
                                // zone. Either check already prevents a marquee from starting, so
                                // reordering doesn't change that behavior, only which early-return
                                // gets hit first.
                                if let guide = guideAtPoint(viewportPoint: value.startLocation) {
                                    if !ModifierTracker.shared.isModifierPressed {
                                        NotificationCenter.default.post(name: NSNotification.Name("ShowGuideModifierClue"), object: guide.id)
                                        return
                                    }
                                }

                                // Don't start a marquee if the click lands inside a selected tile's
                                // resize-handle halo. The cursor already shows the resize affordance
                                // for ~14pt outside the tile edge, and starting a marquee there
                                // contradicts that hint.
                                if isPointInResizeHaloOfSelectedTile(viewportPoint: value.startLocation) {
                                    return
                                }

                                selectionStartPoint = value.startLocation
                            }
                            selectionCurrentPoint = value.location
                        }
                        .onEnded { value in
                            guard !isViewportGestureActive else { return }
                            selectionCurrentPoint = value.location
                            if let rect = selectionRectCanvas {
                                updateSelection(with: rect)
                            }
                            selectionStartPoint = nil
                            selectionCurrentPoint = nil
                        }
                )
        }
    }

    /// True when `viewportPoint` lands inside the 28×28 resize-handle halo of any
    /// currently-selected tile. Mirrors the hit frame used by `ResizeHandle` so the
    /// marquee gesture defers to resizes wherever the resize cursor is shown.
    private func isPointInResizeHaloOfSelectedTile(viewportPoint: CGPoint) -> Bool {
        guard !isLiveMode, !selectedTileIDs.isEmpty,
              let selectedTab = selectedTabSafe else { return false }

        let zoom = max(0.0001, canvasViewportZoom)
        let canvasPoint = CGPoint(
            x: (viewportPoint.x - canvasViewportPan.width) / zoom,
            y: (viewportPoint.y - canvasViewportPan.height) / zoom
        )

        // Half of ResizeHandle's 28pt hit frame.
        let halo: CGFloat = 14

        for tile in selectedTab.tiles where selectedTileIDs.contains(tile.id) {
            let size = effectiveSize(for: tile)
            let ox = tile.offset.width
            let oy = tile.offset.height

            // Mirrors ResizeHandleLayout in DashboardTileContainer. Includes all 8
            // handle positions; over-blocking near a non-visible handle (e.g. corners
            // hidden during group resize) is harmless — the user can still marquee
            // by clicking away from the tile edges.
            let centers: [CGPoint] = [
                CGPoint(x: ox + max(1, size.width - 5),  y: oy + max(1, size.height - 5)),
                CGPoint(x: ox + max(1, size.width - 5),  y: oy + 5),
                CGPoint(x: ox + 5,                       y: oy + 5),
                CGPoint(x: ox + 1,                       y: oy + size.height / 2),
                CGPoint(x: ox + 5,                       y: oy + max(1, size.height - 5)),
                CGPoint(x: ox + max(1, size.width - 1),  y: oy + size.height / 2),
                CGPoint(x: ox + size.width / 2,          y: oy + max(1, size.height - 1)),
                CGPoint(x: ox + size.width / 2,          y: oy + 1),
            ]

            for c in centers {
                if abs(canvasPoint.x - c.x) <= halo && abs(canvasPoint.y - c.y) <= halo {
                    return true
                }
            }
        }
        return false
    }

    /// Returns the guide underneath the viewport point if one exists.
    private func guideAtPoint(viewportPoint: CGPoint) -> CanvasGuide? {
        guard showGuidesEnabled, !isLiveMode, let guides = selectedTabGuidesBindingSafe?.wrappedValue else { return nil }
        
        let zoom = max(0.0001, canvasViewportZoom)
        let canvasPoint = CGPoint(
            x: (viewportPoint.x - canvasViewportPan.width) / zoom,
            y: (viewportPoint.y - canvasViewportPan.height) / zoom
        )
        
        // Hit tolerance is 20px visually, so 20 / zoom in canvas points
        let hitTolerance = 20 / zoom
        
        for guide in guides {
            switch guide.orientation {
            case .vertical:
                print("[guideAtPoint] vertical guide at \(guide.position), diff: \(abs(guide.position - canvasPoint.x))")
                if abs(guide.position - canvasPoint.x) <= hitTolerance {
                    return guide
                }
            case .horizontal:
                print("[guideAtPoint] horizontal guide at \(guide.position), diff: \(abs(guide.position - canvasPoint.y))")
                if abs(guide.position - canvasPoint.y) <= hitTolerance {
                    return guide
                }
            }
        }
        return nil
    }

    /// Optional grid-only layer (no guides). Grid should sit behind tiles.
    @ViewBuilder
    private func gridLayer() -> some View {
        // If the user ever saved 0.0 by accident, keep the grid visible by clamping.
        let effectiveOpacity = max(gridBackgroundOpacity, 0.05)

        if showGridEnabled && !isLiveMode {
            GeometryReader { geo in
                GridBackground(
                    gridSize: CGFloat(gridSizeSetting),
                    lineOpacity: effectiveOpacity
                )
                // Match the user-defined canvas bounds; fall back to the viewport size
                // during the first layout pass when canvasSize may be zero.
                .frame(
                    width: canvasSize.width > 0 ? canvasSize.width : geo.size.width,
                    height: canvasSize.height > 0 ? canvasSize.height : geo.size.height,
                    alignment: .topLeading
                )
                .clipped()
                .allowsHitTesting(false)
            }
            .zIndex(-1)
        }
    }
    /// Guides overlay layer, rendered above tiles.
    @ViewBuilder
    private func guidesLayer() -> some View {
        if showGuidesEnabled && !isLiveMode && !(isInspectorVisible && editingTileID != nil) {
            GuidesOverlay(
                guides: selectedTabGuidesBindingSafe ?? .constant([]),
                canvasSize: canvasSize,
                gridSize: CGFloat(gridSizeSetting),
                snapToGrid: snapToGridEnabled,
                viewportZoom: canvasViewportZoom,
                viewportPan: canvasViewportPan
            )
            .scaleEffect(canvasViewportZoom, anchor: .topLeading)
            .offset(canvasViewportPan)
            .frame(width: canvasViewportSize.width, height: canvasViewportSize.height, alignment: .topLeading)
            .clipped()
            .zIndex(10_000) // ensure guides render above all tiles, even selected ones
        }
    }

    /// Floating toolbar above the current selection: canvas-fraction sizing for a
    /// single tile, or even-distribution for 2+ tiles. Hidden when neither applies.
    ///
    /// The actual bounding-rect computation (which needs the *live* drag delta
    /// from `interactionSession`, updated every gesture frame) is delegated to
    /// `DashboardSelectionActionToolbarHost` below -- this function only computes
    /// the *committed* per-tile rects, which change only when `tabs`/`selectedTileIDs`
    /// change (i.e. not at gesture frequency), so this root body itself never reads
    /// `interactionSession`'s per-frame properties.
    @ViewBuilder
    private func selectionActionToolbarLayer() -> some View {
        if !isLiveMode, tabs.indices.contains(selectedTabIndex), !selectedTileIDs.isEmpty {
            let committedSelectedRects: [UUID: CGRect] = Dictionary(
                uniqueKeysWithValues: tabs[selectedTabIndex].tiles
                    .filter { selectedTileIDs.contains($0.id) }
                    .map { tile in
                        let size = effectiveSize(for: tile)
                        return (
                            tile.id,
                            CGRect(
                                x: tile.offset.width,
                                y: tile.offset.height,
                                width: size.width,
                                height: size.height
                            )
                        )
                    }
            )

            DashboardSelectionActionToolbarHost(
                session: interactionSession,
                committedSelectedRects: committedSelectedRects,
                selectedTileIDs: selectedTileIDs,
                canvasViewportZoom: canvasViewportZoom,
                canvasViewportPan: canvasViewportPan,
                canvasSize: canvasSize,
                onApplyFractionRegion: { region in
                    if let tileID = selectedTileIDs.first {
                        applyFractionRegion(region, toTileID: tileID)
                    }
                },
                onDistribute: { axis in
                    distributeSelectedTiles(axis: axis)
                }
            )
        }
    }

    /// Tiles for the currently selected tab, positioned on the canvas.
    @ViewBuilder
    private func tilesLayer() -> some View {
        if selectedLANShareId != nil {
            if let image = lanRenderImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(width: canvasViewportSize.width, height: canvasViewportSize.height, alignment: .center)
                    .clipped()
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for LAN snapshot…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: canvasViewportSize.width, height: canvasViewportSize.height, alignment: .center)
            }
        } else if let tabBinding = selectedTabBindingSafe {
            if layoutMode == .canvas {
                // Wraps the whole canvas ZStack directly (rather than via
                // `.modifier(DashboardCanvasViewportHostModifier(...))`) so the
                // visible-rect parameter this host publishes (for viewport
                // culling, `DashboardFeatureFlags.canvasViewportCulling`) can
                // reach `DashboardTileCanvas` below. The modifier form can't
                // do this: its `content` is an already-built, opaque view by
                // the time the modifier runs, so it can't be re-parameterized
                // by the rect.
                DashboardCanvasViewportHost(
                    pan: $canvasViewportPan,
                    zoom: $canvasViewportZoom,
                    isInteracting: $isViewportGestureActive,
                    contentSize: canvasViewportSize,
                    isEnabled: !isLiveMode && !tutorialController.isPresented,
                    blocksOverScrollableViews: !isPostTileDragViewportOverrideActive,
                    blocksOverWebViews: isWebpageViewportBypassActive
                ) { visibleCanvasRect in
                ZStack(alignment: .topLeading) {
                    // Photoshop-style "artboard" outline showing the canvas bounds.
                    // Hidden only when the viewport transform is effectively at identity.
                    let shouldShowScreenBounds = !isLiveMode && (
                        (abs(canvasViewportZoom - 1.0) > 0.001)
                            || (abs(canvasViewportPan.width) > 0.5)
                            || (abs(canvasViewportPan.height) > 0.5)
                    )
                    if shouldShowScreenBounds {
                        ZStack(alignment: .top) {
                            // Dashed screen bounds
                            Rectangle()
                                .stroke(
                                    Color.white.opacity(0.22),
                                    style: StrokeStyle(
                                        lineWidth: max(1, 2 / max(1, canvasViewportZoom)),
                                        dash: [6 / max(1, canvasViewportZoom), 4 / max(1, canvasViewportZoom)]
                                    )
                                )

                            // Screen size label
                            Text("Canvas Size : \(Int(canvasSize.width)) x \(Int(canvasSize.height))")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
//                                .background(
//                                    Capsule()
//                                        .fill(Color.black.opacity(0.55))
//                                )
                                // Offset slightly downward so it sits just inside the top edge
                                .offset(y: -25 / max(1, canvasViewportZoom))
                        }
                        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
                        .allowsHitTesting(false)
                    }

                    let isMirrorTabSelected = tabs.indices.contains(selectedTabIndex) && (tabs[selectedTabIndex].lanMirrorShareId != nil)

                    let syncGroupID = tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex].syncGroupID : nil
                    let tileRemoteEditors: [UUID: [(name: String, color: Color)]] = {
                        guard let groupID = syncGroupID else { return [:] }
                        var result: [UUID: [(name: String, color: Color)]] = [:]
                        // Merge poll-based and push-based presence, deduplicating by deviceID
                        // (pushedPresence wins for the same device — it's more real-time).
                        var seenDeviceIDs: Set<String> = []
                        let allPresence = Array(lanService.pushedPresence.values) + Array(lanService.peerPresence.values)
                        for presence in allPresence {
                            guard seenDeviceIDs.insert(presence.deviceID).inserted else { continue }
                            let color = syncedPresenceColor(for: presence.deviceID)
                            // Inspector-editing tiles (higher priority — shown first)
                            if let tileIDs = presence.editingByGroup[groupID] {
                                for idStr in tileIDs {
                                    guard let tileID = UUID(uuidString: idStr) else { continue }
                                    result[tileID, default: []].append((presence.deviceName, color))
                                }
                            }
                            // Selected / moving tiles
                            if let tileIDs = presence.selectedByGroup?[groupID] {
                                for idStr in tileIDs {
                                    guard let tileID = UUID(uuidString: idStr) else { continue }
                                    if result[tileID]?.contains(where: { $0.name == presence.deviceName }) != true {
                                        result[tileID, default: []].append((presence.deviceName, color))
                                    }
                                }
                            }
                        }
                        return result
                    }()

                    let _ = configureCanvasActions(tabBinding: tabBinding)

                    DashboardTileCanvas(
                        interactionSession: interactionSession,
                        tab: tabBinding.wrappedValue,
                        selectedTileIDs: $selectedTileIDs,
                        editingTileID: $editingTileID,
                        isInspectorVisible: $isInspectorVisible,
                        pendingFirstModuleSelectTileID: $pendingFirstModuleSelectTileID,
                        isDraggingTilesOnCanvas: $isDraggingTilesOnCanvas,
                        selectionSource: $selectionSource,
                        groupSelectionColor: $groupSelectionColor,
                        sharedRosters: sharedRosters,
                        isLiveMode: isLiveMode,
                        liveModeReloadToken: liveModeReloadToken,
                        allowTileOverlap: allowTileOverlap,
                        snapToGridEnabled: snapToGridEnabled,
                        canvasSize: canvasSize,
                        canvasGuides: selectedTabGuides,
                        showGuidesEnabled: showGuidesEnabled,
                        gridSizeSetting: gridSizeSetting,
                        showGridEnabled: showGridEnabled,
                        gridLineOpacity: gridBackgroundOpacity,
                        isPCORefreshing: isPCORefreshing,
                        viewportZoom: canvasViewportZoom,
                        visibleCanvasRect: visibleCanvasRect,
                        defaultTileSize: defaultTileSize,
                        disableDragging: (isLiveMode || isMirrorTabSelected || isViewportGestureActive || isWebpageViewportBypassActive),
                        actions: canvasActions,
                        tileRemoteEditors: tileRemoteEditors
                    )
                    .environmentObject(lanService)
                    .coordinateSpace(.named("dashboardCanvas"))
                } // end ZStack
                } // end DashboardCanvasViewportHost's { visibleCanvasRect in ... } trailing closure
                .overlay(alignment: .bottom) {
                    if !isLiveMode && !tutorialController.isPresented {
                        ViewportPanZoomControls(
                            pan: $canvasViewportPan,
                            zoom: $canvasViewportZoom,
                            contentSize: canvasSize,
                            viewportSize: canvasViewportSize
                        )
                        .padding(.bottom, 12)
                    }
                }
                .onChange(of: isViewportGestureActive, initial: false) { _, active in
                    if active {
                        selectionStartPoint = nil
                        selectionCurrentPoint = nil
                    }
                }
                // IMPORTANT: Constrain the transformed (pan/zoom) canvas to its viewport.
                // Without clipping, a zoomed/panned layer can render outside its parent and
                // visually overlap the left overview sidebar.
                .frame(width: canvasViewportSize.width, height: canvasViewportSize.height, alignment: .topLeading)
                .clipped()
                .onChange(of: isLiveMode, initial: false) { _, newValue in
                    if newValue {
                        if liveModeCanvasBehavior == .fitToScreen {
                            // Entering Live Mode: remember current viewport, then fit the canvas to the viewport.
                            canvasViewportZoomBeforeLive = canvasViewportZoom
                            canvasViewportPanBeforeLive = canvasViewportPan

                            let viewportWidth = max(1.0, canvasViewportSize.width)
                            let viewportHeight = max(1.0, canvasViewportSize.height)
                            let canvasWidth = max(1.0, canvasSize.width)
                            let canvasHeight = max(1.0, canvasSize.height)

                            let zoomToFit = min(viewportWidth / canvasWidth, viewportHeight / canvasHeight)
                            let fittedZoom = min(1.0, zoomToFit)
                            let fittedWidth = canvasWidth * fittedZoom
                            let fittedHeight = canvasHeight * fittedZoom
                            let fittedPan = CGSize(
                                width: (viewportWidth - fittedWidth) * 0.5,
                                height: (viewportHeight - fittedHeight) * 0.5
                            )

                            withAnimation(.easeInOut(duration: 0.25)) {
                                canvasViewportZoom = fittedZoom
                                canvasViewportPan = fittedPan
                            }
                        }
#if os(macOS)
                        if liveModeWindowBehavior == .fullScreen, let window = NSApp.keyWindow {
                            let alreadyFullScreen = window.styleMask.contains(.fullScreen)
                            didEnterFullScreenForLiveMode = !alreadyFullScreen
                            if !alreadyFullScreen {
                                window.toggleFullScreen(nil)
                            }
                        }
#endif
                    } else {
                        if liveModeCanvasBehavior == .fitToScreen {
                            // Exiting Live Mode: restore the previous viewport.
                            withAnimation(.easeInOut(duration: 0.25)) {
                                canvasViewportZoom = canvasViewportZoomBeforeLive
                                canvasViewportPan = canvasViewportPanBeforeLive
                            }
                        }
#if os(macOS)
                        if didEnterFullScreenForLiveMode, let window = NSApp.keyWindow {
                            didEnterFullScreenForLiveMode = false
                            if window.styleMask.contains(.fullScreen) {
                                window.toggleFullScreen(nil)
                            }
                        }
#endif
                    }
                }
            } else {
                // Graph layout is rendered by mainCenterAndInspector() when active.
                EmptyView()
            }
        }
    }


    /// Drag-selection rectangle overlay.
    @ViewBuilder
    private func selectionOverlay() -> some View {
        if let rect = selectionRectViewport, !isViewportGestureActive {
            Rectangle()
                .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
                .background(
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.15))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .zIndex(9_000)
        }
    }
    private func selectAllTiles() {
        guard tabs.indices.contains(selectedTabIndex) else { return }

        let ids = Set(tabs[selectedTabIndex].tiles.filter { !$0.isHidden }.map(\.id))
        selectedTileIDs = ids
        overviewSelectionAnchorID = ids.first

        if isInspectorVisible {
            if let first = ids.first {
                editingTileID = first
            } else {
                editingTileID = nil
                isInspectorVisible = false
            }
        }
    }
    private var shouldForceToolbarVisible: Bool {
        isTabInteractionActive || isTextInputActive
    }
private struct DashboardNotificationBanner: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
        let durationSeconds: Double
    }

    private func presentLiveModeTabChangeNotification() {
        guard isLiveMode,
              tabs.indices.contains(selectedTabIndex) else { return }

        let rawName = tabs[selectedTabIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawName.isEmpty ? "Tab \(selectedTabIndex + 1)" : rawName
        presentNotification(title: title, message: "", durationSeconds: 1.4)
    }

    private func presentNotification(title: String, message: String, durationSeconds: Double) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeDuration = max(0.5, min(30, durationSeconds))

        let banner = DashboardNotificationBanner(
            title: trimmedTitle.isEmpty ? "Notification" : trimmedTitle,
            message: trimmedMessage,
            durationSeconds: safeDuration
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            activeNotificationBanner = banner
        }

        notificationDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            if activeNotificationBanner?.id == banner.id {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeNotificationBanner = nil
                }
            }
        }
        notificationDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + safeDuration, execute: workItem)
    }

    private func canvasViewportSize(for rootSize: CGSize) -> CGSize {
        let overviewWidth: CGFloat = isTileOverviewVisible ? overviewPanelWidth : 0
        return CGSize(
            width: max(rootSize.width - overviewWidth, 0),
            height: max(rootSize.height, 0)
        )
    }

    private func updateCanvasViewportSize(for rootSize: CGSize) {
        let nextSize = canvasViewportSize(for: rootSize)
        guard abs(canvasViewportSize.width - nextSize.width) > 0.5
            || abs(canvasViewportSize.height - nextSize.height) > 0.5
        else {
            return
        }
        canvasViewportSize = nextSize
    }

    /// Scales/centers the canvas viewport so the whole canvas is visible, matching
    /// what the "Fit to Window" toolbar button does. Used to avoid opening a
    /// freshly loaded (or newly created) dashboard at a 1:1 zoom that clips it.
    private func fitCanvasToViewport() {
        let contentSize = canvasSize
        let viewportSize = canvasViewportSize
        guard contentSize.width > 0, contentSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else { return }

        let zoomRange: ClosedRange<CGFloat> = 0.25...3.00
        let fittedZoom = min(
            max(
                min(viewportSize.width / contentSize.width, viewportSize.height / contentSize.height),
                zoomRange.lowerBound
            ),
            zoomRange.upperBound
        )
        let targetWidth = contentSize.width * fittedZoom
        let targetHeight = contentSize.height * fittedZoom

        canvasViewportZoom = fittedZoom
        canvasViewportPan = CGSize(
            width: (viewportSize.width - targetWidth) * 0.5,
            height: (viewportSize.height - targetHeight) * 0.5
        )
    }

    private var hiddenGraphNodeCountForAddMenu: Int {
        guard layoutMode == .graph else { return 0 }
        return effectiveGraphForTab(at: selectedTabIndex)?.hiddenNodeIds.count ?? 0
    }

    private var hiddenTileCountForAddMenu: Int {
        guard layoutMode == .canvas,
              let tab = selectedTabSafe
        else { return 0 }

        var count = 0
        for tile in tab.tiles where tile.isHidden {
            count += 1
        }
        return count
    }

    private var shouldShowGraphPerformanceNotice: Bool {
        guard layoutMode == .graph,
              !isLiveMode,
              graphNodeCountForPerformanceMode >= 18
        else { return false }

        return true
    }

    private var graphNodeCountForPerformanceMode: Int {
        guard layoutMode == .graph,
              let tab = selectedTabSafe
        else { return 0 }

        let graphCount = effectiveGraphForTab(at: selectedTabIndex)?.moduleGroupNodeInstances.count ?? 0
        let canvasPersonCount = tab.tiles.contains(where: containsPersonContent) ? 1 : 0
        return canvasPersonCount + graphCount
    }

    private func containsPersonContent(_ tile: DashboardTileModel) -> Bool {
        if case .person = tile.kind {
            return true
        }

        guard let modules = tile.modules else { return false }
        return modules.contains { module in
            if case .person = module.kind {
                return true
            }
            return false
        }
    }

    /// Toolbar + mode banner overlays.
    @ViewBuilder
    private func chromeOverlays() -> some View {
        #if os(iOS)
        DashboardModeBannerOverlay(
            isVisible: modeBannerVisible,
            text: modeBannerText,
            subtitle: modeBannerSubtitle ?? ((modeBannerVisible && modeBannerText == "Live Mode") ? "Double Tap to Exit" : nil),
            bottomPadding: 70
        )
        #else
        DashboardModeBannerOverlay(
            isVisible: modeBannerVisible,
            text: modeBannerText,
            subtitle: modeBannerSubtitle,
            bottomPadding: 70
        )
        #endif

        if let banner = activeNotificationBanner {
            let subtitle = banner.message.trimmingCharacters(in: .whitespacesAndNewlines)
            DashboardModeBannerOverlay(
                isVisible: true,
                text: banner.title,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                bottomPadding: 70
            )
        }

        if isLiveMode {
            liveModeTopChrome()
        }

        // Simple overlay toolbar for adding tiles + tab bar (hidden in Live Mode).
        // Keep it visually stable during tile drags; disable hit-testing instead of
        // hiding chrome on the first drag frame.
        if !isLiveMode {
            topToolbar()
                .allowsHitTesting(!isDraggingTilesOnCanvas || shouldForceToolbarVisible)
        }
    }

    fileprivate enum NavigableDashboardTabTarget: Hashable {
        case local(Int)
        case lan(LANSharedTabManifest)
    }

    fileprivate struct NavigableDashboardTabItem: Identifiable, Hashable {
        let id: String
        let title: String
        let target: NavigableDashboardTabTarget
    }

    private func localTabDisplayTitle(at index: Int) -> String {
        guard tabs.indices.contains(index) else { return "Tab" }
        let name = tabs[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Tab \(index + 1)" : name
    }

    private func lanTabDisplayTitle(_ manifest: LANSharedTabManifest) -> String {
        let tabName = manifest.tabName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTabName = tabName.isEmpty ? "Untitled Tab" : tabName
        let deviceName = manifest.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDeviceName = deviceName.isEmpty ? "LAN Device" : deviceName
        return "\(resolvedTabName) - \(resolvedDeviceName)"
    }

    private var navigableDashboardTabs: [NavigableDashboardTabItem] {
        let localItems = tabs.enumerated().map { index, _ in
            NavigableDashboardTabItem(
                id: "local-\(index)",
                title: localTabDisplayTitle(at: index),
                target: .local(index)
            )
        }

        guard lanHostingAllowed else { return localItems }

        let lanItems = lanService.remoteTabs.map { manifest in
            NavigableDashboardTabItem(
                id: "lan-\(manifest.shareId)",
                title: lanTabDisplayTitle(manifest),
                target: .lan(manifest)
            )
        }

        return localItems + lanItems
    }

    private var currentNavigableDashboardTabIndex: Int? {
        if let selectedLANShareId {
            return navigableDashboardTabs.firstIndex {
                if case .lan(let manifest) = $0.target {
                    return manifest.shareId == selectedLANShareId
                }
                return false
            }
        }

        return navigableDashboardTabs.firstIndex {
            if case .local(let index) = $0.target {
                return index == selectedTabIndex
            }
            return false
        }
    }

    private var liveModeSelectedTabTitle: String {
        guard let currentNavigableDashboardTabIndex,
              navigableDashboardTabs.indices.contains(currentNavigableDashboardTabIndex) else {
            return "Tab"
        }

        return navigableDashboardTabs[currentNavigableDashboardTabIndex].title
    }

    private var liveModeSelectedTabID: String? {
        guard let currentNavigableDashboardTabIndex,
              navigableDashboardTabs.indices.contains(currentNavigableDashboardTabIndex) else {
            return nil
        }

        return navigableDashboardTabs[currentNavigableDashboardTabIndex].id
    }

    private var canSelectPreviousLiveModeTab: Bool {
        guard let currentNavigableDashboardTabIndex else { return false }
        return currentNavigableDashboardTabIndex > 0
    }

    private var canSelectNextLiveModeTab: Bool {
        guard let currentNavigableDashboardTabIndex else { return false }
        return currentNavigableDashboardTabIndex < (navigableDashboardTabs.count - 1)
    }

    private func showLiveModeChrome() {
        liveModeChromeRevealWorkItem?.cancel()
        liveModeChromeRevealWorkItem = nil
        liveModeChromeHideWorkItem?.cancel()
        liveModeChromeHideWorkItem = nil
        liveModeChromeHideRespectsHover = true

        liveModeChromeDragProgress = 1
        withAnimation(.spring(response: 0.18, dampingFraction: 0.86, blendDuration: 0.1)) {
            isLiveModeChromeVisible = true
        }
    }

    /// Real-time drag tracking for revealing the live mode toolbar: the chrome's
    /// offset/opacity follow the gesture 1:1 as the user drags down from the
    /// top-center hot zone, like macOS Control Center or iOS Notification Center.
    private func handleLiveModeChromeDragChanged(_ value: DragGesture.Value) {
        guard isLiveMode else { return }
        let translation = value.translation.height
        guard translation > 0 else { return }

        if !isLiveModeChromeVisible {
            liveModeChromeRevealWorkItem?.cancel()
            liveModeChromeRevealWorkItem = nil
            liveModeChromeHideWorkItem?.cancel()
            liveModeChromeHideWorkItem = nil
            liveModeChromeDragProgress = 0
            isLiveModeChromeVisible = true
        }
        isLiveModeChromeInteracting = true
        liveModeChromeDragProgress = min(1, translation / liveModeChromeDragRevealDistance)
    }

    private func handleLiveModeChromeDragEnded(_ value: DragGesture.Value) {
        guard isLiveMode, isLiveModeChromeVisible else { return }
        isLiveModeChromeInteracting = false

        let translation = value.translation.height
        let shouldCommit = translation > liveModeChromeDragRevealDistance / 2
            || value.predictedEndTranslation.height > liveModeChromeDragRevealDistance

        if shouldCommit {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.86, blendDuration: 0.1)) {
                liveModeChromeDragProgress = 1
            }
            scheduleLiveModeChromeHide(delay: 4.0, respectsHover: false)
        } else {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.86, blendDuration: 0.1)) {
                liveModeChromeDragProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isLiveModeChromeVisible = false
                liveModeChromeDragProgress = 1
            }
        }
    }

    private func hideLiveModeChromeImmediately() {
        liveModeChromeRevealWorkItem?.cancel()
        liveModeChromeRevealWorkItem = nil
        liveModeChromeHideWorkItem?.cancel()
        liveModeChromeHideWorkItem = nil
        liveModeChromeHideRespectsHover = true
        isHoveringLiveModeChrome = false
        isLiveModeChromeInteracting = false

        withAnimation(.easeInOut(duration: 0.18)) {
            isLiveModeChromeVisible = false
        }
    }

    private func scheduleLiveModeChromeHide(delay: Double? = nil, respectsHover: Bool = true) {
        liveModeChromeHideWorkItem?.cancel()
        liveModeChromeHideRespectsHover = respectsHover
        guard isLiveMode else { return }

        let workItem = DispatchWorkItem {
            guard isLiveMode else { return }
            guard LiveModeChromeAutoHidePolicy.shouldHide(
                isHovering: isHoveringLiveModeChrome,
                isInteracting: isLiveModeChromeInteracting,
                respectsHover: respectsHover
            ) else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                isLiveModeChromeVisible = false
            }
            liveModeChromeHideRespectsHover = true
        }

        liveModeChromeHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (delay ?? liveModeChromeAutoHideDelay),
            execute: workItem
        )
    }

    private func beginLiveModeChromeHoverDwell() {
        liveModeChromeRevealWorkItem?.cancel()
        liveModeChromeHideWorkItem?.cancel()
        liveModeChromeHideWorkItem = nil

        let workItem = DispatchWorkItem {
            guard isLiveMode else { return }
            showLiveModeChrome()
            scheduleLiveModeChromeHide()
        }

        liveModeChromeRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + liveModeChromeRevealDelay, execute: workItem)
    }

    private func selectLANManifestFromUnifiedNavigation(_ manifest: LANSharedTabManifest) {
        selectedLANShareId = manifest.shareId
        selectedLANDeviceName = manifest.deviceName
        selectedLANPeerEndpointKey = nil
        recomputeLANMirrorScale()

        Task {
            await openLANMirror(manifest)
        }
    }

    private func selectNavigableDashboardTab(_ item: NavigableDashboardTabItem, animated: Bool = true) {
        switch item.target {
        case .local(let index):
            selectedLANShareId = nil
            selectedLANDeviceName = nil
            selectedLANPeerEndpointKey = nil
            lanMirrorReferenceCanvasSize = nil
            recomputeLANMirrorScale()
            selectTab(at: index, animated: animated)
        case .lan(let manifest):
            selectLANManifestFromUnifiedNavigation(manifest)
        }
    }

    private func selectNavigableDashboardTab(at index: Int, animated: Bool = true) {
        guard navigableDashboardTabs.indices.contains(index) else { return }
        selectNavigableDashboardTab(navigableDashboardTabs[index], animated: animated)
    }

    private func selectPreviousNavigableDashboardTab(animated: Bool = true) {
        guard let currentNavigableDashboardTabIndex else { return }
        selectNavigableDashboardTab(at: max(0, currentNavigableDashboardTabIndex - 1), animated: animated)
    }

    private func selectNextNavigableDashboardTab(animated: Bool = true) {
        guard let currentNavigableDashboardTabIndex else { return }
        selectNavigableDashboardTab(
            at: min(navigableDashboardTabs.count - 1, currentNavigableDashboardTabIndex + 1),
            animated: animated
        )
    }

    private func selectFirstNavigableDashboardTab(animated: Bool = true) {
        selectNavigableDashboardTab(at: 0, animated: animated)
    }

    private func selectLastNavigableDashboardTab(animated: Bool = true) {
        guard !navigableDashboardTabs.isEmpty else { return }
        selectNavigableDashboardTab(at: navigableDashboardTabs.count - 1, animated: animated)
    }

    private func selectLiveModeTab(_ item: NavigableDashboardTabItem) {
        selectNavigableDashboardTab(item)
        showLiveModeChrome()
        scheduleLiveModeChromeHide(respectsHover: false)
    }

    @ViewBuilder
    private func liveModeTopChrome() -> some View {
        #if os(iOS)
        if isIPad {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(width: liveModeChromeHotZoneWidth, height: iPadAutoHideToolbarEnabled ? 46 : 54)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showLiveModeChrome()
                            scheduleLiveModeChromeHide(delay: 4.0, respectsHover: false)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                                .onChanged(handleLiveModeChromeDragChanged)
                                .onEnded(handleLiveModeChromeDragEnded)
                        )

                    if isLiveModeChromeVisible {
                        DashboardLiveModeChromeView(
                            tabItems: navigableDashboardTabs,
                            selectedTabID: liveModeSelectedTabID,
                            selectedTitle: liveModeSelectedTabTitle,
                            canSelectPreviousTab: canSelectPreviousLiveModeTab,
                            canSelectNextTab: canSelectNextLiveModeTab,
                            onSelectTab: selectLiveModeTab,
                            onSelectPreviousTab: {
                                guard let currentNavigableDashboardTabIndex else { return }
                                selectLiveModeTab(navigableDashboardTabs[max(0, currentNavigableDashboardTabIndex - 1)])
                            },
                            onSelectNextTab: {
                                guard let currentNavigableDashboardTabIndex else { return }
                                selectLiveModeTab(
                                    navigableDashboardTabs[
                                        min(navigableDashboardTabs.count - 1, currentNavigableDashboardTabIndex + 1)
                                    ]
                                )
                            },
                            onToggleLiveMode: {
                                showLiveModeChrome()
                                isLiveMode = false
                            },
                            onShowTabSettings: {
                                showLiveModeChrome()
                                showingPCOConfigForTab = true
                            },
                            onShowRosters: {
                                showLiveModeChrome()
                                showingRosters = true
                            },
                            onShowSettings: {
                                showLiveModeChrome()
                                showingSettings = true
                            },
                            onInteractionBegan: {
                                liveModeChromeHideWorkItem?.cancel()
                                isLiveModeChromeInteracting = true
                                showLiveModeChrome()
                            },
                            onInteractionEnded: {
                                isLiveModeChromeInteracting = false
                                scheduleLiveModeChromeHide(respectsHover: false)
                            },
                            isGraphMode: layoutMode == .graph,
                            showAutomationProBadge: !subscriptionManager.hasPro,
                            onToggleGraphCanvas: {
                                showLiveModeChrome()
                                handleToggleGraphCanvas()
                            }
                        )
                        .padding(.top, 8)
                        .offset(y: (liveModeChromeDragProgress - 1) * liveModeChromeDragRevealDistance)
                        .opacity(liveModeChromeDragProgress)
                        .transition(
                            .move(edge: .top)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.985, anchor: .top))
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        #else
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(width: liveModeChromeHotZoneWidth, height: 14)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            beginLiveModeChromeHoverDwell()
                        } else {
                            liveModeChromeRevealWorkItem?.cancel()
                            liveModeChromeRevealWorkItem = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .local)
                            .onChanged(handleLiveModeChromeDragChanged)
                            .onEnded(handleLiveModeChromeDragEnded)
                    )

                if isLiveModeChromeVisible {
                    DashboardLiveModeChromeView(
                        tabItems: navigableDashboardTabs,
                        selectedTabID: liveModeSelectedTabID,
                        selectedTitle: liveModeSelectedTabTitle,
                        canSelectPreviousTab: canSelectPreviousLiveModeTab,
                        canSelectNextTab: canSelectNextLiveModeTab,
                        onSelectTab: selectLiveModeTab,
                        onSelectPreviousTab: {
                            guard let currentNavigableDashboardTabIndex else { return }
                            selectLiveModeTab(navigableDashboardTabs[max(0, currentNavigableDashboardTabIndex - 1)])
                        },
                        onSelectNextTab: {
                            guard let currentNavigableDashboardTabIndex else { return }
                            selectLiveModeTab(
                                navigableDashboardTabs[
                                    min(navigableDashboardTabs.count - 1, currentNavigableDashboardTabIndex + 1)
                                ]
                            )
                        },
                        onToggleLiveMode: {
                            showLiveModeChrome()
                            isLiveMode = false
                        },
                        onShowTabSettings: {
                            showLiveModeChrome()
                            showingPCOConfigForTab = true
                        },
                        onShowRosters: {
                            showLiveModeChrome()
                            showingRosters = true
                        },
                        onShowSettings: {
                            showLiveModeChrome()
                            showingSettings = true
                        },
                        onInteractionBegan: {
                            liveModeChromeHideWorkItem?.cancel()
                            isLiveModeChromeInteracting = true
                            showLiveModeChrome()
                        },
                        onInteractionEnded: {
                            isLiveModeChromeInteracting = false
                            scheduleLiveModeChromeHide(respectsHover: false)
                        },
                        isGraphMode: layoutMode == .graph,
                        showAutomationProBadge: !subscriptionManager.hasPro,
                        onToggleGraphCanvas: {
                            showLiveModeChrome()
                            handleToggleGraphCanvas()
                        }
                    )
                    .padding(.top, 8)
                    .offset(y: (liveModeChromeDragProgress - 1) * liveModeChromeDragRevealDistance)
                    .opacity(liveModeChromeDragProgress)
                    .onHover { hovering in
                        isHoveringLiveModeChrome = hovering
                        if hovering {
                            guard LiveModeChromeAutoHidePolicy.shouldPauseScheduledHideForHover(
                                respectsHover: liveModeChromeHideRespectsHover
                            ) else { return }
                            liveModeChromeHideWorkItem?.cancel()
                            liveModeChromeHideWorkItem = nil
                            showLiveModeChrome()
                        } else {
                            scheduleLiveModeChromeHide()
                        }
                    }
                    .transition(
                        .move(edge: .top)
                            .combined(with: .scale(scale: 0.985, anchor: .top))
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        #endif
    }

    @ViewBuilder
    private func logExportProgressOverlay() -> some View {
        if isPreparingLogExport {
            ZStack {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Preparing Log Export")
                        .font(.headline)
                    Text("Compiling diagnostics and archived logs...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 20, y: 10)
                .padding(24)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func mainCenterAndInspector(proxy: GeometryProxy) -> some View {
        let overviewWidth: CGFloat = isTileOverviewVisible ? overviewPanelWidth : 0
        // Reserve space for the left overview sidebar in layout.
        // The inspector floats above the right side as an overlay and does not change canvas width.
        let reservedWidth = overviewWidth
        let effectiveWidth = max(proxy.size.width - reservedWidth, 0)

        let canvasStack = ZStack(alignment: .topLeading) {
            canvasBackgroundView()
            gridLayer()
            tilesLayer()
            guidesLayer()
            selectionActionToolbarLayer()
            selectionOverlay()
        }
        .tutorialAnchor("root.canvas")

        let graphStack = ZStack(alignment: .topLeading) {
            Color.black
                .ignoresSafeArea()

            if let tabBinding = resolvedGraphTabBinding {
                GraphDashboardView(
                    tab: tabBinding,
                    isLiveMode: isLiveMode,
                    lanPeers: lanService.peers.filter { lanService.isPeerEnabled($0) },
                    lanNotificationsEnabled: subscriptionManager.hasPro,
                    externalDevicesSnapshot: ExternalDevicesStore.shared.currentSnapshot().devices,
                    tilesSnapshot: graphTilesSnapshot,
                    pcoRundownSnapshotTitles: rundownTitlesSnapshot,
                    onGraphChanged: {
                        saveState.hasUnsavedChanges = true
                        scheduleTabsSaveDebounced(reconcileGraphNodes: false)
                    }
                )
                // Force recreation per tab so stale @State (positions, selections)
                // doesn't carry over, and onAppear fires fresh on every tab switch.
                .id(tabBinding.wrappedValue.id)
                .onAppear {
                    selectedTileIDs.removeAll()
                    editingTileID = nil
                    isInspectorVisible = false
                }
            }
        }
        .tutorialAnchor("root.graph")
        let base = FlipContainer(
            isFlipped: isGraphLayoutActive,
            onFlipBegan: { _ in
                modeBannerVisible = false
            },
            onFlipCompleted: { flipped in
                // Show AFTER the flip settles.
                modeBannerText = flipped ? "Automation View" : "Canvas View"
                modeBannerSubtitle = flipped ? "Beta" : nil
                withAnimation(.easeInOut(duration: 0.18)) {
                    modeBannerVisible = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        modeBannerVisible = false
                    }
                }
            }
        ) {
            canvasStack
                .allowsHitTesting(!isGraphLayoutActive)
        } back: {
            graphStack
                .allowsHitTesting(isGraphLayoutActive)
        }
        .frame(width: effectiveWidth, height: proxy.size.height, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if showSystemUsage {
                SystemUsageOverlayView(
                    showsLANConnections: lanHostingAllowed,
                    lanPeerCount: lanService.peers.count
                )
                    .padding(12)
            }
        }
        .onAppear {
            updateCanvasViewportSize(for: proxy.size)
            if gridBackgroundOpacity < 0.02 {
                gridBackgroundOpacity = 0.35
            }
            applyDeviceFitScaleIfNeeded()
            if needsInitialViewportFit {
                needsInitialViewportFit = false
                fitCanvasToViewport()
            }
        }
        .onChange(of: proxy.size, initial: false) { _, newSize in
            updateCanvasViewportSize(for: newSize)
        }
        .onChange(of: canvasBoundsStore.size, initial: false) { _, _ in
            // Canvas document-default changes no longer auto-scale tiles.
            // Tiles are already in the correct coordinate space.
        }
        .onChange(of: isInspectorVisible, initial: false) { _, _ in
            updateCanvasViewportSize(for: proxy.size)
        }
        .onChange(of: isTileOverviewVisible, initial: false) { _, _ in
            updateCanvasViewportSize(for: proxy.size)
        }
        //
        //        .contextMenu {
        //            // Canvas-level Add menu when not in Live Mode.
        //            if !isLiveMode && !draggingDisabled {
        //                Button {
        //                    addEmptyTile(openModuleCatalog: true)
        //                } label: {
        //                    Label("Add Tile", systemImage: "plus")
        //                }
        //
        //                Divider()
        //
        //                Button("Add Horizontal Guide") {
        //                    canvasGuides.addGuide(
        //                        .horizontal,
        //                        canvasSize: canvasSize,
        //                        gridSize: CGFloat(gridSizeSetting)
        //                    )
        //                    saveGuides()
        //                }
        //
        //                Button("Add Vertical Guide") {
        //                    canvasGuides.addGuide(
        //                        .vertical,
        //                        canvasSize: canvasSize,
        //                        gridSize: CGFloat(gridSizeSetting)
        //                    )
        //                    saveGuides()
        //                }
        //                Divider()
        //
        //                Button("Clear guides") {
        //                    canvasGuides.removeAll()
        //                }
        //                .disabled(canvasGuides.isEmpty)
        //            }
        //        }
        //
        //        .simultaneousGesture(
        //            LongPressGesture(minimumDuration: 0.35)
        //                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
        //                .onEnded { value in
        //                    guard !isLiveMode else { return }
        //                    if case .second(true, let drag?) = value {
        //                        canvasMenuLocation = drag.location
        //                        isCanvasMenuPresented = true
        //                    }
        //                }
        //        )
        .overlay(alignment: .bottomTrailing) {
            let hiddenGraphNodeCount = hiddenGraphNodeCountForAddMenu
            let hiddenTileCount = hiddenTileCountForAddMenu
            let showGraphPerformanceNotice = shouldShowGraphPerformanceNotice

            ZStack(alignment: .bottomTrailing) {
                FloatingAddMenuView(
                    isLiveMode: isLiveMode,
                    layoutMode: (layoutMode == .canvas ? .canvas : .graph),
                    isAddMenuOpen: $isAddMenuOpen,
                    selectedTileCount: selectedTileIDs.count,
                    selectedGraphNodeCount: selectedGraphNodeCount,
                    deleteSelectedTiles: {
                        self.deleteSelectedTiles()
                    },
                    deleteSelectedGraphNodes: {
                        NotificationCenter.default.post(name: .prodLinkDeleteGraphSelectionRequested, object: nil)
                    },
                    addTile: {
                        addEmptyTile(openModuleCatalog: true)
                    },
                    addVerticalGuide: {
                        if !showGuidesEnabled {
                            showGuidesEnabled = true
                        }
                        mutateSelectedTabGuides { guides in
                            guides.addGuide(
                                .vertical,
                                canvasSize: canvasSize,
                                gridSize: CGFloat(gridSizeSetting)
                            )
                        }
                    },
                    addHorizontalGuide: {
                        if !showGuidesEnabled {
                            showGuidesEnabled = true
                        }
                        mutateSelectedTabGuides { guides in
                            guides.addGuide(
                                .horizontal,
                                canvasSize: canvasSize,
                                gridSize: CGFloat(gridSizeSetting)
                            )
                        }
                    },
                    addNode: {
                        NotificationCenter.default.post(
                            name: Notification.Name("Relay.GraphAddNodeRequested"),
                            object: nil
                        )
                    },
                    hiddenNodesCount: hiddenGraphNodeCount,
                    showHiddenNodes: {
                        NotificationCenter.default.post(name: .prodLinkUnhideAllGraphNodesRequested, object: nil)
                    },
                    hiddenTilesCount: hiddenTileCount,
                    showHiddenTiles: {
                        unhideAllTilesOnCurrentTab()
                    }
                )
                .alert(
                    pendingSharedSwitchHasExistingShared ? "Replace shared automation?" : "Share with all tabs?",
                    isPresented: $showSwitchToUniversalConfirmation
                ) {
                    Button(pendingSharedSwitchHasExistingShared ? "Replace" : "Share with all tabs",
                           role: pendingSharedSwitchHasExistingShared ? .destructive : nil) {
                        promoteSelectedOrPendingTabToShared()
                    }
                    if pendingSharedSwitchHasExistingShared {
                        Button("Use shared instead") {
                            adoptSharedForPendingTab()
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        pendingSharedSwitchTabID = nil
                    }
                } message: {
                    Text(pendingSharedSwitchHasExistingShared
                         ? "This tab's automation will replace the shared graph used by all shared tabs."
                         : "This tab's automation will become the shared graph used by all tabs set to \u{201C}All tabs\u{201D}.")
                }
                .tutorialAnchor("root.addMenu")

                if showGraphPerformanceNotice {
                    Button {
                        showGraphPerformanceNoticeDetails.toggle()
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.yellow)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.64)))
                            .overlay(Circle().stroke(Color.yellow.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Automation performance mode")
                    .popover(isPresented: $showGraphPerformanceNoticeDetails, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Large automation graph")
                                .font(.headline)

                            Text("To keep editing responsive, Relay can simplify unselected node cards when many nodes are visible.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(forceDetailedNodeRendering
                                 ? "Full node details are currently enabled. Responsiveness may decrease on very large graphs."
                                 : "Simplified node cards are currently enabled.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Toggle("Show full node details", isOn: $forceDetailedNodeRendering)

                            Text("Selected or actively linked nodes still expand for editing when simplification is on.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(width: 360)
                    }
                    .padding(.trailing, 100)
                    .padding(.bottom, 45)
                }
            }
            .allowsHitTesting(!isDraggingTilesOnCanvas)
        }
        .onChange(of: isDraggingTilesOnCanvas, initial: false) { _, dragging in
            postTileDragViewportOverrideWorkItem?.cancel()
            if dragging {
                isPostTileDragViewportOverrideActive = true
                isAddMenuOpen = false
            } else {
                let viewportWorkItem = DispatchWorkItem {
                    isPostTileDragViewportOverrideActive = false
                }
                postTileDragViewportOverrideWorkItem = viewportWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: viewportWorkItem)
            }
        }

        // Compose chrome as a sibling overlay (not a modifier on the flipped view)
        // so it doesn't inherit the flip animation transaction.
        let composed = ZStack(alignment: .topLeading) {
            base

            chromeOverlays()
                .zIndex(900_000)

            logExportProgressOverlay()
                .zIndex(910_000)
        }

        withDashboardFileIOAndDialogs(
            withDashboardPersistenceHandlers(composed)
        )
    }
    // MARK: - Legacy Import Migration (tile-level fields -> modules)

        /// Older dashboard files (pre "pluginized modules") stored content directly on the tile
        /// (e.g. `shureChannelSelection`) and often had `kind = empty` with no `modules`.
        /// This migration reconstructs modern `tile.modules` so imported dashboards render.
        private func migrateLegacyTilesToModulesIfNeeded() {
            guard !tabs.isEmpty else { return }

            var didChange = false

            for tabIndex in tabs.indices {
                for tileIndex in tabs[tabIndex].tiles.indices {
                    var tile = tabs[tabIndex].tiles[tileIndex]

                    let existingModules = tile.modules ?? []

                    // If the tile already has modules, do not modify it.
                    if !existingModules.isEmpty {
                        continue
                    }

                    // --- Legacy reconstruction path ---
                    // Build module list based on legacy tile fields.
                    var reconstructed: [DashboardModuleModel] = []

                    // 1) Legacy Shure: tile.shureChannelSelection existed on the tile.
                    if let legacySelection = tile.shureChannelSelection {
                        var cfg = ShureModuleConfig.default()
                        cfg.selectedChannel = legacySelection

                        // Legacy tiles had a single Shure module worth of content.
                        let shureModule = DashboardModuleModel(
                            kind: .shureWireless,
                            order: 0,
                            shureConfig: cfg
                        )
                        reconstructed.append(shureModule)

                    } else {
                        // 2) Legacy tile.kind fallback (best-effort).
                        switch tile.kind {
                        case .empty:
                            // Leave truly empty tiles empty.
                            break

                        case .person(let personModel):
                            reconstructed.append(DashboardModuleModel(kind: .person(personModel), order: 0))

                        case .time:
                            reconstructed.append(DashboardModuleModel(kind: .time, order: 0, timeConfig: TimeModuleConfig.default()))

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

                    // Apply if we actually built anything meaningful.
                    if !reconstructed.isEmpty {
                        tile.modules = reconstructed
                        // When module-first, legacy kind is not meaningful.
                        tile.kind = .empty
                        tabs[tabIndex].tiles[tileIndex] = tile
                        didChange = true
                    }
                }
            }

            if didChange {
                saveState.hasUnsavedChanges = true
                scheduleTabsSaveDebounced()

                #if DEBUG
                let totalTiles = tabs.first?.tiles.count ?? 0
                let tilesWithModules = tabs.first?.tiles.filter { !($0.modules?.isEmpty ?? true) }.count ?? 0
                let moduleTotal = tabs.first?.tiles.reduce(0) { $0 + ($1.modules?.count ?? 0) } ?? 0
                print("[Import] MIGRATED tiles=\(totalTiles) tilesWithModules=\(tilesWithModules) moduleTotal=\(moduleTotal)")
                #endif
            }
        }
    // MARK: - View Composition Helpers (reduce type-check complexity)

// MARK: - Automation Runtime (runs in both Canvas + Graph modes)
@ObservedObject private var graphAutomationRuntime = GraphAutomationRuntime.shared
@State private var didStartGraphAutomationRuntime: Bool = false
@State private var didInstallSendAllListener: Bool = false

    /// Safely read UI/main-actor state from any thread.
    /// If already on the main thread, executes inline.
    /// If called from a background thread, synchronously hops to main.
    private func onMainSync<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        var result: T! = nil
        DispatchQueue.main.sync {
            result = work()
        }
        return result
    }

    /// Best-effort: build "Position — Name" labels for the active tab.
    /// This is used by Send-All to match the keys used in `consoleChannelAssignments`.
    private func activeTabPeopleLabels() -> [String] {
        guard tabs.indices.contains(selectedTabIndex) else { return [] }
        let tab = tabs[selectedTabIndex]

        func unwrapOptional(_ any: Any) -> Any? {
            let m = Mirror(reflecting: any)
            guard m.displayStyle == .optional else { return any }
            return m.children.first?.value
        }

        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 1) If tab already has a cached array of formatted labels, use it.
        let cachedArrayKeys: Set<String> = [
            "pcoPositionAssignments",
            "pcoAllPositionAssignments",
            "peopleLabels",
            "peopleLabelsInOrder",
            "pcoPeopleLabels"
        ]

        for child in Mirror(reflecting: tab).children {
            guard let label = child.label, cachedArrayKeys.contains(label) else { continue }

            if let arr = unwrapOptional(child.value) as? [String] {
                let cleaned = arr.map(norm).filter { !$0.isEmpty }
                if !cleaned.isEmpty { return cleaned }
            }

            // Common mapping shapes: [String: String] (position -> person)
            if let dict = unwrapOptional(child.value) as? [String: String] {
                let labels = dict
                    .map { "\(norm($0.key)) — \(norm($0.value))" }
                    .map(norm)
                    .filter { !$0.isEmpty && !$0.hasPrefix("—") }
                    .sorted()
                if !labels.isEmpty { return labels }
            }
        }

        // 2) If we find a collection of structs/classes with position + name fields, pack them.
        let m = Mirror(reflecting: tab)
        for child in m.children {
            guard let label = child.label else { continue }
            guard label.lowercased().contains("position") || label.lowercased().contains("assignment") else { continue }

            guard let v = unwrapOptional(child.value) else { continue }
            let vm = Mirror(reflecting: v)
            guard vm.displayStyle == .collection else { continue }

            var packed: [String] = []
            for item in vm.children.map({ $0.value }) {
                let im = Mirror(reflecting: item)
                var pos: String? = nil
                var name: String? = nil

                for f in im.children {
                    guard let k = f.label else { continue }
                    let key = k.lowercased()
                    if pos == nil && (key.contains("position") || key == "role") {
                        if let s = unwrapOptional(f.value) as? String { pos = norm(s) }
                    }
                    if name == nil && (key.contains("person") || key.contains("name")) {
                        if let s = unwrapOptional(f.value) as? String { name = norm(s) }
                    }
                }

                let p = norm(pos ?? "")
                let n = norm(name ?? "")
                if !p.isEmpty && !n.isEmpty {
                    packed.append("\(p) — \(n)")
                }
            }

            let cleaned = packed.map(norm).filter { !$0.isEmpty }
            if !cleaned.isEmpty { return cleaned }
        }

        return []
    }

    private func withDashboardPersistenceHandlers<Content: View>(_ content: Content) -> some View {
        // Break the long modifier chain into chunks to avoid type-check timeouts.
        let a = content
            .onChange(of: tabs, initial: false) { _, dragging in
                // Defer mutations to avoid "Publishing changes from within view updates" and UI snap-back.
                DispatchQueue.main.async {
                    let shouldMarkUnsavedChanges =
                        !isReplacingDocumentState && Date() >= suppressUnsavedChangesUntil

                    // Keep selection index valid to avoid out-of-bounds crashes during delete/reorder/import.
                    if tabs.isEmpty {
                        selectedTabIndex = 0
                    } else if selectedTabIndex < 0 {
                        selectedTabIndex = 0
                    } else if selectedTabIndex >= tabs.count {
                        selectedTabIndex = tabs.count - 1
                    }

                    if shouldMarkUnsavedChanges {
                        saveState.hasUnsavedChanges = true
                    }

                    syncGraphAutomationRuntimeSnapshots()

                    // Keep automation runtime provider up-to-date (avoid stale tab copies).
                    graphAutomationRuntime.setActiveTabProvider { [weak lanService] in
                        _ = lanService // keep capture list non-empty and explicit; avoids capturing `tabs`.
                        guard layoutMode == .canvas else { return nil }
                        guard tabs.indices.contains(selectedTabIndex) else { return nil }
                        return tabs[selectedTabIndex]
                    }

                    // Don't spam LAN manifests while dragging or editing tab UI.
                    guard !isDraggingTilesOnCanvas else { return }
                    guard !isTabInteractionActive else { return }

                    // Debounced LAN update.
                    scheduleLANShareUpdateDebounced()
                }
            }
            .onChange(of: isInspectorVisible, initial: false) { _, visible in
                // When leaving the inspector, publish one consolidated LAN update.
                if !visible {
                    scheduleLANShareUpdateDebounced()
                }
            }

        let b = a
            .onReceive(NotificationCenter.default.publisher(for: .saveDashboardRequested)) { _ in
                documentController.saveCurrentDocumentAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lanImportRequested)) { note in
                guard let shareId = note.userInfo?["shareId"] as? String else { return }
                guard let manifest = lanService.remoteTabs.first(where: { $0.shareId == shareId }) else { return }

                DispatchQueue.main.async {
                    pendingLANImportManifest = manifest
                    showingLANImportDialog = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveDashboardQuickRequested)) { _ in
                documentController.saveCurrentDocument()
            }

        let c = b
            .onReceive(NotificationCenter.default.publisher(for: .openDashboardRequested)) { _ in
                documentController.openDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardAppTerminateRequested)) { _ in
                documentController.quitApplication()
            }
#if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .dashboardCloseWindowRequested)) { note in
                if let window = note.object as? NSWindow {
                    windowCloseCoordinator.markPendingClose(window: window)
                }
                requestCloseWindow()
            }
#endif
            .onReceive(NotificationCenter.default.publisher(for: .prodLinkShowSettings)) { _ in
                settingsInitialSelection = .general
                showingSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .prodLinkShowKeyboardShortcuts)) { _ in
                showingKeyboardShortcuts = true
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .relayShowSharedValues)) { _ in
                openWindow(id: "shared-values")
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .showAudioInputsConfigRequested)) { _ in
                settingsInitialSelection = .audio(.measurement)
                showingSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showTranscriptionInputsConfigRequested)) { _ in
                settingsInitialSelection = .audio(.transcription)
                showingSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .prodLinkExportLogsRequested)) { _ in
                print("[Logs] Export requested")
                exportLogs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .prodLinkDeleteSelectionRequested)) { _ in
                guard !shouldBlockDelete else { return }
                deleteSelectedTiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .prodLinkGraphSelectionCountChanged)) { note in
                selectedGraphNodeCount = (note.object as? Int) ?? 0
            }
            .onReceive(NotificationCenter.default.publisher(for: .prodLinkToggleVisibilityRequested)) { _ in
                if layoutMode == .graph {
                    let hiddenGraphNodeCount: Int = {
                        guard tabs.indices.contains(selectedTabIndex) else { return 0 }
                        return effectiveGraphForTab(at: selectedTabIndex)?.hiddenNodeIds.count ?? 0
                    }()
                    if hiddenGraphNodeCount > 0 {
                        NotificationCenter.default.post(name: .prodLinkUnhideAllGraphNodesRequested, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .prodLinkToggleGraphNodeVisibilityRequested, object: nil)
                    }
                } else if currentTabHasHiddenTiles() {
                    unhideAllTilesOnCurrentTab()
                } else {
                    toggleVisibilityForSelectedTiles()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .duplicateTileRequested)) { _ in
                duplicateSelectedTiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .createTileGroupRequested)) { _ in
                guard !isLiveMode else { return }
                guard !isTextInputActive else { return }
                guard selectedTileIDs.count >= 1 else { return }
                tileGroupSheetMode = .create
                editingTileGroupID = nil
                seedTileGroupDraft()
                if showingTileGroupSheet {
                    showingTileGroupSheet = false
                    DispatchQueue.main.async {
                        showingTileGroupSheet = true
                    }
                } else {
                    showingTileGroupSheet = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .prodlinkOpenExternalDeviceSettings)) { note in
                guard let id = note.object as? ExternalDeviceConfig.ID else { return }

                // Deep-link into the editor for this device
                externalDevicesEntryMode = .editDeviceOnly
                externalDevicesInitialSelection = id

                // Present on next runloop so the sheet reads the updated selection
                DispatchQueue.main.async {
                    showExternalDevicesSettingsSheet = true
                }
            }

        let d = c
            // View menu: Cmd+1 / Cmd+2
            .onReceive(NotificationCenter.default.publisher(for: .dashboardCanvasViewRequested)) { _ in
                guard layoutMode != .canvas else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    layoutMode = .canvas
                    dashboardViewMode = "canvas"

                    // Resume LAN mirror polling when leaving Graph/Automation view.
                    if selectedLANShareId != nil {
                        startLANMirrorRefreshLoop()
                    }

                    // Match toolbar behavior when switching modes.
                    clearSelectionForViewSwitch()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardAutomationViewRequested)) { _ in
                guard layoutMode != .graph else { return }
                if subscriptionManager.hasPro {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        layoutMode = .graph
                        dashboardViewMode = "automation"

                        // Stop LAN mirror polling while in Graph/Automation view.
                        lanMirrorRefreshTask?.cancel()
                        lanMirrorRefreshTask = nil

                        // Match toolbar behavior when switching modes.
                        clearSelectionForViewSwitch()
                    }

                    if !automationTutorialSeen {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            tutorialController.start(kind: .proAutomation, hasPro: true)
                            automationTutorialSeen = true
                        }
                    }
                } else {
                    tutorialController.start(kind: .lockedAutomationPreview, hasPro: false)
                    automationPreviewSeen = true
                    return
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.appControl)) { note in
                handleAppControlNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardSelectFirstTabRequested)) { _ in
                performAppControlAction(.selectFirstTab)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardAddTabRequested)) { _ in
                addTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardSelectPreviousTabRequested)) { _ in
                performAppControlAction(.selectPreviousTab)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardSelectNextTabRequested)) { _ in
                performAppControlAction(.selectNextTab)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardSelectLastTabRequested)) { _ in
                performAppControlAction(.selectLastTab)
            }

        let e = d
            // Keep View menu checkmarks in sync with the actual mode (fix stale AppStorage on launch)
            .onAppear {
                dashboardViewMode = (layoutMode == .graph) ? "automation" : "canvas"
            }
            .onAppear {
                if !didStartGraphAutomationRuntime {
                    didStartGraphAutomationRuntime = true
                    graphAutomationRuntime.start(center: .default)
                }
                syncGraphAutomationRuntimeSnapshots()
                // Install the always-on Send-All listener once so Canvas mode can execute console actions.
                if !didInstallSendAllListener {
                    didInstallSendAllListener = true

                    GraphActionExecutor.installSendAllToConsolesListener(
                        snapshotDevicesProvider: {
                            onMainSync {
                                ExternalDevicesStore.shared.currentSnapshot().devices.map { $0 as Any }
                            }
                        },
                        rundownTitlesProvider: {
                            onMainSync {
                                guard tabs.indices.contains(selectedTabIndex) else { return [] }
                                return snapshotRundownTitles(for: tabs[selectedTabIndex])
                            }
                        },
                        peopleLabelsProvider: {
                            onMainSync {
                                activeTabPeopleLabels()
                            }
                        },
                        linkedConsoleIdsProvider: {
                            onMainSync {
                                guard tabs.indices.contains(selectedTabIndex) else { return [] }
                                let tabAny: Any = tabs[selectedTabIndex]

                                func unwrapOptional(_ any: Any) -> Any? {
                                    let m = Mirror(reflecting: any)
                                    guard m.displayStyle == .optional else { return any }
                                    return m.children.first?.value
                                }

                                let mirror = Mirror(reflecting: tabAny)
                                let keys: Set<String> = ["graph", "dashboardGraph", "automationGraph"]

                                for child in mirror.children {
                                    guard let label = child.label, keys.contains(label) else { continue }
                                    if let g = unwrapOptional(child.value) as? DashboardGraph {
                                        return GraphActionExecutor.linkedConsoleExternalDeviceIds(in: g)
                                    }
                                }
                                return []
                            }
                        },
                        pcoRundownLinkedConsoleIdsProvider: {
                            onMainSync {
                                guard tabs.indices.contains(selectedTabIndex) else { return Set<UUID>() }
                                let tab = tabs[selectedTabIndex]

                                // 1) Collect node ids for PCO Rundown sender nodes in this tab.
                                // Module-first, with legacy fallback.
                                let pcoTileNodeIds: Set<UUID> = Set(tab.tiles.compactMap { tile in
                                    if let modules = tile.modules {
                                        for m in modules {
                                            // Avoid hard-typing against enum cases here; keep it resilient.
                                            if String(describing: m.kind).contains("pcoRundown") {
                                                return tile.id
                                            }
                                        }
                                    }
                                    // Legacy fallback
                                    if String(describing: tile.kind).contains("pco") {
                                        return tile.id
                                    }
                                    return nil
                                })

                                guard !pcoTileNodeIds.isEmpty else { return Set<UUID>() }

                                // 2) Extract the graph model from the tab (same reflection approach as linkedConsoleIdsProvider).
                                let tabAny: Any = tab

                                func unwrapOptional(_ any: Any) -> Any? {
                                    let m = Mirror(reflecting: any)
                                    guard m.displayStyle == .optional else { return any }
                                    return m.children.first?.value
                                }

                                let mirror = Mirror(reflecting: tabAny)
                                let keys: Set<String> = ["graph", "dashboardGraph", "automationGraph"]

                                var graph: DashboardGraph? = nil
                                for child in mirror.children {
                                    guard let label = child.label, keys.contains(label) else { continue }
                                    if let g = unwrapOptional(child.value) as? DashboardGraph {
                                        graph = g
                                        break
                                    }
                                }
                                guard let g = graph else { return Set<UUID>() }

                                // 3) Find console-node ids directly linked FROM a PCO Rundown node.
                                let linkedConsoleNodeIds: Set<UUID> = Set(
                                    g.links
                                        .filter { $0.isEnabled }
                                        .filter { pcoTileNodeIds.contains($0.fromTileId) }
                                        .map { $0.toTileId }
                                )

                                guard !linkedConsoleNodeIds.isEmpty else { return Set<UUID>() }

                                // 4) Map console node ids -> externalDeviceIds using the SAME hashing as GraphDashboardView.
                                func graphNodeId(forExternalDeviceId id: UUID) -> UUID {
                                    let data = Data(id.uuidString.utf8)
                                    let digest = SHA256.hash(data: data)
                                    let bytes = Array(digest.prefix(16))

                                    var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
                                        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

                                    withUnsafeMutableBytes(of: &uuidBytes) { buf in
                                        buf.copyBytes(from: bytes)
                                    }

                                    return UUID(uuid: uuidBytes)
                                }

                                let liveConsoles = ExternalDevicesStore.shared.devices
                                    .filter { $0.kind == .audioConsole }

                                var externalIds = Set<UUID>()

                                // First pass: new-style nodes stored in consoleDeviceIdByNodeId
                                // (nodes created after the multi-instance feature landed use fresh UUIDs).
                                var unresolvedNodeIds = Set<UUID>()
                                for nodeId in linkedConsoleNodeIds {
                                    if let deviceId = g.consoleDeviceIdByNodeId[nodeId.uuidString] {
                                        externalIds.insert(deviceId)
                                    } else {
                                        unresolvedNodeIds.insert(nodeId)
                                    }
                                }

                                // Second pass: backward compat — old nodes used SHA-256-derived UUIDs.
                                if !unresolvedNodeIds.isEmpty {
                                    for dev in liveConsoles {
                                        let nodeId = graphNodeId(forExternalDeviceId: dev.id)
                                        if unresolvedNodeIds.contains(nodeId) {
                                            externalIds.insert(dev.id)
                                        }
                                    }
                                }

                                return externalIds
                            }
                        },
                        log: { msg in
                            #if DEBUG
                            print(msg)
                            #endif
                        }
                    )
                }
                // In Canvas mode, enable runtime + provide the selected tab (avoid stale copies).
                graphAutomationRuntime.isEnabled = (layoutMode == .canvas)
                syncGraphAutomationRuntimeSnapshots()
                graphAutomationRuntime.setActiveTabProvider { [weak lanService] in
                    _ = lanService
                    guard layoutMode == .canvas else { return nil }
                    guard tabs.indices.contains(selectedTabIndex) else { return nil }
                    return tabs[selectedTabIndex]
                }
            }
            .onChange(of: layoutMode, initial: false) { _, isEnabled in
                dashboardViewMode = (layoutMode == .graph) ? "automation" : "canvas"
                // Avoid double-execution: GraphDashboardView handles automation while in graph mode.
                graphAutomationRuntime.isEnabled = (layoutMode == .canvas)
                syncGraphAutomationRuntimeSnapshots()
                graphAutomationRuntime.setActiveTabProvider { [weak lanService] in
                    _ = lanService
                    guard layoutMode == .canvas else { return nil }
                    guard tabs.indices.contains(selectedTabIndex) else { return nil }
                    return tabs[selectedTabIndex]
                }
                updateLANPollingState()
            }
            .onChange(of: selectedTabIndex, initial: false) { _, newValue in
                graphAutomationRuntime.isEnabled = (layoutMode == .canvas)
                syncGraphAutomationRuntimeSnapshots()
                graphAutomationRuntime.setActiveTabProvider { [weak lanService] in
                    _ = lanService
                    guard layoutMode == .canvas else { return nil }
                    guard tabs.indices.contains(selectedTabIndex) else { return nil }
                    return tabs[selectedTabIndex]
                }
                if tabs.indices.contains(newValue) {
                    NotificationCenter.default.post(
                        name: .relayTabDidChange,
                        object: nil,
                        userInfo: ["tabId": tabs[newValue].id, "tabIndex": newValue]
                    )
                }
            }

        let f = e
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSText.didBeginEditingNotification)) { _ in
                // During tab interactions (rename/drag/reorder), the toolbar manages focus.
                guard !isTabInteractionActive else { return }
                isTextInputActive = true
                updateLANPollingState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSText.didEndEditingNotification)) { _ in
                // During tab interactions (rename/drag/reorder), the toolbar manages focus.
                guard !isTabInteractionActive else { return }
                DispatchQueue.main.async {
                    isTextInputActive = false
                    updateLANPollingState()
                }
            }
            #elseif os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in
                isTextInputActive = true
                updateLANPollingState()
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in
                isTextInputActive = true
                updateLANPollingState()
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
                DispatchQueue.main.async {
                    isTextInputActive = false
                    updateLANPollingState()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in
                DispatchQueue.main.async {
                    isTextInputActive = false
                    updateLANPollingState()
                }
            }
            #endif
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("Relay.ToggleLiveModeRequested")
                )
            ) { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    isLiveMode.toggle()

                    if isLiveMode {
                        // When entering live mode, hide the inspector and clear the editing tile.
                        isInspectorVisible = false
                        editingTileID = nil
                    }

                    let caption = isLiveMode ? "Live Mode" : "Edit Mode"
                    modeBannerText = caption
                    modeBannerSubtitle = nil
                    modeBannerVisible = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        // Only hide if we're still showing the same caption (prevents race conditions).
                        if modeBannerText == caption {
                            modeBannerVisible = false
                        }
                    }
                }
            }
            #if os(macOS)
            .onDeleteCommand {
                guard !shouldBlockDelete else { return }
                deleteSelectedTiles()
            }
            #endif

        return f
    }

    // MARK: - Debug Logging for Imported External Devices

#if DEBUG
    /// Logs a readable summary of imported external devices for debugging import issues.
    private func logImportedExternalDevices(_ snapshot: ExternalDevicesStore.Snapshot?, context: String) {
        guard let snapshot else {
            print("[ExternalDevices][Import] \(context): snapshot = nil")
            return
        }

        print("[ExternalDevices][Import] \(context): devices=\(snapshot.devices.count) shureSelectedChannel=\(snapshot.shureSelectedChannel != nil ? "yes" : "no")")

        // Dump a readable summary of each device
        for (idx, dev) in snapshot.devices.enumerated() {
            // Best-effort fields (keep resilient across model changes)
            let kind = String(describing: dev.kind)
            let name = (Mirror(reflecting: dev).children.first { $0.label == "name" }?.value as? String) ??
                       (Mirror(reflecting: dev).children.first { $0.label == "deviceName" }?.value as? String) ??
                       (Mirror(reflecting: dev).children.first { $0.label == "label" }?.value as? String) ??
                       "(unnamed)"

            let ip = (Mirror(reflecting: dev).children.first { $0.label == "ip" }?.value as? String) ??
                     (Mirror(reflecting: dev).children.first { $0.label == "host" }?.value as? String) ??
                     (Mirror(reflecting: dev).children.first { $0.label == "address" }?.value as? String) ??
                     "(no ip)"

            // Ports can be Int or String depending on older models
            func intFromAny(_ any: Any?) -> Int? {
                guard let any else { return nil }
                if let i = any as? Int { return i }
                if let s = any as? String { return Int(s) }
                let m = Mirror(reflecting: any)
                if m.displayStyle == .optional, let v = m.children.first?.value {
                    if let i = v as? Int { return i }
                    if let s = v as? String { return Int(s) }
                }
                return nil
            }

            let portAny = Mirror(reflecting: dev).children.first { $0.label == "port" }?.value
            let oscPortAny = Mirror(reflecting: dev).children.first { $0.label == "oscPort" }?.value
            let apiPortAny = Mirror(reflecting: dev).children.first { $0.label == "apiPort" }?.value
            let port = intFromAny(portAny)
            let oscPort = intFromAny(oscPortAny)
            let apiPort = intFromAny(apiPortAny)

            print("  [\(idx)] kind=\(kind) name=\(name) ip=\(ip) port=\(port.map(String.init) ?? "-") osc=\(oscPort.map(String.init) ?? "-") api=\(apiPort.map(String.init) ?? "-")")
        }
    }
#endif

    private func externalDevicesSnapshotHasChanges(_ incoming: ExternalDevicesStore.Snapshot) -> Bool {
        let current = ExternalDevicesStore.shared.currentSnapshot()

        func key(for d: ExternalDeviceConfig) -> String {
            let host = d.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !host.isEmpty && d.port != 0 {
                return "\(d.kind.rawValue)|\(host)|\(d.port)"
            }

            let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !name.isEmpty {
                let model = (d.consoleModelIdentifier ?? d.shureModelIdentifier ?? d.sennheiserModelIdentifier ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return "\(d.kind.rawValue)|name:\(name)|model:\(model)"
            }

            return "\(d.kind.rawValue)|id:\(d.id.uuidString.lowercased())"
        }

        let zeroID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        func normalizedDevice(_ d: ExternalDeviceConfig) -> ExternalDeviceConfig {
            var copy = d
            copy.id = zeroID
            copy.host = copy.host.lowercased()
            return copy
        }

        func mapByKey(_ devices: [ExternalDeviceConfig]) -> [String: ExternalDeviceConfig] {
            var result: [String: ExternalDeviceConfig] = [:]
            for device in devices {
                result[key(for: device)] = normalizedDevice(device)
            }
            return result
        }

        let currentByKey = mapByKey(current.devices)
        let incomingByKey = mapByKey(incoming.devices)

        if currentByKey.count != incomingByKey.count {
            return true
        }

        let currentKeys = Set(currentByKey.keys)
        let incomingKeys = Set(incomingByKey.keys)
        if currentKeys != incomingKeys {
            return true
        }

        for key in currentKeys {
            if currentByKey[key] != incomingByKey[key] {
                return true
            }
        }

        func normalizedShureSelection(_ snap: ExternalDevicesStore.Snapshot) -> (key: String, channel: Int)? {
            guard let sel = snap.shureSelectedChannel else { return nil }
            guard let device = snap.devices.first(where: { $0.id == sel.deviceID }) else { return nil }
            return (key(for: device), sel.channelIndex)
        }

        let currentSel = normalizedShureSelection(current)
        let incomingSel = normalizedShureSelection(incoming)
        if currentSel?.key != incomingSel?.key || currentSel?.channel != incomingSel?.channel {
            return true
        }

        return false
    }

    private func captureSettingsSnapshot() -> DashboardSettingsSnapshot {
        let defaults = UserDefaults.standard

        let oscEnabled = defaults.bool(forKey: "osc.global.enabled")
        let oscPort = defaults.object(forKey: "osc.global.port") as? Int ?? 8000

        let midiEnabled = defaults.bool(forKey: "midi.global.enabled")
        let midiSourceId = defaults.object(forKey: "midi.global.sourceId") as? Int ?? -1

        let proPresenterHost = defaults.string(forKey: "propresenter_host") ?? ""
        let proPresenterPort = defaults.object(forKey: "propresenter_port") as? Int ?? 1025
        let proPresenterPassword = ProPresenterPasswordPolicy.exportedPassword(ProPresenterKeychainStore.shared.password)
        let proPresenterTransport = defaults.string(forKey: "propresenter_transport") ?? ProPresenterTransport.auto.rawValue
        let proPresenterPollInterval = defaults.object(forKey: "propresenter_pollInterval") as? Double ?? 0.5
        let proPresenterProfilesData = defaults.data(forKey: "propresenter_profiles")
        let proPresenterActiveProfileID = defaults.string(forKey: "propresenter_activeProfileID")

        let resolumeProfilesData = defaults.data(forKey: "Relay.ResolumeProfilesStore.v1")
        let ndiPreferences = NDIPreferencesStore.load(defaults: defaults)

        let x32DeviceSettingsByKey: [String: DashboardSettingsSnapshot.X32DeviceSettings] = {
            let devices = ExternalDevicesStore.shared.devices
            var result: [String: DashboardSettingsSnapshot.X32DeviceSettings] = [:]

            for device in devices {
                let key = "\(device.kind.rawValue)|\(device.host.lowercased())|\(device.port)"
                let syncMapKey = "prodlink.x32sync.map.\(device.id.uuidString)"
                let syncTimestampKey = "prodlink.x32sync.ts.\(device.id.uuidString)"
                let showSendModeKey = "prodlink.x32show.sendmode.\(device.id.uuidString)"

                var settings = DashboardSettingsSnapshot.X32DeviceSettings()
                if let data = defaults.data(forKey: syncMapKey),
                   let decoded = try? JSONDecoder().decode([Int: String].self, from: data) {
                    settings.syncMap = decoded
                }
                if defaults.object(forKey: syncTimestampKey) != nil {
                    let ts = defaults.double(forKey: syncTimestampKey)
                    if ts > 0 { settings.syncTimestamp = ts }
                }
                if let raw = defaults.string(forKey: showSendModeKey) {
                    settings.showSendMode = raw
                }

                if settings.syncMap != nil || settings.syncTimestamp != nil || settings.showSendMode != nil {
                    result[key] = settings
                }
            }

            return result
        }()

        return DashboardSettingsSnapshot(
            oscEnabled: oscEnabled,
            oscPort: oscPort,
            midiEnabled: midiEnabled,
            midiSourceId: midiSourceId,
            proPresenterHost: proPresenterHost,
            proPresenterPort: proPresenterPort,
            proPresenterPassword: proPresenterPassword,
            proPresenterTransport: proPresenterTransport,
            proPresenterPollInterval: proPresenterPollInterval,
            proPresenterProfilesData: proPresenterProfilesData,
            proPresenterActiveProfileID: proPresenterActiveProfileID,
            resolumeProfilesData: resolumeProfilesData,
            ndiPreferredInterfaceID: ndiPreferences.preferredInterfaceID,
            ndiAllowAutoFallback: ndiPreferences.allowAutoFallback,
            x32DeviceSettingsByKey: x32DeviceSettingsByKey.isEmpty ? nil : x32DeviceSettingsByKey
        )
    }

    private func settingsSnapshotHasChanges(_ incoming: DashboardSettingsSnapshot) -> Bool {
        let current = captureSettingsSnapshot()
        return current != incoming
    }

    private func clearPendingImportedConfiguration() {
        pendingImportedExternalDevicesSnapshot = nil
        pendingImportedSettingsSnapshot = nil
        pendingImportedLANSettingsBundle = nil
    }

    private func applySettingsSnapshot(_ snapshot: DashboardSettingsSnapshot) {
        let defaults = UserDefaults.standard

        defaults.set(snapshot.oscEnabled, forKey: "osc.global.enabled")
        defaults.set(snapshot.oscPort, forKey: "osc.global.port")

        defaults.set(snapshot.midiEnabled, forKey: "midi.global.enabled")
        defaults.set(snapshot.midiSourceId, forKey: "midi.global.sourceId")

        defaults.set(snapshot.proPresenterHost, forKey: "propresenter_host")
        defaults.set(snapshot.proPresenterPort, forKey: "propresenter_port")
        if ProPresenterPasswordPolicy.shouldApplyImported(snapshot.proPresenterPassword) { ProPresenterKeychainStore.shared.password = snapshot.proPresenterPassword }
        defaults.set(snapshot.proPresenterTransport, forKey: "propresenter_transport")
        defaults.set(snapshot.proPresenterPollInterval, forKey: "propresenter_pollInterval")
        if let data = snapshot.proPresenterProfilesData {
            defaults.set(data, forKey: "propresenter_profiles")
        } else {
            defaults.removeObject(forKey: "propresenter_profiles")
        }
        if let active = snapshot.proPresenterActiveProfileID {
            defaults.set(active, forKey: "propresenter_activeProfileID")
        } else {
            defaults.removeObject(forKey: "propresenter_activeProfileID")
        }

        if let data = snapshot.resolumeProfilesData {
            defaults.set(data, forKey: "Relay.ResolumeProfilesStore.v1")
        } else {
            defaults.removeObject(forKey: "Relay.ResolumeProfilesStore.v1")
        }

        NDIPreferencesStore.save(
            NDIGlobalPreferences(
                preferredInterfaceID: snapshot.ndiPreferredInterfaceID,
                allowAutoFallback: snapshot.ndiAllowAutoFallback ?? true
            ),
            defaults: defaults
        )

        if let x32Settings = snapshot.x32DeviceSettingsByKey {
            let devices = ExternalDevicesStore.shared.devices
            for device in devices {
                let key = "\(device.kind.rawValue)|\(device.host.lowercased())|\(device.port)"
                guard let settings = x32Settings[key] else { continue }

                let syncMapKey = "prodlink.x32sync.map.\(device.id.uuidString)"
                let syncTimestampKey = "prodlink.x32sync.ts.\(device.id.uuidString)"
                let showSendModeKey = "prodlink.x32show.sendmode.\(device.id.uuidString)"

                if let map = settings.syncMap, let data = try? JSONEncoder().encode(map) {
                    defaults.set(data, forKey: syncMapKey)
                } else {
                    defaults.removeObject(forKey: syncMapKey)
                }

                if let ts = settings.syncTimestamp {
                    defaults.set(ts, forKey: syncTimestampKey)
                } else {
                    defaults.removeObject(forKey: syncTimestampKey)
                }

                if let mode = settings.showSendMode {
                    defaults.set(mode, forKey: showSendModeKey)
                } else {
                    defaults.removeObject(forKey: showSendModeKey)
                }
            }
        }

        OSCManager.shared.setGlobalListening(enabled: snapshot.oscEnabled, port: UInt16(max(1, min(65535, snapshot.oscPort))))

        let selectedID = snapshot.midiSourceId >= 0 ? Int32(snapshot.midiSourceId) : nil
        MIDIGlobalReceiveManager.shared.setGlobalListening(enabled: snapshot.midiEnabled, preferredSourceID: selectedID)

        ResolumeProfilesStore.shared.loadFromDisk()
    }

    private func importedExternalDevicesOrSettingsHasChanges(
        externalDevices: ExternalDevicesStore.Snapshot?,
        settings: DashboardSettingsSnapshot?
    ) -> Bool {
        if let snapshot = externalDevices, externalDevicesSnapshotHasChanges(snapshot) {
            return true
        }
        if let snapshot = settings, settingsSnapshotHasChanges(snapshot) {
            return true
        }
        return false
    }

    private func exportLogs() {
        guard !isPreparingLogExport else { return }
        let start = Date()
        isPreparingLogExport = true
        logExportErrorMessage = nil
        print("[Logs] Export requested.")
        RelayDiagnosticsStore.shared.update(tabs: tabs)
        syncActiveCanvasDiagnostics()
        print("[Logs] Snapshot refreshed before export tabs=\(tabs.count)")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try RelayLogManager.shared.makeCombinedLogData()
                DispatchQueue.main.async {
                    isPreparingLogExport = false
                    #if os(macOS)
                    presentLogSavePanel(data: data, startedAt: start)
                    #else
                    logArchiveDocument = RelayLogArchiveDocument(data: data)
                    isExportingLogs = true
                    let elapsed = Date().timeIntervalSince(start)
                    print("[Logs] Export prepared (\(data.count) bytes, \(String(format: "%.2f", elapsed))s). Presenting save sheet.")
                    #endif
                }
            } catch {
                DispatchQueue.main.async {
                    isPreparingLogExport = false
                    logExportErrorMessage = error.localizedDescription
                    RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Log Export")
                    print("❌ Failed to prepare logs: \(error)")
                }
            }
        }
    }

    @MainActor
    private func syncGraphAutomationRuntimeSnapshots() {
        let selectedTabId = tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex].id : nil
        graphAutomationRuntime.setActiveTabsSnapshot(tabs, selectedTabId: selectedTabId)
        graphAutomationRuntime.setUniversalGraph(universalGraph)
    }

    @MainActor
    private func syncActiveCanvasDiagnostics() {
        let selectedTab = tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex] : nil
        RelayDiagnosticsStore.shared.updateActiveCanvasComposition(tab: selectedTab)
    }

    private func logDashboardSummary(_ tabs: [DashboardTab], context: String) {
        RelayDiagnosticsStore.shared.update(tabs: tabs)
        let snapshot = RelayDiagnosticsStore.shared.snapshot
        print("🧩 [Dashboard] \(context): tabs=\(snapshot.tabCount) tiles=\(snapshot.tileCount) modules=\(snapshot.moduleCount) largestTab=\(snapshot.largestTabTileCount)")
    }

    private func refreshOSCListeningConfiguration() {
        let defaults = UserDefaults.standard
        let oscEnabled = defaults.bool(forKey: "osc.global.enabled")
        let configuredPort = defaults.integer(forKey: "osc.global.port")
        let globalPort = UInt16(max(1, min(65535, configuredPort == 0 ? 8000 : configuredPort)))

        OSCManager.shared.setGlobalListening(enabled: oscEnabled, port: globalPort)
        OSCManager.shared.setCustomListeningPorts(customOSCPorts(in: tabs))
    }

    private func customOSCPorts(in tabs: [DashboardTab]) -> Set<UInt16> {
        var ports: Set<UInt16> = []
        for tab in tabs {
            guard let graph = tab.graph else { continue }
            for cfg in graph.oscReceiveConfigByNodeId.values where cfg.useCustomPort && cfg.customListenPort != 0 {
                ports.insert(cfg.customListenPort)
            }
        }
        return ports
    }

    #if os(macOS)
    private func presentLogSavePanel(data: Data, startedAt: Date) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Relay Logs.txt"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                print("[Logs] Export cancelled.")
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                let elapsed = Date().timeIntervalSince(startedAt)
                print("[Logs] Exported to \(url.path) (\(data.count) bytes, \(String(format: "%.2f", elapsed))s)")
            } catch {
                logExportErrorMessage = error.localizedDescription
                RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Log Export")
                print("❌ Failed to export logs: \(error)")
            }
        }
    }

    private func presentSavePanel(payload: DashboardDocument.Payload) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.prodlinkDashboard]
        panel.nameFieldStringValue = saveState.currentFileName.isEmpty ? "Relay Dashboard" : saveState.currentFileName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                handleDocumentSaveCompletion(success: false, savedURL: nil)
                return
            }
            writeDashboardPayload(payload, to: url) { success in
                if success {
                    handleDocumentSaveCompletion(success: true, savedURL: url)
                } else {
                    handleDocumentSaveCompletion(success: false, savedURL: nil)
                    print("❌ Failed to export dashboard to \(url.path)")
                }
            }
        }
    }
    #endif

    private func withDashboardFileIOAndDialogs<Content: View>(_ content: Content) -> some View {
        let a = content.fileExporter(
                isPresented: $isExportingDashboard,
                document: dashboardDocument,
                contentType: .prodlinkDashboard,
                defaultFilename: "Relay Dashboard"
            ) { result in
                switch result {
                case .success(let url):
                    handleDocumentSaveCompletion(success: true, savedURL: url)
                    print("✅ Dashboard exported successfully")
                case .failure(let error):
                    handleDocumentSaveCompletion(success: false, savedURL: nil)
                    print("❌ Failed to export dashboard: \(error)")
                    RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Dashboard Export")
                }
            }
        #if os(macOS)
        let b = a
        #else
        let b = a.fileExporter(
                isPresented: $isExportingLogs,
                document: logArchiveDocument,
                contentType: .plainText,
                defaultFilename: "Relay Logs"
            ) { result in
                switch result {
                case .success(let url):
                    print("[Logs] Exported to \(url.path)")
                case .failure(let error):
                    logExportErrorMessage = error.localizedDescription
                    RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Log Export")
                    print("❌ Failed to export logs: \(error)")
                }
            }
        #endif
        let c = b.fileImporter(
                isPresented: $isImportingDashboard,
                allowedContentTypes: [.prodlinkDashboard, .legacyProdlinkDashboard],
                allowsMultipleSelection: false
            ) { result in
                DashboardHomeScreenState.shared.openPickerLaunchedFromHome = false
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importDashboard(from: url)
                case .failure(let error):
                    RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Dashboard Import")
                    print("❌ Failed to open dashboard file: \(error)")
                }
            } onCancellation: {
                // `onCompletion` is never called when the user cancels the picker (isPresented
                // just flips back to false silently) — `onCancellation` is the only hook for it.
                // The home screen dismisses itself before the picker appears (see
                // RelayDashboardApp.onOpenFile); if the user then cancels, bring it back
                // instead of leaving the blank dashboard exposed underneath.
                if DashboardHomeScreenState.shared.openPickerLaunchedFromHome {
                    DashboardHomeScreenState.shared.openPickerLaunchedFromHome = false
                    NotificationCenter.default.post(name: .showHomeRequested, object: nil)
                }
            }
        let d = c.alert("Unsaved Dashboard", isPresented: $showingOpenUnsavedAlert) {
                Button("Cancel", role: .cancel) {
                    pendingDocumentContinuation = nil
                }
                Button("Don’t Save") {
                    continuePendingDocumentContinuationAfterDiscard()
                }
                Button("Save…") {
                    saveCurrentDocument()
                }
            } message: {
                Text("You have unsaved changes. Do you want to save your current dashboard before opening another one?")
            }
        let e = d.alert("Save Changes Before Closing?", isPresented: $showingCloseUnsavedAlert) {
                Button("Cancel", role: .cancel) {
                    pendingDocumentContinuation = nil
                    windowCloseCoordinator.clearPendingClose()
                }
                Button("Don’t Save", role: .destructive) {
                    continuePendingDocumentContinuationAfterDiscard()
                }
                Button("Save…") {
                    saveCurrentDocument()
                }
            } message: {
                Text("You have unsaved changes. Do you want to save your current dashboard before closing this window?")
            }
        let f = e.alert("Save Changes Before Quitting?", isPresented: $showingQuitUnsavedAlert) {
                Button("Cancel", role: .cancel) {
                    pendingDocumentContinuation = nil
                    AppTerminationCoordinator.shared.cancelTermination()
                }
                Button("Don’t Save", role: .destructive) {
                    continuePendingDocumentContinuationAfterDiscard()
                }
                Button("Save…") {
                    saveCurrentDocument()
                }
            } message: {
                Text("You have unsaved changes. Do you want to save your current dashboard before quitting Relay?")
            }
        let g = f.alert("Dashboard Import Error", isPresented: Binding(
                get: { dashboardFileErrorMessage != nil },
                set: { newValue in
                    if !newValue { dashboardFileErrorMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) {
                    dashboardFileErrorMessage = nil
                }
            } message: {
                Text(dashboardFileErrorMessage ?? "Unknown error")
            }
        let h = g.alert("Log Export Failed", isPresented: Binding(
                get: { logExportErrorMessage != nil },
                set: { newValue in
                    if !newValue { logExportErrorMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) {
                    logExportErrorMessage = nil
                }
            } message: {
                Text(logExportErrorMessage ?? "Unknown error")
            }
        let i = h.alert("Pro Features Locked", isPresented: Binding(
                get: { freeImportWarningMessage != nil },
                set: { newValue in
                    if !newValue { freeImportWarningMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) {
                    freeImportWarningMessage = nil
                }
            } message: {
                Text(freeImportWarningMessage ?? "")
            }
        let j = i.confirmationDialog(
                "Import LAN Tab",
                isPresented: $showingLANImportDialog,
                titleVisibility: Visibility.visible
            ) {
                Button("Import Tab") {
                    Task { await performLANImport(mode: .addNewTab, adjustCanvasToImport: false) }
                }
                Button("Cancel", role: .cancel) {
                    pendingLANImportManifest = nil
                }
            } message: {
                if let m = pendingLANImportManifest {
                    Text("Add \"\(m.tabName)\" as a new tab from \(m.deviceDisplayLabel)?")
                } else {
                    Text("No LAN tab selected.")
                }
            }
            .alert("LAN Import Failed", isPresented: Binding(
                get: { lanImportErrorMessage != nil },
                set: { if !$0 { lanImportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { lanImportErrorMessage = nil }
            } message: {
                Text(lanImportErrorMessage ?? "Unknown error")
            }
            .alert("Could Not Connect", isPresented: Binding(
                get: { !showingSettings && lanService.lastPairingFailureMessage != nil },
                set: { if !$0 { lanService.clearPairingFailure() } }
            )) {
                Button("OK", role: .cancel) { lanService.clearPairingFailure() }
            } message: {
                Text(lanService.lastPairingFailureMessage ?? "")
            }
            .confirmationDialog(
                "Import External Devices",
                isPresented: $showingExternalDevicesImportDialog,
                titleVisibility: Visibility.visible
            ) {
                Button("Replace Local Device Config") {
                    if let snapshot = pendingImportedExternalDevicesSnapshot {
                        #if DEBUG
                        logImportedExternalDevices(snapshot, context: "Open File → Replace tapped")
                        #endif
                        ExternalDevicesStore.shared.applySnapshot(snapshot)
                        ExternalDevicesStore.shared.savePersistentState()
                    }
                    if let settings = pendingImportedSettingsSnapshot {
                        applySettingsSnapshot(settings)
                    }
                    if let bundle = pendingImportedLANSettingsBundle {
                        lanService.applyImportedSettings(from: bundle)
                    }
                    clearPendingImportedConfiguration()
                }

                Button("Merge Device Config") {
                    if let snapshot = pendingImportedExternalDevicesSnapshot {
                        #if DEBUG
                        logImportedExternalDevices(snapshot, context: "Open File → Merge tapped")
                        #endif
                        ExternalDevicesStore.shared.mergeSnapshot(snapshot)
                        ExternalDevicesStore.shared.savePersistentState()
                    }
                    if let settings = pendingImportedSettingsSnapshot {
                        applySettingsSnapshot(settings)
                    }
                    if let bundle = pendingImportedLANSettingsBundle {
                        lanService.applyImportedSettings(from: bundle)
                    }
                    clearPendingImportedConfiguration()
                }

                Button("Skip", role: .cancel) {
                    clearPendingImportedConfiguration()
                }
            } message: {
                Text("This import contains External Devices/config and connection settings. Replace will overwrite this device’s current config. Merge will add missing devices and update matching devices by IP/port. Skip keeps your current device config.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .newDashboardRequested)) { _ in
                documentController.newDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .changeDashboardSizeRequested)) { _ in
                presentCanvasSizePrompt(.resizeCurrent)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bringAllTilesIntoCanvasRequested)) { _ in
                bringAllTilesIntoCanvas()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
                showingSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .createBlankDashboardRequested)) { note in
                if let w = note.userInfo?["width"] as? CGFloat,
                   let h = note.userInfo?["height"] as? CGFloat {
                    canvasBoundsStore.size = CGSize(width: w, height: h)
                }
                handleNewDashboardRequested()
            }
            .onChange(of: showingSettings, initial: false) { _, showing in
                if !showing {
                    NotificationCenter.default.post(name: .settingsDidDismiss, object: nil)
                }
            }
            .alert(
                "Scale Tile Positions?",
                isPresented: $isShowingCanvasResizeScaleAlert
            ) {
                Button("Scale Tile Positions") {
                    resolvePendingCanvasResize(scaleTiles: true)
                }
                Button("Keep Positions") {
                    resolvePendingCanvasResize(scaleTiles: false)
                }
                Button("Cancel", role: .cancel) {
                    pendingCanvasResize = nil
                }
            } message: {
                Text("Some tiles extend beyond the new canvas size. Scale their positions to fit? Tile sizes will not change.")
            }
            .alert(
                "Do you want to save changes to this dashboard?",
                isPresented: $isShowingNewDashboardAlert
            ) {
                Button("Save") {
                    saveCurrentDocument()
                }
                Button("Don’t Save", role: .destructive) {
                    continuePendingDocumentContinuationAfterDiscard()
                }
                Button("Cancel", role: .cancel) {
                    pendingDocumentContinuation = nil
                }
            } message: {
                Text("Your changes will be lost if you don’t save them.")
            }
        let k = j.overlay(alignment: .top) {
            if showingBookmarkRestoreFailedBanner {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Could not reopen last dashboard — choose a file to continue.")
                        .font(.subheadline)
                    Spacer()
                    Button("Dismiss") {
                        withAnimation { showingBookmarkRestoreFailedBanner = false }
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: showingBookmarkRestoreFailedBanner)
            }
        }
        // Approval (needs a human decision) takes priority over the passive waiting
        // overlay when a device is simultaneously host and joiner — see PairingSheetKind.
        let currentPairingSheetKind: PairingSheetKind? = {
            // Sync & Mirror settings presents its own pairing sheet so approval remains
            // visible while the settings sheet is open (SwiftUI only supports one sheet
            // presentation at a time from the same presenter).
            guard !showingSettings else { return nil }
            if let requestId = pendingApprovalRequestId,
               let request = lanService.pendingPairingRequests.first(where: { $0.id == requestId }) {
                return .approval(request)
            }
            if let outgoing = lanService.activePairingRequest, outgoing != dismissedActivePairingRequest {
                return .waiting(outgoing)
            }
            return nil
        }()
        let l = k.sheet(item: Binding<PairingSheetKind?>(
            get: { currentPairingSheetKind },
            set: { newValue in
                // Only clear state for whichever kind was actually on screen — not both —
                // so an approval dismissal can never mark an unrelated, unseen waiting
                // request as locally dismissed (self-contained regardless of what dismiss
                // policy, e.g. .interactiveDismissDisabled(), a child view happens to set).
                guard newValue == nil else { return }
                switch currentPairingSheetKind {
                case .approval:
                    pendingApprovalRequestId = nil
                case .waiting:
                    dismissedActivePairingRequest = lanService.activePairingRequest
                case nil:
                    break
                }
            }
        )) { kind in
            pairingSheetContent(for: kind)
        }
        let m = l.sheet(isPresented: Binding(
            get: { orphanedBannerGroupID != nil },
            set: { if !$0 { orphanedBannerGroupID = nil } }
        )) {
            if let gid = orphanedBannerGroupID,
               let tabIndex = tabs.firstIndex(where: { $0.syncGroupID == gid }) {
                SyncOrphanBanner(
                    tabName: tabs[tabIndex].name,
                    hostStopped: lanService.hostStoppedGroupIDs.contains(gid),
                    canReconnect: lanService.peerVersionsForJoinedGroups[gid] != nil,
                    onReconnect: {
                        orphanedBannerGroupID = nil
                        reconnectSyncedTab(groupID: gid)
                    },
                    onKeep: {
                        orphanedBannerGroupID = nil
                        keepOrphanedTabAsLocal(groupID: gid)
                    },
                    onRemove: {
                        orphanedBannerGroupID = nil
                        autoRemoveOrphanedTab(groupID: gid)
                    }
                )
                .interactiveDismissDisabled()
                .presentationSizing(.fitted)
            }
        }
        let o = m.sheet(isPresented: $showingAutosaveAnnouncement) {
            AutosaveAnnouncementView(
                fileAutosaveEnabled: $fileAutosaveEnabled,
                onDismiss: { showingAutosaveAnnouncement = false }
            )
        }
        return o
    }

    @ViewBuilder
    private func pairingSheetContent(for kind: PairingSheetKind) -> some View {
        switch kind {
        case .approval(let request):
            PairingApprovalSheet(
                request: request,
                shortAuthString: lanService.shortAuthString(for: request),
                onApprove: {
                    lanService.approvePairingRequest(request)
                    pendingApprovalRequestId = nil
                },
                onDeny: {
                    lanService.denyPairingRequest(request)
                    pendingApprovalRequestId = nil
                }
            )
        case .waiting(let request):
            PairingWaitingOverlay(request: request, onCancel: {
                // The pairing timeout resolves the handshake; Cancel dismisses only this overlay.
                dismissedActivePairingRequest = request
            })
        }
    }

/// Best-effort: fetch a per-tab reference canvas size that was saved with the tab (authoring coordinate space).
/// Uses reflection so this remains compatible even if the stored property name changes.
private func referenceCanvasSize(for tab: DashboardTab) -> CGSize? {
    let mirror = Mirror(reflecting: tab)
    let candidateKeys: [String] = [
        "referenceCanvasSize",
        "savedReferenceCanvasSize",
        "tabReferenceCanvasSize",
        "authoringCanvasSize",
        "canvasReferenceSize"
    ]

    for child in mirror.children {
        guard let label = child.label, candidateKeys.contains(label) else { continue }

        // Direct CGSize
        if let s = child.value as? CGSize { return s }

        // Optional<CGSize>
        let vm = Mirror(reflecting: child.value)
        if vm.displayStyle == .optional, let first = vm.children.first?.value as? CGSize {
            return first
        }
    }

    return nil
}

/// Best-effort: extract cached PCO rundown snapshot titles from the tab using reflection.
private func snapshotRundownTitles(for tab: DashboardTab) -> [String] {
    // Graph mode is intentionally static, so we capture these titles once when entering graph mode.

    // Fast path: If the tab has a property for pcoRundownSnapshotTitles, use it (with default for back-compat).
    if let arr = (Mirror(reflecting: tab).children.first { $0.label == "pcoRundownSnapshotTitles" }?.value as? [String]) {
        return arr
    }

    func unwrapOptional(_ any: Any) -> Any? {
        let m = Mirror(reflecting: any)
        guard m.displayStyle == .optional else { return any }
        return m.children.first?.value
    }

    func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pack(title: String, key: String?) -> String {
        let t = normalize(title)
        guard !t.isEmpty else { return "" }
        let k = normalize(key ?? "")
        return k.isEmpty ? t : (t + "\n__KEY__:" + k)
    }

    func unpackTitle(_ s: String) -> String {
        let trimmed = normalize(s)
        if let r = trimmed.range(of: "\n__KEY__:") {
            return normalize(String(trimmed[..<r.lowerBound]))
        }
        return trimmed
    }

    // Prefer explicit cached arrays if present (fast path, alternate names).
    do {
        let mirror = Mirror(reflecting: tab)
        let candidateKeys: [String] = [
            "pcoRundownSnapshotTitles",
            "rundownSnapshotTitles",
            "pcoRundownTitles",
            "pcoSnapshotTitles",
            "snapshotTitles",
            // common alternates we may have used
            "pcoRundownItemTitles",
            "pcoRundownItems",
            "pcoRundown",
            "rundownItems",
            "rundown"
        ]

        for child in mirror.children {
            guard let label = child.label, candidateKeys.contains(label) else { continue }

            if let arr = unwrapOptional(child.value) as? [String] {
                let cleaned = arr.map(normalize).filter { !$0.isEmpty }
                if !cleaned.isEmpty { return cleaned }
            }

            if let joined = unwrapOptional(child.value) as? String {
                let cleaned = joined
                    .components(separatedBy: "||")
                    .map(normalize)
                    .filter { !$0.isEmpty }
                if !cleaned.isEmpty { return cleaned }
            }
        }
    }

    let titleKeys: Set<String> = [
        "title",
        "name",
        "label",
        "itemTitle",
        "itemName",
        "rundownTitle",
        "rundownItemTitle"
    ]

    let keyKeys: Set<String> = [
        "key",
        "songKey",
        "song_key",
        "keyName",
        "key_name"
    ]

    func extractPackedTitles(from any: Any, depth: Int) -> [String] {
        guard depth > 0 else { return [] }
        guard let value = unwrapOptional(any) else { return [] }

        // Direct string (already packed or plain)
        if let s = value as? String {
            let n = normalize(s)
            return n.isEmpty ? [] : [n]
        }

        // Array of strings
        if let arr = value as? [String] {
            return arr.map(normalize).filter { !$0.isEmpty }
        }

        // Collections (Array/Set/Dictionary/etc)
        let m = Mirror(reflecting: value)
        if m.displayStyle == .collection {
            return m.children.flatMap { extractPackedTitles(from: $0.value, depth: depth - 1) }
        }
        if m.displayStyle == .dictionary {
            return m.children.flatMap { child -> [String] in
                // Dictionary children are key/value tuples
                let tupleMirror = Mirror(reflecting: child.value)
                let parts = tupleMirror.children.map { $0.value }
                return parts.flatMap { extractPackedTitles(from: $0, depth: depth - 1) }
            }
        }

        // Struct/class: try to extract title + key from the same object.
        var foundTitle: String? = nil
        var foundKey: String? = nil

        for child in m.children {
            guard let label = child.label else { continue }

            if titleKeys.contains(label) {
                if let s = unwrapOptional(child.value) as? String {
                    let n = normalize(s)
                    if !n.isEmpty { foundTitle = n }
                }
            }

            if keyKeys.contains(label) {
                if let s = unwrapOptional(child.value) as? String {
                    let n = normalize(s)
                    if !n.isEmpty { foundKey = n }
                }
            }
        }

        if let t = foundTitle, !t.isEmpty {
            let packed = pack(title: t, key: foundKey)
            return packed.isEmpty ? [] : [packed]
        }

        // Otherwise recurse into children.
        return m.children.flatMap { extractPackedTitles(from: $0.value, depth: depth - 1) }
    }

    // Search order:
    // 1) tab (in case it caches rundown data)
    // 2) tiles and modules (most likely)
    var titles: [String] = []

    titles.append(contentsOf: extractPackedTitles(from: tab, depth: 6))

    // Also explicitly walk tiles (this tends to be much more productive than the broad tab walk).
    for tile in tab.tiles {
        titles.append(contentsOf: extractPackedTitles(from: tile, depth: 6))
        if let modules = tile.modules {
            for m in modules {
                titles.append(contentsOf: extractPackedTitles(from: m, depth: 6))
            }
        }
    }

    // Cleanup: de-dupe by base title, preserving first packed key encountered.
    var seenBase = Set<String>()
    var ordered: [String] = []
    for t in titles {
        let n = normalize(t)
        guard !n.isEmpty else { continue }
        let base = unpackTitle(n)
        guard !base.isEmpty else { continue }
        if !seenBase.contains(base) {
            seenBase.insert(base)
            ordered.append(n)
        }
    }

    return ordered
}

private func recomputeLANMirrorScale() {
    guard let ref = lanMirrorReferenceCanvasSize, ref.width > 0, ref.height > 0 else {
        lanMirrorScale = 1.0
        return
    }
    let viewport = canvasViewportSize
    guard viewport.width > 0, viewport.height > 0 else {
        lanMirrorScale = 1.0
        return
    }

    let sx = viewport.width / ref.width
    let sy = viewport.height / ref.height
    // Only scale DOWN to fit; never scale up beyond 1.0 to avoid clipping.
    lanMirrorScale = min(1.0, min(sx, sy))
}
    /// Debounce rapid edits and re-advertise current tabs over LAN.
    private var lanPollIntervalSeconds: Double {
        let raw = UserDefaults.standard.object(forKey: "lan_poll_interval") as? Double ?? 1.0
        return max(0.2, min(5.0, raw))
    }

    private var lanRenderIntervalSeconds: Double {
        max(lanPollIntervalSeconds, 2.0)
    }

    private var isLANMirrorTabActive: Bool {
        if selectedLANShareId != nil {
            return true
        }
        guard tabs.indices.contains(selectedTabIndex) else { return false }
        return tabs[selectedTabIndex].lanMirrorShareId != nil
    }

    private func jumpToNearestLocalTab(from index: Int) {
        guard !tabs.isEmpty else { return }
        if tabs.indices.contains(index), tabs[index].lanMirrorShareId == nil {
            return
        }
        let count = tabs.count
        for offset in 1..<count {
            let left = index - offset
            if tabs.indices.contains(left), tabs[left].lanMirrorShareId == nil {
                selectedTabIndex = left
                return
            }
            let right = index + offset
            if tabs.indices.contains(right), tabs[right].lanMirrorShareId == nil {
                selectedTabIndex = right
                return
            }
        }
        selectedTabIndex = 0
    }

    private func startLANRenderUpdateLoop() {
        guard lanBrowserServingAllowed else {
            lanRenderUpdateTask?.cancel()
            lanRenderUpdateTask = nil
            return
        }
        lanRenderUpdateTask?.cancel()
        lanRenderUpdateTask = Task {
            while !Task.isCancelled {
                let snapshot = await MainActor.run { () -> (tabs: [DashboardTab], size: CGSize, enabled: Bool, hasPeers: Bool, live: Bool) in
                    (
                        tabs: tabs,
                        size: canvasSize,
                        enabled: lanBrowserServingAllowed,
                        hasPeers: true,
                        live: isLiveMode
                    )
                }

                guard snapshot.enabled, snapshot.hasPeers else {
                    let interval = lanRenderIntervalSeconds
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    continue
                }

                let tabsSnapshot = snapshot.tabs
                if tabsSnapshot.isEmpty {
                    await MainActor.run {
                        lanService.setSharedTabRenders([:])
                    }
                    let interval = lanRenderIntervalSeconds
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    continue
                }

                let activeShareIds = await MainActor.run {
                    lanService.activeRenderShareIds(within: 8.0)
                }
                if !activeShareIds.isEmpty {
                    let filtered = tabsSnapshot.filter { activeShareIds.contains($0.id.uuidString) }
                    if filtered.isEmpty {
                        let interval = lanRenderIntervalSeconds
                        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                        continue
                    }
                    let tabIndex = await MainActor.run { () -> Int in
                        let count = max(1, filtered.count)
                        let idx = lanRenderCursor % count
                        lanRenderCursor = (idx + 1) % count
                        return idx
                    }
                    let tab = filtered[tabIndex]

                    let renderScale: CGFloat = snapshot.live ? 0.5 : 1.0
                    let data = await MainActor.run {
                        renderTabImageData(tab: tab, canvasSize: snapshot.size, scale: renderScale)
                    }
                    await MainActor.run {
                        lanService.setSharedTabRender(shareId: tab.id.uuidString, data: data)
                    }

                    let baseInterval = snapshot.live
                        ? max(1.0, lanRenderIntervalSeconds)
                        : lanRenderIntervalSeconds
                    try? await Task.sleep(nanoseconds: UInt64(baseInterval * 1_000_000_000))
                    continue
                }

                // Poll frequently when idle so a newly-connected browser gets its first
                // render within ~0.5s rather than waiting the full render interval.
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
        }
    }

    @MainActor
    private func updateLANSharedTabRenders() {
        let tabsToShare = tabs
        guard !tabsToShare.isEmpty else {
            lanService.setSharedTabRenders([:])
            return
        }

        let size = canvasSize
        var renders: [String: Data] = [:]
        for tab in tabsToShare {
            let shareId = tab.id.uuidString
            if let data = renderTabImageData(tab: tab, canvasSize: size, scale: 1.0) {
                renders[shareId] = data
            }
        }
        lanService.setSharedTabRenders(renders)
    }

    private func renderTabImageData(tab: DashboardTab, canvasSize: CGSize, scale: CGFloat = 1.0) -> Data? {
        let clampedScale = max(0.25, min(1.0, scale))
        let view = ZStack(alignment: .topLeading) {
            Color.black
            // Fresh, unconfigured coordinator: this renders an arbitrary (possibly inactive)
            // tab for LAN thumbnails, so it must never share DashboardRootView's canvasActions
            // (which is bound to the currently-active tab) or a write here could silently
            // mutate the wrong tab.
            DashboardTileCanvas(
                interactionSession: DashboardTileInteractionSession(),
                tab: tab,
                selectedTileIDs: .constant([]),
                editingTileID: .constant(nil),
                isInspectorVisible: .constant(false),
                pendingFirstModuleSelectTileID: .constant(nil),
                isDraggingTilesOnCanvas: .constant(false),
                selectionSource: .constant(.canvas),
                groupSelectionColor: .constant(nil),
                sharedRosters: [],
                isLiveMode: true,
                liveModeReloadToken: UUID(),
                allowTileOverlap: allowTileOverlap,
                snapToGridEnabled: false,
                canvasSize: canvasSize,
                canvasGuides: [],
                showGuidesEnabled: false,
                gridSizeSetting: gridSizeSetting,
                showGridEnabled: false,
                gridLineOpacity: gridBackgroundOpacity,
                isPCORefreshing: false,
                viewportZoom: 1,
                disableDragging: true,
                actions: DashboardCanvasActionCoordinator()
            )
        }
        .environment(\.dashboardIsLANSnapshotRendering, true)
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(DashboardSaveState.shared)
        .environmentObject(lanService)
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)

        let renderer = ImageRenderer(content: view)
        renderer.scale = clampedScale

        #if os(iOS)
        if let image = renderer.uiImage {
            return image.jpegData(compressionQuality: 0.7)
        }
        #else
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        }
        #endif

        return nil
    }

    private func decodeLANRenderImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func scheduleLANShareUpdateDebounced() {
        // If we aren't sharing, don't waste cycles rebuilding manifests.
        guard lanBrowserServingAllowed else { return }

        // Avoid spamming manifests while the user is actively editing in the inspector or typing.
        // We'll publish a consolidated update when editing ends.
        if isInspectorVisible || isTextInputActive || showingPCOConfigForTab || isTabInteractionActive {
            lanShareUpdateTask?.cancel()
            return
        }

        lanShareUpdateTask?.cancel()

        // Capture current tabs snapshot for encoding.
        let currentTabs = tabs
        lanShareUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s

            // Re-check gating after the debounce.
            guard lanBrowserServingAllowed else { return }
            if isInspectorVisible || isTextInputActive || showingPCOConfigForTab || isTabInteractionActive {
                return
            }

            await MainActor.run {
                updateLANSharedTabs(currentTabs)
            }
        }
    }
    private func updateShureModulePresence() {
        let hasShureModule = tabs.contains { tab in
            tab.tiles.contains { tile in
                if let modules = tile.modules {
                    return modules.contains { module in
                        switch module.kind {
                        case .shureWireless, .shureOverview:
                            return true
                        default:
                            return false
                        }
                    }
                }
                return false
            }
        }
        ExternalDevicesStore.shared.setShureModuleActive(hasShureModule)
    }

    private func updateLANPollingState() {
        guard lanDiscoveryAllowed else {
            lanService.setPollingEnabled(false)
            lanMirrorRefreshTask?.cancel()
            lanMirrorRefreshTask = nil
            return
        }
        // Pause LAN polling while the edit inspector is open so Lists/ScrollViews don't jump
        // due to background updates (LAN poll -> tabs refresh -> PCO refresh chain).
        let shouldPoll = (layoutMode != .graph)
            && !isInspectorVisible
            && !showingPCOConfigForTab
            && !showExternalDevicesSettingsSheet
            && !isTabInteractionActive
            && !isTextInputActive
            && !isDraggingTilesOnCanvas
        lanService.setPollingEnabled(shouldPoll)

        // Mirror refresh loop is only relevant when not in graph mode and a LAN share is selected.
        if shouldPoll, isLANMirrorTabActive {
            startLANMirrorRefreshLoop()
        } else {
            lanMirrorRefreshTask?.cancel()
            lanMirrorRefreshTask = nil
        }
    }

    private func updateLANBrowserViewSelection() {
        lanService.setBrowserViewShareId(currentLANBrowserViewShareId())
    }

    private func currentLANBrowserViewShareId() -> String? {
        if tabs.indices.contains(selectedTabIndex), tabs[selectedTabIndex].lanMirrorShareId == nil {
            return tabs[selectedTabIndex].id.uuidString
        }
        return tabs.first(where: { $0.lanMirrorShareId == nil })?.id.uuidString
    }
/// Encode and advertise the given tabs as shareable LAN manifests.
@MainActor
private func updateLANSharedTabs(_ currentTabs: [DashboardTab]? = nil) {
    guard lanBrowserServingAllowed else {
        lanService.setSharedTabs([], canvasSize: canvasBoundsStore.size, referenceCanvasSizes: [:])
        return
    }
    let tabsToShare = (currentTabs ?? tabs).filter { $0.syncGroupID == nil }

    do {
        let encoder = JSONEncoder()

        let shared = try tabsToShare.map { tab -> (shareId: String, tabName: String, exportedTabJSON: Data, tileCount: Int, moduleTypes: [String], schemaVersion: Int) in
            let shareId = tab.id.uuidString

            // Summary metadata (optional, but nice for UI).
            let tileCount = tab.tiles.count
            var moduleTypesSet: Set<String> = []

            for tile in tab.tiles {
                if let modules = tile.modules {
                    for m in modules {
                        switch m.kind {
                        case .person: moduleTypesSet.insert("person")
                        case .pcoRundown: moduleTypesSet.insert("pco")
                        case .pcoTeamAssignments: moduleTypesSet.insert("pcoTeamAssignments")
                        case .rosterTeamAssignments: moduleTypesSet.insert("rosterTeamAssignments")
                        case .shureWireless: moduleTypesSet.insert("shure")
                        case .shureOverview: moduleTypesSet.insert("shureOverview")
                        case .sennheiserWireless: moduleTypesSet.insert("sennheiser")
                        case .proPresenter: moduleTypesSet.insert("propresenter")
                        case .resolume: moduleTypesSet.insert("resolume")
                        case .time: moduleTypesSet.insert("time")
                        case .timecode: moduleTypesSet.insert("timecode")
                        case .dawTransport: moduleTypesSet.insert("dawTransport")
                        case .rosterPicker: moduleTypesSet.insert("rosterPicker")
                        case .text: moduleTypesSet.insert("text")
                        case .image: moduleTypesSet.insert("image")
                        case .document: moduleTypesSet.insert("document")
                        case .ndi: moduleTypesSet.insert("ndi")
                        case .webpage: moduleTypesSet.insert("webpage")
                        case .youtubeStreamMonitor: moduleTypesSet.insert("youtubeStreamMonitor")
                        case .separator: moduleTypesSet.insert("separator")
                        case .dbReader: moduleTypesSet.insert("dbReader")
                        case .liveTranscription: moduleTypesSet.insert("liveTranscription")
                        case .button: moduleTypesSet.insert("button")
                        case .rta: moduleTypesSet.insert("rta")
                        case .spectrograph: moduleTypesSet.insert("spectrograph")
                        }
                    }
                } else {
                    // Legacy tile kind support (best-effort summary)
                    switch tile.kind {
                    case .person: moduleTypesSet.insert("person")
                    case .pcoPlaceholder: moduleTypesSet.insert("pco")
                    case .time: moduleTypesSet.insert("time")
                    case .empty: break
                    }
                }
            }

            let exported = try encoder.encode(tab)
            return (
                shareId: shareId,
                tabName: tab.name,
                exportedTabJSON: exported,
                tileCount: tileCount,
                moduleTypes: Array(moduleTypesSet).sorted(),
                schemaVersion: 1
            )
        }

        // Provide per-tab reference canvas sizes so peers mirror in the correct coordinate space.
        var refMap: [String: CGSize] = [:]
        for tab in tabsToShare {
            let shareId = tab.id.uuidString
            if let ref = referenceCanvasSize(for: tab) {
                refMap[shareId] = ref
            }
        }

        lanService.setSharedTabs(shared, canvasSize: canvasSize, referenceCanvasSizes: refMap)
    } catch {
        print("❌ LAN share update failed: \(error)")
    }
}

    // MARK: - Synced Tabs

    /// Applies any synced-tab snapshots received via push or poll fallback, using LWW
    /// (`incoming.version > local.version`). If this device's own last edit is about to
    /// be overwritten by a peer's newer snapshot, shows a brief "lost the race" toast.
    /// Force-applies the host's snapshot on reconnect, bypassing LWW.
    /// Used when the host was orphaned and just reappeared — the host is authoritative.
    @MainActor
    private func forceApplyHostSnapshot(_ snapshot: SyncedTabSnapshot) {
        guard let index = tabs.firstIndex(where: { $0.syncGroupID == snapshot.groupID && !$0.syncIsOwner }) else { return }
        guard var incomingTab = try? JSONDecoder().decode(DashboardTab.self, from: snapshot.exportedTabJSON) else { return }
        incomingTab = SyncedTabSnapshotCompatibility.applying(
            snapshot,
            to: incomingTab,
            preserving: tabs[index]
        )
        // canvasSize intentionally NOT preserved — subscriber adopts host's canvas dimensions.
        incomingTab = preservingLocalConnectionConfig(incoming: incomingTab, current: tabs[index])
        lastSyncedContentHashByGroupID[snapshot.groupID] = incomingTab.syncContentHash()
        var updated = tabs
        updated[index] = incomingTab
        tabs = updated
    }

    private func applyIncomingSyncedSnapshots() {
        let pending = lanService.consumePendingSyncedSnapshots()
        print("🟣 applyIncomingSyncedSnapshots: pending=\(pending.count)")
        guard !pending.isEmpty else { return }

        var updated = tabs
        var didApply = false

        for snapshot in pending {
            guard let index = updated.firstIndex(where: { $0.syncGroupID == snapshot.groupID }) else {
                print("🟣 applyIncomingSyncedSnapshots: NO MATCHING TAB for groupID=\(snapshot.groupID). local groupIDs=\(updated.compactMap(\.syncGroupID))")
                continue
            }

            let localVersion = SyncedTabVersion(
                revision: updated[index].syncRevision,
                editedAt: updated[index].syncLastEditedAt,
                editedByDeviceID: updated[index].syncLastEditedByDeviceID
            )
            // For subscriber tabs with a pending unsent push: require strictly higher revision
            // to avoid the editedAt/deviceID tiebreaker overwriting our in-flight edit.
            let hasPendingPush = !updated[index].syncIsOwner && syncedTabPushTask != nil
            let shouldApply = hasPendingPush
                ? snapshot.version.revision > localVersion.revision
                : snapshot.version > localVersion
            print("🟣 applyIncomingSyncedSnapshots: groupID=\(snapshot.groupID) incoming=rev\(snapshot.version.revision)/\(snapshot.version.editedByDeviceID) local=rev\(localVersion.revision)/\(localVersion.editedByDeviceID) isOwner=\(updated[index].syncIsOwner) hasPendingPush=\(hasPendingPush) shouldApply=\(shouldApply)")
            guard shouldApply else { continue }

            guard var incomingTab = try? JSONDecoder().decode(DashboardTab.self, from: snapshot.exportedTabJSON) else {
                print("🟣 applyIncomingSyncedSnapshots: DECODE FAILED for groupID=\(snapshot.groupID), bytes=\(snapshot.exportedTabJSON.count)")
                continue
            }

            // Preserve this device's local identity fields; everything else comes from the snapshot.
            incomingTab = SyncedTabSnapshotCompatibility.applying(
                snapshot,
                to: incomingTab,
                preserving: updated[index]
            )
            // Host preserves its canvas size so its layout doesn't jump when applying subscriber edits.
            // Subscribers adopt the host's canvas dimensions (no preservation).
            if updated[index].syncIsOwner {
                incomingTab.canvasSize = updated[index].canvasSize
            }
            // A peer's copy of a device-local connection (ProPresenter/Resolume endpoint, a
            // paired Shure/Sennheiser receiver, an NDI source, a DAW's MIDI transport, an audio
            // input) never overwrites what's already configured on this device.
            incomingTab = preservingLocalConnectionConfig(incoming: incomingTab, current: updated[index])

            lastSyncedContentHashByGroupID[snapshot.groupID] = incomingTab.syncContentHash()
            updated[index] = incomingTab
            didApply = true
            print("🟣 applyIncomingSyncedSnapshots: APPLIED groupID=\(snapshot.groupID) at local index \(index), tileCount=\(incomingTab.tiles.count)")

            // Race-loss is now surfaced via the colored-ring presence overlay rather than a popup.
        }

        if didApply {
            tabs = updated
            print("🟣 applyIncomingSyncedSnapshots: tabs array reassigned, didApply=true")
        }
    }

    /// Detects local content changes to synced tabs and bumps their LWW version.
    /// Called as the first step of `.onChange(of: tabs)` so every local edit is captured,
    /// including programmatic ones (undo/redo, tile drag, module config, etc.).
    @MainActor
    private func processSyncedTabRevisions() {
        guard tabs.contains(where: { $0.syncGroupID != nil }) else { return }

        var updated = tabs
        var changed = false

        for i in updated.indices {
            guard let groupID = updated[i].syncGroupID else { continue }
            let hash = updated[i].syncContentHash()

            if let previousHash = lastSyncedContentHashByGroupID[groupID] {
                if previousHash == hash { continue }
                updated[i].syncRevision += 1
                // Track local edits for quick-visitor detection (only for joined groups).
                if lanService.joinedSyncGroupIDs.contains(groupID) {
                    localEditCountsByGroupID[groupID, default: 0] += 1
                }
                updated[i].syncLastEditedAt = Date().timeIntervalSince1970
                updated[i].syncLastEditedByDeviceID = lanService.localDeviceID
                updated[i].syncLastEditedByDeviceName = lanService.localDeviceName
                changed = true
            }

            lastSyncedContentHashByGroupID[groupID] = hash
        }

        if changed {
            tabs = updated
        }
    }

    /// Debounced (~600ms) push of every synced tab's current snapshot to LAN peers,
    /// mirroring `scheduleLANShareUpdateDebounced`.
    private func scheduleSyncedTabPushDebounced() {
        syncedTabPushTask?.cancel()

        guard tabs.contains(where: { $0.syncGroupID != nil }) else { return }

        if isTextInputActive || showingPCOConfigForTab || isTabInteractionActive {
            return
        }

        let currentTabs = tabs
        let presenceTileID = lastSyncedEditingTileID?.uuidString
        let presenceGroupID = lastSyncedEditingGroupID
        // First edit after idle: push immediately (no debounce).
        // Rapid subsequent edits: 150ms debounce so only the final state is sent.
        let delayNs: UInt64 = syncedTabPushIsActive ? 150_000_000 : 0
        syncedTabPushIsActive = true
        syncedTabPushTask = Task {
            if delayNs > 0 {
                do { try await Task.sleep(nanoseconds: delayNs) } catch { syncedTabPushIsActive = false; return }
            }

            if isTextInputActive || showingPCOConfigForTab || isTabInteractionActive {
                syncedTabPushIsActive = false
                return
            }

            await pushSyncedTabs(currentTabs, presenceTileID: presenceTileID, presenceGroupID: presenceGroupID)
            syncedTabPushIsActive = false
            lastSyncedEditingTileID = nil
            lastSyncedEditingGroupID = nil
        }
    }

    /// Debounced (300ms) push of this device's current presence (editing + selection)
    /// to all known LAN peers. Used by joiner devices that can't be polled.
    private func schedulePresencePushDebounced() {
        presencePushTask?.cancel()
        let groupID = tabs.indices.contains(selectedTabIndex)
            ? tabs[selectedTabIndex].syncGroupID : nil
        // When groupID is nil (non-synced tab) still push so peers clear any stale rings.
        let tileIDs: Set<UUID> = groupID != nil ? selectedTileIDs : []
        let editingID: UUID? = groupID != nil ? editingTileID : nil
        let gid = groupID
        let deviceID = lanService.localDeviceID
        let deviceName = lanService.localDeviceName
        presencePushTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            // Guard prevents stale data from a cancelled task's resumed continuation firing.
            guard !Task.isCancelled else { return }
            var editingByGroup: [String: [String]] = [:]
            if let eid = editingID, let g = gid { editingByGroup[g] = [eid.uuidString] }
            var selectedByGroup: [String: [String]] = [:]
            if let g = gid, !tileIDs.isEmpty { selectedByGroup[g] = tileIDs.map { $0.uuidString } }
            let payload = SyncedPresencePayload(
                deviceID: deviceID,
                deviceName: deviceName,
                editingByGroup: editingByGroup,
                selectedByGroup: selectedByGroup
            )
            await lanService.pushPresence(payload)
        }
    }

    /// Pushes the current snapshot of every synced tab to all known LAN peers.
    /// Returns a copy of `tab` with `relayFileHash` stamped on every image module that has
    /// a local file, registering those files in the LAN service so they can be served via
    /// GET /localFile/<hash>. Call before encoding any snapshot for subscribers.
    private func tabWithFileProxyHashes(_ tab: DashboardTab) -> DashboardTab {
        var tabForExport = tab
        // Stamp the actual canvas size so subscribers adopt the host's coordinate space.
        // tab.canvasSize is nil when the user hasn't set a custom size (view uses canvasBoundsStore.size).
        if tabForExport.canvasSize == nil {
            tabForExport.canvasSize = canvasBoundsStore.size
        }
        for i in tabForExport.tiles.indices {
            guard let modules = tabForExport.tiles[i].modules else { continue }
            var updatedModules = modules
            for j in updatedModules.indices {
                switch updatedModules[j].kind {
                case .image(var imageModel):
                    if let path = imageModel.cachedFilePath, !path.isEmpty {
                        imageModel.relayFileHash = lanService.registerLocalFile(at: path)
                        updatedModules[j].kind = .image(imageModel)
                    }
                case .person(var personModel):
                    if let path = personModel.backgroundImageName, !path.isEmpty,
                       FileManager.default.fileExists(atPath: path) {
                        personModel.relayBackgroundImageHash = lanService.registerLocalFile(at: path)
                        updatedModules[j].kind = .person(personModel)
                    }
                default:
                    break
                }
            }
            tabForExport.tiles[i].modules = updatedModules
        }
        return tabForExport
    }

    private func pushSyncedTabs(_ currentTabs: [DashboardTab], presenceTileID: String? = nil, presenceGroupID: String? = nil) async {
        let encoder = JSONEncoder()
        lanService.setPersonImageFolderPath(personImageFolder)
        for tab in currentTabs {
            guard let groupID = tab.syncGroupID else { continue }

            let tabForExport = tabWithFileProxyHashes(tab)
            guard let exported = try? encoder.encode(tabForExport) else { continue }

            let version = SyncedTabVersion(
                revision: tabForExport.syncRevision,
                editedAt: tabForExport.syncLastEditedAt,
                editedByDeviceID: tabForExport.syncLastEditedByDeviceID
            )

            // Only piggyback presence on the tab the user was actually editing.
            let tabPresenceTileID = (groupID == presenceGroupID) ? presenceTileID : nil
            let tabPresenceGroupID = (groupID == presenceGroupID) ? presenceGroupID : nil

            await lanService.pushSyncedSnapshot(
                groupID: groupID,
                tabName: tabForExport.name,
                exportedTabJSON: exported,
                version: version,
                lastEditedByDeviceName: tabForExport.syncLastEditedByDeviceName,
                schemaVersion: 1,
                presenceTileID: tabPresenceTileID,
                presenceGroupID: tabPresenceGroupID
            )
        }
        // Do NOT call clearFileRegistry() here — the registry must stay populated so
        // subscribers can fetch files via GET /localFile/<hash> at any time after the push.
    }

    /// Publishes the synced tabs this device holds so peers can discover and poll-fallback against them.
    @MainActor
    private var linkedComputerNamesByDeviceID: [String: String] {
        lanService.peers.reduce(into: [String: String]()) { result, peer in
            guard let name = peer.deviceName,
                  !name.isEmpty else { return }
            result[peer.deviceId] = name
        }
    }

    private func updateSyncedTabs(_ currentTabs: [DashboardTab]? = nil) {
        let tabsToSync = currentTabs ?? tabs
        let encoder = JSONEncoder()

        // Keep the file registry current so GET /localFile/<hash> works even before the
        // first push fires. This ensures joiners that fetch via GET /syncedTab/<groupID>
        // already have relayFileHash in the snapshot without waiting for a push.
        lanService.setPersonImageFolderPath(personImageFolder)

        var entries: [(groupID: String, tabName: String, exportedTabJSON: Data, version: SyncedTabVersion, lastEditedByDeviceName: String, tileCount: Int, moduleTypes: [String], schemaVersion: Int)] = []

        for tab in tabsToSync {
            guard let groupID = tab.syncGroupID else { continue }
            guard tab.syncIsOwner else { continue }
            let tabForExport = tabWithFileProxyHashes(tab)
            guard let exported = try? encoder.encode(tabForExport) else { continue }

            let tileCount = tab.tiles.count
            var moduleTypesSet: Set<String> = []
            for tile in tab.tiles {
                if let modules = tile.modules {
                    for m in modules {
                        switch m.kind {
                        case .person: moduleTypesSet.insert("person")
                        case .pcoRundown: moduleTypesSet.insert("pco")
                        case .pcoTeamAssignments: moduleTypesSet.insert("pcoTeamAssignments")
                        case .rosterTeamAssignments: moduleTypesSet.insert("rosterTeamAssignments")
                        case .shureWireless: moduleTypesSet.insert("shure")
                        case .shureOverview: moduleTypesSet.insert("shureOverview")
                        case .sennheiserWireless: moduleTypesSet.insert("sennheiser")
                        case .proPresenter: moduleTypesSet.insert("propresenter")
                        case .resolume: moduleTypesSet.insert("resolume")
                        case .time: moduleTypesSet.insert("time")
                        case .timecode: moduleTypesSet.insert("timecode")
                        case .dawTransport: moduleTypesSet.insert("dawTransport")
                        case .rosterPicker: moduleTypesSet.insert("rosterPicker")
                        case .text: moduleTypesSet.insert("text")
                        case .image: moduleTypesSet.insert("image")
                        case .document: moduleTypesSet.insert("document")
                        case .ndi: moduleTypesSet.insert("ndi")
                        case .webpage: moduleTypesSet.insert("webpage")
                        case .youtubeStreamMonitor: moduleTypesSet.insert("youtubeStreamMonitor")
                        case .separator: moduleTypesSet.insert("separator")
                        case .dbReader: moduleTypesSet.insert("dbReader")
                        case .liveTranscription: moduleTypesSet.insert("liveTranscription")
                        case .button: moduleTypesSet.insert("button")
                        case .rta: moduleTypesSet.insert("rta")
                        case .spectrograph: moduleTypesSet.insert("spectrograph")
                        }
                    }
                } else {
                    switch tile.kind {
                    case .person: moduleTypesSet.insert("person")
                    case .pcoPlaceholder: moduleTypesSet.insert("pco")
                    case .time: moduleTypesSet.insert("time")
                    case .empty: break
                    }
                }
            }

            let version = SyncedTabVersion(
                revision: tab.syncRevision,
                editedAt: tab.syncLastEditedAt,
                editedByDeviceID: tab.syncLastEditedByDeviceID
            )

            entries.append((
                groupID: groupID,
                tabName: tab.name,
                exportedTabJSON: exported,
                version: version,
                lastEditedByDeviceName: tab.syncLastEditedByDeviceName,
                tileCount: tileCount,
                moduleTypes: Array(moduleTypesSet).sorted(),
                schemaVersion: 1
            ))
        }

        lanService.setSyncedTabs(entries)

        // Also publish tabs this device has joined as a subscriber, so LAN settings can
        // show them even though they're excluded from both hostedSyncedManifests (not owned)
        // and syncedRemoteManifests (already joined, no longer "available to join").
        var joinedManifests: [SyncedTabManifest] = []
        for tab in tabsToSync {
            guard let groupID = tab.syncGroupID, !tab.syncIsOwner else { continue }
            let ownerID = tab.syncOwnerDeviceID ?? tab.syncLastEditedByDeviceID
            let ownerName = lanService.peers.first(where: { $0.deviceId == ownerID })?.deviceName
                ?? (tab.syncLastEditedByDeviceName.isEmpty ? "Unknown host" : tab.syncLastEditedByDeviceName)
            joinedManifests.append(SyncedTabManifest(
                groupID: groupID,
                tabName: tab.name,
                deviceID: ownerID,
                deviceName: ownerName,
                version: SyncedTabVersion(
                    revision: tab.syncRevision,
                    editedAt: tab.syncLastEditedAt,
                    editedByDeviceID: tab.syncLastEditedByDeviceID
                ),
                summary: SyncedTabManifest.Summary(tileCount: tab.tiles.count, moduleTypes: [])
            ))
        }
        lanService.setJoinedSyncedTabs(joinedManifests)
    }

    // MARK: - Toolbar Helper
    /// Reorder local tabs by dragging one local tab pill onto another.
    private func reorderLocalTabs(draggedID: UUID, onto targetID: UUID) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == draggedID }),
              let toIndex = tabs.firstIndex(where: { $0.id == targetID }),
              fromIndex != toIndex else { return }

        // Preserve selection by ID.
        let selectedID: UUID? = tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex].id : nil

        pushUndoSnapshot("Reorder Tabs")

        var updated = tabs
        let moved = updated.remove(at: fromIndex)

        let insertIndex = min(max(toIndex, 0), updated.count)
        updated.insert(moved, at: insertIndex)
        tabs = updated

        if let selectedID, let newIndex = tabs.firstIndex(where: { $0.id == selectedID }) {
            selectedTabIndex = newIndex
        } else if !tabs.isEmpty {
            selectedTabIndex = min(selectedTabIndex, tabs.count - 1)
        } else {
            selectedTabIndex = 0
        }

        saveState.hasUnsavedChanges = true
        scheduleTabsSaveDebounced()
    }

    private struct LocalTabDropDelegate: DropDelegate {
        let targetID: UUID
        let onReorder: (UUID, UUID) -> Void
        @Binding var draggingID: UUID?

        func dropEntered(info: DropInfo) {
            guard let dragged = draggingID, dragged != targetID else { return }
            onReorder(dragged, targetID)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingID = nil
            return true
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }
    }
        // MARK: - Selected Tab Access Helpers
        private var hasSelectedTab: Bool {
            tabs.indices.contains(selectedTabIndex)
        }

        private var selectedTabSafe: DashboardTab? {
            hasSelectedTab ? tabs[selectedTabIndex] : nil
        }
        private var selectedTabBindingSafe: Binding<DashboardTab>? {
            guard let selectedTab = selectedTabSafe else { return nil }
            let tabID = selectedTab.id
            return Binding(
                get: {
                    guard let index = DashboardTabIdentityMutation.index(of: tabID, in: self.tabs) else {
                        return selectedTab   // last-known snapshot; the tab was deleted
                    }
                    return self.tabs[index]
                },
                set: { newValue in
                    guard DashboardTabIdentityMutation.replaceTab(newValue, withID: tabID, in: &self.tabs) else {
                        // The tab was deleted/reordered out from under a stale binding.
                        // Dropping the write is correct, but it's still lost user input.
                        RelayDiagnosticsStore.shared.incrementCounter("ui.canvas.setTab.rejected")
                        return
                    }
                }
            )
        }

        /// A tab binding whose `.graph` resolves to the correct backing store:
        /// the document `universalGraph` in shared mode, the tab's own graph in private mode.
        /// Writes route graph edits to the right store WITHOUT persisting a universal copy
        /// into `tabs[idx].graph` (which is what previously caused the duplication + crashes).
        private var resolvedGraphTabBinding: Binding<DashboardTab>? {
            guard let selectedTab = selectedTabSafe else { return nil }
            let tabID = selectedTab.id

            return Binding(
                get: {
                    guard let index = DashboardTabIdentityMutation.index(of: tabID, in: self.tabs) else {
                        return selectedTab   // last-known snapshot; the tab was deleted
                    }
                    var value = self.tabs[index]
                    if value.automationMode == .universal { value.graph = self.universalGraph }
                    return value
                },
                set: { newValue in
                    guard let index = DashboardTabIdentityMutation.index(of: tabID, in: self.tabs) else {
                        // The tab was deleted/reordered out from under a stale binding.
                        // Dropping the write is correct, but it's still lost user input.
                        RelayDiagnosticsStore.shared.incrementCounter("ui.canvas.setTab.rejected")
                        return
                    }
                    // Unchanged routing: universal edits go to `universalGraph`, and the
                    // tab's own `graph` is preserved so no universal copy is persisted.
                    if self.tabs[index].automationMode == .universal {
                        if let editedGraph = newValue.graph { self.universalGraph = editedGraph }
                        var t = newValue
                        t.graph = self.tabs[index].graph
                        self.tabs[index] = t
                    } else {
                        self.tabs[index] = newValue
                    }
                }
            )
        }

private func topToolbar() -> some View {
    let localIsMirror = (selectedTabSafe?.lanMirrorShareId != nil)
    let isMirrorTabSelected: Bool = (selectedLANShareId != nil) || localIsMirror
    let canUndo = (systemUndoManager?.canUndo ?? false) && !isMirrorTabSelected
    let canRedo = (systemUndoManager?.canRedo ?? false) && !isMirrorTabSelected

    #if os(iOS)
    return DashboardTopToolbarView(
        lanService: lanService,
        tabs: $tabs,
        selectedTabIndex: $selectedTabIndex,
        selectedLANShareId: $selectedLANShareId,
        selectedLANDeviceName: $selectedLANDeviceName,
        lanMirrorReferenceCanvasSize: $lanMirrorReferenceCanvasSize,
        recomputeLANMirrorScale: {
            recomputeLANMirrorScale()
        },
        lanSharingEnabled: lanHostingAllowed,
        isGraphMode: layoutMode == .graph,
        automationScopePrimerShown: $automationScopePrimerShown,
        onSetAutomationMode: { newMode in
            requestAutomationModeChange(to: newMode)
        },
        onSelectAutomationScopeForTab: { tabID in
            requestAutomationModeChangeForTab(tabID)
        },
        onAutomationContextualAction: {
            handleAutomationContextualAction()
        },
        isTileOverviewVisible: $isTileOverviewVisible,
        isInspectorVisible: $isInspectorVisible,
        editingTileID: $editingTileID,
        selectedTileIDs: $selectedTileIDs,
        focusTileForInspector: { tileID in
            focusTileForInspector(tileID: tileID)
        },
        bindingForEditingTile: {
            bindingForEditingTile()
        },
        clearEditFocusOffsetsX: {
        },
        deleteTilesWithIDs: { ids in
            deleteTiles(with: ids)
        },
        deleteSelectedTiles: {
            deleteSelectedTiles()
        },
        onTabInteractionChanged: { isActive in
            if isTabInteractionActive == isActive { return }
            isTabInteractionActive = isActive
            updateLANPollingState()
            if !isActive {
                scheduleLANShareUpdateDebounced()
                scheduleSyncedTabPushDebounced()
            }
        },
        onUndo: {
            undo()
        },
        onRedo: {
            redo()
        },
        canUndo: canUndo,
        canRedo: canRedo,
        showingPCOConfigForTab: $showingPCOConfigForTab,
        showingRosters: $showingRosters,
        showingSettings: $showingSettings,
        isLiveMode: $isLiveMode,
        snapToGridEnabled: $snapToGridEnabled,
        showGridEnabled: $showGridEnabled,
        showGuidesEnabled: $showGuidesEnabled,
        iPadAutoHideToolbarEnabled: $iPadAutoHideToolbarEnabled,
        isTutorialPresented: $tutorialController.isPresented,
        canvasSize: canvasSize,
        documentDefaultCanvasSize: canvasBoundsStore.size,
        isMirrorTabSelected: isMirrorTabSelected,
        reorderLocalTabs: { dragged, onto in
            reorderLocalTabs(draggedID: dragged, onto: onto)
        },
        duplicateTab: { idx in
            duplicateTab(at: idx)
        },
        deleteTab: { idx in
            deleteTab(at: idx)
        },
        addTab: {
            addTab()
        },
        presentCanvasSizeForTab: { index in
            presentCanvasSizeForTab(at: index)
        },
        makeSyncedTab: { index in
            makeSyncedTab(at: index)
        },
        stopSyncingTab: { index in
            stopSyncingTab(at: index)
        },
        reconnectSyncedTab: { index in
            guard tabs.indices.contains(index), let gid = tabs[index].syncGroupID else { return }
            reconnectSyncedTab(groupID: gid)
        },
        joinSyncedTab: { manifest in
            joinSyncedTab(manifest)
        },
        openLANMirror: { manifest in
            await openLANMirror(manifest)
        },
        beginLANImport: { manifest in
            pendingLANImportManifest = manifest
            showingLANImportDialog = true
        },
        toggleGraphCanvas: handleToggleGraphCanvas
    )
    #else
    return DashboardTopToolbarView(
        lanService: lanService,
        tabs: $tabs,
        selectedTabIndex: $selectedTabIndex,
        selectedLANShareId: $selectedLANShareId,
        selectedLANDeviceName: $selectedLANDeviceName,
        lanMirrorReferenceCanvasSize: $lanMirrorReferenceCanvasSize,
        recomputeLANMirrorScale: {
            recomputeLANMirrorScale()
        },
        lanSharingEnabled: lanHostingAllowed,
        isGraphMode: layoutMode == .graph,
        automationScopePrimerShown: $automationScopePrimerShown,
        onSetAutomationMode: { newMode in
            requestAutomationModeChange(to: newMode)
        },
        onSelectAutomationScopeForTab: { tabID in
            requestAutomationModeChangeForTab(tabID)
        },
        onAutomationContextualAction: {
            handleAutomationContextualAction()
        },
        isTileOverviewVisible: $isTileOverviewVisible,
        isInspectorVisible: $isInspectorVisible,
        editingTileID: $editingTileID,
        selectedTileIDs: $selectedTileIDs,
        focusTileForInspector: { tileID in
            focusTileForInspector(tileID: tileID)
        },
        bindingForEditingTile: {
            bindingForEditingTile()
        },
        clearEditFocusOffsetsX: {
        },
        deleteTilesWithIDs: { ids in
            deleteTiles(with: ids)
        },
        deleteSelectedTiles: {
            deleteSelectedTiles()
        },
        onTabInteractionChanged: { isActive in
            if isTabInteractionActive == isActive { return }
            isTabInteractionActive = isActive
            updateLANPollingState()
            if !isActive {
                scheduleLANShareUpdateDebounced()
                scheduleSyncedTabPushDebounced()
            }
        },
        onUndo: {
            undo()
        },
        onRedo: {
            redo()
        },
        canUndo: canUndo,
        canRedo: canRedo,
        showingPCOConfigForTab: $showingPCOConfigForTab,
        showingRosters: $showingRosters,
        showingSettings: $showingSettings,
        isLiveMode: $isLiveMode,
        canvasSize: canvasSize,
        documentDefaultCanvasSize: canvasBoundsStore.size,
        isMirrorTabSelected: isMirrorTabSelected,
        reorderLocalTabs: { dragged, onto in
            reorderLocalTabs(draggedID: dragged, onto: onto)
        },
        duplicateTab: { idx in
            duplicateTab(at: idx)
        },
        deleteTab: { idx in
            deleteTab(at: idx)
        },
        addTab: {
            addTab()
        },
        presentCanvasSizeForTab: { index in
            presentCanvasSizeForTab(at: index)
        },
        makeSyncedTab: { index in
            makeSyncedTab(at: index)
        },
        stopSyncingTab: { index in
            stopSyncingTab(at: index)
        },
        reconnectSyncedTab: { index in
            guard tabs.indices.contains(index), let gid = tabs[index].syncGroupID else { return }
            reconnectSyncedTab(groupID: gid)
        },
        joinSyncedTab: { manifest in
            joinSyncedTab(manifest)
        },
        openLANMirror: { manifest in
            await openLANMirror(manifest)
        },
        beginLANImport: { manifest in
            pendingLANImportManifest = manifest
            showingLANImportDialog = true
        },
        toggleGraphCanvas: handleToggleGraphCanvas

    )
    #endif

}

// MARK: - Graph: Send All to Consoles

private func syncedPresenceColor(for deviceID: String) -> Color {
    let palette: [Color] = [
        Color(red: 0.24, green: 0.52, blue: 0.89),
        Color(red: 0.13, green: 0.69, blue: 0.42),
        Color(red: 0.94, green: 0.56, blue: 0.15),
        Color(red: 0.67, green: 0.22, blue: 0.87),
        Color(red: 0.95, green: 0.26, blue: 0.39),
        Color(red: 0.07, green: 0.71, blue: 0.78),
    ]
    let hash = deviceID.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
    return palette[abs(hash) % palette.count]
}

private func handleToggleGraphCanvas() {
    withAnimation(.easeInOut(duration: 0.25)) {
        if layoutMode == .canvas && !subscriptionManager.hasPro {
            tutorialController.start(kind: .lockedAutomationPreview, hasPro: false)
            automationPreviewSeen = true
            return
        }
        layoutMode = (layoutMode == .canvas) ? .graph : .canvas
        if layoutMode == .graph {
            lanMirrorRefreshTask?.cancel()
            lanMirrorRefreshTask = nil
        } else {
            if selectedLANShareId != nil {
                startLANMirrorRefreshLoop()
            }
        }
        clearSelectionForViewSwitch()
    }
}

/// Triggers GraphDashboardView to compute console order + post `.prodlinkGraphSendAllToConsoles`.
/// We keep this helper in RootView so existing buttons can keep calling it without changing
/// `DashboardTopToolbarView`’s initializer.
private func fireGraphSendAllToConsoles(staggerMs: Double = 180) {
    guard layoutMode == .graph else { return }

    NotificationCenter.default.post(
        name: Notification.Name("Relay.GraphSendAllToConsolesRequested"),
        object: nil,
        userInfo: [
            "delayMs": max(0, staggerMs),
            "includeAssignments": true,
            "includeSnapshots": true
        ]
    )
}

    private func startLANMirrorRefreshLoop() {
        // Do not poll while in Graph view or when a LAN mirror tab is not active.
        guard layoutMode != .graph, isLANMirrorTabActive else { return }

        lanMirrorRefreshTask?.cancel()
        lanMirrorRefreshTask = Task {
            while !Task.isCancelled {
                // Stop polling immediately if we enter Graph view or leave the LAN mirror tab.
                let shouldContinue = await MainActor.run {
                    layoutMode != .graph && isLANMirrorTabActive
                }
                if !shouldContinue {
                    break
                }
                let interval = lanPollIntervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await refreshLANRenderOnce()
            }
        }
    }
    @MainActor
    private func refreshLANRenderOnce() async {
        guard isLANMirrorTabActive, let shareId = selectedLANShareId else { return }
        let peer: LANSharedTabsService.Peer? = {
            if let mapped = lanService.peerForShareId(shareId) {
                return mapped
            }
            if let endpointKey = selectedLANPeerEndpointKey,
               let byEndpoint = lanService.peers.first(where: { $0.endpointKey == endpointKey }) {
                return byEndpoint
            }
            let targetName = selectedLANDeviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !targetName.isEmpty {
                if let exact = lanService.peers.first(where: {
                    ($0.deviceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == targetName
                }) {
                    return exact
                }
                if let contains = lanService.peers.first(where: {
                    ($0.deviceName ?? "").localizedCaseInsensitiveContains(targetName)
                }) {
                    return contains
                }
            }
            return lanService.peers.sorted(by: { $0.lastSeen > $1.lastSeen }).first
        }()
        guard let peer else { return }

        do {
            let data = try await lanService.fetchSharedTabRender(shareId: shareId, from: peer)
            if let image = decodeLANRenderImage(from: data) {
                lanRenderImage = image
            }
        } catch {
            // ignore transient failures
        }
    }
    @MainActor
    private func performLANImport(mode: LANImportMode, adjustCanvasToImport: Bool) async {
        guard let manifest = pendingLANImportManifest else { return }
        if mode == .addNewTab && !subscriptionManager.hasPro {
            showingProUpgrade = true
            pendingLANImportManifest = nil
            return
        }

        // Make sure we know which peer owns this shareId
        guard let peer = lanService.peerForShareId(manifest.shareId) else {
            lanImportErrorMessage = "No peer found for shareId \(manifest.shareId)."
            pendingLANImportManifest = nil
            return
        }

        do {
            // Fetch bundle (tab + settings snapshots)
            let bundle = try await lanService.fetchSharedTabImportBundle(shareId: manifest.shareId, from: peer)

            // Decode the remote tab
            let remoteTab = try JSONDecoder().decode(DashboardTab.self, from: bundle.payload.exportedTabJSON)

            // Canvas size is now per-tab; LAN import no longer changes the global canvas size.

            // LAN imports should keep the local canvas size and avoid auto-scaling tiles.
            pendingImportReferenceCanvasSize = nil
            pendingImportScaleTabIDs = nil
            didApplyImportDeviceFitScale = true

            // Decode external devices snapshot if present, and only prompt if
            // imported devices or LAN-shared settings differ from local config.
            var importedExternalDevicesSnapshot: ExternalDevicesStore.Snapshot? = nil
            if let extJSON = bundle.externalDevicesJSON {
                if let snap = try? JSONDecoder().decode(ExternalDevicesStore.Snapshot.self, from: extJSON) {
                    let hasIncomingDevices = !snap.devices.isEmpty || snap.shureSelectedChannel != nil
                    importedExternalDevicesSnapshot = hasIncomingDevices ? snap : nil
                }
            }

            let externalDevicesHaveChanges: Bool = {
                guard let snapshot = importedExternalDevicesSnapshot else { return false }
                return externalDevicesSnapshotHasChanges(snapshot)
            }()
            let lanSettingsHaveChanges = lanService.importedSettingsHasChanges(from: bundle)

            if externalDevicesHaveChanges || lanSettingsHaveChanges {
                pendingImportedExternalDevicesSnapshot = externalDevicesHaveChanges ? importedExternalDevicesSnapshot : nil
                pendingImportedSettingsSnapshot = nil
                pendingImportedLANSettingsBundle = lanSettingsHaveChanges ? bundle : nil
                showingExternalDevicesImportDialog = true
            } else {
                clearPendingImportedConfiguration()
                #if DEBUG
                print("[ExternalDevices][Import] LAN import: devices/settings already match local config; skipping prompt")
                #endif
            }

            // Now import tab data
            switch mode {
            case .addNewTab:
                var newTab = remoteTab

                // Ensure it has a name
                var baseName = newTab.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if baseName.isEmpty {
                    baseName = manifest.tabName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if baseName.isEmpty {
                    baseName = "Imported Tab"
                }

                // Make the name unique
                let existingNames = Set(tabs.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
                var candidate = baseName
                var n = 2
                while existingNames.contains(candidate) {
                    candidate = "\(baseName) \(n)"
                    n += 1
                }

                newTab.name = candidate

                // Append and select
                tabs.append(newTab)
                selectedTabIndex = max(tabs.count - 1, 0)
            }

            migrateLegacyTilesToModulesIfNeeded()

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()

            // cleanup
            pendingLANImportManifest = nil

        } catch {
            lanImportErrorMessage = "\(error)"
            pendingLANImportManifest = nil
        }
    }
    @MainActor
    private func openLANMirror(_ manifest: LANSharedTabManifest) async {
        do {
            // Resolve peer using only known peers from lanService.peers, with a series of fallbacks.
            let peer: LANSharedTabsService.Peer? = {
                // Primary path: owner map
                if let p = lanService.peerForShareId(manifest.shareId) {
                    return p
                }

                // Fallback: match by device name from currently known peers
                let targetName = manifest.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !targetName.isEmpty {
                    if let exact = lanService.peers.first(where: {
                        ($0.deviceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == targetName
                    }) {
                        return exact
                    }

                    if let contains = lanService.peers.first(where: {
                        ($0.deviceName ?? "").localizedCaseInsensitiveContains(targetName)
                    }) {
                        return contains
                    }
                }

                // Last resort: most recently seen peer
                return lanService.peers.sorted(by: { $0.lastSeen > $1.lastSeen }).first
            }()

            guard let peer else {
                print("❌ LAN mirror: no peer found for shareId \(manifest.shareId) (no matching peers available)")
                return
            }

            let data = try await lanService.fetchSharedTabRender(shareId: manifest.shareId, from: peer, attemptPairingIfNeeded: true)
            let image = decodeLANRenderImage(from: data)

            selectedLANShareId = manifest.shareId
            selectedLANDeviceName = manifest.deviceName
            selectedLANPeerEndpointKey = peer.endpointKey
            lanRenderImage = image

            #if DEBUG
            print("✅ LAN render applied: device=\(manifest.deviceName) tab=\(manifest.tabName) shareId=\(manifest.shareId)")
            #endif

            isInspectorVisible = false
            editingTileID = nil

        } catch {
            print("❌ LAN mirror open failed: \(error)")

            if let nsError = error as NSError?, nsError.domain == "Relay.LAN", nsError.code == 404 {
                // No render yet; keep selection and let the refresh loop retry.
                return
            }

            // If the open failed (common: 401 unauthorized because this device isn't paired),
            // don't leave the user stuck on a black mirror selection.
            await MainActor.run {
                if selectedLANShareId == manifest.shareId {
                    selectedLANShareId = nil
                    selectedLANDeviceName = nil
                    selectedLANPeerEndpointKey = nil

                    // Clear any cached render so the UI doesn't keep showing stale content.
                    lanRenderImage = nil

                    // `lanMirrorTab` is non-optional in this build. Reset it to an empty tab
                    // so the UI doesn't keep rendering stale mirrored content.
                    lanMirrorTab = DashboardTab(name: "", tiles: [])

                    lanMirrorReferenceCanvasSize = nil
                    lanMirrorScale = 1.0
                }
            }
        }
    }
        // MARK: - Inspector Helper

        
@ViewBuilder
private func inspectorView(for tileBinding: Binding<DashboardTileModel>) -> some View {
    // Avoid out-of-bounds crashes if tabs are mutated (reorder/delete/import) during a render pass.
    if let tabBinding = selectedTabBindingSafe {
        let tileValue = tileBinding.wrappedValue
        DashboardInspectorPanelView(
            inspectorPanelWidth: inspectorPanelWidth,
            tabs: $tabs,
            sharedRosters: $sharedRosters,
            selectedTabIndex: $selectedTabIndex,
            selectedTileIDs: $selectedTileIDs,
            editingTileID: $editingTileID,
            isInspectorVisible: $isInspectorVisible,
            pendingModuleCatalogTileID: $pendingModuleCatalogTileID,
            pendingFirstModuleSelectTileID: $pendingFirstModuleSelectTileID,
            clearEditFocusOffsetsX: {
            },
            pushUndoSnapshot: { actionName in
                pushUndoSnapshot(actionName)
            },
            markUnsavedAndScheduleSave: {
                saveState.hasUnsavedChanges = true
                scheduleTabsSaveDebounced()
            },
            tileBinding: tileBinding,
            tabBinding: tabBinding,
            onOpenPCOTabSettings: {
                showingPCOConfigForTab = true
            },
            tileHeightPoints: effectiveSize(for: tileValue).height,
            defaultTileSize: defaultTileSize
        )
        .id(tileValue.id)
    }
}
        
        // MARK: - Undo / Redo

        private func pushUndoSnapshot(_ actionName: String = "Edit Dashboard") {
            guard let um = systemUndoManager else { return }

            let oldTabs = tabs
            let oldSelectedIndex = selectedTabIndex

            um.registerUndo(withTarget: undoBridge) { bridge in
                let newTabs = bridge.tabs?.wrappedValue ?? []
                let newSelectedIndex = bridge.selectedTabIndex?.wrappedValue ?? 0

                bridge.applyTabs(oldTabs, selectedIndex: oldSelectedIndex)

                um.registerUndo(withTarget: bridge) { b2 in
                    b2.applyTabs(newTabs, selectedIndex: newSelectedIndex)
                    um.setActionName(actionName)
                }

                um.setActionName(actionName)
            }

            um.setActionName(actionName)
        }

        /// Class target used for UndoManager registration (UndoManager requires a class target).
        private final class DashboardUndoBridge: NSObject {
            var tabs: Binding<[DashboardTab]>?
            var selectedTabIndex: Binding<Int>?
            var hasUnsavedChanges: Binding<Bool>?

            func bind(
                tabs: Binding<[DashboardTab]>,
                selectedTabIndex: Binding<Int>,
                hasUnsavedChanges: Binding<Bool>
            ) {
                self.tabs = tabs
                self.selectedTabIndex = selectedTabIndex
                self.hasUnsavedChanges = hasUnsavedChanges
            }

            func applyTabs(_ newTabs: [DashboardTab], selectedIndex: Int) {
                tabs?.wrappedValue = newTabs
                if newTabs.isEmpty {
                    selectedTabIndex?.wrappedValue = 0
                } else {
                    selectedTabIndex?.wrappedValue = min(max(selectedIndex, 0), newTabs.count - 1)
                }
                hasUnsavedChanges?.wrappedValue = true
            }
        }

        private func undo() { systemUndoManager?.undo() }
        private func redo() { systemUndoManager?.redo() }
        /// Binding for the tile currently being edited in the inspector sidebar.
        private func bindingForEditingTile() -> Binding<DashboardTileModel>? {
            guard let id = editingTileID,
                  let tabBinding = selectedTabBindingSafe,
                  let idx = tabBinding.wrappedValue.tiles.firstIndex(where: { $0.id == id }) else {
                return nil
            }

            let fallbackTile = tabBinding.wrappedValue.tiles[idx]

            // Create an explicit binding to the array element to avoid out-of-bounds crashes
            // during transient tab mutations.
            return Binding<DashboardTileModel>(
                get: {
                    tabBinding.wrappedValue.tiles.first(where: { $0.id == id }) ?? fallbackTile
                },
                set: { newValue in
                    guard let currentIndex = tabBinding.wrappedValue.tiles.firstIndex(where: { $0.id == id }) else { return }
                    tabBinding.wrappedValue.tiles[currentIndex] = newValue
                }
            )
        }
        
        /// Current selection rectangle in viewport coordinates (screen space) while dragging.
        private var selectionRectViewport: CGRect? {
            guard let start = selectionStartPoint,
                  let current = selectionCurrentPoint else {
                return nil
            }
            
            let minX = min(start.x, current.x)
            let maxX = max(start.x, current.x)
            let minY = min(start.y, current.y)
            let maxY = max(start.y, current.y)
            
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        
        /// Current selection rectangle in canvas coordinates, accounting for pan/zoom.
        private var selectionRectCanvas: CGRect? {
            guard let viewportRect = selectionRectViewport else { return nil }
            let zoom = max(0.0001, canvasViewportZoom)
            
            let origin = CGPoint(
                x: (viewportRect.origin.x - canvasViewportPan.width) / zoom,
                y: (viewportRect.origin.y - canvasViewportPan.height) / zoom
            )
            let size = CGSize(
                width: viewportRect.size.width / zoom,
                height: viewportRect.size.height / zoom
            )
            
            return CGRect(origin: origin, size: size)
        }
        
        /// Computes the effective size for a tile, matching DashboardTileContainer.
        private func effectiveSize(for tile: DashboardTileModel) -> CGSize {
            let minWidth: CGFloat = 44
            let minHeight: CGFloat = 44
            
            // Width: either user-defined or default.
            let baseWidth = tile.size?.width ?? defaultTileSize.width
            let width = max(minWidth, baseWidth)
            
            // Height: auto-grow based on module count unless the user has
            // explicitly resized the tile.
            let explicitHeight = tile.size?.height
            let moduleCount = tile.modules?.count ?? 0
            
            let height: CGFloat
            if let explicitHeight {
                height = explicitHeight
            } else if moduleCount > 0 {
                let extraPerModule: CGFloat = 80
                height = defaultTileSize.height + CGFloat(moduleCount - 1) * extraPerModule
            } else {
                height = defaultTileSize.height
            }
            
            return CGSize(
                width: width,
                height: max(minHeight, height)
            )
        }
        
        /// Returns a short human-readable summary of what a tile contains, used by
        /// the left-side tile overview.
        private func tileSummary(for tile: DashboardTileModel, in tab: DashboardTab) -> String {
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
                    case .image:
                        return "Image"
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
                return parts.joined(separator: ", ")
            } else {
                switch tile.kind {
                case .empty:
                    return "Empty Tile"
                case .person(let model):
                    let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? "Person Tile" : "Person: \(name)"
                case .pcoPlaceholder:
                    return "PCO Placeholder"
                case .time:
                    return "Time Tile"
                    
                }
            }
        }
        
        /// Updates `selectedTileIDs` based on which tiles intersect the given selection rect.
        private func updateSelection(with rect: CGRect) {
            guard tabs.indices.contains(selectedTabIndex) else { return }
            
            var newSelection = Set<UUID>()
            
            for tile in tabs[selectedTabIndex].tiles {
                let size = effectiveSize(for: tile)
                let tileRect = CGRect(
                    x: tile.offset.width,
                    y: tile.offset.height,
                    width: size.width,
                    height: size.height
                )
                
                if rect.intersects(tileRect) {
                    newSelection.insert(tile.id)
                }
            }
            
            selectedTileIDs = newSelection
            selectionSource = .canvas
            groupSelectionColor = nil

            if isInspectorVisible {
                if newSelection.isEmpty {
                    // No tiles selected: close inspector
                    editingTileID = nil
                    isInspectorVisible = false
                } else if let first = newSelection.first {
                    // One or more tiles selected: retarget inspector to the first selected tile
                    editingTileID = first
                }
            }
        }
        private func moveSelectedTiles(anchorID: UUID, translation: CGSize) {
            guard tabs.indices.contains(selectedTabIndex) else { return }
            // Only perform a group move if the anchor tile is part of the selection
            // and there is more than one tile selected.
            guard selectedTileIDs.contains(anchorID), selectedTileIDs.count > 1 else { return }

            guard abs(translation.width) > 0.001 || abs(translation.height) > 0.001 else { return }

            var didMove = false

            // Called once at gesture end with the final translation to apply the
            // group move to all other selected tiles. Per-frame visual following
            // during the drag is handled separately via DashboardTileInteractionSession.
            for index in tabs[selectedTabIndex].tiles.indices {
                if selectedTileIDs.contains(tabs[selectedTabIndex].tiles[index].id),
                   tabs[selectedTabIndex].tiles[index].id != anchorID {
                    tabs[selectedTabIndex].tiles[index].offset.width += translation.width
                    tabs[selectedTabIndex].tiles[index].offset.height += translation.height
                    didMove = true
                }
            }

            if didMove {
                saveState.hasUnsavedChanges = true
            }
        }

        /// Applies a canvas-fraction region to a single tile: resizes and repositions
        /// it to exactly fill that region. Single-tile only — ambiguous for a group.
        private func applyFractionRegion(_ region: CanvasFractionRegion, toTileID tileID: UUID) {
            guard tabs.indices.contains(selectedTabIndex),
                  let idx = tabs[selectedTabIndex].tiles.firstIndex(where: { $0.id == tileID }),
                  canvasSize.width > 0, canvasSize.height > 0
            else { return }

            pushUndoSnapshot("Resize Tile")

            let rect = region.rect(in: canvasSize)
            tabs[selectedTabIndex].tiles[idx].offset = CGSize(width: rect.origin.x, height: rect.origin.y)
            tabs[selectedTabIndex].tiles[idx].size = CGSize(width: rect.width, height: rect.height)

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        /// Commits an option-drag-to-snap. A single dragged tile behaves
        /// exactly like `applyFractionRegion` (the Size button); a 2+ tile
        /// selection whose anchor was dragged instead distributes every
        /// selected tile edge-to-edge within the target region's rect,
        /// reusing `TileDistribution` exactly as `distributeSelectedTiles`
        /// does -- just scoped to `region.rect(in: canvasSize)` instead of
        /// the whole canvas. Reuses `applyFractionRegion`'s "Resize Tile"
        /// undo title and `distributeSelectedTiles`'s "Distribute Tiles"
        /// undo title rather than inventing new ones, since both paths are
        /// the same underlying operation as their button-triggered
        /// counterparts, just reached via a drag instead of a click.
        private func applySnapRegion(_ region: CanvasFractionRegion, anchorID: UUID) {
            guard TileDistribution.isMultiTileSelection(anchorID: anchorID, selectedTileIDs: selectedTileIDs) else {
                applyFractionRegion(region, toTileID: anchorID)
                return
            }
            guard tabs.indices.contains(selectedTabIndex),
                  canvasSize.width > 0, canvasSize.height > 0
            else { return }

            let distributable = tabs[selectedTabIndex].tiles
                .filter { selectedTileIDs.contains($0.id) }
                .map { DistributableTile(id: $0.id, offset: $0.offset) }

            guard let newFrames = TileDistribution.distribute(tiles: distributable, into: region.rect(in: canvasSize)) else {
                return
            }

            pushUndoSnapshot("Distribute Tiles")

            for idx in tabs[selectedTabIndex].tiles.indices {
                if let newFrame = newFrames[tabs[selectedTabIndex].tiles[idx].id] {
                    tabs[selectedTabIndex].tiles[idx].offset = CGSize(width: newFrame.origin.x, height: newFrame.origin.y)
                    tabs[selectedTabIndex].tiles[idx].size = CGSize(width: newFrame.width, height: newFrame.height)
                }
            }

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        /// Divides the canvas into equal panes along `axis` and resizes/repositions
        /// the currently-selected tiles to exactly fill them, edge-to-edge — like
        /// macOS's split-screen thirds, generalized to the selection count. No-ops
        /// below 2 selected tiles (matches `TileDistribution.distribute`'s own guard).
        private func distributeSelectedTiles(axis: DistributeAxis) {
            guard tabs.indices.contains(selectedTabIndex), selectedTileIDs.count >= 2 else { return }

            let distributable = tabs[selectedTabIndex].tiles
                .filter { selectedTileIDs.contains($0.id) }
                .map { DistributableTile(id: $0.id, offset: $0.offset) }

            let newFrames = TileDistribution.distribute(tiles: distributable, axis: axis, canvasSize: canvasSize)
            guard !newFrames.isEmpty else { return }

            pushUndoSnapshot("Distribute Tiles")

            for idx in tabs[selectedTabIndex].tiles.indices {
                if let newFrame = newFrames[tabs[selectedTabIndex].tiles[idx].id] {
                    tabs[selectedTabIndex].tiles[idx].offset = CGSize(width: newFrame.origin.x, height: newFrame.origin.y)
                    tabs[selectedTabIndex].tiles[idx].size = CGSize(width: newFrame.width, height: newFrame.height)
                }
            }

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        #if os(macOS)
        /// Nudge selected tiles by a translation in canvas coordinates.
        /// Returns true if at least one tile moved.
        private func nudgeSelectedTiles(translation: CGSize, onFirstMove: () -> Void) -> Bool {
            guard !selectedTileIDs.isEmpty else { return false }
            guard tabs.indices.contains(selectedTabIndex) else { return false }

            var didMove = false
            var didInvokeFirstMove = false
            let selected = selectedTileIDs

            for tileID in selected {
                guard let idx = tabs[selectedTabIndex].tiles.firstIndex(where: { $0.id == tileID }) else { continue }

                var tile = tabs[selectedTabIndex].tiles[idx]
                let size = effectiveTileSize(for: tile)

                let newX = tile.offset.width + translation.width
                let newY = tile.offset.height + translation.height

                // Allow nudged tiles to move outside the canvas bounds.

                // Optional overlap blocking.
                if !allowTileOverlap {
                    let proposed = CGRect(x: newX, y: newY, width: size.width, height: size.height)

                    var overlaps = false
                    for other in tabs[selectedTabIndex].tiles {
                        if other.id == tileID { continue }
                        if selected.contains(other.id) { continue }

                        let otherSize = effectiveTileSize(for: other)
                        let otherRect = CGRect(
                            x: other.offset.width,
                            y: other.offset.height,
                            width: otherSize.width,
                            height: otherSize.height
                        )
                        if proposed.intersects(otherRect) {
                            overlaps = true
                            break
                        }
                    }
                    if overlaps { continue }
                }

                if abs(newX - tile.offset.width) > 0.0001 || abs(newY - tile.offset.height) > 0.0001 {
                    if !didInvokeFirstMove {
                        didInvokeFirstMove = true
                        onFirstMove()
                    }
                    tile.offset.width = newX
                    tile.offset.height = newY
                    tabs[selectedTabIndex].tiles[idx] = tile
                    didMove = true
                }
            }

            return didMove
        }
        #endif
        
        /// Duplicates all currently selected tiles on the active tab, offsetting the
        /// copies slightly so they are visible, and updates the selection to the new copies.
        private func duplicatedModule(from module: DashboardModuleModel) -> DashboardModuleModel {
            DashboardModuleModel(
                kind: module.kind.duplicatedForCanvasCopy(),
                order: module.order,
                id: UUID(),
                pcoConfig: module.pcoConfig,
                shureConfig: module.shureConfig,
                shureOverviewConfig: module.shureOverviewConfig,
                sennheiserConfig: module.sennheiserConfig,
                proPresenterConfig: module.proPresenterConfig,
                resolumeConfig: module.resolumeConfig,
                timeConfig: module.timeConfig,
                timecodeConfig: module.timecodeConfig,
                paddingTop: module.paddingTop,
                paddingBottom: module.paddingBottom,
                moduleScale: module.moduleScale,
                moduleHeightPoints: module.moduleHeightPoints
            )
        }

        private func duplicatedTile(
            from tile: DashboardTileModel,
            id: UUID = UUID(),
            offset: CGSize? = nil
        ) -> DashboardTileModel {
            let newModules = tile.modules?.map(duplicatedModule)

            return DashboardTileModel(
                id: id,
                name: tile.name,
                kind: tile.kind,
                modules: newModules,
                moduleLayout: tile.moduleLayout,
                offset: offset ?? tile.offset,
                size: tile.size,
                backgroundStyle: tile.backgroundStyle,
                backgroundOpacity: tile.backgroundOpacity,
                cornerRadius: tile.cornerRadius,
                backgroundCustomColor: tile.backgroundCustomColor,
                backgroundGradient: tile.backgroundGradient,
                shureChannelSelection: tile.shureSelectedChannel,
                shureShowDeviceName: tile.shureShowDeviceName,
                shureShowChannelName: tile.shureShowChannelName,
                shureShowIPPort: tile.shureShowIPPort,
                shureShowFrequency: tile.shureShowFrequency,
                shureShowBattery: tile.shureShowBattery,
                shureShowRFStrength: tile.shureShowRFStrength,
                textFontSize: tile.textFontSize,
                textFontWeight: tile.textFontWeight,
                textColor: tile.textColor,
                textCapitalization: tile.textCapitalization,
                textJustification: tile.textJustification,
                textVerticalAlignment: tile.textVerticalAlignment,
                showsTitle: tile.showsTitle,
                contentPadding: tile.contentPadding,
                isHidden: tile.isHidden
            )
        }

        private func duplicateSelectedTiles() {
            guard tabs.indices.contains(selectedTabIndex) else { return }
            guard !selectedTileIDs.isEmpty else { return }
            
            // Capture state before duplicating tiles
            pushUndoSnapshot("Duplicate Tiles")
            
            var tiles = tabs[selectedTabIndex].tiles
            let originalIDs = selectedTileIDs
            
            // We'll collect the IDs of the new copies to select them afterward.
            var newSelection: Set<UUID> = []
            
            // Offset new tiles slightly so they don't land exactly on top of originals.
            let offsetDelta = CGSize(width: 30, height: 30)
            
            // Preserve original order by iterating over the existing indices.
            for tile in tiles where originalIDs.contains(tile.id) {
                
                // Offset new tile position
                let newOffset = CGSize(
                    width: tile.offset.width + offsetDelta.width,
                    height: tile.offset.height + offsetDelta.height
                )
                
                // Build new tile with a fresh ID
                let newTile = duplicatedTile(from: tile, offset: newOffset)
                
                newSelection.insert(newTile.id)
                tiles.append(newTile)
            }
            
            tabs[selectedTabIndex].tiles = tiles
            selectedTileIDs = newSelection
            
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }
        
        /// Deletes the provided tile IDs from the active tab and updates selection accordingly.
        private func deleteTiles(with ids: Set<UUID>) {
            guard tabs.indices.contains(selectedTabIndex) else { return }
            guard !ids.isEmpty else { return }

            // Capture state before deleting tiles
            pushUndoSnapshot("Delete Tiles")

            tabs[selectedTabIndex].tiles.removeAll { tile in
                ids.contains(tile.id)
            }

            if !tabs[selectedTabIndex].tileGroups.isEmpty {
                var groups = tabs[selectedTabIndex].tileGroups
                for idx in groups.indices {
                    groups[idx].tileIds.removeAll { ids.contains($0) }
                }
                groups.removeAll { $0.tileIds.isEmpty }
                tabs[selectedTabIndex].tileGroups = groups
            }

            mutateEffectiveGraph(forTabAt: selectedTabIndex) { graph in
                graph.tileLayouts = graph.tileLayouts.filter { !ids.contains($0.key) }

                let removedIdStrings = Set(ids.map { $0.uuidString })
                graph.peopleTeamFiltersByNodeId = graph.peopleTeamFiltersByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.customPeopleByNodeId = graph.customPeopleByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.oscReceiveConfigByNodeId = graph.oscReceiveConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.midiReceiveConfigByNodeId = graph.midiReceiveConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.timeTriggerConfigByNodeId = graph.timeTriggerConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.dbThresholdConfigByNodeId = graph.dbThresholdConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.shureTriggerConfigByNodeId = graph.shureTriggerConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.sennheiserTriggerConfigByNodeId = graph.sennheiserTriggerConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.wordTriggerConfigByNodeId = graph.wordTriggerConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.pcoItemChangedConfigByNodeId   = graph.pcoItemChangedConfigByNodeId.filter   { !removedIdStrings.contains($0.key) }
                graph.appStateTriggerConfigByNodeId  = graph.appStateTriggerConfigByNodeId.filter  { !removedIdStrings.contains($0.key) }
                graph.httpRequestActionConfigByNodeId = graph.httpRequestActionConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.setVariableActionConfigByNodeId = graph.setVariableActionConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.toggleNodeConfigByNodeId       = graph.toggleNodeConfigByNodeId.filter       { !removedIdStrings.contains($0.key) }
                graph.counterNodeConfigByNodeId      = graph.counterNodeConfigByNodeId.filter      { !removedIdStrings.contains($0.key) }
                graph.sequenceNodeConfigByNodeId     = graph.sequenceNodeConfigByNodeId.filter     { !removedIdStrings.contains($0.key) }
                graph.latchNodeConfigByNodeId        = graph.latchNodeConfigByNodeId.filter        { !removedIdStrings.contains($0.key) }
                graph.currentTimeSourceConfigByNodeId = graph.currentTimeSourceConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.sendAllConsolesActionConfigByNodeId = graph.sendAllConsolesActionConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.oscSendActionConfigByNodeId = graph.oscSendActionConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.notifyActionConfigByNodeId = graph.notifyActionConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.midiSendActionConfigByNodeId = graph.midiSendActionConfigByNodeId.filter { !removedIdStrings.contains($0.key) }
                graph.repeaterActionConfigByNodeId = graph.repeaterActionConfigByNodeId.filter { !removedIdStrings.contains($0.key) }

                let portIdsToRemove = Set(graph.nodeIdByPortId.filter { ids.contains($0.value) }.map { $0.key })
                graph.nodeIdByPortId = graph.nodeIdByPortId.filter { !ids.contains($0.value) }

                graph.links.removeAll { link in
                    if ids.contains(link.fromTileId) { return true }
                    if ids.contains(link.toTileId) { return true }
                    if portIdsToRemove.contains(link.fromPortId) { return true }
                    if portIdsToRemove.contains(link.toPortId) { return true }
                    return false
                }
            }

            // Remove only the deleted IDs from the current selection
            selectedTileIDs.subtract(ids)

            if let editing = editingTileID, ids.contains(editing) {
                editingTileID = nil
                isInspectorVisible = false
            }
            if selectedTileIDs.isEmpty {
                selectionSource = .canvas
                groupSelectionColor = nil
            }

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        /// Deletes all currently selected tiles on the active tab and clears selection.
        private func deleteSelectedTiles() {
            let ids = selectedTileIDs
            deleteTiles(with: ids)
        }

        private func currentTabHasHiddenTiles() -> Bool {
            guard tabs.indices.contains(selectedTabIndex) else { return false }
            return tabs[selectedTabIndex].tiles.contains { $0.isHidden }
        }

        private func updateHiddenTilesFlag() {
            // Compute on main thread (reads SwiftUI state), then write UserDefaults on a
            // background queue to avoid the synchronous KVO notification chain
            // (-[NSObservableDefaults _notifyObserversOfChangeFromValuesForKeys:toValuesForKeys:])
            // that fires on the caller's thread and causes 500–1200 ms main-thread hangs.
            let hasHidden = currentTabHasHiddenTiles()
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(hasHidden, forKey: "dashboard_has_hidden_tiles")
            }
        }

        private func unhideAllTilesOnCurrentTab() {
            guard tabs.indices.contains(selectedTabIndex) else { return }

            var tab = tabs[selectedTabIndex]
            var didChange = false
            for index in tab.tiles.indices {
                if tab.tiles[index].isHidden {
                    tab.tiles[index].isHidden = false
                    didChange = true
                }
            }

            guard didChange else { return }

            tabs[selectedTabIndex] = tab
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
            updateHiddenTilesFlag()
        }

        private func toggleVisibilityForSelectedTiles() {
            guard tabs.indices.contains(selectedTabIndex) else { return }
            guard !selectedTileIDs.isEmpty else { return }

            var tab = tabs[selectedTabIndex]
            let selectedIDs = selectedTileIDs
            let shouldHide = tab.tiles.contains { tile in
                selectedIDs.contains(tile.id) && !tile.isHidden
            }

            var didChange = false
            for index in tab.tiles.indices where selectedIDs.contains(tab.tiles[index].id) {
                if tab.tiles[index].isHidden != shouldHide {
                    tab.tiles[index].isHidden = shouldHide
                    didChange = true
                }
            }

            guard didChange else { return }

            if shouldHide {
                selectedTileIDs.subtract(selectedIDs)
                if let editing = editingTileID, selectedIDs.contains(editing) {
                    editingTileID = nil
                    isInspectorVisible = false
                }
                if selectedTileIDs.isEmpty {
                    selectionSource = .canvas
                    groupSelectionColor = nil
                }
            }

            tabs[selectedTabIndex] = tab
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
            updateHiddenTilesFlag()
        }
        
        // MARK: - Tile Management
        private func seedTileGroupDraft() {
            let baseName = "Group"
            let existing = Set((tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex].tileGroups : []).map { $0.name })
            var candidate = baseName
            var idx = 1
            while existing.contains(candidate) {
                idx += 1
                candidate = "\(baseName) \(idx)"
            }
            tileGroupName = candidate
            tileGroupColor = .blue
        }

        private var tileGroupSheetSelectedCount: Int {
            switch tileGroupSheetMode {
            case .create:
                return selectedTileIDs.count
            case .edit:
                return editingTileGroupTileIDs.count
            }
        }

        private var tileGroupAvailableTiles: [DashboardTileModel] {
            guard tabs.indices.contains(selectedTabIndex) else { return [] }
            return tabs[selectedTabIndex].tiles
        }

        private var tileGroupSheetTab: DashboardTab {
            guard tabs.indices.contains(selectedTabIndex) else {
                return DashboardTab(name: "", tiles: [])
            }
            return tabs[selectedTabIndex]
        }

        private func createTileGroup(name: String, color: Color) {
            guard tabs.indices.contains(selectedTabIndex) else { return }

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return }

            let validIDs = Set(tabs[selectedTabIndex].tiles.map { $0.id })
            let selectedIDs = selectedTileIDs.intersection(validIDs)
            guard !selectedIDs.isEmpty else { return }

            pushUndoSnapshot("Create Tile Group")

            var groups = tabs[selectedTabIndex].tileGroups
            for idx in groups.indices {
                groups[idx].tileIds.removeAll { selectedIDs.contains($0) }
            }
            groups.removeAll { $0.tileIds.isEmpty }

            let newGroup = DashboardTileGroup(
                name: trimmedName,
                color: CodableColor(color),
                tileIds: Array(selectedIDs)
            )
            groups.append(newGroup)
            tabs[selectedTabIndex].tileGroups = groups

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        private func beginEditTileGroup(_ group: DashboardTileGroup) {
            tileGroupSheetMode = .edit
            editingTileGroupID = group.id
            tileGroupName = group.name
            tileGroupColor = group.color.swiftUIColor

            if tabs.indices.contains(selectedTabIndex) {
                let validIDs = Set(tabs[selectedTabIndex].tiles.map { $0.id })
                editingTileGroupTileIDs = Set(group.tileIds).intersection(validIDs)
            } else {
                editingTileGroupTileIDs.removeAll()
            }

            showingTileGroupSheet = true
        }

        private func updateTileGroup(id: UUID, name: String, color: Color, tileIDs: Set<UUID>) {
            guard tabs.indices.contains(selectedTabIndex) else { return }

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return }
            guard let idx = tabs[selectedTabIndex].tileGroups.firstIndex(where: { $0.id == id }) else { return }

            let validIDs = Set(tabs[selectedTabIndex].tiles.map { $0.id })
            let filteredIDs = tileIDs.intersection(validIDs)
            guard !filteredIDs.isEmpty else { return }

            pushUndoSnapshot("Edit Tile Group")

            tabs[selectedTabIndex].tileGroups[idx].name = trimmedName
            tabs[selectedTabIndex].tileGroups[idx].color = CodableColor(color)
            tabs[selectedTabIndex].tileGroups[idx].tileIds = Array(filteredIDs)

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        private func deleteTileGroup(id: UUID) {
            guard tabs.indices.contains(selectedTabIndex) else { return }
            guard let idx = tabs[selectedTabIndex].tileGroups.firstIndex(where: { $0.id == id }) else { return }

            pushUndoSnapshot("Delete Tile Group")

            tabs[selectedTabIndex].tileGroups.remove(at: idx)

            if editingTileGroupID == id {
                editingTileGroupID = nil
            }

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        private func centerInitialTileIfNeeded() {
            guard needsInitialTileCentering else { return }
            needsInitialTileCentering = false

            guard tabs.count == 1, tabs[0].tiles.count == 1 else { return }
            guard tabs[0].tiles[0].offset == .zero else { return }

            let canvas = canvasSize
            let tileSize = defaultTileSize
            let centeredOffset = CGSize(
                width: (canvas.width - tileSize.width) * 0.5,
                height: (canvas.height - tileSize.height) * 0.5
            )
            let clampedOffset = CGSize(
                width: max(0, centeredOffset.width),
                height: max(0, centeredOffset.height)
            )

            tabs[0].tiles[0].offset = clampedOffset
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        private func addEmptyTile(openModuleCatalog: Bool = false) {
            guard tabs.indices.contains(selectedTabIndex) else { return }
            
            // Capture state before adding a new tile
            pushUndoSnapshot("Add Tile")
            
            // Match the default tile size used in DashboardTileContainer.
            let spacing: CGFloat = 20
            
            // Determine the canvas width/height we can lay tiles into.
            let canvasWidth = canvasSize.width > 0 ? canvasSize.width : 1200
            let canvasHeight = canvasSize.height > 0 ? canvasSize.height : 800
            
            // Helper that returns a rect for a given offset.
            func rectFor(offset: CGSize, size: CGSize) -> CGRect {
                CGRect(x: offset.width,
                       y: offset.height,
                       width: size.width,
                       height: size.height)
            }
            
            // Collect existing tile rects for collision checking.
            let existingRects: [CGRect] = tabs[selectedTabIndex].tiles.map { tile in
                let size = effectiveSize(for: tile)
                return rectFor(offset: tile.offset, size: size)
            }
            
            // Start from the center of the *current viewport* in canvas coordinates,
            // then walk outward in a simple grid until we find a free position.
            let zoom = max(0.0001, canvasViewportZoom)
            let viewportSize = canvasViewportSize
            let hasViewport = viewportSize.width > 0 && viewportSize.height > 0
            let viewportCenter = CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5)
            let canvasCenterX = hasViewport
                ? (viewportCenter.x - canvasViewportPan.width) / zoom
                : canvasWidth * 0.5
            let canvasCenterY = hasViewport
                ? (viewportCenter.y - canvasViewportPan.height) / zoom
                : canvasHeight * 0.5

            let startX = min(max(canvasCenterX - defaultTileSize.width * 0.5, 0), max(0, canvasWidth - defaultTileSize.width))
            let startY = min(max(canvasCenterY - defaultTileSize.height * 0.5, 0), max(0, canvasHeight - defaultTileSize.height))
            
            var foundOffset = CGSize(width: startX, height: startY)
            
            // Try a bounded number of positions to avoid any accidental infinite loops.
            let stepX = defaultTileSize.width + spacing
            let stepY = defaultTileSize.height + spacing
            let maxRows = Int(ceil(canvasHeight / stepY))
            let maxCols = Int(ceil(canvasWidth / stepX))
            let maxRing = max(maxRows, maxCols)

            outerLoop: for ring in 0...maxRing {
                for dy in -ring...ring {
                    for dx in -ring...ring {
                        if abs(dx) != ring && abs(dy) != ring { continue }
                        let candidateOffset = CGSize(
                            width: startX + CGFloat(dx) * stepX,
                            height: startY + CGFloat(dy) * stepY
                        )

                        // Clamp within the canvas.
                        let clampedX = min(max(candidateOffset.width, 0), max(0, canvasWidth - defaultTileSize.width))
                        let clampedY = min(max(candidateOffset.height, 0), max(0, canvasHeight - defaultTileSize.height))
                        let finalOffset = CGSize(width: clampedX, height: clampedY)
                        let candidateRect = rectFor(offset: finalOffset, size: defaultTileSize)

                        // Does this candidate intersect any existing tile?
                        let intersectsExisting = existingRects.contains { $0.intersects(candidateRect) }
                        if !intersectsExisting {
                            foundOffset = finalOffset
                            break outerLoop
                        }
                    }
                }
            }
            
            let new = DashboardTileModel(
                kind: .empty,
                modules: nil,
                offset: foundOffset,
                showsTitle: false
            )
            
            tabs[selectedTabIndex].tiles.append(new)
            selectedTileIDs = [new.id]
            editingTileID = new.id
            isInspectorVisible = true
            if openModuleCatalog {
                pendingModuleCatalogTileID = new.id
            }
            focusTileForInspector(tileID: new.id)
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        private func addTab() {
            guard subscriptionManager.hasPro else {
                showingProUpgrade = true
                return
            }
            pushUndoSnapshot("Add Tab")
            let newIndex = tabs.count + 1
            let newTab = DashboardTab(
                name: "Tab \(newIndex)",
                tiles: [],
                attachedRosterIDs: sharedRosters.map(\.id)
            )
            tabs.append(newTab)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.10)) {
                selectedTabIndex = tabs.count - 1
            }
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }
        
        private func deleteTab(at index: Int) {
            guard tabs.indices.contains(index) else { return }
            // Don't allow deleting the last remaining tab
            guard tabs.count > 1 else { return }

            // Clear sync join state so the host's tab reappears in discovery after removal.
            if let groupID = tabs[index].syncGroupID {
                lanService.clearGroupJoinState(groupID)
                lastSyncedContentHashByGroupID.removeValue(forKey: groupID)
                localEditCountsByGroupID.removeValue(forKey: groupID)
            }

            pushUndoSnapshot("Delete Tab")

            // Adjust renaming index if needed
            if let currentRenaming = renamingTabIndex {
                if currentRenaming == index {
                    renamingTabIndex = nil
                } else if currentRenaming > index {
                    renamingTabIndex = currentRenaming - 1
                }
            }

            tabs.remove(at: index)
            
            // Fix up selected index if needed
            if selectedTabIndex >= tabs.count {
                selectedTabIndex = max(0, tabs.count - 1)
            }
            
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        /// Promotes the tab at `index` to a Synced Tab: generates a new `syncGroupID` and
        /// initial LWW version. The existing tab-change pipeline (Task 9) then advertises
        /// and pushes it to LAN peers.
        private func makeSyncedTab(at index: Int) {
            guard tabs.indices.contains(index) else { return }
            guard subscriptionManager.hasPro else {
                showingProUpgrade = true
                return
            }
            guard tabs[index].syncGroupID == nil else { return }
            guard tabs[index].lanMirrorShareId == nil else { return }

            pushUndoSnapshot("Make Synced Tab")

            var updatedTab = tabs[index]
            updatedTab.syncGroupID = UUID().uuidString
            updatedTab.syncIsOwner = true
            updatedTab.syncOwnerDeviceID = lanService.localDeviceID
            updatedTab.syncOwnerDeviceName = lanService.localDeviceName
            updatedTab.syncRevision = 1
            updatedTab.syncLastEditedAt = Date().timeIntervalSince1970
            updatedTab.syncLastEditedByDeviceID = lanService.localDeviceID
            updatedTab.syncLastEditedByDeviceName = lanService.localDeviceName
            tabs[index] = updatedTab

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }

        /// Removes this device's local copy from its sync group. Other devices' copies are
        /// unaffected — this tab becomes a normal local tab with its current content.
        private func stopSyncingTab(at index: Int) {
            guard tabs.indices.contains(index) else { return }
            guard let groupID = tabs[index].syncGroupID else { return }

            pushUndoSnapshot("Stop Syncing")

            // Push stop signal to peers before clearing local state.
            Task {
                await lanService.pushSyncStop(groupID: groupID)
            }

            var updatedTab = tabs[index]
            updatedTab.syncGroupID = nil
            updatedTab.syncIsOwner = false
            updatedTab.syncOwnerDeviceID = nil
            updatedTab.syncOwnerDeviceName = ""
            updatedTab.syncRevision = 0
            updatedTab.syncLastEditedAt = 0
            updatedTab.syncLastEditedByDeviceID = ""
            updatedTab.syncLastEditedByDeviceName = ""
            tabs[index] = updatedTab
            lastSyncedContentHashByGroupID.removeValue(forKey: groupID)
            localEditCountsByGroupID.removeValue(forKey: groupID)
            lanService.clearGroupJoinState(groupID)
            lanService.clearFileRegistry()

            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
            updateSyncedTabs()
        }


        /// Strips syncGroupID from the tab so it becomes a plain local tab; clears orphan state.
        /// Re-fetches the host's latest snapshot and force-applies it, clearing the orphaned state.
        private func reconnectSyncedTab(groupID: String) {
            lanService.clearOrphanState(for: groupID)
            Task { @MainActor in
                guard let snapshot = await lanService.fetchSyncedTabSnapshot(groupID: groupID) else { return }
                forceApplyHostSnapshot(snapshot)
            }
        }

        private func keepOrphanedTabAsLocal(groupID: String) {
            guard let index = tabs.firstIndex(where: { $0.syncGroupID == groupID }) else { return }
            var updatedTab = tabs[index]
            updatedTab.syncGroupID = nil
            updatedTab.syncIsOwner = false
            updatedTab.syncOwnerDeviceID = nil
            updatedTab.syncRevision = 0
            updatedTab.syncLastEditedAt = 0
            updatedTab.syncLastEditedByDeviceID = ""
            updatedTab.syncLastEditedByDeviceName = ""
            tabs[index] = updatedTab
            lastSyncedContentHashByGroupID.removeValue(forKey: groupID)
            localEditCountsByGroupID.removeValue(forKey: groupID)
            lanService.clearGroupJoinState(groupID)
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
            updateSyncedTabs()
        }

        /// Removes the orphaned tab entirely; clears orphan state.
        private func autoRemoveOrphanedTab(groupID: String) {
            guard let index = tabs.firstIndex(where: { $0.syncGroupID == groupID }) else { return }
            lanService.clearGroupJoinState(groupID)
            localEditCountsByGroupID.removeValue(forKey: groupID)
            lastSyncedContentHashByGroupID.removeValue(forKey: groupID)
            tabs.remove(at: index)
            if selectedTabIndex >= tabs.count {
                selectedTabIndex = max(0, tabs.count - 1)
            }
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
            updateSyncedTabs()
        }

        /// Joins a discovered synced tab: fetches its current snapshot from the owning peer,
        /// adds it as a new local tab carrying the same `syncGroupID`, and switches to it.
        private func joinSyncedTab(_ manifest: SyncedTabManifest) {
            guard subscriptionManager.hasPro else {
                showingProUpgrade = true
                return
            }

            // If we already hold this group (orphaned), reconnect instead of creating a duplicate.
            if lanService.joinedSyncGroupIDs.contains(manifest.groupID) {
                reconnectSyncedTab(groupID: manifest.groupID)
                return
            }

            Task { @MainActor in
                guard let snapshot = await lanService.fetchSyncedTabSnapshot(groupID: manifest.groupID) else { return }
                guard var newTab = try? JSONDecoder().decode(DashboardTab.self, from: snapshot.exportedTabJSON) else { return }

                pushUndoSnapshot("Join Synced Tab")

                newTab.id = UUID()
                newTab.lanMirrorShareId = nil
                newTab.syncIsOwner = false
                newTab.syncOwnerDeviceID = manifest.deviceID
                newTab.syncOwnerDeviceName = manifest.deviceName

                if let joinedGroupID = newTab.syncGroupID {
                    lanService.markGroupAsJoined(joinedGroupID)
                }
                tabs.append(newTab)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.10)) {
                    selectedTabIndex = tabs.count - 1
                }
                saveState.hasUnsavedChanges = true
                scheduleTabsSaveDebounced()
            }
        }

        private func duplicateTab(at index: Int) {
            guard tabs.indices.contains(index) else { return }
            guard subscriptionManager.hasPro else {
                showingProUpgrade = true
                return
            }
            
            // Capture state before duplicating a tab
            pushUndoSnapshot("Duplicate Tab")
            
            let sourceTab = tabs[index]
            
            // Deep-copy tiles so the duplicated tab does not share tile or module IDs
            var duplicatedTiles: [DashboardTileModel] = []
            var tileIdMap: [UUID: UUID] = [:]
            for tile in sourceTab.tiles {
                let newId = UUID()
                let duplicatedTile = duplicatedTile(from: tile, id: newId)
                
                tileIdMap[tile.id] = newId
                duplicatedTiles.append(duplicatedTile)
            }
            
            // Generate a unique name for the duplicated tab
            let baseName = sourceTab.name.isEmpty ? "Dashboard" : sourceTab.name
            let existingNames = Set(tabs.map { $0.name })
            
            var candidate = baseName + " Copy"
            var copyIndex = 2
            while existingNames.contains(candidate) {
                candidate = baseName + " Copy \(copyIndex)"
                copyIndex += 1
            }
            
            // Start from the original tab to preserve any extra properties,
            // then override the name and tiles for the duplicate.
            var newTab = sourceTab
            newTab.id = UUID()
            newTab.name = candidate
            newTab.tiles = duplicatedTiles

            if var graph = newTab.graph {
                graph.id = UUID()

                var moduleGroupIdMap: [UUID: UUID] = [:]
                if !graph.moduleGroupNodeInstances.isEmpty {
                    graph.moduleGroupNodeInstances = graph.moduleGroupNodeInstances.map { instance in
                        var updated = instance
                        let newId = UUID()
                        moduleGroupIdMap[instance.id] = newId
                        updated.id = newId
                        return updated
                    }
                }

                func remapNodeKeyed<T>(_ dict: [String: T]) -> [String: T] {
                    guard !moduleGroupIdMap.isEmpty else { return dict }
                    var remapped: [String: T] = [:]
                    remapped.reserveCapacity(dict.count)
                    for (key, value) in dict {
                        if let oldId = UUID(uuidString: key), let newId = moduleGroupIdMap[oldId] {
                            remapped[newId.uuidString] = value
                        } else {
                            remapped[key] = value
                        }
                    }
                    return remapped
                }

                if !graph.peopleSourceByNodeId.isEmpty {
                    graph.peopleSourceByNodeId = remapNodeKeyed(graph.peopleSourceByNodeId)
                }
                if !graph.peopleTeamFiltersByNodeId.isEmpty {
                    graph.peopleTeamFiltersByNodeId = remapNodeKeyed(graph.peopleTeamFiltersByNodeId)
                }
                if !graph.customPeopleByNodeId.isEmpty {
                    graph.customPeopleByNodeId = remapNodeKeyed(graph.customPeopleByNodeId)
                }
                if !graph.oscReceiveConfigByNodeId.isEmpty {
                    graph.oscReceiveConfigByNodeId = remapNodeKeyed(graph.oscReceiveConfigByNodeId)
                }
                if !graph.midiReceiveConfigByNodeId.isEmpty {
                    graph.midiReceiveConfigByNodeId = remapNodeKeyed(graph.midiReceiveConfigByNodeId)
                }
                if !graph.timeTriggerConfigByNodeId.isEmpty {
                    graph.timeTriggerConfigByNodeId = remapNodeKeyed(graph.timeTriggerConfigByNodeId)
                }
                if !graph.dbThresholdConfigByNodeId.isEmpty {
                    graph.dbThresholdConfigByNodeId = remapNodeKeyed(graph.dbThresholdConfigByNodeId)
                }
                if !graph.shureTriggerConfigByNodeId.isEmpty {
                    graph.shureTriggerConfigByNodeId = remapNodeKeyed(graph.shureTriggerConfigByNodeId)
                }
                if !graph.sennheiserTriggerConfigByNodeId.isEmpty {
                    graph.sennheiserTriggerConfigByNodeId = remapNodeKeyed(graph.sennheiserTriggerConfigByNodeId)
                }
                if !graph.wordTriggerConfigByNodeId.isEmpty {
                    graph.wordTriggerConfigByNodeId = remapNodeKeyed(graph.wordTriggerConfigByNodeId)
                }
                if !graph.pcoItemChangedConfigByNodeId.isEmpty   { graph.pcoItemChangedConfigByNodeId   = remapNodeKeyed(graph.pcoItemChangedConfigByNodeId) }
                if !graph.appStateTriggerConfigByNodeId.isEmpty  { graph.appStateTriggerConfigByNodeId  = remapNodeKeyed(graph.appStateTriggerConfigByNodeId) }
                if !graph.httpRequestActionConfigByNodeId.isEmpty { graph.httpRequestActionConfigByNodeId = remapNodeKeyed(graph.httpRequestActionConfigByNodeId) }
                if !graph.setVariableActionConfigByNodeId.isEmpty { graph.setVariableActionConfigByNodeId = remapNodeKeyed(graph.setVariableActionConfigByNodeId) }
                if !graph.toggleNodeConfigByNodeId.isEmpty       { graph.toggleNodeConfigByNodeId       = remapNodeKeyed(graph.toggleNodeConfigByNodeId) }
                if !graph.counterNodeConfigByNodeId.isEmpty      { graph.counterNodeConfigByNodeId      = remapNodeKeyed(graph.counterNodeConfigByNodeId) }
                if !graph.sequenceNodeConfigByNodeId.isEmpty     { graph.sequenceNodeConfigByNodeId     = remapNodeKeyed(graph.sequenceNodeConfigByNodeId) }
                if !graph.latchNodeConfigByNodeId.isEmpty        { graph.latchNodeConfigByNodeId        = remapNodeKeyed(graph.latchNodeConfigByNodeId) }
                if !graph.currentTimeSourceConfigByNodeId.isEmpty { graph.currentTimeSourceConfigByNodeId = remapNodeKeyed(graph.currentTimeSourceConfigByNodeId) }
                if !graph.sendAllConsolesActionConfigByNodeId.isEmpty {
                    graph.sendAllConsolesActionConfigByNodeId = remapNodeKeyed(graph.sendAllConsolesActionConfigByNodeId)
                }
                if !graph.oscSendActionConfigByNodeId.isEmpty {
                    graph.oscSendActionConfigByNodeId = remapNodeKeyed(graph.oscSendActionConfigByNodeId)
                }
                if !graph.notifyActionConfigByNodeId.isEmpty {
                    graph.notifyActionConfigByNodeId = remapNodeKeyed(graph.notifyActionConfigByNodeId)
                }
                if !graph.midiSendActionConfigByNodeId.isEmpty {
                    graph.midiSendActionConfigByNodeId = remapNodeKeyed(graph.midiSendActionConfigByNodeId)
                }
                if !graph.repeaterActionConfigByNodeId.isEmpty {
                    graph.repeaterActionConfigByNodeId = remapNodeKeyed(graph.repeaterActionConfigByNodeId)
                }

                if !graph.nodeIdByPortId.isEmpty {
                    var remappedNodeIds: [String: UUID] = [:]
                    remappedNodeIds.reserveCapacity(graph.nodeIdByPortId.count)
                    for (portId, nodeId) in graph.nodeIdByPortId {
                        let updatedNodeId = moduleGroupIdMap[nodeId] ?? tileIdMap[nodeId] ?? nodeId
                        var updatedPortId = portId
                        if portId.hasPrefix("node:"),
                           let oldNode = UUID(uuidString: String(portId.dropFirst("node:".count))),
                           let newNode = moduleGroupIdMap[oldNode] {
                            updatedPortId = "node:\(newNode.uuidString)"
                        }
                        remappedNodeIds[updatedPortId] = updatedNodeId
                    }
                    graph.nodeIdByPortId = remappedNodeIds
                }

                if !graph.tileLayouts.isEmpty {
                    var remappedLayouts: [UUID: TileGraphLayout] = [:]
                    remappedLayouts.reserveCapacity(graph.tileLayouts.count)
                    for (oldId, layout) in graph.tileLayouts {
                        if let newId = tileIdMap[oldId] {
                            remappedLayouts[newId] = layout
                        }
                    }
                    graph.tileLayouts = remappedLayouts
                }

                if !graph.links.isEmpty {
                    graph.links = graph.links.compactMap { link in
                        guard let newFrom = tileIdMap[link.fromTileId],
                              let newTo = tileIdMap[link.toTileId] else {
                            return nil
                        }
                        var updated = link
                        updated.fromTileId = newFrom
                        updated.toTileId = newTo
                        return updated
                    }
                }

                if !graph.nodeIdByPortId.isEmpty {
                    var remappedNodeIds: [String: UUID] = [:]
                    remappedNodeIds.reserveCapacity(graph.nodeIdByPortId.count)
                    for (portId, nodeId) in graph.nodeIdByPortId {
                        remappedNodeIds[portId] = tileIdMap[nodeId] ?? nodeId
                    }
                    graph.nodeIdByPortId = remappedNodeIds
                }

                newTab.graph = graph
            }

            if !newTab.tileGroups.isEmpty {
                var remapped: [DashboardTileGroup] = []
                remapped.reserveCapacity(newTab.tileGroups.count)
                for group in newTab.tileGroups {
                    let mappedIds = group.tileIds.compactMap { tileIdMap[$0] }
                    if mappedIds.isEmpty { continue }
                    var updated = group
                    updated.tileIds = mappedIds
                    remapped.append(updated)
                }
                newTab.tileGroups = remapped
            }
            
            // Insert the duplicated tab immediately after the source tab
            tabs.insert(newTab, at: index + 1)
            selectedTabIndex = index + 1
            
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }
        
        // MARK: - Persistence Helpers
    private func applyDeviceFitScaleIfNeeded() {
        guard !didApplyImportDeviceFitScale else { return }
        guard let ref = pendingImportReferenceCanvasSize else { return }
        guard ref.width > 20, ref.height > 20 else { return }
        guard canvasSize.width > 20, canvasSize.height > 20 else { return }

        let sx = canvasSize.width / ref.width
        let sy = canvasSize.height / ref.height
        let scale = min(sx, sy)

        // If the imported reference is basically the same size, mark done and bail.
        if abs(scale - 1.0) < 0.01 {
            didApplyImportDeviceFitScale = true
            pendingImportReferenceCanvasSize = nil
            pendingImportScaleTabIDs = nil
            return
        }

        // ✅ Option B: scale only specific tab IDs (typically just the newly imported LAN tab)
        let scaleOnlyTabIDs = pendingImportScaleTabIDs

        // ✅ 1) SCALE TILES
        for tabIndex in tabs.indices {
            // If we're scoping the scale, skip any tabs not in the set
            if let ids = scaleOnlyTabIDs, !ids.contains(tabs[tabIndex].id) {
                continue
            }

            for tileIndex in tabs[tabIndex].tiles.indices {
                tabs[tabIndex].tiles[tileIndex].offset = CGSize(
                    width: tabs[tabIndex].tiles[tileIndex].offset.width * scale,
                    height: tabs[tabIndex].tiles[tileIndex].offset.height * scale
                )

                if let s = tabs[tabIndex].tiles[tileIndex].size {
                    tabs[tabIndex].tiles[tileIndex].size = CGSize(
                        width: s.width * scale,
                        height: s.height * scale
                    )
                }
            }
        }

        // ✅ 2) SCALE GUIDES
        // Only scale guides when we are scaling "everything" (file-open import).
        // For Option B (new tab only), guides should NOT move.
        if scaleOnlyTabIDs == nil {
            for tabIndex in tabs.indices {
                for i in tabs[tabIndex].guides.indices {
                    tabs[tabIndex].guides[i].position *= scale
                }

                // ✅ 3) CLAMP GUIDES TO NEW CANVAS
                for i in tabs[tabIndex].guides.indices {
                    switch tabs[tabIndex].guides[i].orientation {
                    case .vertical:
                        tabs[tabIndex].guides[i].position = min(
                            max(tabs[tabIndex].guides[i].position, 0),
                            canvasSize.width
                        )
                    case .horizontal:
                        tabs[tabIndex].guides[i].position = min(
                            max(tabs[tabIndex].guides[i].position, 0),
                            canvasSize.height
                        )
                    }
                }
            }
        }

        didApplyImportDeviceFitScale = true
        pendingImportReferenceCanvasSize = nil
        pendingImportScaleTabIDs = nil
    }
    // MARK: - Persistence Helpers

    private func currentDashboardPayload() -> DashboardDocument.Payload {
        DashboardDocument.Payload(
            version: 5,
            tabs: tabs,
            rosters: sharedRosters,
            selectedTabIndex: selectedTabIndex,
            externalDevices: ExternalDevicesStore.shared.currentSnapshot(),
            settings: captureSettingsSnapshot(),
            canvasGuides: selectedTabGuides,
            referenceCanvasSize: canvasSize,
            universalGraph: universalGraph
        )
    }

    private func persistWorkingDocumentURL(_ url: URL) {
        _ = url
    }

    private func clearPersistedWorkingDocumentURL() {}

    /// Ensures LANSharedTabsService.joinedSyncGroupIDs stays consistent with what `tabs` actually
    /// contains. Idempotent, safe to call on every `tabs` change (document load, import, undo/redo).
    ///
    /// A subscriber tab's "linked" icon is driven purely by the DashboardTab model
    /// (syncGroupID/syncIsOwner) — it renders correctly the instant such a tab enters `tabs`,
    /// regardless of how it got there. But polling, orphan-detection, and reconnect all key off
    /// LANSharedTabsService.joinedSyncGroupIDs, which is a separate piece of state that has to be
    /// explicitly populated. If a subscriber tab's groupID is missing from joinedSyncGroupIDs —
    /// e.g. because the working document loaded asynchronously after the one-shot restore hook
    /// already ran — the tab looks linked but is completely inert: no reconnect attempt is ever
    /// made, and it will never go stale/orphaned either, since the poll loop only evaluates
    /// groupIDs already in joinedSyncGroupIDs.
    private func reconcileJoinedSyncGroupIDs() {
        for tab in tabs where tab.syncGroupID != nil && !tab.syncIsOwner {
            guard let gid = tab.syncGroupID, !lanService.joinedSyncGroupIDs.contains(gid) else { continue }
            lanService.markGroupAsRestoredJoined(gid)
        }
    }

    private func applyRestoredDocumentStateIfNeeded() {
        guard !didApplyRestoredDocumentState else { return }
        didApplyRestoredDocumentState = true
        resetLiveModeForDocumentTransition()

        // Note: joinedSyncGroupIDs re-population for subscriber tabs happens in
        // reconcileJoinedSyncGroupIDs() (called from .onChange(of: tabs)) rather than here.
        // The working document actually loads asynchronously via documentController.pendingRequest,
        // which is not guaranteed to have completed by the time this one-shot .onAppear-driven
        // function runs — doing it here raced tabs being replaced by the real document content,
        // silently leaving a subscriber tab showing the "linked" icon with no corresponding
        // LANSharedTabsService join record, so it could never reconnect, orphan, or refresh.

        if let lastSavedURL {
            saveState.currentFileName = lastSavedURL.deletingPathExtension().lastPathComponent
        }

        if let restoredCanvasSizeFromDocument {
            canvasBoundsStore.size = restoredCanvasSizeFromDocument
        }

        // Show banner if a bookmark was stored but the working document didn't restore.
        let bookmarkKey = Self.workingDocumentBookmarkKey
        let hadStoredBookmark = UserDefaults.standard.data(forKey: bookmarkKey) != nil
        if hadStoredBookmark && lastSavedURL == nil {
            showingBookmarkRestoreFailedBanner = true
        }
    }

    private func showAutosaveAnnouncementIfNeeded() {
        guard !autosaveAnnouncementShown else { return }
        autosaveAnnouncementShown = true
        // Delay lets any dismissing sheet (home screen) finish before we present.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showingAutosaveAnnouncement = true
        }
    }

    private func showCanvasTutorialIfNeeded() {
        guard !tutorialSeen else { return }
        let hasPro = subscriptionManager.hasPro
        let kind: DashboardTutorialKind = hasPro ? .proCanvas : .freeCanvas
        tutorialSeen = true
        // Delay lets any dismissing sheet (home screen) finish before we present.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            tutorialController.start(kind: kind, hasPro: hasPro)
        }
    }

    private func cancelPendingDashboardPersistence() {
        pendingTabsSaveWorkItem?.cancel()
        pendingTabsSaveWorkItem = nil
    }

    private func beginReplacingDocumentState() {
        cancelPendingDashboardPersistence()
        isReplacingDocumentState = true
        suppressUnsavedChangesUntil = Date().addingTimeInterval(0.5)
    }

    private func endReplacingDocumentState() {
        DispatchQueue.main.async {
            self.isReplacingDocumentState = false
        }
    }

    private var shouldAutoSaveWithoutPrompt: Bool {
        fileAutosaveEnabled && lastSavedURL != nil
    }

    private func autosaveWorkingDocumentIfNeeded(
        payload: DashboardDocument.Payload? = nil,
        expectedEditGeneration: Int? = nil
    ) {
        guard
            fileAutosaveEnabled,
            !isDocumentWriteInProgress,
            saveState.hasUnsavedChanges,
            let url = lastSavedURL
        else { return }

        let payloadToWrite = payload ?? currentDashboardPayload()
        let generationToComplete = expectedEditGeneration ?? autosaveEditGeneration

        DispatchQueue.global(qos: .utility).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try JSONEncoder().encode(payloadToWrite)
                try data.write(to: url, options: .atomic)

                DispatchQueue.main.async {
                    self.applyAutosaveCompletion(for: url, expectedEditGeneration: generationToComplete)
                }
            } catch {
                print("[Dashboard] Autosave failed for \(url.path): \(error)")
                DispatchQueue.main.async {
                    self.presentNotification(
                        title: "Autosave Failed",
                        message: "Your changes haven't been saved to disk.",
                        durationSeconds: 7
                    )
                }
            }
        }
    }

    private func applyAutosaveCompletion(for url: URL, expectedEditGeneration: Int) {
        persistWorkingDocumentURL(url)

        guard autosaveEditGeneration == expectedEditGeneration else {
            return
        }

        lastSavedURL = url
        saveState.currentFileURL = url
        saveState.currentFileName = url.deletingPathExtension().lastPathComponent
        saveState.hasAssociatedFile = true
        saveState.hasUnsavedChanges = false
        saveState.isSaving = false
        saveState.lastSavedAt = Date()
        saveThumbnail(for: url)
    }

    private func saveThumbnail(for url: URL) {
        guard tabs.indices.contains(selectedTabIndex) else { return }
        let tab = tabs[selectedTabIndex]
        let size = canvasSize
        guard let thumbURL = Self.thumbnailCacheURL(for: url) else { return }
        if let data = renderTabImageData(tab: tab, canvasSize: size, scale: 0.2) {
            DispatchQueue.global(qos: .utility).async {
                try? data.write(to: thumbURL)
            }
        }
    }

    /// Returns the cache URL for a document's thumbnail, stored in ~/Library/Caches/Relay/thumbnails/.
    /// Keyed by SHA256 of the document path so thumbnails never appear next to user files.
    static func thumbnailCacheURL(for documentURL: URL) -> URL? {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let thumbDir = cachesDir.appendingPathComponent("Relay/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        let hash = SHA256.hash(data: Data(documentURL.path.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return thumbDir.appendingPathComponent("\(hashString).jpg")
    }

    private func handleDocumentControllerRequest(_ request: DashboardDocumentController.Request) {
        defer { documentController.consumeRequest(request) }

        switch request.action {
        case .save:
            saveCurrentDocument()
        case .saveAs:
            saveCurrentDocumentAs()
        case .openPicker:
            requestOpenDocumentPicker()
        case .newDashboard:
            requestNewDashboard()
        case .quitApplication:
            requestQuitApplication()
        case .openSpecific(let url):
            requestOpenSpecificDocument(url)
        }
    }

    private func requestOpenDocumentPicker() {
        if saveState.hasUnsavedChanges && !isDefaultBlankDocument {
            pendingDocumentContinuation = .openPicker
            showingOpenUnsavedAlert = true
        } else {
            isImportingDashboard = true
        }
    }

    private func requestOpenSpecificDocument(_ url: URL) {
        if saveState.hasUnsavedChanges && !isDefaultBlankDocument {
            pendingDocumentContinuation = .openSpecific(url)
            showingOpenUnsavedAlert = true
        } else {
            importDashboard(from: url)
        }
    }

    /// True when the document is still the auto-generated blank state —
    /// one tab with no user-added tiles (or an empty canvas with no associated file).
    /// In this state, opening a file should never prompt to save.
    private var isDefaultBlankDocument: Bool {
        guard !saveState.hasAssociatedFile else { return false }
        // Blank if there's exactly one tab containing only auto-placed empty tiles
        // (the default "Tab 1" the app creates on fresh launch).
        if tabs.count == 1 {
            let tile = tabs[0].tiles
            return tile.isEmpty || tile.allSatisfy { $0.kind == .empty && ($0.modules?.isEmpty ?? true) }
        }
        return false
    }

    private func requestNewDashboard() {
        if saveState.hasUnsavedChanges {
            pendingDocumentContinuation = .newDashboard
            isShowingNewDashboardAlert = true
        } else {
            presentCanvasSizePrompt(.newDashboard)
        }
    }

    /// True if any modal sheet is currently on screen that would prevent a SwiftUI
    /// `.alert()` from being displayed (macOS cannot stack an alert on top of an
    /// active sheet). Must be dismissed before showing the Quit/Close-Window
    /// save-changes prompt.
    private var hasBlockingModalPresented: Bool {
        showingProUpgrade || showingProUpgradePrompt || showingPCOConfigForTab ||
        showingRosters || showingSettings || showingKeyboardShortcuts ||
        showExternalDevicesSettingsSheet || isShowingNewDashboardSizePrompt ||
        showingTileGroupSheet || showingAutosaveAnnouncement ||
        subscriptionManager.isShowingAppStoreAccountLinkSheet ||
        DashboardHomeScreenState.shared.isPresented
    }

    private func dismissBlockingModalsForTermination() {
        showingProUpgrade = false
        showingProUpgradePrompt = false
        showingPCOConfigForTab = false
        showingRosters = false
        showingSettings = false
        showingKeyboardShortcuts = false
        showExternalDevicesSettingsSheet = false
        isShowingNewDashboardSizePrompt = false
        showingTileGroupSheet = false
        showingAutosaveAnnouncement = false
        subscriptionManager.isShowingAppStoreAccountLinkSheet = false
        // The home/launch screen isn't local @State — it's owned by RelayDashboardApp —
        // so it's dismissed indirectly via notification rather than direct assignment.
        NotificationCenter.default.post(name: .dashboardDismissBlockingModalsRequested, object: nil)
    }

    private func requestCloseWindow() {
        if hasBlockingModalPresented {
            dismissBlockingModalsForTermination()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.requestCloseWindow()
            }
            return
        }
        if shouldAutoSaveWithoutPrompt {
            pendingDocumentContinuation = .closeWindow
            saveCurrentDocument()
        } else if saveState.hasUnsavedChanges && !isDefaultBlankDocument {
            pendingDocumentContinuation = .closeWindow
            showingCloseUnsavedAlert = true
        } else {
            windowCloseCoordinator.continuePendingClose()
        }
    }

    private func requestQuitApplication() {
        if hasBlockingModalPresented {
            dismissBlockingModalsForTermination()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.requestQuitApplication()
            }
            return
        }
        if shouldAutoSaveWithoutPrompt {
            pendingDocumentContinuation = .quitApplication
            saveCurrentDocument()
        } else if saveState.hasUnsavedChanges && !isDefaultBlankDocument {
            pendingDocumentContinuation = .quitApplication
            showingQuitUnsavedAlert = true
        } else {
#if os(macOS)
            AppTerminationCoordinator.shared.continueTermination()
#endif
        }
    }

    private func saveCurrentDocument() {
#if os(macOS)
        guard beginManualDocumentWrite() else { return }
        let payload = currentDashboardPayload()
        if let url = lastSavedURL {
            writeDashboardPayload(payload, to: url) { success in
                if success {
                    print("✅ Quick-save dashboard to \(url.path)")
                    handleDocumentSaveCompletion(success: true, savedURL: url)
                } else {
                    print("❌ Quick save failed for \(url.path). Falling back to Save As…")
                    presentSavePanel(payload: payload)
                }
            }
        } else {
            presentSavePanel(payload: payload)
        }
#else
        // iOS: if we already have a saved URL, write directly (no share sheet).
        if let url = lastSavedURL {
            guard beginManualDocumentWrite() else { return }
            let payload = currentDashboardPayload()
            writeDashboardPayload(payload, to: url) { success in
                if success {
                    self.handleDocumentSaveCompletion(success: true, savedURL: url)
                } else {
                    // Fall back to share sheet on write failure.
                    self.presentIOSDashboardExporter()
                }
            }
        } else {
            // No saved URL yet — present share sheet (same as saveAs).
            presentIOSDashboardExporter()
        }
#endif
    }

    private func saveCurrentDocumentAs() {
#if os(macOS)
        guard beginManualDocumentWrite() else { return }
        presentSavePanel(payload: currentDashboardPayload())
#else
        presentIOSDashboardExporter()
#endif
    }

#if os(iOS)
    private func makeDashboardDocumentForExport() -> DashboardDocument {
        DashboardDocument(
            tabs: tabs,
            rosters: sharedRosters,
            selectedTabIndex: selectedTabIndex,
            externalDevices: ExternalDevicesStore.shared.currentSnapshot(),
            settings: captureSettingsSnapshot(),
            canvasGuides: selectedTabGuides,
            referenceCanvasSize: canvasSize,
            universalGraph: universalGraph
        )
    }

    private func presentIOSDashboardExporter() {
        dashboardDocument = makeDashboardDocumentForExport()

        Task { @MainActor in
            await Task.yield()
            isExportingDashboard = true
            presentNotification(
                title: "Choose Where to Save",
                message: "Select a location in Files to save this dashboard.",
                durationSeconds: 2.0
            )
        }
    }
#endif

    private func beginManualDocumentWrite() -> Bool {
        guard !isDocumentWriteInProgress else { return false }
        isDocumentWriteInProgress = true
        return true
    }

    private func endManualDocumentWrite() {
        isDocumentWriteInProgress = false
    }

    private func handleDocumentSaveCompletion(success: Bool, savedURL: URL?) {
        endManualDocumentWrite()

        if success, let savedURL {
            ExternalDevicesStore.shared.savePersistentState()
            lastSavedURL = savedURL
            persistWorkingDocumentURL(savedURL)
            DashboardRecentDocumentsStore.shared.noteDocumentURL(savedURL)
            saveState.currentFileURL = savedURL
            saveState.currentFileName = savedURL.deletingPathExtension().lastPathComponent
            saveState.hasAssociatedFile = true
            saveState.hasUnsavedChanges = false
            saveState.hasRealDocument = true
            saveState.isSaving = false
            saveState.lastSavedAt = Date()
            saveThumbnail(for: savedURL)
            continuePendingDocumentContinuationAfterSave()
        } else {
            saveState.isSaving = false
            cancelPendingContinuationAfterFailedSave()
        }
    }

    private func continuePendingDocumentContinuationAfterSave() {
        let continuation = pendingDocumentContinuation
        pendingDocumentContinuation = nil
        continuePendingDocumentContinuation(continuation)
    }

    private func continuePendingDocumentContinuationAfterDiscard() {
        // "Don't Save" means the user is abandoning these changes. Must clear this before
        // continuing: the quit/close bypass paths (Cmd+Q/Cmd+W/close-button monitors) re-invoke
        // applicationShouldTerminate/windowShouldClose fresh rather than just replying to an
        // already-pending one, and those re-checks read this flag again.
        saveState.hasUnsavedChanges = false
        let continuation = pendingDocumentContinuation
        pendingDocumentContinuation = nil
        continuePendingDocumentContinuation(continuation)
    }

    private func cancelPendingContinuationAfterFailedSave() {
        switch pendingDocumentContinuation {
        case .closeWindow:
            windowCloseCoordinator.clearPendingClose()
        case .quitApplication:
#if os(macOS)
            AppTerminationCoordinator.shared.cancelTermination()
#endif
        default:
            break
        }
        pendingDocumentContinuation = nil
    }

    private func continuePendingDocumentContinuation(_ continuation: PendingDocumentContinuation?) {
        switch continuation {
        case .openPicker:
            isImportingDashboard = true
        case .openSpecific(let url):
            importDashboard(from: url)
        case .newDashboard:
            presentCanvasSizePrompt(.newDashboard)
        case .closeWindow:
            windowCloseCoordinator.continuePendingClose()
        case .quitApplication:
#if os(macOS)
            AppTerminationCoordinator.shared.continueTermination()
#endif
        case nil:
            break
        }
    }

    private func writeDashboardPayload(
        _ payload: DashboardDocument.Payload,
        to url: URL,
        completion: @escaping (Bool) -> Void
    ) {
        saveState.isSaving = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try JSONEncoder().encode(payload)
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    completion(true)
                }
            } catch {
                DispatchQueue.main.async {
                    RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Dashboard Export")
                    completion(false)
                }
            }
        }
    }

    private func importDashboard(from url: URL) {
        isLoadingDashboardFile = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let payload = try readDashboardPayload(from: url)
                DispatchQueue.main.async {
                    adoptImportedPayload(payload, from: url)
                    showAutosaveAnnouncementIfNeeded()
                    showCanvasTutorialIfNeeded()
                    print("✅ Dashboard imported successfully")
                    logDashboardSummary(tabs, context: "Import success")
                    isLoadingDashboardFile = false
                }
            } catch let error as DashboardDocumentIOError {
                DispatchQueue.main.async {
                    dashboardFileErrorMessage = error.errorDescription
                    RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Dashboard Import")
                    print("❌ Failed to import dashboard: \(error)")
                    isLoadingDashboardFile = false
                }
            } catch {
                DispatchQueue.main.async {
                    dashboardFileErrorMessage = error.localizedDescription
                    RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Dashboard Import")
                    print("❌ Failed to import dashboard: \(error)")
                    isLoadingDashboardFile = false
                }
            }
        }
    }

    private func readDashboardPayload(from url: URL) throws -> DashboardDocument.Payload {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            throw DashboardDocumentIOError.selectedDirectory
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DashboardDocumentIOError.fileMissing(url)
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(DashboardDocument.Payload.self, from: data)
            guard !payload.tabs.isEmpty else {
                throw DashboardDocumentIOError.invalidPayload("This Relay dashboard file doesn’t contain any tabs.")
            }
            return payload
        } catch let error as DashboardDocumentIOError {
            throw error
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw DashboardDocumentIOError.permissionDenied(url)
        } catch let error as DecodingError {
            throw DashboardDocumentIOError.decodeFailed(url, underlying: error)
        } catch {
            throw DashboardDocumentIOError.readFailed(url, underlying: error)
        }
    }

    private func adoptImportedPayload(_ payload: DashboardDocument.Payload, from url: URL) {
        beginReplacingDocumentState()
        defer { endReplacingDocumentState() }
        resetLiveModeForDocumentTransition()
        #if DEBUG
        logImportedExternalDevices(payload.externalDevices, context: "Open File → decoded payload")
        #endif
        let importedCanvasSize = payload.canvasSize ?? payload.referenceCanvasSize
        if let importedCanvasSize {
            canvasBoundsStore.size = importedCanvasSize
        }
        restoredCanvasSizeFromDocument = importedCanvasSize
        // Canvas size now travels with the document (per-tab canvasSize field).
        // Tile scaling on import is no longer needed — tiles are already in the
        // correct coordinate space for their canvas. Mark as applied immediately
        // so the onChange(of: canvasBoundsStore.size) handler never fires it.
        pendingImportReferenceCanvasSize = nil
        didApplyImportDeviceFitScale = true
        pendingImportScaleTabIDs = nil

        var importedTabs = payload.tabs
        let isPro = subscriptionManager.hasPro
        let hadExtraTabs = importedTabs.count > 1
        let proModuleCount = importedTabs.reduce(0) { partial, tab in
            partial + tab.tiles.reduce(0) { tilePartial, tile in
                tilePartial + (tile.modules?.filter { $0.kind.requiresPro }.count ?? 0)
            }
        }

        if !isPro, importedTabs.count > 1 {
            importedTabs = [importedTabs[0]]
        }

        if !isPro, hadExtraTabs || proModuleCount > 0 {
            if hadExtraTabs && proModuleCount > 0 {
                freeImportWarningMessage = "This dashboard uses Pro features. Free opens only the first tab, and Pro modules are locked until you upgrade."
            } else if hadExtraTabs {
                freeImportWarningMessage = "This dashboard has multiple tabs. Free opens only the first tab. Upgrade to Pro to unlock the rest."
            } else {
                freeImportWarningMessage = "This dashboard includes Pro modules. They are locked until you upgrade."
            }
        }

        let migratedRosters = Self.migrateLegacyRosters(
            tabs: importedTabs,
            rosters: payload.rosters
        )
        let migratedForTranscription = Self.migrateTranscriptionInputs(tabs: migratedRosters.tabs)

        // On file import, strip sync-host state from tabs created by a different device.
        // Uses syncOwnerDeviceID (set at group creation, never changed) to reliably identify
        // foreign host tabs regardless of who last edited the content. Tabs without
        // syncOwnerDeviceID (created before this field was added) are trusted as-is.
        let localDeviceID = lanService.localDeviceID
        let tabsWithCorrectedOwnership = migratedForTranscription.map { tab -> DashboardTab in
            guard tab.syncGroupID != nil,
                  tab.syncIsOwner,
                  let ownerDeviceID = tab.syncOwnerDeviceID,
                  ownerDeviceID != localDeviceID else { return tab }
            var corrected = tab
            corrected.syncGroupID = nil
            corrected.syncIsOwner = false
            corrected.syncOwnerDeviceID = nil
            corrected.syncOwnerDeviceName = ""
            corrected.syncRevision = 0
            corrected.syncLastEditedAt = 0
            corrected.syncLastEditedByDeviceID = ""
            corrected.syncLastEditedByDeviceName = ""
            return corrected
        }
        tabs = tabsWithCorrectedOwnership
        universalGraph = payload.universalGraph
        sharedRosters = migratedRosters.rosters
        if !payload.canvasGuides.isEmpty,
           tabs.indices.contains(payload.selectedTabIndex),
           tabs[payload.selectedTabIndex].guides.isEmpty {
            tabs[payload.selectedTabIndex].guides = payload.canvasGuides
        }
        migrateLegacyTilesToModulesIfNeeded()

        if tabs.isEmpty {
            selectedTabIndex = 0
        } else {
            selectedTabIndex = min(
                max(payload.selectedTabIndex, 0),
                tabs.count - 1
            )
        }

        fitCanvasToViewport()

        let importedSettings = payload.settings
        clearPendingImportedConfiguration()
        if let snapshot = payload.externalDevices {
            ExternalDevicesStore.shared.applySnapshot(snapshot)
            ExternalDevicesStore.shared.savePersistentState()
        }
        if let importedSettings {
            applySettingsSnapshot(importedSettings)
        }

        lastSavedURL = url
        persistWorkingDocumentURL(url)
        DashboardRecentDocumentsStore.shared.noteDocumentURL(url)
        saveState.currentFileURL = url
        saveState.currentFileName = url.deletingPathExtension().lastPathComponent
        saveState.hasAssociatedFile = true
        saveState.hasUnsavedChanges = false
        saveState.hasRealDocument = true
        restoredWorkingDocumentCandidate = nil
        pendingDocumentContinuation = nil
    }

    private func payloadSignature(_ payload: DashboardDocument.Payload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func saveTabs() {
        let payload = currentDashboardPayload()
        let expectedEditGeneration = autosaveEditGeneration
        ExternalDevicesStore.shared.savePersistentState()
        autosaveWorkingDocumentIfNeeded(
            payload: payload,
            expectedEditGeneration: expectedEditGeneration
        )
    }

    /// Reassigns every `DashboardCanvasActionCoordinator` closure on each
    /// render. Cheap (a dozen property writes on an existing object) and
    /// invisible to SwiftUI's view diffing -- unlike passing these as
    /// constructor closures, which would defeat diffing for every tile again.
    private func configureCanvasActions(tabBinding: Binding<DashboardTab>) {
        canvasActions.onExitLiveMode = {
            withAnimation(.easeInOut(duration: 0.25)) {
                isLiveMode = false
            }
        }
        canvasActions.onGroupMoveCommit = { anchorID, translation in
            moveSelectedTiles(anchorID: anchorID, translation: translation)
        }
        canvasActions.onSnapCommit = { anchorID, region in
            applySnapRegion(region, anchorID: anchorID)
        }
        canvasActions.onPushUndoSnapshot = { actionName in
            pushUndoSnapshot(actionName)
        }
        canvasActions.onSaveTabs = { saveTabs() }
        canvasActions.onScheduleTabsSaveDebounced = { reconcileGraphNodes in
            scheduleTabsSaveDebounced(reconcileGraphNodes: reconcileGraphNodes)
        }
        canvasActions.onFocusTileForInspector = { tileID in
            focusTileForInspector(tileID: tileID)
        }
        canvasActions.onSetTab = { newValue in
            guard newValue.id == tabBinding.wrappedValue.id else { return }
            tabBinding.wrappedValue = newValue
        }
        canvasActions.onSetTile = { tabID, tileID, newValue in
            guard DashboardTabIdentityMutation.replaceTile(newValue, tabID: tabID, tileID: tileID, in: &tabs) else {
                // The target tab or tile disappeared between render and write (reorder,
                // delete, or a stale inspector binding). Dropping the write is correct,
                // but it is still lost user input -- make it visible rather than silent.
                RelayDiagnosticsStore.shared.incrementCounter("ui.canvas.setTile.rejected")
                return
            }
        }
        canvasActions.onPrimarySelect = { tileID in
            #if os(macOS)
            let isShiftDown = NSEvent.modifierFlags.contains(.shift)
            #else
            let isShiftDown = false
            #endif

            #if os(macOS)
            if isShiftDown {
                if selectedTileIDs.contains(tileID) {
                    selectedTileIDs.remove(tileID)
                } else {
                    selectedTileIDs.insert(tileID)
                }
            } else {
                selectedTileIDs = [tileID]
            }
            #else
            selectedTileIDs = [tileID]
            #endif

            selectionSource = .canvas
            groupSelectionColor = nil

            if isInspectorVisible {
                if selectedTileIDs.isEmpty {
                    editingTileID = nil
                    isInspectorVisible = false
                } else if let first = selectedTileIDs.first {
                    editingTileID = first
                }
            }
        }
        canvasActions.onContextSelect = { tileID in
            selectedTileIDs = [tileID]
            selectionSource = .canvas
            groupSelectionColor = nil
            if isInspectorVisible {
                editingTileID = tileID
            }
        }
        canvasActions.onDragBegan = { tileID in
            if !selectedTileIDs.contains(tileID) {
                selectedTileIDs = [tileID]
                selectionSource = .canvas
                groupSelectionColor = nil
                if isInspectorVisible {
                    editingTileID = tileID
                }
            }
            pushUndoSnapshot("Move Tiles")
        }
        canvasActions.onDelete = { tileID in
            pushUndoSnapshot("Delete Tile(s)")
            if selectedTileIDs.contains(tileID) {
                tabBinding.wrappedValue.tiles.removeAll { selectedTileIDs.contains($0.id) }
                selectedTileIDs.removeAll()
            } else {
                tabBinding.wrappedValue.tiles.removeAll { $0.id == tileID }
            }
            saveTabs()
        }
        canvasActions.onPersist = { reconcileGraphNodes in
            DashboardSaveState.shared.hasUnsavedChanges = true
            scheduleTabsSaveDebounced(reconcileGraphNodes: reconcileGraphNodes)
        }
        canvasActions.onUndoSnapshot = { title in
            pushUndoSnapshot(title)
        }
        canvasActions.onResizeBegan = {
            pushUndoSnapshot("Resize Tile")
        }
        canvasActions.onEditRequested = { tileID, selectFirstModule in
            guard !isLiveMode else { return }
            let resolvedTileID = (selectedTileIDs.count > 1 && selectedTileIDs.contains(tileID)) ? (selectedTileIDs.first ?? tileID) : tileID
            withAnimation(.easeInOut(duration: 0.25)) {
                editingTileID = resolvedTileID
                isInspectorVisible = true
                focusTileForInspector(tileID: tileID)
            }
            if selectFirstModule {
                pendingFirstModuleSelectTileID = resolvedTileID
            }
        }
        canvasActions.onDraggingTilesChanged = { isDragging in
            guard isDraggingTilesOnCanvas != isDragging else { return }
            isDraggingTilesOnCanvas = isDragging
        }
    }

    /// Computes an effective size for a tile so we can reason about its
    /// position when ensuring it stays visible next to the inspector.
    private func effectiveTileSize(for tile: DashboardTileModel) -> CGSize {
        let minWidth: CGFloat = 44
        let minHeight: CGFloat = 44

        let baseWidth = tile.size?.width ?? defaultTileSize.width
        let width = max(minWidth, baseWidth)

        let baseHeight = tile.size?.height ?? defaultTileSize.height
        let height = max(minHeight, baseHeight)

        return CGSize(width: width, height: height)
    }
    /// Legacy inspector focus behavior (used to shift tiles into view).
    /// With pan/zoom available, we no longer auto-shift tiles.
    private func focusTileForInspector(tileID: UUID) {
        _ = tileID
    }
    /// Schedules a debounced save of the current tabs to persistent storage.
    /// Rapid calls within the debounce window will cancel and reschedule,
    /// so only the latest state gets written.
    private func scheduleTabsSaveDebounced(reconcileGraphNodes: Bool = true) {
        autosaveEditGeneration &+= 1

        // Reconcile auto-mirrored Button trigger nodes when tile/module composition changes.
        // Position-only edits like drag/resize should skip this synchronous work.
        if reconcileGraphNodes {
            for i in tabs.indices {
                tabs[i].reconcileButtonTriggerNodes()
            }
        }

        // Cancel any pending save so we only persist the latest state.
        pendingTabsSaveWorkItem?.cancel()

        let work = DispatchWorkItem {
            saveTabs()
        }

        pendingTabsSaveWorkItem = work

        // Debounce window: tweak if you want faster/slower persistence.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private func clampGuidesToCanvasBounds() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        mutateSelectedTabGuides { guides in
            for i in guides.indices {
                switch guides[i].orientation {
                case .vertical:
                    guides[i].position = min(max(guides[i].position, 0), canvasSize.width)
                case .horizontal:
                    guides[i].position = min(max(guides[i].position, 0), canvasSize.height)
                }
            }
        }
    }

    private func bringAllTilesIntoCanvas() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        pushUndoSnapshot("Bring All Tiles Into Canvas")

        var didChange = false
        for tabIndex in tabs.indices {
            for tileIndex in tabs[tabIndex].tiles.indices {
                var tile = tabs[tabIndex].tiles[tileIndex]
                let size = effectiveTileSize(for: tile)

                let maxX = max(0, canvasSize.width - size.width)
                let maxY = max(0, canvasSize.height - size.height)

                let clampedX = min(max(tile.offset.width, 0), maxX)
                let clampedY = min(max(tile.offset.height, 0), maxY)

                if abs(clampedX - tile.offset.width) > 0.0001 || abs(clampedY - tile.offset.height) > 0.0001 {
                    tile.offset = CGSize(width: clampedX, height: clampedY)
                    tabs[tabIndex].tiles[tileIndex] = tile
                    didChange = true
                }
            }
        }

        if didChange {
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        }
    }

#if os(macOS)
    private func updateEscapeKeyMonitor(isActive: Bool) {
        if isActive {
            if escapeKeyMonitor == nil {
                escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53 {
                        tutorialController.stop()
                        return nil
                    }
                    return event
                }
            }
        } else {
            if let monitor = escapeKeyMonitor {
                NSEvent.removeMonitor(monitor)
                escapeKeyMonitor = nil
            }
        }
    }
#endif

    private func presentCanvasSizePrompt(_ purpose: DashboardCanvasBoundsStore.Purpose) {
        dashboardCanvasSizePromptPurpose = purpose
        canvasBoundsStore.seedPromptFromCurrentCanvas(
            width: canvasSize.width,
            height: canvasSize.height,
            defaultPresetID: purpose == .newDashboard ? "builtin:p1920x1080" : "custom"
        )
        isShowingNewDashboardSizePrompt = true
    }

    private func presentCanvasSizeForTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        pendingCanvasSizeTabIndex = index
        let currentSize = tabs[index].canvasSize ?? canvasBoundsStore.size
        canvasBoundsStore.seedPromptFromCurrentCanvas(
            width: currentSize.width,
            height: currentSize.height,
            defaultPresetID: "custom"
        )
        dashboardCanvasSizePromptPurpose = .resizeCurrent
        isShowingNewDashboardSizePrompt = true
    }

    private func applyCanvasSizeChange(_ newSize: CGSize, purpose: DashboardCanvasBoundsStore.Purpose) {
        let oldSize = canvasSize
        if oldSize == newSize, purpose != .newDashboard {
            return
        }

        if purpose == .resizeCurrent,
           shouldPromptForTileScale(newSize: newSize) {
            pendingCanvasResize = PendingCanvasResize(
                oldSize: oldSize,
                newSize: newSize,
                purpose: purpose
            )
            isShowingCanvasResizeScaleAlert = true
            return
        }

        applyCanvasSizeChangeInternal(
            newSize,
            oldSize: oldSize,
            purpose: purpose,
            scaleTiles: false
        )
    }

    private func resolvePendingCanvasResize(scaleTiles: Bool) {
        guard let pending = pendingCanvasResize else { return }
        pendingCanvasResize = nil

        applyCanvasSizeChangeInternal(
            pending.newSize,
            oldSize: pending.oldSize,
            purpose: pending.purpose,
            scaleTiles: scaleTiles
        )
    }

    private func applyCanvasSizeChangeInternal(
        _ newSize: CGSize,
        oldSize: CGSize,
        purpose: DashboardCanvasBoundsStore.Purpose,
        scaleTiles: Bool
    ) {
        if purpose == .resizeCurrent {
            registerCanvasSizeUndo(oldSize: oldSize, newSize: newSize)
        }

        if scaleTiles {
            if purpose == .resizeCurrent {
                pushUndoSnapshot("Scale Tiles for Canvas Resize")
            }
            scaleTilePositionsForCanvasResize(from: oldSize, to: newSize)
        }

        if purpose == .resizeCurrent {
            let targetIndex = pendingCanvasSizeTabIndex ?? selectedTabIndex
            pendingCanvasSizeTabIndex = nil
            if tabs.indices.contains(targetIndex) {
                tabs[targetIndex].canvasSize = newSize
            }
            saveState.hasUnsavedChanges = true
            scheduleTabsSaveDebounced()
        } else {
            // newDashboard — sets the document-level default
            pendingCanvasSizeTabIndex = nil
            canvasBoundsStore.size = newSize
        }
        clampGuidesToCanvasBounds()
        recomputeLANMirrorScale()

        switch purpose {
        case .newDashboard:
            handleNewDashboardRequested()
        case .resizeCurrent:
            break
        }
    }

    private func shouldPromptForTileScale(newSize: CGSize) -> Bool {
        guard newSize.width > 0, newSize.height > 0 else { return false }
        return tilesOutsideCanvas(for: newSize)
    }

    private func tilesOutsideCanvas(for size: CGSize) -> Bool {
        for tab in tabs {
            for tile in tab.tiles {
                let tileSize = effectiveTileSize(for: tile)
                let rect = CGRect(
                    x: tile.offset.width,
                    y: tile.offset.height,
                    width: tileSize.width,
                    height: tileSize.height
                )
                if rect.minX < 0
                    || rect.minY < 0
                    || rect.maxX > size.width
                    || rect.maxY > size.height {
                    return true
                }
            }
        }
        return false
    }

    private func scaleTilePositionsForCanvasResize(from oldSize: CGSize, to newSize: CGSize) {
        guard oldSize.width > 0, oldSize.height > 0 else { return }

        let sx = newSize.width / oldSize.width
        let sy = newSize.height / oldSize.height
        guard abs(sx - 1.0) > 0.0001 || abs(sy - 1.0) > 0.0001 else { return }

        for tabIndex in tabs.indices {
            for tileIndex in tabs[tabIndex].tiles.indices {
                var tile = tabs[tabIndex].tiles[tileIndex]
                let tileSize = effectiveTileSize(for: tile)

                var newX = tile.offset.width * sx
                var newY = tile.offset.height * sy

                let maxX = max(0, newSize.width - tileSize.width)
                let maxY = max(0, newSize.height - tileSize.height)

                newX = min(max(newX, 0), maxX)
                newY = min(max(newY, 0), maxY)

                tile.offset = CGSize(width: newX, height: newY)
                tabs[tabIndex].tiles[tileIndex] = tile
            }
        }
    }

    private func registerCanvasSizeUndo(oldSize: CGSize, newSize _: CGSize) {
        guard let um = systemUndoManager else { return }

        um.registerUndo(withTarget: canvasBoundsStore) { _ in
            let currentSize = canvasBoundsStore.size
            canvasBoundsStore.size = oldSize
            clampGuidesToCanvasBounds()
            recomputeLANMirrorScale()
            saveState.hasUnsavedChanges = true
            registerCanvasSizeUndo(oldSize: currentSize, newSize: oldSize)
        }

        um.setActionName("Change Canvas Size")
    }

    /// Resets all tabs to a single provided tab, clearing guides, selection,
    /// and file association, and persisting the fresh document state. Shared
    /// by the File > New Dashboard command and the onboarding wizard's
    /// "create dashboard" completion.
    private func resetDocumentForNewDashboard(tab: DashboardTab) {
        beginReplacingDocumentState()
        defer { endReplacingDocumentState() }
        resetLiveModeForDocumentTransition()

        tabs = [tab]
        selectedTabIndex = 0
        fitCanvasToViewport()
        lastSavedURL = nil
        restoredWorkingDocumentCandidate = nil
        clearPersistedWorkingDocumentURL()
        saveState.currentFileURL = nil
        saveState.currentFileName = "Untitled"
        saveState.hasAssociatedFile = false
        saveState.hasUnsavedChanges = false
        saveState.hasRealDocument = true
        logDashboardSummary(tabs, context: "New dashboard")

        selectedTileIDs.removeAll()
        editingTileID = nil
        isInspectorVisible = false

        saveTabs()
    }

    /// Handles the File > New Dashboard command by resetting all tabs,
    /// clearing guides and selection, and persisting a fresh empty dashboard.
    private func handleNewDashboardRequested() {
        resetDocumentForNewDashboard(tab: DashboardTab(name: "Dashboard 1", tiles: []))
        showCanvasTutorialIfNeeded()

        // TODO: If you have explicit APIs to clear PCO login or External Devices
        // configuration, call them here so New Dashboard also wipes those:
        // PCOAuthStore.shared.reset()
        // ExternalDevicesStore.shared.resetToDefaults()
    }

    /// Builds real dashboard tiles from the wizard's checked candidates, laid
    /// out via OnboardingReviewLayout, and commits them as a new dashboard.
    private func handleOnboardingWizardCompletion(
        candidates: [OnboardingTileCandidate],
        canvasSize: CGSize,
        name: String
    ) {
        let frames = OnboardingReviewLayout.layout(candidateIDs: candidates.map(\.id), canvasSize: canvasSize)
        let tiles: [DashboardTileModel] = candidates.map { candidate in
            let rect = frames[candidate.id] ?? CGRect(origin: .zero, size: CGSize(width: 320, height: 240))
            let (offset, size) = OnboardingReviewLayout.offsetAndSize(for: rect)
            return DashboardTileModel(kind: .empty, modules: [candidate.module], offset: offset, size: size, showsTitle: true)
        }

        canvasBoundsStore.size = canvasSize
        resetDocumentForNewDashboard(tab: DashboardTab(name: name, tiles: tiles, canvasSize: canvasSize))
    }

    private func resetLiveModeForDocumentTransition() {
        isLiveMode = false
    }

    private func startPCORefreshAnimation() {
        isPCORefreshing = true
        refreshPCOModulesForSelectedTab()
        
    }

    private func resyncConsoleAndWirelessDeviceNames(
        nodeId: UUID?,
        refreshDeviceOptions: AppControlRefreshDeviceOptions = AppControlRefreshDeviceOptions(),
        buttonConfigId: UUID? = nil
    ) {
        let allTargets = ExternalDevicesStore.shared.devices.filter(\.isNameRefreshTarget)
        let targetIDs = Set(refreshDeviceOptions.selectedDeviceIDs)
        let targets: [ExternalDeviceConfig]
        switch refreshDeviceOptions.targetScope {
        case .allDevices:
            targets = allTargets
        case .selectedDevices:
            targets = allTargets.filter { targetIDs.contains($0.id) }
        }

        let shureDevices = targets.filter { $0.kind == .shureWireless }
        let syncableConsoleDevices = targets.filter { $0.kind == .audioConsole }

        guard !shureDevices.isEmpty || !syncableConsoleDevices.isEmpty else {
            let message = refreshDeviceOptions.targetScope == .selectedDevices
                ? "No selected devices to refresh"
                : "Refresh failed"
            postAppControlFailure(nodeId: nodeId, message: message, buttonConfigId: buttonConfigId)
            presentNotification(title: "Automation", message: message, durationSeconds: 2.5)
            return
        }

        postAppControlStarted(nodeId: nodeId, buttonConfigId: buttonConfigId)

        Task.detached(priority: .utility) {
            let shureResult = await refreshShureDeviceNames(for: shureDevices)
            let consoleResult = await refreshConsoleChannelNames(for: syncableConsoleDevices)
            let hadShureTargets = !shureDevices.isEmpty
            let hadConsoleTargets = !syncableConsoleDevices.isEmpty
            let succeeded = (!hadShureTargets || shureResult.succeeded) && (!hadConsoleTargets || consoleResult.succeeded)
            let failureMessage = shureResult.failureMessage ?? consoleResult.failureMessage ?? "Refresh failed"

            await MainActor.run {
                if succeeded {
                    postAppControlSuccess(nodeId: nodeId, buttonConfigId: buttonConfigId)
                } else {
                    postAppControlFailure(nodeId: nodeId, message: failureMessage, buttonConfigId: buttonConfigId)
                    presentNotification(title: "Automation", message: failureMessage, durationSeconds: 2.5)
                }
            }
        }
    }

    private struct DeviceRefreshResult {
        var succeeded: Bool
        var failureMessage: String?
    }

    private func refreshShureDeviceNames(for devices: [ExternalDeviceConfig]) async -> DeviceRefreshResult {
        guard !devices.isEmpty else { return DeviceRefreshResult(succeeded: true, failureMessage: nil) }

        var anySucceeded = false
        var firstFailureMessage: String? = nil

        for device in devices {
            let isReachable = await probeReachability(for: device)
            guard isReachable else {
                if firstFailureMessage == nil {
                    firstFailureMessage = "Cannot reach \(device.name)"
                }
                continue
            }

            let modelCode = device.shureModelIdentifier?.uppercased() ?? ""
            let upperName = device.name.uppercased()
            let isP10T = modelCode.contains("P10T") || upperName.contains("P10T")

            if isP10T {
                let didRefreshDeviceName = await ShureWirelessService.refreshDeviceIDNameSync(
                    for: device,
                    allowP10T: true,
                    forceRefresh: true,
                    timeoutSeconds: 8.0
                )
                let didRefreshChannelNames = await ShureWirelessService.refreshChannelNamesSync(
                    for: device,
                    timeoutSeconds: 3.0
                )
                let didSucceed = didRefreshDeviceName || didRefreshChannelNames
                anySucceeded = anySucceeded || didSucceed
                if !didSucceed, firstFailureMessage == nil {
                    firstFailureMessage = "\(device.name) timed out while refreshing names"
                }
            } else {
                let result = await ShureWirelessService.refreshShureAfterScan(for: device)
                ShureWirelessService.refreshDeviceIDName(for: device)
                let didSucceed = result.0 || result.1
                anySucceeded = anySucceeded || didSucceed
                if !didSucceed, firstFailureMessage == nil {
                    firstFailureMessage = "\(device.name) timed out while refreshing names"
                }
            }

            await MainActor.run {
                ExternalDevicesStore.shared.updateDevice(id: device.id) { device in
                    device.lastChannelSyncAt = Date()
                }
            }
        }

        return DeviceRefreshResult(
            succeeded: anySucceeded,
            failureMessage: anySucceeded ? nil : firstFailureMessage
        )
    }

    private func refreshConsoleChannelNames(for devices: [ExternalDeviceConfig]) async -> DeviceRefreshResult {
        guard !devices.isEmpty else { return DeviceRefreshResult(succeeded: true, failureMessage: nil) }

        var anySucceeded = false
        var firstFailureMessage: String? = nil

        for device in devices {
            let isReachable = await probeReachability(for: device)
            guard isReachable else {
                if firstFailureMessage == nil {
                    firstFailureMessage = "Cannot reach \(device.name)"
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
                continue
            }

            let map: [Int: String]
            switch device.audioConsoleModel {
            case .behringerX32, .midasM32:
                map = await ConsoleConnectorRegistry.shared.syncX32ChannelNames(
                    externalDeviceId: device.id,
                    channelCount: 32,
                    timeout: 2.0
                )
            case .allenHeathDlive:
                map = await ConsoleConnectorRegistry.shared.syncAllenHeathChannelNames(
                    externalDeviceId: device.id,
                    channelCount: 128,
                    timeout: 1.0
                )
            case .allenHeathAvantis, .allenHeathSq:
                map = await ConsoleConnectorRegistry.shared.syncAllenHeathChannelNames(
                    externalDeviceId: device.id,
                    channelCount: 64,
                    timeout: 1.0
                )
            default:
                continue
            }

            guard !map.isEmpty else {
                if firstFailureMessage == nil {
                    firstFailureMessage = "\(device.name) timed out while refreshing channel names"
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
                continue
            }

            anySucceeded = true

            let now = Date()
            persistConsoleNameSync(map: map, at: now, for: device)

            await MainActor.run {
                ExternalDevicesStore.shared.updateDevice(id: device.id) { device in
                    device.lastChannelSyncAt = now
                }
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        return DeviceRefreshResult(
            succeeded: anySucceeded,
            failureMessage: anySucceeded ? nil : firstFailureMessage
        )
    }

    private func probeReachability(for device: ExternalDeviceConfig) async -> Bool {
        let trimmedHost = device.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return false }

        if !NetUtils.resolve(host: trimmedHost).isEmpty {
            return await probeResolvedEndpoint(host: trimmedHost, port: probePort(for: device))
        }

        return await probeResolvedEndpoint(host: trimmedHost, port: probePort(for: device))
    }

    private func probePort(for device: ExternalDeviceConfig) -> UInt16 {
        if device.kind == .shureWireless {
            return device.port > 0 ? device.port : 2202
        }

        switch device.audioConsoleModel {
        case .behringerX32, .midasM32:
            return 10023
        case .allenHeathDlive, .allenHeathAvantis, .allenHeathSq:
            return device.port > 0 ? device.port : 51325
        default:
            return device.port
        }
    }

    private func probeResolvedEndpoint(host: String, port: UInt16) async -> Bool {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: max(1, port)) else { return false }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let queue = DispatchQueue(label: "Relay.DeviceReachabilityProbe")
            let gate = OneShotGate()

            let finish: @Sendable (Bool) -> Void = { reachable in
                guard gate.tryFire() else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: reachable)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed(_), .cancelled:
                    finish(false)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 1.25) {
                finish(false)
            }
        }
    }

    private func postAppControlStarted(nodeId: UUID?, buttonConfigId: UUID? = nil) {
        guard let nodeId else { return }
        var info: [AnyHashable: Any] = [ActionNodeUserInfoKeys.nodeId: nodeId]
        if let buttonConfigId { info["buttonConfigId"] = buttonConfigId }
        NotificationCenter.default.post(name: ActionNodeNotifications.appControlStarted, object: nil, userInfo: info)
    }

    private func postAppControlFailure(nodeId: UUID?, message: String, buttonConfigId: UUID? = nil) {
        guard let nodeId else { return }
        var info: [AnyHashable: Any] = [ActionNodeUserInfoKeys.nodeId: nodeId, ActionNodeUserInfoKeys.errorMessage: message]
        if let buttonConfigId { info["buttonConfigId"] = buttonConfigId }
        NotificationCenter.default.post(name: ActionNodeNotifications.appControlFailed, object: nil, userInfo: info)
    }

    private func postAppControlSuccess(nodeId: UUID?, buttonConfigId: UUID? = nil) {
        guard let nodeId else { return }
        var info: [AnyHashable: Any] = [ActionNodeUserInfoKeys.nodeId: nodeId]
        if let buttonConfigId { info["buttonConfigId"] = buttonConfigId }
        NotificationCenter.default.post(name: ActionNodeNotifications.appControlSucceeded, object: nil, userInfo: info)
    }

    private func completeImmediateAppControl(
        nodeId: UUID?,
        success: Bool,
        failureMessage: String? = nil,
        bannerMessage: String? = nil,
        buttonConfigId: UUID? = nil
    ) {
        postAppControlStarted(nodeId: nodeId, buttonConfigId: buttonConfigId)
        if success {
            postAppControlSuccess(nodeId: nodeId, buttonConfigId: buttonConfigId)
            return
        }

        let message = failureMessage ?? "Action failed"
        postAppControlFailure(nodeId: nodeId, message: message, buttonConfigId: buttonConfigId)
        if let bannerMessage {
            presentNotification(title: "Automation", message: bannerMessage, durationSeconds: 2.5)
        }
    }

    private func clearSplMeters(nodeId: UUID?, buttonConfigId: UUID? = nil) {
        guard tabs.indices.contains(selectedTabIndex) else {
            completeImmediateAppControl(
                nodeId: nodeId,
                success: false,
                failureMessage: "No SPL meters found",
                bannerMessage: "Clear failed",
                buttonConfigId: buttonConfigId
            )
            return
        }

        let tab = tabs[selectedTabIndex]
        let targets: [(moduleId: UUID, tileId: UUID)] = tab.tiles.flatMap { tile in
            (tile.modules ?? []).compactMap { module in
                guard case .dbReader = module.kind else { return nil }
                return (module.id, tile.id)
            }
        }

        guard !targets.isEmpty else {
            completeImmediateAppControl(
                nodeId: nodeId,
                success: false,
                failureMessage: "No SPL meters found",
                bannerMessage: "Clear failed",
                buttonConfigId: buttonConfigId
            )
            return
        }

        postAppControlStarted(nodeId: nodeId, buttonConfigId: buttonConfigId)
        for target in targets {
            NotificationCenter.default.post(
                name: .dbReaderClearRequested,
                object: nil,
                userInfo: [
                    "moduleId": target.moduleId,
                    "tileId": target.tileId
                ]
            )
        }
        postAppControlSuccess(nodeId: nodeId, buttonConfigId: buttonConfigId)
    }

    private func clearLiveTranscript(nodeId: UUID?, buttonConfigId: UUID? = nil) {
        guard tabs.indices.contains(selectedTabIndex) else {
            completeImmediateAppControl(
                nodeId: nodeId,
                success: false,
                failureMessage: "No live transcript found",
                bannerMessage: "Clear failed",
                buttonConfigId: buttonConfigId
            )
            return
        }

        let tab = tabs[selectedTabIndex]
        let targetTileIDs = Set(tab.tiles.compactMap { tile in
            let hasLiveTranscription = (tile.modules ?? []).contains { module in
                if case .liveTranscription = module.kind { return true }
                return false
            }
            return hasLiveTranscription ? tile.id : nil
        })

        guard !targetTileIDs.isEmpty else {
            completeImmediateAppControl(
                nodeId: nodeId,
                success: false,
                failureMessage: "No live transcript found",
                bannerMessage: "Clear failed",
                buttonConfigId: buttonConfigId
            )
            return
        }

        postAppControlStarted(nodeId: nodeId, buttonConfigId: buttonConfigId)
        for tileId in targetTileIDs {
            NotificationCenter.default.post(
                name: .liveTranscriptionClearRequested,
                object: nil,
                userInfo: ["tileId": tileId]
            )
        }
        postAppControlSuccess(nodeId: nodeId, buttonConfigId: buttonConfigId)
    }

    private func persistConsoleNameSync(map: [Int: String], at date: Date, for device: ExternalDeviceConfig) {
        let defaults = UserDefaults.standard
        let mapKey: String
        let timestampKey: String

        switch device.audioConsoleModel {
        case .behringerX32, .midasM32:
            mapKey = "prodlink.x32sync.map.\(device.id.uuidString)"
            timestampKey = "prodlink.x32sync.ts.\(device.id.uuidString)"
        case .allenHeathDlive, .allenHeathAvantis, .allenHeathSq:
            mapKey = "prodlink.ah.sync.map.\(device.id.uuidString)"
            timestampKey = "prodlink.ah.sync.ts.\(device.id.uuidString)"
        default:
            return
        }

        do {
            let data = try JSONEncoder().encode(map)
            defaults.set(data, forKey: mapKey)
        } catch {
            defaults.removeObject(forKey: mapKey)
        }

        defaults.set(date.timeIntervalSince1970, forKey: timestampKey)

        if case .allenHeathDlive = device.audioConsoleModel {
            defaults.removeObject(forKey: "prodlink.dlive.sync.map.\(device.id.uuidString)")
            defaults.removeObject(forKey: "prodlink.dlive.sync.ts.\(device.id.uuidString)")
        }
    }

    /// Extracted from the `.onReceive(ActionNodeNotifications.appControl)` closure — inline, the
    /// guard's chained optional casts made the surrounding modifier chain too complex for the
    /// type-checker to resolve in reasonable time on some build configurations.
    private func handleAppControlNotification(_ note: Notification) {
        guard let rawValue = note.userInfo?[ActionNodeUserInfoKeys.appActionKind] as? String,
              let actionKind = DashboardGraph.AppControlActionConfig.ActionKind(rawValue: rawValue) else {
            return
        }

        let nodeId = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID
        let buttonConfigId = note.userInfo?["buttonConfigId"] as? UUID
        let refreshTargetScopeRawValue = note.userInfo?[ActionNodeUserInfoKeys.refreshTargetScope] as? String
        let refreshTargetScope = AppControlRefreshDeviceOptions.TargetScope(rawValue: refreshTargetScopeRawValue ?? "")
            ?? .allDevices
        let selectedDeviceIDs = (note.userInfo?[ActionNodeUserInfoKeys.selectedDeviceIDs] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))
        let refreshDeviceOptions = AppControlRefreshDeviceOptions(
            targetScope: refreshTargetScope,
            selectedDeviceIDs: selectedDeviceIDs
        )
        performAppControlAction(
            actionKind,
            nodeId: nodeId,
            refreshDeviceOptions: refreshDeviceOptions,
            buttonConfigId: buttonConfigId
        )
    }

    private func performAppControlAction(
        _ actionKind: DashboardGraph.AppControlActionConfig.ActionKind,
        nodeId: UUID? = nil,
        refreshDeviceOptions: AppControlRefreshDeviceOptions = AppControlRefreshDeviceOptions(),
        buttonConfigId: UUID? = nil
    ) {
        switch actionKind {
        case .selectFirstTab:
            selectFirstNavigableDashboardTab()
        case .selectPreviousTab:
            selectPreviousNavigableDashboardTab()
        case .selectNextTab:
            selectNextNavigableDashboardTab()
        case .selectLastTab:
            selectLastNavigableDashboardTab()
        case .refreshPCO:
            startPCORefreshAnimation()
            if tabs.indices.contains(selectedTabIndex) {
                let tab = tabs[selectedTabIndex]
                Task {
                    _ = await pcoAutoAdvanceCoordinator.advanceIfNeeded(tab: tab, force: true)
                }
            }
        case .resyncDeviceNames:
            resyncConsoleAndWirelessDeviceNames(
                nodeId: nodeId,
                refreshDeviceOptions: refreshDeviceOptions,
                buttonConfigId: buttonConfigId
            )
        case .clearSplMeters:
            clearSplMeters(nodeId: nodeId, buttonConfigId: buttonConfigId)
        case .clearLiveTranscript:
            clearLiveTranscript(nodeId: nodeId, buttonConfigId: buttonConfigId)
        case .switchToCanvasView:
            NotificationCenter.default.post(name: .dashboardCanvasViewRequested, object: nil)
        case .switchToAutomationView:
            NotificationCenter.default.post(name: .dashboardAutomationViewRequested, object: nil)
        case .enterLiveMode:
            isLiveMode = true
        case .exitLiveMode:
            isLiveMode = false
        case .toggleLiveMode:
            isLiveMode.toggle()
        case .saveDashboard:
            NotificationCenter.default.post(name: .saveDashboardQuickRequested, object: nil)
        case .saveDashboardAs:
            NotificationCenter.default.post(name: .saveDashboardRequested, object: nil)
        case .startSplLogging:
            Task { await SPLLoggingManager.shared.startLogging() }
        case .stopSplLogging:
            Task { await SPLLoggingManager.shared.stopLogging() }
        case .toggleSplLogging:
            Task { await SPLLoggingManager.shared.toggleLogging() }
        }
    }

    private func selectTab(at requestedIndex: Int, animated: Bool = true) {
        guard !tabs.isEmpty else { return }
        let clampedIndex = min(max(0, requestedIndex), tabs.count - 1)
        guard clampedIndex != selectedTabIndex else { return }

        let tabSelectionAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.10)
        if animated {
            withAnimation(tabSelectionAnimation) {
                selectedTabIndex = clampedIndex
            }
        } else {
            selectedTabIndex = clampedIndex
        }
    }

    private struct TabScheduleActivation {
        let tabIndex: Int
        let activationKey: String
    }

    private func evaluateTabSchedule(now: Date = .now) {
        guard isLiveMode, subscriptionManager.hasPro else {
            lastObservedScheduleActivationKey = nil
            return
        }

        let activation = scheduledTabActivation(at: now)
        let activationKey = activation?.activationKey
        guard activationKey != lastObservedScheduleActivationKey else { return }

        lastObservedScheduleActivationKey = activationKey

        guard let activation else { return }
        selectTab(at: activation.tabIndex)
    }

    private func scheduledTabActivation(at now: Date) -> TabScheduleActivation? {
        for tabIndex in tabs.indices {
            let tab = tabs[tabIndex]
            guard tab.lanMirrorShareId == nil,
                  tab.tabScheduleEnabled else { continue }

            for rule in tab.tabScheduleRules {
                guard let windowStart = scheduledWindowStart(for: rule, at: now) else { continue }
                let activationKey = "\(tab.id.uuidString)|\(rule.id.uuidString)|\(Int(windowStart.timeIntervalSince1970))"
                return TabScheduleActivation(tabIndex: tabIndex, activationKey: activationKey)
            }
        }

        return nil
    }

    private func scheduledWindowStart(for rule: DashboardTabScheduleRule, at now: Date) -> Date? {
        let selectedWeekdays = Set(rule.weekdays.filter { (1...7).contains($0) })
        guard !selectedWeekdays.isEmpty else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: now)
        let startOfToday = calendar.startOfDay(for: now)
        let minutesNow = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        if rule.isAllDay {
            guard selectedWeekdays.contains(weekday) else { return nil }
            return startOfToday
        }

        let clampedStart = max(0, min(rule.startMinutes, (24 * 60) - 1))
        let clampedEnd = max(0, min(rule.endMinutes, (24 * 60) - 1))

        if clampedStart == clampedEnd {
            guard selectedWeekdays.contains(weekday) else { return nil }
            return calendar.date(byAdding: .minute, value: clampedStart, to: startOfToday)
        }

        if clampedStart < clampedEnd {
            guard selectedWeekdays.contains(weekday),
                  minutesNow >= clampedStart,
                  minutesNow < clampedEnd else { return nil }
            return calendar.date(byAdding: .minute, value: clampedStart, to: startOfToday)
        }

        if minutesNow >= clampedStart, selectedWeekdays.contains(weekday) {
            return calendar.date(byAdding: .minute, value: clampedStart, to: startOfToday)
        }

        guard minutesNow < clampedEnd,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return nil
        }

        let previousWeekday = calendar.component(.weekday, from: previousDay)
        guard selectedWeekdays.contains(previousWeekday) else { return nil }
        return calendar.date(byAdding: .minute, value: clampedStart, to: previousDay)
    }

    private func disableWebpageViewportBypass() {
        isWebpageViewportBypassActive = false
        webpageViewportBypassModuleID = nil
    }

    private func syncWebpageViewportBypassSelectionState() {
        guard isWebpageViewportBypassActive,
              let moduleID = webpageViewportBypassModuleID else {
            return
        }

        guard selectedTileIDs.contains(where: { selectedTileID in
            tileContainsModule(selectedTileID, moduleID: moduleID)
        }) else {
            disableWebpageViewportBypass()
            return
        }
    }

    private func tileContainsModule(_ tileID: UUID, moduleID: UUID) -> Bool {
        guard tabs.indices.contains(selectedTabIndex),
              let tile = tabs[selectedTabIndex].tiles.first(where: { $0.id == tileID }),
              let modules = tile.modules else {
            return false
        }

        return modules.contains(where: { $0.id == moduleID })
    }

    private func refreshPCOModulesForSelectedTab() {
        guard tabs.indices.contains(selectedTabIndex) else { return }

        var tab = tabs[selectedTabIndex]

        for tileIndex in tab.tiles.indices {
            // Skip hidden tiles entirely so we don't waste work refreshing modules
            // for tiles that are not visible on the dashboard.
            if tab.tiles[tileIndex].isHidden {
                continue
            }

            // Next, refresh any person / PCO modules on this tile.
            if var modules = tab.tiles[tileIndex].modules {
                var changedModules = false

                for moduleIndex in modules.indices {
                    switch modules[moduleIndex].kind {
                    case .pcoRundown:
                        // Bump the kind to itself to ensure SwiftUI sees a change and re-renders,
                        // in case the view caches anything based on the module identity.
                        let kind = modules[moduleIndex].kind
                        modules[moduleIndex].kind = kind
                        changedModules = true

                    case .person(let personModel):
                        // Re-resolve the person model from the current PCO configuration
                        // so that changes to service / plan reflect in the tile.
                        let resolved = tab.resolvedPersonModel(personModel)
                        modules[moduleIndex].kind = .person(resolved)
                        changedModules = true

                    default:
                        break
                    }
                }

                if changedModules {
                    tab.tiles[tileIndex].modules = modules
                }
            }
        }

        tabs[selectedTabIndex] = tab
        saveTabs()
    }

}

// MARK: - Selection action toolbar (isolated from root body's invalidation)

/// Wraps the selection action toolbar so only this small view re-renders as
/// live drag deltas change, instead of the entire root body.
///
/// `DashboardRootView.body` used to compute the selection's live bounding
/// rect directly (via `selectedTilesBoundingRect()`/`liveDragDelta(for:)`),
/// which read `interactionSession.draggedTileID`/`draggedTileDelta`/
/// `groupDragFollowerIDs`/`groupDragDelta` -- all written every gesture
/// frame. Under `@Observable`, any body that reads those properties becomes
/// a dependent of every drag-frame write, so a single-tile drag was
/// re-running the entire ~10k-line root body every frame. Isolating the read
/// here means a drag frame only re-renders this small view; the root body
/// only supplies `committedSelectedRects`, which change at selection/layout
/// frequency, not gesture frequency.
private struct DashboardSelectionActionToolbarHost: View {
    let session: DashboardTileInteractionSession
    /// Committed (non-live) rects for every currently selected tile, in
    /// canvas coordinates -- i.e. `tile.offset`/effective size with no live
    /// drag delta applied. Plain values computed by the parent from
    /// `tabs`/`selectedTileIDs`, neither of which changes at gesture
    /// frequency.
    let committedSelectedRects: [UUID: CGRect]
    let selectedTileIDs: Set<UUID>
    let canvasViewportZoom: CGFloat
    let canvasViewportPan: CGSize
    let canvasSize: CGSize
    let onApplyFractionRegion: (CanvasFractionRegion) -> Void
    let onDistribute: (DistributeAxis) -> Void

    /// The live, uncommitted translation currently being applied to `tileID`
    /// during an active drag -- either as the tile the cursor is directly
    /// on, or as a group-drag follower -- so this toolbar can track the
    /// tile in real time instead of freezing until the drag commits.
    private func liveDragDelta(for tileID: UUID) -> CGSize {
        if session.draggedTileID == tileID {
            return session.draggedTileDelta
        }
        if session.groupDragFollowerIDs.contains(tileID) {
            return session.groupDragDelta
        }
        return .zero
    }

    /// The union of all currently-selected tiles' rects, in canvas
    /// coordinates, with live drag deltas applied. `nil` when nothing is
    /// selected, which hides the toolbar entirely.
    private var selectionRect: CGRect? {
        guard !selectedTileIDs.isEmpty else { return nil }

        let rects: [CGRect] = selectedTileIDs.compactMap { tileID -> CGRect? in
            guard let base = committedSelectedRects[tileID] else { return nil }
            let delta = liveDragDelta(for: tileID)
            return base.offsetBy(dx: delta.width, dy: delta.height)
        }

        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    var body: some View {
        if let rect = selectionRect {
            let flipBelow = SelectionToolbarPlacement.shouldFlipBelow(
                selectionRect: rect,
                viewportZoom: canvasViewportZoom,
                viewportPanY: canvasViewportPan.height
            )

            SelectionActionToolbarView(
                selectionRect: rect,
                selectedTileCount: selectedTileIDs.count,
                viewportZoom: canvasViewportZoom,
                shouldFlipBelow: flipBelow,
                onApplyFractionRegion: onApplyFractionRegion,
                onDistribute: onDistribute,
                canvasSize: canvasSize
            )
            .scaleEffect(canvasViewportZoom, anchor: .topLeading)
            .offset(canvasViewportPan)
            .zIndex(10_001) // above guidesLayer (10_000)
        }
    }
}

// MARK: - Layout-aware scaling (so scaled views affect layout)

private struct MeasuredSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        // Prefer the largest non-zero measurement.
        if next.width * next.height > value.width * value.height {
            value = next
        }
    }
}

private struct DashboardLiveModeChromeView: View {
    let tabItems: [DashboardRootView.NavigableDashboardTabItem]
    let selectedTabID: String?
    let selectedTitle: String
    let canSelectPreviousTab: Bool
    let canSelectNextTab: Bool
    let onSelectTab: (DashboardRootView.NavigableDashboardTabItem) -> Void
    let onSelectPreviousTab: () -> Void
    let onSelectNextTab: () -> Void
    let onToggleLiveMode: () -> Void
    let onShowTabSettings: () -> Void
    let onShowRosters: () -> Void
    let onShowSettings: () -> Void
    let onInteractionBegan: () -> Void
    let onInteractionEnded: () -> Void
    let isGraphMode: Bool
    let showAutomationProBadge: Bool
    let onToggleGraphCanvas: () -> Void

    private var iconScale: Image.Scale {
        #if os(iOS)
        .medium
        #else
        .small
        #endif
    }

    private var barFont: Font {
        #if os(iOS)
        .system(size: 15, weight: .semibold, design: .rounded)
        #else
        .system(size: 13, weight: .semibold, design: .rounded)
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: interactionWrapped(onToggleLiveMode)) {
                Image(systemName: "xmark")
                    .imageScale(iconScale)
                    .frame(width: 28, height: 28)
                    .liveModeToolbarIconChrome()
            }
            .buttonStyle(.plain)
            .help("Exit Live Mode")

            Button(action: interactionWrapped(onSelectPreviousTab)) {
                Image(systemName: "chevron.left")
                    .imageScale(iconScale)
                    .frame(width: 28, height: 28)
                    .liveModeToolbarIconChrome()
            }
            .buttonStyle(.plain)
            .disabled(!canSelectPreviousTab)
            .opacity(canSelectPreviousTab ? 1.0 : 0.35)
            .help("Previous Tab")

            Menu {
                ForEach(tabItems) { item in
                    Button {
                        interactionWrapped {
                            onSelectTab(item)
                        }()
                    } label: {
                        if item.id == selectedTabID {
                            Label(item.title, systemImage: "checkmark")
                        } else {
                            Text(item.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTitle)
                        .font(barFont)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 170)
                .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onInteractionBegan() }
                    .onEnded { _ in onInteractionEnded() }
            )

            Button(action: interactionWrapped(onSelectNextTab)) {
                Image(systemName: "chevron.right")
                    .imageScale(iconScale)
                    .frame(width: 28, height: 28)
                    .liveModeToolbarIconChrome()
            }
            .buttonStyle(.plain)
            .disabled(!canSelectNextTab)
            .opacity(canSelectNextTab ? 1.0 : 0.35)
            .help("Next Tab")

            Button(action: interactionWrapped(onToggleGraphCanvas)) {
                ZStack(alignment: .topTrailing) {
                    DashboardSymbolImage(isGraphMode ? "square.grid.2x2" : "point.3.connected.trianglepath.dotted")
                        .imageScale(iconScale)
                        .foregroundStyle(isGraphMode ? Color.accentColor : Color.primary)
                        .frame(width: 28, height: 28)
                        .liveModeToolbarIconChrome()

                    if showAutomationProBadge && !isGraphMode {
                        ProBadgeView(label: "PRO", fontSize: 7)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .offset(x: 6, y: -6)
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(isGraphMode ? "Switch to Canvas View" : "Switch to Graph View")

            Menu {
                Button(action: interactionWrapped(onShowTabSettings)) {
                    Label("Tab Settings", systemImage: "slider.horizontal.below.rectangle")
                }
                Button(action: interactionWrapped(onShowRosters)) {
                    Label("Rosters", systemImage: "person.3")
                }
                Button(action: interactionWrapped(onShowSettings)) {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(iconScale)
                    .frame(width: 28, height: 28)
                    .liveModeToolbarIconChrome()
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onInteractionBegan() }
                    .onEnded { _ in onInteractionEnded() }
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liveModePillSurface()
        .frame(maxWidth: 460)
    }

    private func interactionWrapped(_ action: @escaping () -> Void) -> () -> Void {
        {
            onInteractionBegan()
            action()
            onInteractionEnded()
        }
    }
}

private struct LiveModeToolbarIconChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if os(macOS)
            content
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .opacity(0.85)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                        .allowsHitTesting(false)
                )
            #else
            content
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                        .allowsHitTesting(false)
                )
            #endif
        } else {
            content
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }
}

private extension View {
    func liveModeToolbarIconChrome() -> some View {
        modifier(LiveModeToolbarIconChrome())
    }

    @ViewBuilder
    func liveModePillSurface() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.regularMaterial)
                        .opacity(0.85)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                        .allowsHitTesting(false)
                )
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }
}


// MARK: - Autosave Announcement

private struct AutosaveAnnouncementView: View {
    @Binding var fileAutosaveEnabled: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 32)
            .padding(.bottom, 16)

            Text("Auto-Save is Now On")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 8)

            Text("Relay now automatically saves your dashboards as you work — as long as the file has been saved at least once.\n\nYou can turn this off below or any time in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            Divider()

            // Inline toggle
            Toggle(isOn: $fileAutosaveEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Save")
                        .font(.subheadline.weight(.medium))
                    Text("Save changes automatically when a file is open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)

            Divider()

            Button {
                onDismiss()
            } label: {
                Text("Got It")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SyncOrphanBanner: View {
    let tabName: String
    let hostStopped: Bool
    let canReconnect: Bool
    let onReconnect: () -> Void
    let onKeep: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hostStopped ? "stop.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(hostStopped ? Color.red : Color.orange)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text(hostStopped ? "\"\(tabName)\" — host stopped sharing" : "\"\(tabName)\" lost connection")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(hostStopped
                     ? "The host ended the sync session. Keep a local copy or remove the tab."
                     : (canReconnect ? "Host is available — reconnect or keep a local copy." : "The host is offline."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                if canReconnect {
                    Button("Reconnect") { onReconnect() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                Button("Keep as Local") { onKeep() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Remove") { onRemove() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}
