//
//  SeparatorModuleModel.swift
//  Relay
//
//  Created by David Bullard on 12/1/25.
//


import Foundation
import SwiftUI

// MARK: - CodableColor convenience
// Some modules expect `CodableColor.color` to exist. If your project’s CodableColor uses
// different internal channel names, we derive a SwiftUI Color via reflection.
extension CodableColor {
    var color: Color {
        // Try common channel names
        let mirror = Mirror(reflecting: self)
        func doubleValue(_ key: String) -> Double? {
            for child in mirror.children {
                guard let label = child.label else { continue }
                if label == key {
                    if let d = child.value as? Double { return d }
                    if let f = child.value as? Float { return Double(f) }
                    if let cg = child.value as? CGFloat { return Double(cg) }
                    if let i = child.value as? Int { return Double(i) }
                }
            }
            return nil
        }

        let r = doubleValue("red") ?? doubleValue("r")
        let g = doubleValue("green") ?? doubleValue("g")
        let b = doubleValue("blue") ?? doubleValue("b")
        let a = doubleValue("alpha") ?? doubleValue("opacity") ?? doubleValue("a")

        if let r, let g, let b {
            return Color(
                red: max(0, min(1, r)),
                green: max(0, min(1, g)),
                blue: max(0, min(1, b)),
                opacity: max(0, min(1, a ?? 1.0))
            )
        }

        // Fallback: if we can’t introspect channels, use white.
        return .white
    }
}

struct SeparatorModuleModel: Identifiable, Equatable, Codable {
    enum LineStyle: String, CaseIterable, Codable {
        case solid
        case dashed
        case dotted
        
        var displayName: String {
            switch self {
            case .solid: return "Solid"
            case .dashed: return "Dashed"
            case .dotted: return "Dotted"
            }
        }
    }
    
    var id: UUID
    var thickness: Double      // points
    var style: LineStyle
    var color: CodableColor?
    
    init(
        id: UUID = UUID(),
        thickness: Double = 2,
        style: LineStyle = .solid,
        color: CodableColor? = nil
    ) {
        self.id = id
        self.thickness = thickness
        self.style = style
        self.color = color
    }
}

// MARK: - Tile Rendering

struct SeparatorModuleView: View {
    let model: SeparatorModuleModel
    let moduleLayout: TileModuleLayout

    var body: some View {
        let styleBump: CGFloat = {
            switch model.style {
            case .solid: return 0
            case .dashed: return 0.001
            case .dotted: return 0.002
            }
        }()

        let direction: SeparatorLine.Direction = (moduleLayout == .horizontal) ? .vertical : .horizontal

        SeparatorLine(
            style: model.style,
            thickness: model.thickness,
            color: (model.color?.color ?? .white).opacity(model.color == nil ? 0.85 : 1.0),
            direction: direction
        )
        .id("sep_\(direction == .horizontal ? "h" : "v")_\(model.style.rawValue)_\(Int(model.thickness))")
        .frame(
            maxWidth: direction == .horizontal ? .infinity : max(1, model.thickness) + styleBump,
            maxHeight: direction == .vertical ? .infinity : nil
        )
        .frame(
            width: direction == .vertical ? max(1, model.thickness) + styleBump : nil,
            height: direction == .horizontal ? max(1, model.thickness) + styleBump : nil,
            alignment: .center
        )
        .contentShape(Rectangle())
    }
}

private struct SeparatorLine: View {
    enum Direction {
        case horizontal
        case vertical
    }

    let style: SeparatorModuleModel.LineStyle
    let thickness: Double
    let color: Color
    let direction: Direction

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                switch direction {
                case .horizontal:
                    let midY = proxy.size.height / 2
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: midY))
                case .vertical:
                    let midX = proxy.size.width / 2
                    path.move(to: CGPoint(x: midX, y: 0))
                    path.addLine(to: CGPoint(x: midX, y: proxy.size.height))
                }
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: CGFloat(max(1, thickness)),
                    lineCap: .round,
                    dash: dashPattern
                )
            )
        }
    }

    private var dashPattern: [CGFloat] {
        switch style {
        case .solid:
            return []
        case .dashed:
            return [10, 6]
        case .dotted:
            return [2, 6]
        }
    }
}

// MARK: - Settings (Plugin-owned)

/// Host that edits the live module binding directly so style changes redraw immediately.
struct SeparatorModuleSettingsHostView: View {
    @Binding var module: DashboardModuleModel
    let onPersist: () -> Void

    private var modelBinding: Binding<SeparatorModuleModel> {
        Binding<SeparatorModuleModel>(
            get: {
                if case .separator(let m) = module.kind { return m }
                return SeparatorModuleModel()
            },
            set: { newValue in
                module.kind = .separator(newValue)
                onPersist()
            }
        )
    }

    var body: some View {
        SeparatorModuleSettingsView(model: modelBinding, onPersist: onPersist)
    }
}

struct SeparatorModuleSettingsView: View {
    @Binding private var model: SeparatorModuleModel
    let onPersist: () -> Void

    @State private var draft: SeparatorModuleModel

    init(model: Binding<SeparatorModuleModel>, onPersist: @escaping () -> Void) {
        self._model = model
        self.onPersist = onPersist
        self._draft = State(initialValue: model.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Separator")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("Thickness")
                    .frame(width: 70, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { draft.thickness },
                        set: { newValue in
                            draft.thickness = newValue
                            model = draft
                            onPersist()
                        }
                    ),
                    in: 1...12,
                    step: 1
                )

                Text("\(Int(draft.thickness))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }

            Picker("Style", selection: Binding(
                get: { draft.style },
                set: { newValue in
                    draft.style = newValue
                    model = draft
                    onPersist()
                }
            )) {
                ForEach(SeparatorModuleModel.LineStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)

            ColorPicker(
                "Color",
                selection: Binding(
                    get: { draft.color?.color ?? .white },
                    set: { newValue in
                        draft.color = CodableColor(newValue)
                        model = draft
                        onPersist()
                    }
                ),
                supportsOpacity: false
            )

            Button("Reset color") {
                draft.color = nil
                model = draft
                onPersist()
            }
#if os(macOS)
            .dashboardLinkButtonStyle()
#else
            .buttonStyle(.borderless)
#endif
        }
        .padding(.vertical, 6)
        .onChange(of: model, initial: false) { _, newValue in
            draft = newValue
        }
    }
}

// MARK: - Plugin Glue

enum SeparatorModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .separator(SeparatorModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        AnyView(
            SeparatorModuleTileHostView(module: module, moduleLayout: tile.wrappedValue.moduleLayout)
                .frame(maxWidth: .infinity, alignment: .center)
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        // Hosted by DashboardTileEditView via `SeparatorModuleSettingsView` binding.
        AnyView(EmptyView())
    }
}
/// Binding-backed host so style/thickness changes propagate reliably.
private struct SeparatorModuleTileHostView: View {
    @Binding var module: DashboardModuleModel
    let moduleLayout: TileModuleLayout

    var body: some View {
        let model: SeparatorModuleModel = {
            if case .separator(let m) = module.kind {
                return m
            } else {
                return SeparatorModuleModel()
            }
        }()

        SeparatorModuleView(model: model, moduleLayout: moduleLayout)
    }
}
