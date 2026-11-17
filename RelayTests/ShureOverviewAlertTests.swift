import XCTest
@testable import Relay

final class ShureOverviewAlertTests: XCTestCase {
    func testConditionIsNotSustainedUntilDurationPasses() {
        var condition = ShureOverviewSustainedCondition()
        let start = Date()

        XCTAssertFalse(condition.isSustained(id: "ch1", active: true, now: start, for: 12))
        XCTAssertFalse(condition.isSustained(id: "ch1", active: true, now: start.addingTimeInterval(11), for: 12))
        XCTAssertTrue(condition.isSustained(id: "ch1", active: true, now: start.addingTimeInterval(12), for: 12))
    }

    /// A mic switched off: RF drops while presence still reads "on" for a few seconds, then
    /// the condition stops applying. It must never reach the alert threshold.
    func testBriefConditionResetsWhenItClears() {
        var condition = ShureOverviewSustainedCondition()
        let start = Date()

        XCTAssertFalse(condition.isSustained(id: "ch1", active: true, now: start, for: 12))
        XCTAssertFalse(condition.isSustained(id: "ch1", active: false, now: start.addingTimeInterval(8), for: 12))
        // Comes back later: the clock starts over.
        XCTAssertFalse(condition.isSustained(id: "ch1", active: true, now: start.addingTimeInterval(20), for: 12))
        XCTAssertFalse(condition.isSustained(id: "ch1", active: true, now: start.addingTimeInterval(31), for: 12))
        XCTAssertTrue(condition.isSustained(id: "ch1", active: true, now: start.addingTimeInterval(32), for: 12))
    }

    func testChannelsAreTrackedSeparately() {
        var condition = ShureOverviewSustainedCondition()
        let start = Date()

        _ = condition.isSustained(id: "ch1", active: true, now: start, for: 12)
        XCTAssertFalse(condition.isSustained(id: "ch2", active: true, now: start.addingTimeInterval(12), for: 12))
        XCTAssertTrue(condition.isSustained(id: "ch1", active: true, now: start.addingTimeInterval(12), for: 12))
    }

    func testPruneForgetsUnlistedChannels() {
        var condition = ShureOverviewSustainedCondition()
        let start = Date()
        _ = condition.isSustained(id: "ch1", active: true, now: start, for: 12)

        condition.prune(keeping: ["ch2"])

        XCTAssertFalse(condition.isSustained(id: "ch1", active: true, now: start.addingTimeInterval(12), for: 12))
    }

    func testRfAlertsWaitOutTheTransmitterPresenceHold() {
        XCTAssertGreaterThanOrEqual(
            ShureOverviewViewModel.rfAlertSustainSeconds,
            ShureAxientPresenceResolver.positiveEvidenceHoldSeconds
        )
    }
}
