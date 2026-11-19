import XCTest
@testable import Relay

/// The macOS top toolbar pill used to be hard-capped at 900pt. With a few tabs
/// the tab strip's ScrollView got only ~266pt of that, so the last tab was
/// clipped even in a wide window. The pill now grows to its content's ideal
/// width (so every tab fits) but never past the space the window offers.
final class DashboardToolbarPillWidthTests: XCTestCase {
    func testKeepsMinimumWidthWhenContentIsNarrow() {
        // One short tab: the pill keeps its familiar 900pt look.
        XCTAssertEqual(
            DashboardToolbarPillWidthLayout.resolvedWidth(available: 1438, idealContentWidth: 640, minWidth: 900),
            900
        )
    }

    func testGrowsToFitAllTabsWhenWindowHasRoom() {
        // Three tabs need more than 900pt; the window is wide enough to show them all.
        XCTAssertEqual(
            DashboardToolbarPillWidthLayout.resolvedWidth(available: 1438, idealContentWidth: 1010, minWidth: 900),
            1010
        )
    }

    func testNeverExceedsTheAvailableWidth() {
        // Many tabs in a narrow window: cap at the window so the tab strip scrolls instead.
        XCTAssertEqual(
            DashboardToolbarPillWidthLayout.resolvedWidth(available: 800, idealContentWidth: 1400, minWidth: 900),
            800
        )
    }

    func testUnspecifiedProposalReportsIdealWidth() {
        XCTAssertEqual(
            DashboardToolbarPillWidthLayout.resolvedWidth(available: nil, idealContentWidth: 1010, minWidth: 900),
            1010
        )
    }
}
