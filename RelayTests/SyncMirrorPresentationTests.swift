import XCTest
import SwiftUI
@testable import Relay

final class SyncMirrorPresentationTests: XCTestCase {

    func testBadgeStateOwner() {
        let state = SyncMirrorPresentation.syncBadgeState(isOwner: true, isOrphaned: false, isStale: false)
        XCTAssertEqual(state, .owner)
    }

    func testBadgeStateSubscriber() {
        let state = SyncMirrorPresentation.syncBadgeState(isOwner: false, isOrphaned: false, isStale: false)
        XCTAssertEqual(state, .subscriber)
    }

    func testBadgeStateOrphanedTakesPriorityOverStale() {
        // A tab can be both orphaned and unverified at once; orphaned (actively broken)
        // must win over stale (merely unconfirmed) so the red state always surfaces.
        let state = SyncMirrorPresentation.syncBadgeState(isOwner: true, isOrphaned: true, isStale: true)
        XCTAssertEqual(state, .orphaned)
    }

    func testBadgeStateStaleWhenNotOrphaned() {
        let state = SyncMirrorPresentation.syncBadgeState(isOwner: false, isOrphaned: false, isStale: true)
        XCTAssertEqual(state, .stale)
    }

    func testIconNameForSubscriberIsLink() {
        XCTAssertEqual(SyncMirrorPresentation.syncIconName(isSubscriber: true), "link")
    }

    func testIconNameForOwnerIsArrowPath() {
        XCTAssertEqual(SyncMirrorPresentation.syncIconName(isSubscriber: false), "arrow.triangle.2.circlepath")
    }

    func testIconNameForOrphanedSubscriberStillShowsLink() {
        // Orphaned/stale only affect color (via syncBadgeColor); a subscriber tab that
        // goes orphaned must still show the "link" glyph, not switch to the owner glyph.
        XCTAssertEqual(SyncMirrorPresentation.syncIconName(isSubscriber: true), "link")
        let state = SyncMirrorPresentation.syncBadgeState(isOwner: false, isOrphaned: true, isStale: false)
        XCTAssertEqual(state, .orphaned)
    }

    func testIconNameForStaleOwnerStillShowsArrowPath() {
        XCTAssertEqual(SyncMirrorPresentation.syncIconName(isSubscriber: false), "arrow.triangle.2.circlepath")
        let state = SyncMirrorPresentation.syncBadgeState(isOwner: true, isOrphaned: false, isStale: true)
        XCTAssertEqual(state, .stale)
    }

    func testSyncBadgeColorOrphanedIsRed() {
        let color = SyncMirrorPresentation.syncBadgeColor(for: .orphaned, toolbarForeground: .white, isSelected: true)
        XCTAssertEqual(color, .red)
    }

    func testSyncBadgeColorStaleUsesDimmedToolbarForeground() {
        let color = SyncMirrorPresentation.syncBadgeColor(for: .stale, toolbarForeground: .white, isSelected: true)
        XCTAssertEqual(color, Color.white.opacity(0.35))
    }

    func testSyncBadgeColorOwnerAndSubscriberBothUseSyncColor() {
        let ownerColor = SyncMirrorPresentation.syncBadgeColor(for: .owner, toolbarForeground: .white, isSelected: false)
        let subscriberColor = SyncMirrorPresentation.syncBadgeColor(for: .subscriber, toolbarForeground: .white, isSelected: false)
        XCTAssertEqual(ownerColor, SyncMirrorPresentation.syncColor.opacity(0.75))
        XCTAssertEqual(subscriberColor, SyncMirrorPresentation.syncColor.opacity(0.75))
    }

    func testMirrorBadgeColorReflectsSelection() {
        XCTAssertEqual(SyncMirrorPresentation.mirrorBadgeColor(isSelected: true), SyncMirrorPresentation.mirrorColor.opacity(1.0))
        XCTAssertEqual(SyncMirrorPresentation.mirrorBadgeColor(isSelected: false), SyncMirrorPresentation.mirrorColor.opacity(0.75))
    }
}
