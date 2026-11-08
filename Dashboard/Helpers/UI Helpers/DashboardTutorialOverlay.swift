//
//  TutorialAnchor.swift
//  Relay
//
//  Created by David Bullard on 1/31/26.
//


import SwiftUI
import Combine



// MARK: - Public API

/// Attach to any view you want to highlight during the tutorial.
/// Use a stable id string (e.g. "toolbar.graphToggle", "left.tabs", "inspector", etc.)
struct TutorialAnchor: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: TutorialAnchorPreferenceKey.self,
                            value: [id: proxy.frame(in: .named("tutorialRoot"))]
                        )
                }
            )
    }
}

extension View {
    func tutorialAnchor(_ id: String) -> some View {
        modifier(TutorialAnchor(id: id))
    }
}

/// A controller you can keep in `DashboardRootView` as a @StateObject.
final class DashboardTutorialController: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var stepIndex: Int = 0
    @Published private(set) var context: DashboardTutorialContext = DashboardTutorialContext(
        kind: .canvas,
        platform: .current
    )

    /// Steps can be swapped per screen/feature set.
    var steps: [DashboardTutorialStep] = []

    func start(kind: DashboardTutorialKind = .canvas) {
        let nextContext = DashboardTutorialContext(
            kind: kind,
            platform: .current
        )
        start(context: nextContext)
    }

    func start(context: DashboardTutorialContext) {
        self.context = context
        self.steps = DashboardTutorialStep.steps(for: context)
        stepIndex = 0
        isPresented = true
    }

    func stop() {
        isPresented = false
        stepIndex = 0
    }

    func next() {
        let next = stepIndex + 1
        if next >= steps.count {
            stop()
        } else {
            stepIndex = next
        }
    }

    func back() {
        stepIndex = max(0, stepIndex - 1)
    }
}

// MARK: - Steps

enum DashboardTutorialKind: String, Equatable {
    case canvas
    case automation
}

enum TutorialPlatform: String, Equatable {
    case mac
    case iPad
    case iPhone

    static var current: TutorialPlatform {
#if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
#else
        return .mac
#endif
    }
}

struct DashboardTutorialContext: Equatable {
    let kind: DashboardTutorialKind
    let platform: TutorialPlatform
}

enum TutorialCompletionTrigger: String, Equatable {
    case manual
    case anchorFocused
    case actionPerformed
}

enum TutorialStepPresentation: String, Equatable {
    case standard
    case onboardingWizardPrompt
}

struct DashboardTutorialStep: Identifiable, Equatable {
    let id: String
    let kind: DashboardTutorialKind
    let anchorId: String
    let title: String
    let message: String
    let sectionLabel: String?
    let supplement: TutorialSupplement?
    let placement: CalloutPlacement
    let calloutOffset: CGSize
    let presentation: TutorialStepPresentation
    let expectedAction: String?
    let completionTrigger: TutorialCompletionTrigger?
    let canAdvanceAutomatically: Bool

    static func steps(for context: DashboardTutorialContext) -> [DashboardTutorialStep] {
        switch context.kind {
        case .canvas:
            return canvasSteps(for: context)
        case .automation:
            return automationSteps(for: context)
        }
    }

    private static func step(
        id: String,
        kind: DashboardTutorialKind,
        anchorId: String,
        title: String,
        message: String,
        sectionLabel: String? = nil,
        supplement: TutorialSupplement? = nil,
        placement: CalloutPlacement = .auto,
        calloutOffset: CGSize = .zero,
        presentation: TutorialStepPresentation = .standard,
        expectedAction: String? = nil,
        completionTrigger: TutorialCompletionTrigger? = nil,
        canAdvanceAutomatically: Bool = false
    ) -> DashboardTutorialStep {
        DashboardTutorialStep(
            id: id,
            kind: kind,
            anchorId: anchorId,
            title: title,
            message: message,
            sectionLabel: sectionLabel,
            supplement: supplement,
            placement: placement,
            calloutOffset: calloutOffset,
            presentation: presentation,
            expectedAction: expectedAction,
            completionTrigger: completionTrigger,
            canAdvanceAutomatically: canAdvanceAutomatically
        )
    }


    private static func canvasSteps(for context: DashboardTutorialContext) -> [DashboardTutorialStep] {
        let (tap, doubleTap) = interactionCopy(for: context.platform)
        return [
            step(
                id: "canvas",
                kind: .canvas,
                anchorId: "root.canvas",
                title: "Build your dashboard",
                message: "This canvas is your control room. Drag tiles into position and shape the layout.",
                sectionLabel: "Build Your Dashboard",
                supplement: .canvasDragDemo,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -20)
            ),
            step(
                id: "add",
                kind: .canvas,
                anchorId: "root.addMenu",
                title: "Add a tile",
                message: "\(tap) Add to place a tile, then drag to arrange.",
                sectionLabel: "Add and Arrange Tiles",
                supplement: .addTileDemo,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -20)
            ),
            step(
                id: "overview",
                kind: .canvas,
                anchorId: "root.overviewButton",
                title: "Overview",
                message: "Scan all tiles at once and jump directly to the one you need.",
                sectionLabel: "Organize and Review",
                supplement: .overviewDemo,
                placement: .below,
                calloutOffset: CGSize(width: 0, height: 28)
            ),
            step(
                id: "tabs",
                kind: .canvas,
                anchorId: "root.tabs",
                title: "Organize tabs",
                message: "\(tap) to switch dashboards, drag to reorder your run order.",
                sectionLabel: "Organize and Review",
                supplement: .tabsPreview,
                placement: .below,
                calloutOffset: CGSize(width: 0, height: 28)
            ),
            step(
                id: "planningCenter",
                kind: .canvas,
                anchorId: "root.tabSettings",
                title: "Tab Settings",
                message: "Set the Planning Center service, plan, and other tab-level options from here.",
                sectionLabel: "Tab Settings",
                supplement: .pcoSetupDemo,
                placement: .below,
                calloutOffset: CGSize(width: 0, height: 36)
            ),
            step(
                id: "rosters",
                kind: .canvas,
                anchorId: "root.rosters",
                title: "Rosters",
                message: "Open the shared Rosters library to manage General, Equipment, and future People rosters for this dashboard.",
                sectionLabel: "Rosters",
                placement: .below,
                calloutOffset: CGSize(width: 0, height: 36)
            ),
            step(
                id: "settings",
                kind: .canvas,
                anchorId: "root.settings",
                title: "Settings",
                message: "Manage connections, devices, LAN sharing, OSC, and MIDI in one place.",
                sectionLabel: "Settings",
                supplement: .settingsDemo,
                placement: .below,
                calloutOffset: CGSize(width: 0, height: 44)
            ),
            step(
                id: "inspector",
                kind: .canvas,
                anchorId: "root.inspectorButton",
                title: "Edit with Inspector",
                message: "Select a tile, then use Inspector to adjust content and style.",
                sectionLabel: "Edit with Inspector",
                supplement: .inspectorDemo,
                placement: .below,
                calloutOffset: CGSize(width: 0, height: 45)
            ),
            step(
                id: "liveMode",
                kind: .canvas,
                anchorId: "root.canvas",
                title: "Go Live",
                message: context.platform == .mac ? "Live Mode turns your dashboard into a clean, real-time view. Use View → Live Mode or ⌘+L to toggle." : "Live Mode turns your dashboard into a clean, real-time view. \(doubleTap) to exit.",
                sectionLabel: "Go Live",
                supplement: .liveModeDemo,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -20)
            ),
            step(
                id: "onboardingWizardOffer",
                kind: .canvas,
                anchorId: "root.addMenu",
                title: "Set up your first dashboard",
                message: "",
                sectionLabel: "Guided Setup",
                supplement: nil,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -20),
                presentation: .onboardingWizardPrompt,
                expectedAction: nil,
                completionTrigger: .manual
            )
        ]
    }

    private static func automationSteps(for context: DashboardTutorialContext) -> [DashboardTutorialStep] {
        [
            step(
                id: "automationIntro",
                kind: .automation,
                anchorId: "root.graph",
                title: "What automation does",
                message: "Automation lets triggers run actions across your tools. For example, using OSC to trigger events on a audio console.",
                sectionLabel: "Automation Basics",
                supplement: .automationSignalDemo,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -10),
                expectedAction: nil,
                completionTrigger: .manual
            ),
            step(
                id: "automationCanvasBacked",
                kind: .automation,
                anchorId: "root.graph",
                title: "Canvas-backed nodes",
                message: "Some nodes stay linked to your dashboard tiles so changes stay in sync.",
                sectionLabel: "Automation Basics",
                supplement: .automationCanvasBackedDemo,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -10),
                expectedAction: nil,
                completionTrigger: .manual
            ),
            step(
                id: "automationAddNode",
                kind: .automation,
                anchorId: "root.graph",
                title: "Add a node",
                message: "Use the Add menu to drop triggers, sources, and actions onto the canvas.",
                sectionLabel: "Automation Basics",
                supplement: .automationAddNodeDemo,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -10),
                expectedAction: nil,
                completionTrigger: .manual
            ),
            step(
                id: "automationNodeTypes",
                kind: .automation,
                anchorId: "root.graph",
                title: "Know your node types",
                message: "Each type has a role in your flow:",
                sectionLabel: "Automation Basics",
                supplement: .automationNodeTypesDemo,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -10),
                expectedAction: nil,
                completionTrigger: .manual
            ),
            step(
                id: "automationLink",
                kind: .automation,
                anchorId: "root.graph",
                title: "Link nodes",
                message: "Drag from a node output to connect it to the next step.",
                sectionLabel: "Automation Basics",
                supplement: .automationConnectionDemo,
                placement: .center,
                calloutOffset: CGSize(width: 0, height: -10),
                expectedAction: nil,
                completionTrigger: .manual
            )
        ]
    }


    private static func interactionCopy(for platform: TutorialPlatform) -> (String, String) {
        switch platform {
        case .mac:
            return ("Click", "Double-click")
        case .iPad, .iPhone:
            return ("Tap", "Double-tap")
        }
    }
}

enum TutorialSupplement: String, Equatable {
    case toolbarIcons
    case addMenu
    case canvasTips
    case graphTips
    case inspectorTips
    case settingsList
    case addTileDemo
    case canvasDragDemo
    case inspectorDemo
    case liveModeDemo
    case automationSignalDemo
    case automationConnectionDemo
    case automationAddNodeDemo
    case automationCanvasBackedDemo
    case automationNodeTypesDemo
    case tabsPreview
    case overviewDemo
    case pcoSetupDemo
    case settingsDemo
}

enum CalloutPlacement: String, Equatable {
    case auto
    case above
    case below
    case left
    case right
    case center
}

private struct ArrowLine: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

private struct ArrowHead: Shape {
    let tip: CGPoint
    let angle: CGFloat

    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 8

        let leftAngle = angle + .pi - .pi / 6
        let rightAngle = angle + .pi + .pi / 6

        let left = CGPoint(
            x: tip.x + cos(leftAngle) * length,
            y: tip.y + sin(leftAngle) * length
        )
        let right = CGPoint(
            x: tip.x + cos(rightAngle) * length,
            y: tip.y + sin(rightAngle) * length
        )

        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}

// MARK: - Preferences

struct TutorialAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Overlay View

/// A dimming overlay that highlights a specific anchored rect and shows a coachmark bubble.
struct DashboardTutorialOverlay: View {
    @ObservedObject var controller: DashboardTutorialController
    let anchors: [String: CGRect]
    let lanSharingEnabled: Bool
    let onOnboardingWizardRequested: () -> Void

    /// If you need to offset for safe areas / titlebars you can do it here later.
    var cornerRadius: CGFloat = 14
    var spotlightPadding: CGFloat = 4

    @Namespace private var highlightNamespace
    @State private var highlightPulse: Bool = false

    private let debugAnchors: Bool = false

    var body: some View {
        // This overlay depends on anchors, so it must be applied ABOVE the UI
        // that emits `.tutorialAnchor(...)` preferences.
        GeometryReader { proxy in
            overlayBody(proxy: proxy, anchors: anchors)
                .overlay(alignment: .topLeading) {
                    if controller.isPresented && debugAnchors {
                        debugAnchorOverlay()
                    }
                }
        }
        .allowsHitTesting(controller.isPresented) // receive tutorial interactions while presented
        .accessibilityHidden(!controller.isPresented)
        .opacity(controller.isPresented ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.25), value: controller.isPresented)
#if os(macOS)
        .focusable(controller.isPresented)
        .onMoveCommand { direction in
            guard controller.isPresented else { return }
            switch direction {
            case .left:
                controller.back()
            case .right:
                controller.next()
            default:
                break
            }
        }
        .onExitCommand {
            guard controller.isPresented else { return }
            controller.stop()
        }
#endif
        .onChange(of: controller.isPresented, initial: true) { _, isPresented in
            if isPresented {
                highlightPulse = false
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    highlightPulse = true
                }
            } else {
                highlightPulse = false
            }
        }
    }

    @ViewBuilder
    private func overlayBody(proxy: GeometryProxy, anchors: [String: CGRect]) -> some View {
        if controller.isPresented, controller.stepIndex < controller.steps.count {
            let step = controller.steps[controller.stepIndex]
            let rect = anchors[step.anchorId]
            let highlightRect = rect?.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
            let firstHighlightIndex = controller.steps.firstIndex(where: { $0.anchorId != "root.canvas" }) ?? 0
            let shouldAnimateHighlight = controller.stepIndex > firstHighlightIndex
            let allowsCoachmarkHitTesting = step.presentation == .onboardingWizardPrompt
            let allowHighlightPulse = step.kind != .automation

            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(0)

                if let highlightRect {
                    if !shouldSkipHighlight(for: step) {
                        // Outline highlight only (no dimming scrim).
                        let outline = RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                            )
                            .frame(
                                width: max(0, highlightRect.width),
                                height: max(0, highlightRect.height)
                            )
                            .position(x: highlightRect.midX, y: highlightRect.midY)
                            .animation(shouldAnimateHighlight ? .spring(response: 0.38, dampingFraction: 0.82) : .none, value: highlightRect)
                            .allowsHitTesting(false)

                        Group {
                            if shouldAnimateHighlight {
                                outline.matchedGeometryEffect(id: "tutorialHighlight", in: highlightNamespace)
                            } else {
                                outline
                            }
                        }
                        .overlay {
                            if allowHighlightPulse {
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                                    .frame(
                                        width: max(0, highlightRect.width),
                                        height: max(0, highlightRect.height)
                                    )
                                    .position(x: highlightRect.midX, y: highlightRect.midY)
                                    .scaleEffect(highlightPulse ? 1.08 : 0.96)
                                    .opacity(highlightPulse ? 0.0 : 0.55)
                                    .allowsHitTesting(false)
                            }
                        }
                        .transaction { txn in
                            if !shouldAnimateHighlight {
                                txn.disablesAnimations = true
                            }
                        }
                    }

                    coachmark(step: step, near: highlightRect, in: proxy.size)
                        .allowsHitTesting(allowsCoachmarkHitTesting)
                } else {
                    // If the anchor isn’t available (layout not on-screen), still show the copy.
                    coachmark(step: step, near: CGRect(x: proxy.size.width/2, y: proxy.size.height/2, width: 1, height: 1), in: proxy.size)
                        .allowsHitTesting(allowsCoachmarkHitTesting)
                }

                tutorialControls(in: proxy.size)
                    .allowsHitTesting(true)
                    .zIndex(2)
            }
        }
    }

    private func coachmark(step: DashboardTutorialStep, near rect: CGRect, in size: CGSize) -> some View {
        let isOnboardingWizardPrompt = step.presentation == .onboardingWizardPrompt
        let baseWidth: CGFloat = {
            if isOnboardingWizardPrompt { return 440 }
            if step.kind == .automation { return 520 }
            return 330
        }()
        let bubbleWidth: CGFloat = min(baseWidth, size.width - 48)
        let bubbleHeightEstimate: CGFloat = isOnboardingWizardPrompt ? 260 : 210
        let margin: CGFloat = 16
        let progressText = "\(controller.stepIndex + 1) of \(controller.steps.count)"

        let bubbleX = size.width / 2
        let bubbleY = size.height / 2

        let clampedBubbleX = clamp(bubbleX, margin + bubbleWidth / 2, size.width - margin - bubbleWidth / 2)
        let clampedBubbleY = clamp(bubbleY, margin + bubbleHeightEstimate / 2, size.height - margin - bubbleHeightEstimate / 2)
        let adjustedBubbleY = clampedBubbleY

        return ZStack {
            if isOnboardingWizardPrompt {
                VStack(spacing: 16) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    Text("Set up your first dashboard")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("We'll walk through connecting your services, finding devices on your network, and choosing audio inputs — then build a dashboard from what you set up.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Skip") {
                            controller.stop()
                        }
                        .buttonStyle(.bordered)
                        Button("Set Up Now") {
                            onOnboardingWizardRequested()
                            controller.stop()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(width: bubbleWidth)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(radius: 14)
                .transition(.opacity.combined(with: .scale))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    calloutHeader(sectionLabel: step.sectionLabel, progressText: progressText)

                    HStack(spacing: 6) {
                        Text(step.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    Text(step.message)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    if let expectedAction = step.expectedAction {
                        Text("Try: \(expectedAction)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    if let supplement = step.supplement {
                        supplementView(supplement)
                    }

                    if step.id == "tabs" {
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "wifi")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            Text(lanSharingEnabled
                                 ? "LAN tabs are on — connected tabs show up here."
                                 : "LAN tabs are off — enable LAN Sharing in Settings to mirror tabs.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(width: bubbleWidth, alignment: .leading)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(radius: 14)
                .zIndex(1)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .position(x: clampedBubbleX, y: adjustedBubbleY)
    }

    private func adjustedBubbleY(
        originalY: CGFloat,
        bubbleCenterX: CGFloat,
        bubbleSize: CGSize,
        targetRect: CGRect,
        canvasSize: CGSize,
        margin: CGFloat
    ) -> CGFloat {
        let bubbleRect = CGRect(
            x: bubbleCenterX - bubbleSize.width / 2,
            y: originalY - bubbleSize.height / 2,
            width: bubbleSize.width,
            height: bubbleSize.height
        )

        let belowY = targetRect.maxY + margin + bubbleSize.height / 2
        let aboveY = targetRect.minY - margin - bubbleSize.height / 2
        let clampedBelow = clamp(belowY, margin + bubbleSize.height / 2, canvasSize.height - margin - bubbleSize.height / 2)
        let clampedAbove = clamp(aboveY, margin + bubbleSize.height / 2, canvasSize.height - margin - bubbleSize.height / 2)

        // Top-toolbar anchors should always push the bubble below to avoid overlap.
        if targetRect.minY < 120 {
            return clampedBelow
        }

        guard bubbleRect.intersects(targetRect) else { return originalY }

        if abs(clampedBelow - originalY) < abs(clampedAbove - originalY) {
            return clampedBelow
        }
        return clampedAbove
    }

    private func calloutHeader(sectionLabel: String?, progressText: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if let sectionLabel {
                Text(sectionLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            Spacer()
            Text(progressText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func supplementView(_ supplement: TutorialSupplement) -> some View {
        Group {
            switch supplement {
            case .addTileDemo:
                TutorialAddTileDemo()
            case .canvasDragDemo:
                TutorialCanvasDragDemo()
            case .inspectorDemo:
                TutorialInspectorDemo()
            case .liveModeDemo:
                TutorialLiveModeDemo()
            case .automationConnectionDemo:
                TutorialAutomationDemo(showPulse: false)
            case .automationSignalDemo:
                TutorialAutomationSignalDemo()
            case .automationAddNodeDemo:
                TutorialAutomationAddNodeDemo()
            case .automationCanvasBackedDemo:
                TutorialAutomationCanvasBackedDemo()
            case .automationNodeTypesDemo:
                TutorialAutomationNodeTypesDemo()
            case .tabsPreview:
                TutorialTabsPreview()
            case .overviewDemo:
                TutorialOverviewDemo()
            case .toolbarIcons:
                HStack(spacing: 10) {
                    DashboardSymbolLabel("Canvas", preferred: "square.grid.2x2")
                    DashboardSymbolLabel("Automation", preferred: "point.3.connected.trianglepath.dotted")
                    Label("Settings", systemImage: "gearshape")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 10))

            case .addMenu:
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Add Tile / Guide")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 10))

            case .canvasTips:
                VStack(alignment: .leading, spacing: 4) {
                    DashboardSymbolLabel("Drag tiles to move", preferred: "arrow.up.and.down.and.arrow.left.and.right")
                    DashboardSymbolLabel("Shift-click to multi-select", preferred: "cursorarrow.and.square.on.square.dashed")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 10))

            case .graphTips:
                VStack(alignment: .leading, spacing: 4) {
                    DashboardSymbolLabel("Connect nodes", preferred: "point.3.connected.trianglepath.dotted")
                    Label("Send data to consoles", systemImage: "paperplane")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 10))

            case .inspectorTips:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Edit module settings", systemImage: "slider.horizontal.3")
                    Label("Adjust tile style", systemImage: "paintbrush")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 10))

            case .settingsList:
                VStack(alignment: .leading, spacing: 6) {
                    DashboardSymbolLabel("External Connections", preferred: "link.badge.plus")
                    DashboardSymbolLabel("External Devices", preferred: "externaldrive.connected.to.line.below")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 10))

            case .pcoSetupDemo:
                TutorialPCOSetupDemo()

            case .settingsDemo:
                TutorialSettingsDemo()
            }
        }
    }

    private struct TutorialDemoCard<Content: View>: View {
        let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            content
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private struct TutorialMiniCanvas<Content: View>: View {
        let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.1))
                TutorialCanvasGrid(spacing: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                content
            }
            .frame(height: 86)
        }
    }

    private struct TutorialCanvasGrid: Shape {
        let spacing: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            stride(from: rect.minX, through: rect.maxX, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            stride(from: rect.minY, through: rect.maxY, by: spacing).forEach { y in
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            return path
        }
    }

    private struct TutorialAddTileDemo: View {
        @State private var pulse: Bool = false
        @State private var tileVisible: Bool = false

        var body: some View {
            TutorialDemoCard {
                TutorialMiniCanvas {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 44, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .offset(x: -16, y: 6)
                        .scaleEffect(tileVisible ? 1.0 : 0.2)
                        .opacity(tileVisible ? 1.0 : 0.0)

                    Circle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .overlay(Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.white))
                        .scaleEffect(pulse ? 1.1 : 0.9)
                        .offset(x: 28, y: -18)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                    tileVisible = true
                }
            }
        }
    }

    private struct TutorialCanvasDragDemo: View {
        @State private var dragOffset: CGFloat = -16

        var body: some View {
            TutorialDemoCard {
                TutorialMiniCanvas {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: 42, height: 26)
                        .offset(x: 16, y: -8)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 42, height: 26)
                        .offset(x: dragOffset, y: 8)
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    dragOffset = 18
                }
            }
        }
    }

    private struct TutorialInspectorDemo: View {
        @State private var highlight: Bool = false

        var body: some View {
            TutorialDemoCard {
                HStack(spacing: 12) {
                    TutorialMiniCanvas {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 46, height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(highlight ? 0.8 : 0.3), lineWidth: 1.5)
                            )
                            .scaleEffect(highlight ? 1.02 : 1.0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Edit Tile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(highlight ? 0.18 : 0.1))
                            .frame(height: 18)
                            .overlay(alignment: .leading) {
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.35))
                                        .frame(width: 10, height: 10)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.35))
                                        .frame(width: 40, height: 6)
                                }
                                .padding(.horizontal, 6)
                            }
                        HStack {
                            Text("Add Module")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 12, height: 12)
                                .overlay(Image(systemName: "plus").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 6) {
                            sliderRow(width: 86)
                            sliderRow(width: 72)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    highlight = true
                }
            }
        }

        private func sliderRow(width: CGFloat) -> some View {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: width, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 22, height: 6)
            }
        }
    }

    private struct TutorialPCOSetupDemo: View {
        @State private var pulse: Bool = false

        var body: some View {
            TutorialDemoCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Planning Center")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.green.opacity(pulse ? 0.9 : 0.6))
                            Text("Service • Plan")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 36, height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 28, height: 6)
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private struct TutorialSettingsDemo: View {
        @State private var pulse: Bool = false

        var body: some View {
            TutorialDemoCard {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let phase = time.truncatingRemainder(dividingBy: 2.4)
                    let first = min(max(phase / 0.7, 0), 1)
                    let second = min(max((phase - 0.4) / 0.7, 0), 1)
                    let third = min(max((phase - 0.8) / 0.7, 0), 1)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            settingsRow(title: "Connections", icon: "link.badge.plus", checkmarkOpacity: first)
                            settingsRow(title: "Devices", icon: "externaldrive.connected.to.line.below", checkmarkOpacity: second)
                            settingsRow(title: "MIDI/OSC", icon: "bolt.fill", checkmarkOpacity: third)
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color.white.opacity(pulse ? 0.35 : 0.18))
                                .frame(width: 16, height: 16)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 34, height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 26, height: 6)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }

        private func settingsRow(title: String, icon: String, checkmarkOpacity: Double) -> some View {
            HStack(spacing: 6) {
                DashboardSymbolImage(icon)
                Text(title)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.85))
                    .opacity(checkmarkOpacity)
            }
        }
    }

    private struct TutorialLiveModeDemo: View {
        @State private var pulse: Bool = false

        var body: some View {
            TutorialDemoCard {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .overlay {
                            TimelineView(.animation) { context in
                                let time = context.date.timeIntervalSinceReferenceDate
                                let fade = 1 - min(max((time.truncatingRemainder(dividingBy: 2.2)) / 1.2, 0), 1)
                                TutorialCanvasGrid(spacing: 12)
                                    .stroke(Color.white.opacity(0.18 * fade), lineWidth: 1)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 70, height: 38)
                        }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red.opacity(pulse ? 1.0 : 0.4))
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.top, 6)
                    .padding(.leading, 8)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private struct TutorialAutomationDemo: View {
        let showPulse: Bool

        init(showPulse: Bool = true) {
            self.showPulse = showPulse
        }

        var body: some View {
            TutorialDemoCard {
                TutorialAutomationNodes(showPulse: showPulse)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
    }

    private struct TutorialAutomationSignalDemo: View {
        var body: some View {
            TutorialDemoCard {
                TutorialAutomationSignalNodes()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
    }

    private struct TutorialAutomationNodeTypesDemo: View {
        var body: some View {
            TutorialDemoCard {
                VStack(alignment: .leading, spacing: 8) {
                    nodeTypeRow(
                        title: "Triggers",
                        color: Color.orange.opacity(0.9),
                        detail: "Start flows from timers, OSC, MIDI, and other events."
                    )
                    nodeTypeRow(
                        title: "Sources",
                        color: Color.gray.opacity(0.9),
                        detail: "Provide data and context for the actions you run."
                    )
                    nodeTypeRow(
                        title: "Actions",
                        color: Color.green.opacity(0.9),
                        detail: "Send commands to consoles, apps, and devices."
                    )
                    nodeTypeRow(
                        title: "Destinations",
                        color: Color.blue.opacity(0.85),
                        detail: "Devices you set up in External Devices, ready to receive actions."
                    )
                    nodeTypeRow(
                        title: "Utility",
                        color: Color.purple.opacity(0.9),
                        detail: "Transform, delay, and route signals between nodes."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private func nodeTypeRow(title: String, color: Color, detail: String) -> some View {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color, in: Capsule())
                    .frame(width: 80, alignment: .center)
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 18, height: 1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct TutorialAutomationAddNodeDemo: View {
        @State private var pulse: Bool = false

        var body: some View {
            TutorialDemoCard {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 160, height: 70)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .overlay(alignment: .leading) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                                .offset(x: -3)
                        }
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.9))
                            .frame(width: 30, height: 30)
                            .overlay(Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.white))
                            .scaleEffect(pulse ? 1.06 : 0.94)
                        Text("Add Node")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private struct TutorialAutomationCanvasBackedDemo: View {
        @State private var pop: Bool = false

        var body: some View {
            TutorialDemoCard {
                TutorialMiniCanvas {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 90, height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                Text("Tile")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(8)
                            }
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 132, height: 58)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                Text("Node")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(8)
                            }
                            .overlay(alignment: .topTrailing) {
                                HStack(spacing: 4) {
                                    DashboardSymbolImage("square.grid.2x2")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Text("Canvas")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.12), in: Capsule())
                                .padding(6)
                            }
                            .scaleEffect(pop ? 1.0 : 0.2, anchor: .leading)
                            .offset(x: pop ? 104 : 0, y: pop ? -12 : 0)
                            .opacity(pop ? 1.0 : 0.0)
                    }
                }
                .frame(height: 120)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                    pop = true
                }
            }
        }
    }

    private struct AutomationNodeCard: View {
        let size: CGSize
        let nubOffset: CGFloat
        let title: String
        let subtitle: String
        let chip: String
        let chipColor: Color
        let systemImage: String
        let showLeadingNub: Bool
        let showTrailingNub: Bool
        let pulseStrength: CGFloat

        var body: some View {
            let clampedPulse = max(0, min(1, pulseStrength))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    DashboardSymbolImage(systemImage)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text(chip)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(chipColor, in: Capsule())
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 18)
            }
            .padding(10)
            .frame(width: size.width, height: size.height)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if showLeadingNub {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .offset(x: -nubOffset)
                }
            }
            .overlay(alignment: .trailing) {
                if showTrailingNub {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .offset(x: nubOffset)
                }
            }
            .overlay {
                if clampedPulse > 0.01 {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.6 * clampedPulse), lineWidth: 1)
                        .scaleEffect(1.02 + 0.03 * clampedPulse)
                }
            }
        }
    }

    private struct TutorialAutomationNodes: View {
        let showPulse: Bool

        @State private var pulse: Bool = false

        init(showPulse: Bool = true) {
            self.showPulse = showPulse
        }

        private let nodeSize = CGSize(width: 190, height: 80)
        private let spacing: CGFloat = 36
        private let nubOffset: CGFloat = 3

        var body: some View {
            let totalWidth = nodeSize.width * 2 + spacing
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let travelDuration: Double = 1.2
                let holdDuration: Double = 1.6
                let cycle = travelDuration + holdDuration
                let phase = time.truncatingRemainder(dividingBy: cycle)
                let travelProgress = min(max(phase / travelDuration, 0), 1)

                ZStack {
                    HStack(spacing: spacing) {
                        AutomationNodeCard(
                            size: nodeSize,
                            nubOffset: nubOffset,
                            title: "OSC",
                            subtitle: "Trigger",
                            chip: "TRIGGER",
                            chipColor: Color.orange.opacity(0.85),
                            systemImage: "waveform.path",
                            showLeadingNub: false,
                            showTrailingNub: true,
                            pulseStrength: showPulse ? (pulse ? 1.0 : 0.0) : 0.0
                        )
                        AutomationNodeCard(
                            size: nodeSize,
                            nubOffset: nubOffset,
                            title: "Console",
                            subtitle: "Destination",
                            chip: "DESTINATION",
                            chipColor: Color.blue.opacity(0.85),
                            systemImage: "hifispeaker.fill",
                            showLeadingNub: true,
                            showTrailingNub: false,
                            pulseStrength: 0.0
                        )
                    }
                    .frame(width: totalWidth, height: nodeSize.height)
                    .overlay {
                        GeometryReader { proxy in
                            let size = proxy.size
                            let midY = size.height / 2
                            let leftCenterX = nodeSize.width / 2
                            let rightCenterX = nodeSize.width + spacing + nodeSize.width / 2
                            let start = CGPoint(x: leftCenterX + nodeSize.width / 2 + nubOffset, y: midY)
                            let end = CGPoint(x: rightCenterX - nodeSize.width / 2 - nubOffset, y: midY)
                            let control1 = CGPoint(x: start.x + 40, y: start.y - 18)
                            let control2 = CGPoint(x: end.x - 40, y: end.y + 18)
                            Path { path in
                                path.move(to: start)
                                path.addCurve(to: end, control1: control1, control2: control2)
                            }
                            .trim(from: 0, to: CGFloat(travelProgress))
                            .stroke(Color.white.opacity(0.7), lineWidth: 2)
                        }
                    }
                }
                .frame(width: totalWidth, height: nodeSize.height)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .onAppear {
                if showPulse {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
            }
        }

        private func bezierPoint(
            t: CGFloat,
            start: CGPoint,
            control1: CGPoint,
            control2: CGPoint,
            end: CGPoint
        ) -> CGPoint {
            let oneMinusT = 1 - t
            let a = oneMinusT * oneMinusT * oneMinusT
            let b = 3 * oneMinusT * oneMinusT * t
            let c = 3 * oneMinusT * t * t
            let d = t * t * t
            return CGPoint(
                x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                y: a * start.y + b * control1.y + c * control2.y + d * end.y
            )
        }
    }

    private struct TutorialAutomationSignalNodes: View {
        private let nodeSize = CGSize(width: 190, height: 80)
        private let spacing: CGFloat = 36
        private let nubOffset: CGFloat = 3

        var body: some View {
            let totalWidth = nodeSize.width * 2 + spacing
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let travelDuration: Double = 0.75
                let holdDuration: Double = 1.65
                let cycle = travelDuration + holdDuration
                let phase = time.truncatingRemainder(dividingBy: cycle)
                let travelProgress = min(max(phase / travelDuration, 0), 1)
                let oscPulse = pulseWindow(phase: phase, center: 0.08, width: 0.16)
                let consolePulse = pulseWindow(phase: phase, center: travelDuration + 0.15, width: 0.18)

                ZStack {
                    HStack(spacing: spacing) {
                        AutomationNodeCard(
                            size: nodeSize,
                            nubOffset: nubOffset,
                            title: "OSC",
                            subtitle: "Trigger",
                            chip: "TRIGGER",
                            chipColor: Color.orange.opacity(0.85),
                            systemImage: "waveform.path",
                            showLeadingNub: false,
                            showTrailingNub: true,
                            pulseStrength: CGFloat(oscPulse)
                        )
                        AutomationNodeCard(
                            size: nodeSize,
                            nubOffset: nubOffset,
                            title: "Console",
                            subtitle: "Destination",
                            chip: "DESTINATION",
                            chipColor: Color.blue.opacity(0.85),
                            systemImage: "slider.horizontal.3",
                            showLeadingNub: true,
                            showTrailingNub: false,
                            pulseStrength: CGFloat(consolePulse)
                        )
                    }
                    .frame(width: totalWidth, height: nodeSize.height)
                    .overlay {
                        GeometryReader { proxy in
                            let size = proxy.size
                            let midY = size.height / 2
                            let leftCenterX = nodeSize.width / 2
                            let rightCenterX = nodeSize.width + spacing + nodeSize.width / 2
                            let start = CGPoint(x: leftCenterX + nodeSize.width / 2 + nubOffset, y: midY)
                            let end = CGPoint(x: rightCenterX - nodeSize.width / 2 - nubOffset, y: midY)
                            let control1 = CGPoint(x: start.x + 40, y: start.y - 18)
                            let control2 = CGPoint(x: end.x - 40, y: end.y + 18)
                            let point = bezierPoint(
                                t: CGFloat(travelProgress),
                                start: start,
                                control1: control1,
                                control2: control2,
                                end: end
                            )
                            Path { path in
                                path.move(to: start)
                                path.addCurve(to: end, control1: control1, control2: control2)
                            }
                            .stroke(Color.white.opacity(0.7), lineWidth: 2)
                            let isTraveling = phase <= travelDuration
                            let fadeOut = max(0, min(1, (1 - (CGFloat(travelProgress) - 0.85) / 0.15)))
                            let dotOpacity = isTraveling ? fadeOut : 0
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .shadow(color: Color.accentColor.opacity(0.6 * dotOpacity), radius: 4, x: 0, y: 0)
                                .position(point)
                                .opacity(dotOpacity)
                            Circle()
                                .fill(Color.accentColor.opacity(0.25 * dotOpacity))
                                .frame(width: 14, height: 14)
                                .position(point)
                                .opacity(dotOpacity)
                        }
                    }
                }
                .frame(width: totalWidth, height: nodeSize.height)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }

        private func bezierPoint(
            t: CGFloat,
            start: CGPoint,
            control1: CGPoint,
            control2: CGPoint,
            end: CGPoint
        ) -> CGPoint {
            let oneMinusT = 1 - t
            let a = oneMinusT * oneMinusT * oneMinusT
            let b = 3 * oneMinusT * oneMinusT * t
            let c = 3 * oneMinusT * t * t
            let d = t * t * t
            return CGPoint(
                x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                y: a * start.y + b * control1.y + c * control2.y + d * end.y
            )
        }

        private func pulseWindow(phase: Double, center: Double, width: Double) -> Double {
            let normalized = max(0, 1 - abs(phase - center) / width)
            let eased = normalized * normalized
            return min(max(eased, 0), 1)
        }
    }


    private struct TutorialTabsPreview: View {
        var body: some View {
            TutorialDemoCard {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let index = Int((time / 1.2).truncatingRemainder(dividingBy: 3))
                    HStack(spacing: 6) {
                        tabPill(title: "Tab 1", isActive: index == 0)
                        tabPill(title: "Tab 2", isActive: index == 1)
                        tabPill(title: "Tab 3", isActive: index == 2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }

        private func tabPill(title: String, isActive: Bool) -> some View {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isActive ? Color.white.opacity(0.9) : Color.white.opacity(0.12), in: Capsule())
        }
    }

    private struct TutorialOverviewDemo: View {
        var body: some View {
            TutorialDemoCard {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let selectedIndex = Int((time / 1.4).truncatingRemainder(dividingBy: 2))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                            Text("Search tiles")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Circle()
                                .fill(Color.white.opacity(0.16))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.6))
                                )
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())

                        HStack {
                            Text("Tiles")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text("1")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            overviewRow(isSelected: selectedIndex == 0)
                            overviewRow(isSelected: selectedIndex == 1)
                        }
                    }
                }
            }
        }

        private func overviewRow(isSelected: Bool) -> some View {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.22 : 0.12))
                    .frame(width: 32, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(isSelected ? 0.32 : 0.2))
                        .frame(width: 80, height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 54, height: 5)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(isSelected ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private struct LineShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }

    private func arrowLine(from: CGPoint, to: CGPoint) -> some View {
        let angle = atan2(to.y - from.y, to.x - from.x)
        return ZStack {
            ArrowLine(from: from, to: to)
                .stroke(Color.white.opacity(0.85), lineWidth: 1.5)

            ArrowLine(from: from, to: to)
                .stroke(Color.black.opacity(0.6), lineWidth: 3)
                .blendMode(.destinationOver)

            ArrowHead(tip: to, angle: angle)
                .fill(Color.white.opacity(0.85))
            ArrowHead(tip: to, angle: angle)
                .stroke(Color.black.opacity(0.6), lineWidth: 1)
        }
        .compositingGroup()
    }

    private func tutorialControls(in size: CGSize) -> some View {
        let panelWidth: CGFloat = min(340, size.width - 40)
        let isLastStep = controller.stepIndex == controller.steps.count - 1
        let controls = HStack(spacing: 10) {
            Button {
                controller.stop()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("Skip")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.caption.weight(.semibold))
                .padding(.vertical, 2)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(TutorialPillButtonStyle())

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(0..<controller.steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == controller.stepIndex ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                        )
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            Button {
                controller.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(TutorialIconButtonStyle())
                .disabled(controller.stepIndex == 0)
            Button {
                controller.next()
            } label: {
                Image(systemName: isLastStep ? "checkmark" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(TutorialIconButtonStyle(isPrimary: true, isAccent: isLastStep))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: panelWidth)

        let fallback = controls
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )

#if os(macOS)
        if #available(macOS 26.0, *) {
            return controls
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .position(x: size.width / 2, y: size.height - 56)
        } else {
            return fallback
                .position(x: size.width / 2, y: size.height - 56)
        }
#else
        return fallback
            .position(x: size.width / 2, y: size.height - 56)
#endif
    }

    private struct TutorialIconButtonStyle: ButtonStyle {
        var isPrimary: Bool = false
        var isAccent: Bool = false

        func makeBody(configuration: Configuration) -> some View {
            let accent = Color.accentColor
            configuration.label
                .foregroundStyle(isPrimary ? (isAccent ? Color.white : Color.black) : Color.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(
                            isPrimary
                            ? (isAccent ? accent.opacity(0.95) : Color.white.opacity(0.90))
                            : Color.white.opacity(0.14)
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isPrimary ? 0.50 : 0.28), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
    }

    private struct TutorialPillButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.7 : 1.0)
        }
    }

    private func intersectionPoint(from start: CGPoint, to end: CGPoint, with rect: CGRect) -> CGPoint? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else { return nil }

        let candidates: [CGFloat] = [
            (rect.minX - start.x) / (dx == 0 ? 0.0001 : dx),
            (rect.maxX - start.x) / (dx == 0 ? 0.0001 : dx),
            (rect.minY - start.y) / (dy == 0 ? 0.0001 : dy),
            (rect.maxY - start.y) / (dy == 0 ? 0.0001 : dy)
        ]

        let valid = candidates
            .filter { $0.isFinite && $0 > 0 && $0 < 1 }
            .sorted()

        guard let t = valid.first else { return nil }
        let x = start.x + dx * t
        let y = start.y + dy * t
        return CGPoint(x: x, y: y)
    }

    private func nudgedPointOutsideBubble(from point: CGPoint, toward target: CGPoint) -> CGPoint {
        let dx = point.x - target.x
        let dy = point.y - target.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        let offset: CGFloat = 6
        return CGPoint(x: point.x + dx / len * offset, y: point.y + dy / len * offset)
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }

    private func extraVerticalOffset(for rect: CGRect, placement: CalloutPlacement) -> CGFloat {
        guard placement == .below else { return 0 }
        // If the target sits in the top toolbar band, push the callout slightly down.
        return rect.minY < 120 ? 12 : 0
    }

    @ViewBuilder
    private func debugAnchorOverlay() -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(anchors.keys.sorted(), id: \.self) { key in
        if let rect = anchors[key] {
            Rectangle()
                .stroke(Color.green.opacity(0.9), lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .position(x: rect.midX, y: rect.midY)

                    Text(key)
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(Color.white)
                        .position(x: rect.minX + min(100, rect.width / 2), y: rect.minY - 10)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func shouldSkipOutline(for step: DashboardTutorialStep) -> Bool {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return step.anchorId == "root.addMenu"
        }
#endif
        return false
    }

    private func shouldSkipHighlight(for step: DashboardTutorialStep) -> Bool {
        if step.anchorId == "root.canvas" || step.anchorId == "root.addMenu" {
            return true
        }
        return shouldSkipOutline(for: step)
    }
}
