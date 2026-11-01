import XCTest
import Combine
@testable import Relay

final class ShureWirelessTelemetryTests: XCTestCase {

    func testCompactSampleFrameParsesRfAndAudioLevels() {
        let parsed = ShureSampleFrameTelemetryParser.parseCompactSamplePayload(
            from: "SAMPLE 1 ALL XX 034 000"
        )

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.rfLevel, 34)
        XCTAssertEqual(parsed?.audioLevel, 0)
    }

    func testExtendedSampleFrameParsesRfAndAudioLevels() {
        let parsed = ShureSampleFrameTelemetryParser.parseCompactSamplePayload(
            from: "SAMPLE 1 ALL 255 000 005 033 XX 00 019 00 018"
        )

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.rfLevel, 33)
        XCTAssertEqual(parsed?.audioLevel, 19)
    }

    func testAxientSampleFrameUsesMeterFieldsInsteadOfTrailingRssiBytes() {
        let parsed = ShureAxientSampleFrameTelemetryParser.parse(
            from: "SAMPLE 2 ALL 255 003 005 033 XX 00 016 00 021"
        )

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.channelQuality, 255)
        XCTAssertEqual(parsed?.audioBitmap, 3)
        XCTAssertEqual(parsed?.audioPeakLevel, 5)
        XCTAssertEqual(parsed?.audioRmsLevel, 33)
    }

    func testAxientSampleFrameParsesZeroBitmapWithoutTreatingRssiAsAudio() {
        let parsed = ShureAxientSampleFrameTelemetryParser.parse(
            from: "SAMPLE 2 ALL 255 000 005 033 XX 00 016 00 021"
        )

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.audioBitmap, 0)
        XCTAssertEqual(parsed?.audioRmsLevel, 33)
    }

    func testRecentFalsePresenceWinsOverOlderTruePresence() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let resolved = ShureReceiverPresenceResolver.resolveNonAxientState(
            rfBarCount: 3,
            recentFalseAt: now.addingTimeInterval(-0.2),
            recentTrueAt: now.addingTimeInterval(-0.1),
            rfUpdatedRecently: true
        )

        XCTAssertEqual(resolved, .off)
    }

    func testRecentTruePresenceStillResolvesOnWithoutFalseEvidence() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let resolved = ShureReceiverPresenceResolver.resolveNonAxientState(
            rfBarCount: 3,
            recentFalseAt: nil,
            recentTrueAt: now.addingTimeInterval(-0.1),
            rfUpdatedRecently: true
        )

        XCTAssertEqual(resolved, .on)
    }

    func testAxientZeroBitmapClearsStoredMeterLevel() {
        // The receiver's own LED bitmap saying "no audio" should actively
        // zero the meter, not just leave a stale nonzero reading in place.
        let disposition = ShureAxientAudioDispositionResolver.resolve(
            keyUpper: "AUDIO_LED_BITMAP",
            level: 0,
            shouldAccept: true,
            bitmapAllowsLevel: false
        )

        XCTAssertEqual(disposition.acceptedLevel, 0)
        XCTAssertTrue(disposition.shouldClearStoredLevel)
    }

    func testAxientRmsIsBlockedWhenBitmapBlocksSignal() {
        // Real AD4Q hardware reports a nonzero RMS noise floor even on a
        // channel with no transmitter present; AUDIO_LED_BITMAP is the
        // receiver's own gate on whether that numeric reading is real, so
        // RMS must defer to it rather than being accepted regardless.
        let disposition = ShureAxientAudioDispositionResolver.resolve(
            keyUpper: "AUDIO_LEVEL_RMS",
            level: 5.5,
            shouldAccept: true,
            bitmapAllowsLevel: false
        )

        XCTAssertNil(disposition.acceptedLevel)
        XCTAssertTrue(disposition.shouldClearStoredLevel)
    }

    func testAxientRmsStaysBlockedWhileBitmapZero() {
        let disposition = ShureAxientAudioDispositionResolver.resolve(
            keyUpper: "AUDIO_LEVEL_RMS",
            level: 12.7,
            shouldAccept: true,
            bitmapAllowsLevel: false
        )

        XCTAssertNil(disposition.acceptedLevel)
        XCTAssertTrue(disposition.shouldClearStoredLevel)
    }

    func testAxientRmsIsAcceptedWhenBitmapAllowsSignal() {
        let disposition = ShureAxientAudioDispositionResolver.resolve(
            keyUpper: "AUDIO_LEVEL_RMS",
            level: 12.7,
            shouldAccept: true,
            bitmapAllowsLevel: true
        )

        XCTAssertEqual(disposition.acceptedLevel, 12.7)
        XCTAssertFalse(disposition.shouldClearStoredLevel)
    }

    func testSilenceWatchdogFlagsConnectionWithNoTrafficSinceReady() {
        let readyAt = Date(timeIntervalSinceReferenceDate: 10_000)
        XCTAssertFalse(ShureConnectionSilenceWatchdog.isSilent(
            connectionReadyAt: readyAt, lastHeardAt: nil, now: readyAt.addingTimeInterval(10)))
        XCTAssertTrue(ShureConnectionSilenceWatchdog.isSilent(
            connectionReadyAt: readyAt, lastHeardAt: nil, now: readyAt.addingTimeInterval(16)))
    }

    func testSilenceWatchdogMeasuresFromLastFrameAfterTrafficStops() {
        let readyAt = Date(timeIntervalSinceReferenceDate: 10_000)
        let lastHeard = readyAt.addingTimeInterval(60)
        XCTAssertFalse(ShureConnectionSilenceWatchdog.isSilent(
            connectionReadyAt: readyAt, lastHeardAt: lastHeard, now: lastHeard.addingTimeInterval(10)))
        XCTAssertTrue(ShureConnectionSilenceWatchdog.isSilent(
            connectionReadyAt: readyAt, lastHeardAt: lastHeard, now: lastHeard.addingTimeInterval(16)))
    }

    func testSilenceWatchdogIgnoresStaleHeardTimeFromPreviousConnection() {
        let readyAt = Date(timeIntervalSinceReferenceDate: 10_000)
        let oldHeard = readyAt.addingTimeInterval(-300)
        XCTAssertFalse(ShureConnectionSilenceWatchdog.isSilent(
            connectionReadyAt: readyAt, lastHeardAt: oldHeard, now: readyAt.addingTimeInterval(5)))
    }

    func testAxientRecentPositiveEvidenceWinsOverBriefFalseFrames() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let resolved = ShureAxientPresenceResolver.resolve(
            recentPositiveEvidenceAt: now.addingTimeInterval(-4),
            recentNegativeEvidenceAt: now.addingTimeInterval(-0.2),
            now: now
        )

        XCTAssertEqual(resolved, .on)
    }

    func testAxientFallsOffWhenPositiveEvidenceExpires() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let resolved = ShureAxientPresenceResolver.resolve(
            recentPositiveEvidenceAt: now.addingTimeInterval(-20),
            recentNegativeEvidenceAt: now.addingTimeInterval(-0.2),
            now: now
        )

        XCTAssertEqual(resolved, .off)
    }

    func testAxientSustainedNegativeEvidenceOverridesInProgressPositiveHold() {
        // Reconstructed from a real customer field log: last positive
        // TX_DEVICE_ID reply 1s before the mic was powered off, then
        // continuous negative evidence (empty TX_DEVICE_ID, CHAN_QUALITY
        // 255) every second after. Positive evidence's 12s hold was still
        // in progress the whole time, resolving .on throughout, while RF
        // had already collapsed to 0 -- Overview showed "Critical" instead
        // of "Off" for most of that window.
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let resolved = ShureAxientPresenceResolver.resolve(
            recentPositiveEvidenceAt: now.addingTimeInterval(-3.5),
            recentNegativeEvidenceAt: now.addingTimeInterval(-0.2),
            negativeEvidenceStreakStartAt: now.addingTimeInterval(-2.5),
            now: now
        )

        XCTAssertEqual(resolved, .off)
    }

    func testAxientBriefNegativeStreakStillDoesNotOverridePositiveHold() {
        // Same shape as the sustained case, but the negative streak just
        // started (0.3s old) -- still within the "could be a blip" window,
        // shouldn't flip yet.
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let resolved = ShureAxientPresenceResolver.resolve(
            recentPositiveEvidenceAt: now.addingTimeInterval(-3.5),
            recentNegativeEvidenceAt: now.addingTimeInterval(-0.2),
            negativeEvidenceStreakStartAt: now.addingTimeInterval(-0.3),
            now: now
        )

        XCTAssertEqual(resolved, .on)
    }

    func testAxientSustainedNegativeStreakButStaleLatestSampleDoesNotOverride() {
        // The streak started long enough ago, but the most recent negative
        // sample itself is stale (past the 1.5s freshness window) -- e.g.
        // positive evidence came back moments ago and just hasn't cleared
        // the streak-start bookkeeping yet. Freshness of the latest sample
        // still gates the override.
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let resolved = ShureAxientPresenceResolver.resolve(
            recentPositiveEvidenceAt: now.addingTimeInterval(-3.5),
            recentNegativeEvidenceAt: now.addingTimeInterval(-3.0),
            negativeEvidenceStreakStartAt: now.addingTimeInterval(-5.0),
            now: now
        )

        XCTAssertEqual(resolved, .on)
    }

    func testRfBarHoldAcceptsRiseImmediately() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let previous = ShureAxientRfBarHoldState(acceptedValue: 2, candidateValue: nil, candidateSince: nil)
        let resolved = ShureAxientRfBarHoldResolver.resolve(rawBars: 4, previousState: previous, now: now)

        XCTAssertEqual(resolved.acceptedValue, 4)
        XCTAssertNil(resolved.candidateValue)
    }

    func testRfBarHoldWithholdsDropUntilItPersists() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let previous = ShureAxientRfBarHoldState(acceptedValue: 4, candidateValue: nil, candidateSince: nil)

        // First low sample: candidate opens, but the accepted (displayed)
        // value must not drop yet.
        let firstDrop = ShureAxientRfBarHoldResolver.resolve(rawBars: 1, previousState: previous, now: now)
        XCTAssertEqual(firstDrop.acceptedValue, 4)
        XCTAssertEqual(firstDrop.candidateValue, 1)

        // Same low sample again, but still within the hold window.
        let stillHolding = ShureAxientRfBarHoldResolver.resolve(
            rawBars: 1,
            previousState: firstDrop,
            now: now.addingTimeInterval(0.5)
        )
        XCTAssertEqual(stillHolding.acceptedValue, 4)

        // Same low sample, now past the hold window -- the drop is accepted.
        let afterHold = ShureAxientRfBarHoldResolver.resolve(
            rawBars: 1,
            previousState: firstDrop,
            now: now.addingTimeInterval(1.6)
        )
        XCTAssertEqual(afterHold.acceptedValue, 1)
        XCTAssertNil(afterHold.candidateValue)
    }

    func testRfBarHoldResetsCandidateWhenDropValueChanges() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let previous = ShureAxientRfBarHoldState(acceptedValue: 4, candidateValue: 1, candidateSince: now)

        // A different (still-lower) candidate value restarts the hold clock
        // rather than accumulating time toward the old candidate's window.
        let resolved = ShureAxientRfBarHoldResolver.resolve(
            rawBars: 2,
            previousState: previous,
            now: now.addingTimeInterval(1.4)
        )

        XCTAssertEqual(resolved.acceptedValue, 4)
        XCTAssertEqual(resolved.candidateValue, 2)
    }

    // The following bit patterns are taken directly from Shure's Axient
    // Digital and ANX4 command-string references (identical wording in
    // both): "00 = b000000 = All LEDs off ... 31 = b011111 = LEDs 1-5 ON
    // ... 32 = b100000 = LED6 ON (top, OL, all others OFF) ... 63 =
    // b111111 = All LEDs on". These prove the parsing matches the
    // documented spec even without hardware capable of triggering a real
    // overload condition.

    func testRssiLedBitmapDecodesAllOff() {
        let decoded = ShureRssiLedBitmapDecoder.decode(0)
        XCTAssertEqual(decoded, ShureRssiLedBitmapDecoded(bars: 0, isOverload: false))
    }

    func testRssiLedBitmapDecodesLaddersOneThroughFiveWithoutOverload() {
        // 1 = b000001, 3 = b000011, 7 = b000111, 15 = b001111, 31 = b011111
        let raws = [1, 3, 7, 15, 31]
        let expectedBars = [1, 2, 3, 4, 5]
        for (raw, expected) in zip(raws, expectedBars) {
            let decoded = ShureRssiLedBitmapDecoder.decode(raw)
            XCTAssertEqual(decoded.bars, expected, "raw=\(raw)")
            XCTAssertFalse(decoded.isOverload, "raw=\(raw)")
        }
    }

    func testRssiLedBitmapDecodesOverloadAloneWithLaddersOff() {
        // 32 = b100000 = LED6 ON (top, OL), all others OFF -- confirms
        // overload is an independent flag, not just "6 bars."
        let decoded = ShureRssiLedBitmapDecoder.decode(32)
        XCTAssertEqual(decoded, ShureRssiLedBitmapDecoded(bars: 0, isOverload: true))
    }

    func testRssiLedBitmapDecodesAllOnIncludingOverload() {
        let decoded = ShureRssiLedBitmapDecoder.decode(63)
        XCTAssertEqual(decoded, ShureRssiLedBitmapDecoded(bars: 5, isOverload: true))
    }

    func testRssiLedBitmapIgnoresBitsAboveTheDocumentedSixBitRegister() {
        // Real device replies never set bits beyond 5, but the decoder
        // should not treat stray high bits as anything meaningful.
        let decoded = ShureRssiLedBitmapDecoder.decode(0xFF)
        XCTAssertEqual(decoded, ShureRssiLedBitmapDecoded(bars: 5, isOverload: true))
    }

    func testMicAudioBucketMapsFullScaleToAllLevelSegments() {
        let bucket = ShureOverviewAudioBucket.bucket(level: 20, isMuted: false, kind: .mic)
        XCTAssertEqual(bucket, ShureOverviewAudioBucket.levelSegmentCount)
        XCTAssertEqual(ShureOverviewAudioBucket.segmentCount, 10)
    }

    func testMicAudioBucketIsZeroAtOrBelowFloor() {
        // 10 on the 0-20 scale is -60 dBFS for Axient: the meter floor.
        XCTAssertEqual(ShureOverviewAudioBucket.bucket(level: 10, isMuted: false, kind: .mic), 0)
        XCTAssertEqual(ShureOverviewAudioBucket.bucket(level: 3, isMuted: false, kind: .mic), 0)
    }

    func testMicAudioBucketMapsMidpointOfWindowToHalfTheSegments() {
        // 15 = -30 dBFS, halfway through the -60..0 window (9 * 0.5 rounds to 5).
        XCTAssertEqual(ShureOverviewAudioBucket.bucket(level: 15, isMuted: false, kind: .mic), 5)
    }

    func testMicAudioBucketIsZeroWhenMuted() {
        let bucket = ShureOverviewAudioBucket.bucket(level: 18, isMuted: true, kind: .mic)
        XCTAssertEqual(bucket, 0)
    }

    func testMicAudioBucketIsZeroForNilOrNonPositiveLevel() {
        XCTAssertEqual(ShureOverviewAudioBucket.bucket(level: nil, isMuted: false, kind: .mic), 0)
        XCTAssertEqual(ShureOverviewAudioBucket.bucket(level: 0, isMuted: false, kind: .mic), 0)
    }

    func testIemAudioBucketLogScalesAcrossWideRange() {
        XCTAssertEqual(ShureOverviewAudioBucket.bucket(level: 100, isMuted: false, kind: .iem), 0)
        XCTAssertEqual(ShureOverviewAudioBucket.bucket(level: 10_000, isMuted: false, kind: .iem), 5)
        XCTAssertEqual(ShureOverviewAudioBucket.bucket(level: 1_000_000, isMuted: false, kind: .iem), ShureOverviewAudioBucket.levelSegmentCount)
    }

    func testOverviewMeterRateSignalLightTiersScaleWithChannelCount() {
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 1, mode: .signalLight), 300)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 8, mode: .signalLight), 300)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 9, mode: .signalLight), 600)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 16, mode: .signalLight), 600)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 17, mode: .signalLight), 900)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 24, mode: .signalLight), 900)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 25, mode: .signalLight), 1200)
    }

    func testOverviewMeterRateOffModeMatchesSignalLightTiers() {
        XCTAssertEqual(
            ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 12, mode: .off),
            ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 12, mode: .signalLight)
        )
    }

    func testOverviewMeterRateMeterTiersScaleWithChannelCountAndStayUnderOneSecond() {
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 1, mode: .meter), 100)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 8, mode: .meter), 100)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 9, mode: .meter), 200)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 16, mode: .meter), 200)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 17, mode: .meter), 350)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 24, mode: .meter), 350)
        XCTAssertEqual(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 25, mode: .meter), 500)
        XCTAssertLessThan(ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: 1000, mode: .meter), 1000)
    }

    func testOverviewPollingIntervalSignalLightTiersScaleWithChannelCount() {
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 8, mode: .signalLight), 0.4)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 9, mode: .signalLight), 0.6)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 16, mode: .signalLight), 0.6)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 17, mode: .signalLight), 0.9)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 24, mode: .signalLight), 0.9)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 25, mode: .signalLight), 1.2)
    }

    func testOverviewPollingIntervalMeterTiersScaleWithChannelCount() {
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 8, mode: .meter), 0.15)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 9, mode: .meter), 0.3)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 16, mode: .meter), 0.3)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 17, mode: .meter), 0.45)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 24, mode: .meter), 0.45)
        XCTAssertEqual(ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: 25, mode: .meter), 0.6)
    }

    @MainActor
    func testSnapshotPublishIntervalPrioritizesChannelDetailConsumer() {
        let service = ShureWirelessService(deviceID: nil)
        service.setOverviewPollingInterval(1.0)
        service.setLiveModeEnabled(true)

        let overviewConsumer = UUID()
        service.setOverviewConsumerVisible(overviewConsumer, visible: true)
        XCTAssertEqual(service.snapshotPublishInterval(), 1.0)

        let channelConsumer = UUID()
        service.setChannelConsumer(channelConsumer, channelIndex: 1)
        XCTAssertEqual(service.snapshotPublishInterval(), 0.15)

        service.setChannelConsumer(channelConsumer, channelIndex: nil)
        XCTAssertEqual(service.snapshotPublishInterval(), 1.0)
    }

    @MainActor
    func testSnapshotPublishIntervalUsesOverviewPollingIntervalWhenNoChannelConsumer() {
        let service = ShureWirelessService(deviceID: nil)
        service.setLiveModeEnabled(true)
        service.setOverviewPollingInterval(0.75)

        let overviewConsumer = UUID()
        service.setOverviewConsumerVisible(overviewConsumer, visible: true)
        XCTAssertEqual(service.snapshotPublishInterval(), 0.75)
    }

    @MainActor
    func testEffectiveMeterRateFavorsChannelDetailConsumer() {
        let service = ShureWirelessService(deviceID: nil)
        service.setOverviewMeterRateMilliseconds(750)
        XCTAssertEqual(service.effectiveMeterRateMilliseconds(), 750)

        let channelConsumer = UUID()
        service.setChannelConsumer(channelConsumer, channelIndex: 1)
        XCTAssertEqual(service.effectiveMeterRateMilliseconds(), 100)

        service.setChannelConsumer(channelConsumer, channelIndex: nil)
        XCTAssertEqual(service.effectiveMeterRateMilliseconds(), 750)
    }

    @MainActor
    func testEffectiveMeterRateDefaultsTo100MillisecondsBeforeOverviewSetsRate() {
        let service = ShureWirelessService(deviceID: nil)
        XCTAssertEqual(service.effectiveMeterRateMilliseconds(), 100)
    }

    @MainActor
    func testOverviewHubIsSharedSingleton() {
        let first = ShureOverviewHub.shared
        let second = ShureOverviewHub.shared
        XCTAssertTrue(first === second)
        XCTAssertNotNil(first.rawChannels)
    }

    @MainActor
    func testOverviewHubThrottlesRapidRecomputeRequests() async throws {
        let hub = ShureOverviewHub.shared

        // `ExternalDevicesStore` in this test host is backed by real,
        // persisted app data rather than a hermetic fixture, so the Hub's
        // actual throttle interval depends on however many real Shure
        // channels happen to be configured locally (confirmed empirically
        // in this environment: enough real channels to sit in the top,
        // worst-case tier already). The Hub also runs its own 3-second
        // stale-sweep timer that calls `requestRecompute()` on its own,
        // independent of anything this test does, and other tests in this
        // suite that also touch `ShureOverviewHub.shared` can leave the
        // throttle pipeline in a not-quite-idle state depending on test
        // execution order (which Xcode does not guarantee).
        //
        // Given those two sources of nondeterminism, this can't reliably
        // pin down whether Combine's `throttle` forwards our burst via its
        // leading edge (near-instant) or its trailing edge (up to a full
        // `worstCaseInterval` later) — both are legitimate, observed
        // behavior here. So: drain with a single sleep past the worst-case
        // tier's interval to flush any pending emission left by an earlier
        // test, then wait that same worst-case interval again after the
        // burst (long enough to observe the update on either edge), and
        // assert that the 5 rapid calls collapsed to a small handful of
        // updates rather than passing straight through uncoalesced — up to
        // 2 rather than exactly 1, since the wait is also long enough to
        // occasionally pick up one incidental stale-sweep tick.
        let worstCaseInterval = ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: .max, mode: .off)
        let settleNanoseconds = UInt64((worstCaseInterval + 0.3) * 1_000_000_000)

        hub.requestRecompute()
        try await Task.sleep(nanoseconds: settleNanoseconds)

        var updateCount = 0
        let token = hub.$lastUpdated
            .dropFirst() // ignore the value already published by init
            .sink { _ in updateCount += 1 }

        // Simulate several rapid telemetry updates within one throttle window.
        for _ in 0..<5 {
            hub.requestRecompute()
        }

        try await Task.sleep(nanoseconds: settleNanoseconds)
        token.cancel()

        XCTAssertGreaterThanOrEqual(updateCount, 1)
        XCTAssertLessThanOrEqual(updateCount, 2, "5 rapid recompute requests should coalesce, not pass straight through")
    }

    @MainActor
    func testOverviewHubInstanceLifecycleTracksLiveState() {
        let hub = ShureOverviewHub.shared
        let instanceA = UUID()
        let instanceB = UUID()

        hub.registerInstance(instanceA)
        hub.registerInstance(instanceB)

        hub.setInstanceLiveMode(instanceA, enabled: true)
        XCTAssertTrue(hub.isHubLive)

        hub.setInstanceLiveMode(instanceA, enabled: false)
        XCTAssertFalse(hub.isHubLive)

        hub.setInstanceLiveMode(instanceB, enabled: true)
        XCTAssertTrue(hub.isHubLive)

        hub.unregisterInstance(instanceB)
        XCTAssertFalse(hub.isHubLive)

        hub.unregisterInstance(instanceA)
    }

    @MainActor
    func testOverviewViewModelStartsEmptyAndTracksHubUpdates() {
        let viewModel = ShureOverviewViewModel(hub: ShureOverviewHub.shared)
        viewModel.updateConfig(.default())

        // With the default config (all Shure devices, nothing hidden), the
        // view model should mirror every channel the hub currently knows
        // about — whether that's none (a clean environment) or some (real
        // devices configured in this environment's persisted store).
        XCTAssertEqual(viewModel.channels.count, ShureOverviewHub.shared.rawChannels.count)
        XCTAssertEqual(viewModel.lastUpdated, ShureOverviewHub.shared.lastUpdated)
    }

    func testTelemetrySnapshotHasSameContentIgnoresNothingForIsReconnecting() {
        let base = ShureTelemetryDeviceSnapshot(
            deviceID: nil,
            deviceName: "Test",
            isConnected: false,
            isReconnecting: false,
            lastHeardAt: nil,
            updatedAt: Date(),
            channels: [],
            diagnostics: .empty
        )
        let reconnecting = ShureTelemetryDeviceSnapshot(
            deviceID: nil,
            deviceName: "Test",
            isConnected: false,
            isReconnecting: true,
            lastHeardAt: nil,
            updatedAt: Date(),
            channels: [],
            diagnostics: .empty
        )

        XCTAssertFalse(base.hasSameContent(as: reconnecting))
    }
}
