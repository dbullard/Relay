#if os(macOS)
import AppKit
import AVFoundation
import Speech
import XCTest
@testable import Relay

/// Live probe of the real speech pipelines: synthesized speech is fed through the
/// in-process transcriber and the XPC helper, with on-device and server recognition.
/// It needs speech-recognition permission and (for server recognition) the network,
/// so it only runs when `RELAY_SPEECH_PROBE=1` is set in the test environment
/// (`TEST_RUNNER_RELAY_SPEECH_PROBE=1 xcodebuild test ...`).
///
/// Two tasks in the same process fail (see `TranscriptionSlotPlanner`), so the
/// concurrent case covered here is the one Relay uses: one task per process.
final class SpeechRecognitionProbeTests: XCTestCase {
    private struct ProbeResult {
        var partials: [String] = []
        var finals: [String] = []
        var errors: [String] = []
        var bestText: String { finals.last ?? partials.last ?? "" }
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RELAY_SPEECH_PROBE"] == "1",
                          "Set RELAY_SPEECH_PROBE=1 to run the live speech probe.")
        try ensureSpeechAuthorization()
    }

    func testInProcessOnDevice() throws {
        try runProbe(label: "in-process on-device", requiresOnDevice: true) { InProcessSpeechTranscriberAdapter(config: $0) }
    }

    func testInProcessServer() throws {
        try runProbe(label: "in-process server", requiresOnDevice: false) { InProcessSpeechTranscriberAdapter(config: $0) }
    }

    func testHelperOnDevice() throws {
        try runProbe(label: "helper on-device", requiresOnDevice: true) { XPCSpeechTranscriberAdapter(config: $0) }
    }

    func testHelperServer() throws {
        try runProbe(label: "helper server", requiresOnDevice: false) { XPCSpeechTranscriberAdapter(config: $0) }
    }

    func testInProcessAndHelperAtOnce() throws {
        try runConcurrent(label: "in-process + helper", [
            (InProcessSpeechTranscriberAdapter(config: config(onDevice: false)), true),
            (XPCSpeechTranscriberAdapter(config: config(onDevice: false)), true),
        ])
    }

    /// Every slot the planner hands out, at once.
    func testAllSlotsAtOnce() throws {
        let transcribers: [(SpeechTranscribing, Bool)] = TranscriptionSlotPlanner.hosts.map { host in
            if let serviceName = host.helperServiceName {
                return (XPCSpeechTranscriberAdapter(config: config(onDevice: false), serviceName: serviceName), true)
            }
            return (InProcessSpeechTranscriberAdapter(config: config(onDevice: false)), true)
        }
        try runConcurrent(label: "all slots", transcribers)
    }

    private func config(onDevice: Bool) -> Relay.SpeechTranscriber.Config {
        Relay.SpeechTranscriber.Config(publishHz: 5, requiresOnDevice: onDevice, localeIdentifier: nil)
    }

    /// Runs the transcribers at once; only those flagged `true` are fed audio and expected to return text.
    private func runConcurrent(label: String, _ transcribers: [(SpeechTranscribing, Bool)]) throws {
        let chunks = try synthesizedSpeechChunks()
        var results = Array(repeating: ProbeResult(), count: transcribers.count)
        for (index, (transcriber, _)) in transcribers.enumerated() {
            transcriber.onPartial = { text, _ in results[index].partials.append(text) }
            transcriber.onFinal = { text, _ in results[index].finals.append(text) }
            transcriber.onError = { failure in results[index].errors.append(failure.message) }
            try transcriber.start()
        }
        for chunk in chunks {
            for (transcriber, fed) in transcribers where fed {
                transcriber.append(pcmData: chunk, sampleRate: 16000)
            }
            spin(0.02)
        }
        waitUntil(timeout: 15) {
            transcribers.indices.allSatisfy { !transcribers[$0].1 || !results[$0].bestText.isEmpty }
        }
        transcribers.forEach { $0.0.stop() }
        spin(0.5)
        for (index, result) in results.enumerated() where transcribers[index].1 {
            print("[SpeechProbe] \(label) #\(index) text=\"\(result.bestText)\" partials=\(result.partials.count) finals=\(result.finals.count) errors=\(result.errors)")
            XCTAssertFalse(result.bestText.isEmpty, "\(label) #\(index) returned no text; errors=\(result.errors)")
        }
    }

    // MARK: - Helpers

    private func runProbe(
        label: String,
        requiresOnDevice: Bool,
        make: (Relay.SpeechTranscriber.Config) -> SpeechTranscribing
    ) throws {
        if requiresOnDevice, !Relay.SpeechTranscriber.supportsOnDevice(localeIdentifier: nil) {
            throw XCTSkip("On-device recognition unsupported for the system locale.")
        }
        let chunks = try synthesizedSpeechChunks()
        let transcriber = make(Relay.SpeechTranscriber.Config(publishHz: 5, requiresOnDevice: requiresOnDevice, localeIdentifier: nil))
        var result = ProbeResult()
        transcriber.onPartial = { text, _ in result.partials.append(text) }
        transcriber.onFinal = { text, _ in result.finals.append(text) }
        transcriber.onError = { failure in result.errors.append(failure.message) }
        try transcriber.start()
        for chunk in chunks {
            transcriber.append(pcmData: chunk, sampleRate: 16000)
            spin(0.02)
        }
        waitUntil(timeout: 20) { !result.bestText.isEmpty }
        transcriber.stop()
        print("[SpeechProbe] \(label) text=\"\(result.bestText)\" partials=\(result.partials.count) finals=\(result.finals.count) errors=\(result.errors)")
        XCTAssertFalse(result.bestText.isEmpty, "\(label) returned no text; errors=\(result.errors)")
    }

    private func ensureSpeechAuthorization() throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            let done = expectation(description: "speech authorization")
            SFSpeechRecognizer.requestAuthorization { newStatus in
                status = newStatus
                done.fulfill()
            }
            wait(for: [done], timeout: 30)
        }
        try XCTSkipUnless(status == .authorized, "Speech recognition is not authorized for the test host.")
    }

    /// Speech synthesized to a file, converted to the pipeline's wire format:
    /// 16 kHz mono Int16 in 3200-byte (0.1 s) chunks.
    private func synthesizedSpeechChunks() throws -> [Data] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-speech-probe-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let synthesizer = NSSpeechSynthesizer()
        XCTAssertTrue(synthesizer.startSpeaking(
            "Good morning everyone. Please welcome our first speaker to the stage. The quick brown fox jumps over the lazy dog.",
            to: url
        ))
        waitUntil(timeout: 30) { !synthesizer.isSpeaking }

        let file = try AVAudioFile(forReading: url)
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let converter = try XCTUnwrap(AVAudioConverter(from: file.processingFormat, to: target))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: input)
        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024))
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }

        let samples = UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            var value = Int16(max(-1, min(1, sample)) * Float(Int16.max))
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        // A second of silence lets the recognizer close the utterance.
        pcm.append(Data(count: 32000))
        return stride(from: 0, to: pcm.count, by: 3200).map { pcm.subdata(in: $0..<min($0 + 3200, pcm.count)) }
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            spin(0.05)
        }
    }
}
#endif
