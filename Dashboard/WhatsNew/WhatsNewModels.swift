import Foundation

struct WhatsNewFeature: Codable, Equatable {
    let icon: String
    let iconColor: String
    let title: String
    let description: String
}

struct WhatsNewRelease: Codable, Equatable {
    let version: String
    let date: String
    let features: [WhatsNewFeature]
}

struct WhatsNewFeed: Codable, Equatable {
    let releases: [WhatsNewRelease]
}

extension WhatsNewRelease {
    /// Formats `date` for display. Accepts a plain "yyyy-MM-dd" string or a full ISO 8601
    /// timestamp (with or without fractional seconds) — the server accepts either — and
    /// renders it as a locale-appropriate long date. Falls back to the raw string if it
    /// can't be parsed, so an unexpected format degrades gracefully instead of showing nothing.
    var formattedDate: String {
        guard let parsed = Self.parseDate(date) else { return date }
        return Self.displayFormatter.string(from: parsed)
    }

    private static func parseDate(_ raw: String) -> Date? {
        isoWithFractionalSeconds.date(from: raw)
            ?? isoFormatter.date(from: raw)
            ?? plainDateFormatter.date(from: raw)
    }

    private static let plainDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

extension String {
    /// Compares dotted version strings numerically, so "2.10.0" is newer than "2.9.0"
    /// (plain lexicographic comparison would get this wrong).
    func isNewerRelayVersion(than other: String) -> Bool {
        compare(other, options: .numeric) == .orderedDescending
    }
}

/// Parses a "#RRGGBB" or "RRGGBB" hex string into 0-1 RGB components. Returns nil for invalid input.
func relayHexColorComponents(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if sanitized.hasPrefix("#") { sanitized.removeFirst() }
    guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
    let red = Double((value >> 16) & 0xFF) / 255
    let green = Double((value >> 8) & 0xFF) / 255
    let blue = Double(value & 0xFF) / 255
    return (red, green, blue)
}
