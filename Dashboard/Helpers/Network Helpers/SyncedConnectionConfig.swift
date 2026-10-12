//
//  SyncedConnectionConfig.swift
//  Relay
//
//  Synced Tabs replicate a tab's full content between paired devices. Most of that content
//  (layout, PCO rundown selection, roster assignments, display preferences) is meant to be
//  shared — that's the point of Sync. But some fields identify a resource that only exists,
//  or only means something, on the device that configured it: a ProPresenter connection
//  profile, a Resolume endpoint, a paired Shure/Sennheiser receiver, an NDI source on a
//  specific network interface, a DAW's MIDI transport, or a physical audio-interface input.
//  A peer's copy of one of these fields is never meaningful locally, so it must never
//  overwrite the local device's own configuration — in either direction.
//

import Foundation

/// Returns a copy of `incoming` with every device-local "external connection" field rewritten
/// to match `current`'s value, tile-by-tile and module-by-module (matched by id). Everything
/// else in `incoming` — layout, PCO data, display preferences, etc. — passes through unchanged.
/// Call this on every incoming synced-tab snapshot before it's adopted as local truth.
@MainActor
func preservingLocalConnectionConfig(incoming: DashboardTab, current: DashboardTab) -> DashboardTab {
    var result = incoming

    for i in result.tiles.indices {
        guard let currentTile = current.tiles.first(where: { $0.id == result.tiles[i].id }) else { continue }
        guard var modules = result.tiles[i].modules else { continue }
        guard let currentModules = currentTile.modules else { continue }

        for j in modules.indices {
            guard let currentModule = currentModules.first(where: { $0.id == modules[j].id }) else { continue }

            if var pp = modules[j].proPresenterConfig {
                pp.connectionProfileID = currentModule.proPresenterConfig?.connectionProfileID
                modules[j].proPresenterConfig = pp
            }
            if var shure = modules[j].shureConfig {
                shure.selectedChannel = currentModule.shureConfig?.selectedChannel
                modules[j].shureConfig = shure
            }
            if var shureOverview = modules[j].shureOverviewConfig, let curShureOverview = currentModule.shureOverviewConfig {
                shureOverview.deviceScope = curShureOverview.deviceScope
                shureOverview.selectedDeviceIDs = curShureOverview.selectedDeviceIDs
                modules[j].shureOverviewConfig = shureOverview
            }
            if var sennheiser = modules[j].sennheiserConfig {
                let curSennheiser = currentModule.sennheiserConfig
                sennheiser.externalDeviceID = curSennheiser?.externalDeviceID
                sennheiser.channelRemoteID = curSennheiser?.channelRemoteID
                if let curChannelIndex = curSennheiser?.channelIndex {
                    sennheiser.channelIndex = curChannelIndex
                }
                modules[j].sennheiserConfig = sennheiser
            }
            if var resolume = modules[j].resolumeConfig {
                let curResolume = currentModule.resolumeConfig
                resolume.profileID = curResolume?.profileID
                if let curEndpoint = curResolume?.endpoint {
                    resolume.endpoint = curEndpoint
                }
                modules[j].resolumeConfig = resolume
            }
            if var dawTransport = modules[j].dawTransportConfig, let curDAWTransport = currentModule.dawTransportConfig {
                dawTransport.dawType = curDAWTransport.dawType
                dawTransport.connectionName = curDAWTransport.connectionName
                dawTransport.midiInputSourceID = curDAWTransport.midiInputSourceID
                dawTransport.midiOutputDestinationID = curDAWTransport.midiOutputDestinationID
                modules[j].dawTransportConfig = dawTransport
            }

            switch (modules[j].kind, currentModule.kind) {
            case (.ndi(var incomingNDI), .ndi(let currentNDI)):
                incomingNDI.sourceID = currentNDI.sourceID
                incomingNDI.sourceName = currentNDI.sourceName
                incomingNDI.interfaceSelection = currentNDI.interfaceSelection
                modules[j].kind = .ndi(incomingNDI)
            case (.rta(var incomingRTA), .rta(let currentRTA)):
                incomingRTA.inputID = currentRTA.inputID
                incomingRTA.additionalInputIDs = currentRTA.additionalInputIDs
                incomingRTA.hiddenSourceIDs = currentRTA.hiddenSourceIDs
                modules[j].kind = .rta(incomingRTA)
            case (.spectrograph(var incomingSpectrogram), .spectrograph(let currentSpectrogram)):
                incomingSpectrogram.inputID = currentSpectrogram.inputID
                modules[j].kind = .spectrograph(incomingSpectrogram)
            case (.dbReader(var incomingDbReader), .dbReader(let currentDbReader)):
                incomingDbReader.inputID = currentDbReader.inputID
                modules[j].kind = .dbReader(incomingDbReader)
            default:
                break
            }
        }

        result.tiles[i].modules = modules
    }

    return result
}
