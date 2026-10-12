import Foundation
import Combine

@MainActor
final class UsageDiagnosticsPreferences: ObservableObject {
    static let shared = UsageDiagnosticsPreferences()
    static let enabledKey = "relay_usage_diagnostics_enabled"
    static let promptKey = "relay_usage_diagnostics_prompted_v1"

    @Published private(set) var isEnabled: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    var shouldPresentPrompt: Bool { !defaults.bool(forKey: Self.promptKey) }

    func recordPromptChoice(enabled: Bool) {
        defaults.set(true, forKey: Self.promptKey)
        setEnabled(enabled)
    }

    func markPromptSeenWithoutEnabling() {
        recordPromptChoice(enabled: false)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        isEnabled = enabled
        RelaySentry.applyConsent(enabled: enabled)
    }
}
