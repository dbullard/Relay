import Foundation

enum PairingInputSanitizer {
    static let maxPendingRequests = 5
    private static let maxNameLength = 40

    static func deviceName(_ raw: String) -> String {
        let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return "Unknown device" }
        return String(cleaned.prefix(maxNameLength))
    }
}
