import Foundation

enum SmartLightProviderType: String, Codable, CaseIterable, Identifiable {
    case philipsHue
    case govee
    case genericFuture

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .philipsHue:
            return "Philips Hue"
        case .govee:
            return "Govee"
        case .genericFuture:
            return "Generic / Future"
        }
    }
}

enum SmartLightCapability: String, Codable, CaseIterable, Hashable, Identifiable {
    case power
    case brightness
    case color
    case colorTemperature
    case scene
    case stateRead
    case toggle

    var id: String { rawValue }
}

nonisolated struct SmartLightColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    nonisolated init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    nonisolated var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    nonisolated static func parse(_ raw: String) -> SmartLightColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return SmartLightColor(red: red, green: green, blue: blue)
    }
}

struct SmartLightSceneSummary: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
}

nonisolated struct SmartLightDeviceState: Codable, Equatable, Hashable {
    var isOn: Bool?
    var brightnessPercent: Double?
    var color: SmartLightColor?
    var colorTemperatureKelvin: Int?
    var activeSceneID: String?
    var isReachable: Bool?

    static let empty = SmartLightDeviceState()
}

struct SmartLightDevice: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var providerType: SmartLightProviderType
    var name: String
    var model: String?
    var capabilities: Set<SmartLightCapability>
    var isOnline: Bool?
    var isGroup: Bool
    var scenes: [SmartLightSceneSummary]
    var currentState: SmartLightDeviceState?

    init(
        id: String,
        providerType: SmartLightProviderType,
        name: String,
        model: String? = nil,
        capabilities: Set<SmartLightCapability> = [],
        isOnline: Bool? = nil,
        isGroup: Bool = false,
        scenes: [SmartLightSceneSummary] = [],
        currentState: SmartLightDeviceState? = nil
    ) {
        self.id = id
        self.providerType = providerType
        self.name = name
        self.model = model
        self.capabilities = capabilities
        self.isOnline = isOnline
        self.isGroup = isGroup
        self.scenes = scenes
        self.currentState = currentState
    }
}

enum SmartLightActionKind: String, Codable, CaseIterable, Identifiable {
    case turnOn
    case turnOff
    case toggle
    case flash
    case setBrightness
    case setColor
    case setColorTemperature
    case activateScene
    case queryState

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turnOn:
            return "Turn On"
        case .turnOff:
            return "Turn Off"
        case .toggle:
            return "Toggle"
        case .flash:
            return "Flash"
        case .setBrightness:
            return "Set Brightness"
        case .setColor:
            return "Set Color"
        case .setColorTemperature:
            return "Set Color Temperature"
        case .activateScene:
            return "Activate Scene"
        case .queryState:
            return "Read Current State"
        }
    }
}

struct SmartLightAction: Codable, Equatable, Hashable {
    var kind: SmartLightActionKind
    var powerState: Bool?
    var brightnessPercent: Double?
    var color: SmartLightColor?
    var colorTemperatureKelvin: Int?
    var sceneID: String?
    var flashCount: Int?

    init(
        kind: SmartLightActionKind = .turnOn,
        powerState: Bool? = nil,
        brightnessPercent: Double? = nil,
        color: SmartLightColor? = nil,
        colorTemperatureKelvin: Int? = nil,
        sceneID: String? = nil,
        flashCount: Int? = nil
    ) {
        self.kind = kind
        self.powerState = powerState
        self.brightnessPercent = brightnessPercent
        self.color = color
        self.colorTemperatureKelvin = colorTemperatureKelvin
        self.sceneID = sceneID
        self.flashCount = flashCount
    }
}

struct SmartLightConnectionConfig: Codable, Equatable, Hashable {
    var providerType: SmartLightProviderType
    var host: String
    var apiKeyReference: String?
    var applicationKeyReference: String?
    var bridgeIdentifier: String?

    init(
        providerType: SmartLightProviderType,
        host: String = "",
        apiKeyReference: String? = nil,
        applicationKeyReference: String? = nil,
        bridgeIdentifier: String? = nil
    ) {
        self.providerType = providerType
        self.host = host
        self.apiKeyReference = apiKeyReference
        self.applicationKeyReference = applicationKeyReference
        self.bridgeIdentifier = bridgeIdentifier
    }
}

struct SmartLightExecutionResult: Codable, Equatable {
    var providerType: SmartLightProviderType
    var deviceID: String
    var deviceName: String?
    var state: SmartLightDeviceState?
    var message: String?

    func graphPayloadJSON() -> String? {
        try? String(data: JSONEncoder().encode(self), encoding: .utf8)
    }
}

enum SmartLightSecretKind: String, Codable {
    case goveeAPIKey
    case hueApplicationKey
}

struct SmartLightProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var providerType: SmartLightProviderType
    var isEnabled: Bool
    var host: String
    var bridgeIdentifier: String?
    var bridgeName: String?
    var lastValidatedAt: Date?
    var lastValidationMessage: String?
    var lastDiscoveredDevices: [SmartLightDevice]

    init(
        id: UUID = UUID(),
        name: String = "",
        providerType: SmartLightProviderType,
        isEnabled: Bool = true,
        host: String = "",
        bridgeIdentifier: String? = nil,
        bridgeName: String? = nil,
        lastValidatedAt: Date? = nil,
        lastValidationMessage: String? = nil,
        lastDiscoveredDevices: [SmartLightDevice] = []
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.isEnabled = isEnabled
        self.host = host
        self.bridgeIdentifier = bridgeIdentifier
        self.bridgeName = bridgeName
        self.lastValidatedAt = lastValidatedAt
        self.lastValidationMessage = lastValidationMessage
        self.lastDiscoveredDevices = lastDiscoveredDevices
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let bridgeName, !bridgeName.isEmpty {
            return bridgeName
        }
        if !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return host
        }
        return providerType.displayName
    }
}

enum SmartLightProfileSecretReference {
    static func make(profileID: UUID, kind: SmartLightSecretKind) -> String {
        "\(profileID.uuidString).\(kind.rawValue)"
    }
}
