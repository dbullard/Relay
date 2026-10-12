import Foundation

/// Shared formatting for frequency/level cursor readouts on the RTA and Spectrograph tiles.
enum AudioReadoutFormatting {
    static func formatHz(_ hz: Double) -> String {
        if hz >= 1000 {
            let khz = hz / 1000
            let decimals = khz < 10 ? 1 : 0
            return String(format: "%.\(decimals)f kHz", khz)
        }
        return "\(Int(hz.rounded())) Hz"
    }

    static func formatDb(_ db: Double) -> String {
        String(format: "%.1f dB", db)
    }
}
