//
//  RelayCommands.swift
//  Relay
//
//  Created by David Bullard on 11/21/25.
//

// RelayCommands.swift

import SwiftUI
import UniformTypeIdentifiers
#if canImport(Sparkle)
import Sparkle
#endif
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct RelayCommands: Commands {
#if canImport(Sparkle)
    private let updater: SPUUpdater
    @ObservedObject private var updateViewModel: UpdateCommandViewModel
#endif
    @ObservedObject private var saveState = DashboardSaveState.shared
    @ObservedObject private var recentDocuments = DashboardRecentDocumentsStore.shared
    @ObservedObject private var homeScreenState = DashboardHomeScreenState.shared
    @AppStorage("dashboard_snap_to_grid_enabled")
    private var snapToGridEnabled: Bool = false

    @AppStorage("dashboard_live_mode_enabled")
    private var liveModeEnabled: Bool = false

    @AppStorage("dashboard_show_guides_enabled")
    private var showGuidesEnabled: Bool = true

    @AppStorage("dashboard_toolbar_autohide_enabled")
    private var toolbarAutoHideEnabled: Bool = false

    @AppStorage("dashboard_show_system_usage")
    private var showSystemUsage: Bool = false

    // Persisted view mode so the View menu can show checkmarks.
    // Values: "canvas" | "automation"
    @AppStorage("dashboard_view_mode")
    private var dashboardViewMode: String = "canvas"

    @AppStorage("dashboard_has_hidden_tiles")
    private var dashboardHasHiddenTiles: Bool = false
    @AppStorage("dashboard_has_hidden_nodes")
    private var dashboardHasHiddenNodes: Bool = false

    @AppStorage("dashboard_show_grid_enabled")
    private var showGridEnabled: Bool = true

    @AppStorage("dashboard_gridSize")
    private var gridSizeSetting: Double = 20.0

    @ObservedObject private var menuState = DashboardMenuState.shared

    private var isAutomationView: Bool { dashboardViewMode == "automation" }
    private var menu: DashboardMenuSnapshot { menuState.snapshot }
    /// Tile edits (Edit Tile, Arrange) need the canvas of a local tab, outside Live Mode.
    private var canEditCanvasTiles: Bool {
        !isAutomationView && !liveModeEnabled && menu.isEditableTabSelected
    }
    /// Tab edits (Duplicate, Rename) need a local tab, outside Live Mode.
    private var canEditSelectedTab: Bool {
        !liveModeEnabled && menu.isEditableTabSelected
    }

    /// Native checkmark items for Canvas / Automation: choosing the other mode switches,
    /// choosing the current one does nothing.
    private func viewModeBinding(_ mode: String) -> Binding<Bool> {
        Binding(
            get: { dashboardViewMode == mode },
            set: { isOn in
                guard isOn, dashboardViewMode != mode else { return }
                dashboardViewMode = mode
                NotificationCenter.default.post(
                    name: mode == "automation" ? .dashboardAutomationViewRequested : .dashboardCanvasViewRequested,
                    object: nil
                )
            }
        )
    }

    private func post(_ name: Notification.Name, _ object: Any? = nil) {
        NotificationCenter.default.post(name: name, object: object)
    }


#if canImport(Sparkle)
    init(updater: SPUUpdater) {
        self.updater = updater
        self.updateViewModel = UpdateCommandViewModel(updater: updater)
    }
#else
    init() {}
#endif

    var body: some Commands {
        // App menu: Settings… (Cmd+,)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NotificationCenter.default.post(name: .prodLinkShowSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        // File: New / New from Setup Wizard / Open / Open Recent, then Home.
        CommandGroup(replacing: .newItem) {
            Button("New Dashboard") {
                DashboardDocumentController.shared.newDocument()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New from Setup Wizard…") {
                post(.relayStartOnboardingWizard)
            }

            Button("Open…") {
                DashboardDocumentController.shared.openDocument()
            }
            .keyboardShortcut("o", modifiers: [.command])

#if os(macOS)
            Menu("Open Recent") {
                if recentDocuments.recentDocumentURLs.isEmpty {
                    Text("No Recent Dashboards")
                } else {
                    ForEach(recentDocuments.recentDocumentURLs, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            DashboardDocumentController.shared.openSpecificDocument(url)
                        }
                    }

                    Divider()

                    Button("Clear Menu") {
                        recentDocuments.clearRecentDocuments()
                    }
                }
            }
#endif

            Divider()

            Button(homeScreenState.isPresented ? "Close Home" : "Home") {
                post(homeScreenState.isPresented ? .dismissHomeRequested : .showHomeRequested)
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
            .disabled(homeScreenState.isPresented && !saveState.hasRealDocument)
        }

        // Save (quick save) and Save As…
        CommandGroup(replacing: .saveItem) {
            // Cmd+S: quick save to existing file if one is open, otherwise falls back to Save As
            Button("Save") {
                DashboardDocumentController.shared.saveCurrentDocument()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!saveState.canSaveCurrentDocument)

            // Shift+Cmd+S: always show the Save As panel
            Button("Save As…") {
                DashboardDocumentController.shared.saveCurrentDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        // Quit: replace the default menu item so a mouse click bypasses the
        // AppKit terminate: delivery that's blocked while a sheet is presented —
        // posts the same notification the Cmd+Q keyDown monitor already uses.
#if os(macOS)
        CommandGroup(replacing: .appTermination) {
            Button("Quit Relay") {
                NotificationCenter.default.post(name: .dashboardAppTerminateRequested, object: nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
#endif

        // Edit menu: selection commands, then canvas layout.
        CommandGroup(after: .textEditing) {
            Button(isAutomationView ? "Duplicate Node" : "Duplicate Tile") {
                post(isAutomationView ? .duplicateGraphNodesRequested : .duplicateTileRequested)
            }
            .keyboardShortcut("d", modifiers: [.command])

            // The root view routes this to the graph's node delete in Automation view.
            Button(DashboardMenuTitles.deleteSelection(isAutomation: isAutomationView)) {
                post(.prodLinkDeleteSelectionRequested)
            }
            .keyboardShortcut(.delete)

            Divider()

            Button("Edit Tile…") {
                post(.dashboardEditSelectedTilesRequested)
            }
            .disabled(!canEditCanvasTiles || menu.selectedTileCount == 0)

            Button("Group Selected Tiles…") {
                post(.createTileGroupRequested)
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(isAutomationView)

            let hideShowTitle: String = {
                if dashboardViewMode == "canvas", dashboardHasHiddenTiles {
                    return "Show Hidden Tiles"
                }
                if dashboardViewMode == "automation" {
                    return dashboardHasHiddenNodes ? "Show Hidden Nodes" : "Hide/Show Selected Nodes"
                }
                return "Hide/Show Selected"
            }()

            Button(hideShowTitle) {
                post(.prodLinkToggleVisibilityRequested)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Menu("Arrange") {
                Button("Distribute Horizontally") {
                    post(.dashboardDistributeSelectedTilesRequested, DistributeAxis.horizontal)
                }
                .disabled(!canEditCanvasTiles || menu.selectedTileCount < 2)

                Button("Distribute Vertically") {
                    post(.dashboardDistributeSelectedTilesRequested, DistributeAxis.vertical)
                }
                .disabled(!canEditCanvasTiles || menu.selectedTileCount < 2)

                Divider()

                Button("Align to Grid") {
                    post(.dashboardAlignSelectedTilesToGridRequested)
                }
                .disabled(!canEditCanvasTiles || menu.selectedTileCount == 0 || gridSizeSetting <= 0)

                // Acts on the selection, or on every visible tile when nothing is selected.
                Button("Resolve Overlaps") {
                    post(.dashboardResolveTileOverlapsRequested)
                }
                .disabled(!canEditCanvasTiles || !menu.hasTilesInTab || gridSizeSetting <= 0)
            }

            Button("Canvas Size…") {
                post(.changeDashboardSizeRequested)
            }

            Button("Bring All Tiles Into Canvas") {
                post(.bringAllTilesIntoCanvasRequested)
            }
        }

        // Extend the existing system View menu by placing after the Sidebar group
        CommandGroup(after: .sidebar) {
            Toggle("Canvas View", isOn: viewModeBinding("canvas"))
                .keyboardShortcut("1", modifiers: [.command])

            Toggle("Automation View", isOn: viewModeBinding("automation"))
                .keyboardShortcut("2", modifiers: [.command])

            Divider()

            // Same state as the toolbar's Tile Overview and Inspector buttons.
            Button(DashboardMenuTitles.tileOverviewToggle(isVisible: menu.isTileOverviewVisible)) {
                post(.dashboardToggleTileOverviewRequested)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(isAutomationView || liveModeEnabled || !(menu.hasTilesInTab || menu.isTileOverviewVisible))

            Button(DashboardMenuTitles.inspectorToggle(isVisible: menu.isInspectorVisible)) {
                post(.dashboardToggleInspectorRequested)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(
                isAutomationView || liveModeEnabled
                    || !(menu.isInspectorVisible || (menu.isEditableTabSelected && menu.selectedTileCount > 0))
            )

            Divider()

            // Zooms the canvas, or the graph in Automation view. ⌘= also zooms in through
            // a hidden button in the root view, since a menu item takes one shortcut.
            Button("Zoom In") {
                post(.dashboardViewportZoomRequested, ViewportZoomCommand.zoomIn)
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(liveModeEnabled)

            Button("Zoom Out") {
                post(.dashboardViewportZoomRequested, ViewportZoomCommand.zoomOut)
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(liveModeEnabled)

            Button("Actual Size") {
                post(.dashboardViewportZoomRequested, ViewportZoomCommand.actualSize)
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(liveModeEnabled)

            Divider()

            Toggle("Show Grid", isOn: $showGridEnabled)

            Toggle("Snap to Grid", isOn: $snapToGridEnabled)
                .keyboardShortcut("g", modifiers: [.command, .option])

            // Cmd+; is the system Check Spelling shortcut and Option+Cmd+M is Minimize All,
            // so these use free combinations instead (keep DashboardKeyboardShortcutsView in sync).
            Toggle("Show Guides", isOn: $showGuidesEnabled)
                .keyboardShortcut("'", modifiers: [.command])

            Divider()

            Toggle("Live Mode", isOn: $liveModeEnabled)
                .keyboardShortcut("l", modifiers: [.command])

            Toggle("Auto-Hide Toolbar", isOn: $toolbarAutoHideEnabled)
                .keyboardShortcut("m", modifiers: [.command, .control])

            Divider()

            Toggle("Show System Status", isOn: $showSystemUsage)

            Divider()
        }

#if os(macOS)
        // Window menu: the floating panels. (iPadOS has no window-list placement.)
        CommandGroup(before: .windowList) {
            Button("Variables") {
                post(.relayShowSharedValues)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Button("Rosters") {
                post(.dashboardShowRostersRequested)
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Divider()
        }
#endif

        CommandMenu("Tabs") {
            Button("New Tab") {
                post(.dashboardAddTabRequested)
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("Duplicate Tab") {
                post(.dashboardDuplicateSelectedTabRequested)
            }
            .disabled(!canEditSelectedTab)

#if os(macOS)
            // Renames inline in the tab strip, which Automation view replaces with a title.
            Button("Rename Tab…") {
                post(.dashboardRenameSelectedTabRequested)
            }
            .disabled(!canEditSelectedTab || isAutomationView)
#endif

            Button("Tab Settings…") {
                post(.dashboardShowTabSettingsRequested)
            }

            Divider()

            Button("Select Previous Tab") {
                post(.dashboardSelectPreviousTabRequested)
            }
            .keyboardShortcut("[", modifiers: [.command])

            Button("Select Next Tab") {
                post(.dashboardSelectNextTabRequested)
            }
            .keyboardShortcut("]", modifiers: [.command])

            Button("Select First Tab") {
                post(.dashboardSelectFirstTabRequested)
            }
            .keyboardShortcut("[", modifiers: [.command, .option])

            Button("Select Last Tab") {
                post(.dashboardSelectLastTabRequested)
            }
            .keyboardShortcut("]", modifiers: [.command, .option])

            Divider()

            // Same confirmation (with undo) as the tab's close button.
            Button("Delete Tab…") {
                post(.dashboardDeleteSelectedTabRequested)
            }
            .disabled(liveModeEnabled || !menu.canDeleteSelectedTab)
        }

#if canImport(Sparkle)
        CommandGroup(after: .appInfo) {
            CheckForUpdatesCommandView(model: updateViewModel)
        }
#endif

        // Help menu: keep Export Logs, add Tutorial.
        CommandGroup(replacing: .help) {
            Button("Relay Help Center") {
                openHelpCenter()
            }

            Divider()

            Button("Start Tutorial…") {
                NotificationCenter.default.post(name: .prodlinkStartTutorial, object: nil)
            }

            Divider()

            Button("Keyboard Shortcuts…") {
                NotificationCenter.default.post(name: .prodLinkShowKeyboardShortcuts, object: nil)
            }

            Divider()

            Button("Export Logs…") {
                NotificationCenter.default.post(name: .prodLinkExportLogsRequested, object: nil)
            }
        }
    }

    private func openHelpCenter() {
        let url = RelaySupportContact.helpCenterURL
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}

#if canImport(Sparkle)
private final class UpdateCommandViewModel: ObservableObject {
    @Published var canCheckForUpdates: Bool = false

    private let updater: SPUUpdater
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        self.updater = updater
        canCheckForUpdates = updater.canCheckForUpdates
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
#endif

#if canImport(Sparkle)
private struct CheckForUpdatesCommandView: View {
    @ObservedObject var model: UpdateCommandViewModel

    var body: some View {
        Button("Check for Updates…") {
            model.checkForUpdates()
        }
        .disabled(!model.canCheckForUpdates)
    }
}
#endif
extension Notification.Name {
    static let saveDashboardRequested = Notification.Name("saveDashboardRequested")
}
extension Notification.Name {
    static let openDashboardRequested = Notification.Name("openDashboardRequested")
}
extension Notification.Name {
    static let saveDashboardQuickRequested = Notification.Name("saveDashboardQuickRequested")
}
extension Notification.Name {
    static let duplicateTileRequested = Notification.Name("duplicateTileRequested")
}
extension Notification.Name {
    static let duplicateGraphNodesRequested = Notification.Name("duplicateGraphNodesRequested")
}
extension Notification.Name {
    static let createTileGroupRequested = Notification.Name("createTileGroupRequested")
}
extension Notification.Name {
    static let newDashboardRequested = Notification.Name("newDashboardRequested")
}
extension Notification.Name {
    static let dashboardCanvasViewRequested = Notification.Name("dashboardCanvasViewRequested")
}

extension Notification.Name {
    static let dashboardAutomationViewRequested = Notification.Name("dashboardAutomationViewRequested")
}

extension Notification.Name {
    static let dashboardAddTabRequested = Notification.Name("dashboardAddTabRequested")
    static let dashboardSelectFirstTabRequested = Notification.Name("dashboardSelectFirstTabRequested")
    static let dashboardSelectPreviousTabRequested = Notification.Name("dashboardSelectPreviousTabRequested")
    static let dashboardSelectNextTabRequested = Notification.Name("dashboardSelectNextTabRequested")
    static let dashboardSelectLastTabRequested = Notification.Name("dashboardSelectLastTabRequested")
}

extension Notification.Name {
    static let prodLinkShowSettings = Notification.Name("Relay.ShowSettings")
}

extension Notification.Name {
    /// Toolbar-equivalent toggles, handled by `DashboardTopToolbarView`.
    static let dashboardToggleTileOverviewRequested = Notification.Name("Relay.ToggleTileOverviewRequested")
    static let dashboardToggleInspectorRequested = Notification.Name("Relay.ToggleInspectorRequested")
    /// Opens the inspector on the selected tiles (Edit ▸ Edit Tile…), handled by the toolbar.
    static let dashboardEditSelectedTilesRequested = Notification.Name("Relay.EditSelectedTilesRequested")
    /// object: `ViewportZoomCommand`. The canvas or the graph handles it, whichever is showing.
    static let dashboardViewportZoomRequested = Notification.Name("Relay.ViewportZoomRequested")
    /// The root view's forward of `dashboardViewportZoomRequested` to the graph in Automation view.
    static let dashboardGraphZoomRequested = Notification.Name("Relay.GraphZoomRequested")
    static let dashboardShowRostersRequested = Notification.Name("Relay.ShowRostersRequested")
    /// object: `DistributeAxis`.
    static let dashboardDistributeSelectedTilesRequested = Notification.Name("Relay.DistributeSelectedTilesRequested")
    static let dashboardAlignSelectedTilesToGridRequested = Notification.Name("Relay.AlignSelectedTilesToGridRequested")
    static let dashboardResolveTileOverlapsRequested = Notification.Name("Relay.ResolveTileOverlapsRequested")
    /// object: `Set<UUID>` of tiles to hide (the tile context menu's Hide).
    static let dashboardHideTilesRequested = Notification.Name("Relay.HideTilesRequested")
    /// Tabs menu commands that act on the selected tab. Rename and Delete are handled by
    /// the toolbar (inline rename, delete confirmation); the rest by the root view.
    static let dashboardDuplicateSelectedTabRequested = Notification.Name("Relay.DuplicateSelectedTabRequested")
    static let dashboardRenameSelectedTabRequested = Notification.Name("Relay.RenameSelectedTabRequested")
    static let dashboardShowTabSettingsRequested = Notification.Name("Relay.ShowTabSettingsRequested")
    static let dashboardDeleteSelectedTabRequested = Notification.Name("Relay.DeleteSelectedTabRequested")
}

extension Notification.Name {
    static let prodLinkShowKeyboardShortcuts = Notification.Name("Relay.ShowKeyboardShortcuts")
    static let relayShowSharedValues = Notification.Name("Relay.ShowSharedValues")
}

extension Notification.Name {
    static let prodlinkStartTutorial = Notification.Name("Relay.StartTutorial")
}

extension Notification.Name {
    static let prodLinkExportLogsRequested = Notification.Name("Relay.ExportLogsRequested")
}
extension Notification.Name {
    static let changeDashboardSizeRequested = Notification.Name("Relay.ChangeDashboardSizeRequested")
}

extension Notification.Name {
    static let bringAllTilesIntoCanvasRequested = Notification.Name("Relay.BringAllTilesIntoCanvasRequested")
}

extension Notification.Name {
    static let prodLinkDeleteSelectionRequested = Notification.Name("Relay.DeleteSelectionRequested")
}

extension Notification.Name {
    static let prodLinkDeleteGraphSelectionRequested = Notification.Name("Relay.DeleteGraphSelectionRequested")
    /// Edit ▸ Delete in Automation view: deletes a selected link, otherwise the selected nodes,
    /// like the graph's Delete key. (The floating menu's node delete keeps the name above.)
    static let dashboardDeleteGraphSelectionRequested = Notification.Name("Relay.DeleteGraphMenuSelectionRequested")
}

extension Notification.Name {
    static let prodLinkGraphSelectionCountChanged = Notification.Name("Relay.GraphSelectionCountChanged")
}

extension Notification.Name {
    /// Posted just before flipping to Automation so the hidden graph builds itself before the
    /// flip animation starts, instead of stalling it partway through.
    static let relayPrewarmAutomationView = Notification.Name("Relay.PrewarmAutomationView")
}

extension Notification.Name {
    static let prodLinkToggleVisibilityRequested = Notification.Name("Relay.ToggleVisibilityRequested")
}

extension Notification.Name {
    static let prodLinkToggleGraphNodeVisibilityRequested = Notification.Name("Relay.GraphToggleNodeVisibilityRequested")
}

extension Notification.Name {
    static let prodLinkUnhideAllGraphNodesRequested = Notification.Name("Relay.GraphUnhideAllNodesRequested")
}

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("Relay.OpenSettingsRequested")
}

extension Notification.Name {
    static let settingsDidDismiss = Notification.Name("Relay.SettingsDidDismiss")
}

extension Notification.Name {
    static let showHomeRequested = Notification.Name("Relay.ShowHomeRequested")
}

extension Notification.Name {
    static let dismissHomeRequested = Notification.Name("Relay.DismissHomeRequested")
}

extension Notification.Name {
    /// Posted by the home screen when "Create Dashboard" is confirmed.
    /// userInfo keys: "width" (CGFloat), "height" (CGFloat)
    static let createBlankDashboardRequested = Notification.Name("Relay.CreateBlankDashboardRequested")
}
