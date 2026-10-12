import SwiftUI

extension View {
    /// Shared card treatment for the wizard's redesigned rows, footer, and preview
    /// canvas: a subtle tinted fill plus a hairline border, consistent across light
    /// and dark appearance without reaching for platform-specific system colors.
    func onboardingCardStyle(cornerRadius: CGFloat = 10) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
