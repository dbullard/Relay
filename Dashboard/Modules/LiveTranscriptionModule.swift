import SwiftUI
import CryptoKit
@preconcurrency import AVFoundation
import Speech
import Combine
import CoreMedia

extension Notification.Name {
    static let liveTranscriptionClearRequested = Notification.Name("Relay.LiveTranscriptionClearRequested")
}

// MARK: - Live Transcription Models

nonisolated enum LiveTranscriptionSourceKind: String, Codable, CaseIterable {
    case microphone
    case systemAudio

    var label: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .systemAudio:
            return "System Audio"
        }
    }
}

nonisolated enum LiveTranscriptionQualityMode: String, Codable, CaseIterable {
    case low
    case balanced
    case high

    var publishHz: Double {
        switch self {
        case .low:
            return 2
        case .balanced:
            return 5
        case .high:
            return 10
        }
    }
}

nonisolated enum LiveTranscriptionProfanityMode: String, Codable, CaseIterable {
    case off
    case mask
    case remove
}

nonisolated struct LiveTranscriptionAudioDevice: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let name: String
}

enum LiveTranscriptionAudioDevices {
    static func microphones() -> [LiveTranscriptionAudioDevice] {
        #if os(macOS)
        let mapped = AudioDeviceEnumerator.inputDevices().map { LiveTranscriptionAudioDevice(uid: $0.uid, name: $0.name) }
        return mapped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #else
        let mapped = AudioDeviceEnumerator.inputDevices().map { LiveTranscriptionAudioDevice(uid: $0.uid, name: $0.name) }
        return mapped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #endif
    }
}

nonisolated struct LiveTranscriptionProfanitySettings: Codable, Equatable {
    var mode: LiveTranscriptionProfanityMode
    var includeDefaultList: Bool
    var customBlockedWords: [String]

    init(
        mode: LiveTranscriptionProfanityMode = .off,
        includeDefaultList: Bool = true,
        customBlockedWords: [String] = []
    ) {
        self.mode = mode
        self.includeDefaultList = includeDefaultList
        self.customBlockedWords = customBlockedWords
    }
}

nonisolated struct LiveTranscriptionRetentionSettings: Codable, Equatable {
    var limitsEnabled: Bool?
    var maxMinutes: Int?
    var maxEntries: Int?
    var maxCharacters: Int?

    init(limitsEnabled: Bool? = false, maxMinutes: Int? = 10, maxEntries: Int? = 400, maxCharacters: Int? = 8000) {
        self.limitsEnabled = limitsEnabled
        self.maxMinutes = maxMinutes
        self.maxEntries = maxEntries
        self.maxCharacters = maxCharacters
    }
}

/// Normalizing `Binding` factories shared by the retention/display controls in
/// `LiveTranscriptionSourcesSheet`. Centralizes the "optional reads as false/0,
/// writes a concrete value (never nil)" convention so the `Form` body doesn't
/// repeat the same inline get/set closures for each control.
enum LiveTranscriptionRetentionBindings {
    static func limitsEnabled(get: @escaping () -> Bool?, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { get() == true }, set: set)
    }

    static func maxMinutes(get: @escaping () -> Int?, set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(get: { get() ?? 0 }, set: set)
    }

    static func maxEntries(get: @escaping () -> Int?, set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(get: { get() ?? 0 }, set: set)
    }

    static func relativeTimestamps(get: @escaping () -> Bool?, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { get() == true }, set: set)
    }
}

nonisolated struct LiveTranscriptionSourceConfig: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: LiveTranscriptionSourceKind
    var displayName: String
    var channelName: String?
    var deviceUID: String?
    var channelIndex: Int = 0
    var color: CodableColor
    var isEnabled: Bool
    var transInputID: UUID?   // references TranscriptionInputConfig in global store

    init(
        id: UUID = UUID(),
        kind: LiveTranscriptionSourceKind,
        displayName: String,
        channelName: String? = nil,
        deviceUID: String? = nil,
        channelIndex: Int = 0,
        color: CodableColor,
        isEnabled: Bool = true,
        transInputID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.channelName = channelName
        self.deviceUID = deviceUID
        self.channelIndex = max(0, channelIndex)
        self.color = color
        self.isEnabled = isEnabled
        self.transInputID = transInputID
    }
}

extension LiveTranscriptionSourceConfig {
    var transcriptDisplayName: String {
        let channel = channelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !channel.isEmpty {
            return channel
        }

        let input = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return input.isEmpty ? "Source" : input
    }
}

struct LiveTranscriptionModuleModel: Codable, Equatable {
    var isEnabled: Bool
    var label: String
    var showsDiagnostics: Bool
    var sources: [LiveTranscriptionSourceConfig]
    var retention: LiveTranscriptionRetentionSettings
    var profanity: LiveTranscriptionProfanitySettings
    var quality: LiveTranscriptionQualityMode
    var includeTimestampsInExport: Bool
    var includeSourceNamesInExport: Bool
    var usesRelativeTimestamps: Bool?

    init(
        isEnabled: Bool = true,
        label: String = "Live Transcription",
        showsDiagnostics: Bool = true,
        sources: [LiveTranscriptionSourceConfig]? = nil,
        retention: LiveTranscriptionRetentionSettings = LiveTranscriptionRetentionSettings(),
        profanity: LiveTranscriptionProfanitySettings = LiveTranscriptionProfanitySettings(),
        quality: LiveTranscriptionQualityMode = .balanced,
        includeTimestampsInExport: Bool = true,
        includeSourceNamesInExport: Bool = true,
        usesRelativeTimestamps: Bool? = false
    ) {
        self.isEnabled = isEnabled
        if let sources {
        self.sources = sources
        } else {
            self.sources = [
                LiveTranscriptionSourceConfig(
                    kind: .microphone,
                    displayName: "Microphone",
                    deviceUID: nil,
                    color: CodableColor(Color.cyan),
                    isEnabled: true
                )
            ]
        }
        self.label = label
        self.showsDiagnostics = showsDiagnostics
        self.retention = retention
        self.profanity = profanity
        self.quality = quality
        self.includeTimestampsInExport = includeTimestampsInExport
        self.includeSourceNamesInExport = includeSourceNamesInExport
        self.usesRelativeTimestamps = usesRelativeTimestamps
    }
}

// MARK: - Transcript Payload

struct TranscriptEntry: Identifiable, Equatable {
    var id: UUID
    var timestamp: Date
    var sourceId: UUID
    var sourceDisplayName: String
    var rawText: String
    var displayText: String
    var isFinal: Bool
    var confidence: Double?
}

struct TranscriptOutputPayload: Equatable {
    var latestEntry: TranscriptEntry?
    var window: [TranscriptEntry]
    var inputLevel: Double

    static let empty = TranscriptOutputPayload(latestEntry: nil, window: [], inputLevel: 0)
}

// MARK: - Output Store

final class LiveTranscriptionOutputStore {
    static let shared = LiveTranscriptionOutputStore()
    private let queue = DispatchQueue(label: "LiveTranscriptionOutputStore")
    private var payloadByTileId: [UUID: TranscriptOutputPayload] = [:]

    func update(tileId: UUID, payload: TranscriptOutputPayload) {
        queue.async {
            self.payloadByTileId[tileId] = payload
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .liveTranscriptionDidPublish,
                    object: nil,
                    userInfo: ["tileId": tileId, "payload": payload]
                )
            }
        }
    }

    func payload(for tileId: UUID) -> TranscriptOutputPayload {
        queue.sync { payloadByTileId[tileId] ?? .empty }
    }

    func clear(tileId: UUID) {
        update(tileId: tileId, payload: .empty)
    }
}

struct LiveTranscriptionSourceDescriptor: Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var color: CodableColor
}

final class LiveTranscriptionSourceRegistry {
    static let shared = LiveTranscriptionSourceRegistry()
    private let queue = DispatchQueue(label: "LiveTranscriptionSourceRegistry")
    private var sourcesByTileId: [UUID: [LiveTranscriptionSourceDescriptor]] = [:]
    private var transcriptionTileIdsByTabId: [UUID: Set<UUID>] = [:]

    func update(tabId: UUID, tileId: UUID, sources: [LiveTranscriptionSourceDescriptor]) {
        queue.async {
            self.sourcesByTileId[tileId] = sources
            var tileIds = self.transcriptionTileIdsByTabId[tabId] ?? []
            tileIds.insert(tileId)
            self.transcriptionTileIdsByTabId[tabId] = tileIds

            let groupNodeId = Self.groupNodeId(for: tabId, groupKey: "moduleGroup.transcription")
            let mergedSources = tileIds.flatMap { self.sourcesByTileId[$0] ?? [] }
            self.sourcesByTileId[groupNodeId] = Self.deduplicatedSources(mergedSources)
        }
    }

    func sources(for tileId: UUID) -> [LiveTranscriptionSourceDescriptor] {
        queue.sync { sourcesByTileId[tileId] ?? [] }
    }

    private static func deduplicatedSources(_ sources: [LiveTranscriptionSourceDescriptor]) -> [LiveTranscriptionSourceDescriptor] {
        var seen: Set<UUID> = []
        return sources.filter { seen.insert($0.id).inserted }
    }

    private static func groupNodeId(for tabId: UUID, groupKey: String) -> UUID {
        let data = Data((tabId.uuidString + "|" + groupKey).utf8)
        let digest = SHA256.hash(data: data)
        let byteArray = Array(digest.prefix(16))
        var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuidBytes) { buf in
            buf.copyBytes(from: byteArray)
        }
        return UUID(uuid: uuidBytes)
    }
}

private struct DashboardTranscriptionSourceSelection {
    var allowedSources: [LiveTranscriptionSourceConfig]
    var allAllowedSourceIDs: [UUID]
    var totalEnabledSources: Int
    var selectedEnabledSources: Int
}

extension Notification.Name {
    static let liveTranscriptionDidPublish = Notification.Name("Relay.LiveTranscription.DidPublish")
}

// MARK: - Controller

enum LiveTranscriptionState: Equatable {
    case idle
    case listening
    case permissionRequired
    case microphoneBusy
    case error(String)
}

private struct TranscriptionChannelStats {
    var rms: Double
    var peak: Double
    var lastBufferTime: Date
    var lastResultTime: Date?
    var lastError: String?
    var lastSpeechError: String?
    var inputSampleRate: Double
    var outputSampleRate: Double
    var channelCount: Int
    var lastFrameCount: Int
    var totalFrames: Int
}

private final class TranscriptionChannelPipeline: NSObject {
    let channel: TranscriptChannel
    private let quality: LiveTranscriptionQualityMode
    private let requiresOnDevice: Bool
    private let usesHelperTransport: Bool
    private let localeIdentifier: String?
    private let autoGainEnabled: Bool
    private let autoGainTarget: Double
    private let enginePreference: TranscriptionEnginePreference
    private let levelThrottler = TranscriptionThrottler()
    private var downmixer: PCMDownmixer?
    private var lastStats: TranscriptionChannelStats?
    private var transcriber: SpeechTranscribing?
    private var pendingPCM = Data()
    private let pendingPCMLock = NSLock()
    private let pcmChunkBytes = 3200
    private let maxPendingPCMBytes = 3200 * 50
    private var emittedChunkCount = 0
    private var firstBufferAt: Date?
    private var lastTranscriberRestartAt: Date?
    private var hasLoggedFirstAudio = false

    #if os(macOS)
    private var captureSession: AVCaptureSession?
    private var captureHAL: DeviceInputCaptureHAL?
    private let captureQueue = DispatchQueue(label: "Relay.Transcription.Capture", qos: .userInitiated)
    private let captureStateLock = NSLock()
    private var captureGeneration = 0
    #else
    private let capture = EngineInputCapture()
    #endif

    var onEvent: ((TranscriptEvent, TranscriptChannel) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onError: ((String) -> Void)?
    var onStats: ((UUID, TranscriptionChannelStats) -> Void)?

    init(
        channel: TranscriptChannel,
        quality: LiveTranscriptionQualityMode,
        requiresOnDevice: Bool,
        usesHelperTransport: Bool,
        localeIdentifier: String?,
        autoGainEnabled: Bool = true,
        autoGainTarget: Double = 0.06,
        enginePreference: TranscriptionEnginePreference = .auto
    ) throws {
        self.channel = channel
        self.quality = quality
        self.requiresOnDevice = requiresOnDevice
        self.usesHelperTransport = usesHelperTransport
        self.localeIdentifier = localeIdentifier
        self.autoGainEnabled = autoGainEnabled
        self.autoGainTarget = autoGainTarget
        self.enginePreference = enginePreference
        super.init()
    }

    func start() throws {
        log("start requested deviceUID=\(channel.deviceUID ?? "default") channelIndex=\(channel.channelIndex) onDevice=\(requiresOnDevice) locale=\(localeIdentifier ?? "system")")
        if transcriber == nil {
            transcriber = try ensureTranscriber()
        }
        try transcriber?.start()
        log("transcriber started")

        #if os(macOS)
        beginCaptureAsync(deviceUID: channel.deviceUID)
        log("capture startup scheduled")
        #else
        capture.onBuffer = { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
        try capture.start()
        log("capture started")
        #endif
    }

    func stop() {
        log("stop requested emittedChunks=\(emittedChunkCount)")
        #if os(macOS)
        _ = nextCaptureGeneration()
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.captureHAL?.stop()
            self.captureHAL = nil
        }
        #else
        capture.stop()
        #endif
        transcriber?.stop()
        transcriber = nil
        firstBufferAt = nil
        lastTranscriberRestartAt = nil
        pendingPCMLock.lock()
        pendingPCM.removeAll()
        pendingPCMLock.unlock()
    }

    #if os(macOS)
    private func beginCaptureAsync(deviceUID: String?) {
        let generation = nextCaptureGeneration()
        let channelIndex = channel.channelIndex
        captureQueue.async { [weak self] in
            self?.beginCapture(deviceUID: deviceUID, channelIndex: channelIndex, generation: generation)
        }
    }

    private func nextCaptureGeneration() -> Int {
        captureStateLock.lock()
        defer { captureStateLock.unlock() }
        captureGeneration += 1
        return captureGeneration
    }

    private func isCurrentCaptureGeneration(_ generation: Int) -> Bool {
        captureStateLock.lock()
        defer { captureStateLock.unlock() }
        return captureGeneration == generation
    }

    private func beginCapture(deviceUID: String?, channelIndex: Int, generation: Int) {
        captureSession?.stopRunning()
        captureSession = nil
        captureHAL?.stop()
        captureHAL = nil

        do {
            if let uid = deviceUID, !uid.isEmpty {
                try startCaptureHAL(deviceUID: uid, channelIndex: channelIndex, generation: generation)
            } else {
                let device = captureDevice(for: deviceUID)
                try startCaptureSession(with: device, generation: generation)
            }
            guard isCurrentCaptureGeneration(generation) else {
                captureSession?.stopRunning()
                captureSession = nil
                captureHAL?.stop()
                captureHAL = nil
                return
            }
            log("capture started")
        } catch {
            guard isCurrentCaptureGeneration(generation) else { return }
            onError?(error.localizedDescription)
        }
    }

    private func captureDevice(for deviceUID: String?) -> AVCaptureDevice? {
        guard let deviceUID, !deviceUID.isEmpty else {
            return AVCaptureDevice.default(for: .audio)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.first(where: { $0.uniqueID == deviceUID })
    }

    private func startCaptureSession(with device: AVCaptureDevice?, generation: Int) throws {
        let session = AVCaptureSession()
        session.beginConfiguration()

        guard let device else {
            session.commitConfiguration()
            throw NSError(domain: "Relay.Transcription", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio device unavailable"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48000
        ]
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        output.setSampleBufferDelegate(self, queue: captureQueue)

        session.commitConfiguration()
        session.startRunning()
        guard isCurrentCaptureGeneration(generation) else {
            session.stopRunning()
            return
        }
        captureSession = session
        log("using AVCaptureSession device=\(device.uniqueID)")
    }

    private func startCaptureHAL(deviceUID: String, channelIndex: Int, generation: Int) throws {
        guard let deviceId = AudioDeviceEnumerator.deviceId(for: deviceUID) else {
            throw NSError(domain: "Relay.Transcription", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio device not found"])
        }

        let hal = DeviceInputCaptureHAL(deviceId: deviceId)
        hal.channelIndex = channelIndex
        hal.onBuffer = { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
        try hal.start()
        guard isCurrentCaptureGeneration(generation) else {
            hal.stop()
            return
        }
        captureHAL = hal
        log("using HAL deviceUID=\(deviceUID) deviceId=\(deviceId)")
    }

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return nil
        }

        var streamDesc = asbd
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        var bufferListSize = MemoryLayout<AudioBufferList>.size

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: &audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let srcList = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        let dstList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for i in 0..<min(srcList.count, dstList.count) {
            let src = srcList[i]
            let dst = dstList[i]
            if let srcData = src.mData, let dstData = dst.mData {
                memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
            }
        }
        return buffer
    }
    #endif

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        if !hasLoggedFirstAudio {
            hasLoggedFirstAudio = true
            firstBufferAt = Date()
            log("first audio buffer sampleRate=\(String(format: "%.0f", buffer.format.sampleRate)) channels=\(buffer.format.channelCount)")
        }
        if downmixer == nil {
            downmixer = PCMDownmixer(
                inputFormat: buffer.format,
                channelIndex: channel.channelIndex,
                targetSampleRate: 16000
            )
        }
        guard let mono = downmixer?.monoBuffer(from: buffer) else { return }
        if autoGainEnabled {
            let gain = computeAutoGain(for: mono, target: autoGainTarget)
            if gain != 1.0 {
                applyGain(gain, to: mono)
            }
        }
        let level = Self.sanitizedAudioLevel(rmsLevel(from: mono))
        let peak = Self.sanitizedAudioLevel(peakLevel(from: mono))
        let priorFrames = lastStats?.totalFrames ?? 0
        let stats = TranscriptionChannelStats(
            rms: level,
            peak: peak,
            lastBufferTime: Date(),
            lastResultTime: lastStats?.lastResultTime,
            lastError: lastStats?.lastError,
            lastSpeechError: lastStats?.lastSpeechError,
            inputSampleRate: Self.sanitizedSampleRate(buffer.format.sampleRate),
            outputSampleRate: Self.sanitizedSampleRate(mono.format.sampleRate),
            channelCount: Int(buffer.format.channelCount),
            lastFrameCount: Int(mono.frameLength),
            totalFrames: priorFrames + Int(mono.frameLength)
        )
        lastStats = stats
        if let pcmData = int16Data(from: mono) {
            pendingPCMLock.lock()
            pendingPCM.append(pcmData)
            if pendingPCM.count > maxPendingPCMBytes {
                let overflow = pendingPCM.count - maxPendingPCMBytes
                pendingPCM.removeFirst(overflow)
            }
            while pendingPCM.count >= pcmChunkBytes {
                let chunk = pendingPCM.prefix(pcmChunkBytes)
                emittedChunkCount += 1
                if emittedChunkCount == 1 || emittedChunkCount % 50 == 0 {
                    log("forwarding pcm chunk=\(emittedChunkCount) bytes=\(chunk.count) sampleRate=\(String(format: "%.0f", mono.format.sampleRate))")
                }
                transcriber?.append(pcmData: Data(chunk), sampleRate: mono.format.sampleRate)
                pendingPCM.removeFirst(pcmChunkBytes)
            }
            pendingPCMLock.unlock()
        }
        let channelId = channel.id
        levelThrottler.publish(isFinal: false, targetHz: quality.publishHz) { [weak self] in
            self?.onLevel?(Self.sanitizedAudioLevel(level))
            if let stats = self?.lastStats {
                self?.onStats?(channelId, stats)
            }
        }
    }

    private func ensureTranscriber() throws -> SpeechTranscribing {
        let config = SpeechTranscriber.Config(
            publishHz: quality.publishHz,
            requiresOnDevice: requiresOnDevice,
            localeIdentifier: localeIdentifier
        )
        #if os(macOS)
        let transcriber: SpeechTranscribing
        if usesHelperTransport {
            transcriber = XPCSpeechTranscriberAdapter(config: config)
        } else {
            transcriber = InProcessSpeechTranscriberAdapter(config: config)
        }
        #else
        let transcriber: SpeechTranscribing = InProcessSpeechTranscriberAdapter(config: config)
        #endif
        transcriber.onPartial = { [weak self] text, confidence in
            self?.log("partial textLength=\(text.count) confidence=\(Self.formatConfidence(confidence))")
            self?.emitEvent(text: text, isFinal: false, confidence: confidence)
        }
        transcriber.onFinal = { [weak self] text, confidence in
            self?.log("final textLength=\(text.count) confidence=\(Self.formatConfidence(confidence))")
            self?.emitEvent(text: text, isFinal: true, confidence: confidence)
        }
        transcriber.onError = { [weak self] failure in
            self?.log("transcriber error: \(failure.message)")
            self?.onError?(failure.message)
            if var stats = self?.lastStats {
                stats.lastSpeechError = failure.message
                self?.lastStats = stats
            }
        }
        return transcriber
    }

    func restartTranscriberIfStalled(now: Date, quietWindow: TimeInterval = 8.0) {
        guard let stats = lastStats else { return }
        guard now.timeIntervalSince(stats.lastBufferTime) <= 1.5 else { return }
        let referenceTime = stats.lastResultTime ?? firstBufferAt
        guard let referenceTime else { return }
        guard now.timeIntervalSince(referenceTime) >= quietWindow else { return }
        if let lastRestart = lastTranscriberRestartAt,
           now.timeIntervalSince(lastRestart) < quietWindow {
            return
        }
        guard let existing = transcriber else { return }
        lastTranscriberRestartAt = now
        log("restarting stalled transcriber after quietWindow=\(String(format: "%.1f", quietWindow))s")
        existing.stop()
        do {
            let replacement = try ensureTranscriber()
            transcriber = replacement
            try replacement.start()
            if var stats = lastStats {
                stats.lastSpeechError = nil
                lastStats = stats
            }
            log("stalled transcriber restarted")
        } catch {
            let message = error.localizedDescription
            log("stalled transcriber restart failed: \(message)")
            if var stats = lastStats {
                stats.lastSpeechError = message
                lastStats = stats
            }
            onError?(message)
        }
    }

    private func log(_ message: String) {
        print("[Transcription Pipeline][\(channel.displayName)] \(message)")
    }

    private static func formatConfidence(_ confidence: Double?) -> String {
        guard let confidence else { return "n/a" }
        return String(format: "%.3f", confidence)
    }

    private func int16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }
        guard let channelData = buffer.floatChannelData else { return nil }
        let channel = channelData.pointee
        var data = Data(count: frameCount * MemoryLayout<Int16>.size)
        data.withUnsafeMutableBytes { raw in
            guard let dst = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for i in 0..<frameCount {
                let rawSample = channel[i]
                let sample = rawSample.isFinite ? max(-1.0, min(1.0, rawSample)) : 0
                dst[i] = Int16(sample * Float(Int16.max))
            }
        }
        return data
    }

    private func emitEvent(text: String, isFinal: Bool, confidence: Double?) {
        let event = TranscriptEvent(
            channelId: channel.id,
            timestamp: Date(),
            text: text,
            isFinal: isFinal,
            confidence: confidence
        )
        onEvent?(event, channel)
    }

    private func rmsLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channel = channelData.pointee
        var sum: Double = 0
        for i in 0..<frameCount {
            let sample = Double(channel[i])
            guard sample.isFinite else { continue }
            sum += sample * sample
        }
        return Self.sanitizedAudioLevel(sqrt(sum / Double(frameCount)))
    }

    private func computeAutoGain(for buffer: AVAudioPCMBuffer, target: Double) -> Float {
        let rms = rmsLevel(from: buffer)
        guard rms.isFinite, rms > 0 else { return 1.0 }
        let gain = min(8.0, max(0.25, target / rms))
        return gain.isFinite ? Float(gain) : 1.0
    }

    private func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channel = channelData.pointee
        for i in 0..<frameCount {
            guard channel[i].isFinite else {
                channel[i] = 0
                continue
            }
            let sample = channel[i] * gain
            let limited = softLimit(sample)
            channel[i] = limited.isFinite ? max(-1.0, min(1.0, limited)) : 0
        }
    }

    private func peakLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channel = channelData.pointee
        var peak: Double = 0
        for i in 0..<frameCount {
            let sample = abs(Double(channel[i]))
            guard sample.isFinite else { continue }
            if sample > peak { peak = sample }
        }
        return Self.sanitizedAudioLevel(peak)
    }

    private func softLimit(_ sample: Float) -> Float {
        let drive = Float(2.0)
        let x = Double(sample * drive)
        let denom = tanh(Double(drive))
        guard denom != 0 else { return sample }
        let limited = tanh(x) / denom
        return limited.isFinite ? Float(limited) : 0
    }

    private static func sanitizedAudioLevel(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private static func sanitizedSampleRate(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }
}

#if os(macOS)
extension TranscriptionChannelPipeline: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let buffer = pcmBuffer(from: sampleBuffer) else { return }
        handleBuffer(buffer)
    }
}
#endif

@MainActor
final class LiveTranscriptionController: ObservableObject {
    private final class WeakControllerBox {
        weak var controller: LiveTranscriptionController?

        init(controller: LiveTranscriptionController?) {
            self.controller = controller
        }
    }

    private static var activeControllers: [UUID: WeakControllerBox] = [:]
    private static var sharedControllers: [UUID: LiveTranscriptionController] = [:]

    @Published private(set) var state: LiveTranscriptionState = .idle
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var debugInfo: String = ""
    @Published private(set) var inputWarning: String?

    private let tileId: UUID
    private let tabId: UUID
    private var settings: LiveTranscriptionModuleModel
    private var tabSnapshot: DashboardTab
    private var isLiveMode = false
    private var isLinked = false
    private var isRunning = false
    private var isStarting = false
    private var startGeneration = 0
    private var pipelines: [UUID: TranscriptionChannelPipeline] = [:]
    private var segmenters: [UUID: TranscriptSegmenter] = [:]
    private var channelStats: [UUID: TranscriptionChannelStats] = [:]
    private var channelLevels: [UUID: Double] = [:]
    private var committedPrefixes: [UUID: String] = [:]
    private struct RecentFinalRecord {
        var text: String
        var timestamp: Date
    }

    private var recentFinals: [UUID: [RecentFinalRecord]] = [:]
    private var lastAudioActivity: [UUID: Date] = [:]
    private var finalWordHistoryByChannel: [UUID: [String]] = [:]
    private var configurationWarnings: [String] = []
    private var runtimeWarningsByChannel: [UUID: String] = [:]
    private var moduleWarning: String?
    private var transcriptionLocaleIdentifier: String?
    private let levelPublishThrottler = TranscriptionThrottler()
    private let duplicateFinalSuppressWindow: TimeInterval = 1.5
    private let segmenterConfig = TranscriptSegmenterConfig(
        silenceGapSeconds: 0.8,
        maxLineAgeSeconds: 4.0,
        minCharsForPunctuationFlush: 24,
        maxChars: 140
    )
    private var silenceTimer: DispatchSourceTimer?
    private var retryWorkItem: DispatchWorkItem?
    private let logQueue = DispatchQueue(label: "LiveTranscription.Log", qos: .userInitiated)
    private var transcriptionInputsObserver: NSObjectProtocol?

    static func shared(
        tabId: UUID,
        tileId: UUID,
        settings: LiveTranscriptionModuleModel,
        tabSnapshot: DashboardTab,
        transcriptionLocaleIdentifier: String?
    ) -> LiveTranscriptionController {
        if let existing = sharedControllers[tileId] {
            return existing
        }
        let controller = LiveTranscriptionController(
            tabId: tabId,
            tileId: tileId,
            settings: settings,
            tabSnapshot: tabSnapshot,
            transcriptionLocaleIdentifier: transcriptionLocaleIdentifier
        )
        sharedControllers[tileId] = controller
        return controller
    }

    init(
        tabId: UUID,
        tileId: UUID,
        settings: LiveTranscriptionModuleModel,
        tabSnapshot: DashboardTab,
        transcriptionLocaleIdentifier: String?
    ) {
        self.tabId = tabId
        self.tileId = tileId
        self.settings = settings
        self.tabSnapshot = tabSnapshot
        self.transcriptionLocaleIdentifier = transcriptionLocaleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        LiveTranscriptionSourceRegistry.shared.update(
            tabId: tabId,
            tileId: tileId,
            sources: settings.sources.map { LiveTranscriptionSourceDescriptor(id: $0.id, displayName: $0.transcriptDisplayName, color: $0.color) }
        )
        restoreFromStore()
        transcriptionInputsObserver = NotificationCenter.default.addObserver(
            forName: .transcriptionInputsConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.recomputeDisplayTexts()
                self.evaluateRunState(restartIfRunning: true)
            }
        }
    }

    deinit {
        if let observer = transcriptionInputsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        let tileId = tileId
        Task { @MainActor in
            if Self.activeControllers[tileId]?.controller == nil {
                Self.activeControllers[tileId] = nil
            }
        }
    }

    func updateSettings(_ settings: LiveTranscriptionModuleModel) {
        let previousSettings = self.settings
        self.settings = settings
        LiveTranscriptionSourceRegistry.shared.update(
            tabId: tabId,
            tileId: tileId,
            sources: settings.sources.map { LiveTranscriptionSourceDescriptor(id: $0.id, displayName: $0.transcriptDisplayName, color: $0.color) }
        )
        restoreFromStore()
        recomputeDisplayTexts()
        trimLogIfNeeded()
        if !settings.showsDiagnostics {
            debugInfo = ""
        }
        if requiresPipelineRestart(from: previousSettings, to: settings) {
            evaluateRunState(restartIfRunning: true)
        } else if previousSettings.isEnabled != settings.isEnabled {
            evaluateRunState(restartIfRunning: false)
        }
    }

    func updateTabSnapshot(_ tabSnapshot: DashboardTab) {
        guard tabSnapshot.id == tabId else { return }
        let previousAllowedSourceIds = Set(dashboardSourceSelection(in: self.tabSnapshot).allowedSources.map(\.id))
        self.tabSnapshot = tabSnapshot
        let updatedAllowedSourceIds = Set(dashboardSourceSelection(in: tabSnapshot).allowedSources.map(\.id))
        if previousAllowedSourceIds != updatedAllowedSourceIds {
            evaluateRunState(restartIfRunning: true)
        }
    }

    func updateTranscriptionPreferences(localeIdentifier: String?) {
        let normalized = localeIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocale = (normalized?.isEmpty ?? true) ? nil : normalized
        let didChange = normalizedLocale != transcriptionLocaleIdentifier
        transcriptionLocaleIdentifier = normalizedLocale
        if didChange {
            moduleWarning = nil
            evaluateRunState(restartIfRunning: true)
        }
    }

    func setLiveMode(_ isLiveMode: Bool) {
        let wasLive = self.isLiveMode
        guard wasLive != isLiveMode else { return }
        self.isLiveMode = isLiveMode
        evaluateRunState(restartIfRunning: isLiveMode && !wasLive)
    }

    func setLinkState(_ isLinked: Bool) {
        guard self.isLinked != isLinked else { return }
        self.isLinked = isLinked
        evaluateRunState(restartIfRunning: false)
    }

    func refreshAfterViewReturn() {
        guard !isRunning else { return }
        evaluateRunState(restartIfRunning: true)
    }

    func clearOutputs() {
        entries.removeAll()
        committedPrefixes.removeAll()
        recentFinals.removeAll()
        finalWordHistoryByChannel.removeAll()
        LiveTranscriptionOutputStore.shared.clear(tileId: tileId)
    }

    func restoreFromStore() {
        let payload = LiveTranscriptionOutputStore.shared.payload(for: tileId)
        guard !payload.window.isEmpty else { return }
        entries = payload.window
        inputLevel = payload.inputLevel
    }

    private func evaluateRunState(restartIfRunning: Bool) {
        retryWorkItem?.cancel()
        retryWorkItem = nil

        let shouldRun = isLiveMode && settings.isEnabled
        if shouldRun {
            #if os(iOS)
            if settings.sources.count > 1 {
                state = .error("iPadOS supports one input per transcription module")
                stopAll(shouldClearOutputs: true)
                return
            }
            #endif
            if (isRunning || isStarting) && restartIfRunning {
                startGeneration += 1
                stopAll(shouldClearOutputs: false)
                start()
            } else if !isRunning && !isStarting {
                start()
            }
        } else {
            startGeneration += 1
            stopAll(shouldClearOutputs: false)
        }
    }

    private func start() {
        guard !isStarting else { return }
        claimActiveOwnership()
        isStarting = true
        startGeneration += 1
        let generation = startGeneration
        Task { await startAsync(generation: generation) }
    }

    private func startAsync(generation: Int) async {
        defer {
            if startGeneration == generation {
                isStarting = false
            }
        }

        guard Self.activeControllers[tileId]?.controller === self else { return }
        guard generation == startGeneration else { return }
        guard settings.isEnabled else { return }
        guard isLiveMode else { return }

        let permissionGranted = await ensurePermissions()
        guard Self.activeControllers[tileId]?.controller === self else { return }
        guard generation == startGeneration else { return }
        if !permissionGranted {
            state = .permissionRequired
            return
        }

        let sourceSelection = dashboardSourceSelection(in: tabSnapshot)
        var enabledSources = sourceSelection.allowedSources
        if enabledSources.isEmpty {
            #if os(macOS)
            if sourceSelection.selectedEnabledSources > 0 {
                debugInfo = "Dashboard input cap reached: no slots available for this tile."
            }
            #endif
            state = .idle
            return
        }

        #if os(iOS)
        if enabledSources.count > 1 {
            enabledSources = [enabledSources[0]]
            debugInfo = "iPadOS supports one input per tile."
        } else {
            debugInfo = ""
        }
        #else
        if sourceSelection.selectedEnabledSources > enabledSources.count {
            debugInfo = "Dashboard input cap reached: using \(enabledSources.count) of \(sourceSelection.selectedEnabledSources) enabled inputs for this tile."
        } else if enabledSources.count > 2 {
            debugInfo = "Running \(enabledSources.count) sources. Performance may vary."
        } else {
            debugInfo = ""
        }
        #endif

        do {
            guard Self.activeControllers[tileId]?.controller === self else { return }
            guard generation == startGeneration else { return }
            try setupPipelines(with: enabledSources)
            guard Self.activeControllers[tileId]?.controller === self else { return }
            guard generation == startGeneration else { return }
            startSilenceTimer()
            state = .listening
            isRunning = true
        } catch {
            guard generation == startGeneration else { return }
            handleStartError(error)
        }
    }

    private func resolveTranscriptionInput(for source: LiveTranscriptionSourceConfig) -> TranscriptionInputConfig? {
        guard let transInputID = source.transInputID else { return nil }
        return TranscriptionInputsConfigStore.shared.input(for: transInputID)
    }

    /// Text filters are read from the input store on demand rather than cached at pipeline
    /// start. A cache is emptied on every restart, and entries recomputed in that window
    /// silently lost their profanity filtering.
    private func textFilters(forSourceID id: UUID) -> (profanity: ProfanityFilter, wordFilters: [WordReplacementFilter]) {
        let input = settings.sources.first(where: { $0.id == id }).flatMap(resolveTranscriptionInput(for:))
        return (ProfanityFilter(settings: input?.profanitySettings ?? LiveTranscriptionProfanitySettings()),
                input?.wordFilters ?? [])
    }

    private func setupPipelines(with sources: [LiveTranscriptionSourceConfig]) throws {
        stopPipelines()
        pipelines.removeAll()
        segmenters.removeAll()
        lastAudioActivity.removeAll()
        runtimeWarningsByChannel.removeAll()

        let localeIdentifier = SpeechTranscriber.resolvedLocaleIdentifier(preferred: transcriptionLocaleIdentifier)
        #if os(macOS)
        let supportsOnDevice = SpeechTranscriber.supportsOnDevice(localeIdentifier: localeIdentifier)
        let activeSources = sources
        let requiresOnDevice = supportsOnDevice && activeSources.count <= 1
        let dashboardSelection = dashboardSourceSelection(in: tabSnapshot)
        var warnings: [String] = []
        if activeSources.count > 2 {
            warnings.append("Running \(activeSources.count) sources. Performance may vary.")
        }
        if dashboardSelection.selectedEnabledSources > activeSources.count {
            warnings.append("Dashboard input cap reached: this tile is using \(activeSources.count) of its \(dashboardSelection.selectedEnabledSources) enabled inputs.")
        }
        if transcriptionLocaleIdentifier != nil && localeIdentifier == nil {
            warnings.append("Selected language not supported for speech. Using system default.")
        }
        if activeSources.count > 1 {
            warnings.append("Using server-based transcription for multiple sources.")
        } else if !supportsOnDevice {
            warnings.append("On-device recognition unavailable. Using server-based transcription.")
        }
        configurationWarnings = warnings
        recomputeModuleWarning()
        #else
        let supportsOnDevice = SpeechTranscriber.supportsOnDevice(localeIdentifier: localeIdentifier)
        let requiresOnDevice = supportsOnDevice
        let usesHelperTransport = false
        let activeSources = Array(sources.prefix(1))
        var warnings: [String] = []
        if !supportsOnDevice {
            warnings.append("On-device recognition unavailable. Using server-based transcription.")
        }
        configurationWarnings = warnings
        recomputeModuleWarning()
        #endif

        var firstStartupError: Error?
        for (index, source) in activeSources.enumerated() {
            let channel = TranscriptChannel(
                id: source.id,
                displayName: source.transcriptDisplayName,
                color: source.color,
                deviceUID: source.deviceUID,
                channelIndex: source.channelIndex
            )
            let resolvedInput = resolveTranscriptionInput(for: source)
            let autoGainEnabled = resolvedInput?.autoGainEnabled ?? true
            let autoGainTarget = resolvedInput?.autoGainTarget ?? 0.06
            let sourceEnginePreference = resolvedInput?.enginePreference ?? .auto
            let sourceRequiresOnDevice: Bool
            switch sourceEnginePreference {
            case .auto:
                sourceRequiresOnDevice = supportsOnDevice && activeSources.count <= 1
            case .onDevice:
                sourceRequiresOnDevice = supportsOnDevice
            case .cloud:
                sourceRequiresOnDevice = false
            }
            #if os(macOS)
            let globalSourceIndex = dashboardSelection.allAllowedSourceIDs.firstIndex(of: source.id) ?? index
            let usesHelperTransport = globalSourceIndex > 0
            #else
            let usesHelperTransport = false
            #endif
            let pipeline = try TranscriptionChannelPipeline(
                channel: channel,
                quality: settings.quality,
                requiresOnDevice: sourceRequiresOnDevice,
                usesHelperTransport: usesHelperTransport,
                localeIdentifier: localeIdentifier,
                autoGainEnabled: autoGainEnabled,
                autoGainTarget: autoGainTarget,
                enginePreference: sourceEnginePreference
            )
            pipeline.onEvent = { [weak self] event, channel in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.handleEvent(event, channel: channel)
                    if var stats = self.channelStats[channel.id] {
                        stats.lastResultTime = event.timestamp
                        stats.lastError = nil
                        stats.lastSpeechError = nil
                        self.channelStats[channel.id] = stats
                    }
                }
            }
            pipeline.onLevel = { [weak self] level in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let sanitizedLevel = Self.sanitizedInputLevel(level)
                    self.channelLevels[channel.id] = sanitizedLevel
                    self.inputLevel = Self.sanitizedInputLevel(self.channelLevels.values.max() ?? 0)
                    if sanitizedLevel >= 0.003 {
                        self.lastAudioActivity[channel.id] = Date()
                    }
                    self.levelPublishThrottler.publish(isFinal: false, targetHz: 6) { [weak self] in
                        guard let self else { return }
                        self.publishOutputs(entries: self.entries)
                    }
                }
            }
            pipeline.onError = { [weak self] message in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.runtimeWarningsByChannel[channel.id] = "\(channel.displayName): \(message)"
                    self.recomputeModuleWarning()
                    let otherActivePipelines = self.pipelines.keys.contains { $0 != channel.id }
                    if otherActivePipelines {
                        self.state = .listening
                    } else {
                        self.state = .error(message)
                    }
                    if var stats = self.channelStats[channel.id] {
                        stats.lastError = message
                        self.channelStats[channel.id] = stats
                    }
                }
            }
            pipeline.onStats = { [weak self] channelId, stats in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.channelStats[channelId] = stats
                    self.updateInputWarning()
                }
            }
            do {
                try pipeline.start()
            } catch {
                if firstStartupError == nil {
                    firstStartupError = error
                }
                runtimeWarningsByChannel[channel.id] = "\(channel.displayName): \(error.localizedDescription)"
                recomputeModuleWarning()
                continue
            }
            pipelines[channel.id] = pipeline
            segmenters[channel.id] = TranscriptSegmenter(config: segmenterConfig)
            lastAudioActivity[channel.id] = Date()
        }

        if pipelines.isEmpty, let firstStartupError {
            throw firstStartupError
        }
    }

    private func stopPipelines() {
        pipelines.values.forEach { $0.stop() }
        pipelines.removeAll()
        segmenters.removeAll()
        channelStats.removeAll()
        channelLevels.removeAll()
        committedPrefixes.removeAll()
        recentFinals.removeAll()
        lastAudioActivity.removeAll()
        runtimeWarningsByChannel.removeAll()
        inputWarning = nil
        recomputeModuleWarning()
    }

    private func updateInputWarning() {
        let hasHotInput = channelStats.values.contains { $0.peak >= 0.98 || $0.rms >= 0.25 }
        inputWarning = hasHotInput ? "Input is hot. Reduce device gain." : nil
    }

    private func recomputeModuleWarning() {
        var warnings = configurationWarnings
        let runtimeWarnings = runtimeWarningsByChannel.values.sorted()
        warnings.append(contentsOf: runtimeWarnings)
        moduleWarning = warnings.isEmpty ? nil : warnings.joined(separator: " ")
    }

    private func dashboardSourceSelection(in tab: DashboardTab) -> DashboardTranscriptionSourceSelection {
        #if os(iOS)
        let sourceLimit = 1
        #else
        let sourceLimit = 4
        #endif

        var totalEnabledSources = 0
        var selectedEnabledSources = 0
        var allowedSources: [LiveTranscriptionSourceConfig] = []
        var allAllowedSourceIDs: [UUID] = []
        var remainingSlots = sourceLimit

        for tile in tab.tiles {
            guard let modules = tile.modules else { continue }
            guard let module = modules.first(where: {
                if case .liveTranscription = $0.kind { return true }
                return false
            }) else {
                continue
            }
            guard case .liveTranscription(let model) = module.kind else { continue }
            let enabledSources = model.sources.filter(\.isEnabled)
            totalEnabledSources += enabledSources.count
            if remainingSlots > 0 {
                allAllowedSourceIDs.append(contentsOf: enabledSources.prefix(remainingSlots).map(\.id))
            }

            if tile.id == tileId {
                selectedEnabledSources = enabledSources.count
                if remainingSlots > 0 {
                    allowedSources = Array(enabledSources.prefix(remainingSlots))
                    remainingSlots -= allowedSources.count
                }
            } else if remainingSlots > 0 {
                remainingSlots -= min(remainingSlots, enabledSources.count)
            }
        }

        if totalEnabledSources == 0 {
            let enabledSources = settings.sources.filter(\.isEnabled)
            return DashboardTranscriptionSourceSelection(
                allowedSources: Array(enabledSources.prefix(sourceLimit)),
                allAllowedSourceIDs: Array(enabledSources.prefix(sourceLimit)).map(\.id),
                totalEnabledSources: enabledSources.count,
                selectedEnabledSources: enabledSources.count
            )
        }

        return DashboardTranscriptionSourceSelection(
            allowedSources: allowedSources,
            allAllowedSourceIDs: allAllowedSourceIDs,
            totalEnabledSources: totalEnabledSources,
            selectedEnabledSources: selectedEnabledSources
        )
    }

    private func stopAll(shouldClearOutputs: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.stopAll(shouldClearOutputs: shouldClearOutputs)
            }
            return
        }

        silenceTimer?.cancel()
        silenceTimer = nil
        if !shouldClearOutputs {
            finalizeInProgressEntries()
        }
        stopPipelines()
        isRunning = false
        isStarting = false
        state = .idle
        inputLevel = 0
        debugInfo = ""
        if Self.activeControllers[tileId]?.controller === self {
            Self.activeControllers[tileId] = nil
        }
        if shouldClearOutputs {
            clearOutputs()
        }
    }

    private func claimActiveOwnership() {
        if let existing = Self.activeControllers[tileId]?.controller, existing !== self {
            existing.forceStopFromOwnershipChange()
        }
        Self.activeControllers[tileId] = WeakControllerBox(controller: self)
    }

    private func forceStopFromOwnershipChange() {
        startGeneration += 1
        stopAll(shouldClearOutputs: false)
    }

    private func requiresPipelineRestart(
        from oldSettings: LiveTranscriptionModuleModel,
        to newSettings: LiveTranscriptionModuleModel
    ) -> Bool {
        oldSettings.sources != newSettings.sources || oldSettings.quality != newSettings.quality
    }

    private func finalizeInProgressEntries() {
        guard !entries.isEmpty else { return }

        var updated = entries
        var didChange = false

        for idx in updated.indices {
            if !updated[idx].isFinal {
                updated[idx].isFinal = true
                didChange = true
                committedPrefixes[updated[idx].sourceId] = updated[idx].displayText
            }
        }

        if didChange {
            entries = updated
            publishOutputs(entries: updated)
        }
    }

    private func startSilenceTimer() {
        silenceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: logQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.handleSilenceTick()
                self?.emitDebugInfo()
            }
        }
        timer.resume()
        silenceTimer = timer
    }

    private func handleSilenceTick() {
        let now = Date()
        for pipeline in pipelines.values {
            pipeline.restartTranscriberIfStalled(now: now)
        }
        for (channelId, segmenter) in segmenters {
            if let lastAudio = lastAudioActivity[channelId],
               now.timeIntervalSince(lastAudio) >= segmenterConfig.silenceGapSeconds,
               let update = segmenter.forceFlush(now: now) {
                applySegmenterUpdate(update, channelId: channelId)
                continue
            }
            if let update = segmenter.tick(now: now) {
                applySegmenterUpdate(update, channelId: channelId)
            }
        }
    }

    private func emitDebugInfo() {
        guard settings.showsDiagnostics else {
            if !debugInfo.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.debugInfo = ""
                }
            }
            return
        }
        guard !channelStats.isEmpty else { return }
        var lines: [String] = channelStats.compactMap { channelId, stats in
            let name = settings.sources.first(where: { $0.id == channelId })?.displayName ?? "Source"
            let lastAge = max(0, Date().timeIntervalSince(stats.lastBufferTime))
            let rmsText = String(format: "%.4f", stats.rms)
            let peakText = String(format: "%.4f", stats.peak)
            let ageText = String(format: "%.1fs", lastAge)
            let resultAgeText: String
            if let lastResult = stats.lastResultTime {
                let resultAge = max(0, Date().timeIntervalSince(lastResult))
                resultAgeText = String(format: "%.1fs", resultAge)
            } else {
                resultAgeText = "-"
            }
            let errorText = stats.lastError ?? "none"
            let speechErrorText = stats.lastSpeechError ?? "none"
            return "\(name): rms=\(rmsText) peak=\(peakText) in=\(Int(stats.inputSampleRate)) out=\(Int(stats.outputSampleRate)) ch=\(stats.channelCount) frames=\(stats.lastFrameCount) total=\(stats.totalFrames) lastBuf=\(ageText) lastResult=\(resultAgeText) err=\(errorText) speechErr=\(speechErrorText)"
        }.sorted()

        if let warning = moduleWarning {
            lines.insert("Warning: \(warning)", at: 0)
        }

        DispatchQueue.main.async { [lines] in
            self.debugInfo = lines.joined(separator: "\n")
        }
    }

    private func handleEvent(_ event: TranscriptEvent, channel: TranscriptChannel) {
        guard let segmenter = segmenters[channel.id] else { return }
        let baseText = event.isFinal ? event.text : stripLeadingFinalText(event.text, channelId: channel.id)
        let cleanedText = stripCommittedPrefix(baseText, channelId: channel.id)
        let update = segmenter.handleUpdate(text: cleanedText, isFinal: event.isFinal, now: event.timestamp)
        segmenters[channel.id] = segmenter
        applySegmenterUpdate(update, channelId: channel.id, overrideChannel: channel)
    }

    private func applySegmenterUpdate(_ update: TranscriptSegmenterUpdate, channelId: UUID, overrideChannel: TranscriptChannel? = nil) {
        let channel = overrideChannel ?? TranscriptChannel(
            id: channelId,
            displayName: settings.sources.first(where: { $0.id == channelId })?.transcriptDisplayName ?? "Source",
            color: settings.sources.first(where: { $0.id == channelId })?.color ?? CodableColor(.white),
            deviceUID: settings.sources.first(where: { $0.id == channelId })?.deviceUID,
            channelIndex: settings.sources.first(where: { $0.id == channelId })?.channelIndex ?? 0
        )

        switch update.kind {
        case .none:
            return
        case .partial(let text):
            appendEntry(
                source: channel,
                raw: text,
                display: text,
                isFinal: false,
                confidence: nil,
                timestamp: update.timestamp
            )
        case .flush(let text):
            guard !text.isEmpty else { return }
            let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty else { return }
            appendEntry(
                source: channel,
                raw: cleanedText,
                display: cleanedText,
                isFinal: true,
                confidence: nil,
                timestamp: update.timestamp
            )
        }
    }

    private func stripCommittedPrefix(_ text: String, channelId: UUID) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = committedPrefixes[channelId], !prefix.isEmpty else {
            return trimmed
        }

        let normalizedText = normalizeForDedup(trimmed)
        let normalizedPrefix = normalizeForDedup(prefix)
        if normalizedText.isEmpty { return "" }

        if normalizedText.hasPrefix(normalizedPrefix) {
            // If the recognizer produced the same text again, preserve it so repeated
            // spoken trigger words still appear in the transcript/output stream.
            if normalizedText == normalizedPrefix {
                return trimmed
            }
            let remainder = String(normalizedText.dropFirst(normalizedPrefix.count))
            let cleanedRemainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanedRemainder.isEmpty ? trimmed : cleanedRemainder
        }

        let textWords = normalizedText.split(separator: " ").map(String.init)
        let prefixWords = normalizedPrefix.split(separator: " ").map(String.init)
        if textWords.isEmpty { return trimmed }

        if let dropIndex = lastOverlapDropIndex(textWords: textWords, prefixWords: prefixWords) {
            if dropIndex >= textWords.count {
                return trimmed
            }
            let remainderWords = textWords.dropFirst(dropIndex)
            return remainderWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        committedPrefixes[channelId] = ""
        return trimmed
    }

    private func updateCommittedPrefix(_ flushed: String, channelId: UUID) {
        let trimmed = flushed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = committedPrefixes[channelId]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existing.isEmpty {
            committedPrefixes[channelId] = trimmed
        } else {
            committedPrefixes[channelId] = "\(existing) \(trimmed)"
        }
    }

    private func shouldSkipFinal(_ text: String, channelId: UUID, now: Date) -> Bool {
        let normalized = normalizeForDedup(text)
        guard !normalized.isEmpty else { return true }
        let recent = (recentFinals[channelId] ?? []).filter { now.timeIntervalSince($0.timestamp) <= duplicateFinalSuppressWindow }
        recentFinals[channelId] = recent
        for entry in recent {
            if entry.text.contains(normalized) || normalized.contains(entry.text) {
                return true
            }
            if isNearDuplicate(lhs: normalized, rhs: entry.text) {
                return true
            }
        }
        return false
    }

    private func recordFinal(_ text: String, channelId: UUID, timestamp: Date) {
        let normalized = normalizeForDedup(text)
        guard !normalized.isEmpty else { return }
        var recent = (recentFinals[channelId] ?? []).filter { timestamp.timeIntervalSince($0.timestamp) <= duplicateFinalSuppressWindow }
        recent.append(RecentFinalRecord(text: normalized, timestamp: timestamp))
        if recent.count > 6 {
            recent = Array(recent.suffix(6))
        }
        recentFinals[channelId] = recent
    }

    private func normalizeForDedup(_ text: String) -> String {
        let lowered = text.lowercased()
        let collapsed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private func lastOverlapDropIndex(textWords: [String], prefixWords: [String]) -> Int? {
        guard !prefixWords.isEmpty else { return nil }
        let maxScan = min(textWords.count, prefixWords.count)
        var best: Int? = nil
        for k in stride(from: maxScan, to: 0, by: -1) {
            let textSlice = textWords.prefix(k)
            let prefixSlice = prefixWords.suffix(k)
            if textSlice.elementsEqual(prefixSlice) {
                best = k
                break
            }
        }
        return best
    }

    private func isNearDuplicate(lhs: String, rhs: String) -> Bool {
        let left = lhs.split(separator: " ").map(String.init)
        let right = rhs.split(separator: " ").map(String.init)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let leftSet = Set(left)
        let rightSet = Set(right)
        let intersection = leftSet.intersection(rightSet).count
        let union = leftSet.union(rightSet).count
        guard union > 0 else { return false }
        let similarity = Double(intersection) / Double(union)
        if similarity >= 0.85 {
            let lengthRatio = Double(min(left.count, right.count)) / Double(max(left.count, right.count))
            return lengthRatio >= 0.8
        }
        return false
    }

    private func applyWordFilters(_ filters: [WordReplacementFilter], to text: String) -> String {
        guard !filters.isEmpty else { return text }
        var result = text
        for filter in filters {
            let from = filter.from.trimmingCharacters(in: .whitespacesAndNewlines)
            let to = filter.to
            guard !from.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: from)
            guard let regex = try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: to)
        }
        return result
    }

    private func appendEntry(
        source: TranscriptChannel,
        raw: String,
        display: String,
        isFinal: Bool,
        confidence: Double?,
        timestamp: Date
    ) {
        let retention = settings.retention
        let filters = textFilters(forSourceID: source.id)
        let displayText = applyWordFilters(filters.wordFilters, to: filters.profanity.apply(to: display))
        let normalizedDisplay = normalizeForDedup(displayText)

        if isFinal, shouldSkipFinal(displayText, channelId: source.id, now: timestamp) {
            return
        }

        let currentEntries = entries
        let hasActivePartial = currentEntries.contains { $0.sourceId == source.id && !$0.isFinal }
        if let lastFinal = currentEntries.last(where: { $0.sourceId == source.id && $0.isFinal }) {
            let lastNormalized = normalizeForDedup(lastFinal.displayText)
            if !normalizedDisplay.isEmpty {
                let isDuplicateFinal = normalizedDisplay == lastNormalized
                    || lastNormalized.contains(normalizedDisplay)
                    || normalizedDisplay.contains(lastNormalized)
                let isRecentDuplicateFinal = timestamp.timeIntervalSince(lastFinal.timestamp) <= duplicateFinalSuppressWindow
                if isFinal && isDuplicateFinal && isRecentDuplicateFinal {
                    return
                }
                if !isFinal, normalizedDisplay == lastNormalized, !hasActivePartial {
                    return
                }
            }
        }

        var updated = currentEntries

        if let index = updated.lastIndex(where: { $0.sourceId == source.id && !$0.isFinal }) {
            let existing = updated[index]
            let existingNormalized = normalizeForDedup(existing.displayText)
            if !isFinal,
               !normalizedDisplay.isEmpty,
               normalizedDisplay.count < existingNormalized.count,
               existingNormalized.contains(normalizedDisplay) {
                return
            }
            let existingTimestamp = updated[index].timestamp
            updated[index] = TranscriptEntry(
                id: existing.id,
                timestamp: existingTimestamp,
                sourceId: source.id,
                sourceDisplayName: source.displayName,
                rawText: raw,
                displayText: displayText,
                isFinal: isFinal,
                confidence: confidence
            )
        } else {
            updated.append(
                TranscriptEntry(
                    id: UUID(),
                    timestamp: timestamp,
                    sourceId: source.id,
                    sourceDisplayName: source.displayName,
                    rawText: raw,
                    displayText: displayText,
                    isFinal: isFinal,
                    confidence: confidence
                )
            )
        }

        if isFinal {
            updated.removeAll { $0.sourceId == source.id && !$0.isFinal }
        }

        let trimmed = LiveTranscriptionController.trimmedEntries(updated, retention: retention)
        entries = trimmed.sorted { $0.timestamp < $1.timestamp }
        if isFinal {
            appendFinalWordHistory(displayText, channelId: source.id)
            recordFinal(displayText, channelId: source.id, timestamp: timestamp)
            updateCommittedPrefix(displayText, channelId: source.id)
        }
        publishOutputs(entries: entries)
    }

    private func stripLeadingFinalText(_ text: String, channelId: UUID) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = normalizeForDedup(trimmed)
        if normalizedText.isEmpty { return "" }
        guard let history = finalWordHistoryByChannel[channelId], !history.isEmpty else {
            return trimmed
        }

        let normalizedWords = normalizedText.split(separator: " ").map(String.init)
        guard !normalizedWords.isEmpty else { return "" }
        let originalWords = trimmed.split(separator: " ").map(String.init)

        let dropCount = suffixPrefixOverlap(textWords: normalizedWords, historyWords: history)
        guard dropCount >= 3 else { return trimmed }
        let remainingCount = normalizedWords.count - dropCount
        if remainingCount <= 2 {
            return trimmed
        }
        let remainder = originalWords.dropFirst(dropCount).joined(separator: " ")
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    

    private func appendFinalWordHistory(_ text: String, channelId: UUID) {
        let normalized = normalizeForDedup(text)
        guard !normalized.isEmpty else { return }
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return }
        var history = finalWordHistoryByChannel[channelId] ?? []
        history.append(contentsOf: words)
        let cap = 800
        if history.count > cap {
            history.removeFirst(history.count - cap)
        }
        finalWordHistoryByChannel[channelId] = history
    }

    private func suffixPrefixOverlap(textWords: [String], historyWords: [String]) -> Int {
        guard !textWords.isEmpty, !historyWords.isEmpty else { return 0 }
        let maxHistoryWindow = 200
        let history = historyWords.count > maxHistoryWindow
            ? Array(historyWords.suffix(maxHistoryWindow))
            : historyWords
        let maxLen = min(textWords.count, history.count)
        for k in stride(from: maxLen, to: 0, by: -1) {
            let textSlice = textWords.prefix(k)
            let historySlice = history.suffix(k)
            if textSlice.elementsEqual(historySlice) {
                return k
            }
        }
        return 0
    }

    nonisolated private static func trimmedEntries(
        _ entries: [TranscriptEntry],
        retention: LiveTranscriptionRetentionSettings
    ) -> [TranscriptEntry] {
        guard retention.limitsEnabled == true else {
            return entries
        }

        var result = entries

        if let maxMinutes = retention.maxMinutes, maxMinutes > 0 {
            let cutoff = Date().addingTimeInterval(-Double(maxMinutes) * 60)
            result = result.filter { $0.timestamp >= cutoff }
        }

        if let maxEntries = retention.maxEntries, maxEntries > 0, result.count > maxEntries {
            result = Array(result.suffix(maxEntries))
        }

        if let maxChars = retention.maxCharacters, maxChars > 0 {
            var total = 0
            var trimmed: [TranscriptEntry] = []
            for entry in result.reversed() {
                let length = entry.rawText.count
                if total + length > maxChars { break }
                total += length
                trimmed.append(entry)
            }
            result = trimmed.reversed()
        }

        return result
    }

    private func recomputeDisplayTexts() {
        var filtersBySource: [UUID: (profanity: ProfanityFilter, wordFilters: [WordReplacementFilter])] = [:]
        let updated = entries.map { entry in
            let source = settings.sources.first(where: { $0.id == entry.sourceId })
            let filters = filtersBySource[entry.sourceId] ?? textFilters(forSourceID: entry.sourceId)
            filtersBySource[entry.sourceId] = filters
            return TranscriptEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                sourceId: entry.sourceId,
                sourceDisplayName: source?.transcriptDisplayName ?? entry.sourceDisplayName,
                rawText: entry.rawText,
                displayText: applyWordFilters(filters.wordFilters, to: filters.profanity.apply(to: entry.rawText)),
                isFinal: entry.isFinal,
                confidence: entry.confidence
            )
        }
        entries = updated
        publishOutputs(entries: updated)
    }

    private func trimLogIfNeeded() {
        let trimmed = LiveTranscriptionController.trimmedEntries(entries, retention: settings.retention)
        if trimmed != entries {
            entries = trimmed
            publishOutputs(entries: trimmed)
        }
    }

    private func publishOutputs(entries: [TranscriptEntry]) {
        let latest = entries.last
        let payload = TranscriptOutputPayload(latestEntry: latest, window: entries, inputLevel: Self.sanitizedInputLevel(inputLevel))
        LiveTranscriptionOutputStore.shared.update(tileId: tileId, payload: payload)
    }

    private static func sanitizedInputLevel(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private func handleStartError(_ error: Error) {
        #if os(iOS)
        let nsError = error as NSError
        if nsError.domain == "AVAudioSessionErrorDomain",
           nsError.code == AVAudioSession.ErrorCode.isBusy.rawValue {
            state = .microphoneBusy
            scheduleRetry()
            return
        }
        #endif
        if (error as NSError).localizedDescription.localizedCaseInsensitiveContains("busy") {
            state = .microphoneBusy
            scheduleRetry()
        } else {
            state = .error(error.localizedDescription)
        }
    }

    private func scheduleRetry() {
        retryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.evaluateRunState(restartIfRunning: false)
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func ensurePermissions() async -> Bool {
        let micGranted = await requestMicPermission()
        guard micGranted else { return false }
        let speechGranted = await requestSpeechPermission()
        return speechGranted
    }

    private func requestMicPermission() async -> Bool {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch { }
        return await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        #else
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

// MARK: - Tile View

struct LiveTranscriptionTileView: View {
    @Binding var tab: DashboardTab
    @Binding var tile: DashboardTileModel
    @Binding var module: DashboardModuleModel
    let isLiveMode: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    @AppStorage("dashboard_live_mode_enabled") private var liveModeEnabled: Bool = false
    @AppStorage("dashboard_transcription_locale_identifier") private var transcriptionLocaleIdentifier: String = ""
    @AppStorage("dashboard_app_language_locale_identifier") private var appLanguageLocaleIdentifier: String = ""
    @StateObject private var controller: LiveTranscriptionController
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var isPinnedToBottom: Bool = true
    @State private var autoScrollEnabled: Bool = true
    @State private var scrollerAlpha: CGFloat = 0.0
    @State private var scrollerHideWorkItem: DispatchWorkItem?
    @State private var relativeTimestampRefreshDate: Date = Date()
    private let chromeTextColor = Color.white.opacity(0.72)

    private var effectiveLiveMode: Bool {
        isLiveMode || liveModeEnabled
    }

    private var preferredTranscriptionLocaleIdentifier: String? {
        let trimmed = transcriptionLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        let appTrimmed = appLanguageLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return appTrimmed.isEmpty ? nil : appTrimmed
    }

    init(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) {
        self._tab = tab
        self._tile = tile
        self._module = module
        self.isLiveMode = isLiveMode

        let model = LiveTranscriptionTileView.resolveModel(module: module.wrappedValue)
        _controller = StateObject(
            wrappedValue: LiveTranscriptionController.shared(
                tabId: tab.wrappedValue.id,
                tileId: tile.wrappedValue.id,
                settings: model,
                tabSnapshot: tab.wrappedValue,
                transcriptionLocaleIdentifier: nil
            )
        )
    }

    var body: some View {
        let model = LiveTranscriptionTileView.resolveModel(module: module)
        let tileId = tile.id
        if isLANSnapshotRendering {
            lanSnapshotView(model: model)
        } else {
            let content = VStack(alignment: .leading, spacing: 10) {
                header(model: model)

                ScrollViewReader { proxy in
                    ScrollView {
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .named("transcriptionScroll")).minY
                                )
                        }
                        .frame(height: 0)
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(controller.entries) { entry in
                                TranscriptRow(
                                    entry: entry,
                                    color: colorForSource(entry.sourceId, model: model),
                                    underlineRules: underlineRules,
                                    usesRelativeTimestamp: model.usesRelativeTimestamps == true,
                                    relativeTimestampRefreshDate: relativeTimestampRefreshDate
                                )
                                .id(entry.id)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: ScrollContentHeightPreferenceKey.self, value: geo.size.height)
                            }
                        )
                    }
                    .coordinateSpace(.named("transcriptionScroll"))
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .layoutPriority(1)
#if os(macOS)
                    .background(ScrollViewConfigurator(scrollerAlpha: $scrollerAlpha))
#endif
                    .onChange(of: controller.entries.count) { _, _ in
                        guard autoScrollEnabled, let last = controller.entries.last else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                        let maxOffset = scrollViewHeight - contentHeight
                        let pinnedThreshold: CGFloat = 24
                        let pinned = contentHeight <= scrollViewHeight || value <= maxOffset + pinnedThreshold
                        isPinnedToBottom = pinned
                        if pinned {
                            autoScrollEnabled = true
                        } else {
                            autoScrollEnabled = false
                        }
                        showScrollerTemporarily()
                    }
                    .onPreferenceChange(ScrollContentHeightPreferenceKey.self) { value in
                        contentHeight = value
                        let maxOffset = scrollViewHeight - value
                        let pinnedThreshold: CGFloat = 24
                        let pinned = value <= scrollViewHeight || scrollOffset <= maxOffset + pinnedThreshold
                        isPinnedToBottom = pinned
                        if pinned {
                            autoScrollEnabled = true
                        }
                        if autoScrollEnabled, let last = controller.entries.last {
                            DispatchQueue.main.async {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        showScrollerTemporarily()
                    }
                .overlay(alignment: .top) {
                    if scrollOffset < -6 {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.6),
                                Color.black.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 18)
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottom) {
                    if contentHeight > scrollViewHeight,
                       scrollOffset > (scrollViewHeight - contentHeight) + 6 {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.0),
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 18)
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !autoScrollEnabled, let last = controller.entries.last {
                        Button {
                            autoScrollEnabled = true
                            DispatchQueue.main.async {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        } label: {
                            Label("Jump to latest", systemImage: "arrow.down.to.line")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.55))
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { scrollViewHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, newValue in
                                scrollViewHeight = newValue
                            }
                    }
                )
            }
                }
            .padding(10)

            content
                .opacity(model.isEnabled ? 1.0 : 0.45)
                .grayscale(model.isEnabled ? 0.0 : 0.6)
                .overlay {
                    if !model.isEnabled {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.35))
                            .overlay(
                                Text("Disabled")
                                    .font(.caption)
                                    .foregroundStyle(chromeTextColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.08))
                                    )
                            )
                            .padding(6)
                    }
                }
                .allowsHitTesting(model.isEnabled)
            .onAppear {
                guard !isLANSnapshotRendering else { return }
                controller.updateSettings(model)
                controller.updateTabSnapshot(tab)
                controller.updateTranscriptionPreferences(
                    localeIdentifier: preferredTranscriptionLocaleIdentifier
                )
                controller.setLiveMode(effectiveLiveMode)
                controller.setLinkState(true)
                controller.refreshAfterViewReturn()
            }
            .onChange(of: module) { _, newValue in
                guard !isLANSnapshotRendering else { return }
                let updated = LiveTranscriptionTileView.resolveModel(module: newValue)
                controller.updateSettings(updated)
                controller.updateTabSnapshot(tab)
                controller.setLiveMode(effectiveLiveMode)
                controller.setLinkState(true)
            }
            .onChange(of: tab) { _, newValue in
                guard !isLANSnapshotRendering else { return }
                controller.updateTabSnapshot(newValue)
            }
            .onChange(of: transcriptionLocaleIdentifier) { _, _ in
                guard !isLANSnapshotRendering else { return }
                controller.updateTranscriptionPreferences(
                    localeIdentifier: preferredTranscriptionLocaleIdentifier
                )
            }
            .onChange(of: appLanguageLocaleIdentifier) { _, _ in
                guard !isLANSnapshotRendering else { return }
                controller.updateTranscriptionPreferences(
                    localeIdentifier: preferredTranscriptionLocaleIdentifier
                )
            }
            .onChange(of: isLiveMode) { _, newValue in
                guard !isLANSnapshotRendering else { return }
                let updatedLiveMode = newValue || liveModeEnabled
                controller.setLinkState(true)
                controller.setLiveMode(updatedLiveMode)
                if updatedLiveMode {
                    controller.refreshAfterViewReturn()
                }
            }
            .onChange(of: liveModeEnabled) { _, newValue in
                guard !isLANSnapshotRendering else { return }
                let updatedLiveMode = isLiveMode || newValue
                controller.setLinkState(true)
                controller.setLiveMode(updatedLiveMode)
                if updatedLiveMode {
                    controller.refreshAfterViewReturn()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard !isLANSnapshotRendering else { return }
                #if os(iOS)
                controller.setLiveMode(effectiveLiveMode && phase == .active)
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .liveTranscriptionClearRequested)) { note in
                guard let id = note.userInfo?["tileId"] as? UUID, id == tileId else { return }
                controller.clearOutputs()
            }
            .onReceive(SharedSecondTicker.shared.publisher) { date in
                guard model.usesRelativeTimestamps == true else { return }
                relativeTimestampRefreshDate = date
            }
        }
    }

    private func lanSnapshotView(model: LiveTranscriptionModuleModel) -> some View {
        let payload = LiveTranscriptionOutputStore.shared.payload(for: tile.id)
        let label = displayLabel(for: model)
        let titleFontSize = clampedTileFontSize(defaultSize: 24)
        let titleWeight = (tileTextFormatting?.fontWeight ?? .regular).swiftUIFontWeight
        let titleColor = tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
        let entries = payload.window
        let latest = payload.latestEntry
        let snapshotEntries = Array(entries.suffix(6))

        let headerView = VStack(alignment: .leading, spacing: 4) {
            Text(applyTitleCapitalization(label))
                .font(.system(size: titleFontSize, weight: titleWeight))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Image(systemName: "network")
                    .imageScale(.small)
                Text("LAN Snapshot")
            }
            .font(.caption)
            .foregroundStyle(chromeTextColor)
        }

        return VStack(alignment: .leading, spacing: 10) {
            headerView
            LazyVStack(alignment: .leading, spacing: 6) {
                if snapshotEntries.isEmpty {
                    Text("No transcript yet.")
                        .font(.caption)
                        .foregroundStyle(chromeTextColor)
                } else {
                    ForEach(snapshotEntries) { entry in
                        TranscriptRow(
                            entry: entry,
                            color: colorForSource(entry.sourceId, model: model),
                            underlineRules: underlineRules,
                            usesRelativeTimestamp: model.usesRelativeTimestamps == true,
                            relativeTimestampRefreshDate: relativeTimestampRefreshDate,
                            timestampFont: .caption,
                            timestampColor: Color.secondary.opacity(0.9)
                        )
                    }
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let latest {
                Text("Last update: \(Self.snapshotTimeFormatter.string(from: latest.timestamp))")
                    .font(.caption2)
                    .foregroundStyle(chromeTextColor)
            }
        }
        .padding(10)
        .opacity(model.isEnabled ? 1.0 : 0.45)
        .grayscale(model.isEnabled ? 0.0 : 0.6)
        .overlay {
            if !model.isEnabled {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(chromeTextColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            )
                    )
                    .padding(6)
            }
        }
    }

    private static let snapshotTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func showScrollerTemporarily() {
        scrollerHideWorkItem?.cancel()
        scrollerHideWorkItem = nil

        if scrollerAlpha < 0.45 {
            withAnimation(.easeOut(duration: 0.15)) {
                scrollerAlpha = 0.45
            }
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.35)) {
                scrollerAlpha = 0.0
            }
        }
        scrollerHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func header(model: LiveTranscriptionModuleModel) -> some View {
        let label = displayLabel(for: model)
        let sourceNames = sourceSubtitle(for: model)
        let titleFontSize = clampedTileFontSize(defaultSize: 24)
        let metadataFontSize = liveTranscriptionMetadataFontSize
        let titleWeight = (tileTextFormatting?.fontWeight ?? .regular).swiftUIFontWeight
        let titleColor = tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(applyTitleCapitalization(label))
                    .font(.system(size: titleFontSize, weight: titleWeight))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    statusBadge

                    if !sourceNames.isEmpty {
                        Text(sourceNames)
                            .font(.system(size: metadataFontSize, weight: .medium))
                            .foregroundStyle(chromeTextColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let warning = controller.inputWarning, effectiveLiveMode {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.showsDiagnostics {
                    if controller.state == .listening {
                        Text("Input level: \(String(format: "%.3f", controller.inputLevel))")
                            .font(.caption2)
                            .foregroundStyle(chromeTextColor)
                    }
                    if !controller.debugInfo.isEmpty {
                        Text(controller.debugInfo)
                            .font(.caption2)
                            .foregroundStyle(chromeTextColor)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Menu {
                Button("Export Transcript (.txt)") { exportTranscript(model: model) }
                Button("Copy Transcript") { copyTranscript(model: model) }
                Button("Clear") { controller.clearOutputs() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private func displayLabel(for model: LiveTranscriptionModuleModel) -> String {
        let label = model.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Live Transcription" : label
    }

    private func sourceSubtitle(for model: LiveTranscriptionModuleModel) -> String {
        let enabledNames = model.sources
            .filter(\.isEnabled)
            .map(\.transcriptDisplayName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let names = enabledNames.isEmpty
            ? model.sources
                .map(\.transcriptDisplayName)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            : enabledNames

        return names.joined(separator: " • ")
    }

    private func clampedTileFontSize(defaultSize: CGFloat) -> CGFloat {
        let raw = CGFloat(tileTextFormatting?.fontSize ?? Double(defaultSize))
        guard raw.isFinite else { return defaultSize }
        return min(96, max(10, raw))
    }

    private var liveTranscriptionMetadataFontSize: CGFloat {
        max(10, clampedTileFontSize(defaultSize: 24) * 0.56)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(effectiveLiveMode ? statusLabel : "Live Mode Off")
                .font(.system(size: liveTranscriptionMetadataFontSize, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(statusColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(statusColor.opacity(0.13))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(statusColor.opacity(0.24), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        guard effectiveLiveMode else { return Color.white.opacity(0.58) }
        switch controller.state {
        case .listening:
            return .green
        case .idle:
            return Color.white.opacity(0.58)
        case .permissionRequired, .microphoneBusy:
            return .orange
        case .error:
            return .red
        }
    }

    private func applyTitleCapitalization(_ string: String) -> String {
        switch tileTextFormatting?.capitalization ?? .normal {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }

    private var statusLabel: String {
        switch controller.state {
        case .idle:
            return "Idle"
        case .listening:
            return "Listening"
        case .permissionRequired:
            return "Permission required"
        case .microphoneBusy:
            return "Microphone busy"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    private func colorForSource(_ sourceId: UUID, model: LiveTranscriptionModuleModel) -> Color {
        model.sources.first(where: { $0.id == sourceId })?.color.swiftUIColor ?? Color.white
    }

    private var underlineRules: [DashboardGraph.WordTriggerRule] {
        guard let graph = tab.graph else { return [] }
        let transcriptionNodeId = groupNodeId(for: tab.id, groupKey: "moduleGroup.transcription")

        func resolvesToNodeId(_ link: GraphLink, target: UUID, graph: DashboardGraph) -> Bool {
            let resolved = graph.nodeIdByPortId[link.toPortId] ?? link.toTileId
            return resolved == target
        }

        func resolvesFromTranscriptionSource(_ link: GraphLink, graph: DashboardGraph) -> Bool {
            let resolved = graph.nodeIdByPortId[link.fromPortId] ?? link.fromTileId
            return resolved == tile.id || resolved == transcriptionNodeId
        }

        func isLinkedFromTranscription(toNodeId: UUID, graph: DashboardGraph) -> Bool {
            for link in graph.links where link.isEnabled {
                guard resolvesToNodeId(link, target: toNodeId, graph: graph) else { continue }
                if resolvesFromTranscriptionSource(link, graph: graph) {
                    return true
                }
            }
            return false
        }

        var rules: [DashboardGraph.WordTriggerRule] = []
        var hasLinkedWordTrigger = false

        for (key, cfg) in graph.wordTriggerConfigByNodeId {
            guard let nodeId = UUID(uuidString: key) else { continue }
            if isLinkedFromTranscription(toNodeId: nodeId, graph: graph) {
                hasLinkedWordTrigger = true
                rules.append(contentsOf: cfg.rules)
            } else if nodeId == transcriptionNodeId {
                rules.append(contentsOf: cfg.rules)
            }
        }

        if hasLinkedWordTrigger {
            rules = rules.filter { !$0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return rules
        }

        // Fallback: use the transcription node config if no linked word-trigger nodes are present.
        let cfg = graph.wordTriggerConfigByNodeId[transcriptionNodeId.uuidString] ?? DashboardGraph.WordTriggerConfig()
        return cfg.rules.filter { !$0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func updateModuleModel(_ model: LiveTranscriptionModuleModel) {
        if case .liveTranscription = module.kind {
            module.kind = .liveTranscription(model)
        }
    }

    private func copyTranscript(model: LiveTranscriptionModuleModel) {
        let string = LiveTranscriptionExportBuilder.build(
            entries: controller.entries,
            includeTimestamps: model.includeTimestampsInExport,
            includeSourceNames: model.includeSourceNamesInExport
        )
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    private func exportTranscript(model: LiveTranscriptionModuleModel) {
        let string = LiveTranscriptionExportBuilder.build(
            entries: controller.entries,
            includeTimestamps: model.includeTimestampsInExport,
            includeSourceNames: model.includeSourceNamesInExport
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStamp = dateFormatter.string(from: Date())
        let defaultName = "transcript-\(dateStamp).txt"

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.global(qos: .utility).async {
                try? string.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(defaultName)
        DispatchQueue.global(qos: .utility).async {
            try? string.write(to: tempURL, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                let exporter = LiveTranscriptionFileExporter(url: tempURL)
                exporter.present()
            }
        }
        #endif
    }

    private static func resolveModel(module: DashboardModuleModel) -> LiveTranscriptionModuleModel {
        if case let .liveTranscription(model) = module.kind {
            return model
        }
        return LiveTranscriptionModuleModel()
    }
}

private struct TranscriptRow: View {
    @Environment(\.tileTextFormatting) private var tileTextFormatting
    let entry: TranscriptEntry
    let color: Color
    let underlineRules: [DashboardGraph.WordTriggerRule]
    let usesRelativeTimestamp: Bool
    let relativeTimestampRefreshDate: Date
    let timestampFont: Font
    let timestampColor: Color
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            sourceMarker
                .padding(.top, metadataFontSize + 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !entry.sourceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(entry.sourceDisplayName)
                            .font(.system(size: metadataFontSize, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Text(timestampText)
                        .font(.system(size: metadataFontSize, weight: .medium))
                        .foregroundStyle(timestampColor.opacity(0.9))
                    if !entry.isFinal {
                        Text("In progress")
                            .font(.system(size: metadataFontSize * 0.92, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                let renderedText = applyCapitalization(entry.displayText)
                if underlineRules.isEmpty {
                    Text(renderedText)
                        .font(.system(size: resolvedFontSize, weight: resolvedFontWeight))
                        .foregroundStyle(tintedTranscriptTextColor)
                } else {
                    Text(attributedTranscriptText(renderedText, rules: underlineRules))
                        .font(.system(size: resolvedFontSize, weight: resolvedFontWeight))
                        .foregroundStyle(tintedTranscriptTextColor)
                }
            }
        }
    }

    init(
        entry: TranscriptEntry,
        color: Color,
        underlineRules: [DashboardGraph.WordTriggerRule],
        usesRelativeTimestamp: Bool = false,
        relativeTimestampRefreshDate: Date = Date(),
        timestampFont: Font = .caption2,
        timestampColor: Color = .secondary
    ) {
        self.entry = entry
        self.color = color
        self.underlineRules = underlineRules
        self.usesRelativeTimestamp = usesRelativeTimestamp
        self.relativeTimestampRefreshDate = relativeTimestampRefreshDate
        self.timestampFont = timestampFont
        self.timestampColor = timestampColor
    }

    private var timestampText: String {
        _ = relativeTimestampRefreshDate
        if usesRelativeTimestamp {
            return entry.timestamp.formatted(.relative(presentation: .named))
        }
        return Self.timeFormatter.string(from: entry.timestamp)
    }

    private var resolvedFontSize: CGFloat {
        let raw = CGFloat(tileTextFormatting?.fontSize ?? 24)
        guard raw.isFinite else { return 24 }
        return min(96, max(10, raw))
    }

    private var resolvedFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .regular).swiftUIFontWeight
    }

    private var resolvedTextColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
    }

    private var metadataFontSize: CGFloat {
        max(12, resolvedFontSize * 0.56)
    }

    private var sourceMarker: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
            Circle()
                .stroke(color.opacity(0.82), lineWidth: 1.5)
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
        }
        .frame(width: 14, height: 14)
    }

    private var tintedTranscriptTextColor: Color {
        let base = CodableColor(resolvedTextColor)
        let tint = CodableColor(color)
        let tintAmount = 0.10
        let baseAmount = 1.0 - tintAmount
        return Color(
            .sRGB,
            red: (base.red * baseAmount) + (tint.red * tintAmount),
            green: (base.green * baseAmount) + (tint.green * tintAmount),
            blue: (base.blue * baseAmount) + (tint.blue * tintAmount),
            opacity: base.alpha
        )
    }

    private func applyCapitalization(_ string: String) -> String {
        switch tileTextFormatting?.capitalization ?? .normal {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }
}

private func attributedTranscriptText(_ text: String, rules: [DashboardGraph.WordTriggerRule]) -> AttributedString {
    var output = AttributedString(text)
    for rule in rules {
        let phrase = rule.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { continue }

        let base = text.lowercased()
        let needle = phrase.lowercased()

        switch rule.matchMode {
        case .contains:
            var searchStart = base.startIndex
            while let range = base.range(of: needle, range: searchStart..<base.endIndex) {
                let nsRange = NSRange(range, in: base)
                if let attrRange = Range(nsRange, in: output) {
                    output[attrRange].underlineStyle = .single
                }
                searchStart = range.upperBound
            }
        case .wholeWord:
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
            underlineMatches(pattern: pattern, in: base, output: &output)
        }
    }
    return output
}

private func underlineMatches(pattern: String, in haystack: String, output: inout AttributedString) {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
    let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
    regex.enumerateMatches(in: haystack, options: [], range: range) { match, _, _ in
        guard let matchRange = match?.range, let attrRange = Range(matchRange, in: output) else { return }
        output[attrRange].underlineStyle = .single
    }
}

private func groupNodeId(for tabId: UUID, groupKey: String) -> UUID {
    let data = Data((tabId.uuidString + "|" + groupKey).utf8)
    let digest = SHA256.hash(data: data)
    let byteArray = Array(digest.prefix(16))
    var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    withUnsafeMutableBytes(of: &uuidBytes) { buf in
        buf.copyBytes(from: byteArray)
    }
    return UUID(uuid: uuidBytes)
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if os(macOS)
private struct ScrollViewConfigurator: NSViewRepresentable {
    @Binding var scrollerAlpha: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scroll = view.enclosingScrollView {
                configure(scroll)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scroll = nsView.enclosingScrollView {
                configure(scroll)
            }
        }
    }

    private func configure(_ scroll: NSScrollView) {
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .overlay
        scroll.verticalScroller?.alphaValue = scrollerAlpha
        scroll.verticalScroller?.isHidden = scrollerAlpha <= 0.01
    }
}
#endif

private struct LiveTranscriptionSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LiveTranscriptionModuleModel
    let onSave: (LiveTranscriptionModuleModel) -> Void

    init(model: LiveTranscriptionModuleModel, onSave: @escaping (LiveTranscriptionModuleModel) -> Void) {
        _draft = State(initialValue: model)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sources") {
                    ForEach($draft.sources) { $source in
                        HStack {
                            Toggle(source.transcriptDisplayName, isOn: $source.isEnabled)
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: { source.color.swiftUIColor },
                                set: { source.color = CodableColor($0) }
                            ))
                            .labelsHidden()
                            .frame(width: 28)
                        }
                    }
                }

                Section("Retention") {
                    Toggle("Limit transcript history", isOn: LiveTranscriptionRetentionBindings.limitsEnabled(
                        get: { draft.retention.limitsEnabled },
                        set: { draft.retention.limitsEnabled = $0 }
                    ))

                    if draft.retention.limitsEnabled == true {
                        Stepper("Max minutes: \(draft.retention.maxMinutes ?? 0)", value: LiveTranscriptionRetentionBindings.maxMinutes(
                            get: { draft.retention.maxMinutes },
                            set: { draft.retention.maxMinutes = $0 }
                        ), in: 0...120)

                        Stepper("Max entries: \(draft.retention.maxEntries ?? 0)", value: LiveTranscriptionRetentionBindings.maxEntries(
                            get: { draft.retention.maxEntries },
                            set: { draft.retention.maxEntries = $0 }
                        ), in: 0...2000)
                    }
                }

                Section("Display") {
                    Toggle("Relative timestamps", isOn: LiveTranscriptionRetentionBindings.relativeTimestamps(
                        get: { draft.usesRelativeTimestamps },
                        set: { draft.usesRelativeTimestamps = $0 }
                    ))
                }
            }
            .navigationTitle("Transcription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}


#if os(iOS)
private final class LiveTranscriptionFileExporter: NSObject, UIDocumentPickerDelegate {
    private let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    func present() {
        let picker = UIDocumentPickerViewController(forExporting: [url])
        picker.delegate = self
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.rootViewController?
            .present(picker, animated: true)
    }
}
#endif

private enum LiveTranscriptionExportBuilder {
    static func build(entries: [TranscriptEntry], includeTimestamps: Bool, includeSourceNames: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        return entries.map { entry in
            var parts: [String] = []
            if includeTimestamps {
                parts.append("[\(formatter.string(from: entry.timestamp))]")
            }
            if includeSourceNames {
                parts.append("\(entry.sourceDisplayName):")
            }
            parts.append(entry.displayText)
            return parts.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

// MARK: - Plugin Glue

enum LiveTranscriptionModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .liveTranscription(LiveTranscriptionModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        AnyView(LiveTranscriptionTileView(tab: tab, tile: tile, module: module, isLiveMode: isLiveMode))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }
}
