//
//  GraphTypes.swift
//  Relay Dashboard
//
//  A tile-backed patch/automation graph.
//  Nodes are existing Dashboard tiles; the graph stores only layout + links.
//

import Foundation
import SwiftUI

// MARK: - Codable geometry helpers

struct CGPointCodable: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct GraphTriggerPayload: Codable, Equatable {
    var sourceNodeId: UUID
    var eventKind: String?
    var text: String?
    var number: Double?
    var boolean: Bool?
    var address: String?
    var localPort: Int?
    var dataJSON: String?

    init(
        sourceNodeId: UUID,
        eventKind: String? = nil,
        text: String? = nil,
        number: Double? = nil,
        boolean: Bool? = nil,
        address: String? = nil,
        localPort: Int? = nil,
        dataJSON: String? = nil
    ) {
        self.sourceNodeId = sourceNodeId
        self.eventKind = eventKind
        self.text = text
        self.number = number
        self.boolean = boolean
        self.address = address
        self.localPort = localPort
        self.dataJSON = dataJSON
    }
}

enum GraphVariableValueType: String, Codable, CaseIterable {
    case text
    case number
    case float
    case boolean

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = GraphVariableValueType(rawValue: rawValue) ?? .text
    }

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .number: return "Integer"
        case .float: return "Float"
        case .boolean: return "Boolean"
        }
    }
}

func normalizeGraphVariableName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

var isGraphVariablesFeatureEnabled: Bool {
    true
}

var isGraphConditionalsFeatureEnabled: Bool {
    true
}

var isProPresenterTriggerFeatureEnabled: Bool {
    RelayBuildConfig.isPreviewEnabled
}

var isVistaIntegrationEnabled: Bool {
    RelayBuildConfig.isVistaIntegrationEnabled
}

enum GraphNodeCategory: String, CaseIterable {
    case sources
    case triggers
    case actions
    case destinations
    case utility
    case unknown

    init(categoryLabel: String) {
        switch categoryLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sources":
            self = .sources
        case "triggers":
            self = .triggers
        case "actions":
            self = .actions
        case "destinations":
            self = .destinations
        case "utility":
            self = .utility
        default:
            self = .unknown
        }
    }

    init(nodeKey: String) {
        switch nodeKey {
        case "utility.variable", "utility.repeater", "utility.delay", "utility.condition",
             "utility.toggle", "utility.counter", "utility.sequence", "utility.latch",
             "utility.merge":
            self = .utility
        case "destination.console",
             "destination.vista",
             "action.proPresenterTrigger",
             "action.shureSend",
             "action.sennheiserSend":
            self = .destinations
        case "moduleGroup.time",
             "moduleGroup.shure",
             "moduleGroup.sennheiser",
             "moduleGroup.oscReceive",
             "moduleGroup.midiReceive",
             "moduleGroup.keystrokeTrigger",
             "moduleGroup.wordTrigger",
             "moduleGroup.transcription",
             "moduleGroup.dbThreshold",
             "moduleGroup.manualTrigger",
             "moduleGroup.button",
             "moduleGroup.proPresenterTrigger":
            self = .triggers
        default:
            if nodeKey.hasPrefix("action.") {
                self = .actions
            } else if nodeKey.hasPrefix("source.") || nodeKey.hasPrefix("moduleGroup.") {
                self = .sources
            } else {
                self = .unknown
            }
        }
    }

    var accentColor: Color {
        switch self {
        case .sources:
            return .gray
        case .triggers:
            return .orange
        case .actions:
            return .green
        case .destinations:
            return .blue
        case .utility:
            return .purple
        case .unknown:
            return .white
        }
    }

    var menuColor: Color {
        accentColor.opacity(self == .unknown ? 0.4 : 0.9)
    }

    var badgeColor: Color {
        accentColor.opacity(self == .unknown ? 0.16 : 0.22)
    }

    var tintColor: Color {
        accentColor.opacity(self == .unknown ? 0.06 : 0.10)
    }

    var borderColor: Color {
        accentColor.opacity(self == .unknown ? 0.18 : 0.30)
    }
}

struct AppControlRefreshDeviceOptions: Codable, Equatable {
    enum TargetScope: String, Codable, CaseIterable {
        case allDevices
        case selectedDevices

        var displayName: String {
            switch self {
            case .allDevices: return "All Devices"
            case .selectedDevices: return "Selected Devices"
            }
        }
    }

    var targetScope: TargetScope
    var selectedDeviceIDs: [UUID]

    init(
        targetScope: TargetScope = .allDevices,
        selectedDeviceIDs: [UUID] = []
    ) {
        self.targetScope = targetScope
        self.selectedDeviceIDs = selectedDeviceIDs
    }

    enum CodingKeys: String, CodingKey {
        case targetScope
        case selectedDeviceIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetScope = try container.decodeIfPresent(TargetScope.self, forKey: .targetScope) ?? .allDevices
        selectedDeviceIDs = try container.decodeIfPresent([UUID].self, forKey: .selectedDeviceIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetScope, forKey: .targetScope)
        try container.encode(selectedDeviceIDs, forKey: .selectedDeviceIDs)
    }
}

// MARK: - Graph model

/// Layout state for a tile when rendered in Graph view.
/// Stored separately from the normal dashboard canvas/grid layout.
struct TileGraphLayout: Codable, Equatable {
    /// Node position in Graph-space.
    var position: CGPointCodable
    var pinned: Bool
    /// Primary collapse state (module group nodes: item list; console nodes: assignments section).
    var collapsed: Bool
    /// Secondary collapse state (console nodes: snapshots/cues section).
    var collapsedSnapshots: Bool

    init(position: CGPoint = .zero, pinned: Bool = false, collapsed: Bool = false, collapsedSnapshots: Bool = false) {
        self.position = CGPointCodable(position)
        self.pinned = pinned
        self.collapsed = collapsed
        self.collapsedSnapshots = collapsedSnapshots
    }

    // Custom decoder for backward compatibility: collapsedSnapshots was added after initial release.
    // Files saved before this field existed will decode with the default value of false.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decode(CGPointCodable.self, forKey: .position)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        collapsedSnapshots = try c.decodeIfPresent(Bool.self, forKey: .collapsedSnapshots) ?? false
    }
}

/// The graph for a tab/dashboard.
/// Nodes are the tab's tiles; this holds only their graph layout + links.
struct DashboardGraph: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    /// A graph-only node instance created from the Add Node menu.
    /// Canvas-backed nodes (derived from tiles) are not stored here.
    struct ModuleGroupNodeInstance: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        /// Group key such as "moduleGroup.person" or "moduleGroup.pco".
        var groupKey: String

        init(id: UUID = UUID(), groupKey: String) {
            self.id = id
            self.groupKey = groupKey
        }
    }

    /// Custom people rows added to a manual People node.
    struct CustomPeopleEntry: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var position: String
        var name: String
        /// Optional team label (used later for filtering/grouping).
        var teamName: String? = nil

        init(id: UUID = UUID(), position: String, name: String, teamName: String? = nil) {
            self.id = id
            self.position = position
            self.name = name
            self.teamName = teamName
        }
    }

    // MARK: - Action node configs (graph-only nodes)

    struct SendAllConsolesActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var includeAssignments: Bool
        var includeSnapshots: Bool
        var staggerMs: Int

        init(id: UUID = UUID(), includeAssignments: Bool = true, includeSnapshots: Bool = true, staggerMs: Int = 0) {
            self.id = id
            self.includeAssignments = includeAssignments
            self.includeSnapshots = includeSnapshots
            self.staggerMs = staggerMs
        }
    }

    /// A typed OSC argument persisted by an OSC Send action node.
    struct OSCSendActionArgument: Identifiable, Codable, Equatable {
        enum Value: Codable, Equatable {
            case int32(Int32)
            case float32(Float)
            case string(String)
            case blobBase64(String)
            case `true`
            case `false`
            case null
            case impulse
            case timetag(UInt64)

            private enum CodingKeys: String, CodingKey { case type, int32, float32, string, blobBase64, timetag }
            private enum Kind: String, Codable { case int32, float32, string, blobBase64, `true`, `false`, null, impulse, timetag }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                switch try container.decode(Kind.self, forKey: .type) {
                case .int32: self = .int32(try container.decode(Int32.self, forKey: .int32))
                case .float32: self = .float32(try container.decode(Float.self, forKey: .float32))
                case .string: self = .string(try container.decode(String.self, forKey: .string))
                case .blobBase64: self = .blobBase64(try container.decode(String.self, forKey: .blobBase64))
                case .true: self = .true
                case .false: self = .false
                case .null: self = .null
                case .impulse: self = .impulse
                case .timetag: self = .timetag(try container.decode(UInt64.self, forKey: .timetag))
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .int32(let value):
                    try container.encode(Kind.int32, forKey: .type)
                    try container.encode(value, forKey: .int32)
                case .float32(let value):
                    try container.encode(Kind.float32, forKey: .type)
                    try container.encode(value, forKey: .float32)
                case .string(let value):
                    try container.encode(Kind.string, forKey: .type)
                    try container.encode(value, forKey: .string)
                case .blobBase64(let value):
                    try container.encode(Kind.blobBase64, forKey: .type)
                    try container.encode(value, forKey: .blobBase64)
                case .true: try container.encode(Kind.true, forKey: .type)
                case .false: try container.encode(Kind.false, forKey: .type)
                case .null: try container.encode(Kind.null, forKey: .type)
                case .impulse: try container.encode(Kind.impulse, forKey: .type)
                case .timetag(let value):
                    try container.encode(Kind.timetag, forKey: .type)
                    try container.encode(value, forKey: .timetag)
                }
            }
        }

        var id: UUID
        var value: Value

        init(id: UUID = UUID(), value: Value = .string("")) {
            self.id = id
            self.value = value
        }

        func resolvedValue() -> OSCValue? {
            switch value {
            case .int32(let value): return .int32(value)
            case .float32(let value): return .float32(value)
            case .string(let value): return .string(value)
            case .blobBase64(let value): return Data(base64Encoded: value).map(OSCValue.blob)
            case .true: return .bool(true)
            case .false: return .bool(false)
            case .null: return .null
            case .impulse: return .impulse
            case .timetag(let value): return .timetag(value)
            }
        }
    }

    /// Lightweight config for the OSC Send action node (separate from the richer OSCSendConfig templates).
    struct OSCSendActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var targetIP: String
        var targetPort: UInt16
        var address: String
        var arguments: [OSCSendActionArgument]

        private enum CodingKeys: String, CodingKey { case id, targetIP, targetPort, address, arguments }

        init(id: UUID = UUID(), targetIP: String = "127.0.0.1", targetPort: UInt16 = 9000, address: String = "/", arguments: [OSCSendActionArgument] = []) {
            self.id = id
            self.targetIP = targetIP
            self.targetPort = targetPort
            self.address = address
            self.arguments = arguments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            targetIP = try container.decode(String.self, forKey: .targetIP)
            targetPort = try container.decode(UInt16.self, forKey: .targetPort)
            address = try container.decode(String.self, forKey: .address)
            arguments = try container.decodeIfPresent([OSCSendActionArgument].self, forKey: .arguments) ?? []
        }
    }

    struct NotifyActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var title: String
        var message: String
        var durationSeconds: Double

        init(id: UUID = UUID(), title: String = "Automation", message: String = "", durationSeconds: Double = 3.0) {
            self.id = id
            self.title = title
            self.message = message
            self.durationSeconds = durationSeconds
        }
    }

    struct LANNotifyActionConfig: Identifiable, Codable, Equatable {
        enum TargetMode: String, Codable, CaseIterable {
            case allPeers
            case specificPeer
            case allHTTPViewers
            case allPeersAndHTTPViewers

            var displayName: String {
                switch self {
                case .allPeers: return "All Peers"
                case .specificPeer: return "Specific Peer"
                case .allHTTPViewers: return "All HTTP Viewers"
                case .allPeersAndHTTPViewers: return "Peers + HTTP Viewers"
                }
            }
        }

        var id: UUID = UUID()
        var title: String
        var message: String
        var durationSeconds: Double
        var targetMode: TargetMode
        var peerDeviceId: String

        init(
            id: UUID = UUID(),
            title: String = "Automation",
            message: String = "",
            durationSeconds: Double = 3.0,
            targetMode: TargetMode = .allPeers,
            peerDeviceId: String = ""
        ) {
            self.id = id
            self.title = title
            self.message = message
            self.durationSeconds = durationSeconds
            self.targetMode = targetMode
            self.peerDeviceId = peerDeviceId
        }
    }

    struct AppControlActionConfig: Identifiable, Codable, Equatable {
        enum ActionKind: String, Codable, CaseIterable {
            case selectFirstTab
            case selectPreviousTab
            case selectNextTab
            case selectLastTab
            case refreshPCO
            case resyncDeviceNames
            case clearSplMeters
            case clearLiveTranscript
            case switchToCanvasView
            case switchToAutomationView
            case enterLiveMode
            case exitLiveMode
            case toggleLiveMode
            case saveDashboard
            case saveDashboardAs
            case startSplLogging
            case stopSplLogging
            case toggleSplLogging

            var displayName: String {
                switch self {
                case .selectFirstTab: return "Select First Tab"
                case .selectPreviousTab: return "Select Previous Tab"
                case .selectNextTab: return "Select Next Tab"
                case .selectLastTab: return "Select Last Tab"
                case .refreshPCO: return "Refresh Planning Center"
                case .resyncDeviceNames: return "Resync Console + Wireless Names"
                case .clearSplMeters: return "Clear SPL Meters"
                case .clearLiveTranscript: return "Clear Live Transcript"
                case .switchToCanvasView: return "Switch to Canvas View"
                case .switchToAutomationView: return "Switch to Automation View"
                case .enterLiveMode: return "Enter Live Mode"
                case .exitLiveMode: return "Exit Live Mode"
                case .toggleLiveMode: return "Toggle Live Mode"
                case .saveDashboard: return "Save Dashboard"
                case .saveDashboardAs: return "Save Dashboard As"
                case .startSplLogging:  return "Start SPL Logging"
                case .stopSplLogging:   return "Stop SPL Logging"
                case .toggleSplLogging: return "Toggle SPL Logging"
                }
            }
        }

        var id: UUID = UUID()
        var actionKind: ActionKind
        var refreshDeviceOptions: AppControlRefreshDeviceOptions

        init(
            id: UUID = UUID(),
            actionKind: ActionKind = .selectNextTab,
            refreshDeviceOptions: AppControlRefreshDeviceOptions = AppControlRefreshDeviceOptions()
        ) {
            self.id = id
            self.actionKind = actionKind
            self.refreshDeviceOptions = refreshDeviceOptions
        }

        enum CodingKeys: String, CodingKey {
            case id
            case actionKind
            case refreshDeviceOptions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            actionKind = try container.decodeIfPresent(ActionKind.self, forKey: .actionKind) ?? .selectNextTab
            refreshDeviceOptions = try container.decodeIfPresent(AppControlRefreshDeviceOptions.self, forKey: .refreshDeviceOptions)
                ?? AppControlRefreshDeviceOptions()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(actionKind, forKey: .actionKind)
            try container.encode(refreshDeviceOptions, forKey: .refreshDeviceOptions)
        }
    }

    struct MIDISendActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var destinationUniqueID: Int32?
        var messageKind: MIDIMessageKind
        var channel: Int
        var note: Int
        var velocity: Int
        var program: Int
        var control: Int
        var value: Int
        var sysexHex: String

        init(
            id: UUID = UUID(),
            destinationUniqueID: Int32? = nil,
            messageKind: MIDIMessageKind = .noteOn,
            channel: Int = 1,
            note: Int = 60,
            velocity: Int = 100,
            program: Int = 0,
            control: Int = 1,
            value: Int = 0,
            sysexHex: String = ""
        ) {
            self.id = id
            self.destinationUniqueID = destinationUniqueID
            self.messageKind = messageKind
            self.channel = channel
            self.note = note
            self.velocity = velocity
            self.program = program
            self.control = control
            self.value = value
            self.sysexHex = sysexHex
        }
    }

    struct ProPresenterTriggerActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var profileId: UUID?
        var triggerPath: String

        init(id: UUID = UUID(), profileId: UUID? = nil, triggerPath: String = "/v1/trigger/next") {
            self.id = id
            self.profileId = profileId
            self.triggerPath = triggerPath
        }
    }

    struct ShureSendActionConfig: Identifiable, Codable, Equatable {
        enum CommandKind: String, Codable, CaseIterable {
            case setChannelName
            case rawCommand
        }

        var id: UUID = UUID()
        var deviceId: UUID?
        var commandKind: CommandKind
        var channelIndex: Int
        var additionalChannelIndices: [Int]
        var channelAssignments: [String: Int]
        var channelName: String
        var channelNameSource: String
        var nameFormat: String
        var nameCasing: String
        var rawCommand: String

        init(
            id: UUID = UUID(),
            deviceId: UUID? = nil,
            commandKind: CommandKind = .setChannelName,
            channelIndex: Int = 1,
            additionalChannelIndices: [Int] = [],
            channelAssignments: [String: Int] = [:],
            channelName: String = "",
            channelNameSource: String = "manual",
            nameFormat: String = "first",
            nameCasing: String = "upper",
            rawCommand: String = ""
        ) {
            self.id = id
            self.deviceId = deviceId
            self.commandKind = commandKind
            self.channelIndex = channelIndex
            self.additionalChannelIndices = additionalChannelIndices
            self.channelAssignments = channelAssignments
            self.channelName = channelName
            self.channelNameSource = channelNameSource
            self.nameFormat = nameFormat
            self.nameCasing = nameCasing
            self.rawCommand = rawCommand
        }

        enum CodingKeys: String, CodingKey {
            case id
            case deviceId
            case commandKind
            case channelIndex
            case additionalChannelIndices
            case channelAssignments
            case channelName
            case channelNameSource
            case nameFormat
            case nameCasing
            case rawCommand
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            deviceId = try c.decodeIfPresent(UUID.self, forKey: .deviceId)
            commandKind = try c.decodeIfPresent(CommandKind.self, forKey: .commandKind) ?? .setChannelName
            channelIndex = try c.decodeIfPresent(Int.self, forKey: .channelIndex) ?? 1
            additionalChannelIndices = try c.decodeIfPresent([Int].self, forKey: .additionalChannelIndices) ?? []
            channelAssignments = try c.decodeIfPresent([String: Int].self, forKey: .channelAssignments) ?? [:]
            channelName = try c.decodeIfPresent(String.self, forKey: .channelName) ?? ""
            channelNameSource = try c.decodeIfPresent(String.self, forKey: .channelNameSource) ?? "manual"
            nameFormat = try c.decodeIfPresent(String.self, forKey: .nameFormat) ?? "first"
            nameCasing = try c.decodeIfPresent(String.self, forKey: .nameCasing) ?? "upper"
            rawCommand = try c.decodeIfPresent(String.self, forKey: .rawCommand) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(deviceId, forKey: .deviceId)
            try c.encode(commandKind, forKey: .commandKind)
            try c.encode(channelIndex, forKey: .channelIndex)
            try c.encode(additionalChannelIndices, forKey: .additionalChannelIndices)
            try c.encode(channelAssignments, forKey: .channelAssignments)
            try c.encode(channelName, forKey: .channelName)
            try c.encode(channelNameSource, forKey: .channelNameSource)
            try c.encode(nameFormat, forKey: .nameFormat)
            try c.encode(nameCasing, forKey: .nameCasing)
            try c.encode(rawCommand, forKey: .rawCommand)
        }
    }

    struct SennheiserSendActionConfig: Identifiable, Codable, Equatable {
        enum CommandKind: String, Codable, CaseIterable {
            case setChannelName
            case setMute
            case setGain
            case setRfMute
            case advanced
        }

        enum HTTPMethod: String, Codable, CaseIterable {
            case get = "GET"
            case post = "POST"
            case put = "PUT"
            case patch = "PATCH"
        }

        var id: UUID = UUID()
        var deviceId: UUID?
        var commandKind: CommandKind
        var channelIndex: Int
        var additionalChannelIndices: [Int]
        var channelAssignments: [String: Int]
        var channelName: String
        var channelNameSource: String
        var nameFormat: String
        var nameCasing: String
        var muteEnabled: Bool
        var gainDb: Double
        var rfMuteEnabled: Bool
        var scheme: String
        var method: HTTPMethod
        var path: String
        var jsonBody: String

        init(
            id: UUID = UUID(),
            deviceId: UUID? = nil,
            commandKind: CommandKind = .setChannelName,
            channelIndex: Int = 1,
            additionalChannelIndices: [Int] = [],
            channelAssignments: [String: Int] = [:],
            channelName: String = "",
            channelNameSource: String = "manual",
            nameFormat: String = "first",
            nameCasing: String = "upper",
            muteEnabled: Bool = false,
            gainDb: Double = 0,
            rfMuteEnabled: Bool = false,
            scheme: String = "http",
            method: HTTPMethod = .post,
            path: String = "/",
            jsonBody: String = ""
        ) {
            self.id = id
            self.deviceId = deviceId
            self.commandKind = commandKind
            self.channelIndex = channelIndex
            self.additionalChannelIndices = additionalChannelIndices
            self.channelAssignments = channelAssignments
            self.channelName = channelName
            self.channelNameSource = channelNameSource
            self.nameFormat = nameFormat
            self.nameCasing = nameCasing
            self.muteEnabled = muteEnabled
            self.gainDb = gainDb
            self.rfMuteEnabled = rfMuteEnabled
            self.scheme = scheme
            self.method = method
            self.path = path
            self.jsonBody = jsonBody
        }

        enum CodingKeys: String, CodingKey {
            case id
            case deviceId
            case commandKind
            case channelIndex
            case additionalChannelIndices
            case channelAssignments
            case channelName
            case channelNameSource
            case nameFormat
            case nameCasing
            case muteEnabled
            case gainDb
            case rfMuteEnabled
            case scheme
            case method
            case path
            case jsonBody
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            deviceId = try c.decodeIfPresent(UUID.self, forKey: .deviceId)
            channelIndex = try c.decodeIfPresent(Int.self, forKey: .channelIndex) ?? 1
            additionalChannelIndices = try c.decodeIfPresent([Int].self, forKey: .additionalChannelIndices) ?? []
            channelAssignments = try c.decodeIfPresent([String: Int].self, forKey: .channelAssignments) ?? [:]
            channelName = try c.decodeIfPresent(String.self, forKey: .channelName) ?? ""
            channelNameSource = try c.decodeIfPresent(String.self, forKey: .channelNameSource) ?? "manual"
            nameFormat = try c.decodeIfPresent(String.self, forKey: .nameFormat) ?? "first"
            nameCasing = try c.decodeIfPresent(String.self, forKey: .nameCasing) ?? "upper"
            muteEnabled = try c.decodeIfPresent(Bool.self, forKey: .muteEnabled) ?? false
            gainDb = try c.decodeIfPresent(Double.self, forKey: .gainDb) ?? 0
            rfMuteEnabled = try c.decodeIfPresent(Bool.self, forKey: .rfMuteEnabled) ?? false
            scheme = try c.decodeIfPresent(String.self, forKey: .scheme) ?? "http"
            method = try c.decodeIfPresent(HTTPMethod.self, forKey: .method) ?? .post
            path = try c.decodeIfPresent(String.self, forKey: .path) ?? "/"
            jsonBody = try c.decodeIfPresent(String.self, forKey: .jsonBody) ?? ""

            if let decoded = try c.decodeIfPresent(CommandKind.self, forKey: .commandKind) {
                commandKind = decoded
            } else {
                let advancedConfigured = scheme != "http"
                    || method != .post
                    || path != "/"
                    || !jsonBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                commandKind = advancedConfigured ? .advanced : .setChannelName
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(deviceId, forKey: .deviceId)
            try c.encode(commandKind, forKey: .commandKind)
            try c.encode(channelIndex, forKey: .channelIndex)
            try c.encode(additionalChannelIndices, forKey: .additionalChannelIndices)
            try c.encode(channelAssignments, forKey: .channelAssignments)
            try c.encode(channelName, forKey: .channelName)
            try c.encode(channelNameSource, forKey: .channelNameSource)
            try c.encode(nameFormat, forKey: .nameFormat)
            try c.encode(nameCasing, forKey: .nameCasing)
            try c.encode(muteEnabled, forKey: .muteEnabled)
            try c.encode(gainDb, forKey: .gainDb)
            try c.encode(rfMuteEnabled, forKey: .rfMuteEnabled)
            try c.encode(scheme, forKey: .scheme)
            try c.encode(method, forKey: .method)
            try c.encode(path, forKey: .path)
            try c.encode(jsonBody, forKey: .jsonBody)
        }
    }

    struct RepeaterActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var outputCount: Int
        var repeatCount: Int
        var delayMs: Int

        init(id: UUID = UUID(), outputCount: Int = 2, repeatCount: Int = 1, delayMs: Int = 250) {
            self.id = id
            self.outputCount = outputCount
            self.repeatCount = repeatCount
            self.delayMs = delayMs
        }
    }

    struct DelayActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var delayMs: Int

        init(id: UUID = UUID(), delayMs: Int = 500) {
            self.id = id
            self.delayMs = delayMs
        }
    }

    // MARK: - Qu console action config

    enum QuActionKind: String, Codable, CaseIterable {
        case sceneRecall
        case softKey
        case channelMute
        case channelLevel
        case channelPan
        case mixAssign
        case sendLevel
        case groupLevel
        case groupMute
        case fxSendLevel
        case fxReturnLevel

        var displayName: String {
            switch self {
            case .sceneRecall: return "Scene Recall"
            case .softKey: return "Soft Key"
            case .channelMute: return "Channel Mute"
            case .channelLevel: return "Channel Level"
            case .channelPan: return "Channel Pan"
            case .mixAssign: return "Mix Assign"
            case .sendLevel: return "Send Level"
            case .groupLevel: return "Group Level"
            case .groupMute: return "Group Mute"
            case .fxSendLevel: return "FX Send Level"
            case .fxReturnLevel: return "FX Return Level"
            }
        }
    }

    enum QuSceneRecallMode: String, Codable, CaseIterable {
        case custom
        case next
        case previous

        var displayName: String {
            switch self {
            case .custom: return "Custom"
            case .next: return "Next"
            case .previous: return "Previous"
            }
        }
    }

    enum QuMuteMode: String, Codable, CaseIterable {
        case on
        case off
        case toggle

        var displayName: String {
            switch self {
            case .on: return "On"
            case .off: return "Off"
            case .toggle: return "Toggle"
            }
        }
    }

    enum QuSourceKind: String, Codable, CaseIterable {
        case input
        case st1
        case st2
        case usb
        case fxReturn
        case group
        case mix
        case lr
        case dca
        case muteGroup

        var displayName: String {
            switch self {
            case .input: return "Input"
            case .st1: return "ST1"
            case .st2: return "ST2"
            case .usb: return "USB"
            case .fxReturn: return "FX Return"
            case .group: return "Group"
            case .mix: return "Mix"
            case .lr: return "LR"
            case .dca: return "DCA"
            case .muteGroup: return "Mute Group"
            }
        }
    }

    enum QuDestinationKind: String, Codable, CaseIterable {
        case lr
        case mix
        case fxSend

        var displayName: String {
            switch self {
            case .lr: return "Main"
            case .mix: return "Mix"
            case .fxSend: return "FX Send"
            }
        }
    }

    struct QuConsoleAction: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var kind: QuActionKind = .sceneRecall
        var isEnabled: Bool = true
        var midiChannel: Int = 1

        // Scene recall
        var bank: Int? = nil
        var program: Int? = nil
        var sceneRecallMode: QuSceneRecallMode = .custom

        // Soft key
        var softKey: Int = 1

        // NRPN target routing
        var sourceKind: QuSourceKind = .input
        var sourceIndex: Int = 1
        var destinationKind: QuDestinationKind = .lr
        var destinationIndex: Int = 1

        // NRPN value / toggle
        var value: Int = 0
        var boolValue: Bool = true
        var muteMode: QuMuteMode = .on

        // Manual override for MSB/LSB
        var useManualParameter: Bool = false
        var manualMSB: Int = 0
        var manualLSB: Int = 0
    }

    enum DiGiCoChannelType: String, Codable, CaseIterable {
        case inputChannel
        case controlGroup
        case groupOutput
        case auxOutput
        case matrixOutput

        var displayName: String {
            switch self {
            case .inputChannel: return "Input Channel"
            case .controlGroup: return "Control Group"
            case .groupOutput: return "Group Output"
            case .auxOutput: return "Aux Output"
            case .matrixOutput: return "Matrix Output"
            }
        }

        var oscPrefix: String {
            switch self {
            case .inputChannel: return "/Input_Channels"
            case .controlGroup: return "/Control_Groups"
            case .groupOutput: return "/Group_Outputs"
            case .auxOutput: return "/Aux_Outputs"
            case .matrixOutput: return "/Matrix_Outputs"
            }
        }

        var defaultMaxScanCount: Int {
            switch self {
            case .inputChannel:  return 256
            case .auxOutput:     return 128
            case .groupOutput:   return 128
            case .matrixOutput:  return 64
            case .controlGroup:  return 64
            }
        }
    }

    enum DiGiCoActionKind: String, Codable, CaseIterable {
        case mute
        case solo
        case fader
        case macro

        var displayName: String {
            switch self {
            case .mute: return "Mute"
            case .solo: return "Solo"
            case .fader: return "Fader"
            case .macro: return "Recall Macro"
            }
        }
    }

    struct DiGiCoConsoleAction: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var isEnabled: Bool = true
        var kind: DiGiCoActionKind = .mute
        var channelType: DiGiCoChannelType = .inputChannel
        var channelIndex: Int = 1
        var boolValue: Bool = true    // mute/solo: true = 1.0 (on), false = 0.0 (off)
        var faderDb: Double = 0.0     // fader level in dB; 0.0 = unity
    }

    // MARK: - Standard console action config (X32/M32, Yamaha DM7/Rivage, Allen & Heath)

    enum StandardActionKind: String, Codable, CaseIterable {
        case sceneRecall
        case mute
        case level
        case pan

        var displayName: String {
            switch self {
            case .sceneRecall: return "Scene Recall"
            case .mute: return "Mute"
            case .level: return "Level"
            case .pan: return "Pan"
            }
        }
    }

    enum StandardMuteMode: String, Codable, CaseIterable {
        case on
        case off
        case toggle

        var displayName: String {
            switch self {
            case .on: return "On"
            case .off: return "Off"
            case .toggle: return "Toggle"
            }
        }
    }

    struct StandardConsoleAction: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var isEnabled: Bool = true
        var kind: StandardActionKind = .sceneRecall
        var channelIndex: Int = 1

        // Scene recall
        var sceneNumber: String = "1.00"

        // Mute
        var muteMode: StandardMuteMode = .on

        // Level (dB, -90...+10; -90 or below is sent as -inf where the protocol supports it)
        var levelDb: Double = 0.0

        // Pan (-1.0 full left ... 0.0 center ... 1.0 full right)
        var panValue: Double = 0.0
    }

    /// Per-console-node trigger binding for auto-send on trigger fire.
    struct ConsoleTriggerSendConfig: Codable, Equatable {
        /// The trigger node whose firing auto-sends channel assignments for this console. nil = no binding.
        var assignmentsTriggerNodeId: UUID?
        /// The trigger node whose firing auto-sends snapshots for this console. nil = no binding.
        var snapshotsTriggerNodeId: UUID?
    }

    // MARK: - New node configs (2026-06-03)

    struct PCOItemChangedTriggerConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var cooldownSeconds: Double = 2.0
        var titleFilter: String = ""
    }

    enum ProPresenterTriggerEvent: String, Codable, CaseIterable {
        case slideChanged
        case presentationChanged
        case messageChanged
        case timerChanged

        var displayName: String {
            switch self {
            case .slideChanged: return "Slide Changed"
            case .presentationChanged: return "Presentation Changed"
            case .messageChanged: return "Message Changed"
            case .timerChanged: return "Timer Changed"
            }
        }
    }

    struct ProPresenterTriggerConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var profileId: UUID? = nil
        var event: ProPresenterTriggerEvent = .slideChanged
        var filter: String = ""
        var cooldownSeconds: Double = 0.5
    }

    struct AppStateTriggerConfig: Identifiable, Codable, Equatable {
        enum EventKind: String, Codable, CaseIterable {
            case enterLiveMode
            case exitLiveMode
            case tabSwitch
            case appLaunch

            var displayName: String {
                switch self {
                case .enterLiveMode:  return "Enter Live Mode"
                case .exitLiveMode:   return "Exit Live Mode"
                case .tabSwitch:      return "Tab Switch"
                case .appLaunch:      return "App Launch"
                }
            }
        }
        var id: UUID = UUID()
        var eventKind: EventKind = .enterLiveMode
        var cooldownSeconds: Double = 0
    }

    struct HTTPRequestActionConfig: Identifiable, Codable, Equatable {
        enum Method: String, Codable, CaseIterable {
            case get = "GET"
            case post = "POST"
            case put = "PUT"
            case patch = "PATCH"
            case delete = "DELETE"
        }
        var id: UUID = UUID()
        var urlString: String = ""
        var method: Method = .post
        var headersJSON: String = ""
        var body: String = ""
        var timeoutSeconds: Double = 10.0
    }

    struct SetVariableActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var targetVariableNodeId: UUID? = nil
        var valueType: GraphVariableValueType = .text
        var textValue: String = ""
        var numberValue: Double = 0
        var booleanValue: Bool = false
    }

    struct SmartLightActionConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var profileID: UUID? = nil
        var providerType: SmartLightProviderType = .philipsHue
        /// Legacy single-device field kept for backward compatibility. Prefer `deviceIDs`.
        var deviceID: String = ""
        /// Ordered list of device IDs to control with this node. When non-empty, takes precedence over `deviceID`.
        var deviceIDs: [String] = []
        var action: SmartLightAction = SmartLightAction(kind: .turnOn)
        var brightnessInputOverridesConfig: Bool = true
        var colorInputOverridesConfig: Bool = true
        var powerInputOverridesConfig: Bool = true
        var sceneName: String = ""
        var showOutputPorts: Bool = false

        /// Effective device list: `deviceIDs` when populated, falls back to `deviceID`.
        var effectiveDeviceIDs: [String] {
            if !deviceIDs.isEmpty { return deviceIDs }
            if !deviceID.isEmpty { return [deviceID] }
            return []
        }

        init(
            id: UUID = UUID(),
            profileID: UUID? = nil,
            providerType: SmartLightProviderType = .philipsHue,
            deviceID: String = "",
            deviceIDs: [String] = [],
            action: SmartLightAction = SmartLightAction(kind: .turnOn),
            brightnessInputOverridesConfig: Bool = true,
            colorInputOverridesConfig: Bool = true,
            powerInputOverridesConfig: Bool = true,
            sceneName: String = "",
            showOutputPorts: Bool = false
        ) {
            self.id = id
            self.profileID = profileID
            self.providerType = providerType
            self.deviceID = deviceID
            self.deviceIDs = deviceIDs
            self.action = action
            self.brightnessInputOverridesConfig = brightnessInputOverridesConfig
            self.colorInputOverridesConfig = colorInputOverridesConfig
            self.powerInputOverridesConfig = powerInputOverridesConfig
            self.sceneName = sceneName
            self.showOutputPorts = showOutputPorts
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID)
            providerType = try c.decodeIfPresent(SmartLightProviderType.self, forKey: .providerType) ?? .philipsHue
            deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
            deviceIDs = try c.decodeIfPresent([String].self, forKey: .deviceIDs) ?? []
            action = try c.decodeIfPresent(SmartLightAction.self, forKey: .action) ?? SmartLightAction(kind: .turnOn)
            brightnessInputOverridesConfig = try c.decodeIfPresent(Bool.self, forKey: .brightnessInputOverridesConfig) ?? true
            colorInputOverridesConfig = try c.decodeIfPresent(Bool.self, forKey: .colorInputOverridesConfig) ?? true
            powerInputOverridesConfig = try c.decodeIfPresent(Bool.self, forKey: .powerInputOverridesConfig) ?? true
            sceneName = try c.decodeIfPresent(String.self, forKey: .sceneName) ?? ""
            showOutputPorts = try c.decodeIfPresent(Bool.self, forKey: .showOutputPorts) ?? false
        }
    }

    struct ToggleNodeConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var currentState: Bool = false
        var resetOnLaunch: Bool = false
    }

    struct CounterNodeConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var threshold: Int = 3
        var currentCount: Int = 0
        var resetAfterFire: Bool = true
        var resetOnLaunch: Bool = false
    }

    struct SequenceNodeConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var stepCount: Int = 3
        var currentStep: Int = 0
        var resetOnLaunch: Bool = false
    }

    struct LatchNodeConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var isEnabled: Bool = true
        var resetOnLaunch: Bool = false
        var enableTriggerNodeId: UUID? = nil
        var disableTriggerNodeId: UUID? = nil
    }

    struct CurrentTimeSourceConfig: Identifiable, Codable, Equatable {
        enum Format: String, Codable, CaseIterable {
            case timeOfDay
            case timeOfDayShort
            case secondsSinceMidnight
            case unixTimestamp

            var displayName: String {
                switch self {
                case .timeOfDay:             return "HH:mm:ss"
                case .timeOfDayShort:        return "HH:mm"
                case .secondsSinceMidnight:  return "Seconds since midnight"
                case .unixTimestamp:         return "Unix timestamp"
                }
            }
        }
        var id: UUID = UUID()
        var format: Format = .timeOfDay
    }

    // MARK: - Trigger/Sender node configs (graph-only nodes)

    struct OSCEndpointConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var host: String
        var port: UInt16

        init(id: UUID = UUID(), host: String, port: UInt16) {
            self.id = id
            self.host = host
            self.port = port
        }
    }

    enum OSCArgTemplate: Codable, Equatable {
        case int(Int)
        case float(Double)
        case string(String)
        case bool(Bool)
        case token(String)

        private enum CodingKeys: String, CodingKey { case type, int, float, string, bool, token }
        private enum Kind: String, Codable { case int, float, string, bool, token }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(Kind.self, forKey: .type)
            switch kind {
            case .int: self = .int(try c.decode(Int.self, forKey: .int))
            case .float: self = .float(try c.decode(Double.self, forKey: .float))
            case .string: self = .string(try c.decode(String.self, forKey: .string))
            case .bool: self = .bool(try c.decode(Bool.self, forKey: .bool))
            case .token: self = .token(try c.decode(String.self, forKey: .token))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .int(let v):
                try c.encode(Kind.int, forKey: .type)
                try c.encode(v, forKey: .int)
            case .float(let v):
                try c.encode(Kind.float, forKey: .type)
                try c.encode(v, forKey: .float)
            case .string(let v):
                try c.encode(Kind.string, forKey: .type)
                try c.encode(v, forKey: .string)
            case .bool(let v):
                try c.encode(Kind.bool, forKey: .type)
                try c.encode(v, forKey: .bool)
            case .token(let v):
                try c.encode(Kind.token, forKey: .type)
                try c.encode(v, forKey: .token)
            }
        }
    }

    struct OSCMessageTemplate: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var address: String
        var args: [OSCArgTemplate]

        init(id: UUID = UUID(), address: String, args: [OSCArgTemplate] = []) {
            self.id = id
            self.address = address
            self.args = args
        }
    }

    struct OSCSendConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var endpoint: OSCEndpointConfig
        var templates: [OSCMessageTemplate]

        init(id: UUID = UUID(), endpoint: OSCEndpointConfig, templates: [OSCMessageTemplate] = []) {
            self.id = id
            self.endpoint = endpoint
            self.templates = templates
        }
    }

    struct OSCReceiveConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()

        /// Legacy per-node port value used by older builds. Kept for backward compatibility.
        /// New builds should prefer `customListenPort` when `useCustomPort` is enabled.
        var listenPort: UInt16

        /// If true, this node uses `customListenPort` instead of the app's global OSC port.
        var useCustomPort: Bool

        /// Per-node override listen port (only used when `useCustomPort == true`).
        var customListenPort: UInt16

        /// Optional exact-match address filter (e.g. "/prodlink/apply").
        var addressFilter: String?

        /// If set, emit this automation event kind when a matching message arrives.
        var emitEventKind: String

        init(
            id: UUID = UUID(),
            listenPort: UInt16 = 9000,
            useCustomPort: Bool = false,
            customListenPort: UInt16 = 9000,
            addressFilter: String? = nil,
            emitEventKind: String = "osc.received"
        ) {
            self.id = id
            self.listenPort = listenPort
            self.useCustomPort = useCustomPort
            self.customListenPort = customListenPort
            self.addressFilter = addressFilter
            self.emitEventKind = emitEventKind
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case listenPort
            case useCustomPort
            case customListenPort
            case addressFilter
            case emitEventKind
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

            let legacyPort = try c.decodeIfPresent(UInt16.self, forKey: .listenPort) ?? 9000
            self.listenPort = legacyPort

            self.useCustomPort = try c.decodeIfPresent(Bool.self, forKey: .useCustomPort) ?? false

            // Migration: if `customListenPort` wasn't present in older files, seed it from legacy listenPort.
            if c.contains(.customListenPort) {
                self.customListenPort = try c.decodeIfPresent(UInt16.self, forKey: .customListenPort) ?? legacyPort
            } else {
                self.customListenPort = legacyPort
            }

            self.addressFilter = try c.decodeIfPresent(String.self, forKey: .addressFilter)
            self.emitEventKind = try c.decodeIfPresent(String.self, forKey: .emitEventKind) ?? "osc.received"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(listenPort, forKey: .listenPort)
            try c.encode(useCustomPort, forKey: .useCustomPort)
            try c.encode(customListenPort, forKey: .customListenPort)
            try c.encodeIfPresent(addressFilter, forKey: .addressFilter)
            try c.encode(emitEventKind, forKey: .emitEventKind)
        }
    }

    enum MIDIMessageType: String, Codable, CaseIterable {
        case any
        case programChange
        case noteOn
        case noteOff
        case controlChange
        case sysex
    }

    struct MIDIReceiveConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var messageType: MIDIMessageType
        var programFilter: Int?
        var channelFilter: Int?
        var noteFilter: Int?
        var ccNumberFilter: Int?
        var ccValueFilter: Int?
        var sysexPrefixHex: String?
        var emitEventKind: String

        init(
            id: UUID = UUID(),
            messageType: MIDIMessageType = .programChange,
            programFilter: Int? = nil,
            channelFilter: Int? = nil,
            noteFilter: Int? = nil,
            ccNumberFilter: Int? = nil,
            ccValueFilter: Int? = nil,
            sysexPrefixHex: String? = nil,
            emitEventKind: String = "midi.programChange"
        ) {
            self.id = id
            self.messageType = messageType
            self.programFilter = programFilter
            self.channelFilter = channelFilter
            self.noteFilter = noteFilter
            self.ccNumberFilter = ccNumberFilter
            self.ccValueFilter = ccValueFilter
            self.sysexPrefixHex = sysexPrefixHex
            self.emitEventKind = emitEventKind
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case messageType
            case programFilter
            case channelFilter
            case noteFilter
            case ccNumberFilter
            case ccValueFilter
            case sysexPrefixHex
            case emitEventKind
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.messageType = try c.decodeIfPresent(MIDIMessageType.self, forKey: .messageType) ?? .programChange
            self.programFilter = try c.decodeIfPresent(Int.self, forKey: .programFilter)
            self.channelFilter = try c.decodeIfPresent(Int.self, forKey: .channelFilter)
            self.noteFilter = try c.decodeIfPresent(Int.self, forKey: .noteFilter)
            self.ccNumberFilter = try c.decodeIfPresent(Int.self, forKey: .ccNumberFilter)
            self.ccValueFilter = try c.decodeIfPresent(Int.self, forKey: .ccValueFilter)
            self.sysexPrefixHex = try c.decodeIfPresent(String.self, forKey: .sysexPrefixHex)
            self.emitEventKind = try c.decodeIfPresent(String.self, forKey: .emitEventKind) ?? "midi.programChange"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(messageType, forKey: .messageType)
            try c.encodeIfPresent(programFilter, forKey: .programFilter)
            try c.encodeIfPresent(channelFilter, forKey: .channelFilter)
            try c.encodeIfPresent(noteFilter, forKey: .noteFilter)
            try c.encodeIfPresent(ccNumberFilter, forKey: .ccNumberFilter)
            try c.encodeIfPresent(ccValueFilter, forKey: .ccValueFilter)
            try c.encodeIfPresent(sysexPrefixHex, forKey: .sysexPrefixHex)
            try c.encode(emitEventKind, forKey: .emitEventKind)
        }
    }

    struct TimeTriggerConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()

        enum Mode: String, Codable, CaseIterable {
            case interval
            case atTime
        }

        var mode: Mode
        /// Used when mode == interval
        var intervalSeconds: Double
        /// Used when mode == atTime (local time, "HH:mm")
        var timeOfDay: String
        /// Optional debounce/cooldown to prevent repeated firing
        var cooldownSeconds: Double

        init(id: UUID = UUID(), mode: Mode = .interval, intervalSeconds: Double = 60, timeOfDay: String = "09:00", cooldownSeconds: Double = 0) {
            self.id = id
            self.mode = mode
            self.intervalSeconds = intervalSeconds
            self.timeOfDay = timeOfDay
            self.cooldownSeconds = cooldownSeconds
        }
    }

    enum DbThresholdComparison: String, Codable, CaseIterable {
        case above
        case below
    }

    enum DbThresholdMetric: String, Codable, CaseIterable {
        case spl
        case peak
        case rawDbFS
        case rawPeakDbFS
    }

    struct DbThresholdTriggerConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var metric: DbThresholdMetric
        var comparison: DbThresholdComparison
        var threshold: Double
        var cooldownSeconds: Double

        init(
            id: UUID = UUID(),
            metric: DbThresholdMetric = .spl,
            comparison: DbThresholdComparison = .above,
            threshold: Double = 70,
            cooldownSeconds: Double = 2
        ) {
            self.id = id
            self.metric = metric
            self.comparison = comparison
            self.threshold = threshold
            self.cooldownSeconds = cooldownSeconds
        }
    }

    struct WirelessTriggerConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()

        enum TriggerKind: String, Codable, CaseIterable {
            case batteryBelow
            case rfBelow
            case audioClip
            case disconnected
        }

        /// Selected wireless device to watch.
        var deviceID: UUID?
        /// Selected channel index on the device.
        var channelIndex: Int?

        var triggerKind: TriggerKind
        /// Optional threshold value, meaning depends on triggerKind.
        var threshold: Double
        /// Cooldown to prevent spam.
        var cooldownSeconds: Double

        init(
            id: UUID = UUID(),
            deviceID: UUID? = nil,
            channelIndex: Int? = nil,
            triggerKind: TriggerKind = .batteryBelow,
            threshold: Double = 25,
            cooldownSeconds: Double = 60
        ) {
            self.id = id
            self.deviceID = deviceID
            self.channelIndex = channelIndex
            self.triggerKind = triggerKind
            self.threshold = threshold
            self.cooldownSeconds = cooldownSeconds
        }
    }

    struct WordTriggerRule: Identifiable, Codable, Equatable {
        enum MatchMode: String, Codable, CaseIterable {
            case contains
            case wholeWord
        }

        var id: UUID = UUID()
        var phrase: String
        var matchMode: MatchMode
        var sourceIds: [UUID]
        var minimumConfidence: Double?
        var finalOnly: Bool
        var cooldownSeconds: Double
        var debounceSeconds: Double

        init(
            id: UUID = UUID(),
            phrase: String = "",
            matchMode: MatchMode = .contains,
            sourceIds: [UUID] = [],
            minimumConfidence: Double? = nil,
            finalOnly: Bool = true,
            cooldownSeconds: Double = 2,
            debounceSeconds: Double = 0
        ) {
            self.id = id
            self.phrase = phrase
            self.matchMode = matchMode
            self.sourceIds = sourceIds
            self.minimumConfidence = minimumConfidence
            self.finalOnly = finalOnly
            self.cooldownSeconds = cooldownSeconds
            self.debounceSeconds = debounceSeconds
        }
    }

    struct WordTriggerConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var rules: [WordTriggerRule]

        init(id: UUID = UUID(), rules: [WordTriggerRule] = [WordTriggerRule()]) {
            self.id = id
            self.rules = rules
        }
    }

    struct RosterSourceConfig: Identifiable, Codable, Equatable {
        enum Mode: String, Codable, CaseIterable {
            case singleValue
            case wholeColumn
        }

        var id: UUID = UUID()
        var mode: Mode
        var selectedColumnID: String?
        var selectedRowID: UUID?

        init(
            id: UUID = UUID(),
            mode: Mode = .singleValue,
            selectedColumnID: String? = nil,
            selectedRowID: UUID? = nil
        ) {
            self.id = id
            self.mode = mode
            self.selectedColumnID = selectedColumnID
            self.selectedRowID = selectedRowID
        }
    }

    struct ConsoleLabelSourceConfig: Identifiable, Codable, Equatable {
        enum Mode: String, Codable, CaseIterable {
            case singleChannel
            case allChannels
        }

        var id: UUID = UUID()
        var mode: Mode
        var deviceId: UUID?
        var channelIndex: Int

        init(
            id: UUID = UUID(),
            mode: Mode = .allChannels,
            deviceId: UUID? = nil,
            channelIndex: Int = 1
        ) {
            self.id = id
            self.mode = mode
            self.deviceId = deviceId
            self.channelIndex = channelIndex
        }
    }

    struct WirelessLabelSourceConfig: Identifiable, Codable, Equatable {
        enum DeviceKind: String, Codable, CaseIterable {
            case shure
            case sennheiser
        }

        enum Mode: String, Codable, CaseIterable {
            case singleChannel
            case allChannels
        }

        var id: UUID = UUID()
        var mode: Mode
        var deviceKind: DeviceKind
        var deviceId: UUID?
        var channelIndex: Int

        init(
            id: UUID = UUID(),
            mode: Mode = .allChannels,
            deviceKind: DeviceKind = .shure,
            deviceId: UUID? = nil,
            channelIndex: Int = 1
        ) {
            self.id = id
            self.mode = mode
            self.deviceKind = deviceKind
            self.deviceId = deviceId
            self.channelIndex = channelIndex
        }
    }

    struct StaticLabelSourceConfig: Identifiable, Codable, Equatable {
        enum Mode: String, Codable, CaseIterable {
            case singleValue
            case labelList
        }

        var id: UUID = UUID()
        var mode: Mode
        var label: String

        init(id: UUID = UUID(), mode: Mode = .singleValue, label: String = "") {
            self.id = id
            self.mode = mode
            self.label = label
        }
    }

    struct VariableNodeConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var name: String
        var valueType: GraphVariableValueType
        var manualTextValue: String
        var manualNumberValue: Double
        var manualBooleanValue: Bool
        /// A selected universal variable. Nil preserves the legacy manual/graph-input behavior.
        var sharedValueToken: String? = nil
        var currentTextValue: String?
        var currentNumberValue: Double?
        var currentBooleanValue: Bool?
        var lastUpdatedAt: Date?
        var sourceNodeId: UUID?

        init(
            id: UUID = UUID(),
            name: String = "",
            valueType: GraphVariableValueType = .text,
            manualTextValue: String = "",
            manualNumberValue: Double = 0,
            manualBooleanValue: Bool = false,
            sharedValueToken: String? = nil,
            currentTextValue: String? = nil,
            currentNumberValue: Double? = nil,
            currentBooleanValue: Bool? = nil,
            lastUpdatedAt: Date? = nil,
            sourceNodeId: UUID? = nil
        ) {
            self.id = id
            self.name = name
            self.valueType = valueType
            self.manualTextValue = manualTextValue
            self.manualNumberValue = manualNumberValue
            self.manualBooleanValue = manualBooleanValue
            self.sharedValueToken = sharedValueToken
            self.currentTextValue = currentTextValue
            self.currentNumberValue = currentNumberValue
            self.currentBooleanValue = currentBooleanValue
            self.lastUpdatedAt = lastUpdatedAt
            self.sourceNodeId = sourceNodeId
        }
    }

    struct ConditionNodeConfig: Identifiable, Codable, Equatable {
        enum SourceKind: String, Codable, CaseIterable {
            case payloadText
            case payloadNumber
            case payloadBoolean
            case variable

            var displayName: String {
                switch self {
                case .payloadText: return "Payload Text"
                case .payloadNumber: return "Payload Number"
                case .payloadBoolean: return "Payload Boolean"
                case .variable: return "Variable"
                }
            }
        }

        enum Operator: String, Codable, CaseIterable {
            case equals
            case notEquals
            case contains
            case greaterThan
            case lessThan
            case isTrue
            case isFalse
            case isEmpty
            case isNotEmpty

            var displayName: String {
                switch self {
                case .equals: return "Equals"
                case .notEquals: return "Does Not Equal"
                case .contains: return "Contains"
                case .greaterThan: return "Greater Than"
                case .lessThan: return "Less Than"
                case .isTrue: return "Is True"
                case .isFalse: return "Is False"
                case .isEmpty: return "Is Empty"
                case .isNotEmpty: return "Is Not Empty"
                }
            }
        }

        var id: UUID = UUID()
        var sourceKind: SourceKind
        var `operator`: Operator
        var variableNodeId: UUID?
        var comparisonText: String
        var comparisonNumber: Double
        var comparisonBoolean: Bool
        var lastPayloadText: String?
        var lastPayloadNumber: Double?
        var lastPayloadBoolean: Bool?
        var lastResolvedValueSummary: String?
        var lastEvaluationDebugSummary: String?
        var lastEvaluationResult: Bool?
        var lastEvaluatedAt: Date?

        init(
            id: UUID = UUID(),
            sourceKind: SourceKind = .payloadBoolean,
            operator: Operator = .isTrue,
            variableNodeId: UUID? = nil,
            comparisonText: String = "",
            comparisonNumber: Double = 0,
            comparisonBoolean: Bool = true,
            lastPayloadText: String? = nil,
            lastPayloadNumber: Double? = nil,
            lastPayloadBoolean: Bool? = nil,
            lastResolvedValueSummary: String? = nil,
            lastEvaluationDebugSummary: String? = nil,
            lastEvaluationResult: Bool? = nil,
            lastEvaluatedAt: Date? = nil
        ) {
            self.id = id
            self.sourceKind = sourceKind
            self.operator = `operator`
            self.variableNodeId = variableNodeId
            self.comparisonText = comparisonText
            self.comparisonNumber = comparisonNumber
            self.comparisonBoolean = comparisonBoolean
            self.lastPayloadText = lastPayloadText
            self.lastPayloadNumber = lastPayloadNumber
            self.lastPayloadBoolean = lastPayloadBoolean
            self.lastResolvedValueSummary = lastResolvedValueSummary
            self.lastEvaluationDebugSummary = lastEvaluationDebugSummary
            self.lastEvaluationResult = lastEvaluationResult
            self.lastEvaluatedAt = lastEvaluatedAt
        }
    }

    struct VistaExternalDeviceConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var displayName: String
        var host: String
        var oscPort: UInt16
        var consoleTarget: String
        var isEnabled: Bool

        init(
            id: UUID = UUID(),
            displayName: String = "Vista 3",
            host: String = "127.0.0.1",
            oscPort: UInt16 = 8000,
            consoleTarget: String = "EX1",
            isEnabled: Bool = false
        ) {
            self.id = id
            self.displayName = displayName
            self.host = host
            self.oscPort = oscPort
            self.consoleTarget = consoleTarget
            self.isEnabled = isEnabled
        }
    }

    struct VistaNodeConfig: Identifiable, Codable, Equatable {
        enum CommandKind: String, Codable, CaseIterable {
            case play
            case back
            case skipForward
            case skipBack
            case gmFader

            var displayName: String {
                switch self {
                case .play:
                    return "Play"
                case .back:
                    return "Back"
                case .skipForward:
                    return "Skip Forward"
                case .skipBack:
                    return "Skip Back"
                case .gmFader:
                    return "GM Fader"
                }
            }
        }

        var id: UUID = UUID()
        var cuelistID: String
        var cuelistLabel: String
        var lastAutoGeneratedCuelistLabel: String
        var selectedDeviceID: UUID?
        var commandKind: CommandKind
        var gmFaderValue: Double
        var externalDeviceConfig: VistaExternalDeviceConfig

        init(
            id: UUID = UUID(),
            cuelistID: String = "900",
            cuelistLabel: String = "",
            lastAutoGeneratedCuelistLabel: String = "",
            selectedDeviceID: UUID? = nil,
            commandKind: CommandKind = .play,
            gmFaderValue: Double = 1.0,
            externalDeviceConfig: VistaExternalDeviceConfig = VistaExternalDeviceConfig()
        ) {
            self.id = id
            self.cuelistID = cuelistID
            self.cuelistLabel = cuelistLabel
            self.lastAutoGeneratedCuelistLabel = lastAutoGeneratedCuelistLabel
            self.selectedDeviceID = selectedDeviceID
            self.commandKind = commandKind
            self.gmFaderValue = gmFaderValue
            self.externalDeviceConfig = externalDeviceConfig
        }
    }

    struct KeystrokeTriggerConfig: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var keyEquivalent: String
        var requiresCommand: Bool
        var requiresShift: Bool
        var requiresOption: Bool
        var requiresControl: Bool
        var allowsRepeat: Bool
        var cooldownSeconds: Double

        init(
            id: UUID = UUID(),
            keyEquivalent: String = "",
            requiresCommand: Bool = true,
            requiresShift: Bool = false,
            requiresOption: Bool = false,
            requiresControl: Bool = false,
            allowsRepeat: Bool = false,
            cooldownSeconds: Double = 0
        ) {
            self.id = id
            self.keyEquivalent = keyEquivalent
            self.requiresCommand = requiresCommand
            self.requiresShift = requiresShift
            self.requiresOption = requiresOption
            self.requiresControl = requiresControl
            self.allowsRepeat = allowsRepeat
            self.cooldownSeconds = cooldownSeconds
        }
    }

    /// Per-tile graph layout, keyed by tileID.
    /// Per-node Send-All-Consoles action configuration, keyed by node UUID string.
    var sendAllConsolesActionConfigByNodeId: [String: SendAllConsolesActionConfig] = [:]

    /// Per-node OSC Send action configuration, keyed by node UUID string.
    var oscSendActionConfigByNodeId: [String: OSCSendActionConfig] = [:]

    /// Per-node Notify action configuration, keyed by node UUID string.
    var notifyActionConfigByNodeId: [String: NotifyActionConfig] = [:]

    /// Per-node LAN Notify action configuration, keyed by node UUID string.
    var lanNotifyActionConfigByNodeId: [String: LANNotifyActionConfig] = [:]

    /// Per-node in-app control action configuration, keyed by node UUID string.
    var appControlActionConfigByNodeId: [String: AppControlActionConfig] = [:]

    /// Per-node MIDI Send action configuration, keyed by node UUID string.
    var midiSendActionConfigByNodeId: [String: MIDISendActionConfig] = [:]

    /// Per-node ProPresenter trigger action configuration, keyed by node UUID string.
    var proPresenterTriggerActionConfigByNodeId: [String: ProPresenterTriggerActionConfig] = [:]

    /// Per-node Repeater configuration, keyed by node UUID string.
    var repeaterActionConfigByNodeId: [String: RepeaterActionConfig] = [:]

    /// Per-node Delay configuration, keyed by node UUID string.
    var delayActionConfigByNodeId: [String: DelayActionConfig] = [:]

    /// Per-console Qu action list, keyed by console node UUID string.
    var quConsoleActionsByNodeId: [String: [QuConsoleAction]] = [:]
    var standardConsoleActionsByNodeId: [String: [StandardConsoleAction]] = [:]

    /// Per-console DiGiCo action list, keyed by console node UUID string.
    var digicoConsoleActionsByNodeId: [String: [DiGiCoConsoleAction]] = [:]

    /// Per-console-node trigger send bindings. Keyed by console node UUID string.
    var consoleTriggerSendConfigByNodeId: [String: ConsoleTriggerSendConfig] = [:]

    /// Per-console-node device association. Keyed by node UUID string.
    /// Maps a console graph node instance ID -> ExternalDeviceConfig.id.
    /// Absent entries (nodes created before this field existed) are resolved at the call site
    /// via SHA-256 derivation from the device UUID.
    var consoleDeviceIdByNodeId: [String: UUID] = [:]

    var tileLayouts: [UUID: TileGraphLayout] = [:]
    var hiddenNodeIds: [UUID] = []
    /// Manual People node source mode by nodeId ("pco" or "custom"). Default "pco".
    var peopleSourceByNodeId: [String: String] = [:]
    /// Deprecated: older files used a single on/off key list for module-group nodes.
    /// Keep for backward compatibility; new builds should prefer `moduleGroupNodeInstances`.
    var enabledModuleGroupKeys: [String] = []

    /// Graph-only module-group nodes that the user explicitly added in Graph view.
    /// Allows multiple instances of the same group (e.g. multiple People nodes).
    var moduleGroupNodeInstances: [ModuleGroupNodeInstance] = []

    /// Per-People-node team filter. Keyed by node UUID string for JSON compatibility.
    /// Missing/empty array means "All teams".
    var peopleTeamFiltersByNodeId: [String: [String]] = [:]

    /// Per-node custom people list for manual People nodes, keyed by node UUID string.
    var customPeopleByNodeId: [String: [CustomPeopleEntry]] = [:]

    /// Per-node roster source configuration, keyed by node UUID string.
    var rosterSourceConfigByNodeId: [String: RosterSourceConfig] = [:]

    /// Per-node console label source configuration, keyed by node UUID string.
    var consoleLabelSourceConfigByNodeId: [String: ConsoleLabelSourceConfig] = [:]

    /// Per-node wireless label source configuration, keyed by node UUID string.
    var wirelessLabelSourceConfigByNodeId: [String: WirelessLabelSourceConfig] = [:]

    /// Per-node static label source configuration, keyed by node UUID string.
    var staticLabelSourceConfigByNodeId: [String: StaticLabelSourceConfig] = [:]

    /// Per-node variable configuration, keyed by node UUID string.
    var variableNodeConfigByNodeId: [String: VariableNodeConfig] = [:]

    /// Per-node conditional branching configuration, keyed by node UUID string.
    var conditionNodeConfigByNodeId: [String: ConditionNodeConfig] = [:]

    /// Per-node Vista export configuration, keyed by node UUID string.
    var vistaNodeConfigByNodeId: [String: VistaNodeConfig] = [:]

    /// Per-node OSC Receive configuration, keyed by node UUID string.
    var oscReceiveConfigByNodeId: [String: OSCReceiveConfig] = [:]

    /// Per-node MIDI Receive configuration, keyed by node UUID string.
    var midiReceiveConfigByNodeId: [String: MIDIReceiveConfig] = [:]

    /// Per-node Keystroke trigger configuration, keyed by node UUID string.
    var keystrokeTriggerConfigByNodeId: [String: KeystrokeTriggerConfig] = [:]

    /// Per-node Time trigger configuration, keyed by node UUID string.
    var timeTriggerConfigByNodeId: [String: TimeTriggerConfig] = [:]

    /// Per-node dB Threshold trigger configuration, keyed by node UUID string.
    var dbThresholdConfigByNodeId: [String: DbThresholdTriggerConfig] = [:]

    /// Per-node Shure trigger configuration, keyed by node UUID string.
    var shureTriggerConfigByNodeId: [String: WirelessTriggerConfig] = [:]

    /// Per-node Sennheiser trigger configuration, keyed by node UUID string.
    var sennheiserTriggerConfigByNodeId: [String: WirelessTriggerConfig] = [:]

    /// Per-node Shure destination configuration, keyed by node UUID string.
    var shureSendActionConfigByNodeId: [String: ShureSendActionConfig] = [:]

    /// Per-node Sennheiser destination configuration, keyed by node UUID string.
    var sennheiserSendActionConfigByNodeId: [String: SennheiserSendActionConfig] = [:]

    /// Per-node Word Trigger configuration, keyed by node UUID string.
    var wordTriggerConfigByNodeId: [String: WordTriggerConfig] = [:]
    var pcoItemChangedConfigByNodeId: [String: PCOItemChangedTriggerConfig] = [:]
    var proPresenterTriggerConfigByNodeId: [String: ProPresenterTriggerConfig] = [:]
    var appStateTriggerConfigByNodeId: [String: AppStateTriggerConfig] = [:]
    var httpRequestActionConfigByNodeId: [String: HTTPRequestActionConfig] = [:]
    var setVariableActionConfigByNodeId: [String: SetVariableActionConfig] = [:]
    var smartLightActionConfigByNodeId: [String: SmartLightActionConfig] = [:]
    var toggleNodeConfigByNodeId: [String: ToggleNodeConfig] = [:]
    var counterNodeConfigByNodeId: [String: CounterNodeConfig] = [:]
    var sequenceNodeConfigByNodeId: [String: SequenceNodeConfig] = [:]
    var latchNodeConfigByNodeId: [String: LatchNodeConfig] = [:]
    var currentTimeSourceConfigByNodeId: [String: CurrentTimeSourceConfig] = [:]

    /// Stable mapping from a port identifier string -> owning node (tile or module-group node) UUID.
    ///
    /// Our `GraphLink` stores `fromPortId`/`toPortId` as `String` identifiers. To reliably determine which
    /// node a port belongs to (for things like "OSC Receive directly linked to a Console"), we persist
    /// this reverse index in the graph model.
    ///
    /// This is populated by the Graph UI when nodes/ports are rendered and updated whenever nodes are
    /// added/removed.
    var nodeIdByPortId: [String: UUID] = [:]

    /// Links between tile ports.
    var links: [GraphLink] = []

    /// Optional: user-visible name for multiple graphs per tab (future).
    var name: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case tileLayouts
        case hiddenNodeIds
        case enabledModuleGroupKeys
        case moduleGroupNodeInstances
        case peopleTeamFiltersByNodeId
        case customPeopleByNodeId
        case rosterSourceConfigByNodeId
        case consoleLabelSourceConfigByNodeId
        case wirelessLabelSourceConfigByNodeId
        case staticLabelSourceConfigByNodeId
        case variableNodeConfigByNodeId
        case conditionNodeConfigByNodeId
        case vistaNodeConfigByNodeId
        case oscReceiveConfigByNodeId
        case midiReceiveConfigByNodeId
        case keystrokeTriggerConfigByNodeId
        case timeTriggerConfigByNodeId
        case dbThresholdConfigByNodeId
        case shureTriggerConfigByNodeId
        case sennheiserTriggerConfigByNodeId
        case shureSendActionConfigByNodeId
        case sennheiserSendActionConfigByNodeId
        case wordTriggerConfigByNodeId
        case pcoItemChangedConfigByNodeId
        case proPresenterTriggerConfigByNodeId
        case appStateTriggerConfigByNodeId
        case httpRequestActionConfigByNodeId
        case setVariableActionConfigByNodeId
        case smartLightActionConfigByNodeId
        case toggleNodeConfigByNodeId
        case counterNodeConfigByNodeId
        case sequenceNodeConfigByNodeId
        case latchNodeConfigByNodeId
        case currentTimeSourceConfigByNodeId
        case sendAllConsolesActionConfigByNodeId
        case oscSendActionConfigByNodeId
        case notifyActionConfigByNodeId
        case lanNotifyActionConfigByNodeId
        case appControlActionConfigByNodeId
        case midiSendActionConfigByNodeId
        case proPresenterTriggerActionConfigByNodeId
        case repeaterActionConfigByNodeId
        case delayActionConfigByNodeId
        case quConsoleActionsByNodeId
        case standardConsoleActionsByNodeId
        case digicoConsoleActionsByNodeId
        case consoleTriggerSendConfigByNodeId
        case consoleDeviceIdByNodeId
        case nodeIdByPortId
        case links
        case name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.tileLayouts = try c.decodeIfPresent([UUID: TileGraphLayout].self, forKey: .tileLayouts) ?? [:]
        self.hiddenNodeIds = try c.decodeIfPresent([UUID].self, forKey: .hiddenNodeIds) ?? []
        self.enabledModuleGroupKeys = try c.decodeIfPresent([String].self, forKey: .enabledModuleGroupKeys) ?? []
        self.moduleGroupNodeInstances = try c.decodeIfPresent([ModuleGroupNodeInstance].self, forKey: .moduleGroupNodeInstances) ?? []
        self.peopleTeamFiltersByNodeId = try c.decodeIfPresent([String: [String]].self, forKey: .peopleTeamFiltersByNodeId) ?? [:]
        self.customPeopleByNodeId = try c.decodeIfPresent([String: [CustomPeopleEntry]].self, forKey: .customPeopleByNodeId) ?? [:]
        self.rosterSourceConfigByNodeId = try c.decodeIfPresent([String: RosterSourceConfig].self, forKey: .rosterSourceConfigByNodeId) ?? [:]
        self.consoleLabelSourceConfigByNodeId = try c.decodeIfPresent([String: ConsoleLabelSourceConfig].self, forKey: .consoleLabelSourceConfigByNodeId) ?? [:]
        self.wirelessLabelSourceConfigByNodeId = try c.decodeIfPresent([String: WirelessLabelSourceConfig].self, forKey: .wirelessLabelSourceConfigByNodeId) ?? [:]
        self.staticLabelSourceConfigByNodeId = try c.decodeIfPresent([String: StaticLabelSourceConfig].self, forKey: .staticLabelSourceConfigByNodeId) ?? [:]
        self.variableNodeConfigByNodeId = try c.decodeIfPresent([String: VariableNodeConfig].self, forKey: .variableNodeConfigByNodeId) ?? [:]
        self.conditionNodeConfigByNodeId = try c.decodeIfPresent([String: ConditionNodeConfig].self, forKey: .conditionNodeConfigByNodeId) ?? [:]
        self.vistaNodeConfigByNodeId = try c.decodeIfPresent([String: VistaNodeConfig].self, forKey: .vistaNodeConfigByNodeId) ?? [:]
        self.oscReceiveConfigByNodeId = try c.decodeIfPresent([String: OSCReceiveConfig].self, forKey: .oscReceiveConfigByNodeId) ?? [:]
        self.midiReceiveConfigByNodeId = try c.decodeIfPresent([String: MIDIReceiveConfig].self, forKey: .midiReceiveConfigByNodeId) ?? [:]
        self.keystrokeTriggerConfigByNodeId = try c.decodeIfPresent([String: KeystrokeTriggerConfig].self, forKey: .keystrokeTriggerConfigByNodeId) ?? [:]
        self.timeTriggerConfigByNodeId = try c.decodeIfPresent([String: TimeTriggerConfig].self, forKey: .timeTriggerConfigByNodeId) ?? [:]
        self.dbThresholdConfigByNodeId = try c.decodeIfPresent([String: DbThresholdTriggerConfig].self, forKey: .dbThresholdConfigByNodeId) ?? [:]
        self.shureTriggerConfigByNodeId = try c.decodeIfPresent([String: WirelessTriggerConfig].self, forKey: .shureTriggerConfigByNodeId) ?? [:]
        self.sennheiserTriggerConfigByNodeId = try c.decodeIfPresent([String: WirelessTriggerConfig].self, forKey: .sennheiserTriggerConfigByNodeId) ?? [:]
        self.shureSendActionConfigByNodeId = try c.decodeIfPresent([String: ShureSendActionConfig].self, forKey: .shureSendActionConfigByNodeId) ?? [:]
        self.sennheiserSendActionConfigByNodeId = try c.decodeIfPresent([String: SennheiserSendActionConfig].self, forKey: .sennheiserSendActionConfigByNodeId) ?? [:]
        self.wordTriggerConfigByNodeId = try c.decodeIfPresent([String: WordTriggerConfig].self, forKey: .wordTriggerConfigByNodeId) ?? [:]
        self.pcoItemChangedConfigByNodeId = try c.decodeIfPresent([String: PCOItemChangedTriggerConfig].self, forKey: .pcoItemChangedConfigByNodeId) ?? [:]
        self.proPresenterTriggerConfigByNodeId = try c.decodeIfPresent([String: ProPresenterTriggerConfig].self, forKey: .proPresenterTriggerConfigByNodeId) ?? [:]
        self.appStateTriggerConfigByNodeId = try c.decodeIfPresent([String: AppStateTriggerConfig].self, forKey: .appStateTriggerConfigByNodeId) ?? [:]
        self.httpRequestActionConfigByNodeId = try c.decodeIfPresent([String: HTTPRequestActionConfig].self, forKey: .httpRequestActionConfigByNodeId) ?? [:]
        self.setVariableActionConfigByNodeId = try c.decodeIfPresent([String: SetVariableActionConfig].self, forKey: .setVariableActionConfigByNodeId) ?? [:]
        self.smartLightActionConfigByNodeId = try c.decodeIfPresent([String: SmartLightActionConfig].self, forKey: .smartLightActionConfigByNodeId) ?? [:]
        self.toggleNodeConfigByNodeId = try c.decodeIfPresent([String: ToggleNodeConfig].self, forKey: .toggleNodeConfigByNodeId) ?? [:]
        self.counterNodeConfigByNodeId = try c.decodeIfPresent([String: CounterNodeConfig].self, forKey: .counterNodeConfigByNodeId) ?? [:]
        self.sequenceNodeConfigByNodeId = try c.decodeIfPresent([String: SequenceNodeConfig].self, forKey: .sequenceNodeConfigByNodeId) ?? [:]
        self.latchNodeConfigByNodeId = try c.decodeIfPresent([String: LatchNodeConfig].self, forKey: .latchNodeConfigByNodeId) ?? [:]
        self.currentTimeSourceConfigByNodeId = try c.decodeIfPresent([String: CurrentTimeSourceConfig].self, forKey: .currentTimeSourceConfigByNodeId) ?? [:]
        self.sendAllConsolesActionConfigByNodeId = try c.decodeIfPresent([String: SendAllConsolesActionConfig].self, forKey: .sendAllConsolesActionConfigByNodeId) ?? [:]
        self.oscSendActionConfigByNodeId = try c.decodeIfPresent([String: OSCSendActionConfig].self, forKey: .oscSendActionConfigByNodeId) ?? [:]
        self.notifyActionConfigByNodeId = try c.decodeIfPresent([String: NotifyActionConfig].self, forKey: .notifyActionConfigByNodeId) ?? [:]
        self.lanNotifyActionConfigByNodeId = try c.decodeIfPresent([String: LANNotifyActionConfig].self, forKey: .lanNotifyActionConfigByNodeId) ?? [:]
        self.appControlActionConfigByNodeId = try c.decodeIfPresent([String: AppControlActionConfig].self, forKey: .appControlActionConfigByNodeId) ?? [:]
        self.midiSendActionConfigByNodeId = try c.decodeIfPresent([String: MIDISendActionConfig].self, forKey: .midiSendActionConfigByNodeId) ?? [:]
        self.proPresenterTriggerActionConfigByNodeId = try c.decodeIfPresent([String: ProPresenterTriggerActionConfig].self, forKey: .proPresenterTriggerActionConfigByNodeId) ?? [:]
        self.repeaterActionConfigByNodeId = try c.decodeIfPresent([String: RepeaterActionConfig].self, forKey: .repeaterActionConfigByNodeId) ?? [:]
        self.delayActionConfigByNodeId = try c.decodeIfPresent([String: DelayActionConfig].self, forKey: .delayActionConfigByNodeId) ?? [:]
        self.quConsoleActionsByNodeId = try c.decodeIfPresent([String: [QuConsoleAction]].self, forKey: .quConsoleActionsByNodeId) ?? [:]
        self.standardConsoleActionsByNodeId = try c.decodeIfPresent([String: [StandardConsoleAction]].self, forKey: .standardConsoleActionsByNodeId) ?? [:]
        self.digicoConsoleActionsByNodeId = try c.decodeIfPresent([String: [DiGiCoConsoleAction]].self, forKey: .digicoConsoleActionsByNodeId) ?? [:]
        self.consoleTriggerSendConfigByNodeId = try c.decodeIfPresent([String: ConsoleTriggerSendConfig].self, forKey: .consoleTriggerSendConfigByNodeId) ?? [:]
        self.consoleDeviceIdByNodeId = try c.decodeIfPresent([String: UUID].self, forKey: .consoleDeviceIdByNodeId) ?? [:]
        self.nodeIdByPortId = try c.decodeIfPresent([String: UUID].self, forKey: .nodeIdByPortId) ?? [:]
        self.links = try c.decodeIfPresent([GraphLink].self, forKey: .links) ?? []
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tileLayouts, forKey: .tileLayouts)
        try c.encode(hiddenNodeIds, forKey: .hiddenNodeIds)
        try c.encode(enabledModuleGroupKeys, forKey: .enabledModuleGroupKeys)
        try c.encode(moduleGroupNodeInstances, forKey: .moduleGroupNodeInstances)
        try c.encode(peopleTeamFiltersByNodeId, forKey: .peopleTeamFiltersByNodeId)
        try c.encode(customPeopleByNodeId, forKey: .customPeopleByNodeId)
        try c.encode(rosterSourceConfigByNodeId, forKey: .rosterSourceConfigByNodeId)
        try c.encode(consoleLabelSourceConfigByNodeId, forKey: .consoleLabelSourceConfigByNodeId)
        try c.encode(wirelessLabelSourceConfigByNodeId, forKey: .wirelessLabelSourceConfigByNodeId)
        try c.encode(staticLabelSourceConfigByNodeId, forKey: .staticLabelSourceConfigByNodeId)
        try c.encode(variableNodeConfigByNodeId, forKey: .variableNodeConfigByNodeId)
        try c.encode(conditionNodeConfigByNodeId, forKey: .conditionNodeConfigByNodeId)
        try c.encode(vistaNodeConfigByNodeId, forKey: .vistaNodeConfigByNodeId)
        try c.encode(oscReceiveConfigByNodeId, forKey: .oscReceiveConfigByNodeId)
        try c.encode(midiReceiveConfigByNodeId, forKey: .midiReceiveConfigByNodeId)
        try c.encode(keystrokeTriggerConfigByNodeId, forKey: .keystrokeTriggerConfigByNodeId)
        try c.encode(timeTriggerConfigByNodeId, forKey: .timeTriggerConfigByNodeId)
        try c.encode(dbThresholdConfigByNodeId, forKey: .dbThresholdConfigByNodeId)
        try c.encode(shureTriggerConfigByNodeId, forKey: .shureTriggerConfigByNodeId)
        try c.encode(sennheiserTriggerConfigByNodeId, forKey: .sennheiserTriggerConfigByNodeId)
        try c.encode(shureSendActionConfigByNodeId, forKey: .shureSendActionConfigByNodeId)
        try c.encode(sennheiserSendActionConfigByNodeId, forKey: .sennheiserSendActionConfigByNodeId)
        try c.encode(wordTriggerConfigByNodeId, forKey: .wordTriggerConfigByNodeId)
        try c.encode(pcoItemChangedConfigByNodeId, forKey: .pcoItemChangedConfigByNodeId)
        try c.encode(proPresenterTriggerConfigByNodeId, forKey: .proPresenterTriggerConfigByNodeId)
        try c.encode(appStateTriggerConfigByNodeId, forKey: .appStateTriggerConfigByNodeId)
        try c.encode(httpRequestActionConfigByNodeId, forKey: .httpRequestActionConfigByNodeId)
        try c.encode(setVariableActionConfigByNodeId, forKey: .setVariableActionConfigByNodeId)
        try c.encode(smartLightActionConfigByNodeId, forKey: .smartLightActionConfigByNodeId)
        try c.encode(toggleNodeConfigByNodeId, forKey: .toggleNodeConfigByNodeId)
        try c.encode(counterNodeConfigByNodeId, forKey: .counterNodeConfigByNodeId)
        try c.encode(sequenceNodeConfigByNodeId, forKey: .sequenceNodeConfigByNodeId)
        try c.encode(latchNodeConfigByNodeId, forKey: .latchNodeConfigByNodeId)
        try c.encode(currentTimeSourceConfigByNodeId, forKey: .currentTimeSourceConfigByNodeId)
        try c.encode(sendAllConsolesActionConfigByNodeId, forKey: .sendAllConsolesActionConfigByNodeId)
        try c.encode(oscSendActionConfigByNodeId, forKey: .oscSendActionConfigByNodeId)
        try c.encode(notifyActionConfigByNodeId, forKey: .notifyActionConfigByNodeId)
        try c.encode(lanNotifyActionConfigByNodeId, forKey: .lanNotifyActionConfigByNodeId)
        try c.encode(appControlActionConfigByNodeId, forKey: .appControlActionConfigByNodeId)
        try c.encode(midiSendActionConfigByNodeId, forKey: .midiSendActionConfigByNodeId)
        try c.encode(proPresenterTriggerActionConfigByNodeId, forKey: .proPresenterTriggerActionConfigByNodeId)
        try c.encode(repeaterActionConfigByNodeId, forKey: .repeaterActionConfigByNodeId)
        try c.encode(delayActionConfigByNodeId, forKey: .delayActionConfigByNodeId)
        try c.encode(quConsoleActionsByNodeId, forKey: .quConsoleActionsByNodeId)
        try c.encode(standardConsoleActionsByNodeId, forKey: .standardConsoleActionsByNodeId)
        try c.encode(digicoConsoleActionsByNodeId, forKey: .digicoConsoleActionsByNodeId)
        try c.encode(consoleTriggerSendConfigByNodeId, forKey: .consoleTriggerSendConfigByNodeId)
        try c.encode(consoleDeviceIdByNodeId, forKey: .consoleDeviceIdByNodeId)
        try c.encode(nodeIdByPortId, forKey: .nodeIdByPortId)
        try c.encode(links, forKey: .links)
        try c.encodeIfPresent(name, forKey: .name)
    }

    init(
        id: UUID = UUID(),
        tileLayouts: [UUID: TileGraphLayout] = [:],
        hiddenNodeIds: [UUID] = [],
        enabledModuleGroupKeys: [String] = [],
        moduleGroupNodeInstances: [ModuleGroupNodeInstance] = [],
        peopleTeamFiltersByNodeId: [String: [String]] = [:],
        customPeopleByNodeId: [String: [CustomPeopleEntry]] = [:],
        rosterSourceConfigByNodeId: [String: RosterSourceConfig] = [:],
        consoleLabelSourceConfigByNodeId: [String: ConsoleLabelSourceConfig] = [:],
        wirelessLabelSourceConfigByNodeId: [String: WirelessLabelSourceConfig] = [:],
        staticLabelSourceConfigByNodeId: [String: StaticLabelSourceConfig] = [:],
        variableNodeConfigByNodeId: [String: VariableNodeConfig] = [:],
        conditionNodeConfigByNodeId: [String: ConditionNodeConfig] = [:],
        vistaNodeConfigByNodeId: [String: VistaNodeConfig] = [:],
        oscReceiveConfigByNodeId: [String: OSCReceiveConfig] = [:],
        midiReceiveConfigByNodeId: [String: MIDIReceiveConfig] = [:],
        keystrokeTriggerConfigByNodeId: [String: KeystrokeTriggerConfig] = [:],
        timeTriggerConfigByNodeId: [String: TimeTriggerConfig] = [:],
        dbThresholdConfigByNodeId: [String: DbThresholdTriggerConfig] = [:],
        shureTriggerConfigByNodeId: [String: WirelessTriggerConfig] = [:],
        sennheiserTriggerConfigByNodeId: [String: WirelessTriggerConfig] = [:],
        shureSendActionConfigByNodeId: [String: ShureSendActionConfig] = [:],
        sennheiserSendActionConfigByNodeId: [String: SennheiserSendActionConfig] = [:],
        wordTriggerConfigByNodeId: [String: WordTriggerConfig] = [:],
        pcoItemChangedConfigByNodeId: [String: PCOItemChangedTriggerConfig] = [:],
        proPresenterTriggerConfigByNodeId: [String: ProPresenterTriggerConfig] = [:],
        appStateTriggerConfigByNodeId: [String: AppStateTriggerConfig] = [:],
        httpRequestActionConfigByNodeId: [String: HTTPRequestActionConfig] = [:],
        setVariableActionConfigByNodeId: [String: SetVariableActionConfig] = [:],
        smartLightActionConfigByNodeId: [String: SmartLightActionConfig] = [:],
        toggleNodeConfigByNodeId: [String: ToggleNodeConfig] = [:],
        counterNodeConfigByNodeId: [String: CounterNodeConfig] = [:],
        sequenceNodeConfigByNodeId: [String: SequenceNodeConfig] = [:],
        latchNodeConfigByNodeId: [String: LatchNodeConfig] = [:],
        currentTimeSourceConfigByNodeId: [String: CurrentTimeSourceConfig] = [:],
        sendAllConsolesActionConfigByNodeId: [String: SendAllConsolesActionConfig] = [:],
        oscSendActionConfigByNodeId: [String: OSCSendActionConfig] = [:],
        notifyActionConfigByNodeId: [String: NotifyActionConfig] = [:],
        lanNotifyActionConfigByNodeId: [String: LANNotifyActionConfig] = [:],
        appControlActionConfigByNodeId: [String: AppControlActionConfig] = [:],
        midiSendActionConfigByNodeId: [String: MIDISendActionConfig] = [:],
        proPresenterTriggerActionConfigByNodeId: [String: ProPresenterTriggerActionConfig] = [:],
        repeaterActionConfigByNodeId: [String: RepeaterActionConfig] = [:],
        delayActionConfigByNodeId: [String: DelayActionConfig] = [:],
        quConsoleActionsByNodeId: [String: [QuConsoleAction]] = [:],
        standardConsoleActionsByNodeId: [String: [StandardConsoleAction]] = [:],
        digicoConsoleActionsByNodeId: [String: [DiGiCoConsoleAction]] = [:],
        consoleTriggerSendConfigByNodeId: [String: ConsoleTriggerSendConfig] = [:],
        consoleDeviceIdByNodeId: [String: UUID] = [:],
        nodeIdByPortId: [String: UUID] = [:],
        links: [GraphLink] = [],
        name: String? = nil
    ) {
        self.id = id
        self.tileLayouts = tileLayouts
        self.hiddenNodeIds = hiddenNodeIds
        self.enabledModuleGroupKeys = enabledModuleGroupKeys
        self.moduleGroupNodeInstances = moduleGroupNodeInstances
        self.peopleTeamFiltersByNodeId = peopleTeamFiltersByNodeId
        self.customPeopleByNodeId = customPeopleByNodeId
        self.rosterSourceConfigByNodeId = rosterSourceConfigByNodeId
        self.consoleLabelSourceConfigByNodeId = consoleLabelSourceConfigByNodeId
        self.wirelessLabelSourceConfigByNodeId = wirelessLabelSourceConfigByNodeId
        self.staticLabelSourceConfigByNodeId = staticLabelSourceConfigByNodeId
        self.variableNodeConfigByNodeId = variableNodeConfigByNodeId
        self.conditionNodeConfigByNodeId = conditionNodeConfigByNodeId
        self.vistaNodeConfigByNodeId = vistaNodeConfigByNodeId
        self.oscReceiveConfigByNodeId = oscReceiveConfigByNodeId
        self.midiReceiveConfigByNodeId = midiReceiveConfigByNodeId
        self.keystrokeTriggerConfigByNodeId = keystrokeTriggerConfigByNodeId
        self.timeTriggerConfigByNodeId = timeTriggerConfigByNodeId
        self.dbThresholdConfigByNodeId = dbThresholdConfigByNodeId
        self.shureTriggerConfigByNodeId = shureTriggerConfigByNodeId
        self.sennheiserTriggerConfigByNodeId = sennheiserTriggerConfigByNodeId
        self.shureSendActionConfigByNodeId = shureSendActionConfigByNodeId
        self.sennheiserSendActionConfigByNodeId = sennheiserSendActionConfigByNodeId
        self.wordTriggerConfigByNodeId = wordTriggerConfigByNodeId
        self.pcoItemChangedConfigByNodeId = pcoItemChangedConfigByNodeId
        self.proPresenterTriggerConfigByNodeId = proPresenterTriggerConfigByNodeId
        self.appStateTriggerConfigByNodeId = appStateTriggerConfigByNodeId
        self.httpRequestActionConfigByNodeId = httpRequestActionConfigByNodeId
        self.setVariableActionConfigByNodeId = setVariableActionConfigByNodeId
        self.smartLightActionConfigByNodeId = smartLightActionConfigByNodeId
        self.toggleNodeConfigByNodeId = toggleNodeConfigByNodeId
        self.counterNodeConfigByNodeId = counterNodeConfigByNodeId
        self.sequenceNodeConfigByNodeId = sequenceNodeConfigByNodeId
        self.latchNodeConfigByNodeId = latchNodeConfigByNodeId
        self.currentTimeSourceConfigByNodeId = currentTimeSourceConfigByNodeId
        self.sendAllConsolesActionConfigByNodeId = sendAllConsolesActionConfigByNodeId
        self.oscSendActionConfigByNodeId = oscSendActionConfigByNodeId
        self.notifyActionConfigByNodeId = notifyActionConfigByNodeId
        self.lanNotifyActionConfigByNodeId = lanNotifyActionConfigByNodeId
        self.appControlActionConfigByNodeId = appControlActionConfigByNodeId
        self.midiSendActionConfigByNodeId = midiSendActionConfigByNodeId
        self.proPresenterTriggerActionConfigByNodeId = proPresenterTriggerActionConfigByNodeId
        self.repeaterActionConfigByNodeId = repeaterActionConfigByNodeId
        self.delayActionConfigByNodeId = delayActionConfigByNodeId
        self.quConsoleActionsByNodeId = quConsoleActionsByNodeId
        self.standardConsoleActionsByNodeId = standardConsoleActionsByNodeId
        self.digicoConsoleActionsByNodeId = digicoConsoleActionsByNodeId
        self.consoleTriggerSendConfigByNodeId = consoleTriggerSendConfigByNodeId
        self.consoleDeviceIdByNodeId = consoleDeviceIdByNodeId
        self.nodeIdByPortId = nodeIdByPortId
        self.links = links
        self.name = name
    }
}

/// A directed connection between two ports.
/// Ports are identified by stable string IDs (derived from tile kind/modules).
struct GraphLink: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    var fromTileId: UUID
    var fromPortId: String

    var toTileId: UUID
    var toPortId: String

    var kind: LinkKind
    var isEnabled: Bool

    /// Optional label for display/debug.
    var label: String?

    init(
        id: UUID = UUID(),
        fromTileId: UUID,
        fromPortId: String,
        toTileId: UUID,
        toPortId: String,
        kind: LinkKind,
        isEnabled: Bool = true,
        label: String? = nil
    ) {
        self.id = id
        self.fromTileId = fromTileId
        self.fromPortId = fromPortId
        self.toTileId = toTileId
        self.toPortId = toPortId
        self.kind = kind
        self.isEnabled = isEnabled
        self.label = label
    }
}

enum LinkKind: String, Codable, CaseIterable {
    /// Data/value flows (e.g. PersonName -> ConsoleChannelName).
    case patch
    /// Identity mapping (e.g. PCO Position -> Person tile).
    case identity
    /// Event/trigger automation (e.g. PCO CurrentItemChanged -> Console Snapshot Fire).
    case automation
}

// MARK: - Graph events

/// External events that can cause graph evaluation.
/// This stays very small; most of the work is handled by the runtime.
enum GraphEvent: Equatable {
    /// User explicitly requests apply (button press or OSC inbound).
    case apply

    /// Apply only for a specific console device.
    case applyForConsole(externalDeviceId: UUID)

    /// A PCO current item changed (rundown follow).
    case pcoCurrentItemChanged(itemId: String?, title: String?)
}
