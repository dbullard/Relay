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

/// Strips the lines already shown from a recognizer result.
///
/// A recognizer task's text is cumulative: each result repeats everything heard since the task
/// started, which can be many minutes when the input is quiet. `committed` is the task's text
/// as of the last line shown. The recognizer also keeps revising its last few words after a line
/// has been shown ("it's bob" → "Bob's fault"), so an exact prefix match is not enough: a revision
/// used to re-show the whole task as a new line, re-firing word triggers for every name in it.
nonisolated enum TranscriptCommittedPrefix {
    /// How many already-shown words a revision may repeat. Words before this window are never
    /// shown again, even if the recognizer revised them.
    static let maxRevisedWords = 6

    /// The words of `text` not yet shown, keeping their case, or nil when `text` does not
    /// continue `committed` (for example a new recognizer task), which the caller must handle.
    static func remainder(of text: String, committed: String) -> String? {
        let committedWords = words(committed).map { $0.lowercased() }
        guard !committedWords.isEmpty else { return nil }
        let textWords = words(text)

        var shared = 0
        while shared < min(committedWords.count, textWords.count),
              textWords[shared].lowercased() == committedWords[shared] {
            shared += 1
        }

        // Two shared leading words is the same task: a new task starting with the old task's
        // opening words is far less likely than the recognizer revising one of its own words.
        guard shared == committedWords.count || shared >= 2 else { return nil }

        let drop = min(textWords.count, max(shared, committedWords.count - maxRevisedWords))
        return textWords.dropFirst(drop).joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
