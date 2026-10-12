//
//  ResolumeEndpoint.swift
//  Relay
//
//  Created by David Bullard on 12/17/25.
//

//
//  ResolumeConnection.swift
//  Relay
//
//  REST API connection + polling wrapper for Resolume Arena/Avenue.
//  This file is intentionally “connection only” (no Dashboard UI).
//

import Foundation
import Combine

// MARK: - Public Types

@preconcurrency public struct ResolumeEndpoint: Hashable, Codable {
    public var host: String
    public var port: Int

    public init(host: String, port: Int = 8080) {
        self.host = host
        self.port = port
    }

    public var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }

    public var display: String { "\(host):\(port)" }
}

public enum ResolumeConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case error(String)
}

public enum ResolumeHTTPMethod: String {
    case GET, POST, PUT, PATCH, DELETE
}

/// A lightweight “snapshot” object you can use in your module view.
/// Keep this flexible—Resolume’s JSON varies by endpoint/version.
public struct ResolumeSnapshot: Equatable {
    public var lastUpdated: Date = .init()
    public var compositionName: String?
    public var rawJSONPreview: String?
}

// MARK: - Core Connection (Actor)

public actor ResolumeConnectionCore {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    public init() {}

    public func requestData(
        endpoint: ResolumeEndpoint,
        path: String,
        method: ResolumeHTTPMethod = .GET,
        query: [URLQueryItem] = [],
        body: Encodable? = nil,
        timeout: TimeInterval = 4.0
    ) async throws -> Data {
        let (host, port) = await MainActor.run { (endpoint.host, endpoint.port) }
        guard let base = URL(string: "http://\(host):\(port)") else {
            throw URLError(.badURL)
        }

        // NOTE: Keep path handling simple/robust.
        // If caller passes "/api/v1/..." we should accept it.
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/" + cleanPath
        if !query.isEmpty { components?.queryItems = query }

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let bodyData = try await MainActor.run {
                let encoder = JSONEncoder()
                return try encoder.encode(AnyEncodable(body))
            }
            req.httpBody = bodyData
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let preview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw ResolumeHTTPError(statusCode: http.statusCode, responsePreview: preview)
        }

        return data
    }

    public func requestJSON<T: Decodable>(
        _ type: T.Type,
        endpoint: ResolumeEndpoint,
        path: String,
        method: ResolumeHTTPMethod = .GET,
        query: [URLQueryItem] = [],
        body: Encodable? = nil
    ) async throws -> T {
        let data = try await requestData(endpoint: endpoint, path: path, method: method, query: query, body: body)
        return try decoder.decode(T.self, from: data)
    }

    public func requestJSONObject(
        endpoint: ResolumeEndpoint,
        path: String,
        method: ResolumeHTTPMethod = .GET,
        query: [URLQueryItem] = [],
        body: Encodable? = nil
    ) async throws -> Any {
        let data = try await requestData(endpoint: endpoint, path: path, method: method, query: query, body: body)
        return try JSONSerialization.jsonObject(with: data, options: [])
    }
}

public struct ResolumeHTTPError: LocalizedError {
    public let statusCode: Int
    public let responsePreview: String

    public var errorDescription: String? {
        "Resolume HTTP \(statusCode): \(responsePreview)"
    }
}


// MARK: - Profiles Store (Shared)

public typealias ResolumeConnectionProfile = ResolumeProfilesStore.Profile

/// Stores multiple Resolume connection profiles (similar to ProPresenter profiles).
/// This is intentionally kept in the connection layer so both Settings + Modules can reuse it.
@MainActor
public final class ResolumeProfilesStore: ObservableObject {
    public static let shared = ResolumeProfilesStore()

    public struct Profile: Identifiable, Hashable, Codable {
        public var id: UUID
        public var name: String
        public var endpoint: ResolumeEndpoint
        public var isEnabled: Bool

        public init(id: UUID = UUID(), name: String, endpoint: ResolumeEndpoint, isEnabled: Bool = true) {
            self.id = id
            self.name = name
            self.endpoint = endpoint
            self.isEnabled = isEnabled
        }

        /// Convenience init used by Settings “Add Profile” sheets.
        public init() {
            self.init(
                id: UUID(),
                name: "",
                endpoint: ResolumeEndpoint(host: "127.0.0.1", port: 8080),
                isEnabled: true
            )
        }

        public var displayHostPort: String { "\(host):\(port)" }

        // Convenience so Settings UI can bind to host/port directly.
        public var host: String {
            get { endpoint.host }
            set { endpoint.host = newValue }
        }

        public var port: Int {
            get { endpoint.port }
            set { endpoint.port = newValue }
        }

        // Backward-compatible decoding (older saved profiles won't have isEnabled).
        private enum CodingKeys: String, CodingKey {
            case id, name, endpoint, isEnabled
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(UUID.self, forKey: .id)
            self.name = try c.decode(String.self, forKey: .name)
            self.endpoint = try c.decode(ResolumeEndpoint.self, forKey: .endpoint)
            self.isEnabled = (try c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(endpoint, forKey: .endpoint)
            try c.encode(isEnabled, forKey: .isEnabled)
        }
    }

    @Published public var profiles: [Profile] = [] {
        didSet { save() }
    }

    /// Selected profile id for modules (Settings can change this, modules can override).
    @Published public var selectedProfileID: UUID? {
        didSet { save() }
    }

    private let storageKey = "Relay.ResolumeProfilesStore.v1"

    private init() {
        load()
        // If nothing exists, create a safe placeholder (localhost:8080)
        if profiles.isEmpty {
            profiles = [Profile(name: "Localhost", endpoint: ResolumeEndpoint(host: "127.0.0.1", port: 8080), isEnabled: true)]
            selectedProfileID = profiles.first?.id
        } else if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
        }
    }

    public var selectedProfile: Profile? {
        guard let id = selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    public func upsert(_ profile: Profile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
    }

    public func remove(id: UUID) {
        profiles.removeAll(where: { $0.id == id })
        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }
    }

    fileprivate func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode(Persisted.self, from: data)
            self.profiles = decoded.profiles
            self.selectedProfileID = decoded.selectedProfileID
        } catch {
            // If decode fails, start fresh.
            self.profiles = []
            self.selectedProfileID = nil
        }
    }

    fileprivate func save() {
        do {
            let persisted = Persisted(profiles: profiles, selectedProfileID: selectedProfileID)
            let data = try JSONEncoder().encode(persisted)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Ignore save failures.
        }
    }

    private struct Persisted: Codable {
        var profiles: [Profile]
        var selectedProfileID: UUID?
    }

    // MARK: Public Persistence API (used by Settings UI)

    public func loadFromDisk() {
        load()
    }

    public func saveToDisk() {
        save()
    }

    // MARK: Lookup Helpers

    public func endpoint(for id: UUID?) -> ResolumeEndpoint? {
        guard let id else { return nil }
        return profiles.first(where: { $0.id == id })?.endpoint
    }

    public func profileName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return profiles.first(where: { $0.id == id })?.name
    }
}

// MARK: - Observable Wrapper (for SwiftUI / modules)

@MainActor
public final class ResolumeConnection: ObservableObject {
    public static let shared = ResolumeConnection()

    /// Shared profiles configured in Settings → Resolume.
    public let profilesStore = ResolumeProfilesStore.shared

    @Published public private(set) var state: ResolumeConnectionState = .idle
    @Published public private(set) var snapshot: ResolumeSnapshot = .init()

    private let core = ResolumeConnectionCore()

    private var pollTask: Task<Void, Never>?
    private var currentEndpoint: ResolumeEndpoint?

    private init() {}

    // MARK: Logging

    public var isLoggingEnabled: Bool = true
    private func log(_ msg: String) {
        guard isLoggingEnabled else { return }
        print("[Resolume] \(msg)")
    }

    // MARK: Public API

    public func connect(endpoint: ResolumeEndpoint) {
        currentEndpoint = endpoint
        state = .connecting
        log("Connecting to \(endpoint.display)")
        // We don’t “open a socket” here—REST is stateless—so just mark idle/connected after first successful poll.
    }

    public func disconnect() {
        stopPolling()
        currentEndpoint = nil
        state = .idle
        snapshot = .init()
        log("Disconnected")
    }

    public func startPolling(intervalSeconds: Double = 0.5, compositionPath: String = "/api/v1/composition") {
        stopPolling()

        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce(compositionPath: compositionPath)
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, intervalSeconds)) * 1_000_000_000)
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Generic “fire a control call” helper (useful for triggering clips/params).
    public func send(
        path: String,
        method: ResolumeHTTPMethod = .POST,
        query: [URLQueryItem] = [],
        body: Encodable? = nil
    ) async {
        guard let endpoint = currentEndpoint else {
            log("Send skipped (no endpoint). path=\(path)")
            return
        }

        do {
            _ = try await core.requestData(endpoint: endpoint, path: path, method: method, query: query, body: body)
            log("Send OK \(endpoint.display) \(method.rawValue) \(path)")
        } catch {
            log("Send FAILED \(endpoint.display) \(method.rawValue) \(path) err=\(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    // MARK: Poll

    private func pollOnce(compositionPath: String) async {
        guard let endpoint = currentEndpoint else { return }

        do {
            let obj = try await core.requestJSONObject(endpoint: endpoint, path: compositionPath)
            let pretty = Self.prettyJSON(obj) ?? "<json>"
            let name = Self.extractPossibleName(obj)

            snapshot = ResolumeSnapshot(
                lastUpdated: Date(),
                compositionName: name,
                rawJSONPreview: String(pretty.prefix(800))
            )

            if case .connected = state {
                // ok
            } else {
                state = .connected
                log("Connected ✓ \(endpoint.display)")
            }

        } catch {
            let msg = error.localizedDescription
            state = .error(msg)
            log("Poll FAILED \(endpoint.display) path=\(compositionPath) err=\(msg)")
        }
    }

    // MARK: Helpers

    private static func prettyJSON(_ obj: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    /// Resolume’s schema can vary. We try a few common keys without crashing.
    private static func extractPossibleName(_ obj: Any) -> String? {
        guard let dict = obj as? [String: Any] else { return nil }

        // Try common candidates. Adjust as you confirm actual keys.
        let candidates: [String] = [
            "name",
            "title",
            "compositionName",
            "composition",
            "label"
        ]

        for key in candidates {
            if let s = dict[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
        }

        // Sometimes nested:
        if let comp = dict["composition"] as? [String: Any] {
            for key in candidates {
                if let s = comp[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
        }

        return nil
    }
}

// MARK: - AnyEncodable

@preconcurrency private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self._encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
