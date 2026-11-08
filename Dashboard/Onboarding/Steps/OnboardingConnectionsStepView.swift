import SwiftUI

/// Checklist of the 4 cloud/API integrations (auth-based, not discoverable).
/// Tapping a row pushes into its real settings sub-page inline.
struct OnboardingConnectionsStepView: View {
    private enum ConnectionKind: String, CaseIterable, Identifiable {
        case pco = "Planning Center"
        case proPresenter = "ProPresenter"
        case liveStream = "Live Stream"
        case smartLights = "Smart Lights"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .pco: return "calendar"
            case .proPresenter: return "play.rectangle"
            case .liveStream: return "dot.radiowaves.left.and.right"
            case .smartLights: return "lightbulb"
            }
        }

        var subtitle: String {
            switch self {
            case .pco: return "Sync service plans and schedules"
            case .proPresenter: return "Control slides and media playback"
            case .liveStream: return "Push your program feed to a streaming platform"
            case .smartLights: return "Trigger looks and scenes during service"
            }
        }

        /// Mirrors `ExternalConnectionsSettingsView.visiblePages` so the onboarding
        /// wizard never surfaces a row that the main Settings flow would hide.
        static var visibleCases: [ConnectionKind] {
            allCases.filter { kind in
                switch kind {
                case .liveStream:
                    return LiveStreamFeatureFlags.isEnabled
                case .smartLights:
                    return SmartLightFeatureFlags.isEnabled
                case .pco, .proPresenter:
                    return true
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ConnectionKind.visibleCases) { kind in
                        NavigationLink {
                            destination(for: kind)
                        } label: {
                            OnboardingChecklistRow(
                                icon: kind.systemImage,
                                title: kind.rawValue,
                                subtitle: kind.subtitle
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func destination(for kind: ConnectionKind) -> some View {
        switch kind {
        case .pco:
            DashboardPCOSettingsView()
        case .proPresenter:
            DashboardProPresenterSettingsView()
        case .liveStream:
            DashboardLiveStreamSettingsView()
        case .smartLights:
            DashboardSmartLightsSettingsView()
        }
    }
}
