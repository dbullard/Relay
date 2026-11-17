import Foundation

@objc protocol TranscriptionHelperProtocol {
    func createSession(
        _ sessionID: String,
        localeIdentifier: String?,
        requiresOnDevice: Bool,
        publishHz: Double,
        withReply reply: @escaping (Int32, String?) -> Void
    )

    func appendPCMData(_ data: Data, sampleRate: Double, sessionID: String)
    func endSession(_ sessionID: String)
}

@objc protocol TranscriptionHelperCallbackProtocol {
    func session(_ sessionID: String, didReceivePartial text: String, confidence: Double)
    func session(_ sessionID: String, didReceiveFinal text: String, confidence: Double)
    func session(_ sessionID: String, didEncounterError code: Int32, message: String)
    /// Diagnostic line from the helper. An XPC service's stdout goes nowhere, so the
    /// helper forwards its log lines here and the app writes them to RelayLogs.
    func session(_ sessionID: String, didLog message: String)
}
