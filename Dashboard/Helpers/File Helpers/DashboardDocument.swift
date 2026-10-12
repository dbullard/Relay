//
//  DashboardDocument.swift
//  Relay
//
//  Created by David Bullard on 11/21/25.
//

// DashboardDocument.swift
// Relay

import SwiftUI
import Combine
import UniformTypeIdentifiers

extension UTType {
    static let relayDashboard = UTType(exportedAs: "com.relay.dashboard", conformingTo: .data)
    static let relayDashboardLegacy = UTType(importedAs: "com.relay.dashboard.legacy", conformingTo: .data)
    static var prodlinkDashboard: UTType { .relayDashboard }
    static var legacyProdlinkDashboard: UTType { .relayDashboardLegacy }
}

enum DashboardDocumentIOError: LocalizedError {
    case selectedDirectory
    case fileMissing(URL)
    case permissionDenied(URL)
    case bookmarkRestoreFailed(underlying: Error)
    case decodeFailed(URL, underlying: Error)
    case invalidPayload(String)
    case readFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .selectedDirectory:
            return "The selected item is a folder, not a Relay dashboard file."
        case .fileMissing(let url):
            return "The dashboard file could not be found at \(url.path)."
        case .permissionDenied(let url):
            return "Relay doesn’t have permission to open \(url.lastPathComponent). Please choose the file again."
        case .bookmarkRestoreFailed:
            return "Relay couldn’t restore the last opened dashboard. You can reopen it manually from File > Open."
        case .decodeFailed(let url, _):
            return "\(url.lastPathComponent) isn’t a valid Relay dashboard file or it’s corrupted."
        case .invalidPayload(let message):
            return message
        case .readFailed(let url, _):
            return "Relay couldn’t read \(url.lastPathComponent)."
        }
    }
}

struct DashboardSettingsSnapshot: Codable, Equatable {
    struct X32DeviceSettings: Codable, Equatable {
        var syncMap: [Int: String]?
        var syncTimestamp: Double?
        var showSendMode: String?
    }

    var oscEnabled: Bool
    var oscPort: Int
    var midiEnabled: Bool
    var midiSourceId: Int

    var proPresenterHost: String
    var proPresenterPort: Int
    var proPresenterPassword: String
    var proPresenterTransport: String
    var proPresenterPollInterval: Double
    var proPresenterProfilesData: Data?
    var proPresenterActiveProfileID: String?

    var resolumeProfilesData: Data?
    var ndiPreferredInterfaceID: String?
    var ndiAllowAutoFallback: Bool?

    /// Keyed by stable external device key: kind|host|port (lowercased host).
    var x32DeviceSettingsByKey: [String: X32DeviceSettings]?
}


/// File format for saving/loading a dashboard layout.
struct DashboardDocument: FileDocument {
    // SwiftUI FileDocument requirements
    static var readableContentTypes: [UTType] { [.prodlinkDashboard, .legacyProdlinkDashboard] }
    static var writableContentTypes: [UTType] { [.prodlinkDashboard] }

    /// What we actually store in the file.
    struct Payload: Codable {
        var version: Int
        var tabs: [DashboardTab]
        var rosters: [DashboardRoster]
        var selectedTabIndex: Int
        var externalDevices: ExternalDevicesStore.Snapshot?
        var settings: DashboardSettingsSnapshot?
        var canvasGuides: [CanvasGuide]

        /// Preferred persisted canvas/document size (Photoshop-style artboard).
        /// Added in version 2.
        var canvasSize: CGSize? = nil

        /// Legacy field kept for backwards compatibility (older dashboards).
        var referenceCanvasSize: CGSize? = nil

        /// Universal automation graph shared across all tabs (version 5+).
        var universalGraph: DashboardGraph? = nil

        init(
            version: Int = 5,
            tabs: [DashboardTab],
            rosters: [DashboardRoster] = [],
            selectedTabIndex: Int,
            externalDevices: ExternalDevicesStore.Snapshot? = nil,
            settings: DashboardSettingsSnapshot? = nil,
            canvasGuides: [CanvasGuide] = [],
            canvasSize: CGSize? = nil,
            referenceCanvasSize: CGSize? = nil,
            universalGraph: DashboardGraph? = nil
        ) {
            self.version = version
            self.tabs = tabs
            self.rosters = rosters
            self.selectedTabIndex = selectedTabIndex
            self.externalDevices = externalDevices
            self.settings = settings
            self.canvasGuides = canvasGuides
            self.canvasSize = canvasSize
            self.referenceCanvasSize = referenceCanvasSize
            self.universalGraph = universalGraph
        }
        
        private enum CodingKeys: String, CodingKey {
            case version
            case tabs
            case rosters
            case selectedTabIndex
            case externalDevices
            case settings
            case canvasGuides
            case canvasSize
            case referenceCanvasSize
            case universalGraph
        }

        private static func normalizeLegacyButtonModuleIDs(in tabs: [DashboardTab]) -> [DashboardTab] {
            var seenButtonIDs: Set<UUID> = []
            return tabs.map { tab in
                var updatedTab = tab
                updatedTab.tiles = tab.tiles.map { tile in
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
                                return updatedConfig
                            }
                        }

                        seenButtonIDs.insert(buttonModel.id)
                        updatedModule.kind = .button(buttonModel)
                        return updatedModule
                    }
                    return updatedTile
                }
                return updatedTab
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Older files may not contain these keys; default them when missing.
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            let decodedTabs = try container.decode([DashboardTab].self, forKey: .tabs)
            tabs = Self.normalizeLegacyButtonModuleIDs(in: decodedTabs)
            rosters = try container.decodeIfPresent([DashboardRoster].self, forKey: .rosters) ?? []
            selectedTabIndex = try container.decodeIfPresent(Int.self, forKey: .selectedTabIndex) ?? 0
            externalDevices = try container.decodeIfPresent(ExternalDevicesStore.Snapshot.self, forKey: .externalDevices)
            settings = try container.decodeIfPresent(DashboardSettingsSnapshot.self, forKey: .settings)
            canvasGuides = try container.decodeIfPresent([CanvasGuide].self, forKey: .canvasGuides) ?? []

            // Prefer the newer `canvasSize`, but fall back to legacy `referenceCanvasSize`.
            canvasSize = try container.decodeIfPresent(CGSize.self, forKey: .canvasSize)
            referenceCanvasSize = try container.decodeIfPresent(CGSize.self, forKey: .referenceCanvasSize)
            if canvasSize == nil {
                canvasSize = referenceCanvasSize
            }
            universalGraph = try container.decodeIfPresent(DashboardGraph.self, forKey: .universalGraph)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(tabs, forKey: .tabs)
            try container.encode(rosters, forKey: .rosters)
            try container.encode(selectedTabIndex, forKey: .selectedTabIndex)
            try container.encodeIfPresent(externalDevices, forKey: .externalDevices)
            try container.encodeIfPresent(settings, forKey: .settings)
            try container.encode(canvasGuides, forKey: .canvasGuides)

            // Preferred key going forward.
            try container.encodeIfPresent(canvasSize, forKey: .canvasSize)

            // Legacy key for backwards compatibility.
            try container.encodeIfPresent(referenceCanvasSize ?? canvasSize, forKey: .referenceCanvasSize)

            try container.encodeIfPresent(universalGraph, forKey: .universalGraph)
        }
    }

    var payload: Payload

    // MARK: - Initializers

    /// Create a document from the current dashboard state.
    init(
        tabs: [DashboardTab],
        rosters: [DashboardRoster] = [],
        selectedTabIndex: Int,
        externalDevices: ExternalDevicesStore.Snapshot? = nil,
        settings: DashboardSettingsSnapshot? = nil,
        canvasGuides: [CanvasGuide] = [],
        referenceCanvasSize: CGSize? = nil,
        universalGraph: DashboardGraph? = nil
    ) {
        self.payload = Payload(
            version: 5,
            tabs: tabs,
            rosters: rosters,
            selectedTabIndex: selectedTabIndex,
            externalDevices: externalDevices,
            settings: settings,
            canvasGuides: canvasGuides,
            referenceCanvasSize: referenceCanvasSize,
            universalGraph: universalGraph
        )
    }

    /// Create a document when opening from disk.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        self.payload = try decoder.decode(Payload.self, from: data)
    }

    // MARK: - Writing

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        let data = try encoder.encode(payload)
        return .init(regularFileWithContents: data)
    }
}
