import Foundation
import Network
import os

enum DiGiCoOSCError: Error, LocalizedError {
    case invalidHost
    case portUnavailable(port: UInt16)
    case bindFailed(underlying: Error)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidHost: return "Invalid or empty console IP address."
        case .portUnavailable(let p): return "Port \(p) is already in use by another app."
        case .bindFailed(let e): return "Network bind failed: \(e.localizedDescription)"
        case .notConnected: return "OSC client not connected."
        }
    }
}

/// Actor owning all mutable OSC client state: the UDP `NWConnection`, ready flag, console host,
/// pending response/raw-packet handlers, and the piggybacked NotificationCenter observer.
///
/// This replaces a prior design where the same state lived on a plain `final class` marked
/// `@unchecked Sendable`, guarded only by a private serial `DispatchQueue` that every method
/// dispatched onto by convention. Under `SWIFT_STRICT_CONCURRENCY = targeted`, that design
/// produced 16 diagnostics -- all in `configure()`, `query()`, and `queryBatch()`, the three
/// `async` methods, where the checker could see state declared main-actor-isolated (by this
/// module's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default) being mutated from inside
/// `@Sendable` closures dispatched onto that queue. Making the type an `actor` gives the
/// compiler an isolation domain it can actually verify instead of one enforced only by
/// convention.
///
/// `NWConnection` still requires a plain `DispatchQueue` to drive its callbacks (Network
/// framework predates Swift Concurrency and has no actor-based API) -- `nwQueue` below exists
/// solely for that; no state lives on it. Callbacks forward only immutable/Sendable event data
/// (`Data`, `String`, `NWError`) back into this actor via `Task { await self... }` rather than
/// mutating anything directly from the callback thread, matching the pattern used for
/// `ProPresenterConnection`/`ConsoleConnector` in Task 6.
///
/// `sendQuery(address:)`, `addRawHandler(_:)`, `removeRawHandler(id:)`, and `disconnect()`
/// remain plain, synchronous, fire-and-forget methods (`nonisolated`, hopping onto the actor
/// internally via `Task`) rather than becoming `async` -- this preserves the exact call-site
/// shape `DiGiCoConsoleSyncService.swift` already uses (that file is unchanged by this refactor)
/// and matches those methods' pre-existing fire-and-forget semantics: the original
/// `queue.async { ... }` dispatch didn't let callers observe completion either.
actor DiGiCoOSCClient {

    enum OSCValue {
        case string(String)
        case int32(Int32)
        case float32(Float)
    }

    // Sendable + immutable, so this can be read synchronously from `nonisolated` contexts
    // (e.g. inside NWConnection callback closures) without hopping onto the actor first.
    private nonisolated let log = Logger(subsystem: "com.relay.digico-sync", category: "OSCClient")

    /// Drives `NWConnection`'s callbacks only; no state is stored on this queue. See the type
    /// doc comment above.
    private nonisolated let nwQueue = DispatchQueue(label: "com.relay.DiGiCoOSCClient", qos: .userInitiated)

    private var connection: NWConnection?
    private var isReady = false
    private var consoleHost: String = ""

    // One-shot response handlers keyed by OSC address.
    private var responseHandlers: [String: [(String) -> Void]] = [:]
    // Raw packet handlers (layout bank collection).
    private var rawHandlers: [UUID: (String, Data) -> Void] = [:]
    // NotificationCenter observer for piggybacking the existing [OSC] listener on port 8000.
    private var notificationObserver: NSObjectProtocol?

    init() {}

    // MARK: - Configuration

    /// Set up a send-only UDP connection to the console (OS assigns ephemeral local port).
    /// Responses are received via the existing app OSC listener + NotificationCenter,
    /// avoiding any conflict with the OSC stack already bound to port 8000.
    ///
    /// `localPort` is accepted for API compatibility but is no longer used to bind a socket.
    func configure(consoleHost: String, consolePort: UInt16, localPort: UInt16) async throws {
        let trimmed = consoleHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DiGiCoOSCError.invalidHost }

        connection?.cancel()
        connection = nil
        isReady = false
        self.consoleHost = trimmed
        responseHandlers.removeAll()
        rawHandlers.removeAll()
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
            notificationObserver = nil
        }

        guard let remotePort = NWEndpoint.Port(rawValue: consolePort) else {
            throw DiGiCoOSCError.invalidHost
        }

        // Send-only: no requiredLocalEndpoint, so the OS assigns an ephemeral port.
        // DiGiCo responds to the app's configured remote address (port 8000) which is
        // owned by the existing [OSC] stack. We receive via NotificationCenter instead.
        let params = NWParameters.udp
        let conn = NWConnection(
            host: NWEndpoint.Host(trimmed),
            port: remotePort,
            using: params
        )
        self.connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = OneShotGate()

            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.log.info("UDP send-ready → \(trimmed):\(consolePort)")
                    Task { await self?.handleReady(host: trimmed, gate: gate, continuation: continuation) }
                case .failed(let error):
                    self?.log.error("Connection failed: \(error)")
                    if gate.tryFire() {
                        continuation.resume(throwing: DiGiCoOSCError.bindFailed(underlying: error))
                    }
                default:
                    break
                }
            }

            conn.start(queue: nwQueue)

            nwQueue.asyncAfter(deadline: .now() + 4.0) {
                if gate.tryFire() {
                    continuation.resume(throwing: DiGiCoOSCError.bindFailed(
                        underlying: NSError(domain: "DiGiCoOSC", code: -1,
                                           userInfo: [NSLocalizedDescriptionKey: "Connection timed out"])
                    ))
                }
            }
        }
    }

    /// Runs once the `NWConnection` reaches `.ready`. Fires the `configure()` continuation
    /// (if it hasn't already fired via the failure/timeout paths), then starts both receive
    /// paths.
    private func handleReady(
        host: String,
        gate: OneShotGate,
        continuation: CheckedContinuation<Void, Error>
    ) {
        isReady = true
        if gate.tryFire() { continuation.resume(returning: ()) }
        // Best-effort raw receive (fires if DiGiCo responds to our sender port).
        startReceiveLoop()
        // Primary receive: piggyback the existing [OSC] listener via notifications.
        startNotificationObserver(consoleHost: host)
    }

    // MARK: - Sending

    /// Fire-and-forget, matching the pre-actor `queue.async` dispatch: callers do not await
    /// delivery.
    nonisolated func sendQuery(address: String) {
        Task { await self.performSendQuery(address: address) }
    }

    private func performSendQuery(address: String) {
        guard let conn = connection, isReady else {
            log.warning("sendQuery before ready: \(address)")
            return
        }
        log.debug("→ \(address)")
        conn.send(content: Self.buildQueryPacket(address: address),
                  completion: .contentProcessed { [weak self] error in
            if let error { self?.log.error("Send error \(address): \(error)") }
        })
    }

    // MARK: - Query API

    func query(address: String, timeout: TimeInterval = 1.5) async -> String? {
        let responseAddr = address.hasSuffix("/?") ? String(address.dropLast(2)) : address

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let gate = OneShotGate()
            // Register the handler before sending. Both run synchronously within this
            // actor-isolated continuation body (no cross-queue hand-off needed -- the actor
            // already serializes access), so the handler is in place before the send executes.
            responseHandlers[responseAddr, default: []].append { value in
                if gate.tryFire() { continuation.resume(returning: value) }
            }
            performSendQuery(address: address)
            nwQueue.asyncAfter(deadline: .now() + timeout) {
                if gate.tryFire() { continuation.resume(returning: nil) }
            }
        }
    }

    func queryBatch(addresses: [String], timeout: TimeInterval) async -> [String: String] {
        actor Accumulator {
            var results: [String: String] = [:]
            func set(_ addr: String, _ val: String) { results[addr] = val }
        }
        let acc = Accumulator()

        for address in addresses {
            let responseAddr = address.hasSuffix("/?") ? String(address.dropLast(2)) : address
            // Register before sending, for the same reason as query() -- both happen
            // synchronously in this same actor-isolated loop iteration.
            responseHandlers[responseAddr, default: []].append { value in
                Task { await acc.set(responseAddr, value) }
            }
            performSendQuery(address: address)
        }

        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        return await acc.results
    }

    @discardableResult
    nonisolated func addRawHandler(_ handler: @escaping (String, Data) -> Void) -> UUID {
        let id = UUID()
        Task { await self.registerRawHandler(id: id, handler: handler) }
        return id
    }

    private func registerRawHandler(id: UUID, handler: @escaping (String, Data) -> Void) {
        rawHandlers[id] = handler
    }

    nonisolated func removeRawHandler(id: UUID) {
        Task { await self.unregisterRawHandler(id: id) }
    }

    private func unregisterRawHandler(id: UUID) {
        rawHandlers.removeValue(forKey: id)
    }

    // MARK: - Disconnect

    nonisolated func disconnect() {
        Task { await self.performDisconnect() }
    }

    private func performDisconnect() {
        connection?.cancel()
        connection = nil
        isReady = false
        responseHandlers.removeAll()
        rawHandlers.removeAll()
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
            notificationObserver = nil
        }
    }

    // MARK: - OSC Parsing (static, testable)

    nonisolated static func parseOSCResponse(_ data: Data) -> (address: String, value: String)? {
        guard let parsed = parseOSCArguments(data) else { return nil }
        for arg in parsed.args {
            if case .string(let s) = arg { return (parsed.address, s) }
        }
        return nil
    }

    nonisolated static func parseOSCArguments(_ data: Data) -> (address: String, args: [OSCValue])? {
        guard let (address, afterAddr) = readPaddedString(from: data, at: 0),
              let (typeTags, afterTags) = readPaddedString(from: data, at: afterAddr),
              typeTags.hasPrefix(",") else { return nil }

        var args: [OSCValue] = []
        var offset = afterTags

        for tag in typeTags.dropFirst() {
            switch tag {
            case "s":
                guard let (str, next) = readPaddedString(from: data, at: offset) else {
                    return (address, args)
                }
                args.append(.string(str))
                offset = next
            case "i":
                guard offset + 4 <= data.count else { return (address, args) }
                let raw = data[offset..<(offset + 4)].withUnsafeBytes {
                    $0.load(as: Int32.self)
                }
                args.append(.int32(Int32(bigEndian: raw)))
                offset += 4
            case "f":
                guard offset + 4 <= data.count else { return (address, args) }
                let raw = data[offset..<(offset + 4)].withUnsafeBytes {
                    $0.load(as: UInt32.self)
                }
                args.append(.float32(Float(bitPattern: UInt32(bigEndian: raw))))
                offset += 4
            default:
                break
            }
        }
        return (address, args)
    }

    // MARK: - Private

    /// Primary receive path: subscribe to the existing [OSC] listener's parsed-packet notifications.
    /// This avoids any conflict with the OSC stack already bound to port 8000.
    private func startNotificationObserver(consoleHost: String) {
        let obs = NotificationCenter.default.addObserver(
            forName: .oscReceivePacketDidArrive,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let address = notification.userInfo?["address"] as? String,
                  let payloadText = notification.userInfo?["payloadText"] as? String,
                  let remoteHost = notification.userInfo?["remoteHost"] as? String,
                  remoteHost == consoleHost
            else { return }
            Task { await self?.handleNotificationResponse(address: address, payloadText: payloadText) }
        }
        notificationObserver = obs
    }

    private func handleNotificationResponse(address: String, payloadText: String) {
        log.debug("← \(address) = \"\(payloadText)\" (notification)")
        dispatchResponse(address: address, value: payloadText)
    }

    /// Best-effort fallback receive path via NWConnection.receiveMessage.
    /// Fires only if DiGiCo routes its reply to our ephemeral sender port rather than to port 8000.
    /// Also drives `rawHandlers` for layout bank collection (multi-arg OSC packets).
    private func startReceiveLoop() {
        guard let conn = connection else { return }
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                Task { await self?.handleRawPacket(data) }
            }
            if error == nil {
                Task { await self?.startReceiveLoop() }
            }
        }
    }

    /// Handle a raw UDP packet received on our ephemeral NWConnection.
    private func handleRawPacket(_ data: Data) {
        // Dispatch to raw handlers (layout bank collection needs all OSC args).
        if let parsed = Self.parseOSCArguments(data) {
            for handler in rawHandlers.values {
                handler(parsed.address, data)
            }
        }
        // Also route string responses (belt-and-suspenders with notification path).
        if let (address, value) = Self.parseOSCResponse(data) {
            log.debug("← \(address) = \"\(value)\" (raw socket)")
            dispatchResponse(address: address, value: value)
        }
    }

    /// Dispatch a parsed address+value to any waiting response handlers.
    private func dispatchResponse(address: String, value: String) {
        let handlers = responseHandlers.removeValue(forKey: address) ?? []
        handlers.forEach { $0(value) }
    }

    private nonisolated static func buildQueryPacket(address: String) -> Data {
        paddedCString(address)
    }

    private nonisolated static func paddedCString(_ s: String) -> Data {
        var bytes = Array(s.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        return Data(bytes)
    }

    private nonisolated static func readPaddedString(from data: Data, at start: Int) -> (String, Int)? {
        guard start < data.count else { return nil }
        var nullPos = start
        while nullPos < data.count, data[nullPos] != 0 { nullPos += 1 }
        guard nullPos < data.count else { return nil }
        let str = String(bytes: data[start..<nullPos], encoding: .utf8) ?? ""
        let strLen = nullPos - start
        let paddedLen = ((strLen + 1 + 3) / 4) * 4
        return (str, start + paddedLen)
    }
}
