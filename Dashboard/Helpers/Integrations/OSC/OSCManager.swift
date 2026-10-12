// MARK: - Notifications

extension Notification.Name {
    // `nonisolated` because this is a plain Sendable value constant (a `Notification.Name`
    // wraps a `String`) referenced from many places, including from `DiGiCoOSCClient`'s
    // actor-isolated methods (Task 7) -- without this, the compiler treats the
    // compiler-synthesized-default main-actor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION =
    // MainActor`) as applying to this `static let`, making it a cross-actor reference from
    // any non-main-actor isolation domain.
    nonisolated static let oscReceivePacketDidArrive = Notification.Name("oscReceivePacketDidArrive")
}
//
//  OSCEndpoint.swift
//  Relay
//
//  Created by David Bullard on 1/11/26.
//


//
//  OSCManager.swift
//  Relay
//
//  Generic OSC send/receive manager (Option 1)
//
//  - Nodes provide IP:Port and OSC address/args templates.
//  - OSCManager handles UDP networking + OSC codec.
//  - Can be used by any module (Shure/Sennheiser triggers, console raw OSC, inbound triggers).
//

import Foundation
import Network
import Combine
import OSLog

// MARK: - Public Models

nonisolated public struct OSCEndpoint: Codable, Hashable, Sendable {
    public var host: String
    public var port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    nonisolated public static func == (lhs: OSCEndpoint, rhs: OSCEndpoint) -> Bool {
        lhs.host == rhs.host && lhs.port == rhs.port
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(host)
        hasher.combine(port)
    }
}

public enum OSCValue: Hashable, Sendable {
    case int32(Int32)
    case float32(Float)
    case string(String)
    case bool(Bool)          // Encoded as typetag 'T'/'F'
    case blob(Data)          // Optional / future-proof
    case null                // Encoded as typetag 'N'
    case impulse             // Encoded as typetag 'I'
    case timetag(UInt64)     // Encoded as typetag 't'

    public var debugDescription: String {
        switch self {
        case .int32(let v): return "i:\(v)"
        case .float32(let v): return "f:\(v)"
        case .string(let v): return "s:\"\(v)\""
        case .bool(let v): return "b:\(v)"
        case .blob(let d): return "blob(\(d.count))"
        case .null: return "null"
        case .impulse: return "impulse"
        case .timetag(let v): return "t:\(v)"
        }
    }
}

public struct OSCMessage: Hashable, Sendable {
    public var address: String
    public var args: [OSCValue]

    public init(address: String, args: [OSCValue] = []) {
        self.address = address
        self.args = args
    }
}

public struct OSCReceivedMessage: Hashable, Sendable {
    public var remoteHost: String
    public var remotePort: UInt16
    public var message: OSCMessage
    public var receivedAt: Date

    public init(remoteHost: String, remotePort: UInt16, message: OSCMessage, receivedAt: Date = Date()) {
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.message = message
        self.receivedAt = receivedAt
    }
}

// MARK: - Templates (for node actions)

public enum OSCArgTemplate: Codable, Hashable, Sendable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)
    case token(String)   // looks up token in payload (e.g. "batteryPct", "channelName")

    // Codable
    private enum CodingKeys: String, CodingKey { case type, int, float, string, bool, token }
    private enum Kind: String, Codable { case int, float, string, bool, token }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .int: self = .int(try c.decode(Int.self, forKey: .int))
        case .float: self = .float(try c.decode(Double.self, forKey: .float))
        case .string: self = .string(try c.decode(String.self, forKey: .string))
        case .bool: self = .bool(try c.decode(Bool.self, forKey: .bool))
        case .token: self = .token(try c.decode(String.self, forKey: .token))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let v):
            try c.encode(Kind.int, forKey: .type)
            try c.encode(v, forKey: .int)
        case .float(let v):
            try c.encode(Kind.float, forKey: .type)
            try c.encode(v, forKey: .float)
        case .string(let v):
            try c.encode(Kind.string, forKey: .type)
            try c.encode(v, forKey: .string)
        case .bool(let v):
            try c.encode(Kind.bool, forKey: .type)
            try c.encode(v, forKey: .bool)
        case .token(let v):
            try c.encode(Kind.token, forKey: .type)
            try c.encode(v, forKey: .token)
        }
    }
}

public struct OSCMessageTemplate: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var address: String
    public var args: [OSCArgTemplate]

    public init(address: String, args: [OSCArgTemplate] = []) {
        self.address = address
        self.args = args
    }
}

// Simple payload event for automation.
// (You can swap this for your existing event type; just feed payload to resolveArgs.)
public struct AutomationEvent: Hashable, Sendable {
    public var kind: String
    public var payload: [String: String]
    public var timestamp: Date

    public init(kind: String, payload: [String : String], timestamp: Date = Date()) {
        self.kind = kind
        self.payload = payload
        self.timestamp = timestamp
    }
}

// MARK: - OSCManager

public final class OSCManager: ObservableObject {

    public static let shared = OSCManager()

    // Inbound publish (latest)
    @Published public private(set) var lastReceived: OSCReceivedMessage?
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var listeningPort: UInt16?

    // Optional: log sink you can redirect to your app logger.
    public var log: ((String) -> Void)?

    // Global receive configuration (not node-specific)
    @Published public private(set) var globalListeningEnabled: Bool = false
    @Published public private(set) var globalListeningPort: UInt16 = 0
    @Published public private(set) var lastSendAt: Date? = nil
    @Published public private(set) var lastSendRemote: String? = nil
    @Published public private(set) var lastReceiveAt: Date? = nil
    @Published public private(set) var lastReceiveRemote: String? = nil

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Relay", category: "OSC")

    private func emit(_ s: String) {
        if let log = log {
            log(s)
        } else {
            // Visible in Xcode console + Console.app even when `log` isn't wired.
            logger.info("\(s, privacy: .public)")
        }
    }

    // Internal networking
    private var listener: NWListener?
    private var customListeners: [UInt16: NWListener] = [:]
    private var customListeningPorts: Set<UInt16> = []
    private var pendingListenPort: UInt16? = nil
    private var isRestartingListener: Bool = false
    private var receiveQueue = DispatchQueue(label: "com.prodlink.osc.receive", qos: .userInitiated)
    private var sendQueue = DispatchQueue(label: "com.prodlink.osc.send", qos: .userInitiated)

    // Cache connections per endpoint for efficiency
    private var connectionCache: [OSCEndpoint: NWConnection] = [:]

    // Inbound UDP "connections" that NWListener synthesizes per distinct remote sender.
    // Nothing else in Network.framework retires these automatically, so we track last-seen
    // activity and periodically reap ones that have gone quiet (e.g. a device rebooted onto
    // a new ephemeral source port, or was unplugged) — otherwise they accumulate for as long
    // as the app stays open. Only ever touched from `receiveQueue`.
    private struct InboundConnectionInfo {
        let connection: NWConnection
        let localPort: UInt16
        var lastActivityAt: CFAbsoluteTime
    }
    private var inboundConnections: [ObjectIdentifier: InboundConnectionInfo] = [:]
    private let inboundConnectionIdleTimeout: CFAbsoluteTime = 45 * 60   // reap after 45 min of silence
    private let inboundConnectionSweepInterval: TimeInterval = 5 * 60    // check every 5 min
    private var inboundSweepScheduled = false

    private var receivedPacketCount: Int = 0
    private var receivedMessageCount: Int = 0
    private var lastReceiveSummaryAt: CFAbsoluteTime = 0
    private var lastReceiveDetailAt: CFAbsoluteTime = 0
    private var lastReceiveRemoteSummary: String = ""
    private var sentPacketCount: Int = 0
    private var sentByteCount: Int = 0
    private var lastSendSummaryAt: CFAbsoluteTime = 0
    private var lastSendDetailAt: CFAbsoluteTime = 0
    private var lastSendRemoteSummary: String = ""

    private init() {}

    deinit {
        stopListening()
        closeAllConnections()
        closeAllInboundConnections()
    }

    // MARK: - Public Send API

    /// Send one OSC message to an endpoint.
    public func send(to endpoint: OSCEndpoint, message: OSCMessage) {
        guard validate(address: message.address) else {
            emit("[OSC] Invalid address: \(message.address)")
            return
        }
        let data = OSCCodec.encode(message: message)
        sendRaw(to: endpoint, data: data)
    }

    /// Convenience: send with address + args.
    public func send(to endpoint: OSCEndpoint, address: String, args: [OSCValue] = []) {
        send(to: endpoint, message: OSCMessage(address: address, args: args))
    }

    /// Send a template with event payload resolution (tokens).
    public func send(to endpoint: OSCEndpoint, template: OSCMessageTemplate, event: AutomationEvent) {
        let args = resolveArgs(template.args, payload: event.payload)
        send(to: endpoint, address: template.address, args: args)
    }

    /// Send multiple templates for a single event (typical node action).
    public func send(to endpoint: OSCEndpoint, templates: [OSCMessageTemplate], event: AutomationEvent) {
        for t in templates {
            send(to: endpoint, template: t, event: event)
        }
    }

    /// Configure global inbound OSC listening for the app.
    /// This is intended to be driven by a single app-level setting (not node UI).
    /// If enabled, the manager will bind to `port` and keep listening until disabled.
    public func setGlobalListening(enabled: Bool, port: UInt16) {
        let needsListenerUpdate = (globalListeningEnabled != enabled) || (globalListeningPort != port)
        globalListeningEnabled = enabled
        globalListeningPort = port

        if needsListenerUpdate {
            if enabled {
                startListening(port: port)
            } else {
                stopListening()
            }
        }

        syncCustomListeners()
    }

    /// Keep additional listeners active for graph trigger nodes that override the global port.
    public func setCustomListeningPorts(_ ports: Set<UInt16>) {
        let sanitized = Set(ports.filter { $0 != 0 })
        receiveQueue.async { [weak self] in
            guard let self else { return }
            self.customListeningPorts = sanitized
            self.syncCustomListenersLocked()
        }
    }

    // MARK: - Public Receive API

    /// Start listening for inbound OSC on a UDP port.
    public func startListening(port: UInt16) {
        // Serialize restarts on the receive queue so we don't race cancel/start.
        receiveQueue.async { [weak self] in
            guard let self else { return }

            // If already listening on this port, no-op.
            if self.isListening, self.listeningPort == port {
                self.emit("[OSC] startListening(port=\(port)) ignored (already listening)")
                return
            }

            // Validate port.
            guard let p = NWEndpoint.Port(rawValue: port), port != 0 else {
                DispatchQueue.main.async {
                    self.emit("[OSC] Invalid listen port: \(port)")
                    self.isListening = false
                    self.listeningPort = nil
                }
                return
            }

            self.emit("[OSC] startListening(port=\(port))")

            // Record what we want, and cancel any existing listener first.
            self.pendingListenPort = port

            if self.listener != nil {
                self.isRestartingListener = true
                DispatchQueue.main.async {
                    self.isListening = false
                    self.listeningPort = nil
                }
                self.listener?.cancel()
                return
            }

            // No existing listener: start immediately.
            self.startListenerInternal(on: p, requestedPort: port)
        }
    }

    private func startListenerInternal(on p: NWEndpoint.Port, requestedPort: UInt16) {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true
            let newListener = try NWListener(using: params, on: p)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self.isListening = true
                        let actual = newListener.port?.rawValue ?? requestedPort
                        self.listeningPort = actual
                        self.emit("[OSC] Listening on UDP \(actual)")
                        self.isRestartingListener = false
                        self.pendingListenPort = nil

                    case .failed(let err):
                        self.isListening = false
                        self.listeningPort = nil
                        self.emit("[OSC] Listener failed: \(err)")

                        // If we hit EADDRINUSE, retry after a short delay. This commonly happens
                        // when cancel/start happens too quickly or another process owns the port.
                        if case .posix(let code) = err, code == .EADDRINUSE {
                            // Best-effort retry: if the pending port matches, try again.
                            if let pending = self.pendingListenPort {
                                self.emit("[OSC] Will retry listen on UDP \(pending) in 0.35s")
                                self.listener?.cancel()
                                self.listener = nil
                                self.isRestartingListener = false
                                DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                                    self.startListening(port: pending)
                                }
                            }
                        }

                    case .cancelled:
                        self.isListening = false
                        self.listeningPort = nil
                        self.emit("[OSC] Listener cancelled")

                        // If a restart was requested, start the pending port now.
                        if let next = self.pendingListenPort {
                            self.pendingListenPort = nil
                            self.isRestartingListener = false

                            // Start on receiveQueue (serialized).
                            self.receiveQueue.async {
                                guard let p2 = NWEndpoint.Port(rawValue: next), next != 0 else { return }
                                self.startListenerInternal(on: p2, requestedPort: next)
                            }
                        }

                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                let ep = conn.endpoint.debugDescription
                let localPort = newListener.port?.rawValue ?? requestedPort
                self.emit("[OSC] newConnectionHandler endpoint=\(ep)")
                self.handleIncoming(connection: conn, localPort: localPort)
            }

            listener = newListener
            newListener.start(queue: receiveQueue)

        } catch {
            DispatchQueue.main.async {
                self.emit("[OSC] Failed to start listener: \(error)")
                self.isListening = false
                self.listeningPort = nil
            }
        }
    }

    public func stopListening() {
        receiveQueue.async { [weak self] in
            guard let self else { return }
            self.pendingListenPort = nil
            self.isRestartingListener = false
            self.listener?.cancel()
            self.listener = nil
            DispatchQueue.main.async {
                self.isListening = false
                self.listeningPort = nil
                self.emit("[OSC] stopListening()")
            }
        }
    }

    private func syncCustomListeners() {
        receiveQueue.async { [weak self] in
            self?.syncCustomListenersLocked()
        }
    }

    private func syncCustomListenersLocked() {
        let reservedGlobalPort: UInt16? = globalListeningEnabled ? globalListeningPort : nil
        let desiredPorts = customListeningPorts.filter { $0 != reservedGlobalPort }

        for port in customListeners.keys where !desiredPorts.contains(port) {
            customListeners[port]?.cancel()
            customListeners.removeValue(forKey: port)
            emit("[OSC] Stopped custom listener on UDP \(port)")
        }

        for port in desiredPorts where customListeners[port] == nil {
            startCustomListenerLocked(port: port)
        }
    }

    private func startCustomListenerLocked(port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port), port != 0 else {
            emit("[OSC] Invalid custom listen port: \(port)")
            return
        }

        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true

            let newListener = try NWListener(using: params, on: nwPort)
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let actual = newListener.port?.rawValue ?? port
                    self.emit("[OSC] Listening on custom UDP \(actual)")
                case .failed(let err):
                    self.emit("[OSC] Custom listener failed on UDP \(port): \(err)")
                    self.receiveQueue.async {
                        if self.customListeners[port] === newListener {
                            self.customListeners.removeValue(forKey: port)
                        }
                    }
                case .cancelled:
                    self.emit("[OSC] Custom listener cancelled on UDP \(port)")
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                let ep = conn.endpoint.debugDescription
                self.emit("[OSC] custom newConnectionHandler endpoint=\(ep) localPort=\(port)")
                self.handleIncoming(connection: conn, localPort: port)
            }

            customListeners[port] = newListener
            newListener.start(queue: receiveQueue)
        } catch {
            emit("[OSC] Failed to start custom listener on UDP \(port): \(error)")
        }
    }

    // MARK: - Token Resolution (Templates)

    /// Resolve templates into OSCValues using a payload dictionary.
    /// Rules:
    /// - token value parses as Int -> int32
    /// - else parses as Double -> float32
    /// - else "true/false" -> bool
    /// - else string
    public func resolveArgs(_ templates: [OSCArgTemplate], payload: [String: String]) -> [OSCValue] {
        templates.compactMap { t in
            switch t {
            case .int(let v): return .int32(Int32(v))
            case .float(let v): return .float32(Float(v))
            case .string(let v): return .string(v)
            case .bool(let v): return .bool(v)
            case .token(let key):
                let raw = payload[key] ?? ""
                if let i = Int(raw) { return .int32(Int32(i)) }
                if let d = Double(raw) { return .float32(Float(d)) }
                let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lower == "true" { return .bool(true) }
                if lower == "false" { return .bool(false) }
                return .string(raw)
            }
        }
    }

    // MARK: - Internal Send

    private func sendRaw(to endpoint: OSCEndpoint, data: Data) {
        sendQueue.async { [weak self] in
            guard let self else { return }
            let remote = "\(endpoint.host):\(endpoint.port)"
            self.sentPacketCount += 1
            self.sentByteCount += data.count
            self.lastSendRemoteSummary = remote
            DispatchQueue.main.async {
                self.lastSendAt = Date()
                self.lastSendRemote = remote
            }
            self.maybeEmitSendSummary()
            if self.shouldLogSendDetail() {
                self.emit("[OSC] Sending \(data.count) bytes to \(remote)")
            }

            let conn = self.connection(for: endpoint)
            conn.send(content: data, completion: .contentProcessed({ err in
                if let err {
                    self.emit("[OSC] Send failed to \(endpoint.host):\(endpoint.port) — \(err)")
                }
            }))
        }
    }

    private func connection(for endpoint: OSCEndpoint) -> NWConnection {
        if let cached = connectionCache[endpoint] {
            return cached
        }
        let host = NWEndpoint.Host(endpoint.host)
        let port = NWEndpoint.Port(rawValue: endpoint.port) ?? 0
        let params = NWParameters.udp
        params.includePeerToPeer = true
        let conn = NWConnection(host: host, port: port, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.emit("[OSC] UDP ready \(endpoint.host):\(endpoint.port)")
            case .failed(let err):
                self.emit("[OSC] UDP failed \(endpoint.host):\(endpoint.port): \(err)")
                self.sendQueue.async {
                    if self.connectionCache[endpoint] === conn {
                        self.connectionCache.removeValue(forKey: endpoint)
                    }
                }
            case .cancelled:
                self.emit("[OSC] UDP cancelled \(endpoint.host):\(endpoint.port)")
                self.sendQueue.async {
                    if self.connectionCache[endpoint] === conn {
                        self.connectionCache.removeValue(forKey: endpoint)
                    }
                }
            default:
                break
            }
        }

        conn.start(queue: sendQueue)
        connectionCache[endpoint] = conn
        return conn
    }

    private func closeAllConnections() {
        for (_, c) in connectionCache {
            c.cancel()
        }
        connectionCache.removeAll()
    }

    private func closeAllInboundConnections() {
        receiveQueue.async { [weak self] in
            guard let self else { return }
            for (_, info) in self.inboundConnections {
                info.connection.cancel()
            }
            self.inboundConnections.removeAll()
        }
    }

    // MARK: - Inbound connection reaping

    /// Schedules a one-shot sweep on `receiveQueue`; re-schedules itself only while there are
    /// still tracked connections, so the timer goes dormant instead of ticking forever when idle.
    private func scheduleInboundSweepIfNeeded() {
        guard !inboundSweepScheduled else { return }
        inboundSweepScheduled = true
        receiveQueue.asyncAfter(deadline: .now() + inboundConnectionSweepInterval) { [weak self] in
            self?.sweepIdleInboundConnections()
        }
    }

    private func sweepIdleInboundConnections() {
        inboundSweepScheduled = false
        guard !inboundConnections.isEmpty else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let staleKeys = inboundConnections.filter { now - $0.value.lastActivityAt > inboundConnectionIdleTimeout }.keys
        for key in staleKeys {
            guard let info = inboundConnections.removeValue(forKey: key) else { continue }
            let idleFor = Int(now - info.lastActivityAt)
            emit("[OSC] Reaping idle inbound connection endpoint=\(info.connection.endpoint.debugDescription) localPort=\(info.localPort) idleFor=\(idleFor)s")
            info.connection.cancel()
        }

        if !inboundConnections.isEmpty {
            scheduleInboundSweepIfNeeded()
        }
    }

    private func validate(address: String) -> Bool {
        // OSC address must start with '/'
        return address.first == "/" && address.count > 1
    }

    // MARK: - Incoming Handling

    private func handleIncoming(connection: NWConnection, localPort: UInt16) {
        emit("[OSC] handleIncoming start endpoint=\(connection.endpoint.debugDescription) localPort=\(localPort)")
        inboundConnections[ObjectIdentifier(connection)] = InboundConnectionInfo(
            connection: connection, localPort: localPort, lastActivityAt: CFAbsoluteTimeGetCurrent()
        )
        scheduleInboundSweepIfNeeded()
        connection.start(queue: receiveQueue)
        receiveNext(on: connection, localPort: localPort)
    }

    private func receiveNext(on connection: NWConnection, localPort: UInt16) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self else { return }

            if let error {
                let remote = (connection.currentPath?.remoteEndpoint?.debugDescription ?? "unknown")
                self.emit("[OSC] Receive error from \(remote): \(error)")
                self.inboundConnections.removeValue(forKey: ObjectIdentifier(connection))
                connection.cancel()
                return
            }

            self.inboundConnections[ObjectIdentifier(connection)]?.lastActivityAt = CFAbsoluteTimeGetCurrent()

            if let data, !data.isEmpty {
                let remoteHost = (connection.currentPath?.remoteEndpoint?.debugDescription ?? "unknown")
                let (host, port) = self.bestEffortParseRemote(from: connection)
                let srcHost = host ?? remoteHost
                let srcPort = port ?? 0
                let remoteSummary = "\(srcHost):\(srcPort)"
                let packetTimestamp = Date()
                let shouldLogDetail = self.shouldLogReceiveDetail()

                self.receivedPacketCount += 1
                self.lastReceiveRemoteSummary = remoteSummary
                DispatchQueue.main.async {
                    self.lastReceiveAt = packetTimestamp
                    self.lastReceiveRemote = remoteSummary
                }
                self.maybeEmitReceiveSummary()

                if shouldLogDetail {
                    self.emit("[OSC] UDP packet received \(data.count) bytes from \(srcHost):\(srcPort)")
                }

                let messages = OSCCodec.decode(packet: data)
                if messages.isEmpty {
                    self.emit("[OSC] Decode produced 0 messages from \(srcHost):\(srcPort) (bytes=\(data.count))")
                    let first = data.first.map { String(format: "0x%02X", $0) } ?? "nil"
                    let startsSlash = data.first == 0x2F
                    let startsBundle = data.starts(with: Array("#bundle".utf8))
                    let lenPrefixedSlash = (data.count > 4 && data[4] == 0x2F)
                    let lenPrefixedBundle: Bool = {
                        guard data.count > 11 else { return false }
                        return data.subdata(in: 4..<11).starts(with: Array("#bundle".utf8))
                    }()
                    self.emit("[OSC] Raw signature first=\(first) startsWith/='\(startsSlash)' startsWith#bundle='\(startsBundle)' lenPrefixed/='\(lenPrefixedSlash)' lenPrefixed#bundle='\(lenPrefixedBundle)'")
                    self.emit("[OSC] Raw preview \(previewBytes(data))")
                } else {
                    self.receivedMessageCount += messages.count
                    var latestReceived: OSCReceivedMessage?
                    for msg in messages {
                        if shouldLogDetail {
                            self.emit("[OSC] Message \(msg.address) args=\(msg.args.count) from \(srcHost):\(srcPort)")
                        }
                        latestReceived = OSCReceivedMessage(
                            remoteHost: srcHost,
                            remotePort: srcPort,
                            message: msg,
                            receivedAt: packetTimestamp
                        )

                        if shouldLogDetail {
                            self.emit("[OSC] Posting oscReceivePacketDidArrive address=\(msg.address) localPort=\(localPort)")
                        }

                        let payload = self.primaryOSCValues(in: msg.args)

                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .oscReceivePacketDidArrive,
                                object: nil,
                                userInfo: [
                                    "localPort": localPort,
                                    "port": localPort,
                                    "remoteHost": srcHost,
                                    "remotePort": srcPort,
                                    "address": msg.address,
                                    "argsCount": msg.args.count,
                                    "payloadText": payload.text as Any,
                                    "payloadNumber": payload.number as Any,
                                    "payloadBoolean": payload.boolean as Any
                                ]
                            )
                        }
                    }
                    if let latestReceived {
                        DispatchQueue.main.async {
                            self.lastReceived = latestReceived
                        }
                    }
                }
            } else {
                // Helpful when debugging: indicates reads are happening but no payload arrived.
                let ep = connection.endpoint.debugDescription
                self.emit("[OSC] receiveMessage empty/nil (endpoint=\(ep))")
            }

            self.receiveNext(on: connection, localPort: localPort)
        }
    }

    private func maybeEmitReceiveSummary() {
        let now = CFAbsoluteTimeGetCurrent()
        let interval: CFAbsoluteTime = 30.0
        guard now - lastReceiveSummaryAt > interval else { return }
        lastReceiveSummaryAt = now
        emit("[OSC] RX summary packets=\(receivedPacketCount) messages=\(receivedMessageCount) lastRemote=\(lastReceiveRemoteSummary)")
    }

    private func shouldLogReceiveDetail() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let interval: CFAbsoluteTime = 2.0
        if now - lastReceiveDetailAt > interval {
            lastReceiveDetailAt = now
            return true
        }
        return false
    }

    private func firstOSCTextValue(in args: [OSCValue]) -> String? {
        guard let first = args.first else { return nil }
        switch first {
        case .string(let value):
            return value
        case .int32(let value):
            return String(value)
        case .float32(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .blob, .null, .impulse, .timetag:
            return nil
        }
    }

    private func firstOSCNumberValue(in args: [OSCValue]) -> Double? {
        for arg in args {
            switch arg {
            case .int32(let value):
                return Double(value)
            case .float32(let value):
                return Double(value)
            case .string(let value):
                if let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return parsed
                }
            case .bool, .blob, .null, .impulse, .timetag:
                continue
            }
        }
        return nil
    }

    private func firstOSCBoolValue(in args: [OSCValue]) -> Bool? {
        for arg in args {
            switch arg {
            case .bool(let value):
                return value
            case .int32(let value):
                if value == 0 { return false }
                if value == 1 { return true }
            case .string(let value):
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes", "on":
                    return true
                case "false", "0", "no", "off":
                    return false
                default:
                    continue
                }
            case .float32(let value):
                if value == 0 { return false }
                if value == 1 { return true }
            case .blob, .null, .impulse, .timetag:
                continue
            }
        }
        return nil
    }

    private func primaryOSCValues(in args: [OSCValue]) -> (text: String?, number: Double?, boolean: Bool?) {
        var text: String?
        var number: Double?
        var boolean: Bool?

        for arg in args {
            switch arg {
            case .string(let value):
                if text == nil {
                    text = value
                }
                if number == nil {
                    number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            case .int32(let value):
                if text == nil {
                    text = String(value)
                }
                if number == nil {
                    number = Double(value)
                }
                if boolean == nil {
                    if value == 0 { boolean = false }
                    if value == 1 { boolean = true }
                }
            case .float32(let value):
                if text == nil {
                    text = String(value)
                }
                if number == nil {
                    number = Double(value)
                }
                if boolean == nil {
                    if value == 0 { boolean = false }
                    if value == 1 { boolean = true }
                }
            case .bool(let value):
                if text == nil {
                    text = value ? "true" : "false"
                }
                if boolean == nil {
                    boolean = value
                }
            case .blob, .null, .impulse, .timetag:
                continue
            }

            if text != nil && number != nil && boolean != nil {
                break
            }
        }

        return (text, number, boolean)
    }

    private func maybeEmitSendSummary() {
        let now = CFAbsoluteTimeGetCurrent()
        let interval: CFAbsoluteTime = 30.0
        guard now - lastSendSummaryAt > interval else { return }
        lastSendSummaryAt = now
        emit("[OSC] TX summary packets=\(sentPacketCount) bytes=\(sentByteCount) lastRemote=\(lastSendRemoteSummary)")
    }

    private func shouldLogSendDetail() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let interval: CFAbsoluteTime = 2.0
        if now - lastSendDetailAt > interval {
            lastSendDetailAt = now
            return true
        }
        return false
    }

    private func previewBytes(_ data: Data, max: Int = 64) -> String {
        let n = min(max, data.count)
        let slice = data.prefix(n)
        let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
        let ascii = slice.map { b -> String in
            if b >= 0x20 && b <= 0x7E { return String(UnicodeScalar(b)) }
            return "."
        }.joined()
        return "hex=[\(hex)] ascii=\(ascii)"
    }

    private func bestEffortParseRemote(from connection: NWConnection) -> (String?, UInt16?) {
        guard let ep = connection.currentPath?.remoteEndpoint else { return (nil, nil) }
        switch ep {
        case .hostPort(let host, let port):
            let p = port.rawValue
            return (host.debugDescription, p)
        default:
            return (nil, nil)
        }
    }
}

// MARK: - OSC Codec

/// OSC encoding/decoding (message + minimal bundle support)
public enum OSCCodec {

    // MARK: Encode

    public static func encode(message: OSCMessage) -> Data {
        var data = Data()

        data.append(oscString(message.address))
        data.append(oscString(typeTagString(for: message.args)))

        for arg in message.args {
            data.append(encode(arg: arg))
        }
        return data
    }

    private static func typeTagString(for args: [OSCValue]) -> String {
        // Must start with comma
        var tags = ","
        for a in args {
            switch a {
            case .int32: tags.append("i")
            case .float32: tags.append("f")
            case .string: tags.append("s")
            case .bool(let b): tags.append(b ? "T" : "F")
            case .blob: tags.append("b")
            case .null: tags.append("N")
            case .impulse: tags.append("I")
            case .timetag: tags.append("t")
            }
        }
        return tags
    }

    private static func encode(arg: OSCValue) -> Data {
        switch arg {
        case .int32(let v):
            return oscInt32(v)
        case .float32(let v):
            return oscFloat32(v)
        case .string(let s):
            return oscString(s)
        case .bool:
            // For typetag T/F, there is no payload.
            return Data()
        case .blob(let d):
            var out = Data()
            out.append(oscInt32(Int32(d.count)))
            out.append(d)
            out.append(padTo4Bytes(count: d.count))
            return out
        case .null, .impulse:
            return Data()
        case .timetag(let value):
            return oscUInt64(value)
        }
    }

    // MARK: Decode

    /// Decode an OSC packet. Returns all messages found (including inside bundles).
    public static func decode(packet: Data) -> [OSCMessage] {
        // Message starts with '/' address.
        if packet.starts(with: [0x2F]) {
            if let msg = decodeMessage(from: packet, startIndex: 0).message {
                return [msg]
            }
            return []
        }

        // Bundle starts with "#bundle"
        if packet.starts(with: Array("#bundle".utf8)) {
            return decodeBundle(packet)
        }

        // Compatibility: some stacks prepend a 4-byte length (OSC TCP framing)
        // before the actual OSC payload.
        if packet.count > 4 {
            let framed = packet.subdata(in: 4..<packet.count)

            if framed.starts(with: [0x2F]) {
                if let msg = decodeMessage(from: framed, startIndex: 0).message {
                    return [msg]
                }
                return []
            }

            if framed.starts(with: Array("#bundle".utf8)) {
                return decodeBundle(framed)
            }
        }

        return []
    }

    private static func decodeBundle(_ packet: Data) -> [OSCMessage] {
        var idx = 0

        // "#bundle\0"
        guard let (bundleStr, next) = readOSCString(packet, from: idx),
              bundleStr == "#bundle" else {
            return []
        }
        idx = next

        // timetag (8 bytes)
        guard idx + 8 <= packet.count else { return [] }
        idx += 8

        var out: [OSCMessage] = []
        while idx + 4 <= packet.count {
            // element size int32
            guard let (size, nextIdx) = readInt32(packet, from: idx) else { break }
            idx = nextIdx
            let elemSize = Int(size)
            guard elemSize >= 0, idx + elemSize <= packet.count else { break }

            let elem = packet.subdata(in: idx ..< idx + elemSize)
            idx += elemSize

            out.append(contentsOf: decode(packet: elem))
        }
        return out
    }

    private struct DecodedMessageResult {
        var message: OSCMessage?
        var nextIndex: Int
    }

    private static func decodeMessage(from packet: Data, startIndex: Int) -> DecodedMessageResult {
        var idx = startIndex

        guard let (address, next1) = readOSCString(packet, from: idx) else {
            return DecodedMessageResult(message: nil, nextIndex: idx)
        }
        idx = next1

        // OSC 1.0 requires a type tag string (starting with ',') after the address.
        // However, some senders omit it entirely for no-argument messages and send only the address.
        // In that case, treat it as a valid message with zero args.
        guard let (typeTags, next2) = readOSCString(packet, from: idx) else {
            return DecodedMessageResult(message: OSCMessage(address: address, args: []), nextIndex: idx)
        }
        idx = next2

        guard typeTags.first == "," else {
            // No args
            return DecodedMessageResult(message: OSCMessage(address: address, args: []), nextIndex: idx)
        }

        var args: [OSCValue] = []
        for tag in typeTags.dropFirst() {
            switch tag {
            case "i":
                guard let (v, ni) = readInt32(packet, from: idx) else { break }
                idx = ni
                args.append(.int32(v))
            case "f":
                guard let (v, ni) = readFloat32(packet, from: idx) else { break }
                idx = ni
                args.append(.float32(v))
            case "s":
                guard let (s, ni) = readOSCString(packet, from: idx) else { break }
                idx = ni
                args.append(.string(s))
            case "T":
                args.append(.bool(true))
            case "F":
                args.append(.bool(false))
            case "b":
                guard let (blob, ni) = readBlob(packet, from: idx) else { break }
                idx = ni
                args.append(.blob(blob))
            case "N":
                args.append(.null)
            case "I":
                args.append(.impulse)
            case "t":
                guard let (value, ni) = readUInt64(packet, from: idx) else { break }
                idx = ni
                args.append(.timetag(value))
            default:
                // Unknown tag -> stop parsing remaining
                break
            }
        }

        return DecodedMessageResult(message: OSCMessage(address: address, args: args), nextIndex: idx)
    }

    // MARK: - OSC Primitive Encoding

    private static func oscString(_ s: String) -> Data {
        var d = Data(s.utf8)
        d.append(0) // null terminator
        d.append(padTo4Bytes(count: d.count))
        return d
    }

    private static func oscInt32(_ v: Int32) -> Data {
        var be = v.bigEndian
        return Data(bytes: &be, count: 4)
    }

    private static func oscFloat32(_ v: Float) -> Data {
        var bits = v.bitPattern.bigEndian
        return Data(bytes: &bits, count: 4)
    }

    private static func oscUInt64(_ v: UInt64) -> Data {
        var be = v.bigEndian
        return Data(bytes: &be, count: 8)
    }


    private static func padTo4Bytes(count: Int) -> Data {
        let mod = count % 4
        if mod == 0 { return Data() }
        return Data(repeating: 0, count: 4 - mod)
    }

    // MARK: - OSC Primitive Decoding

    private static func readOSCString(_ data: Data, from index: Int) -> (String, Int)? {
        guard index < data.count else { return nil }
        var i = index
        while i < data.count, data[i] != 0 { i += 1 }
        guard i < data.count else { return nil } // need null

        let strData = data.subdata(in: index..<i)
        let s = String(data: strData, encoding: .utf8) ?? ""

        // advance to next 4-byte boundary after null terminator
        i += 1
        while i % 4 != 0 { i += 1 }
        guard i <= data.count else { return nil }
        return (s, i)
    }

    private static func readInt32(_ data: Data, from index: Int) -> (Int32, Int)? {
        guard index + 4 <= data.count else { return nil }
        let v = data[index..<index+4].withUnsafeBytes { $0.load(as: Int32.self) }.bigEndian
        return (v, index + 4)
    }

    private static func readFloat32(_ data: Data, from index: Int) -> (Float, Int)? {
        guard index + 4 <= data.count else { return nil }
        let bits = data[index..<index+4].withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        return (Float(bitPattern: bits), index + 4)
    }

    private static func readUInt64(_ data: Data, from index: Int) -> (UInt64, Int)? {
        guard index + 8 <= data.count else { return nil }
        let value = data[index..<index+8].withUnsafeBytes { $0.load(as: UInt64.self) }.bigEndian
        return (value, index + 8)
    }

    private static func readBlob(_ data: Data, from index: Int) -> (Data, Int)? {
        guard let (len32, idx1) = readInt32(data, from: index) else { return nil }
        let len = Int(len32)
        guard len >= 0, idx1 + len <= data.count else { return nil }
        let blob = data.subdata(in: idx1 ..< idx1 + len)
        var idx = idx1 + len
        while idx % 4 != 0 { idx += 1 }
        guard idx <= data.count else { return nil }
        return (blob, idx)
    }
}

// MARK: - Trigger / Cooldown helper (optional)

/// Use this in wireless triggers so you only fire on boundary crossings + cooldowns.
public final class TriggerCooldownGate {
    private var lastFireAt: [String: Date] = [:]
    private let queue = DispatchQueue(label: "com.prodlink.osc.cooldown")

    public init() {}

    /// Returns true if allowed to fire for `key`. If allowed, updates lastFire timestamp.
    public func allow(key: String, cooldownSeconds: Double) -> Bool {
        queue.sync {
            let now = Date()
            if let last = lastFireAt[key], now.timeIntervalSince(last) < cooldownSeconds {
                return false
            }
            lastFireAt[key] = now
            return true
        }
    }

    public func reset(key: String) {
        queue.sync { lastFireAt[key] = nil }
    }
}
