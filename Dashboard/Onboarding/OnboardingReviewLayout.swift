import Foundation
import CoreGraphics

/// Computes preview/final placement for the Review & Create step's checked tile
/// candidates, reusing TileDistribution — the same grid algorithm the canvas's
/// "Distribute Selected Tiles" toolbar action uses — so the wizard's dashboard
/// looks the same as a manually-tidied one.
enum OnboardingReviewLayout {
    /// Returns a rect per candidate ID, filling `canvasSize` edge-to-edge.
    ///
    /// `TileDistribution.distribute` only handles 2+ tiles (it returns `[:]`
    /// below that), so the common single-candidate case — e.g. a first-run
    /// user who only checks one audio input — is special-cased here to a
    /// single rect spanning the full canvas, rather than delegating to a grid
    /// algorithm that can't represent a 1-tile layout.
    static func layout(candidateIDs: [UUID], canvasSize: CGSize, axis: DistributeAxis = .horizontal) -> [UUID: CGRect] {
        if candidateIDs.count == 1, let onlyID = candidateIDs.first {
            return [onlyID: CGRect(origin: .zero, size: canvasSize)]
        }
        let distributable = candidateIDs.map { DistributableTile(id: $0, offset: .zero) }
        return TileDistribution.distribute(tiles: distributable, axis: axis, canvasSize: canvasSize)
    }

    /// Converts a TileDistribution rect into a DashboardTileModel's offset/size
    /// pair, matching the exact formula DashboardRootView.distributeSelectedTiles
    /// uses: the rect's raw origin becomes the offset, with no re-centering.
    static func offsetAndSize(for rect: CGRect) -> (offset: CGSize, size: CGSize) {
        let offset = CGSize(width: rect.origin.x, height: rect.origin.y)
        let size = CGSize(width: rect.width, height: rect.height)
        return (offset, size)
    }
}
