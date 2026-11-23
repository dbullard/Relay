import SwiftUI

// MARK: - View activity gating (Canvas vs Graph)

struct RelayIsActiveSideKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var prodLinkIsActiveSide: Bool {
        get { self[RelayIsActiveSideKey.self] }
        set { self[RelayIsActiveSideKey.self] = newValue }
    }
}

/// Whether the view side should perform heavy work (cache refresh, large list building, etc.).
/// Unlike `prodLinkIsActiveSide`, this stays false for the hidden side even during flip transitions.
struct RelayIsWorkEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var prodLinkIsWorkEnabled: Bool {
        get { self[RelayIsWorkEnabledKey.self] }
        set { self[RelayIsWorkEnabledKey.self] = newValue }
    }
}

struct FlipContainer<Front: View, Back: View>: View {
    let isFlipped: Bool
    let duration: Double
    let front: Front
    let back: Back
    let onFlipBegan: ((Bool) -> Void)?
    let onFlipCompleted: ((Bool) -> Void)?

    // Keep both sides mounted; we only gate heavy work via environment while inactive.
    @State private var isTransitioning: Bool = false
    /// The side the faces are drawn for. Follows `isFlipped` inside `withAnimation`,
    /// so the completion callback knows when the turn has actually finished.
    @State private var displayedFlipped: Bool
    /// Bumped per flip, so an interrupted flip's completion doesn't end the newer one.
    @State private var flipGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isFlipped: Bool,
        duration: Double = 0.55,
        onFlipBegan: ((Bool) -> Void)? = nil,
        onFlipCompleted: ((Bool) -> Void)? = nil,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.isFlipped = isFlipped
        self._displayedFlipped = State(initialValue: isFlipped)
        self.duration = duration
        self.onFlipBegan = onFlipBegan
        self.onFlipCompleted = onFlipCompleted
        self.front = front()
        self.back = back()
    }

    private var frontIsActive: Bool {
        // Front is active when not flipped, and also during transition so it can animate smoothly.
        !isFlipped || isTransitioning
    }

    private var backIsActive: Bool {
        // Back is active when flipped, and also during transition so it can animate smoothly.
        isFlipped || isTransitioning
    }

    private var frontWorkEnabled: Bool {
        // During the flip transition, both sides need live content so the
        // 3D card turn renders visually instead of flipping into a blank face.
        !isFlipped || isTransitioning
    }

    private var backWorkEnabled: Bool {
        isFlipped || isTransitioning
    }

    /// Under Reduce Motion the sides crossfade in place instead of turning in 3D.
    private func rotation(forBack isBack: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        if isBack {
            return displayedFlipped ? 0 : -180
        }
        return displayedFlipped ? 180 : 0
    }

    var body: some View {
        ZStack {
            front
                .opacity(displayedFlipped ? 0.0 : 1.0)
                .rotation3DEffect(
                    .degrees(rotation(forBack: false)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.75
                )
                .environment(\.prodLinkIsActiveSide, frontIsActive)
                .environment(\.prodLinkIsWorkEnabled, frontWorkEnabled)

            back
                .opacity(displayedFlipped ? 1.0 : 0.0)
                .rotation3DEffect(
                    .degrees(rotation(forBack: true)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.75
                )
                .environment(\.prodLinkIsActiveSide, backIsActive)
                .environment(\.prodLinkIsWorkEnabled, backWorkEnabled)
        }
        .onChange(of: isFlipped, initial: false) { _, newValue in
            isTransitioning = true
            onFlipBegan?(newValue)

            flipGeneration &+= 1
            let generation = flipGeneration
            let animation: Animation = reduceMotion
                ? .easeInOut(duration: min(duration, 0.25))
                : .easeInOut(duration: duration)
            withAnimation(animation) {
                displayedFlipped = newValue
            } completion: {
                // A flip that was interrupted by a newer one completes late; only
                // the latest flip may end the transition.
                guard generation == flipGeneration else { return }
                isTransitioning = false
                onFlipCompleted?(isFlipped)
            }
        }
    }
}
