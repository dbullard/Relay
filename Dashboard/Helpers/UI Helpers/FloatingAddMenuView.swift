//
//  FloatingAddMenuView.swift
//  Relay
//
//  Extracted from DashboardRootView.swift
//

import SwiftUI

/// A floating “+” add menu that expands into quick actions.
/// Designed to look at home with Liquid Glass on iOS 26+/macOS 26+
/// while keeping a solid, tasteful fallback on older OSes.
struct FloatingAddMenuView: View {
    let isLiveMode: Bool
    let layoutMode: LayoutMode

    @Binding var isAddMenuOpen: Bool

    @State private var isPlusPressed: Bool = false

    let selectedTileCount: Int
    let selectedGraphNodeCount: Int
    let deleteSelectedTiles: () -> Void
    let deleteSelectedGraphNodes: () -> Void
    let addTile: () -> Void
    let addVerticalGuide: () -> Void
    let addHorizontalGuide: () -> Void
    let addNode: () -> Void
    let hiddenNodesCount: Int
    let showHiddenNodes: () -> Void
    let hiddenTilesCount: Int
    let showHiddenTiles: () -> Void

    /// Mirror of DashboardRootView.DashboardLayoutMode without importing DashboardRootView.
    enum LayoutMode: Equatable {
        case canvas
        case graph
    }

    private struct PlusButtonAnchorKey: PreferenceKey {
        static var defaultValue: Anchor<CGRect>? = nil
        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

    var body: some View {
        if !isLiveMode {
            ZStack(alignment: .bottomTrailing) {
                // Dismiss scrim
                if isAddMenuOpen {
                    Button {
                        close()
                    } label: {
                        Color.clear
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.001).ignoresSafeArea())
                    .contentShape(Rectangle())
                    .accessibilityLabel("Close add menu")
                        .zIndex(1)
                }

                // Layout constants (match button frame)
                let buttonSize: CGFloat = 52
                let gapAboveButton: CGFloat = 26
                let edgePadding: CGFloat = 36

                // Menu panel (always positioned above the button; animate only local properties)
                menuPanel
                    .fixedSize()
                    .opacity(isAddMenuOpen ? 1.0 : 0.0)
                    .scaleEffect(isAddMenuOpen ? 1.0 : 0.98, anchor: .bottomTrailing)
                    .offset(y: isAddMenuOpen ? 0.0 : 18.0) // vertical-only
                    .allowsHitTesting(isAddMenuOpen)
                    .animation(.spring(response: 0.22, dampingFraction: 0.86), value: isAddMenuOpen)
                    .padding(.trailing, edgePadding)
                    .padding(.bottom, edgePadding + buttonSize + gapAboveButton)
                    .zIndex(3)

                // Controls row (optional pill + plus)
                controlsRow
                    .padding(.trailing, edgePadding)
                    .padding(.bottom, edgePadding)
                    .zIndex(2)


            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            // This control cluster always floats over the canvas, which is a fixed
            // Color.black in both edit and live mode (see DashboardRootView's
            // canvasBackgroundView/graphStack) -- so its glass surfaces and white
            // labels must stay dark-adapted regardless of the system appearance,
            // or Light Mode turns .regularMaterial light and the white text/icons
            // disappear into it.
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Menu Panel

    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if layoutMode == .canvas {
                Button {
                    addTile()
                    close()
                } label: {
                    menuRow(title: "Add Tile", systemImage: "square.grid.2x2", trailingSystemImage: "plus")
                }
                .buttonStyle(FloatingMenuPrimaryRowStyle())

                Divider()
                    .overlay(Color.white.opacity(0.12))
                    .padding(.vertical, 4)

                Button {
                    addVerticalGuide()
                    close()
                } label: {
                    menuRow(title: "Vertical Guide", systemImage: "lines.measurement.horizontal", trailingSystemImage: "plus")
                }
                .buttonStyle(FloatingMenuRowStyle())

                Button {
                    addHorizontalGuide()
                    close()
                } label: {
                    menuRow(title: "Horizontal Guide", systemImage: "lines.measurement.vertical", trailingSystemImage: "plus")
                }
                .buttonStyle(FloatingMenuRowStyle())
            } else {
                Button {
                    addNode()
                    close()
                } label: {
                    menuRow(title: "Add Node", systemImage: "point.3.connected.trianglepath.dotted", trailingSystemImage: "plus")
                }
                .buttonStyle(FloatingMenuPrimaryRowStyle())
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(10)
        .frame(width: 240, alignment: .leading)
        .foregroundStyle(.white)
        .floatingGlassPanel()
    }

    private func close() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isAddMenuOpen = false
        }
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack(spacing: 10) {
            if layoutMode == .graph, hiddenNodesCount > 0 {
                showHiddenNodesButton
            }
            if layoutMode == .canvas, hiddenTilesCount > 0 {
                showHiddenTilesButton
            }
            VStack(spacing: 10) {
                if layoutMode == .canvas, selectedTileCount > 0 {
                    deleteSelectionButton
                }
                if layoutMode == .graph, selectedGraphNodeCount > 0 {
                    deleteSelectionButton
                }
                plusButton
            }
        }
    }

    private var showHiddenNodesButton: some View {
        Button {
            showHiddenNodes()
        } label: {
            let labelText = "\(hiddenNodesCount) \(hiddenNodesCount == 1 ? "Node" : "Nodes") Hidden"
            pillLabel(icon: "eye.slash", text: labelText)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var showHiddenTilesButton: some View {
        Button {
            showHiddenTiles()
        } label: {
            let labelText = "\(hiddenTilesCount) \(hiddenTilesCount == 1 ? "Tile" : "Tiles") Hidden"
            pillLabel(icon: "eye.slash", text: labelText)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var deleteSelectionButton: some View {
        Button {
            if layoutMode == .graph {
                deleteSelectedGraphNodes()
            } else {
                deleteSelectedTiles()
            }
        } label: {
            ZStack {
                if #available(iOS 26.0, macOS 26.0, *) {
                    Circle()
                        .fill(.regularMaterial)
                        .glassEffect(.regular.tint(.red).interactive(), in: Circle())
                        .backgroundExtensionEffect()
                } else {
                    Circle()
                        .fill(Color(.sRGB, red: 0.78, green: 0.16, blue: 0.16, opacity: 0.98))
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
                }

                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.98))
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layoutMode == .graph ? "Delete selected nodes" : "Delete selected tiles")
    }

    private func pillLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            DashboardSymbolImage(icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .floatingGlassPanel()
    }

    // MARK: - Plus Button

    private var plusButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                isAddMenuOpen.toggle()
            }
        } label: {
            ZStack {
                // Background surface
                if #available(iOS 26.0, macOS 26.0, *) {
                    Circle()
                        // Brighter glass lens so it pops on dark canvases
                        .fill(.regularMaterial)
                        // Global brightening wash
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.16))
                                .allowsHitTesting(false)
                        )
                        // Very subtle bottom shading (keep depth, but don’t darken)
                        .overlay(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.00),
                                            Color.black.opacity(0.04)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .allowsHitTesting(false)
                        )
                        .glassEffect(in: Circle())
                        .backgroundExtensionEffect()
                        // Rim highlight (brighter + slightly thicker)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.75),
                                            Color.white.opacity(0.28),
                                            Color.white.opacity(0.12)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.25
                                )
                                .allowsHitTesting(false)
                        )
                        // Outer edge definition
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                                .allowsHitTesting(false)
                        )
                        // Open state: slightly brighter (no color fill)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(isAddMenuOpen ? 0.10 : 0.0))
                                .allowsHitTesting(false)
                        )
                } else {
                    Circle()
                        .fill(
                            isAddMenuOpen
                            ? Color(.sRGB, red: 0.55, green: 0.18, blue: 0.18, opacity: 0.95)
                            : Color(.sRGB, white: 0.18, opacity: 1.0)
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
                }

                // Icon
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .rotationEffect(.degrees(isAddMenuOpen ? 45 : 0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isAddMenuOpen)
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
            .scaleEffect(isPlusPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isPlusPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAddMenuOpen ? "Close add menu" : "Open add menu")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPlusPressed { isPlusPressed = true }
                }
                .onEnded { _ in
                    isPlusPressed = false
                }
        )
    }

    // MARK: - Row Builder

    private func menuRow(title: String, systemImage: String, trailingSystemImage: String? = nil) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                DashboardSymbolImage(systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .frame(width: 26, height: 22)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))

            Spacer(minLength: 0)

            if let trailingSystemImage {
                DashboardSymbolImage(trailingSystemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }
}

// MARK: - Styles

private struct FloatingMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FloatingMenuPrimaryRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        configuration.isPressed
                        ? Color.accentColor.opacity(0.85)
                        : Color.accentColor.opacity(0.75)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Liquid Glass panel surface

private extension View {
    @ViewBuilder
    func floatingGlassPanel() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
                .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .backgroundExtensionEffect()
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.26),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.sRGB, white: 0.12, opacity: 0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
    }
}
