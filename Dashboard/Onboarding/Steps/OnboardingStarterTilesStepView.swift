import SwiftUI

/// Checklist of free-tier-eligible tile types (see OnboardingStarterTileCatalog),
/// laid out identically to OnboardingReviewStepView (checklist + live ghost preview) so
/// picking starter tiles feels like building a dashboard, not filling out a settings
/// form. Selections are written onto the wizard controller; OnboardingReviewStepView
/// merges them into its own candidate list.
struct OnboardingStarterTilesStepView: View {
    @ObservedObject var wizardController: OnboardingWizardController

    @State private var candidates: [OnboardingTileCandidate] = []
    private let previewCanvasSize = CGSize(width: 1920, height: 1080)

    var body: some View {
        HStack(spacing: 0) {
            checklist
                .frame(width: 280)
            Divider()
            OnboardingPreviewCanvas(candidates: candidates, canvasSize: previewCanvasSize)
        }
        .onAppear(perform: loadCandidates)
        .onChange(of: candidates, initial: false) { _, newValue in
            wizardController.starterTileSelections = newValue.filter(\.isIncluded)
        }
    }

    private var checklist: some View {
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
            .padding(12)
        }
    }

    /// Starter tiles start unchecked — this is an opt-in picker ("choose what to add"),
    /// unlike Review's opt-out checklist ("here's what you already configured").
    private func loadCandidates() {
        let selectedTitles = Set(wizardController.starterTileSelections.map(\.title))
        candidates = OnboardingStarterTileCatalog.availableEntries()
            .map { entry in
                var candidate = OnboardingTileCandidateFactory.candidate(for: entry)
                candidate.isIncluded = selectedTitles.contains(entry.title)
                return candidate
            }
    }
}
