import Foundation
import AVFoundation
import Accelerate
#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

// MARK: - AudioInputProcessor

/// Manages one audio tap for a single named input.
/// Runs the SPL pipeline (all weightings simultaneously) and an adaptive FFT pipeline.
/// Multiple subscribers may attach; the tap starts on first subscriber and stops on last.
nonisolated final class AudioInputProcessor {
    let inputID: UUID
    private var config: AudioInputConfig
    private let processingQueue = DispatchQueue(label: "Relay.AudioInputProcessor", qos: .userInitiated)

    private var splContinuations: [UUID: AsyncStream<SPLPayload>.Continuation] = [:]
    private var fftContinuations: [UUID: FFTSubscription] = [:]

    // Structs avoid `LockingConcurrentMap<TupleCacheEntry>` mutex contention on the
    // audio IO thread that occurred with the previous tuple-valued dictionary and
    // labeled-tuple stored properties.
    private struct FFTSubscription {
        var continuation: AsyncStream<FFTFrame>.Continuation
        var resolution: RTABandResolution
    }

    private struct SmoothPair {
        var fast: Double = 0
        var slow: Double = 0
    }

    private var smoothA = SmoothPair()
    private var smoothC = SmoothPair()
    private var smoothZ = SmoothPair()
    private var peakHoldRaw: Double = 0
    private var noiseFloor: Double = -120
    private var lastSampleRate: Double = 0

    private var filterA: WeightingFilter? = nil
    private var filterC: WeightingFilter? = nil

    private var fftRingBuffer: [Float] = []
    private var fftWriteIndex: Int = 0    // monotonically increasing — never reset below its current value
    private var fftNextFrameAt: Int = 0   // fire FFT when fftWriteIndex reaches this; advances by hopSize
    private var fftSetup: OpaquePointer? = nil
    private var fftWindow: [Float] = []
    private var currentFFTSize: Int = 0
    // Pre-allocated working buffers for computeFFTFrame, resized in configureFFT.
    // Avoids 4 × ~32 KB heap allocations per FFT frame (~23 Hz per source).
    // fftSqrtMagnitudes is NOT pre-allocated; FFTFrame takes ownership of its own copy.
    private var fftWindowed: [Float] = []
    private var fftRealPart: [Float] = []
    private var fftImagPart: [Float] = []
    private var fftMagnitudes: [Float] = []

    #if os(macOS)
    private var captureHAL: DeviceInputCaptureHAL?
    private let captureQueue = DispatchQueue(label: "Relay.AudioInputProcessor.Capture", qos: .userInitiated)
    #else
    private let capture = EngineInputCapture()
    #endif

    init(config: AudioInputConfig) {
        self.inputID = config.id
        self.config = config
    }

    deinit {
        stop()
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    // MARK: - Subscriber management

    func addSPLSubscriber() -> (id: UUID, stream: SPLStream) {
        let subID = UUID()
        var cont: AsyncStream<SPLPayload>.Continuation!
        let stream = AsyncStream<SPLPayload>(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        processingQueue.sync { splContinuations[subID] = cont }
        return (subID, stream)
    }

    func removeSPLSubscriber(id: UUID) {
        processingQueue.sync {
            splContinuations[id]?.finish()
            splContinuations.removeValue(forKey: id)
        }
    }

    func addFFTSubscriber(resolution: RTABandResolution) -> (id: UUID, stream: FFTStream) {
        let subID = UUID()
        var cont: AsyncStream<FFTFrame>.Continuation!
        let stream = AsyncStream<FFTFrame>(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        processingQueue.sync {
            fftContinuations[subID] = FFTSubscription(continuation: cont, resolution: resolution)
            updateFFTSize()
        }
        return (subID, stream)
    }

    func removeFFTSubscriber(id: UUID) {
        processingQueue.sync {
            fftContinuations[id]?.continuation.finish()
            fftContinuations.removeValue(forKey: id)
            updateFFTSize()
        }
    }

    var hasSPLSubscribers: Bool { processingQueue.sync { !splContinuations.isEmpty } }
    var hasFFTSubscribers: Bool { processingQueue.sync { !fftContinuations.isEmpty } }
    var hasAnySubscribers: Bool { processingQueue.sync { !splContinuations.isEmpty || !fftContinuations.isEmpty } }

    // MARK: - Start / stop

    func start() {
        #if os(macOS)
        startHAL()
        #else
        startEngine()
        #endif
    }

    func stop() {
        #if os(macOS)
        captureHAL?.stop()
        captureHAL = nil
        #else
        capture.stop()
        #endif
    }

    func updateConfig(_ newConfig: AudioInputConfig) {
        var deviceChanged = false
        processingQueue.sync {
            deviceChanged = newConfig.deviceUID != config.deviceUID
                || newConfig.channelIndex != config.channelIndex
            config = newConfig
        }
        if deviceChanged { stop(); start() }
    }

    // MARK: - Platform capture

    #if os(macOS)
    private func startHAL() {
        let uid = config.deviceUID ?? ""
        guard let deviceId = AudioDeviceEnumerator.deviceId(for: uid)
                              ?? AudioDeviceEnumerator.defaultInputDeviceId() else {
            return
        }
        let hal = DeviceInputCaptureHAL(deviceId: deviceId)
        hal.channelIndex = config.channelIndex
        hal.onBuffer = { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
        do {
            try hal.start()
            captureHAL = hal
        } catch {
            captureHAL = nil
        }
    }
    #else
    private func startEngine() {
        capture.onBuffer = { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
        do {
            try capture.start()
        } catch {
            // capture remains stopped; callers can retry via updateConfig
        }
    }
    #endif

    // MARK: - Buffer processing

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        let sampleRate = buffer.format.sampleRate
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var samples = [Double](repeating: 0, count: frameCount)
        extractSamples(from: buffer, into: &samples, channelIndex: config.channelIndex)

        processingQueue.sync {
            if sampleRate != lastSampleRate {
                lastSampleRate = sampleRate
                resetFilters(sampleRate: sampleRate)
            }

            let dt = 1.0 / sampleRate
            let alphaFast = exp(-dt / 0.125)
            let alphaSlow  = exp(-dt / 1.0)
            var instA: Double = 0, instC: Double = 0, instZ: Double = 0
            var rawPeakThisBuffer: Double = 0

            for sample in samples {
                let z = sample
                let a = filterA?.processSample(z) ?? z
                let c = filterC?.processSample(z) ?? z

                let z2 = z * z, a2 = a * a, c2 = c * c

                smoothZ.fast = alphaFast * smoothZ.fast + (1 - alphaFast) * z2
                smoothZ.slow = alphaSlow  * smoothZ.slow + (1 - alphaSlow) * z2
                smoothA.fast = alphaFast * smoothA.fast + (1 - alphaFast) * a2
                smoothA.slow = alphaSlow  * smoothA.slow + (1 - alphaSlow) * a2
                smoothC.fast = alphaFast * smoothC.fast + (1 - alphaFast) * c2
                smoothC.slow = alphaSlow  * smoothC.slow + (1 - alphaSlow) * c2

                rawPeakThisBuffer = max(rawPeakThisBuffer, abs(z))
                instZ += z2; instA += a2; instC += c2
            }
            peakHoldRaw = max(peakHoldRaw, rawPeakThisBuffer)

            let n = max(1.0, Double(samples.count))
            instA /= n; instC /= n; instZ /= n

            func toDb(_ energy: Double) -> Double {
                let rms = sqrt(max(0, energy))
                return rms > 1e-10 ? 20 * log10(rms) : -120
            }

            let rawPeakDbFS = rawPeakThisBuffer > 1e-10 ? 20 * log10(rawPeakThisBuffer) : -120

            // Apply per-input calibration offset to dB outputs and scale linear instant
            // powers proportionally so LAeq computations stay consistent.
            let cal = config.calibrationOffsetDb
            let linCal = cal != 0 ? pow(10.0, cal / 10.0) : 1.0

            // C-A is the difference between C-weighted and A-weighted dB levels.
            // The calibration offset cancels out (it shifts both C and A equally),
            // so no +cal is needed here.
            let caFastDb = toDb(smoothC.fast) - toDb(smoothA.fast)
            let caSlowDb = toDb(smoothC.slow) - toDb(smoothA.slow)

            let payload = SPLPayload(
                aFast: toDb(smoothA.fast) + cal, aSlow: toDb(smoothA.slow) + cal,
                cFast: toDb(smoothC.fast) + cal, cSlow: toDb(smoothC.slow) + cal,
                zFast: toDb(smoothZ.fast) + cal, zSlow: toDb(smoothZ.slow) + cal,
                caFast: caFastDb, caSlow: caSlowDb,
                rawDbFS: toDb(smoothZ.fast) + cal,
                rawPeakDbFS: rawPeakDbFS + cal,
                aInstantPower: instA * linCal, cInstantPower: instC * linCal, zInstantPower: instZ * linCal,
                estimatedFrequencyHz: .nan,
                clippingWarning: rawPeakThisBuffer >= 0.999,
                // Headroom is a digital (dBFS) concept — calibration offset does not affect it.
                headroomDb: max(0, -rawPeakDbFS),
                noiseFloorDbFS: noiseFloor + cal,
                sampleRate: sampleRate,
                timestamp: Date(),
                isStale: false
            )
            for cont in splContinuations.values { cont.yield(payload) }

            if !fftContinuations.isEmpty && currentFFTSize > 0 {
                appendToFFTRingBuffer(samples)
                if fftWriteIndex >= fftNextFrameAt, let frame = computeFFTFrame(sampleRate: sampleRate) {
                    for entry in fftContinuations.values { entry.continuation.yield(frame) }
                    // Advance the next-frame trigger by hopSize. fftWriteIndex is NEVER
                    // decremented — it grows monotonically so the ring buffer always holds
                    // the most recent currentFFTSize samples at any write position.
                    let hopSize = min(currentFFTSize / 4, 2048)
                    fftNextFrameAt = fftWriteIndex + hopSize
                }
            }
        }
    }

    // MARK: - Helpers

    private func extractSamples(from buffer: AVAudioPCMBuffer, into output: inout [Double], channelIndex: Int) {
        let frameCount = Int(buffer.frameLength)
        guard let floatData = buffer.floatChannelData else { return }
        let chCount = Int(buffer.format.channelCount)
        let ch = min(max(channelIndex, 0), chCount - 1)
        let ptr = floatData[ch]
        for i in 0..<frameCount { output[i] = Double(ptr[i]) }
    }

    private func resetFilters(sampleRate: Double) {
        filterA = WeightingFilter(weighting: .a, sampleRate: sampleRate)
        filterC = WeightingFilter(weighting: .c, sampleRate: sampleRate)
        smoothA = SmoothPair(); smoothC = SmoothPair(); smoothZ = SmoothPair()
        peakHoldRaw = 0
    }

    private func updateFFTSize() {
        let maxRes = fftContinuations.values.map(\.resolution).max()
        currentFFTSize = maxRes.map { RTABandResolution.minimumFFTSize(for: $0) } ?? 0
        if currentFFTSize > 0 { configureFFT(size: currentFFTSize) }
    }

    private func configureFFT(size: Int) {
        if let existing = fftSetup { vDSP_destroy_fftsetup(existing) }
        let log2n = vDSP_Length(log2(Double(size)).rounded())
        fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))
        fftWindow = [Float](repeating: 0, count: size)
        // DENORM (standard 0...1 Hann): its mean value of 0.5 is the coherent-gain loss
        // compensated for below via the 2/n scale. NORM applies an extra sqrt(8/3)
        // factor meant for noise/PSD averaging, which would throw off tone/level accuracy.
        vDSP_hann_window(&fftWindow, vDSP_Length(size), Int32(vDSP_HANN_DENORM))
        fftRingBuffer = [Float](repeating: 0, count: size)
        fftWriteIndex = 0
        fftNextFrameAt = size   // fire first frame once we have a full window of samples
        let halfN = size / 2
        fftWindowed = [Float](repeating: 0, count: size)
        fftRealPart = [Float](repeating: 0, count: halfN)
        fftImagPart = [Float](repeating: 0, count: halfN)
        fftMagnitudes = [Float](repeating: 0, count: halfN)
    }

    private func appendToFFTRingBuffer(_ samples: [Double]) {
        for s in samples {
            fftRingBuffer[fftWriteIndex % currentFFTSize] = Float(s)
            fftWriteIndex += 1
        }
    }

    private func computeFFTFrame(sampleRate: Double) -> FFTFrame? {
        guard let setup = fftSetup, currentFFTSize > 0 else { return nil }
        let n = currentFFTSize
        let halfN = n / 2
        let log2n = vDSP_Length(log2(Double(n)).rounded())

        // Apply Hann window to the ring-buffer contents using pre-allocated buffer.
        let startIdx = fftWriteIndex % n
        for i in 0..<n { fftWindowed[i] = fftRingBuffer[(startIdx + i) % n] * fftWindow[i] }

        // Real-input FFT via vDSP_fft_zrip ("z" = split-complex, "r" = real input, "ip" = in-place).
        //
        // Step 1 – vDSP_ctoz with stride 2:
        //   Deinterleaves the n windowed real samples into halfN complex pairs (even sample ->
        //   real, odd sample -> imag). IC is a stride over the *original real buffer's* element
        //   spacing as seen through the DSPComplex reinterpretation, not a stride bounded by the
        //   halfN capacity annotation on the pointer — that annotation only describes the *output*
        //   element count read, not a byte-range check. Empirically verified: stride 1 here
        //   silently reports every bin at half its true frequency (a bin-aligned tone at bin k
        //   measures at bin k/2, confirmed by comparing against vDSP_fft_zip on the same signal),
        //   which is the root cause of the RTA/spectrogram frequency axis reading roughly an
        //   octave low. Stride 2 matches Apple's documented real-FFT packing and reproduces the
        //   reference vDSP_fft_zip result exactly.
        //
        // Step 2 – vDSP_fft_zrip (NOT vDSP_fft_zip):
        //   vDSP_fft_zip is the complex FFT; with log2n it processes n complex elements and
        //   would write n floats into the halfN-float split buffers, overflowing by n/2 elements
        //   and corrupting heap memory. vDSP_fft_zrip is the real FFT; it processes the n real
        //   samples packed as halfN complex pairs and writes back exactly halfN complex bins.
        //
        // All three array storage pointers are pinned for the entire duration so DSPSplitComplex
        // internal pointers remain valid across all vDSP calls.
        fftRealPart.withUnsafeMutableBufferPointer { rPtr in
            fftImagPart.withUnsafeMutableBufferPointer { iPtr in
                fftMagnitudes.withUnsafeMutableBufferPointer { mPtr in
                    var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                    fftWindowed.withUnsafeBufferPointer { wPtr in
                        wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfN))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))  // real FFT, not zip
                    // Bin 0's imaginary slot is repurposed by the packed real-FFT format to hold
                    // the Nyquist bin's (real-only) value, not a second bin's imaginary part.
                    // Left alone, vDSP_zvmags would report magnitude[0] = DC^2 + Nyquist^2,
                    // mixing 0 Hz energy with ~sampleRate/2 energy into the lowest band. There's
                    // no separate slot for Nyquist in a halfN-bin output, so drop it and keep
                    // bin 0 as pure DC.
                    iPtr[0] = 0
                    vDSP_zvmags(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(halfN))
                }
            }
        }

        // Convert power spectrum (squared magnitudes) to amplitude spectrum.
        // sqrtMagnitudes is a new allocation per frame because FFTFrame takes ownership.
        var sqrtMagnitudes = [Float](repeating: 0, count: halfN)
        vvsqrtf(&sqrtMagnitudes, fftMagnitudes, [Int32(halfN)])

        // Normalize to true signal amplitude: vDSP_fft_zrip's forward output is scaled 2x vs a
        // standard DFT, and the (unity-max, DENORM) Hann window has a coherent gain of 0.5 that
        // must be compensated for, so the two factors combine to a net 2/n. Verified against a
        // 0 dBFS bin-aligned test tone: this yields exactly 1.0 amplitude (0 dB), matching the
        // reference vDSP_fft_zip computation of the same signal.
        var scale = Float(2.0) / Float(n)
        vDSP_vsmul(sqrtMagnitudes, 1, &scale, &sqrtMagnitudes, 1, vDSP_Length(halfN))

        return FFTFrame(magnitudes: sqrtMagnitudes, sampleRate: sampleRate,
                        timestamp: Date().timeIntervalSinceReferenceDate, isRepeated: false)
    }
}
