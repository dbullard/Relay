import Foundation
import Combine

enum OnboardingStep {
    case welcome
    case connections
    case devices
    case audioInputs
    case starterTiles
    case reviewAndCreate
}

/// Owns onboarding-wizard step navigation. Mirrors DashboardTutorialController's
/// shape (isPresented + step + start/stop), kept as a @StateObject on
/// DashboardRootView. Each step writes its own configuration directly to its
/// real store (ExternalDevicesStore, AudioInputsConfigStore, etc.) as the user
/// configures it — the controller only tracks *which step* is showing. The
/// Review & Create step reads those stores directly, so candidacy always
/// reflects actual current state rather than a wizard-session diff.
///
/// Step sequence is tier-dependent: free-tier users still get Connections before
/// Starter Tiles so they can configure the free Planning Center login before choosing
/// PCO starter tiles. Device and audio setup remain Pro-only. `activeSteps` is
/// computed once at `start(hasPro:)` and navigation moves by index within it rather
/// than by the step enum's raw ordering.
final class OnboardingWizardController: ObservableObject {
    @Published var isPresented: Bool = false
    @Published private(set) var step: OnboardingStep = .welcome
    @Published private(set) var activeSteps: [OnboardingStep] = []

    /// Tiles the user picked in the Starter Tiles step. Reset on every `start(hasPro:)`;
    /// written by OnboardingStarterTilesStepView, read by OnboardingReviewStepView.
    @Published var starterTileSelections: [OnboardingTileCandidate] = []

    func start(hasPro: Bool) {
        activeSteps = hasPro
            ? [.welcome, .connections, .devices, .audioInputs, .starterTiles, .reviewAndCreate]
            : [.welcome, .connections, .starterTiles, .reviewAndCreate]
        step = activeSteps[0]
        starterTileSelections = []
        isPresented = true
    }

    func stop() {
        isPresented = false
    }

    func next() {
        guard let idx = activeSteps.firstIndex(of: step), idx + 1 < activeSteps.count else {
            stop()
            return
        }
        step = activeSteps[idx + 1]
    }

    func back() {
        guard let idx = activeSteps.firstIndex(of: step), idx > 0 else { return }
        step = activeSteps[idx - 1]
    }

    /// Per-step skip is identical to Next — skipping just means "nothing to add
    /// from this step."
    func skip() {
        next()
    }
}

extension Notification.Name {
    /// Posted by the macOS File menu's and iOS ellipsis menu's "Setup Wizard…"
    /// items to manually relaunch the onboarding wizard.
    static let relayStartOnboardingWizard = Notification.Name("Relay.StartOnboardingWizard")
}
