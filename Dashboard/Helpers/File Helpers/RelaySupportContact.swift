import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum RelaySupportContact {
    static let supportEmail = "support@ondeckapps.com"
    static let helpCenterURL = URL(string: "https://github.com/dbullard/Relay")!

    @MainActor
    static func openSupportEmail(context: String? = nil) {
        let diagnostics = RelayDiagnosticsStore.shared.diagnosticSummary()
        guard let url = supportEmailURL(context: context, diagnosticSummary: diagnostics) else { return }
        openURL(url)
    }

    static func openHelpCenter() {
        openURL(helpCenterURL)
    }

    nonisolated static func supportEmailURL(context: String?, diagnosticSummary: String) -> URL? {
        let body: String
        if let context, !context.isEmpty {
            body = "\(context)\n\n\(diagnosticSummary)"
        } else {
            body = diagnosticSummary
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Relay Support Request"),
            URLQueryItem(name: "body", value: body)
        ]

        return components.url
    }

    private static func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}
