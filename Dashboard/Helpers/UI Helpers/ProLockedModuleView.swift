import SwiftUI

struct ProLockedModuleView: View {
    let title: String
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                ProBadgeView(fontSize: 10)
            }

            Text("Upgrade to Pro to unlock this module.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Upgrade to Pro") {
                onUpgrade()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.15))
        )
    }
}

struct UnavailableModuleView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.15))
        )
    }
}
