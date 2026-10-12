import SwiftUI

/// Owns the only read of `interactionSession.activeSmartGuides` on the
/// canvas, so a guide update (written every frame of a snapping drag/resize)
/// re-runs this view's trivial body instead of `DashboardTileCanvas.body`
/// (which rebuilds every tile row).
struct DashboardSmartGuidesLayer: View {
    let session: DashboardTileInteractionSession
    let canvasSize: CGSize

    var body: some View {
        if !session.activeSmartGuides.isEmpty {
            SmartGuidesOverlay(guides: session.activeSmartGuides, canvasSize: canvasSize)
        }
    }
}
