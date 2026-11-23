import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Every glass/material surface here honours Reduce Transparency: the blur is
// replaced with an opaque fill, and a stronger border keeps the edge visible.
// The same modifiers are applied either way (only their values change), so
// toggling the setting doesn't reset the state of the content inside.

extension View {
    func dashboardGlassPanel(cornerRadius: CGFloat, appliesScrollContentBackground: Bool = false) -> some View {
        modifier(DashboardGlassPanelModifier(
            cornerRadius: cornerRadius,
            appliesScrollContentBackground: appliesScrollContentBackground
        ))
    }

    func dashboardGlassControl(cornerRadius: CGFloat) -> some View {
        modifier(DashboardGlassControlModifier(cornerRadius: cornerRadius))
    }

    func dashboardGlassCircleButton() -> some View {
        modifier(DashboardGlassCircleButtonModifier())
    }
}

private struct DashboardGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let appliesScrollContentBackground: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let fill = DashboardGlassSurfaceMetrics.fill(.ultraThinMaterial, reduceTransparency: reduceTransparency)

        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .modifier(DashboardScrollBackgroundModifier(isHidden: appliesScrollContentBackground))
                .background(Color.clear)
                .background(shape.fill(fill))
                .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
                .backgroundExtensionEffect()
                .dashboardGlassHighlightOverlay(shape: shape, blackStrokeOpacity: 0.10)
                .overlay(DashboardGlassSurfaceMetrics.opaqueBorder(shape, isVisible: reduceTransparency))
                .clipShape(shape)
                .compositingGroup()
        } else {
            content
                .background(shape.fill(fill))
                .overlay(
                    shape
                        .stroke(Color.primary.opacity(reduceTransparency ? 0.35 : 0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .clipShape(shape)
                .compositingGroup()
        }
    }
}

private struct DashboardGlassControlModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background(shape.fill(DashboardGlassSurfaceMetrics.fill(.thinMaterial, reduceTransparency: reduceTransparency)))
                .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
                .backgroundExtensionEffect()
                .dashboardGlassHighlightOverlay(shape: shape, blackStrokeOpacity: 0.08)
                .overlay(DashboardGlassSurfaceMetrics.opaqueBorder(shape, isVisible: reduceTransparency))
        } else {
            content
                .background(shape.fill(Color.primary.opacity(0.08)))
                .overlay(
                    shape
                        .stroke(Color.primary.opacity(reduceTransparency ? 0.35 : 0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }
}

private struct DashboardGlassCircleButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background(DashboardGlassSurfaceMetrics.fill(.thinMaterial, reduceTransparency: reduceTransparency), in: Circle())
                .glassEffect(reduceTransparency ? .identity : .regular, in: Circle())
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
                .overlay(DashboardGlassSurfaceMetrics.opaqueBorder(Circle(), isVisible: reduceTransparency))
        } else {
            content
                .background(Circle().fill(DashboardGlassSurfaceMetrics.fill(.ultraThinMaterial, reduceTransparency: reduceTransparency)))
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(reduceTransparency ? 0.35 : 0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }
}

extension View {
    fileprivate func dashboardGlassHighlightOverlay<S: InsettableShape>(
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

    /// Opaque stand-in for a material under Reduce Transparency.
    static var opaqueFill: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static func fill(_ material: Material, reduceTransparency: Bool) -> AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(opaqueFill) : AnyShapeStyle(material)
    }

    /// The border that outlines an opaque surface; clear when transparency is allowed.
    static func opaqueBorder<S: Shape>(_ shape: S, isVisible: Bool) -> some View {
        shape
            .stroke(Color.primary.opacity(isVisible ? 0.35 : 0), lineWidth: 1)
            .allowsHitTesting(false)
    }
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
