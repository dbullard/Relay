import XCTest
@testable import Relay

/// What's New showed the old paid app's 1.x notes in the open-source build, which has no
/// Relay server. It now reads the GitHub releases; these pin how release notes become rows.
final class WhatsNewGitHubReleasesTests: XCTestCase {
    private let sample = #"""
    [
      {"tag_name": "v2.1.0", "published_at": "2026-11-24T14:40:00Z", "draft": false, "prerelease": false,
       "body": "## Relay 2.1.0\n\nIntro paragraph.\n\n### You can trust what's on screen\n- **Stale and offline tiles are marked.** Tiles dim and show a badge.\n- A double-tap no longer exits Live Mode.\n\nRequires macOS 15.6 or later.\n"},
      {"tag_name": "v2.2.0-beta", "published_at": "2026-11-25T00:00:00Z", "draft": false, "prerelease": true, "body": "- Beta"},
      {"tag_name": "v2.3.0", "published_at": null, "draft": true, "prerelease": false, "body": "- Draft"},
      {"tag_name": "v2.0.6", "published_at": "2026-11-19T02:40:13Z", "draft": false, "prerelease": false,
       "body": "- **Every tab fits in the canvas tab bar.** The bar now grows."}
    ]
    """#

    func testPublishedReleasesBecomeTheFeedNewestFirst() throws {
        let feed = try WhatsNewGitHubReleases.feed(fromReleasesJSON: Data(sample.utf8))
        XCTAssertEqual(feed.releases.map(\.version), ["2.1.0", "2.0.6"])
        XCTAssertEqual(feed.releases.first?.date, "2026-11-24T14:40:00Z")
    }

    func testBulletsBecomeFeaturesWithBoldLeadInAsTitle() throws {
        let feed = try WhatsNewGitHubReleases.feed(fromReleasesJSON: Data(sample.utf8))
        let features = try XCTUnwrap(feed.releases.first?.features)
        XCTAssertEqual(features.count, 2, "Headings and paragraphs are not features")
        XCTAssertEqual(features[0].title, "Stale and offline tiles are marked")
        XCTAssertEqual(features[0].description, "Tiles dim and show a badge.")
        XCTAssertEqual(features[1].title, "A double-tap no longer exits Live Mode.")
        XCTAssertEqual(features[1].description, "")
    }

    func testTagPrefixIsDropped() {
        XCTAssertEqual(WhatsNewGitHubReleases.versionString(fromTag: "v2.1.0"), "2.1.0")
        XCTAssertEqual(WhatsNewGitHubReleases.versionString(fromTag: "2.1.0"), "2.1.0")
    }

    func testBoldPhraseRunningIntoTheSentenceGetsACleanDescription() {
        let comma = WhatsNewGitHubReleases.splitBoldLeadIn("**\"Saved\" only appears when a save worked**, and a failed quick save tells you.")
        XCTAssertEqual(comma.title, "\"Saved\" only appears when a save worked")
        XCTAssertEqual(comma.description, "And a failed quick save tells you.")

        let colon = WhatsNewGitHubReleases.splitBoldLeadIn("**Automation:** delete a single wire.")
        XCTAssertEqual(colon.title, "Automation")
        XCTAssertEqual(colon.description, "Delete a single wire.")
    }

    func testBoldTextNotAtTheStartIsKeptInTheTitle() {
        let split = WhatsNewGitHubReleases.splitBoldLeadIn("Show Guides is now **⌘'**.")
        XCTAssertEqual(split.title, "Show Guides is now **⌘'**.")
        XCTAssertEqual(split.description, "")
    }

    func testReleaseLinksToItsGitHubNotes() {
        let release = WhatsNewRelease(version: "2.1.0", date: "", features: [])
        XCTAssertEqual(release.notesURL?.absoluteString, "https://github.com/dbullard/Relay/releases/tag/v2.1.0")
        let tagged = WhatsNewRelease(version: "v2.0", date: "", features: [])
        XCTAssertEqual(tagged.notesURL?.absoluteString, "https://github.com/dbullard/Relay/releases/tag/v2.0")
    }
}
