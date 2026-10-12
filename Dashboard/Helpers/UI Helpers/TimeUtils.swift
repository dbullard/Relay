
import Foundation

public enum TimeUtils {
    public static let chicago = TimeZone(identifier: "America/Chicago")!

    public static func parseISOZ(_ s: String?) -> Date? {
        guard var s = s else { return nil }
        if s.hasSuffix("Z") { s = s.replacingOccurrences(of: "Z", with: "+00:00") }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s.replacingOccurrences(of: "+00:00", with: "Z"))
    }

    public static func toChicagoHM(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = chicago
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
