#if os(macOS)
import Foundation

final class XPCSpeechTranscriberAdapter: NSObject, SpeechTranscribing {
    private enum Constants {
        static let appendLogInterval = 50
    }

    private static let connectionLock = NSLock()
    /// One connection per helper service. Each service is a separate process, and the
    /// Speech framework allows one recognition task per process.
    private static var connections: [String: NSXPCConnection] = [:]

    private let config: SpeechTranscriber.Config
    private let serviceName: String
    private let sessionID = UUID().uuidString
    private var hasStarted = false
    private var appendedChunkCount = 0

    var onPartial: ((String, Double?) -> Void)?
    var onFinal: ((String, Double?) -> Void)?
    var onError: ((TranscriptionFailure) -> Void)?

    init(config: SpeechTranscriber.Config, serviceName: String = TranscriptionEngineHost.helperServiceNames[0]) {
        self.config = config
        self.serviceName = serviceName
        super.init()
    }

    func start() throws {
        log("start requested service=\(serviceName) locale=\(config.localeIdentifier ?? "system") onDevice=\(config.requiresOnDevice) publishHz=\(String(format: "%.1f", config.publishHz))")
        let connection = Self.connection(serviceName: serviceName)
        guard let proxy = remoteProxy(for: connection) else {
            throw TranscriptionFailure(
                code: .connectionUnavailable,
                message: "Transcription helper proxy is unavailable. Check XPC service codesign and bundle ID."
            )
        }
        let semaphore = DispatchSemaphore(value: 0)
        var startupCode: Int32 = TranscriptionErrorCode.success.rawValue
        var startupMessage: String?

        TranscriptionHelperCallbackRouter.shared.register(sessionID: sessionID, adapter: self)
        proxy.createSession(
            sessionID,
            localeIdentifier: config.localeIdentifier,
            requiresOnDevice: config.requiresOnDevice,
            publishHz: config.publishHz
        ) { code, errorMessage in
            startupCode = code
            startupMessage = errorMessage
            semaphore.signal()
        }

        semaphore.wait()

        if startupCode != TranscriptionErrorCode.success.rawValue {
            let message = startupMessage ?? "Transcription session failed to start."
            log("start failed: \(message)")
            TranscriptionHelperCallbackRouter.shared.unregister(sessionID: sessionID)
            throw TranscriptionFailure(code: TranscriptionErrorCode(rawValue: startupCode) ?? .unknown, message: message)
        }

        hasStarted = true
        log("start succeeded")
    }

    func append(pcmData: Data, sampleRate: Double) {
        guard hasStarted else { return }
        appendedChunkCount += 1
        if appendedChunkCount == 1 || appendedChunkCount % Constants.appendLogInterval == 0 {
            log("append chunk=\(appendedChunkCount) bytes=\(pcmData.count) sampleRate=\(String(format: "%.0f", sampleRate))")
        }
        remoteProxy(for: Self.connection(serviceName: serviceName))?.appendPCMData(pcmData, sampleRate: sampleRate, sessionID: sessionID)
    }

    func stop() {
        guard hasStarted else {
            log("stop before start completed")
            TranscriptionHelperCallbackRouter.shared.unregister(sessionID: sessionID)
            return
        }

        log("stop requested after \(appendedChunkCount) chunks")
        remoteProxy(for: Self.connection(serviceName: serviceName))?.endSession(sessionID)
        hasStarted = false
        TranscriptionHelperCallbackRouter.shared.unregister(sessionID: sessionID)
    }

    private func remoteProxy(for connection: NSXPCConnection) -> TranscriptionHelperProtocol? {
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                self?.log("remote proxy error: \(error.localizedDescription)")
                self?.onError?(TranscriptionFailure(code: .connectionUnavailable, message: error.localizedDescription))
            }
        }

        guard let typedProxy = proxy as? TranscriptionHelperProtocol else {
            let msg = "Transcription helper proxy is unavailable. Check XPC service codesign and bundle ID."
            log(msg)
            onError?(TranscriptionFailure(code: .connectionUnavailable, message: msg))
            return nil
        }

        return typedProxy
    }

    private static func connection(serviceName: String) -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = connections[serviceName] {
            return existing
        }

        let connection = makeConnection(serviceName: serviceName)
        connections[serviceName] = connection
        return connection
    }

    private static func makeConnection(serviceName: String) -> NSXPCConnection {
        print("[Transcription XPC][Connection] creating service=\(serviceName)")
        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: TranscriptionHelperProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: TranscriptionHelperCallbackProtocol.self)
        connection.exportedObject = TranscriptionHelperCallbackRouter.shared
        connection.invalidationHandler = { [weak connection] in
            print("[Transcription XPC][Connection] invalidated service=\(serviceName)")
            forget(connection, serviceName: serviceName)
        }
        connection.interruptionHandler = { [weak connection] in
            print("[Transcription XPC][Connection] interrupted service=\(serviceName)")
            forget(connection, serviceName: serviceName)
        }
        connection.resume()
        print("[Transcription XPC][Connection] resumed")
        return connection
    }

    private static func forget(_ connection: NSXPCConnection?, serviceName: String) {
        connectionLock.lock()
        if let connection, connections[serviceName] === connection {
            connections[serviceName] = nil
        }
        connectionLock.unlock()
    }

    fileprivate func log(_ message: String) {
        print("[Transcription XPC][Adapter \(sessionID.prefix(8))] \(message)")
    }
}
#endif
