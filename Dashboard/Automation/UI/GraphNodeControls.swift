import SwiftUI

// MARK: - SwiftUI-drawn controls for graph nodes
//
// SwiftUI applies the Automation canvas zoom (`scaleEffect`) to every AppKit-backed
// control (TextField, Picker, Stepper, Toggle, bordered Button) with `setFrameTransform`.
// AppKit treats each scale change as a backing-property change, so the controls
// re-measure and the node layout caches are thrown away: every zoom or pan frame
// re-measured every node form (100–160 ms per frame on a 15-node dashboard).
//
// The controls here draw with SwiftUI only. Their initializers mirror the native ones so
// call sites only change the type name. `GraphTextField` shows its value as text and swaps
// in a real `TextField` while it is being edited, so at most one native field exists.

enum GraphControlMetrics {
    static let cornerRadius: CGFloat = 5

    static func height(for size: ControlSize) -> CGFloat {
        switch size {
        case .mini: return 16
        case .small: return 19
        default: return 22
        }
    }

    static func font(for size: ControlSize) -> Font {
        switch size {
        case .mini: return .system(size: 9)
        case .small: return .system(size: 11)
        default: return .system(size: 13)
        }
    }

    // Dark canvas: raised surfaces are lighter, borders are translucent (ui-rules S2, S3).
    static let fieldFill = Color.white.opacity(0.06)
    static let controlFill = Color.white.opacity(0.11)
    static let controlPressedFill = Color.white.opacity(0.18)
    static let selectedSegmentFill = Color.white.opacity(0.22)
    static let border = Color.white.opacity(0.10)
}

// MARK: - Text field

/// Records that a click just started editing a graph text field. Node and background taps
/// move keyboard focus to the graph surface (`focusGraphSurface`), and they fire for the same
/// click; without this they took focus back from the field the click had just created.
@MainActor
enum GraphTextEditingClaim {
    private static var lastClaim = Date.distantPast

    static func claim() { lastClaim = Date() }

    /// True for a short while after a field claimed a click.
    static var isRecent: Bool { Date().timeIntervalSince(lastClaim) < 0.5 }
}

/// A text field that shows its value as text until clicked, then edits with a real
/// `TextField`. Modifiers applied to it (`.textFieldStyle`, `.font`, `.onSubmit`,
/// `.multilineTextAlignment`, `.lineLimit`, `.disabled`) reach the real field too.
struct GraphTextField<Field: View>: View {
    private let placeholder: Text
    private let isMultiline: Bool
    private let currentText: () -> String
    private let makeField: () -> Field

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.font) private var font
    @Environment(\.multilineTextAlignment) private var textAlignment
    @State private var isEditing = false
    @State private var editingStartedAt = Date.distantPast
    @FocusState private var isFocused: Bool

    fileprivate init(
        placeholder: Text,
        isMultiline: Bool,
        currentText: @escaping () -> String,
        makeField: @escaping () -> Field
    ) {
        self.placeholder = placeholder
        self.isMultiline = isMultiline
        self.currentText = currentText
        self.makeField = makeField
    }

    var body: some View {
        if isEditing {
            makeField()
                .focused($isFocused)
                .onAppear {
                    editingStartedAt = Date()
                    // Focus once the field is in the window.
                    DispatchQueue.main.async { isFocused = true }
                }
                .onChange(of: isFocused) { _, focused in
                    guard !focused else { return }
                    // Something else grabbed focus during the click that started editing
                    // (e.g. a gesture on the node): take it back instead of closing.
                    if Date().timeIntervalSince(editingStartedAt) < 0.4 {
                        DispatchQueue.main.async { isFocused = true }
                    } else {
                        isEditing = false
                    }
                }
        } else {
            display
        }
    }

    private var display: some View {
        let value = currentText()
        return Group {
            if value.isEmpty {
                placeholder.foregroundStyle(.tertiary)
            } else {
                Text(verbatim: value).foregroundStyle(isEnabled ? .primary : .secondary)
            }
        }
        .font(font ?? GraphControlMetrics.font(for: controlSize))
        .lineLimit(isMultiline ? nil : 1)
        .truncationMode(.tail)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(
            maxWidth: .infinity,
            minHeight: GraphControlMetrics.height(for: controlSize),
            alignment: frameAlignment
        )
        .background(
            RoundedRectangle(cornerRadius: GraphControlMetrics.cornerRadius)
                .fill(GraphControlMetrics.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GraphControlMetrics.cornerRadius)
                .strokeBorder(GraphControlMetrics.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            GraphTextEditingClaim.claim()
            isEditing = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(placeholder)
        .accessibilityValue(Text(verbatim: value))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled else { return }
            GraphTextEditingClaim.claim()
            isEditing = true
        }
    }

    private var frameAlignment: Alignment {
        switch textAlignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }
}

extension GraphTextField where Field == TextField<Text> {
    init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(placeholder: Text(titleKey), isMultiline: false, currentText: { text.wrappedValue }) {
            TextField(titleKey, text: text)
        }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, text: Binding<String>) {
        self.init(placeholder: Text(title), isMultiline: false, currentText: { text.wrappedValue }) {
            TextField(title, text: text)
        }
    }

    init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) {
        self.init(placeholder: Text(titleKey), isMultiline: axis == .vertical, currentText: { text.wrappedValue }) {
            TextField(titleKey, text: text, axis: axis)
        }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis) {
        self.init(placeholder: Text(title), isMultiline: axis == .vertical, currentText: { text.wrappedValue }) {
            TextField(title, text: text, axis: axis)
        }
    }

    init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) {
        self.init(placeholder: Text(titleKey), isMultiline: false, currentText: { text.wrappedValue }) {
            TextField(titleKey, text: text, onEditingChanged: onEditingChanged)
        }
    }

    init<F: ParseableFormatStyle>(
        _ titleKey: LocalizedStringKey,
        value: Binding<F.FormatInput>,
        format: F
    ) where F.FormatOutput == String {
        self.init(placeholder: Text(titleKey), isMultiline: false, currentText: { format.format(value.wrappedValue) }) {
            TextField(titleKey, value: value, format: format)
        }
    }

    @_disfavoredOverload
    init<S: StringProtocol, F: ParseableFormatStyle>(
        _ title: S,
        value: Binding<F.FormatInput>,
        format: F
    ) where F.FormatOutput == String {
        self.init(placeholder: Text(title), isMultiline: false, currentText: { format.format(value.wrappedValue) }) {
            TextField(title, value: value, format: format)
        }
    }

    init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter) {
        self.init(
            placeholder: Text(titleKey),
            isMultiline: false,
            currentText: { formatter.string(for: value.wrappedValue) ?? "" }
        ) {
            TextField(titleKey, value: value, formatter: formatter)
        }
    }

    @_disfavoredOverload
    init<S: StringProtocol, V>(_ title: S, value: Binding<V>, formatter: Formatter) {
        self.init(
            placeholder: Text(title),
            isMultiline: false,
            currentText: { formatter.string(for: value.wrappedValue) ?? "" }
        ) {
            TextField(title, value: value, formatter: formatter)
        }
    }
}

// MARK: - Picker

enum GraphPickerDisplayStyle {
    case menu
    case segmented
}

private struct GraphPickerDisplayStyleKey: EnvironmentKey {
    static let defaultValue: GraphPickerDisplayStyle = .menu
}

extension EnvironmentValues {
    var graphPickerDisplayStyle: GraphPickerDisplayStyle {
        get { self[GraphPickerDisplayStyleKey.self] }
        set { self[GraphPickerDisplayStyleKey.self] = newValue }
    }
}

extension View {
    /// Style for `GraphPicker`s inside this view (the native `.pickerStyle` doesn't apply).
    func graphPickerStyle(_ style: GraphPickerDisplayStyle) -> some View {
        environment(\.graphPickerDisplayStyle, style)
    }
}

/// A picker drawn with SwiftUI. Content is the same as a native `Picker`: views tagged with
/// `.tag(value)`. Menu style opens a popover list; segmented style shows inline segments.
struct GraphPicker<SelectionValue: Hashable, Content: View, Label: View>: View {
    @Binding private var selection: SelectionValue
    private let content: Content
    private let label: Label

    @Environment(\.graphPickerDisplayStyle) private var style
    @Environment(\.labelsVisibility) private var labelsVisibility
    @Environment(\.controlSize) private var controlSize
    @Environment(\.font) private var font
    @Environment(\.isEnabled) private var isEnabled
    @State private var isMenuPresented = false

    init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self._selection = selection
        self.content = content()
        self.label = label()
    }

    var body: some View {
        HStack(spacing: 6) {
            if labelsVisibility != .hidden {
                label
            }
            switch style {
            case .segmented: segmented
            case .menu: menuButton
            }
        }
    }

    private var controlFont: Font { font ?? GraphControlMetrics.font(for: controlSize) }
    private var height: CGFloat { GraphControlMetrics.height(for: controlSize) }

    private func isSelected(_ subview: Subview) -> Bool {
        subview.containerValues.tag(for: SelectionValue.self) == selection
    }

    // MARK: Segmented

    private var segmented: some View {
        let outerRadius: CGFloat = 6
        let inset: CGFloat = 2
        return HStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    let selected = isSelected(subview)
                    let tag = subview.containerValues.tag(for: SelectionValue.self)
                    // A Button (not a tap gesture) so Tab and Space can operate it.
                    Button {
                        guard isEnabled, let tag else { return }
                        selection = tag
                    } label: {
                        subview
                            .font(controlFont)
                            .lineLimit(1)
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 28, maxHeight: .infinity)
                            .background(
                                // Concentric with the track (ui-rules S1).
                                RoundedRectangle(cornerRadius: outerRadius - inset)
                                    .fill(selected ? GraphControlMetrics.selectedSegmentFill : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(inset)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: outerRadius).fill(GraphControlMetrics.controlFill)
        )
        .opacity(isEnabled ? 1 : 0.5)
    }

    // MARK: Menu

    private var menuButton: some View {
        Button {
            isMenuPresented = true
        } label: {
            HStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    // Reserve the widest item's width, like a native pop-up button, so the
                    // control doesn't resize when the selection changes.
                    Group(subviews: content) { subviews in
                        if subviews.count <= 40 {
                            ForEach(subviews) { $0 }
                        }
                    }
                    .hidden()
                    Group(subviews: content) { subviews in
                        if let selected = subviews.first(where: isSelected) {
                            selected
                        }
                    }
                }
                .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(controlFont)
            .padding(.horizontal, 7)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: GraphControlMetrics.cornerRadius)
                    .fill(GraphControlMetrics.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GraphControlMetrics.cornerRadius)
                    .strokeBorder(GraphControlMetrics.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
            GraphPickerMenuList(content: content, selection: $selection, isPresented: $isMenuPresented)
        }
    }
}

extension GraphPicker where Label == Text {
    init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(titleKey) }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(title) }
    }
}

private struct GraphPickerMenuList<SelectionValue: Hashable, Content: View>: View {
    let content: Content
    @Binding var selection: SelectionValue
    @Binding var isPresented: Bool

    var body: some View {
        Group(subviews: content) { subviews in
            if subviews.count > 14 {
                ScrollView { rows(subviews) }
                    .frame(height: 360)
            } else {
                rows(subviews)
            }
        }
        .frame(minWidth: 140)
        .padding(.vertical, 4)
        #if os(iOS)
        .presentationCompactAdaptation(.popover)
        #endif
    }

    private func rows(_ subviews: SubviewsCollection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subviews) { subview in
                if let tag = subview.containerValues.tag(for: SelectionValue.self) {
                    GraphPickerMenuRow(subview: subview, isSelected: tag == selection) {
                        selection = tag
                        isPresented = false
                    }
                } else {
                    // Dividers and other untagged content.
                    subview.padding(.horizontal, 8)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct GraphPickerMenuRow: View {
    let subview: Subview
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
                subview
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 6)
            .frame(minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Menu

/// A menu drawn with SwiftUI: the label opens a popover with the content. Tapping any
/// row closes it.
struct GraphMenu<Content: View, Label: View>: View {
    private let content: Content
    private let label: Label
    @State private var isPresented = false

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                label
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                content
                    .buttonStyle(GraphMenuRowButtonStyle())
            }
            .padding(4)
            .frame(minWidth: 120)
            .simultaneousGesture(TapGesture().onEnded { isPresented = false })
            #if os(iOS)
            .presentationCompactAdaptation(.popover)
            #endif
        }
    }
}

private struct GraphMenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GraphMenuRowButton(configuration: configuration)
    }

    private struct GraphMenuRowButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovered ? Color.white : Color.primary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Stepper

/// Up/down arrows drawn with SwiftUI, with the native `Stepper` initializers.
struct GraphStepper<Label: View>: View {
    private let label: Label
    private let canIncrement: Bool
    private let canDecrement: Bool
    private let increment: () -> Void
    private let decrement: () -> Void

    @Environment(\.labelsVisibility) private var labelsVisibility
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    init<V: Strideable>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        let current = value.wrappedValue
        self.canIncrement = current < bounds.upperBound
        self.canDecrement = current > bounds.lowerBound
        self.increment = {
            value.wrappedValue = min(value.wrappedValue.advanced(by: step), bounds.upperBound)
        }
        self.decrement = {
            value.wrappedValue = max(value.wrappedValue.advanced(by: -step), bounds.lowerBound)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if labelsVisibility != .hidden {
                label
            }
            VStack(spacing: 0) {
                arrow("chevron.up", isEnabled: canIncrement, action: increment)
                Rectangle()
                    .fill(GraphControlMetrics.border)
                    .frame(height: 1)
                arrow("chevron.down", isEnabled: canDecrement, action: decrement)
            }
            .frame(width: 15, height: GraphControlMetrics.height(for: controlSize))
            .background(
                RoundedRectangle(cornerRadius: 4).fill(GraphControlMetrics.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(GraphControlMetrics.border, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.5)
        }
    }

    private func arrow(_ systemName: String, isEnabled arrowEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(arrowEnabled ? Color.primary : Color.secondary.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Hit area wider than the drawn arrow (ui-rules U2).
                .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .disabled(!arrowEnabled)
    }
}

extension GraphStepper where Label == Text {
    init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1) {
        self.init(value: value, in: bounds, step: step) { Text(titleKey) }
    }

    @_disfavoredOverload
    init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1) {
        self.init(value: value, in: bounds, step: step) { Text(title) }
    }
}

// MARK: - Toggle styles

struct GraphSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        GraphSwitch(configuration: configuration)
    }

    private struct GraphSwitch: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.labelsVisibility) private var labelsVisibility
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let size: CGSize = switch controlSize {
            case .mini: CGSize(width: 26, height: 15)
            case .small: CGSize(width: 32, height: 18)
            default: CGSize(width: 38, height: 22)
            }
            HStack(spacing: 6) {
                if labelsVisibility != .hidden {
                    configuration.label
                }
                Button {
                    guard isEnabled else { return }
                    configuration.isOn.toggle()
                } label: {
                    Capsule()
                        .fill(configuration.isOn ? Color.accentColor : GraphControlMetrics.controlPressedFill)
                        .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                            Circle()
                                .fill(Color.white)
                                .padding(2)
                                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        }
                        .frame(width: size.width, height: size.height)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
            .accessibilityAction { if isEnabled { configuration.isOn.toggle() } }
        }
    }
}

struct GraphCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        GraphCheckbox(configuration: configuration)
    }

    private struct GraphCheckbox: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.labelsVisibility) private var labelsVisibility
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button {
                guard isEnabled else { return }
                configuration.isOn.toggle()
            } label: {
                checkboxLabel
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
        }

        private var checkboxLabel: some View {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(configuration.isOn ? Color.accentColor : GraphControlMetrics.fieldFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5)
                            .strokeBorder(
                                configuration.isOn ? Color.clear : Color.white.opacity(0.28),
                                lineWidth: 1
                            )
                    )
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 14, height: 14)
                if labelsVisibility != .hidden {
                    configuration.label
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Button styles

/// Stand-in for the default / `.bordered` button look.
struct GraphPushButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        GraphPushButton(configuration: configuration, isProminent: isProminent)
    }

    private struct GraphPushButton: View {
        let configuration: ButtonStyleConfiguration
        let isProminent: Bool
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let fill: Color = if isProminent {
                Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)
            } else {
                configuration.isPressed ? GraphControlMetrics.controlPressedFill : GraphControlMetrics.controlFill
            }
            configuration.label
                .font(GraphControlMetrics.font(for: controlSize))
                .lineLimit(1)
                .foregroundStyle(isProminent ? Color.white : Color.primary)
                .padding(.horizontal, controlSize == .small || controlSize == .mini ? 7 : 10)
                .frame(minHeight: GraphControlMetrics.height(for: controlSize))
                .background(
                    RoundedRectangle(cornerRadius: GraphControlMetrics.cornerRadius + 1).fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GraphControlMetrics.cornerRadius + 1)
                        .strokeBorder(GraphControlMetrics.border, lineWidth: isProminent ? 0 : 1)
                )
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
        }
    }
}

/// Stand-in for `.borderless`: no bezel, dims while pressed.
struct GraphBorderlessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GraphBorderlessButton(configuration: configuration)
    }

    private struct GraphBorderlessButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
                .contentShape(Rectangle())
        }
    }
}

extension View {
    /// Default control styles for graph node content, so buttons and toggles without an
    /// explicit style don't fall back to AppKit-backed controls.
    func graphNodeControlStyles() -> some View {
        self
            .buttonStyle(GraphPushButtonStyle())
            #if os(macOS)
            .toggleStyle(GraphCheckboxToggleStyle())
            #endif
    }
}
