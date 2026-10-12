//
//  DiGiCoRTFParser.swift
//  PCODiGiCoApp
//
//  Created by David Bullard on 9/29/25.
//


import Foundation

struct DiGiCoRTFParser {
    struct Channel: Hashable {
        let channel: Int       // DiGiCo channel number (e.g., 9)
        let stereo: Bool       // true if token had trailing 's' (e.g., "9s")
        let name: String       // Channel label text
        var inputs: [Int] { stereo ? [channel, channel + 1] : [channel] }
    }

    private static let startRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(?:\\ul\b[^\r\n\\]*Input Channels[^\r\n\\]*\\par)"#,
        options: [.caseInsensitive]
    )

    private static let endRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(?:\\ul\b[^\r\n\\]*(?:Aux Outputs|Group Outputs|Matrix Inputs|Matrix Outputs|Control Groups|Talkback Input))"#,
        options: [.caseInsensitive]
    )

    private static let rowRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(?m)^\s*(\d{1,3})(s)?\\tab\s*([^\r\n\\]+?)\\tab"#,
        options: []
    )

    /// Parse the DiGiCo RTF dump into channel entries (channel number, stereo, name).
    /// This looks for rows like:  `<digits>[s]\tab <name>\tab`
    static func parseChannels(from rtf: String) -> [Channel] {
        // 1) Narrow to "Input Channels" section if we can (between underlined headers)
        let full = NSRange(rtf.startIndex..<rtf.endIndex, in: rtf)
        let startMatch = startRegex.firstMatch(in: rtf, range: full)
        let endMatch   = endRegex.firstMatch(in: rtf, range: full)

        let startIdx = startMatch.map { Range($0.range, in: rtf)!.upperBound } ?? rtf.startIndex
        let endIdx   = endMatch.map { Range($0.range, in: rtf)!.lowerBound } ?? rtf.endIndex
        let section  = String(rtf[startIdx..<endIdx])

        // 2) Row regex:  beginning of line, <digits>[s] \tab <name> \tab
        // Multiline mode so ^ anchors to line-start in the section.
        let secRange = NSRange(section.startIndex..<section.endIndex, in: section)

        var byChannel: [Int: Channel] = [:]
        rowRegex.enumerateMatches(in: section, options: [], range: secRange) { m, _, _ in
            guard let m else { return }
            guard m.numberOfRanges >= 4 else { return }
            guard
                let chRange = Range(m.range(at: 1), in: section),
                let nameRange = Range(m.range(at: 3), in: section)
            else { return }

            let ch = Int(section[chRange]) ?? 0
            if ch <= 0 { return }
            let stereo = m.range(at: 2).location != NSNotFound
            let name = String(section[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.lowercased() != "name" else { return }

            // Keep the first row for a channel; DiGiCo often prints continuation rows after
            if byChannel[ch] == nil {
                byChannel[ch] = Channel(channel: ch, stereo: stereo, name: name)
            }
        }

        // Sort by channel
        return byChannel.values.sorted { $0.channel < $1.channel }
    }

    /// Convenience to load a .rtf file and parse.
    static func parseRTFFile(at url: URL) throws -> [Channel] {
        // Some DiGiCo RTF exports are Windows-1252; try UTF-8 first, then fallback.
        if let data = try? Data(contentsOf: url) {
            if let s = String(data: data, encoding: .utf8) {
                return parseChannels(from: s)
            }
            if let s = String(data: data, encoding: .windowsCP1252) ??
                       String(data: data, encoding: .isoLatin1) {
                return parseChannels(from: s)
            }
            // As a last resort, force raw
            let s = String(decoding: data, as: UTF8.self)
            return parseChannels(from: s)
        } else {
            // Fallback path via String init
            let s = try String(contentsOf: url, encoding: .utf8)
            return parseChannels(from: s)
        }
    }
}