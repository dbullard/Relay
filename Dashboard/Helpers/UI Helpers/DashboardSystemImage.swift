import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum DashboardSystemImage {
    static func name(_ preferred: String, fallback explicitFallback: String? = nil) -> String {
        let fallback = explicitFallback ?? fallbackName(for: preferred)

        if symbolExists(preferred) {
            return preferred
        }

        if symbolExists(fallback) {
            return fallback
        }

        return "circle"
    }

    private static func fallbackName(for preferred: String) -> String {
        symbolFallbacks[preferred] ?? "circle"
    }

    private static func symbolExists(_ name: String) -> Bool {
        #if os(macOS)
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        } else {
            return false
        }
        #elseif canImport(UIKit)
        if #available(iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
            return UIImage(systemName: name) != nil
        } else {
            return false
        }
        #else
        return true
        #endif
    }

    private static let symbolFallbacks: [String: String] = [
        "arrow.triangle.branch": "arrow.branch",
        "arrow.up.and.down.and.arrow.left.and.right": "arrow.up.and.down",
        "button.programmable": "circle",
        "cursorarrow.and.square.on.square.dashed": "cursorarrow",
        "doc.badge.plus": "doc",
        "doc.richtext": "doc.text",
        "externaldrive.connected.to.line.below": "externaldrive",
        "line.horizontal.3": "minus",
        "link.icloud.fill": "link",
        "lines.measurement.horizontal": "ruler",
        "lines.measurement.vertical": "ruler",
        "link.badge.plus": "link",
        "list.bullet.below.rectangle": "list.bullet.rectangle",
        "list.bullet.rectangle.portrait": "list.bullet.rectangle",
        "list.dash.badge.ellipsis": "list.bullet",
        "person.2.crop.square.stack": "person.2",
        "person.2.crop.square.stack.fill": "person.2.fill",
        "person.crop.square": "person.crop.circle",
        "play.tv": "play.rectangle",
        "point.3.connected.trianglepath.dotted": "network",
        "rectangle.3.group": "rectangle.stack",
        "sidebar.leading": "sidebar.left",
        "sidebar.trailing": "sidebar.right",
        "slider.horizontal.below.rectangle": "slider.horizontal.3",
        "sparkles.tv": "sparkles",
        "square.and.arrow.down.on.square": "square.and.arrow.down",
        "square.grid.2x2": "grid",
        "square.grid.3x3": "grid",
        "text.bubble.fill": "text.bubble",
        "wrench.and.screwdriver": "wrench"
    ]
}

struct DashboardSymbolImage: View {
    let preferred: String
    let fallback: String?

    init(_ preferred: String, fallback: String? = nil) {
        self.preferred = preferred
        self.fallback = fallback
    }

    var body: some View {
        Image(systemName: DashboardSystemImage.name(preferred, fallback: fallback))
    }
}

struct DashboardSymbolLabel: View {
    let title: String
    let preferred: String
    let fallback: String?

    init(_ title: String, preferred: String, fallback: String? = nil) {
        self.title = title
        self.preferred = preferred
        self.fallback = fallback
    }

    var body: some View {
        Label(title, systemImage: DashboardSystemImage.name(preferred, fallback: fallback))
    }
}

extension View {
    @ViewBuilder
    func dashboardLinkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }
}
