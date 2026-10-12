//
//  GraphCommands.swift
//  Relay Dashboard
//
//  Execution payloads produced by GraphRuntime.
//

import Foundation

/// A parameter kind for `ConsoleCommand.setChannelParameter`. Value semantics are
/// normalized across consoles: mute uses 1.0=muted/0.0=unmuted, level is dB, pan is
/// -1.0 (full left) ... 1.0 (full right). Each connector translates to its own wire format.
enum ConsoleParameterKind: String, Equatable {
    case mute
    case level
    case pan
}

/// High-level command intended for external device integrations.
enum GraphCommand: Equatable {
    case console(ConsoleCommand)
    /// Send an OSC message to a network endpoint.
    case osc(OSCCommand)
    /// Internal automation/event emitted by trigger nodes (used by GraphRuntime).
    case event(TriggerEvent)
}

/// A device-facing command that can be executed by a ConsoleConnector.
enum ConsoleCommand: Equatable {
    /// Rename an input/channel on a console.
    case setChannelName(externalDeviceId: UUID, channel: Int, name: String)

    /// Legacy / compatibility snapshot command.
    /// For DiGiCo this may be interpreted as create+rename depending on connector.
    case fireSnapshot(externalDeviceId: UUID, snapshot: ConsoleSnapshotSelector)

    /// Set a normalized channel parameter (mute/level/pan). Value semantics documented
    /// on `ConsoleParameterKind`. Not all consoles/parameters are supported — connectors
    /// that don't support a given (console, parameter) pair silently no-op, matching the
    /// existing pattern for unsupported ConsoleCommand cases.
    case setChannelParameter(externalDeviceId: UUID, channel: Int, parameter: ConsoleParameterKind, value: Double)

    /// Explicitly create a snapshot at the given index.
    case createSnapshot(externalDeviceId: UUID, index: Int)

    /// Explicitly rename an existing snapshot at the given index.
    case renameSnapshot(externalDeviceId: UUID, index: Int, name: String)

    /// Send raw MIDI bytes to a console connector.
    case sendMidi(externalDeviceId: UUID, bytes: [UInt8])
    
    // MARK: X32 / M32 cues & snippets

    /// X32/M32: /add "cue" <index> <name>
    case createCue(externalDeviceId: UUID, index: Int, name: String)

    /// X32/M32: /add "snippet" <index> <name>
    case createSnippet(externalDeviceId: UUID, index: Int, name: String)

    /// X32/M32: /-show/showfile/snippet/XYZ/name <name>
    case renameSnippet(externalDeviceId: UUID, slot: Int, name: String)

    /// DiGiCo: send a raw OSC float message to the console.
    case digicoOSC(externalDeviceId: UUID, address: String, floatValue: Float)

    /// DiGiCo: send a raw OSC int32 message to the console (used for macro recall).
    case digicoOSCInt32(externalDeviceId: UUID, address: String, intValue: Int32)

    /// Avid VENUE S6L: send a raw OSC message built from a device's configured address
    /// template. See ConsoleCapabilities and GraphAutomationRuntime.venueCommand.
    case venueOSC(externalDeviceId: UUID, address: String, value: OSCValue)
}

enum ConsoleSnapshotSelector: Equatable {
    case index(Int)
    case name(String)
}

// MARK: - OSC

enum OSCCommand: Equatable {
    case send(OSCSendPayload)
}

struct OSCSendPayload: Equatable {
    var host: String
    var port: UInt16
    var address: String
    var args: [OSCArg]

    init(host: String, port: UInt16, address: String, args: [OSCArg] = []) {
        self.host = host
        self.port = port
        self.address = address
        self.args = args
    }
}

enum OSCArg: Equatable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)
}

// MARK: - Trigger events

/// A trigger node emits a semantic event. GraphRuntime can route it to links/actions.
struct TriggerEvent: Equatable {
    /// e.g. "wireless.batteryBelow", "time.interval", "osc.received"
    var kind: String

    /// The node that emitted the event (graph-only trigger node UUID).
    var sourceNodeId: UUID

    /// Optional device/channel context (wireless, console, etc.).
    var deviceId: UUID?
    var channelIndex: Int?

    /// Additional structured fields for integrations.
    var fields: [String: TriggerEventValue]

    init(
        kind: String,
        sourceNodeId: UUID,
        deviceId: UUID? = nil,
        channelIndex: Int? = nil,
        fields: [String: TriggerEventValue] = [:]
    ) {
        self.kind = kind
        self.sourceNodeId = sourceNodeId
        self.deviceId = deviceId
        self.channelIndex = channelIndex
        self.fields = fields
    }
}

enum TriggerEventValue: Equatable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)
}
