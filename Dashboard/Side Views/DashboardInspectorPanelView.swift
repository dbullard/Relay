//
//  DashboardInspectorPanelView.swift
//  Relay
//
//  Extracted from DashboardRootView.inspectorView(for:) to keep DashboardRootView.swift smaller.
//  This view is intentionally UI-focused and receives bindings + closures from DashboardRootView.
//

import SwiftUI

struct DashboardInspectorPanelView: View {

    // MARK: - Inputs

    let inspectorPanelWidth: CGFloat

    @Binding var tabs: [DashboardTab]
    @Binding var sharedRosters: [DashboardRoster]
    @Binding var selectedTabIndex: Int
    @Binding var selectedTileIDs: Set<UUID>

    @Binding var editingTileID: UUID?
    @Binding var isInspectorVisible: Bool
    @Binding var pendingModuleCatalogTileID: UUID?
    @Binding var pendingFirstModuleSelectTileID: UUID?

    /// Temporary focus offsets used by the canvas to keep tiles visible next to the inspector.
    let clearEditFocusOffsetsX: () -> Void

    /// Persist / undo hooks owned by DashboardRootView
    let pushUndoSnapshot: (_ actionName: String) -> Void
    let markUnsavedAndScheduleSave: () -> Void

    /// Tile + tab bindings
    let tileBinding: Binding<DashboardTileModel>
    let tabBinding: Binding<DashboardTab>
    let onOpenPCOTabSettings: () -> Void

    /// Precomputed from RootView so this file doesn't need to know tile sizing rules.
    let tileHeightPoints: CGFloat
    let defaultTileSize: CGSize

    // Snapshot the size at the moment the inspector opens so reset stays stable.
    @State private var initialTileSizeWidthSnapshot: String = ""
    @State private var initialTileSizeHeightSnapshot: String = ""
    @State private var initialTileSizeSnapshot: CGSize? = nil

    /// Folds a slider drag (or a burst of colour-panel changes) into one undo step.
    /// A reference box: updating it must not re-render the inspector.
    @State private var undoCoalescing = InspectorUndoCoalescingBox()

    /// The dashboard's undo manager (the one `pushUndoSnapshot` registers with).
    @Environment(\.undoManager) private var undoManager

    // MARK: - Body

    var body: some View {
        let tileValue = tileBinding.wrappedValue
        let modules = tileValue.modules ?? []

        let hasPCORundown: Bool = modules.contains { m in
            if case .pcoRundown = m.kind { return true }
            return false
        }

        let hasShureWireless: Bool = modules.contains { m in
            switch m.kind {
            case .shureWireless, .shureOverview:
                return true
            default:
                return false
            }
        }

        let initialPerson: PersonTileModel? = {
            if let modules = tileValue.modules {
                for module in modules {
                    if case .person(let model) = module.kind {
                        return model
                    }
                }
            }

            if case .person(let model) = tileValue.kind {
                return model
            }

            return nil
        }()

        let isMultiTileEdit = selectedTileIDs.count > 1

        let allPersonNamesRaw: [String] = tabs.flatMap { tab in
            tab.tiles.flatMap { tile in
                let tilePersonName: String? = {
                    guard case .person(let model) = tile.kind else { return nil }
                    let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? nil : name
                }()
                let moduleNames = (tile.modules ?? []).compactMap { module -> String? in
                    if case .person(let model) = module.kind {
                        let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        return name.isEmpty ? nil : name
                    }
                    return nil
                }
                return [tilePersonName].compactMap { $0 } + moduleNames
            }
        }
        var seen = Set<String>()
        let allPersonNames = allPersonNamesRaw.filter { seen.insert($0).inserted }

        DashboardTileEditView(
            tileID: tileValue.id,
            tileHeightPoints: tileHeightPoints,
            isMultiTileEdit: isMultiTileEdit,
            tileName: tileValue.name,
            selectedTileCount: selectedTileIDs.count,
            initialPerson: initialPerson,
            hasPCORundown: hasPCORundown,
            hasShureWireless: hasShureWireless,
            initialBackgroundStyle: tileValue.backgroundStyle,
            initialBackgroundOpacity: tileValue.backgroundOpacity,
            initialCornerRadius: tileValue.cornerRadius,
            initialBackgroundColor: tileValue.backgroundCustomColor,
            initialBackgroundGradient: tileValue.backgroundGradient,
            initialModuleLayout: tileValue.moduleLayout,
            initialShureSelection: tileValue.shureSelectedChannel,
            modules: tileValue.modules ?? [],
            sharedRosters: sharedRosters,
            pendingModuleCatalogTileID: $pendingModuleCatalogTileID,
            pendingFirstModuleSelectTileID: $pendingFirstModuleSelectTileID,

            onMoveModule: { moduleID, newIndex in
                pushUndoSnapshot("Reorder Modules")

                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                modules.sort { $0.order < $1.order }

                guard let oldIndex = modules.firstIndex(where: { $0.id == moduleID }) else {
                    return
                }

                let clampedIndex = max(0, min(newIndex, modules.count - 1))
                let moved = modules.remove(at: oldIndex)
                modules.insert(moved, at: clampedIndex)

                for idx in modules.indices {
                    modules[idx].order = idx
                }

                tile.modules = modules
                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
            },

            onAddModule: { kind in
                pushUndoSnapshot("Add Module")
                var tile = tileBinding.wrappedValue
                var modules = tile.modules ?? []
                let nextOrder = (modules.map { $0.order }.max() ?? -1) + 1
                let newModule: DashboardModuleModel = {
                    switch kind {
                    case .time:
                        return DashboardModuleModel(kind: kind, order: nextOrder, timeConfig: TimeModuleConfig.default())
                    case .timecode:
                        return DashboardModuleModel(kind: kind, order: nextOrder, timecodeConfig: TimecodeModuleConfig.default())
                    case .dawTransport:
                        return DashboardModuleModel(kind: kind, order: nextOrder, dawTransportConfig: DAWTransportModuleConfiguration.default())
                    default:
                        return DashboardModuleModel(kind: kind, order: nextOrder)
                    }
                }()
                modules.append(newModule)
                tile.modules = modules
                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
            },

            onRemoveModule: { moduleID in
                pushUndoSnapshot("Remove Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }
                modules.removeAll { $0.id == moduleID }
                tile.modules = modules.isEmpty ? nil : modules
                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
            },

            onDuplicateModule: { moduleID in
                pushUndoSnapshot("Duplicate Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                modules.sort { $0.order < $1.order }

                guard let sourceIndex = modules.firstIndex(where: { $0.id == moduleID }) else {
                    return
                }

                let source = modules[sourceIndex]
                let copy = DashboardModuleModel(
                    kind: source.kind.duplicatedForCanvasCopy(),
                    order: source.order,
                    id: UUID(),
                    pcoConfig: source.pcoConfig,
                    shureConfig: source.shureConfig,
                    shureOverviewConfig: source.shureOverviewConfig,
                    sennheiserConfig: source.sennheiserConfig,
                    proPresenterConfig: source.proPresenterConfig,
                    resolumeConfig: source.resolumeConfig,
                    timeConfig: source.timeConfig,
                    timecodeConfig: source.timecodeConfig,
                    dawTransportConfig: source.dawTransportConfig,
                    rosterTeamAssignmentsConfig: source.rosterTeamAssignmentsConfig,
                    paddingTop: source.paddingTop,
                    paddingBottom: source.paddingBottom,
                    moduleScale: source.moduleScale,
                    moduleHeightPoints: source.moduleHeightPoints
                )

                let insertIndex = min(sourceIndex + 1, modules.count)
                modules.insert(copy, at: insertIndex)

                for idx in modules.indices {
                    modules[idx].order = idx
                }

                tile.modules = modules
                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
            },

            onUpdateTextModule: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Text")) { module in
                    module.kind = .text(updatedModel)
                }
            },

            onUpdateImageModule: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Image")) { module in
                    module.kind = .image(updatedModel)
                }
            },

            onUpdateDocumentModule: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Document")) { module in
                    module.kind = .document(updatedModel)
                }
            },

            onUpdateNDIModule: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("NDI")) { module in
                    module.kind = .ndi(updatedModel)
                }
            },

            onUpdateWebpageModule: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Webpage")) { module in
                    module.kind = .webpage(updatedModel)
                }
            },

            onUpdateYouTubeStreamMonitorModule: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("YouTube Stream Monitor")) { module in
                    module.kind = .youtubeStreamMonitor(updatedModel)
                }
            },

            onUpdateButtonModule: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Button")) { module in
                    module.kind = .button(updatedModel)
                }
            },

            onUpdateRosterPickerModule: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Picker")) { module in
                    module.kind = .rosterPicker(updatedModel)
                }
            },

            onUpdateSeparator: { moduleID, updatedModel in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Separator")) { module in
                    module.kind = .separator(updatedModel)
                }
            },
            onOpenPCOTabSettings: onOpenPCOTabSettings,

            onUpdateTimeModuleConfig: { moduleID, config in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Time")) { module in
                    module.timeConfig = config
                }
            },

            onUpdateTimecodeModuleConfig: { moduleID, config in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Timecode")) { module in
                    module.timecodeConfig = config
                }
            },

            onUpdateDAWTransportModuleConfig: { moduleID, config in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("DAW Transport")) { module in
                    module.dawTransportConfig = config
                }
            },

            onUpdateModulePadding: { moduleID, top, bottom in
                guard tileBinding.wrappedValue.modules?.contains(where: { $0.id == moduleID }) == true else { return }
                commitTileEdit("Edit Module Padding", toSelection: false) { tile in
                    guard let idx = tile.modules?.firstIndex(where: { $0.id == moduleID }) else { return }
                    if let top = top { tile.modules?[idx].paddingTop = top }
                    if let bottom = bottom { tile.modules?[idx].paddingBottom = bottom }
                }
            },

            onUpdateModuleScale: { moduleID, scale in
                guard tileBinding.wrappedValue.modules?.contains(where: { $0.id == moduleID }) == true else { return }
                commitTileEdit("Edit Module Scale", toSelection: false) { tile in
                    guard let mIdx = tile.modules?.firstIndex(where: { $0.id == moduleID }) else { return }
                    // Height is in points; nil means Auto.
                    tile.modules?[mIdx].moduleHeightPoints = scale
                    // Clear legacy scale so height points are the sole driver.
                    tile.modules?[mIdx].moduleScale = nil
                }
            },

            tab: tabBinding,

            onSavePerson: { updatedPerson in
                guard let updated = updatedPerson else { return }

                pushUndoSnapshot("Edit Person")
                var tile = tileBinding.wrappedValue

                if var modules = tile.modules {
                    for idx in modules.indices {
                        switch modules[idx].kind {
                        case .person:
                            modules[idx].kind = .person(updated)
                        default:
                            break
                        }
                    }
                    tile.modules = modules
                }

                switch tile.kind {
                case .person:
                    tile.kind = .person(updated)
                default:
                    break
                }

                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
            },

            onSaveTileAppearance: { style, opacity, radius, color, gradient in
                commitTileEdit("Edit Tile Appearance", toSelection: isMultiTileEdit) { tile in
                    tile.backgroundStyle = style
                    tile.backgroundOpacity = opacity
                    tile.cornerRadius = radius
                    tile.backgroundCustomColor = color
                    tile.backgroundGradient = gradient
                }
            },

            onPreviewTileAppearance: { style, opacity, radius, color, gradient in
                if isMultiTileEdit {
                    guard tabs.indices.contains(selectedTabIndex) else { return }
                    for id in selectedTileIDs {
                        if let idx = tabs[selectedTabIndex].tiles.firstIndex(where: { $0.id == id }) {
                            tabs[selectedTabIndex].tiles[idx].backgroundStyle = style
                            tabs[selectedTabIndex].tiles[idx].backgroundOpacity = opacity
                            tabs[selectedTabIndex].tiles[idx].cornerRadius = radius
                            tabs[selectedTabIndex].tiles[idx].backgroundCustomColor = color
                            tabs[selectedTabIndex].tiles[idx].backgroundGradient = gradient
                        }
                    }
                } else {
                    var tile = tileBinding.wrappedValue
                    tile.backgroundStyle = style
                    tile.backgroundOpacity = opacity
                    tile.cornerRadius = radius
                    tile.backgroundCustomColor = color
                    tile.backgroundGradient = gradient
                    tileBinding.wrappedValue = tile
                }
            },

            initialTileContentPadding: tileValue.contentPadding ?? 0,

            onPreviewTileContentPadding: { padding in
                if isMultiTileEdit {
                    guard tabs.indices.contains(selectedTabIndex) else { return }
                    for id in selectedTileIDs {
                        if let idx = tabs[selectedTabIndex].tiles.firstIndex(where: { $0.id == id }) {
                            tabs[selectedTabIndex].tiles[idx].contentPadding = padding
                        }
                    }
                } else {
                    var tile = tileBinding.wrappedValue
                    tile.contentPadding = padding
                    tileBinding.wrappedValue = tile
                }
            },

            onSaveTileContentPadding: { padding in
                commitTileEdit("Edit Tile Padding", toSelection: isMultiTileEdit) { tile in
                    tile.contentPadding = padding
                }
            },

            onSaveModuleLayout: { layout in
                pushUndoSnapshot("Edit Module Layout")

                if isMultiTileEdit {
                    guard tabs.indices.contains(selectedTabIndex) else { return }
                    for id in selectedTileIDs {
                        if let idx = tabs[selectedTabIndex].tiles.firstIndex(where: { $0.id == id }) {
                            tabs[selectedTabIndex].tiles[idx].moduleLayout = layout
                        }
                    }
                } else {
                    var tile = tileBinding.wrappedValue
                    tile.moduleLayout = layout
                    tileBinding.wrappedValue = tile
                }

                markUnsavedAndScheduleSave()
            },

            onSaveShureSelection: { selection in
                pushUndoSnapshot("Edit Shure Selection")
                var tile = tileBinding.wrappedValue
                tile.shureSelectedChannel = selection
                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
            },

            onDismiss: {
                editingTileID = nil
                isInspectorVisible = false
                clearEditFocusOffsetsX()
            },

            onPreviewTextFormatting: { size, weight, color, caps, justification, verticalAlignment in
                if isMultiTileEdit {
                    guard tabs.indices.contains(selectedTabIndex) else { return }
                    for id in selectedTileIDs {
                        if let idx = tabs[selectedTabIndex].tiles.firstIndex(where: { $0.id == id }) {
                            tabs[selectedTabIndex].tiles[idx].textFontSize = size
                            tabs[selectedTabIndex].tiles[idx].textFontWeight = weight
                            tabs[selectedTabIndex].tiles[idx].textColor = color
                            tabs[selectedTabIndex].tiles[idx].textCapitalization = caps
                            tabs[selectedTabIndex].tiles[idx].textJustification = justification
                            tabs[selectedTabIndex].tiles[idx].textVerticalAlignment = verticalAlignment
                        }
                    }
                } else {
                    var tile = tileBinding.wrappedValue
                    tile.textFontSize = size
                    tile.textFontWeight = weight
                    tile.textColor = color
                    tile.textCapitalization = caps
                    tile.textJustification = justification
                    tile.textVerticalAlignment = verticalAlignment
                    tileBinding.wrappedValue = tile
                }
            },

            initialTextFontSize: tileValue.textFontSize,
            initialTextFontWeight: tileValue.textFontWeight,
            initialTextColor: tileValue.textColor,
            initialTextCapitalization: tileValue.textCapitalization,
            initialTextJustification: tileValue.textJustification,
            initialTextVerticalAlignment: tileValue.textVerticalAlignment,

            onSaveTextFormatting: { size, weight, color, caps, justification, verticalAlignment in
                commitTileEdit("Edit Text Formatting", toSelection: isMultiTileEdit) { tile in
                    tile.textFontSize = size
                    tile.textFontWeight = weight
                    tile.textColor = color
                    tile.textCapitalization = caps
                    tile.textJustification = justification
                    tile.textVerticalAlignment = verticalAlignment
                }
            },

            initialTileSizeWidthText: initialTileSizeWidthSnapshot,
            initialTileSizeHeightText: initialTileSizeHeightSnapshot,
            defaultTileSize: defaultTileSize,
            currentTileSize: DashboardTileSnappingHelper.effectiveSize(
                for: tileValue,
                defaultTileSize: defaultTileSize
            ),
            initialTileSize: initialTileSizeSnapshot,
            onBeginTileSizeEdit: {
                pushUndoSnapshot("Resize Tile")
            },
            onUpdateTileSizeLive: { widthInput, heightInput in
                let selectedIDs = selectedTileIDs.contains(tileValue.id) ? selectedTileIDs : [tileValue.id]
                for id in selectedIDs {
                    guard let idx = tabs[selectedTabIndex].tiles.firstIndex(where: { $0.id == id }) else { continue }
                    let currentSize = DashboardTileSnappingHelper.effectiveSize(
                        for: tabs[selectedTabIndex].tiles[idx],
                        defaultTileSize: defaultTileSize
                    )
                    let rawWidth = widthInput ?? Double(currentSize.width)
                    let rawHeight = heightInput ?? Double(currentSize.height)

                    let clampedWidth = max(44, rawWidth)
                    let clampedHeight = max(44, rawHeight)

                    tabs[selectedTabIndex].tiles[idx].size = CGSize(width: clampedWidth, height: clampedHeight)
                }

                markUnsavedAndScheduleSave()
            },

            onContinuousEditChanged: { isEditing in
                if isEditing {
                    undoCoalescing.coalescer.beginContinuousEdit()
                } else {
                    undoCoalescing.coalescer.endContinuousEdit()
                }
            },

            onUpdatePCOModuleConfig: { moduleID, newConfig in
                commitModuleEdit(moduleID, TileEditorCopy.moduleSettingsActionName("Planning Center")) { module in
                    module.pcoConfig = newConfig
                }
            },

            onUpdateShureModuleConfig: { moduleID, newConfig in
                let actionName = TileEditorCopy.moduleSettingsActionName("Shure")
                commitTileEdit(
                    actionName,
                    coalescingKey: InspectorUndoCoalescer.moduleKey(actionName: actionName, moduleID: moduleID),
                    toSelection: false
                ) { tile in
                    guard let moduleIndex = tile.modules?.firstIndex(where: { $0.id == moduleID }) else { return }

                    // Update the per-module Shure configuration.
                    tile.modules?[moduleIndex].shureConfig = newConfig

                    // Keep tile-level Shure properties in sync for backward compatibility.
                    tile.shureSelectedChannel = newConfig.selectedChannel
                    tile.shureShowDeviceName = newConfig.showDeviceName
                    tile.shureShowChannelName = newConfig.showChannelName
                    tile.shureShowIPPort = newConfig.showIPPort
                    tile.shureShowFrequency = newConfig.showFrequency
                    tile.shureShowBattery = newConfig.showBattery
                    tile.shureShowRFStrength = newConfig.showRFStrength
                }
            },

            onCommitModuleChange: { moduleID, actionName, change in
                commitModuleEdit(moduleID, actionName, change)
            },

            onSuppressUndoRegistration: { duration in
                undoCoalescing.coalescer.suppressRegistrations(until: Date().addingTimeInterval(duration))
            },

            initialShowsTitle: tileValue.showsTitle,

            onSaveShowsTitle: { newValue in
                pushUndoSnapshot("Toggle Tile Title")

                if isMultiTileEdit {
                    guard tabs.indices.contains(selectedTabIndex) else { return }
                    for id in selectedTileIDs {
                        if let idx = tabs[selectedTabIndex].tiles.firstIndex(where: { $0.id == id }) {
                            tabs[selectedTabIndex].tiles[idx].showsTitle = newValue
                        }
                    }
                } else {
                    var tile = tileBinding.wrappedValue
                    tile.showsTitle = newValue
                    tileBinding.wrappedValue = tile
                }

                markUnsavedAndScheduleSave()
            },

            initialShureShowDeviceName: tileValue.shureShowDeviceName,
            initialShureShowChannelName: tileValue.shureShowChannelName,
            initialShureShowIPPort: tileValue.shureShowIPPort,
            initialShureShowFrequency: tileValue.shureShowFrequency,
            initialShureShowBattery: tileValue.shureShowBattery,
            initialShureShowRFStrength: tileValue.shureShowRFStrength,

            onSaveShureDisplayOptions: { showDevice, showChannel, showIP, showFreq, showBatt, showRF in
                pushUndoSnapshot("Update Shure Display Options")
                var tile = tileBinding.wrappedValue
                tile.shureShowDeviceName = showDevice
                tile.shureShowChannelName = showChannel
                tile.shureShowIPPort = showIP
                tile.shureShowFrequency = showFreq
                tile.shureShowBattery = showBatt
                tile.shureShowRFStrength = showRF
                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
            },
            allPersonNames: allPersonNames
        )
        .onAppear {
            captureInitialTileSizeSnapshot(tileValue: tileValue)
        }
        .onChange(of: editingTileID, initial: false) { _, _ in
            captureInitialTileSizeSnapshot(tileValue: tileValue)
        }
        // After an undo/redo the step being coalesced is gone; the next edit must open a new one.
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { note in
            guard let manager = note.object as? UndoManager, manager === undoManager else { return }
            undoCoalescing.coalescer.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { note in
            guard let manager = note.object as? UndoManager, manager === undoManager else { return }
            undoCoalescing.coalescer.reset()
        }
        .tutorialAnchor("root.inspector")
        .frame(width: inspectorPanelWidth)
        .padding(.trailing, 12)
#if os(iOS)
        // iPad should stay dark in our app.
        .preferredColorScheme(.dark)
#endif
    }

    /// Applies `change` to the edited tile (or every selected tile), registering an
    /// undo step only when something actually changes and the change doesn't fold
    /// into the current one (see `InspectorUndoCoalescer`).
    private func commitTileEdit(
        _ actionName: String,
        coalescingKey: String? = nil,
        toSelection: Bool,
        _ change: (inout DashboardTileModel) -> Void
    ) {
        if toSelection {
            guard tabs.indices.contains(selectedTabIndex) else { return }
            var tab = tabs[selectedTabIndex]
            for idx in tab.tiles.indices where selectedTileIDs.contains(tab.tiles[idx].id) {
                change(&tab.tiles[idx])
            }
            guard tab != tabs[selectedTabIndex] else { return }
            registerUndoIfNeeded(actionName, coalescingKey: coalescingKey)
            tabs[selectedTabIndex] = tab
        } else {
            var tile = tileBinding.wrappedValue
            change(&tile)
            guard tile != tileBinding.wrappedValue else { return }
            registerUndoIfNeeded(actionName, coalescingKey: coalescingKey)
            tileBinding.wrappedValue = tile
        }
        markUnsavedAndScheduleSave()
    }

    /// Applies `change` to one module of the edited tile through the same coalescing
    /// undo path, so a drag or a burst of typing in its settings is one undo step.
    private func commitModuleEdit(
        _ moduleID: UUID,
        _ actionName: String,
        _ change: (inout DashboardModuleModel) -> Void
    ) {
        commitTileEdit(
            actionName,
            coalescingKey: InspectorUndoCoalescer.moduleKey(actionName: actionName, moduleID: moduleID),
            toSelection: false
        ) { tile in
            guard let idx = tile.modules?.firstIndex(where: { $0.id == moduleID }) else { return }
            change(&tile.modules![idx])
        }
    }

    private func registerUndoIfNeeded(_ actionName: String, coalescingKey: String? = nil) {
        guard undoCoalescing.coalescer.shouldRegisterUndo(actionName: coalescingKey ?? actionName) else { return }
        pushUndoSnapshot(actionName)
    }

    private func captureInitialTileSizeSnapshot(tileValue: DashboardTileModel) {
        guard tabs.indices.contains(selectedTabIndex) else {
            initialTileSizeWidthSnapshot = ""
            initialTileSizeHeightSnapshot = ""
            initialTileSizeSnapshot = nil
            return
        }

        let selectedIDs = selectedTileIDs.contains(tileValue.id) ? selectedTileIDs : [tileValue.id]
        let sizes = tabs[selectedTabIndex].tiles
            .filter { selectedIDs.contains($0.id) }
            .map { tile in
                DashboardTileSnappingHelper.effectiveSize(
                    for: tile,
                    defaultTileSize: defaultTileSize
                )
            }
        let widths = Set(sizes.map { Int($0.width.rounded()) })
        let heights = Set(sizes.map { Int($0.height.rounded()) })

        if let first = sizes.first {
            let fallbackWidth = Int(first.width.rounded())
            let fallbackHeight = Int(first.height.rounded())
            initialTileSizeWidthSnapshot = widths.count == 1 ? String(widths.first ?? fallbackWidth) : String(fallbackWidth)
            initialTileSizeHeightSnapshot = heights.count == 1 ? String(heights.first ?? fallbackHeight) : String(fallbackHeight)

            if widths.count == 1, heights.count == 1,
               let width = widths.first, let height = heights.first {
                initialTileSizeSnapshot = CGSize(width: CGFloat(width), height: CGFloat(height))
            } else {
                initialTileSizeSnapshot = CGSize(width: CGFloat(fallbackWidth), height: CGFloat(fallbackHeight))
            }
        } else {
            initialTileSizeWidthSnapshot = ""
            initialTileSizeHeightSnapshot = ""
            initialTileSizeSnapshot = nil
        }
    }
}

/// Holds the inspector's `InspectorUndoCoalescer` by reference, so updating it
/// from edit callbacks doesn't invalidate the view.
private final class InspectorUndoCoalescingBox {
    var coalescer = InspectorUndoCoalescer()
}
