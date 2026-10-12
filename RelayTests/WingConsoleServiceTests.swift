import XCTest
@testable import Relay

final class WingConsoleServiceTests: XCTestCase {
    func testWingPanValueCenter() {
        XCTAssertEqual(WingConsoleService.wingPanValue(from: 0.0), 0)
    }

    func testWingPanValueFullLeftAndRight() {
        XCTAssertEqual(WingConsoleService.wingPanValue(from: -1.0), -100)
        XCTAssertEqual(WingConsoleService.wingPanValue(from: 1.0), 100)
    }

    func testWingPanValueClampsOutOfRangeInput() {
        XCTAssertEqual(WingConsoleService.wingPanValue(from: -2.5), -100)
        XCTAssertEqual(WingConsoleService.wingPanValue(from: 2.5), 100)
    }

    func testWingPanValueRounds() {
        XCTAssertEqual(WingConsoleService.wingPanValue(from: 0.375), 38) // 37.5 rounds to 38
    }

    func testWingLevelDbPassesThroughInRange() {
        XCTAssertEqual(WingConsoleService.wingLevelDb(from: -12.0), -12.0)
        XCTAssertEqual(WingConsoleService.wingLevelDb(from: 0.0), 0.0)
    }

    func testWingLevelDbClampsToFloorAndCeiling() {
        XCTAssertEqual(WingConsoleService.wingLevelDb(from: -200.0), -144.0)
        XCTAssertEqual(WingConsoleService.wingLevelDb(from: 20.0), 10.0)
    }
}
