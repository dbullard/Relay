//
//  ProPresenterConnection.swift
//  Relay
//
//  Created by David Bullard on 12/16/25.
//

import Foundation
import Network
import SwiftUI

// MARK: - Shared Settings (global defaults)

/// Matches the @AppStorage keys used in DashboardSettingsView.swift
struct ProPresenterGlobalConnectionSettings: Equatable {
    var host: String
    var port: Int
    var password: String
    var pollInterval: TimeInterval

    static func loadFromAppStorage() -> ProPresenterGlobalConnectionSettings {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: "propresenter_host") ?? ""
        let port = defaults.object(forKey: "propresenter_port") as? Int ?? 1025
        let password = ProPresenterKeychainStore.shared.password
        let pollInterval = defaults.object(forKey: "propresenter_pollInterval") as? Double ?? 0.5

        return .init(
            host: host,
            port: port,
            password: password,
            pollInterval: pollInterval
        )
    }

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && port > 0 && port < 65536
    }
}

private enum ProPresenterHostParser {
    static func normalize(host: String, port: Int) -> (host: String, port: Int) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", port) }

        if let components = URLComponents(string: trimmed), let parsedHost = components.host {
            let parsedPort = components.port ?? port
            return (parsedHost, parsedPort)
        }

        if let components = URLComponents(string: "http://\(trimmed)"), let parsedHost = components.host {
            let parsedPort = components.port ?? port
            return (parsedHost, parsedPort)
        }

        var raw = trimmed
        if let slashIndex = raw.firstIndex(of: "/") {
            raw = String(raw[..<slashIndex])
        }

        if raw.hasPrefix("[") {
            if let end = raw.firstIndex(of: "]") {
                let hostPart = String(raw[raw.index(after: raw.startIndex)..<end])
                let remainder = raw[raw.index(after: end)...]
                if remainder.hasPrefix(":"),
                   let parsedPort = Int(remainder.dropFirst()),
                   port == 0 || port == 1025 || port == parsedPort {
                    return (hostPart, parsedPort)
                }
                return (hostPart, port)
            }
        }

        if raw.filter({ $0 == ":" }).count == 1, let colonIndex = raw.lastIndex(of: ":") {
            let hostPart = String(raw[..<colonIndex])
            let portPart = String(raw[raw.index(after: colonIndex)...])
            if let parsedPort = Int(portPart), port == 0 || port == 1025 || port == parsedPort {
                return (hostPart, parsedPort)
            }
        }

        return (raw, port)
    }
}

// MARK: - Profiles Store (UserDefaults)

/// Shared store for the ProPresenter saved connection profiles created in DashboardProPresenterSettingsView.
///
/// Modules can use this to resolve a specific profile by UUID so multiple ProPresenters can be connected
/// simultaneously (one per module).
enum ProPresenterProfilesStore {
    // Storage keys shared with DashboardProPresenterSettingsView
    static let profilesKey = "propresenter_profiles"
    static let activeProfileIDKey = "propresenter_activeProfileID"

    static func loadProfiles(from defaults: UserDefaults = .standard) -> [ProPresenterConnectionProfile] {
        guard let data = defaults.data(forKey: profilesKey), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ProPresenterConnectionProfile].self, from: data)) ?? []
    }

    static func loadProfile(id: UUID, from defaults: UserDefaults = .standard) -> ProPresenterConnectionProfile? {
        loadProfiles(from: defaults).first(where: { $0.id == id })
    }

    static func activeProfileID(from defaults: UserDefaults = .standard) -> UUID? {
        guard let s = defaults.string(forKey: activeProfileIDKey) else { return nil }
        return UUID(uuidString: s)
    }

    static func activeProfile(from defaults: UserDefaults = .standard) -> ProPresenterConnectionProfile? {
        guard let id = activeProfileID(from: defaults) else { return nil }
        return loadProfile(id: id, from: defaults)
    }

    /// Resolves a configured profile id to its canonical identity, applying the same
    /// "fall back to the active profile" rule init(profileID:) already uses for live
    /// connections -- but returning just the UUID identity (which may itself be nil if
    /// there's no active profile either), so two different configured profile ids can be
    /// compared for whether they refer to the same effective ProPresenter connection.
    static func resolvedProfileIdentity(configuredProfileId: UUID?, from defaults: UserDefaults = .standard) -> UUID? {
        if let id = configuredProfileId, loadProfile(id: id, from: defaults) != nil {
            return id
        }
        return activeProfile(from: defaults)?.id
    }
}

extension ProPresenterGlobalConnectionSettings {
    /// Load settings for a specific saved connection profile.
    static func loadProfile(id: UUID, defaults: UserDefaults = .standard) -> ProPresenterGlobalConnectionSettings? {
        guard let p = ProPresenterProfilesStore.loadProfile(id: id, from: defaults) else { return nil }
        let pollInterval = defaults.object(forKey: "propresenter_pollInterval") as? Double ?? 0.5
        return .init(host: p.host, port: p.port, password: p.password, pollInterval: pollInterval)
    }

    /// Load settings for the ACTIVE profile (if selected), otherwise fall back to the global host/port/password keys.
    static func loadActiveOrGlobal(defaults: UserDefaults = .standard) -> ProPresenterGlobalConnectionSettings {
        if let p = ProPresenterProfilesStore.activeProfile(from: defaults) {
            let pollInterval = defaults.object(forKey: "propresenter_pollInterval") as? Double ?? 0.5
            return .init(host: p.host, port: p.port, password: p.password, pollInterval: pollInterval)
        }
        return loadFromAppStorage()
    }
}

enum ProPresenterTransport: String, CaseIterable, Codable {
    case auto
    case http
    case tcpip
}

// MARK: - HTTP Client

struct ProPresenterHTTPClient {
    let host: String
    let port: Int
    let password: String?

    private var baseURL: URL? {
        // If ProPresenter supports https in your environment, we can add that later.
        URL(string: "http://\(host):\(port)/")
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        timeout: TimeInterval = 2.0
    ) async throws -> T {
        guard let baseURL else { throw URLError(.badURL) }
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appendingPathComponent(trimmedPath)

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        // If ProPresenter uses a specific auth header, wire it here.
        // Some installs may use password/auth endpoints instead; keep optional.
        if let password, !password.isEmpty {
            req.setValue(password, forHTTPHeaderField: "X-ProPresenter-Password")
        }

        if let bodyData = try encodedBodyData(body) {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProPresenterConnectionError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let sanitized = sanitizedJSONData(data),
               let decoded = try? JSONDecoder().decode(T.self, from: sanitized) {
                return decoded
            }
            let preview = String(data: data.prefix(300), encoding: .utf8)
            throw ProPresenterConnectionError.decoding(preview)
        }
    }

    private func sanitizedJSONData(_ data: Data) -> Data? {
        var trimmed = data
        if trimmed.count >= 3, trimmed[0] == 0xEF, trimmed[1] == 0xBB, trimmed[2] == 0xBF {
            trimmed = trimmed.dropFirst(3)
        }
        guard let text = String(data: trimmed, encoding: .utf8) else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = cleaned.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start <= end else {
            return nil
        }
        let json = String(cleaned[start...end])
        return json.data(using: .utf8)
    }

    func requestVoid(
        _ path: String,
        method: String = "POST",
        body: Encodable? = nil,
        timeout: TimeInterval = 2.0
    ) async throws {
        guard let baseURL else { throw URLError(.badURL) }
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appendingPathComponent(trimmedPath)

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let password, !password.isEmpty {
            req.setValue(password, forHTTPHeaderField: "X-ProPresenter-Password")
        }

        if let bodyData = try encodedBodyData(body) {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData
        }

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProPresenterConnectionError.httpStatus(http.statusCode, nil)
        }
    }

    private func encodedBodyData(_ body: Encodable?) throws -> Data? {
        guard let body else { return nil }
        let data = try JSONEncoder().encode(AnyEncodable(body))
        guard let json = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              json != "null" else {
            return nil
        }
        return data
    }
}

enum ProPresenterSettingsConnectionProbe {
    static func testHTTP(host: String, port: Int, password: String, timeout: TimeInterval = 2.0) async throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw URLError(.badURL)
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = trimmedHost
        components.port = port
        components.path = "/v1/status/slide"
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        if !password.isEmpty {
            req.setValue(password, forHTTPHeaderField: "X-ProPresenter-Password")
        }

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "ProPresenter", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"
            ])
        }
    }

    static func testTCPBridge(host: String, port: Int) async throws {
        let reqLine = #"{\"url\":\"v1/status/slide\",\"method\":\"GET\",\"chunked\":false}"#

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 1025
            let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
            let queue = DispatchQueue(label: "ProPresenterTCPBridgeTest")

            // Owns the one-shot "have we already resumed?" flag. NWConnection invokes
            // its handlers on `queue`, and the timeout fallback below can race with them,
            // so the flag itself must live behind an actor rather than a plain captured var.
            let finishState = TransportEventState()
            let finish: @Sendable (Result<Void, Error>) -> Void = { result in
                Task {
                    guard await finishState.finishIfNeeded() else { return }
                    conn.cancel()
                    switch result {
                    case .success:
                        cont.resume()
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let payload = (reqLine + "\r\n").data(using: .utf8) ?? Data()
                    conn.send(content: payload, completion: .contentProcessed { sendErr in
                        if let sendErr { finish(.failure(sendErr)); return }

                        conn.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { data, _, _, recvErr in
                            if let recvErr { finish(.failure(recvErr)); return }
                            guard let data, !data.isEmpty else {
                                finish(.failure(NSError(domain: "ProPresenter", code: -1, userInfo: [
                                    NSLocalizedDescriptionKey: "No response"
                                ])))
                                return
                            }
                            finish(.success(()))
                        }
                    })

                case .failed(let err):
                    finish(.failure(err))
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + 2.0) {
                finish(.failure(NSError(domain: "ProPresenter", code: -1001, userInfo: [
                    NSLocalizedDescriptionKey: "Timed out"
                ])))
            }

            conn.start(queue: queue)
        }
    }
}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

// MARK: - TCP/IP JSON Bridge (line-delimited)

/// ProPresenter TCP/IP bridge format:
/// Send one JSON object per line, terminated with CRLF.
/// Receive one JSON object per line, terminated with CRLF.
///
/// Example request shape:
/// { "url":"v1/...", "method":"GET", "body":{...}, "chunked":false }
nonisolated struct ProPresenterTCPBridgeRequest<Body: Encodable>: Encodable {
    var url: String
    var method: String?
    var body: Body?
    var chunked: Bool?

    init(url: String, method: String? = nil, body: Body? = nil, chunked: Bool? = nil) {
        self.url = url
        self.method = method
        self.body = body
        self.chunked = chunked
    }
}

/// If you want typed responses, decode into your own structs.
/// The bridge tends to respond with JSON objects/arrays depending on endpoint.
/// Owns its connection, receive buffer, and state as actor-isolated storage.
///
/// This client is not currently instantiated anywhere in the app (no live call sites),
/// but it was previously a plain class whose public API (`connect`/`disconnect`/`send`)
/// mutated `connection`/`lineBuffer`/`state` directly on the caller's thread, while
/// `NWConnection`'s callbacks mutated the same storage on `queue` -- a genuine
/// cross-domain data race the moment this got wired up. Actor isolation removes that
/// hazard structurally rather than relying on callers to happen to stay on one queue.
/// The line-buffering here (accumulate, then drain up to the last newline while keeping
/// the remainder) is a distinct shape from `TransportEventState`'s "append/take-everything"
/// contract, so it stays local to this actor rather than being forced into the shared type.
actor ProPresenterTCPBridgeClient {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private let queue = DispatchQueue(label: "ProPresenterTCPBridgeClient")
    private var connection: NWConnection?
    private var lineBuffer = Data()

    private(set) var state: State = .disconnected {
        didSet { onStateChange?(state) }
    }

    var onStateChange: ((State) -> Void)?
    var onLineJSON: ((Data) -> Void)?
    var onLineText: ((String) -> Void)?

    func connect(host: String, port: Int) {
        disconnect()

        state = .connecting
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 1025
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] newState in
            Task { await self?.handleStateUpdate(newState) }
        }

        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        lineBuffer.removeAll(keepingCapacity: true)
        state = .disconnected
    }

    func send<Body: Encodable>(_ req: ProPresenterTCPBridgeRequest<Body>) throws {
        guard let conn = connection else { throw ProPresenterConnectionError.notConnected }
        let data = try JSONEncoder().encode(req)
        sendRawLine(data: data, on: conn)
    }

    func sendRawLine(string: String) throws {
        guard let conn = connection else { throw ProPresenterConnectionError.notConnected }
        guard let data = string.data(using: .utf8) else { return }
        sendRawLine(data: data, on: conn)
    }

    private func sendRawLine(data: Data, on conn: NWConnection) {
        // CRLF line terminator
        var payload = Data()
        payload.append(data)
        payload.append(contentsOf: [0x0D, 0x0A])

        conn.send(content: payload, completion: .contentProcessed { _ in })
    }

    private func handleStateUpdate(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            state = .connected
            startReceiveLoop()
        case .failed(let err):
            state = .failed(err.localizedDescription)
        case .cancelled:
            state = .disconnected
        default:
            break
        }
    }

    private func startReceiveLoop() {
        guard let conn = connection else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { [weak self] data, _, isComplete, error in
            Task { await self?.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            state = .failed(error.localizedDescription)
            return
        }

        if let data, !data.isEmpty {
            ingest(data: data)
        }

        if isComplete {
            state = .disconnected
            return
        }

        // loop
        startReceiveLoop()
    }

    private func ingest(data: Data) {
        lineBuffer.append(data)

        // Split on LF; tolerate CRLF.
        while let range = lineBuffer.firstRange(of: Data([0x0A])) {
            let lineData = lineBuffer.subdata(in: 0..<range.lowerBound)
            lineBuffer.removeSubrange(0..<range.upperBound)

            let trimmed = trimCR(from: lineData)
            guard !trimmed.isEmpty else { continue }

            onLineJSON?(trimmed)
            if let s = String(data: trimmed, encoding: .utf8) {
                onLineText?(s)
            }
        }
    }

    private func trimCR(from data: Data) -> Data {
        if data.last == 0x0D { // CR
            return data.dropLast()
        }
        return data
    }
}

struct ProPresenterRequestOptions: Equatable {
    /// If true, when an HTTP request fails, we will attempt the TCP/IP JSON bridge as a fallback.
    var allowTCPFallback: Bool = true

    /// If true, attempt TCP first, then HTTP fallback.
    var preferTCP: Bool = false

    /// Total timeout (seconds) applied to HTTP request and to TCP fallback attempt.
    var timeout: TimeInterval = 2.0

    static let defaultTimeout: TimeInterval = 2.0
    static let defaultOptions = ProPresenterRequestOptions()
    static let tcpPreferred = ProPresenterRequestOptions(allowTCPFallback: true, preferTCP: true, timeout: 2.0)
}

struct ProPresenterTCPBridgeOneShot {
    static func request<T: Decodable>(
        host: String,
        port: Int,
        path: String,
        method: String = "GET",
        bodyJSON: String? = nil,
        timeout: TimeInterval = 2.0
    ) async throws -> T {
        let urlPath = path.hasPrefix("v1/") ? path : (path.hasPrefix("/") ? String(path.dropFirst()) : path)

        var line = "{\"url\":\"\(urlPath)\",\"method\":\"\(method)\",\"chunked\":false"
        if let bodyJSON, !bodyJSON.isEmpty {
            line += ",\"body\":\(bodyJSON)"
        }
        line += "}"

        let responseData = try await roundTrip(host: host, port: port, requestLine: line, timeout: timeout)
        do {
            return try JSONDecoder().decode(T.self, from: responseData)
        } catch {
            if let sanitized = sanitizedJSONData(responseData),
               let decoded = try? JSONDecoder().decode(T.self, from: sanitized) {
                return decoded
            }
            let preview = String(data: responseData.prefix(300), encoding: .utf8)
            throw ProPresenterConnectionError.decoding(preview)
        }
    }

    private static func sanitizedJSONData(_ data: Data) -> Data? {
        var trimmed = data
        if trimmed.count >= 3, trimmed[0] == 0xEF, trimmed[1] == 0xBB, trimmed[2] == 0xBF {
            trimmed = trimmed.dropFirst(3)
        }
        guard let text = String(data: trimmed, encoding: .utf8) else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = cleaned.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start <= end else {
            return nil
        }
        let json = String(cleaned[start...end])
        return json.data(using: .utf8)
    }

    static func requestVoid(
        host: String,
        port: Int,
        path: String,
        method: String = "POST",
        bodyJSON: String? = nil,
        timeout: TimeInterval = 2.0
    ) async throws {
        struct Empty: Decodable {}
        _ = try await request(host: host, port: port, path: path, method: method, bodyJSON: bodyJSON, timeout: timeout) as Empty
    }

    private static func roundTrip(
        host: String,
        port: Int,
        requestLine: String,
        timeout: TimeInterval
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 1025
            let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
            let queue = DispatchQueue(label: "ProPresenterTCPBridgeOneShot")

            // Owns the one-shot "have we already resumed?" flag. NWConnection invokes
            // its handlers on `queue`, and the timeout fallback below can race with them,
            // so the flag itself must live behind an actor rather than a plain captured var.
            let finishState = TransportEventState()
            let finish: @Sendable (Result<Data, Error>) -> Void = { result in
                Task {
                    guard await finishState.finishIfNeeded() else { return }
                    conn.cancel()
                    switch result {
                    case .success(let data):
                        cont.resume(returning: data)
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let payload = (requestLine + "\r\n").data(using: .utf8) ?? Data()
                    conn.send(content: payload, completion: .contentProcessed { sendErr in
                        if let sendErr { finish(.failure(sendErr)); return }
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { data, _, _, recvErr in
                            if let recvErr { finish(.failure(recvErr)); return }
                            guard let data, !data.isEmpty else {
                                finish(.failure(NSError(domain: "ProPresenter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])) )
                                return
                            }
                            // Best-effort: trim trailing CRLF if present.
                            var trimmed = data
                            while trimmed.last == 0x0A || trimmed.last == 0x0D { trimmed.removeLast() }
                            finish(.success(trimmed))
                        }
                    })
                case .failed(let err):
                    finish(.failure(err))
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(NSError(domain: "ProPresenter", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Timed out"])) )
            }

            conn.start(queue: queue)
        }
    }
}

// MARK: - Convenience “Client Wrapper” used by modules/services

struct ProPresenterConnection {
    let settings: ProPresenterGlobalConnectionSettings
    var options: ProPresenterRequestOptions = .defaultOptions

    static func normalizeHostAndPort(host: String, port: Int) -> (host: String, port: Int) {
        ProPresenterHostParser.normalize(host: host, port: port)
    }

    /// Convenience initializer to target a specific saved connection profile.
    /// - Parameters:
    ///   - profileID: UUID of the saved profile. If nil or not found, falls back to ACTIVE profile or global settings.
    ///   - options: request options for timeouts and TCP fallback.
    init(profileID: UUID?, options: ProPresenterRequestOptions = .defaultOptions) {
        let rawSettings: ProPresenterGlobalConnectionSettings
        if let id = profileID,
           ProPresenterProfilesStore.loadProfile(id: id) != nil {
            rawSettings = ProPresenterGlobalConnectionSettings.loadProfile(id: id) ?? ProPresenterGlobalConnectionSettings.loadActiveOrGlobal()
        } else {
            rawSettings = ProPresenterGlobalConnectionSettings.loadActiveOrGlobal()
        }

        let normalized = ProPresenterHostParser.normalize(host: rawSettings.host, port: rawSettings.port)
        self.settings = ProPresenterGlobalConnectionSettings(
            host: normalized.host,
            port: normalized.port,
            password: rawSettings.password,
            pollInterval: rawSettings.pollInterval
        )

        self.options = options
    }

    private var http: ProPresenterHTTPClient {
        ProPresenterHTTPClient(
            host: settings.host,
            port: settings.port,
            password: settings.password.isEmpty ? nil : settings.password
        )
    }

    /// HTTP-first request, with optional TCP/IP bridge fallback.
    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        let bodyJSON = serializedBodyJSON(body)

        if options.preferTCP {
            do {
                return try await ProPresenterTCPBridgeOneShot.request(
                    host: settings.host,
                    port: settings.port,
                    path: path,
                    method: method,
                    bodyJSON: bodyJSON,
                    timeout: options.timeout
                )
            } catch {
                return try await http.request(path, method: method, body: body, timeout: options.timeout)
            }
        }

        do {
            return try await http.request(path, method: method, body: body, timeout: options.timeout)
        } catch {
            guard options.allowTCPFallback, shouldAttemptTCPFallback(for: error) else { throw error }
            return try await ProPresenterTCPBridgeOneShot.request(
                host: settings.host,
                port: settings.port,
                path: path,
                method: method,
                bodyJSON: bodyJSON,
                timeout: options.timeout
            )
        }
    }

    private func shouldAttemptTCPFallback(for error: Error) -> Bool {
        if error is URLError {
            return true
        }
        if let connError = error as? ProPresenterConnectionError {
            switch connError {
            case .notConnected:
                return true
            case .httpStatus:
                // An HTTP status proves we reached the HTTP transport. Falling
                // back to the TCP bridge on the same port only converts empty
                // 400 responses into misleading "invalid JSON" errors.
                return false
            case .decoding:
                return true
            }
        }
        return false
    }

    /// HTTP-first void request, with optional TCP/IP bridge fallback.
    func requestVoid(
        _ path: String,
        method: String = "POST",
        body: Encodable? = nil
    ) async throws {
        let bodyJSON = serializedBodyJSON(body)

        if options.preferTCP {
            do {
                try await ProPresenterTCPBridgeOneShot.requestVoid(
                    host: settings.host,
                    port: settings.port,
                    path: path,
                    method: method,
                    bodyJSON: bodyJSON,
                    timeout: options.timeout
                )
                return
            } catch {
                try await http.requestVoid(path, method: method, body: body, timeout: options.timeout)
                return
            }
        }

        do {
            try await http.requestVoid(path, method: method, body: body, timeout: options.timeout)
        } catch {
            guard options.allowTCPFallback, shouldAttemptTCPFallback(for: error) else { throw error }
            try await ProPresenterTCPBridgeOneShot.requestVoid(
                host: settings.host,
                port: settings.port,
                path: path,
                method: method,
                bodyJSON: bodyJSON,
                timeout: options.timeout
            )
        }
    }

    private func serializedBodyJSON(_ body: Encodable?) -> String? {
        guard let body,
              let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let json = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              json != "null" else {
            return nil
        }
        return json
    }
}

// MARK: - Errors

enum ProPresenterConnectionError: LocalizedError {
    case notConnected
    case httpStatus(Int, String?)
    case decoding(String?)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to ProPresenter."
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty { return "HTTP \(code): \(body)" }
            return "HTTP \(code)"
        case .decoding(let body):
            if let body, !body.isEmpty { return "Response was not valid JSON: \(body)" }
            return "Response was not valid JSON."
        }
    }
}
