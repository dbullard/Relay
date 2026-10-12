import Foundation
import AVFoundation

final class PCMDownmixer {
    private let channelIndex: Int
    private let floatConverter: AVAudioConverter?
    private let resampleConverter: AVAudioConverter?
    private let targetSampleRate: Double

    init(inputFormat: AVAudioFormat, channelIndex: Int, targetSampleRate: Double) {
        self.channelIndex = max(0, channelIndex)
        self.targetSampleRate = targetSampleRate
        if inputFormat.commonFormat == .pcmFormatFloat32,
           inputFormat.isInterleaved == false {
            self.floatConverter = nil
        } else {
            let floatFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: inputFormat.channelCount,
                interleaved: false
            )
            if let floatFormat {
                self.floatConverter = AVAudioConverter(from: inputFormat, to: floatFormat)
            } else {
                self.floatConverter = nil
            }
        }

        let monoInputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        )
        let monoOutputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )
        if let monoInputFormat, let monoOutputFormat {
            self.resampleConverter = AVAudioConverter(from: monoInputFormat, to: monoOutputFormat)
        } else {
            self.resampleConverter = nil
        }
    }

    func monoBuffer(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let floatBuffer = convertToFloatIfNeeded(buffer) else { return nil }
        guard let floatData = floatBuffer.floatChannelData else { return nil }
        let channelCount = Int(floatBuffer.format.channelCount)
        let targetChannel = min(channelIndex, max(0, channelCount - 1))
        let frameCount = Int(floatBuffer.frameLength)
        guard frameCount > 0 else { return nil }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: floatBuffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        monoBuffer.frameLength = AVAudioFrameCount(frameCount)

        let source = floatData[targetChannel]
        if let dst = monoBuffer.floatChannelData?.pointee {
            memcpy(dst, source, frameCount * MemoryLayout<Float>.size)
        }

        return resampleIfNeeded(monoBuffer)
    }

    private func resampleIfNeeded(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = resampleConverter else { return buffer }
        if abs(buffer.format.sampleRate - targetSampleRate) < 0.5 {
            return buffer
        }

        let ratio = targetSampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio).clamped(to: 1...UInt32.max)
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outCapacity) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: output, error: &error, withInputFrom: inputBlock)
        if error != nil {
            return nil
        }

        if output.frameLength == 0 {
            let expected = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            output.frameLength = min(expected, output.frameCapacity)
        }

        return output
    }

    private func convertToFloatIfNeeded(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if floatConverter == nil {
            return buffer
        }

        guard let converter = floatConverter else { return buffer }
        let floatFormat = converter.outputFormat
        guard let converted = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: buffer.frameCapacity) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        if error != nil {
            return nil
        }

        converted.frameLength = buffer.frameLength
        return converted
    }
}

private extension AVAudioFrameCount {
    func clamped(to range: ClosedRange<AVAudioFrameCount>) -> AVAudioFrameCount {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}
