import XCTest
@testable import Relay

final class TranscriptTextFilterTests: XCTestCase {

    private func filter(
        _ replacements: [(String, String)],
        profanity: LiveTranscriptionProfanitySettings = .init()
    ) -> TranscriptTextFilter {
        TranscriptTextFilter(
            wordFilters: replacements.map { WordReplacementFilter(from: $0.0, to: $0.1) },
            profanitySettings: profanity
        )
    }

    // MARK: - Word replacement

    func testReplacesWholeWordsCaseInsensitively() {
        let f = filter([("pro presenter", "ProPresenter"), ("relay", "Relay")])
        XCTAssertEqual(f.apply(to: "open Pro Presenter and relay"), "open ProPresenter and Relay")
    }

    func testDoesNotReplaceInsideLongerWords() {
        let f = filter([("art", "ART")])
        XCTAssertEqual(f.apply(to: "start the art show"), "start the ART show")
    }

    func testReplacementTextIsLiteral() {
        // "$1" and "\" are regex template syntax; a replacement must not interpret them.
        XCTAssertEqual(filter([("five dollars", "$5")]).apply(to: "five dollars"), "$5")
        XCTAssertEqual(filter([("backslash", "\\")]).apply(to: "a backslash"), "a \\")
        XCTAssertEqual(filter([("ticket", "$0$1")]).apply(to: "ticket"), "$0$1")
    }

    func testReplacementPhraseWithPunctuationMatches() {
        XCTAssertEqual(filter([("c++", "C++")]).apply(to: "we use c++ here"), "we use C++ here")
    }

    func testEmptyReplacementSourceIsIgnored() {
        XCTAssertEqual(filter([("  ", "x")]).apply(to: "hello"), "hello")
    }

    // MARK: - Ordering with profanity

    func testReplacementRunsBeforeProfanityFilter() {
        let f = filter([("shit", "shoot")], profanity: .init(mode: .mask))
        XCTAssertEqual(f.apply(to: "oh shit"), "oh shoot")
    }

    func testReplacementCannotIntroduceUnfilteredProfanity() {
        let f = filter([("darn", "damn")], profanity: .init(mode: .mask))
        XCTAssertEqual(f.apply(to: "darn it"), "•••• it")
    }

    func testPassthroughLeavesTextUnchanged() {
        XCTAssertEqual(TranscriptTextFilter.passthrough.apply(to: "oh shit"), "oh shit")
    }

    // MARK: - Custom blocked words

    func testCustomBlockedWordWithPunctuationIsMasked() {
        let f = filter([], profanity: .init(mode: .mask, includeDefaultList: false, customBlockedWords: ["a$$"]))
        XCTAssertEqual(f.apply(to: "what an a$$ move"), "what an ••• move")
    }

    func testCustomBlockedWordStillRequiresWholeWord() {
        let f = filter([], profanity: .init(mode: .mask, includeDefaultList: false, customBlockedWords: ["heck"]))
        XCTAssertEqual(f.apply(to: "heck, check the deck"), "••••, check the deck")
    }

    // MARK: - Phrase matcher

    func testWholeWordPatternMatchesOnlyWholeWords() throws {
        let regex = try NSRegularExpression(pattern: TranscriptPhraseMatcher.wholeWordPattern(for: "go"))
        let count: (String) -> Int = { regex.numberOfMatches(in: $0, range: NSRange($0.startIndex..., in: $0)) }
        XCTAssertEqual(count("go, go! going ago"), 2)
        XCTAssertEqual(count("let's go."), 1)
    }

    func testContainsWordSequenceIsWordLevel() {
        XCTAssertTrue(TranscriptPhraseMatcher.containsWordSequence("let's go now", "go now"))
        XCTAssertTrue(TranscriptPhraseMatcher.containsWordSequence("go", "go"))
        XCTAssertFalse(TranscriptPhraseMatcher.containsWordSequence("i know", "no"))
        XCTAssertFalse(TranscriptPhraseMatcher.containsWordSequence("rescue the cue", "the rescue"))
        XCTAssertFalse(TranscriptPhraseMatcher.containsWordSequence("", "no"))
    }
}
