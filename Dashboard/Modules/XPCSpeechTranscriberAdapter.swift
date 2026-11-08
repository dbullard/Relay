#if os(macOS)
import Foundation

final class XPCSpeechTranscriberAdapter: NSObject, SpeechTranscribing {
    private enum Constants {
        static let serviceName = "app.relay.Relay.TranscriptionHelper"
        static let appendLogInterval = 50
    }

    private static let connectionLock = NSLock()
    private static var sharedConnection: NSXPCConnection?

    private let config: SpeechTranscriber.Config
    private let sessionID = UUID().uuidString
    private var hasStarted = false
    private var appendedChunkCount = 0

    var onPartial: ((String, Double?) -> Void)?
    var onFinal: ((String, Double?) -> Void)?
    var onError: ((TranscriptionFailure) -> Void)?

    init(config: SpeechTranscriber.Config) {
        self.config = config
        super.init()
    }

    func start() throws {
        log("start requested locale=\(config.localeIdentifier ?? "system") onDevice=\(config.requiresOnDevice) publishHz=\(String(format: "%.1f", config.publishHz))")
        let connection = Self.connection()
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
        remoteProxy(for: Self.connection())?.appendPCMData(pcmData, sampleRate: sampleRate, sessionID: sessionID)
    }

    func stop() {
        guard hasStarted else {
            log("stop before start completed")
            TranscriptionHelperCallbackRouter.shared.unregister(sessionID: sessionID)
            return
        }

        log("stop requested after \(appendedChunkCount) chunks")
        remoteProxy(for: Self.connection())?.endSession(sessionID)
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

    private static func connection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let sharedConnection {
            return sharedConnection
        }

        let connection = makeConnection()
        sharedConnection = connection
        return connection
    }

    private static func makeConnection() -> NSXPCConnection {
        print("[Transcription XPC][Connection] creating service=\(Constants.serviceName)")
        let connection = NSXPCConnection(serviceName: Constants.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: TranscriptionHelperProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: TranscriptionHelperCallbackProtocol.self)
        connection.exportedObject = TranscriptionHelperCallbackRouter.shared
        connection.invalidationHandler = {
            print("[Transcription XPC][Connection] invalidated")
            connectionLock.lock()
            if sharedConnection === connection {
                sharedConnection = nil
            }
            connectionLock.unlock()
        }
        connection.interruptionHandler = {
            print("[Transcription XPC][Connection] interrupted")
            connectionLock.lock()
            if sharedConnection === connection {
                sharedConnection = nil
            }
            connectionLock.unlock()
        }
        connection.resume()
        print("[Transcription XPC][Connection] resumed")
        return connection
    }

    fileprivate func log(_ message: String) {
        print("[Transcription XPC][Adapter \(sessionID.prefix(8))] \(message)")
    }
}
#endif
