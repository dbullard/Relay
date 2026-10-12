import SwiftUI

/// Mirrors the app's existing Pro-lock treatment (ExternalDevicesSettingsView's
/// fullSettingsContent/editDeviceOnlyBody): dims + disables the wrapped content and
/// overlays a blurred upgrade card when `isLocked` is true, so free users see what a
/// Pro-only wizard step contains without being able to interact with it. The overlay
/// itself is inset with rounded corners so it reads as a card consistent with the
/// rest of the redesigned wizard, rather than going full-bleed to the sheet edges.
private struct OnboardingProLockOverlay: ViewModifier {
    let isLocked: Bool

    func body(content: Content) -> some View {
        content
            .disabled(isLocked)
            .opacity(isLocked ? 0.35 : 1.0)
            .allowsHitTesting(!isLocked)
            .overlay {
                if isLocked {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.7)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))

                        // The wizard's step area is shorter than the full-height sheet
                        // ProUpgradePromptView/ProUpgradePromptViewIOS were designed for
                        // (it sits between the wizard's header/progress bar and its
                        // Back/Skip/Next footer), so wrap it in a ScrollView here rather
                        // than letting it clip.
                        ScrollView {
#if os(iOS)
                            ProUpgradePromptViewIOS(
                                buttonTitle: "Upgrade to Pro",
                                secondaryButtonTitle: "Continue with Free",
                                secondaryAction: {},
                                showPlanSelector: true,
                                showManageLinks: true
                            ) { }
#else
                            ProUpgradePromptView(
                                buttonTitle: "Upgrade to Pro",
                                secondaryButtonTitle: "Continue with Free",
                                secondaryAction: {},
                                showPlanSelector: true,
                                showManageLinks: true
                            ) { }
#endif
                        }
                        .padding(.vertical, 12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
    }
}

extension View {
    /// Applies the onboarding wizard's Pro-lock treatment when `isLocked` is true.
    func onboardingProLocked(_ isLocked: Bool) -> some View {
        modifier(OnboardingProLockOverlay(isLocked: isLocked))
    }
}
