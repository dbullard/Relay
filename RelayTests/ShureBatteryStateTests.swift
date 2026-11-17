import XCTest
@testable import Relay

final class ShureBatteryStateTests: XCTestCase {
    private func runtime(_ minutes: Int) -> ShureBatteryState.Update {
        .set(label: String(format: "%d:%02d", minutes / 60, minutes % 60), percentage: nil, isApproximate: false, priority: 3)
    }

    private func charge(_ percent: Int) -> ShureBatteryState.Update {
        .set(label: "\(percent)%", percentage: percent, isApproximate: false, priority: 2)
    }

    private func bars(_ count: Int) -> ShureBatteryState.Update {
        let percent = count * 20
        return .set(label: "\(percent)% approx", percentage: percent, isApproximate: true, priority: 1)
    }

    func testUnknownKeepsLastGoodReading() {
        var battery = ShureBatteryState()
        battery.apply(runtime(550))
        battery.apply(charge(100))

        battery.apply(.unknown)

        XCTAssertEqual(battery.label, "9:10")
        XCTAssertEqual(battery.percentage, 100)
        XCTAssertEqual(battery.isApproximate, false)
    }

    /// The sequence a ULX-D receiver sent for WL 1: valid smart-battery data, then the
    /// unknown burst (BATT_BARS 255 becomes `.unknown`; 65535 runtime and 255 charge are
    /// dropped as sentinels before they get here), then data again.
    func testReceiverUnknownBurstDoesNotBlankBattery() {
        var battery = ShureBatteryState()
        battery.applyBatteryType("LION")
        battery.apply(bars(5))
        battery.apply(runtime(550))
        battery.apply(charge(100))

        battery.applyBatteryType("UNKN")
        battery.apply(.unknown)

        XCTAssertTrue(battery.hasReading)
        XCTAssertEqual(battery.label, "9:10")
        XCTAssertEqual(battery.percentage, 100)
        XCTAssertEqual(battery.batteryType, "LION")

        battery.apply(runtime(549))
        XCTAssertEqual(battery.label, "9:09")
    }

    func testRuntimeOwnsLabelButPercentageStillUpdates() {
        var battery = ShureBatteryState()
        battery.apply(runtime(120))
        battery.apply(charge(86))

        XCTAssertEqual(battery.label, "2:00")
        XCTAssertEqual(battery.percentage, 86)
    }

    func testApproximatePercentageDoesNotOverwriteExact() {
        var battery = ShureBatteryState()
        battery.apply(charge(86))
        battery.apply(bars(5))

        XCTAssertEqual(battery.percentage, 86)
        XCTAssertEqual(battery.isApproximate, false)
    }

    func testApproximatePercentageAppliesWithoutExactReading() {
        var battery = ShureBatteryState()
        battery.apply(bars(3))

        XCTAssertEqual(battery.percentage, 60)
        XCTAssertEqual(battery.isApproximate, true)
    }

    func testDifferentBatteryTypeStartsFresh() {
        var battery = ShureBatteryState()
        battery.applyBatteryType("LION")
        battery.apply(runtime(300))
        battery.apply(charge(40))

        battery.applyBatteryType("ALKA")

        XCTAssertFalse(battery.hasReading)
        XCTAssertNil(battery.priority)
        XCTAssertEqual(battery.batteryType, "ALKA")

        // Bars can set the label again; the old runtime priority no longer blocks them.
        battery.apply(bars(4))
        XCTAssertEqual(battery.label, "80% approx")
    }

    func testSameBatteryTypeKeepsReading() {
        var battery = ShureBatteryState()
        battery.applyBatteryType("LION")
        battery.apply(charge(70))

        battery.applyBatteryType(" lion ")

        XCTAssertEqual(battery.percentage, 70)
    }

    func testClearDropsEverything() {
        var battery = ShureBatteryState()
        battery.applyBatteryType("LION")
        battery.apply(runtime(300))
        battery.apply(charge(40))

        battery.clear()

        XCTAssertEqual(battery, ShureBatteryState())
        XCTAssertFalse(battery.hasReading)
    }
}
