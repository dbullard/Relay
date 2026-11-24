import Foundation

/// Builds the What's New feed from the GitHub releases of this repository, the same releases
/// in-app updates come from. Each release's notes become its feature list: one row per
/// bullet, with a bold lead-in ("- **Title.** More text") as the row's title.
enum WhatsNewGitHubReleases {
    static let releasesURL = URL(string: "https://api.github.com/repos/dbullard/Relay/releases?per_page=15")!

    private struct Release: Decodable {
        let tagName: String
        let publishedAt: String?
        let body: String?
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case publishedAt = "published_at"
            case body, draft, prerelease
        }
    }

    static let featureIcon = "sparkles"
    static let featureIconColor = "#5E5CE6"

    /// Parses the GitHub "list releases" response. Drafts and pre-releases are skipped.
    static func feed(fromReleasesJSON data: Data) throws -> WhatsNewFeed {
        let releases = try JSONDecoder().decode([Release].self, from: data)
        let mapped = releases
            .filter { !$0.draft && !$0.prerelease }
            .compactMap { release -> WhatsNewRelease? in
                let version = versionString(fromTag: release.tagName)
                guard !version.isEmpty else { return nil }
                return WhatsNewRelease(
                    version: version,
                    date: release.publishedAt ?? "",
                    features: features(fromNotes: release.body ?? "")
                )
            }
        return WhatsNewFeed(releases: mapped)
    }

    /// "v2.1.0" → "2.1.0".
    static func versionString(fromTag tag: String) -> String {
        var trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        return trimmed
    }

    /// One feature per Markdown bullet. Headings and paragraphs are skipped.
    static func features(fromNotes notes: String) -> [WhatsNewFeature] {
        notes.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
            let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let (title, description) = splitBoldLeadIn(text)
            return WhatsNewFeature(
                icon: featureIcon,
                iconColor: featureIconColor,
                title: title,
                description: description
            )
        }
    }

    /// "**No more repeats.** When the recognizer…" → ("No more repeats", "When the recognizer…").
    /// A bullet without a bold lead-in becomes a title on its own.
    static func splitBoldLeadIn(_ text: String) -> (title: String, description: String) {
        guard text.hasPrefix("**"),
              let closing = text.range(of: "**", range: text.index(text.startIndex, offsetBy: 2)..<text.endIndex)
        else {
            return (text, "")
        }
        var title = String(text[text.index(text.startIndex, offsetBy: 2)..<closing.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        while let last = title.last, ".:".contains(last) { title.removeLast() }
        // The bold phrase may run straight into the sentence ("**Cancel works**, even …"):
        // drop the joining punctuation and start the description with a capital.
        var description = String(text[closing.upperBound...])
        while let first = description.first, ",;:—– ".contains(first) { description.removeFirst() }
        if let first = description.first, first.isLowercase {
            description = first.uppercased() + description.dropFirst()
        }
        return (title, description.trimmingCharacters(in: .whitespaces))
    }
}
