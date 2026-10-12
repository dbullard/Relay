import SwiftUI
import WebKit

struct PCOLiveWebView: View {
    let url: URL
    var scrollInputEnabled: Bool = true
    var onFailure: ((URL) -> Void)? = nil

    var body: some View {
        WebViewRepresentable(url: url, scrollInputEnabled: scrollInputEnabled, onFailure: onFailure)
            .compositingGroup()
    }
}

#if os(macOS)
private struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    let scrollInputEnabled: Bool
    var onFailure: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = CanvasFriendlyWKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.scrollInputEnabled = scrollInputEnabled
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let webView = nsView as? CanvasFriendlyWKWebView {
            webView.scrollInputEnabled = scrollInputEnabled
        }
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            nsView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject {
        var lastURL: URL?
        var lastFailedURL: URL?
        let onFailure: ((URL) -> Void)?

        init(onFailure: ((URL) -> Void)?) {
            self.onFailure = onFailure
        }
    }
}

extension WebViewRepresentable.Coordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        notifyFailure(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        notifyFailure(for: webView.url)
    }

    private func notifyFailure(for url: URL?) {
        guard let url else { return }
        if lastFailedURL == url { return }
        lastFailedURL = url
        onFailure?(url)
    }
}

private final class CanvasFriendlyWKWebView: WKWebView {
    var scrollInputEnabled: Bool = true

    override func scrollWheel(with event: NSEvent) {
        guard scrollInputEnabled else { return }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        guard scrollInputEnabled else { return }
        super.magnify(with: event)
    }
}
#else
private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    let scrollInputEnabled: Bool
    var onFailure: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.isScrollEnabled = scrollInputEnabled
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.scrollView.isScrollEnabled = scrollInputEnabled
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            uiView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject {
        var lastURL: URL?
        var lastFailedURL: URL?
        let onFailure: ((URL) -> Void)?

        init(onFailure: ((URL) -> Void)?) {
            self.onFailure = onFailure
        }
    }
}

extension WebViewRepresentable.Coordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        notifyFailure(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        notifyFailure(for: webView.url)
    }

    private func notifyFailure(for url: URL?) {
        guard let url else { return }
        if lastFailedURL == url { return }
        lastFailedURL = url
        onFailure?(url)
    }
}
#endif
