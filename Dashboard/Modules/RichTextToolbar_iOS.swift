//
//  RichTextToolbar_iOS.swift
//  Relay
//

#if os(iOS)
import Combine
import SwiftUI
import UIKit

// MARK: - Shared formatting state

/// Shared observable state that bridges RichTextEditor_iOS (UIKit) and
/// RichTextToolbar_iOS (SwiftUI).  The editor holds a weak reference to the
/// UITextView and surfaces it here; the toolbar reads/writes through this
/// object so no Binding<UITextView?> races with the async rendering cycle.
@MainActor
final class RichTextToolbarState: ObservableObject {
    // Weak ref to the live UITextView — set synchronously in makeUIView.
    weak var textView: UITextView?

    // Formatting state observed by the toolbar.
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false
    @Published var alignment: TextAlignment = .leading
    @Published var fontSize: CGFloat = 17
    @Published var fontFamily: String = "System"
    @Published var textColor: Color = .primary

    /// Called by the coordinator after any mutation that touches `tv.attributedText`
    /// programmatically (i.e. programmatic changes that don't fire textViewDidChange).
    /// The coordinator implementation syncs the SwiftUI binding and then persists.
    /// Toggle actions (bold/italic/underline) go through UITextView's responder chain
    /// and DO fire textViewDidChange, so they don't need this handler.
    var onFormattingChanged: (() -> Void)?

    // MARK: - Sync from cursor / content

    /// Reads toolbar state from the text view's current typing attributes (reflects
    /// cursor position after user taps into the view).
    func syncFromCursor() {
        guard let tv = textView else { return }
        let attrs = tv.typingAttributes
        if let font = attrs[.font] as? UIFont {
            isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            fontSize = font.pointSize
            fontFamily = font.familyName == ".AppleSystemUIFont" ? "System" : font.familyName
        }
        isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        let para = attrs[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle()
        switch para.alignment {
        case .left, .natural: alignment = .leading
        case .center: alignment = .center
        case .right: alignment = .trailing
        default: alignment = .leading
        }
        if let uiColor = attrs[.foregroundColor] as? UIColor {
            textColor = Color(uiColor)
        }
    }

    /// Seeds toolbar state on first load from the stored attributed content.
    /// Reads from character 0 of `attributedText` for font/alignment; if the stored
    /// content carries no explicit attributes (brand-new module), falls through to
    /// `typingAttributes` which already reflects our forced defaults (white text, etc.).
    /// Color always comes from `typingAttributes` to avoid showing adaptive colors
    /// (e.g. UIColor.label resolves to black in some trait contexts even on dark tiles).
    func syncFromContent(
        _ attributedText: AttributedString,
        typingAttributes: [NSAttributedString.Key: Any]
    ) {
        let ns = NSAttributedString(attributedText)

        // Font / bold / italic / underline / alignment — prefer stored content,
        // fall back to typing defaults when no explicit attributes are saved.
        let sourceAttrs: [NSAttributedString.Key: Any]
        if ns.length > 0 {
            let stored = ns.attributes(at: 0, effectiveRange: nil)
            sourceAttrs = stored.isEmpty ? typingAttributes : stored
        } else {
            sourceAttrs = typingAttributes
        }

        if let font = sourceAttrs[.font] as? UIFont {
            isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            fontSize = font.pointSize
            let family = font.familyName
            fontFamily = family == ".AppleSystemUIFont" ? "System" : family
        }
        isUnderline = (sourceAttrs[.underlineStyle] as? Int ?? 0) != 0
        if let para = sourceAttrs[.paragraphStyle] as? NSParagraphStyle {
            switch para.alignment {
            case .center: alignment = .center
            case .right: alignment = .trailing
            default: alignment = .leading
            }
        }

        // Color: always use typingAttributes (which we force to white in makeUIView).
        // Stored colors may be UIColor.label (adaptive) and would resolve to black
        // in the trait collection of the settings sheet, misleading the color picker.
        if let uiColor = typingAttributes[.foregroundColor] as? UIColor {
            textColor = Color(uiColor)
        } else if let uiColor = sourceAttrs[.foregroundColor] as? UIColor {
            textColor = Color(uiColor)
        }
    }

    // MARK: - Formatting actions

    func toggleBold() {
        guard let tv = textView else { return }
        tv.toggleBoldface(nil)
        isBold.toggle()
        // textViewDidChange fires via UITextView's responder chain — no need to call onFormattingChanged.
    }

    func toggleItalic() {
        guard let tv = textView else { return }
        tv.toggleItalics(nil)
        isItalic.toggle()
        // textViewDidChange fires via UITextView's responder chain — no need to call onFormattingChanged.
    }

    func toggleUnderline() {
        guard let tv = textView else { return }
        tv.toggleUnderline(nil)
        isUnderline.toggle()
        // textViewDidChange fires via UITextView's responder chain — no need to call onFormattingChanged.
    }

    func applyAlignment(_ nsAlignment: NSTextAlignment) {
        guard let tv = textView else { return }
        let para = NSMutableParagraphStyle()
        para.alignment = nsAlignment
        let range = tv.selectedRange.length > 0
            ? tv.selectedRange
            : NSRange(location: 0, length: tv.attributedText.length)
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.addAttribute(.paragraphStyle, value: para, range: range)
        alignment = nsAlignment == .left ? .leading : (nsAlignment == .center ? .center : .trailing)
        setAttributedTextPreservingSelection(tv, attributedText: mutable, actionName: "Alignment")
        onFormattingChanged?()
    }

    func applyFontSize(_ size: CGFloat) {
        guard let tv = textView else { return }
        fontSize = size
        var attrs = tv.typingAttributes
        if let currentFont = attrs[.font] as? UIFont {
            attrs[.font] = currentFont.withSize(size)
        } else {
            attrs[.font] = UIFont.systemFont(ofSize: size)
        }
        tv.typingAttributes = attrs
        if tv.selectedRange.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            mutable.enumerateAttribute(.font, in: tv.selectedRange) { value, range, _ in
                let existingFont = (value as? UIFont) ?? UIFont.systemFont(ofSize: size)
                mutable.addAttribute(.font, value: existingFont.withSize(size), range: range)
            }
            setAttributedTextPreservingSelection(tv, attributedText: mutable, actionName: "Font Size")
        }
        onFormattingChanged?()
    }

    func applyFontFamily(_ name: String) {
        guard let tv = textView else { return }
        fontFamily = name
        var attrs = tv.typingAttributes
        let currentFont = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: fontSize)
        let newFont: UIFont
        if name == "System" {
            newFont = UIFont.systemFont(ofSize: currentFont.pointSize)
        } else {
            // UIFont(name:) needs a PostScript name, not a family display name.
            // Try the display name first (works for some fonts), then fall back
            // to enumerating the family's actual PostScript names and picking the
            // "Regular" variant (or the first available).
            if let f = UIFont(name: name, size: currentFont.pointSize) {
                newFont = f
            } else {
                let psNames = UIFont.fontNames(forFamilyName: name)
                let regular = psNames.first { n in
                    let lower = n.lowercased()
                    return lower.hasSuffix("-regular") || lower == name.lowercased()
                } ?? psNames.first
                guard let psName = regular, let f = UIFont(name: psName, size: currentFont.pointSize) else {
                    return
                }
                newFont = f
            }
        }
        attrs[.font] = newFont
        tv.typingAttributes = attrs
        // Also apply to any currently selected text range.
        if tv.selectedRange.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            mutable.enumerateAttribute(.font, in: tv.selectedRange) { value, range, _ in
                let existingFont = (value as? UIFont) ?? currentFont
                // Preserve the existing point size within the selection.
                if let sized = UIFont(name: newFont.fontName, size: existingFont.pointSize) {
                    mutable.addAttribute(.font, value: sized, range: range)
                } else {
                    mutable.addAttribute(.font, value: newFont, range: range)
                }
            }
            setAttributedTextPreservingSelection(tv, attributedText: mutable, actionName: "Font")
        }
        onFormattingChanged?()
    }

    func applyTextColor(_ color: Color) {
        guard let tv = textView else { return }
        let uiColor = UIColor(color)
        var attrs = tv.typingAttributes
        attrs[.foregroundColor] = uiColor
        tv.typingAttributes = attrs
        if tv.selectedRange.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            mutable.addAttribute(.foregroundColor, value: uiColor, range: tv.selectedRange)
            setAttributedTextPreservingSelection(tv, attributedText: mutable, actionName: "Text Color")
        }
        onFormattingChanged?()
    }

    func insertToken(_ token: String) {
        guard let tv = textView else { return }
        let replacement = NSAttributedString(string: token, attributes: tv.typingAttributes)
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        let insertRange = tv.selectedRange
        mutable.replaceCharacters(in: insertRange, with: replacement)
        // Place cursor after the inserted token
        let newCursor = insertRange.location + replacement.length
        replaceAttributedText(
            tv,
            with: mutable,
            selection: NSRange(location: newCursor, length: 0),
            actionName: "Insert Variable"
        )
        onFormattingChanged?()
    }

    // MARK: - Private helpers

    /// Replaces the text view's attributed text while preserving the current
    /// selected range (setting attributedText resets selection to end-of-text).
    private func setAttributedTextPreservingSelection(
        _ tv: UITextView,
        attributedText: NSMutableAttributedString,
        actionName: String
    ) {
        replaceAttributedText(tv, with: attributedText, selection: tv.selectedRange, actionName: actionName)
    }

    /// Sets `attributedText` and registers an undo step that puts the previous text and
    /// selection back. Programmatic `attributedText` writes bypass UITextView's own undo,
    /// so without this the toolbar's edits couldn't be undone with ⌘Z or shake.
    private func replaceAttributedText(
        _ tv: UITextView,
        with attributedText: NSAttributedString,
        selection: NSRange,
        actionName: String
    ) {
        let previousText = NSAttributedString(attributedString: tv.attributedText ?? NSAttributedString())
        let previousSelection = tv.selectedRange
        tv.attributedText = attributedText
        let newLength = tv.attributedText.length
        let loc = min(selection.location, newLength)
        let len = min(selection.length, newLength - loc)
        tv.selectedRange = NSRange(location: loc, length: len)

        guard let undoManager = tv.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [weak tv] state in
            guard let tv else { return }
            state.replaceAttributedText(tv, with: previousText, selection: previousSelection, actionName: actionName)
            state.syncFromCursor()
            state.onFormattingChanged?()
        }
        undoManager.setActionName(actionName)
    }

    func dismissKeyboard() {
        textView?.resignFirstResponder()
    }
}

// MARK: - Toolbar view

/// Formatting toolbar that lives as the UITextView's inputAccessoryView so it
/// stays pinned above the keyboard while the user is editing.
struct RichTextToolbar_iOS: View {
    @ObservedObject var formattingState: RichTextToolbarState
    let tokenSections: [TokenInsertMenuSection]

    // Family names as recognised by UIFont.fontNames(forFamilyName:).
    // "Helvetica Neue" and "Times New Roman" are the correct iOS family names;
    // "Menlo" and "Courier New" are also valid family names on iOS.
    private let availableFonts = [
        "System", "Menlo", "Georgia", "Helvetica Neue", "Times New Roman", "Courier New"
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                // Bold
                toolbarButton("Bold", systemImage: "bold", isActive: formattingState.isBold) {
                    formattingState.toggleBold()
                }

                // Italic
                toolbarButton("Italic", systemImage: "italic", isActive: formattingState.isItalic) {
                    formattingState.toggleItalic()
                }

                // Underline
                toolbarButton("Underline", systemImage: "underline", isActive: formattingState.isUnderline) {
                    formattingState.toggleUnderline()
                }

                Divider().frame(height: 24)

                // Alignment
                toolbarButton(
                    "Align Left",
                    systemImage: "text.alignleft",
                    isActive: formattingState.alignment == .leading
                ) {
                    formattingState.applyAlignment(.left)
                }
                toolbarButton(
                    "Align Center",
                    systemImage: "text.aligncenter",
                    isActive: formattingState.alignment == .center
                ) {
                    formattingState.applyAlignment(.center)
                }
                toolbarButton(
                    "Align Right",
                    systemImage: "text.alignright",
                    isActive: formattingState.alignment == .trailing
                ) {
                    formattingState.applyAlignment(.right)
                }

                Divider().frame(height: 24)

                // Font size
                HStack(spacing: 0) {
                    Button {
                        formattingState.applyFontSize(max(8, formattingState.fontSize - 1))
                    } label: {
                        Label("Decrease Font Size", systemImage: "minus")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: Self.hitTarget, minHeight: Self.hitTarget)
                            .contentShape(.rect)
                    }
                    Text("\(Int(formattingState.fontSize))")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 24)
                        .accessibilityLabel("Font size \(Int(formattingState.fontSize))")
                    Button {
                        formattingState.applyFontSize(min(72, formattingState.fontSize + 1))
                    } label: {
                        Label("Increase Font Size", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: Self.hitTarget, minHeight: Self.hitTarget)
                            .contentShape(.rect)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Divider().frame(height: 24)

                // Font family
                Menu {
                    ForEach(availableFonts, id: \.self) { name in
                        Button(name) { formattingState.applyFontFamily(name) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formattingState.fontFamily == "System"
                             ? "Font"
                             : formattingState.fontFamily)
                            .font(.caption)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .frame(minHeight: Self.hitTarget)
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("Font")
                .accessibilityValue(formattingState.fontFamily)

                Divider().frame(height: 24)

                // Text color
                ColorPicker("Text Color", selection: Binding(
                    get: { formattingState.textColor },
                    set: { formattingState.applyTextColor($0) }
                ), supportsOpacity: true)
                .labelsHidden()
                .frame(minWidth: Self.hitTarget, minHeight: Self.hitTarget)

                // Variable insert — always show so users can see what's available
                Divider().frame(height: 24)
                tokenInsertMenu

                // Done button — pins to trailing end via Spacer
                Spacer()
                Button("Done") { formattingState.dismissKeyboard() }
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: Self.hitTarget)
                    .contentShape(.rect)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        // `axes:` defaults to `.vertical`; explicit here since this is a
        // `ScrollView(.horizontal)`.
        .scrollIndicators(.hidden, axes: .horizontal)
        .background(Color(UIColor.secondarySystemBackground))
    }

    @ViewBuilder
    private var tokenInsertMenu: some View {
        Menu {
            if tokenSections.isEmpty {
                Text("No variables available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tokenSections) { section in
                    if !section.items.isEmpty {
                        Section(section.title) {
                            ForEach(section.items) { item in
                                Button(item.title) { formattingState.insertToken(item.token) }
                            }
                        }
                    }
                    ForEach(section.groups) { group in
                        Menu(group.title) {
                            ForEach(group.subgroups) { subgroup in
                                Menu(subgroup.title) {
                                    ForEach(subgroup.items) { item in
                                        Button(item.title) { formattingState.insertToken(item.token) }
                                    }
                                }
                            }
                            ForEach(group.items) { item in
                                Button(item.title) { formattingState.insertToken(item.token) }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "curlybraces")
                Text("Insert").font(.caption)
            }
            .frame(height: 36)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
            )
            .frame(minHeight: Self.hitTarget)
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Insert Variable")
    }

    private static let hitTarget: CGFloat = 44

    @ViewBuilder
    private func toolbarButton(
        _ title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .fontWeight(isActive ? .bold : .regular)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
                .background(
                    // Active = solid fill, not just a tint change.
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor : Color.clear)
                )
                .frame(minWidth: Self.hitTarget, minHeight: Self.hitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
#endif
