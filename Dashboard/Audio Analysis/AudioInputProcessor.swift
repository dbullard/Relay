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
///
/// Threading:
/// - `controlQueue` owns capture start/stop and the signal watchdog. It may call into
///   `processingQueue` (sync), never the other way round.
/// - `processingQueue` owns the DSP state, the subscriber lists and `config`.
nonisolated final class AudioInputProcessor: @unchecked Sendable {
    let inputID: UUID
    private var config: AudioInputConfig
    private let processingQueue = DispatchQueue(label: "Relay.AudioInputProcessor", qos: .userInitiated)
    private let controlQueue = DispatchQueue(label: "Relay.AudioInputProcessor.Control", qos: .userInitiated)

    private var splContinuations: [UUID: AsyncStream<SPLPayload>.Continuation] = [:]
    private var fftContinuations: [UUID: FFTSubscription] = [:]

    // Structs avoid `LockingConcurrentMap<TupleCacheEntry>` mutex contention on the
    // audio IO thread that occurred with the previous tuple-valued dictionary and
    // labeled-tuple stored properties.
    private struct FFTSubscription {
        var continuation: AsyncStream<FFTFrame>.Continuation
        var resolution: RTABandResolution
    }

    /// SPL weighting and time-weighting state; recreated when the sample rate changes.
    private var meter: SPLMeterDSP?
    private var noiseFloor: Double = -120
    private var lastSampleRate: Double = 0


    /// Reused per buffer so the processing path doesn't allocate.
    private var sampleScratch: [Double] = []

    // Running energy totals (see SPLPayload.cumulative*). Never reset.
    private var cumulativeA: Double = 0
    private var cumulativeC: Double = 0
    private var cumulativeZ: Double = 0
    private var cumulativeSamples: Double = 0

    /// Uptime of the last buffer received; read by the watchdog.
    private var lastBufferUptime: TimeInterval = 0
    /// True after the watchdog has told subscribers the input went silent.
    private var isSignalStale = false

    /// Holds the newest `longFFTSize` samples; the normal FFT reads the last `currentFFTSize`.
    private var fftRingBuffer: [Float] = []
    private var fftWriteIndex: Int = 0    // monotonically increasing — never reset below its current value
    private var fftNextFrameAt: Int = 0   // fire FFT when fftWriteIndex reaches this; advances by hopSize
    private var fftAnalyzer: FFTAnalyzer?
    private var currentFFTSize: Int = 0
    /// Long window for low-frequency RTA bands (see FFTFrame.lowFrequencyMagnitudes).
    private var longFFTAnalyzer: FFTAnalyzer?
    private var longFFTSize: Int = 0
    private var lastLongSpectrum: [Float]?
    private var framesSinceLongSpectrum = 0
    /// Long-window length relative to the normal window.
    static let lowFrequencyWindowFactor = 8
    /// Recompute the long spectrum every this many normal frames (it changes slowly).
    private static let longSpectrumEveryFrames = 4

    // MARK: Control-queue state

    /// True while at least one subscriber wants audio.
    private var wantsRunning = false
    private var isCaptureRunning = false
    private var watchdog: DispatchSourceTimer?
    private var lastRestartAttemptUptime: TimeInterval = 0

    /// No buffer for this long while running ⇒ the input is treated as gone.
    private static let staleAfterSeconds: TimeInterval = 1.5
    /// Minimum spacing between capture restart attempts while the input is gone.
    private static let restartIntervalSeconds: TimeInterval = 2.0

    #if os(macOS)
    private var captureHAL: DeviceInputCaptureHAL?
    #else
    private let capture = EngineInputCapture()
    #endif

    init(config: AudioInputConfig) {
        self.inputID = config.id
        self.config = config
    }

    deinit {
        // No other references exist at this point, so tear down directly rather than via
        // controlQueue.sync — deinit can run on controlQueue (the watchdog handler holds a
        // temporary strong reference), where a sync would deadlock.
        watchdog?.cancel()
        #if os(macOS)
        captureHAL?.stop()
        #else
        capture.stop()
        #endif
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

    // Start, stop and restart run asynchronously on this input's own `controlQueue`.
    // Opening a device can block for seconds (a slow or waking interface, a driver that
    // hangs, a pending microphone-permission prompt). These used to run synchronously
    // inside the shared `AudioAnalysisEngine` actor, so one slow device stalled every
    // subscribe and unsubscribe for every input: all meters froze until it returned.
    // The serial queue keeps start/stop/restart in call order for this input.

    /// Called at the start of every capture start attempt. Tests use it to simulate a
    /// device that is slow to open.
    var captureStartHookForTesting: (() -> Void)?

    /// Starts capture (idempotent). If the device can't be opened now, the watchdog keeps
    /// retrying until it can or `stop()` is called. Returns immediately.
    func start() {
        controlQueue.async { [self] in
            wantsRunning = true
            processingQueue.sync { lastBufferUptime = ProcessInfo.processInfo.systemUptime }
            if !isCaptureRunning { startCaptureLocked() }
            startWatchdogLocked()
        }
    }

    /// Stops capture. Returns immediately.
    func stop() {
        controlQueue.async { [self] in
            wantsRunning = false
            watchdog?.cancel()
            watchdog = nil
            stopCaptureLocked()
        }
    }

    func updateConfig(_ newConfig: AudioInputConfig) {
        var deviceChanged = false
        processingQueue.sync {
            deviceChanged = newConfig.deviceUID != config.deviceUID
                || newConfig.channelIndex != config.channelIndex
            config = newConfig
        }
        guard deviceChanged else { return }
        // Only restart capture that is supposed to be running — an idle processor (no
        // subscribers) must not open the device just because its config changed.
        controlQueue.async { [self] in
            guard wantsRunning else { return }
            stopCaptureLocked()
            processingQueue.sync { lastBufferUptime = ProcessInfo.processInfo.systemUptime }
            startCaptureLocked()
        }
    }

    // MARK: - Watchdog (controlQueue)

    private func startWatchdogLocked() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        watchdog = timer
        timer.resume()
    }

    private func watchdogTick() {
        guard wantsRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let silentFor = processingQueue.sync { now - lastBufferUptime }
        #if os(macOS)
        // The opened device vanished or the unit moved to another device; the capture has
        // already stopped delivering buffers, so don't wait out the silence timeout.
        let deviceLost = captureHAL?.isDeviceLost ?? false
        #else
        let deviceLost = false
        #endif
        guard !isCaptureRunning || deviceLost || silentFor > Self.staleAfterSeconds else { return }

        processingQueue.async { [weak self] in self?.markSignalStale() }

        // Device unplugged, sample-rate/format change, failed start, or (iOS) an audio
        // session interruption: tear down and try again, re-resolving the device by UID.
        guard now - lastRestartAttemptUptime >= Self.restartIntervalSeconds else { return }
        lastRestartAttemptUptime = now
        stopCaptureLocked()
        startCaptureLocked()
    }

    // MARK: - Platform capture (controlQueue)

    private func startCaptureLocked() {
        captureStartHookForTesting?()
        #if os(macOS)
        startHALLocked()
        #else
        startEngineLocked()
        #endif
    }

    private func stopCaptureLocked() {
        #if os(macOS)
        captureHAL?.stop()
        captureHAL = nil
        #else
        capture.stop()
        #endif
        isCaptureRunning = false
    }

    #if os(macOS)
    private func startHALLocked() {
        let snapshot = processingQueue.sync { config }
        let uid = snapshot.deviceUID ?? ""
        // Only fall back to the system default input when no device was chosen. A chosen
        // device that's missing (unplugged) must not silently meter a different mic — the
        // watchdog keeps retrying until it comes back.
        let resolved = uid.isEmpty
            ? AudioDeviceEnumerator.defaultInputDeviceId()
            : AudioDeviceEnumerator.deviceId(for: uid)
        guard let deviceId = resolved else { return }
        let hal = DeviceInputCaptureHAL(deviceId: deviceId)
        hal.channelIndex = snapshot.channelIndex
        hal.onBuffer = { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
        do {
            try hal.start()
            captureHAL = hal
            isCaptureRunning = true
        } catch {
            hal.stop()
            captureHAL = nil
            isCaptureRunning = false
        }
    }
    #else
    private func startEngineLocked() {
        let snapshot = processingQueue.sync { config }
        capture.preferredInputUID = snapshot.deviceUID
        capture.channelIndex = snapshot.channelIndex
        capture.onBuffer = { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
        do {
            try capture.start()
            isCaptureRunning = true
        } catch {
            isCaptureRunning = false
        }
    }
    #endif

    // MARK: - Buffer processing

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        let sampleRate = buffer.format.sampleRate
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, sampleRate > 0 else { return }

        processingQueue.sync {
            lastBufferUptime = ProcessInfo.processInfo.systemUptime
            if isSignalStale {
                isSignalStale = false
                // Levels from before the dropout are stale; start the meters fresh.
                resetFilters(sampleRate: sampleRate)
            }

            if sampleRate != lastSampleRate {
                lastSampleRate = sampleRate
                resetFilters(sampleRate: sampleRate)
                updateFFTSize()
            }

            if sampleScratch.count < frameCount {
                sampleScratch = [Double](repeating: 0, count: frameCount)
            }
            extractSamples(from: buffer, frameCount: frameCount, channelIndex: config.channelIndex)

            if meter == nil { meter = SPLMeterDSP(sampleRate: sampleRate) }
            let levels = sampleScratch.withUnsafeBufferPointer {
                meter!.process(UnsafeBufferPointer(rebasing: $0[0..<frameCount]))
            }
            var instA = levels.sumA, instC = levels.sumC, instZ = levels.sumZ
            let rawPeakThisBuffer = levels.peak

            // Apply per-input calibration offset to dB outputs and scale linear powers
            // proportionally so Leq computations stay consistent.
            let cal = config.calibrationOffsetDb
            let linCal = cal != 0 ? pow(10.0, cal / 10.0) : 1.0

            cumulativeA += instA * linCal
            cumulativeC += instC * linCal
            cumulativeZ += instZ * linCal
            cumulativeSamples += Double(frameCount)

            let n = Double(frameCount)
            instA /= n; instC /= n; instZ /= n

            let rawPeakDbFS = rawPeakThisBuffer > 1e-10 ? 20 * log10(rawPeakThisBuffer) : -120

            // C-A is the difference between C-weighted and A-weighted dB levels.
            // The calibration offset cancels out (it shifts both C and A equally),
            // so no +cal is needed here.
            let caFastDb = levels.cFast - levels.aFast
            let caSlowDb = levels.cSlow - levels.aSlow

            if !splContinuations.isEmpty {
                let payload = SPLPayload(
                    aFast: levels.aFast + cal, aSlow: levels.aSlow + cal,
                    cFast: levels.cFast + cal, cSlow: levels.cSlow + cal,
                    zFast: levels.zFast + cal, zSlow: levels.zSlow + cal,
                    caFast: caFastDb, caSlow: caSlowDb,
                    // Raw values are digital levels (dBFS) and deliberately exclude the
                    // calibration offset — the automation trigger, log columns and
                    // calibration sheet all treat them as dBFS.
                    rawDbFS: levels.zFast,
                    rawPeakDbFS: rawPeakDbFS,
                    aInstantPower: instA * linCal, cInstantPower: instC * linCal, zInstantPower: instZ * linCal,
                    clippingWarning: rawPeakThisBuffer >= 0.999,
                    // Headroom is a digital (dBFS) concept — calibration offset does not affect it.
                    headroomDb: max(0, -rawPeakDbFS),
                    noiseFloorDbFS: noiseFloor,
                    sampleRate: sampleRate,
                    timestamp: Date(),
                    isStale: false,
                    cumulativeAPower: cumulativeA,
                    cumulativeCPower: cumulativeC,
                    cumulativeZPower: cumulativeZ,
                    cumulativeSampleCount: cumulativeSamples,
                    calibrationOffsetDb: cal
                )
                for cont in splContinuations.values { cont.yield(payload) }
            }

            if !fftContinuations.isEmpty && currentFFTSize > 0 {
                appendToFFTRingBuffer(count: frameCount)
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

    /// Tells every subscriber once that the input stopped delivering audio.
    private func markSignalStale() {
        guard !isSignalStale else { return }
        isSignalStale = true
        var payload = SPLPayload.empty
        payload.timestamp = Date()
        payload.calibrationOffsetDb = config.calibrationOffsetDb
        payload.cumulativeAPower = cumulativeA
        payload.cumulativeCPower = cumulativeC
        payload.cumulativeZPower = cumulativeZ
        payload.cumulativeSampleCount = cumulativeSamples
        for cont in splContinuations.values { cont.yield(payload) }
        let frame = FFTFrame.stale(timestamp: Date().timeIntervalSinceReferenceDate)
        for entry in fftContinuations.values { entry.continuation.yield(frame) }
    }

    // MARK: - Helpers

    private func extractSamples(from buffer: AVAudioPCMBuffer, frameCount: Int, channelIndex: Int) {
        guard let floatData = buffer.floatChannelData else {
            for i in 0..<frameCount { sampleScratch[i] = 0 }
            return
        }
        let chCount = Int(buffer.format.channelCount)
        let ch = min(max(channelIndex, 0), chCount - 1)
        let ptr = floatData[ch]
        sampleScratch.withUnsafeMutableBufferPointer { out in
            vDSP_vspdp(ptr, 1, out.baseAddress!, 1, vDSP_Length(frameCount))
        }
    }

    private func resetFilters(sampleRate: Double) {
        meter = SPLMeterDSP(sampleRate: sampleRate)
    }

    /// FFT length for the finest resolution any subscriber asked for. The table in
    /// `RTABandResolution.minimumFFTSize` is tuned for 44.1/48 kHz, so it is scaled up at
    /// higher sample rates to keep the same frequency resolution (Hz per bin).
    static func fftSize(for resolution: RTABandResolution, sampleRate: Double) -> Int {
        let base = RTABandResolution.minimumFFTSize(for: resolution)
        guard sampleRate > 0 else { return base }
        let octavesAbove48k = log2(sampleRate / 48_000).rounded()
        let multiplier = octavesAbove48k > 0 ? 1 << min(Int(octavesAbove48k), 3) : 1
        return base * multiplier
    }

    private func updateFFTSize() {
        let maxRes = fftContinuations.values.map(\.resolution).max()
        let newSize = maxRes.map { Self.fftSize(for: $0, sampleRate: lastSampleRate) } ?? 0
        // Reconfiguring wipes the ring buffer, which stalls every other FFT subscriber on
        // this input for a full window — only do it when the size really changes.
        guard newSize != currentFFTSize else { return }
        currentFFTSize = newSize
        if newSize > 0 { configureFFT(size: newSize) }
    }

    private func configureFFT(size: Int) {
        fftAnalyzer = FFTAnalyzer(size: size)
        longFFTSize = size * Self.lowFrequencyWindowFactor
        longFFTAnalyzer = FFTAnalyzer(size: longFFTSize)
        lastLongSpectrum = nil
        framesSinceLongSpectrum = 0
        fftRingBuffer = [Float](repeating: 0, count: longFFTSize)
        fftWriteIndex = 0
        fftNextFrameAt = size   // fire first frame once we have a full window of samples
    }

    /// Copies the first `count` samples of `sampleScratch` into the FFT ring buffer in at
    /// most two contiguous runs.
    private func appendToFFTRingBuffer(count: Int) {
        let n = fftRingBuffer.count
        guard n > 0 else { return }
        // Only the newest n samples can survive in the ring.
        let skip = max(0, count - n)
        var remaining = count - skip
        var src = skip
        fftWriteIndex += skip
        sampleScratch.withUnsafeBufferPointer { samples in
            fftRingBuffer.withUnsafeMutableBufferPointer { ring in
                while remaining > 0 {
                    let pos = fftWriteIndex % n
                    let run = min(remaining, n - pos)
                    vDSP_vdpsp(samples.baseAddress! + src, 1, ring.baseAddress! + pos, 1, vDSP_Length(run))
                    src += run
                    remaining -= run
                    fftWriteIndex += run
                }
            }
        }
    }

    private func computeFFTFrame(sampleRate: Double) -> FFTFrame? {
        guard let analyzer = fftAnalyzer, currentFFTSize > 0, analyzer.size == currentFFTSize else { return nil }
        let capacity = fftRingBuffer.count
        guard capacity >= currentFFTSize else { return nil }

        /// The newest `length` samples, oldest first, as up to two contiguous runs.
        func spectrum(_ fft: FFTAnalyzer, length: Int) -> [Float] {
            let start = ((fftWriteIndex - length) % capacity + capacity) % capacity
            let firstCount = min(length, capacity - start)
            return fftRingBuffer.withUnsafeBufferPointer { ring in
                fft.amplitudeSpectrum(first: ring.baseAddress! + start, firstCount: firstCount,
                                      second: firstCount < length ? ring.baseAddress! : nil,
                                      secondCount: length - firstCount)
            }
        }

        let magnitudes = spectrum(analyzer, length: currentFFTSize)
        if let long = longFFTAnalyzer, fftWriteIndex >= longFFTSize,
           lastLongSpectrum == nil || framesSinceLongSpectrum >= Self.longSpectrumEveryFrames - 1 {
            lastLongSpectrum = spectrum(long, length: longFFTSize)
            framesSinceLongSpectrum = 0
        } else {
            framesSinceLongSpectrum += 1
        }
        return FFTFrame(magnitudes: magnitudes, sampleRate: sampleRate,
                        timestamp: Date().timeIntervalSinceReferenceDate, isRepeated: false,
                        calibrationOffsetDb: config.calibrationOffsetDb,
                        lowFrequencyMagnitudes: lastLongSpectrum)
    }
}
