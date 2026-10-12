import SwiftUI

/// Floating toolbar shown above (or, near the top of the canvas, below) the current
/// tile selection. Offers canvas-fraction sizing for a single selected tile, and
/// even-spacing distribution for 2+ selected tiles. Renders nothing when neither
/// action applies (e.g. exactly 0 or 1 tiles selected).
struct SelectionActionToolbarView: View {
    let selectionRect: CGRect
    let selectedTileCount: Int
    let viewportZoom: CGFloat
    let shouldFlipBelow: Bool
    let onApplyFractionRegion: (CanvasFractionRegion) -> Void
    let onDistribute: (DistributeAxis) -> Void
    let canvasSize: CGSize

    @State private var isRegionPickerPresented = false

    private static let regionSections = ["Half", "Thirds", "Fourths", "Quarters", "Full"]

    private var safeZoom: CGFloat { max(0.0001, viewportZoom) }
    /// Keeps toolbar chrome a constant on-screen size regardless of canvas zoom —
    /// same fix as CanvasGuide's labelScale: cap only the upper bound, never floor it.
    private var chromeScale: CGFloat { min(1 / safeZoom, 2) }

    private var showsSizeButton: Bool { selectedTileCount == 1 }
    private var showsDistributeButtons: Bool { selectedTileCount >= 2 }
    private var canDistributeHorizontally: Bool {
        TileDistribution.canDistribute(count: selectedTileCount, axis: .horizontal, canvasSize: canvasSize)
    }
    private var canDistributeVertically: Bool {
        TileDistribution.canDistribute(count: selectedTileCount, axis: .vertical, canvasSize: canvasSize)
    }
    /// Caps how many cells the toolbar icon draws so a large selection still
    /// gets a legible preview -- purely a drawing-time clamp, with no effect
    /// on `distribute()`'s actual shape for the real `selectedTileCount`.
    private static let iconCellCap = 6
    private func previewShape(axis: DistributeAxis) -> TileDistribution.GridShape {
        TileDistribution.idealShape(count: min(selectedTileCount, Self.iconCellCap), axis: axis)
    }

    /// The selection's current dimensions, rounded to whole points (e.g. "780 × 360").
    private var sizeLabel: String {
        "\(Int(selectionRect.width.rounded())) × \(Int(selectionRect.height.rounded()))"
    }

    var body: some View {
        if showsSizeButton || showsDistributeButtons {
            HStack(spacing: 8) {
                Text(sizeLabel)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Divider()
                    .frame(height: 14)

                if showsSizeButton {
                    Button {
                        isRegionPickerPresented = true
                    } label: {
                        Label("Size", systemImage: "rectangle.grid.2x2")
                    }
                    .popover(isPresented: $isRegionPickerPresented, arrowEdge: shouldFlipBelow ? .bottom : .top) {
                        regionPickerPopover
                    }
                }
                if showsDistributeButtons {
                    Button {
                        onDistribute(.horizontal)
                    } label: {
                        DistributeGridPreview(shape: previewShape(axis: .horizontal))
                    }
                    .accessibilityLabel("Distribute Horizontally")
                    .help(canDistributeHorizontally ? "Distribute Horizontally" : "Too many tiles to fit at minimum size")
                    .disabled(!canDistributeHorizontally)

                    Button {
                        onDistribute(.vertical)
                    } label: {
                        DistributeGridPreview(shape: previewShape(axis: .vertical))
                    }
                    .accessibilityLabel("Distribute Vertically")
                    .help(canDistributeVertically ? "Distribute Vertically" : "Too many tiles to fit at minimum size")
                    .disabled(!canDistributeVertically)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(radius: 6)
            .scaleEffect(chromeScale)
            .position(
                x: selectionRect.midX,
                y: shouldFlipBelow ? selectionRect.maxY + SelectionToolbarPlacement.defaultAnchorOffset : selectionRect.minY - SelectionToolbarPlacement.defaultAnchorOffset
            )
            .allowsHitTesting(true)
        }
    }

    private var regionPickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.regionSections, id: \.self) { section in
                Text(section)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(CanvasFractionRegion.allCases.filter { $0.section == section }) { region in
                        Button {
                            onApplyFractionRegion(region)
                            isRegionPickerPresented = false
                        } label: {
                            CanvasFractionRegionPreview(region: region)
                                .frame(width: 40, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .help(region.label)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 220)
    }
}

/// A small diagram of the canvas with `region`'s exact target area filled in —
/// shows the user precisely where the tile will end up, rather than relying on
/// a generic (and, for thirds/quarters, ambiguous) icon.
private struct CanvasFractionRegionPreview: View {
    let region: CanvasFractionRegion

    /// Fixed preview canvas size; only the proportions matter here; the aspect
    /// ratio doesn't need to match the user's actual canvas.
    private static let previewSize = CGSize(width: 26, height: 16)

    var body: some View {
        let rect = region.rect(in: Self.previewSize)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(width: Self.previewSize.width, height: Self.previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

/// A small grid diagram showing exactly how many rows/columns the selection
/// would be distributed into — same visual language as
/// `CanvasFractionRegionPreview` (bordered canvas, accent-color fill), but
/// filling every cell instead of one target region, since distribute
/// affects the whole selection rather than positioning a single tile.
private struct DistributeGridPreview: View {
    let shape: TileDistribution.GridShape

    /// Matches `CanvasFractionRegionPreview.previewSize` for visual consistency.
    private static let previewSize = CGSize(width: 26, height: 16)
    private static let cellSpacing: CGFloat = 1.5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
            VStack(spacing: Self.cellSpacing) {
                ForEach(0..<shape.rows, id: \.self) { _ in
                    HStack(spacing: Self.cellSpacing) {
                        ForEach(0..<shape.columns, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(Color.accentColor)
                        }
                    }
                }
            }
            .padding(3)
        }
        .frame(width: Self.previewSize.width, height: Self.previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}
