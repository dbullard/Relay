import SwiftUI

struct BetaBadgeView: View {
    var label: String = "BETA"
    var fontSize: CGFloat = 11
    var foreground: Color = .secondary
    var backgroundOpacity: Double = 0.10
    var borderOpacity: Double = 0.14

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(backgroundOpacity))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(borderOpacity), lineWidth: 1)
            )
    }
}
