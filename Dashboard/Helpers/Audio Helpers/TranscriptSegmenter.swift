import Foundation

struct TranscriptSegmenterConfig {
    var silenceGapSeconds: Double = 1.5
    var maxLineAgeSeconds: Double = 6.0
    var minCharsForPunctuationFlush: Int = 24
    var maxChars: Int = 180
}

struct TranscriptSegmenterUpdate {
    enum Kind {
        case none
        case partial(String)
        case flush(String)
    }

    let kind: Kind
    let timestamp: Date
}

final class TranscriptSegmenter {
    private var currentText: String = ""
    private var currentNormalized: String = ""
    private var lastUpdate: Date?
    private var lineStart: Date?
    private let config: TranscriptSegmenterConfig

    init(config: TranscriptSegmenterConfig = TranscriptSegmenterConfig()) {
        self.config = config
    }

    func handleUpdate(text: String, isFinal: Bool, now: Date) -> TranscriptSegmenterUpdate {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(trimmed)
        if lineStart == nil {
            lineStart = now
        }
        if !isFinal, !normalized.isEmpty, normalized == currentNormalized {
            // Avoid resetting the silence timer when the recognizer repeats the same partial.
            return TranscriptSegmenterUpdate(kind: .none, timestamp: now)
        }
        lastUpdate = now
        currentText = trimmed
        currentNormalized = normalized

        guard !trimmed.isEmpty else {
            return TranscriptSegmenterUpdate(kind: .none, timestamp: now)
        }

        if isFinal {
            let flushed = flush(now: now)
            return TranscriptSegmenterUpdate(kind: .flush(flushed), timestamp: now)
        }

        if shouldFlushForPunctuation(text: trimmed) || shouldFlushForMaxChars(text: trimmed) || shouldFlushForMaxAge(now: now) {
            let flushed = flush(now: now)
            return TranscriptSegmenterUpdate(kind: .flush(flushed), timestamp: now)
        }

        return TranscriptSegmenterUpdate(kind: .partial(trimmed), timestamp: now)
    }

    func tick(now: Date) -> TranscriptSegmenterUpdate? {
        guard !currentText.isEmpty else { return nil }
        if shouldFlushForSilence(now: now) || shouldFlushForMaxAge(now: now) {
            let flushed = flush(now: now)
            return TranscriptSegmenterUpdate(kind: .flush(flushed), timestamp: now)
        }
        return nil
    }

    func forceFlush(now: Date) -> TranscriptSegmenterUpdate? {
        guard !currentText.isEmpty else { return nil }
        let flushed = flush(now: now)
        return TranscriptSegmenterUpdate(kind: .flush(flushed), timestamp: now)
    }

    private func flush(now: Date) -> String {
        let output = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = ""
        currentNormalized = ""
        lastUpdate = nil
        lineStart = nil
        return output
    }

    private func shouldFlushForSilence(now: Date) -> Bool {
        guard let lastUpdate else { return false }
        return now.timeIntervalSince(lastUpdate) >= config.silenceGapSeconds
    }

    private func shouldFlushForMaxAge(now: Date) -> Bool {
        guard let lineStart else { return false }
        return now.timeIntervalSince(lineStart) >= config.maxLineAgeSeconds
    }

    private func shouldFlushForPunctuation(text: String) -> Bool {
        guard text.count >= config.minCharsForPunctuationFlush else { return false }
        guard let last = text.last else { return false }
        return last == "." || last == "?" || last == "!"
    }

    private func shouldFlushForMaxChars(text: String) -> Bool {
        return text.count >= config.maxChars
    }

    private func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let collapsed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
