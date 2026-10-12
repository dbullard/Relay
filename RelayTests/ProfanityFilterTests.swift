import XCTest
@testable import Relay

final class ProfanityFilterTests: XCTestCase {

    private func mask(_ text: String, custom: [String] = [], includeDefault: Bool = true) -> String {
        ProfanityFilter(settings: .init(mode: .mask, includeDefaultList: includeDefault, customBlockedWords: custom))
            .apply(to: text)
    }

    private func remove(_ text: String) -> String {
        ProfanityFilter(settings: .init(mode: .remove)).apply(to: text)
    }

    // MARK: - Word forms

    func testMasksInflectedAndCompoundForms() {
        let words = [
            "fucking", "fucked", "fucker", "motherfucker", "shitty", "bullshit", "horseshit",
            "damned", "damning", "goddamn", "goddamnit", "bitches", "bitchy", "assholes",
            "dumbass", "jackass", "asses", "pissed", "pissing", "bastards", "dickhead",
            "hellish", "crappy", "whores", "sluts", "cocksucker", "arsehole", "douchebag"
        ]
        for word in words {
            let result = mask("that was \(word) today")
            XCTAssertFalse(result.lowercased().contains(word), "\(word) leaked: \(result)")
            XCTAssertTrue(result.contains("•"), "\(word) was not masked: \(result)")
        }
    }

    func testMasksBaseWordsCaseInsensitivelyWithPunctuation() {
        XCTAssertEqual(mask("Holy SHIT!"), "Holy ••••!")
        XCTAssertEqual(mask("what the fuck."), "what the ••••.")
        XCTAssertEqual(mask("Damn, it's hell's kitchen"), "••••, it's ••••'s kitchen")
    }

    func testMasksWholeInflectedWordLength() {
        XCTAssertEqual(mask("fucking"), "•••••••")
    }

    // MARK: - No false positives

    func testDoesNotMaskInnocentWords() {
        let clean = [
            "hello", "shell", "shellfish", "class", "pass", "passion", "assembly", "assist",
            "assure", "Scripture", "grace", "damnation", "Shittim wood", "Scunthorpe",
            "Dickens", "peacock", "cockpit", "scrap", "analysis", "Cassandra", "bass", "mass",
            "therapist", "Hellenistic", "Thessalonians", "document", "cocktail"
        ]
        for word in clean {
            XCTAssertEqual(mask("we read \(word) today"), "we read \(word) today", "\(word) was wrongly masked")
        }
    }

    // MARK: - Modes and settings

    func testRemoveModeDropsWordsAndCollapsesSpaces() {
        XCTAssertEqual(remove("what the fucking hell is this"), "what the is this")
        XCTAssertEqual(remove("shit"), "")
    }

    func testOffModeIsPassThrough() {
        let filter = ProfanityFilter(settings: .init(mode: .off))
        XCTAssertEqual(filter.apply(to: "fuck shit damn"), "fuck shit damn")
    }

    func testCustomWordsAreMatchedAsWholeWordsAndPhrases() {
        XCTAssertEqual(mask("darn it and heck", custom: ["darn", "heck"], includeDefault: false), "•••• it and ••••")
        XCTAssertEqual(mask("oh my word", custom: ["my word"], includeDefault: false), "oh •••••••")
        XCTAssertEqual(mask("darning socks", custom: ["darn"], includeDefault: false), "darning socks")
    }

    func testDefaultListCanBeDisabled() {
        XCTAssertEqual(mask("what the fuck", includeDefault: false), "what the fuck")
    }

    // MARK: - Pre-censored text from the recognizer

    func testMasksAsteriskCensoredProfanity() {
        XCTAssertEqual(mask("what the f***ing hell"), "what the ••••••• ••••")
        XCTAssertEqual(mask("oh sh*t"), "oh ••••")
        XCTAssertEqual(mask("s***"), "••••")
        XCTAssertEqual(mask("f**k this"), "•••• this")
        XCTAssertEqual(mask("you b*tch."), "you •••••.")
        XCTAssertEqual(mask("a**hole"), "•••••••")
        XCTAssertEqual(mask("motherf*****"), "••••••••••••")
        XCTAssertEqual(mask("F***ING"), "•••••••")
    }

    func testRemovesAsteriskCensoredProfanity() {
        XCTAssertEqual(remove("what the f***ing hell is this"), "what the is this")
        XCTAssertEqual(remove("oh sh*t, really"), "oh, really")
    }

    func testLeavesOrdinaryAsterisksAlone() {
        for text in ["*hello*", "5 * 3", "see note* below", "God* is good", "**", "a * b", "pass* the plate"] {
            XCTAssertEqual(mask(text), text, "\(text) was wrongly masked")
        }
    }

    func testCensoredMatchingHonorsSettings() {
        XCTAssertEqual(mask("oh sh*t", includeDefault: false), "oh sh*t")
        XCTAssertEqual(ProfanityFilter(settings: .init(mode: .off)).apply(to: "oh sh*t"), "oh sh*t")
        XCTAssertEqual(mask("oh d*rn", custom: ["darn"], includeDefault: false), "oh ••••")
    }
}
