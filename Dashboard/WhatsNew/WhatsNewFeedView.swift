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
                Text("Version \(release.version)")
                    .font(.headline)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(release.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            WhatsNewReleaseFeatures(release: release)
        }
    }
}

/// A release's highlights: its first few items, then a link to the full notes on GitHub.
/// Release notes can run to dozens of bullets; the app shows only the top of the list.
struct WhatsNewReleaseFeatures: View {
    let release: WhatsNewRelease
    var limit: Int = WhatsNewRelease.highlightLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // By position: release-note bullets can share a title (or have none).
            ForEach(Array(release.features.prefix(limit).enumerated()), id: \.offset) { _, feature in
                WhatsNewFeatureRow(feature: feature)
            }
            if release.features.count > limit, let url = release.notesURL {
                Link("See all \(release.features.count) changes on GitHub", destination: url)
                    .font(.caption)
                    .padding(.top, 6)
                    .padding(.leading, 54)
            }
        }
    }
}
