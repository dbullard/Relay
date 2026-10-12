import SwiftUI

#if os(macOS)
import AppKit
#endif

private struct DashboardVariableValuesKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

extension EnvironmentValues {
    var dashboardVariableValues: [String: String] {
        get { self[DashboardVariableValuesKey.self] }
        set { self[DashboardVariableValuesKey.self] = newValue }
    }
}

#if os(macOS)
private struct PlainVariableTokenCompletionContext {
    let replacementRange: NSRange
    let query: String
    let usesBraces: Bool

    func token(for variableName: String) -> String {
        usesBraces ? "#{\(variableName)}" : "#\(variableName)"
    }
}

private func plainVariableTokenCompletionContext(in text: String, selection: NSRange) -> PlainVariableTokenCompletionContext? {
    guard selection.length == 0 else { return nil }

    let nsText = text as NSString
    let cursor = min(selection.location, nsText.length)
    let prefix = nsText.substring(to: cursor)
    guard let regex = try? NSRegularExpression(pattern: #"#(\{?)([A-Za-z0-9_]*)$"#) else {
        return nil
    }

    let range = NSRange(location: 0, length: (prefix as NSString).length)
    guard let match = regex.firstMatch(in: prefix, range: range) else { return nil }
    let queryRange = match.range(at: 2)
    guard queryRange.location != NSNotFound else { return nil }

    return PlainVariableTokenCompletionContext(
        replacementRange: match.range(at: 0),
        query: (prefix as NSString).substring(with: queryRange),
        usesBraces: match.range(at: 1).length > 0
    )
}

private final class PlainVariableSuggestingTextView: NSTextView {
    var variableValueProvider: (() -> [String: String])?
    fileprivate private(set) var currentVariableCompletionContext: PlainVariableTokenCompletionContext?
    private var activeCompletionMenuContext: PlainVariableTokenCompletionContext?

    func syncVariableCompletionContext() {
        currentVariableCompletionContext = plainVariableTokenCompletionContext(in: string, selection: selectedRange())
    }

    func refreshVariableCompletion() {
        syncVariableCompletionContext()
        guard window?.firstResponder === self else { return }
        guard let context = currentVariableCompletionContext else {
            activeCompletionMenuContext = nil
            updateCandidates()
            return
        }

        let normalizedQuery = normalizeGraphVariableName(context.query)
        let hasMatches = (variableValueProvider?() ?? [:]).keys.contains { variableName in
            normalizedQuery.isEmpty || variableName.hasPrefix(normalizedQuery)
        }

        if hasMatches {
            activeCompletionMenuContext = context
            complete(nil)
        } else {
            activeCompletionMenuContext = nil
            updateCandidates()
        }
    }

    fileprivate func completionWords() -> [String] {
        guard let context = currentVariableCompletionContext ?? activeCompletionMenuContext else { return [] }
        let normalizedQuery = normalizeGraphVariableName(context.query)
        return (variableValueProvider?() ?? [:])
            .filter { normalizedQuery.isEmpty || $0.key.hasPrefix(normalizedQuery) }
            .sorted { $0.key < $1.key }
            .map(\.key)
    }

    fileprivate var shouldPreselectCompletionCandidate: Bool {
        let query = (currentVariableCompletionContext ?? activeCompletionMenuContext)?.query ?? ""
        return !query.isEmpty
    }

    fileprivate func completionTokenIfNeeded(for replacementString: String?, affectedRange: NSRange) -> (range: NSRange, token: String)? {
        guard let replacementString else { return nil }
        guard let context = currentVariableCompletionContext ?? activeCompletionMenuContext else { return nil }

        let normalizedReplacement = normalizeGraphVariableName(
            replacementString
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
        )
        guard !normalizedReplacement.isEmpty else { return nil }

        let availableNames = Set((variableValueProvider?() ?? [:]).keys)
        guard availableNames.contains(normalizedReplacement) else { return nil }

        let contextRange = context.replacementRange
        let matchesContextRange = NSEqualRanges(affectedRange, contextRange)
            || affectedRange.location == contextRange.location + 1
            || NSLocationInRange(affectedRange.location, contextRange)
        guard matchesContextRange else { return nil }

        activeCompletionMenuContext = nil
        currentVariableCompletionContext = nil
        return (contextRange, context.token(for: normalizedReplacement))
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            SharedValuePickerCoordinator.shared.target = self
        }
        return becameFirstResponder
    }

}

extension PlainVariableSuggestingTextView: SharedValueInsertionTarget {
    func insertSharedValueToken(_ token: String) -> Bool {
        guard isEditable else { return false }
        insertText(token, replacementRange: selectedRange())
        return true
    }
}

private struct VariableSuggestingPlainTextInput: NSViewRepresentable {
    @Binding var text: String
    let variableValues: [String: String]
    let multiline: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, multiline: multiline)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlainVariableSuggestingTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: multiline ? 6 : 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = multiline
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: multiline ? 72 : 22)
        textView.textContainer?.widthTracksTextView = true
        if !multiline {
            textView.textContainer?.heightTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.variableValueProvider = { variableValues }
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = multiline
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PlainVariableSuggestingTextView else { return }
        textView.variableValueProvider = { variableValues }
        if textView.string != text, !context.coordinator.isSynchronizingFromSwiftUI {
            context.coordinator.isSynchronizingFromSwiftUI = true
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, textView.string.utf16.count), length: 0))
            context.coordinator.isSynchronizingFromSwiftUI = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let multiline: Bool
        weak var textView: PlainVariableSuggestingTextView?
        var isSynchronizingFromSwiftUI = false
        var shouldTriggerVariableCompletionAfterChange = false
        var shouldSuppressNextVariableCompletionRefresh = false

        init(text: Binding<String>, multiline: Bool) {
            self._text = text
            self.multiline = multiline
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PlainVariableSuggestingTextView else { return }
            guard !isSynchronizingFromSwiftUI else { return }
            text = textView.string
            textView.syncVariableCompletionContext()
            if shouldSuppressNextVariableCompletionRefresh {
                shouldSuppressNextVariableCompletionRefresh = false
            } else if shouldTriggerVariableCompletionAfterChange {
                DispatchQueue.main.async { [weak textView] in
                    textView?.refreshVariableCompletion()
                }
            }
            shouldTriggerVariableCompletionAfterChange = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? PlainVariableSuggestingTextView else { return }
            guard !isSynchronizingFromSwiftUI else { return }
            textView.syncVariableCompletionContext()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !isSynchronizingFromSwiftUI else { return true }

            if !multiline, let replacementString, replacementString.contains("\n") {
                return false
            }

            if
                let variableTextView = textView as? PlainVariableSuggestingTextView,
                let completionReplacement = variableTextView.completionTokenIfNeeded(
                    for: replacementString,
                    affectedRange: affectedCharRange
                ),
                let textStorage = textView.textStorage
            {
                shouldTriggerVariableCompletionAfterChange = false
                shouldSuppressNextVariableCompletionRefresh = true
                textView.shouldChangeText(in: completionReplacement.range, replacementString: completionReplacement.token)
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: completionReplacement.range, with: completionReplacement.token)
                textStorage.endEditing()
                textView.didChangeText()
                let caretLocation = completionReplacement.range.location + (completionReplacement.token as NSString).length
                textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
                return false
            }

            guard let replacementString, !replacementString.isEmpty else {
                shouldTriggerVariableCompletionAfterChange = false
                return true
            }

            let existing = textView.string as NSString
            let prospective = existing.replacingCharacters(in: affectedCharRange, with: replacementString)
            let newCursorLocation = affectedCharRange.location + (replacementString as NSString).length
            let prospectiveSelection = NSRange(location: newCursorLocation, length: 0)
            shouldTriggerVariableCompletionAfterChange =
                plainVariableTokenCompletionContext(in: prospective, selection: prospectiveSelection) != nil
            return true
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard let variableTextView = textView as? PlainVariableSuggestingTextView else {
                return words
            }

            let matches = variableTextView.completionWords()
            if !matches.isEmpty {
                index?.pointee = variableTextView.shouldPreselectCompletionCandidate ? 0 : -1
            }
            return matches.isEmpty ? words : matches
        }
    }
}
#endif

struct VariableSuggestingTextField: View {
    private let title: String
    @Binding private var text: String
    @Environment(\.dashboardVariableValues) private var variableValues

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        #if os(macOS)
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(title)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .allowsHitTesting(false)
            }

            VariableSuggestingPlainTextInput(text: $text, variableValues: variableValues, multiline: false)
        }
        .frame(minHeight: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.12))
        )
        #else
        TextField(title, text: $text)
        #endif
    }
}

/// A graph text input whose Variables button inserts into this specific field.
struct AutomationVariableTokenField: View {
    let title: String
    @Binding var text: String
    let variableValues: [String: String]
    var multiline = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Group {
                if multiline {
                    VariableSuggestingTextEditor(text: $text)
                        .frame(minHeight: 64)
                } else {
                    VariableSuggestingTextField(title, text: $text)
                }
            }
            .environment(\.dashboardVariableValues, variableValues.filter { !$0.key.contains(":") })

            AutomationVariableInsertButton(title: title, text: $text)
        }
    }
}

struct AutomationVariableInsertButton: View {
    let title: String
    @Binding var text: String
    @State private var insertionTarget = SharedValueBindingInsertionTarget()

    var body: some View {
        #if os(macOS)
        Button {
            insertionTarget.onInsert = { token in
                text += token
                return true
            }
            SharedValuePickerCoordinator.shared.target = insertionTarget
            NotificationCenter.default.post(name: .relayShowSharedValues, object: nil)
        } label: {
            Image(systemName: "number.square")
        }
        .buttonStyle(.borderless)
        .help("Insert a variable")
        .accessibilityLabel("Insert variable into \(title)")
        #else
        EmptyView()
        #endif
    }
}

struct VariableSuggestingTextEditor: View {
    @Binding private var text: String
    @Environment(\.dashboardVariableValues) private var variableValues

    init(text: Binding<String>) {
        self._text = text
    }

    var body: some View {
        #if os(macOS)
        VariableSuggestingPlainTextInput(text: $text, variableValues: variableValues, multiline: true)
            .frame(minHeight: 96)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
        #else
        TextEditor(text: $text)
        #endif
    }
}
