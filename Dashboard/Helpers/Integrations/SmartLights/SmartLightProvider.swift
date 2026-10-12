import Foundation

enum SmartLightProviderError: LocalizedError, Equatable {
    case profileMissing
    case secretMissing(String)
    case invalidConfiguration(String)
    case bridgePairingRequired
    case invalidAPIKey
    case unsupportedCapability(String)
    case deviceOffline(String)
    case rateLimited
    case requestTimedOut
    case unreachableHost(String)
    case transportFailure(String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .profileMissing:
            return "The selected smart light profile could not be found."
        case .secretMissing(let label):
            return "\(label) is missing. Open Smart Lights settings and update the saved credentials."
        case .invalidConfiguration(let message):
            return message
        case .bridgePairingRequired:
            return "Hue bridge pairing is required. Press the bridge link button and try again."
        case .invalidAPIKey:
            return "The Govee API key is invalid or has expired."
        case .unsupportedCapability(let message):
            return message
        case .deviceOffline(let name):
            return "\(name) appears to be offline or unreachable."
        case .rateLimited:
            return "The provider asked Relay to slow down. Please try again in a moment."
        case .requestTimedOut:
            return "The request timed out before the light responded."
        case .unreachableHost(let host):
            return "Relay could not reach \(host)."
        case .transportFailure(let message):
            return message
        case .notImplemented(let message):
            return message
        }
    }
}

protocol SmartLightProvider {
    var providerType: SmartLightProviderType { get }
    var profile: SmartLightProfile { get }

    func discoverDevices() async throws -> [SmartLightDevice]
    func listDevices() async throws -> [SmartLightDevice]
    func getDeviceState(deviceID: String) async throws -> SmartLightDeviceState
    @discardableResult func setPower(deviceID: String, isOn: Bool) async throws -> SmartLightDeviceState
    func setBrightness(deviceID: String, percent: Double) async throws -> SmartLightDeviceState
    func setColor(deviceID: String, color: SmartLightColor) async throws -> SmartLightDeviceState
    func setColorTemperature(deviceID: String, kelvin: Int) async throws -> SmartLightDeviceState
    func activateScene(deviceID: String, sceneID: String) async throws -> SmartLightDeviceState
}

enum SmartLightProviderRegistry {
    static func makeProvider(
        profile: SmartLightProfile,
        session: URLSession = .shared
    ) -> any SmartLightProvider {
        switch profile.providerType {
        case .philipsHue:
            return HueSmartLightProvider(profile: profile)
        case .govee:
            return GoveeSmartLightProvider(profile: profile, session: session)
        case .genericFuture:
            return PlaceholderGenericSmartLightProvider(profile: profile)
        }
    }
}

