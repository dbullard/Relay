import SwiftUI

/// Owns the only read of `interactionSession.activeSnapRegion`/
/// `activeSnapTileFrames` on the canvas -- the same isolation
/// `DashboardSmartGuidesLayer` uses for `activeSmartGuides`, so a preview
/// update (written every frame of an option-drag near an edge/corner)
/// re-runs this view's trivial body instead of `DashboardTileCanvas.body`
/// (which rebuilds every tile row).
struct DashboardSnapRegionPreviewLayer: View {
    let session: DashboardTileInteractionSession
    let canvasSize: CGSize

    private static let outlineColor = Color(red: 0.63, green: 0.36, blue: 0.86)

    var body: some View {
        if let region = session.activeSnapRegion {
            ZStack(alignment: .topLeading) {
                outline(for: region.rect(in: canvasSize), color: Self.outlineColor)
                SwiftUI.ForEach(Array(session.activeSnapTileFrames.keys), id: \.self) { tileID in
                    if let frame = session.activeSnapTileFrames[tileID] {
                        outline(for: frame, color: Self.outlineColor.opacity(0.6))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func outline(for rect: CGRect, color: Color) -> some View {
        Rectangle()
            .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}
