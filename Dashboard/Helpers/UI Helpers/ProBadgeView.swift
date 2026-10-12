import SwiftUI

struct ProBadgeView: View {
    var label: String = "PRO"
    var fontSize: CGFloat = 11
    var foreground: Color = .white
    var backgroundOpacity: Double = 0.9
    var borderOpacity: Double = 0.3

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.29, green: 0.35, blue: 0.98),
                Color(red: 0.19, green: 0.55, blue: 1.0),
                Color(red: 0.16, green: 0.84, blue: 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(gradient.opacity(backgroundOpacity))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(gradient.opacity(borderOpacity), lineWidth: 1)
            )
    }
}
