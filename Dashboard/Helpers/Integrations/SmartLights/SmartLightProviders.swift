import Foundation

// MARK: - Hue catalog cache

/// Caches the Hue device/light/scene catalog per profile so that action commands
/// (setPower, setBrightness, etc.) don't need to refetch 3 endpoints each time.
/// listDevices() always bypasses this cache and repopulates it.
private actor HueCatalogCache {
    static let shared = HueCatalogCache()
    private struct Entry { var catalog: HueCatalog; var fetchedAt: Date }
    private var entries: [UUID: Entry] = [:]
    private let ttl: TimeInterval = 30

    func catalog(for profileID: UUID) -> HueCatalog? {
        guard let entry = entries[profileID],
              Date().timeIntervalSince(entry.fetchedAt) < ttl else { return nil }
        return entry.catalog
    }

    func store(_ catalog: HueCatalog, for profileID: UUID) {
        entries[profileID] = Entry(catalog: catalog, fetchedAt: Date())
    }

    func invalidate(for profileID: UUID) {
        entries.removeValue(forKey: profileID)
    }
}

private final class HueBridgeURLSessionDelegate: NSObject, URLSessionDelegate {
    private let allowedHostnames: [String]

    init(allowedHostnames: [String]) {
        self.allowedHostnames = allowedHostnames
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            for hostname in allowedHostnames where !hostname.isEmpty {
                SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, hostname as CFString))
                var error: CFError?
                if SecTrustEvaluateWithError(trust, &error) {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                    return
                }
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

struct HueSmartLightProvider: SmartLightProvider {
    let providerType: SmartLightProviderType = .philipsHue
    let profile: SmartLightProfile

    private let timeout: TimeInterval = 5

    init(profile: SmartLightProfile) {
        self.profile = profile
    }

    func discoverDevices() async throws -> [SmartLightDevice] {
        try await listDevices()
    }

    func listDevices() async throws -> [SmartLightDevice] {
        let appKey = try requiredSecret(.hueApplicationKey, label: "Hue bridge application key")
        let catalog = try await loadCatalog(applicationKey: appKey, bypassCache: true)

        return catalog.devices.compactMap { device in
            guard let lightID = device.lightServiceIDs.first(where: { catalog.lightsByID[$0] != nil }),
                  let light = catalog.lightsByID[lightID] else {
                return nil
            }
            let mappedScenes = (device.groupID.flatMap { catalog.scenesByOwner[$0] } ?? []).map {
                SmartLightSceneSummary(id: $0.id, name: $0.name)
            }
            var capabilities = light.capabilities
            if !mappedScenes.isEmpty {
                capabilities.insert(.scene)
            }
            return SmartLightDevice(
                id: lightID,
                providerType: providerType,
                name: device.metadata.name,
                model: device.productData.modelID,
                capabilities: capabilities,
                isOnline: true,
                scenes: mappedScenes,
                currentState: light.deviceState
            )
        }
    }

    func getDeviceState(deviceID: String) async throws -> SmartLightDeviceState {
        let appKey = try requiredSecret(.hueApplicationKey, label: "Hue bridge application key")
        let target = try await resolveLightTarget(for: deviceID, applicationKey: appKey)
        let state = try await fetchLightState(lightID: target.lightID, applicationKey: appKey)
        return state
    }

    func setPower(deviceID: String, isOn: Bool) async throws -> SmartLightDeviceState {
        let appKey = try requiredSecret(.hueApplicationKey, label: "Hue bridge application key")
        let target = try await resolveLightTarget(for: deviceID, applicationKey: appKey)
        try ensureCapability(.power, for: target)
        _ = try await sendLightCommand(lightID: target.lightID, applicationKey: appKey, body: ["on": ["on": isOn]])
        return try await fetchLightState(lightID: target.lightID, applicationKey: appKey)
    }

    func setBrightness(deviceID: String, percent: Double) async throws -> SmartLightDeviceState {
        let appKey = try requiredSecret(.hueApplicationKey, label: "Hue bridge application key")
        let target = try await resolveLightTarget(for: deviceID, applicationKey: appKey)
        try ensureCapability(.brightness, for: target)
        let clamped = min(max(percent, 0), 100)
        _ = try await sendLightCommand(lightID: target.lightID, applicationKey: appKey, body: ["dimming": ["brightness": clamped]])
        return try await fetchLightState(lightID: target.lightID, applicationKey: appKey)
    }

    func setColor(deviceID: String, color: SmartLightColor) async throws -> SmartLightDeviceState {
        let appKey = try requiredSecret(.hueApplicationKey, label: "Hue bridge application key")
        let target = try await resolveLightTarget(for: deviceID, applicationKey: appKey)
        try ensureCapability(.color, for: target)
        let xy = HueColorSpace.xy(from: color)
        _ = try await sendLightCommand(
            lightID: target.lightID,
            applicationKey: appKey,
            body: [
                "color": [
                    "xy": [
                        "x": xy.x,
                        "y": xy.y
                    ]
                ]
            ]
        )
        return try await fetchLightState(lightID: target.lightID, applicationKey: appKey)
    }

    func setColorTemperature(deviceID: String, kelvin: Int) async throws -> SmartLightDeviceState {
        let appKey = try requiredSecret(.hueApplicationKey, label: "Hue bridge application key")
        let target = try await resolveLightTarget(for: deviceID, applicationKey: appKey)
        try ensureCapability(.colorTemperature, for: target)
        let mirek = max(153, min(500, Int((1_000_000.0 / Double(max(1500, kelvin))).rounded())))
        _ = try await sendLightCommand(lightID: target.lightID, applicationKey: appKey, body: ["color_temperature": ["mirek": mirek]])
        return try await fetchLightState(lightID: target.lightID, applicationKey: appKey)
    }

    func activateScene(deviceID: String, sceneID: String) async throws -> SmartLightDeviceState {
        let appKey = try requiredSecret(.hueApplicationKey, label: "Hue bridge application key")
        let target = try await resolveLightTarget(for: deviceID, applicationKey: appKey)
        try ensureCapability(.scene, for: target)
        guard target.scenes.contains(where: { $0.id == sceneID }) else {
            throw SmartLightProviderError.invalidConfiguration("The selected Hue scene is no longer available. Refresh devices and choose a scene again.")
        }
        _ = try await sendSceneCommand(sceneID: sceneID, applicationKey: appKey)
        return try await fetchLightState(lightID: target.lightID, applicationKey: appKey)
    }

    func pairBridge() async throws -> String {
        let data = try await performUnauthenticatedRequest(
            path: "/api",
            method: "POST",
            bodyData: Data(#"{"devicetype":"relay#smart-light-control"}"#.utf8)
        )
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = payload.first else {
            throw SmartLightProviderError.transportFailure("Relay received an unreadable pairing response from the Hue bridge.")
        }
        if let success = first["success"] as? [String: Any], let username = success["username"] as? String {
            return username
        }
        throw SmartLightProviderError.bridgePairingRequired
    }

    private func loadCatalog(applicationKey: String, bypassCache: Bool = false) async throws -> HueCatalog {
        if !bypassCache, let cached = await HueCatalogCache.shared.catalog(for: profile.id) {
            return cached
        }

        // One session for all three parallel fetches — avoids creating a new URLSession per request.
        let session = makeSession()
        async let devicesData = performRequest(path: "/clip/v2/resource/device", applicationKey: applicationKey, session: session)
        async let lightsData = performRequest(path: "/clip/v2/resource/light", applicationKey: applicationKey, session: session)
        async let scenesData = performRequest(path: "/clip/v2/resource/scene", applicationKey: applicationKey, session: session)

        let devices = try JSONDecoder().decode(HueResourceEnvelope<HueDeviceResource>.self, from: try await devicesData).data
        let lights = try JSONDecoder().decode(HueResourceEnvelope<HueLightResource>.self, from: try await lightsData).data
        let sceneResources = try JSONDecoder().decode(HueResourceEnvelope<HueSceneResource>.self, from: try await scenesData).data

        let scenesByOwner = Dictionary(
            grouping: sceneResources.compactMap { scene -> (String, HueSceneResource)? in
                guard let groupID = scene.groupID else { return nil }
                return (groupID, scene)
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }

        let catalog = HueCatalog(
            devices: devices,
            lightsByID: Dictionary(uniqueKeysWithValues: lights.map { ($0.id, $0) }),
            scenesByOwner: scenesByOwner
        )
        await HueCatalogCache.shared.store(catalog, for: profile.id)
        return catalog
    }

    private func resolveLightTarget(for deviceID: String, applicationKey: String) async throws -> HueResolvedLightTarget {
        let catalog = try await loadCatalog(applicationKey: applicationKey)

        if let directDevice = catalog.devices.first(where: { $0.lightServiceIDs.contains(deviceID) }),
           let light = catalog.lightsByID[deviceID] {
            let scenes = (directDevice.groupID.flatMap { catalog.scenesByOwner[$0] } ?? []).map {
                SmartLightSceneSummary(id: $0.id, name: $0.name)
            }
            return HueResolvedLightTarget(
                lightID: deviceID,
                name: directDevice.metadata.name,
                capabilities: sceneAwareCapabilities(from: light, scenes: scenes),
                scenes: scenes
            )
        }

        if let legacyDevice = catalog.devices.first(where: { $0.id == deviceID }),
           let lightID = legacyDevice.lightServiceIDs.first(where: { catalog.lightsByID[$0] != nil }),
           let light = catalog.lightsByID[lightID] {
            let scenes = (legacyDevice.groupID.flatMap { catalog.scenesByOwner[$0] } ?? []).map {
                SmartLightSceneSummary(id: $0.id, name: $0.name)
            }
            return HueResolvedLightTarget(
                lightID: lightID,
                name: legacyDevice.metadata.name,
                capabilities: sceneAwareCapabilities(from: light, scenes: scenes),
                scenes: scenes
            )
        }

        throw SmartLightProviderError.invalidConfiguration("The saved Hue light could not be found. Refresh devices and choose the light again.")
    }

    private func ensureCapability(_ capability: SmartLightCapability, for target: HueResolvedLightTarget) throws {
        guard target.capabilities.contains(capability) else {
            throw SmartLightProviderError.unsupportedCapability("\(target.name) does not support \(capability.userFacingDescription) in Hue.")
        }
    }

    private func sceneAwareCapabilities(from light: HueLightResource, scenes: [SmartLightSceneSummary]) -> Set<SmartLightCapability> {
        var capabilities = light.capabilities
        if !scenes.isEmpty {
            capabilities.insert(.scene)
        }
        return capabilities
    }

    private func fetchLightState(lightID: String, applicationKey: String) async throws -> SmartLightDeviceState {
        let data = try await performRequest(path: "/clip/v2/resource/light/\(lightID)", applicationKey: applicationKey)
        let response = try JSONDecoder().decode(HueResourceEnvelope<HueLightResource>.self, from: data)
        guard let light = response.data.first else {
            throw SmartLightProviderError.transportFailure("Relay could not read the Hue light state.")
        }
        return light.deviceState
    }

    private func sendLightCommand(lightID: String, applicationKey: String, body: [String: Any]) async throws -> Data {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(
            path: "/clip/v2/resource/light/\(lightID)",
            method: "PUT",
            applicationKey: applicationKey,
            bodyData: bodyData
        )
    }

    private func sendSceneCommand(sceneID: String, applicationKey: String) async throws -> Data {
        let bodyData = try JSONSerialization.data(withJSONObject: ["recall": ["action": "active"]])
        return try await performRequest(
            path: "/clip/v2/resource/scene/\(sceneID)",
            method: "PUT",
            applicationKey: applicationKey,
            bodyData: bodyData
        )
    }

    private func requiredSecret(_ kind: SmartLightSecretKind, label: String) throws -> String {
        guard let secret = SmartLightKeychainStore.shared.loadSecret(profileID: profile.id, kind: kind),
              !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SmartLightProviderError.secretMissing(label)
        }
        return secret
    }

    private func makeURL(path: String) throws -> URL {
        let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw SmartLightProviderError.invalidConfiguration("Enter a Hue bridge IP address or host name in Smart Lights settings.")
        }
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw SmartLightProviderError.invalidConfiguration("The saved Hue bridge address is invalid.")
        }
        return url
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        return URLSession(
            configuration: config,
            delegate: HueBridgeURLSessionDelegate(allowedHostnames: tlsValidationNames()),
            delegateQueue: nil
        )
    }

    private func tlsValidationNames() -> [String] {
        [profile.bridgeIdentifier, profile.host]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func performRequest(
        path: String,
        method: String = "GET",
        applicationKey: String,
        bodyData: Data? = nil,
        session: URLSession? = nil
    ) async throws -> Data {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue(applicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }
        do {
            let (data, response) = try await (session ?? makeSession()).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SmartLightProviderError.transportFailure("Relay received an invalid response from the Hue bridge.")
            }
            logHueResponse(request: request, response: http, data: data, authenticated: true)
            if http.statusCode == 401 { throw SmartLightProviderError.invalidAPIKey }
            if http.statusCode == 403 { throw SmartLightProviderError.bridgePairingRequired }
            guard (200..<300).contains(http.statusCode) else {
                throw SmartLightProviderError.transportFailure("Hue bridge request failed with status \(http.statusCode).")
            }
            return data
        } catch let error as SmartLightProviderError {
            throw error
        } catch {
            if let urlError = error as? URLError {
                if urlError.code == .timedOut {
                    throw SmartLightProviderError.requestTimedOut
                }
                if [
                    URLError.serverCertificateUntrusted,
                    .serverCertificateHasBadDate,
                    .serverCertificateHasUnknownRoot,
                    .serverCertificateNotYetValid,
                    .secureConnectionFailed
                ].contains(urlError.code) {
                    throw SmartLightProviderError.transportFailure("Relay could not verify the Hue bridge's secure certificate. Check the saved host or bridge ID and try again.")
                }
            }
            throw SmartLightProviderError.unreachableHost(profile.host)
        }
    }

    private func performUnauthenticatedRequest(path: String, method: String, bodyData: Data?) async throws -> Data {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        do {
            let (data, response) = try await makeSession().data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SmartLightProviderError.bridgePairingRequired
            }
            logHueResponse(request: request, response: http, data: data, authenticated: false)
            guard (200..<300).contains(http.statusCode) else {
                throw SmartLightProviderError.bridgePairingRequired
            }
            return data
        } catch let error as SmartLightProviderError {
            throw error
        } catch {
            if let urlError = error as? URLError,
               [
                    URLError.serverCertificateUntrusted,
                    .serverCertificateHasBadDate,
                    .serverCertificateHasUnknownRoot,
                    .serverCertificateNotYetValid,
                    .secureConnectionFailed
               ].contains(urlError.code) {
                throw SmartLightProviderError.transportFailure("Relay could not verify the Hue bridge's secure certificate. Check the saved host or bridge ID and try again.")
            }
            throw SmartLightProviderError.unreachableHost(profile.host)
        }
    }

    private func logHueResponse(
        request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        authenticated: Bool
    ) {
        let path = request.url?.path ?? "<unknown>"
        let host = request.url?.host ?? profile.host
        let mode = authenticated ? "auth" : "pair"
        var parts = [
            "[Relay] [Hue] \(request.httpMethod ?? "GET") \(path)",
            "status=\(response.statusCode)",
            "host=\(host)",
            "mode=\(mode)"
        ]
        if let server = response.value(forHTTPHeaderField: "Server"), !server.isEmpty {
            parts.append("server=\(server)")
        }
        if let dateHeader = response.value(forHTTPHeaderField: "Date"), !dateHeader.isEmpty {
            parts.append("date=\(dateHeader)")
        }
        let body = sanitizedResponseBody(data)
        if !body.isEmpty {
            parts.append("body=\(body)")
        }
        print(parts.joined(separator: " • "))
    }
}

struct GoveeSmartLightProvider: SmartLightProvider {
    let providerType: SmartLightProviderType = .govee
    let profile: SmartLightProfile
    private let session: URLSession
    private let baseURL = URL(string: "https://openapi.api.govee.com")!

    init(profile: SmartLightProfile, session: URLSession = .shared) {
        self.profile = profile
        self.session = session
    }

    func discoverDevices() async throws -> [SmartLightDevice] {
        try await listDevices()
    }

    func listDevices() async throws -> [SmartLightDevice] {
        let response: GoveeV2DevicesResponse = try await get(path: "/router/api/v1/user/devices")
        let filtered = response.data.filter { $0.isLightOrPlug }

        if filtered.isEmpty {
            print("[Relay] [Govee] Connected account returned no compatible lights or plugs. totalDevices=\(response.data.count)")
        } else {
            print("[Relay] [Govee] Loaded \(filtered.count) compatible device(s) from \(response.data.count) total account device(s).")
        }

        // Govee's developer API (/router/api/v1/user/devices/scenes) returns 404 —
        // scene names/IDs are not accessible via the public developer tier.
        // Fall back to capability-embedded options (usually empty for most models).
        return filtered.map { device in
            let scenes = device.sceneSummaries
            return SmartLightDevice(
                id: "\(device.device)|\(device.sku)",
                providerType: providerType,
                name: device.deviceName,
                model: device.sku,
                capabilities: device.derivedCapabilities,
                isOnline: true,
                isGroup: device.isGroup,
                scenes: scenes
            )
        }
    }

    func getDeviceState(deviceID: String) async throws -> SmartLightDeviceState {
        let id = try splitDeviceID(deviceID)
        struct StateRequest: Encodable {
            var requestId: String
            var payload: Payload
            struct Payload: Encodable { var sku: String; var device: String }
        }
        let body = StateRequest(requestId: UUID().uuidString, payload: .init(sku: id.model, device: id.device))
        let response: GoveeV2StateResponse = try await post(path: "/router/api/v1/device/state", body: body)
        return response.data?.toState() ?? SmartLightDeviceState(isReachable: true)
    }

    func setPower(deviceID: String, isOn: Bool) async throws -> SmartLightDeviceState {
        try await control(deviceID, type: "devices.capabilities.on_off", instance: "powerSwitch", value: isOn ? 1 : 0)
        return SmartLightDeviceState(isOn: isOn, isReachable: true)
    }

    func setBrightness(deviceID: String, percent: Double) async throws -> SmartLightDeviceState {
        let value = max(1, min(100, Int(percent.rounded())))
        try await control(deviceID, type: "devices.capabilities.range", instance: "brightness", value: value)
        return SmartLightDeviceState(brightnessPercent: percent, isReachable: true)
    }

    func setColor(deviceID: String, color: SmartLightColor) async throws -> SmartLightDeviceState {
        let r = Int((color.red * 255).rounded())
        let g = Int((color.green * 255).rounded())
        let b = Int((color.blue * 255).rounded())
        try await control(deviceID, type: "devices.capabilities.color_setting", instance: "colorRgb", value: (r << 16) | (g << 8) | b)
        return SmartLightDeviceState(color: color, isReachable: true)
    }

    func setColorTemperature(deviceID: String, kelvin: Int) async throws -> SmartLightDeviceState {
        // Govee v2 API uses "colorTemperatureK" as the instance name (not "colorTemInK").
        try await control(deviceID, type: "devices.capabilities.color_setting", instance: "colorTemperatureK", value: kelvin)
        return SmartLightDeviceState(colorTemperatureKelvin: kelvin, isReachable: true)
    }

    func activateScene(deviceID: String, sceneID: String) async throws -> SmartLightDeviceState {
        guard let sceneValue = Int(sceneID) else {
            throw SmartLightProviderError.invalidConfiguration(
                "'\(sceneID)' is a scene name, but Govee requires a numeric ID (e.g. 1, 2, 3). " +
                "Refresh Devices in Settings — if your device reports scenes, they'll appear as a picker. " +
                "Otherwise find the numeric ID in the Govee app under the device's Effects tab."
            )
        }

        // Govee v2 requires scene value as a nested object {"id": N, "paramId": 0},
        // not a bare integer. Confirmed working on H6010 firmware via API log.
        let id = try splitDeviceID(deviceID)
        let body = GoveeV2ControlRequest(
            requestId: UUID().uuidString,
            payload: .init(
                sku: id.model, device: id.device,
                capability: .init(
                    type: "devices.capabilities.dynamic_scene",
                    instance: "lightScene",
                    value: AnyEncodable(["id": sceneValue, "paramId": 0])
                )
            )
        )
        let _: GoveeV2Response = try await post(path: "/router/api/v1/device/control", body: body)
        return SmartLightDeviceState(activeSceneID: sceneID, isReachable: true)
    }

    // MARK: - Private

    private func splitDeviceID(_ raw: String) throws -> (device: String, model: String) {
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw SmartLightProviderError.invalidConfiguration("The saved Govee device identifier is invalid.")
        }
        return (parts[0], parts[1])
    }

    private func control(_ deviceID: String, type: String, instance: String, value: Int) async throws {
        let id = try splitDeviceID(deviceID)
        let body = GoveeV2ControlRequest(
            requestId: UUID().uuidString,
            payload: .init(sku: id.model, device: id.device,
                           capability: .init(type: type, instance: instance, value: AnyEncodable(value)))
        )
        let _: GoveeV2Response = try await post(path: "/router/api/v1/device/control", body: body)
    }

    private func requiredAPIKey() throws -> String {
        guard let apiKey = SmartLightKeychainStore.shared.loadSecret(profileID: profile.id, kind: .goveeAPIKey),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SmartLightProviderError.secretMissing("Govee API key")
        }
        return apiKey
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        return try await perform(URLRequest(url: url, method: "GET", apiKey: try requiredAPIKey()))
    }

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, method: "POST", apiKey: try requiredAPIKey())
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SmartLightProviderError.transportFailure("Relay received an invalid response from Govee.")
            }
            let envelope = try? JSONDecoder().decode(GoveeV2Response.self, from: data)
            logResponse(request: request, response: http, envelope: envelope, data: data)
            if http.statusCode == 401 || http.statusCode == 403 { throw SmartLightProviderError.invalidAPIKey }
            if http.statusCode == 429 { throw SmartLightProviderError.rateLimited }
            guard (200..<300).contains(http.statusCode) else {
                throw SmartLightProviderError.transportFailure(httpFailureMessage(statusCode: http.statusCode, envelope: envelope))
            }

            // Govee uses HTTP 200 for both success and soft errors.
            // Check the body code field and surface failures as proper errors.
            if let code = envelope?.code, code != 200 {
                let msg = envelope?.message ?? ""
                let isAuthError = code == 401 || code == 403
                    || msg.localizedCaseInsensitiveContains("api key")
                    || msg.localizedCaseInsensitiveContains("api-key")
                if isAuthError {
                    throw SmartLightProviderError.invalidAPIKey
                }
                if code == 429 || (envelope?.message?.localizedCaseInsensitiveContains("too many request") == true) {
                    throw SmartLightProviderError.rateLimited
                }
                let message = envelope?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SmartLightProviderError.transportFailure(
                    "Govee error \(code): \((message?.isEmpty == false ? message : nil) ?? "Unknown error")"
                )
            }

            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as SmartLightProviderError {
            throw error
        } catch {
            if (error as? URLError)?.code == .timedOut { throw SmartLightProviderError.requestTimedOut }
            throw SmartLightProviderError.transportFailure(error.localizedDescription)
        }
    }

    private func logResponse(
        request: URLRequest,
        response: HTTPURLResponse,
        envelope: GoveeV2Response?,
        data: Data
    ) {
        let path = request.url?.path ?? "<unknown>"
        let traceID = response.value(forHTTPHeaderField: "X-Trace-Id")
            ?? response.value(forHTTPHeaderField: "Trace-Id")
            ?? response.value(forHTTPHeaderField: "X-Request-Id")
        let dateHeader = response.value(forHTTPHeaderField: "Date")
        let message = envelope?.message?.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts = ["[Relay] [Govee] \(request.httpMethod ?? "GET") \(path)", "status=\(response.statusCode)"]
        if let code = envelope?.code {
            parts.append("code=\(code)")
        }
        if let message, !message.isEmpty {
            parts.append("message=\(message)")
        }
        if let traceID, !traceID.isEmpty {
            parts.append("trace=\(traceID)")
        }
        if let dateHeader, !dateHeader.isEmpty {
            parts.append("date=\(dateHeader)")
        }
        let body = sanitizedResponseBody(data)
        if !body.isEmpty {
            parts.append("body=\(body)")
        }
        print(parts.joined(separator: " • "))
    }

    private func httpFailureMessage(statusCode: Int, envelope: GoveeV2Response?) -> String {
        let trimmedMessage = envelope?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = envelope?.code {
            if let trimmedMessage, !trimmedMessage.isEmpty {
                return "Govee request failed with status \(statusCode) (code \(code)): \(trimmedMessage)"
            }
            return "Govee request failed with status \(statusCode) (code \(code))."
        }
        if let trimmedMessage, !trimmedMessage.isEmpty {
            return "Govee request failed with status \(statusCode): \(trimmedMessage)"
        }
        return "Govee request failed with status \(statusCode)."
    }
}

private func sanitizedResponseBody(_ data: Data, limit: Int = 400) -> String {
    guard let raw = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return ""
    }

    let collapsed = raw.replacingOccurrences(of: "\n", with: " ")
    if collapsed.count <= limit {
        return collapsed
    }
    return String(collapsed.prefix(limit)) + "…"
}

struct PlaceholderGenericSmartLightProvider: SmartLightProvider {
    let providerType: SmartLightProviderType = .genericFuture
    let profile: SmartLightProfile

    func discoverDevices() async throws -> [SmartLightDevice] {
        []
    }

    func listDevices() async throws -> [SmartLightDevice] {
        []
    }

    func getDeviceState(deviceID: String) async throws -> SmartLightDeviceState {
        throw SmartLightProviderError.notImplemented("The Generic smart-light provider is a placeholder in this build.")
    }

    func setPower(deviceID: String, isOn: Bool) async throws -> SmartLightDeviceState {
        throw SmartLightProviderError.notImplemented("The Generic smart-light provider is a placeholder in this build.")
    }

    func setBrightness(deviceID: String, percent: Double) async throws -> SmartLightDeviceState {
        throw SmartLightProviderError.notImplemented("The Generic smart-light provider is a placeholder in this build.")
    }

    func setColor(deviceID: String, color: SmartLightColor) async throws -> SmartLightDeviceState {
        throw SmartLightProviderError.notImplemented("The Generic smart-light provider is a placeholder in this build.")
    }

    func setColorTemperature(deviceID: String, kelvin: Int) async throws -> SmartLightDeviceState {
        throw SmartLightProviderError.notImplemented("The Generic smart-light provider is a placeholder in this build.")
    }

    func activateScene(deviceID: String, sceneID: String) async throws -> SmartLightDeviceState {
        throw SmartLightProviderError.notImplemented("The Generic smart-light provider is a placeholder in this build.")
    }
}

struct MockSmartLightProvider: SmartLightProvider {
    let providerType: SmartLightProviderType
    let profile: SmartLightProfile
    var devices: [SmartLightDevice]

    func discoverDevices() async throws -> [SmartLightDevice] { devices }
    func listDevices() async throws -> [SmartLightDevice] { devices }

    func getDeviceState(deviceID: String) async throws -> SmartLightDeviceState {
        devices.first { $0.id == deviceID }?.currentState ?? .empty
    }

    func setPower(deviceID: String, isOn: Bool) async throws -> SmartLightDeviceState {
        SmartLightDeviceState(isOn: isOn)
    }

    func setBrightness(deviceID: String, percent: Double) async throws -> SmartLightDeviceState {
        SmartLightDeviceState(brightnessPercent: percent)
    }

    func setColor(deviceID: String, color: SmartLightColor) async throws -> SmartLightDeviceState {
        SmartLightDeviceState(color: color)
    }

    func setColorTemperature(deviceID: String, kelvin: Int) async throws -> SmartLightDeviceState {
        SmartLightDeviceState(colorTemperatureKelvin: kelvin)
    }

    func activateScene(deviceID: String, sceneID: String) async throws -> SmartLightDeviceState {
        SmartLightDeviceState(activeSceneID: sceneID)
    }
}

private enum HueColorSpace {
    nonisolated static func xy(from color: SmartLightColor) -> (x: Double, y: Double) {
        let r = linearize(color.red)
        let g = linearize(color.green)
        let b = linearize(color.blue)
        let x = r * 0.664511 + g * 0.154324 + b * 0.162028
        let y = r * 0.283881 + g * 0.668433 + b * 0.047685
        let z = r * 0.000088 + g * 0.072310 + b * 0.986039
        let total = x + y + z
        guard total > 0 else { return (0.0, 0.0) }
        return (x / total, y / total)
    }

    nonisolated static func rgb(from color: HueLightResource.ColorData) -> SmartLightColor {
        let x = color.xy.x
        let y = color.xy.y
        guard y > 0 else { return SmartLightColor(red: 0, green: 0, blue: 0) }
        let z = 1.0 - x - y
        let Y = 1.0
        let X = (Y / y) * x
        let Z = (Y / y) * z

        var red = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var green = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var blue = X * 0.051713 - Y * 0.121364 + Z * 1.011530

        // Clamp negatives, then normalize so the brightest component = 1.0.
        // Saturated xy values (outside sRGB gamut) can produce components > 1.0
        // without normalization, which causes the color preview to render incorrectly.
        red = max(0, red); green = max(0, green); blue = max(0, blue)
        let maxComponent = max(red, green, blue, 1.0)
        red = gammaCorrect(red / maxComponent)
        green = gammaCorrect(green / maxComponent)
        blue = gammaCorrect(blue / maxComponent)
        return SmartLightColor(red: red, green: green, blue: blue)
    }

    nonisolated private static func linearize(_ value: Double) -> Double {
        value > 0.04045 ? pow((value + 0.055) / 1.055, 2.4) : value / 12.92
    }

    nonisolated private static func gammaCorrect(_ value: Double) -> Double {
        value <= 0.0031308 ? value * 12.92 : (1.055 * pow(value, 1 / 2.4) - 0.055)
    }
}

private struct HueResourceEnvelope<Resource: Decodable>: Decodable {
    var data: [Resource]
}

private struct HueDeviceResource: Decodable {
    struct Metadata: Decodable {
        var name: String
    }

    struct ProductData: Decodable {
        var modelID: String?

        enum CodingKeys: String, CodingKey {
            case modelID = "model_id"
        }
    }

    struct Service: Decodable {
        var rid: String
        var rtype: String
    }

    var id: String
    var metadata: Metadata
    var productData: ProductData
    var services: [Service]
    var group: HueResourceReference?

    enum CodingKeys: String, CodingKey {
        case id
        case metadata
        case productData = "product_data"
        case services
        case group
    }

    var groupID: String? {
        group?.rid
    }

    var lightServiceIDs: [String] {
        services.filter { $0.rtype == "light" }.map(\.rid)
    }
}

private struct HueLightResource: Decodable {
    struct OnState: Decodable { var on: Bool }
    struct Dimming: Decodable { var brightness: Double? }
    struct ColorTemperature: Decodable { var mirek: Int? }
    struct ColorData: Decodable {
        struct XY: Decodable {
            var x: Double
            var y: Double
        }
        var xy: XY
    }

    var id: String
    var on: OnState?
    var dimming: Dimming?
    var colorTemperature: ColorTemperature?
    var color: ColorData?

    enum CodingKeys: String, CodingKey {
        case id
        case on
        case dimming
        case colorTemperature = "color_temperature"
        case color
    }

    var capabilities: Set<SmartLightCapability> {
        var capabilities: Set<SmartLightCapability> = [.power, .stateRead, .toggle]
        if dimming != nil {
            capabilities.insert(.brightness)
        }
        if color != nil {
            capabilities.insert(.color)
        }
        if colorTemperature != nil {
            capabilities.insert(.colorTemperature)
        }
        return capabilities
    }

    var deviceState: SmartLightDeviceState {
        SmartLightDeviceState(
            isOn: on?.on,
            brightnessPercent: dimming?.brightness,
            color: color.flatMap(HueColorSpace.rgb(from:)),
            colorTemperatureKelvin: colorTemperature?.mirek.map { Int((1_000_000.0 / Double(max(1, $0))).rounded()) },
            activeSceneID: nil,
            isReachable: true
        )
    }
}

private struct HueSceneResource: Decodable {
    var id: String
    var metadata: HueSceneMetadata
    var group: HueResourceReference?

    var name: String { metadata.name }
    var groupID: String? { group?.rid }
}

private struct HueSceneMetadata: Decodable {
    var name: String
}

private struct HueResourceReference: Decodable {
    var rid: String
    var rtype: String
}

// MARK: - Govee OpenAPI v2 types

private struct GoveeV2DevicesResponse: Decodable {
    struct Device: Decodable {
        struct Capability: Decodable {
            var type: String
            var instance: String
            var parameters: AnyDecodableValue?
        }
        var sku: String
        var device: String
        var deviceName: String
        var type: String?          // "devices.types.light", "devices.types.group", etc.
        var capabilities: [Capability]?

        var isGroup: Bool {
            if let t = type?.lowercased(), t.contains("group") { return true }
            let s = sku.lowercased()
            return s.contains("group") || s == "basegroup" || s == "samemodegroup"
        }

        /// True when this device is a controllable light or smart plug.
        /// Filters out sensors, appliances (humidifiers, fans, air purifiers, etc.)
        /// and anything else that isn't a light or plug.
        var isLightOrPlug: Bool {
            // Groups always pass — they aggregate lights/plugs.
            if isGroup { return true }

            // Use the explicit type field when available (most reliable).
            if let t = type?.lowercased() {
                return t.contains("light") || t.contains("plug") || t.contains("strip")
            }

            // SKU-based fallback for devices that don't report a type.
            // Govee SKU prefixes: H6xxx/H8xxx/H9xxx = lights, H7xxx = appliances, H5xxx = sensors.
            let prefix = String(sku.prefix(2)).uppercased()
            switch prefix {
            case "H6", "H8", "H9": return true   // lights / strips
            default:
                // Unknown SKU — include by default rather than silently drop.
                let lower = sku.lowercased()
                let isAppliance = lower.contains("humidif") || lower.contains("purif")
                    || lower.contains("fan") || lower.contains("thermo")
                    || lower.contains("sensor") || lower.contains("monitor")
                    || lower.contains("hub") || lower.contains("socket") == false && lower.contains("meter")
                return !isAppliance
            }
        }

        // Capability types that carry selectable scenes/effects.
        private static let sceneCapabilityTypes: Set<String> = [
            "devices.capabilities.dynamic_scene",
            "devices.capabilities.work_mode",
            "devices.capabilities.music_setting",
            "devices.capabilities.segment_color_setting"
        ]

        var derivedCapabilities: Set<SmartLightCapability> {
            var caps: Set<SmartLightCapability> = [.power, .stateRead, .toggle]
            for cap in capabilities ?? [] {
                switch cap.type {
                case "devices.capabilities.range" where cap.instance == "brightness":
                    caps.insert(.brightness)
                case "devices.capabilities.color_setting" where cap.instance == "colorRgb":
                    caps.insert(.color)
                case "devices.capabilities.color_setting"
                     where cap.instance == "colorTemInK" || cap.instance == "colorTemperatureK":
                    caps.insert(.colorTemperature)
                case let t where Self.sceneCapabilityTypes.contains(t):
                    // Add .scene even when options list is empty — Govee returns capabilities
                    // without scene names for many devices; IDs must be fetched separately.
                    caps.insert(.scene)
                default:
                    break
                }
            }
            return caps
        }

        var sceneSummaries: [SmartLightSceneSummary] {
            for capType in Self.sceneCapabilityTypes {
                for cap in capabilities ?? [] where cap.type == capType {
                    let scenes = cap.parameters?.sceneOptions ?? []
                    if !scenes.isEmpty { return scenes }
                }
            }
            return []
        }
    }

    var code: Int?
    var message: String?
    var data: [Device] = []
}

private struct GoveeV2StateResponse: Decodable {
    struct Payload: Decodable {
        struct CapabilityState: Decodable {
            struct StateValue: Decodable {
                var value: AnyDecodableValue?
            }
            var type: String
            var instance: String
            var state: StateValue?
        }
        var sku: String
        var device: String
        var capabilities: [CapabilityState]?

        func toState() -> SmartLightDeviceState {
            var state = SmartLightDeviceState(isReachable: true)
            for cap in capabilities ?? [] {
                switch cap.instance {
                case "powerSwitch":
                    state.isOn = cap.state?.value?.intValue == 1
                case "brightness":
                    state.brightnessPercent = cap.state?.value?.doubleValue
                case "colorTemInK", "colorTemperatureK":
                    state.colorTemperatureKelvin = cap.state?.value?.intValue
                case "colorRgb":
                    if let rgb = cap.state?.value?.intValue, rgb > 0 {
                        let r = Double((rgb >> 16) & 0xFF) / 255.0
                        let g = Double((rgb >> 8) & 0xFF) / 255.0
                        let b = Double(rgb & 0xFF) / 255.0
                        state.color = SmartLightColor(red: r, green: g, blue: b)
                    }
                default:
                    break
                }
            }
            return state
        }
    }

    var code: Int?
    var message: String?
    var data: Payload?  // nil when API returns an error envelope with no data key
}

private struct GoveeV2ControlRequest: Encodable {
    struct Payload: Encodable {
        struct Capability: Encodable {
            var type: String
            var instance: String
            var value: AnyEncodable
        }
        var sku: String
        var device: String
        var capability: Capability
    }
    var requestId: String
    var payload: Payload
}

private struct GoveeV2Response: Decodable {
    var code: Int?
    var message: String?
}

nonisolated struct GoveeDeviceStateResponse: Decodable {
    struct Payload: Decodable {
        struct Property: Decodable {
            var name: String
            var value: AnyDecodableValue

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: DynamicCodingKey.self)
                guard let key = container.allKeys.first else {
                    throw DecodingError.dataCorruptedError(
                        forKey: DynamicCodingKey(stringValue: "property")!,
                        in: container,
                        debugDescription: "Expected a state property entry."
                    )
                }
                name = key.stringValue
                value = try container.decode(AnyDecodableValue.self, forKey: key)
            }
        }

        var properties: [Property]

        func toState() -> SmartLightDeviceState {
            var state = SmartLightDeviceState.empty
            for property in properties {
                switch property.name.lowercased() {
                case "online":
                    state.isReachable = property.value.boolValue
                case "powerstate":
                    state.isOn = property.value.stringValue?.lowercased() == "on"
                case "brightness":
                    state.brightnessPercent = property.value.doubleValue
                case "colortem":
                    state.colorTemperatureKelvin = property.value.intValue
                case "colorteminkelvin":
                    state.colorTemperatureKelvin = property.value.intValue
                case "color":
                    if let dict = property.value.dictionaryValue {
                        let red = Double(dict["r"]?.intValue ?? 0) / 255.0
                        let green = Double(dict["g"]?.intValue ?? 0) / 255.0
                        let blue = Double(dict["b"]?.intValue ?? 0) / 255.0
                        state.color = SmartLightColor(red: red, green: green, blue: blue)
                    }
                default:
                    break
                }
            }
            return state
        }
    }

    var data: Payload
}

private extension URLRequest {
    init(url: URL, method: String, apiKey: String) {
        self.init(url: url, timeoutInterval: 8)
        httpMethod = method
        setValue(apiKey, forHTTPHeaderField: "Govee-API-Key")
        setValue("application/json", forHTTPHeaderField: "Accept")
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        self.encodeValue = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

struct AnyDecodableValue: Decodable {
    var stringValue: String?
    var doubleValue: Double?
    var intValue: Int?
    var boolValue: Bool?
    var dictionaryValue: [String: AnyDecodableValue]?
    var arrayValue: [AnyDecodableValue]?

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let string = try? container.decode(String.self) {
                stringValue = string
                doubleValue = Double(string)
                intValue = Int(string)
                return
            }
            if let int = try? container.decode(Int.self) {
                intValue = int
                doubleValue = Double(int)
                stringValue = String(int)
                return
            }
            if let double = try? container.decode(Double.self) {
                doubleValue = double
                intValue = Int(double)
                stringValue = String(double)
                return
            }
            if let bool = try? container.decode(Bool.self) {
                boolValue = bool
                stringValue = bool ? "true" : "false"
                intValue = bool ? 1 : 0
                doubleValue = bool ? 1 : 0
                return
            }
            if let array = try? container.decode([AnyDecodableValue].self) {
                arrayValue = array
                return
            }
        }
        if let dict = try? decoder.singleValueContainer().decode([String: AnyDecodableValue].self) {
            dictionaryValue = dict
            return
        }
        arrayValue = try decoder.singleValueContainer().decode([AnyDecodableValue].self)
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct HueCatalog {
    var devices: [HueDeviceResource]
    var lightsByID: [String: HueLightResource]
    var scenesByOwner: [String: [HueSceneResource]]
}

private struct HueResolvedLightTarget {
    var lightID: String
    var name: String
    var capabilities: Set<SmartLightCapability>
    var scenes: [SmartLightSceneSummary]
}

private extension SmartLightCapability {
    var userFacingDescription: String {
        switch self {
        case .power:
            return "power control"
        case .brightness:
            return "brightness changes"
        case .color:
            return "color changes"
        case .colorTemperature:
            return "color temperature changes"
        case .scene:
            return "scene activation"
        case .stateRead:
            return "state reads"
        case .toggle:
            return "toggle"
        }
    }
}

private extension AnyDecodableValue {
    var sceneOptions: [SmartLightSceneSummary] {
        if let options = dictionaryValue?["options"]?.arrayValue {
            let mapped = options.compactMap(\.sceneSummary)
            if !mapped.isEmpty {
                return mapped
            }
        }
        return arrayValue?.compactMap(\.sceneSummary) ?? []
    }

    var sceneSummary: SmartLightSceneSummary? {
        if let stringValue, !stringValue.isEmpty {
            return SmartLightSceneSummary(id: stringValue, name: stringValue)
        }
        guard let dictionaryValue else { return nil }

        let name = dictionaryValue["name"]?.stringValue
            ?? dictionaryValue["sceneName"]?.stringValue
            ?? dictionaryValue["label"]?.stringValue

        // value may be a bare int, a string, or a nested object like {"id":1,"paramId":2}.
        // Prefer the most direct numeric identifier for API activation.
        let identifier: String? = {
            if let s = dictionaryValue["value"]?.stringValue, !s.isEmpty { return s }
            // Nested object: {"id": 1, ...}
            if let nested = dictionaryValue["value"]?.dictionaryValue,
               let idStr = nested["id"]?.stringValue, !idStr.isEmpty { return idStr }
            if let s = dictionaryValue["id"]?.stringValue, !s.isEmpty { return s }
            return dictionaryValue["sceneName"]?.stringValue ?? dictionaryValue["name"]?.stringValue
        }()

        guard let resolvedID = identifier, !resolvedID.isEmpty else { return nil }
        let resolvedName = (name?.isEmpty == false ? name : nil) ?? resolvedID
        return SmartLightSceneSummary(id: resolvedID, name: resolvedName)
    }
}
