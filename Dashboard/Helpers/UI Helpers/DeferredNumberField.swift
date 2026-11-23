import SwiftUI

/// A numeric text field that buffers keystrokes in local state and only commits to
/// `value` when editing ends (blur, Return, or the view disappearing).
///
/// `TextField(_:value:formatter:)` re-parses and re-formats its text on every keystroke,
/// committing straight to `value` as you type. When `value` is also read by a live-rendered
/// view (e.g. a dashboard tile canvas), that live view visibly races the digits being typed
/// (typing "20" flashes 2, then 20). This view stages edits locally so the bound value only
/// changes once, with the final parsed number.
///
/// Input the formatter rejects reverts to the last value, with a brief hint below the
/// field (also announced to VoiceOver) so the revert isn't silent.
struct DeferredNumberField<Value: Numeric>: View {
    @Binding private var value: Value
    private let formatter: Formatter
    private let title: String
    private let valueFromNumber: (NSNumber) -> Value
    private let numberFromValue: (Value) -> NSNumber

    @State private var text: String = ""
    @State private var invalidInputHint: String?
    @State private var hintDismissTask: Task<Void, Never>?
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
            .onDisappear {
                hintDismissTask?.cancel()
                commit(showsHintOnRevert: false)
            }
            .overlay(alignment: .bottomLeading) {
                if let invalidInputHint {
                    Label(invalidInputHint, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .fixedSize()
                        .alignmentGuide(.bottom) { $0[.top] - 2 }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.15), value: invalidInputHint)
    }

    /// "Enter a number", or the allowed range when the formatter has one.
    private var invalidInputMessage: String {
        guard let numberFormatter = formatter as? NumberFormatter else { return "Enter a number" }
        switch (numberFormatter.minimum, numberFormatter.maximum) {
        case let (min?, max?):
            return "Enter a number from \(numberFormatter.string(from: min) ?? min.stringValue) to \(numberFormatter.string(from: max) ?? max.stringValue)"
        case let (min?, nil):
            return "Enter a number of at least \(numberFormatter.string(from: min) ?? min.stringValue)"
        case let (nil, max?):
            return "Enter a number up to \(numberFormatter.string(from: max) ?? max.stringValue)"
        case (nil, nil):
            return "Enter a number"
        }
    }

    private func showInvalidInputHint() {
        let message = invalidInputMessage
        invalidInputHint = message
        AccessibilityNotification.Announcement(message).post()
        hintDismissTask?.cancel()
        hintDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            invalidInputHint = nil
        }
    }

    private func formattedText(for value: Value) -> String {
        formatter.string(for: numberFromValue(value)) ?? ""
    }

    private func commit(showsHintOnRevert: Bool = true) {
        var obj: AnyObject?
        guard formatter.getObjectValue(&obj, for: text, errorDescription: nil),
              let number = obj as? NSNumber
        else {
            let reverted = formattedText(for: value)
            if showsHintOnRevert, text != reverted {
                showInvalidInputHint()
            }
            text = reverted
            return
        }
        invalidInputHint = nil
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
