import Foundation

enum ProPresenterAutomationError: LocalizedError {
    case invalidTriggerPath

    var errorDescription: String? {
        switch self {
        case .invalidTriggerPath:
            return "Invalid ProPresenter trigger path."
        }
    }
}

struct ProPresenterAutomationService {
    static func sendTrigger(profileId: UUID?, triggerPath: String) async throws {
        let path = normalizeTriggerPath(triggerPath)
        guard !path.isEmpty else { throw ProPresenterAutomationError.invalidTriggerPath }

        let options = ProPresenterRequestOptions(allowTCPFallback: false, preferTCP: false, timeout: 2.0)
        let connection = ProPresenterConnection(profileID: profileId, options: options)
        try await connection.requestVoid(path, method: "GET")
    }

    private static func normalizeTriggerPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }
}
