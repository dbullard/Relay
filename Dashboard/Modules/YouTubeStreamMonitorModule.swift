import SwiftUI
import Combine

@MainActor
final class YouTubeStreamMonitorViewModel: ObservableObject {
    @Published private(set) var snapshot: YouTubeMonitorSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private var currentConfigKey: String?

    func startMonitoring(model: YouTubeStreamMonitorModuleModel) {
        guard LiveStreamFeatureFlags.isEnabled else {
            stopMonitoring()
            return
        }

        let nextKey = configKey(for: model)
        guard nextKey != currentConfigKey else { return }

        stopMonitoring(clearSnapshot: false)
        currentConfigKey = nextKey

        guard let broadcastID = model.selectedBroadcastID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !broadcastID.isEmpty else {
            snapshot = nil
            errorMessage = nil
            isLoading = false
            return
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.loadSnapshot(broadcastID: broadcastID)
                do {
                    try await Task.sleep(nanoseconds: UInt64(model.clampedPollIntervalSeconds * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    func stopMonitoring(clearSnapshot: Bool = true) {
        pollingTask?.cancel()
        pollingTask = nil
        currentConfigKey = nil
        isLoading = false
        errorMessage = nil
        if clearSnapshot {
            snapshot = nil
        }
    }

    private func loadSnapshot(broadcastID: String) async {
        isLoading = snapshot == nil
        do {
            let client = try makeClient()
            let snapshot = try await client.fetchMonitorSnapshot(broadcastID: broadcastID)
            guard !Task.isCancelled else { return }
            self.snapshot = snapshot
            self.errorMessage = nil
            self.isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.isLoading = false
        }
    }

    private func configKey(for model: YouTubeStreamMonitorModuleModel) -> String {
        [
            model.selectedBroadcastID ?? "",
            String(Int(model.clampedPollIntervalSeconds)),
            String(model.showHealthDetails)
        ].joined(separator: "::")
    }

    private func makeClient() throws -> YouTubeAPIClient {
        let tokenStore = YouTubeKeychainTokenStore()
        let configuration = try YouTubeOAuthConfiguration.load()
        let service = YouTubeOAuthService(configuration: configuration, tokenStore: tokenStore)
        return YouTubeAPIClient(oauthService: service, tokenStore: tokenStore)
    }
}

struct YouTubeStreamMonitorModuleView: View {
    @Binding var model: YouTubeStreamMonitorModuleModel
    let isLiveMode: Bool

    @StateObject private var viewModel = YouTubeStreamMonitorViewModel()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.13, blue: 0.16),
                            Color(red: 0.07, green: 0.08, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            content
                .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { viewModel.startMonitoring(model: model) }
        .onDisappear { viewModel.stopMonitoring(clearSnapshot: false) }
        .onChange(of: model, initial: false) { _, newValue in
            viewModel.startMonitoring(model: newValue)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !LiveStreamFeatureFlags.isEnabled {
            placeholder(
                systemImage: "testtube.2",
                title: "Live Stream Is Limited",
                message: "YouTube stream monitoring is only available in Relay beta and debug builds right now."
            )
        } else if let message = missingConfigurationMessage {
            placeholder(
                systemImage: "key.slash",
                title: "YouTube OAuth Not Configured",
                message: message
            )
        } else if model.selectedBroadcastID?.isEmpty != false {
            placeholder(
                systemImage: "dot.radiowaves.left.and.right",
                title: "No Broadcast Selected",
                message: "Open module settings, connect YouTube, and choose a live broadcast to monitor."
            )
        } else if let message = viewModel.errorMessage {
            placeholder(
                systemImage: "exclamationmark.triangle",
                title: "Unable To Load Stream",
                message: message
            )
        } else if let snapshot = viewModel.snapshot {
            liveContent(snapshot: snapshot)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text(viewModel.isLoading ? "Loading YouTube stream…" : "Waiting for data…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func liveContent(snapshot: YouTubeMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("YouTube", systemImage: "play.rectangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.74))
                    Text(snapshot.broadcastTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                statusPill(snapshot.liveState)
            }

            HStack(spacing: 12) {
                let viewerValue = snapshot.viewerCount
                    .flatMap { Self.numberFormatter.string(from: NSNumber(value: $0)) }
                    ?? "Unavailable"

                metricCard(
                    label: "Viewers",
                    value: viewerValue,
                    accent: Color(red: 0.89, green: 0.18, blue: 0.15)
                )
                metricCard(
                    label: "Health",
                    value: snapshot.healthState.title,
                    accent: color(for: snapshot.healthState)
                )
            }

            if model.showHealthDetails, let summary = snapshot.healthSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Text("Updated \(snapshot.lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.58))

                Spacer(minLength: 8)

                if let url = snapshot.deepLinkURL, !isLiveMode {
                    Button {
                        open(url: url)
                    } label: {
                        Label("Open", systemImage: "safari")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placeholder(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func statusPill(_ liveState: YouTubeMonitorSnapshot.LiveState) -> some View {
        Text(liveState.title.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color(for: liveState))
            )
    }

    private func metricCard(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.45), lineWidth: 1)
        )
    }

    private func color(for liveState: YouTubeMonitorSnapshot.LiveState) -> Color {
        switch liveState {
        case .live:
            return Color(red: 0.90, green: 0.19, blue: 0.16)
        case .starting:
            return Color.orange
        case .offline, .ended:
            return Color.white.opacity(0.18)
        case .error:
            return Color.red.opacity(0.8)
        }
    }

    private func color(for healthState: YouTubeMonitorSnapshot.HealthState) -> Color {
        switch healthState {
        case .good:
            return Color.green
        case .warning:
            return Color.orange
        case .bad:
            return Color.red
        case .unknown:
            return Color.white.opacity(0.22)
        }
    }

    private var missingConfigurationMessage: String? {
        do {
            _ = try YouTubeOAuthConfiguration.load()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func open(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

struct YouTubeStreamMonitorSettingsView: View {
    @Binding var model: YouTubeStreamMonitorModuleModel
    let onPersist: () -> Void

    @State private var accountTitle: String = ""
    @State private var broadcastChoices: [YouTubeBroadcastChoice] = []
    @State private var isLoadingChoices = false
    @State private var errorMessage: String?

    private let tokenStore = YouTubeKeychainTokenStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YouTube Stream Monitor")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !LiveStreamFeatureFlags.isEnabled {
                Text("YouTube stream monitoring is only available in Relay beta and debug builds right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let configurationError = configurationError {
                Text(configurationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)

                    Text(connectionLabel)
                        .foregroundStyle(isConnected ? .primary : .secondary)

                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        loadBroadcastChoices()
                    } label: {
                        if isLoadingChoices {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Label("Refresh Broadcasts", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(!isConnected || isLoadingChoices)
                }

                Picker("Broadcast", selection: Binding(
                    get: { model.selectedBroadcastID ?? "" },
                    set: { newValue in
                        applySelection(broadcastID: newValue.isEmpty ? nil : newValue)
                    }
                )) {
                    Text("None").tag("")
                    ForEach(availableBroadcastChoices) { choice in
                        Text("\(choice.title) • \(choice.subtitle)").tag(choice.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!isConnected)

                if isConnected && broadcastChoices.isEmpty && !isLoadingChoices {
                    Text("No active or upcoming YouTube broadcasts were found for this account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !isConnected {
                    Text("Connect YouTube in Settings > External Connections > Live Stream, then return here to choose a broadcast.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Text("Poll every")
                Spacer()
                Stepper(value: pollBinding, in: 10...60, step: 5) {
                    Text("\(Int(model.clampedPollIntervalSeconds)) sec")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Show health details", isOn: Binding(
                get: { model.showHealthDetails },
                set: { newValue in
                    model.showHealthDetails = newValue
                    onPersist()
                }
            ))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            await refreshConnectionState()
            if isConnected {
                loadBroadcastChoices()
            }
        }
    }

    private var pollBinding: Binding<Double> {
        Binding(
            get: { model.clampedPollIntervalSeconds },
            set: { newValue in
                model.pollIntervalSeconds = min(max(newValue, 10), 60)
                onPersist()
            }
        )
    }

    private var isConnected: Bool {
        tokenStore.loadTokens() != nil
    }

    private var connectionLabel: String {
        if !accountTitle.isEmpty {
            return "Connected as \(accountTitle)"
        }
        return isConnected ? "Connected to YouTube" : "Not connected"
    }

    private var configurationError: String? {
        do {
            _ = try YouTubeOAuthConfiguration.load()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var availableBroadcastChoices: [YouTubeBroadcastChoice] {
        guard let selectedID = model.selectedBroadcastID,
              !selectedID.isEmpty,
              !broadcastChoices.contains(where: { $0.id == selectedID }) else {
            return broadcastChoices
        }

        let title = model.selectedBroadcastTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = (title?.isEmpty == false) ? title! : "Selected broadcast"
        let preservedChoice = YouTubeBroadcastChoice(
            id: selectedID,
            title: fallbackTitle,
            state: .upcoming,
            scheduledStartTime: nil,
            boundStreamID: model.selectedStreamID
        )

        return [preservedChoice] + broadcastChoices
    }

    private func loadBroadcastChoices() {
        guard isConnected else { return }
        isLoadingChoices = true
        errorMessage = nil

        Task {
            do {
                let client = try makeClient()
                let choices = try await client.fetchBroadcastChoices()
                await MainActor.run {
                    broadcastChoices = choices
                    if model.selectedBroadcastID == nil,
                       let autoChoice = choices.first(where: { $0.state == .live }) ?? (choices.count == 1 ? choices.first : nil) {
                        applySelection(broadcastID: autoChoice.id)
                    }
                    isLoadingChoices = false
                }
            } catch {
                await MainActor.run {
                    isLoadingChoices = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func applySelection(broadcastID: String?) {
        model.selectedBroadcastID = broadcastID
        if let broadcastID, let choice = broadcastChoices.first(where: { $0.id == broadcastID }) {
            model.selectedBroadcastTitle = choice.title
            model.selectedStreamID = choice.boundStreamID
        } else {
            model.selectedBroadcastTitle = nil
            model.selectedStreamID = nil
        }
        onPersist()
    }

    private func refreshConnectionState() async {
        guard isConnected else {
            await MainActor.run {
                accountTitle = ""
            }
            return
        }

        do {
            let client = try makeClient()
            let channel = try await client.fetchCurrentChannel()
            await MainActor.run {
                accountTitle = channel?.title ?? ""
            }
        } catch {
            await MainActor.run {
                accountTitle = ""
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func makeClient() throws -> YouTubeAPIClient {
        let configuration = try YouTubeOAuthConfiguration.load()
        let service = YouTubeOAuthService(configuration: configuration, tokenStore: tokenStore)
        return YouTubeAPIClient(oauthService: service, tokenStore: tokenStore)
    }
}

enum YouTubeStreamMonitorModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .youtubeStreamMonitor(YouTubeStreamMonitorModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let modelBinding = Binding<YouTubeStreamMonitorModuleModel>(
            get: {
                if case .youtubeStreamMonitor(let model) = module.wrappedValue.kind {
                    return model
                }
                return YouTubeStreamMonitorModuleModel()
            },
            set: { newValue in
                var updated = module.wrappedValue
                updated.kind = .youtubeStreamMonitor(newValue)
                module.wrappedValue = updated
            }
        )

        return AnyView(YouTubeStreamMonitorModuleView(model: modelBinding, isLiveMode: isLiveMode))
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
