import XCTest
@testable import Relay

final class DashboardPlatformCopyTests: XCTestCase {
    func testStartupFileHintUsesPlatformAppropriateInteraction() {
        let hint = DashboardPlatformCopy.startupFileHint

        #if os(iOS)
        XCTAssertFalse(hint.localizedCaseInsensitiveContains("right-click"))
        XCTAssertTrue(hint.localizedCaseInsensitiveContains("touch and hold"))
        #else
        XCTAssertTrue(hint.localizedCaseInsensitiveContains("right-click"))
        #endif
    }

    func testPlanningCenterHelpTextDoesNotSayMacOnIOS() {
        let help = DashboardPlatformCopy.planningCenterOAuthHelpText

        #if os(iOS)
        XCTAssertFalse(help.localizedCaseInsensitiveContains("Mac"))
        XCTAssertTrue(help.localizedCaseInsensitiveContains("device"))
        #else
        XCTAssertTrue(help.localizedCaseInsensitiveContains("Mac"))
        #endif
    }

    func testPlanningCenterConnectHelpStepUsesPlatformAppropriateVerb() {
        let helpStep = DashboardPlatformCopy.planningCenterConnectHelpStep

        #if os(iOS)
        XCTAssertFalse(helpStep.localizedCaseInsensitiveContains("Click"))
        XCTAssertTrue(helpStep.localizedCaseInsensitiveContains("Tap"))
        #else
        XCTAssertTrue(helpStep.localizedCaseInsensitiveContains("Click"))
        #endif
    }
}
