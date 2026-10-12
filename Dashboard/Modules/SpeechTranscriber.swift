import Foundation
import AVFoundation
import Speech

protocol SpeechTranscribing: AnyObject {
    var onPartial: ((String, Double?) -> Void)? { get set }
    var onFinal: ((String, Double?) -> Void)? { get set }
    var onError: ((TranscriptionFailure) -> Void)? { get set }
    func start() throws
    func append(pcmData: Data, sampleRate: Double)
    func stop()
}

final class SpeechTranscriber {
    struct Config {
        var publishHz: Double
        var requiresOnDevice: Bool
        var localeIdentifier: String?
    }

    private let config: Config
    private let throttler = TranscriptionThrottler()
    private let queue = DispatchQueue(label: "Relay.SpeechTranscriber")
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var onPartial: ((String, Double?) -> Void)?
    var onFinal: ((String, Double?) -> Void)?
    var onError: ((TranscriptionFailure) -> Void)?

    init(config: Config) {
        self.config = config
    }

    static func supportsOnDevice(localeIdentifier: String?) -> Bool {
        let locale = localeIdentifier.map { Locale(identifier: $0) }
        let recognizer = locale != nil ? SFSpeechRecognizer(locale: locale!) : SFSpeechRecognizer()
        return recognizer?.supportsOnDeviceRecognition ?? false
    }

    static func resolvedLocaleIdentifier(preferred: String?) -> String? {
        guard let preferred else { return nil }
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let supported = Array(SFSpeechRecognizer.supportedLocales())
        let normalizedPreferred = normalizeLocaleIdentifier(trimmed)

        if let exact = supported.first(where: { normalizeLocaleIdentifier($0.identifier) == normalizedPreferred }) {
            if supportsOnDevice(localeIdentifier: exact.identifier) {
                return exact.identifier
            }
            if let lang = languageCodeIdentifier(for: exact),
               let onDeviceMatch = supported.first(where: { languageCodeIdentifier(for: $0) == lang && supportsOnDevice(localeIdentifier: $0.identifier) }) {
                return onDeviceMatch.identifier
            }
            return exact.identifier
        }

        let locale = Locale(identifier: trimmed)
        if let lang = languageCodeIdentifier(for: locale) {
            if let onDeviceMatch = supported.first(where: { languageCodeIdentifier(for: $0) == lang && supportsOnDevice(localeIdentifier: $0.identifier) }) {
                return onDeviceMatch.identifier
            }
            if let match = supported.first(where: { languageCodeIdentifier(for: $0) == lang }) {
                return match.identifier
            }
        }

        return nil
    }

    private static func normalizeLocaleIdentifier(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func languageCodeIdentifier(for locale: Locale) -> String? {
        if #available(macOS 13.0, iOS 16.0, *) {
            return locale.language.languageCode?.identifier
        }
        let normalized = locale.identifier.replacingOccurrences(of: "-", with: "_")
        let parts = normalized.split(separator: "_")
        return parts.first.map(String.init)
    }

    func start() throws {
        try TranscriptionAuthorization.ensureAuthorized()
        let locale = config.localeIdentifier.map { Locale(identifier: $0) }
        let recognizer = locale != nil ? SFSpeechRecognizer(locale: locale!) : SFSpeechRecognizer()
        guard let recognizer else {
            throw TranscriptionFailure(code: .recognizerUnavailable, message: "Speech recognizer unavailable")
        }
        if !recognizer.isAvailable {
            throw TranscriptionFailure(code: .recognizerUnavailable, message: "Speech recognizer unavailable")
        }
        self.recognizer = recognizer
        startRecognition()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, self.request != nil, self.task != nil else { return }
            self.request?.append(buffer)
        }
    }

    func stop() {
        // Cancel any pending throttled publish synchronously, before the async
        // teardown below, so a scheduled result can't be delivered for a session
        // the caller was just told had stopped. (Same ordering as
        // HelperSpeechTranscriber.stop(), which needed this explicitly after a
        // proven stale-transcript-after-stop bug in its sibling throttler.)
        throttler.cancel()
        queue.async { [weak self] in
            self?.request?.endAudio()
            self?.task?.cancel()
            self?.task = nil
            self?.request = nil
            self?.recognizer = nil
        }
    }

    private func startRecognition() {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if config.requiresOnDevice {
            guard recognizer.supportsOnDeviceRecognition else {
                let failure = TranscriptionFailure(code: .onDeviceUnsupported, message: "On-device recognition is not supported for this locale.")
                onError?(failure)
                return
            }
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] (result: SFSpeechRecognitionResult?, error: Error?) in
            guard let self else { return }
            if let error {
                let nsError = error as NSError
                let wrapped = TranscriptionFailure(
                    code: .recognitionFailed,
                    message: "Speech error (\(nsError.domain) \(nsError.code)): \(nsError.localizedDescription)"
                )
                if self.shouldRestart(for: error) {
                    self.queue.async { [weak self] in
                        self?.request?.endAudio()
                        self?.task?.cancel()
                        self?.task = nil
                        self?.request = nil
                        self?.startRecognition()
                    }
                    return
                }
                self.onError?(wrapped)
                return
            }
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            let confidence = result.bestTranscription.segments.last.map { Double($0.confidence) }
            if result.isFinal {
                self.throttler.publish(isFinal: true, targetHz: self.config.publishHz) { [weak self] in
                    self?.onFinal?(text, confidence)
                }
            } else {
                self.throttler.publish(isFinal: false, targetHz: self.config.publishHz) { [weak self] in
                    self?.onPartial?(text, confidence)
                }
            }
        }
    }

    private func shouldRestart(for error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "SFSpeechRecognizerErrorDomain" {
            if nsError.code == 203 {
                return true
            }
        }
        let lower = nsError.localizedDescription.lowercased()
        if lower.contains("no speech") {
            return true
        }
        return false
    }
}
final class InProcessSpeechTranscriberAdapter: SpeechTranscribing {
    private let transcriber: SpeechTranscriber

    var onPartial: ((String, Double?) -> Void)?
    var onFinal: ((String, Double?) -> Void)?
    var onError: ((TranscriptionFailure) -> Void)?

    init(config: SpeechTranscriber.Config) {
        transcriber = SpeechTranscriber(config: config)
        transcriber.onPartial = { [weak self] text, confidence in
            self?.onPartial?(text, confidence)
        }
        transcriber.onFinal = { [weak self] text, confidence in
            self?.onFinal?(text, confidence)
        }
        transcriber.onError = { [weak self] failure in
            self?.onError?(failure)
        }
    }

    func start() throws {
        try transcriber.start()
    }

    func append(pcmData: Data, sampleRate: Double) {
        guard let buffer = bufferFromInt16(data: pcmData, sampleRate: sampleRate) else { return }
        transcriber.append(buffer)
    }

    func stop() {
        transcriber.stop()
    }

    private func bufferFromInt16(data: Data, sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let dst = buffer.int16ChannelData?.pointee
        data.withUnsafeBytes { raw in
            if let src = raw.baseAddress, let dst {
                memcpy(dst, src, data.count)
            }
        }
        return buffer
    }
}

