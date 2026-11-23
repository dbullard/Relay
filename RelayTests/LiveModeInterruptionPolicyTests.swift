import XCTest
@testable import Relay

final class LiveModeInterruptionPolicyTests: XCTestCase {

    func testConnectionLostIsAlertOutsideLiveModeAndBannerInLiveMode() {
        XCTAssertEqual(LiveModeInterruptionPolicy.connectionLostPresentation(isLiveMode: false), .modal)
        XCTAssertEqual(LiveModeInterruptionPolicy.connectionLostPresentation(isLiveMode: true), .banner)
    }

    func testPairingSheetPresentsOutsideLiveMode() {
        XCTAssertTrue(LiveModeInterruptionPolicy.mayPresentPairingApproval(isLiveMode: false, reviewRequested: false))
        XCTAssertFalse(LiveModeInterruptionPolicy.showsPairingReviewBanner(
            isLiveMode: false, hasQueuedRequest: true, reviewRequested: false))
    }

    func testPairingRequestIsQueuedBehindBannerInLiveMode() {
        XCTAssertFalse(LiveModeInterruptionPolicy.mayPresentPairingApproval(isLiveMode: true, reviewRequested: false))
        XCTAssertTrue(LiveModeInterruptionPolicy.showsPairingReviewBanner(
            isLiveMode: true, hasQueuedRequest: true, reviewRequested: false))
    }

    func testReviewPresentsSheetInLiveModeAndHidesBanner() {
        XCTAssertTrue(LiveModeInterruptionPolicy.mayPresentPairingApproval(isLiveMode: true, reviewRequested: true))
        XCTAssertFalse(LiveModeInterruptionPolicy.showsPairingReviewBanner(
            isLiveMode: true, hasQueuedRequest: true, reviewRequested: true))
    }

    func testNoBannerWithoutAQueuedRequest() {
        XCTAssertFalse(LiveModeInterruptionPolicy.showsPairingReviewBanner(
            isLiveMode: true, hasQueuedRequest: false, reviewRequested: false))
    }

    func testBannerCopy() {
        XCTAssertEqual(LiveModeInterruptionPolicy.pairingBannerTitle(queuedCount: 1), "Pairing request waiting")
        XCTAssertEqual(LiveModeInterruptionPolicy.pairingBannerTitle(queuedCount: 3), "3 pairing requests waiting")
        XCTAssertEqual(
            LiveModeInterruptionPolicy.pairingBannerSubtitle(deviceName: " Stage iPad "),
            "\u{201C}Stage iPad\u{201D} wants to pair. Nothing is allowed until you review it."
        )
        XCTAssertTrue(LiveModeInterruptionPolicy.pairingBannerSubtitle(deviceName: "  ").hasPrefix("A device"))
    }
}
