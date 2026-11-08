import SwiftUI

struct WhatsNewFeedView: View {
    let releases: [WhatsNewRelease]

    var body: some View {
        ScrollView {
            if releases.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(releases, id: \.version) { release in
                        releaseSection(release)
                    }
                }
                .padding(24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No updates yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private func releaseSection(_ release: WhatsNewRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Version \(release.version) (\(RelayBuildConfig.channelDisplayLabel))")
                    .font(.headline)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(release.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(release.features, id: \.title) { feature in
                    WhatsNewFeatureRow(feature: feature)
                }
            }
        }
    }
}
