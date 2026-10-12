import Foundation
@preconcurrency import AVFoundation

#if os(macOS)
import AudioToolbox
import CoreAudio

nonisolated final class DeviceInputCaptureHAL {
    private let deviceId: AudioDeviceID
    private let queue = DispatchQueue(label: "Relay.DeviceInputCaptureHAL")
    private var audioUnit: AudioUnit?
    private var format: AudioStreamBasicDescription?
    private var inputGainScalar: Double = 1.0
    private var isRunning = false
    private var didLogFormat = false
    private var didLogChannelPeaks = false
    private var didLogRenderCallback = false
    private var didLogBufferState = false
    private var didLogRenderFailure = false
    private var didLogConversionPeak = false
    private var silentBufferCount = 0
    private var renderBufferListPointer: UnsafeMutableRawPointer?
    private var renderAllocatedBuffers: [UnsafeMutableRawPointer] = []
    private var renderBufferCapacityFrames: UInt32 = 0
    private var renderBufferCount: Int = 0
    private var monoBufferPool: [AVAudioPCMBuffer] = []
    private var monoBufferPoolIndex = 0

    var channelIndex: Int = 0
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    init(deviceId: AudioDeviceID) {
        self.deviceId = deviceId
    }

    private func deviceStreamFormat() -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &asbd)
        guard status == noErr, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else {
            return nil
        }
        return asbd
    }

    private func deviceInputGainScalar(for channel: Int) -> Double {
        func readScalar(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Double? {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            guard AudioObjectHasProperty(deviceId, &address) else { return nil }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &value)
            guard status == noErr, value.isFinite, value > 0 else { return nil }
            return Double(value)
        }

        let element = AudioObjectPropertyElement(channel + 1)
        if let scalar = readScalar(kAudioDevicePropertyVolumeScalar, element: element) {
            return scalar
        }

        if let scalar = readScalar(kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return scalar
        }

        return 1.0
    }

    func start() throws {
        if isRunning { return }
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "Relay.DeviceInputCaptureHAL", code: -1, userInfo: [NSLocalizedDescriptionKey: "HAL audio component not found"]) 
        }

        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(comp, &unit)
        guard status == noErr, let audioUnit = unit else {
            throw NSError(domain: "Relay.DeviceInputCaptureHAL", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Unable to create audio unit"]) 
        }

        var enableIO: UInt32 = 1
        status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableIO, UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else { throw error(status) }

        var disableIO: UInt32 = 0
        status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disableIO, UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else { throw error(status) }

        var currentDevice = deviceId
        status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &currentDevice, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw error(status) }

        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd, &asbdSize)

        let desiredChannels = max(1, AudioDeviceEnumerator.inputChannelCount(deviceId: deviceId))
        if let deviceFormat = deviceStreamFormat() {
            asbd = deviceFormat
        } else if status != noErr || asbd.mFormatID != kAudioFormatLinearPCM {
            // Fallback to a safe float format if the unit format is unusable.
            let channelCount = max(1, desiredChannels)
            let sampleRate = asbd.mSampleRate > 0
                ? asbd.mSampleRate
                : (AudioDeviceEnumerator.inputSampleRate(deviceId: deviceId) ?? 44100)
            let bytesPerFrame = UInt32(MemoryLayout<Float>.size * channelCount)
            asbd = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: bytesPerFrame,
                mFramesPerPacket: 1,
                mBytesPerFrame: bytesPerFrame,
                mChannelsPerFrame: UInt32(channelCount),
                mBitsPerChannel: 32,
                mReserved: 0
            )
        }

        status = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw error(status) }

        var callback = AURenderCallbackStruct(
            inputProc: { inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData in
                let capture = Unmanaged<DeviceInputCaptureHAL>.fromOpaque(inRefCon).takeUnretainedValue()
                return capture.render(ioActionFlags: ioActionFlags, timeStamp: inTimeStamp, busNumber: inBusNumber, frameCount: inNumberFrames)
            },
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw error(status) }

        status = AudioUnitInitialize(audioUnit)
        guard status == noErr else { throw error(status) }

        prepareRenderBuffers(audioUnit: audioUnit, format: asbd)

        self.audioUnit = audioUnit
        self.format = asbd

        inputGainScalar = deviceInputGainScalar(for: channelIndex)

        didLogChannelPeaks = false
        didLogRenderCallback = false
        didLogBufferState = false
        didLogRenderFailure = false
        didLogConversionPeak = false
        silentBufferCount = 0

        if !didLogFormat {
            didLogFormat = true
            let flags = String(format: "0x%08X", asbd.mFormatFlags)
            let formatDescription = "HAL format: sr=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame) bits=\(asbd.mBitsPerChannel) bytesPF=\(asbd.mBytesPerFrame) flags=\(flags) desiredCh=\(desiredChannels)"
            #if DEBUG
            print("[Audio HAL] \(formatDescription)")
            #endif
        }

        #if DEBUG
        if inputGainScalar != 1.0 {
            print("[Audio HAL] input gain scalar=\(String(format: "%.3f", inputGainScalar)) channel=\(channelIndex + 1)")
        }
        #endif

        status = AudioOutputUnitStart(audioUnit)
        guard status == noErr else { throw error(status) }
        isRunning = true
    }

    func stop() {
        guard let audioUnit else { return }
        if isRunning {
            AudioOutputUnitStop(audioUnit)
        }
        AudioUnitUninitialize(audioUnit)
        AudioComponentInstanceDispose(audioUnit)
        self.audioUnit = nil
        cleanupRenderBuffers()
        isRunning = false
    }

    private func prepareRenderBuffers(audioUnit: AudioUnit, format: AudioStreamBasicDescription) {
        cleanupRenderBuffers()

        var maxFrames: UInt32 = 0
        var maxFramesSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maxFrames,
            &maxFramesSize
        )
        if status != noErr || maxFrames == 0 {
            maxFrames = 4096
        }
        let frameCapacity = max(maxFrames, 8192)
        let isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bufferCount = isNonInterleaved ? max(1, Int(format.mChannelsPerFrame)) : 1
        let bytesPerFrame = max(1, Int(format.mBytesPerFrame))
        let byteSizePerBuffer = Int(frameCapacity) * bytesPerFrame
        let bufferListSize = MemoryLayout<AudioBufferList>.size
            + (max(0, bufferCount - 1) * MemoryLayout<AudioBuffer>.size)

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        let audioBufferList = pointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        audioBufferList.pointee.mNumberBuffers = UInt32(bufferCount)

        let listPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        var allocatedBuffers: [UnsafeMutableRawPointer] = []
        allocatedBuffers.reserveCapacity(bufferCount)

        for index in 0..<bufferCount {
            let data = UnsafeMutableRawPointer.allocate(
                byteCount: byteSizePerBuffer,
                alignment: MemoryLayout<UInt32>.alignment
            )
            allocatedBuffers.append(data)
            listPointer[index].mData = data
            listPointer[index].mDataByteSize = UInt32(byteSizePerBuffer)
            listPointer[index].mNumberChannels = isNonInterleaved ? 1 : format.mChannelsPerFrame
        }

        renderBufferListPointer = pointer
        renderAllocatedBuffers = allocatedBuffers
        renderBufferCapacityFrames = frameCapacity
        renderBufferCount = bufferCount

        if let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.mSampleRate, channels: 1) {
            monoBufferPool = (0..<8).compactMap { _ in
                AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCapacity)
            }
        } else {
            monoBufferPool = []
        }
        monoBufferPoolIndex = 0
    }

    private func cleanupRenderBuffers() {
        renderAllocatedBuffers.forEach { $0.deallocate() }
        renderAllocatedBuffers.removeAll()
        renderBufferListPointer?.deallocate()
        renderBufferListPointer = nil
        renderBufferCapacityFrames = 0
        renderBufferCount = 0
        monoBufferPool.removeAll()
        monoBufferPoolIndex = 0
    }

    private func render(ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timeStamp: UnsafePointer<AudioTimeStamp>, busNumber: UInt32, frameCount: UInt32) -> OSStatus {
        guard let audioUnit, let format else { return noErr }

        if !didLogRenderCallback {
            didLogRenderCallback = true
            #if DEBUG
            print("[Audio HAL] HAL render callback active")
            #endif
        }

        let stream = format

        let isNonInterleaved = (stream.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bufferCount = isNonInterleaved ? Int(stream.mChannelsPerFrame) : 1
        let bytesPerFrame = max(1, Int(stream.mBytesPerFrame))
        let byteSizePerBuffer = Int(frameCount) * bytesPerFrame
        guard frameCount <= renderBufferCapacityFrames,
              bufferCount == renderBufferCount,
              let bufferListPointer = renderBufferListPointer else {
            return noErr
        }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let listPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for index in 0..<bufferCount {
            listPointer[index].mDataByteSize = UInt32(byteSizePerBuffer)
            listPointer[index].mNumberChannels = isNonInterleaved ? 1 : stream.mChannelsPerFrame
        }

        let renderBus = busNumber
        let renderStatus = AudioUnitRender(audioUnit, ioActionFlags, timeStamp, renderBus, frameCount, audioBufferList)
        guard renderStatus == noErr else {
            if !didLogRenderFailure {
                didLogRenderFailure = true
                let flags = String(format: "0x%08X", stream.mFormatFlags)
                DispatchQueue.main.async {
                    RelayDiagnosticsStore.shared.recordError(
                        "HAL render failed: \(renderStatus) bus=\(renderBus) sr=\(stream.mSampleRate) ch=\(stream.mChannelsPerFrame) bits=\(stream.mBitsPerChannel) bytesPF=\(stream.mBytesPerFrame) flags=\(flags)",
                        tag: "Audio HAL"
                    )
                }
            }
            return renderStatus
        }

        let srcList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        if !didLogBufferState {
            didLogBufferState = true
            let flags = String(format: "0x%08X", stream.mFormatFlags)
            let firstBytes = srcList.first?.mDataByteSize ?? 0
            let hasData = srcList.first?.mData != nil
            #if DEBUG
            print("[Audio HAL] HAL buffers=\(srcList.count) firstBytes=\(firstBytes) hasData=\(hasData) frameCount=\(frameCount) flags=\(flags)")
            #endif
        }

        if let first = srcList.first, let data = first.mData {
            let frameLimit = min(128, Int(frameCount))
            let channels = max(1, Int(stream.mChannelsPerFrame))
            var peak: Double = 0

            if (stream.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
                let stride = channels
                let base = data.bindMemory(to: Float.self, capacity: frameLimit * stride)
                for i in 0..<frameLimit {
                    let sample = Double(abs(base[i * stride]))
                    if sample > peak { peak = sample }
                }
            } else if stream.mBitsPerChannel == 16 {
                let stride = channels
                let base = data.bindMemory(to: Int16.self, capacity: frameLimit * stride)
                let denom = Double(Int16.max)
                for i in 0..<frameLimit {
                    let sample = Double(abs(base[i * stride])) / denom
                    if sample > peak { peak = sample }
                }
            } else if stream.mBitsPerChannel == 32 {
                let stride = channels
                let base = data.bindMemory(to: Int32.self, capacity: frameLimit * stride)
                let denom = Double(Int32.max)
                for i in 0..<frameLimit {
                    let sample = Double(abs(base[i * stride])) / denom
                    if sample > peak { peak = sample }
                }
            }

            if peak < 1.0e-7 {
                silentBufferCount += 1
                if silentBufferCount == 30 {
                    #if DEBUG
                    print("[Audio HAL] HAL input appears silent (first buffer peak < 1e-7)")
                    #endif
                }
            } else {
                silentBufferCount = 0
            }

            if !didLogChannelPeaks {
                let channelCount = min(channels, 64)
                var peaks: [(Int, Double)] = []
                peaks.reserveCapacity(channelCount)

                if (stream.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
                    let base = data.bindMemory(to: Float.self, capacity: frameLimit * channels)
                    for ch in 0..<channelCount {
                        var chPeak: Double = 0
                        var idx = ch
                        for _ in 0..<frameLimit {
                            let sample = Double(abs(base[idx]))
                            if sample > chPeak { chPeak = sample }
                            idx += channels
                        }
                        peaks.append((ch, chPeak))
                    }
                } else if stream.mBitsPerChannel == 16 {
                    let base = data.bindMemory(to: Int16.self, capacity: frameLimit * channels)
                    let denom = Double(Int16.max)
                    for ch in 0..<channelCount {
                        var chPeak: Double = 0
                        var idx = ch
                        for _ in 0..<frameLimit {
                            let sample = Double(abs(base[idx])) / denom
                            if sample > chPeak { chPeak = sample }
                            idx += channels
                        }
                        peaks.append((ch, chPeak))
                    }
                } else if stream.mBitsPerChannel == 32 {
                    let base = data.bindMemory(to: Int32.self, capacity: frameLimit * channels)
                    let denom = Double(Int32.max)
                    for ch in 0..<channelCount {
                        var chPeak: Double = 0
                        var idx = ch
                        for _ in 0..<frameLimit {
                            let sample = Double(abs(base[idx])) / denom
                            if sample > chPeak { chPeak = sample }
                            idx += channels
                        }
                        peaks.append((ch, chPeak))
                    }
                }

                let top = peaks.sorted { $0.1 > $1.1 }.prefix(6)
                let summary = top.map { "ch\($0.0 + 1):\(String(format: "%.6f", $0.1))" }.joined(separator: ", ")
                let flags = String(format: "0x%08X", stream.mFormatFlags)
                #if DEBUG
                print("[Audio HAL] HAL channel peaks: \(summary) buffers=\(srcList.count) flags=\(flags)")
                #endif
                didLogChannelPeaks = true
            }
        }

        guard !monoBufferPool.isEmpty else {
            DispatchQueue.main.async {
                RelayDiagnosticsStore.shared.recordError("HAL mono AVAudioPCMBuffer alloc failed", tag: "Audio HAL")
            }
            return noErr
        }
        let monoBuffer = monoBufferPool[monoBufferPoolIndex]
        monoBufferPoolIndex = (monoBufferPoolIndex + 1) % monoBufferPool.count
        monoBuffer.frameLength = frameCount

        let frames = Int(frameCount)
        let channels = max(1, Int(stream.mChannelsPerFrame))
        let channel = min(max(0, channelIndex), channels - 1)

        if let mono = monoBuffer.floatChannelData?.pointee {
            if (stream.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
                if isNonInterleaved {
                    if channel < srcList.count, let srcData = srcList[channel].mData {
                        let base = srcData.bindMemory(to: Float.self, capacity: frames)
                        for i in 0..<frames { mono[i] = base[i] }
                    }
                } else if let srcData = srcList.first?.mData {
                    let base = srcData.bindMemory(to: Float.self, capacity: frames * channels)
                    var idx = channel
                    for i in 0..<frames {
                        mono[i] = base[idx]
                        idx += channels
                    }
                }
            } else if stream.mBitsPerChannel == 16 {
                let denom = Float(Int16.max)
                if isNonInterleaved {
                    if channel < srcList.count, let srcData = srcList[channel].mData {
                        let base = srcData.bindMemory(to: Int16.self, capacity: frames)
                        for i in 0..<frames { mono[i] = Float(base[i]) / denom }
                    }
                } else if let srcData = srcList.first?.mData {
                    let base = srcData.bindMemory(to: Int16.self, capacity: frames * channels)
                    var idx = channel
                    for i in 0..<frames {
                        mono[i] = Float(base[idx]) / denom
                        idx += channels
                    }
                }
            } else if stream.mBitsPerChannel == 32 {
                let denom = Float(Int32.max)
                if isNonInterleaved {
                    if channel < srcList.count, let srcData = srcList[channel].mData {
                        let base = srcData.bindMemory(to: Int32.self, capacity: frames)
                        for i in 0..<frames { mono[i] = Float(base[i]) / denom }
                    }
                } else if let srcData = srcList.first?.mData {
                    let base = srcData.bindMemory(to: Int32.self, capacity: frames * channels)
                    var idx = channel
                    for i in 0..<frames {
                        mono[i] = Float(base[idx]) / denom
                        idx += channels
                    }
                }
            }

            if inputGainScalar != 1.0 {
                let gain = Float(inputGainScalar)
                for i in 0..<frames {
                    mono[i] *= gain
                }
            }
        }

        #if DEBUG
        if !didLogConversionPeak, let mono = monoBuffer.floatChannelData?.pointee {
            var monoPeak: Double = 0
            for i in 0..<frames {
                let sample = Double(abs(mono[i]))
                if sample > monoPeak { monoPeak = sample }
            }

            var rawPeak: Double = 0
            if (stream.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
                if isNonInterleaved {
                    if channel < srcList.count, let srcData = srcList[channel].mData {
                        let base = srcData.bindMemory(to: Float.self, capacity: frames)
                        for i in 0..<frames {
                            let sample = Double(abs(base[i]))
                            if sample > rawPeak { rawPeak = sample }
                        }
                    }
                } else if let srcData = srcList.first?.mData {
                    let base = srcData.bindMemory(to: Float.self, capacity: frames * channels)
                    var idx = channel
                    for _ in 0..<frames {
                        let sample = Double(abs(base[idx]))
                        if sample > rawPeak { rawPeak = sample }
                        idx += channels
                    }
                }
            } else if stream.mBitsPerChannel == 16 {
                let denom = Double(Int16.max)
                if isNonInterleaved {
                    if channel < srcList.count, let srcData = srcList[channel].mData {
                        let base = srcData.bindMemory(to: Int16.self, capacity: frames)
                        for i in 0..<frames {
                            let sample = Double(abs(base[i])) / denom
                            if sample > rawPeak { rawPeak = sample }
                        }
                    }
                } else if let srcData = srcList.first?.mData {
                    let base = srcData.bindMemory(to: Int16.self, capacity: frames * channels)
                    var idx = channel
                    for _ in 0..<frames {
                        let sample = Double(abs(base[idx])) / denom
                        if sample > rawPeak { rawPeak = sample }
                        idx += channels
                    }
                }
            } else if stream.mBitsPerChannel == 32 {
                let denom = Double(Int32.max)
                if isNonInterleaved {
                    if channel < srcList.count, let srcData = srcList[channel].mData {
                        let base = srcData.bindMemory(to: Int32.self, capacity: frames)
                        for i in 0..<frames {
                            let sample = Double(abs(base[i])) / denom
                            if sample > rawPeak { rawPeak = sample }
                        }
                    }
                } else if let srcData = srcList.first?.mData {
                    let base = srcData.bindMemory(to: Int32.self, capacity: frames * channels)
                    var idx = channel
                    for _ in 0..<frames {
                        let sample = Double(abs(base[idx])) / denom
                        if sample > rawPeak { rawPeak = sample }
                        idx += channels
                    }
                }
            }

            let flags = String(format: "0x%08X", stream.mFormatFlags)
            print("[Audio HAL] conversion peak raw=\(String(format: "%.6f", rawPeak)) mono=\(String(format: "%.6f", monoPeak)) gain=\(String(format: "%.3f", inputGainScalar)) bits=\(stream.mBitsPerChannel) flags=\(flags) nonInterleaved=\(isNonInterleaved)")
            didLogConversionPeak = true
        }
        #endif

        let onBuffer = self.onBuffer
        queue.async {
            onBuffer?(monoBuffer)
        }

        return noErr
    }

    private func error(_ status: OSStatus) -> NSError {
        NSError(domain: "Relay.DeviceInputCaptureHAL", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "AudioUnit error \(status)"])
    }
}
#endif
