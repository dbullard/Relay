import SwiftUI

/// A numeric text field that buffers keystrokes in local state and only commits to
/// `value` when editing ends (blur, Return, or the view disappearing).
///
/// `TextField(_:value:formatter:)` re-parses and re-formats its text on every keystroke,
/// committing straight to `value` as you type. When `value` is also read by a live-rendered
/// view (e.g. a dashboard tile canvas), that live view visibly races the digits being typed
/// (typing "20" flashes 2, then 20). This view stages edits locally so the bound value only
/// changes once, with the final parsed number.
struct DeferredNumberField<Value: Numeric>: View {
    @Binding private var value: Value
    private let formatter: Formatter
    private let title: String
    private let valueFromNumber: (NSNumber) -> Value
    private let numberFromValue: (Value) -> NSNumber

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    fileprivate init(
        title: String,
        value: Binding<Value>,
        formatter: Formatter,
        valueFromNumber: @escaping (NSNumber) -> Value,
        numberFromValue: @escaping (Value) -> NSNumber
    ) {
        self.title = title
        self._value = value
        self.formatter = formatter
        self.valueFromNumber = valueFromNumber
        self.numberFromValue = numberFromValue
    }

    var body: some View {
        TextField(title, text: $text)
            .focused($isFocused)
            .onAppear { text = formattedText(for: value) }
            .onChange(of: value) { _, newValue in
                guard !isFocused else { return }
                text = formattedText(for: newValue)
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit { commit() }
            .onDisappear { commit() }
    }

    private func formattedText(for value: Value) -> String {
        formatter.string(for: numberFromValue(value)) ?? ""
    }

    private func commit() {
        var obj: AnyObject?
        guard formatter.getObjectValue(&obj, for: text, errorDescription: nil),
              let number = obj as? NSNumber
        else {
            text = formattedText(for: value)
            return
        }
        value = valueFromNumber(number)
        text = formattedText(for: value)
    }
}

extension DeferredNumberField where Value == Double {
    init(_ title: String = "", value: Binding<Double>, formatter: Formatter) {
        self.init(
            title: title,
            value: value,
            formatter: formatter,
            valueFromNumber: { $0.doubleValue },
            numberFromValue: { NSNumber(value: $0) }
        )
    }
}

extension DeferredNumberField where Value == Int {
    init(_ title: String = "", value: Binding<Int>, formatter: Formatter) {
        self.init(
            title: title,
            value: value,
            formatter: formatter,
            valueFromNumber: { $0.intValue },
            numberFromValue: { NSNumber(value: $0) }
        )
    }
}
