import SwiftUI

/// Full-screen wizard shell: shared progress chrome + Back/Skip/Next footer
/// wrapping a switch over the current OnboardingStep. Presented as a .sheet()
/// from DashboardRootView, mirroring WhatsNewSheet's presentation pattern.
struct OnboardingWizardView: View {
    @ObservedObject var controller: OnboardingWizardController
    let onCreateDashboard: (_ candidates: [OnboardingTileCandidate], _ canvasSize: CGSize, _ name: String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepContent
            footer
        }
        .frame(minWidth: 720, minHeight: 820)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(for: controller.step))
                .font(.title2.weight(.bold))
            OnboardingStepDotsView(
                steps: controller.activeSteps,
                current: controller.step,
                currentTitle: title(for: controller.step)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stepAccessibilityLabel)
        }
        .padding(20)
    }

    private var stepAccessibilityLabel: String {
        let index = (controller.activeSteps.firstIndex(of: controller.step) ?? 0) + 1
        return "Step \(index) of \(controller.activeSteps.count), \(title(for: controller.step))"
    }

    @ViewBuilder
    private var stepContent: some View {
        switch controller.step {
        case .welcome:
            OnboardingWelcomeStepView()
        case .connections:
            OnboardingConnectionsStepView()
        case .devices:
            OnboardingDevicesStepView()
        case .audioInputs:
            OnboardingAudioInputsStepView()
        case .starterTiles:
            OnboardingStarterTilesStepView(wizardController: controller)
        case .reviewAndCreate:
            OnboardingReviewStepView(wizardController: controller, onCreateDashboard: { candidates, canvasSize, name in
                onCreateDashboard(candidates, canvasSize, name)
                controller.stop()
            })
        }
    }

    private var footer: some View {
        HStack {
            if controller.step != .welcome {
                Button("Back") { controller.back() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
            Spacer()
            if controller.step != .reviewAndCreate {
                Button(controller.step == .welcome ? "Skip Setup" : "Skip this step") {
                    if controller.step == .welcome {
                        controller.stop()
                    } else {
                        controller.skip()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(controller.step == .welcome ? "Get Started" : "Continue") { controller.next() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .onboardingCardStyle(cornerRadius: 12)
        .padding(16)
    }

    private func title(for step: OnboardingStep) -> String {
        switch step {
        case .welcome: return "Welcome to Relay"
        case .connections: return "Connect Your Services"
        case .devices: return "Find Your Devices"
        case .audioInputs: return "Set Up Audio Inputs"
        case .starterTiles: return "Choose Starter Tiles"
        case .reviewAndCreate: return "Review & Create Your Dashboard"
        }
    }
}
