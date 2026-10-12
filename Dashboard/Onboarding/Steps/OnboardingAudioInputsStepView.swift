import SwiftUI

/// Embeds the real audio-input configuration screen inline. Pro-only: the underlying
/// AudioInputsConfigView (and its device-enumeration `.onAppear`, which can trigger a
/// mic-permission prompt) is skipped entirely when locked, rather than just being
/// disabled/dimmed on top — free users shouldn't trigger microphone access for a
/// feature they can't use (RTA/Spectrograph, the only tiles that read an audio input,
/// already require Pro).
struct OnboardingAudioInputsStepView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    private var isLocked: Bool { !subscriptionManager.hasPro }

    var body: some View {
        Group {
            if isLocked {
                Color.clear
            } else {
                AudioInputsConfigView(presentationStyle: .embedded)
            }
        }
        .onboardingProLocked(isLocked)
    }
}
