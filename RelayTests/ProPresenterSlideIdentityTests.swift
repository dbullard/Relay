import XCTest
@testable import Relay

@MainActor
final class ProPresenterSlideIdentityTests: XCTestCase {

    func testDuplicateSlideTextDoesNotOverrideKnownCurrentIndex() {
        let ranges = [
            ProPresenterService.ProPresenterGroupRange(
                start: 1,
                end: 4,
                name: "Verse",
                color: nil,
                slideTexts: ["Alpha", "Repeat", "Bridge", "Repeat"],
                slideUUIDs: []
            )
        ]

        let resolved = ProPresenterService.ProPresenterSlideIdentity.resolvedCurrentSlideIndex(
            currentSlideIndex: 3,
            currentSlideText: "Repeat",
            preferredDisplayIndex: 2,
            ranges: ranges
        )

        XCTAssertEqual(resolved, 3)
    }

    func testBlankSlideKeepsKnownCurrentIndex() {
        let ranges = [
            ProPresenterService.ProPresenterGroupRange(
                start: 1,
                end: 4,
                name: "Verse",
                color: nil,
                slideTexts: ["Alpha", "", "Bridge", "Tag"],
                slideUUIDs: []
            )
        ]

        let resolved = ProPresenterService.ProPresenterSlideIdentity.resolvedBlankCurrentSlideIndex(
            currentSlideIndex: 1,
            nextSlideText: "Bridge",
            preferredDisplayIndex: nil,
            ranges: ranges
        )

        XCTAssertEqual(resolved, 1)
    }

    func testBlankSlideUsesNextSlideTextToResolveCurrentIndex() {
        let ranges = [
            ProPresenterService.ProPresenterGroupRange(
                start: 1,
                end: 4,
                name: "Verse",
                color: nil,
                slideTexts: ["Alpha", "", "Bridge", "Tag"],
                slideUUIDs: []
            )
        ]

        let resolved = ProPresenterService.ProPresenterSlideIdentity.resolvedBlankCurrentSlideIndex(
            currentSlideIndex: nil,
            nextSlideText: "Bridge",
            preferredDisplayIndex: nil,
            ranges: ranges
        )

        XCTAssertEqual(resolved, 1)
    }

    // Regression test: shouldRefreshGroupsSoon previously compared two values that were
    // always set together at the end of the previous poll cycle (lastGroupSlideIndex and
    // the cached status slideIndex), so it could never detect that the slide had actually
    // moved since then. That silently defeated the fast (0.5s) group refresh cadence and
    // left the group label stuck on stale data until the slow (5s) cadence caught up --
    // the "current slide group label stays on Verse 1" bug. The fix requires callers to
    // pass the index freshly fetched THIS cycle so a real change can be detected.
    func testShouldRefreshGroupsSoonDetectsSlideIndexChange() {
        let refreshed = ProPresenterService.ProPresenterSlideIdentity.shouldRefreshGroupsSoon(
            hasRanges: true,
            lastMatchedRawIndex: 3,
            currentRawIndex: 5,
            timeRefreshDue: false
        )
        XCTAssertTrue(refreshed)
    }

    func testShouldRefreshGroupsSoonDoesNotRefreshWhenIndexUnchanged() {
        let refreshed = ProPresenterService.ProPresenterSlideIdentity.shouldRefreshGroupsSoon(
            hasRanges: true,
            lastMatchedRawIndex: 3,
            currentRawIndex: 3,
            timeRefreshDue: false
        )
        XCTAssertFalse(refreshed)
    }

    func testShouldRefreshGroupsSoonRefreshesWhenRangesEmpty() {
        let refreshed = ProPresenterService.ProPresenterSlideIdentity.shouldRefreshGroupsSoon(
            hasRanges: false,
            lastMatchedRawIndex: nil,
            currentRawIndex: nil,
            timeRefreshDue: false
        )
        XCTAssertTrue(refreshed)
    }

    func testShouldRefreshGroupsSoonRefreshesWhenTimeIsDueRegardlessOfIndex() {
        let refreshed = ProPresenterService.ProPresenterSlideIdentity.shouldRefreshGroupsSoon(
            hasRanges: true,
            lastMatchedRawIndex: 3,
            currentRawIndex: 3,
            timeRefreshDue: true
        )
        XCTAssertTrue(refreshed)
    }

    func testBlankSlideWithoutReliableNextSlideTextDoesNotGuess() {
        let ranges = [
            ProPresenterService.ProPresenterGroupRange(
                start: 1,
                end: 4,
                name: "Verse",
                color: nil,
                slideTexts: ["Alpha", "", "Bridge", "Tag"],
                slideUUIDs: []
            )
        ]

        let resolved = ProPresenterService.ProPresenterSlideIdentity.resolvedBlankCurrentSlideIndex(
            currentSlideIndex: nil,
            nextSlideText: nil,
            preferredDisplayIndex: nil,
            ranges: ranges
        )

        XCTAssertNil(resolved)
    }
}
