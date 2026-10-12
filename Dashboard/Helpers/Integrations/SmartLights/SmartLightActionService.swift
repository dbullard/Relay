import Foundation

enum SmartLightActionNotification {
    static let started = Notification.Name("Relay.ActionNode.SmartLightStarted")
    static let succeeded = Notification.Name("Relay.ActionNode.SmartLightSucceeded")
    static let failed = Notification.Name("Relay.ActionNode.SmartLightFailed")
}

enum SmartLightActionUserInfoKeys {
    static let nodeId = "nodeId"
    static let message = "message"
    static let providerType = "providerType"
    static let deviceID = "deviceID"
    static let stateJSON = "stateJSON"
    static let powerState = "powerState"
    static let brightness = "brightness"
    static let colorTemperature = "colorTemperature"
}

enum SmartLightActionService {
    /// Executes `action` on every device in `deviceIDs`, posting a single aggregate
    /// started/succeeded/failed notification for `nodeId`.
    static func execute(
        nodeId: UUID,
        profileID: UUID,
        deviceIDs: [String],
        action: SmartLightAction,
        center: NotificationCenter = .default
    ) {
        guard !deviceIDs.isEmpty else {
            center.post(
                name: SmartLightActionNotification.failed,
                object: nil,
                userInfo: [
                    SmartLightActionUserInfoKeys.nodeId: nodeId,
                    SmartLightActionUserInfoKeys.message: "No device selected.",
                    ActionNodeUserInfoKeys.errorMessage: "No device selected."
                ]
            )
            return
        }

        center.post(
            name: SmartLightActionNotification.started,
            object: nil,
            userInfo: [SmartLightActionUserInfoKeys.nodeId: nodeId]
        )

        Task {
            do {
                guard let profile = SmartLightProfilesStore.shared.profile(id: profileID) else {
                    throw SmartLightProviderError.profileMissing
                }
                let provider = SmartLightProviderRegistry.makeProvider(profile: profile)

                var firstResult: SmartLightDeviceState? = nil
                var errors: [String] = []

                // (state, errorMessage) — errorMessage is nil on success
                await withTaskGroup(of: (SmartLightDeviceState?, String?).self) { group in
                    for deviceID in deviceIDs {
                        group.addTask {
                            do {
                                let state = try await runAction(provider: provider, profileID: profileID, deviceID: deviceID, action: action)
                                return (state, nil)
                            } catch {
                                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                return (nil, message)
                            }
                        }
                    }
                    for await (state, errorMessage) in group {
                        if let state { if firstResult == nil { firstResult = state } }
                        if let errorMessage { errors.append(errorMessage) }
                    }
                }

                if !errors.isEmpty {
                    let message = errors.joined(separator: "\n")
                    center.post(
                        name: SmartLightActionNotification.failed,
                        object: nil,
                        userInfo: [
                            SmartLightActionUserInfoKeys.nodeId: nodeId,
                            SmartLightActionUserInfoKeys.message: message,
                            ActionNodeUserInfoKeys.errorMessage: message
                        ]
                    )
                    return
                }

                let resultState = firstResult ?? SmartLightDeviceState()
                let payload = SmartLightExecutionResult(
                    providerType: profile.providerType,
                    deviceID: deviceIDs.first ?? "",
                    deviceName: profile.displayName,
                    state: resultState,
                    message: successMessage(for: action.kind, profileName: profile.displayName, deviceCount: deviceIDs.count)
                )
                var userInfo: [String: Any] = [
                    SmartLightActionUserInfoKeys.nodeId: nodeId,
                    SmartLightActionUserInfoKeys.providerType: profile.providerType.rawValue,
                    SmartLightActionUserInfoKeys.deviceID: deviceIDs.first ?? "",
                    SmartLightActionUserInfoKeys.message: payload.message ?? "Smart light action complete"
                ]
                if let stateJSON = payload.graphPayloadJSON() {
                    userInfo[SmartLightActionUserInfoKeys.stateJSON] = stateJSON
                }
                if let isOn = resultState.isOn {
                    userInfo[SmartLightActionUserInfoKeys.powerState] = isOn
                }
                if let brightness = resultState.brightnessPercent {
                    userInfo[SmartLightActionUserInfoKeys.brightness] = brightness
                }
                if let kelvin = resultState.colorTemperatureKelvin {
                    userInfo[SmartLightActionUserInfoKeys.colorTemperature] = kelvin
                }
                center.post(name: SmartLightActionNotification.succeeded, object: nil, userInfo: userInfo)
            } catch {
                center.post(
                    name: SmartLightActionNotification.failed,
                    object: nil,
                    userInfo: [
                        SmartLightActionUserInfoKeys.nodeId: nodeId,
                        SmartLightActionUserInfoKeys.message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                        ActionNodeUserInfoKeys.errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    ]
                )
            }
        }
    }

    /// Single-device convenience wrapper (used by tests and legacy callers).
    static func execute(
        nodeId: UUID,
        profileID: UUID,
        deviceID: String,
        action: SmartLightAction,
        center: NotificationCenter = .default
    ) {
        execute(nodeId: nodeId, profileID: profileID, deviceIDs: [deviceID], action: action, center: center)
    }

    private static func runAction(
        provider: any SmartLightProvider,
        profileID: UUID,
        deviceID: String,
        action: SmartLightAction
    ) async throws -> SmartLightDeviceState {
        switch action.kind {
        case .turnOn:
            return try await provider.setPower(deviceID: deviceID, isOn: true)
        case .turnOff:
            return try await provider.setPower(deviceID: deviceID, isOn: false)
        case .toggle:
            // Groups and some devices don't support state reads — default to turning on if unknown.
            let current = (try? await provider.getDeviceState(deviceID: deviceID)) ?? SmartLightDeviceState()
            return try await provider.setPower(deviceID: deviceID, isOn: !(current.isOn ?? true))
        case .setBrightness:
            guard let brightness = action.brightnessPercent else {
                throw SmartLightProviderError.invalidConfiguration("Enter a brightness value before running this node.")
            }
            return try await provider.setBrightness(deviceID: deviceID, percent: brightness)
        case .setColor:
            guard let color = action.color else {
                throw SmartLightProviderError.invalidConfiguration("Choose a color before running this node.")
            }
            return try await provider.setColor(deviceID: deviceID, color: color)
        case .setColorTemperature:
            guard let kelvin = action.colorTemperatureKelvin else {
                throw SmartLightProviderError.invalidConfiguration("Enter a color temperature before running this node.")
            }
            return try await provider.setColorTemperature(deviceID: deviceID, kelvin: kelvin)
        case .activateScene:
            guard let rawSceneID = action.sceneID, !rawSceneID.isEmpty else {
                throw SmartLightProviderError.invalidConfiguration("Choose a scene before running this node.")
            }
            // If the user typed a scene name rather than a numeric ID, try to resolve it
            // against the profile's discovered scene list (which stores integer IDs).
            let resolvedSceneID: String
            if Int(rawSceneID) == nil,
               let profile = SmartLightProfilesStore.shared.profile(id: profileID) {
                let allScenes = profile.lastDiscoveredDevices.flatMap(\.scenes)
                if let match = allScenes.first(where: {
                    $0.name.lowercased() == rawSceneID.lowercased()
                }) {
                    resolvedSceneID = match.id
                } else {
                    resolvedSceneID = rawSceneID
                }
            } else {
                resolvedSceneID = rawSceneID
            }
            return try await provider.activateScene(deviceID: deviceID, sceneID: resolvedSceneID)
        case .flash:
            let count = max(1, min(10, action.flashCount ?? 3))
            // Flash by cycling power off → on. 600 ms per state gives cloud APIs
            // (Govee) enough time to process each command before the next arrives.
            for i in 0..<count {
                if i == 0 {
                    try await provider.setPower(deviceID: deviceID, isOn: true)
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                try await provider.setPower(deviceID: deviceID, isOn: false)
                try await Task.sleep(nanoseconds: 500_000_000)
                try await provider.setPower(deviceID: deviceID, isOn: true)
                if i < count - 1 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            return SmartLightDeviceState(isOn: true, isReachable: true)
        case .queryState:
            return try await provider.getDeviceState(deviceID: deviceID)
        }
    }

    private static func successMessage(for action: SmartLightActionKind, profileName: String, deviceCount: Int) -> String {
        let suffix = deviceCount > 1 ? " (\(deviceCount) devices)" : ""
        switch action {
        case .turnOn:            return "\(profileName) turned on\(suffix)."
        case .turnOff:           return "\(profileName) turned off\(suffix)."
        case .toggle:            return "\(profileName) toggled\(suffix)."
        case .setBrightness:     return "\(profileName) brightness updated\(suffix)."
        case .setColor:          return "\(profileName) color updated\(suffix)."
        case .setColorTemperature: return "\(profileName) color temperature updated\(suffix)."
        case .activateScene:     return "\(profileName) scene activated\(suffix)."
        case .flash:
            return "\(profileName) flashed\(suffix)."
        case .queryState:        return "\(profileName) state refreshed\(suffix)."
        }
    }
}
