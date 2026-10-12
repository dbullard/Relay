import SwiftUI

struct WhatsNewSheet: View {
    let releases: [WhatsNewRelease]
    /// Invoked only by the in-view "Got It" button — not by system dismiss gestures
    /// (e.g. swipe-to-dismiss). Callers that need to react to any dismissal, such as
    /// marking a release as seen, should also hook into `.sheet(isPresented:onDismiss:)`.
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                if releases.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(releases, id: \.version) { release in
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(release.features, id: \.title) { feature in
                                    WhatsNewFeatureRow(feature: feature)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            Divider()
            footer
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Nothing new to show")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's New")
                .font(.title2.weight(.bold))
            Text("Here's what changed in this update.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Got It") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}
