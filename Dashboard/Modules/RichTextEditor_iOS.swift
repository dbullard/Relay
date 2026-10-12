//
//  RichTextEditor_iOS.swift
//  Relay
//

#if os(iOS)
import SwiftUI
import UIKit

struct RichTextEditor_iOS: UIViewRepresentable {
    @Binding var attributedText: AttributedString
    let formattingState: RichTextToolbarState
    let tokenSections: [TokenInsertMenuSection]
    let onPersist: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.allowsEditingTextAttributes = true
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.delegate = context.coordinator
        textView.isScrollEnabled = true

        // Wire formatting state to this text view synchronously
        formattingState.textView = textView

        // Text module tiles always appear on a dark background, so white is
        // the correct default.  Do NOT read UIColor.label from stored attributes
        // here — .label is adaptive and resolves to black in certain trait
        // collection contexts (e.g. inside a UIHostingController), which would
        // make the text invisible against a dark tile.
        textView.textColor = .white

        // Seed typingAttributes so newly typed text inherits white.
        var defaultAttrs = textView.typingAttributes
        defaultAttrs[.foregroundColor] = UIColor.white
        textView.typingAttributes = defaultAttrs

        // Build the toolbar hosted in a UIHostingController and attach it as inputAccessoryView
        let toolbar = RichTextToolbar_iOS(
            formattingState: formattingState,
            tokenSections: tokenSections
        )
        let hostingController = UIHostingController(rootView: toolbar)
        hostingController.view.backgroundColor = .clear

        // Size the accessory view to a fixed height; width is handled by the system
        let accessoryContainer = UIView()
        accessoryContainer.backgroundColor = .clear
        accessoryContainer.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        accessoryContainer.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: accessoryContainer.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: accessoryContainer.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: accessoryContainer.bottomAnchor),
        ])
        accessoryContainer.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        textView.inputAccessoryView = accessoryContainer

        context.coordinator.inputAccessoryHostingController = hostingController

        // Set initial content
        textView.attributedText = NSAttributedString(attributedText)

        // Seed the toolbar immediately from the stored content so it shows the correct
        // font/size/alignment on first open — no user tap required.  typingAttributes
        // is passed as the fallback for text with no explicit stored attributes.
        formattingState.syncFromContent(attributedText, typingAttributes: textView.typingAttributes)

        // Wire onFormattingChanged so programmatic changes to tv.attributedText (alignment,
        // font family, font size, text color, token insert) sync the SwiftUI binding and
        // persist immediately — they don't fire textViewDidChange so the delegate alone
        // isn't sufficient.
        context.coordinator.wireFormattingChanged()

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Keep the toolbar's token sections fresh (e.g. variables change)
        context.coordinator.inputAccessoryHostingController?.rootView = RichTextToolbar_iOS(
            formattingState: formattingState,
            tokenSections: tokenSections
        )

        // Only update content from outside if the coordinator is not currently editing
        guard !context.coordinator.isEditing else { return }
        let incoming = NSAttributedString(attributedText)
        if textView.attributedText != incoming {
            textView.attributedText = incoming
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor_iOS
        var isEditing = false
        var inputAccessoryHostingController: UIHostingController<RichTextToolbar_iOS>?

        init(parent: RichTextEditor_iOS) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            parent.formattingState.syncFromCursor()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.formattingState.syncFromCursor()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            syncToBinding(textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            syncToBinding(textView)
        }

        /// Called once from makeUIView to close the loop for programmatic attributedText
        /// mutations (alignment, font, color, token insert) that bypass textViewDidChange.
        func wireFormattingChanged() {
            parent.formattingState.onFormattingChanged = { [weak self] in
                guard let self, let tv = self.parent.formattingState.textView else { return }
                self.syncToBinding(tv)
            }
        }

        func syncToBinding(_ textView: UITextView) {
            let nsAttr = textView.attributedText ?? NSAttributedString()
            if let converted = try? AttributedString(nsAttr, including: \.uiKit) {
                parent.attributedText = converted
            } else {
                // Fallback: preserve text, drop attributes
                parent.attributedText = AttributedString(nsAttr.string)
            }
            parent.onPersist()
        }
    }
}
#endif
