import Foundation

/// Builds a prefilled GitHub "new issue" link for bug reports. Nothing is sent from the
/// app: the user reviews the report on GitHub and submits it themselves.
enum GitHubIssueReport {
    static let newIssueBaseURL = URL(string: "https://github.com/dbullard/Relay/issues/new")!
    /// GitHub rejects very long URLs, so longer diagnostics are copied instead of linked.
    static let maxInlineDiagnosticsLength = 3000

    struct Result {
        let url: URL
        /// True when the diagnostics were too long to put in the link and should be pasted.
        let diagnosticsNeedPasting: Bool
    }

    static func make(message: String, diagnostics: String?, info: [String: Any]? = Bundle.main.infoDictionary) -> Result? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        var items: [URLQueryItem] = [
            .init(name: "template", value: "bug_report.yml"),
            .init(name: "title", value: "[Bug]: " + String(trimmed.prefix(60)).replacingOccurrences(of: "\n", with: " ")),
            .init(name: "version", value: "Relay \(version) (\(build))"),
            .init(name: "platform", value: "macOS \(os)"),
            .init(name: "actual", value: trimmed)
        ]

        var needsPasting = false
        if let diagnostics, !diagnostics.isEmpty {
            if diagnostics.count <= maxInlineDiagnosticsLength {
                items.append(.init(name: "evidence", value: diagnostics))
            } else {
                needsPasting = true
                items.append(.init(name: "evidence", value: "(Full diagnostic summary copied to the clipboard. Paste it here after reviewing it.)"))
            }
        }

        var components = URLComponents(url: newIssueBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        guard let url = components.url else { return nil }
        return Result(url: url, diagnosticsNeedPasting: needsPasting)
    }
}
