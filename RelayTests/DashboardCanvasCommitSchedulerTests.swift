import XCTest
@testable import Relay

final class DashboardCanvasCommitSchedulerTests: XCTestCase {

    func testCommitsImmediatelyForAProgrammaticChangeOutsideAGesture() {
        var scheduler = DashboardCanvasCommitScheduler()
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(scheduler.shouldCommit(now: now, isInteracting: false, wasInteracting: false))
    }

    func testDoesNotThrottleBackToBackProgrammaticChanges() {
        var scheduler = DashboardCanvasCommitScheduler()
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(scheduler.shouldCommit(now: start, isInteracting: false, wasInteracting: false))
        // A second toolbar-button zoom change 10ms later should still commit
        // immediately -- throttling only applies to live in-gesture updates.
        XCTAssertTrue(
            scheduler.shouldCommit(now: start.addingTimeInterval(0.01), isInteracting: false, wasInteracting: false)
        )
    }

    func testThrottlesRapidUpdatesDuringAnActiveGesture() {
        var scheduler = DashboardCanvasCommitScheduler(minimumInterval: 0.12)
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(scheduler.shouldCommit(now: start, isInteracting: true, wasInteracting: true))
        // 50ms later -- inside the throttle window, should NOT commit.
        XCTAssertFalse(
            scheduler.shouldCommit(now: start.addingTimeInterval(0.05), isInteracting: true, wasInteracting: true)
        )
        // 130ms after the first commit -- past the window, should commit.
        XCTAssertTrue(
            scheduler.shouldCommit(now: start.addingTimeInterval(0.13), isInteracting: true, wasInteracting: true)
        )
    }

    func testAlwaysCommitsTheInstantAGestureEnds() {
        var scheduler = DashboardCanvasCommitScheduler(minimumInterval: 0.12)
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(scheduler.shouldCommit(now: start, isInteracting: true, wasInteracting: true))
        // Gesture ends 10ms later -- well inside the throttle window, but a
        // gesture-end must always commit so nothing is left stale.
        let ended = start.addingTimeInterval(0.01)
        XCTAssertTrue(scheduler.shouldCommit(now: ended, isInteracting: false, wasInteracting: true))
    }

    func testCommitsOnTheFirstTickOfANewGesture() {
        var scheduler = DashboardCanvasCommitScheduler(minimumInterval: 0.12)
        let start = Date(timeIntervalSince1970: 0)
        // The very first tick of a brand-new gesture -- `lastCommitDate` is
        // still nil, so this should fall through and commit immediately
        // rather than being throttled.
        XCTAssertTrue(scheduler.shouldCommit(now: start, isInteracting: true, wasInteracting: false))
    }

    func testResetsTheThrottleWindowAfterEachCommit() {
        var scheduler = DashboardCanvasCommitScheduler(minimumInterval: 0.12)
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(scheduler.shouldCommit(now: start, isInteracting: true, wasInteracting: true))
        let secondCommit = start.addingTimeInterval(0.13)
        XCTAssertTrue(scheduler.shouldCommit(now: secondCommit, isInteracting: true, wasInteracting: true))
        // Only 50ms after the *second* commit -- should be throttled again,
        // even though it's 180ms after the first.
        XCTAssertFalse(
            scheduler.shouldCommit(now: secondCommit.addingTimeInterval(0.05), isInteracting: true, wasInteracting: true)
        )
    }
}
