import SwiftUI

#if os(macOS)
import CoreAudio
#endif

extension DashboardTileEditView {

    /// Applies `change` to the local copy (for an immediate UI refresh), then writes it to the
    /// tile through the inspector's undo path, named "Change <settingsName> Settings".
    /// A drag or a burst of typing in one module's settings becomes a single undo step.
    func commitModuleEdit(
        _ moduleID: UUID,
        settingsName: String,
        _ change: (inout DashboardModuleModel) -> Void
    ) {
        guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
        change(&editableModules[idx])
        onCommitModuleChange(moduleID, TileEditorCopy.moduleSettingsActionName(settingsName), change)
    }

    @ViewBuilder func moduleSettings_person(module: DashboardModuleModel) -> some View {
        // Module-owned settings (PersonTileView.swift)
        let moduleID = module.id
        let initialModel: PersonTileModel = {
            if case .person(let personModel) = module.kind {
                return personModel
            }
            return PersonTileModel(name: "Person", role: "Role", initials: "P")
        }()
        let personBinding = Binding<PersonTileModel>(
            get: {
                if let latest = editableModules.first(where: { $0.id == moduleID }),
                   case .person(let personModel) = latest.kind {
                    return personModel
                }
                return initialModel
            },
            set: { newValue in
                commitModuleEdit(moduleID, settingsName: "Person") { $0.kind = .person(newValue) }
                persistChanges()
            }
        )

        // Full catalog of positions by Team (preferred). This enables a Team picker
        // and prevents position options from disappearing week-to-week.
        let positionsByTeamName: [String: [String]] = tab.pcoTeamPositionsByTeamName ?? [:]
        let assignmentCandidates = tab.pcoPositionAssignmentCandidates ?? [:]

        // Legacy flat list (used when the settings view is in legacy mode or as a fallback).
        // IMPORTANT: make this a union across ALL available teams, not just the currently
        // selected team name, so multi-team tabs (Band/Orchestra/Singers) keep all options.
        let positions: [String] = {
            if !positionsByTeamName.isEmpty {
                var set = Set<String>()
                for list in positionsByTeamName.values {
                    for p in list {
                        let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { set.insert(trimmed) }
                    }
                }
                return Array(set).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }

            // Fallback: only positions that are assigned in the current plan
            return (
                tab.pcoAllPositionAssignments?.keys.map { $0 } ??
                tab.pcoPositionAssignments?.keys.map { $0 } ??
                []
            ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }()

        PersonModuleSettingsView(
            model: personBinding,
            isPCOConfigured: (tab.serviceTypeID != nil),
            availablePositions: positions,
            availablePositionsByTeamName: positionsByTeamName,
            assignmentCandidatesByLookupKey: assignmentCandidates,
            onPersist: { persistChanges() }
        )
    }

    @ViewBuilder func moduleSettings_pcoRundown(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        // Bind directly into this module's PCO config.
        let configBinding = Binding<PCOModuleConfig>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.pcoConfig ?? PCOModuleConfig.rundownDefault()
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }

                // Update local copy for immediate UI refresh.
                editableModules[idx].pcoConfig = newValue

                // Push through the existing callback so the live tile updates.
                onUpdatePCOModuleConfig(moduleID, newValue)

                // Persist any tile-level formatting that needs save callbacks.
                persistChanges()
            }
        )

        PCOModuleSettingsInspector(
            config: configBinding,
            tab: tab,
            onPersist: { persistChanges() },
            onOpenTabSettings: onOpenPCOTabSettings
        )
    }

    @ViewBuilder func moduleSettings_pcoTeamAssignments(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        let configBinding = Binding<PCOModuleConfig>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.pcoConfig ?? PCOModuleConfig.teamAssignmentsDefault()
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                editableModules[idx].pcoConfig = newValue
                onUpdatePCOModuleConfig(moduleID, newValue)
                persistChanges()
            }
        )

        // Filter the cached team assignments by this module's selected
        // teams (or the tab's selection when none is set on the module)
        // so the per-assignment editor only shows relevant rows.
        let cachedAssignments: [PCOTeamAssignmentRow] = {
            let allowedTeamRaw = editableModules.first(where: { $0.id == moduleID })?.pcoConfig?.teamName
                ?? tab.teamName ?? ""
            let allowedTeams = Set(
                allowedTeamRaw
                    .components(separatedBy: "||")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            guard !allowedTeams.isEmpty else { return tab.pcoCachedTeamAssignments }
            return tab.pcoCachedTeamAssignments.filter { row in
                let team = (row.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return allowedTeams.contains(team)
            }
        }()

        PCOTeamAssignmentsSettingsInspector(
            config: configBinding,
            tab: tab,
            sharedRosters: sharedRosters,
            cachedAssignments: cachedAssignments,
            onPersist: { persistChanges() },
            onOpenTabSettings: onOpenPCOTabSettings
        )
    }

    @ViewBuilder func moduleSettings_rosterTeamAssignments(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        let configBinding = Binding<RosterTeamAssignmentsConfig>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.rosterTeamAssignmentsConfig
                    ?? RosterTeamAssignmentsConfig.defaults()
            },
            set: { newValue in
                commitModuleEdit(moduleID, settingsName: "Roster Team Assignments") {
                    $0.rosterTeamAssignmentsConfig = newValue
                }
                persistChanges()
            }
        )

        RosterTeamAssignmentsSettingsInspector(
            config: configBinding,
            tab: tab,
            sharedRosters: sharedRosters,
            onPersist: { persistChanges() }
        )
    }

    @ViewBuilder func moduleSettings_time(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        let configBinding = Binding<TimeModuleConfig>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.timeConfig ?? TimeModuleConfig.default()
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                editableModules[idx].timeConfig = newValue
                onUpdateTimeModuleConfig(moduleID, newValue)
                persistChanges()
            }
        )

        TimeModuleSettingsHost(
            config: configBinding,
            onPersist: { persistChanges() }
        )
    }

    @ViewBuilder func moduleSettings_timecode(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        let configBinding = Binding<TimecodeModuleConfig>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.timecodeConfig ?? TimecodeModuleConfig.default()
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                editableModules[idx].timecodeConfig = newValue
                onUpdateTimecodeModuleConfig(moduleID, newValue)
                persistChanges()
            }
        )

        TimecodeModuleSettingsHost(
            config: configBinding,
            onPersist: { persistChanges() }
        )
    }

    @ViewBuilder func moduleSettings_dawTransport(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        let configBinding = Binding<DAWTransportModuleConfiguration>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.dawTransportConfig ?? DAWTransportModuleConfiguration.default()
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                editableModules[idx].dawTransportConfig = newValue
                onUpdateDAWTransportModuleConfig(moduleID, newValue)
                persistChanges()
            }
        )

        DAWTransportModuleSettingsHost(
            config: configBinding,
            onPersist: { persistChanges() }
        )
    }

    @ViewBuilder func moduleSettings_shureWireless(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        let configBinding = Binding<ShureModuleConfig>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.shureConfig ?? ShureModuleConfig.default()
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                editableModules[idx].shureConfig = newValue
                onUpdateShureModuleConfig(moduleID, newValue)
                persistChanges()
            }
        )

        ShureModuleSettingsInspector(
            config: configBinding,
            channels: shureChannelDescriptors,
            onPersist: { persistChanges() }
        )
        .onAppear {
            // Seed module-owned config once (migration from tile-level initial values).
            guard let currentIdx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
            if editableModules[currentIdx].shureConfig == nil {
                var seeded = ShureModuleConfig.default()
                seeded.selectedChannel = initialShureSelection
                seeded.showDeviceName = initialShureShowDeviceName
                seeded.showChannelName = initialShureShowChannelName
                seeded.showIPPort = initialShureShowIPPort
                seeded.showFrequency = initialShureShowFrequency
                seeded.showBattery = initialShureShowBattery
                seeded.showRFStrength = initialShureShowRFStrength

                // A one-time migration, not an edit: write it without an undo step (like the
                // ProPresenter/Resolume seeding). Undoing it would only re-seed on appear.
                editableModules[currentIdx].shureConfig = seeded
                if let tileIndex = tab.tiles.firstIndex(where: { $0.id == tileID }),
                   let moduleIndex = tab.tiles[tileIndex].modules?.firstIndex(where: { $0.id == moduleID }) {
                    tab.tiles[tileIndex].modules?[moduleIndex].shureConfig = seeded
                }
                persistChanges()
            }
        }
    }

    @ViewBuilder func moduleSettings_shureOverview(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let configBinding = Binding<ShureOverviewModuleConfig>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.shureOverviewConfig ?? ShureOverviewModuleConfig.default()
            },
            set: { newValue in
                // Write config back into the live dashboard model so the tile
                // re-renders immediately (e.g. displayStyle cards/list switch).
                commitModuleEdit(moduleID, settingsName: "Shure Overview") {
                    $0.shureOverviewConfig = newValue
                }
                persistChanges()
            }
        )

        ShureOverviewModuleSettingsInspector(
            config: configBinding,
            allPersonNames: allPersonNames,
            onPersist: { persistChanges() }
        )
        .onAppear {
            guard let currentIdx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
            if editableModules[currentIdx].shureOverviewConfig == nil {
                editableModules[currentIdx].shureOverviewConfig = ShureOverviewModuleConfig.default()
                persistChanges()
            }
        }
    }

    @ViewBuilder func moduleSettings_sennheiserWireless(module: DashboardModuleModel) -> some View {
        if !module.kind.isAvailableInCurrentBuild {
            UnavailableModuleView(
                title: "Sennheiser Wireless",
                message: module.kind.unavailableInCurrentBuildMessage
            )
        } else {
        let moduleID = module.id

        let configBinding = Binding<SennheiserWirelessModuleConfig>(
            get: {
                editableModules.first(where: { $0.id == moduleID })?.sennheiserConfig ?? SennheiserWirelessModuleConfig()
            },
            set: { newValue in
                commitModuleEdit(moduleID, settingsName: "Sennheiser") { $0.sennheiserConfig = newValue }
                persistChanges()
            }
        )

        SennheiserWirelessModuleInspector(config: configBinding)
        }
    }

    @ViewBuilder func moduleSettings_proPresenter(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        let configBinding = Binding<ProPresenterModuleConfig>(
            get: {
                if let existing = editableModules.first(where: { $0.id == moduleID })?.proPresenterConfig {
                    return existing
                }
                var seeded = ProPresenterModuleConfig()
                seeded.id = moduleID
                return seeded
            },
            set: { newValue in
                guard editableModules.contains(where: { $0.id == moduleID }) else { return }

                // Push live config updates so the module immediately switches endpoints/modes.
                ProPresenterModulePlugin.sharedService.setConfig(moduleID: moduleID, config: newValue)

                // Persist ProPresenter module config back into the dashboard model.
                commitModuleEdit(moduleID, settingsName: "ProPresenter") { $0.proPresenterConfig = newValue }
                persistChanges()
            }
        )

        ProPresenterModuleEditView(moduleID: moduleID, config: configBinding)
            .onAppear {
                // Seed/repair module-owned config once.
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }

                if editableModules[idx].proPresenterConfig == nil {
                    var seeded = ProPresenterModuleConfig()
                    seeded.id = moduleID
                    var updatedModule = editableModules[idx]
                    updatedModule.proPresenterConfig = seeded
                    editableModules[idx] = updatedModule
                    ProPresenterModulePlugin.sharedService.setConfig(moduleID: moduleID, config: seeded)

                    if let tileIndex = tab.tiles.firstIndex(where: { $0.id == tileID }) {
                        if var tileModules = tab.tiles[tileIndex].modules,
                           let moduleIndex = tileModules.firstIndex(where: { $0.id == moduleID }) {
                            tileModules[moduleIndex].proPresenterConfig = seeded
                            tab.tiles[tileIndex].modules = tileModules
                        }
                    }
                    persistChanges()
                } else if editableModules[idx].proPresenterConfig?.id != moduleID {
                    var updatedModule = editableModules[idx]
                    updatedModule.proPresenterConfig?.id = moduleID
                    editableModules[idx] = updatedModule
                    if let repaired = updatedModule.proPresenterConfig {
                        ProPresenterModulePlugin.sharedService.setConfig(moduleID: moduleID, config: repaired)
                        if let tileIndex = tab.tiles.firstIndex(where: { $0.id == tileID }) {
                            if var tileModules = tab.tiles[tileIndex].modules,
                               let moduleIndex = tileModules.firstIndex(where: { $0.id == moduleID }) {
                                tileModules[moduleIndex].proPresenterConfig = repaired
                                tab.tiles[tileIndex].modules = tileModules
                            }
                        }
                    }
                    persistChanges()
                }
            }
    }

    @ViewBuilder func moduleSettings_rosterPicker(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let initialModel = module.rosterPickerModel ?? RosterPickerModuleModel()

        let modelBinding = Binding<RosterPickerModuleModel>(
            get: {
                // Always read from editableModules so the binding reflects the
                // latest persisted state rather than the stale captured value.
                if let latest = editableModules.first(where: { $0.id == moduleID }),
                   case .rosterPicker(let m) = latest.kind {
                    return m
                }
                return initialModel
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                editableModules[idx].kind = .rosterPicker(newValue)
                onUpdateRosterPickerModule(moduleID, newValue)
                persistChanges()
            }
        )

        RosterPickerModuleSettingsView(
            model: modelBinding,
            tab: $tab,
            sharedRosters: sharedRosters,
            onPersist: {
                persistChanges()
            }
        )
    }

    @ViewBuilder func moduleSettings_text(module: DashboardModuleModel) -> some View {
        // Plugin-owned settings UI (lives with the module)
        let initialModel = module.textModel ?? TextModuleModel(
            header: nil,
            content: AttributedString("")
        )

        let modelBinding = Binding<TextModuleModel>(
            get: { module.textModel ?? initialModel },
            set: { newValue in
                if let idx = editableModules.firstIndex(where: { $0.id == module.id }) {
                    editableModules[idx].kind = .text(newValue)
                }
                onUpdateTextModule(module.id, newValue)
                persistChanges()
            }
        )

        TextModuleSettingsView(moduleId: module.id, tab: $tab, model: modelBinding, onPersist: {
            persistChanges()
        })
    }

    @ViewBuilder func moduleSettings_image(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let initialModel = module.imageModel ?? ImageModuleModel()

        let modelBinding = Binding<ImageModuleModel>(
            get: {
                if let latest = editableModules.first(where: { $0.id == moduleID }),
                   case .image(let model) = latest.kind {
                    return model
                }
                return initialModel
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                var updatedModule = editableModules[idx]
                updatedModule.kind = .image(newValue)
                editableModules[idx] = updatedModule

                onUpdateImageModule(moduleID, newValue)
                persistChanges()
            }
        )

        ImageModuleSettingsView(model: modelBinding, onPersist: {
            persistChanges()
        })
    }

    @ViewBuilder func moduleSettings_document(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let initialModel = module.documentModel ?? DocumentModuleModel()

        let modelBinding = Binding<DocumentModuleModel>(
            get: {
                if let latest = editableModules.first(where: { $0.id == moduleID }),
                   case .document(let model) = latest.kind {
                    return model
                }
                return initialModel
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                var updatedModule = editableModules[idx]
                updatedModule.kind = .document(newValue)
                editableModules[idx] = updatedModule

                onUpdateDocumentModule(moduleID, newValue)
                persistChanges()
            }
        )

        DocumentModuleSettingsView(model: modelBinding, onPersist: {
            persistChanges()
        })
    }

    @ViewBuilder func moduleSettings_ndi(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let initialModel = module.ndiModel ?? NDIModuleModel()

        let modelBinding = Binding<NDIModuleModel>(
            get: {
                if let latest = editableModules.first(where: { $0.id == moduleID }),
                   case .ndi(let model) = latest.kind {
                    return model
                }
                return initialModel
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                editableModules[idx].kind = .ndi(newValue)
                onUpdateNDIModule(moduleID, newValue)
                persistChanges()
            }
        )

        NDIModuleSettingsView(model: modelBinding, onPersist: {
            persistChanges()
        })
    }

    @ViewBuilder func moduleSettings_webpage(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let initialModel = module.webpageModel ?? WebpageModuleModel()

        let modelBinding = Binding<WebpageModuleModel>(
            get: {
                if let latest = editableModules.first(where: { $0.id == moduleID }),
                   case .webpage(let model) = latest.kind {
                    return model
                }
                return initialModel
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                var updatedModule = editableModules[idx]
                updatedModule.kind = .webpage(newValue)
                editableModules[idx] = updatedModule

                onUpdateWebpageModule(moduleID, newValue)
                persistChanges()
            }
        )

        WebpageModuleSettingsView(model: modelBinding, onPersist: {
            persistChanges()
        })
    }

    @ViewBuilder func moduleSettings_youtubeStreamMonitor(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let initialModel = module.youtubeStreamMonitorModel ?? YouTubeStreamMonitorModuleModel()

        let modelBinding = Binding<YouTubeStreamMonitorModuleModel>(
            get: {
                if let latest = editableModules.first(where: { $0.id == moduleID }),
                   case .youtubeStreamMonitor(let model) = latest.kind {
                    return model
                }
                return initialModel
            },
            set: { newValue in
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }
                var updatedModule = editableModules[idx]
                updatedModule.kind = .youtubeStreamMonitor(newValue)
                editableModules[idx] = updatedModule

                onUpdateYouTubeStreamMonitorModule(moduleID, newValue)
                persistChanges()
            }
        )

        YouTubeStreamMonitorSettingsView(model: modelBinding, onPersist: {
            persistChanges()
        })
    }

    @ViewBuilder func moduleSettings_button(module: DashboardModuleModel) -> some View {
        let initialModel = module.buttonModel ?? ButtonModuleModel()

        let modelBinding = Binding<ButtonModuleModel>(
            get: { module.buttonModel ?? initialModel },
            set: { newValue in
                if let idx = editableModules.firstIndex(where: { $0.id == module.id }) {
                    editableModules[idx].kind = .button(newValue)
                }
                onUpdateButtonModule(module.id, newValue)
                persistChanges()
            }
        )

        VStack(alignment: .leading, spacing: 10) {
            if isButtonLinkedInAutomation(buttonModuleId: modelBinding.wrappedValue.id) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .imageScale(.small)
                    Text("Linked in Automation")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.orange.opacity(0.30), lineWidth: 1)
                )
                .accessibilityLabel("This button is wired to actions in Automation view")
            }

            ButtonModuleSettingsView(model: modelBinding, onPersist: {
                persistChanges()
            })
        }
    }

    @ViewBuilder func moduleSettings_separator(module: DashboardModuleModel) -> some View {
        // Plugin-owned settings UI (lives with the module)
        let initialModel: SeparatorModuleModel = {
            if let latest = editableModules.first(where: { $0.id == module.id }),
               case .separator(let m) = latest.kind {
                return m
            }
            return SeparatorModuleModel()
        }()

        let modelBinding = Binding<SeparatorModuleModel>(
            get: {
                if let latest = editableModules.first(where: { $0.id == module.id }),
                   case .separator(let m) = latest.kind {
                    return m
                }
                return initialModel
            },
            set: { newValue in
                if let idx = editableModules.firstIndex(where: { $0.id == module.id }) {
                    editableModules[idx].kind = .separator(newValue)
                }
                onUpdateSeparator(module.id, newValue)
                persistChanges()
            }
        )

        SeparatorModuleSettingsView(model: modelBinding, onPersist: {
            persistChanges()
        })
    }

    @ViewBuilder func moduleSettings_resolume(module: DashboardModuleModel) -> some View {
        let moduleID = module.id

        let configBinding = Binding<ResolumeModuleConfig>(
            get: {
                if let existing = editableModules.first(where: { $0.id == moduleID })?.resolumeConfig {
                    return existing
                }
                var seeded = ResolumeModuleConfig()
                seeded.id = moduleID
                return seeded
            },
            set: { newValue in
                commitModuleEdit(moduleID, settingsName: "Resolume") { $0.resolumeConfig = newValue }
                persistChanges()
            }
        )

        ResolumeModuleSettingsView(config: configBinding)
            .onAppear {
                guard let idx = editableModules.firstIndex(where: { $0.id == moduleID }) else { return }

                // Seed/repair module-owned config once.
                if editableModules[idx].resolumeConfig == nil {
                    var seeded = ResolumeModuleConfig()
                    seeded.id = moduleID
                    editableModules[idx].resolumeConfig = seeded

                    // Persist back into the dashboard model so it saves/loads.
                    if let tileIndex = tab.tiles.firstIndex(where: { $0.id == tileID }) {
                        if var tileModules = tab.tiles[tileIndex].modules,
                           let moduleIndex = tileModules.firstIndex(where: { $0.id == moduleID }) {
                            tileModules[moduleIndex].resolumeConfig = seeded
                            tab.tiles[tileIndex].modules = tileModules
                        }
                    }

                    persistChanges()
                } else if editableModules[idx].resolumeConfig?.id != moduleID {
                    editableModules[idx].resolumeConfig?.id = moduleID
                    if let repaired = editableModules[idx].resolumeConfig {
                        if let tileIndex = tab.tiles.firstIndex(where: { $0.id == tileID }) {
                            if var tileModules = tab.tiles[tileIndex].modules,
                               let moduleIndex = tileModules.firstIndex(where: { $0.id == moduleID }) {
                                tileModules[moduleIndex].resolumeConfig = repaired
                                tab.tiles[tileIndex].modules = tileModules
                            }
                        }
                    }
                    persistChanges()
                }
            }
    }

    // MARK: - DbReader Section Helpers (split to avoid iOS stack overflow)

    @ViewBuilder private func dbReader_generalSection(
        currentModel: DbReaderModuleModel,
        updateModel: @escaping (DbReaderModuleModel) -> Void
    ) -> some View {
        settingsSection("General") {
            Toggle("Enabled", isOn: Binding(
                get: { currentModel.isEnabled },
                set: { v in var u = currentModel; u.isEnabled = v; updateModel(u) }
            ))
            Toggle("Show title", isOn: Binding(
                get: { currentModel.showsTitle },
                set: { v in var u = currentModel; u.showsTitle = v; updateModel(u) }
            ))
        }
    }

    @ViewBuilder private func dbReader_inputSection(
        currentModel: DbReaderModuleModel,
        updateModel: @escaping (DbReaderModuleModel) -> Void
    ) -> some View {
        settingsSection("Input") {
            let inputs = AudioInputsConfigStore.shared.inputs
            Picker("Input", selection: Binding(
                get: { currentModel.inputID },
                set: { v in var u = currentModel; u.inputID = v; updateModel(u) }
            )) {
                Text("None").tag(nil as UUID?)
                ForEach(inputs) { input in
                    HStack { Circle().fill(input.color.swiftUIColor).frame(width: 8, height: 8); Text(input.name) }
                        .tag(input.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            configureInputsButton
        }
    }

    @ViewBuilder private func dbReader_weightingSection(
        currentModel: DbReaderModuleModel,
        updateModel: @escaping (DbReaderModuleModel) -> Void
    ) -> some View {
        settingsSection("Weighting") {
            Picker("Weighting", selection: Binding(
                get: { currentModel.weighting },
                set: { v in var u = currentModel; u.weighting = v; updateModel(u) }
            )) {
                Text("A").tag(DbWeighting.a)
                Text("C").tag(DbWeighting.c)
                Text("Z").tag(DbWeighting.z)
                Text("C-A").tag(DbWeighting.ca)
            }
            .pickerStyle(.segmented)

            Picker("Time Weighting", selection: Binding(
                get: { currentModel.timeWeighting },
                set: { v in var u = currentModel; u.timeWeighting = v; updateModel(u) }
            )) {
                Text("Fast").tag(DbTimeWeighting.fast)
                Text("Slow").tag(DbTimeWeighting.slow)
            }
            .pickerStyle(.segmented)
            .disabled(currentModel.weighting == .ca)

            if currentModel.weighting == .ca {
                Text("C-A shows Fast and Slow at the same time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func dbReader_averagingSection(
        currentModel: DbReaderModuleModel,
        updateModel: @escaping (DbReaderModuleModel) -> Void
    ) -> some View {
        settingsSection("Averaging") {
            Toggle("Average SPL", isOn: Binding(
                get: { currentModel.averagingEnabled },
                set: { v in var u = currentModel; u.averagingEnabled = v; updateModel(u) }
            ))

            if currentModel.averagingEnabled {
                HStack {
                    Text("Average Window")
                    Spacer()
                    TextField("", value: Binding(
                        get: { currentModel.averagingWindowSeconds },
                        set: { v in var u = currentModel; u.averagingWindowSeconds = v; updateModel(u) }
                    ), formatter: historySecondsFormatter)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    Text("sec").foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("1m") { var u = currentModel; u.averagingWindowSeconds = 60; updateModel(u) }
                    Button("5m") { var u = currentModel; u.averagingWindowSeconds = 300; updateModel(u) }
                    Button("10m") { var u = currentModel; u.averagingWindowSeconds = 600; updateModel(u) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private func dbReader_displayGraphSubsection(
        currentModel: DbReaderModuleModel,
        updateModel: @escaping (DbReaderModuleModel) -> Void
    ) -> some View {
        Toggle("Show SPL Value", isOn: Binding(
            get: { currentModel.showMainValue },
            set: { v in var u = currentModel; u.showMainValue = v; updateModel(u) }
        ))

        Toggle("Show Graph", isOn: Binding(
            get: { currentModel.showGraph },
            set: { v in var u = currentModel; u.showGraph = v; updateModel(u) }
        ))

        if currentModel.showGraph {
            Toggle("Graph Units", isOn: Binding(
                get: { currentModel.showGraphUnits },
                set: { v in var u = currentModel; u.showGraphUnits = v; updateModel(u) }
            ))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Graph Height")
                    Spacer()
                    Text("\(Int(round(currentModel.graphHeight)))").foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { currentModel.graphHeight },
                    set: { v in var u = currentModel; u.graphHeight = v; updateModel(u) }
                ), in: 120...300)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Visible History")
                    Spacer()
                    Text("\(Int(round(currentModel.historyWindowSeconds)))").foregroundStyle(.secondary)
                }
                HStack {
                    Slider(value: Binding(
                        get: { currentModel.historyWindowSeconds },
                        set: { v in var u = currentModel; u.historyWindowSeconds = Double(Int(round(v))); updateModel(u) }
                    ), in: 5...30)
                    TextField("", value: Binding(
                        get: { currentModel.historyWindowSeconds },
                        set: { v in var u = currentModel; u.historyWindowSeconds = v; updateModel(u) }
                    ), formatter: historySecondsFormatter)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("sec").foregroundStyle(.secondary)
                }
            }
        }

        if currentModel.showMainValue {
            Toggle("Show Bar Meter", isOn: Binding(
                get: { currentModel.showBarMeter },
                set: { v in var u = currentModel; u.showBarMeter = v; updateModel(u) }
            ))
        }
    }

    @ViewBuilder private func dbReader_displayLimitsSubsection(
        currentModel: DbReaderModuleModel,
        updateModel: @escaping (DbReaderModuleModel) -> Void
    ) -> some View {
        Toggle("Color by Limits", isOn: Binding(
            get: { currentModel.limitColorEnabled },
            set: { v in var u = currentModel; u.limitColorEnabled = v; updateModel(u) }
        ))

        if currentModel.limitColorEnabled {
            if currentModel.weighting == .ca {
                HStack {
                    Text("Upper Limit"); Spacer()
                    TextField("12", value: Binding(
                        get: { currentModel.caUpperLimit },
                        set: { v in var u = currentModel; u.caUpperLimit = max(u.caLowerLimit + 0.5, v); updateModel(u) }
                    ), format: .number)
                    .frame(width: 60).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    Text("dB").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Lower Limit"); Spacer()
                    TextField("8", value: Binding(
                        get: { currentModel.caLowerLimit },
                        set: { v in var u = currentModel; u.caLowerLimit = min(u.caUpperLimit - 0.5, max(0, v)); updateModel(u) }
                    ), format: .number)
                    .frame(width: 60).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    Text("dB").foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text("Warning"); Spacer()
                    TextField("", text: $dbReaderLimitWarningText)
                        .frame(width: 60).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                        .onChange(of: dbReaderLimitWarningText) { _, newValue in
                            guard let value = Double(newValue) else { return }
                            let clamped = min(max(value, -120), 200)
                            var u = currentModel; u.limitWarningDb = min(clamped, u.limitAlertDb); updateModel(u)
                        }
                        .onSubmit {
                            if let value = Double(dbReaderLimitWarningText) {
                                dbReaderLimitWarningText = String(format: "%.1f", min(max(value, -120), 200))
                            }
                        }
                    Text("dB").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Alert"); Spacer()
                    TextField("", text: $dbReaderLimitAlertText)
                        .frame(width: 60).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                        .onChange(of: dbReaderLimitAlertText) { _, newValue in
                            guard let value = Double(newValue) else { return }
                            let clamped = min(max(value, -120), 200)
                            var u = currentModel; u.limitAlertDb = max(clamped, u.limitWarningDb); updateModel(u)
                        }
                        .onSubmit {
                            if let value = Double(dbReaderLimitAlertText) {
                                dbReaderLimitAlertText = String(format: "%.1f", min(max(value, -120), 200))
                            }
                        }
                    Text("dB").foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(currentModel.weighting == .ca ? "Safe Color" : "Normal Color"); Spacer()
                ColorPicker(currentModel.weighting == .ca ? "Safe Color" : "Normal Color", selection: Binding(
                    get: { currentModel.limitColorNormal.swiftUIColor },
                    set: { v in var u = currentModel; u.limitColorNormal = CodableColor(v); updateModel(u) }
                )).labelsHidden()
            }
            HStack {
                Text(currentModel.weighting == .ca ? "Limit Color" : "Warning Color"); Spacer()
                ColorPicker(currentModel.weighting == .ca ? "Limit Color" : "Warning Color", selection: Binding(
                    get: { currentModel.limitColorWarning.swiftUIColor },
                    set: { v in var u = currentModel; u.limitColorWarning = CodableColor(v); updateModel(u) }
                )).labelsHidden()
            }
            HStack {
                Text(currentModel.weighting == .ca ? "Out of Range Color" : "Alert Color"); Spacer()
                ColorPicker(currentModel.weighting == .ca ? "Out of Range Color" : "Alert Color", selection: Binding(
                    get: { currentModel.limitColorAlert.swiftUIColor },
                    set: { v in var u = currentModel; u.limitColorAlert = CodableColor(v); updateModel(u) }
                )).labelsHidden()
            }
        }
    }

    @ViewBuilder private func dbReader_displaySection(
        currentModel: DbReaderModuleModel,
        updateModel: @escaping (DbReaderModuleModel) -> Void
    ) -> some View {
        settingsSection("Display") {
            dbReader_displayGraphSubsection(currentModel: currentModel, updateModel: updateModel)
            dbReader_displayLimitsSubsection(currentModel: currentModel, updateModel: updateModel)
        }
    }

    @ViewBuilder private func dbReader_caLimitsSection(
        currentModel: DbReaderModuleModel,
        updateModel: @escaping (DbReaderModuleModel) -> Void
    ) -> some View {
        settingsSection("C-A Limits") {
            HStack {
                Text("Upper limit").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("12", value: Binding(
                    get: { currentModel.caUpperLimit },
                    set: { v in var u = currentModel; u.caUpperLimit = max(u.caLowerLimit + 0.5, v); updateModel(u) }
                ), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 60)
                Text("dB").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Lower limit").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("8", value: Binding(
                    get: { currentModel.caLowerLimit },
                    set: { v in var u = currentModel; u.caLowerLimit = min(u.caUpperLimit - 0.5, max(0, v)); updateModel(u) }
                ), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 60)
                Text("dB").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func dbReader_advancedSection() -> some View {
        settingsSection("Advanced") {
            Button("Advanced…") { showsDbReaderAdvanced = true }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder func moduleSettings_dbReader(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let currentModel: DbReaderModuleModel = {
            if let latest = editableModules.first(where: { $0.id == moduleID }),
               case .dbReader(let model) = latest.kind {
                return model
            }
            if case .dbReader(let model) = module.kind { return model }
            return DbReaderModuleModel()
        }()
        let updateModel: (DbReaderModuleModel) -> Void = { updated in
            commitModuleEdit(moduleID, settingsName: "SPL Meter") { $0.kind = .dbReader(updated) }
            persistChanges()
        }
        let dbReaderController = DbReaderControllerStore.shared.controller(moduleId: moduleID, tileId: tileID, settings: currentModel)

        VStack(alignment: .leading, spacing: 12) {
            dbReader_generalSection(currentModel: currentModel, updateModel: updateModel)
            dbReader_inputSection(currentModel: currentModel, updateModel: updateModel)
            dbReader_weightingSection(currentModel: currentModel, updateModel: updateModel)
            dbReader_averagingSection(currentModel: currentModel, updateModel: updateModel)
            dbReader_displaySection(currentModel: currentModel, updateModel: updateModel)
            if currentModel.weighting == .ca && !currentModel.limitColorEnabled {
                dbReader_caLimitsSection(currentModel: currentModel, updateModel: updateModel)
            }
            dbReader_advancedSection()
            // Export options now live in the Export flow.
        }
        .onAppear {
            if dbReaderLimitWarningText.isEmpty {
                dbReaderLimitWarningText = String(format: "%.1f", currentModel.limitWarningDb)
            }
            if dbReaderLimitAlertText.isEmpty {
                dbReaderLimitAlertText = String(format: "%.1f", currentModel.limitAlertDb)
            }
            dbReaderController.updateSettings(currentModel)
            dbReaderController.setPreviewActive(false)
        }
        .onChange(of: currentModel.inputID) { _, _ in dbReaderController.updateSettings(currentModel) }
        .onChange(of: currentModel.isEnabled) { _, _ in dbReaderController.updateSettings(currentModel) }
        .onDisappear { dbReaderController.setPreviewActive(false) }
        .onChange(of: showsDbReaderCalibration) { _, isPresented in
            dbReaderController.updateSettings(currentModel)
            dbReaderController.setPreviewActive(isPresented)
        }
        .sheet(isPresented: $showsDbReaderCalibration) {
            // Calibration now lives at the input level (AudioInputConfig.calibrationOffsetDb).
            // The sheet reads and writes through AudioInputsConfigStore directly.
            let inputCal = currentModel.inputID.flatMap {
                AudioInputsConfigStore.shared.input(for: $0)?.calibrationOffsetDb
            } ?? 0
            DbReaderCalibrationSheet(
                targetDb: $dbReaderCalibrationTargetDb,
                currentSpl: resolvedDbReaderZSlow(for: moduleID, model: currentModel),
                currentRawDbFS: resolvedDbReaderRawDbFS(for: moduleID, model: currentModel),
                currentOffset: inputCal,
                liveSplProvider: { dbReaderController.currentZSlow },
                liveRawDbFSProvider: { dbReaderController.rawDbFS },
                onApply: { targetDb, capturedSpl, capturedRawDbFS in
                    // measuredVal is uncalibrated dBFS, so the offset is simply target − raw.
                    // The SPL fallback does include the current offset, so it is added back.
                    let measuredVal = capturedRawDbFS ?? resolvedDbReaderRawDbFS(for: moduleID, model: currentModel)
                    let measuredSpl = capturedSpl ?? resolvedDbReaderZSlow(for: moduleID, model: currentModel)
                    let currentCal = currentModel.inputID.flatMap {
                        AudioInputsConfigStore.shared.input(for: $0)?.calibrationOffsetDb
                    } ?? 0
                    let newCal: Double
                    if measuredVal.isFinite && measuredVal != 0 {
                        newCal = targetDb - measuredVal
                    } else {
                        newCal = targetDb - measuredSpl + currentCal
                    }
                    if let inputID = currentModel.inputID,
                       let idx = AudioInputsConfigStore.shared.inputs.firstIndex(where: { $0.id == inputID }) {
                        AudioInputsConfigStore.shared.inputs[idx].calibrationOffsetDb = newCal
                    }
                },
                onSetOffset: { offset in
                    if let inputID = currentModel.inputID,
                       let idx = AudioInputsConfigStore.shared.inputs.firstIndex(where: { $0.id == inputID }) {
                        AudioInputsConfigStore.shared.inputs[idx].calibrationOffsetDb = offset
                    }
                }
            )
        }
        .sheet(isPresented: $showsDbReaderAdvanced) {
            DbReaderAdvancedSheet(model: currentModel, onApply: { updateModel($0) })
        }
    }

    /// Calibration offset (dB) of an audio input, 0 if none/unknown.
    func audioCalibrationOffset(for inputID: UUID?) -> Double {
        inputID.flatMap { AudioInputsConfigStore.shared.input(for: $0)?.calibrationOffsetDb } ?? 0
    }

    // MARK: - RTA Module Settings

    @ViewBuilder func moduleSettings_rta(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let currentModel: RTAModuleModel = {
            if let latest = editableModules.first(where: { $0.id == moduleID }),
               case .rta(let m) = latest.kind { return m }
            if case .rta(let m) = module.kind { return m }
            return RTAModuleModel()
        }()
        let update: (RTAModuleModel) -> Void = { updated in
            commitModuleEdit(moduleID, settingsName: "RTA") { $0.kind = .rta(updated) }
            persistChanges()
        }

        VStack(alignment: .leading, spacing: 12) {
            // General
            settingsSection("General") {
                Toggle("Enabled", isOn: Binding(
                    get: { currentModel.isEnabled },
                    set: { v in var u = currentModel; u.isEnabled = v; update(u) }
                ))
            }
            // Input
            settingsSection("Input") {
                let inputs = AudioInputsConfigStore.shared.inputs
                Picker("Primary Source", selection: Binding(
                    get: { currentModel.inputID },
                    set: { v in
                        var u = currentModel
                        u.inputID = v
                        if let v { u.additionalInputIDs.removeAll { $0 == v } }
                        update(u)
                    }
                )) {
                    Text("None").tag(nil as UUID?)
                    ForEach(inputs) { input in
                        HStack { Circle().fill(input.color.swiftUIColor).frame(width: 8, height: 8); Text(input.name) }
                            .tag(input.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                configureInputsButton
            }
            // Additional Sources (overlaid as colored traces)
            if AudioInputsConfigStore.shared.inputs.count > 1 {
                settingsSection("Additional Sources") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(AudioInputsConfigStore.shared.inputs.filter { $0.id != currentModel.inputID }) { input in
                            Toggle(isOn: Binding(
                                get: { currentModel.additionalInputIDs.contains(input.id) },
                                set: { isOn in
                                    var u = currentModel
                                    if isOn {
                                        if !u.additionalInputIDs.contains(input.id) { u.additionalInputIDs.append(input.id) }
                                    } else {
                                        u.additionalInputIDs.removeAll { $0 == input.id }
                                        u.hiddenSourceIDs.remove(input.id)
                                    }
                                    update(u)
                                }
                            )) {
                                HStack { Circle().fill(input.color.swiftUIColor).frame(width: 8, height: 8); Text(input.name) }
                            }
                        }
                        Text("Toggle visibility of active sources from the legend on the RTA in Live Mode.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Resolution
            settingsSection("Resolution") {
                Picker("Resolution", selection: Binding(
                    get: { currentModel.bandResolution },
                    set: { v in var u = currentModel; u.bandResolution = v; update(u) }
                )) {
                    ForEach(RTABandResolution.allCases, id: \.self) { res in
                        Text(res.displayTitle).tag(res)
                    }
                }
                .pickerStyle(.menu)
            }
            // Display
            settingsSection("Display") {
                Picker("Style", selection: Binding(
                    get: { currentModel.displayMode },
                    set: { v in var u = currentModel; u.displayMode = v; update(u) }
                )) {
                    ForEach(RTADisplayMode.allCases, id: \.self) { Text($0.displayTitle).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Peak Hold", isOn: Binding(
                    get: { currentModel.showPeakHold },
                    set: { v in var u = currentModel; u.showPeakHold = v; update(u) }
                ))
                Toggle("Frequency Axis", isOn: Binding(
                    get: { currentModel.showFrequencyAxis },
                    set: { v in var u = currentModel; u.showFrequencyAxis = v; update(u) }
                ))
                Toggle("dB Axis", isOn: Binding(
                    get: { currentModel.showDBAxis },
                    set: { v in var u = currentModel; u.showDBAxis = v; update(u) }
                ))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Opacity")
                        Spacer()
                        Text("\(Int(currentModel.opacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { currentModel.opacity },
                            set: { v in var u = currentModel; u.opacity = v; update(u) }
                        ),
                        in: 0.1...1.0
                    )
                }
            }
            // Level scale and weighting
            let rtaCal = audioCalibrationOffset(for: currentModel.inputID)
            let rtaShift = currentModel.levelScale == .calibrated ? rtaCal : 0
            settingsSection("Levels") {
                Picker("Scale", selection: Binding(
                    get: { currentModel.levelScale },
                    set: { v in
                        guard v != currentModel.levelScale else { return }
                        // Keep the same picture framed: move the range and alert thresholds
                        // by the input's calibration offset.
                        var u = currentModel
                        let delta = v == .calibrated ? rtaCal : -rtaCal
                        u.levelScale = v
                        u.dBRangeLow += delta; u.dBRangeHigh += delta
                        u.limitWarningDb += delta; u.limitAlertDb += delta
                        update(u)
                    }
                )) {
                    ForEach(AudioLevelScale.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Weighting", selection: Binding(
                    get: { currentModel.weighting },
                    set: { v in var u = currentModel; u.weighting = v; update(u) }
                )) {
                    Text("Z").tag(DbWeighting.z)
                    Text("A").tag(DbWeighting.a)
                    Text("C").tag(DbWeighting.c)
                }
                .pickerStyle(.segmented)
                if currentModel.levelScale == .calibrated && rtaCal == 0 {
                    Text("This input isn't calibrated yet, so dB SPL equals dBFS. Calibrate it in Settings → Audio.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            // Level Range (threshold controls)
            settingsSection("Level Range") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Noise Floor")
                        Spacer()
                        Text("\(Int(currentModel.dBRangeLow)) \(currentModel.levelScale.unitLabel)")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { currentModel.dBRangeLow },
                            set: { v in var u = currentModel; u.dBRangeLow = v; update(u) }
                        ),
                        in: (-120 + rtaShift)...(-20 + rtaShift)
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Ceiling")
                        Spacer()
                        Text("\(Int(currentModel.dBRangeHigh)) \(currentModel.levelScale.unitLabel)")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { currentModel.dBRangeHigh },
                            set: { v in var u = currentModel; u.dBRangeHigh = v; update(u) }
                        ),
                        // RTA band energy sums multiple FFT bins, so it can read well above
                        // 0 dBFS even when no single bin is clipping — allow gaining down further.
                        in: (-40 + rtaShift)...(30 + rtaShift)
                    )
                }
            }
        }
    }

    // MARK: - Spectrograph Module Settings

    @ViewBuilder func moduleSettings_spectrograph(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        let currentModel: SpectrogramModuleModel = {
            if let latest = editableModules.first(where: { $0.id == moduleID }),
               case .spectrograph(let m) = latest.kind { return m }
            if case .spectrograph(let m) = module.kind { return m }
            return SpectrogramModuleModel()
        }()
        let update: (SpectrogramModuleModel) -> Void = { updated in
            commitModuleEdit(moduleID, settingsName: "Spectrograph") { $0.kind = .spectrograph(updated) }
            persistChanges()
        }

        VStack(alignment: .leading, spacing: 12) {
            // General
            settingsSection("General") {
                Toggle("Enabled", isOn: Binding(
                    get: { currentModel.isEnabled },
                    set: { v in var u = currentModel; u.isEnabled = v; update(u) }
                ))
            }
            // Input
            settingsSection("Input") {
                let linkedRTA: RTAModuleModel? = tab.tiles
                    .flatMap { $0.modules ?? [] }
                    .compactMap { module -> RTAModuleModel? in
                        if case .rta(let m) = module.kind { return m }
                        return nil
                    }
                    .first

                Toggle("Link to RTA in this Tab", isOn: Binding(
                    get: { currentModel.linkToRTA },
                    set: { v in var u = currentModel; u.linkToRTA = v; update(u) }
                ))

                if currentModel.linkToRTA {
                    if let linkedRTA {
                        let name = linkedRTA.inputID.flatMap { AudioInputsConfigStore.shared.input(for: $0)?.name } ?? "None"
                        Text("Following the RTA's source (\(name)) and level range.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No RTA module found in this tab — add one to link.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let inputs = AudioInputsConfigStore.shared.inputs
                    Picker("Input", selection: Binding(
                        get: { currentModel.inputID },
                        set: { v in var u = currentModel; u.inputID = v; update(u) }
                    )) {
                        Text("None").tag(nil as UUID?)
                        ForEach(inputs) { input in
                            HStack { Circle().fill(input.color.swiftUIColor).frame(width: 8, height: 8); Text(input.name) }
                                .tag(input.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    configureInputsButton
                }
            }
            // Display
            settingsSection("Display") {
                Toggle("Frequency Axis", isOn: Binding(
                    get: { currentModel.showFrequencyAxis },
                    set: { v in var u = currentModel; u.showFrequencyAxis = v; update(u) }
                ))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Opacity")
                        Spacer()
                        Text("\(Int(currentModel.opacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { currentModel.opacity },
                            set: { v in var u = currentModel; u.opacity = v; update(u) }
                        ),
                        in: 0.1...1.0
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Scroll Speed")
                        Spacer()
                        Text("\(Int(currentModel.scrollRate)) rows/s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { currentModel.scrollRate },
                            set: { v in var u = currentModel; u.scrollRate = v.rounded(); update(u) }
                        ),
                        in: 1...60
                    )
                }
            }
            // Level Range (threshold controls)
            if !currentModel.linkToRTA {
                let specCal = audioCalibrationOffset(for: currentModel.inputID)
                let specShift = currentModel.levelScale == .calibrated ? specCal : 0
                settingsSection("Level Range") {
                    Picker("Scale", selection: Binding(
                        get: { currentModel.levelScale },
                        set: { v in
                            guard v != currentModel.levelScale else { return }
                            var u = currentModel
                            let delta = v == .calibrated ? specCal : -specCal
                            u.levelScale = v
                            u.dBRangeLow += delta; u.dBRangeHigh += delta
                            update(u)
                        }
                    )) {
                        ForEach(AudioLevelScale.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Noise Floor")
                            Spacer()
                            Text("\(Int(currentModel.dBRangeLow)) \(currentModel.levelScale.unitLabel)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { currentModel.dBRangeLow },
                                set: { v in var u = currentModel; u.dBRangeLow = v; update(u) }
                            ),
                            in: (-120 + specShift)...(-20 + specShift)
                        )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Ceiling")
                            Spacer()
                            Text("\(Int(currentModel.dBRangeHigh)) \(currentModel.levelScale.unitLabel)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { currentModel.dBRangeHigh },
                                set: { v in var u = currentModel; u.dBRangeHigh = v; update(u) }
                            ),
                            in: (-40 + specShift)...(0 + specShift)
                        )
                    }
                }
            }
            // Color Map
            settingsSection("Color Map") {
                Picker("Preset", selection: Binding(
                    get: { currentModel.colorMap.preset },
                    set: { v in var u = currentModel; u.colorMap = SpectrogramColorMap(preset: v, customStops: []); update(u) }
                )) {
                    Text("Fire Plasma").tag(SpectrogramPreset.firePlasma)
                    Text("Green Phosphor").tag(SpectrogramPreset.greenPhosphor)
                    Text("Purple Glow").tag(SpectrogramPreset.purpleGlow)
                    Text("Amber").tag(SpectrogramPreset.amber)
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - LiveTranscription Section Helpers (split to avoid iOS stack overflow)

    private struct LiveTranscriptionSourceContext {
        var currentModel: LiveTranscriptionModuleModel
        var updateModel: (LiveTranscriptionModuleModel) -> Void
        var makeSource: (Int) -> LiveTranscriptionSourceConfig
        var configuredSourceLimit: Int?
        var dashboardTranscriptionInputLimit: Int
        var enabledSourcesOnDashboard: Int
        var tileID: UUID
    }

    @ViewBuilder private func liveTranscription_sourceRow(
        idx: Int,
        ctx: LiveTranscriptionSourceContext
    ) -> some View {
        let source = ctx.currentModel.sources[idx]
        let sourceCanBeEnabled = source.isEnabled || ctx.enabledSourcesOnDashboard < ctx.dashboardTranscriptionInputLimit

        #if os(macOS)
        let deviceOptions = [AudioInputDevice(deviceId: AudioDeviceID(0), uid: "", name: "System Default", channelCount: 0)] + audioInputDeviceCache.devices
        #else
        let deviceOptions = audioInputDeviceCache.devices
        #endif

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle(source.transcriptDisplayName, isOn: Binding(
                    get: { ctx.currentModel.sources.indices.contains(idx) ? ctx.currentModel.sources[idx].isEnabled : false },
                    set: { newValue in
                        var updated = ctx.currentModel
                        guard updated.sources.indices.contains(idx) else { return }
                        if newValue && !updated.sources[idx].isEnabled {
                            let otherEnabled = enabledLiveTranscriptionSourceCount(excludingTileId: ctx.tileID)
                            let thisEnabled = updated.sources.filter(\.isEnabled).count
                            guard otherEnabled + thisEnabled < ctx.dashboardTranscriptionInputLimit else { return }
                        }
                        updated.sources[idx].isEnabled = newValue
                        ctx.updateModel(updated)
                    }
                ))
                .disabled(!sourceCanBeEnabled)

                Spacer(minLength: 0)

                ColorPicker("Transcript color for \(source.displayName.isEmpty ? "this input" : source.displayName)", selection: Binding(
                    get: { ctx.currentModel.sources.indices.contains(idx) ? ctx.currentModel.sources[idx].color.swiftUIColor : .white },
                    set: { v in
                        var updated = ctx.currentModel
                        guard updated.sources.indices.contains(idx) else { return }
                        updated.sources[idx].color = CodableColor(v)
                        ctx.updateModel(updated)
                    }
                ))
                .labelsHidden()
                .frame(width: 28)

                if ctx.currentModel.sources.count > 1 {
                    Button(role: .destructive) {
                        var updated = ctx.currentModel
                        guard updated.sources.indices.contains(idx) else { return }
                        updated.sources.remove(at: idx)
                        ctx.updateModel(updated)
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }

            TextField("Channel Name", text: Binding(
                get: { ctx.currentModel.sources.indices.contains(idx) ? ctx.currentModel.sources[idx].transcriptDisplayName : "" },
                set: { v in
                    var updated = ctx.currentModel
                    guard updated.sources.indices.contains(idx) else { return }
                    updated.sources[idx].channelName = v
                    ctx.updateModel(updated)
                }
            ))
            .textFieldStyle(.roundedBorder)

            Picker("Input", selection: Binding(
                get: { ctx.currentModel.sources.indices.contains(idx) ? (ctx.currentModel.sources[idx].deviceUID ?? "") : "" },
                set: { newValue in
                    var updated = ctx.currentModel
                    guard updated.sources.indices.contains(idx) else { return }
                    let previousUID = updated.sources[idx].deviceUID ?? ""
                    let previousInputName = deviceOptions.first(where: { $0.uid == previousUID })?.name
                        ?? (previousUID.isEmpty ? "Microphone" : nil)
                    let currentName = updated.sources[idx].displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasChannelName = !(updated.sources[idx].channelName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    if !hasChannelName, !currentName.isEmpty, currentName != previousInputName {
                        updated.sources[idx].channelName = currentName
                    }
                    updated.sources[idx].deviceUID = newValue.isEmpty ? nil : newValue
                    if let match = deviceOptions.first(where: { $0.uid == newValue }) {
                        updated.sources[idx].displayName = match.name
                    } else if newValue.isEmpty {
                        updated.sources[idx].displayName = "Microphone"
                    }
                    ctx.updateModel(updated)
                }
            )) {
                ForEach(deviceOptions) { device in Text(device.name).tag(device.uid) }
            }
            .pickerStyle(.menu)

            let selectedUID = ctx.currentModel.sources.indices.contains(idx) ? (ctx.currentModel.sources[idx].deviceUID ?? "") : ""
            let selectedDevice = deviceOptions.first(where: { $0.uid == selectedUID }) ?? deviceOptions.first
            let channelCount = max(1, selectedDevice?.channelCount ?? 1)
            Picker("Channel", selection: Binding(
                get: { ctx.currentModel.sources.indices.contains(idx) ? (ctx.currentModel.sources[idx].channelIndex + 1) : 1 },
                set: { v in
                    var updated = ctx.currentModel
                    guard updated.sources.indices.contains(idx) else { return }
                    updated.sources[idx].channelIndex = max(0, v - 1)
                    ctx.updateModel(updated)
                }
            )) {
                ForEach(1...channelCount, id: \.self) { ch in Text("Ch \(ch)").tag(ch) }
            }
            .pickerStyle(.menu)
            .disabled(channelCount <= 1)
        }
    }

    @ViewBuilder private func liveTranscription_globalSourceRow(
        idx: Int,
        ctx: LiveTranscriptionSourceContext
    ) -> some View {
        let source = ctx.currentModel.sources[idx]
        let globalInputs = TranscriptionInputsConfigStore.shared.inputs
        let resolvedInput = source.transInputID.flatMap { id in globalInputs.first { $0.id == id } }
        let sourceCanBeEnabled = source.isEnabled || ctx.enabledSourcesOnDashboard < ctx.dashboardTranscriptionInputLimit

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { ctx.currentModel.sources.indices.contains(idx) ? ctx.currentModel.sources[idx].isEnabled : false },
                    set: { newValue in
                        var updated = ctx.currentModel
                        guard updated.sources.indices.contains(idx) else { return }
                        if newValue && !updated.sources[idx].isEnabled {
                            let otherEnabled = enabledLiveTranscriptionSourceCount(excludingTileId: ctx.tileID)
                            let thisEnabled = updated.sources.filter(\.isEnabled).count
                            guard otherEnabled + thisEnabled < ctx.dashboardTranscriptionInputLimit else { return }
                        }
                        updated.sources[idx].isEnabled = newValue
                        ctx.updateModel(updated)
                    }
                ))
                .labelsHidden()
                .disabled(!sourceCanBeEnabled)

                if let resolved = resolvedInput {
                    HStack(spacing: 6) {
                        Circle().fill(resolved.color.swiftUIColor).frame(width: 8, height: 8)
                        Text(resolved.name).font(.subheadline)
                    }
                } else {
                    Text(source.displayName.isEmpty ? "Unknown Input" : source.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                ColorPicker("Transcript color for \(source.displayName.isEmpty ? "this input" : source.displayName)", selection: Binding(
                    get: { ctx.currentModel.sources.indices.contains(idx) ? ctx.currentModel.sources[idx].color.swiftUIColor : .white },
                    set: { v in
                        var updated = ctx.currentModel
                        guard updated.sources.indices.contains(idx) else { return }
                        updated.sources[idx].color = CodableColor(v)
                        ctx.updateModel(updated)
                    }
                ))
                .labelsHidden()
                .frame(width: 28)

                if ctx.currentModel.sources.count > 1 {
                    Button(role: .destructive) {
                        var updated = ctx.currentModel
                        guard updated.sources.indices.contains(idx) else { return }
                        updated.sources.remove(at: idx)
                        ctx.updateModel(updated)
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }

            // Display name override
            TextField("Display name override (optional)", text: Binding(
                get: { ctx.currentModel.sources.indices.contains(idx) ? (ctx.currentModel.sources[idx].channelName ?? "") : "" },
                set: { v in
                    var updated = ctx.currentModel
                    guard updated.sources.indices.contains(idx) else { return }
                    updated.sources[idx].channelName = v.isEmpty ? nil : v
                    ctx.updateModel(updated)
                }
            ))
            .textFieldStyle(.roundedBorder)

            // Read-only summary from resolved global input
            if let resolved = resolvedInput {
                #if os(macOS)
                let deviceName = audioInputDeviceCache.devices.first(where: { $0.uid == resolved.deviceUID })?.name ?? resolved.deviceUID ?? "Unknown Device"
                #else
                let deviceName = audioInputDeviceCache.devices.first(where: { $0.uid == resolved.deviceUID })?.name ?? resolved.deviceUID ?? "Unknown Device"
                #endif
                Text("\(deviceName) · ch \(resolved.channelIndex + 1) · \(resolved.autoGainEnabled ? "Auto-gain" : "Fixed") · \(resolved.enginePreference.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func liveTranscription_sourcesSection(ctx: LiveTranscriptionSourceContext) -> some View {
        settingsSection("Sources") {
            HStack {
                Text("Configured sources on this tile: \(ctx.currentModel.sources.count)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Enabled dashboard inputs: \(ctx.enabledSourcesOnDashboard)/\(ctx.dashboardTranscriptionInputLimit)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Menu {
                    let globalInputs = TranscriptionInputsConfigStore.shared.inputs
                    let assignedIDs = Set(ctx.currentModel.sources.compactMap(\.transInputID))
                    ForEach(globalInputs.filter { !assignedIDs.contains($0.id) }) { globalInput in
                        Button(globalInput.name) {
                            var updated = ctx.currentModel
                            var newSource = ctx.makeSource(updated.sources.count)
                            newSource.transInputID = globalInput.id
                            newSource.displayName = globalInput.name
                            newSource.deviceUID = globalInput.deviceUID
                            newSource.channelIndex = globalInput.channelIndex
                            newSource.color = globalInput.color
                            updated.sources.append(newSource)
                            ctx.updateModel(updated)
                        }
                    }
                    Divider()
                    Button("New Input…") {
                        NotificationCenter.default.post(name: .showTranscriptionInputsConfigRequested, object: nil)
                    }
                } label: {
                    Label("Add Input", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .disabled(ctx.configuredSourceLimit.map { ctx.currentModel.sources.count >= $0 } ?? false)
            }

            if ctx.enabledSourcesOnDashboard >= ctx.dashboardTranscriptionInputLimit {
                Text("Disable another tile's transcription input to enable more sources here.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Identity is the source's stable UUID, not its array position — `idx` is
            // re-resolved per source.id so a mid-list deletion can't cause a later row
            // to inherit an earlier row's SwiftUI identity/state.
            ForEach(ctx.currentModel.sources, id: \.id) { source in
                if let idx = ctx.currentModel.sources.firstIndex(where: { $0.id == source.id }) {
                    liveTranscription_globalSourceRow(idx: idx, ctx: ctx)
                }
            }

            #if os(macOS)
            Text("Multiple sources can run in one transcription log. Performance may vary above 2 active sources.")
                .font(.caption2).foregroundStyle(.secondary)
            #else
            Text("Live Transcription supports one input per tile on iPadOS.")
                .font(.caption2).foregroundStyle(.secondary)
            #endif

            Button {
                NotificationCenter.default.post(name: .showTranscriptionInputsConfigRequested, object: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3").font(.caption)
                    Text("Configure Transcription Inputs…").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder func moduleSettings_liveTranscription(module: DashboardModuleModel) -> some View {
        let moduleID = module.id
        #if os(macOS)
        let dashboardTranscriptionInputLimit = 4
        let configuredSourceLimit: Int? = nil
        #else
        let dashboardTranscriptionInputLimit = 1
        let configuredSourceLimit: Int? = 1
        #endif
        let currentModel: LiveTranscriptionModuleModel = {
            if let latest = editableModules.first(where: { $0.id == moduleID }),
               case .liveTranscription(let model) = latest.kind {
                return model
            }
            if case .liveTranscription(let model) = module.kind { return model }
            return LiveTranscriptionModuleModel()
        }()
        let makeSource: (Int) -> LiveTranscriptionSourceConfig = { index in
            let palette: [Color] = [.cyan, .green, .orange, .yellow]
            let color = palette[index % palette.count]
            let displayIndex = index + 1
            return LiveTranscriptionSourceConfig(
                kind: .microphone,
                displayName: displayIndex == 1 ? "Microphone" : "Microphone \(displayIndex)",
                channelName: displayIndex == 1 ? "Microphone" : "Microphone \(displayIndex)",
                deviceUID: nil,
                channelIndex: 0,
                color: CodableColor(color),
                isEnabled: true
            )
        }
        let updateModel: (LiveTranscriptionModuleModel) -> Void = { updated in
            var normalized = updated
            if normalized.sources.isEmpty { normalized.sources = [makeSource(0)] }
            if let limit = configuredSourceLimit, normalized.sources.count > limit {
                normalized.sources = Array(normalized.sources.prefix(limit))
            }
            commitModuleEdit(moduleID, settingsName: "Live Transcription") {
                $0.kind = .liveTranscription(normalized)
            }
            persistChanges()
        }
        let enabledSourcesOnOtherTiles = enabledLiveTranscriptionSourceCount(excludingTileId: tileID)
        let enabledSourcesOnThisTile = currentModel.sources.filter(\.isEnabled).count
        let enabledSourcesOnDashboard = enabledSourcesOnOtherTiles + enabledSourcesOnThisTile
        let ctx = LiveTranscriptionSourceContext(
            currentModel: currentModel,
            updateModel: updateModel,
            makeSource: makeSource,
            configuredSourceLimit: configuredSourceLimit,
            dashboardTranscriptionInputLimit: dashboardTranscriptionInputLimit,
            enabledSourcesOnDashboard: enabledSourcesOnDashboard,
            tileID: tileID
        )

        VStack(alignment: .leading, spacing: 12) {
            settingsSection("General") {
                Toggle("Enabled", isOn: Binding(
                    get: { currentModel.isEnabled },
                    set: { v in var u = currentModel; u.isEnabled = v; updateModel(u) }
                ))
                HStack {
                    Text("Label")
                    TextField("Live Transcription", text: Binding(
                        get: { currentModel.label },
                        set: { v in var u = currentModel; u.label = v; updateModel(u) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            liveTranscription_sourcesSection(ctx: ctx)

            settingsSection("Display") {
                Toggle("Relative timestamps", isOn: Binding(
                    get: { currentModel.usesRelativeTimestamps == true },
                    set: { v in var u = currentModel; u.usesRelativeTimestamps = v; updateModel(u) }
                ))
            }

            settingsSection("Info") {
                Toggle("Show diagnostics", isOn: Binding(
                    get: { currentModel.showsDiagnostics },
                    set: { v in var u = currentModel; u.showsDiagnostics = v; updateModel(u) }
                ))
                Text("NOTE: Export, copy, and clear settings live in the tile ellipses menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Shared helpers

    /// A small tappable link that opens the Audio Inputs configuration sheet.
    @ViewBuilder var configureInputsButton: some View {
        Button {
            NotificationCenter.default.post(name: .showAudioInputsConfigRequested, object: nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                Text("Configure Inputs…")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
