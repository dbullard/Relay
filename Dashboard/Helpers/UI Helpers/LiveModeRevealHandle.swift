//
//  LiveModeRevealHandle.swift
//  Relay
//
//  A small always-present grabber at the top of the screen in Live Mode (macOS and iPad)
//  that opens the live menu with a tap or a drag down — reliable on touch monitors and
//  iPad, where there is no hover to trigger the reveal strip and the strip itself is
//  invisible.
//

import SwiftUI
import CoreGraphics

enum LiveModeRevealHandlePolicy {
    /// Height of the macOS top-center reveal strip (was 14 pt; taller so a finger can catch it).
    static let hotZoneHeight: CGFloat = 28
    static let pillSize = CGSize(width: 44, height: 6)
    /// Minimum 44 pt touch target (UI rule U2).
    static let tapTargetSize = CGSize(width: 60, height: 44)
    static let idleDimDelay: TimeInterval = 3
    static let fullOpacity: Double = 0.9
    /// Dimmed but never invisible, so operators can always find it.
    static let dimmedOpacity: Double = 0.3

    /// Movement under this many points counts as a tap: finger taps on touch monitors
    /// usually wobble a pixel or two, which would otherwise start a (useless) drag.
    static let tapSlop: CGFloat = 6

    /// The handle stays mounted for all of Live Mode (removing it mid-gesture would cancel
    /// its drag without `onEnded`); this decides whether it is drawn and hit-testable.
    static func isShown(isChromeVisible: Bool, isHandleDragging: Bool) -> Bool {
        !isChromeVisible || isHandleDragging
    }

    static func isTap(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) < tapSlop
    }
}

struct LiveModeRevealHandle: View {
    let isChromeVisible: Bool
    let onTap: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onHoverChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false
    @State private var dimWorkItem: DispatchWorkItem?
    /// True while a touch/click on the handle is down (auto-resets if the gesture is cancelled).
    @GestureState private var isTracking = false
    /// Whether the current gesture has moved past `tapSlop` and is being forwarded as a drag.
    @State private var isForwardingDrag = false

    init(
        isChromeVisible: Bool,
        onTap: @escaping () -> Void,
        onDragChanged: @escaping (DragGesture.Value) -> Void,
        onDragEnded: @escaping (DragGesture.Value) -> Void,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        self.isChromeVisible = isChromeVisible
        self.onTap = onTap
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onHoverChanged = onHoverChanged
    }

    private static var outlineColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    private var isShown: Bool {
        LiveModeRevealHandlePolicy.isShown(isChromeVisible: isChromeVisible, isHandleDragging: isTracking)
    }

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.6))
            .overlay(Capsule().strokeBorder(Self.outlineColor.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .frame(width: LiveModeRevealHandlePolicy.pillSize.width, height: LiveModeRevealHandlePolicy.pillSize.height)
            .padding(.top, 8)
            .frame(
                width: LiveModeRevealHandlePolicy.tapTargetSize.width,
                height: LiveModeRevealHandlePolicy.tapTargetSize.height,
                alignment: .top
            )
            .contentShape(Rectangle())
            .opacity(isShown ? (isDimmed ? LiveModeRevealHandlePolicy.dimmedOpacity : LiveModeRevealHandlePolicy.fullOpacity) : 0)
            .allowsHitTesting(isShown)
            // One zero-distance drag handles both: under `tapSlop` it's a tap (tolerates
            // finger wobble), past it the movement is forwarded to the reveal drag.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($isTracking) { _, tracking, _ in tracking = true }
                    .onChanged { value in
                        wake()
                        if isForwardingDrag || !LiveModeRevealHandlePolicy.isTap(translation: value.translation) {
                            isForwardingDrag = true
                            onDragChanged(value)
                        }
                    }
                    .onEnded { value in
                        if isForwardingDrag {
                            onDragEnded(value)
                        } else {
                            onTap()
                        }
                        isForwardingDrag = false
                    }
            )
            .onHover { hovering in
                if hovering { wake() }
                // The handle sits above the reveal strip; pass hover through so pointing at
                // the top-center edge still triggers the strip's hover reveal.
                onHoverChanged(hovering)
            }
            .onAppear { wake() }
            .onChange(of: isChromeVisible, initial: false) { _, visible in
                if !visible { wake() }
            }
            .onDisappear {
                dimWorkItem?.cancel()
                dimWorkItem = nil
            }
            .accessibilityElement()
            .accessibilityLabel("Show live menu")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityHidden(!isShown)
    }

    /// Brighten now, then dim again after `idleDimDelay` of no interaction.
    private func wake() {
        setDimmed(false)
        dimWorkItem?.cancel()
        let item = DispatchWorkItem { setDimmed(true) }
        dimWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + LiveModeRevealHandlePolicy.idleDimDelay, execute: item)
    }

    private func setDimmed(_ dimmed: Bool) {
        guard isDimmed != dimmed else { return }
        if reduceMotion {
            isDimmed = dimmed
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { isDimmed = dimmed }
        }
    }
}
