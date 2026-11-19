import XCTest
@testable import Relay

/// The speech recognizer's text is cumulative for the life of a task: every result repeats
/// everything heard since the task started. Lines already shown must be stripped from it,
/// even when the recognizer revises words it already sent.
final class TranscriptCommittedPrefixTests: XCTestCase {
    private func remainder(_ text: String, committed: String) -> String? {
        TranscriptCommittedPrefix.remainder(of: text, committed: committed)
    }

    func testNewWordsAfterCommittedTextAreKeptWithTheirCase() {
        XCTAssertEqual(
            remainder("Hey Davis hey Davis hey David we got it Bob", committed: "Hey Davis hey Davis hey David"),
            "we got it Bob"
        )
    }

    func testSingleNewWordIsNotReplacedByTheWholeTask() {
        // Tonight's "…on the board here earlier" line repeated the whole task for one new word.
        XCTAssertEqual(
            remainder(
                "Hey Davis hey Davis hey David we got it Bob had it muted on the board here earlier",
                committed: "Hey Davis hey Davis hey David we got it Bob had it muted on the board here"
            ),
            "earlier"
        )
    }

    func testRevisedLastWordOnlyRepeatsTheRevision() {
        XCTAssertEqual(
            remainder(
                "Hey Davis hey David we got it muted on the board here sorry for Bob's fault",
                committed: "Hey Davis hey David we got it muted on the board here earlier"
            ),
            "sorry for Bob's fault"
        )
    }

    func testRevisedWordsDeepInTheTaskRepeatAtMostTheRevisionWindow() {
        let committed = (1...30).map { "w\($0)" }.joined(separator: " ")
        var revised = (1...30).map { "w\($0)" }
        revised[9] = "changed"
        let text = (revised + ["new"]).joined(separator: " ")
        XCTAssertEqual(remainder(text, committed: committed), "new")
    }

    func testDroppedWordDoesNotReShowTheWordsAfterIt() {
        XCTAssertEqual(remainder("we got it had it", committed: "we got it Bob had it"), "")
        XCTAssertEqual(
            remainder("we got it had it on the board", committed: "we got it Bob had it"),
            "on the board"
        )
    }

    func testIdenticalTextHasNothingNew() {
        XCTAssertEqual(remainder("we got it Bob", committed: "We got it bob"), "")
    }

    func testShorterRevisionHasNothingNew() {
        XCTAssertEqual(remainder("we got it", committed: "we got it Bob"), "")
    }

    func testCommittedTextMatchesWholeWordsOnly() {
        // A character prefix would turn "hereafter" into "after".
        XCTAssertNil(remainder("hereafter", committed: "here"))
    }

    func testUnrelatedTextIsLeftToTheCaller() {
        XCTAssertNil(remainder("stand by for walk in", committed: "we got it Bob had it muted"))
        XCTAssertNil(remainder("hey there", committed: "hey david"))
        XCTAssertNil(remainder("anything", committed: ""))
    }

    /// Replays the recognizer results behind the 2026-11-18 comms transcript, where one
    /// recognizer task stayed open from 18:40 to 18:54 and each re-sent line fired the
    /// "David"/"Davis" automations again. The committed text is the task's text at each flush.
    func testCommsTranscriptReplayShowsEachWordOnce() {
        let results = [
            "Hey Davis",
            "Hey Davis hey Davis",
            "Hey Davis hey Davis hey David",
            "Hey Davis hey Davis hey David we got it Bob had it muted on the board here",
            "Hey Davis hey Davis hey David we got it Bob had it muted on the board here earlier",
            "Hey Davis hey Davis hey David we got it Bob had it muted on the board here sorry for Bob's fault",
            "Hey Davis hey Davis hey David we got it Bob had it muted on the board here sorry for Bob's fault it's bob",
            "Hey Davis hey Davis hey David we got it Bob had it muted on the board here sorry for Bob's fault Bob's fault",
        ]
        var committed = ""
        var lines: [String] = []
        for text in results {
            let line = committed.isEmpty ? text : remainder(text, committed: committed)
            lines.append(line ?? "<unaligned>")
            committed = text
        }
        XCTAssertEqual(lines, [
            "Hey Davis",
            "hey Davis",
            "hey David",
            "we got it Bob had it muted on the board here",
            "earlier",
            "sorry for Bob's fault",
            "it's bob",
            "Bob's fault",
        ])
        let nameMentions = lines.filter { $0.lowercased().contains("david") || $0.lowercased().contains("davis") }
        XCTAssertEqual(nameMentions.count, 3, "Only the three spoken calls should be able to fire name triggers")
    }
}
