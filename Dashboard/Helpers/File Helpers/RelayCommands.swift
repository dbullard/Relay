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

        // New / Open dashboard in the currently focused window via the fileImporter
        CommandGroup(replacing: .newItem) {
            Button(homeScreenState.isPresented ? "Close Home" : "Home") {
                let name: Notification.Name = homeScreenState.isPresented ? .dismissHomeRequested : .showHomeRequested
                NotificationCenter.default.post(name: name, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
            .disabled(homeScreenState.isPresented && !saveState.hasRealDocument)

            Divider()

            Button("New Dashboard") {
                DashboardDocumentController.shared.newDocument()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Setup Wizard…") {
                NotificationCenter.default.post(name: .relayStartOnboardingWizard, object: nil)
            }

            Button("Open Dashboard…") {
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
        }

        // Save Dashboard (quick save) and Save As…
        CommandGroup(replacing: .saveItem) {
            // Cmd+S: quick save to existing file if one is open, otherwise falls back to Save As
            Button("Save Dashboard") {
                DashboardDocumentController.shared.saveCurrentDocument()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!saveState.canSaveCurrentDocument)

            // Shift+Cmd+S: always show the Save As panel
            Button("Save Dashboard As…") {
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

        // Edit menu: Canvas sizing
        CommandGroup(after: .textEditing) {
            Button(dashboardViewMode == "automation" ? "Duplicate Node" : "Duplicate Tile") {
                NotificationCenter.default.post(
                    name: dashboardViewMode == "automation" ? .duplicateGraphNodesRequested : .duplicateTileRequested,
                    object: nil
                )
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("Group Selected Tiles…") {
                NotificationCenter.default.post(name: .createTileGroupRequested, object: nil)
            }
            .keyboardShortcut("g", modifiers: [.command])

            Divider()

            Button("Resize Dashboard Canvas…") {
                NotificationCenter.default.post(name: .changeDashboardSizeRequested, object: nil)
            }

            Button("Bring All Tiles Into Canvas") {
                NotificationCenter.default.post(name: .bringAllTilesIntoCanvasRequested, object: nil)
            }

            Divider()

            Button("Delete Selected Tiles") {
                NotificationCenter.default.post(name: .prodLinkDeleteSelectionRequested, object: nil)
            }
            .keyboardShortcut(.delete)

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
                NotificationCenter.default.post(name: .prodLinkToggleVisibilityRequested, object: nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

        }

        // Extend the existing system View menu by placing after the Sidebar group
        CommandGroup(after: .sidebar) {
            // View mode switching
            Button {
                guard dashboardViewMode != "canvas" else { return }
                dashboardViewMode = "canvas"
                NotificationCenter.default.post(name: .dashboardCanvasViewRequested, object: nil)
            } label: {
                HStack(spacing: 8) {
                    if dashboardViewMode == "canvas" {
                        Image(systemName: "checkmark")
                    } else {
                        Color.clear.frame(width: 14, height: 14)
                    }
                    Text("Canvas View")
                }
            }
            .keyboardShortcut("1", modifiers: [.command])
            .disabled(dashboardViewMode == "canvas")

            Button {
                guard dashboardViewMode != "automation" else { return }
                dashboardViewMode = "automation"
                NotificationCenter.default.post(name: .dashboardAutomationViewRequested, object: nil)
            } label: {
                HStack(spacing: 8) {
                    if dashboardViewMode == "automation" {
                        Image(systemName: "checkmark")
                    } else {
                        Color.clear.frame(width: 14, height: 14)
                    }
                    Text("Automation View")
                }
            }
            .keyboardShortcut("2", modifiers: [.command])
            .disabled(dashboardViewMode == "automation")

            Divider()

            Button("Variables") {
                NotificationCenter.default.post(name: .relayShowSharedValues, object: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Divider()

            Toggle("Snap to Grid", isOn: $snapToGridEnabled)
                .keyboardShortcut("g", modifiers: [.command, .option])

            Divider()

            Toggle("Live Mode", isOn: $liveModeEnabled)
                .keyboardShortcut("l", modifiers: [.command])

            Toggle("Show Guides", isOn: $showGuidesEnabled)
                .keyboardShortcut(";", modifiers: [.command])

            Toggle("Auto-Hide Menu", isOn: $toolbarAutoHideEnabled)
                .keyboardShortcut("m", modifiers: [.command, .option])

            Divider()

            Toggle("Show System Status", isOn: $showSystemUsage)

            Divider()
        }

        CommandMenu("Tabs") {
            Button("New Tab") {
                NotificationCenter.default.post(name: .dashboardAddTabRequested, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command])

            Divider()

            Button("Select Previous Tab") {
                NotificationCenter.default.post(name: .dashboardSelectPreviousTabRequested, object: nil)
            }
            .keyboardShortcut("[", modifiers: [.command])

            Button("Select Next Tab") {
                NotificationCenter.default.post(name: .dashboardSelectNextTabRequested, object: nil)
            }
            .keyboardShortcut("]", modifiers: [.command])

            Divider()

            Button("Select First Tab") {
                NotificationCenter.default.post(name: .dashboardSelectFirstTabRequested, object: nil)
            }
            .keyboardShortcut("[", modifiers: [.command, .option])

            Button("Select Last Tab") {
                NotificationCenter.default.post(name: .dashboardSelectLastTabRequested, object: nil)
            }
            .keyboardShortcut("]", modifiers: [.command, .option])
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
}

extension Notification.Name {
    static let prodLinkGraphSelectionCountChanged = Notification.Name("Relay.GraphSelectionCountChanged")
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
