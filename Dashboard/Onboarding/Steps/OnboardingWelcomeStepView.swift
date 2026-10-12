import SwiftUI

struct OnboardingWelcomeStepView: View {
    /// Static, illustrative preview of what the wizard covers — not tied to which
    /// steps are actually active for the current tier. Purely informational, so each
    /// row has no trailing indicator (EmptyView).
    private struct FeaturePreview: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
    }

    private let previewFeatures: [FeaturePreview] = [
        FeaturePreview(
            icon: "link.circle.fill",
            title: "Connect Services",
            subtitle: "Link Planning Center, ProPresenter, and more"
        ),
        FeaturePreview(
            icon: "wifi",
            title: "Find Devices",
            subtitle: "Discover mixers and wireless gear on your network"
        ),
        FeaturePreview(
            icon: "square.grid.2x2.fill",
            title: "Build Your Dashboard",
            subtitle: "Pick starter tiles and create your first layout"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Let's set up your first dashboard.")
                .font(.title3.weight(.semibold))
            Text("We'll walk through connecting your services, finding devices on your network, and choosing audio inputs — then build a dashboard from what you set up. Every step is optional, and you can skip anything you don't use.")
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(previewFeatures) { feature in
                    OnboardingChecklistRow(
                        icon: feature.icon,
                        title: feature.title,
                        subtitle: feature.subtitle
                    ) {
                        EmptyView()
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
