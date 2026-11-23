import CoreGraphics

/// Sizes the tile resize-handle hit areas so they stay the same size on screen
/// at every canvas zoom.
///
/// The handles live inside the zoomed canvas layer, so a fixed radius in canvas
/// points shrinks with the zoom: the old fixed 14pt radius was only 3.5pt on screen
/// at 25%. The radius here is the on-screen target divided by the zoom.
enum DashboardTileResizeHitTarget {
    /// On-screen hit radius: a 28pt target on macOS, 44pt on iPad.
    static var platformOnScreenRadius: CGFloat {
        #if os(iOS)
        return 22
        #else
        return 14
        #endif
    }

    /// Hit radius in canvas points for a handle on a tile of `tileSize`.
    ///
    /// When zoomed far out, a constant on-screen radius would let the eight handles
    /// cover a small tile completely, leaving nowhere to grab it to move it. The
    /// radius is therefore capped at a third of the tile's shorter side (never
    /// below the original 14pt halo, so nothing gets smaller than before at 100%).
    static func hitRadius(
        viewportZoom: CGFloat,
        tileSize: CGSize,
        onScreenRadius: CGFloat = platformOnScreenRadius
    ) -> CGFloat {
        let zoom = max(viewportZoom, 0.0001)
        let constantOnScreen = onScreenRadius / zoom
        let shorterSide = max(0, min(tileSize.width, tileSize.height))
        let cap = max(DashboardTileResizeHandleLayout.hitHalo, shorterSide / 3)
        return min(constantOnScreen, cap)
    }

    /// Whether a resize drag result actually changes the tile. A tap on a handle
    /// (iPad's resize gesture starts at distance 0) produces the start size again,
    /// and must not register a "Resize Tile" undo step.
    static func resizeChangesTile(
        startSize: CGSize,
        startOffset: CGSize,
        newSize: CGSize,
        newOffsetY: CGFloat?,
        newOffsetX: CGFloat?,
        tolerance: CGFloat = 0.01
    ) -> Bool {
        if abs(newSize.width - startSize.width) > tolerance { return true }
        if abs(newSize.height - startSize.height) > tolerance { return true }
        if let newOffsetY, abs(newOffsetY - startOffset.height) > tolerance { return true }
        if let newOffsetX, abs(newOffsetX - startOffset.width) > tolerance { return true }
        return false
    }
}
