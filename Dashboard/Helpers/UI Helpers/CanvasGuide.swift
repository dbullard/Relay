//
//  CanvasGuide.swift
//  Relay
//
//  Created by David Bullard on 12/1/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A simple draggable guide line, similar to Photoshop/Illustrator guides.
struct CanvasGuide: Identifiable, Codable, Equatable {
    enum Orientation: String, Codable {
        case vertical
        case horizontal
    }

    static let defaultTint = CodableColor(red: 0.24, green: 0.56, blue: 0.98, alpha: 1.0)

    var id: UUID = UUID()
    var orientation: Orientation
    /// Position in canvas coordinates:
    /// - For vertical guides, this is the x position.
    /// - For horizontal guides, this is the y position.
    var position: CGFloat
    var tint: CodableColor? = nil

    var tintColor: Color {
        (tint ?? Self.defaultTint).swiftUIColor
    }
}

/// Overlay that renders and manages all guides on the canvas.
struct GuidesOverlay: View {
    @Binding var guides: [CanvasGuide]
    let canvasSize: CGSize
    let gridSize: CGFloat
    let snapToGrid: Bool
    let viewportZoom: CGFloat
    let viewportPan: CGSize
#if os(macOS)
    /// Effective snap-to-grid: true when the global setting is on OR
    /// when the user is holding Shift while dragging a guide.
    private var effectiveSnapToGrid: Bool {
        snapToGrid || NSEvent.modifierFlags.contains(.shift)
    }
    #else
    /// On non-macOS platforms we only respect the stored snapToGrid flag.
    private var effectiveSnapToGrid: Bool { snapToGrid }
    #endif
    var body: some View {
        let safeZoom = max(0.0001, viewportZoom)
        // This view sits under an ancestor `.scaleEffect(viewportZoom)`, so the local
        // size here is multiplied back up by `safeZoom` on screen. Flooring the local
        // value at 40 (instead of only capping it at 80) would make the on-screen band
        // grow unbounded as the user zooms in past 1x; only the upper bound is needed.
        let interactiveBand = min(40 / safeZoom, 80)
        ZStack(alignment: .topLeading) {
            // Existing guides rendering
            ForEach($guides) { $guide in
                let isVertical = (guide.orientation == .vertical)

                GuideLineView(
                    guide: $guide,
                    canvasSize: canvasSize,
                    gridSize: gridSize,
                    snapToGrid: effectiveSnapToGrid,
                    viewportZoom: viewportZoom,
                    viewportPan: viewportPan,
                    onDelete: {
                        if let idx = guides.firstIndex(where: { $0.id == guide.id }) {
                            guides.remove(at: idx)
                        }
                    }
                )
                // Each guide only occupies a narrow band, not the whole canvas.
                .frame(
                    width: isVertical ? interactiveBand : canvasSize.width,
                    height: isVertical ? canvasSize.height : interactiveBand
                )
                .position(
                    x: isVertical ? guide.position : canvasSize.width / 2,
                    y: isVertical ? canvasSize.height / 2 : guide.position
                )
            }
        }
    }
}

/// Renders a single draggable guide line and handles snapping to the grid.
struct GuideLineView: View {
    @Binding var guide: CanvasGuide
    let canvasSize: CGSize
    let gridSize: CGFloat
    let snapToGrid: Bool
    let viewportZoom: CGFloat
    let viewportPan: CGSize
    let onDelete: () -> Void

    @State private var dragStartPosition: CGFloat?
    @State private var dragStartGlobalAxis: CGFloat?
    @State private var willDelete: Bool = false
    /// Whether this guide is currently being dragged; used to show a
    /// temporary coordinate indicator.
    @State private var isDragging: Bool = false
    @State private var showClueTemporarily: Bool = false
    @State private var isEditorPresented: Bool = false
    @State private var positionDraft: Double = 0
    @State private var clueDismissTask: Task<Void, Never>?
    @StateObject private var modifierTracker = ModifierTracker.shared

    private var tintColor: Color { guide.tintColor }

    var body: some View {
        let safeZoom = max(0.0001, viewportZoom)
        // Same fix as GuidesOverlay.interactiveBand: only cap the upper bound so the
        // on-screen size stays ~constant instead of ballooning above 1x zoom.
        let bandThickness = min(40 / safeZoom, 80)
        let labelScale = min(1 / safeZoom, 2)
        // Local size for this guide view: a thin band around the guide.
        let size = CGSize(
            width: guide.orientation == .vertical ? bandThickness : canvasSize.width,
            height: guide.orientation == .vertical ? canvasSize.height : bandThickness
        )
        let path = guidePath(in: size)

        ZStack {
            // Visual dashed guide line — not hit-testable so it doesn't eat clicks.
            path
                .stroke(
                    willDelete ? Color.red.opacity(0.9) : tintColor.opacity(0.9),
                    style: StrokeStyle(
                        lineWidth: min(3, 1 / safeZoom),
                        dash: [4 / safeZoom, 2 / safeZoom]
                    )
                )
                .allowsHitTesting(false)

            // Temporary coordinate label shown while this guide is being dragged.
            // Center it visibly relative to the user's pan position, accounting for zoom.
            let safeZoom = max(0.0001, viewportZoom)
            let centerX = (size.width / 2) - (guide.orientation == .horizontal ? (viewportPan.width / safeZoom) : 0)
            let centerY = (size.height / 2) - (guide.orientation == .vertical ? (viewportPan.height / safeZoom) : 0)
            let offset: CGFloat = 14

            if isDragging {
                Text(willDelete ? "Release to delete" : guideLabelText())
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, willDelete ? 8 : 4)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(willDelete ? Color.red.opacity(0.85) : tintColor.opacity(0.92))
                    )
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
                    .scaleEffect(labelScale)
                    .position(
                        x: centerX,
                        y: guide.orientation == .vertical ? centerY : centerY + offset
                    )
            } else if showClueTemporarily && !modifierTracker.isModifierPressed {
                Text(dragHintText)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(tintColor.opacity(0.92))
                    )
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
                    .scaleEffect(labelScale)
                    .position(
                        x: centerX,
                        y: guide.orientation == .vertical ? centerY : centerY + offset
                    )
            }

            // Wider invisible strip used only for dragging and delete-on-orthogonal-drag.
            dragStrip(for: size)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !modifierTracker.isModifierPressed {
                        print("[CanvasGuide] Tapped on guide \(guide.id)")
                        showClueTemporarily = true
                        scheduleClueDismiss()
                    }
                }
                .contextMenu {
                    Button("Edit Guide") {
                        positionDraft = Double(guide.position)
                        isEditorPresented = true
                    }
                    Button("Delete Guide", role: .destructive) {
                        onDelete()
                    }
                }
                .popover(isPresented: $isEditorPresented, arrowEdge: .top) {
                    guideEditorPopover
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowGuideModifierClue"))) { notification in
                    if let guideID = notification.object as? UUID, guideID == guide.id {
                        showClueTemporarily = true
                        scheduleClueDismiss()
                    }
                }
                .onChange(of: modifierTracker.isModifierPressed, initial: false) { _, pressed in
                    // Dragging is only attached to this view while the modifier is held
                    // (see `including:` below). If the modifier lifts mid-drag, SwiftUI
                    // tears the gesture recognizer down without ever calling `onEnded`,
                    // which used to leave `isDragging`/`dragStartPosition` stuck and the
                    // guide unresponsive to further input. Reset explicitly instead.
                    guard !pressed, isDragging else { return }
                    dragStartPosition = nil
                    dragStartGlobalAxis = nil
                    isDragging = false
                    willDelete = false
                }
                #if os(macOS)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            handleDragChanged(location: value.location, translation: value.translation)
                        }
                        .onEnded { value in
                            handleDragEnded(translation: value.translation)
                        },
                    including: modifierTracker.isModifierPressed ? .all : .none
                )
                #else
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                        .onChanged { value in
                            guard case .second(true, let drag?) = value else { return }
                            handleDragChanged(location: drag.location, translation: drag.translation)
                        }
                        .onEnded { value in
                            guard case .second(true, let drag?) = value else { return }
                            handleDragEnded(translation: drag.translation)
                        }
                )
                #endif
        }
        .onDisappear {
            clueDismissTask?.cancel()
        }
    }

    /// Schedules `showClueTemporarily` to reset to `false` after a short delay,
    /// cancelling any previously-scheduled dismissal first.
    private func scheduleClueDismiss() {
        clueDismissTask?.cancel()
        clueDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            showClueTemporarily = false
        }
    }

    /// Returns a short label for this guide in canvas pixels.
    private func guideLabelText() -> String {
        let axisPrefix: String
        switch guide.orientation {
        case .vertical:
            axisPrefix = "X"
        case .horizontal:
            axisPrefix = "Y"
        }

        let value = Int(guide.position.rounded())
        return "\(axisPrefix): \(value) px"
    }

    /// The hint shown when the user taps (but doesn't drag) a guide without the
    /// gesture armed — "Hold ⌥" only makes sense where a hardware Option key exists.
    private var dragHintText: String {
        #if os(iOS)
        return "Press and Hold to Drag"
        #else
        return "Hold ⌥ to Drag"
        #endif
    }

    /// Shared position-update math for both the macOS Option-drag gesture and the
    /// iOS long-press-then-drag gesture. `location` must be in `.global` coordinate
    /// space (matching each gesture's `coordinateSpace: .global`).
    private func handleDragChanged(location: CGPoint, translation: CGSize) {
        if dragStartPosition == nil {
            dragStartPosition = guide.position
            switch guide.orientation {
            case .vertical:
                dragStartGlobalAxis = location.x
            case .horizontal:
                dragStartGlobalAxis = location.y
            }
        }

        isDragging = true

        guard
            let start = dragStartPosition,
            let startGlobal = dragStartGlobalAxis
        else { return }

        let deleteThreshold: CGFloat = 180
        let mainDelta: CGFloat
        let orthoDeltaScreen: CGFloat
        let maxExtent: CGFloat
        let zoom = max(0.0001, viewportZoom)

        switch guide.orientation {
        case .vertical:
            mainDelta = (location.x - startGlobal) / zoom
            orthoDeltaScreen = translation.height
            maxExtent = canvasSize.width
        case .horizontal:
            mainDelta = (location.y - startGlobal) / zoom
            orthoDeltaScreen = translation.width
            maxExtent = canvasSize.height
        }

        let rawPosition = start + mainDelta
        let clampedPosition = clamped(rawPosition, maxExtent: maxExtent)

        if snapToGrid, gridSize > 0 {
            guide.position = snapped(clampedPosition, step: gridSize, maxExtent: maxExtent)
        } else {
            guide.position = clampedPosition
        }

        willDelete = abs(orthoDeltaScreen) > deleteThreshold
    }

    private func handleDragEnded(translation: CGSize) {
        defer {
            dragStartPosition = nil
            dragStartGlobalAxis = nil
            isDragging = false
        }
        willDelete = false

        guard let start = dragStartPosition else { return }

        let deleteThreshold: CGFloat = 180
        let mainDelta: CGFloat
        let orthoDeltaScreen: CGFloat
        let maxExtent: CGFloat
        let zoom = max(0.0001, viewportZoom)

        switch guide.orientation {
        case .vertical:
            mainDelta = translation.width / zoom
            orthoDeltaScreen = translation.height
            maxExtent = canvasSize.width
        case .horizontal:
            mainDelta = translation.height / zoom
            orthoDeltaScreen = translation.width
            maxExtent = canvasSize.height
        }

        if abs(orthoDeltaScreen) > deleteThreshold {
            onDelete()
            return
        }

        let finalRaw = start + mainDelta
        let clampedPosition = clamped(finalRaw, maxExtent: maxExtent)

        if snapToGrid, gridSize > 0 {
            guide.position = snapped(clampedPosition, step: gridSize, maxExtent: maxExtent)
        } else {
            guide.position = clampedPosition
        }
    }

    /// Wider invisible strip along the guide used only for drag hit-testing.
    @ViewBuilder
    private func dragStrip(for size: CGSize) -> some View {
        let thickness = min(16 / max(viewportZoom, 0.0001), 32)
        switch guide.orientation {
        case .vertical:
            Rectangle()
                .fill(Color.clear)
                .frame(width: thickness, height: size.height)
                .position(x: size.width / 2, y: size.height / 2)
        case .horizontal:
            Rectangle()
                .fill(Color.clear)
                .frame(width: size.width, height: thickness)
                .position(x: size.width / 2, y: size.height / 2)
        }
    }

    /// Builds the path for the visual guide line based on its orientation and position.
    private func guidePath(in size: CGSize) -> Path {
        var path = Path()
        switch guide.orientation {
        case .vertical:
            // Draw vertical line centered in this view's width.
            let x = size.width / 2
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        case .horizontal:
            // Draw horizontal line centered in this view's height.
            let y = size.height / 2
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        return path
    }
    private func clamped(_ value: CGFloat, maxExtent: CGFloat) -> CGFloat {
        let lower: CGFloat = 0
        let upper = max(0, maxExtent)
        return min(max(value, lower), upper)
    }

    private func snapped(_ value: CGFloat, step: CGFloat, maxExtent: CGFloat) -> CGFloat {
        guard step > 0 else { return clamped(value, maxExtent: maxExtent) }
        let snapped = (value / step).rounded() * step
        return clamped(snapped, maxExtent: maxExtent)
    }

    private var guideEditorPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Guide")
                .font(.headline)

            ColorPicker(
                "Color",
                selection: Binding(
                    get: { guide.tintColor },
                    set: { guide.tint = CodableColor($0) }
                ),
                supportsOpacity: true
            )

            HStack(alignment: .center, spacing: 8) {
                Text(guide.orientation == .vertical ? "X Position" : "Y Position")
                Spacer(minLength: 0)
                TextField(
                    "0",
                    value: $positionDraft,
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                Text("px")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Reset Color") {
                    guide.tint = nil
                }

                Spacer(minLength: 0)

                Button("Apply") {
                    applyPositionDraft()
                    isEditorPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 240)
        .onAppear {
            positionDraft = Double(guide.position)
        }
        .onSubmit {
            applyPositionDraft()
            isEditorPresented = false
        }
    }

    private func applyPositionDraft() {
        let maxExtent = guide.orientation == .vertical ? canvasSize.width : canvasSize.height
        let newPosition = clamped(CGFloat(positionDraft), maxExtent: maxExtent)
        if snapToGrid, gridSize > 0 {
            guide.position = snapped(newPosition, step: gridSize, maxExtent: maxExtent)
        } else {
            guide.position = newPosition
        }
    }
}

// MARK: - Convenience API for adding guides

extension Array where Element == CanvasGuide {
    /// Adds a new guide of the given orientation, offset from any existing
    /// guides of that orientation and clamped within the current canvas.
    mutating func addGuide(
        _ orientation: CanvasGuide.Orientation,
        canvasSize: CGSize,
        gridSize: CGFloat
    ) {
        // Require a non-zero canvas so we don't add at meaningless coordinates.
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        let extent: CGFloat
        switch orientation {
        case .vertical:
            extent = canvasSize.width
        case .horizontal:
            extent = canvasSize.height
        }

        guard extent > 0 else { return }

        // Find the last guide of this orientation, if any, so we can offset from it.
        let existing = self.filter { $0.orientation == orientation }
        let basePosition: CGFloat
        if let last = existing.last {
            let step = gridSize > 0 ? gridSize : 40
            basePosition = last.position + step
        } else {
            basePosition = extent / 2
        }

        // Clamp into the canvas.
        let clampedPosition = Swift.max(0, Swift.min(basePosition, extent))
        let guide = CanvasGuide(orientation: orientation, position: clampedPosition)
        append(guide)
    }
}

// MARK: - Smart Guides

/// A temporary guide line displayed only during drag or resize snapping
struct SmartGuideLine: Equatable, Hashable {
    enum Orientation { case vertical, horizontal }
    var orientation: Orientation
    var position: CGFloat
}

/// Overlay that renders the bright pink smart snapping lines across the entire canvas
struct SmartGuidesOverlay: View {
    var guides: [SmartGuideLine]
    let canvasSize: CGSize
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(guides, id: \.self) { guide in
                Path { path in
                    if guide.orientation == .vertical {
                        path.move(to: CGPoint(x: guide.position, y: 0))
                        path.addLine(to: CGPoint(x: guide.position, y: canvasSize.height))
                    } else {
                        path.move(to: CGPoint(x: 0, y: guide.position))
                        path.addLine(to: CGPoint(x: canvasSize.width, y: guide.position))
                    }
                }
                .stroke(Color.pink, style: StrokeStyle(lineWidth: 1))
                .allowsHitTesting(false)
            }
        }
    }
}
