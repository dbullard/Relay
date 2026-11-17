import Foundation

/// Where a source's speech recognition runs.
nonisolated enum TranscriptionEngineHost: Equatable, Hashable, Sendable {
    /// Inside the Relay process.
    case inProcess
    /// Inside one of the TranscriptionHelper XPC services (0-based).
    case helper(Int)

    /// Each helper is its own XPC service bundle, so each runs in its own process.
    /// Their bundle IDs must match the TranscriptionHelper targets in the project.
    static let helperServiceNames = [
        "app.relay.Relay.TranscriptionHelper",
        "app.relay.Relay.TranscriptionHelper2",
        "app.relay.Relay.TranscriptionHelper3",
    ]

    var helperServiceName: String? {
        guard case .helper(let index) = self, Self.helperServiceNames.indices.contains(index) else { return nil }
        return Self.helperServiceNames[index]
    }
}

nonisolated enum TranscriptionSlotAssignment: Equatable, Sendable {
    case host(TranscriptionEngineHost)
    /// The source's audio device is not connected, so it takes no recognizer slot.
    case deviceMissing
    /// Every recognizer slot is taken by an earlier source.
    case overCapacity
}

/// Hands out speech-recognizer slots to a dashboard's enabled sources.
///
/// The Speech framework runs one recognition task per process. A second concurrent
/// task in the same process (on-device or server) makes both fail with
/// kAFAssistantErrorDomain 1110 "No speech detected", even if one of them gets no
/// audio at all. So every transcribing source needs a process of its own: the app,
/// or one of the TranscriptionHelper XPC services.
///
/// Slots are handed out in dashboard order. Sources whose device is missing are
/// skipped so they can't block a source that has audio.
nonisolated enum TranscriptionSlotPlanner {
    static let hosts: [TranscriptionEngineHost] =
        [.inProcess] + TranscriptionEngineHost.helperServiceNames.indices.map { .helper($0) }

    static var capacity: Int { hosts.count }

    static func plan(
        orderedSourceIDs: [UUID],
        isDeviceAvailable: (UUID) -> Bool
    ) -> [UUID: TranscriptionSlotAssignment] {
        var assignments: [UUID: TranscriptionSlotAssignment] = [:]
        var freeHosts = hosts[...]
        for id in orderedSourceIDs where assignments[id] == nil {
            if !isDeviceAvailable(id) {
                assignments[id] = .deviceMissing
            } else if let host = freeHosts.popFirst() {
                assignments[id] = .host(host)
            } else {
                assignments[id] = .overCapacity
            }
        }
        return assignments
    }

    /// The tile warning for a source that was not given a slot, or nil if it was.
    static func warning(for assignment: TranscriptionSlotAssignment, sourceName: String) -> String? {
        switch assignment {
        case .host:
            return nil
        case .deviceMissing:
            return "\(sourceName): audio device not found."
        case .overCapacity:
            return "\(sourceName): not transcribing. Relay can transcribe \(capacity) inputs at once."
        }
    }
}

/// Separates speech from background noise for one input by tracking its noise floor.
///
/// The floor falls quickly toward quieter levels and creeps up slowly otherwise, so it
/// settles on the input's quiet level -- a laptop mic in a noisy room and a quiet
/// Dante line calibrate themselves. Speech is anything well above that floor.
///
/// Digital silence (all-zero buffers from device warm-up or resampler priming) is
/// ignored: one of those used to drop the floor to zero, after which ordinary room
/// noise counted as speech.
nonisolated struct VoiceActivityDetector: Sendable {
    /// How far above the noise floor counts as speech (4x RMS is about 12 dB).
    var ratio: Double = 4
    /// Below this RMS nothing counts as speech, however quiet the floor (about -54 dBFS).
    var absoluteMinimum: Double = 0.002
    /// Seconds for the floor to double while the level stays above it.
    var riseDoublingTime: TimeInterval = 10
    /// Seconds for the floor to close most (about 63%) of the gap to a quieter level,
    /// measured in log terms, so a single quiet buffer barely moves it.
    var fallTimeConstant: TimeInterval = 0.5
    /// Levels below this are digital silence, not a real input's noise.
    var digitalSilence: Double = 1e-5
    /// For this long after the first audio the floor follows rises as fast as falls,
    /// so a quiet warm-up buffer can't leave it far below the real room level.
    var calibrationTime: TimeInterval = 2

    private(set) var noiseFloor: Double?
    private var calibratedFor: TimeInterval = 0

    /// - Parameters:
    ///   - rms: the buffer's RMS before any gain is applied.
    ///   - duration: the buffer's length in seconds.
    mutating func isVoice(rms: Double, duration: TimeInterval) -> Bool {
        guard rms.isFinite, rms >= digitalSilence, duration > 0 else { return false }
        guard let floor = noiseFloor else {
            noiseFloor = rms
            return false
        }
        let voice = rms >= max(absoluteMinimum, floor * ratio)
        let calibrating = calibratedFor < calibrationTime
        calibratedFor += duration
        if rms <= floor || calibrating {
            // Geometric step toward the new level.
            let step = 1 - exp(-duration / fallTimeConstant)
            noiseFloor = floor * pow(rms / floor, step)
        } else {
            let grown = floor * pow(2, duration / riseDoublingTime)
            noiseFloor = min(rms, grown)
        }
        return voice
    }
}

/// Decides when a transcriber should be restarted because it isn't answering.
///
/// Only unanswered *speech* counts. Restarting during silence gains nothing, and a
/// restart that lands just as someone starts talking drops their first words. A
/// healthy recognizer answers within a second or two of speech, so several seconds
/// of speech with no result means it's stuck.
nonisolated struct TranscriptionStallTracker: Sendable {
    /// Seconds of speech, since the last result or restart, that go unanswered before a restart.
    var unansweredSpeechLimit: TimeInterval = 4
    /// Speech evidence older than this (no speech since) is dropped, so a stray noise
    /// burst now and then never adds up to a restart.
    var speechExpiry: TimeInterval = 8
    /// No restart unless audio is still arriving.
    var audioFreshness: TimeInterval = 1.5

    private(set) var unansweredSpeech: TimeInterval = 0
    private(set) var lastSpeechAt: Date?
    private(set) var lastAudioAt: Date?

    mutating func noteAudio(at time: Date, duration: TimeInterval, isVoice: Bool) {
        lastAudioAt = time
        guard isVoice else { return }
        if let lastSpeechAt, time.timeIntervalSince(lastSpeechAt) > speechExpiry {
            unansweredSpeech = 0
        }
        unansweredSpeech += max(0, duration)
        lastSpeechAt = time
    }

    /// The transcriber returned text, or was restarted.
    mutating func reset() {
        unansweredSpeech = 0
        lastSpeechAt = nil
    }

    func shouldRestart(now: Date) -> Bool {
        guard let lastAudioAt, now.timeIntervalSince(lastAudioAt) <= audioFreshness else { return false }
        guard let lastSpeechAt, now.timeIntervalSince(lastSpeechAt) <= speechExpiry else { return false }
        return unansweredSpeech >= unansweredSpeechLimit
    }
}
