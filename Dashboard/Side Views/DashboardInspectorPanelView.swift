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
                pushUndoSnapshot("Edit Text Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .text(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateImageModule: { moduleID, updatedModel in
                pushUndoSnapshot("Edit Image Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .image(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateDocumentModule: { moduleID, updatedModel in
                pushUndoSnapshot("Edit Document Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .document(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateNDIModule: { moduleID, updatedModel in
                pushUndoSnapshot("Edit NDI Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .ndi(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateWebpageModule: { moduleID, updatedModel in
                pushUndoSnapshot("Edit Webpage Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .webpage(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateYouTubeStreamMonitorModule: { moduleID, updatedModel in
                pushUndoSnapshot("Edit YouTube Stream Monitor")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .youtubeStreamMonitor(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateButtonModule: { moduleID, updatedModel in
                pushUndoSnapshot("Edit Button Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .button(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateRosterPickerModule: { moduleID, updatedModel in
                pushUndoSnapshot("Edit Picker Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .rosterPicker(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateSeparator: { moduleID, updatedModel in
                pushUndoSnapshot("Edit Separator Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].kind = .separator(updatedModel)
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },
            onOpenPCOTabSettings: onOpenPCOTabSettings,

            onUpdateTimeModuleConfig: { moduleID, config in
                pushUndoSnapshot("Edit Time Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].timeConfig = config
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateTimecodeModuleConfig: { moduleID, config in
                pushUndoSnapshot("Edit Timecode Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].timecodeConfig = config
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateDAWTransportModuleConfig: { moduleID, config in
                pushUndoSnapshot("Edit DAW Transport Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].dawTransportConfig = config
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateModulePadding: { moduleID, top, bottom in
                pushUndoSnapshot("Edit Module Padding")

                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    if let top = top { modules[idx].paddingTop = top }
                    if let bottom = bottom { modules[idx].paddingBottom = bottom }

                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateModuleScale: { moduleID, scale in
                pushUndoSnapshot("Edit Module Scale")

                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules,
                      let mIdx = modules.firstIndex(where: { $0.id == moduleID }) else {
                    return
                }

                // Height is in points; nil means Auto.
                modules[mIdx].moduleHeightPoints = scale
                // Clear legacy scale so height points are the sole driver.
                modules[mIdx].moduleScale = nil

                tile.modules = modules
                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
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
                pushUndoSnapshot("Edit Tile Appearance")

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

                markUnsavedAndScheduleSave()
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
                pushUndoSnapshot("Edit Tile Padding")

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

                markUnsavedAndScheduleSave()
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
                pushUndoSnapshot("Edit Text Formatting")

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

                markUnsavedAndScheduleSave()
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

            onUpdatePCOModuleConfig: { moduleID, newConfig in
                pushUndoSnapshot("Edit PCO Module")
                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules else { return }

                if let idx = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[idx].pcoConfig = newConfig
                    tile.modules = modules
                    tileBinding.wrappedValue = tile
                    markUnsavedAndScheduleSave()
                }
            },

            onUpdateShureModuleConfig: { moduleID, newConfig in
                pushUndoSnapshot("Edit Shure Module")

                var tile = tileBinding.wrappedValue
                guard var modules = tile.modules,
                      let moduleIndex = modules.firstIndex(where: { $0.id == moduleID }) else {
                    return
                }

                // Update the per-module Shure configuration.
                modules[moduleIndex].shureConfig = newConfig
                tile.modules = modules

                // Keep tile-level Shure properties in sync for backward compatibility.
                tile.shureSelectedChannel = newConfig.selectedChannel
                tile.shureShowDeviceName = newConfig.showDeviceName
                tile.shureShowChannelName = newConfig.showChannelName
                tile.shureShowIPPort = newConfig.showIPPort
                tile.shureShowFrequency = newConfig.showFrequency
                tile.shureShowBattery = newConfig.showBattery
                tile.shureShowRFStrength = newConfig.showRFStrength

                tileBinding.wrappedValue = tile
                markUnsavedAndScheduleSave()
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
        .tutorialAnchor("root.inspector")
        .frame(width: inspectorPanelWidth)
        .padding(.trailing, 12)
#if os(iOS)
        // iPad should stay dark in our app.
        .preferredColorScheme(.dark)
#endif
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
