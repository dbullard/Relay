import SwiftUI

/// Connected dot-and-line progress indicator for the wizard header, replacing a bare
/// linear ProgressView. Current step is enlarged with a ring; completed steps and their
/// connectors are accent-colored, upcoming ones are dimmed. `currentTitle` is shown as
/// a caption below the dots since 6 step names won't all fit across the row on iOS.
struct OnboardingStepDotsView: View {
    let steps: [OnboardingStep]
    let current: OnboardingStep
    let currentTitle: String

    private var currentIndex: Int {
        steps.firstIndex(of: current) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                    dot(at: index)
                    if index < steps.count - 1 {
                        connector(filled: index < currentIndex)
                    }
                }
            }
            Text(currentTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dot(at index: Int) -> some View {
        if index == currentIndex {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 9, height: 9)
                .padding(3)
                .overlay(Circle().stroke(Color.accentColor.opacity(0.35), lineWidth: 2))
        } else {
            Circle()
                .fill(index < currentIndex ? Color.accentColor : Color.primary.opacity(0.15))
                .frame(width: 7, height: 7)
                .padding(4)
        }
    }

    private func connector(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? Color.accentColor : Color.primary.opacity(0.15))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
}
