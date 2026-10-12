import Foundation

struct NDIPipelinePresentation {
    var headline: String
    var subtitle: String?
    var recoveryAction: NDIRecoveryAction?
}

enum NDIRecoveryAction {
    case retryNow(() -> Void)
    case openSettings
}

enum NDIErrorPresenter {
    // Returns nil when the pipeline is .connected (video renders, no overlay needed).
    // retryCount drives progressive disclosure: 1-3 → reconnecting badge, 4+ → full error + retry button.
    static func presentation(
        for state: NDIFramePipeline.State,
        sourceName: String?,
        retryCount: Int,
        onRetry: (() -> Void)? = nil
    ) -> NDIPipelinePresentation? {
        switch state {
        case .idle:
            // Recovery for idle is intentionally nil — settings are accessed via the tile gear icon.
            return NDIPipelinePresentation(
                headline: "No Source Selected",
                subtitle: "Choose an NDI source in settings."
            )
        case .connecting:
            return NDIPipelinePresentation(
                headline: "Connecting…",
                subtitle: sourceName?.nilIfEmpty
            )
        case .connected:
            return nil
        case .disconnected(let reason):
            return NDIPipelinePresentation(headline: "Disconnected", subtitle: reason)
        case .suspended(let reason):
            return suspendedPresentation(for: reason)
        case .failed:
            return failedPresentation(retryCount: retryCount, onRetry: onRetry)
        }
    }

    private static func suspendedPresentation(for reason: NDIStreamSuspensionReason) -> NDIPipelinePresentation {
        switch reason {
        case .none:
            return NDIPipelinePresentation(headline: "Paused", subtitle: nil)
        case .hiddenTile:
            return NDIPipelinePresentation(headline: "Paused", subtitle: "Stream resumes when this tile is visible.")
        case .inactiveTab:
            return NDIPipelinePresentation(headline: "Paused", subtitle: "Stream resumes when this tab is active.")
        case .tinyTile:
            return NDIPipelinePresentation(headline: "Paused", subtitle: "Resize the tile to resume video.")
        case .overBudget:
            return NDIPipelinePresentation(headline: "Inactive", subtitle: "Two NDI modules are already active on this tab.")
        case .userPaused:
            return NDIPipelinePresentation(headline: "Paused", subtitle: "Click to resume.")
        }
    }

    private static func failedPresentation(retryCount: Int, onRetry: (() -> Void)?) -> NDIPipelinePresentation {
        if retryCount <= 3 {
            return NDIPipelinePresentation(headline: "Reconnecting…", subtitle: nil)
        }
        let recoveryAction: NDIRecoveryAction = onRetry.map { .retryNow($0) } ?? .openSettings
        return NDIPipelinePresentation(
            headline: "Source Unavailable",
            subtitle: "The source stopped responding. Relay will keep trying.",
            recoveryAction: recoveryAction
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
