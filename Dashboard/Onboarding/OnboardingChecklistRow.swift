import SwiftUI

/// Shared bordered/icon-chip row used across the wizard's checklist steps
/// (Connections, Devices, Starter Tiles, Review). Mirrors WhatsNewFeatureRow's
/// icon-chip treatment (icon in a colored rounded-rect, title + caption subtitle),
/// with a caller-supplied trailing indicator (checkbox, PRO badge, chevron, status
/// label) instead of WhatsNewFeatureRow's plain layout. Purely presentational —
/// callers wrap it in whatever tap/navigation control fits their step (Button,
/// NavigationLink), so this component makes no assumption about interaction.
struct OnboardingChecklistRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let trailing: () -> Trailing

    init(
        icon: String,
        iconColor: Color = .accentColor,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            trailing()
        }
        .padding(11)
        .onboardingCardStyle()
        .contentShape(Rectangle())
    }
}
