import SwiftUI
import Observation

// MARK: - Interaction store

/// High-frequency Automation canvas state: viewport pan/zoom, live node drag positions,
/// the in-progress link line, and the marquee rectangle.
///
/// This lives outside `GraphDashboardView`'s `@State` on purpose. Those values change on
/// every scroll tick or mouse move; as `@State` on the graph view they re-ran its entire
/// body (every node, the links, the grid) per event, which is why the canvas got sluggish
/// as nodes were added. Only the small views/modifiers below read the tracked properties,
/// so only they update per event.
///
/// Code that runs inside `GraphDashboardView` (gesture handlers and helpers that can also
/// be called while its body is evaluated) must use the `untracked…` accessors. Reading
/// the tracked properties from that body would subscribe the whole graph view again.
@Observable
final class GraphInteractionStore {
    var pan: CGSize = .zero
    /// Set through `setZoom(_:)` so `isZoomedOut` stays in sync.
    private(set) var zoom: CGFloat = 1.0

    /// Below this zoom, nodes render as compact summary cards (their form text is too small
    /// to read, and full forms make every zoom step expensive). Hysteresis keeps it from
    /// flipping back and forth around the threshold. Changes only when the threshold is
    /// crossed, so the graph view can read it without re-rendering on every zoom step.
    private(set) var isZoomedOut: Bool = false
    static let zoomedOutEnterBelow: CGFloat = 0.55
    static let zoomedOutExitAbove: CGFloat = 0.65
    /// True while a pan/zoom gesture is in progress (debounced by the viewport monitor).
    var isInteracting: Bool = false

    /// Node sizes reported since the last apply. Bookkeeping only, never rendered.
    @ObservationIgnored var pendingNodeSizes: [UUID: CGSize] = [:]

    /// Graph-space positions of nodes being dragged (or nudged by collision resolution)
    /// before they are committed to `tab.graph`.
    private(set) var dragPositions: [UUID: CGPoint] = [:]

    var linkingFromPoint: CGPoint? = nil
    var linkingCurrentPoint: CGPoint? = nil

    var isMarqueeSelecting: Bool = false
    var marqueeStart: CGPoint? = nil
    var marqueeCurrent: CGPoint? = nil

    /// Link the user clicked; Delete removes it. Only the links canvas and the selected-link
    /// toolbar read it, so selecting a link doesn't re-run the graph body.
    var selectedLinkId: UUID? = nil
    /// Link under the pointer, drawn highlighted.
    var hoveredLinkId: UUID? = nil

    /// Link geometry from the last graph render, for hit-testing clicks without re-running
    /// the graph body. Bookkeeping only, never rendered from directly.
    @ObservationIgnored var linkHitSpecs: [GraphLinkSpec] = []
    @ObservationIgnored var linkHitPositions: [UUID: CGPoint] = [:]

    // Untracked reads: the macro's backing storage, which skips observation registration.
    var untrackedPan: CGSize { _pan }
    var untrackedZoom: CGFloat { _zoom }
    var untrackedLinkingFromPoint: CGPoint? { _linkingFromPoint }
    var untrackedLinkingCurrentPoint: CGPoint? { _linkingCurrentPoint }
    var untrackedIsMarqueeSelecting: Bool { _isMarqueeSelecting }
    var untrackedMarqueeStart: CGPoint? { _marqueeStart }
    var untrackedMarqueeCurrent: CGPoint? { _marqueeCurrent }
    var untrackedSelectedLinkId: UUID? { _selectedLinkId }
    var untrackedHoveredLinkId: UUID? { _hoveredLinkId }

    func untrackedDragPosition(for nodeId: UUID) -> CGPoint? {
        _dragPositions[nodeId]
    }

    func setZoom(_ newZoom: CGFloat) {
        guard newZoom != _zoom else { return }
        zoom = newZoom
        let zoomedOut = _isZoomedOut
            ? newZoom < Self.zoomedOutExitAbove
            : newZoom < Self.zoomedOutEnterBelow
        if zoomedOut != _isZoomedOut { isZoomedOut = zoomedOut }
    }

    /// Binding for gesture/controls code; writes go through `setZoom(_:)`.
    var zoomBinding: Binding<CGFloat> {
        Binding(get: { self.zoom }, set: { self.setZoom($0) })
    }

    /// Observation notifies on every write, even for an equal value, so skip no-ops.
    func setDragPosition(_ point: CGPoint?, for nodeId: UUID) {
        if let point {
            guard _dragPositions[nodeId] != point else { return }
            dragPositions[nodeId] = point
        } else {
            guard _dragPositions[nodeId] != nil else { return }
            dragPositions.removeValue(forKey: nodeId)
        }
    }

    /// One observation update for a group drag instead of one per node.
    func setDragPositions(_ updates: [UUID: CGPoint]) {
        guard updates.contains(where: { _dragPositions[$0.key] != $0.value }) else { return }
        dragPositions.merge(updates) { _, new in new }
    }

    func clearDragPositions(_ nodeIds: [UUID]) {
        guard nodeIds.contains(where: { _dragPositions[$0] != nil }) else { return }
        let ids = Set(nodeIds)
        dragPositions = _dragPositions.filter { !ids.contains($0.key) }
    }

    func setLinkingFromPoint(_ point: CGPoint?) {
        guard _linkingFromPoint != point else { return }
        linkingFromPoint = point
    }

    func setLinkingCurrentPoint(_ point: CGPoint?) {
        guard _linkingCurrentPoint != point else { return }
        linkingCurrentPoint = point
    }

    func setMarqueeSelecting(_ value: Bool) {
        guard _isMarqueeSelecting != value else { return }
        isMarqueeSelecting = value
    }

    func setMarqueeStart(_ point: CGPoint?) {
        guard _marqueeStart != point else { return }
        marqueeStart = point
    }

    func setMarqueeCurrent(_ point: CGPoint?) {
        guard _marqueeCurrent != point else { return }
        marqueeCurrent = point
    }

    func setSelectedLinkId(_ id: UUID?) {
        guard _selectedLinkId != id else { return }
        selectedLinkId = id
    }

    func setHoveredLinkId(_ id: UUID?) {
        guard _hoveredLinkId != id else { return }
        hoveredLinkId = id
    }

    /// Graph-space endpoints of the cached links, following live drag positions.
    func untrackedLinkCurves() -> [GraphLinkGeometry.Curve] {
        GraphLinkGeometry.curves(
            for: linkHitSpecs,
            center: { nodeId in self._dragPositions[nodeId] ?? self.linkHitPositions[nodeId] ?? .zero }
        )
    }
}

// MARK: - Store-reading modifiers

/// Hides the graph from accessibility while the viewport is being panned or zoomed.
/// When any accessibility client is attached (VoiceOver, window managers, automation
/// tools), SwiftUI recomputes accessibility attachments for every gesture on every node
/// each frame the nodes move, which was about a third of main-thread time during zoom.
/// The tree is restored ~0.15s after the gesture ends.
struct GraphInteractionAccessibility: ViewModifier {
    let store: GraphInteractionStore

    func body(content: Content) -> some View {
        content.accessibilityHidden(store.isInteracting)
    }
}

/// Installs the scroll/pinch handling with bindings built here, inside the modifier.
/// SwiftUI compares a child's `Binding` inputs by reading their values, and that read happens
/// in the parent's update. Building `$store.pan` / `store.zoomBinding` in a large body (the
/// canvas view, the graph scene) silently subscribed that body to pan and zoom, so every zoom
/// frame rebuilt every node. Here only this modifier subscribes; `content` is a placeholder.
struct GraphViewportPanZoom: ViewModifier {
    let store: GraphInteractionStore
    let isEnabled: Bool

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.viewportPanZoom(
            pan: $store.pan,
            zoom: store.zoomBinding,
            isInteracting: $store.isInteracting,
            isEnabled: isEnabled,
            showsControls: false,
            blocksOverScrollableViews: false
        )
    }
}

/// Zoom buttons and percentage menu for the graph, with its bindings built here for the same
/// reason as `GraphViewportPanZoom`.
struct GraphViewportZoomControls: View {
    let store: GraphInteractionStore
    let viewportSize: CGSize
    let onActualSize: () -> Void
    let onFitToWindow: () -> Void

    var body: some View {
        @Bindable var store = store
        ViewportPanZoomControls(
            pan: $store.pan,
            zoom: store.zoomBinding,
            zoomRange: 0.25...2.5,
            viewportSize: viewportSize,
            onActualSize: onActualSize,
            onFitToWindow: onFitToWindow
        )
    }
}

/// Applies the viewport pan/zoom. Only this modifier re-runs on scroll/pinch; the graph
/// content it wraps is not rebuilt.
struct GraphViewportTransform: ViewModifier {
    let store: GraphInteractionStore

    func body(content: Content) -> some View {
        content
            .scaleEffect(store.zoom, anchor: .topLeading)
            .offset(x: store.pan.width, y: store.pan.height)
    }
}

/// Positions a node at its live drag position, falling back to the persisted layout.
/// During a drag only these tiny modifiers re-run, not the node bodies.
struct GraphNodePositioner: ViewModifier {
    let nodeId: UUID
    let persistedPosition: CGPoint
    let store: GraphInteractionStore

    func body(content: Content) -> some View {
        content.position(store.dragPositions[nodeId] ?? persistedPosition)
    }
}

/// Reports a node's size, but not while the viewport is being panned or zoomed: sizes don't
/// change then, and the geometry query otherwise re-ran for every node on every frame.
/// Re-attaching after the gesture reports the current size once (a no-op if unchanged).
struct GraphNodeSizeReporter: View {
    let store: GraphInteractionStore
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        if !store.isInteracting {
            Color.clear.onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
                onSizeChange(newSize)
            }
        }
    }
}

/// Marquee selection rectangle (view space).
struct GraphMarqueeOverlay: View {
    let store: GraphInteractionStore

    var body: some View {
        if store.isMarqueeSelecting, let start = store.marqueeStart, let current = store.marqueeCurrent {
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: max(1, abs(current.x - start.x)),
                height: max(1, abs(current.y - start.y))
            )
            Path { p in p.addRect(rect) }
                .stroke(Color.accentColor.opacity(0.9), lineWidth: 1.5)
                .background(
                    Path { p in p.addRect(rect) }
                        .fill(Color.accentColor.opacity(0.15))
                )
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Grid

/// Dot grid drawn in screen space from the current pan/zoom. It used to be a canvas
/// several thousand points on each side inside the zoomed content (~20k dots), which was
/// re-rasterized on zoom and redrawn on every graph re-render. This draws only the
/// visible dots and re-runs only when the viewport changes.
struct GraphViewportGrid: View {
    let store: GraphInteractionStore

    var body: some View {
        let zoom = max(0.0001, store.zoom)
        let pan = store.pan
        Canvas { context, size in
            let step: CGFloat = 40 * zoom
            let majorEvery = 4
            // Too dense to read when zoomed far out: keep only the major dots.
            let drawMinor = step >= 12
            let minorDot = max(1, 2 * zoom)
            let majorDot = max(1.5, 3 * zoom)

            // Graph-space dot (col * 40, row * 40) appears at (col * step + pan).
            let firstCol = Int((-pan.width / step).rounded(.down)) - 1
            let lastCol = Int(((size.width - pan.width) / step).rounded(.up)) + 1
            let firstRow = Int((-pan.height / step).rounded(.down)) - 1
            let lastRow = Int(((size.height - pan.height) / step).rounded(.up)) + 1
            guard lastCol >= firstCol, lastRow >= firstRow else { return }

            var minorPath = Path()
            var majorPath = Path()
            for row in firstRow...lastRow {
                let isMajorRow = row % majorEvery == 0
                if !drawMinor && !isMajorRow { continue }
                let y = CGFloat(row) * step + pan.height
                for col in firstCol...lastCol {
                    let isMajor = isMajorRow && col % majorEvery == 0
                    if !isMajor && !drawMinor { continue }
                    let x = CGFloat(col) * step + pan.width
                    if isMajor {
                        majorPath.addEllipse(in: CGRect(x: x, y: y, width: majorDot, height: majorDot))
                    } else {
                        minorPath.addEllipse(in: CGRect(x: x, y: y, width: minorDot, height: minorDot))
                    }
                }
            }
            context.fill(minorPath, with: .color(Color.white.opacity(0.10)))
            context.fill(majorPath, with: .color(Color.white.opacity(0.16)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Links

/// One link to draw. Endpoints are node-center-relative so the canvas can follow live
/// drag positions without the graph view recomputing port geometry.
struct GraphLinkSpec: Equatable {
    let linkId: UUID
    let fromNodeId: UUID
    let fromOffset: CGPoint
    let toNodeId: UUID
    let toOffset: CGPoint
    /// Event/trigger flow (drawn solid) vs data/value flow (drawn dashed, in a different colour).
    var isEventFlow: Bool = true
}

/// Pure link-curve geometry: the bezier every link is drawn with, and hit-testing against it.
enum GraphLinkGeometry {
    struct Curve: Equatable {
        let id: UUID
        let from: CGPoint
        let to: CGPoint
    }

    /// Control points of the link curve from `p0` to `p3` (horizontal tangents).
    static func controlPoints(from p0: CGPoint, to p3: CGPoint) -> (CGPoint, CGPoint) {
        let dx = max(80, abs((p3.x - p0.x) * 0.45))
        return (CGPoint(x: p0.x + dx, y: p0.y), CGPoint(x: p3.x - dx, y: p3.y))
    }

    /// Point at `t` (0...1) on the link curve.
    static func point(at t: CGFloat, from p0: CGPoint, to p3: CGPoint) -> CGPoint {
        let (c1, c2) = controlPoints(from: p0, to: p3)
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p3.y
        )
    }

    /// Shortest distance from `point` to the link curve, measured against a fine polyline.
    static func distance(from point: CGPoint, toCurveFrom p0: CGPoint, to p3: CGPoint, segments: Int = 48) -> CGFloat {
        let count = max(2, segments)
        var best = CGFloat.greatestFiniteMagnitude
        var previous = p0
        for i in 1...count {
            let next = self.point(at: CGFloat(i) / CGFloat(count), from: p0, to: p3)
            best = min(best, distance(from: point, toSegment: previous, next))
            previous = next
        }
        return best
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared))
        return hypot(p.x - (a.x + t * abx), p.y - (a.y + t * aby))
    }

    /// Bounding box of the curve (endpoints plus control points contain it).
    static func bounds(from p0: CGPoint, to p3: CGPoint) -> CGRect {
        let (c1, c2) = controlPoints(from: p0, to: p3)
        let xs = [p0.x, p3.x, c1.x, c2.x], ys = [p0.y, p3.y, c1.y, c2.y]
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    /// The nearest curve within `tolerance` of `point`, or nil.
    static func hitTest(_ point: CGPoint, curves: [Curve], tolerance: CGFloat) -> UUID? {
        var best: (id: UUID, distance: CGFloat)?
        for curve in curves {
            guard bounds(from: curve.from, to: curve.to).insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            let d = distance(from: point, toCurveFrom: curve.from, to: curve.to)
            if d <= tolerance, d < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (curve.id, d)
            }
        }
        return best?.id
    }

    static func curves(for specs: [GraphLinkSpec], center: (UUID) -> CGPoint) -> [Curve] {
        specs.map { spec in
            let a = center(spec.fromNodeId), b = center(spec.toNodeId)
            return Curve(
                id: spec.linkId,
                from: CGPoint(x: a.x + spec.fromOffset.x, y: a.y + spec.fromOffset.y),
                to: CGPoint(x: b.x + spec.toOffset.x, y: b.y + spec.toOffset.y)
            )
        }
    }
}

/// The in-progress link line while dragging from an output nub.
struct GraphPendingLinkSpec: Equatable {
    let fromNodeId: UUID
    /// Used when the store has no explicit `linkingFromPoint`.
    let fallbackFromOffset: CGPoint
    let color: Color
}

/// Equatable (used with `.equatable()`) so a graph-view re-render that didn't change any
/// link doesn't redraw this large canvas. Live drag/link updates come through `store`.
struct GraphLinksCanvasView: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.links == rhs.links &&
            lhs.pendingLink == rhs.pendingLink &&
            lhs.persistedPositions == rhs.persistedPositions &&
            lhs.store === rhs.store &&
            lhs.size == rhs.size &&
            lhs.drawPadding == rhs.drawPadding
    }

    let links: [GraphLinkSpec]
    let pendingLink: GraphPendingLinkSpec?
    let persistedPositions: [UUID: CGPoint]
    let store: GraphInteractionStore
    let size: CGSize
    let drawPadding: CGFloat
    /// Context-menu "Delete Link" on a wire (macOS). Not part of `==`.
    var onDeleteLink: ((UUID) -> Void)? = nil

    /// Event flow: solid white. Data flow: dashed cyan, so the two differ by more than colour.
    static let eventFlowColor = Color.white.opacity(0.45)
    static let dataFlowColor = Color(red: 0.45, green: 0.82, blue: 1.0).opacity(0.65)
    static let dataFlowDash: [CGFloat] = [7, 5]

    private struct Stroke {
        let from: CGPoint
        let to: CGPoint
        let color: Color
        let lineWidth: CGFloat
        let dash: [CGFloat]
    }

    var body: some View {
        let pad = drawPadding
        // Read tracked state here (not inside the Canvas closure) so the dependency is
        // registered by this view's body.
        let dragPositions = store.dragPositions
        let linkingFromPoint = store.linkingFromPoint
        let linkingCurrentPoint = store.linkingCurrentPoint
        let selectedLinkId = store.selectedLinkId
        let hoveredLinkId = store.hoveredLinkId

        // Resolve every curve in graph space up front, then draw them into a canvas sized
        // to just their bounds. The layout frame stays the original oversized area (an
        // invisible Color.clear, which costs nothing to draw) so placement is unchanged,
        // but the rendered layer is only as big as the links. A canvas thousands of points
        // wide was re-rasterized at every zoom step, which made zoom stutter while pan
        // (a plain translation) stayed smooth.
        func center(_ nodeId: UUID) -> CGPoint {
            dragPositions[nodeId] ?? persistedPositions[nodeId] ?? .zero
        }
        func point(_ nodeId: UUID, _ offset: CGPoint) -> CGPoint {
            let c = center(nodeId)
            return CGPoint(x: c.x + offset.x, y: c.y + offset.y)
        }
        var strokes: [Stroke] = links.map { spec in
            let isSelected = spec.linkId == selectedLinkId
            let isHovered = spec.linkId == hoveredLinkId
            let base = spec.isEventFlow ? Self.eventFlowColor : Self.dataFlowColor
            return Stroke(
                from: point(spec.fromNodeId, spec.fromOffset),
                to: point(spec.toNodeId, spec.toOffset),
                color: isSelected ? Color.accentColor.opacity(0.95) : (isHovered ? base.opacity(1) : base),
                lineWidth: isSelected ? 3.5 : (isHovered ? 3 : 2),
                dash: spec.isEventFlow ? [] : Self.dataFlowDash
            )
        }
        // Draw the selected link last so it sits on top where links cross.
        if let selectedIndex = links.firstIndex(where: { $0.linkId == selectedLinkId }) {
            strokes.append(strokes.remove(at: selectedIndex))
        }
        if let pendingLink, let current = linkingCurrentPoint {
            let start = linkingFromPoint ?? point(pendingLink.fromNodeId, pendingLink.fallbackFromOffset)
            strokes.append(Stroke(from: start, to: current, color: pendingLink.color, lineWidth: 2, dash: []))
        }
        let bounds = Self.bounds(of: strokes.map { ($0.from, $0.to) })
        // Hit targets for hover and the context menu; skipped while dragging, when they'd be
        // rebuilt every frame and nothing can be clicked anyway.
        let showsHitTargets = dragPositions.isEmpty && linkingCurrentPoint == nil && !links.isEmpty

        return Color.clear
            .frame(width: size.width + pad * 2, height: size.height + pad * 2)
            .overlay(alignment: .topLeading) {
                if let bounds {
                    Canvas { context, _ in
                        func local(_ p: CGPoint) -> CGPoint {
                            CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY)
                        }
                        for stroke in strokes {
                            let path = Self.bezierPath(from: local(stroke.from), to: local(stroke.to))
                            context.stroke(
                                path,
                                with: .color(stroke.color),
                                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, dash: stroke.dash)
                            )
                        }
                    }
                    .frame(width: bounds.width, height: bounds.height)
                    // Overlay space: graph point p sits at p + pad (the frame is offset by -pad).
                    .offset(x: bounds.minX + pad, y: bounds.minY + pad)
                    .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                if showsHitTargets {
                    ZStack(alignment: .topLeading) {
                        ForEach(links, id: \.linkId) { spec in
                            let from = point(spec.fromNodeId, spec.fromOffset)
                            let to = point(spec.toNodeId, spec.toOffset)
                            linkHitTarget(
                                linkId: spec.linkId,
                                path: Self.bezierPath(
                                    from: CGPoint(x: from.x + pad, y: from.y + pad),
                                    to: CGPoint(x: to.x + pad, y: to.y + pad)
                                )
                            )
                        }
                    }
                }
            }
            .offset(x: -pad, y: -pad)
    }

    /// Invisible band along one wire: hover highlight, and on macOS a "Delete Link" context
    /// menu. Clicks pass through to the scene, which selects links by `GraphLinkGeometry`.
    @ViewBuilder
    private func linkHitTarget(linkId: UUID, path: Path) -> some View {
        let target = Color.clear
            .contentShape(path.strokedPath(StrokeStyle(lineWidth: 12, lineCap: .round)))
            .onHover { inside in
                if inside {
                    store.setHoveredLinkId(linkId)
                } else if store.untrackedHoveredLinkId == linkId {
                    store.setHoveredLinkId(nil)
                }
            }
            .accessibilityHidden(true)
        #if os(macOS)
        target.contextMenu {
            Button("Delete Link", role: .destructive) {
                onDeleteLink?(linkId)
            }
        }
        #else
        target
        #endif
    }

    /// Bounding box of the bezier curves (their endpoints plus control points, which
    /// contain the curve), padded for the stroke width. Nil when there's nothing to draw.
    static func bounds(of curves: [(CGPoint, CGPoint)]) -> CGRect? {
        var rect: CGRect?
        for (p0, p3) in curves {
            let r = GraphLinkGeometry.bounds(from: p0, to: p3)
            rect = rect?.union(r) ?? r
        }
        return rect?.insetBy(dx: -4, dy: -4)
    }

    static func bezierPath(from p0: CGPoint, to p3: CGPoint) -> Path {
        var path = Path()
        path.move(to: p0)
        let (c1, c2) = GraphLinkGeometry.controlPoints(from: p0, to: p3)
        path.addCurve(to: p3, control1: c1, control2: c2)
        return path
    }
}

/// Small toolbar at the selected link's midpoint (view space) with Delete Link: the touch
/// and pointer path to removing one wire. Delete/Backspace does the same.
struct GraphSelectedLinkOverlay: View {
    let store: GraphInteractionStore
    let onDelete: (UUID) -> Void

    var body: some View {
        if let linkId = store.selectedLinkId,
           let spec = store.linkHitSpecs.first(where: { $0.linkId == linkId }) {
            let drag = store.dragPositions
            let pan = store.pan
            let zoom = store.zoom
            let curve = GraphLinkGeometry.curves(for: [spec]) { nodeId in
                drag[nodeId] ?? store.linkHitPositions[nodeId] ?? .zero
            }[0]
            let mid = GraphLinkGeometry.point(at: 0.5, from: curve.from, to: curve.to)
            Button {
                onDelete(linkId)
            } label: {
                Label("Delete Link", systemImage: "trash")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: graphMinimumHitTarget)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.8), lineWidth: 1))
            .fixedSize()
            .position(x: mid.x * zoom + pan.width, y: mid.y * zoom + pan.height - graphMinimumHitTarget)
            .help("Delete this link (Delete key)")
        }
    }
}

// MARK: - Canvas container

struct GraphDashboardCanvasView<Content: View, Popover: View>: View {
    let geoSize: CGSize
    let isWorkEnabled: Bool
    @Binding var showAddNodePopover: Bool
    let interaction: GraphInteractionStore
    let onBackgroundDoubleTap: () -> Void
    /// Built once by the caller (not a closure re-invoked from this body) so viewport
    /// updates never rebuild the graph content.
    let content: Content
    @ViewBuilder let popover: () -> Popover

    init(
        geoSize: CGSize,
        isWorkEnabled: Bool,
        showAddNodePopover: Binding<Bool>,
        interaction: GraphInteractionStore,
        onBackgroundDoubleTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder popover: @escaping () -> Popover
    ) {
        self.geoSize = geoSize
        self.isWorkEnabled = isWorkEnabled
        self._showAddNodePopover = showAddNodePopover
        self.interaction = interaction
        self.onBackgroundDoubleTap = onBackgroundDoubleTap
        self.content = content()
        self.popover = popover
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(count: 2) {
                    guard isWorkEnabled, !showAddNodePopover else { return }
                    onBackgroundDoubleTap()
                }

            GraphViewportGrid(store: interaction)
                .frame(width: geoSize.width, height: geoSize.height)

            ZStack(alignment: .topLeading) {
                ZStack {
                    content
                }
                .graphNodeControlStyles()
                .frame(width: geoSize.width, height: geoSize.height, alignment: .topLeading)
                .coordinateSpace(.named("GraphSpace"))
                .modifier(GraphViewportTransform(store: interaction))
                .modifier(GraphInteractionAccessibility(store: interaction))
            }
            .frame(width: geoSize.width, height: geoSize.height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(!showAddNodePopover)
            .modifier(GraphViewportPanZoom(store: interaction, isEnabled: isWorkEnabled && !showAddNodePopover))

            if showAddNodePopover {
                popover()
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
    }
}
