import XCTest
@testable import Relay

final class TranscriptionSlotPlannerTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    func testEachSourceGetsItsOwnProcess() {
        let plan = TranscriptionSlotPlanner.plan(orderedSourceIDs: [a, b, c, d]) { _ in true }
        XCTAssertEqual(plan[a], .host(.inProcess))
        XCTAssertEqual(plan[b], .host(.helper(0)))
        XCTAssertEqual(plan[c], .host(.helper(1)))
        XCTAssertEqual(plan[d], .host(.helper(2)))
    }

    func testCapacityMatchesTheDashboardInputCap() {
        XCTAssertEqual(TranscriptionSlotPlanner.capacity, 4)
    }

    func testSourcesBeyondCapacityDoNotShareAHost() {
        let plan = TranscriptionSlotPlanner.plan(orderedSourceIDs: [a, b, c, d, e]) { _ in true }
        XCTAssertEqual(plan[e], .overCapacity)
    }

    /// The field failure: two Dante inputs with no Dante device, then the built-in mic.
    /// The mic must get a slot of its own instead of sharing a process with a dead input.
    func testMissingDevicesTakeNoSlot() {
        let plan = TranscriptionSlotPlanner.plan(orderedSourceIDs: [a, b, c]) { $0 == c }
        XCTAssertEqual(plan[a], .deviceMissing)
        XCTAssertEqual(plan[b], .deviceMissing)
        XCTAssertEqual(plan[c], .host(.inProcess))
    }

    func testMissingDeviceInTheMiddleIsSkipped() {
        let plan = TranscriptionSlotPlanner.plan(orderedSourceIDs: [a, b, c]) { $0 != b }
        XCTAssertEqual(plan[a], .host(.inProcess))
        XCTAssertEqual(plan[b], .deviceMissing)
        XCTAssertEqual(plan[c], .host(.helper(0)))
    }

    /// A device arriving later moves later sources along, which is why the tile restarts.
    func testDeviceArrivingChangesThePlan() {
        let before = TranscriptionSlotPlanner.plan(orderedSourceIDs: [a, b, c]) { $0 == c }
        let after = TranscriptionSlotPlanner.plan(orderedSourceIDs: [a, b, c]) { _ in true }
        XCTAssertEqual(before[c], .host(.inProcess))
        XCTAssertEqual(after[a], .host(.inProcess))
        XCTAssertEqual(after[c], .host(.helper(1)))
    }

    func testNoHostIsHandedOutTwice() {
        let ids = (0..<8).map { _ in UUID() }
        let plan = TranscriptionSlotPlanner.plan(orderedSourceIDs: ids) { _ in true }
        let hosts = plan.values.compactMap { assignment -> TranscriptionEngineHost? in
            if case .host(let host) = assignment { return host }
            return nil
        }
        XCTAssertEqual(hosts.count, TranscriptionSlotPlanner.capacity)
        XCTAssertEqual(Set(hosts).count, hosts.count)
    }

    func testEveryHelperHasADistinctService() {
        let names = TranscriptionSlotPlanner.hosts.compactMap(\.helperServiceName)
        XCTAssertEqual(names.count, TranscriptionSlotPlanner.capacity - 1)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertNil(TranscriptionEngineHost.inProcess.helperServiceName)
        XCTAssertEqual(names.first, "app.relay.Relay.TranscriptionHelper")
    }

    func testWarnings() {
        XCTAssertNil(TranscriptionSlotPlanner.warning(for: .host(.helper(0)), sourceName: "MD"))
        XCTAssertEqual(TranscriptionSlotPlanner.warning(for: .deviceMissing, sourceName: "MD"), "MD: audio device not found.")
        XCTAssertEqual(
            TranscriptionSlotPlanner.warning(for: .overCapacity, sourceName: "COMMS"),
            "COMMS: not transcribing. Relay can transcribe 4 inputs at once."
        )
    }
}

final class VoiceActivityDetectorTests: XCTestCase {
    /// Feeds `seconds` of 0.1 s buffers at `rms` and returns how many counted as voice.
    private func feed(_ detector: inout VoiceActivityDetector, rms: Double, seconds: Double) -> Int {
        (0..<Int(seconds * 10)).filter { _ in detector.isVoice(rms: rms, duration: 0.1) }.count
    }

    /// Regression: a fixed threshold took this room's background noise for speech.
    func testSteadyRoomNoiseIsNotVoice() {
        var detector = VoiceActivityDetector()
        _ = feed(&detector, rms: 0.012, seconds: 5)
        XCTAssertEqual(feed(&detector, rms: 0.012, seconds: 60), 0)
    }

    func testSpeechAboveTheRoomIsVoice() {
        var detector = VoiceActivityDetector()
        _ = feed(&detector, rms: 0.012, seconds: 5)
        XCTAssertEqual(feed(&detector, rms: 0.08, seconds: 2), 20)
    }

    func testFloorFallsToAQuieterRoom() {
        var detector = VoiceActivityDetector()
        _ = feed(&detector, rms: 0.05, seconds: 1)
        _ = feed(&detector, rms: 0.004, seconds: 3)
        XCTAssertEqual(detector.noiseFloor ?? -1, 0.004, accuracy: 0.0002)
        XCTAssertGreaterThan(feed(&detector, rms: 0.03, seconds: 1), 0)
    }

    /// Regression (live run 13:30): all-zero buffers from mic warm-up sank the floor to
    /// 0.0000, and then room noise counted as speech, restarting every 4.5 s.
    func testZeroBuffersDoNotSinkTheFloor() {
        var detector = VoiceActivityDetector()
        _ = feed(&detector, rms: 0, seconds: 0.5)
        _ = feed(&detector, rms: 0.012, seconds: 3)
        for _ in 0..<20 {
            _ = feed(&detector, rms: 0, seconds: 0.2)
            XCTAssertEqual(feed(&detector, rms: 0.012, seconds: 3), 0)
        }
        XCTAssertEqual(detector.noiseFloor ?? -1, 0.012, accuracy: 0.001)
    }

    /// Regression (live run 13:30): a near-silent warm-up buffer first left the floor
    /// far below the room, and the slow rise took a minute to catch up.
    func testQuietWarmUpDoesNotLeaveTheFloorLow() {
        var detector = VoiceActivityDetector()
        _ = feed(&detector, rms: 0.00003, seconds: 0.3)
        _ = feed(&detector, rms: 0.012, seconds: 2)
        XCTAssertEqual(feed(&detector, rms: 0.012, seconds: 10), 0)
    }

    func testOneQuietBufferBarelyMovesTheFloor() {
        var detector = VoiceActivityDetector()
        _ = feed(&detector, rms: 0.012, seconds: 3)
        _ = detector.isVoice(rms: 0.0001, duration: 0.1)
        XCTAssertGreaterThan(detector.noiseFloor ?? 0, 0.005)
        XCTAssertEqual(feed(&detector, rms: 0.012, seconds: 3), 0)
    }

    func testEmptyBuffersAreIgnored() {
        var detector = VoiceActivityDetector()
        XCTAssertFalse(detector.isVoice(rms: 0.5, duration: 0))
        XCTAssertNil(detector.noiseFloor)
    }

    func testFloorRisesSlowlyToALouderRoom() {
        var detector = VoiceActivityDetector()
        _ = feed(&detector, rms: 0.003, seconds: 2)
        // The room gets louder (air handling starts). It reads as voice at first...
        XCTAssertGreaterThan(feed(&detector, rms: 0.02, seconds: 2), 0)
        // ...then the floor catches up and it stops.
        _ = feed(&detector, rms: 0.02, seconds: 40)
        XCTAssertEqual(feed(&detector, rms: 0.02, seconds: 10), 0)
    }

    /// A near-silent digital line (Dante with nothing on it) never reads as voice.
    func testDigitalSilenceIsNotVoice() {
        var detector = VoiceActivityDetector()
        XCTAssertEqual(feed(&detector, rms: 0, seconds: 5), 0)
        XCTAssertEqual(feed(&detector, rms: 0.001, seconds: 1), 0)
        XCTAssertGreaterThan(feed(&detector, rms: 0.05, seconds: 1), 0)
    }

    func testRejectsNonFiniteLevels() {
        var detector = VoiceActivityDetector()
        _ = detector.isVoice(rms: 0.01, duration: 0.1)
        XCTAssertFalse(detector.isVoice(rms: .nan, duration: 0.1))
        XCTAssertEqual(detector.noiseFloor ?? -1, 0.01, accuracy: 1e-9)
    }
}

final class TranscriptionStallTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    /// Feeds 0.1 s buffers from `from` to `to` seconds after `start`.
    private func feed(_ tracker: inout TranscriptionStallTracker, from: Double, to: Double, voice: Bool) {
        var t = from
        while t < to - 1e-9 {
            tracker.noteAudio(at: start.addingTimeInterval(t), duration: 0.1, isVoice: voice)
            t += 0.1
        }
    }

    private func at(_ offset: Double) -> Date { start.addingTimeInterval(offset) }

    /// Regression: silence used to trigger a restart every 8 s.
    func testNeverRestartsDuringSilence() {
        var tracker = TranscriptionStallTracker()
        feed(&tracker, from: 0, to: 120, voice: false)
        XCTAssertFalse(tracker.shouldRestart(now: at(120)))
    }

    func testRestartsAfterUnansweredSpeech() {
        var tracker = TranscriptionStallTracker()
        feed(&tracker, from: 0, to: 3.9, voice: true)
        XCTAssertFalse(tracker.shouldRestart(now: at(3.9)))
        feed(&tracker, from: 3.9, to: 4.1, voice: true)
        XCTAssertTrue(tracker.shouldRestart(now: at(4.1)))
    }

    func testResultsKeepItRunning() {
        var tracker = TranscriptionStallTracker()
        for second in 0..<30 {
            feed(&tracker, from: Double(second), to: Double(second) + 1, voice: true)
            tracker.reset()  // a partial arrives every second
            XCTAssertFalse(tracker.shouldRestart(now: at(Double(second) + 1)))
        }
    }

    /// Stray noise bursts spread over minutes never add up to a restart.
    func testOccasionalBurstsExpire() {
        var tracker = TranscriptionStallTracker()
        for burst in 0..<20 {
            let t = Double(burst) * 10
            feed(&tracker, from: t, to: t + 0.5, voice: true)
            feed(&tracker, from: t + 0.5, to: t + 10, voice: false)
        }
        XCTAssertFalse(tracker.shouldRestart(now: at(200)))
    }

    func testNoRestartWithoutFreshAudio() {
        var tracker = TranscriptionStallTracker()
        feed(&tracker, from: 0, to: 5, voice: true)
        XCTAssertFalse(tracker.shouldRestart(now: at(7)))
    }

    func testRestartResetsTheCount() {
        var tracker = TranscriptionStallTracker()
        feed(&tracker, from: 0, to: 5, voice: true)
        XCTAssertTrue(tracker.shouldRestart(now: at(5)))
        tracker.reset()
        XCTAssertFalse(tracker.shouldRestart(now: at(5)))
    }
}
