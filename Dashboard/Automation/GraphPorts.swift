//
//  GraphPorts.swift
//  Relay Dashboard
//
//  Port definitions for tile-backed graph nodes.
//  Ports are derived from tile content (kind + modules) so they stay accurate.
//

import Foundation

struct GraphLinkFeatureFlags: Equatable {
    var conditionalsEnabled: Bool
    var variablesEnabled: Bool

    init(
        conditionalsEnabled: Bool = true,
        variablesEnabled: Bool = true
    ) {
        self.conditionalsEnabled = conditionalsEnabled
        self.variablesEnabled = variablesEnabled
    }
}

enum GraphLinkNodeRole: String, Codable, Equatable, CaseIterable {
    case trigger
    case buttonTrigger
    case action
    case actionWithResults
    case destinationAction
    case consoleDestination
    case vistaDestination
    case repeater
    case delay
    case condition
    case variable
    case merge
    case source
    case unknown
}

enum GraphLinkFailureReason: String, Codable, Equatable {
    case sameNode
    case receiverDoesNotAcceptLinks
    case sourceCannotLinkToReceiver
    case conditionalsDisabled
    case variablesDisabled
    case consoleCapabilityMismatch
}

struct GraphLinkValidation: Equatable {
    var isAllowed: Bool
    var failureReason: GraphLinkFailureReason?

    static let allowed = GraphLinkValidation(isAllowed: true, failureReason: nil)

    static func rejected(_ reason: GraphLinkFailureReason) -> GraphLinkValidation {
        GraphLinkValidation(isAllowed: false, failureReason: reason)
    }
}

enum GraphLinkPolicy {
    static func allowedSourceRoles(
        for receiverRole: GraphLinkNodeRole,
        features: GraphLinkFeatureFlags = GraphLinkFeatureFlags()
    ) -> Set<GraphLinkNodeRole> {
        guard canReceiveLinks(nodeRole: receiverRole, features: features) else { return [] }

        switch receiverRole {
        case .consoleDestination, .destinationAction:
            return [.trigger, .source, .repeater, .delay, .condition, .merge, .actionWithResults]

        case .vistaDestination:
            return [.source, .trigger, .repeater, .delay, .condition, .merge, .actionWithResults]

        case .action:
            return [.trigger, .buttonTrigger, .repeater, .delay, .condition, .merge, .actionWithResults]

        case .actionWithResults:
            return [.trigger, .buttonTrigger, .repeater, .delay, .condition, .merge, .actionWithResults]

        case .merge:
            return [.trigger, .buttonTrigger, .condition, .repeater, .delay, .actionWithResults]

        case .repeater:
            return [.trigger, .condition, .delay, .merge, .actionWithResults]

        case .delay:
            return [.trigger, .condition, .repeater, .merge, .actionWithResults]

        case .condition:
            return [.trigger, .condition, .repeater, .delay, .merge, .actionWithResults]

        case .variable:
            return features.variablesEnabled ? [.trigger, .repeater, .delay, .condition, .source, .variable, .merge, .actionWithResults] : []

        case .trigger, .buttonTrigger, .source, .unknown:
            return []
        }
    }

    static func allowedReceiverRoles(
        for sourceRole: GraphLinkNodeRole,
        features: GraphLinkFeatureFlags = GraphLinkFeatureFlags()
    ) -> Set<GraphLinkNodeRole> {
        Set(
            GraphLinkNodeRole.allCases.filter { receiverRole in
                validate(from: sourceRole, to: receiverRole, features: features).isAllowed
            }
        )
    }

    static func canReceiveLinks(
        nodeRole: GraphLinkNodeRole,
        features: GraphLinkFeatureFlags = GraphLinkFeatureFlags()
    ) -> Bool {
        switch nodeRole {
        case .action, .actionWithResults, .destinationAction, .consoleDestination, .vistaDestination, .repeater, .delay, .merge:
            return true
        case .condition:
            return features.conditionalsEnabled
        case .variable:
            return features.variablesEnabled
        case .trigger, .buttonTrigger, .source, .unknown:
            return false
        }
    }

    static func validate(
        from sourceRole: GraphLinkNodeRole,
        to receiverRole: GraphLinkNodeRole,
        isSameNode: Bool = false,
        features: GraphLinkFeatureFlags = GraphLinkFeatureFlags()
    ) -> GraphLinkValidation {
        if isSameNode {
            return .rejected(.sameNode)
        }

        guard canReceiveLinks(nodeRole: receiverRole, features: features) else {
            switch receiverRole {
            case .condition:
                return .rejected(.conditionalsDisabled)
            case .variable:
                return .rejected(.variablesDisabled)
            default:
                return .rejected(.receiverDoesNotAcceptLinks)
            }
        }

        if allowedSourceRoles(for: receiverRole, features: features).contains(sourceRole) {
            return .allowed
        }

        switch receiverRole {
        case .condition:
            return features.conditionalsEnabled ? .rejected(.sourceCannotLinkToReceiver) : .rejected(.conditionalsDisabled)
        case .variable:
            return features.variablesEnabled ? .rejected(.sourceCannotLinkToReceiver) : .rejected(.variablesDisabled)
        case .trigger, .buttonTrigger, .source, .unknown:
            return .rejected(.receiverDoesNotAcceptLinks)
        case .action, .actionWithResults, .destinationAction, .consoleDestination, .vistaDestination, .repeater, .delay, .merge:
            return .rejected(.sourceCannotLinkToReceiver)
        }
    }
}

/// Lightweight port value type for link compatibility.
/// Keep it small; we can grow this as we add richer node behaviors.
enum GraphValueType: String, Codable, CaseIterable {
    case trigger
    case text
    case number
    case boolean
    case transcript
    case entityPerson
    case entityPosition
    case entityWirelessChannel
    case entityConsoleChannel
}

enum GraphPortDirection: String, Codable {
    case input
    case output
}

struct GraphPort: Identifiable, Codable, Equatable {
    var id: String            // stable within a tile type/module type
    var label: String
    var direction: GraphPortDirection
    var valueType: GraphValueType

    init(id: String, label: String, direction: GraphPortDirection, valueType: GraphValueType) {
        self.id = id
        self.label = label
        self.direction = direction
        self.valueType = valueType
    }
}

/// Derives ports for a tile. This keeps the graph cohesive because tiles are the nodes.
///
/// NOTE: This intentionally starts small. We can expand based on real UI needs.
///
/// - Person tiles: expose a display name output.
/// - Shure/Sennheiser tiles: expose wireless label output.
/// - Console tiles (future): expose channel-name input ports / snapshot trigger inputs.
struct GraphPortProvider {

    static func ports(for tile: DashboardTileModel) -> [GraphPort] {
        var ports: [GraphPort] = []

        // 1) Legacy tile kinds
        switch tile.kind {
        case .person:
            ports.append(contentsOf: [
                GraphPort(id: "person.name", label: "Name", direction: .output, valueType: .text),
                GraphPort(id: "person.position", label: "Position", direction: .output, valueType: .entityPosition)
            ])
        default:
            break
        }

        // 2) Modular tile ports derived from modules
        if let modules = tile.modules {
            for m in modules {
                switch m.kind {
                case .shureWireless:
                    ports.append(contentsOf: [
                        GraphPort(id: "shure.label", label: "Shure Label", direction: .output, valueType: .text),
                        GraphPort(id: "shure.channel", label: "Shure Channel", direction: .output, valueType: .entityWirelessChannel)
                    ])
                case .shureOverview:
                    ports.append(contentsOf: [
                        GraphPort(id: "shureOverview.summary", label: "Shure Overview", direction: .output, valueType: .text)
                    ])
                case .sennheiserWireless:
                    ports.append(contentsOf: [
                        GraphPort(id: "sennheiser.label", label: "Sennheiser Label", direction: .output, valueType: .text),
                        GraphPort(id: "sennheiser.channel", label: "Sennheiser Channel", direction: .output, valueType: .entityWirelessChannel)
                    ])
                case .liveTranscription:
                    ports.append(contentsOf: [
                        GraphPort(id: "transcript.latest", label: "Latest Transcript", direction: .output, valueType: .transcript),
                        GraphPort(id: "transcript.window", label: "Transcript Window", direction: .output, valueType: .transcript)
                    ])
                case .dbReader:
                    ports.append(contentsOf: [
                        GraphPort(id: "db.spl", label: "SPL (dB)", direction: .output, valueType: .number),
                        GraphPort(id: "db.peak", label: "Peak (dB)", direction: .output, valueType: .number),
                        GraphPort(id: "db.rawDbFS", label: "Raw dBFS", direction: .output, valueType: .number),
                        GraphPort(id: "db.rawPeakDbFS", label: "Raw Peak dBFS", direction: .output, valueType: .number)
                    ])
                default:
                    break
                }
            }
        }

        // De-dupe by id (modules could repeat across a tile)
        var seen: Set<String> = []
        return ports.filter { seen.insert($0.id).inserted }
    }
}
