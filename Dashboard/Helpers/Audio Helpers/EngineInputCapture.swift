import Foundation
import AVFoundation

#if os(iOS)
final class EngineInputCapture {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "Relay.EngineInputCapture")
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

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
