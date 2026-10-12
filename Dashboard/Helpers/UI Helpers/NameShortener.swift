//
//  NameShortener.swift
//  PCODiGiCoApp
//
//  Created by David Bullard on 9/25/25.
//

import Foundation

/// Heuristic, "intelligent" shortener for snapshot names.
/// Goals:
///  - Only shorten if name.count > limit
///  - Prefer meaningful words; drop common stopwords
///  - Acronymize multi-word names where helpful
///  - Vowel-trim interior of long words (keep first & last)
///  - Ensure uniqueness with minimal numeric suffix if collisions occur
enum NameShortener {

    static let stopwords: Set<String> = [
        "the","a","an","and","or","of","for","to","in","on","at","with","by"
    ]

    /// Shorten a single name to at most `limit` characters.
    /// Does nothing if `name.count <= limit`.
    static func shorten(_ name: String, limit: Int = 20) -> String {
        guard name.count > limit, limit > 0 else { return name }

        // 1) Trim whitespace & collapse spaces
        let cleaned = name
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2) Split into tokens, drop stopwords (case-insensitive)
        let tokens = cleaned.split(separator: " ").map(String.init)
        let filtered = tokens.filter { !stopwords.contains($0.lowercased()) }

        // 3) If many tokens, try acronyms where useful
        if filtered.count >= 3 {
            // e.g., "Call To Worship Bridge" → "CTW Bridge"
            let head = filtered.dropLast()
            let tail = filtered.last!

            let headAcr = head.map { String($0.prefix(1)) }.joined()
            var candidate = headAcr + " " + tail
            candidate = candidate.replacingOccurrences(of: "  ", with: " ")

            if candidate.count <= limit {
                return candidate
            }
        }

        // 4) Greedy rebuild: keep important words, shorten long ones by vowel trimming
        var out = ""
        for (i, word) in (filtered.isEmpty ? tokens : filtered).enumerated() {
            var piece = (i == 0 ? "" : " ") + shortenWord(word, maxLen: max(3, limit)) // safe minimum
            if out.count + piece.count > limit {
                // try without space if it helps
                piece = shortenWord(word, maxLen: max(3, limit - out.count))
                if out.count + piece.count > limit { break }
            }
            out += piece
            if out.count == limit { break }
        }

        if out.isEmpty {
            // Fallback: brutal cut
            return String(cleaned.prefix(limit))
        }
        return out
    }

    /// For batches: shorten and guarantee uniqueness (by adding minimal numeric suffix).
    static func uniqueShorten(_ names: [String], limit: Int = 20) -> [String] {
        var result: [String] = []
        var seen: [String: Int] = [:]

        for name in names {
            let base = shorten(name, limit: limit)
            if base.count <= limit, seen[base] == nil {
                seen[base] = 1
                result.append(base)
                continue
            }

            // If collision or over limit, append minimal numeric suffix like " (2)", "(3)" …
            var idx = (seen[base] ?? 0) + 1
            while true {
                let candidate = base
                let suffix = "(\(idx))"
                let trimmed = candidate.count + suffix.count > limit
                    ? String(candidate.prefix(max(0, limit - suffix.count)))
                    : candidate
                let final = trimmed + suffix
                if seen[final] == nil {
                    seen[base] = idx
                    seen[final] = 1
                    result.append(final)
                    break
                }
                idx += 1
            }
        }
        return result
    }

    // MARK: - Helpers

    /// Shorten a single word by removing interior vowels until under maxLen (keep first & last char).
    private static func shortenWord(_ word: String, maxLen: Int) -> String {
        if word.count <= maxLen { return word }
        if maxLen < 3 { return String(word.prefix(maxLen)) }

        var chars = Array(word)
        let vowels = Set("aeiouAEIOU")
        var i = 1
        while chars.count > maxLen && i < chars.count - 1 {
            if vowels.contains(chars[i]) {
                chars.remove(at: i)
            } else {
                i += 1
            }
        }
        if chars.count > maxLen {
            // still too long, hard cut center
            return String(chars.prefix(maxLen))
        }
        return String(chars)
    }
}
