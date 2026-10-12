import Foundation

// MARK: - Profanity Filter

/// Masks or removes profanity from transcript text.
///
/// The built-in list has two tiers so inflections and compounds are caught without
/// false positives on innocent words ("class", "hello", "damnation"):
/// - `embeddedStems` match anywhere inside a word, so "fuck" also catches
///   "motherfucker" and "shitty". Only stems that never occur in ordinary words belong here.
/// - `wholeWords` match as complete words, optionally followed by a plain suffix
///   ("damn" → "damned", "ass" → "asses"), but never inside a longer word.
///
/// A matched word is replaced in full, so masking "fucking" yields seven bullets, not four.
///
/// Speech engines sometimes censor profanity themselves ("f***ing", "sh*t"). Those tokens
/// no longer contain the letters the regex needs, so they are matched separately: each `*`
/// stands for exactly one hidden letter and the token is compared against the same word lists.
nonisolated struct ProfanityFilter {
    private static let embeddedStems: [String] = [
        "fuck", "shit", "cunt", "bitch", "bastard", "whore", "slut", "douche",
        "asshole", "asswipe", "asshat", "assclown", "arsehole",
        "jackass", "dumbass", "badass", "smartass", "fatass", "kickass",
        "dickhead", "cocksuck", "blowjob", "faggot", "goddam"
    ]

    private static let wholeWords: [String] = [
        "damn", "dammit", "damnit",
        "hell", "hellish", "hellhole",
        "crap", "crappy", "crapped", "crapping", "crapper", "bullcrap",
        "piss", "pisser",
        "ass", "arse", "dick", "tits", "titty", "titties", "twat", "pussy", "pussies",
        "wank", "wanker", "bollock", "bugger", "turd", "skank", "dildo", "jizz",
        "fag", "retard", "nigger", "nigga",
        "wtf", "stfu", "omfg"
    ]

    /// Suffixes accepted after a `wholeWords` entry. Kept short on purpose: "er" would
    /// turn "dick" into the innocent "dicker".
    private static let wholeWordSuffixes = "(?:s|es|ed|ing)?"

    /// Words the embedded stems would otherwise catch but that are legitimate,
    /// including scripture ("Shittim wood", Exodus 25).
    private static let allowedWords: Set<String> = ["shittim", "shittah", "scunthorpe"]

    private static let builtInPattern: String = {
        let embedded = embeddedStems.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let whole = wholeWords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return "\\b\\p{L}*(?:\(embedded))\\p{L}*\\b|\\b(?:\(whole))\(wholeWordSuffixes)\\b"
    }()

    /// A token containing at least one `*`, such as "f***ing" or "sh*t".
    private static let censoredTokenRegex = try? NSRegularExpression(
        pattern: "(?<![\\p{L}*])[\\p{L}*]*\\*[\\p{L}*]*(?![\\p{L}*])"
    )

    private static let builtInCensoredEmbedded: [[Character]] = embeddedStems.map { Array($0) }

    private static let builtInCensoredWhole: [[Character]] = wholeWords.flatMap { word in
        ["", "s", "es", "ed", "ing"].map { Array(word + $0) }
    }

    let settings: LiveTranscriptionProfanitySettings
    private let regex: NSRegularExpression?
    private let mode: LiveTranscriptionProfanityMode
    private let censoredWhole: [[Character]]
    private let censoredEmbedded: [[Character]]

    init(settings: LiveTranscriptionProfanitySettings) {
        self.settings = settings
        self.mode = settings.mode

        guard settings.mode != .off else {
            self.regex = nil
            self.censoredWhole = []
            self.censoredEmbedded = []
            return
        }

        var alternatives: [String] = []
        var censoredWhole: [[Character]] = []
        var censoredEmbedded: [[Character]] = []
        if settings.includeDefaultList {
            alternatives.append(Self.builtInPattern)
            censoredWhole = Self.builtInCensoredWhole
            censoredEmbedded = Self.builtInCensoredEmbedded
        }

        let customWords = settings.customBlockedWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if !customWords.isEmpty {
            let escaped = customWords.map { NSRegularExpression.escapedPattern(for: $0) }
            alternatives.append("\\b(?:" + escaped.joined(separator: "|") + ")\\b")
            // A censored token is a single word, so multi-word phrases can't match it.
            censoredWhole += customWords.filter { !$0.contains(" ") }.map { Array($0) }
        }
        self.censoredWhole = censoredWhole
        self.censoredEmbedded = censoredEmbedded

        if alternatives.isEmpty {
            self.regex = nil
        } else {
            self.regex = try? NSRegularExpression(
                pattern: alternatives.joined(separator: "|"),
                options: [.caseInsensitive]
            )
        }
    }

    func apply(to text: String) -> String {
        guard mode != .off, let regex else { return text }

        var output = text
        var didReplace = false

        // Censored tokens go first: the main regex would otherwise match the plain-letter
        // fragment of a token like "fuck*" and leave the asterisk behind.
        if text.contains("*"), let censoredTokenRegex = Self.censoredTokenRegex {
            didReplace = replaceMatches(of: censoredTokenRegex, in: &output, where: isCensoredProfanity)
        }
        if replaceMatches(of: regex, in: &output, where: { !Self.allowedWords.contains($0.lowercased()) }) {
            didReplace = true
        }

        guard didReplace, mode == .remove else { return output }
        return Self.tidyAfterRemoval(output)
    }

    /// Masks or removes each match of `regex` that `isProfane` accepts. Returns whether anything changed.
    private func replaceMatches(
        of regex: NSRegularExpression,
        in text: inout String,
        where isProfane: (String) -> Bool
    ) -> Bool {
        let source = text
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var didReplace = false
        // Replace back-to-front so earlier match ranges stay valid.
        for match in regex.matches(in: source, range: range).reversed() {
            guard let r = Range(match.range, in: text), isProfane(String(text[r])) else { continue }
            let replacement = mode == .mask ? String(repeating: "•", count: max(1, text[r].count)) : ""
            text.replaceSubrange(r, with: replacement)
            didReplace = true
        }
        return didReplace
    }

    /// Whether `token` (which contains a `*`) is a blocked word with some letters hidden.
    private func isCensoredProfanity(_ token: String) -> Bool {
        let chars = Array(token.lowercased())
        // "***" alone is punctuation, not a censored word.
        guard chars.contains(where: { $0 != "*" }) else { return false }
        return censoredWhole.contains { Self.equals(chars, $0) }
            || censoredEmbedded.contains { Self.contains(chars, $0) }
    }

    private static func equals(_ token: [Character], _ word: [Character]) -> Bool {
        token.count == word.count && matches(token[...], word)
    }

    private static func contains(_ token: [Character], _ stem: [Character]) -> Bool {
        guard token.count >= stem.count else { return false }
        return (0...(token.count - stem.count)).contains { start in
            matches(token[start..<(start + stem.count)], stem)
        }
    }

    /// Compares position by position, treating `*` in the token as any single letter.
    private static func matches(_ token: ArraySlice<Character>, _ word: [Character]) -> Bool {
        zip(token, word).allSatisfy { $0 == "*" || $0 == $1 }
    }

    /// Removing a word leaves doubled spaces and stranded spaces before punctuation.
    private static func tidyAfterRemoval(_ text: String) -> String {
        text
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
