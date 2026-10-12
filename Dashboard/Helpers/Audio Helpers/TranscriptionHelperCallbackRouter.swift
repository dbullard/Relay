#if os(macOS)
import Foundation

private final class WeakTranscriptionAdapterBox {
    weak var value: XPCSpeechTranscriberAdapter?

    init(value: XPCSpeechTranscriberAdapter?) {
        self.value = value
    }
}

final class TranscriptionHelperCallbackRouter: NSObject, TranscriptionHelperCallbackProtocol {
    static let shared = TranscriptionHelperCallbackRouter()

    private let lock = NSLock()
    private var adaptersBySessionID: [String: WeakTranscriptionAdapterBox] = [:]

    func register(sessionID: String, adapter: XPCSpeechTranscriberAdapter) {
        lock.lock()
        adaptersBySessionID[sessionID] = WeakTranscriptionAdapterBox(value: adapter)
        let count = adaptersBySessionID.count
        lock.unlock()
        print("[Transcription XPC][Router \(sessionID.prefix(8))] registered activeSessions=\(count)")
    }

    func unregister(sessionID: String) {
        lock.lock()
        adaptersBySessionID.removeValue(forKey: sessionID)
        let count = adaptersBySessionID.count
        lock.unlock()
        print("[Transcription XPC][Router \(sessionID.prefix(8))] unregistered activeSessions=\(count)")
    }

    func session(_ sessionID: String, didReceivePartial text: String, confidence: Double) {
        print("[Transcription XPC][Router \(sessionID.prefix(8))] partial textLength=\(text.count) confidence=\(formatConfidence(confidence))")
        dispatchToAdapter(sessionID: sessionID) { adapter in
            adapter.onPartial?(text, confidence.isFinite ? confidence : nil)
        }
    }

    func session(_ sessionID: String, didReceiveFinal text: String, confidence: Double) {
        print("[Transcription XPC][Router \(sessionID.prefix(8))] final textLength=\(text.count) confidence=\(formatConfidence(confidence))")
        dispatchToAdapter(sessionID: sessionID) { adapter in
            adapter.onFinal?(text, confidence.isFinite ? confidence : nil)
        }
    }

    func session(_ sessionID: String, didEncounterError code: Int32, message: String) {
        print("[Transcription XPC][Router \(sessionID.prefix(8))] error \(message)")
        let failure = TranscriptionFailure(code: TranscriptionErrorCode(rawValue: code) ?? .unknown, message: message)
        dispatchToAdapter(sessionID: sessionID) { adapter in
            adapter.onError?(failure)
        }
    }

    private func dispatchToAdapter(sessionID: String, action: @escaping (XPCSpeechTranscriberAdapter) -> Void) {
        let adapter: XPCSpeechTranscriberAdapter?
        lock.lock()
        let box = adaptersBySessionID[sessionID]
        adapter = box?.value
        if box?.value == nil {
            adaptersBySessionID.removeValue(forKey: sessionID)
        }
        lock.unlock()

        guard let adapter else {
            print("[Transcription XPC][Router \(sessionID.prefix(8))] dropped callback: adapter missing")
            return
        }
        DispatchQueue.main.async {
            action(adapter)
        }
    }

    private func formatConfidence(_ confidence: Double) -> String {
        guard confidence.isFinite else { return "n/a" }
        return String(format: "%.3f", confidence)
    }
}
#endif
