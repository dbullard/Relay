import Foundation
import AVFoundation

#if os(iOS)
/// iOS has one app-wide audio session and one active input route. These helpers set the
/// session up for measurement and pick the input port the user chose.
nonisolated enum MeasurementAudioSession {
    /// Older configs and the previous single-entry device list used this placeholder for
    /// "whatever the current route is".
    static let currentRouteUID = "current"

    /// Ensures the session can record, in `.measurement` mode — which turns off the
    /// automatic gain control and voice processing iOS otherwise applies to the mic, both
    /// of which make SPL readings wrong. A category that can already record (Live
    /// Transcription uses `.record`) is kept, so the two features don't fight.
    static func configureForMeasurement() {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category == .record || session.category == .playAndRecord {
                if session.mode != .measurement {
                    try session.setMode(.measurement)
                }
            } else {
                try session.setCategory(.playAndRecord, mode: .measurement,
                                        options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            }
            try session.setActive(true, options: [])
        } catch {
            // Capture start will fail and the watchdog will retry.
        }
    }

    /// Input ports available now (built-in mic, USB interfaces, wired headsets…).
    static func availableInputs() -> [AVAudioSessionPortDescription] {
        configureForMeasurement()
        return AVAudioSession.sharedInstance().availableInputs ?? []
    }

    /// Routes capture to the port with `uid` (nil/empty/"current" keeps the current route)
    /// and asks for enough channels to reach `channelIndex`.
    ///
    /// iOS records from one input port at a time, so if two Relay inputs name different
    /// ports, whichever started last wins.
    static func selectInput(uid: String?, channelIndex: Int) {
        let session = AVAudioSession.sharedInstance()
        if let uid, !uid.isEmpty, uid != currentRouteUID,
           let port = session.availableInputs?.first(where: { $0.uid == uid }),
           session.preferredInput?.uid != port.uid {
            try? session.setPreferredInput(port)
        }
        let wanted = min(max(1, channelIndex + 1), session.maximumInputNumberOfChannels)
        if wanted > session.inputNumberOfChannels {
            try? session.setPreferredInputNumberOfChannels(wanted)
        }
    }
}

nonisolated final class EngineInputCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "Relay.EngineInputCapture")
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Input port to record from (an `AVAudioSessionPortDescription.uid`); nil keeps the
    /// current route.
    var preferredInputUID: String?
    var channelIndex: Int = 0

    func start() throws {
        MeasurementAudioSession.configureForMeasurement()
        MeasurementAudioSession.selectInput(uid: preferredInputUID, channelIndex: channelIndex)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Relay.EngineInputCapture", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No audio input available"])
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let copied = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return }
            copied.frameLength = buffer.frameLength
            if let src = buffer.floatChannelData, let dst = copied.floatChannelData {
                let channels = Int(buffer.format.channelCount)
                let frames = Int(buffer.frameLength)
                for channel in 0..<channels {
                    memcpy(dst[channel], src[channel], frames * MemoryLayout<Float>.size)
                }
            } else {
                let srcList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
                let dstList = UnsafeMutableAudioBufferListPointer(copied.mutableAudioBufferList)
                for i in 0..<min(srcList.count, dstList.count) {
                    if let srcData = srcList[i].mData, let dstData = dstList[i].mData {
                        memcpy(dstData, srcData, Int(min(srcList[i].mDataByteSize, dstList[i].mDataByteSize)))
                    }
                }
            }

            self.queue.async { [weak self] in
                self?.onBuffer?(copied)
            }
        }

        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
#endif
