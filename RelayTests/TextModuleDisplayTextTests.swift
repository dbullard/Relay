#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import Relay

/// A new Text tile's body was invisible on macOS until its first edit: the default text
/// carries SwiftUI attributes, which the AppKit tile renderer dropped, so it drew black on
/// a black tile. These pin the conversion the tile renderer uses.
final class TextModuleDisplayTextTests: XCTestCase {
    private func attributes(of string: NSAttributedString) -> [NSAttributedString.Key: Any] {
        string.attributes(at: 0, effectiveRange: nil)
    }

    func testDefaultModuleTextIsWhiteSystemSixteen() {
        // Same construction as the module catalog's "New text module".
        var text = AttributedString("New text module")
        text.foregroundColor = .white
        text.font = .system(size: 16)

        let converted = TextModuleDisplayText.attributedString(for: text)
        let attrs = attributes(of: converted)

        let color = (attrs[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.whiteComponentIfGray ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual((attrs[.font] as? NSFont)?.pointSize, 16)
    }

    func testUnstyledTextLoadedFromDiskGetsVisibleDefaults() {
        // Saved content loses SwiftUI attributes, so it reloads with none at all.
        let converted = TextModuleDisplayText.attributedString(for: AttributedString("Reloaded"))
        let attrs = attributes(of: converted)

        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, TextModuleDisplayText.defaultColor)
        XCTAssertEqual((attrs[.font] as? NSFont)?.pointSize, TextModuleDisplayText.defaultFontSize)
    }

    func testEditorStylingIsKept() {
        var text = AttributedString("Styled")
        text.appKit.foregroundColor = .systemRed
        text.appKit.font = NSFont.boldSystemFont(ofSize: 30)

        let attrs = attributes(of: TextModuleDisplayText.attributedString(for: text))

        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, .systemRed)
        XCTAssertEqual((attrs[.font] as? NSFont)?.pointSize, 30)
    }

    func testEmptyContentStaysEmpty() {
        XCTAssertEqual(TextModuleDisplayText.attributedString(for: AttributedString("")).length, 0)
    }
}

private extension NSColor {
    /// Average of the RGB components, enough to tell white from black.
    var whiteComponentIfGray: CGFloat {
        (redComponent + greenComponent + blueComponent) / 3
    }
}
#endif
