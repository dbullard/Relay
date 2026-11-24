import SwiftUI

struct WhatsNewFeatureRow: View {
    let feature: WhatsNewFeature

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.inlineMarkdown(feature.title))
                    .font(.subheadline.weight(.semibold))
                if !feature.description.isEmpty {
                    Text(Self.inlineMarkdown(feature.description))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    /// Release notes use inline Markdown (bold, code, links); show it formatted, not raw.
    private static func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private var iconColor: Color {
        guard let components = relayHexColorComponents(feature.iconColor) else { return .accentColor }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}
