import XCTest
import Combine
@testable import Relay

@MainActor
final class DAWTransportViewModelTests: XCTestCase {
    func testStatusTimerRunsOnlyWhileATileIsOnScreen() {
        let model = DAWTransportViewModel(configuration: .default())
        XCTAssertFalse(model.isStatusTimerRunning)

        model.tileDidAppear()
        XCTAssertTrue(model.isStatusTimerRunning)

        // A second view of the same module (e.g. a snapshot render) keeps it running.
        model.tileDidAppear()
        model.tileDidDisappear()
        XCTAssertTrue(model.isStatusTimerRunning)

        model.tileDidDisappear()
        XCTAssertFalse(model.isStatusTimerRunning)
    }

    func testUnchangedStatusPassDoesNotNotify() {
        let model = DAWTransportViewModel(configuration: .default())
        model.tileDidAppear()
        var notifications = 0
        let subscription = model.objectWillChange.sink { notifications += 1 }

        // Each appearance runs a full status pass; nothing has changed since the last one.
        model.tileDidDisappear()
        model.tileDidAppear()

        XCTAssertEqual(notifications, 0)
        subscription.cancel()
        model.tileDidDisappear()
    }
}
