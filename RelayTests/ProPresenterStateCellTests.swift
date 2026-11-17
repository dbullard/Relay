import XCTest
@testable import Relay

@MainActor
final class ProPresenterStateCellTests: XCTestCase {
    func testPollTimestampAloneDoesNotUpdateTheTile() {
        var current = ProPresenterService.State()
        current.lastUpdated = Date(timeIntervalSince1970: 100)
        var next = current
        next.lastUpdated = Date(timeIntervalSince1970: 100.5)

        XCTAssertFalse(ProPresenterService.cellNeedsUpdate(current, to: next))
    }

    func testFirstSuccessfulPollUpdatesTheTile() {
        let current = ProPresenterService.State()
        var next = current
        next.lastUpdated = Date()

        XCTAssertTrue(ProPresenterService.cellNeedsUpdate(current, to: next))
    }

    func testContentChangeUpdatesTheTile() {
        var current = ProPresenterService.State()
        current.lastUpdated = Date(timeIntervalSince1970: 100)
        var next = current
        next.lastUpdated = Date(timeIntervalSince1970: 100.5)
        next.lastAPISlideIndex = 3

        XCTAssertTrue(ProPresenterService.cellNeedsUpdate(current, to: next))
    }

    func testErrorChangeUpdatesTheTile() {
        let current = ProPresenterService.State()
        var next = current
        next.lastError = "Connection refused"

        XCTAssertTrue(ProPresenterService.cellNeedsUpdate(current, to: next))
    }

    func testCellIsSharedPerModule() {
        let service = ProPresenterService()
        let moduleID = UUID()

        XCTAssertTrue(service.stateCell(for: moduleID) === service.stateCell(for: moduleID))
        XCTAssertFalse(service.stateCell(for: moduleID) === service.stateCell(for: UUID()))
    }
}
