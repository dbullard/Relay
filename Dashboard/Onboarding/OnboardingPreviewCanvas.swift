import SwiftUI

/// Shared scaled preview canvas for the Starter Tiles and Review steps: a subtle
/// dot-grid background (signaling "this is a canvas you're arranging") behind ghost
/// tile outlines, framed as a bordered card per the wizard's shared card style.
/// Replaces the flat Color.black.opacity(0.2) rectangle previously duplicated
/// identically in both step views.
struct OnboardingPreviewCanvas: View {
    let candidates: [OnboardingTileCandidate]
    let canvasSize: CGSize

    private var includedCandidates: [OnboardingTileCandidate] {
        candidates.filter(\.isIncluded)
    }

    private var previewFrames: [UUID: CGRect] {
        OnboardingReviewLayout.layout(candidateIDs: includedCandidates.map(\.id), canvasSize: canvasSize)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / canvasSize.width, proxy.size.height / canvasSize.height)
            ZStack {
                gridBackground
                OnboardingGhostPreviewLayer(
                    frames: previewFrames,
                    titlesByID: Dictionary(uniqueKeysWithValues: includedCandidates.map { ($0.id, $0.title) })
                )
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onboardingCardStyle()
        .padding(20)
    }

    private var gridBackground: some View {
        Canvas { context, size in
            let spacing: CGFloat = 40
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.03)))
            var x: CGFloat = 0
            while x <= size.width {
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(Color.primary.opacity(0.06)),
                    lineWidth: 1
                )
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(Color.primary.opacity(0.06)),
                    lineWidth: 1
                )
                y += spacing
            }
        }
    }
}
