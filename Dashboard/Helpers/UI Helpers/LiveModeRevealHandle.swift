//
//  LiveModeRevealHandle.swift
//  Relay
//
//  A small always-present grabber at the top of the screen in Live Mode (macOS) that
//  opens the live menu with a tap or a drag down — reliable on touch monitors, where
//  there is no hover to trigger the reveal strip.
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

    static func isVisible(isLiveMode: Bool, isChromeVisible: Bool) -> Bool {
        isLiveMode && !isChromeVisible
    }
}

#if os(macOS)
struct LiveModeRevealHandle: View {
    let onTap: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false
    @State private var dimWorkItem: DispatchWorkItem?

    init(
        onTap: @escaping () -> Void,
        onDragChanged: @escaping (DragGesture.Value) -> Void,
        onDragEnded: @escaping (DragGesture.Value) -> Void
    ) {
        self.onTap = onTap
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.6))
            .overlay(Capsule().strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .frame(width: LiveModeRevealHandlePolicy.pillSize.width, height: LiveModeRevealHandlePolicy.pillSize.height)
            .padding(.top, 8)
            .frame(
                width: LiveModeRevealHandlePolicy.tapTargetSize.width,
                height: LiveModeRevealHandlePolicy.tapTargetSize.height,
                alignment: .top
            )
            .contentShape(Rectangle())
            .opacity(isDimmed ? LiveModeRevealHandlePolicy.dimmedOpacity : LiveModeRevealHandlePolicy.fullOpacity)
            .onTapGesture {
                wake()
                onTap()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        wake()
                        onDragChanged(value)
                    }
                    .onEnded(onDragEnded)
            )
            .onHover { hovering in
                if hovering { wake() }
            }
            .onAppear { wake() }
            .onDisappear {
                dimWorkItem?.cancel()
                dimWorkItem = nil
            }
            .accessibilityElement()
            .accessibilityLabel("Show live menu")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
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
#endif
