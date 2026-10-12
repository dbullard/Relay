import SwiftUI

#if os(macOS)
import AppKit
#endif

enum ResizeHandleOrientation {
    case horizontal
    case vertical
    case diagonal
    case verticalTop
    case diagonalTopRight
    case horizontalLeft
    case diagonalTopLeft
    case diagonalBottomLeft
}

#if os(macOS)
/// Bundles one resize handle's macOS drag callbacks and cursor so a single
/// consolidated `DashboardResizeInteractionSurface` can dispatch to it.
struct ResizeHandleController {
    let orientation: ResizeHandleOrientation
    let cursor: NSCursor
    let onDragBegan: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
}
#endif

/// Decides what should happen to the NSCursor push/pop stack as the mouse
/// moves between resize handles, independent of AppKit so the transition
/// logic can be unit tested. `ResizeInteractionNSView` is the only caller;
/// it owns one instance and translates each `Action` into the matching
/// `NSCursor` push/pop call.
struct ResizeHandleHoverCursorTracker {
    enum Action: Equatable {
        /// Nothing changed; leave the cursor stack alone.
        case none
        /// Entering a handle from empty space: push its cursor.
        case push(ResizeHandleOrientation)
        /// Moving directly from one handle to another: pop the old cursor,
        /// push the new one.
        case popThenPush(ResizeHandleOrientation)
        /// Leaving the last-hovered handle: pop its cursor.
        case pop
    }

    private(set) var hoveredOrientation: ResizeHandleOrientation?

    /// - Parameter orientation: the handle currently under the mouse, or
    ///   `nil` if the mouse isn't within any handle's hit radius.
    mutating func update(to orientation: ResizeHandleOrientation?) -> Action {
        defer { hoveredOrientation = orientation }

        switch (hoveredOrientation, orientation) {
        case (nil, nil):
            return .none
        case (nil, .some(let new)):
            return .push(new)
        case (.some, nil):
            return .pop
        case (.some(let old), .some(let new)):
            return old == new ? .none : .popThenPush(new)
        }
    }
}

final class ResizeHandleDragState {
    var dragStartSize: CGSize?
    var dragStartLocation: CGPoint?
    var dragStartBottom: CGFloat?
    var dragStartRight: CGFloat?

    func reset() {
        dragStartSize = nil
        dragStartLocation = nil
        dragStartBottom = nil
        dragStartRight = nil
    }
}

struct ResizeHandle: View {
    /// The tile's current stored size as of this render. Read-only here --
    /// writes flow out through `onResizeChanged` (as one combined value
    /// alongside any offset change), not back through a `Binding`, so the
    /// caller can apply size + offset together as a single atomic mutation.
    /// See `onResizeChanged` below for why that matters.
    let size: CGSize?
    let defaultSize: CGSize
    /// Called when the user begins resizing.
    let onResizeBegan: () -> Void
    /// Called when the user finishes resizing.
    let onResizeEnded: () -> Void
    /// Orientation of this handle; used to pick an appropriate resize cursor on macOS.
    let orientation: ResizeHandleOrientation
    /// The tile's current offset in canvas coordinates (top-left origin).
    let tileOffset: CGSize
    /// All canvas guides (vertical and horizontal) available for snapping.
    let guides: [CanvasGuide]
    /// The overall canvas size, used to snap to outer edges.
    let canvasSize: CGSize
    /// Whether guide snapping is enabled/visible.
    let showGuidesEnabled: Bool
    /// Whether snap-to-grid is enabled for resize gestures.
    let snapToGrid: Bool
    /// Grid size used for snapping (in points).
    let gridSize: CGFloat
    /// Current canvas viewport zoom. macOS AppKit drag events arrive in viewport
    /// coordinates, so resize deltas must be converted back to canvas points.
    let viewportZoom: CGFloat
    let otherTileRects: [CGRect]
    let interactionSession: DashboardTileInteractionSession
    /// Fires once per drag-changed event with the full resize result: the
    /// new size, plus (only when this handle's orientation anchors the
    /// opposite edge) a new top and/or left offset. Bundling all fields
    /// that can change in a single event into one callback lets the caller
    /// apply them as one atomic tile mutation -- necessary because this
    /// method is called synchronously, with no re-render in between, so a
    /// corner-handle drag that changes size AND an offset in the same
    /// event must not be split into separate writes that would each see a
    /// stale snapshot of the caller's tile state and clobber each other.
    let onResizeChanged: (_ size: CGSize, _ newOffsetY: CGFloat?, _ newOffsetX: CGFloat?) -> Void
    /// When true, draw a visible affordance (like Canva) inside the hitbox.
    let showsIndicator: Bool
    let isEnabled: Bool
    let dragState: ResizeHandleDragState
    init(
        size: CGSize?,
        defaultSize: CGSize,
        onResizeBegan: @escaping () -> Void = {},
        onResizeEnded: @escaping () -> Void,
        orientation: ResizeHandleOrientation = .diagonal,
        tileOffset: CGSize,
        guides: [CanvasGuide],
        canvasSize: CGSize,
        showGuidesEnabled: Bool,
        snapToGrid: Bool = false,
        gridSize: CGFloat = 0,
        viewportZoom: CGFloat = 1,
        otherTileRects: [CGRect] = [],
        interactionSession: DashboardTileInteractionSession,
        onResizeChanged: @escaping (_ size: CGSize, _ newOffsetY: CGFloat?, _ newOffsetX: CGFloat?) -> Void = { _, _, _ in },
        showsIndicator: Bool = false,
        isEnabled: Bool = true,
        dragState: ResizeHandleDragState
    ) {
        self.size = size
        self.defaultSize = defaultSize
        self.onResizeBegan = onResizeBegan
        self.onResizeEnded = onResizeEnded
        self.orientation = orientation
        self.tileOffset = tileOffset
        self.guides = guides
        self.canvasSize = canvasSize
        self.showGuidesEnabled = showGuidesEnabled
        self.snapToGrid = snapToGrid
        self.gridSize = gridSize
        self.viewportZoom = viewportZoom
        self.otherTileRects = otherTileRects
        self.interactionSession = interactionSession
        self.onResizeChanged = onResizeChanged
        self.showsIndicator = showsIndicator
        self.isEnabled = isEnabled
        self.dragState = dragState
    }
    private func resetDragState() {
        dragState.reset()
    }

    private func applyResizeDrag(startLocation: CGPoint, currentLocation: CGPoint) {
        guard isEnabled else {
            resetDragState()
            return
        }

        if dragState.dragStartSize == nil {
            onResizeBegan()
            dragState.dragStartSize = size ?? defaultSize
        }

        guard let baseSize = dragState.dragStartSize else {
            return
        }

        if dragState.dragStartBottom == nil {
            dragState.dragStartBottom = tileOffset.height + baseSize.height
        }
        if dragState.dragStartRight == nil {
            dragState.dragStartRight = tileOffset.width + baseSize.width
        }

        #if os(macOS)
        let isShiftDown = NSEvent.modifierFlags.contains(.shift)
        #else
        let isShiftDown = snapToGrid
        #endif

        let result = DashboardResizeSnappingHelper.computeResize(
            baseSize: baseSize,
            startLocation: startLocation,
            currentLocation: currentLocation,
            orientation: orientation,
            tileOffset: tileOffset,
            guides: guides,
            canvasSize: canvasSize,
            showGuidesEnabled: showGuidesEnabled,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            isShiftDown: isShiftDown,
            dragStartBottom: dragState.dragStartBottom,
            dragStartRight: dragState.dragStartRight,
            otherTileRects: otherTileRects
        )

        interactionSession.activeSmartGuides = result.activeGuides

        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            onResizeChanged(result.size, result.newOffsetY, result.newOffsetX)
        }
    }

    private func finishResizeDrag() {
        guard isEnabled else {
            resetDragState()
            return
        }
        resetDragState()
        onResizeEnded()
    }

    @ViewBuilder
    private var indicator: some View {
        if showsIndicator {
            let zoomCompensation = min(max(1 / max(viewportZoom, 0.0001), 1), 2)
            let stroke = Color.white.opacity(0.75)
            let fill = Color.white.opacity(0.6)

            switch orientation {
            case .horizontal:
                // Mid-edge handle: small horizontal pill
                Capsule(style: .continuous)
                    .fill(fill)
                    .overlay(Capsule(style: .continuous).stroke(stroke, lineWidth: 1))
                    .frame(width: 5 * zoomCompensation, height: 14 * zoomCompensation)
            case .horizontalLeft:
                Capsule(style: .continuous)
                    .fill(fill)
                    .overlay(Capsule(style: .continuous).stroke(stroke, lineWidth: 1))
                    .frame(width: 5 * zoomCompensation, height: 14 * zoomCompensation)
            case .vertical, .verticalTop:
                // Mid-edge handle: wide pill (hug the outline)
                Capsule(style: .continuous)
                    .fill(fill)
                    .overlay(Capsule(style: .continuous).stroke(stroke, lineWidth: 1))
                    .frame(width: 14 * zoomCompensation, height: 5 * zoomCompensation)
            case .diagonal, .diagonalTopRight, .diagonalTopLeft, .diagonalBottomLeft:
                // Corner handle: small knob
                Circle()
                    .fill(fill)
                    .overlay(Circle().stroke(stroke, lineWidth: 1))
                    .frame(width: 9 * zoomCompensation, height: 9 * zoomCompensation)
            }
        } else {
            EmptyView()
        }
    }
    var body: some View {
        // Keep the hover/cursor target larger than the visible knob so the resize
        // affordance is easy to acquire with the mouse on macOS.
        let handleHitSize = min(max(28 / max(viewportZoom, 0.0001), 28), 56)
        let gesture = DragGesture(minimumDistance: 0, coordinateSpace: .named("dashboardCanvas"))
            .onChanged { value in
                if dragState.dragStartLocation == nil {
                    dragState.dragStartLocation = value.startLocation
                }
                applyResizeDrag(
                    startLocation: dragState.dragStartLocation ?? value.startLocation,
                    currentLocation: value.location
                )
            }
            .onEnded { _ in
                finishResizeDrag()
            }

        #if os(macOS)
        Color.clear
            .frame(width: handleHitSize, height: handleHitSize)
            .overlay {
                indicator
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(false)
        #else
        ZStack {
            Color.clear
            indicator
        }
        .frame(width: handleHitSize, height: handleHitSize)
        .contentShape(Rectangle())
        .allowsHitTesting(isEnabled)
        .highPriorityGesture(gesture)
        #endif
        }
    }

#if os(macOS)
extension ResizeHandle {
    /// The drag controller for this handle, used by
    /// `DashboardResizeInteractionSurface` to dispatch macOS mouse events
    /// to the correct handle's resize math. Mirrors the logic the handle's
    /// own `MacOSResizeHandleTarget` used before consolidation.
    var controller: ResizeHandleController {
        ResizeHandleController(
            orientation: orientation,
            cursor: cursorForCurrentOrientation(),
            onDragBegan: {
                applyResizeDrag(startLocation: .zero, currentLocation: .zero)
            },
            onDragChanged: { translation in
                let zoom = max(0.0001, viewportZoom)
                let canvasTranslation = CGPoint(
                    x: translation.x / zoom,
                    y: translation.y / zoom
                )
                applyResizeDrag(startLocation: .zero, currentLocation: canvasTranslation)
            },
            onDragEnded: {
                finishResizeDrag()
            }
        )
    }
}
#endif




extension ResizeHandle {
#if os(macOS)
    /// Produces a white‑tinted version of an NSImage by drawing it into a new context.
    private static func whiteTinted(_ image: NSImage) -> NSImage {
        let rect = NSRect(origin: .zero, size: image.size)
        let newImage = NSImage(size: image.size)

        newImage.lockFocus()

        // Fill with white, then use the symbol's alpha as a mask so we get
        // a solid white shape in the symbol's silhouette.
        NSColor.white.setFill()
        rect.fill()

        image.draw(
            in: rect,
            from: .zero,
            operation: .destinationIn,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }

    /// Returns a horizontally mirrored copy of the image, used to flip the
    /// diagonal cursor for the top-right corner so it matches the SF Symbols RTL variant.
    private static func mirroredHorizontally(_ image: NSImage) -> NSImage {
        let size = image.size
        let newImage = NSImage(size: size)

        newImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: size.width, yBy: 0)
        transform.scaleX(by: -1.0, yBy: 1.0)
        transform.concat()

        image.draw(
            at: .zero,
            from: NSRect(origin: .zero, size: size),
            operation: .sourceOver,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }

    /// Returns an SF Symbol–based NSCursor for the given orientation (macOS 11+), falling back to system cursors.
    private func cursorForCurrentOrientation() -> NSCursor {
        Self.cachedCursor(for: orientation)
    }

    private static let cachedHorizontalCursor = makeCursor(for: .horizontal)
    private static let cachedVerticalCursor = makeCursor(for: .vertical)
    private static let cachedDiagonalCursor = makeCursor(for: .diagonal)
    private static let cachedMirroredDiagonalCursor = makeCursor(for: .diagonalTopRight)

    private static func cachedCursor(for orientation: ResizeHandleOrientation) -> NSCursor {
        switch orientation {
        case .horizontal, .horizontalLeft:
            return cachedHorizontalCursor
        case .vertical, .verticalTop:
            return cachedVerticalCursor
        case .diagonal, .diagonalTopLeft:
            return cachedDiagonalCursor
        case .diagonalTopRight, .diagonalBottomLeft:
            return cachedMirroredDiagonalCursor
        }
    }

    private static func makeCursor(for orientation: ResizeHandleOrientation) -> NSCursor {
        let symbolName: String
        switch orientation {
        case .horizontal, .horizontalLeft:
            symbolName = "arrow.left.and.right"
        case .vertical, .verticalTop:
            symbolName = "arrow.up.and.down"
        case .diagonal, .diagonalTopRight, .diagonalTopLeft, .diagonalBottomLeft:
            // Use the same base SF Symbol; we'll mirror it for the top-right case
            // so it visually matches the RTL variant shown in SF Symbols.
            symbolName = "arrow.up.backward.and.arrow.down.forward"
        }

        // Attempt to load SF Symbol as NSImage
        if let baseSymbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: symbolName
        ) {
            // Give each orientation a size that better matches its aspect so it
            // doesn't feel squished when used as a cursor.
            let targetSize: NSSize
            switch orientation {
            case .horizontal, .horizontalLeft:
                // Wider than tall for left/right arrow
                targetSize = NSSize(width: 24, height: 16)
            case .vertical, .verticalTop:
                // Taller than wide for up/down arrow
                targetSize = NSSize(width: 16, height: 24)
            case .diagonal, .diagonalTopRight, .diagonalTopLeft, .diagonalBottomLeft:
                // Slightly larger square for diagonal
                targetSize = NSSize(width: 22, height: 22)
            }

            baseSymbol.size = targetSize

            // Generate a white-tinted cursor graphic
            let tinted = whiteTinted(baseSymbol)

            // For the top-right diagonal handle, mirror the symbol horizontally so
            // it visually matches the RTL variant from SF Symbols.
            let finalImage: NSImage
            switch orientation {
            case .diagonalTopRight, .diagonalBottomLeft:
                // Mirror so bottom-left matches top-right diagonal direction
                finalImage = mirroredHorizontally(tinted)
            default:
                finalImage = tinted
            }

            let hotSpot = NSPoint(x: finalImage.size.width / 2, y: finalImage.size.height / 2)
            return NSCursor(image: finalImage, hotSpot: hotSpot)
        }

        // Fallbacks if symbol fails to load
        switch orientation {
        case .horizontal, .horizontalLeft:
            return .resizeLeftRight
        case .vertical, .verticalTop:
            return .resizeUpDown
        case .diagonal, .diagonalTopRight, .diagonalTopLeft, .diagonalBottomLeft:
            return .resizeLeftRight
        }
    }
    #endif
}

#if os(macOS)
/// A single NSView covering a tile's full halo-extended resize-handle bounds.
///
/// Replaces the previous 8 independent `MacOSResizeHandleTarget` views.
/// `hitTest` returns `nil` outside every handle's hit radius, so clicks in
/// the tile's interior fall through to the SwiftUI move-drag gesture below.
/// Inside a handle's hit radius, the closest handle (by
/// `DashboardTileResizeHandleLayout.closestHandle`) is dispatched to for the
/// duration of the drag.
struct DashboardResizeInteractionSurface: NSViewRepresentable {
    /// The tile's content size (excluding the halo).
    let size: CGSize
    let halo: CGFloat
    let isEnabled: Bool
    /// When non-nil, only these orientations are eligible for hit-testing
    /// (used in group-resize mode, which only allows vertical handles).
    let allowedOrientations: Set<ResizeHandleOrientation>?
    let controllers: [ResizeHandleOrientation: ResizeHandleController]

    func makeNSView(context: Context) -> ResizeInteractionNSView {
        let view = ResizeInteractionNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: ResizeInteractionNSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: ResizeInteractionNSView) {
        view.size = size
        view.halo = halo
        view.isEnabled = isEnabled
        view.allowedOrientations = allowedOrientations
        view.controllers = controllers
    }

    final class ResizeInteractionNSView: NSView {
        var size: CGSize = .zero
        var halo: CGFloat = 0
        var isEnabled: Bool = true
        var allowedOrientations: Set<ResizeHandleOrientation>?
        var controllers: [ResizeHandleOrientation: ResizeHandleController] = [:]
        var isDragging: Bool = false

        private var activeOrientation: ResizeHandleOrientation?
        private var startLocationInWindow: NSPoint?
        private var trackingAreaRef: NSTrackingArea?
        private var didPushDragCursor = false
        private var hoverCursorTracker = ResizeHandleHoverCursorTracker()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Converts a view-local point (AppKit bottom-left origin) to a
        /// canvas-space point (top-left origin, halo-relative) and returns
        /// the closest eligible handle, if any is within range.
        private func handle(at point: NSPoint) -> (orientation: ResizeHandleOrientation, controller: ResizeHandleController)? {
            guard isEnabled else { return nil }
            let layoutPoint = CGPoint(x: point.x - halo, y: (bounds.height - point.y) - halo)
            let layout = DashboardTileResizeHandleLayout(size: size)
            guard let hit = layout.closestHandle(
                to: layoutPoint,
                within: DashboardTileResizeHandleLayout.hitHalo,
                allowedOrientations: allowedOrientations
            ) else {
                return nil
            }
            guard let controller = controllers[hit.orientation] else {
                return nil
            }
            return (hit.orientation, controller)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview else { return nil }
            let localPoint = convert(point, from: superview)
            guard handle(at: localPoint) != nil else { return nil }
            return self
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }

            guard isEnabled else { return }

            let options: NSTrackingArea.Options = [
                .activeInKeyWindow,
                .inVisibleRect,
                .enabledDuringMouseDrag,
                .mouseEnteredAndExited,
                .mouseMoved,
                .cursorUpdate
            ]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingAreaRef = area
        }

        // Cursor is driven entirely by `hoverCursorTracker` below rather than
        // AppKit's legacy `addCursorRect` mechanism. Registering both
        // independently meant a handle's cursor could show (via a cursor
        // rect) in a corner of its square hit-test rect that the *actual*
        // circular `handle(at:)` radius used for clicks didn't cover, or
        // linger after the mouse moved off a handle since nothing ever
        // reset it (`resetCursorRects` only fires on geometry changes, not
        // on every mouse move) — the mismatch this audit was chasing.
        private func updateHoverCursor(at point: NSPoint) {
            guard !isDragging else { return }

            switch hoverCursorTracker.update(to: handle(at: point)?.orientation) {
            case .none:
                break
            case .push(let orientation):
                controllers[orientation]?.cursor.push()
            case .popThenPush(let orientation):
                NSCursor.pop()
                controllers[orientation]?.cursor.push()
            case .pop:
                NSCursor.pop()
            }
        }

        private func clearHoverCursor() {
            if hoverCursorTracker.update(to: nil) == .pop {
                NSCursor.pop()
            }
        }

        override func cursorUpdate(with event: NSEvent) {
            updateHoverCursor(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            updateHoverCursor(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            updateHoverCursor(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            clearHoverCursor()
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard let (orientation, controller) = handle(at: point) else { return }

            // A previous drag can fail to reach `mouseUp` at all (button
            // released outside the window, app resigned key mid-drag, ...).
            // Left stuck, `isDragging` would never let a later drag on this
            // handle complete cleanly, and the pushed cursor would never be
            // popped. Recover before starting fresh.
            if isDragging {
                finishDrag()
            }

            isDragging = true
            activeOrientation = orientation
            startLocationInWindow = event.locationInWindow
            window?.disableCursorRects()
            if !didPushDragCursor {
                controller.cursor.push()
                didPushDragCursor = true
            }
            controller.cursor.set()
            controller.onDragBegan()
        }

        override func mouseDragged(with event: NSEvent) {
            guard isEnabled,
                  let activeOrientation,
                  let controller = controllers[activeOrientation],
                  let startLocationInWindow else { return }

            controller.cursor.set()
            let delta = CGPoint(
                x: event.locationInWindow.x - startLocationInWindow.x,
                // AppKit window coordinates grow upward; canvas coordinates grow downward.
                y: startLocationInWindow.y - event.locationInWindow.y
            )
            controller.onDragChanged(delta)
        }

        override func mouseUp(with event: NSEvent) {
            finishDrag()
        }

        /// Resets all drag bookkeeping (state, pushed cursor, cursor-rect
        /// suspension) so this view is ready for a fresh `mouseDown`. Shared
        /// between the normal `mouseUp` path and `mouseDown`'s recovery from
        /// a previous drag that never received its `mouseUp`.
        private func finishDrag() {
            let controller = activeOrientation.flatMap { controllers[$0] }

            isDragging = false
            activeOrientation = nil
            startLocationInWindow = nil
            if didPushDragCursor {
                NSCursor.pop()
                didPushDragCursor = false
            }
            window?.enableCursorRects()
            if let window {
                window.invalidateCursorRects(for: self)
            }

            controller?.onDragEnded()
        }
    }
}
#endif
