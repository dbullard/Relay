import XCTest
@testable import Relay

final class ShureOverviewHubTests: XCTestCase {

    func testAxientMeterSchedulerStaggersDueChannelsInRoundRobinOrder() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let first = ShureAxientOverviewMeterPollScheduler.nextChannel(
            among: [1, 2, 3, 4],
            lastPolledAt: [:],
            now: now,
            minimumInterval: 1
        )
        XCTAssertEqual(first, 1)

        let second = ShureAxientOverviewMeterPollScheduler.nextChannel(
            among: [1, 2, 3, 4],
            lastPolledAt: [1: now],
            now: now,
            minimumInterval: 1
        )
        XCTAssertEqual(second, 2)
    }

    func testAxientMeterSchedulerWaitsUntilAChannelIsDueAgain() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let channel = ShureAxientOverviewMeterPollScheduler.nextChannel(
            among: [1, 2],
            lastPolledAt: [
                1: now.addingTimeInterval(-0.4),
                2: now.addingTimeInterval(-0.6)
            ],
            now: now,
            minimumInterval: 1
        )

        XCTAssertNil(channel)
    }

    func testEffectiveModeIsOffWhenNoInstancesAreLive() {
        let tileA = UUID()
        let mode = ShureOverviewAudioModeReconciler.effectiveMode(
            requestedModes: [tileA: .meter],
            liveInstances: []
        )
        XCTAssertEqual(mode, .off)
    }

    func testEffectiveModeIgnoresNonLiveInstances() {
        let liveTile = UUID()
        let backgroundTile = UUID()
        let mode = ShureOverviewAudioModeReconciler.effectiveMode(
            requestedModes: [liveTile: .signalLight, backgroundTile: .meter],
            liveInstances: [liveTile]
        )
        XCTAssertEqual(mode, .signalLight)
    }

    func testEffectiveModeIsTheFastestAmongLiveInstances() {
        let tileA = UUID()
        let tileB = UUID()
        let mode = ShureOverviewAudioModeReconciler.effectiveMode(
            requestedModes: [tileA: .signalLight, tileB: .meter],
            liveInstances: [tileA, tileB]
        )
        XCTAssertEqual(mode, .meter)
    }

    @MainActor
    func testHubReconcilesEffectiveModeAcrossRegisteredInstances() {
        let hub = ShureOverviewHub.shared
        let tileA = UUID()
        let tileB = UUID()
        hub.registerInstance(tileA)
        hub.registerInstance(tileB)
        defer {
            hub.unregisterInstance(tileA)
            hub.unregisterInstance(tileB)
        }

        hub.setInstanceLiveMode(tileA, enabled: true)
        hub.setInstanceLiveMode(tileB, enabled: true)
        hub.setInstanceAudioMode(tileA, mode: .signalLight)
        XCTAssertEqual(hub.effectiveAudioMode, .signalLight)

        hub.setInstanceAudioMode(tileB, mode: .meter)
        XCTAssertEqual(hub.effectiveAudioMode, .meter)

        hub.unregisterInstance(tileB)
        XCTAssertEqual(hub.effectiveAudioMode, .signalLight)
    }

    @MainActor
    func testEffectiveModeReconcilesWhenTileGoesLiveAfterRequestingMode() {
        let hub = ShureOverviewHub.shared
        let tile = UUID()
        hub.registerInstance(tile)
        defer { hub.unregisterInstance(tile) }

        hub.setInstanceAudioMode(tile, mode: .meter)
        XCTAssertEqual(hub.effectiveAudioMode, .off) // not live yet, shouldn't count

        hub.setInstanceLiveMode(tile, enabled: true)
        XCTAssertEqual(hub.effectiveAudioMode, .meter)
    }

    func testStrainEvaluatorFlagsWhenBusyTimeExceedsBudget() {
        let diagnostics = ShureTelemetryDiagnosticsSnapshot(
            activeServiceCount: 1,
            connectedPhysicalDeviceCount: 1,
            overviewSubscriberCount: 1,
            channelSubscriberCount: 0,
            pollingIntervalDescription: "0.15s",
            snapshotPublishRateHz: 6,
            averageParseTimeMilliseconds: 90,
            averageSnapshotBuildTimeMilliseconds: 30,
            droppedCoalescedUpdateCount: 0,
            lastSlowRefreshAt: nil,
            lastFastTelemetryAt: nil
        )
        // budget = 0.15s = 150ms; 70% of that is 105ms; 90+30=120ms exceeds it.
        let strained = ShureOverviewPerformanceStrainEvaluator.isStrained(
            diagnostics: diagnostics,
            pollingIntervalSeconds: 0.15,
            previousDroppedCount: 0,
            elapsedSeconds: 1.0
        )
        XCTAssertTrue(strained)
    }

    func testStrainEvaluatorDoesNotFlagWellWithinBudget() {
        let diagnostics = ShureTelemetryDiagnosticsSnapshot(
            activeServiceCount: 1,
            connectedPhysicalDeviceCount: 1,
            overviewSubscriberCount: 1,
            channelSubscriberCount: 0,
            pollingIntervalDescription: "0.6s",
            snapshotPublishRateHz: 1.5,
            averageParseTimeMilliseconds: 10,
            averageSnapshotBuildTimeMilliseconds: 5,
            droppedCoalescedUpdateCount: 3,
            lastSlowRefreshAt: nil,
            lastFastTelemetryAt: nil
        )
        let strained = ShureOverviewPerformanceStrainEvaluator.isStrained(
            diagnostics: diagnostics,
            pollingIntervalSeconds: 0.6,
            previousDroppedCount: 3,
            elapsedSeconds: 1.0
        )
        XCTAssertFalse(strained)
    }

    func testStrainEvaluatorDoesNotFlagRoutineCoalescingBelowRateThreshold() {
        // Real 44-channel meter-mode sessions routinely coalesce updates at
        // up to ~80/sec with parse/snapshot time nowhere near budget -- a
        // single stray drop (1/sec here) must not trip strain.
        let diagnostics = ShureTelemetryDiagnosticsSnapshot(
            activeServiceCount: 1,
            connectedPhysicalDeviceCount: 1,
            overviewSubscriberCount: 1,
            channelSubscriberCount: 0,
            pollingIntervalDescription: "0.6s",
            snapshotPublishRateHz: 1.5,
            averageParseTimeMilliseconds: 10,
            averageSnapshotBuildTimeMilliseconds: 5,
            droppedCoalescedUpdateCount: 4,
            lastSlowRefreshAt: nil,
            lastFastTelemetryAt: nil
        )
        let strained = ShureOverviewPerformanceStrainEvaluator.isStrained(
            diagnostics: diagnostics,
            pollingIntervalSeconds: 0.6,
            previousDroppedCount: 3,
            elapsedSeconds: 1.0
        )
        XCTAssertFalse(strained)
    }

    func testStrainEvaluatorFlagsWhenDropRateExceedsThreshold() {
        let diagnostics = ShureTelemetryDiagnosticsSnapshot(
            activeServiceCount: 1,
            connectedPhysicalDeviceCount: 1,
            overviewSubscriberCount: 1,
            channelSubscriberCount: 0,
            pollingIntervalDescription: "0.6s",
            snapshotPublishRateHz: 1.5,
            averageParseTimeMilliseconds: 10,
            averageSnapshotBuildTimeMilliseconds: 5,
            droppedCoalescedUpdateCount: 1000,
            lastSlowRefreshAt: nil,
            lastFastTelemetryAt: nil
        )
        // 900 new drops over 1s = 900/sec, well past the 150/sec threshold.
        let strained = ShureOverviewPerformanceStrainEvaluator.isStrained(
            diagnostics: diagnostics,
            pollingIntervalSeconds: 0.6,
            previousDroppedCount: 100,
            elapsedSeconds: 1.0
        )
        XCTAssertTrue(strained)
    }

    func testStrainEvaluatorDoesNotFlagExactlyAtDropRateThreshold() {
        // The comparison is strict `>`, so a rate exactly at the threshold
        // must NOT be flagged as strained.
        let diagnostics = ShureTelemetryDiagnosticsSnapshot(
            activeServiceCount: 1,
            connectedPhysicalDeviceCount: 1,
            overviewSubscriberCount: 1,
            channelSubscriberCount: 0,
            pollingIntervalDescription: "0.6s",
            snapshotPublishRateHz: 1.5,
            averageParseTimeMilliseconds: 10,
            averageSnapshotBuildTimeMilliseconds: 5,
            droppedCoalescedUpdateCount: 150,
            lastSlowRefreshAt: nil,
            lastFastTelemetryAt: nil
        )
        let strained = ShureOverviewPerformanceStrainEvaluator.isStrained(
            diagnostics: diagnostics,
            pollingIntervalSeconds: 0.6,
            previousDroppedCount: 0,
            elapsedSeconds: 1.0
        )
        XCTAssertFalse(strained)
    }

    func testStrainEvaluatorDoesNotFlagOnFirstObservationWithZeroElapsedTime() {
        // elapsedSeconds == 0 means this is the first check -- there's no
        // time base to compute a rate from, so even a huge raw delta must
        // not be flagged (the busy-time check still runs independently).
        let diagnostics = ShureTelemetryDiagnosticsSnapshot(
            activeServiceCount: 1,
            connectedPhysicalDeviceCount: 1,
            overviewSubscriberCount: 1,
            channelSubscriberCount: 0,
            pollingIntervalDescription: "0.6s",
            snapshotPublishRateHz: 1.5,
            averageParseTimeMilliseconds: 10,
            averageSnapshotBuildTimeMilliseconds: 5,
            droppedCoalescedUpdateCount: 10000,
            lastSlowRefreshAt: nil,
            lastFastTelemetryAt: nil
        )
        let strained = ShureOverviewPerformanceStrainEvaluator.isStrained(
            diagnostics: diagnostics,
            pollingIntervalSeconds: 0.6,
            previousDroppedCount: 0,
            elapsedSeconds: 0
        )
        XCTAssertFalse(strained)
    }

    func testStrainEvaluatorDoesNotFlagExactlyAtBudgetThreshold() {
        // budget = 1.0s = 1000ms; 70% of that is exactly 700ms.
        // The comparison is strict `>`, so busy time exactly at the
        // threshold must NOT be flagged as strained.
        let diagnostics = ShureTelemetryDiagnosticsSnapshot(
            activeServiceCount: 1,
            connectedPhysicalDeviceCount: 1,
            overviewSubscriberCount: 1,
            channelSubscriberCount: 0,
            pollingIntervalDescription: "1.0s",
            snapshotPublishRateHz: 1,
            averageParseTimeMilliseconds: 500,
            averageSnapshotBuildTimeMilliseconds: 200,
            droppedCoalescedUpdateCount: 0,
            lastSlowRefreshAt: nil,
            lastFastTelemetryAt: nil
        )
        let strained = ShureOverviewPerformanceStrainEvaluator.isStrained(
            diagnostics: diagnostics,
            pollingIntervalSeconds: 1.0,
            previousDroppedCount: 0,
            elapsedSeconds: 1.0
        )
        XCTAssertFalse(strained)
    }
}
