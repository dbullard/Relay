import SwiftUI

/// Checklist of every candidate tile (built from ExternalDevicesStore's and
/// AudioInputsConfigStore's *current* contents — not a wizard-session diff, so
/// pre-existing configuration also becomes a candidate) alongside a live ghost
/// preview computed via OnboardingReviewLayout. Ends by creating the dashboard.
struct OnboardingReviewStepView: View {
    @ObservedObject var wizardController: OnboardingWizardController
    let onCreateDashboard: (_ candidates: [OnboardingTileCandidate], _ canvasSize: CGSize, _ name: String) -> Void

    @State private var candidates: [OnboardingTileCandidate] = []
    @State private var dashboardName: String = "Dashboard 1"
    @State private var canvasSize: CGSize = CGSize(width: 1920, height: 1080)

    private var includedCandidates: [OnboardingTileCandidate] {
        candidates.filter(\.isIncluded)
    }

    var body: some View {
        HStack(spacing: 0) {
            checklist
                .frame(width: 280)
            Divider()
            OnboardingPreviewCanvas(candidates: candidates, canvasSize: canvasSize)
        }
        .onAppear(perform: loadCandidates)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Dashboard Name", text: $dashboardName)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($candidates) { $candidate in
                        Button {
                            $candidate.isIncluded.wrappedValue.toggle()
                        } label: {
                            OnboardingChecklistRow(
                                icon: candidate.systemImage,
                                title: candidate.title,
                                subtitle: candidate.subtitle
                            ) {
                                Image(systemName: candidate.isIncluded ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(candidate.isIncluded ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            Button("Create Dashboard") {
                onCreateDashboard(includedCandidates, canvasSize, dashboardName)
            }
            .buttonStyle(.borderedProminent)
            .padding(12)
        }
    }

    private func loadCandidates() {
        let deviceCandidates = ExternalDevicesStore.shared.devices.compactMap(OnboardingTileCandidateFactory.candidate(for:))
        let audioCandidates = AudioInputsConfigStore.shared.inputs.map(OnboardingTileCandidateFactory.candidate(for:))
        candidates = deviceCandidates + audioCandidates + wizardController.starterTileSelections
    }
}
