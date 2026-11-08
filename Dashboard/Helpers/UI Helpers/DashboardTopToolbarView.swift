//
//  DashboardTopToolbarView.swift
//  Relay
//
//  Extracted from DashboardRootView.topToolbar() to keep DashboardRootView.swift smaller.
//  This view is intentionally “dumb UI”: it receives bindings + closures from DashboardRootView.
//

import SwiftUI
import UniformTypeIdentifiers

struct DashboardTopToolbarView: View {

    // MARK: - Inputs (state + dependencies)

    @ObservedObject var lanService: LANSharedTabsService

    @Binding var tabs: [DashboardTab]
    @Binding var selectedTabIndex: Int

    @Binding var selectedLANShareId: String?
    @Binding var selectedLANDeviceName: String?

    @Binding var lanMirrorReferenceCanvasSize: CGSize?
    let recomputeLANMirrorScale: () -> Void

    let lanSharingEnabled: Bool
    let isGraphMode: Bool

    @Binding var automationScopePrimerShown: Bool
    let onSetAutomationMode: (DashboardTab.AutomationMode) -> Void
    let onSelectAutomationScopeForTab: (UUID) -> Void
    let onAutomationContextualAction: () -> Void

    // Tile/Inspector state
    @Binding var isTileOverviewVisible: Bool
    @Binding var isInspectorVisible: Bool
    @Binding var editingTileID: UUID?
    @Binding var selectedTileIDs: Set<UUID>

    // Used by inspector focus logic
    let focusTileForInspector: (_ tileID: UUID) -> Void
    let bindingForEditingTile: () -> Binding<DashboardTileModel>?
    let clearEditFocusOffsetsX: () -> Void

    // Deleting tiles (needed by selection bar)
    let deleteTilesWithIDs: (_ ids: Set<UUID>) -> Void
    let deleteSelectedTiles: () -> Void
    /// Notifies the parent when the user is interacting with tab UI (e.g. renaming a tab).
    /// Used to pause LAN polling so background updates don't dismiss menus or steal focus.
    let onTabInteractionChanged: (Bool) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let canUndo: Bool
    let canRedo: Bool
    // PCO config
    @Binding var showingPCOConfigForTab: Bool
    @Binding var showingRosters: Bool

    // Settings
    @Binding var showingSettings: Bool

    @EnvironmentObject var saveState: DashboardSaveState
    @Environment(\.colorScheme) private var colorScheme

    @Binding var isLiveMode: Bool

#if os(iOS)
    @Binding var snapToGridEnabled: Bool
    @Binding var showGridEnabled: Bool
    @Binding var showGuidesEnabled: Bool
    @Binding var iPadAutoHideToolbarEnabled: Bool
    @Binding var isTutorialPresented: Bool
#endif

    // Canvas size (current tab effective size and document-level default)
    let canvasSize: CGSize
    let documentDefaultCanvasSize: CGSize

    // Mirror tab disables local edits
    let isMirrorTabSelected: Bool

    // Tab operations
    let reorderLocalTabs: (_ draggedID: UUID, _ onto: UUID) -> Void
    let duplicateTab: (_ at: Int) -> Void
    let deleteTab: (_ at: Int) -> Void
    let addTab: () -> Void
    let presentCanvasSizeForTab: (_ tabIndex: Int) -> Void
    let makeSyncedTab: (_ at: Int) -> Void
    let stopSyncingTab: (_ at: Int) -> Void
    let reconnectSyncedTab: (_ at: Int) -> Void
    let joinSyncedTab: (_ manifest: SyncedTabManifest) -> Void

    // LAN operations
    let openLANMirror: (_ manifest: LANSharedTabManifest) async -> Void
    let beginLANImport: (_ manifest: LANSharedTabManifest) -> Void

    // Graph/Canvas toggle
    let toggleGraphCanvas: () -> Void
    /// Fires a global “send all” action in Graph view (caller wires to GraphDashboardView logic).
    let sendAllToConsoles: () -> Void = {}
    // MARK: - Presentation (macOS pill HUD)

    /// When true on macOS, the toolbar is shown as a floating pill that reveals via a top-edge hot zone.
    var usesPillHUD: Bool = true

    /// Height of the invisible hot zone at the very top edge that reveals the pill HUD.
    var hotZoneHeight: CGFloat = 10

    /// Auto-hide delay (seconds) after the cursor leaves the pill HUD.
    var autoHideDelay: Double = 2.0

    /// When false, the pill HUD will not auto-hide.
    /// Driven by the View/Edit menu toggle via this persisted preference.
    @AppStorage("dashboard_toolbar_autohide_enabled")
    private var autoHideEnabled: Bool = false

    @AppStorage("dashboard_show_system_usage")
    private var showSystemUsage: Bool = false
    @AppStorage("dashboard_view_mode")
    private var dashboardViewMode: String = "canvas"
    @AppStorage("dashboard_has_hidden_tiles")
    private var dashboardHasHiddenTiles: Bool = false
    @AppStorage("dashboard_has_hidden_nodes")
    private var dashboardHasHiddenNodes: Bool = false

    // MARK: - Local UI state

    @State private var renamingTabID: UUID? = nil
    @FocusState private var focusedRenameTabID: UUID?
    @State private var renamingDraftName: String = ""
    @State private var draggingLocalTabID: UUID? = nil
    @State private var localTabFrames: [UUID: CGRect] = [:]

    private struct LocalTabFramePreferenceKey: PreferenceKey {
        static var defaultValue: [UUID: CGRect] = [:]

        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }
    
    @State private var pendingDeleteLocalTabIndex: Int? = nil
    @State private var showDeleteTabConfirm: Bool = false
    
    @State private var isPillVisible: Bool = true
    @State private var isHoveringPill: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil
    @State private var savedLabelVisible: Bool = false
    @State private var savedHideTask: Task<Void, Never>? = nil
    @State private var isFlipHoldActive: Bool = false
    @State private var flipHoldTask: Task<Void, Never>? = nil

    @State private var canSendAllToConsoles: Bool = false
    @State private var lanOpenToken: UUID = UUID()
    @State private var showAutomationScopePopover: Bool = false

    @Namespace private var selectionChipNamespace
    // While renaming, freeze LAN-driven UI so frequent LAN publishes don’t disturb TextField selection.
    @State private var frozenLANRemoteTabs: [LANSharedTabManifest] = []
    @State private var frozenLANPeerCount: Int = 0

    @State private var tabsScrollContentWidth: CGFloat = 0
    @State private var tabsScrollContainerWidth: CGFloat = 0
    @State private var tabsScrollMinX: CGFloat = 0

    #if os(macOS)
    @State private var hoveringLocalTabID: UUID? = nil
    #endif

    /// True if a tab is currently being renamed.
    private var isRenamingTab: Bool { renamingTabID != nil }

    // MARK: - Tab rename helpers

    private func beginRename(tabID: UUID, currentName: String) {
        // Mark interaction active so parent can pause LAN/polling.
        onTabInteractionChanged(true)

        // Freeze LAN UI state during rename to prevent periodic selection clearing.
        frozenLANRemoteTabs = lanService.remoteTabs
        frozenLANPeerCount = lanService.peers.count

        // Keep the pill visible and prevent any pending auto-hide while editing.
        hideTask?.cancel()
        hideTask = nil
        flipHoldTask?.cancel()
        flipHoldTask = nil
        isFlipHoldActive = true
        showPillHUD()

        renamingDraftName = currentName
        renamingTabID = tabID

        // Focus on next runloop tick so the TextField is definitely in the hierarchy.
        DispatchQueue.main.async {
            focusedRenameTabID = tabID
        }
    }

    private func commitRename(at idx: Int, tabID: UUID) {
        guard tabs.indices.contains(idx), tabs[idx].id == tabID else {
            cancelRename()
            return
        }
        let trimmed = renamingDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            tabs[idx].name = trimmed
        }
        cancelRename()
    }

    private func cancelRename() {
        renamingTabID = nil
        focusedRenameTabID = nil
        renamingDraftName = ""
        isFlipHoldActive = false
        onTabInteractionChanged(false)
    }

    @ViewBuilder
    private func toolbarClusterDivider(height: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: height)
            .accessibilityHidden(true)
    }

    // Segmented-pill animation state (Liquid Glass style)
    @Namespace private var tabSelectionNamespace
    @State private var lastSelectedTabIndex: Int = 0
    @State private var isSelectionPulsing: Bool = false
    @State private var selectionPulseDirection: CGFloat = 1.0
    @State private var selectionPulseTask: Task<Void, Never>? = nil

#if os(iOS)
    private final class CommandsMenuState {
        var isLikelyOpen: Bool = false
    }
    @State private var commandsMenuState = CommandsMenuState()
    @State private var isCommandsPopoverPresented: Bool = false
    @State private var commandsMenuResumeTask: Task<Void, Never>? = nil
    @State private var isIPadToolbarVisible: Bool = true
    @State private var iPadHideTask: Task<Void, Never>? = nil
#endif

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var selectionPillAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.10)
    }

    // MARK: - Helpers
    
    private func requestDeleteTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        guard tabs[index].lanMirrorShareId == nil else { return } // local only
        pendingDeleteLocalTabIndex = index
        showDeleteTabConfirm = true
    }
    private var hasSelectedTab: Bool {
        tabs.indices.contains(selectedTabIndex)
    }

    private var selectedTabSafe: DashboardTab? {
        hasSelectedTab ? tabs[selectedTabIndex] : nil
    }

    private var selectedTabID: UUID? {
        selectedTabSafe?.id
    }

    private var selectedLocalTabFrame: CGRect? {
        guard let selectedTabID else { return nil }
        return localTabFrames[selectedTabID]
    }

    private var hasTilesInTab: Bool {
        (selectedTabSafe?.tiles.isEmpty == false)
    }

    private var canToggleOverview: Bool { hasTilesInTab }
    private var canToggleInspector: Bool { !selectedTileIDs.isEmpty }


   
    #if os(iOS)
    private var iOSToolbarIconW: CGFloat { 42 }
    private var iOSToolbarIconH: CGFloat { 38 }
    #endif

    // MARK: - Pill HUD animations

    private var pillShowAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.10)
    }

    private var pillHideAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    private var pillTransition: AnyTransition {
        #if os(macOS)
        // Avoid opacity-based transitions on glass materials to prevent flashing.
        return .asymmetric(
            insertion: .move(edge: .top)
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .move(edge: .top)
                .combined(with: .scale(scale: 0.99, anchor: .top))
        )
        #else
        return .asymmetric(
            insertion: .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.99, anchor: .top))
        )
        #endif
    }

    private func showPillHUD() {
        hideTask?.cancel()
        hideTask = nil
        withAnimation(pillShowAnimation) {
            isPillVisible = true
        }
    }

    private func hidePillHUD() {
        withAnimation(pillHideAnimation) {
            isPillVisible = false
        }
    }

    /// Schedules the pill HUD to auto-hide after `delay`, cancelling any
    /// previously-scheduled hide first. Re-checks hover/rename state when it fires,
    /// since either may have changed during the delay.
    private func scheduleAutoHidePillHUD(after delay: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if !isHoveringPill && renamingTabID == nil {
                hidePillHUD()
            }
        }
    }

    /// Cancels every delayed task owned by this view so none of them fire after
    /// the view disappears (tab switch, window close, etc.).
    private func cancelAllScheduledToolbarTasks() {
        hideTask?.cancel()
        hideTask = nil
        savedHideTask?.cancel()
        savedHideTask = nil
        flipHoldTask?.cancel()
        flipHoldTask = nil
        selectionPulseTask?.cancel()
        selectionPulseTask = nil
        #if os(iOS)
        commandsMenuResumeTask?.cancel()
        commandsMenuResumeTask = nil
        iPadHideTask?.cancel()
        iPadHideTask = nil
        #endif
    }

    private func triggerSelectionPulse(from oldIndex: Int, to newIndex: Int) {
        selectionPulseDirection = (newIndex >= oldIndex) ? 1.0 : -1.0
        isSelectionPulsing = true
        // Short pulse; keep it subtle so it feels Apple, not “cartoon”.
        selectionPulseTask?.cancel()
        selectionPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                isSelectionPulsing = false
            }
        }
    }

    private func beginFlipHold() {
        // During the flip animation, keep the pill visible and prevent auto-hide.
        hideTask?.cancel()
        hideTask = nil

        flipHoldTask?.cancel()
        flipHoldTask = nil

        isFlipHoldActive = true
        showPillHUD()

        // Release the hold shortly after the flip typically completes.
        flipHoldTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }

            // Release hold and, if the user isn't hovering the pill, allow it to auto-hide again.
            isFlipHoldActive = false

            // If auto-hide is disabled, keep the pill visible.
            guard autoHideEnabled else {
                hideTask?.cancel()
                hideTask = nil
                showPillHUD()
                return
            }

            // If the cursor isn't over the pill, schedule a normal auto-hide.
            if usesPillHUD && !isHoveringPill {
                scheduleAutoHidePillHUD(after: 0.25)
            }
        }
    }

    private func deviceIconName(for kind: LANDeviceKind?, fallbackDeviceName: String) -> String {
        LANDeviceKind.iconName(for: kind, fallbackDeviceName: fallbackDeviceName)
    }

    // MARK: - LAN tabs grouping (avoid toolbar spam)

    private let lanInlineThresholdPerDevice: Int = 2

    private struct LANDeviceKey: Hashable {
        let name: String
        let kind: LANDeviceKind?
    }

    private func deviceKey(for manifest: LANSharedTabManifest) -> LANDeviceKey {
        LANDeviceKey(name: manifest.deviceName, kind: manifest.deviceKind)
    }

    private func selectLANManifest(_ manifest: LANSharedTabManifest) {
        // Treat LAN selection as an interaction so parent can pause polling.
        // IMPORTANT: Menu selections (device dropdown) can dismiss/rebuild views immediately;
        // defer the async open slightly so it runs after the menu has fully dismissed.
        onTabInteractionChanged(true)

        // Token so multiple quick selections don't resume polling too early.
        let token = UUID()
        lanOpenToken = token

        selectedLANShareId = manifest.shareId
        selectedLANDeviceName = manifest.deviceName
        lanMirrorReferenceCanvasSize = manifest.referenceCanvasSize
        recomputeLANMirrorScale()
        isInspectorVisible = false
        editingTileID = nil
        selectedTileIDs.removeAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Task {
                await openLANMirror(manifest)
                await MainActor.run {
                    // Only resume if this is still the latest selection.
                    if lanOpenToken == token {
                        onTabInteractionChanged(false)
                    }
                }
            }
        }
    }

    private func clearLANMirrorSelection() {
        onTabInteractionChanged(true)

        selectedLANShareId = nil
        selectedLANDeviceName = nil
        lanMirrorReferenceCanvasSize = nil
        recomputeLANMirrorScale()

        isInspectorVisible = false
        editingTileID = nil
        selectedTileIDs.removeAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            onTabInteractionChanged(false)
        }
    }

    private func requestLANImport(_ manifest: LANSharedTabManifest) {
        // Defer until after menus dismiss (prevents sheet/popover presentation being dropped).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .lanImportRequested,
                object: nil,
                userInfo: ["shareId": manifest.shareId]
            )
        }
    }

    @ViewBuilder
    private func lanDeviceMenuPill(
        deviceName: String,
        deviceKind: LANDeviceKind?,
        count: Int,
        showsChevron: Bool = false,
        isAnySelected: Bool,
        iconScale: Image.Scale,
        barFont: Font,
        tabHPad: CGFloat,
        tabVPad: CGFloat,
        toolbarForeground: Color,
        tabsStripHeight: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi")
                .imageScale(.small)
                .foregroundStyle(toolbarForeground.opacity(isAnySelected ? 1.0 : 0.82))

            HStack(spacing: 6) {
                Text(deviceName)
                    .font(barFont)
                    .foregroundStyle(toolbarForeground.opacity(isAnySelected ? 1.0 : 0.88))
                    .lineLimit(1)

                Text("•")
                    .font(barFont)
                    .foregroundStyle(toolbarForeground.opacity(0.55))

                Text("\(count)")
                    .font(barFont.weight(.semibold))
                    .foregroundStyle(toolbarForeground.opacity(isAnySelected ? 0.78 : 0.66))
            }
            .layoutPriority(1)

            Image(systemName: deviceIconName(for: deviceKind, fallbackDeviceName: deviceName))
                .imageScale(.small)
                .foregroundStyle(toolbarForeground.opacity(0.60))

            if showsChevron {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(toolbarForeground.opacity(isAnySelected ? 0.70 : 0.55))
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, tabHPad)
        .padding(.vertical, tabVPad)
        .frame(height: tabsStripHeight)
        .background {
            if isAnySelected {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1)
                            .allowsHitTesting(false)
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
                            .allowsHitTesting(false)
                    )
            }
        }
        .animation(nil, value: isAnySelected)
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func lanRemoteTabsCluster(
        _ manifests: [LANSharedTabManifest],
        iconScale: Image.Scale,
        barFont: Font,
        tabHPad: CGFloat,
        tabVPad: CGFloat,
        toolbarForeground: Color,
        tabsStripHeight: CGFloat
    ) -> some View {
        let grouped = Dictionary(grouping: manifests, by: deviceKey(for:))

        // Stable ordering by device name.
        let deviceKeys = grouped.keys.sorted { a, b in
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        ForEach(deviceKeys, id: \.self) { key in
            let deviceManifests = (grouped[key] ?? []).sorted { a, b in
                a.tabName.localizedCaseInsensitiveCompare(b.tabName) == .orderedAscending
            }

            if deviceManifests.count <= lanInlineThresholdPerDevice {
                // Inline pills (1–2 tabs)
                ForEach(deviceManifests, id: \.shareId) { manifest in
                    Button {
                        selectLANManifest(manifest)
                    } label: {
                        lanRemoteTabPill(
                            manifest: manifest,
                            isSelected: selectedLANShareId == manifest.shareId,
                            iconScale: iconScale,
                            barFont: barFont,
                            tabHPad: tabHPad,
                            tabVPad: tabVPad,
                            toolbarForeground: toolbarForeground,
                            tabsStripHeight: tabsStripHeight
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(nil, value: selectedLANShareId)
                    .contextMenu {
                        Button {
                            requestLANImport(manifest)
                        } label: {
                            Label("Import Tab", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            } else {
                // Collapsed device menu (3+ tabs)
                let isAnySelected = deviceManifests.contains(where: { $0.shareId == selectedLANShareId })

                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Menu {
                        if isAnySelected {
                            Button(role: .destructive) {
                                clearLANMirrorSelection()
                            } label: {
                                Label("Stop Mirroring", systemImage: "xmark.circle")
                            }
                            Divider()
                        }

                        ForEach(deviceManifests, id: \.shareId) { manifest in
                            let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                            Button {
                                selectLANManifest(manifest)
                            } label: {
                                if selectedLANShareId == manifest.shareId {
                                    Label(title, systemImage: "checkmark")
                                } else {
                                    Text(title)
                                }
                            }
                        }

                        Divider()

                        ForEach(deviceManifests, id: \.shareId) { manifest in
                            let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                            Button {
                                requestLANImport(manifest)
                            } label: {
                                Label("Import “\(title)”", systemImage: "square.and.arrow.down")
                            }
                        }
                    } label: {
                        lanDeviceMenuPill(
                            deviceName: key.name,
                            deviceKind: key.kind,
                            count: deviceManifests.count,
                            showsChevron: true,
                            isAnySelected: isAnySelected,
                            iconScale: iconScale,
                            barFont: barFont,
                            tabHPad: tabHPad,
                            tabVPad: tabVPad,
                            toolbarForeground: toolbarForeground,
                            tabsStripHeight: tabsStripHeight
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(nil, value: selectedLANShareId)
                } else {
                    Menu {
                        ForEach(deviceManifests, id: \.shareId) { manifest in
                            let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                            Button {
                                selectLANManifest(manifest)
                            } label: {
                                if selectedLANShareId == manifest.shareId {
                                    Label(title, systemImage: "checkmark")
                                } else {
                                    Text(title)
                                }
                            }
                        }

                        Divider()

                        ForEach(deviceManifests, id: \.shareId) { manifest in
                            let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                            Button {
                                requestLANImport(manifest)
                            } label: {
                                Label("Import “\(title)”", systemImage: "square.and.arrow.down")
                            }
                        }
                    } label: {
                        lanDeviceMenuPill(
                            deviceName: key.name,
                            deviceKind: key.kind,
                            count: deviceManifests.count,
                            showsChevron: true,
                            isAnySelected: isAnySelected,
                            iconScale: iconScale,
                            barFont: barFont,
                            tabHPad: tabHPad,
                            tabVPad: tabVPad,
                            toolbarForeground: toolbarForeground,
                            tabsStripHeight: tabsStripHeight
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(nil, value: selectedLANShareId)
                }
                #else
                Menu {
                    ForEach(deviceManifests, id: \.shareId) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button {
                            selectLANManifest(manifest)
                        } label: {
                            if selectedLANShareId == manifest.shareId {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }

                    Divider()

                    ForEach(deviceManifests, id: \.shareId) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button {
                            requestLANImport(manifest)
                        } label: {
                            Label("Import “\(title)”", systemImage: "square.and.arrow.down")
                        }
                    }
                } label: {
                    lanDeviceMenuPill(
                        deviceName: key.name,
                        deviceKind: key.kind,
                        count: deviceManifests.count,
                        showsChevron: true,
                        isAnySelected: isAnySelected,
                        iconScale: iconScale,
                        barFont: barFont,
                        tabHPad: tabHPad,
                        tabVPad: tabVPad,
                        toolbarForeground: toolbarForeground,
                        tabsStripHeight: tabsStripHeight
                    )
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .animation(nil, value: selectedLANShareId)
                #endif
            }
        }
    }
        

    @ViewBuilder
    private func syncedRemoteTabsCluster(
        _ manifests: [SyncedTabManifest],
        iconScale: Image.Scale,
        barFont: Font,
        tabHPad: CGFloat,
        tabVPad: CGFloat,
        toolbarForeground: Color,
        tabsStripHeight: CGFloat
    ) -> some View {
        let byDevice = Dictionary(grouping: manifests, by: \.deviceName)
        let deviceNames = byDevice.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        ForEach(deviceNames, id: \.self) { deviceName in
            let deviceManifests = (byDevice[deviceName] ?? []).sorted {
                $0.tabName.localizedCaseInsensitiveCompare($1.tabName) == .orderedAscending
            }

            if deviceManifests.count <= lanInlineThresholdPerDevice {
                ForEach(deviceManifests) { manifest in
                    Button {
                        joinSyncedTab(manifest)
                    } label: {
                        syncedRemoteTabPill(
                            manifest: manifest,
                            iconScale: iconScale,
                            barFont: barFont,
                            tabHPad: tabHPad,
                            tabVPad: tabVPad,
                            toolbarForeground: toolbarForeground,
                            tabsStripHeight: tabsStripHeight
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Join \"\(manifest.tabName)\" from \(manifest.deviceName)")
                }
            } else {
                Menu {
                    ForEach(deviceManifests) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button {
                            joinSyncedTab(manifest)
                        } label: {
                            Label("Join \"\(title)\"", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } label: {
                    lanDeviceMenuPill(
                        deviceName: deviceName,
                        deviceKind: nil,
                        count: deviceManifests.count,
                        showsChevron: true,
                        isAnySelected: false,
                        iconScale: iconScale,
                        barFont: barFont,
                        tabHPad: tabHPad,
                        tabVPad: tabVPad,
                        toolbarForeground: toolbarForeground,
                        tabsStripHeight: tabsStripHeight
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func syncedTabsMenuButton(
        _ manifests: [SyncedTabManifest],
        tabHPad: CGFloat,
        tabVPad: CGFloat,
        toolbarForeground: Color,
        tabsStripHeight: CGFloat
    ) -> some View {
        let byDevice = Dictionary(grouping: manifests, by: \.deviceName)
        let deviceNames = byDevice.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let pillLabel = HStack(spacing: 5) {
            Image(systemName: SyncMirrorPresentation.syncIconName(isSubscriber: false))
                .imageScale(.small)
            Text("Sync")
                .font(.caption.weight(.semibold))
                .fixedSize()
        }
            .foregroundStyle(SyncMirrorPresentation.syncColor)
            .padding(.horizontal, tabHPad)
            .padding(.vertical, tabVPad)
            .frame(height: tabsStripHeight)
            .background { Capsule().strokeBorder(SyncMirrorPresentation.syncColor.opacity(0.45), lineWidth: 1) }
            .contentShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)

        #if os(iOS)
        Menu {
            ForEach(deviceNames, id: \.self) { deviceName in
                let deviceManifests = (byDevice[deviceName] ?? []).sorted {
                    $0.tabName.localizedCaseInsensitiveCompare($1.tabName) == .orderedAscending
                }
                Section(deviceName) {
                    ForEach(deviceManifests) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button { joinSyncedTab(manifest) } label: {
                            Label("Join \"\(title)\"", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
        } label: { pillLabel }
        .buttonStyle(.plain)
        #else
        SyncedTabsMacOSPill(
            manifests: manifests,
            tabHPad: tabHPad,
            tabVPad: tabVPad,
            toolbarForeground: toolbarForeground,
            tabsStripHeight: tabsStripHeight,
            onJoin: joinSyncedTab
        )
        #endif
    }

    @ViewBuilder
    private func lanMirrorMenuButton(
        _ manifests: [LANSharedTabManifest],
        tabHPad: CGFloat,
        tabVPad: CGFloat,
        toolbarForeground: Color,
        tabsStripHeight: CGFloat
    ) -> some View {
        let grouped = Dictionary(grouping: manifests, by: deviceKey(for:))
        let deviceKeys = grouped.keys.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let isAnySelected = manifests.contains(where: { $0.shareId == selectedLANShareId })
        let pillLabel = HStack(spacing: 5) {
            Image(systemName: SyncMirrorPresentation.mirrorIconName)
                .imageScale(.small)
            Text("Mirror")
                .font(.caption.weight(.semibold))
                .fixedSize()
        }
            .foregroundStyle(isAnySelected ? SyncMirrorPresentation.mirrorColor : SyncMirrorPresentation.mirrorColor.opacity(0.75))
            .padding(.horizontal, tabHPad)
            .padding(.vertical, tabVPad)
            .frame(height: tabsStripHeight)
            .background { Capsule().strokeBorder(SyncMirrorPresentation.mirrorColor.opacity(0.45), lineWidth: 1) }
            .contentShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)

        #if os(iOS)
        Menu {
            if isAnySelected {
                Button(role: .destructive) { clearLANMirrorSelection() } label: {
                    Label("Stop Mirroring", systemImage: "xmark.circle")
                }
            }
            ForEach(deviceKeys, id: \.self) { key in
                let deviceManifests = (grouped[key] ?? []).sorted {
                    $0.tabName.localizedCaseInsensitiveCompare($1.tabName) == .orderedAscending
                }
                Section(key.name) {
                    ForEach(deviceManifests, id: \.shareId) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button { selectLANManifest(manifest) } label: {
                            if selectedLANShareId == manifest.shareId {
                                Label(title, systemImage: "checkmark")
                            } else { Text(title) }
                        }
                    }
                }
            }
            Section("Import") {
                ForEach(deviceKeys, id: \.self) { key in
                    let deviceManifests = (grouped[key] ?? []).sorted {
                        $0.tabName.localizedCaseInsensitiveCompare($1.tabName) == .orderedAscending
                    }
                    ForEach(deviceManifests, id: \.shareId) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button { requestLANImport(manifest) } label: {
                            Label("Import \"\(title)\" from \(manifest.deviceName)", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
        } label: { pillLabel }
        .buttonStyle(.plain)
        .animation(nil, value: selectedLANShareId)
        #else
        LANMirrorMacOSPill(
            manifests: manifests,
            tabHPad: tabHPad,
            tabVPad: tabVPad,
            toolbarForeground: toolbarForeground,
            tabsStripHeight: tabsStripHeight,
            selectedLANShareId: selectedLANShareId,
            onSelect: selectLANManifest,
            onClearSelection: clearLANMirrorSelection,
            onImport: requestLANImport
        )
        #endif
    }

    private func syncedRemoteTabPill(
        manifest: SyncedTabManifest,
        iconScale: Image.Scale,
        barFont: Font,
        tabHPad: CGFloat,
        tabVPad: CGFloat,
        toolbarForeground: Color,
        tabsStripHeight: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .imageScale(.small)
                .foregroundStyle(toolbarForeground.opacity(0.82))

            HStack(spacing: 6) {
                Text(manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName)
                    .font(barFont)
                    .foregroundStyle(toolbarForeground.opacity(0.88))
                    .lineLimit(1)

                Text("•")
                    .font(barFont)
                    .foregroundStyle(toolbarForeground.opacity(0.55))

                Text(manifest.deviceName)
                    .font(barFont.weight(.regular))
                    .foregroundStyle(toolbarForeground.opacity(0.58))
                    .lineLimit(1)
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, tabHPad)
        .padding(.vertical, tabVPad)
        .frame(height: tabsStripHeight)
        .background {
            Capsule()
                .strokeBorder(toolbarForeground.opacity(0.22), lineWidth: 1)
        }
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func localTabSyncMirrorBadge(idx: Int, isSelected: Bool, toolbarForeground: Color) -> some View {
        let isSynced = tabs[idx].syncGroupID != nil
        let isMirror = tabs[idx].lanMirrorShareId != nil

        if isSynced {
            let isSubscriber = !tabs[idx].syncIsOwner
            let isOrphaned = tabs[idx].syncGroupID.map { lanService.orphanedSyncGroupIDs.contains($0) } ?? false
            let isStale = tabs[idx].syncGroupID.map { lanService.unverifiedSyncGroupIDs.contains($0) } ?? false
            let state = SyncMirrorPresentation.syncBadgeState(
                isOwner: tabs[idx].syncIsOwner,
                isOrphaned: isOrphaned,
                isStale: isStale
            )
            HStack(spacing: 5) {
                Image(systemName: SyncMirrorPresentation.syncIconName(isSubscriber: isSubscriber))
                    .imageScale(.small)
                    .foregroundStyle(SyncMirrorPresentation.syncBadgeColor(
                        for: state,
                        toolbarForeground: toolbarForeground,
                        isSelected: isSelected
                    ))
                if state == .stale {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        } else if isMirror {
            Image(systemName: SyncMirrorPresentation.mirrorIconName)
                .imageScale(.small)
                .foregroundStyle(SyncMirrorPresentation.mirrorBadgeColor(isSelected: isSelected))
        }
    }

    @ViewBuilder
    private func lanRemoteTabPill(
        manifest: LANSharedTabManifest,
        isSelected: Bool,
        iconScale: Image.Scale,
        barFont: Font,
        tabHPad: CGFloat,
        tabVPad: CGFloat,
        toolbarForeground: Color,
        tabsStripHeight: CGFloat
    ) -> some View {
        // Match the visual style of local tabs: Capsule + subtle selected glass.
        // LAN tabs still show a small wifi/device hint, but keep the same geometry.
        HStack(spacing: 6) {
            Image(systemName: "wifi")
                .imageScale(.small)
                .foregroundStyle(toolbarForeground.opacity(isSelected ? 1.0 : 0.82))

            HStack(spacing: 6) {
                Text(manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName)
                    .font(barFont)
                    .foregroundStyle(toolbarForeground.opacity(isSelected ? 1.0 : 0.88))
                    .lineLimit(1)

                Text("•")
                    .font(barFont)
                    .foregroundStyle(toolbarForeground.opacity(0.55))

                Text(manifest.deviceName)
                    .font(barFont.weight(.regular))
                    .font(.caption2)
                    .foregroundStyle(toolbarForeground.opacity(isSelected ? 0.70 : 0.58))
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Image(systemName: deviceIconName(for: manifest.deviceKind, fallbackDeviceName: manifest.deviceName))
                .imageScale(.small)
                .foregroundStyle(toolbarForeground.opacity(0.60))
        }
        .padding(.horizontal, tabHPad)
        .padding(.vertical, tabVPad)
        .frame(height: tabsStripHeight)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1)
                            .allowsHitTesting(false)
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
                            .allowsHitTesting(false)
                    )
            }
        }
        .animation(nil, value: isSelected)
        .contentShape(Capsule())
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

    #if os(iOS)
    /// Captures a two-finger vertical pan gesture (iPad friendly) without interfering with normal single-finger canvas interactions.
    private struct TwoFingerPanCapture: UIViewRepresentable {
        var onBegan: (() -> Void)? = nil
        var onEnded: ((_ translation: CGPoint) -> Void)? = nil

        func makeUIView(context: Context) -> UIView {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear

            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.cancelsTouchesInView = false
            view.addGestureRecognizer(pan)

            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            context.coordinator.onBegan = onBegan
            context.coordinator.onEnded = onEnded
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator: NSObject {
            var onBegan: (() -> Void)?
            var onEnded: ((_ translation: CGPoint) -> Void)?

            @objc func handlePan(_ gr: UIPanGestureRecognizer) {
                switch gr.state {
                case .began:
                    onBegan?()
                case .ended, .cancelled, .failed:
                    let t = gr.translation(in: gr.view)
                    onEnded?(t)
                default:
                    break
                }
            }
        }
    }

    /// Captures a one-finger vertical pan gesture (used only in a tiny top-edge hot zone so it won’t conflict with canvas gestures).
    private struct OneFingerTopEdgePanCapture: UIViewRepresentable {
        var onBegan: (() -> Void)? = nil
        var onEnded: ((_ translation: CGPoint) -> Void)? = nil

        func makeUIView(context: Context) -> UIView {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear

            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delegate = context.coordinator
            view.addGestureRecognizer(pan)

            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            context.coordinator.onBegan = onBegan
            context.coordinator.onEnded = onEnded
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            var onBegan: (() -> Void)?
            var onEnded: ((_ translation: CGPoint) -> Void)?

            @objc func handlePan(_ gr: UIPanGestureRecognizer) {
                switch gr.state {
                case .began:
                    onBegan?()
                case .ended, .cancelled, .failed:
                    let t = gr.translation(in: gr.view)
                    onEnded?(t)
                default:
                    break
                }
            }

            // Allow simultaneous recognition; we’re in a tiny hot zone, but this avoids any accidental blocking.
            func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
                true
            }
        }
    }
    #endif



// --- BEGIN REPLACEMENT: Native Menu for iPad commands ---
#if os(iOS)
    @ViewBuilder
    private func commandsMenu() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            Button {
                isCommandsPopoverPresented = true
            } label: {
                Image(systemName: "ellipsis")
                    .imageScale(.medium)
                    .foregroundStyle(.primary)
                    .frame(width: iOSToolbarIconW, height: iOSToolbarIconH)
                    .toolbarIconChrome(isActive: false)
                    .tutorialAnchor("root.mainMenu")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isCommandsPopoverPresented, arrowEdge: .top) {
                commandsPopoverContent
            }
            .onChange(of: isCommandsPopoverPresented, initial: false) { _, isPresented in
                if isPresented {
                    NotificationCenter.default.post(name: .pauseLANMirrorPolling, object: nil)
                    commandsMenuState.isLikelyOpen = true
                    onTabInteractionChanged(true)
                    showIPadToolbar()
                } else {
                    commandsMenuState.isLikelyOpen = false
                    NotificationCenter.default.post(name: .resumeLANMirrorPolling, object: nil)
                    onTabInteractionChanged(false)
                    scheduleIPadAutoHideIfNeeded(delay: 1.5)
                }
            }
        } else {
            Menu {
                commandsMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .imageScale(.medium)
                    .foregroundStyle(.primary)
                    .frame(width: iOSToolbarIconW, height: iOSToolbarIconH)
                    .toolbarIconChrome(isActive: false)
                    .tutorialAnchor("root.mainMenu")
            }
            .buttonStyle(.plain)
            // When the user taps the menu button, pause LAN polling and keep the toolbar visible.
            .simultaneousGesture(TapGesture().onEnded {
                NotificationCenter.default.post(name: .pauseLANMirrorPolling, object: nil)
                commandsMenuState.isLikelyOpen = true
                onTabInteractionChanged(true)
                showIPadToolbar()

                // Best-effort resume: menus don’t expose an explicit “dismiss” callback.
                // We resume shortly after typical menu interaction completes.
                commandsMenuResumeTask?.cancel()
                commandsMenuResumeTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3.0))
                    guard !Task.isCancelled else { return }
                    commandsMenuState.isLikelyOpen = false
                    NotificationCenter.default.post(name: .resumeLANMirrorPolling, object: nil)
                    onTabInteractionChanged(false)
                    scheduleIPadAutoHideIfNeeded(delay: 1.5)
                }
            })
        }
    }

    @ViewBuilder
    private var commandsMenuItems: some View {
        // File
        Button {
            DashboardDocumentController.shared.newDocument()
            resumeAfterMenuSelection()
        } label: {
            Label("New Dashboard", systemImage: DashboardSystemImage.name("doc.badge.plus"))
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button {
            NotificationCenter.default.post(name: .relayStartOnboardingWizard, object: nil)
            resumeAfterMenuSelection()
        } label: {
            Label("Setup Wizard…", systemImage: "wand.and.stars")
        }

        Button {
            DashboardDocumentController.shared.openDocument()
            resumeAfterMenuSelection()
        } label: {
            Label("Open…", systemImage: "folder")
        }
        .keyboardShortcut("o", modifiers: [.command])

        Divider()

        Button {
            DashboardDocumentController.shared.saveCurrentDocument()
            resumeAfterMenuSelection()
        } label: {
            Label("Save", systemImage: "square.and.arrow.down")
        }
        .keyboardShortcut("s", modifiers: [.command])
        .disabled(!saveState.canSaveCurrentDocument)

        Button {
            DashboardDocumentController.shared.saveCurrentDocumentAs()
            resumeAfterMenuSelection()
        } label: {
            Label("Save As…", systemImage: DashboardSystemImage.name("square.and.arrow.down.on.square"))
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Divider()

        // Edit
        Button {
            NotificationCenter.default.post(
                name: isGraphMode ? .duplicateGraphNodesRequested : .duplicateTileRequested,
                object: nil
            )
            resumeAfterMenuSelection()
        } label: {
            Label(isGraphMode ? "Duplicate Node" : "Duplicate Tile", systemImage: "square.on.square")
        }
        .keyboardShortcut("d", modifiers: [.command])
        .disabled(!isGraphMode && selectedTileIDs.isEmpty)

        Button {
            NotificationCenter.default.post(name: .createTileGroupRequested, object: nil)
            resumeAfterMenuSelection()
        } label: {
            Label("Group Selected Tiles…", systemImage: DashboardSystemImage.name("rectangle.3.group"))
        }
        .keyboardShortcut("g", modifiers: [.command])
        .disabled(selectedTileIDs.isEmpty)

        Button {
            NotificationCenter.default.post(name: .prodLinkToggleVisibilityRequested, object: nil)
            resumeAfterMenuSelection()
        } label: {
            Label(hideShowTitle, systemImage: "eye.slash")
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])

        Divider()

        Divider()

        Toggle(isOn: $iPadAutoHideToolbarEnabled) {
            Label("Auto-hide Toolbar", systemImage: "eye.slash")
        }
        .onChange(of: iPadAutoHideToolbarEnabled, initial: false) { _, _ in
            if !iPadAutoHideToolbarEnabled {
                showIPadToolbar()
            } else {
                scheduleIPadAutoHideIfNeeded(delay: 1.5)
            }
        }

        Divider()

        // View / Mode toggles (menus render these with checkmarks)
        Toggle(isOn: $isLiveMode) {
            Label("Live Mode", systemImage: "play.rectangle")
        }
        .keyboardShortcut("l", modifiers: [.command])

        Toggle(isOn: $snapToGridEnabled) {
            Label("Snap to Grid", systemImage: "dot.square")
        }

        Toggle(isOn: $showGridEnabled) {
            Label("Show Grid", systemImage: "grid")
        }

        Toggle(isOn: $showGuidesEnabled) {
            Label("Show Guides", systemImage: "ruler")
        }
    }

    @ViewBuilder
    private var commandsPopoverContent: some View {
        let menuEnabledColor: Color = .white
        let menuDisabledColor: Color = Color(white: 0.35)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                commandsMenuSectionHeader("File", disabledColor: menuDisabledColor)
                commandsMenuRow("New Dashboard", systemImage: "doc.badge.plus", enabledColor: menuEnabledColor, disabledColor: menuDisabledColor) {
                    DashboardDocumentController.shared.newDocument()
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut("n", modifiers: [.command])

                commandsMenuRow("Setup Wizard…", systemImage: "wand.and.stars", enabledColor: menuEnabledColor, disabledColor: menuDisabledColor) {
                    NotificationCenter.default.post(name: .relayStartOnboardingWizard, object: nil)
                    resumeAfterMenuSelection()
                }

                commandsMenuRow("Open…", systemImage: "folder", enabledColor: menuEnabledColor, disabledColor: menuDisabledColor) {
                    DashboardDocumentController.shared.openDocument()
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut("o", modifiers: [.command])

                commandsMenuRow(
                    "Save",
                    systemImage: "square.and.arrow.down",
                    isEnabled: saveState.canSaveCurrentDocument,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    DashboardDocumentController.shared.saveCurrentDocument()
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut("s", modifiers: [.command])

                commandsMenuRow("Save As…", systemImage: "square.and.arrow.down.on.square", enabledColor: menuEnabledColor, disabledColor: menuDisabledColor) {
                    DashboardDocumentController.shared.saveCurrentDocumentAs()
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                commandsMenuSectionDivider()

                commandsMenuSectionHeader("Edit", disabledColor: menuDisabledColor)
                commandsMenuRow(
                    isGraphMode ? "Duplicate Node" : "Duplicate Tile",
                    systemImage: "square.on.square",
                    isEnabled: isGraphMode || !selectedTileIDs.isEmpty,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    NotificationCenter.default.post(
                        name: isGraphMode ? .duplicateGraphNodesRequested : .duplicateTileRequested,
                        object: nil
                    )
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut("d", modifiers: [.command])

                commandsMenuRow(
                    "Group Selected Tiles…",
                    systemImage: "rectangle.3.group",
                    isEnabled: !selectedTileIDs.isEmpty,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    NotificationCenter.default.post(name: .createTileGroupRequested, object: nil)
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut("g", modifiers: [.command])

                commandsMenuRow("Resize Dashboard Canvas…", enabledColor: menuEnabledColor, disabledColor: menuDisabledColor) {
                    NotificationCenter.default.post(name: .changeDashboardSizeRequested, object: nil)
                    resumeAfterMenuSelection()
                }

                commandsMenuRow("Bring All Tiles Into Canvas", enabledColor: menuEnabledColor, disabledColor: menuDisabledColor) {
                    NotificationCenter.default.post(name: .bringAllTilesIntoCanvasRequested, object: nil)
                    resumeAfterMenuSelection()
                }

                commandsMenuRow(
                    "Delete Selected Tiles",
                    isEnabled: !selectedTileIDs.isEmpty,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    NotificationCenter.default.post(name: .prodLinkDeleteSelectionRequested, object: nil)
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut(.delete)

                commandsMenuRow(
                    hideShowTitle,
                    systemImage: "eye.slash",
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    NotificationCenter.default.post(name: .prodLinkToggleVisibilityRequested, object: nil)
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                commandsMenuSectionDivider()

                commandsMenuSectionHeader("View", disabledColor: menuDisabledColor)
                commandsMenuRow(
                    "Auto-Hide Menu",
                    isChecked: iPadAutoHideToolbarEnabled
                    ,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    iPadAutoHideToolbarEnabled.toggle()
                    if !iPadAutoHideToolbarEnabled {
                        showIPadToolbar()
                    } else {
                        scheduleIPadAutoHideIfNeeded(delay: 1.5)
                    }
                    resumeAfterMenuSelection()
                }

                commandsMenuSectionDivider()

                commandsMenuRow(
                    "Show System Status",
                    isChecked: showSystemUsage,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    showSystemUsage.toggle()
                    resumeAfterMenuSelection()
                }

                commandsMenuRow(
                    "Live Mode",
                    isChecked: isLiveMode,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    isLiveMode.toggle()
                    resumeAfterMenuSelection()
                }
                .keyboardShortcut("l", modifiers: [.command])

                commandsMenuRow(
                    "Snap to Grid",
                    isChecked: snapToGridEnabled,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    snapToGridEnabled.toggle()
                    resumeAfterMenuSelection()
                }

                commandsMenuRow(
                    "Show Grid",
                    isChecked: showGridEnabled,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    showGridEnabled.toggle()
                    resumeAfterMenuSelection()
                }

                commandsMenuRow(
                    "Show Guides",
                    isChecked: showGuidesEnabled,
                    enabledColor: menuEnabledColor,
                    disabledColor: menuDisabledColor
                ) {
                    showGuidesEnabled.toggle()
                    resumeAfterMenuSelection()
                }

                commandsMenuSectionDivider()

                commandsMenuSectionHeader("Help", disabledColor: menuDisabledColor)
                commandsMenuRow("Start Tutorial…", enabledColor: menuEnabledColor, disabledColor: menuDisabledColor) {
                    NotificationCenter.default.post(name: .prodlinkStartTutorial, object: nil)
                    resumeAfterMenuSelection()
                }

                commandsMenuRow("Export Logs…", enabledColor: menuEnabledColor, disabledColor: menuDisabledColor) {
                    NotificationCenter.default.post(name: .prodLinkExportLogsRequested, object: nil)
                    resumeAfterMenuSelection()
                }
            }
            .padding(12)
        }
        .frame(minWidth: 260, minHeight: 320)
        .tint(menuEnabledColor)
        .foregroundStyle(menuEnabledColor)
        // Rows are hardcoded white-on-dark by design; force dark so the popover's
        // own system chrome (background material) stays dark too. Without this,
        // Light Mode gives the popover a light background and the white text/icons
        // become unreadable.
        .preferredColorScheme(.dark)
    }

    private func commandsMenuSectionHeader(_ title: String, disabledColor: Color) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(disabledColor)
            .padding(.top, 6)
    }

    private func commandsMenuSectionDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 6)
    }

    private func commandsMenuRow(
        _ title: String,
        systemImage: String? = nil,
        isChecked: Bool = false,
        isEnabled: Bool = true,
        enabledColor: Color,
        disabledColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                if isChecked {
                    Image(systemName: "checkmark")
                        .frame(width: 16, alignment: .center)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }

                if let systemImage {
                    DashboardSymbolImage(systemImage)
                        .frame(width: 16, alignment: .center)
                }

                Text(title)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? enabledColor : disabledColor)
    }

    private func resumeAfterMenuSelection() {
        // If the user picked an item, resume immediately (better than waiting for the timer).
        commandsMenuResumeTask?.cancel()
        isCommandsPopoverPresented = false
        commandsMenuState.isLikelyOpen = false
        NotificationCenter.default.post(name: .resumeLANMirrorPolling, object: nil)
        scheduleIPadAutoHideIfNeeded(delay: 1.5)
    }

    private var hideShowTitle: String {
        if dashboardViewMode == "canvas", dashboardHasHiddenTiles {
            return "Show Hidden Tiles"
        }
        if dashboardViewMode == "automation" {
            return dashboardHasHiddenNodes ? "Show Hidden Nodes" : "Hide/Show Selected Nodes"
        }
        return "Hide/Show Selected"
    }
// --- END REPLACEMENT ---
    private func showIPadToolbar() {
        guard !isIPadToolbarVisible else { return }
        iPadHideTask?.cancel()
        iPadHideTask = nil
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.10)) {
            isIPadToolbarVisible = true
        }
    }

    private func hideIPadToolbar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isIPadToolbarVisible = false
        }
    }

    private func scheduleIPadAutoHideIfNeeded(delay: Double = 2.0) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        guard iPadAutoHideToolbarEnabled else { return }
        guard !commandsMenuState.isLikelyOpen else { return }
        guard !isTutorialPresented else { return }
        iPadHideTask?.cancel()
        iPadHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard !commandsMenuState.isLikelyOpen else { return }
            hideIPadToolbar()
        }
    }
    #endif
    // MARK: - Body

    var body: some View {
        let localIsMirror = (selectedTabSafe?.lanMirrorShareId != nil)
        let mirrorSelected = (selectedLANShareId != nil) || localIsMirror

        let lanRemoteTabsForUI = isRenamingTab ? frozenLANRemoteTabs : lanService.remoteTabs
        // Only allow closing local (non-mirrored) tabs when there is more than one.
        let localNonMirrorTabCount = tabs.filter { $0.lanMirrorShareId == nil }.count

        #if os(iOS)
        let isCompact = (horizontalSizeClass == .compact)
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        let toolbarHPad: CGFloat = (isPad && !isCompact) ? 10 : 12
        let toolbarVPad: CGFloat = 6

        let tabHPad: CGFloat = (isPad && !isCompact) ? 8 : 10
        let tabVPad: CGFloat = (isPad && !isCompact) ? 4 : 6

        let iconScale: Image.Scale = .medium
        let barFont: Font = (dynamicTypeSize.isAccessibilitySize ? .body : .subheadline)
        let secondaryFont: Font = (dynamicTypeSize.isAccessibilitySize ? .callout : .caption)

        // For the iPad pill HUD we want a lighter surface with darker content.
        // Keep the old dark/white look for the classic iOS top bar.
        let toolbarForeground: Color = isPad ? Color.primary : Color.white.opacity(0.92)

        let iconW: CGFloat = 42
        let iconH: CGFloat = 38
        let tabsStripHeight: CGFloat = max(iconH, 34)
        #else
        let toolbarHPad: CGFloat = 10
        let toolbarVPad: CGFloat = 6
        let tabHPad: CGFloat = 10
        let tabVPad: CGFloat = 6
        let iconScale: Image.Scale = .medium
        let barFont: Font = .subheadline
        let secondaryFont: Font = .caption

        let toolbarForeground: Color = Color.primary

        let iconW: CGFloat = 30
        let iconH: CGFloat = 24
        let tabsStripHeight: CGFloat = max(iconH, 28)
        #endif

        let toolbarContent = VStack(spacing: 0) {
            HStack(spacing: 10) {

            // MARK: - Left cluster
            HStack(spacing: 8) {
                #if os(iOS)
                commandsMenu()
                #endif

                if !isGraphMode {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isTileOverviewVisible.toggle()
                        }
                    } label: {
                        DashboardSymbolImage("sidebar.leading")
                            .imageScale(iconScale)
                            .foregroundStyle(isTileOverviewVisible ? Color.accentColor : toolbarForeground)
                            .frame(width: iconW, height: iconH)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .toolbarIconChrome(isActive: isTileOverviewVisible)
                            .tutorialAnchor("root.overviewButton")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canToggleOverview)
                    .opacity(canToggleOverview ? 1.0 : 0.35)
                }

                if isGraphMode, tabs.indices.contains(selectedTabIndex) {
                    let currentMode = tabs[selectedTabIndex].automationMode
                    AutomationScopeControl(
                        mode: currentMode,
                        onTapAllTabs: { onSetAutomationMode(.universal) },
                        onTapThisTab: { onSetAutomationMode(.perTab) },
                        onOpenPopover: { showAutomationScopePopover = true }
                    )
                    .popover(isPresented: $showAutomationScopePopover, arrowEdge: .bottom) {
                        AutomationScopePopover(
                            currentTabName: tabs[selectedTabIndex].name,
                            currentMode: currentMode,
                            rows: tabs.map { tab in
                                AutomationScopePopover.TabRow(
                                    id: tab.id,
                                    name: tab.name,
                                    mode: tab.automationMode,
                                    isCurrent: tab.id == tabs[selectedTabIndex].id
                                )
                            },
                            showPrimer: !automationScopePrimerShown,
                            onSelectRow: { onSelectAutomationScopeForTab($0) },
                            onContextualAction: {
                                showAutomationScopePopover = false
                                onAutomationContextualAction()
                            },
                            onShowPrimer: { automationScopePrimerShown = false }
                        )
                        .onAppear { automationScopePrimerShown = true }
                    }
                }

                #if os(iOS)
                if canUndo || canRedo {
                    toolbarClusterDivider(height: iconH * 0.6)
                        .transition(.scale(scale: 0.2, anchor: .center).combined(with: .opacity))
                }

                Group {
                    if canUndo {
                        Button {
                            onUndo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .imageScale(iconScale)
                                .foregroundStyle(toolbarForeground)
                                .frame(width: iconW, height: iconH)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                                .toolbarIconChrome(isActive: false)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }

                    if canRedo {
                        Button {
                            onRedo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .imageScale(iconScale)
                                .foregroundStyle(toolbarForeground)
                                .frame(width: iconW, height: iconH)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                                .toolbarIconChrome(isActive: false)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: canUndo)
                .animation(.easeInOut(duration: 0.18), value: canRedo)
                #endif
            }
                #if os(iOS)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .pillHUDSurface(strokeOpacity: 0.08, disableBackgroundExtension: true)
                .frostedGlassSurface()
                #endif

                Spacer(minLength: 8)

                // MARK: - Middle cluster (tabs)
                Group {
                    if isGraphMode {
                    HStack(spacing: 8) {
                        ZStack {
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                                .liquidGlassSelectedSegment()
                                .matchedGeometryEffect(id: "tabSelectionPill", in: tabSelectionNamespace)
                                .animation(selectionPillAnimation, value: selectedTabID)

                            Text(selectedTabSafe?.name ?? "")
                                .font(barFont)
                                .foregroundStyle(toolbarForeground)
                                .padding(.horizontal, tabHPad)
                                .padding(.vertical, tabVPad)
                        }
                    }
                    .frame(height: tabsStripHeight)
                    .tutorialAnchor("root.tabs")
                } else {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                    ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, _ in
                                        let isMirror = (tabs[idx].lanMirrorShareId != nil)
                                        let isSelected = (idx == selectedTabIndex)
                                        let tabID = tabs[idx].id
                                        let isPillSelected = isSelected && selectedLANShareId == nil

                                        if renamingTabID == tabID {
                                            ZStack {
                                                TextField("Tab name", text: $renamingDraftName)
                                                    .focused($focusedRenameTabID, equals: tabID)
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(barFont)
                                                    .frame(minWidth: 80, maxWidth: 160)
                                                    .onSubmit {
                                                        commitRename(at: idx, tabID: tabID)
                                                    }
                                                    #if os(macOS)
                                                    .onExitCommand {
                                                        // Escape cancels rename.
                                                        cancelRename()
                                                    }
                                                    #endif
                                            }
                                        } else {
                                            ZStack {
                                                Button {
                                                    guard renamingTabID == nil else { return }

                                                    let old = selectedTabIndex
                                                    lastSelectedTabIndex = old

                                                    focusedRenameTabID = nil
                                                    selectedLANShareId = nil
                                                    selectedLANDeviceName = nil

                                                    triggerSelectionPulse(from: old, to: idx)

                                                    withAnimation(selectionPillAnimation) {
                                                        selectedTabIndex = idx
                                                    }
                                                } label: {
                                                    ZStack {
                                                        if isPillSelected {
                                                            Capsule()
                                                                .fill(Color.white.opacity(0.10))
                                                                .liquidGlassSelectedSegment()
                                                                .matchedGeometryEffect(id: "tabSelectionPill", in: tabSelectionNamespace)
                                                                .scaleEffect(
                                                                    x: isSelectionPulsing ? 1.10 : 1.0,
                                                                    y: isSelectionPulsing ? 0.94 : 1.0,
                                                                    anchor: (selectionPulseDirection >= 0) ? .leading : .trailing
                                                                )
                                                                .animation(selectionPillAnimation, value: selectedTabID)
                                                                .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isSelectionPulsing)
                                                                .allowsHitTesting(false)
                                                        }

                                                        // Keep the label height stable; render the close button as an overlay so it can't change intrinsic height.
                                                        let baseLabel = HStack(spacing: 8) {
                                                            HStack(spacing: 5) {
                                                                localTabSyncMirrorBadge(idx: idx, isSelected: isSelected, toolbarForeground: toolbarForeground)
                                                                Text(tabs[idx].name)
                                                                    .font(barFont)
                                                                    .foregroundStyle(toolbarForeground.opacity(isSelected ? 1.0 : 0.82))
                                                                    .lineLimit(1)
                                                                if isSelected && canvasSize.width > 0 {
                                                                    Text("\(Int(canvasSize.width))×\(Int(canvasSize.height))")
                                                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                                                        .foregroundStyle(toolbarForeground.opacity(canvasSize != documentDefaultCanvasSize ? 0.65 : 0.38))
                                                                }
                                                            }
                                                            .padding(.trailing, ((!isMirror && localNonMirrorTabCount > 1) ? 18 : 0)) // reserve space for the close button so text never sits underneath it
                                                        }
                                                        .padding(.horizontal, tabHPad)
                                                        .padding(.vertical, tabVPad)
                                                        .frame(height: tabsStripHeight)

                                                        baseLabel
                                                        .overlay(alignment: .trailing) {
                                                            if !isMirror && localNonMirrorTabCount > 1 {
                                                                    #if os(macOS)
                                                                    let showClose = isSelected || (hoveringLocalTabID == tabID)
                                                                    #else
                                                                    let showClose = isSelected
                                                                    #endif

                                                                    Button {
                                                                        requestDeleteTab(at: idx)
                                                                    } label: {
                                                                        Image(systemName: "xmark")
                                                                            .font(.caption2.weight(.semibold))
                                                                            .opacity(showClose ? 0.70 : 0.0)
                                                                            .contentShape(Rectangle())
                                                                    }
                                                                    .buttonStyle(.plain)
                                                                    .frame(width: 18, height: 18)
                                                                    .padding(.trailing, max(2, tabHPad - 6))
                                                                    .accessibilityLabel("Delete Tab")
                                                                    .allowsHitTesting(showClose)
                                                                }
                                                            }
                                                    }
                                                }
                                                .buttonStyle(.plain)
#if os(macOS)
                                                .onHover { hovering in
                                                    hoveringLocalTabID = hovering ? tabID : (hoveringLocalTabID == tabID ? nil : hoveringLocalTabID)
                                                }
#endif
                                                .allowsHitTesting(renamingTabID == nil)
                                            }
                                            .contentShape(Capsule())
                                            .background(
                                                GeometryReader { proxy in
                                                    Color.clear.preference(
                                                        key: LocalTabFramePreferenceKey.self,
                                                        value: [tabID: proxy.frame(in: .named("LocalTabsStrip"))]
                                                    )
                                                }
                                            )
                                            .contextMenu {
                                                // Disable menu entirely while renaming
                                                if renamingTabID == nil {
                                                    if !isMirror {
                                                        Button {
                                                            // Defer until after the context menu dismisses.
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                                let currentName = tabs.indices.contains(idx) ? tabs[idx].name : ""
                                                                beginRename(tabID: tabID, currentName: currentName)
                                                            }
                                                        } label: {
                                                            Label("Rename Tab", systemImage: "pencil")
                                                        }
                                                        Button { duplicateTab(idx) } label: { Label("Duplicate Tab", systemImage: "square.on.square") }
                                                        Button(role: .destructive) { deleteTab(idx) } label: { Label("Delete Tab", systemImage: "trash") }
                                                        Divider()
                                                        Button {
                                                            presentCanvasSizeForTab(idx)
                                                        } label: {
                                                            Label("Canvas Size…", systemImage: "aspectratio")
                                                        }
                                                        Divider()
                                                        if tabs.indices.contains(idx), tabs[idx].syncGroupID != nil {
                                                            let isOrphanedSubscriber = !tabs[idx].syncIsOwner && lanService.orphanedSyncGroupIDs.contains(tabs[idx].syncGroupID ?? "")
                                                            if isOrphanedSubscriber {
                                                                Button {
                                                                    reconnectSyncedTab(idx)
                                                                } label: {
                                                                    Label("Reconnect to Host", systemImage: "arrow.triangle.2.circlepath")
                                                                }
                                                            }
                                                            Button {
                                                                let isSubscriber = tabs.indices.contains(idx) && !tabs[idx].syncIsOwner
                                                                if isOrphanedSubscriber || !isSubscriber {
                                                                    stopSyncingTab(idx)
                                                                } else {
                                                                    requestDeleteTab(at: idx)
                                                                }
                                                            } label: {
                                                                Label(isOrphanedSubscriber ? "Keep as Local" : "Disconnect from Sync", systemImage: "link.badge.minus")
                                                            }
                                                        } else {
                                                            Button {
                                                                makeSyncedTab(idx)
                                                            } label: {
                                                                Label("Make Synced Tab", systemImage: "arrow.triangle.2.circlepath")
                                                            }
                                                        }
                                                    } else {
                                                        Text("LAN mirrored tab")
                                                        Button(role: .destructive) { deleteTab(idx) } label: { Label("Delete Tab", systemImage: "trash") }
                                                    }
                                                }
                                            }
                                            .onDrag {
                                                guard renamingTabID == nil else { return NSItemProvider() }
                                                draggingLocalTabID = tabID
                                                return NSItemProvider(object: tabID.uuidString as NSString)
                                            }
                                            .onDrop(of: [UTType.text], delegate: LocalTabDropDelegate(
                                                targetID: tabID,
                                                onReorder: { dragged, target in
                                                    reorderLocalTabs(dragged, target)
                                                },
                                                draggingID: $draggingLocalTabID
                                            ))
                                        }
                                    }

                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear
                                                .preference(key: TabsScrollContentWidthKey.self, value: proxy.size.width)
                                                .preference(key: TabsScrollMinXKey.self, value: proxy.frame(in: .named("tabsScroll")).minX)
                                        }
                                    )
                                }
                                .coordinateSpace(.named("tabsScroll"))
                                // `axes:` defaults to `.vertical` -- must be explicit for a
                                // `ScrollView(.horizontal)`, or this hides nothing (the tab
                                // strip's scrollbar was visibly showing again after the
                                // `showsIndicators: false` -> `.scrollIndicators(.hidden)`
                                // conversion until this was added).
                                .scrollIndicators(.hidden, axes: .horizontal)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(key: TabsScrollContainerWidthKey.self, value: proxy.size.width)
                                    }
                                )
                                .modifier(ScrollGeometryObserver(
                                    contentWidth: $tabsScrollContentWidth,
                                    containerWidth: $tabsScrollContainerWidth,
                                    minX: $tabsScrollMinX
                                ))
                                .onPreferenceChange(LocalTabFramePreferenceKey.self) { localTabFrames = $0 }

                                let maxOffset = max(0, tabsScrollContentWidth - tabsScrollContainerWidth)
                                let offsetX = -tabsScrollMinX
                                let hasOverflow = maxOffset > 2
                                let showLeftFade = hasOverflow && offsetX > 2
                                let showRightFade = hasOverflow && offsetX < (maxOffset - 2)
                                if showLeftFade || showRightFade {
                                    let fadeWidth: CGFloat = 64
                                    let fadeColor = colorScheme == .dark
                                        ? Color.white.opacity(0.045)
                                        : Color.black.opacity(0.045)
                                    HStack(spacing: 0) {
                                        if showLeftFade {
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [fadeColor, Color.clear],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: fadeWidth, height: tabsStripHeight)
                                        } else {
                                            Color.clear.frame(width: fadeWidth, height: tabsStripHeight)
                                        }
                                        Spacer()
                                        if showRightFade {
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.clear, fadeColor],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: fadeWidth, height: tabsStripHeight)
                                        } else {
                                            Color.clear.frame(width: fadeWidth, height: tabsStripHeight)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .allowsHitTesting(false)
                                    .zIndex(1)
                                }
                            }
                            .coordinateSpace(.named("LocalTabsStrip"))
                        }
                        .onPreferenceChange(TabsScrollContentWidthKey.self) { value in
                            if #available(iOS 17.0, macOS 14.0, *) {
                                return
                            }
                            tabsScrollContentWidth = value
                        }
                        .onPreferenceChange(TabsScrollContainerWidthKey.self) { value in
                            if #available(iOS 17.0, macOS 14.0, *) {
                                return
                            }
                            tabsScrollContainerWidth = value
                        }
                        .onPreferenceChange(TabsScrollMinXKey.self) { value in
                            if #available(iOS 17.0, macOS 14.0, *) {
                                return
                            }
                            tabsScrollMinX = value
                        }
                        // While renaming, avoid implicit animations that can look like flicker on glass materials.
                        .transaction { txn in
                            if isRenamingTab {
                                txn.disablesAnimations = true
                            }
                        }
                        .frame(height: tabsStripHeight)
                        .clipped()
                        .layoutPriority(1)

                        let hasSynced = !lanService.syncedRemoteManifests.isEmpty
                        let hasLAN = lanSharingEnabled && !lanRemoteTabsForUI.isEmpty
                        if hasSynced || hasLAN {
                            Rectangle()
                                .fill(toolbarForeground.opacity(0.25))
                                .frame(width: 1, height: tabsStripHeight * 0.65)
                                .allowsHitTesting(false)
                            if hasSynced {
                                syncedTabsMenuButton(
                                    lanService.syncedRemoteManifests,
                                    tabHPad: tabHPad,
                                    tabVPad: tabVPad,
                                    toolbarForeground: toolbarForeground,
                                    tabsStripHeight: tabsStripHeight
                                )
                            }
                            if hasLAN {
                                lanMirrorMenuButton(
                                    lanRemoteTabsForUI,
                                    tabHPad: tabHPad,
                                    tabVPad: tabVPad,
                                    toolbarForeground: toolbarForeground,
                                    tabsStripHeight: tabsStripHeight
                                )
                            }
                        }

                        Button {
                            addTab()
                        } label: {
                            Image(systemName: "plus.square.on.square")
                                .imageScale(iconScale)
                                .frame(width: iconW, height: iconH)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 720)
                    .frame(height: tabsStripHeight)
                    .tutorialAnchor("root.tabs")

                    saveStatusLabel
                        .animation(.easeInOut(duration: 0.2), value: saveState.isSaving)
                        .animation(.easeInOut(duration: 0.2), value: savedLabelVisible)
                }
                }

                Spacer(minLength: 8)

                // MARK: - Right cluster
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isLiveMode.toggle()
                        }
                    } label: {
                        Image(systemName: "play.rectangle")
                            .imageScale(iconScale)
                            .foregroundStyle(isLiveMode ? Color.accentColor : toolbarForeground)
                            .frame(width: iconW, height: iconH)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .toolbarIconChrome(isActive: isLiveMode)
                            .tutorialAnchor("root.liveMode")
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingPCOConfigForTab = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            DashboardSymbolImage("slider.horizontal.below.rectangle")
                                .imageScale(iconScale)
                                .foregroundStyle(toolbarForeground)
                                .frame(width: iconW, height: iconH)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                                .toolbarIconChrome(isActive: false)
                                .tutorialAnchor("root.tabSettings")
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingRosters = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            DashboardSymbolImage("list.dash.badge.ellipsis")
                                .imageScale(iconScale)
                                .foregroundStyle(toolbarForeground)
                                .frame(width: iconW, height: iconH)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                                .toolbarIconChrome(isActive: false)
                                .tutorialAnchor("root.rosters")
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        toggleGraphCanvas()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            DashboardSymbolImage(isGraphMode ? "square.grid.2x2" : "point.3.connected.trianglepath.dotted")
                                .imageScale(iconScale)
                                .foregroundStyle(isGraphMode ? Color.accentColor : toolbarForeground)
                                .frame(width: iconW, height: iconH)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                                .toolbarIconChrome(isActive: isGraphMode)

                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(isGraphMode ? "Switch to Canvas View" : "Automation")
                        .accessibilityHint(
                            "Switches between dashboard canvas and automation view."
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(mirrorSelected)
                    .opacity(mirrorSelected ? 0.35 : 1.0)
                    .help(isGraphMode ? "Switch to Canvas View" : "Switch to Graph View")
                    .tutorialAnchor("root.graphToggle")

                    Button {
                        editingTileID = nil
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .imageScale(iconScale)
                            .foregroundStyle(toolbarForeground)
                            .frame(width: iconW, height: iconH)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .toolbarIconChrome(isActive: false)
                    }
                    .buttonStyle(.plain)
                    .tutorialAnchor("root.settings")

                    if !isGraphMode {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if isInspectorVisible {
                                    isInspectorVisible = false
                                    editingTileID = nil
                                    clearEditFocusOffsetsX()
                                } else {
                                    if let currentEditing = bindingForEditingTile(),
                                       selectedTileIDs.contains(currentEditing.wrappedValue.id) {
                                        let id = currentEditing.wrappedValue.id
                                        isInspectorVisible = true
                                        focusTileForInspector(id)
                                    } else if let firstSelectedID = selectedTileIDs.first {
                                        editingTileID = firstSelectedID
                                        isInspectorVisible = true
                                        focusTileForInspector(firstSelectedID)
                                    }
                                }
                            }
                        } label: {
                            DashboardSymbolImage("sidebar.trailing")
                                .imageScale(iconScale)
                                .foregroundStyle(isInspectorVisible ? Color.accentColor : toolbarForeground)
                                .frame(width: iconW, height: iconH)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                                .toolbarIconChrome(isActive: isInspectorVisible)
                                .tutorialAnchor("root.inspectorButton")
                        }
                        .buttonStyle(.plain)
                        .disabled(mirrorSelected || !canToggleInspector)
                        .opacity((mirrorSelected || !canToggleInspector) ? 0.35 : 1.0)
                    }
                }
                .layoutPriority(2)
            }
            .frame(minHeight: tabsStripHeight)
        #if os(iOS)
            .controlSize(.small)
            #endif
            .padding(.horizontal, toolbarHPad)
            .padding(.vertical, toolbarVPad)


            // Keyboard shortcuts (keep behavior the same)
            Button(action: { deleteSelectedTiles() }) { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [])
                .buttonStyle(.plain)
                .opacity(0)
                .allowsHitTesting(false)

            Button(action: {}) { EmptyView() }
                .buttonStyle(.plain)
                .opacity(0)
                .allowsHitTesting(false)

            // (removed Spacer at the bottom for pill HUD)
        }

        #if os(macOS)
        ZStack(alignment: .top) {
            // Invisible hot zone at the very top edge to reveal the pill.
            Color.clear
                .frame(height: usesPillHUD ? hotZoneHeight : 0)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard usesPillHUD else { return }
                    guard renamingTabID == nil else { return }
                    if hovering {
                        hideTask?.cancel()
                        hideTask = nil
                        showPillHUD()
                    }
                }
                .onTapGesture {
                    guard usesPillHUD else { return }
                    guard renamingTabID == nil else { return }
                    hideTask?.cancel()
                    hideTask = nil
                    showPillHUD()
                    
                    guard autoHideEnabled else { return }
                    scheduleAutoHidePillHUD(after: max(4.0, autoHideDelay))
                }
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            guard usesPillHUD else { return }
                            guard renamingTabID == nil else { return }
                            // Only treat downward drags as “reveal”.
                            if value.translation.height > 6 {
                                hideTask?.cancel()
                                hideTask = nil
                                showPillHUD()
                            }
                        }
                        .onEnded { value in
                            guard usesPillHUD else { return }
                            guard renamingTabID == nil else { return }
                            guard autoHideEnabled else { return }
                            
                            if value.translation.height > 6 {
                                scheduleAutoHidePillHUD(after: max(4.0, autoHideDelay))
                            }
                        }
                )

            if !usesPillHUD || isPillVisible {
                toolbarContent
                    .tutorialAnchor("root.toolbar")
                    // While renaming, avoid implicit animations that can look like flicker on glass materials.
                    .transaction { txn in
                        if isRenamingTab {
                            txn.disablesAnimations = true
                        }
                    }
                    // Avoid material flash when selection chip appears/disappears.
                    .animation(nil, value: selectedTileIDs.count)
                    .padding(.horizontal, toolbarHPad)
                    .padding(.vertical, max(4, toolbarVPad - 2))
                    .pillHUDSurface(strokeOpacity: 0.10, disableBackgroundExtension: isRenamingTab)
                    .frostedGlassSurface()
                    .accessibilityIdentifier("DashboardTopToolbarPillHUD")
                    .padding(.top, 10)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 900)
                    .onHover { hovering in
                        guard usesPillHUD else { return }
                        guard renamingTabID == nil else { return }

                        isHoveringPill = hovering

                        if hovering {
                            hideTask?.cancel()
                            hideTask = nil
                            showPillHUD()
                        } else {
                            guard !isFlipHoldActive else { return }
                            guard autoHideEnabled else { return }

                            scheduleAutoHidePillHUD(after: autoHideDelay)
                        }
                    }
                    .transition(pillTransition)
            }
        }
        .onAppear {
            guard usesPillHUD else { return }
            guard renamingTabID == nil else { return }

            // Show on launch so users discover there is a menu.
            isPillVisible = true

            // Optionally auto-hide after a short delay (unless hovering).
            guard autoHideEnabled else { return }
            scheduleAutoHidePillHUD(after: max(0.8, autoHideDelay))
        }
        .onChange(of: autoHideEnabled, initial: false) { _, enabled in
            guard usesPillHUD else { return }
            if !enabled {
                hideTask?.cancel()
                hideTask = nil
                showPillHUD()
                return
            }

            guard renamingTabID == nil else { return }

            // Toggling the command from the macOS menu bar can bypass the pill's hover-exit callback,
            // leaving stale hover state that would otherwise block every auto-hide path.
            isHoveringPill = false
            scheduleAutoHidePillHUD(after: max(0.8, autoHideDelay))
        }
        .onChange(of: isGraphMode, initial: false) { _, enabled in
            if usesPillHUD {
                beginFlipHold()
            }
            if !enabled {
                showAutomationScopePopover = false
            }
        }
        .onChange(of: saveState.isSaving) { _, saving in
            if !saving {
                savedLabelVisible = true
                savedHideTask?.cancel()
                savedHideTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.0))
                    guard !Task.isCancelled else { return }
                    withAnimation { savedLabelVisible = false }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Relay.GraphSendAllAvailability"))) { note in
            if let available = note.object as? Bool {
                // Avoid disturbing inline tab rename focus/caret with frequent external publishes.
                guard !isRenamingTab else { return }
                canSendAllToConsoles = available
            }
        }
        .onChange(of: lanSharingEnabled, initial: false) { _, enabled in
            guard !enabled else { return }

            // Drop any stale LAN UI immediately when sharing is turned off.
            lanService.clearDiscoveredState()

            // If we were mirroring a LAN tab, clear selection so the UI reflects disabled state.
            if selectedLANShareId != nil {
                clearLANMirrorSelection()
            }
        }
        .confirmationDialog(
            {
                let isSubscriber = pendingDeleteLocalTabIndex.map { idx in
                    tabs.indices.contains(idx) && tabs[idx].syncGroupID != nil && !tabs[idx].syncIsOwner
                } ?? false
                return isSubscriber ? "Disconnect from sync?" : "Delete this tab?"
            }(),
            isPresented: $showDeleteTabConfirm,
            titleVisibility: .visible
        ) {
            let isSubscriber = pendingDeleteLocalTabIndex.map { idx in
                tabs.indices.contains(idx) && tabs[idx].syncGroupID != nil && !tabs[idx].syncIsOwner
            } ?? false
            if isSubscriber {
                Button("Keep as Local") {
                    if let idx = pendingDeleteLocalTabIndex { stopSyncingTab(idx) }
                    pendingDeleteLocalTabIndex = nil
                }
                Button("Remove Tab", role: .destructive) {
                    if let idx = pendingDeleteLocalTabIndex { deleteTab(idx) }
                    pendingDeleteLocalTabIndex = nil
                }
            } else {
                Button("Delete Tab", role: .destructive) {
                    if let idx = pendingDeleteLocalTabIndex { deleteTab(idx) }
                    pendingDeleteLocalTabIndex = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteLocalTabIndex = nil
            }
        } message: {
            if let idx = pendingDeleteLocalTabIndex, tabs.indices.contains(idx) {
                let isSubscriber = tabs[idx].syncGroupID != nil && !tabs[idx].syncIsOwner
                if isSubscriber {
                    Text("You’ll stop receiving updates from ‘\(tabs[idx].name)’. Keep a local copy or remove it.")
                } else {
                    Text("This will permanently delete ‘\(tabs[idx].name)’.")
                }
            }
        }
        .onDisappear {
            cancelAllScheduledToolbarTasks()
        }
        #else
        // iOS/iPadOS:
        ZStack {
            Color.clear
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isPad {
                ZStack(alignment: .top) {
                    // Hot zone (tiny, top edge only): tap OR one-finger swipe-down to reveal the toolbar.
                    ZStack {
                        Color.clear

                        OneFingerTopEdgePanCapture(
                            onBegan: {
                                // Reveal immediately when the swipe begins.
                                showIPadToolbar()
                            },
                            onEnded: { translation in
                                // Only treat downward drags as “reveal”.
                                // (Upward swipes do nothing.)
                                if translation.y > 6 {
                                    showIPadToolbar()
                                    // Keep it visible for ~4s, then auto-hide again (if enabled).
                                    scheduleIPadAutoHideIfNeeded(delay: 4.0)
                                } else {
                                    // If it was already visible, keep normal behavior.
                                    scheduleIPadAutoHideIfNeeded(delay: 2.0)
                                }
                            }
                        )
                    }
                    .frame(height: (iPadAutoHideToolbarEnabled && !isTutorialPresented) ? 50 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showIPadToolbar()
                        scheduleIPadAutoHideIfNeeded(delay: 4.0)
                    }

                    if isTutorialPresented || !iPadAutoHideToolbarEnabled || isIPadToolbarVisible {
                        iPadFloatingToolbarOverlay(
                            mirrorSelected: mirrorSelected,
                            lanRemoteTabsForUI: lanRemoteTabsForUI,
                            localNonMirrorTabCount: localNonMirrorTabCount,
                            iconScale: iconScale,
                            barFont: barFont,
                            tabHPad: tabHPad,
                            tabVPad: tabVPad,
                            toolbarForeground: toolbarForeground,
                            iconW: iconW,
                            iconH: iconH,
                            tabsStripHeight: tabsStripHeight
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            isIPadToolbarVisible = true
                            scheduleIPadAutoHideIfNeeded(delay: 4.0)
                        }
                    }
                }
            } else {
                toolbarContent
                    .tutorialAnchor("root.toolbar")
                    .overlay(alignment: .topLeading) {
                        Text("toolbar debug")
                            .font(.caption2)
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Capsule())
                            .offset(y: -18)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: 920)
                    .pillHUDSurface(strokeOpacity: 0.08)
                    .frostedGlassSurface()
                    .shadow(radius: 8)
                    .padding(.bottom, 8)
            }
        }
        .onChange(of: selectedTabIndex, initial: false) { oldValue, newValue in
            let clampedOld = min(max(oldValue, 0), max(0, tabs.count - 1))
            let clampedNew = min(max(newValue, 0), max(0, tabs.count - 1))

            if clampedOld != clampedNew {
                lastSelectedTabIndex = clampedOld
                triggerSelectionPulse(from: clampedOld, to: clampedNew)
            }
        }
        .onChange(of: isTutorialPresented, initial: false) { _, isPresented in
            if isPresented {
                iPadHideTask?.cancel()
                showIPadToolbar()
            } else {
                scheduleIPadAutoHideIfNeeded(delay: 2.0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Relay.GraphSendAllAvailability"))) { note in
            if let available = note.object as? Bool {
                canSendAllToConsoles = available
            }
        }
        .onChange(of: lanSharingEnabled, initial: false) { _, enabled in
            guard !enabled else { return }

            // Drop any stale LAN UI immediately when sharing is turned off.
            lanService.clearDiscoveredState()

            // If we were mirroring a LAN tab, clear selection so the UI reflects disabled state.
            if selectedLANShareId != nil {
                clearLANMirrorSelection()
            }
        }
        .confirmationDialog(
            {
                let isSubscriber = pendingDeleteLocalTabIndex.map { idx in
                    tabs.indices.contains(idx) && tabs[idx].syncGroupID != nil && !tabs[idx].syncIsOwner
                } ?? false
                return isSubscriber ? "Disconnect from sync?" : "Delete this tab?"
            }(),
            isPresented: $showDeleteTabConfirm,
            titleVisibility: .visible
        ) {
            let isSubscriber = pendingDeleteLocalTabIndex.map { idx in
                tabs.indices.contains(idx) && tabs[idx].syncGroupID != nil && !tabs[idx].syncIsOwner
            } ?? false
            if isSubscriber {
                Button("Keep as Local") {
                    if let idx = pendingDeleteLocalTabIndex { stopSyncingTab(idx) }
                    pendingDeleteLocalTabIndex = nil
                }
                Button("Remove Tab", role: .destructive) {
                    if let idx = pendingDeleteLocalTabIndex { deleteTab(idx) }
                    pendingDeleteLocalTabIndex = nil
                }
            } else {
                Button("Delete Tab", role: .destructive) {
                    if let idx = pendingDeleteLocalTabIndex { deleteTab(idx) }
                    pendingDeleteLocalTabIndex = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteLocalTabIndex = nil
            }
        } message: {
            if let idx = pendingDeleteLocalTabIndex, tabs.indices.contains(idx) {
                let isSubscriber = tabs[idx].syncGroupID != nil && !tabs[idx].syncIsOwner
                if isSubscriber {
                    Text("You’ll stop receiving updates from ‘\(tabs[idx].name)’. Keep a local copy or remove it.")
                } else {
                    Text("This will permanently delete ‘\(tabs[idx].name)’.")
                }
            }
        }
        .onDisappear {
            cancelAllScheduledToolbarTasks()
        }
        #endif
    }
    #if os(iOS)
    @ViewBuilder
    private func iPadFloatingToolbarOverlay(
        mirrorSelected: Bool,
        lanRemoteTabsForUI: [LANSharedTabManifest],
        localNonMirrorTabCount: Int,
        iconScale: Image.Scale,
        barFont: Font,
        tabHPad: CGFloat,
        tabVPad: CGFloat,
        toolbarForeground: Color,
        iconW: CGFloat,
        iconH: CGFloat,
        tabsStripHeight: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {

            // Leading cluster (no background)
            HStack(spacing: 8) {
                commandsMenu()

                if !isGraphMode {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isTileOverviewVisible.toggle()
                        }
                    } label: {
                        DashboardSymbolImage("sidebar.leading")
                            .imageScale(iconScale)
                            .foregroundStyle(isTileOverviewVisible ? Color.accentColor : toolbarForeground)
                            .frame(width: iconW, height: iconH)
                            .toolbarIconChrome(isActive: isTileOverviewVisible)
                            .tutorialAnchor("root.overviewButton")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canToggleOverview)
                    .opacity(canToggleOverview ? 1.0 : 0.35)
                }

                if canUndo || canRedo {
                    toolbarClusterDivider(height: iconH * 0.6)
                        .transition(.scale(scale: 0.2, anchor: .center).combined(with: .opacity))
                }

                Group {
                    if canUndo {
                        Button {
                            onUndo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .imageScale(iconScale)
                                .foregroundStyle(toolbarForeground)
                                .frame(width: iconW, height: iconH)
                                .toolbarIconChrome(isActive: false)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }

                    if canRedo {
                        Button {
                            onRedo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .imageScale(iconScale)
                                .foregroundStyle(toolbarForeground)
                                .frame(width: iconW, height: iconH)
                                .toolbarIconChrome(isActive: false)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: canUndo)
                .animation(.easeInOut(duration: 0.18), value: canRedo)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .pillHUDSurface(strokeOpacity: 0.10, disableBackgroundExtension: true)
            .frostedGlassSurface()

            Spacer(minLength: 6)

            // Center cluster (tabs) in a capsule
            Group {
                if isGraphMode {
                    Text(selectedTabSafe?.name ?? "")
                        .font(barFont)
                        .foregroundStyle(toolbarForeground)
                        .lineLimit(1)
                        .padding(.horizontal, tabHPad)
                        .padding(.vertical, tabVPad)
                } else {
                    HStack(spacing: 8) {
                        ZStack {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, _ in
                                        let isMirror = (tabs[idx].lanMirrorShareId != nil)
                                        let isSelected = (idx == selectedTabIndex)
                                        let tabID = tabs[idx].id
                                        let isPillSelected = (tabID == selectedTabID)

                                        Button {
                                            let old = selectedTabIndex
                                            lastSelectedTabIndex = old

                                            selectedLANShareId = nil
                                            selectedLANDeviceName = nil

                                            triggerSelectionPulse(from: old, to: idx)

                                            withAnimation(.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.10)) {
                                                selectedTabIndex = idx
                                            }
                                        } label: {
                                            // --- BEGIN PATCHED LABEL CONTENT ---
                                            ZStack {
                                                if isPillSelected && selectedLANShareId == nil {
                                                            Capsule()
                                                                .fill(Color.white.opacity(0.10))
                                                                .liquidGlassSelectedSegment()
                                                                .matchedGeometryEffect(id: "tabSelectionPill", in: tabSelectionNamespace)
                                                                .animation(selectionPillAnimation, value: selectedTabID)
                                                        .allowsHitTesting(false)
                                                }

                                                // Keep the label height stable; render the close button as an overlay so it can't change intrinsic height.
                                                let baseLabel = HStack(spacing: 8) {
                                                    HStack(spacing: 5) {
                                                        localTabSyncMirrorBadge(idx: idx, isSelected: isSelected, toolbarForeground: toolbarForeground)
                                                        Text(tabs[idx].name)
                                                            .font(barFont)
                                                            .foregroundStyle(toolbarForeground.opacity(isSelected ? 1.0 : 0.82))
                                                            .lineLimit(1)
                                                    }
                                                    .padding(.trailing, ((!isMirror && localNonMirrorTabCount > 1) ? 18 : 0)) // reserve space for the close button so text never sits underneath it
                                                }
                                                .padding(.horizontal, tabHPad)
                                                .padding(.vertical, tabVPad)
                                                .frame(height: tabsStripHeight)

                                                baseLabel
                                                    .overlay(alignment: .trailing) {
                                                        if !isMirror && localNonMirrorTabCount > 1 {
                                                            let showClose = isSelected

                                                            Button {
                                                                requestDeleteTab(at: idx)
                                                            } label: {
                                                                Image(systemName: "xmark")
                                                                    .font(.caption2.weight(.semibold))
                                                                    .opacity(showClose ? 0.70 : 0.0)
                                                                    .contentShape(Rectangle())
                                                            }
                                                            .buttonStyle(.plain)
                                                            .frame(width: 18, height: 18)
                                                            .padding(.trailing, max(2, tabHPad - 6))
                                                            .accessibilityLabel("Delete Tab")
                                                            .allowsHitTesting(showClose)
                                                        }
                                                    }
                                            }
                                            // --- END PATCHED LABEL CONTENT ---
                                        }
                                        .buttonStyle(.plain)
                                        .contentShape(Capsule())
                                        .contextMenu {
                                            if !isMirror {
                                                Button { duplicateTab(idx) } label: { Label("Duplicate Tab", systemImage: "square.on.square") }
                                                Button(role: .destructive) { deleteTab(idx) } label: { Label("Delete Tab", systemImage: "trash") }
                                                Divider()
                                                Button {
                                                    presentCanvasSizeForTab(idx)
                                                } label: {
                                                    Label("Canvas Size…", systemImage: "aspectratio")
                                                }
                                                Divider()
                                                if tabs.indices.contains(idx), tabs[idx].syncGroupID != nil {
                                                    Button {
                                                        if tabs[idx].syncIsOwner {
                                                            stopSyncingTab(idx)
                                                        } else {
                                                            requestDeleteTab(at: idx)
                                                        }
                                                    } label: {
                                                        Label("Stop Syncing", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                                                    }
                                                } else {
                                                    Button {
                                                        makeSyncedTab(idx)
                                                    } label: {
                                                        Label("Make Synced Tab", systemImage: "arrow.triangle.2.circlepath")
                                                    }
                                                }
                                            } else {
                                                Text("LAN mirrored tab")
                                                Button(role: .destructive) { deleteTab(idx) } label: { Label("Delete Tab", systemImage: "trash") }
                                            }
                                        }
                                    }

                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(height: tabsStripHeight)
                                .padding(.horizontal, 2)
                            }
                            // See the matching comment on the other tab-strip ScrollView above:
                            // `axes:` defaults to `.vertical`, so it must be explicit here too.
                            .scrollIndicators(.hidden, axes: .horizontal)
                        }
                        .frame(maxWidth: 720 - iconW - 8)
                        .frame(height: tabsStripHeight)
                        .clipped()

                        Button { addTab() } label: {
                            Image(systemName: "plus.square.on.square")
                                .imageScale(iconScale)
                                .frame(width: iconW, height: iconH)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 720)
                    .frame(height: tabsStripHeight)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .pillHUDSurface(strokeOpacity: 0.10, disableBackgroundExtension: true)
            .tutorialAnchor("root.tabs")

            let hasSynced = !lanService.syncedRemoteManifests.isEmpty
            let hasLAN = lanSharingEnabled && !lanRemoteTabsForUI.isEmpty
            if hasSynced || hasLAN {
                HStack(spacing: 4) {
                    if hasSynced {
                        syncedTabsMenuButton(
                            lanService.syncedRemoteManifests,
                            tabHPad: tabHPad,
                            tabVPad: tabVPad,
                            toolbarForeground: toolbarForeground,
                            tabsStripHeight: tabsStripHeight
                        )
                    }
                    if hasLAN {
                        lanMirrorMenuButton(
                            lanRemoteTabsForUI,
                            tabHPad: tabHPad,
                            tabVPad: tabVPad,
                            toolbarForeground: toolbarForeground,
                            tabsStripHeight: tabsStripHeight
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .pillHUDSurface(strokeOpacity: 0.10, disableBackgroundExtension: true)
            }

            Spacer(minLength: 6)

            // Trailing cluster in a capsule
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isLiveMode.toggle()
                    }
                } label: {
                    Image(systemName: "play.rectangle")
                        .imageScale(iconScale)
                        .foregroundStyle(isLiveMode ? Color.accentColor : toolbarForeground)
                        .frame(width: iconW, height: iconH)
                        .toolbarIconChrome(isActive: isLiveMode)
                        .tutorialAnchor("root.liveMode")
                }
                .buttonStyle(.plain)

                Button {
                    showingPCOConfigForTab = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        DashboardSymbolImage("slider.horizontal.below.rectangle")
                            .imageScale(iconScale)
                            .foregroundStyle(toolbarForeground)
                            .frame(width: iconW, height: iconH)
                            .toolbarIconChrome(isActive: false)
                    }
                }
                .buttonStyle(.plain)
                .tutorialAnchor("root.tabSettings")

                Button {
                    showingRosters = true
                } label: {
                    DashboardSymbolImage("list.dash.badge.ellipsis")
                        .imageScale(iconScale)
                        .foregroundStyle(toolbarForeground)
                        .frame(width: iconW, height: iconH)
                        .toolbarIconChrome(isActive: false)
                }
                .buttonStyle(.plain)
                .tutorialAnchor("root.rosters")

                if isGraphMode && canSendAllToConsoles && !mirrorSelected {
                    Button {
                        sendAllToConsoles()
                    } label: {
                        Image(systemName: "paperplane")
                            .imageScale(iconScale)
                            .foregroundStyle(toolbarForeground)
                            .frame(width: iconW, height: iconH)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .toolbarIconChrome(isActive: false)
                    }
                    .buttonStyle(.plain)
                    .help("Send All to Consoles")
                }
                Button {
                    toggleGraphCanvas()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        DashboardSymbolImage(isGraphMode ? "square.grid.2x2" : "point.3.connected.trianglepath.dotted")
                            .imageScale(iconScale)
                            .foregroundStyle(isGraphMode ? Color.accentColor : toolbarForeground)
                            .frame(width: iconW, height: iconH)
                            .toolbarIconChrome(isActive: isGraphMode)

                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isGraphMode ? "Switch to Canvas View" : "Automation")
                    .accessibilityHint(
                        "Switches between dashboard canvas and automation view."
                    )
                }
                .buttonStyle(.plain)
                .disabled(mirrorSelected)
                .opacity(mirrorSelected ? 0.35 : 1.0)
                .tutorialAnchor("root.graphToggle")

                Button {
                    editingTileID = nil
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(iconScale)
                        .foregroundStyle(toolbarForeground)
                        .frame(width: iconW, height: iconH)
                        .toolbarIconChrome(isActive: false)
                }
                .buttonStyle(.plain)
                .tutorialAnchor("root.settings")

                if !isGraphMode {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if isInspectorVisible {
                                isInspectorVisible = false
                                editingTileID = nil
                                clearEditFocusOffsetsX()
                            } else {
                                if let currentEditing = bindingForEditingTile(),
                                   selectedTileIDs.contains(currentEditing.wrappedValue.id) {
                                    let id = currentEditing.wrappedValue.id
                                    isInspectorVisible = true
                                    focusTileForInspector(id)
                                } else if let firstSelectedID = selectedTileIDs.first {
                                    editingTileID = firstSelectedID
                                    isInspectorVisible = true
                                    focusTileForInspector(firstSelectedID)
                                }
                            }
                        }
                    } label: {
                        DashboardSymbolImage("sidebar.trailing")
                            .imageScale(iconScale)
                            .foregroundStyle(isInspectorVisible ? Color.accentColor : toolbarForeground)
                            .frame(width: iconW, height: iconH)
                            .toolbarIconChrome(isActive: isInspectorVisible)
                    }
                    .buttonStyle(.plain)
                    .disabled(mirrorSelected || !canToggleInspector)
                    .opacity((mirrorSelected || !canToggleInspector) ? 0.35 : 1.0)
                    .tutorialAnchor("root.inspectorButton")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .pillHUDSurface(strokeOpacity: 0.10, disableBackgroundExtension: true)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    #endif

    @ViewBuilder
    private var saveStatusLabel: some View {
        if saveState.isSaving {
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        } else if savedLabelVisible {
            Label("Saved", systemImage: "checkmark")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }
}


// MARK: - Liquid Glass (iOS 26+/macOS 26+) compatibility

private extension View {
    /// Applies the new Liquid Glass surface styling on iOS 26+/macOS 26+.
    /// Falls back to the existing ultraThinMaterial capsule styling on older OS versions.
    @ViewBuilder
    func pillHUDSurface(strokeOpacity: Double = 0.10, disableBackgroundExtension: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if os(macOS)
            // macOS: keep a stable material; avoid glass + background extension to prevent flashing.
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
            #else
            self
                // More “Apple pill” geometry
                .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.regularMaterial)
                        .opacity(1.0)
                )
                // Brightening wash to increase perceived blur contrast on dark canvases
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.26))
                        .allowsHitTesting(false)
                )
                // Rim highlight (top glow → bottom fade)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.44),
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                )
                // Outer edge definition
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.03), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .liquidGlassBackgroundExtensionIfAvailable(disable: disableBackgroundExtension)
            #endif
        } else {
            // your existing pre-26 branch unchanged
            self
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.12))
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.04), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }

    @ViewBuilder
    func frostedGlassSurface() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.regularMaterial)
                        .opacity(0.70)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                )
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                )
        }
    }
    @ViewBuilder
    func liquidGlassSelectedSegment() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if os(macOS)
            self
                .background(Capsule().fill(.regularMaterial).opacity(0.85))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.6))
            #else
            self
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .glassEffect(in: Capsule())
            #endif
        } else {
            self
        }
    }

    /// Applies the new background extension effect on 26+ (macOS only).
    /// This duplicates the view into mirrored copies around its edges to extend the background visually.
    @ViewBuilder
    func liquidGlassBackgroundExtensionIfAvailable(disable: Bool = false) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            // Only macOS gets the background extension; on iOS/iPadOS this can look like a reflection.
            if disable {
                self
            } else {
                self.backgroundExtensionEffect()
            }
        } else {
            self
        }
        #else
        // iOS/iPadOS: avoid the background extension effect (it can produce a mirrored “reflection” band).
        self
        #endif
    }
}

// MARK: - Small helpers

private struct LiquidGlassHandleIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .glassEffect(in: Capsule())
                .liquidGlassBackgroundExtensionIfAvailable()
        } else {
            content
        }
    }
}

// MARK: - Toolbar Icon Chrome Modifier

private struct TabsScrollContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollGeometryObserver: ViewModifier {
    @Binding var contentWidth: CGFloat
    @Binding var containerWidth: CGFloat
    @Binding var minX: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, newValue in
                contentWidth = newValue.contentSize.width
                containerWidth = newValue.containerSize.width
                minX = -newValue.contentOffset.x
            }
        } else {
            content
        }
    }
}

private struct TabsScrollContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TabsScrollMinXKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ToolbarIconChrome: ViewModifier {
    var isActive: Bool

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
                        .stroke(Color.white.opacity(isActive ? 0.18 : 0.12), lineWidth: 0.6)
                        .allowsHitTesting(false)
                )
            #else
            content
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isActive ? 0.26 : 0.18),
                                    Color.white.opacity(isActive ? 0.16 : 0.10),
                                    Color.white.opacity(isActive ? 0.06 : 0.04)
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
                .glassEffect(in: Circle())
                .liquidGlassBackgroundExtensionIfAvailable()
            #endif
        } else {
            content
                .background(
                    Circle()
                        .fill(Color.white.opacity(isActive ? 0.12 : 0.08))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isActive ? 0.16 : 0.10), lineWidth: 1)
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
    func toolbarIconChrome(isActive: Bool = false) -> some View {
        self.modifier(ToolbarIconChrome(isActive: isActive))
    }
}



// MARK: - macOS pill popover buttons (Button+popover instead of Menu, which is unreliable in nested pill HUD)

#if os(macOS)
private struct SyncedTabsMacOSPill: View {
    let manifests: [SyncedTabManifest]
    let tabHPad: CGFloat
    let tabVPad: CGFloat
    let toolbarForeground: Color
    let tabsStripHeight: CGFloat
    let onJoin: (SyncedTabManifest) -> Void

    @State private var isPresented = false

    var body: some View {
        let byDevice = Dictionary(grouping: manifests, by: \.deviceName)
        let deviceNames = byDevice.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        Button { isPresented.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: SyncMirrorPresentation.syncIconName(isSubscriber: false))
                    .imageScale(.small)
                Text("Sync")
                    .font(.caption.weight(.semibold))
                    .fixedSize()
            }
                .foregroundStyle(SyncMirrorPresentation.syncColor)
                .padding(.horizontal, tabHPad)
                .padding(.vertical, tabVPad)
                .frame(height: tabsStripHeight)
                .background { Capsule().strokeBorder(SyncMirrorPresentation.syncColor.opacity(0.45), lineWidth: 1) }
                .contentShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(deviceNames, id: \.self) { deviceName in
                    let deviceManifests = (byDevice[deviceName] ?? []).sorted {
                        $0.tabName.localizedCaseInsensitiveCompare($1.tabName) == .orderedAscending
                    }
                    Text(deviceName)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                    ForEach(deviceManifests) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button {
                            onJoin(manifest)
                            isPresented = false
                        } label: {
                            Label("Join \"\(title)\"", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(.bottom, 8)
            .frame(minWidth: 200)
        }
    }
}

private struct LANMirrorMacOSPill: View {
    let manifests: [LANSharedTabManifest]
    let tabHPad: CGFloat
    let tabVPad: CGFloat
    let toolbarForeground: Color
    let tabsStripHeight: CGFloat
    let selectedLANShareId: String?
    let onSelect: (LANSharedTabManifest) -> Void
    let onClearSelection: () -> Void
    let onImport: (LANSharedTabManifest) -> Void

    @State private var isPresented = false

    var body: some View {
        let byDevice = Dictionary(grouping: manifests, by: \.deviceName)
        let deviceNames = byDevice.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let isAnySelected = manifests.contains(where: { $0.shareId == selectedLANShareId })

        Button { isPresented.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: SyncMirrorPresentation.mirrorIconName)
                    .imageScale(.small)
                Text("Mirror")
                    .font(.caption.weight(.semibold))
                    .fixedSize()
            }
                .foregroundStyle(isAnySelected ? SyncMirrorPresentation.mirrorColor : SyncMirrorPresentation.mirrorColor.opacity(0.75))
                .padding(.horizontal, tabHPad)
                .padding(.vertical, tabVPad)
                .frame(height: tabsStripHeight)
                .background { Capsule().strokeBorder(SyncMirrorPresentation.mirrorColor.opacity(0.45), lineWidth: 1) }
                .contentShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if isAnySelected {
                    Button(role: .destructive) {
                        onClearSelection()
                        isPresented = false
                    } label: {
                        Label("Stop Mirroring", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    Divider().padding(.horizontal, 12)
                }
                ForEach(deviceNames, id: \.self) { deviceName in
                    let deviceManifests = (byDevice[deviceName] ?? []).sorted {
                        $0.tabName.localizedCaseInsensitiveCompare($1.tabName) == .orderedAscending
                    }
                    Text(deviceName)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                    ForEach(deviceManifests, id: \.shareId) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button {
                            onSelect(manifest)
                            isPresented = false
                        } label: {
                            HStack {
                                if selectedLANShareId == manifest.shareId {
                                    Image(systemName: "checkmark").frame(width: 14)
                                } else {
                                    Color.clear.frame(width: 14)
                                }
                                Text(title)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
                Divider().padding(.horizontal, 12).padding(.top, 6)
                Text("Import")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                ForEach(deviceNames, id: \.self) { deviceName in
                    let deviceManifests = (byDevice[deviceName] ?? []).sorted {
                        $0.tabName.localizedCaseInsensitiveCompare($1.tabName) == .orderedAscending
                    }
                    ForEach(deviceManifests, id: \.shareId) { manifest in
                        let title = manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName
                        Button {
                            onImport(manifest)
                            isPresented = false
                        } label: {
                            Label("Import \"\(title)\" from \(manifest.deviceName)", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(.bottom, 8)
            .frame(minWidth: 240)
        }
        .animation(nil, value: selectedLANShareId)
    }
}
#endif

#if os(iOS)
extension Notification.Name {
    static let pauseLANMirrorPolling = Notification.Name("Relay.pauseLANMirrorPolling")
    static let resumeLANMirrorPolling = Notification.Name("Relay.resumeLANMirrorPolling")
}
#endif
extension Notification.Name {
    static let lanImportRequested = Notification.Name("Relay.lanImportRequested")
}
