#if os(macOS)
import XCTest
@testable import Relay

/// Quit got stuck when the document flow decided inside applicationShouldTerminate(_:)
/// (an untouched blank dashboard): it replied before .terminateLater was returned, so
/// AppKit waited forever. A decision made while still inside must come back as the
/// return value instead of an early reply. Only the paths that don't call NSApp are tested.
@MainActor
final class AppTerminationCoordinatorTests: XCTestCase {

    func testQuitDecidedInsideShouldTerminateIsReturnedNotReplied() {
        let coordinator = AppTerminationCoordinator()
        coordinator.beginInteractiveTermination()
        let decision = coordinator.runInsideShouldTerminate {
            coordinator.continueTermination()
        }
        XCTAssertEqual(decision, true)
        XCTAssertFalse(coordinator.isAwaitingReply)
    }

    func testCancelDecidedInsideShouldTerminateIsReturned() {
        let coordinator = AppTerminationCoordinator()
        coordinator.beginInteractiveTermination()
        let decision = coordinator.runInsideShouldTerminate {
            coordinator.cancelTermination()
        }
        XCTAssertEqual(decision, false)
        XCTAssertFalse(coordinator.isAwaitingReply)
    }

    func testNoDecisionYetMeansTerminateLater() {
        let coordinator = AppTerminationCoordinator()
        coordinator.beginInteractiveTermination()
        let decision = coordinator.runInsideShouldTerminate {
            // The flow shows a "Save changes?" alert and replies later.
        }
        XCTAssertNil(decision)
        XCTAssertTrue(coordinator.isAwaitingReply)
    }
}
#endif
