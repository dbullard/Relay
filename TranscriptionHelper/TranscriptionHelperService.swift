import Foundation

nonisolated final class TranscriptionHelperService: NSObject, TranscriptionHelperProtocol {
    private enum Constants {
        static let appendLogInterval = 50
    }

    private let lock = NSLock()
    private var sessions: [String: HelperSpeechTranscriberAdapter] = [:]
    private var appendCounts: [String: Int] = [:]
    private let callbackConnection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.callbackConnection = connection
    }

    func createSession(
        _ sessionID: String,
        localeIdentifier: String?,
        requiresOnDevice: Bool,
        publishHz: Double,
        withReply reply: @escaping (Int32, String?) -> Void
    ) {
        log(sessionID, "createSession locale=\(localeIdentifier ?? "system") onDevice=\(requiresOnDevice) publishHz=\(String(format: "%.1f", publishHz))")
        let config = HelperSpeechTranscriber.Config(
            publishHz: publishHz,
            requiresOnDevice: requiresOnDevice,
            localeIdentifier: localeIdentifier
        )
        let adapter = HelperSpeechTranscriberAdapter(config: config)

        adapter.onPartial = { [weak self] text, confidence in
            self?.callbackProxy()?.session(sessionID, didReceivePartial: text, confidence: confidence ?? .nan)
        }
        adapter.onFinal = { [weak self] text, confidence in
            self?.callbackProxy()?.session(sessionID, didReceiveFinal: text, confidence: confidence ?? .nan)
        }
        adapter.onError = { [weak self] failure in
            self?.callbackProxy()?.session(sessionID, didEncounterError: failure.code.rawValue, message: failure.message)
        }

        do {
            try adapter.start()
            lock.lock()
            sessions[sessionID] = adapter
            appendCounts[sessionID] = 0
            let count = sessions.count
            lock.unlock()
            log(sessionID, "session started activeSessions=\(count)")
            reply(TranscriptionErrorCode.success.rawValue, nil)
        } catch {
            let failure = (error as? TranscriptionFailure) ?? TranscriptionFailure(code: .unknown, message: error.localizedDescription)
            log(sessionID, "session start failed: \(failure.message)")
            reply(failure.code.rawValue, failure.message)
        }
    }

    func appendPCMData(_ data: Data, sampleRate: Double, sessionID: String) {
        lock.lock()
        let count = (appendCounts[sessionID] ?? 0) + 1
        appendCounts[sessionID] = count
        lock.unlock()
        if count == 1 || count % Constants.appendLogInterval == 0 {
            log(sessionID, "append chunk=\(count) bytes=\(data.count) sampleRate=\(String(format: "%.0f", sampleRate))")
        }
        session(for: sessionID)?.append(pcmData: data, sampleRate: sampleRate)
    }

    func endSession(_ sessionID: String) {
        lock.lock()
        let adapter = sessions.removeValue(forKey: sessionID)
        let appendCount = appendCounts.removeValue(forKey: sessionID) ?? 0
        let count = sessions.count
        lock.unlock()
        log(sessionID, "endSession chunks=\(appendCount) remainingSessions=\(count)")
        adapter?.stop()
    }

    private func session(for sessionID: String) -> HelperSpeechTranscriberAdapter? {
        lock.lock()
        let session = sessions[sessionID]
        lock.unlock()
        return session
    }

    private func callbackProxy() -> TranscriptionHelperCallbackProtocol? {
        let proxy = callbackConnection.remoteObjectProxyWithErrorHandler { error in
            NSLog("TranscriptionHelper callback error: %@", error.localizedDescription)
        }
        return proxy as? TranscriptionHelperCallbackProtocol
    }

    private func log(_ sessionID: String, _ message: String) {
        print("[Transcription Helper][\(sessionID.prefix(8))] \(message)")
    }
}
