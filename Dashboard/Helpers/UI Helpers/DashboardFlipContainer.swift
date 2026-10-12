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

    init(
        isFlipped: Bool,
        duration: Double = 0.55,
        onFlipBegan: ((Bool) -> Void)? = nil,
        onFlipCompleted: ((Bool) -> Void)? = nil,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.isFlipped = isFlipped
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

    var body: some View {
        ZStack {
            front
                .opacity(isFlipped ? 0.0 : 1.0)
                .rotation3DEffect(
                    .degrees(isFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.75
                )
                .environment(\.prodLinkIsActiveSide, frontIsActive)
                .environment(\.prodLinkIsWorkEnabled, frontWorkEnabled)

            back
                .opacity(isFlipped ? 1.0 : 0.0)
                .rotation3DEffect(
                    .degrees(isFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.75
                )
                .environment(\.prodLinkIsActiveSide, backIsActive)
                .environment(\.prodLinkIsWorkEnabled, backWorkEnabled)
        }
        .animation(.easeInOut(duration: duration), value: isFlipped)
        .onChange(of: isFlipped, initial: false) { _, _ in
            isTransitioning = true
            onFlipBegan?(isFlipped)

            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
                isTransitioning = false
                onFlipCompleted?(isFlipped)
            }
        }
    }
}
