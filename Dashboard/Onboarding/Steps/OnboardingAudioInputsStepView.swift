import SwiftUI

/// Embeds the real audio-input configuration screen inline.
struct OnboardingAudioInputsStepView: View {
    var body: some View {
        AudioInputsConfigView(presentationStyle: .embedded)
    }
}
