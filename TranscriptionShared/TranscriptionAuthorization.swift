import Speech

enum TranscriptionAuthorization {
    /// Resolves the current authorization decision, requesting it if not yet
    /// determined. Safe to call from any thread, including the main thread,
    /// as long as authorization has already been determined (the common case
    /// for both production call sites, which resolve it asynchronously ahead
    /// of time via `SFSpeechRecognizer.requestAuthorization`'s completion
    /// handler before ever reaching this function). Only the not-yet-determined
    /// path below blocks synchronously on that same completion handler, which
    /// the system dispatches back to the main queue -- calling this function
    /// from the main thread while authorization is still undetermined would
    /// deadlock, so that specific path is guarded with a precondition instead
    /// of being allowed to hang silently.
    static func ensureAuthorized() throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        let resolvedStatus: SFSpeechRecognizerAuthorizationStatus
        if status == .notDetermined {
            precondition(!Thread.isMainThread, "TranscriptionAuthorization.ensureAuthorized() must not request authorization from the main thread while status is still undetermined -- it would block synchronously on a completion handler that the system dispatches back to the main queue, which would deadlock.")
            let semaphore = DispatchSemaphore(value: 0)
            var result = status
            SFSpeechRecognizer.requestAuthorization { newStatus in
                result = newStatus
                semaphore.signal()
            }
            semaphore.wait()
            resolvedStatus = result
        } else {
            resolvedStatus = status
        }

        switch resolvedStatus {
        case .authorized:
            return
        case .denied, .restricted:
            throw TranscriptionFailure(
                code: .permissionDenied,
                message: "Speech recognition permission was denied. Enable it in System Settings > Privacy & Security > Speech Recognition."
            )
        case .notDetermined:
            throw TranscriptionFailure(code: .permissionDenied, message: "Speech recognition permission has not been granted yet.")
        @unknown default:
            throw TranscriptionFailure(code: .permissionDenied, message: "Speech recognition permission is unavailable.")
        }
    }
}
