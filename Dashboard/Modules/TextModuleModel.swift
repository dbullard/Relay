//
//  TextModuleModel.swift
//  Relay
//
//  Created by David Bullard on 12/1/25.
//


import Foundation
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#endif

/// Model for a single rich text module instance.
///
/// Word/Pages-like behavior:
/// - Formatting is stored *inside* `content` as attributes (per-range), not as a single set of sliders.
/// - We keep legacy formatting fields for backward-compatible decoding of older saved dashboards,
///   but we do NOT force-apply those legacy fields during render.
struct TextModuleModel: Identifiable, Equatable, Codable {
    var id: UUID = UUID()

    /// Optional header label for the module (e.g., "Notes", "Lyrics", etc.)
    var header: String?

    /// The main rich text content.
    var content: AttributedString

    /// Optional background “chip” style for the header.
    var showsHeaderBackground: Bool = true

    // MARK: - Deprecated legacy defaults (kept for backward compatibility)
    // These were used when the module behaved like a single-style text block.
    // We still decode/encode them so old dashboards don't break, but we no longer
    // enforce them in the renderer. They can be used later as "typing defaults" if desired.
    var alignment: TextAlignment = .leading
    var lineSpacing: Double = 4
    var fontSize: Double = 16
    var fontWeight: Font.Weight = .regular
    var isItalic: Bool = false

    // Explicit memberwise initializer because we provide a custom init(from:) for Codable.
    init(
        id: UUID = UUID(),
        header: String? = nil,
        content: AttributedString = AttributedString(""),
        showsHeaderBackground: Bool = true
    ) {
        self.id = id
        self.header = header
        self.content = content
        self.showsHeaderBackground = showsHeaderBackground
    }

    // MARK: - Codable Support

    private enum CodingKeys: String, CodingKey {
        case id
        case header
        case content
        case showsHeaderBackground

        // Legacy keys (kept for backward compatibility)
        case alignment
        case lineSpacing
        case fontSize
        case fontWeight
        case isItalic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        content = try container.decodeIfPresent(AttributedString.self, forKey: .content) ?? AttributedString("")
        showsHeaderBackground = try container.decodeIfPresent(Bool.self, forKey: .showsHeaderBackground) ?? true

        // Legacy decoding (do not force-apply; kept as defaults)
        let alignmentString = try container.decodeIfPresent(String.self, forKey: .alignment) ?? "leading"
        switch alignmentString {
        case "leading": alignment = .leading
        case "center": alignment = .center
        case "trailing": alignment = .trailing
        default: alignment = .leading
        }

        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 4
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 16

        let weightString = try container.decodeIfPresent(String.self, forKey: .fontWeight) ?? "regular"
        switch weightString {
        case "bold": fontWeight = .bold
        case "semibold": fontWeight = .semibold
        case "medium": fontWeight = .medium
        case "light": fontWeight = .light
        default: fontWeight = .regular
        }

        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(header, forKey: .header)
        try container.encode(content, forKey: .content)
        try container.encode(showsHeaderBackground, forKey: .showsHeaderBackground)

        // Legacy encoding (kept for backward compatibility)
        let alignmentString: String
        switch alignment {
        case .leading: alignmentString = "leading"
        case .center: alignmentString = "center"
        case .trailing: alignmentString = "trailing"
        }
        try container.encode(alignmentString, forKey: .alignment)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(fontSize, forKey: .fontSize)

        let weightString: String
        switch fontWeight {
        case .bold: weightString = "bold"
        case .semibold: weightString = "semibold"
        case .medium: weightString = "medium"
        case .light: weightString = "light"
        default: weightString = "regular"
        }
        try container.encode(weightString, forKey: .fontWeight)
        try container.encode(isItalic, forKey: .isItalic)
    }

    static func == (lhs: TextModuleModel, rhs: TextModuleModel) -> Bool {
        lhs.id == rhs.id
        && lhs.header == rhs.header
        && lhs.showsHeaderBackground == rhs.showsHeaderBackground
        && lhs.alignment == rhs.alignment
        && lhs.lineSpacing == rhs.lineSpacing
        && lhs.fontSize == rhs.fontSize
        && lhs.fontWeight == rhs.fontWeight
        && lhs.isItalic == rhs.isItalic
        && textContentEquals(lhs.content, rhs.content)
    }

    private static func textContentEquals(_ lhs: AttributedString, _ rhs: AttributedString) -> Bool {
        let left = NSAttributedString(lhs)
        let right = NSAttributedString(rhs)
        return left.isEqual(to: right)
    }
}

// MARK: - Tile Rendering

/// A reusable view that renders a `TextModuleModel`.
///
/// Word-like rendering:
/// - Does NOT override fonts/weights/italics/alignment globally.
/// - The attributed content controls formatting.
struct TextModuleView: View {
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    let model: TextModuleModel
    let resolvedContent: AttributedString?

    init(model: TextModuleModel, resolvedContent: AttributedString? = nil) {
        self.model = model
        self.resolvedContent = resolvedContent
    }

    private var displayedContent: AttributedString {
        resolvedContent ?? model.content
    }

    private var resolvedTextAlignment: TextAlignment {
        switch model.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var resolvedHorizontalAlignment: Alignment {
        switch model.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var resolvedStackAlignment: HorizontalAlignment {
        switch model.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    #if os(macOS)
    private var resolvedNSTextAlignment: NSTextAlignment {
        switch model.alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
    #endif

    var body: some View {
        VStack(alignment: resolvedStackAlignment, spacing: 6) {
            if let header = model.header, !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                headerView(header)
                    .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
            }

            #if os(macOS)
            if isLANSnapshotRendering {
                Text(displayedContent)
                    .multilineTextAlignment(resolvedTextAlignment)
                    .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
            } else {
                RichTextDisplay(attributedText: displayedContent, alignment: resolvedNSTextAlignment, lineSpacing: model.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
            }
            #else
            Text(displayedContent)
                .multilineTextAlignment(resolvedTextAlignment)
                .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func headerView(_ text: String) -> some View {
        if model.showsHeaderBackground {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.35))
                )
        } else {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

#if os(macOS)
/// Read-only rich text renderer for better fidelity than `Text(AttributedString)`.
private final class PassthroughScrollView: NSScrollView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class PassthroughTextView: NSTextView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct RichTextDisplay: NSViewRepresentable {
    let attributedText: AttributedString
    let alignment: NSTextAlignment
    let lineSpacing: Double

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PassthroughTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesRuler = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true

        let scroll = PassthroughScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width]
        scroll.documentView = textView

        textView.textStorage?.setAttributedString(NSAttributedString(attributedText))
        applyParagraphStyle(to: textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let incoming = NSAttributedString(attributedText)
        if textView.attributedString() != incoming {
            textView.textStorage?.setAttributedString(incoming)
        }
        applyParagraphStyle(to: textView)
    }

    private func applyParagraphStyle(to textView: NSTextView) {
        let range = NSRange(location: 0, length: textView.string.utf16.count)
        guard range.length > 0 else { return }
        textView.textStorage?.beginEditing()
        textView.textStorage?.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
            let existing = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let next = existing.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            next.alignment = alignment
            next.lineSpacing = CGFloat(lineSpacing)
            textView.textStorage?.addAttribute(.paragraphStyle, value: next, range: subRange)
        }
        textView.textStorage?.endEditing()
    }
}
#endif

// MARK: - Text Module Settings (WYSIWYG Editor)

struct TextModuleSettingsView: View {
    @Binding var tab: DashboardTab
    @Binding var model: TextModuleModel
    let onPersist: () -> Void
    @ObservedObject private var externalDevicesStore = ExternalDevicesStore.shared
    @State private var consoleSyncRevision = 0

    #if os(macOS)
    @StateObject private var editor: RichTextEditorController
    #endif

    #if os(iOS)
    @StateObject private var formattingState = RichTextToolbarState()
    #endif

    init(moduleId: UUID, tab: Binding<DashboardTab>, model: Binding<TextModuleModel>, onPersist: @escaping () -> Void) {
        self._tab = tab
        self._model = model
        self.onPersist = onPersist
        #if os(macOS)
        _editor = StateObject(wrappedValue: TextEditorControllerStore.shared.controller(for: moduleId))
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSettings

            Divider().opacity(0.35)

            contentEditor
        }
        .padding(.vertical, 6)
        .toggleStyle(.switch)
        .onAppear {
            #if os(macOS)
            editor.setIfNeeded(from: model.content)
            editor.availableVariables = availableVariables
            editor.interpolationCandidateProvider = nil
            #endif
        }
        #if os(macOS)
        .onChange(of: availableVariables) { _, newValue in
            editor.availableVariables = newValue
            DispatchQueue.main.async {
                editor.refreshVariableCompletion()
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            consoleSyncRevision += 1
            #if os(macOS)
            editor.interpolationCandidateProvider = nil
            #endif
        }
    }

    private var availableVariables: [String: String] {
        GraphRuntime.variableValuesByName(tab: tab)
    }

    #if os(macOS)
    private var tokenInsertSections: [TokenInsertMenuSection] {
        tokenInsertMenuSections(
            variables: availableVariables,
            devices: externalDevicesStore.devices,
            shureChannelNameCache: externalDevicesStore.shureChannelNameCache,
            sennheiserChannelNameCache: externalDevicesStore.sennheiserChannelNameCache
        )
    }
    #else
    private var tokenInsertSections: [TokenInsertMenuSection] {
        tokenInsertMenuSections(
            variables: availableVariables,
            devices: externalDevicesStore.devices,
            shureChannelNameCache: externalDevicesStore.shureChannelNameCache,
            sennheiserChannelNameCache: externalDevicesStore.sennheiserChannelNameCache
        )
    }
    #endif

    private var headerSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Header")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(
                "Optional header (e.g. Notes)",
                text: Binding(
                    get: { model.header ?? "" },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.header = trimmed.isEmpty ? nil : trimmed
                        onPersist()
                    }
                )
            )

            Toggle("Header background", isOn: Binding(
                get: { model.showsHeaderBackground },
                set: { newValue in
                    model.showsHeaderBackground = newValue
                    onPersist()
                }
            ))
        }
    }

    @ViewBuilder
    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.caption)
                .foregroundStyle(.secondary)

            #if os(macOS)
            let fontOptions = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()

            RichTextToolbar(
                onBold: { editor.toggleBold() },
                onItalic: { editor.toggleItalic() },
                onUnderline: { editor.toggleUnderline() },
                onInsertToken: { token in
                    editor.insertToken(token)
                    onPersist()
                },
                onAlignLeft: {
                    editor.applyAlignment(.left)
                    model.alignment = .leading
                    onPersist()
                },
                onAlignCenter: {
                    editor.applyAlignment(.center)
                    model.alignment = .center
                    onPersist()
                },
                onAlignRight: {
                    editor.applyAlignment(.right)
                    model.alignment = .trailing
                    onPersist()
                },
                onFontChange: { newValue in
                    editor.applyFontFamily(newValue)
                    onPersist()
                },
                onFontWeightChange: { newValue in
                    editor.applyFontWeight(newValue)
                    onPersist()
                },
                onCaseChange: { mode in
                    editor.applyCase(mode)
                    onPersist()
                },
                fontOptions: fontOptions,
                fontName: Binding(
                    get: {
                        fontOptions.contains(editor.currentFontName) ? editor.currentFontName : "System"
                    },
                    set: { newValue in
                        editor.currentFontName = newValue
                    }
                ),
                fontSize: Binding(
                    get: { editor.currentFontSize },
                    set: { newValue in
                        editor.applyFontSize(newValue)
                        onPersist()
                    }
                ),
                textColor: Binding(
                    get: { editor.currentTextColor },
                    set: { newValue in
                        editor.applyTextColor(newValue)
                        onPersist()
                    }
                ),
                selectedWeight: Binding(
                    get: { editor.currentFontWeight },
                    set: { newValue in
                        editor.currentFontWeight = newValue
                    }
                ),
                lineSpacing: Binding(
                    get: { editor.currentLineSpacing },
                    set: { newValue in
                        editor.applyLineSpacing(newValue)
                        model.lineSpacing = newValue
                        onPersist()
                    }
                ),
                kerning: Binding(
                    get: { editor.currentKerning },
                    set: { newValue in
                        editor.applyKerning(newValue)
                        onPersist()
                    }
                ),
                fontSizeDisplay: $editor.fontSizeDisplay,
                lineSpacingDisplay: $editor.lineSpacingDisplay,
                kerningDisplay: $editor.kerningDisplay,
                fontSizeIsMixed: $editor.fontSizeIsMixed,
                lineSpacingIsMixed: $editor.lineSpacingIsMixed,
                kerningIsMixed: $editor.kerningIsMixed,
                fontNameIsMixed: $editor.fontNameIsMixed,
                caseIsMixed: $editor.caseIsMixed,
                tokenSections: tokenInsertSections
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            RichTextEditor(
                controller: editor,
                attributedText: Binding(
                    get: { model.content },
                    set: { newValue in
                        model.content = newValue
                        onPersist()
                    }
                )
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )

            Text("Use `#myVariable`, `{FOH dLive:23}` for a saved console channel name, or `{Lead Vocal:1}` for a saved wireless channel name.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            #else
            RichTextEditor_iOS(
                attributedText: $model.content,
                formattingState: formattingState,
                tokenSections: tokenInsertSections,
                onPersist: onPersist
            )
            .frame(minHeight: 200)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .onChange(of: formattingState.alignment) { _, newAlignment in
                model.alignment = newAlignment
            }

            Text("Use `#myVariable`, `{FOH dLive:23}` for a saved console channel name, or `{Lead Vocal:1}` for a saved wireless channel name.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            #endif
        }
    }
}

#if os(macOS)
private struct VariableTokenCompletionContext {
    let replacementRange: NSRange
    let query: String
    let usesBraces: Bool

    func token(for variableName: String) -> String {
        usesBraces ? "#{\(variableName)}" : "#\(variableName)"
    }
}

private struct InterpolationTokenCompletionContext {
    let replacementRange: NSRange
    let query: String
}

private func variableTokenCompletionContext(in text: String, selection: NSRange) -> VariableTokenCompletionContext? {
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

    return VariableTokenCompletionContext(
        replacementRange: match.range(at: 0),
        query: (prefix as NSString).substring(with: queryRange),
        usesBraces: match.range(at: 1).length > 0
    )
}

private func interpolationTokenCompletionContext(in text: String, selection: NSRange) -> InterpolationTokenCompletionContext? {
    guard selection.length == 0 else { return nil }

    let nsText = text as NSString
    let cursor = min(selection.location, nsText.length)
    let prefix = nsText.substring(to: cursor)
    guard let regex = try? NSRegularExpression(pattern: #"\{([^{}\n]*)$"#) else {
        return nil
    }

    let range = NSRange(location: 0, length: (prefix as NSString).length)
    guard let match = regex.firstMatch(in: prefix, range: range) else { return nil }
    let queryRange = match.range(at: 1)
    guard queryRange.location != NSNotFound else { return nil }

    return InterpolationTokenCompletionContext(
        replacementRange: match.range(at: 0),
        query: (prefix as NSString).substring(with: queryRange)
    )
}

private final class VariableCompletionTextView: NSTextView {
    var variableValueProvider: (() -> [String: String])?
    var interpolationCandidateProvider: ((String) -> [GraphRuntime.TextInterpolationCompletionCandidate])?
    fileprivate private(set) var currentVariableCompletionContext: VariableTokenCompletionContext?
    fileprivate private(set) var currentInterpolationCompletionContext: InterpolationTokenCompletionContext?
    private var activeCompletionMenuContext: VariableTokenCompletionContext?
    private var activeInterpolationMenuContext: InterpolationTokenCompletionContext?

    func syncVariableCompletionContext() {
        currentVariableCompletionContext = variableTokenCompletionContext(in: string, selection: selectedRange())
        currentInterpolationCompletionContext = interpolationTokenCompletionContext(in: string, selection: selectedRange())
    }

    func refreshVariableCompletion() {
        syncVariableCompletionContext()
        guard window?.firstResponder === self else { return }

        if let context = currentInterpolationCompletionContext {
            let matches = interpolationCandidateProvider?(context.query) ?? []
            if !matches.isEmpty {
                activeInterpolationMenuContext = context
                activeCompletionMenuContext = nil
                complete(nil)
                return
            }
        }

        activeInterpolationMenuContext = nil

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
        if let context = currentInterpolationCompletionContext ?? activeInterpolationMenuContext {
            return (interpolationCandidateProvider?(context.query) ?? [])
                .map(\.replacement)
        }

        guard let context = currentVariableCompletionContext ?? activeCompletionMenuContext else { return [] }
        let normalizedQuery = normalizeGraphVariableName(context.query)
        return (variableValueProvider?() ?? [:])
            .filter { normalizedQuery.isEmpty || $0.key.hasPrefix(normalizedQuery) }
            .sorted { $0.key < $1.key }
            .map(\.key)
    }

    fileprivate var shouldPreselectCompletionCandidate: Bool {
        let query = (currentInterpolationCompletionContext ?? activeInterpolationMenuContext)?.query
            ?? (currentVariableCompletionContext ?? activeCompletionMenuContext)?.query
            ?? ""
        return !query.isEmpty
    }

    private func interpolationCompletionCandidate(for replacementString: String) -> GraphRuntime.TextInterpolationCompletionCandidate? {
        guard let context = interpolationTokenCompletionContext(in: string, selection: selectedRange())
            ?? currentInterpolationCompletionContext
            ?? activeInterpolationMenuContext else { return nil }
        let candidates = interpolationCandidateProvider?(context.query) ?? []
        return candidates.first(where: {
            $0.display == replacementString
                || $0.replacement == replacementString
                || $0.replacement.hasSuffix(replacementString)
        })
    }

    fileprivate func completionTokenIfNeeded(for replacementString: String?, affectedRange: NSRange) -> (range: NSRange, token: String)? {
        guard let replacementString else { return nil }

        if let context = interpolationTokenCompletionContext(in: string, selection: selectedRange())
            ?? currentInterpolationCompletionContext
            ?? activeInterpolationMenuContext {
            if let candidate = interpolationCompletionCandidate(for: replacementString) {
                let contextRange = context.replacementRange
                let matchesContextRange = NSEqualRanges(affectedRange, contextRange)
                    || affectedRange.location == contextRange.location + 1
                    || NSLocationInRange(affectedRange.location, contextRange)
                guard matchesContextRange else { return nil }

                activeInterpolationMenuContext = nil
                currentInterpolationCompletionContext = nil
                activeCompletionMenuContext = nil
                currentVariableCompletionContext = nil
                return (contextRange, candidate.replacement)
            }
        }

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
        activeInterpolationMenuContext = nil
        currentInterpolationCompletionContext = nil
        return (contextRange, context.token(for: normalizedReplacement))
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            SharedValuePickerCoordinator.shared.target = self
        }
        return becameFirstResponder
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        if let context = interpolationTokenCompletionContext(in: string, selection: selectedRange())
            ?? currentInterpolationCompletionContext
            ?? activeInterpolationMenuContext,
           let candidate = interpolationCompletionCandidate(for: word),
           let textStorage {
            let attributes: [NSAttributedString.Key: Any] = {
                guard textStorage.length > 0 else { return typingAttributes }
                let attributeLocation = min(max(context.replacementRange.location, 0), textStorage.length - 1)
                return textStorage.attributes(at: attributeLocation, effectiveRange: nil)
            }()

            shouldChangeText(in: context.replacementRange, replacementString: candidate.replacement)
            textStorage.beginEditing()
            textStorage.replaceCharacters(
                in: context.replacementRange,
                with: NSAttributedString(string: candidate.replacement, attributes: attributes)
            )
            textStorage.endEditing()
            didChangeText()

            let caretLocation = context.replacementRange.location + (candidate.replacement as NSString).length
            setSelectedRange(NSRange(location: caretLocation, length: 0))

            activeInterpolationMenuContext = nil
            currentInterpolationCompletionContext = nil
            activeCompletionMenuContext = nil
            currentVariableCompletionContext = nil

            if candidate.replacement.hasSuffix(":") {
                DispatchQueue.main.async { [weak self] in
                    self?.refreshVariableCompletion()
                }
            }
            return
        }

        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }
}

extension VariableCompletionTextView: SharedValueInsertionTarget {
    func insertSharedValueToken(_ token: String) -> Bool {
        guard isEditable else { return false }
        insertText(token, replacementRange: selectedRange())
        return true
    }
}

/// Controls the currently focused text view and provides convenience methods
/// to apply formatting to the selected range.
final class RichTextEditorController: ObservableObject {
    weak var textView: NSTextView?

    @Published var currentFontName: String = "System"
    @Published var currentFontSize: Double = 16
    @Published var currentFontWeight: Int = 4
    @Published var currentLineSpacing: Double = 4
    @Published var currentKerning: Double = 0
    @Published var currentTextColor: Color = .white

    @Published var fontSizeDisplay: String = "16"
    @Published var lineSpacingDisplay: String = "4"
    @Published var kerningDisplay: String = "0"
    @Published var fontSizeIsMixed = false
    @Published var lineSpacingIsMixed = false
    @Published var kerningIsMixed = false
    @Published var fontNameIsMixed = false
    @Published var caseIsMixed = false
    @Published var availableVariables: [String: String] = [:]
    var interpolationCandidateProvider: ((String) -> [GraphRuntime.TextInterpolationCompletionCandidate])?

    private var hasSeededOnce = false
    private var lastCaseRange: NSRange?
    private var lastCaseOriginal: String?

    func setIfNeeded(from attributed: AttributedString) {
        guard !hasSeededOnce else { return }
        hasSeededOnce = true
        // Best-effort: infer a reasonable default from the first character.
        let ns = NSAttributedString(attributed)
        if ns.length > 0 {
            let attrs = ns.attributes(at: 0, effectiveRange: nil)
            if let font = attrs[.font] as? NSFont {
                currentFontSize = Double(font.pointSize)
                currentFontName = font.familyName ?? "System"
                currentFontWeight = NSFontManager.shared.weight(of: font)
            }
            if let color = attrs[.foregroundColor] as? NSColor {
                currentTextColor = Color(color)
            }
            if let style = attrs[.paragraphStyle] as? NSParagraphStyle {
                currentLineSpacing = Double(style.lineSpacing)
            }
            if let kern = attrs[.kern] as? Double {
                currentKerning = kern
            } else if let kern = attrs[.kern] as? CGFloat {
                currentKerning = Double(kern)
            }
        }
        updateDisplayValues(fontSize: currentFontSize, lineSpacing: currentLineSpacing, kerning: currentKerning)
    }

    enum ParagraphAlignment {
        case left, center, right
    }

    func refreshSelectionState(allowVariableCompletion: Bool = true) {
        guard let tv = textView else { return }
        let selection = tv.selectedRange()
        if allowVariableCompletion {
            (tv as? VariableCompletionTextView)?.refreshVariableCompletion()
        }

        let targetRange = selection.length > 0
            ? selection
            : NSRange(location: 0, length: tv.string.utf16.count)

        guard targetRange.length > 0 else {
            fontSizeIsMixed = false
            lineSpacingIsMixed = false
            kerningIsMixed = false
            updateDisplayValues(fontSize: currentFontSize, lineSpacing: currentLineSpacing, kerning: currentKerning)
            return
        }

        let fontSizeValue = uniformFontSize(in: tv, range: targetRange)
        if let value = fontSizeValue {
            fontSizeIsMixed = false
            currentFontSize = value
        } else {
            fontSizeIsMixed = true
        }

        let lineSpacingValue = uniformLineSpacing(in: tv, range: targetRange)
        if let value = lineSpacingValue {
            lineSpacingIsMixed = false
            currentLineSpacing = value
        } else {
            lineSpacingIsMixed = true
        }

        let kerningValue = uniformKerning(in: tv, range: targetRange)
        if let value = kerningValue {
            kerningIsMixed = false
            currentKerning = value
        } else {
            kerningIsMixed = true
        }

        let fontNameValue = uniformFontName(in: tv, range: targetRange)
        if let value = fontNameValue {
            fontNameIsMixed = false
            currentFontName = value
        } else {
            fontNameIsMixed = true
        }

        caseIsMixed = (inferredCaseMode(in: tv, range: targetRange) == nil)

        updateDisplayValues(
            fontSize: fontSizeIsMixed ? nil : currentFontSize,
            lineSpacing: lineSpacingIsMixed ? nil : currentLineSpacing,
            kerning: kerningIsMixed ? nil : currentKerning
        )
    }

    func refreshVariableCompletion() {
        (textView as? VariableCompletionTextView)?.refreshVariableCompletion()
    }

    func syncVariableCompletionContext() {
        (textView as? VariableCompletionTextView)?.syncVariableCompletionContext()
    }

    func insertToken(_ token: String) {
        guard let tv = textView, let textStorage = tv.textStorage else { return }

        let selection = tv.selectedRange()
        let attributes: [NSAttributedString.Key: Any] = {
            guard textStorage.length > 0 else { return tv.typingAttributes }
            let attributeLocation = min(max(selection.location - 1, 0), textStorage.length - 1)
            return textStorage.attributes(at: attributeLocation, effectiveRange: nil)
        }()

        tv.shouldChangeText(in: selection, replacementString: token)
        textStorage.beginEditing()
        textStorage.replaceCharacters(
            in: selection,
            with: NSAttributedString(string: token, attributes: attributes)
        )
        textStorage.endEditing()
        tv.didChangeText()

        let newLocation = selection.location + (token as NSString).length
        tv.setSelectedRange(NSRange(location: newLocation, length: 0))
        refreshSelectionState(allowVariableCompletion: false)
    }

    private func uniformFontSize(in textView: NSTextView, range: NSRange) -> Double? {
        var result: Double?
        var isMixed = false
        textView.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(currentFontSize))
            let size = Double(font.pointSize)
            if let existing = result {
                if abs(existing - size) > 0.001 {
                    isMixed = true
                    stop.pointee = true
                }
            } else {
                result = size
            }
        }
        return isMixed ? nil : result
    }

    private func uniformLineSpacing(in textView: NSTextView, range: NSRange) -> Double? {
        var result: Double?
        var isMixed = false
        textView.textStorage?.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, _, stop in
            let style = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let spacing = Double(style.lineSpacing)
            if let existing = result {
                if abs(existing - spacing) > 0.001 {
                    isMixed = true
                    stop.pointee = true
                }
            } else {
                result = spacing
            }
        }
        return isMixed ? nil : result
    }

    private func uniformKerning(in textView: NSTextView, range: NSRange) -> Double? {
        var result: Double?
        var isMixed = false
        textView.textStorage?.enumerateAttribute(.kern, in: range, options: []) { value, _, stop in
            let kern: Double
            if let v = value as? Double {
                kern = v
            } else if let v = value as? CGFloat {
                kern = Double(v)
            } else {
                kern = 0
            }
            if let existing = result {
                if abs(existing - kern) > 0.001 {
                    isMixed = true
                    stop.pointee = true
                }
            } else {
                result = kern
            }
        }
        return isMixed ? nil : result
    }

    private func uniformFontName(in textView: NSTextView, range: NSRange) -> String? {
        var result: String?
        var isMixed = false
        textView.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(currentFontSize))
            let name = font.familyName ?? "System"
            if let existing = result {
                if existing != name {
                    isMixed = true
                    stop.pointee = true
                }
            } else {
                result = name
            }
        }
        return isMixed ? nil : result
    }

    private func inferredCaseMode(in textView: NSTextView, range: NSRange) -> RichTextEditorController.CaseMode? {
        let raw = (textView.string as NSString).substring(with: range)
        guard raw.rangeOfCharacter(from: CharacterSet.letters) != nil else {
            return .normal
        }
        if raw == raw.uppercased() { return .uppercase }
        if raw == raw.lowercased() { return .lowercase }
        if raw == raw.capitalized { return .title }
        return nil
    }

    private func updateDisplayValues(fontSize: Double?, lineSpacing: Double?, kerning: Double?) {
        fontSizeDisplay = fontSize.map { String(Int(round($0))) } ?? ""
        lineSpacingDisplay = lineSpacing.map { String(format: "%.1f", $0) } ?? ""
        kerningDisplay = kerning.map { String(format: "%.1f", $0) } ?? ""
    }

    private func nsFontWeight(for weight: Int) -> NSFont.Weight {
        switch weight {
        case ..<2: return .ultraLight
        case 2: return .thin
        case 3: return .light
        case 4: return .regular
        case 5: return .medium
        case 6: return .semibold
        case 7: return .bold
        case 8: return .heavy
        default: return .black
        }
    }

    private func systemFontPreservingTraits(from existing: NSFont, size: CGFloat, weight: Int) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: nsFontWeight(for: weight))
        let traits = NSFontManager.shared.traits(of: existing)
        if traits.contains(.italicFontMask) {
            return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask).withSize(size)
        }
        return base.withSize(size)
    }

    private func toggledFont(from existing: NSFont, trait: NSFontTraitMask) -> NSFont {
        let fm = NSFontManager.shared
        let hasTrait = fm.traits(of: existing).contains(trait)
        let converted = hasTrait
            ? fm.convert(existing, toNotHaveTrait: trait)
            : fm.convert(existing, toHaveTrait: trait)
        return converted.withSize(existing.pointSize)
    }

    func toggleBold() {
        toggleFontTrait(.boldFontMask)
    }

    func toggleItalic() {
        toggleFontTrait(.italicFontMask)
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()

        if range.length == 0 {
            var attrs = tv.typingAttributes
            let existing = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(currentFontSize))
            attrs[.font] = toggledFont(from: existing, trait: trait)
            tv.typingAttributes = attrs
            tv.didChangeText()
            return
        }

        tv.textStorage?.beginEditing()
        tv.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let existing = (value as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(self.currentFontSize))
            let next = self.toggledFont(from: existing, trait: trait)
            tv.textStorage?.addAttribute(.font, value: next, range: subRange)
        }
        tv.textStorage?.endEditing()
        tv.didChangeText()
    }

    func toggleUnderline() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()

        let applyStyle: Int = NSUnderlineStyle.single.rawValue

        if range.length == 0 {
            var attrs = tv.typingAttributes
            let existing = (attrs[.underlineStyle] as? Int) ?? 0
            attrs[.underlineStyle] = (existing == 0) ? applyStyle : 0
            tv.typingAttributes = attrs
            tv.didChangeText()
            return
        }

        // Determine if selection is mostly underlined; toggle accordingly.
        var anyUnderlined = false
        tv.textStorage?.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
            let v = (value as? Int) ?? 0
            if v != 0 {
                anyUnderlined = true
                stop.pointee = true
            }
        }

        let newValue = anyUnderlined ? 0 : applyStyle
        tv.textStorage?.addAttribute(.underlineStyle, value: newValue, range: range)
        tv.didChangeText()
    }

    func applyAlignment(_ alignment: ParagraphAlignment) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()

        let nsAlignment: NSTextAlignment
        switch alignment {
        case .left: nsAlignment = .left
        case .center: nsAlignment = .center
        case .right: nsAlignment = .right
        }

        let applyToRange = (range.length > 0)
            ? range
            : NSRange(location: 0, length: tv.string.utf16.count)

        // Always update typing attributes so new text matches.
        var attrs = tv.typingAttributes
        let typingStyle = (attrs[.paragraphStyle] as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        typingStyle.alignment = nsAlignment
        attrs[.paragraphStyle] = typingStyle
        tv.typingAttributes = attrs

        if applyToRange.length == 0 {
            tv.didChangeText()
            return
        }

        tv.textStorage?.beginEditing()
        tv.textStorage?.enumerateAttribute(.paragraphStyle, in: applyToRange, options: []) { value, subRange, _ in
            let existing = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let next = existing.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            next.alignment = nsAlignment
            tv.textStorage?.addAttribute(.paragraphStyle, value: next, range: subRange)
        }
        tv.textStorage?.endEditing()

        if range.length > 0 {
            tv.setSelectedRange(range)
        }

        tv.didChangeText()
    }

    func applyFontSize(_ size: Double) {
        guard let tv = textView else { return }
        currentFontSize = size
        fontSizeIsMixed = false
        updateDisplayValues(fontSize: size, lineSpacing: lineSpacingIsMixed ? nil : currentLineSpacing, kerning: kerningIsMixed ? nil : currentKerning)

        let range = tv.selectedRange()
        let targetRange = range.length > 0 ? range : NSRange(location: 0, length: tv.string.utf16.count)

        if targetRange.length == 0 {
            return
        }

        if range.length == 0 {
            // Set typing attributes for new text
            var attrs = tv.typingAttributes
            let existingFont = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(size))
            attrs[.font] = existingFont.withSize(CGFloat(size))
            tv.typingAttributes = attrs
        }

        tv.textStorage?.beginEditing()
        tv.textStorage?.enumerateAttribute(.font, in: targetRange, options: []) { value, subRange, _ in
            let existing = (value as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(size))
            let next = existing.withSize(CGFloat(size))
            tv.textStorage?.addAttribute(.font, value: next, range: subRange)
        }
        tv.textStorage?.endEditing()

        // Attribute changes don’t always trigger `textDidChange`; force an update.
        tv.didChangeText()
    }

    func applyFontFamily(_ family: String) {
        guard let tv = textView else { return }
        currentFontName = family

        let range = tv.selectedRange()
        let targetRange = range.length > 0 ? range : NSRange(location: 0, length: tv.string.utf16.count)

        let resolveFont: (NSFont) -> NSFont = { existing in
            let size = existing.pointSize
            if family == "System" {
                return self.systemFontPreservingTraits(from: existing, size: size, weight: self.currentFontWeight)
            }
            let traits = NSFontManager.shared.traits(of: existing)
            let weight = self.currentFontWeight
            return NSFontManager.shared.font(withFamily: family, traits: traits, weight: weight, size: size)
                ?? NSFont(name: family, size: size)
                ?? existing
        }

        tv.textStorage?.beginEditing()
        tv.textStorage?.enumerateAttribute(.font, in: targetRange, options: []) { value, subRange, _ in
            let existing = (value as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(self.currentFontSize))
            let nextFont = resolveFont(existing)
            tv.textStorage?.addAttribute(.font, value: nextFont, range: subRange)
        }
        tv.textStorage?.endEditing()

        var attrs = tv.typingAttributes
        let existingTyping = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(currentFontSize))
        attrs[.font] = resolveFont(existingTyping)
        tv.typingAttributes = attrs

        if range.length > 0 {
            tv.setSelectedRange(range)
        }

        tv.didChangeText()
    }

    func applyFontWeight(_ weight: Int) {
        guard let tv = textView else { return }
        currentFontWeight = weight

        let range = tv.selectedRange()
        let targetRange = range.length > 0 ? range : NSRange(location: 0, length: tv.string.utf16.count)

        let resolveFont: (NSFont) -> NSFont = { existing in
            let size = existing.pointSize
            let family = self.currentFontName == "System" ? existing.familyName ?? "System" : self.currentFontName
            if family == "System" {
                return self.systemFontPreservingTraits(from: existing, size: size, weight: weight)
            }
            return NSFontManager.shared.font(withFamily: family, traits: NSFontManager.shared.traits(of: existing), weight: weight, size: size)
                ?? NSFont(name: family, size: size)
                ?? existing
        }

        tv.textStorage?.beginEditing()
        tv.textStorage?.enumerateAttribute(.font, in: targetRange, options: []) { value, subRange, _ in
            let existing = (value as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(self.currentFontSize))
            let nextFont = resolveFont(existing)
            tv.textStorage?.addAttribute(.font, value: nextFont, range: subRange)
        }
        tv.textStorage?.endEditing()

        var attrs = tv.typingAttributes
        let existingTyping = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(currentFontSize))
        attrs[.font] = resolveFont(existingTyping)
        tv.typingAttributes = attrs
        tv.didChangeText()
    }

    func applyLineSpacing(_ spacing: Double) {
        guard let tv = textView else { return }
        currentLineSpacing = spacing
        lineSpacingIsMixed = false
        updateDisplayValues(fontSize: fontSizeIsMixed ? nil : currentFontSize, lineSpacing: spacing, kerning: kerningIsMixed ? nil : currentKerning)

        let range = tv.selectedRange()
        let targetRange = range.length > 0 ? range : NSRange(location: 0, length: tv.string.utf16.count)

        var attrs = tv.typingAttributes
        let typingStyle = (attrs[.paragraphStyle] as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        typingStyle.lineSpacing = CGFloat(spacing)
        attrs[.paragraphStyle] = typingStyle
        tv.typingAttributes = attrs

        if targetRange.length == 0 {
            tv.didChangeText()
            return
        }

        tv.textStorage?.beginEditing()
        tv.textStorage?.enumerateAttribute(.paragraphStyle, in: targetRange, options: []) { value, subRange, _ in
            let existing = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let next = existing.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            next.lineSpacing = CGFloat(spacing)
            tv.textStorage?.addAttribute(.paragraphStyle, value: next, range: subRange)
        }
        tv.textStorage?.endEditing()
        tv.didChangeText()
    }

    func applyKerning(_ value: Double) {
        guard let tv = textView else { return }
        currentKerning = value
        kerningIsMixed = false
        updateDisplayValues(fontSize: fontSizeIsMixed ? nil : currentFontSize, lineSpacing: lineSpacingIsMixed ? nil : currentLineSpacing, kerning: value)

        let range = tv.selectedRange()
        let targetRange = range.length > 0 ? range : NSRange(location: 0, length: tv.string.utf16.count)

        var attrs = tv.typingAttributes
        attrs[.kern] = value
        tv.typingAttributes = attrs

        if targetRange.length == 0 {
            tv.didChangeText()
            return
        }

        tv.textStorage?.beginEditing()
        tv.textStorage?.addAttribute(.kern, value: value, range: targetRange)
        tv.textStorage?.endEditing()
        tv.didChangeText()
    }

    enum CaseMode: String, CaseIterable {
        case normal = "Normal"
        case uppercase = "Uppercase"
        case lowercase = "Lowercase"
        case title = "Title Case"
    }

    func applyCase(_ mode: CaseMode) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let targetRange = range.length > 0 ? range : NSRange(location: 0, length: tv.string.utf16.count)
        guard targetRange.length > 0 else { return }

        guard let storage = tv.textStorage else { return }
        let originalAttr = storage.attributedSubstring(from: targetRange)
        let original = originalAttr.string

        switch mode {
        case .normal:
            if let lastRange = lastCaseRange,
               let lastOriginal = lastCaseOriginal,
               NSEqualRanges(lastRange, targetRange) {
                let restored = NSMutableAttributedString(string: lastOriginal)
                originalAttr.enumerateAttributes(in: NSRange(location: 0, length: originalAttr.length), options: []) { attrs, range, _ in
                    restored.setAttributes(attrs, range: range)
                }
                storage.replaceCharacters(in: targetRange, with: restored)
                lastCaseRange = nil
                lastCaseOriginal = nil
                tv.didChangeText()
            }
            return
        case .uppercase:
            lastCaseRange = targetRange
            lastCaseOriginal = original
            let transformed = original.uppercased()
            let replacement = NSMutableAttributedString(string: transformed)
            originalAttr.enumerateAttributes(in: NSRange(location: 0, length: originalAttr.length), options: []) { attrs, range, _ in
                replacement.setAttributes(attrs, range: range)
            }
            storage.replaceCharacters(in: targetRange, with: replacement)
        case .lowercase:
            lastCaseRange = targetRange
            lastCaseOriginal = original
            let transformed = original.lowercased()
            let replacement = NSMutableAttributedString(string: transformed)
            originalAttr.enumerateAttributes(in: NSRange(location: 0, length: originalAttr.length), options: []) { attrs, range, _ in
                replacement.setAttributes(attrs, range: range)
            }
            storage.replaceCharacters(in: targetRange, with: replacement)
        case .title:
            lastCaseRange = targetRange
            lastCaseOriginal = original
            let transformed = original.capitalized
            let replacement = NSMutableAttributedString(string: transformed)
            originalAttr.enumerateAttributes(in: NSRange(location: 0, length: originalAttr.length), options: []) { attrs, range, _ in
                replacement.setAttributes(attrs, range: range)
            }
            storage.replaceCharacters(in: targetRange, with: replacement)
        }

        tv.didChangeText()
    }

    func applyTextColor(_ color: Color) {
        guard let tv = textView else { return }
        currentTextColor = color
        let nsColor = NSColor(color)

        let range = tv.selectedRange()
        if range.length == 0 {
            var attrs = tv.typingAttributes
            attrs[.foregroundColor] = nsColor
            tv.typingAttributes = attrs
            tv.didChangeText()
        } else {
            tv.textStorage?.addAttribute(.foregroundColor, value: nsColor, range: range)
            tv.didChangeText()
        }
    }
}

/// WYSIWYG editor backed by NSTextView.
private struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var controller: RichTextEditorController
    @Binding var attributedText: AttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText, controller: controller)
    }

    private func defaultTypingAttributes(for textView: NSTextView) -> [NSAttributedString.Key: Any] {
        let size = CGFloat(controller.currentFontSize)
        let font: NSFont
        if controller.currentFontName == "System" {
            font = NSFont.systemFont(ofSize: size)
        } else {
            font = NSFont(name: controller.currentFontName, size: size) ?? NSFont.systemFont(ofSize: size)
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = CGFloat(controller.currentLineSpacing)
        return [
            .font: font,
            .foregroundColor: NSColor(controller.currentTextColor),
            .paragraphStyle: style,
            .kern: controller.currentKerning
        ]
    }

    private func applyingDefaultTypingAttributesIfMissing(to attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }

        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)
        let defaults = defaultTypingAttributes(for: NSTextView())

        mutable.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            for (key, defaultValue) in defaults where attrs[key] == nil {
                mutable.addAttribute(key, value: defaultValue, range: range)
            }
        }

        return mutable
    }

    private func restoreSelection(_ ranges: [Any], in textView: NSTextView) {
        let maxLen = textView.string.utf16.count
        let clamped = ranges.compactMap { item -> NSRange? in
            guard let range = item as? NSRange else { return nil }
            let loc = min(range.location, maxLen)
            let len = min(range.length, maxLen - loc)
            return NSRange(location: loc, length: len)
        }
        if !clamped.isEmpty {
            let values = clamped.map { NSValue(range: $0) }
            textView.setSelectedRanges(values, affinity: .downstream, stillSelecting: false)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = VariableCompletionTextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesRuler = false
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.isAutomaticDashSubstitutionEnabled = true
        tv.isAutomaticSpellingCorrectionEnabled = true
        tv.isAutomaticTextReplacementEnabled = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.textContainer?.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        // Ensure text view expands to inspector width, not scrolling horizontally
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.textContainer?.widthTracksTextView = true

        tv.insertionPointColor = NSColor.white
        tv.typingAttributes = defaultTypingAttributes(for: tv)
        tv.variableValueProvider = { [weak controller] in
            controller?.availableVariables ?? [:]
        }
        tv.interpolationCandidateProvider = { [weak controller] query in
            controller?.interpolationCandidateProvider?(query) ?? []
        }

        // Seed content
        let seeded = applyingDefaultTypingAttributesIfMissing(to: NSAttributedString(attributedText))
        tv.textStorage?.setAttributedString(seeded)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = tv
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width]

        controller.textView = tv
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            controller.refreshSelectionState(allowVariableCompletion: false)
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if let variableTextView = tv as? VariableCompletionTextView {
            variableTextView.variableValueProvider = { [weak controller] in
                controller?.availableVariables ?? [:]
            }
            variableTextView.interpolationCandidateProvider = { [weak controller] query in
                controller?.interpolationCandidateProvider?(query) ?? []
            }
        }
        if context.coordinator.isEditing || context.coordinator.isSynchronizingFromSwiftUI { return }
        let incoming = applyingDefaultTypingAttributesIfMissing(to: NSAttributedString(attributedText))
        if tv.attributedString() != incoming {
            context.coordinator.isSynchronizingFromSwiftUI = true
            defer { context.coordinator.isSynchronizingFromSwiftUI = false }
            let selectedRanges = tv.selectedRanges
            let scrollPoint = nsView.contentView.bounds.origin
            tv.textStorage?.setAttributedString(incoming)
            restoreSelection(selectedRanges, in: tv)
            nsView.contentView.scroll(to: scrollPoint)
            nsView.reflectScrolledClipView(nsView.contentView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var attributedText: AttributedString
        let controller: RichTextEditorController
        var isEditing = false
        var isSynchronizingFromSwiftUI = false
        var shouldTriggerVariableCompletionAfterChange = false
        var shouldSuppressNextVariableCompletionRefresh = false

        init(attributedText: Binding<AttributedString>, controller: RichTextEditorController) {
            self._attributedText = attributedText
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            guard !isSynchronizingFromSwiftUI else { return }
            isEditing = true
            attributedText = AttributedString(tv.attributedString())
            controller.refreshSelectionState(allowVariableCompletion: false)
            controller.syncVariableCompletionContext()
            if shouldSuppressNextVariableCompletionRefresh {
                shouldSuppressNextVariableCompletionRefresh = false
            } else if shouldTriggerVariableCompletionAfterChange {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.controller.refreshVariableCompletion()
                }
            }
            shouldTriggerVariableCompletionAfterChange = false
            DispatchQueue.main.async { [weak self] in
                self?.isEditing = false
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isSynchronizingFromSwiftUI else { return }
            controller.refreshSelectionState(allowVariableCompletion: false)
            controller.syncVariableCompletionContext()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !isSynchronizingFromSwiftUI else { return true }
            if
                let variableTextView = textView as? VariableCompletionTextView,
                let completionReplacement = variableTextView.completionTokenIfNeeded(
                    for: replacementString,
                    affectedRange: affectedCharRange
                ),
                let textStorage = textView.textStorage
            {
                let attributes: [NSAttributedString.Key: Any] = {
                    guard textStorage.length > 0 else { return textView.typingAttributes }
                    let attributeLocation = min(max(completionReplacement.range.location, 0), textStorage.length - 1)
                    return textStorage.attributes(at: attributeLocation, effectiveRange: nil)
                }()

                isEditing = true
                shouldTriggerVariableCompletionAfterChange = false
                shouldSuppressNextVariableCompletionRefresh = true
                textView.shouldChangeText(in: completionReplacement.range, replacementString: completionReplacement.token)
                textStorage.beginEditing()
                textStorage.replaceCharacters(
                    in: completionReplacement.range,
                    with: NSAttributedString(string: completionReplacement.token, attributes: attributes)
                )
                textStorage.endEditing()
                textView.didChangeText()
                let caretLocation = completionReplacement.range.location + (completionReplacement.token as NSString).length
                textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
                let shouldContinueInterpolationCompletion = completionReplacement.token.hasSuffix(":")
                DispatchQueue.main.async { [weak self] in
                    if shouldContinueInterpolationCompletion,
                       let variableTextView = textView as? VariableCompletionTextView {
                        variableTextView.refreshVariableCompletion()
                    }
                    self?.isEditing = false
                }
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
                variableTokenCompletionContext(in: prospective, selection: prospectiveSelection) != nil
                || interpolationTokenCompletionContext(in: prospective, selection: prospectiveSelection) != nil
            return true
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard let variableTextView = textView as? VariableCompletionTextView else {
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

private struct RichTextToolbar: View {
    struct WeightOption: Identifiable {
        let value: Int
        let label: String
        var id: Int { value }
    }

    let onBold: () -> Void
    let onItalic: () -> Void
    let onUnderline: () -> Void
    let onInsertToken: (String) -> Void
    let onAlignLeft: () -> Void
    let onAlignCenter: () -> Void
    let onAlignRight: () -> Void
    let onFontChange: (String) -> Void
    let onFontWeightChange: (Int) -> Void
    let onCaseChange: (RichTextEditorController.CaseMode) -> Void

    let fontOptions: [String]

    @Binding var fontName: String
    @Binding var fontSize: Double
    @Binding var textColor: Color
    @Binding var selectedWeight: Int
    @Binding var lineSpacing: Double
    @Binding var kerning: Double
    @Binding var fontSizeDisplay: String
    @Binding var lineSpacingDisplay: String
    @Binding var kerningDisplay: String
    @Binding var fontSizeIsMixed: Bool
    @Binding var lineSpacingIsMixed: Bool
    @Binding var kerningIsMixed: Bool
    @Binding var fontNameIsMixed: Bool
    @Binding var caseIsMixed: Bool
    let tokenSections: [TokenInsertMenuSection]

    @State private var selectedCase: RichTextEditorController.CaseMode = .normal

    private var toolbarButtonBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }

    private let controlHeight: CGFloat = 24

    private func pillControl<Content: View>(_ content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .frame(height: controlHeight)
            .background(toolbarButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }

    private func controlLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numericField(_ text: Binding<String>, prompt: String, width: CGFloat) -> some View {
        TextField("", text: text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.leading)
            .frame(width: width)
    }

    private func menuLabel(_ text: String, weight: Font.Weight = .medium) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private let weightOptions: [WeightOption] = [
        .init(value: 5, label: "Regular"),
        .init(value: 6, label: "Medium"),
        .init(value: 7, label: "Semibold"),
        .init(value: 9, label: "Bold")
    ]

    private var caseOptions: [RichTextEditorController.CaseMode] {
        RichTextEditorController.CaseMode.allCases
    }

    private func weightLabel(for value: Int) -> String {
        weightOptions.first(where: { $0.value == value })?.label ?? "Regular"
    }

    private func weightFont(for value: Int) -> Font.Weight {
        switch value {
        case 9: return .bold
        case 7: return .semibold
        case 6: return .medium
        default: return .regular
        }
    }

    private func caseDisplayLabel(for mode: RichTextEditorController.CaseMode) -> String {
        switch mode {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .title: return "Title Case"
        case .normal: return "Normal"
        }
    }

    private func parseInt(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }

    private func parseDecimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Style")

            HStack(spacing: 4) {
                Button { onBold() } label: {
                    Image(systemName: "bold")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .help("Bold (⌘B)")
                .keyboardShortcut("b", modifiers: .command)

                Button { onItalic() } label: {
                    Image(systemName: "italic")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .help("Italic (⌘I)")
                .keyboardShortcut("i", modifiers: .command)

                Button { onUnderline() } label: {
                    Image(systemName: "underline")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .help("Underline (⌘U)")
                .keyboardShortcut("u", modifiers: .command)

                Divider().frame(height: 18)
                    .padding(.horizontal, 2)

                Button { onAlignLeft() } label: {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .help("Align Left")

                Button { onAlignCenter() } label: {
                    Image(systemName: "text.aligncenter")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .help("Align Center")

                Button { onAlignRight() } label: {
                    Image(systemName: "text.alignright")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .help("Align Right")

                if !tokenSections.isEmpty {
                    Divider().frame(height: 18)
                        .padding(.horizontal, 2)

                    Menu {
                        ForEach(tokenSections) { section in
                            if !section.items.isEmpty {
                                Section(section.title) {
                                    ForEach(section.items) { item in
                                        Button(item.title) {
                                            onInsertToken(item.token)
                                        }
                                    }
                                }
                            }

                            if !section.groups.isEmpty {
                                Section(section.title) {
                                    ForEach(section.groups) { group in
                                        Menu(group.title) {
                                            // Sub-groups (e.g. DiGiCo channel types under a console)
                                            ForEach(group.subgroups) { subgroup in
                                                Menu(subgroup.title) {
                                                    ForEach(subgroup.items) { item in
                                                        Button(item.title) { onInsertToken(item.token) }
                                                    }
                                                }
                                            }
                                            // Direct items (non-nested consoles, or fallback)
                                            ForEach(group.items) { item in
                                                Button(item.title) { onInsertToken(item.token) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .help("Insert Variable")
                }
            }

            sectionLabel("Type")

            HStack(spacing: 6) {
                controlIcon("textformat.size")
                pillControl(
                    Stepper(value: $fontSize, in: 1...200, step: 1) {
                        numericField($fontSizeDisplay, prompt: fontSizeIsMixed ? "—" : "", width: 36)
                            .onSubmit {
                                if let parsed = parseInt(fontSizeDisplay) {
                                    fontSize = parsed
                                }
                            }
                    }
                    .frame(width: 104)
                )

                controlIcon("textformat")
                pillControl(
                    Menu {
                        ForEach(fontOptions, id: \.self) { name in
                            Button(name) {
                                fontName = name
                                onFontChange(name)
                            }
                        }
                    } label: {
                        menuLabel(fontNameIsMixed ? "—" : fontName)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(width: 150)
                )
            }

            HStack(spacing: 8) {
                controlIcon("textformat.abc")
                pillControl(
                    Menu {
                        ForEach(caseOptions, id: \.self) { mode in
                            Button {
                                selectedCase = mode
                                onCaseChange(mode)
                            } label: {
                                Text(caseDisplayLabel(for: mode))
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    } label: {
                        menuLabel(caseIsMixed ? "—" : caseDisplayLabel(for: selectedCase))
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(width: 120)
                )

                ColorPicker("", selection: $textColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 22, height: 22)
                    .fixedSize()
                    .padding(.leading, 8)
            }

            sectionLabel("Spacing")

            HStack(spacing: 6) {
                controlIcon("line.3.horizontal")
                pillControl(
                    Stepper(value: $lineSpacing, in: 0...50, step: 0.5) {
                        numericField($lineSpacingDisplay, prompt: lineSpacingIsMixed ? "—" : "", width: 48)
                            .onSubmit {
                                if let parsed = parseDecimal(lineSpacingDisplay) {
                                    lineSpacing = parsed
                                }
                            }
                    }
                    .frame(width: 150)
                )

                controlIcon("textformat.size.larger")
                pillControl(
                    Stepper(value: $kerning, in: -10...20, step: 0.5) {
                        numericField($kerningDisplay, prompt: kerningIsMixed ? "—" : "", width: 48)
                            .onSubmit {
                                if let parsed = parseDecimal(kerningDisplay) {
                                    kerning = parsed
                                }
                            }
                    }
                    .frame(width: 150)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlSize(.small)
        .buttonStyle(.borderless)
    }
}
#endif
// MARK: - Plugin Glue
enum TextModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .text(TextModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let model: TextModuleModel
        if case .text(let m) = module.wrappedValue.kind {
            model = m
        } else {
            model = TextModuleModel()
        }
        return AnyView(ResolvedTextModuleTileView(tab: tab, model: model))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        // NOTE: settings are hosted by DashboardTileEditView via TextModuleSettingsView
        AnyView(EmptyView())
    }
}

private struct ResolvedTextModuleTileView: View {
    @Binding var tab: DashboardTab
    let model: TextModuleModel
    @ObservedObject private var externalDevicesStore = ExternalDevicesStore.shared
    @State private var consoleSyncRevision = 0

    var body: some View {
        TextModuleView(
            model: model,
            resolvedContent: interpolateTextModuleContent(model.content, tab: tab)
        )
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            consoleSyncRevision += 1
        }
    }
}

private func interpolateTextModuleContent(_ content: AttributedString, tab: DashboardTab) -> AttributedString {
    let plainText = String(content.characters)
    let containsInterpolationToken = plainText.contains("{") && plainText.contains(":")
    guard plainText.contains("#") || containsInterpolationToken else { return content }

    let mutable = NSMutableAttributedString(attributedString: NSAttributedString(content))
    let pattern = #"\{([^}]*:[^}]+)\}|#\{([^}]+)\}|#([A-Za-z0-9_]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }

    let fullRange = NSRange(location: 0, length: mutable.string.utf16.count)
    let matches = regex.matches(in: mutable.string, range: fullRange).reversed()
    for match in matches {
        guard match.numberOfRanges >= 4 else { continue }
        let nameRange: NSRange = {
            let consoleRange = match.range(at: 1)
            if consoleRange.location != NSNotFound { return consoleRange }

            let bracedRange = match.range(at: 2)
            if bracedRange.location != NSNotFound { return bracedRange }

            return match.range(at: 3)
        }()
        guard let swiftRange = Range(nameRange, in: mutable.string) else { continue }

        let rawName = String(mutable.string[swiftRange])
        guard let replacement = GraphRuntime.resolveTextInterpolationToken(rawName, tab: tab) else { continue }
        let attributes: [NSAttributedString.Key: Any] = {
            guard mutable.length > 0 else { return [:] }
            let location = min(max(match.range.location, 0), max(mutable.length - 1, 0))
            return mutable.attributes(at: location, effectiveRange: nil)
        }()

        let replacementString = NSAttributedString(string: replacement, attributes: attributes)
        mutable.replaceCharacters(in: match.range, with: replacementString)
    }

    return AttributedString(mutable)
}

struct TokenInsertMenuItem: Identifiable {
    let id: String
    let title: String
    let token: String
}

struct TokenInsertMenuGroup: Identifiable {
    let id: String
    let title: String
    let items: [TokenInsertMenuItem]
    let subgroups: [TokenInsertMenuGroup]

    init(id: String, title: String, items: [TokenInsertMenuItem], subgroups: [TokenInsertMenuGroup] = []) {
        self.id = id
        self.title = title
        self.items = items
        self.subgroups = subgroups
    }
}

struct TokenInsertMenuSection: Identifiable {
    let id: String
    let title: String
    let items: [TokenInsertMenuItem]
    let groups: [TokenInsertMenuGroup]
}

func tokenInsertMenuSections(
    variables: [String: String],
    devices: [ExternalDeviceConfig],
    shureChannelNameCache: [UUID: [Int: String]],
    sennheiserChannelNameCache: [UUID: [Int: String]]
) -> [TokenInsertMenuSection] {
    let completionItems = completionDevices(
        from: devices,
        shureChannelNameCache: shureChannelNameCache,
        sennheiserChannelNameCache: sennheiserChannelNameCache
    )

    let variableItems = variables.keys
        .sorted()
        .map { name in
            TokenInsertMenuItem(
                id: "var:\(name)",
                title: name,
                token: "#{\(name)}"
            )
        }

    // Build console groups. DiGiCo devices whose name contains " › " (e.g. "Q338 › Aux Outputs")
    // are channel-type sub-entries — nest them under the parent console as sub-groups so the
    // picker shows: Console > Inputs / Aux Outputs / Groups / Matrix / Control Groups.
    // Tokens are unchanged; only the menu display structure changes.
    let allConsoleDevices = completionItems.filter { $0.kindLabel == "Console" }

    struct ConsoleBucket {
        var inputItems: [TokenInsertMenuItem] = []
        var subgroups: [TokenInsertMenuGroup] = []
    }
    var consoleBuckets: [String: ConsoleBucket] = [:]
    var consoleOrder: [String] = []  // preserve sorted order from completionDevices

    for device in allConsoleDevices {
        func makeItems(for d: CompletionDevice) -> [TokenInsertMenuItem] {
            d.channels.map { ch in
                TokenInsertMenuItem(
                    id: "console:\(d.name):\(ch.number)",
                    title: "#\(ch.number) — \(ch.label)",
                    token: "{\(d.name):\(ch.number)}"
                )
            }
        }

        if let chevronRange = device.name.range(of: " › ") {
            let consoleName = String(device.name[..<chevronRange.lowerBound])
            let typeName    = String(device.name[chevronRange.upperBound...])
            if consoleBuckets[consoleName] == nil {
                consoleBuckets[consoleName] = ConsoleBucket()
                consoleOrder.append(consoleName)
            }
            consoleBuckets[consoleName]!.subgroups.append(
                TokenInsertMenuGroup(id: "console:\(device.name)", title: typeName,
                                     items: makeItems(for: device))
            )
        } else {
            if consoleBuckets[device.name] == nil {
                consoleBuckets[device.name] = ConsoleBucket()
                consoleOrder.append(device.name)
            }
            consoleBuckets[device.name]!.inputItems = makeItems(for: device)
        }
    }

    let consoleGroups: [TokenInsertMenuGroup] = consoleOrder.compactMap { name in
        guard var bucket = consoleBuckets[name] else { return nil }

        // If this console has channel-type sub-groups, also wrap the inputs into
        // an "Inputs" sub-group so all types appear at the same depth.
        if !bucket.subgroups.isEmpty && !bucket.inputItems.isEmpty {
            let inputSubgroup = TokenInsertMenuGroup(
                id: "console:\(name):inputs", title: "Inputs", items: bucket.inputItems)
            bucket.subgroups.insert(inputSubgroup, at: 0)
            return TokenInsertMenuGroup(id: "console:\(name)", title: name,
                                        items: [], subgroups: bucket.subgroups)
        }

        return TokenInsertMenuGroup(id: "console:\(name)", title: name,
                                    items: bucket.inputItems, subgroups: bucket.subgroups)
    }

    let wirelessGroups = completionItems
        .filter { $0.kindLabel == "Mic" }
        .map { device in
            TokenInsertMenuGroup(
                id: "mic:\(device.name)",
                title: device.name,
                items: device.channels.map { channel in
                    TokenInsertMenuItem(
                        id: "mic:\(device.name):\(channel.number)",
                        title: "#\(channel.number) — \(channel.label)",
                        token: "{\(device.name):\(channel.number)}"
                    )
                }
            )
        }

    return [
        TokenInsertMenuSection(
            id: "variables",
            title: "Variables",
            items: variableItems,
            groups: []
        ),
        TokenInsertMenuSection(
            id: "consoles",
            title: "Consoles",
            items: [],
            groups: consoleGroups
        ),
        TokenInsertMenuSection(
            id: "wireless",
            title: "Wireless",
            items: [],
            groups: wirelessGroups
        )
    ].filter { !$0.items.isEmpty || !$0.groups.isEmpty }
}

struct CompletionDevice {
    struct Channel {
        let number: Int
        let label: String
    }

    let name: String
    let kindLabel: String
    let channels: [Channel]
}

func completionDevices(
    from devices: [ExternalDeviceConfig],
    shureChannelNameCache: [UUID: [Int: String]],
    sennheiserChannelNameCache: [UUID: [Int: String]]
) -> [CompletionDevice] {
    // Use flatMap so DiGiCo can emit one CompletionDevice per channel type.
    // Each type gets its own name/namespace so their 1-based indices don't collide
    // in the token system (e.g. {Console:1} vs {Console — Aux Outputs:1}).
    devices.flatMap { device -> [CompletionDevice] in
        switch device.kind {
        case .audioConsole:
            if !device.digicoInputChannels.isEmpty || !device.digicoDiscoveredChannels.isEmpty {
                // DiGiCo: one CompletionDevice per channel type that has names.
                // Input channels keep the plain device.name so existing tokens are unchanged.
                // Non-input types append their type label to avoid index-space collisions.
                var result: [CompletionDevice] = []

                // Input channels
                if !device.digicoInputChannels.isEmpty {
                    let channels = device.digicoInputChannels
                        .sorted { $0.channel < $1.channel }
                        .map { ch -> CompletionDevice.Channel in
                            let label = ch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "CH \(ch.channel)" : ch.name
                            return .init(number: ch.channel, label: label)
                        }
                    result.append(CompletionDevice(name: device.name, kindLabel: "Console", channels: channels))
                }

                // Non-input channels — each type is its own CompletionDevice
                let grouped = Dictionary(grouping: device.digicoDiscoveredChannels, by: \.channelType)
                for channelType in DashboardGraph.DiGiCoChannelType.allCases where channelType != .inputChannel {
                    guard let typeChannels = grouped[channelType], !typeChannels.isEmpty else { continue }
                    let channels = typeChannels
                        .sorted { $0.index < $1.index }
                        .map { ch -> CompletionDevice.Channel in
                            let name = ch.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let label = name.isEmpty ? "CH \(ch.index)" : name
                            return .init(number: ch.index, label: label)
                        }
                    let typeName = "\(device.name) › \(channelType.displayName)s"
                    result.append(CompletionDevice(name: typeName, kindLabel: "Console", channels: channels))
                }

                return result
            } else if let count = consoleCompletionChannelCount(for: device) {
                let channels = (1...count).map { CompletionDevice.Channel(number: $0, label: "CH \($0)") }
                return [CompletionDevice(name: device.name, kindLabel: "Console", channels: channels)]
            }
            return []

        case .shureWireless:
            var names = shureChannelNameCache[device.id, default: [:]]
            for (channel, name) in device.shureChannelNames {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { names[channel] = trimmed }
            }
            if let name = device.psmChannel1Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                names[1] = name
            }
            if let name = device.psmChannel2Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                names[2] = name
            }
            let channelEntries = Array(names)
                .map { (number: $0.key, label: $0.value) }
                .sorted { $0.number < $1.number }
            let channels = channelEntries.map { CompletionDevice.Channel(number: $0.number, label: $0.label) }
            guard !channels.isEmpty else { return [] }
            return [CompletionDevice(name: device.name, kindLabel: "Mic", channels: channels)]

        case .sennheiserWireless:
            let names = sennheiserChannelNameCache[device.id, default: [:]]
            let channelEntries = Array(names)
                .map { (number: $0.key, label: $0.value) }
                .sorted { $0.number < $1.number }
            let channels = channelEntries.map { CompletionDevice.Channel(number: $0.number, label: $0.label) }
            guard !channels.isEmpty else { return [] }
            return [CompletionDevice(name: device.name, kindLabel: "Mic", channels: channels)]

        default:
            return []
        }
    }
    .sorted { lhs, rhs in
        if lhs.kindLabel == rhs.kindLabel {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.kindLabel == "Console"
    }
}

func consoleCompletionChannelCount(for device: ExternalDeviceConfig) -> Int? {
    let modelId = (device.consoleModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if modelId == "Behringer_X32" || modelId == "Midas_M32" || modelId.hasPrefix("AH_Qu") {
        return 32
    }
    guard let model = AudioConsoleModel.from(identifier: modelId) else { return nil }
    switch model {
    case .allenHeathDlive:
        return 128
    case .allenHeathAvantis, .allenHeathSq:
        return 64
    default:
        return nil
    }
}

#if os(macOS)
private func textInterpolationCandidates(
    query rawQuery: String,
    devices: [ExternalDeviceConfig],
    shureChannelNameCache: [UUID: [Int: String]],
    sennheiserChannelNameCache: [UUID: [Int: String]]
) -> [GraphRuntime.TextInterpolationCompletionCandidate] {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let allDevices = completionDevices(
        from: devices,
        shureChannelNameCache: shureChannelNameCache,
        sennheiserChannelNameCache: sennheiserChannelNameCache
    )

    if query.isEmpty || !query.contains(":") {
        let normalized = query.lowercased()
        return allDevices
            .filter { normalized.isEmpty || $0.name.lowercased().hasPrefix(normalized) }
            .map {
                GraphRuntime.TextInterpolationCompletionCandidate(
                    display: "\($0.name) — \($0.kindLabel)",
                    replacement: "{\($0.name):"
                )
            }
    }

    guard let separatorIndex = query.lastIndex(of: ":") else { return [] }
    let deviceName = String(query[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    let channelQuery = String(query[query.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let device = allDevices.first(where: { $0.name.caseInsensitiveCompare(deviceName) == .orderedSame }) else {
        return []
    }

    return device.channels.compactMap { channel in
        let channelString = String(channel.number)
        if !channelQuery.isEmpty && !channelString.hasPrefix(channelQuery) {
            return nil
        }
        return GraphRuntime.TextInterpolationCompletionCandidate(
            display: "#\(channel.number) — \(channel.label)",
            replacement: "{\(device.name):\(channel.number)}"
        )
    }
}
#endif
