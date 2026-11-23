import XCTest
@testable import Relay

/// The Time module's countdown and timer derive their value from wall-clock dates, so a
/// skipped tick (typing, tile off-screen, ticker paused) can't make them fall behind.
final class TimeModuleClockTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testCountdownShowsFullDurationUntilTheFirstSecondPasses() {
        let end = start.addingTimeInterval(300)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: start), 300)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: start.addingTimeInterval(0.4)), 300)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: start.addingTimeInterval(1.0)), 299)
    }

    func testCountdownCatchesUpAfterMissedTicks() {
        // A minute without ticks (e.g. the operator was typing) is not lost.
        let end = start.addingTimeInterval(300)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: start.addingTimeInterval(60.2)), 240)
    }

    func testCountdownReachesZeroOnlyAtTheEndAndNeverGoesNegative() {
        let end = start.addingTimeInterval(10)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: start.addingTimeInterval(9.9)), 1)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: end), 0)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: end.addingTimeInterval(42)), 0)
    }

    func testTimerCountsWholeSecondsAndCatchesUp() {
        XCTAssertEqual(TimeModuleClock.timerElapsed(startDate: start, now: start.addingTimeInterval(0.9)), 0)
        XCTAssertEqual(TimeModuleClock.timerElapsed(startDate: start, now: start.addingTimeInterval(1.0)), 1)
        XCTAssertEqual(TimeModuleClock.timerElapsed(startDate: start, now: start.addingTimeInterval(125.5)), 125)
    }

    func testTimerNeverGoesNegativeIfTheClockMovesBack() {
        XCTAssertEqual(TimeModuleClock.timerElapsed(startDate: start, now: start.addingTimeInterval(-5)), 0)
    }
}
