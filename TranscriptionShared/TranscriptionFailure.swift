import Foundation

enum TranscriptionErrorCode: Int32, Sendable {
    case success = 0                // success sentinel, only used in createSession's reply
    case unknown = 1
    case permissionDenied = 2
    case recognizerUnavailable = 3
    case onDeviceUnsupported = 4
    case recognitionFailed = 5
    case connectionUnavailable = 6 // client-side only: XPC helper/connection itself unreachable
}

struct TranscriptionFailure: Error, LocalizedError, Sendable {
    let code: TranscriptionErrorCode
    let message: String

    var errorDescription: String? { message }
}
