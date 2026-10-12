//
//  GraphActionExecutor.swift
//  Relay
//
//  Created by David Bullard on 1/19/26.
//

import Foundation
import CoreGraphics
import Combine

// MARK: - Action Node Notifications

enum ActionNodeNotifications {
    static let sendAllConsoles = Notification.Name("Relay.ActionNode.SendAllConsoles")
    static let oscSend         = Notification.Name("Relay.ActionNode.OSCSend")
    static let notify          = Notification.Name("Relay.ActionNode.Notify")
    static let lanNotify       = Notification.Name("Relay.ActionNode.LANNotify")
    static let midiSend        = Notification.Name("Relay.ActionNode.MIDISend")
    static let appControl      = Notification.Name("Relay.ActionNode.AppControl")
    static let appControlStarted = Notification.Name("Relay.ActionNode.AppControlStarted")
    static let appControlFailed = Notification.Name("Relay.ActionNode.AppControlFailed")
    static let appControlSucceeded = Notification.Name("Relay.ActionNode.AppControlSucceeded")
    static let proPresenterTriggerFailed = Notification.Name("Relay.ActionNode.ProPresenterTriggerFailed")
    static let proPresenterTriggerSucceeded = Notification.Name("Relay.ActionNode.ProPresenterTriggerSucceeded")
    static let smartLightStarted = SmartLightActionNotification.started
    static let smartLightSucceeded = SmartLightActionNotification.succeeded
    static let smartLightFailed = SmartLightActionNotification.failed
    static let consoleActionStarted = Notification.Name("Relay.ActionNode.ConsoleActionStarted")
    static let consoleActionSucceeded = Notification.Name("Relay.ActionNode.ConsoleActionSucceeded")
    static let consoleActionFailed = Notification.Name("Relay.ActionNode.ConsoleActionFailed")
    static let conditionEvaluationResolved = Notification.Name("Relay.ActionNode.ConditionEvaluationResolved")
    static let conditionEvaluationMismatch = Notification.Name("Relay.ActionNode.ConditionEvaluationMismatch")
}

enum ActionNodeUserInfoKeys {
    static let nodeId = "nodeId"
    static let includeAssignments = "includeAssignments"
    static let includeSnapshots   = "includeSnapshots"
    static let staggerMs          = "staggerMs"
    static let title              = "title"
    static let message            = "message"
    static let durationSeconds    = "durationSeconds"
    static let targetMode         = "targetMode"
    static let peerDeviceId       = "peerDeviceId"
    static let destinationUniqueID = "destinationUniqueID"
    static let midiBytes          = "midiBytes"
    static let appActionKind      = "appActionKind"
    static let refreshTargetScope = "refreshTargetScope"
    static let selectedDeviceIDs  = "selectedDeviceIDs"
    static let errorMessage       = "errorMessage"
    static let stateJSON          = "stateJSON"
}


enum GraphSendAllUserInfoKeys {
    static let delayMs = "delayMs"
    static let includeAssignments = "includeAssignments"
    static let includeSnapshots = "includeSnapshots"
    static let bypassPCOLinkFilter = "bypassPCOLinkFilter"
}

// MARK: - Console Snapshot Edits Cache (from Console node UI)

extension Notification.Name {
    /// Posted when a console node updates its per-sequence snapshot name edits.
    static let prodlinkConsoleSnapshotEditsDidChange = Notification.Name("Relay.ConsoleSnapshotEditsDidChange")
    /// Debug breadcrumb for Send-All execution (Graph view can surface this in-node).
    static let prodlinkGraphSendAllDebug = Notification.Name("Relay.GraphSendAllDebug")
}

enum ConsoleSnapshotEditsUserInfoKeys {
    static let deviceId = "deviceId"        // UUID
    static let edits = "edits"              // [Int: String]
}

// MARK: - Graph Action Executor

/// UI-independent action execution. This does NOT call SwiftUI code.
/// It posts notifications that can be handled by your Graph view OR by Canvas/runtime listeners.
enum GraphActionExecutor {
    private static var lastNotifyByNodeId: [UUID: TimeInterval] = [:]
    private static let notifyEchoSuppressWindow: TimeInterval = 0.6
    private static var lastMidiSendByNodeId: [UUID: TimeInterval] = [:]
    private static let midiSendSuppressWindow: TimeInterval = 0.3

    struct ExecutionContext {
        /// Ordered candidates for Send-All (typically your liveAudioConsoles externalDeviceIds).
        var consoleExternalDeviceIds: [UUID]

        /// Returns a position for a given console externalDeviceId. Used for ordering top-to-bottom then left-to-right.
        /// Provide the exact mapping you currently do via graphNodeId(forExternalDeviceId:) + nodePosition(for:).
        var consolePosition: ((UUID) -> CGPoint)? = nil

        /// Supplies the current list of PCO rundown snapshot titles (used to decide if snapshots exist to send).
        var pcoRundownSnapshotTitles: () -> [String] = { [] }

        /// Snapshot devices array used for assignment existence checks.
        /// Provide this when creating the context (fetch it on the MainActor if needed).
        var externalSnapshotDevices: [Any] = []

        /// Resolves the effective inbound source text for a destination node when patch links are present.
        var linkedSourceTextForDestinationNode: ((UUID, DashboardGraph) -> String?)? = nil

        /// Resolves all inbound source texts for a destination node when a grouped source is linked.
        var linkedSourceTextsForDestinationNode: ((UUID, DashboardGraph) -> [String])? = nil

        /// Resolves universal variable tokens in text action fields at execution time.
        var renderVariableText: (String) -> String = { $0 }
        var renderVariableJSON: (String) -> String = { $0 }

        /// Optional logger.
        var log: (String) -> Void = { _ in }

        public init(
            consoleExternalDeviceIds: [UUID],
            consolePosition: ((UUID) -> CGPoint)? = nil,
            pcoRundownSnapshotTitles: @escaping () -> [String] = { [] },
            externalSnapshotDevices: [Any] = [],
            linkedSourceTextForDestinationNode: ((UUID, DashboardGraph) -> String?)? = nil,
            linkedSourceTextsForDestinationNode: ((UUID, DashboardGraph) -> [String])? = nil,
            renderVariableText: @escaping (String) -> String = { $0 },
            renderVariableJSON: @escaping (String) -> String = { $0 },
            log: @escaping (String) -> Void = { _ in }
        ) {
            self.consoleExternalDeviceIds = consoleExternalDeviceIds
            self.consolePosition = consolePosition
            self.pcoRundownSnapshotTitles = pcoRundownSnapshotTitles
            self.externalSnapshotDevices = externalSnapshotDevices
            self.linkedSourceTextForDestinationNode = linkedSourceTextForDestinationNode
            self.linkedSourceTextsForDestinationNode = linkedSourceTextsForDestinationNode
            self.renderVariableText = renderVariableText
            self.renderVariableJSON = renderVariableJSON
            self.log = log
        }
    }

    /// Executes an action immediately using a runtime context (Canvas/Graph neutral).
    /// - Important: For `action.sendAllConsoles`, this will orchestrate ordering/availability and post `.prodlinkGraphSendAllToConsoles`.
    static func execute(actionKey: String, nodeId: UUID, graph: DashboardGraph, context: ExecutionContext?) {
        switch actionKey {
        case "action.sendAllConsoles":
            let cfg = graph.sendAllConsolesActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.SendAllConsolesActionConfig()

            // If no runtime context is provided, fall back to notification-based execution.
            guard let context else {
                NotificationCenter.default.post(
                    name: ActionNodeNotifications.sendAllConsoles,
                    object: nil,
                    userInfo: [
                        ActionNodeUserInfoKeys.nodeId: nodeId,
                        ActionNodeUserInfoKeys.includeAssignments: cfg.includeAssignments,
                        ActionNodeUserInfoKeys.includeSnapshots: cfg.includeSnapshots,
                        ActionNodeUserInfoKeys.staggerMs: cfg.staggerMs
                    ]
                )
                return
            }

            // Limit Send-All to consoles that are actually linked in the graph.
            // IMPORTANT: If the graph contains console nodes but none are linked, send to NONE.
            // Only fall back to “all consoles” when we cannot inspect graph console nodes.
            let allConsoleNodeIds = consoleExternalDeviceIdsInGraph(graph)
            let linkedConsoleIds  = linkedConsoleExternalDeviceIdsInGraph(graph)

            // If we can see console nodes in the graph, restrict to linked consoles.
            if !allConsoleNodeIds.isEmpty {
                let filtered = context.consoleExternalDeviceIds.filter { linkedConsoleIds.contains($0) }
                if filtered.isEmpty {
                    context.log("[GraphActionExecutor] SendAllConsoles: no linked console nodes (consoleNodes=\(allConsoleNodeIds.count)). Skipping send.")
                    return
                }

                var ctx = context
                ctx.consoleExternalDeviceIds = filtered
                fireSendAllToConsoles(
                    staggerMs: Double(cfg.staggerMs),
                    includeAssignments: cfg.includeAssignments,
                    includeSnapshots: cfg.includeSnapshots,
                    context: ctx
                )
                return
            }

            // If we can’t inspect console nodes, fall through to the existing fallback send below.

            fireSendAllToConsoles(
                staggerMs: Double(cfg.staggerMs),
                includeAssignments: cfg.includeAssignments,
                includeSnapshots: cfg.includeSnapshots,
                context: context
            )

        case "action.oscSend":
            let cfg = graph.oscSendActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.OSCSendActionConfig()

            let trimmedHost = cfg.targetIP.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAddress = cfg.address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedHost.isEmpty, cfg.targetPort != 0, !trimmedAddress.isEmpty else { return }

            let arguments = cfg.arguments.compactMap { $0.resolvedValue() }
            guard arguments.count == cfg.arguments.count else {
                print("[GraphActionExecutor] OSC Send skipped: invalid argument")
                return
            }

            NotificationCenter.default.post(
                name: ActionNodeNotifications.oscSend,
                object: nil,
                userInfo: [
                    ActionNodeUserInfoKeys.nodeId: nodeId,
                    "ip": trimmedHost,
                    "port": Int(cfg.targetPort),
                    "address": trimmedAddress,
                    "arguments": arguments.map(\.debugDescription)
                ]
            )

            OSCManager.shared.send(
                to: OSCEndpoint(host: trimmedHost, port: cfg.targetPort),
                message: OSCMessage(address: trimmedAddress, args: arguments)
            )

        case "action.notify":
            let cfg = graph.notifyActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.NotifyActionConfig()

            let now = Date().timeIntervalSince1970
            if let last = lastNotifyByNodeId[nodeId], (now - last) <= notifyEchoSuppressWindow {
                return
            }
            lastNotifyByNodeId[nodeId] = now

            NotificationCenter.default.post(
                name: ActionNodeNotifications.notify,
                object: nil,
                userInfo: [
                    ActionNodeUserInfoKeys.nodeId: nodeId,
                    ActionNodeUserInfoKeys.title: context?.renderVariableText(cfg.title) ?? cfg.title,
                    ActionNodeUserInfoKeys.message: context?.renderVariableText(cfg.message) ?? cfg.message,
                    ActionNodeUserInfoKeys.durationSeconds: cfg.durationSeconds
                ]
            )

        case "action.lanNotify":
            let cfg = graph.lanNotifyActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.LANNotifyActionConfig()

            NotificationCenter.default.post(
                name: ActionNodeNotifications.lanNotify,
                object: nil,
                userInfo: [
                    ActionNodeUserInfoKeys.nodeId: nodeId,
                    ActionNodeUserInfoKeys.title: context?.renderVariableText(cfg.title) ?? cfg.title,
                    ActionNodeUserInfoKeys.message: context?.renderVariableText(cfg.message) ?? cfg.message,
                    ActionNodeUserInfoKeys.durationSeconds: cfg.durationSeconds,
                    ActionNodeUserInfoKeys.targetMode: cfg.targetMode.rawValue,
                    ActionNodeUserInfoKeys.peerDeviceId: cfg.peerDeviceId
                ]
            )

        case "action.appControl":
            let cfg = graph.appControlActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.AppControlActionConfig()

            var userInfo: [String: Any] = [
                ActionNodeUserInfoKeys.nodeId: nodeId,
                ActionNodeUserInfoKeys.appActionKind: cfg.actionKind.rawValue
            ]
            if cfg.actionKind == .resyncDeviceNames {
                userInfo[ActionNodeUserInfoKeys.refreshTargetScope] = cfg.refreshDeviceOptions.targetScope.rawValue
                userInfo[ActionNodeUserInfoKeys.selectedDeviceIDs] = cfg.refreshDeviceOptions.selectedDeviceIDs.map(\.uuidString)
            }

            NotificationCenter.default.post(
                name: ActionNodeNotifications.appControl,
                object: nil,
                userInfo: userInfo
            )

        case "action.proPresenterTrigger":
            let cfg = graph.proPresenterTriggerActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.ProPresenterTriggerActionConfig()

            Task {
                do {
                    try await ProPresenterAutomationService.sendTrigger(
                        profileId: cfg.profileId,
                        triggerPath: cfg.triggerPath
                    )
                    NotificationCenter.default.post(
                        name: ActionNodeNotifications.proPresenterTriggerSucceeded,
                        object: nil,
                        userInfo: [ActionNodeUserInfoKeys.nodeId: nodeId]
                    )
                } catch {
                    #if DEBUG
                    print("[GraphActionExecutor] ProPresenter trigger failed nodeId=\(nodeId) error=\(error.localizedDescription)")
                    #endif
                    NotificationCenter.default.post(
                        name: ActionNodeNotifications.proPresenterTriggerFailed,
                        object: nil,
                        userInfo: [
                            ActionNodeUserInfoKeys.nodeId: nodeId,
                            ActionNodeUserInfoKeys.errorMessage: error.localizedDescription
                        ]
                    )
                }
            }

        case "action.smartLightControl":
            let cfg = graph.smartLightActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.SmartLightActionConfig()
            guard let profileID = cfg.profileID else {
                NotificationCenter.default.post(
                    name: ActionNodeNotifications.smartLightFailed,
                    object: nil,
                    userInfo: [
                        ActionNodeUserInfoKeys.nodeId: nodeId,
                        ActionNodeUserInfoKeys.errorMessage: "Select a Smart Light profile before running this node.",
                        SmartLightActionUserInfoKeys.message: "Select a Smart Light profile before running this node."
                    ]
                )
                return
            }
            let targetDeviceIDs = cfg.effectiveDeviceIDs
            guard !targetDeviceIDs.isEmpty else {
                NotificationCenter.default.post(
                    name: ActionNodeNotifications.smartLightFailed,
                    object: nil,
                    userInfo: [
                        ActionNodeUserInfoKeys.nodeId: nodeId,
                        ActionNodeUserInfoKeys.errorMessage: "Select a Smart Light device before running this node.",
                        SmartLightActionUserInfoKeys.message: "Select a Smart Light device before running this node."
                    ]
                )
                return
            }
            let resolvedAction = resolvedSmartLightAction(config: cfg, nodeId: nodeId, graph: graph, context: context)
            SmartLightActionService.execute(
                nodeId: nodeId,
                profileID: profileID,
                deviceIDs: targetDeviceIDs,
                action: resolvedAction
            )

        case "action.shureSend":
            let cfg = graph.shureSendActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.ShureSendActionConfig()
            guard let deviceId = cfg.deviceId else { return }
            guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceId }) else { return }
            guard device.shureSupportsDestinationCommands else { return }
            let shureChannelCount = device.effectiveShureChannelCount

            let command: String
            switch cfg.commandKind {
            case .setChannelName:
                let linkedNames = (context?.linkedSourceTextsForDestinationNode?(nodeId, graph) ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let linkedName = linkedNames.first
                let shouldFormatPeople = linkedName == nil && cfg.channelNameSource == "people"
                let namesToSend: [(channel: Int, name: String)] = {
                    if !linkedNames.isEmpty {
                        let explicit = linkedNames.compactMap { raw -> (channel: Int, name: String)? in
                            guard let channel = cfg.channelAssignments[raw], (1...shureChannelCount).contains(channel) else { return nil }
                            return (channel, raw)
                        }
                        if !explicit.isEmpty {
                            return explicit
                        }

                        let startChannels = ([cfg.channelIndex] + cfg.additionalChannelIndices)
                            .map { max(1, $0) }
                            .filter { $0 <= shureChannelCount }
                            .sorted()
                        let uniqueStartChannels = Array(NSOrderedSet(array: startChannels)) as? [Int] ?? [max(1, cfg.channelIndex)]
                        var remaining = linkedNames[...]
                        var out: [(channel: Int, name: String)] = []
                        for (index, startChannel) in uniqueStartChannels.enumerated() {
                            let endExclusive = index + 1 < uniqueStartChannels.count
                                ? min(uniqueStartChannels[index + 1], shureChannelCount + 1)
                                : shureChannelCount + 1
                            guard endExclusive > startChannel else { continue }
                            let capacity = endExclusive - startChannel
                            for offset in 0..<capacity {
                                guard let nextName = remaining.popFirst() else { return out }
                                out.append((startChannel + offset, nextName))
                            }
                        }
                        return out
                    }
                    let rawName = cfg.channelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rawName.isEmpty else { return [] }
                    let formatted = shouldFormatPeople
                        ? formattedPeopleName(from: rawName, format: cfg.nameFormat, casing: cfg.nameCasing)
                        : rawName
                    return [(max(1, cfg.channelIndex), formatted)]
                }()
                guard !namesToSend.isEmpty else { return }

                let commandsToSend: [String] = namesToSend.map { item in
                    let cappedName = item.name.count <= 8 ? item.name : String(item.name.prefix(8))
                    let safeName = cappedName.replacingOccurrences(of: "}", with: ")")
                    return "SET \(item.channel) CHAN_NAME {\(safeName)}"
                }
                command = commandsToSend[0]

                let model = device.shureNetworkModel?.rawValue ?? device.shureModelIdentifier ?? "unknown"
                for (index, item) in namesToSend.enumerated() {
                    let cappedName = item.name.count <= 8 ? item.name : String(item.name.prefix(8))
                    let logMessage = "[GraphActionExecutor] Shure set channel name nodeId=\(nodeId) device=\(device.name) model=\(model) host=\(device.host) port=\(device.port) channel=\(item.channel) name=\(cappedName) command=\(commandsToSend[index])"
                    context?.log(logMessage)
                    #if DEBUG
                    print(logMessage)
                    #endif
                }

                Task {
                    for command in commandsToSend {
                        do {
                            try await ShureWirelessDestinationService.sendCommand(device: device, command: command)
                        } catch {
                            #if DEBUG
                            print("[GraphActionExecutor] Shure send failed nodeId=\(nodeId) error=\(error.localizedDescription)")
                            #endif
                            break
                        }
                    }
                }
                return
            case .rawCommand:
                let raw = (context?.renderVariableText(cfg.rawCommand) ?? cfg.rawCommand).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return }
                command = raw
            }

            Task {
                do {
                    try await ShureWirelessDestinationService.sendCommand(device: device, command: command)
                } catch {
                    #if DEBUG
                    print("[GraphActionExecutor] Shure send failed nodeId=\(nodeId) error=\(error.localizedDescription)")
                    #endif
                }
            }

        case "action.sennheiserSend":
            let cfg = graph.sennheiserSendActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.SennheiserSendActionConfig()
            guard let deviceId = cfg.deviceId else { return }
            guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceId }) else { return }
            guard device.sennheiserSupportsDestinationCommands else { return }

            let model = device.sennheiserNetworkModel
            let channelCount = max(1, model?.channelCount ?? 1)
            let channel = min(max(1, cfg.channelIndex), channelCount)

            switch cfg.commandKind {
            case .advanced:
                Task {
                    do {
                        try await SennheiserWirelessDestinationService.sendRequest(
                            device: device,
                            scheme: cfg.scheme,
                            method: cfg.method,
                            path: context?.renderVariableText(cfg.path) ?? cfg.path,
                            jsonBody: context?.renderVariableJSON(cfg.jsonBody) ?? cfg.jsonBody
                        )
                    } catch {
                        #if DEBUG
                        print("[GraphActionExecutor] Sennheiser send failed nodeId=\(nodeId) error=\(error.localizedDescription)")
                        #endif
                    }
                }
            case .setChannelName:
                guard model?.supportsSscV1Control == true else {
                    #if DEBUG
                    print("[GraphActionExecutor] Sennheiser set name unsupported model=\(model?.rawValue ?? "unknown") nodeId=\(nodeId)")
                    #endif
                    return
                }
                let linkedNames = (context?.linkedSourceTextsForDestinationNode?(nodeId, graph) ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let linkedName = linkedNames.first
                let shouldFormatPeople = linkedName == nil && cfg.channelNameSource == "people"
                let namesToSend: [(channel: Int, name: String)] = {
                    if !linkedNames.isEmpty {
                        let explicit = linkedNames.compactMap { raw -> (channel: Int, name: String)? in
                            guard let assignedChannel = cfg.channelAssignments[raw], (1...channelCount).contains(assignedChannel) else { return nil }
                            return (assignedChannel, raw)
                        }
                        if !explicit.isEmpty {
                            return explicit
                        }

                        let startChannels = ([channel] + cfg.additionalChannelIndices)
                            .map { min(max(1, $0), channelCount) }
                            .sorted()
                        let uniqueStartChannels = Array(NSOrderedSet(array: startChannels)) as? [Int] ?? [channel]
                        var remaining = linkedNames[...]
                        var out: [(channel: Int, name: String)] = []
                        for (index, startChannel) in uniqueStartChannels.enumerated() {
                            let endExclusive = index + 1 < uniqueStartChannels.count
                                ? min(uniqueStartChannels[index + 1], channelCount + 1)
                                : channelCount + 1
                            guard endExclusive > startChannel else { continue }
                            let capacity = endExclusive - startChannel
                            for offset in 0..<capacity {
                                guard let nextName = remaining.popFirst() else { return out }
                                out.append((startChannel + offset, nextName))
                            }
                        }
                        return out
                    }
                    let rawName = cfg.channelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rawName.isEmpty else { return [] }
                    let formatted = shouldFormatPeople
                        ? formattedPeopleName(from: rawName, format: cfg.nameFormat, casing: cfg.nameCasing)
                        : rawName
                    return [(channel, formatted)]
                }()
                guard !namesToSend.isEmpty else { return }
                let message: [String: Any] = Dictionary(uniqueKeysWithValues: namesToSend.map { item in
                    ("rx\(item.channel)", ["name": String(item.name.prefix(8))] as [String: Any])
                })

                Task {
                    do {
                        try await SennheiserWirelessDestinationService.sendSscMessage(device: device, message: message)
                    } catch {
                        #if DEBUG
                        print("[GraphActionExecutor] Sennheiser set name failed nodeId=\(nodeId) error=\(error.localizedDescription)")
                        #endif
                    }
                }
            case .setMute:
                guard model?.supportsSscV1Control == true else {
                    #if DEBUG
                    print("[GraphActionExecutor] Sennheiser mute unsupported model=\(model?.rawValue ?? "unknown") nodeId=\(nodeId)")
                    #endif
                    return
                }
                let message: [String: Any] = ["rx\(channel)": ["mute": cfg.muteEnabled]]

                Task {
                    do {
                        try await SennheiserWirelessDestinationService.sendSscMessage(device: device, message: message)
                    } catch {
                        #if DEBUG
                        print("[GraphActionExecutor] Sennheiser mute failed nodeId=\(nodeId) error=\(error.localizedDescription)")
                        #endif
                    }
                }
            case .setGain:
                guard model?.supportsSscV1Control == true else {
                    #if DEBUG
                    print("[GraphActionExecutor] Sennheiser gain unsupported model=\(model?.rawValue ?? "unknown") nodeId=\(nodeId)")
                    #endif
                    return
                }
                let clamped = min(42, max(-3, cfg.gainDb))
                let stepped = (clamped / 3).rounded() * 3
                let message: [String: Any] = ["rx\(channel)": ["gain": stepped]]

                Task {
                    do {
                        try await SennheiserWirelessDestinationService.sendSscMessage(device: device, message: message)
                    } catch {
                        #if DEBUG
                        print("[GraphActionExecutor] Sennheiser gain failed nodeId=\(nodeId) error=\(error.localizedDescription)")
                        #endif
                    }
                }
            case .setRfMute:
                #if DEBUG
                print("[GraphActionExecutor] Sennheiser RF mute not supported for model=\(model?.rawValue ?? "unknown") nodeId=\(nodeId)")
                #endif
            }

        case "action.setVariable":
            guard isGraphVariablesFeatureEnabled else { return }
            var cfg = graph.setVariableActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.SetVariableActionConfig()
            cfg.textValue = context?.renderVariableText(cfg.textValue) ?? cfg.textValue
            guard let targetId = cfg.targetVariableNodeId else { return }
            guard let target = graph.variableNodeConfigByNodeId[targetId.uuidString],
                  target.sharedValueToken == nil else { return }

            NotificationCenter.default.post(
                name: Notification.Name("Relay.SetVariableActionFired"),
                object: nil,
                userInfo: [
                    "nodeId": nodeId,
                    "targetVariableNodeId": targetId,
                    "config": cfg
                ]
            )

        case "action.httpRequest":
            let cfg = graph.httpRequestActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.HTTPRequestActionConfig()
            let trimmedURL = (context?.renderVariableText(cfg.urlString) ?? cfg.urlString).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else { return }

            var request = URLRequest(url: url, timeoutInterval: max(1, cfg.timeoutSeconds))
            request.httpMethod = cfg.method.rawValue

            let headersRaw = (context?.renderVariableJSON(cfg.headersJSON) ?? cfg.headersJSON).trimmingCharacters(in: .whitespacesAndNewlines)
            if !headersRaw.isEmpty,
               let data = headersRaw.data(using: .utf8),
               let headers = try? JSONDecoder().decode([String: String].self, from: data) {
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            }

            let body = (context?.renderVariableJSON(cfg.body) ?? cfg.body).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                request.httpBody = body.data(using: .utf8)
            }

            Task {
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    context?.log("[GraphActionExecutor] HTTP \(cfg.method.rawValue) \(trimmedURL) → \(status)")
                } catch {
                    context?.log("[GraphActionExecutor] HTTP request failed: \(error.localizedDescription)")
                }
            }

        case "action.midiSend":
            let cfg = graph.midiSendActionConfigByNodeId[nodeId.uuidString]
                ?? DashboardGraph.MIDISendActionConfig()

            let bytes = buildMIDIBytes(from: cfg)
            if !bytes.isEmpty {
                let now = Date().timeIntervalSince1970
                if let last = lastMidiSendByNodeId[nodeId], (now - last) <= midiSendSuppressWindow {
                    return
                }
                lastMidiSendByNodeId[nodeId] = now

                NotificationCenter.default.post(
                    name: ActionNodeNotifications.midiSend,
                    object: nil,
                    userInfo: [
                        ActionNodeUserInfoKeys.nodeId: nodeId,
                        ActionNodeUserInfoKeys.destinationUniqueID: cfg.destinationUniqueID as Any,
                        ActionNodeUserInfoKeys.midiBytes: bytes
                    ]
                )

                let hex = hexString(bytes)
                let destinationLabel = cfg.destinationUniqueID.map(String.init) ?? "default"
                let detail = midiDetailString(from: cfg)
                print("[MIDI] Send action nodeId=\(nodeId) dest=\(destinationLabel) \(detail) bytes=\(hex)")
                MIDISendManager.shared.send(bytes: bytes, to: cfg.destinationUniqueID)
            }

        default:
            break
        }
    }

    /// Back-compat: notification-based execution.
    static func postExecute(actionKey: String, nodeId: UUID, graph: DashboardGraph) {
        execute(actionKey: actionKey, nodeId: nodeId, graph: graph, context: nil)
    }

    // MARK: - Console execution helpers (UI-independent)

    /// Sends snapshots/cues/snippets to a single console.
    /// This is safe to call from Graph OR Canvas.
    static func sendConsoleSnapshots(
        externalDeviceId: UUID,
        deviceAny: Any,
        rundownSnapshotTitles: [String],
        snapshotNameEdits: [Int: String] = [:]
    ) {
        // Merge caller edits with any per-device stored edits (so Send-All matches destination node list).
        var mergedEdits = extractSnapshotNameEdits(deviceAny)
        for (k, v) in snapshotNameEdits { mergedEdits[k] = v }

        let items = buildSnapshotWorkItems(
            deviceAny: deviceAny,
            rundownSnapshotTitles: rundownSnapshotTitles,
            snapshotNameEdits: mergedEdits
        )
        guard !items.isEmpty else {
            #if DEBUG
            print("[GraphActionExecutor] Snapshots: nothing to send deviceId=\(externalDeviceId)")
            #endif
            postSendAllDebug("Snapshots: nothing to send • id=\(externalDeviceId.uuidString.prefix(6))")
            return
        }

        let modelId = extractString(deviceAny, key: "consoleModelIdentifier") ?? ""

        // Qu consoles do not support snapshot rename via MIDI; skip snapshot sends.
        if modelId.hasPrefix("AH_Qu") {
            #if DEBUG
            print("[GraphActionExecutor] Snapshots: skipping for Qu console id=\(externalDeviceId) model=\(modelId)")
            #endif
            postSendAllDebug("Snapshots: skipped (Qu console)")
            return
        }

        let commands: [GraphCommand] = items.flatMap { item -> [GraphCommand] in
            let targetIndex = item.index

            // DiGiCo: explicit create + rename
            if modelId.hasPrefix("DiGiCo") {
                return [
                    .console(.createSnapshot(externalDeviceId: externalDeviceId, index: targetIndex)),
                    .console(.renameSnapshot(externalDeviceId: externalDeviceId, index: targetIndex, name: item.name))
                ]
            }

            // X32/M32: /add includes the name
            if modelId == "Behringer_X32" || modelId == "Midas_M32" {
                switch x32ShowSendMode(for: externalDeviceId) {
                case .cues:
                    return [
                        .console(.createCue(externalDeviceId: externalDeviceId, index: targetIndex, name: item.name))
                    ]
                case .snippets:
                    return [
                        .console(.createSnippet(externalDeviceId: externalDeviceId, index: targetIndex, name: item.name))
                    ]
                }
            }

            // Default: best-effort rename
            return [
                .console(.renameSnapshot(externalDeviceId: externalDeviceId, index: targetIndex, name: item.name))
            ]
        }

        postSendAllDebug("Snapshots: commands=\(commands.count) model=\(modelId)")
        postSendAllDebug("Snapshots: executing cmds for id=\(externalDeviceId.uuidString.prefix(6))")

        Task { @MainActor in
            await ConsoleConnectorRegistry.shared.execute(commands)
            postSendAllDebug("Snapshots: execute returned • id=\(externalDeviceId.uuidString.prefix(6))")
        }
    }

    private static func buildMIDIBytes(from cfg: DashboardGraph.MIDISendActionConfig) -> [UInt8] {
        let channel = UInt8(max(0, min(15, cfg.channel - 1)))
        let note = UInt8(max(0, min(127, cfg.note)))
        let velocity = UInt8(max(0, min(127, cfg.velocity)))
        let program = UInt8(max(0, min(127, cfg.program)))
        let control = UInt8(max(0, min(127, cfg.control)))
        let value = UInt8(max(0, min(127, cfg.value)))

        switch cfg.messageKind {
        case .noteOn:
            return [0x90 | channel, note, velocity]
        case .noteOff:
            return [0x80 | channel, note, velocity]
        case .programChange:
            return [0xC0 | channel, program]
        case .controlChange:
            return [0xB0 | channel, control, value]
        case .sysex:
            return normalizeSysexBytes(parseHexBytes(cfg.sysexHex))
        }
    }

    private static func parseHexBytes(_ raw: String) -> [UInt8] {
        let cleaned = raw
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: " ")
        let parts = cleaned.split { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(parts.count)
        for part in parts {
            if let value = UInt8(part, radix: 16) {
                bytes.append(value)
            }
        }
        return bytes
    }

    private static func normalizeSysexBytes(_ bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return [] }
        var result = bytes
        if result.first != 0xF0 { result.insert(0xF0, at: 0) }
        if result.last != 0xF7 { result.append(0xF7) }
        return result
    }

    private static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func midiDetailString(from cfg: DashboardGraph.MIDISendActionConfig) -> String {
        switch cfg.messageKind {
        case .noteOn:
            return "kind=noteOn ch=\(cfg.channel) note=\(cfg.note) vel=\(cfg.velocity)"
        case .noteOff:
            return "kind=noteOff ch=\(cfg.channel) note=\(cfg.note) vel=\(cfg.velocity)"
        case .programChange:
            return "kind=programChange ch=\(cfg.channel) program=\(cfg.program)"
        case .controlChange:
            return "kind=controlChange ch=\(cfg.channel) cc=\(cfg.control) value=\(cfg.value)"
        case .sysex:
            let raw = cfg.sysexHex.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "kind=sysex" : "kind=sysex raw=\"\(raw)\""
        }
    }

    private static func resolvedSmartLightAction(
        config: DashboardGraph.SmartLightActionConfig,
        nodeId: UUID,
        graph: DashboardGraph,
        context: ExecutionContext?
    ) -> SmartLightAction {
        let linkedValues = context?.linkedSourceTextsForDestinationNode?(nodeId, graph) ?? []
        let trimmedValues = linkedValues
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var action = config.action

        if config.brightnessInputOverridesConfig,
           let brightnessText = trimmedValues.first,
           let brightness = Double(brightnessText),
           action.kind == .setBrightness {
            action.brightnessPercent = brightness
        }

        if config.colorInputOverridesConfig,
           let colorText = trimmedValues.first,
           let color = SmartLightColor.parse(colorText),
           action.kind == .setColor {
            action.color = color
        }

        if config.powerInputOverridesConfig,
           let powerText = trimmedValues.first?.lowercased(),
           action.kind == .toggle || action.kind == .turnOn || action.kind == .turnOff {
            if ["true", "on", "1"].contains(powerText) {
                action.kind = .turnOn
                action.powerState = true
            } else if ["false", "off", "0"].contains(powerText) {
                action.kind = .turnOff
                action.powerState = false
            }
        }

        return action
    }

    /// Sends channel-name assignments to a single console.
    /// Uses `deviceAny.consoleChannelAssignments` and formats names based on the device settings.
    static func sendConsoleChannelAssignments(
        externalDeviceId: UUID,
        deviceAny: Any,
        peopleLabelsInOrder: [String]
    ) {
        let items = buildAssignmentWorkItems(deviceAny: deviceAny, peopleLabelsInOrder: peopleLabelsInOrder)
        guard !items.isEmpty else {
            #if DEBUG
            print("[GraphActionExecutor] Assignments: nothing to send deviceId=\(externalDeviceId)")
            #endif
            return
        }

        let commands: [GraphCommand] = items.map { item in
            .console(.setChannelName(externalDeviceId: externalDeviceId, channel: item.channel, name: item.name))
        }

        Task { @MainActor in
            await ConsoleConnectorRegistry.shared.execute(commands)
        }
    }

    // MARK: - Global Send-All listener (always-on)

    private static var sendAllObserver: AnyCancellable?
    private static var lastSendAllSignature: String = ""
    private static var lastSendAllSignatureTime: TimeInterval = 0
    private static var lastDebugBannerTime: TimeInterval = 0
    private static var snapshotEditsObserver: AnyCancellable?
    private static var snapshotEditsCache: [UUID: [Int: String]] = [:]

    private static func postSendAllDebug(_ message: String) {
        NotificationCenter.default.post(
            name: .prodlinkGraphSendAllDebug,
            object: nil,
            userInfo: ["message": message]
        )
    }

    static func resetSendAllListener() {
        sendAllObserver = nil
        lastSendAllSignature = ""
        lastSendAllSignatureTime = 0
    }

    /// Call once from an owning/root view (e.g. DashboardRootView) so Canvas mode also responds.
    /// - Parameters:
    ///   - snapshotDevicesProvider: must return the current `ExternalDevicesStore.shared.currentSnapshot().devices` (captured on MainActor by the caller).
    ///   - rundownTitlesProvider: must return the active tab’s current rundown snapshot titles.
    ///   - peopleLabelsProvider: must return the active tab’s current people labels in display order ("Position — Name" strings).
    static func installSendAllToConsolesListener(
        snapshotDevicesProvider: @escaping () -> [Any],
        rundownTitlesProvider: @escaping () -> [String],
        peopleLabelsProvider: @escaping () -> [String],
        linkedConsoleIdsProvider: (() -> Set<UUID>)? = nil,
        pcoRundownLinkedConsoleIdsProvider: (() -> Set<UUID>)? = nil,
        rundownTitlesForConsoleProvider: ((UUID) -> [String])? = nil,
        log: @escaping (String) -> Void
    ) {

        // Prevent double-install (which causes duplicate sends).
        if sendAllObserver != nil {
            postSendAllDebug("SendAll listener already installed")
            return
        }

        postSendAllDebug("SendAll listener installing")

        // Install snapshot-edits cache observer once. This allows Send-All to use the same edited list
        // shown in Console destination nodes, even when running from Canvas mode.
        if snapshotEditsObserver == nil {
            snapshotEditsObserver = NotificationCenter.default.publisher(for: .prodlinkConsoleSnapshotEditsDidChange)
                .sink { note in
                    guard let id = note.userInfo?[ConsoleSnapshotEditsUserInfoKeys.deviceId] as? UUID else { return }
                    guard let edits = note.userInfo?[ConsoleSnapshotEditsUserInfoKeys.edits] as? [Int: String] else { return }
                    snapshotEditsCache[id] = edits
                }
        }

        sendAllObserver = NotificationCenter.default.publisher(for: .prodlinkGraphSendAllToConsoles)
            .sink { note in
                let rawIds = (note.object as? [UUID]) ?? []
                if rawIds.isEmpty {
                    postSendAllDebug("Listener received • ids=0 (empty payload)")
                    return
                }

                postSendAllDebug("Listener received • ids=\(rawIds.count)")

                // Deduplicate console IDs while preserving order.
                var seen = Set<UUID>()
                let dedupedIds: [UUID] = rawIds.filter { id in
                    if seen.contains(id) { return false }
                    seen.insert(id)
                    return true
                }

                // Optionally restrict to consoles that are linked in the current graph.
                let linkedSet = linkedConsoleIdsProvider?() ?? []
                let orderedIds: [UUID] = linkedSet.isEmpty
                    ? dedupedIds
                    : dedupedIds.filter { linkedSet.contains($0) }

                // If the graph has linked consoles but none match the event, do nothing.
                if !linkedSet.isEmpty, orderedIds.isEmpty {
                    log("[GraphActionExecutor] SendAll listener: no linked consoles matched notification")
                    postSendAllDebug("Filtered by graph links • orderedIds=0")
                    return
                }

                let delayMs = (note.userInfo?[GraphSendAllUserInfoKeys.delayMs] as? Double) ?? 0
                let includeAssignments = (note.userInfo?[GraphSendAllUserInfoKeys.includeAssignments] as? Bool) ?? true
                let includeSnapshots = (note.userInfo?[GraphSendAllUserInfoKeys.includeSnapshots] as? Bool) ?? true
                // De-dupe on ids + delay + snapshots flag only. This prevents double snapshot sends when a second
                // post flips includeAssignments without changing snapshot intent.
                let stableIds = orderedIds.map { $0.uuidString }.sorted().joined(separator: ",")
                let sig = "\(stableIds)|d=\(delayMs)|s=\(includeSnapshots)"
                let now = Date().timeIntervalSince1970
                if sig == lastSendAllSignature, (now - lastSendAllSignatureTime) < 1.0 {
                    log("[GraphActionExecutor] SendAll listener: duplicate ignored")
                    return
                }
                lastSendAllSignature = sig
                lastSendAllSignatureTime = now
                // Pull providers once per notification so we don't re-evaluate and accidentally double-send.
                let devices = snapshotDevicesProvider()
                let titles = rundownTitlesProvider()
                let peopleLabels = peopleLabelsProvider()

                let firstTitle = titles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let titleSummary = firstTitle.isEmpty ? "none" : firstTitle
                postSendAllDebug("Inputs • devices=\(devices.count) titles=\(titles.count) people=\(peopleLabels.count) firstTitle=\(titleSummary)")

                // Filter targets to console devices only (prevents NO CONNECTOR spam for Shure/etc.)
                let consoleIdSet: Set<UUID> = Set(devices.compactMap { dev in
                    guard isConsoleLikeDevice(dev) else { return nil }
                    return extractUUID(dev, key: "id")
                })

                let filteredIds = orderedIds.filter { consoleIdSet.contains($0) }
                if filteredIds.count != orderedIds.count {
                    log("[GraphActionExecutor] SendAll listener: filtered \(orderedIds.count - filteredIds.count) non-console ids")
                }
                if filteredIds.isEmpty {
                    postSendAllDebug("Filtered non-console ids • remaining=0")
                    return
                }

                postSendAllDebug("Targets resolved • consoles=\(filteredIds.count) assign=\(includeAssignments) snap=\(includeSnapshots)")

                log("[GraphActionExecutor] SendAll listener received consoles=\(filteredIds.count) delayMs=\(delayMs) includeAssignments=\(includeAssignments) includeSnapshots=\(includeSnapshots)")

                for (idx, consoleId) in filteredIds.enumerated() {
                    let totalDelayMs = max(0, delayMs) * Double(idx)

                    // One Task per consoleId, performing both assignment + snapshot sends (no nested tasks).
                    Task {
                        if totalDelayMs > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(totalDelayMs * 1_000_000))
                        }

                        guard let devAny = devices.first(where: { extractUUID($0, key: "id") == consoleId }) else {
                            log("[GraphActionExecutor] SendAll: missing device in snapshot id=\(consoleId)")
                            postSendAllDebug("Missing device snapshot • id=\(consoleId.uuidString.prefix(6))")
                            return
                        }

                        if includeAssignments {
                            let assignmentItems = buildAssignmentWorkItems(deviceAny: devAny, peopleLabelsInOrder: peopleLabels)
                            if assignmentItems.isEmpty {
                                postSendAllDebug("Assignments: skipped • no console items")
                            } else {
                                postSendAllDebug("Send assignments → id=\(consoleId.uuidString.prefix(6))")
                                sendConsoleChannelAssignments(
                                    externalDeviceId: consoleId,
                                    deviceAny: devAny,
                                    peopleLabelsInOrder: peopleLabels
                                )
                            }
                        }

                        if includeSnapshots {
                            let consoleTitles = rundownTitlesForConsoleProvider?(consoleId) ?? titles
                            if consoleTitles.isEmpty {
                                postSendAllDebug("Snapshots: skipped • no console titles")
                            } else {
                                // Merge per-device stored edits + cached UI edits (cached wins).
                                var edits = extractSnapshotNameEdits(devAny)
                                if let cached = snapshotEditsCache[consoleId], !cached.isEmpty {
                                    edits.merge(cached) { _, new in new }
                                }

                                let snapshotItems = buildSnapshotWorkItems(
                                    deviceAny: devAny,
                                    rundownSnapshotTitles: consoleTitles,
                                    snapshotNameEdits: edits
                                )
                                if snapshotItems.isEmpty {
                                    postSendAllDebug("Snapshots: skipped • no console items")
                                } else {
                                    postSendAllDebug("Send snapshots → id=\(consoleId.uuidString.prefix(6))")
                                    sendConsoleSnapshots(
                                        externalDeviceId: consoleId,
                                        deviceAny: devAny,
                                        rundownSnapshotTitles: consoleTitles,
                                        snapshotNameEdits: edits
                                    )
                                }
                            }
                        }
                    }
                }
            }

        postSendAllDebug("SendAll listener installed")
    }

    // MARK: - Graph link filtering

    /// Public wrapper for callers (e.g. DashboardRootView) that want linked console ExternalDeviceIds.
    /// Internally this uses a best-effort reflector so it remains resilient if graph storage changes.
    static func linkedConsoleExternalDeviceIds(in graph: DashboardGraph) -> Set<UUID> {
        linkedConsoleExternalDeviceIdsInGraph(graph)
    }
    /// Returns ALL externalDeviceIds for console nodes in the graph (linked or not).
    /// Used to decide whether we can safely restrict Send-All to linked consoles.
    private static func consoleExternalDeviceIdsInGraph(_ graph: Any) -> Set<UUID> {
        let nodes = extractCollection(from: graph, keys: ["nodes", "graphNodes"])
        guard !nodes.isEmpty else { return [] }

        var result = Set<UUID>()
        for node in nodes {
            if let ext = extractUUIDAny(node, keys: [
                "externalDeviceId", "externalDeviceID",
                "deviceId", "deviceID",
                "consoleExternalDeviceId", "consoleExternalDeviceID"
            ]) {
                if isConsoleLikeNode(node) {
                    result.insert(ext)
                } else {
                    // Best-effort: include anyway; presence of extId is enough for our “console nodes exist” check.
                    result.insert(ext)
                }
            }
        }
        return result
    }
    /// Returns the externalDeviceIds for console nodes that participate in at least one graph link.
    /// This is a best-effort reflector so we don't depend on GraphDashboardView types.
    private static func linkedConsoleExternalDeviceIdsInGraph(_ graph: Any) -> Set<UUID> {
        let nodes = extractCollection(from: graph, keys: ["nodes", "graphNodes"]) 
        let links = extractCollection(from: graph, keys: ["links", "graphLinks"]) 

        guard !nodes.isEmpty, !links.isEmpty else { return [] }
        let portMap = buildPortIdToNodeIdMap(nodes: nodes)
        // Collect nodeIds that appear in any link endpoint.
        var linkedNodeIds = Set<UUID>()
        for link in links {
            if let a = extractLinkEndpointNodeId(link, keyCandidates: ["fromNodeId", "sourceNodeId", "sourceId"]) { linkedNodeIds.insert(a) }
            if let b = extractLinkEndpointNodeId(link, keyCandidates: ["toNodeId", "destNodeId", "destinationNodeId", "targetNodeId", "targetId"]) { linkedNodeIds.insert(b) }

            if let ap = extractUUIDFromString(extractStringAny(link, keys: ["fromPortId", "sourcePortId", "sourcePort"])),
               let nid = portMap[ap] {
                linkedNodeIds.insert(nid)
            }
            if let bp = extractUUIDFromString(extractStringAny(link, keys: ["toPortId", "destPortId", "destinationPortId", "targetPortId", "targetPort"])),
               let nid = portMap[bp] {
                linkedNodeIds.insert(nid)
            }
        }

        guard !linkedNodeIds.isEmpty else { return [] }

        // Map linked console nodeIds -> externalDeviceId.
        var result = Set<UUID>()
        for node in nodes {
            guard let nodeId = extractUUIDAny(node, keys: ["id", "nodeId"]) else { continue }
            guard linkedNodeIds.contains(nodeId) else { continue }

            // Console nodes should have an externalDeviceId/deviceId.
            if let ext = extractUUIDAny(node, keys: ["externalDeviceId", "externalDeviceID",
                                                     "deviceId", "deviceID",
                                                     "consoleExternalDeviceId", "consoleExternalDeviceID"]) {
                // Best-effort: ensure this looks like a console node by inspecting kind/type if available.
                if isConsoleLikeNode(node) {
                    result.insert(ext)
                } else {
                    // If we can't determine kind, still include it; it only applies to linked nodes.
                    result.insert(ext)
                }
            }
        }

        return result
    }

    private static func isConsoleLikeNode(_ node: Any) -> Bool {
        // Try a few common fields for node kind/type.
        let kind = (extractStringAny(node, keys: ["kind", "nodeKind", "type", "nodeType"]) ?? "").lowercased()
        if kind.contains("console") { return true }
        if kind.contains("destination") { return true }
        // If absent, don't block.
        return kind.isEmpty
    }
    /// Best-effort: build a map of portId -> nodeId by scanning node objects for `ports` / `inputPorts` / `outputPorts` collections.
    private static func buildPortIdToNodeIdMap(nodes: [Any]) -> [UUID: UUID] {
        var map: [UUID: UUID] = [:]

        func addPorts(from container: Any, nodeId: UUID) {
            let pm = Mirror(reflecting: container)
            guard pm.displayStyle == .collection || pm.displayStyle == .set else { return }
            for pc in pm.children {
                let port = pc.value
                let mm = Mirror(reflecting: port)

                if let pid = mm.children.first(where: { $0.label == "id" || $0.label == "portId" || $0.label == "portID" })?.value as? UUID {
                    map[pid] = nodeId
                } else if let s = mm.children.first(where: { $0.label == "id" || $0.label == "portId" || $0.label == "portID" })?.value as? String,
                          let pid = UUID(uuidString: s) {
                    map[pid] = nodeId
                } else if let v = mm.children.first(where: { $0.label == "id" || $0.label == "portId" || $0.label == "portID" })?.value {
                    let om = Mirror(reflecting: v)
                    if om.displayStyle == .optional, let child = om.children.first {
                        if let pid = child.value as? UUID { map[pid] = nodeId }
                        if let s = child.value as? String, let pid = UUID(uuidString: s) { map[pid] = nodeId }
                    }
                }
            }
        }

        for node in nodes {
            guard let nodeId = extractUUIDAny(node, keys: ["id", "nodeId"]) else { continue }
            let m = Mirror(reflecting: node)

            if let ports = m.children.first(where: { $0.label == "ports" })?.value { addPorts(from: ports, nodeId: nodeId) }
            if let ports = m.children.first(where: { $0.label == "inputPorts" })?.value { addPorts(from: ports, nodeId: nodeId) }
            if let ports = m.children.first(where: { $0.label == "outputPorts" })?.value { addPorts(from: ports, nodeId: nodeId) }
        }

        return map
    }

    private static func resolveNodeId(fromPossibleNodeId direct: UUID?, fromPossiblePortId port: UUID?, portMap: [UUID: UUID]) -> UUID? {
        if let direct { return direct }
        if let port, let nid = portMap[port] { return nid }
        return nil
    }

    private static func extractCollection(from any: Any, keys: [String]) -> [Any] {
        // Direct cast if already [Any]
        for k in keys {
            if let arr = Mirror(reflecting: any).children.first(where: { $0.label == k })?.value as? [Any] {
                return arr
            }
        }

        for k in keys {
            guard let v = Mirror(reflecting: any).children.first(where: { $0.label == k })?.value else { continue }
            let m = Mirror(reflecting: v)

            // Arrays/Sets/etc
            if m.displayStyle == .collection || m.displayStyle == .set {
                return m.children.map { $0.value }
            }

            // Dictionaries: return VALUES
            if m.displayStyle == .dictionary {
                return m.children.compactMap { child in
                    let pair = Mirror(reflecting: child.value)
                    if let val = pair.children.first(where: { $0.label == "value" })?.value {
                        return val
                    }
                    let elems = Array(pair.children.map { $0.value })
                    if elems.count >= 2 { return elems[1] }
                    return nil
                }
            }
        }

        return []
    }

    private static func extractUUIDAny(_ any: Any, keys: [String]) -> UUID? {
        for k in keys {
            if let u = Mirror(reflecting: any).children.first(where: { $0.label == k })?.value as? UUID { return u }
            if let s = Mirror(reflecting: any).children.first(where: { $0.label == k })?.value as? String, let u = UUID(uuidString: s) { return u }
        }
        return nil
    }

    private static func extractStringAny(_ any: Any, keys: [String]) -> String? {
        for k in keys {
            if let s = Mirror(reflecting: any).children.first(where: { $0.label == k })?.value as? String { return s }
        }
        return nil
    }

    private static func extractLinkEndpointNodeId(_ link: Any, keyCandidates: [String]) -> UUID? {
        for k in keyCandidates {
            if let u = Mirror(reflecting: link).children.first(where: { $0.label == k })?.value as? UUID { return u }
            if let s = Mirror(reflecting: link).children.first(where: { $0.label == k })?.value as? String, let u = UUID(uuidString: s) { return u }
        }
        return nil
    }

    private static func extractUUIDFromString(_ s: String?) -> UUID? {
        guard let s, !s.isEmpty else { return nil }
        // Find the first UUID-looking substring.
        let pattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        if let r = s.range(of: pattern, options: .regularExpression) {
            return UUID(uuidString: String(s[r]))
        }
        return UUID(uuidString: s)
    }
    // MARK: - Direct trigger → console wiring

    /// Returns the ExternalDeviceIds for console nodes that are directly connected to `sourceNodeId` by any link.
    /// Best-effort reflector; works with graphs storing links by nodeId or by portId.
    static func directLinkedConsoleExternalDeviceIds(from sourceNodeId: UUID, in graph: Any) -> [UUID] {
        let nodes = extractCollection(from: graph, keys: ["nodes", "graphNodes"])
        let links = extractCollection(from: graph, keys: ["links", "graphLinks"])
        let portMap = buildPortIdToNodeIdMap(nodes: nodes)
        guard !nodes.isEmpty, !links.isEmpty else { return [] }

        // Map nodeId -> externalDeviceId (for nodes that look like consoles)
        var consoleExtByNodeId: [UUID: UUID] = [:]
        for node in nodes {
            guard let nodeId = extractUUIDAny(node, keys: ["id", "nodeId"]) else { continue }
            guard isConsoleLikeNode(node) else { continue }
            if let ext = extractUUIDAny(node, keys: [
                "externalDeviceId","externalDeviceID",
                "deviceId","deviceID",
                "consoleExternalDeviceId","consoleExternalDeviceID"
            ]) {
                consoleExtByNodeId[nodeId] = ext
            }
        }
        guard !consoleExtByNodeId.isEmpty else { return [] }

        // Find neighbor nodeIds directly connected to sourceNodeId
        var neighborNodeIds = Set<UUID>()

        for link in links {
            // Try explicit node endpoints
            let a = extractLinkEndpointNodeId(link, keyCandidates: ["fromNodeId","sourceNodeId","sourceId"])
            let b = extractLinkEndpointNodeId(link, keyCandidates: ["toNodeId","destNodeId","destinationNodeId","targetNodeId","targetId"])

            if let a, let b {
                if a == sourceNodeId { neighborNodeIds.insert(b) }
                if b == sourceNodeId { neighborNodeIds.insert(a) }
                continue
            }

            // Port-based graphs: resolve port ids to node ids
            let fromPort = extractStringAny(link, keys: ["fromPortId","sourcePortId","sourcePort"])
            let toPort   = extractStringAny(link, keys: ["toPortId","destPortId","destinationPortId","targetPortId","targetPort"])
            let ap = extractUUIDFromString(fromPort)
            let bp = extractUUIDFromString(toPort)

            let aNode = resolveNodeId(fromPossibleNodeId: nil, fromPossiblePortId: ap, portMap: portMap)
            let bNode = resolveNodeId(fromPossibleNodeId: nil, fromPossiblePortId: bp, portMap: portMap)

            if let aNode, let bNode {
                if aNode == sourceNodeId { neighborNodeIds.insert(bNode) }
                if bNode == sourceNodeId { neighborNodeIds.insert(aNode) }
            }
        }

        // Convert neighbor nodeIds → console external ids
        var out: [UUID] = []
        var seen = Set<UUID>()
        for nid in neighborNodeIds {
            if let ext = consoleExtByNodeId[nid], !seen.contains(ext) {
                seen.insert(ext)
                out.append(ext)
            }
        }
        return out
    }
    
    
    // MARK: - Heavy logic (Canvas/Graph neutral)

    private static func orderedConsoleExternalDeviceIdsForSendAll(context: ExecutionContext) -> [UUID] {
        let mapped: [(id: UUID, p: CGPoint)] = context.consoleExternalDeviceIds.map { id in
            let p = context.consolePosition?(id) ?? .zero
            return (id, p)
        }

        let sorted = mapped.sorted { a, b in
            if a.p.y != b.p.y { return a.p.y < b.p.y }     // top -> bottom
            if a.p.x != b.p.x { return a.p.x < b.p.x }     // left -> right
            return a.id.uuidString < b.id.uuidString       // stable tie-break
        }

        return sorted.map { $0.id }
    }

    /// True if at least one target console has any channel assignments/defaults configured.
    private static func hasAnyAssignmentsToSend(consoleIds: [UUID], context: ExecutionContext) -> Bool {
        guard !consoleIds.isEmpty else { return false }
        let devices = context.externalSnapshotDevices

        func extractId(_ dev: Any) -> UUID? {
            (Mirror(reflecting: dev).children.first { $0.label == "id" }?.value as? UUID)
        }

        func extractAssignmentsCount(_ dev: Any) -> Int {
            // Prefer the real dictionary if present.
            if let dict = (Mirror(reflecting: dev).children.first { $0.label == "consoleChannelAssignments" }?.value as? [String: Int]) {
                return dict.count
            }
            // Also treat per-position defaults as meaningful "something to send".
            if let dict = (Mirror(reflecting: dev).children.first { $0.label == "consolePositionChannelDefaults" }?.value as? [String: Int]) {
                return dict.count
            }
            return 0
        }

        for dev in devices {
            guard let id = extractId(dev), consoleIds.contains(id) else { continue }
            if extractAssignmentsCount(dev) > 0 { return true }
        }
        return false
    }

    /// True if we have any Planning Center rundown snapshot titles available to send.
    private static func hasAnySnapshotsToSend(context: ExecutionContext) -> Bool {
        let titles = context.pcoRundownSnapshotTitles()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return !titles.isEmpty
    }
    static func postSendToConsoles(
        consoleExternalDeviceIds: [UUID],
        staggerMs: Double = 0,
        includeAssignments: Bool = true,
        includeSnapshots: Bool = true
    ) {
        guard !consoleExternalDeviceIds.isEmpty else { return }
        NotificationCenter.default.post(
            name: .prodlinkGraphSendAllToConsoles,
            object: consoleExternalDeviceIds,
            userInfo: [
                GraphSendAllUserInfoKeys.delayMs: max(0, staggerMs),
                GraphSendAllUserInfoKeys.includeAssignments: includeAssignments,
                GraphSendAllUserInfoKeys.includeSnapshots: includeSnapshots
            ]
        )
    }
    /// Orchestrates Send-All and posts the graph-wide notification that a non-UI listener can consume.
    private static func fireSendAllToConsoles(
        staggerMs: Double = 180,
        includeAssignments: Bool = true,
        includeSnapshots: Bool = true,
        context: ExecutionContext
    ) {
        let orderedIds = orderedConsoleExternalDeviceIdsForSendAll(context: context)
        guard !orderedIds.isEmpty else {
            context.log("[GraphActionExecutor] SendAllConsoles: no console nodes")
            return
        }

        guard includeAssignments || includeSnapshots else {
            context.log("[GraphActionExecutor] SendAllConsoles: both categories disabled")
            return
        }

        let willSendAssignments = includeAssignments && hasAnyAssignmentsToSend(consoleIds: orderedIds, context: context)
        let willSendSnapshots = includeSnapshots && hasAnySnapshotsToSend(context: context)

        guard willSendAssignments || willSendSnapshots else {
            context.log("[GraphActionExecutor] SendAllConsoles: nothing to send")
            return
        }

        NotificationCenter.default.post(
            name: .prodlinkGraphSendAllToConsoles,
            object: orderedIds,
            userInfo: [
                GraphSendAllUserInfoKeys.delayMs: max(0, staggerMs),
                GraphSendAllUserInfoKeys.includeAssignments: willSendAssignments,
                GraphSendAllUserInfoKeys.includeSnapshots: willSendSnapshots
            ]
        )
    }

    // MARK: - Private helpers lifted from ConsoleGraphNodeView (no SwiftUI dependency)

    private enum X32ShowSendMode: String { case cues, snippets }

    private static func x32ShowSendMode(for externalDeviceId: UUID) -> X32ShowSendMode {
        let key = "prodlink.x32show.sendmode.\(externalDeviceId.uuidString)"
        if let raw = UserDefaults.standard.string(forKey: key), let mode = X32ShowSendMode(rawValue: raw) {
            return mode
        }
        return .cues
    }

    private static func extractUUID(_ dev: Any, key: String) -> UUID? {
        // IMPORTANT: Do NOT use KVC here. Many device models are Swift value types bridged as `__SwiftValue`,
        // which will throw NSUnknownKeyException for arbitrary keys.
        if let v = Mirror(reflecting: dev).children.first(where: { $0.label == key })?.value as? UUID { return v }
        return nil
    }

    private static func extractString(_ dev: Any, key: String) -> String? {
        if let v = Mirror(reflecting: dev).children.first(where: { $0.label == key })?.value as? String { return v }
        return nil
    }

    private static func extractBool(_ dev: Any, key: String) -> Bool? {
        if let v = Mirror(reflecting: dev).children.first(where: { $0.label == key })?.value as? Bool { return v }
        return nil
    }

    private static func extractInt(_ dev: Any, key: String) -> Int? {
        if let v = Mirror(reflecting: dev).children.first(where: { $0.label == key })?.value as? Int { return v }
        // Best-effort: sometimes ints are stored as Doubles or Strings.
        if let v = Mirror(reflecting: dev).children.first(where: { $0.label == key })?.value as? Double { return Int(v) }
        if let v = Mirror(reflecting: dev).children.first(where: { $0.label == key })?.value as? String, let i = Int(v) { return i }
        return nil
    }

    private static func extractAssignmentsMap(_ dev: Any) -> [String: Int] {
        if let dict = Mirror(reflecting: dev).children.first(where: { $0.label == "consoleChannelAssignments" })?.value as? [String: Int] {
            return dict
        }
        return [:]
    }
    private static func extractSnapshotNameEdits(_ dev: Any) -> [Int: String] {
        // Search top-level first.
        if let found = extractSnapshotNameEditsInObject(dev) {
            return found
        }

        // Search one level down (common: config/externalDeviceConfig nested structs).
        let m = Mirror(reflecting: dev)
        for child in m.children {
            if let found = extractSnapshotNameEditsInObject(child.value) {
                return found
            }
        }

        return [:]
    }

    /// Returns edits if present on this object; does not recurse.
    private static func extractSnapshotNameEditsInObject(_ obj: Any) -> [Int: String]? {
        let m = Mirror(reflecting: obj)
        let candidateKeys = [
            "consoleSnapshotNameEdits",
            "consoleSnapshotNameOverrides",
            "snapshotNameEdits",
            "snapshotNameOverrides"
        ]

        for key in candidateKeys {
            if let dict = m.children.first(where: { $0.label == key })?.value as? [Int: String] {
                return dict
            }
            if let dict = m.children.first(where: { $0.label == key })?.value as? [String: String] {
                var out: [Int: String] = [:]
                for (k, v) in dict {
                    if let i = Int(k) { out[i] = v }
                }
                if !out.isEmpty { return out }
            }
        }

        return nil
    }

    /// True when the snapshot device appears to be an audio console (not Shure/Sennheiser/etc.).
    private static func isConsoleLikeDevice(_ dev: Any) -> Bool {
        // Prefer an explicit kind if present.
        let rawKind: Any? = Mirror(reflecting: dev).children.first(where: { $0.label == "kind" || $0.label == "deviceKind" })?.value
        if let kind = rawKind as? String {
            let k = kind.lowercased()
            if k.contains("console") { return true }
            if k.contains("wireless") { return false }
        } else if let kind = rawKind as? ExternalDeviceKind {
            if kind == .audioConsole { return true }
            if kind == .shureWireless || kind == .sennheiserWireless { return false }
        } else if let rawKind {
            let k = String(describing: rawKind).lowercased()
            if k.contains("audioconsole") || k.contains("console") { return true }
            if k.contains("wireless") { return false }
        }

        // Otherwise infer from console model identifier.
        let modelId = (extractString(dev, key: "consoleModelIdentifier") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if modelId.hasPrefix("DiGiCo") { return true }
        if modelId == "Behringer_X32" || modelId == "Midas_M32" { return true }
        let lowered = modelId.lowercased()
        if lowered.contains("yamaha") || lowered.contains("dm7") || lowered.contains("rivage") || lowered.contains("cl") || lowered.contains("ql") {
            return true
        }

        return false
    }
    private static func isX32OrM32(modelId: String) -> Bool {
        let m = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return m == "Behringer_X32" || m == "Midas_M32"
    }

    private static func splitLabel(_ label: String) -> (position: String, fullName: String) {
        let parts = label.components(separatedBy: " — ")
        if parts.count >= 2 {
            return (
                parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return ("", label.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func formattedName(position: String, fullName: String, deviceAny: Any) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let comps = trimmed.split(separator: " ").map(String.init)
        let first = comps.first ?? trimmed
        let last = comps.last ?? trimmed

        let format = (extractString(deviceAny, key: "consoleNameFormat") ?? "").lowercased()
        let casing = (extractString(deviceAny, key: "consoleNameCasing") ?? "").lowercased()

        let base: String
        switch format {
        case "last":
            base = last
        case "position":
            base = position.isEmpty ? first : position
        case "full":
            base = first
        default:
            base = first
        }

        switch casing {
        case "upper":
            return base.uppercased()
        case "lower":
            return base.lowercased()
        default:
            return base.lowercased().localizedCapitalized
        }
    }

    private static func snapshotBaseOffset(deviceAny: Any) -> Int {
        let existing = extractBool(deviceAny, key: "consoleExistingSnapshots") ?? false
        if existing {
            return max(0, extractInt(deviceAny, key: "consoleExistingSnapshotCount") ?? 0)
        }
        return 0
    }

    private static func unpackTitleAndKey(_ raw: String) -> (title: String, key: String?) {
        if let payload = VistaPCORundownPayloadCodec.decode(from: raw) {
            return (payload.title, payload.keyName)
        }
        return (raw.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    private static func effectiveRundownItems(rundownSnapshotTitles: [String]) -> [(title: String, key: String?)] {
        let cleaned = rundownSnapshotTitles
            .map { unpackTitleAndKey($0) }
            .map { (title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), key: $0.key?.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.title.isEmpty }

        guard !cleaned.isEmpty else { return [] }

        var result: [(title: String, key: String?)] = []
        result.reserveCapacity(cleaned.count)
        for item in cleaned {
            if let last = result.last, last.title == item.title, last.key == item.key {
                continue
            }
            result.append(item)
        }
        return result
    }

    private static func formattedRundownTitles(deviceAny: Any, rundownSnapshotTitles: [String]) -> [String] {
        let items = effectiveRundownItems(rundownSnapshotTitles: rundownSnapshotTitles)
        // Match the ExternalDeviceConfig field name used by the UI.
        let casing = (extractString(deviceAny, key: "consoleSnapshotNameCasing") ?? "title").lowercased()
        let shortenEnabled = extractBool(deviceAny, key: "consoleSnapshotShortenEnabled") ?? false
        let shortenLimit = max(6, extractInt(deviceAny, key: "consoleSnapshotShortenLimit") ?? 12)

        func applyCasing(_ s: String) -> String {
            switch casing {
            case "upper": return s.uppercased()
            case "lower": return s.lowercased()
            default: return s
            }
        }

        func shorten(_ s: String) -> String {
            guard shortenEnabled else { return s }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count <= shortenLimit { return t }
            return String(t.prefix(shortenLimit))
        }

        return items.map { item in
            let base = applyCasing(item.title)
            return shorten(base)
        }
    }

    private static func buildSnapshotWorkItems(
        deviceAny: Any,
        rundownSnapshotTitles: [String],
        snapshotNameEdits: [Int: String]
    ) -> [(seq: Int, index: Int, name: String)] {
        let titles = formattedRundownTitles(deviceAny: deviceAny, rundownSnapshotTitles: rundownSnapshotTitles)
        guard !titles.isEmpty else { return [] }

        let baseOffset = snapshotBaseOffset(deviceAny: deviceAny)
        return titles.enumerated().map { (offset, title) in
            let seq = offset + 1
            let idx = (seq - 1) + baseOffset
            let name = snapshotNameEdits[seq] ?? title
            return (seq: seq, index: idx, name: name)
        }
    }

    private static func buildAssignmentWorkItems(
        deviceAny: Any,
        peopleLabelsInOrder: [String]
    ) -> [(channel: Int, name: String)] {
        let assignments = extractAssignmentsMap(deviceAny)
        guard !assignments.isEmpty else { return [] }

        let modelId = extractString(deviceAny, key: "consoleModelIdentifier") ?? ""
        let limitTo32 = isX32OrM32(modelId: modelId)

        var byChannel: [Int: String] = [:]
        for label in peopleLabelsInOrder {
            guard let ch = assignments[label], ch > 0 else { continue }
            if limitTo32, ch > 32 { continue }
            let parts = splitLabel(label)
            let name = formattedName(position: parts.position, fullName: parts.fullName, deviceAny: deviceAny)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            byChannel[ch] = trimmed
        }

        return byChannel.keys.sorted().map { (channel: $0, name: byChannel[$0] ?? "") }
            .filter { !$0.name.isEmpty }
    }

    private static func splitPeopleLabel(_ label: String) -> (position: String, fullName: String) {
        let parts = label.components(separatedBy: " — ")
        if parts.count >= 2 {
            return (
                parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return ("", label.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func formattedPeopleName(from label: String, format: String, casing: String) -> String {
        let parts = splitPeopleLabel(label)
        let full = parts.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let comps = full.split(separator: " ").map(String.init)
        let first = comps.first ?? full
        let last = comps.last ?? full

        let base: String
        switch format {
        case "last":
            base = last
        case "position":
            base = parts.position.isEmpty ? full : parts.position
        default:
            base = first
        }

        let cased: String
        switch casing {
        case "upper":
            cased = base.uppercased()
        default:
            cased = base.lowercased().localizedCapitalized
        }

        if cased.count <= 8 { return cased }
        let shortened = NameShortener.shorten(cased, limit: 8)
        return shortened.count <= 8 ? shortened : String(shortened.prefix(8))
    }
}
