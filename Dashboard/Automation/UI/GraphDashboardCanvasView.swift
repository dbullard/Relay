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
    var zoom: CGFloat = 1.0

    /// Graph-space positions of nodes being dragged (or nudged by collision resolution)
    /// before they are committed to `tab.graph`.
    private(set) var dragPositions: [UUID: CGPoint] = [:]

    var linkingFromPoint: CGPoint? = nil
    var linkingCurrentPoint: CGPoint? = nil

    var isMarqueeSelecting: Bool = false
    var marqueeStart: CGPoint? = nil
    var marqueeCurrent: CGPoint? = nil

    // Untracked reads: the macro's backing storage, which skips observation registration.
    var untrackedPan: CGSize { _pan }
    var untrackedZoom: CGFloat { _zoom }
    var untrackedLinkingFromPoint: CGPoint? { _linkingFromPoint }
    var untrackedLinkingCurrentPoint: CGPoint? { _linkingCurrentPoint }
    var untrackedIsMarqueeSelecting: Bool { _isMarqueeSelecting }
    var untrackedMarqueeStart: CGPoint? { _marqueeStart }
    var untrackedMarqueeCurrent: CGPoint? { _marqueeCurrent }

    func untrackedDragPosition(for nodeId: UUID) -> CGPoint? {
        _dragPositions[nodeId]
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
}

// MARK: - Store-reading modifiers

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

// MARK: - Links

/// One link to draw. Endpoints are node-center-relative so the canvas can follow live
/// drag positions without the graph view recomputing port geometry.
struct GraphLinkSpec {
    let fromNodeId: UUID
    let fromOffset: CGPoint
    let toNodeId: UUID
    let toOffset: CGPoint
}

/// The in-progress link line while dragging from an output nub.
struct GraphPendingLinkSpec {
    let fromNodeId: UUID
    /// Used when the store has no explicit `linkingFromPoint`.
    let fallbackFromOffset: CGPoint
    let color: Color
}

struct GraphLinksCanvasView: View {
    let links: [GraphLinkSpec]
    let pendingLink: GraphPendingLinkSpec?
    let persistedPositions: [UUID: CGPoint]
    let store: GraphInteractionStore
    let size: CGSize
    let drawPadding: CGFloat

    var body: some View {
        let pad = drawPadding
        // Read tracked state here (not inside the Canvas closure) so the dependency is
        // registered by this view's body.
        let dragPositions = store.dragPositions
        let linkingFromPoint = store.linkingFromPoint
        let linkingCurrentPoint = store.linkingCurrentPoint

        Canvas { context, _ in
            func center(_ nodeId: UUID) -> CGPoint {
                dragPositions[nodeId] ?? persistedPositions[nodeId] ?? .zero
            }
            func shifted(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x + pad, y: p.y + pad)
            }
            func point(_ nodeId: UUID, _ offset: CGPoint) -> CGPoint {
                let c = center(nodeId)
                return shifted(CGPoint(x: c.x + offset.x, y: c.y + offset.y))
            }

            for link in links {
                let path = Self.bezierPath(
                    from: point(link.fromNodeId, link.fromOffset),
                    to: point(link.toNodeId, link.toOffset)
                )
                context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 2.0)
            }

            if let pendingLink, let current = linkingCurrentPoint {
                let start = linkingFromPoint.map(shifted)
                    ?? point(pendingLink.fromNodeId, pendingLink.fallbackFromOffset)
                let path = Self.bezierPath(from: start, to: shifted(current))
                context.stroke(path, with: .color(pendingLink.color), lineWidth: 2.0)
            }
        }
        .frame(width: size.width + pad * 2, height: size.height + pad * 2)
        .offset(x: -pad, y: -pad)
        .allowsHitTesting(false)
    }

    static func bezierPath(from p0: CGPoint, to p3: CGPoint) -> Path {
        var path = Path()
        path.move(to: p0)
        let dxRaw = (p3.x - p0.x) * 0.45
        let dx = max(80, abs(dxRaw))
        let c1 = CGPoint(x: p0.x + dx, y: p0.y)
        let c2 = CGPoint(x: p3.x - dx, y: p3.y)
        path.addCurve(to: p3, control1: c1, control2: c2)
        return path
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
        @Bindable var interaction = interaction

        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(count: 2) {
                    guard isWorkEnabled, !showAddNodePopover else { return }
                    onBackgroundDoubleTap()
                }

            ZStack(alignment: .topLeading) {
                ZStack {
                    content
                }
                .frame(width: geoSize.width, height: geoSize.height, alignment: .topLeading)
                .coordinateSpace(.named("GraphSpace"))
                .modifier(GraphViewportTransform(store: interaction))
            }
            .frame(width: geoSize.width, height: geoSize.height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(!showAddNodePopover)
            .viewportPanZoom(
                pan: $interaction.pan,
                zoom: $interaction.zoom,
                isEnabled: isWorkEnabled && !showAddNodePopover,
                showsControls: false,
                blocksOverScrollableViews: false
            )

            if showAddNodePopover {
                popover()
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
    }
}
