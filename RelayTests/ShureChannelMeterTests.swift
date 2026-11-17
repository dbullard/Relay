import XCTest
@testable import Relay

@MainActor
final class ShureChannelMeterTests: XCTestCase {
    func testLevelRisesImmediately() {
        let meter = ShureChannelMeter()
        meter.receive(level: 12, stereo: nil, isOverloaded: false, isMuted: false, sampleAt: Date())
        XCTAssertEqual(meter.level, 12)
    }

    func testLevelFallsGraduallyAndSettlesOnTarget() {
        let meter = ShureChannelMeter()
        let now = Date()
        meter.receive(level: 10, stereo: nil, isOverloaded: false, isMuted: false, sampleAt: now)
        meter.receive(level: 2, stereo: nil, isOverloaded: false, isMuted: false, sampleAt: now)
        XCTAssertEqual(meter.level, 10, "falls are animated, not immediate")

        _ = meter.advance(now: now)
        XCTAssertLessThan(meter.level, 10)
        XCTAssertGreaterThan(meter.level, 2)

        for _ in 0..<200 { _ = meter.advance(now: now) }
        XCTAssertEqual(meter.level, 2)
    }

    func testStaleMeterDropsToZeroAndStopsTicking() {
        let meter = ShureChannelMeter()
        let sampleAt = Date()
        meter.receive(level: 8, stereo: nil, isOverloaded: true, isMuted: false, sampleAt: sampleAt)

        let later = sampleAt.addingTimeInterval(ShureChannelMeter.staleAfter + 1)
        var stillTicking = true
        for _ in 0..<200 where stillTicking {
            stillTicking = meter.advance(now: later)
        }
        XCTAssertEqual(meter.level, 0)
        XCTAssertFalse(meter.isOverloaded)
        XCTAssertFalse(stillTicking)
    }

    func testFreshSamplesKeepLevel() {
        let meter = ShureChannelMeter()
        let now = Date()
        meter.receive(level: 6, stereo: nil, isOverloaded: false, isMuted: false, sampleAt: now)
        for _ in 0..<50 { XCTAssertTrue(meter.advance(now: now)) }
        XCTAssertEqual(meter.level, 6)
    }

    func testStereoSidesTrackSeparately() {
        let meter = ShureChannelMeter()
        meter.receive(level: 50_000, stereo: (left: 50_000, right: 1_000), isOverloaded: false, isMuted: false, sampleAt: Date())
        XCTAssertEqual(meter.left, 50_000)
        XCTAssertEqual(meter.right, 1_000)
    }

    func testStepSnapsWithinTolerance() {
        XCTAssertEqual(ShureChannelMeter.step(0.02, toward: 0), 0)
        XCTAssertGreaterThan(ShureChannelMeter.step(5, toward: 0), 0)
        XCTAssertEqual(ShureChannelMeter.step(5, toward: 7), 7)
    }

    func testStereoSegmentsUseLogScale() {
        XCTAssertEqual(ShureTileStereoMeter.segments(for: 0), 0)
        XCTAssertEqual(ShureTileStereoMeter.segments(for: 100), 0)
        XCTAssertEqual(ShureTileStereoMeter.segments(for: 10_000), 4)
        XCTAssertEqual(ShureTileStereoMeter.segments(for: 1_000_000), 8)
        XCTAssertEqual(ShureTileStereoMeter.segments(for: 50_000_000), 8)
    }
}
