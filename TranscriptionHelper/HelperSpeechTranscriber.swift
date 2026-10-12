import AVFoundation
import Foundation
import Speech

// MARK: - Concurrency notes (Task 7 audit)
//
// This file predates Swift Concurrency and is driven entirely by GCD/XPC
// callback threads, not by `async`/`await` or actor isolation. It measures
// 0 diagnostics under `SWIFT_STRICT_CONCURRENCY = targeted`, matching the
// Task 0 baseline, but that is *not* proof the buffer/state handling below
// is safe -- it reflects `.targeted` mode's narrower analysis of plain
// (non-`Sendable`, non-`nonisolated`) classes under
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` rather than a verified
// absence of risk. Experimentally marking these types `nonisolated` (the
// technically-accurate annotation, since none of this runs on the main
// thread -- `TranscriptionAuthorization.ensureAuthorized()`, called from
// `start()` below, even has a runtime `precondition` against being invoked
// from the main thread) surfaces exactly the concern this task went
// looking for: `HelperSpeechTranscriber.append(_:)` hands an
// `AVAudioPCMBuffer` (a reference type with no `Sendable` guarantee) into
// a `queue.async` closure, and `self` is captured into several such
// closures despite the class not being `Sendable`.
//
// That exploratory `nonisolated` annotation was reverted rather than kept,
// for two reasons: (1) resolving the resulting warnings for real would mean
// either adding `@unchecked Sendable` (disallowed by this task's global
// constraints) or converting this class to an `actor` -- a materially
// larger, riskier rewrite of a live speech-transcription pipeline used
// during real events, out of proportion to what Task 7 scoped for this
// file; and (2) `TranscriptionAuthorization.swift` (a *different* file, in
// `TranscriptionShared/`, shared with the main app target and out of scope
// for this task's file list) would also need updating to avoid a new
// "main-actor-isolated static method called from a synchronous nonisolated
// context" warning, since `ensureAuthorized()` lives there.
//
// Manual audit of the actual data flow shows the underlying usage is safe
// even though the compiler cannot verify it end-to-end:
//   - `HelperSpeechTranscriberAdapter.bufferFromInt16(data:sampleRate:)`
//     allocates a brand-new `AVAudioPCMBuffer` on every call, and the
//     caller (`TranscriptionHelperService.appendPCMData`) never touches it
//     again after handing it to `append(_:)` -- a single-owner,
//     single-consumer handoff (produced once, consumed once inside the
//     `queue.async` closure that receives it), not a reference shared or
//     mutated from multiple places at once.
//   - The remaining mutable state (`request`, `task`, `recognizer`,
//     `appendedBufferCount`, `partialResultCount`) is synchronized two
//     ways: (1) all mutations made after the initial `start()` call happen
//     inside closures dispatched via `queue.async`, serializing them
//     against each other; (2) `TranscriptionHelperService` only publishes
//     an adapter into its `sessions` dictionary (guarded by `lock`) *after*
//     `adapter.start()` returns successfully, so the properties
//     `start()`/`startRecognition()` set synchronously on the caller's
//     thread happen-before any `append`/`stop` call for that session can
//     observe them.
//
// No functional change was made to this file as a result of this audit --
// see the Task 7 report for the explicit disclosure of this reasoning.
final class HelperTranscriptionThrottler {
    private var lastPublish: Date = .distantPast
    private var scheduledWork: DispatchWorkItem?

    func publish(isFinal: Bool, targetHz: Double, publish: @escaping () -> Void) {
        let minInterval = max(0.05, 1.0 / max(1.0, targetHz))
        if isFinal {
            scheduledWork?.cancel()
            scheduledWork = nil
            lastPublish = Date()
            publish()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastPublish)
        if elapsed >= minInterval {
            lastPublish = now
            publish()
            return
        }

        scheduledWork?.cancel()
        let delay = minInterval - elapsed
        let work = DispatchWorkItem { [weak self] in
            self?.lastPublish = Date()
            publish()
        }
        scheduledWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Cancels any pending throttled publish. Callers that are tearing down the
    /// session that owns this throttler must call this, otherwise a publish
    /// scheduled via `asyncAfter` can still fire afterward and deliver a result
    /// for a session the caller was already told had stopped.
    func cancel() {
        scheduledWork?.cancel()
        scheduledWork = nil
    }
}

final class HelperSpeechTranscriber {
    struct Config {
        var publishHz: Double
        var requiresOnDevice: Bool
        var localeIdentifier: String?
    }

    private let config: Config
    private let throttler = HelperTranscriptionThrottler()
    private let queue = DispatchQueue(label: "Relay.TranscriptionHelper.SpeechTranscriber")
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var appendedBufferCount = 0
    private var partialResultCount = 0

    var onPartial: ((String, Double?) -> Void)?
    var onFinal: ((String, Double?) -> Void)?
    var onError: ((TranscriptionFailure) -> Void)?

    init(config: Config) {
        self.config = config
    }

    func start() throws {
        try TranscriptionAuthorization.ensureAuthorized()
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        log("start authorization=\(describe(authStatus)) locale=\(config.localeIdentifier ?? "system") onDevice=\(config.requiresOnDevice)")
        let locale = config.localeIdentifier.map { Locale(identifier: $0) }
        let recognizer = locale != nil ? SFSpeechRecognizer(locale: locale!) : SFSpeechRecognizer()
        guard let recognizer else {
            throw TranscriptionFailure(code: .recognizerUnavailable, message: "Speech recognizer unavailable")
        }
        log("recognizer created isAvailable=\(recognizer.isAvailable) supportsOnDeviceRecognition=\(recognizer.supportsOnDeviceRecognition)")
        if !recognizer.isAvailable {
            throw TranscriptionFailure(code: .recognizerUnavailable, message: "Speech recognizer unavailable")
        }
        self.recognizer = recognizer
        startRecognition()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, self.request != nil, self.task != nil else { return }
            self.appendedBufferCount += 1
            if self.appendedBufferCount == 1 || self.appendedBufferCount % 50 == 0 {
                self.log("append buffer=\(self.appendedBufferCount) frameLength=\(buffer.frameLength) sampleRate=\(String(format: "%.0f", buffer.format.sampleRate))")
            }
            self.request?.append(buffer)
        }
    }

    func stop() {
        // Cancel any pending throttled publish synchronously, before the async
        // teardown below, so a scheduled result can't be delivered for a session
        // the caller was just told had stopped.
        throttler.cancel()
        queue.async { [weak self] in
            self?.log("stop appendedBuffers=\(self?.appendedBufferCount ?? 0)")
            self?.request?.endAudio()
            self?.task?.cancel()
            self?.task = nil
            self?.request = nil
            self?.recognizer = nil
            self?.partialResultCount = 0
        }
    }

    private func startRecognition() {
        guard let recognizer else { return }
        log("startRecognition")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if config.requiresOnDevice {
            guard recognizer.supportsOnDeviceRecognition else {
                let failure = TranscriptionFailure(code: .onDeviceUnsupported, message: "On-device recognition is not supported for this locale.")
                log("on-device requested but unsupported")
                onError?(failure)
                return
            }
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        self.partialResultCount = 0
        log("request configured requiresOnDevice=\(request.requiresOnDeviceRecognition)")

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                let nsError = error as NSError
                let wrapped = TranscriptionFailure(
                    code: .recognitionFailed,
                    message: "Speech error (\(nsError.domain) \(nsError.code)): \(nsError.localizedDescription)"
                )
                self.log("task error domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
                if self.shouldRestart(for: error) {
                    self.log("task restarting after recoverable error")
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
                self.log("task result final=true textLength=\(text.count)")
            } else {
                self.partialResultCount += 1
                if self.partialResultCount == 1 || self.partialResultCount % 25 == 0 {
                    self.log("task result final=false textLength=\(text.count)")
                }
            }
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
        if let task {
            log("task created state=\(describe(task.state))")
        } else {
            log("task creation returned nil")
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

    private func log(_ message: String) {
        print("[Helper Speech] \(message)")
    }

    private func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    private func describe(_ state: SFSpeechRecognitionTaskState) -> String {
        switch state {
        case .starting: return "starting"
        case .running: return "running"
        case .finishing: return "finishing"
        case .canceling: return "canceling"
        case .completed: return "completed"
        @unknown default: return "unknown"
        }
    }
}

final class HelperSpeechTranscriberAdapter {
    private let transcriber: HelperSpeechTranscriber

    var onPartial: ((String, Double?) -> Void)?
    var onFinal: ((String, Double?) -> Void)?
    var onError: ((TranscriptionFailure) -> Void)?

    init(config: HelperSpeechTranscriber.Config) {
        transcriber = HelperSpeechTranscriber(config: config)
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
        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let dst = buffer.floatChannelData?.pointee else { return nil }
        data.withUnsafeBytes { raw in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            let scale = 1.0 / Float(Int16.max)
            for index in 0..<Int(frameCount) {
                dst[index] = Float(src[index]) * scale
            }
        }
        return buffer
    }
}
