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
}
