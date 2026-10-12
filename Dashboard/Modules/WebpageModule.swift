//
//  WebpageModule.swift
//  Relay
//
//  Created by Codex on 4/17/26.
//

import SwiftUI
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct WebpageModuleView: View {
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    @Environment(\.dashboardIsWebpageViewportBypassActive) private var isWebpageViewportBypassActive
    @Environment(\.dashboardSetWebpageViewportBypass) private var setWebpageViewportBypass
    @Binding var model: WebpageModuleModel
    let isLiveMode: Bool

    var body: some View {
        let interactionEnabled = !isLiveMode || model.allowInteractionInLiveMode

        VStack(spacing: 0) {
            if !isLiveMode && !isLANSnapshotRendering {
                WebpageModuleToolbar(
                    model: $model,
                    webInteractionModeEnabled: isWebpageViewportBypassActive
                )
            }

            Group {
                if model.trimmedURLString.isEmpty {
                    WebpageModulePlaceholder(
                        systemImage: "globe",
                        title: "No webpage URL",
                        message: "Open module settings and add a URL."
                    )
                } else if model.normalizedURL == nil {
                    WebpageModulePlaceholder(
                        systemImage: "exclamationmark.triangle",
                        title: "Invalid URL",
                        message: "Use an http or https webpage address."
                    )
                } else if isLANSnapshotRendering {
                    WebpageSnapshotFallback(model: model)
                } else {
                    WebpageWebViewContainer(
                        model: $model,
                        showsToolbar: !isLiveMode,
                        interactionEnabled: interactionEnabled,
                        webInteractionModeEnabled: isWebpageViewportBypassActive
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            if isWebpageViewportBypassActive {
                setWebpageViewportBypass(model.id, false)
            }
        }
    }
}

private struct WebpageSnapshotFallback: View {
    let model: WebpageModuleModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(snapshotTitle)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(snapshotSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let url = model.normalizedURL {
                Text(url.absoluteString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snapshotTitle: String {
        if let url = model.normalizedURL {
            return url.host(percentEncoded: false) ?? "Webpage"
        }
        return "Webpage"
    }

    private var snapshotSubtitle: String {
        "Live webpage content is not captured in LAN/browser snapshots."
    }
}

private struct WebpageModuleToolbar: View {
    @Environment(\.dashboardSetWebpageViewportBypass) private var setWebpageViewportBypass
    @Binding var model: WebpageModuleModel
    let webInteractionModeEnabled: Bool

    @State private var canGoBack = false
    @State private var canGoForward = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .webpageModuleGoBack, object: model.id)
            } label: {
                Image(systemName: "chevron.backward")
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .disabled(!canGoBack)

            Button {
                NotificationCenter.default.post(name: .webpageModuleGoForward, object: model.id)
            } label: {
                Image(systemName: "chevron.forward")
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .disabled(!canGoForward)

            Button {
                NotificationCenter.default.post(name: .webpageModuleReload, object: model.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)

            Button {
                setWebpageViewportBypass(model.id, !webInteractionModeEnabled)
            } label: {
                Image(systemName: webInteractionModeEnabled ? "hand.draw.fill" : "hand.draw")
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .foregroundStyle(webInteractionModeEnabled ? Color.red : .primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(webInteractionModeEnabled ? Color.red.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(webInteractionModeEnabled ? Color.red.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .help(
                webInteractionModeEnabled
                    ? "Disable webpage gesture mode"
                    : "Enable webpage gesture mode so scroll, pinch, and trackpad gestures stay inside the webpage"
            )

            Spacer(minLength: 0)

            Button {
                guard let url = model.normalizedURL else { return }
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .disabled(model.normalizedURL == nil)
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .onReceive(NotificationCenter.default.publisher(for: .webpageModuleNavigationStateChanged)) { note in
            guard let payload = note.object as? WebpageNavigationState,
                  payload.moduleID == model.id else {
                return
            }
            canGoBack = payload.canGoBack
            canGoForward = payload.canGoForward
        }
    }
}

private struct WebpageModulePlaceholder: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WebpageModuleSettingsView: View {
    @Binding var model: WebpageModuleModel
    let onPersist: () -> Void

    @StateObject private var favoritesStore = WebpageFavoritesStore.shared
    @State private var favoritesExpanded = false
    @State private var urlInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Webpage")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("https://example.com", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        urlInput = model.urlString
                    }
                    .onChange(of: model.urlString, initial: false) { _, newValue in
                        if urlInput != newValue {
                            urlInput = newValue
                        }
                    }
                    .onChange(of: urlInput, initial: false) { _, newValue in
                        model.urlString = newValue
                        onPersist()
                    }

                Button {
                    toggleCurrentFavorite()
                } label: {
                    Image(systemName: currentURLIsFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .help(currentURLIsFavorite ? "Remove URL from favorites" : "Save URL as favorite")
                .disabled(model.normalizedURL == nil)
            }

            if !model.trimmedURLString.isEmpty && model.normalizedURL == nil {
                Text("Enter a valid http or https URL.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            DisclosureGroup(isExpanded: $favoritesExpanded) {
                if favoritesStore.favorites.isEmpty {
                    Text("No saved favorites")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(favoritesStore.favorites) { favorite in
                            HStack(spacing: 8) {
                                Button {
                                    applyFavorite(favorite)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(favorite.title)
                                            .foregroundStyle(.primary)
                                        Text(favorite.trimmedURLString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    favoritesStore.removeFavorite(id: favorite.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } label: {
                Label("Favorites", systemImage: "star")
            }

            HStack {
                Text("Auto-refresh")
                Spacer()
                Toggle(
                    "Auto-refresh",
                    isOn: Binding(
                        get: { model.effectiveRefreshIntervalSeconds != nil },
                        set: { isEnabled in
                            model.refreshIntervalSeconds = isEnabled
                                ? max(model.clampedRefreshIntervalSeconds, 60)
                                : 0
                            onPersist()
                        }
                    )
                )
                .labelsHidden()
            }

            if model.effectiveRefreshIntervalSeconds != nil {
                HStack {
                    Text("Refresh every")
                    Spacer()
                    Stepper(value: refreshBinding, in: 15...3600, step: 15) {
                        Text("\(Int(model.clampedRefreshIntervalSeconds)) sec")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Picker("Session", selection: Binding(
                get: { model.sessionMode },
                set: { newValue in
                    model.sessionMode = newValue
                    onPersist()
                }
            )) {
                ForEach(WebpageModuleModel.SessionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Picker("Render mode", selection: Binding(
                get: { model.renderMode },
                set: { newValue in
                    model.renderMode = newValue
                    onPersist()
                }
            )) {
                ForEach(WebpageModuleModel.RenderMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Toggle("Allow interaction in Live mode", isOn: Binding(
                get: { model.allowInteractionInLiveMode },
                set: { newValue in
                    model.allowInteractionInLiveMode = newValue
                    onPersist()
                }
            ))

            if model.sessionMode == .rememberLogin {
                Button("Clear saved website session") {
                    WebpageSessionStore.clearPersistentSession(for: model.id)
                    NotificationCenter.default.post(name: .webpageModuleResetSession, object: model.id)
                }
                .buttonStyle(.borderless)
            }

            Text("Back, forward, reload, and open externally are available only while editing the module.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var refreshBinding: Binding<Double> {
        Binding(
            get: { model.clampedRefreshIntervalSeconds },
            set: { newValue in
                model.refreshIntervalSeconds = min(max(newValue, 15), 3600)
                onPersist()
            }
        )
    }

    private var currentURLIsFavorite: Bool {
        favoritesStore.contains(urlString: model.trimmedURLString)
    }

    private func toggleCurrentFavorite() {
        guard let url = model.normalizedURL else { return }

        if currentURLIsFavorite {
            favoritesStore.removeFavorite(urlString: url.absoluteString)
            return
        }

        favoritesStore.addFavorite(
            title: url.host(percentEncoded: false) ?? "",
            urlString: url.absoluteString
        )
    }

    private func applyFavorite(_ favorite: WebpageFavorite) {
        urlInput = favorite.trimmedURLString
        model.urlString = favorite.trimmedURLString
        onPersist()
    }
}

private struct WebpageWebViewContainer: View {
    @Binding var model: WebpageModuleModel
    let showsToolbar: Bool
    let interactionEnabled: Bool
    let webInteractionModeEnabled: Bool

    @State private var revision: Int = 0

    var body: some View {
        let viewID = "\(model.id.uuidString)-\(revision)-\(model.sessionMode.rawValue)"

        WebpageWebViewRepresentable(
            moduleID: model.id,
            url: model.normalizedURL,
            refreshInterval: model.effectiveRefreshIntervalSeconds,
            sessionMode: model.sessionMode,
            contentMode: model.renderMode.preferredContentMode,
            interactionEnabled: interactionEnabled,
            scrollInputEnabled: interactionEnabled && (webInteractionModeEnabled || !showsToolbar),
            showsToolbar: showsToolbar,
            revision: revision
        )
        .id(viewID)
        .onChange(of: model.normalizedURL, initial: false) { _, _ in
            revision += 1
        }
        .onChange(of: model.sessionMode, initial: false) { _, _ in
            revision += 1
        }
        .onChange(of: model.renderMode, initial: false) { _, _ in
            revision += 1
        }
    }
}

#if os(macOS)
private struct WebpageWebViewRepresentable: NSViewRepresentable {
    let moduleID: UUID
    let url: URL?
    let refreshInterval: Double?
    let sessionMode: WebpageModuleModel.SessionMode
    let contentMode: WKWebpagePreferences.ContentMode
    let interactionEnabled: Bool
    let scrollInputEnabled: Bool
    let showsToolbar: Bool
    let revision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(moduleID: moduleID)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WebpageModuleFactory.makeWebView(
            moduleID: moduleID,
            sessionMode: sessionMode,
            coordinator: context.coordinator
        )
        context.coordinator.attach(webView: view)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(
            webView: nsView,
            url: url,
            refreshInterval: refreshInterval,
            sessionMode: sessionMode,
            contentMode: contentMode,
            interactionEnabled: interactionEnabled,
            scrollInputEnabled: scrollInputEnabled,
            showsToolbar: showsToolbar,
            revision: revision
        )
    }
}
#else
private struct WebpageWebViewRepresentable: UIViewRepresentable {
    let moduleID: UUID
    let url: URL?
    let refreshInterval: Double?
    let sessionMode: WebpageModuleModel.SessionMode
    let contentMode: WKWebpagePreferences.ContentMode
    let interactionEnabled: Bool
    let scrollInputEnabled: Bool
    let showsToolbar: Bool
    let revision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(moduleID: moduleID)
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = WebpageModuleFactory.makeWebView(
            moduleID: moduleID,
            sessionMode: sessionMode,
            coordinator: context.coordinator
        )
        context.coordinator.attach(webView: view)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(
            webView: uiView,
            url: url,
            refreshInterval: refreshInterval,
            sessionMode: sessionMode,
            contentMode: contentMode,
            interactionEnabled: interactionEnabled,
            scrollInputEnabled: scrollInputEnabled,
            showsToolbar: showsToolbar,
            revision: revision
        )
    }
}
#endif

private enum WebpageModuleFactory {
    static func makeWebView(
        moduleID: UUID,
        sessionMode: WebpageModuleModel.SessionMode,
        coordinator: Coordinator
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WebpageSessionStore.dataStore(for: moduleID, sessionMode: sessionMode)
        configuration.defaultWebpagePreferences.preferredContentMode = .recommended
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
#if os(iOS)
        configuration.allowsPictureInPictureMediaPlayback = false
#endif
        let webView = CanvasFriendlyWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = false
        coordinator.registerNotifications()
        NotificationCenter.default.post(
            name: .webpageModuleNavigationStateChanged,
            object: WebpageNavigationState(moduleID: moduleID, canGoBack: false, canGoForward: false)
        )
        return webView
    }
}

private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let moduleID: UUID
    private weak var webView: WKWebView?
    private var lastLoadedURL: URL?
    private var currentRevision: Int = -1
    private var timer: Timer?
    private var configuredRefreshInterval: Double?
    private var notificationsRegistered = false

    init(moduleID: UUID) {
        self.moduleID = moduleID
    }

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func registerNotifications() {
        guard !notificationsRegistered else { return }
        notificationsRegistered = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(goBack), name: .webpageModuleGoBack, object: moduleID)
        center.addObserver(self, selector: #selector(goForward), name: .webpageModuleGoForward, object: moduleID)
        center.addObserver(self, selector: #selector(reloadPage), name: .webpageModuleReload, object: moduleID)
        center.addObserver(self, selector: #selector(resetSession), name: .webpageModuleResetSession, object: moduleID)
    }

    func update(
        webView: WKWebView,
        url: URL?,
        refreshInterval: Double?,
        sessionMode: WebpageModuleModel.SessionMode,
        contentMode: WKWebpagePreferences.ContentMode,
        interactionEnabled: Bool,
        scrollInputEnabled: Bool,
        showsToolbar: Bool,
        revision: Int
    ) {
        _ = sessionMode
        webView.configuration.defaultWebpagePreferences.preferredContentMode = contentMode
        applyInteraction(interactionEnabled, to: webView)
        applyScrollInput(scrollInputEnabled, to: webView)
        webView.allowsBackForwardNavigationGestures = showsToolbar

        if currentRevision != revision {
            currentRevision = revision
            lastLoadedURL = nil
        }

        if let url, lastLoadedURL != url || webView.url == nil {
            lastLoadedURL = url
            webView.load(URLRequest(url: url))
        }

        configureRefresh(interval: refreshInterval, for: webView)
        publishNavigationState(for: webView)
    }

    private func configureRefresh(interval: Double?, for webView: WKWebView) {
        guard configuredRefreshInterval != interval else { return }

        configuredRefreshInterval = interval
        timer?.invalidate()
        timer = nil

        guard let interval else { return }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak webView] _ in
            guard let webView else { return }
            webView.reload()
        }
    }

    private func applyInteraction(_ enabled: Bool, to webView: WKWebView) {
#if os(iOS)
        webView.isUserInteractionEnabled = enabled
#else
        webView.enclosingScrollView?.hasHorizontalScroller = enabled
        webView.enclosingScrollView?.hasVerticalScroller = enabled
#endif
    }

    private func applyScrollInput(_ enabled: Bool, to webView: WKWebView) {
#if os(iOS)
        webView.scrollView.isScrollEnabled = enabled
#else
        (webView as? CanvasFriendlyWKWebView)?.scrollInputEnabled = enabled
#endif
    }

    private func publishNavigationState(for webView: WKWebView) {
        NotificationCenter.default.post(
            name: .webpageModuleNavigationStateChanged,
            object: WebpageNavigationState(
                moduleID: moduleID,
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward
            )
        )
    }

    @objc private func goBack() {
        webView?.goBack()
    }

    @objc private func goForward() {
        webView?.goForward()
    }

    @objc private func reloadPage() {
        webView?.reload()
    }

    @objc private func resetSession() {
        timer?.invalidate()
        if let webView {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }
        lastLoadedURL = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        publishNavigationState(for: webView)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        publishNavigationState(for: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        publishNavigationState(for: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        publishNavigationState(for: webView)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

#if os(macOS)
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
private typealias CanvasFriendlyWKWebView = WKWebView
#endif

private struct WebpageNavigationState {
    let moduleID: UUID
    let canGoBack: Bool
    let canGoForward: Bool
}

private enum WebpageSessionStore {
    static func dataStore(
        for moduleID: UUID,
        sessionMode: WebpageModuleModel.SessionMode
    ) -> WKWebsiteDataStore {
        switch sessionMode {
        case .privateSession:
            return .nonPersistent()
        case .rememberLogin:
            return WKWebsiteDataStore(forIdentifier: moduleID)
        }
    }

    static func clearPersistentSession(for moduleID: UUID) {
        let store = WKWebsiteDataStore(forIdentifier: moduleID)
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: dataTypes) { records in
            store.removeData(ofTypes: dataTypes, for: records) { }
        }
    }
}

private extension Notification.Name {
    static let webpageModuleGoBack = Notification.Name("WebpageModuleGoBack")
    static let webpageModuleGoForward = Notification.Name("WebpageModuleGoForward")
    static let webpageModuleReload = Notification.Name("WebpageModuleReload")
    static let webpageModuleResetSession = Notification.Name("WebpageModuleResetSession")
    static let webpageModuleNavigationStateChanged = Notification.Name("WebpageModuleNavigationStateChanged")
}

enum WebpageModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .webpage(WebpageModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let modelBinding = Binding<WebpageModuleModel>(
            get: {
                if case .webpage(let model) = module.wrappedValue.kind {
                    return model
                }
                return WebpageModuleModel()
            },
            set: { newValue in
                var updated = module.wrappedValue
                updated.kind = .webpage(newValue)
                module.wrappedValue = updated
            }
        )

        return AnyView(WebpageModuleView(model: modelBinding, isLiveMode: isLiveMode))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        _ = showsHeader
        _ = onPersist
        return AnyView(EmptyView())
    }
}
