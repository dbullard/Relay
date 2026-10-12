import SwiftUI

extension View {
    @ViewBuilder
    func dashboardGlassPanel(cornerRadius: CGFloat, appliesScrollContentBackground: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .modifier(DashboardScrollBackgroundModifier(isHidden: appliesScrollContentBackground))
                .background(Color.clear)
                .background(shape.fill(.ultraThinMaterial))
                .glassEffect(in: shape)
                .backgroundExtensionEffect()
                .dashboardGlassHighlightOverlay(shape: shape, blackStrokeOpacity: 0.10)
                .clipShape(shape)
                .compositingGroup()
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .overlay(
                    shape
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .clipShape(shape)
                .compositingGroup()
        }
    }

    @ViewBuilder
    func dashboardGlassControl(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background(shape.fill(.thinMaterial))
                .glassEffect(in: shape)
                .backgroundExtensionEffect()
                .dashboardGlassHighlightOverlay(shape: shape, blackStrokeOpacity: 0.08)
        } else {
            self
                .background(shape.fill(Color.primary.opacity(0.08)))
                .overlay(
                    shape
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }

    @ViewBuilder
    func dashboardGlassCircleButton() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background(.thinMaterial, in: Circle())
                .glassEffect(in: Circle())
                .backgroundExtensionEffect()
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.00)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: DashboardGlassSurfaceMetrics.highlightColors,
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.10), lineWidth: 0.75)
                        .allowsHitTesting(false)
                )
        } else {
            self
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }

    private func dashboardGlassHighlightOverlay<S: InsettableShape>(
        shape: S,
        blackStrokeOpacity: Double
    ) -> some View {
        overlay(
            shape
                .stroke(
                    LinearGradient(
                        colors: DashboardGlassSurfaceMetrics.highlightColors,
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .overlay(
            shape
                .stroke(Color.black.opacity(blackStrokeOpacity), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
    }
}

private enum DashboardGlassSurfaceMetrics {
    static let highlightColors: [Color] = [
        Color.white.opacity(0.22),
        Color.white.opacity(0.08),
        Color.white.opacity(0.03)
    ]
}

private struct DashboardScrollBackgroundModifier: ViewModifier {
    let isHidden: Bool

    func body(content: Content) -> some View {
        if isHidden {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
