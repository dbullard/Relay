import CryptoKit
import Foundation
import Security

enum SpecteraClientError: LocalizedError {
    case missingHost
    case authenticationFailed
    case unsupportedVersion(String)
    case certificateTrustRequired(String)
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingHost: "Spectera host missing"
        case .authenticationFailed: "Spectera authentication failed"
        case .unsupportedVersion: "Unsupported Spectera SSCv2 version"
        case .certificateTrustRequired: "Spectera's certificate must be verified and trusted before Relay can connect"
        case .invalidResponse: "Spectera returned invalid monitoring data"
        case .requestFailed(let status): "Spectera request failed (HTTP \(status))"
        }
    }
}

enum SpecteraCertificateTrust {
    static func fingerprint(for certificate: Data) -> String {
        SHA256.hash(data: certificate)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }
}

private final class SpecteraURLSessionDelegate: NSObject, URLSessionDelegate {
    private let trustedCertificate: Data?
    private let lock = NSLock()
    private var untrustedCertificate: Data?
    private var acceptedPinnedCertificate: Data?

    init(trustedCertificate: Data?) {
        self.trustedCertificate = trustedCertificate
    }

    var presentedUntrustedCertificate: Data? {
        lock.lock()
        defer { lock.unlock() }
        return untrustedCertificate
    }

    var acceptedCertificate: Data? {
        lock.lock()
        defer { lock.unlock() }
        return acceptedPinnedCertificate
    }

    var hasPinnedCertificate: Bool { trustedCertificate != nil }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certificateData = SecCertificateCopyData(certificate) as Data
        guard certificateData == trustedCertificate else {
            lock.lock()
            untrustedCertificate = certificateData
            lock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        lock.lock()
        acceptedPinnedCertificate = certificateData
        lock.unlock()
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

@MainActor
final class SpecteraClient {
    static let subscriptionResources = ["/api/mts/paired/all"]

    struct PairedMobileDevice: Decodable, Equatable {
        let mtUID: String
        let name: String
        let isConnected: Bool
        let micAudioLinkID: String?
        let isMicAudioLinkActive: Bool?

        init(
            mtUID: String,
            name: String,
            isConnected: Bool,
            micAudioLinkID: String?,
            isMicAudioLinkActive: Bool? = nil
        ) {
            self.mtUID = mtUID
            self.name = name
            self.isConnected = isConnected
            self.micAudioLinkID = micAudioLinkID
            self.isMicAudioLinkActive = isMicAudioLinkActive
        }

        private enum CodingKeys: String, CodingKey {
            case mtUID = "mtUid", name, isConnected, state
            case micAudioLinkID = "micAudiolinkId"
            case isMicAudioLinkActive = "micAudiolinkActive"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mtUID = try Self.decodeIdentifier(from: container, forKey: .mtUID)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? mtUID
            micAudioLinkID = try Self.decodeOptionalIdentifier(from: container, forKey: .micAudioLinkID)
            isMicAudioLinkActive = try container.decodeIfPresent(Bool.self, forKey: .isMicAudioLinkActive)
            if let connected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) {
                isConnected = connected
            } else {
                isConnected = (try container.decodeIfPresent(String.self, forKey: .state))?.localizedCaseInsensitiveCompare("connected") == .orderedSame
            }
        }

        private static func decodeIdentifier(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> String {
            if let value = try? container.decode(String.self, forKey: key) { return value }
            if let value = try? container.decode(Int64.self, forKey: key) { return String(value) }
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: container.codingPath + [key], debugDescription: "Expected a string or integer identifier")
            )
        }

        private static func decodeOptionalIdentifier(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> String? {
            guard container.contains(key), !(try container.decodeNil(forKey: key)) else { return nil }
            return try decodeIdentifier(from: container, forKey: key)
        }

        var hasActiveMicAudioLink: Bool {
            guard let micAudioLinkID, micAudioLinkID != "-1" else { return false }
            return isMicAudioLinkActive ?? true
        }
    }

    private struct Version: Decodable { let protocolVersion: String; enum CodingKeys: String, CodingKey { case protocolVersion = "protocol" } }

    private var subscriptionTask: Task<Void, Never>?
    private var pendingCertificates: [UUID: Data] = [:]

    private var shouldTrace: Bool {
        WirelessLoggingPreferences.isVerboseSennheiser(forModel: SennheiserNetworkModel.specteraBaseStation.rawValue)
    }

    private func trace(_ message: String) {
        guard shouldTrace else { return }
        RelayDiagnosticsStore.shared.recordSennheiserTrace("spectera \(message)")
    }

    static func makeRequest(host: String, path: String, password: String) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        components.port = 443
        components.path = path
        var request = URLRequest(url: components.url!)
        let token = Data("controlSennheiser:\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func pendingCertificateFingerprint(for deviceID: UUID) -> String? {
        pendingCertificates[deviceID].map(SpecteraCertificateTrust.fingerprint)
    }

    func trustPendingCertificate(for deviceID: UUID) -> Bool {
        guard let certificate = pendingCertificates.removeValue(forKey: deviceID) else { return false }
        SpecteraKeychainStore.shared.setTrustedCertificate(certificate, for: deviceID)
        trace("certificate_trusted fingerprint=\(SpecteraCertificateTrust.fingerprint(for: certificate))")
        return true
    }

    static func makeSnapshots(deviceID: UUID, deviceName: String, pairedDevices: [PairedMobileDevice]) -> [SennheiserChannelSnapshot] {
        let devices = pairedDevices.filter { $0.isConnected && $0.hasActiveMicAudioLink }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return devices.enumerated().map { offset, device in
            SennheiserChannelSnapshot(
                id: "\(deviceID.uuidString)-\(device.mtUID)",
                deviceID: deviceID,
                deviceName: deviceName,
                channelIndex: offset + 1,
                channelRemoteID: device.mtUID,
                channelName: device.name,
                frequencyMHz: nil,
                rfLevel01: nil,
                audioLevel01: nil,
                batteryPercent: nil,
                warnings: [],
                updatedAt: .now
            )
        }
    }

    func refresh(deviceID: UUID, deviceName: String, host: String, password: String) async throws -> [SennheiserChannelSnapshot] {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            trace("refresh_failed reason=missing_host")
            throw SpecteraClientError.missingHost
        }
        trace("refresh_started host=\(host)")
        let version = try await fetch(Version.self, deviceID: deviceID, host: host, path: "/api/ssc/version", password: password)
        guard version.protocolVersion.hasPrefix("2.") else { throw SpecteraClientError.unsupportedVersion(version.protocolVersion) }
        trace("version_verified protocol=\(version.protocolVersion)")
        let devices = try await fetch([PairedMobileDevice].self, deviceID: deviceID, host: host, path: "/api/mts/paired/all", password: password)
        let snapshots = Self.makeSnapshots(deviceID: deviceID, deviceName: deviceName, pairedDevices: devices)
        trace("refresh_succeeded paired_devices=\(devices.count) monitored_mics=\(snapshots.count)")
        return snapshots
    }

    func startSubscription(
        deviceID: UUID,
        host: String,
        password: String,
        onUpdate: @escaping @MainActor () async -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        guard subscriptionTask == nil else { return }
        trace("subscription_starting host=\(host)")
        subscriptionTask = Task { [weak self] in
            await self?.runSubscription(deviceID: deviceID, host: host, password: password, onUpdate: onUpdate, onFailure: onFailure)
        }
    }

    func stop() {
        trace("subscription_stopping")
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    private func runSubscription(
        deviceID: UUID,
        host: String,
        password: String,
        onUpdate: @escaping @MainActor () async -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async {
        defer { subscriptionTask = nil }
        let sessionDelegate = SpecteraURLSessionDelegate(
            trustedCertificate: SpecteraKeychainStore.shared.trustedCertificate(for: deviceID)
        )

        do {
            var request = Self.makeRequest(host: host, path: "/api/ssc/state/subscriptions", password: password)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            let session = URLSession(configuration: .ephemeral, delegate: sessionDelegate, delegateQueue: nil)
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            do {
                try Self.validate(response)
            } catch {
                trace("subscription_stream_rejected status=\(status) error=\(error.localizedDescription)")
                throw error
            }
            tracePinnedCertificateAcceptance(from: sessionDelegate)
            trace("subscription_stream_opened")

            guard let http = response as? HTTPURLResponse,
                  let location = http.value(forHTTPHeaderField: "Content-Location"),
                  !location.isEmpty else {
                throw SpecteraClientError.invalidResponse
            }
            try await addSubscriptionResources(session: session, host: host, location: location, password: password)
            trace("subscription_resources_registered resources=\(Self.subscriptionResources.count)")

            var receivedInitialEvent = false
            for try await line in bytes.lines where !Task.isCancelled {
                guard line.hasPrefix("data:") else { continue }
                if receivedInitialEvent {
                    trace("subscription_update_received")
                    await onUpdate()
                } else {
                    receivedInitialEvent = true
                    trace("subscription_initial_event_received")
                }
            }

            if !Task.isCancelled {
                trace("subscription_closed")
                onFailure("Spectera live subscription closed")
            }
        } catch {
            let reportedError = untrustedCertificateError(for: deviceID, delegate: sessionDelegate) ?? error
            if !Task.isCancelled {
                trace("subscription_failed error=\(reportedError.localizedDescription)")
                onFailure(reportedError.localizedDescription)
            }
        }
    }

    private func addSubscriptionResources(session: URLSession, host: String, location: String, password: String) async throws {
        let path: String
        if let url = URL(string: location), url.scheme != nil {
            path = url.path
        } else {
            path = location
        }
        var request = Self.makeRequest(host: host, path: "\(path)/add", password: password)
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(Self.subscriptionResources)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            try Self.validate(response)
        } catch {
            trace("subscription_resource_registration_rejected status=\(status) error=\(error.localizedDescription)")
            throw error
        }
        trace("subscription_resource_registration_succeeded status=\(status)")
    }

    private func fetch<T: Decodable>(_ type: T.Type, deviceID: UUID, host: String, path: String, password: String) async throws -> T {
        trace("request_started path=\(path)")
        let sessionDelegate = SpecteraURLSessionDelegate(
            trustedCertificate: SpecteraKeychainStore.shared.trustedCertificate(for: deviceID)
        )
        do {
            let session = URLSession(configuration: .ephemeral, delegate: sessionDelegate, delegateQueue: nil)
            let (data, response) = try await session.data(for: Self.makeRequest(host: host, path: path, password: password))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            do {
                try Self.validate(response)
            } catch {
                trace("request_rejected path=\(path) status=\(status) error=\(error.localizedDescription)")
                throw error
            }
            tracePinnedCertificateAcceptance(from: sessionDelegate)
            trace("request_succeeded path=\(path) status=\(status)")
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch {
                trace("request_invalid_json path=\(path)")
                throw SpecteraClientError.invalidResponse
            }
        } catch {
            let reportedError = untrustedCertificateError(for: deviceID, delegate: sessionDelegate) ?? error
            trace("request_failed path=\(path) error=\(reportedError.localizedDescription)")
            throw reportedError
        }
    }

    private func untrustedCertificateError(
        for deviceID: UUID,
        delegate: SpecteraURLSessionDelegate
    ) -> SpecteraClientError? {
        guard let certificate = delegate.presentedUntrustedCertificate else { return nil }
        pendingCertificates[deviceID] = certificate
        let fingerprint = SpecteraCertificateTrust.fingerprint(for: certificate)
        let event = delegate.hasPinnedCertificate ? "certificate_changed" : "certificate_first_seen"
        trace("\(event) fingerprint=\(fingerprint)")
        return .certificateTrustRequired(fingerprint)
    }

    private func tracePinnedCertificateAcceptance(from delegate: SpecteraURLSessionDelegate) {
        guard let certificate = delegate.acceptedCertificate else { return }
        trace("certificate_pin_accepted fingerprint=\(SpecteraCertificateTrust.fingerprint(for: certificate))")
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw SpecteraClientError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw SpecteraClientError.authenticationFailed }
        guard (200...299).contains(http.statusCode) else { throw SpecteraClientError.requestFailed(http.statusCode) }
    }
}
