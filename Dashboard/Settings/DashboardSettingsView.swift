//
//  DashboardSettingsView.swift
//  Relay
//
//  Created by David Bullard on 11/17/25.
//


import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

enum DashboardSettingsInitialSelection {
    case general
    case audio(AudioInputsConfigView.Tab)
}

/// High-level settings container for the Relay Dashboard.
/// This hosts multiple settings pages (General, Planning Center, etc.).
struct DashboardSettingsView: View {
    private enum SettingsPage: String, CaseIterable, Identifiable {
        case general = "General"
        case audio = "Audio"
        case externalConnections = "External Connections"
        case devices = "External Devices"
        case controlInputs = "External Control"
        case lan = "Sync & Mirror"
        case access = "Access"
        case help = "Help"
        case preview = "Preview"
        case subscription = "Support"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .general: return "gearshape"
            case .audio: return "mic"
            case .externalConnections: return "link.badge.plus"
            case .devices: return "externaldrive.connected.to.line.below"
            case .lan: return "wifi"
            case .controlInputs: return "dot.radiowaves.left.and.right"
            case .access: return "hand.raised"
            case .help: return "questionmark.circle"
            case .preview: return "testtube.2"
            case .subscription: return "heart"
        }
    }
    }

    @State private var selection: SettingsPage = .general
    @State private var initialAudioTab: AudioInputsConfigView.Tab
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.proUpgradeAction) private var proUpgradeAction
    @State private var showingUpgradePrompt: Bool = false
    @EnvironmentObject private var relayAccountCoordinator: RelayAccountCoordinator
#if os(macOS)
    @EnvironmentObject private var licenseCoordinator: LicenseCoordinator
    @State private var showingLicensingManager: Bool = false
#endif
#if os(iOS)
    @State private var phoneNavigationPath: [SettingsPage] = []
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
#endif

    private var lockedPages: Set<SettingsPage> {
        [.audio, .devices, .controlInputs]
    }

    private func isLocked(_ page: SettingsPage) -> Bool {
        !subscriptionManager.hasPro && lockedPages.contains(page)
    }

    init(initialSelection: DashboardSettingsInitialSelection = .general) {
        switch initialSelection {
        case .general:
            _selection = State(initialValue: .general)
            _initialAudioTab = State(initialValue: .measurement)
        case .audio(let tab):
            _selection = State(initialValue: .audio)
            _initialAudioTab = State(initialValue: tab)
        }
    }

    var body: some View {
        let showProPill = !subscriptionManager.hasPro
#if os(macOS)
        HStack(spacing: 0) {
            // Sidebar
            List(selection: $selection) {
                if RelayLicensingConfig.isDirectMacDistribution {
                    FreeStatusCard(isCompact: true) {
                        selection = .subscription
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selection == .subscription ? Color.blue : Color.clear, lineWidth: 2)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = .subscription
                    }
                } else {
                    FreeStatusCard(isCompact: true) {
                        selection = .subscription
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(SettingsPage.allCases.filter { page in
                    if RelayLicensingConfig.isDirectMacDistribution {
                        return page != .subscription
                    }
                    return true
                }) { page in
                    let locked = isLocked(page)
                    if page == .externalConnections {
                        HStack(spacing: 8) {
                            Image(systemName: page.iconName)
                            Text(page.rawValue)
                        }
                        .tag(page)
                        .tutorialAnchor("settings.externalConnections")
                        .opacity(locked ? 0.45 : 1.0)
                        .disabled(locked)
                    } else if page == .devices || page == .audio {
                        HStack(spacing: 8) {
                            Image(systemName: page.iconName)
                            Text(page.rawValue)
                            if showProPill {
                                ProBadgeView(fontSize: 9)
                            }
                        }
                        .tag(page)
                        .tutorialAnchor(page == .devices ? "settings.externalDevices" : "settings.audio")
                        .opacity(locked ? 0.45 : 1.0)
                        .disabled(locked)
                    } else if page == .controlInputs {
                        HStack(spacing: 8) {
                            Image(systemName: page.iconName)
                            Text(page.rawValue)
                            if showProPill {
                                ProBadgeView(fontSize: 9)
                            }
                        }
                        .tag(page)
                        .opacity(locked ? 0.45 : 1.0)
                        .disabled(locked)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: page.iconName)
                            Text(page.rawValue)
                        }
                        .tag(page)
                        .opacity(locked ? 0.45 : 1.0)
                        .disabled(locked)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

            Divider()

            // Content area
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch selection {
                    case .general:
                        GeneralDashboardSettingsPane()
                    case .audio:
                        AudioInputsConfigView(initialTab: initialAudioTab, presentationStyle: .embedded)
                    case .externalConnections:
                        ExternalConnectionsSettingsView()
                    case .devices:
                        ExternalDevicesSettingsView()
                    case .lan:
                        DashboardLANSettingsView()
                    case .controlInputs:
                        ControlInputsSettingsView()
                    case .access:
                        DashboardAccessSettingsView()
                    case .help:
                        DashboardHelpSettingsView()
                    case .preview:
                        DashboardPreviewSettingsView()
                    case .subscription:
                        SubscriptionDetailsSettingsView()
                            .environmentObject(licenseCoordinator)
                    }
                }
                .opacity(isLocked(selection) ? 0.0 : 1.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(12)
            }
                .frame(minWidth: 520, minHeight: 520)
        }
        .frame(minWidth: 820, minHeight: 560)
                .sheet(isPresented: $showingUpgradePrompt) {
                    ZStack {
                        Color.black.ignoresSafeArea()
#if os(iOS)
                    ProUpgradePromptViewIOS(
                        buttonTitle: "Upgrade to Pro",
                        secondaryButtonTitle: "Continue with Free",
                        secondaryAction: {
                            showingUpgradePrompt = false
                        },
                        animateOnAppear: true,
                        showPlanSelector: true,
                        showManageLinks: true
                    ) {
                        showingUpgradePrompt = false
                    }
#else
                    if RelayLicensingConfig.isDirectMacDistribution {
                        LicensingGateView(
                            showsStatusView: false,
                            secondaryButtonTitle: "Continue with Free",
                            secondaryButtonAction: {
                                showingUpgradePrompt = false
                            },
                            showsCloseButton: false
                        )
                        .environmentObject(licenseCoordinator)
                    } else {
                        ProUpgradePromptView(
                            buttonTitle: "Upgrade to Pro",
                            secondaryButtonTitle: "Continue with Free",
                            secondaryAction: {
                                showingUpgradePrompt = false
                            },
                            animateOnAppear: true,
                            showPlanSelector: true,
                            showManageLinks: true
                        ) {
                            showingUpgradePrompt = false
                        }
                    }
#endif
                }
            }
#if os(macOS)
        .sheet(isPresented: $showingLicensingManager) {
            LicensingGateView()
                .environmentObject(licenseCoordinator)
        }
#endif
        .onAppear {
            if isLocked(selection) {
                selection = .general
            }
        }
        .onChange(of: selection, initial: false) { _, newValue in
            if isLocked(newValue) {
                selection = .general
            }
        }
        .onChange(of: subscriptionManager.hasPro, initial: false) { _, _ in
            if isLocked(selection) {
                selection = .general
            }
        }
#else
        if isIPad {
            // iPad: two-column layout matching Mac account management style
            NavigationSplitView {
                List {
                    FreeStatusCard(isCompact: true) {
                        selection = .subscription
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selection == .subscription ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = .subscription }

                    ForEach(SettingsPage.allCases.filter { page in
                        if page == .access { return false }
                        if page == .subscription { return false }
                        return true
                    }) { page in
                        let locked = isLocked(page)
                        if page == .externalConnections {
                            Button { if !locked { selection = page } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: page.iconName)
                                    Text(page.rawValue)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                selection == page
                                    ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.15))
                                    : nil
                            )
                            .tutorialAnchor("settings.externalConnections")
                            .opacity(locked ? 0.45 : 1.0)
                            .disabled(locked)
                        } else if page == .devices || page == .audio {
                            Button { if !locked { selection = page } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: page.iconName)
                                    Text(page.rawValue)
                                    if showProPill { ProBadgeView(fontSize: 9) }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                selection == page
                                    ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.15))
                                    : nil
                            )
                            .tutorialAnchor(page == .devices ? "settings.externalDevices" : "settings.audio")
                            .opacity(locked ? 0.45 : 1.0)
                            .disabled(locked)
                        } else {
                            Button { if !locked { selection = page } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: page.iconName)
                                    Text(page.rawValue)
                                    if showProPill && page == .controlInputs { ProBadgeView(fontSize: 9) }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                selection == page
                                    ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.15))
                                    : nil
                            )
                            .opacity(locked ? 0.45 : 1.0)
                            .disabled(locked)
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            } detail: {
                Group {
                    if isLocked(selection) {
                        GeneralDashboardSettingsPane()
                    } else {
                        switch selection {
                        case .general:
                            GeneralDashboardSettingsPane()
                        case .audio:
                            AudioInputsConfigView(initialTab: initialAudioTab, presentationStyle: .embedded)
                        case .externalConnections:
                            ExternalConnectionsSettingsView()
                        case .devices:
                            ExternalDevicesSettingsView()
                        case .lan:
                            DashboardLANSettingsView()
                        case .controlInputs:
                            ControlInputsSettingsView()
                        case .access:
                            DashboardAccessSettingsView()
                        case .help:
                            DashboardHelpSettingsView()
                        case .preview:
                            DashboardPreviewSettingsView()
                        case .subscription:
                            SubscriptionDetailsSettingsViewIOS(
                                hasPro: subscriptionManager.hasPro,
                                openManageSubscriptions: openManageSubscriptions
                            )
                            .environmentObject(relayAccountCoordinator)
                            .environmentObject(subscriptionManager)
                        }
                    }
                }
                .navigationTitle(selection.rawValue)
                .navigationBarTitleDisplayMode(.inline)
            }
            .onAppear {
                if isLocked(selection) { selection = .general }
            }
            .onChange(of: selection, initial: false) { _, newValue in
                if isLocked(newValue) { selection = .general }
            }
            .onChange(of: subscriptionManager.hasPro, initial: false) { _, _ in
                if isLocked(selection) { selection = .general }
            }
        } else {
            // iPhone: NavigationStack
            NavigationStack(path: $phoneNavigationPath) {
                List {
                    FreeStatusCard(isCompact: false) {
                        phoneNavigationPath.append(.subscription)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)

                    ForEach(SettingsPage.allCases.filter { page in
                        if page == .access { return false }
                        if RelayLicensingConfig.isDirectMacDistribution { return page != .subscription }
                        return true
                    }) { page in
                        let locked = isLocked(page)
                        if page == .externalConnections {
                            NavigationLink(value: page) {
                                HStack(spacing: 8) {
                                    Image(systemName: page.iconName)
                                    Text(page.rawValue)
                                }
                            }
                            .tutorialAnchor("settings.externalConnections")
                            .disabled(locked)
                            .opacity(locked ? 0.45 : 1.0)
                        } else if page == .devices || page == .audio {
                            NavigationLink(value: page) {
                                HStack(spacing: 8) {
                                    Image(systemName: page.iconName)
                                    Text(page.rawValue)
                                    if showProPill {
                                        ProBadgeView(fontSize: 9)
                                    }
                                }
                            }
                            .tutorialAnchor(page == .devices ? "settings.externalDevices" : "settings.audio")
                            .disabled(locked)
                            .opacity(locked ? 0.45 : 1.0)
                        } else if page == .controlInputs {
                            NavigationLink(value: page) {
                                HStack(spacing: 8) {
                                    Image(systemName: page.iconName)
                                    Text(page.rawValue)
                                    if showProPill {
                                        ProBadgeView(fontSize: 9)
                                    }
                                }
                            }
                            .disabled(locked)
                            .opacity(locked ? 0.45 : 1.0)
                        } else {
                            NavigationLink(value: page) {
                                HStack(spacing: 8) {
                                    Image(systemName: page.iconName)
                                    Text(page.rawValue)
                                }
                            }
                            .disabled(locked)
                            .opacity(locked ? 0.45 : 1.0)
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationDestination(for: SettingsPage.self) { page in
                    Group {
                        if isLocked(page) {
                            GeneralDashboardSettingsPane()
                        } else {
                            switch page {
                            case .general:
                                GeneralDashboardSettingsPane()
                            case .audio:
                                AudioInputsConfigView(initialTab: initialAudioTab, presentationStyle: .embedded)
                            case .externalConnections:
                                ExternalConnectionsSettingsView()
                            case .devices:
                                ExternalDevicesSettingsView()
                            case .lan:
                                DashboardLANSettingsView()
                            case .controlInputs:
                                ControlInputsSettingsView()
                            case .access:
                                DashboardAccessSettingsView()
                            case .help:
                                DashboardHelpSettingsView()
                            case .preview:
                                DashboardPreviewSettingsView()
                            case .subscription:
                                SubscriptionDetailsSettingsViewIOS(
                                    hasPro: subscriptionManager.hasPro,
                                    openManageSubscriptions: openManageSubscriptions
                                )
                                .environmentObject(relayAccountCoordinator)
                                .environmentObject(subscriptionManager)
                            }
                        }
                    }
                    .navigationTitle(page.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showingUpgradePrompt) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProUpgradePromptViewIOS(
                        buttonTitle: "Upgrade to Pro",
                        secondaryButtonTitle: "Continue with Free",
                        secondaryAction: {
                            showingUpgradePrompt = false
                        },
                        animateOnAppear: true,
                        showPlanSelector: true,
                        showManageLinks: true
                    ) {
                        showingUpgradePrompt = false
                    }
                }
            }
        }
#endif
    }

    private func openManageSubscriptions() {
        Task {
            await openManageSubscriptionsForCurrentProvider()
        }
    }

    private func openManageSubscriptionsForCurrentProvider() async {
        switch relayAccountSubscriptionProvider {
        case .appStore:
            openAppStoreManageSubscriptions()
            return
        case .lemonSqueezy:
            await openLemonSqueezyManageSubscriptions()
            return
        case nil:
            break
        }

#if os(macOS)
        if RelayLicensingConfig.isDirectMacDistribution {
            selection = .subscription
            return
        }
#endif

        openAppStoreManageSubscriptions()
    }

    private var relayAccountSubscriptionProvider: RelayAccountLicenseProvider? {
        guard let entitlements = relayAccountCoordinator.displayedEntitlements else {
            return nil
        }
        return RelayAccountLicenseProvider.resolve(from: entitlements)
    }

    private func openLemonSqueezyManageSubscriptions() async {
        guard let client = RelayLicensingClient(baseURL: RelayLicensingConfig.apiBaseURL) else {
            return
        }

        do {
            let url = try await client.manageURL()
            openExternalURL(url)
        } catch {
            print("[Licensing] Failed to open Lemon Squeezy management URL: \(error.localizedDescription)")
        }
    }

    private func openAppStoreManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else {
            return
        }
        openExternalURL(url)
    }

    private func openExternalURL(_ url: URL) {
#if os(macOS)
        NSWorkspace.shared.open(url)
#else
        UIApplication.shared.open(url)
#endif
    }
}

#if os(iOS)
private struct SubscriptionDetailsSettingsViewIOS: View {
    let hasPro: Bool
    let openManageSubscriptions: () -> Void

    @EnvironmentObject private var relayAccountCoordinator: RelayAccountCoordinator
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var email: String = ""
    @State private var showingUpgradePrompt: Bool = false
    @State private var showingAccountDetails: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Support")
                    .font(.title2.bold())

                Text("Relay is free. Support is optional and unlocks nothing. You can also sign in to your Relay Account here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                SupportRelayCard()

                if RelayAccountConfig.isAuthEnabled {
                    if relayAccountCoordinator.isSignedIn {
                        accountStatusCard
                        accountActionsCard
                    } else {
                        signInCard
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private var appStoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Store Subscription")
                .font(.headline)

            if subscriptionManager.legacyLicensePro {
                Text("Your Pro subscription is active on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if subscriptionManager.isSuppressingStaleLocalAppStoreEntitlement {
                Text("This device no longer has an active App Store subscription. Relay Account restore has been paused until purchases are restored or re-linked.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if subscriptionManager.isUsingRelayAccountAppStoreEntitlement {
                Text("Pro is currently unlocked through your Relay Account's linked App Store subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if hasPro {
                Text("Pro is currently active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Upgrade to unlock Pro features including unlimited tabs, automations, and more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !hasPro {
                    Button("Upgrade to Pro") {
                        showingUpgradePrompt = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Manage Subscription") {
                    openManageSubscriptions()
                }
                .buttonStyle(.bordered)

                Button("Restore Purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .buttonStyle(.bordered)
            }

            if let message = subscriptionManager.lastPurchaseStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var accountStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Relay Account")
                    .font(.headline)

                Spacer()

                Button {
                    showingAccountDetails = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show account details")
            }

            if let email = relayAccountCoordinator.currentUserEmail ?? relayAccountCoordinator.displayedEntitlements?.user?.email {
                LabeledContent("Signed In") {
                    Text(email)
                        .textSelection(.enabled)
                }
            }

            if let lastRefreshAt = relayAccountCoordinator.lastRefreshAt {
                LabeledContent("Last Refresh") {
                    Text(lastRefreshAt.formatted(date: .abbreviated, time: .standard))
                }
            }

            if let entitlements = relayAccountCoordinator.displayedEntitlements,
               let provider = RelayAccountLicenseProvider.resolve(from: entitlements) {
                LabeledContent("License Provider") {
                    accountLicenseProviderBadge(for: provider)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .sheet(isPresented: $showingAccountDetails) {
            NavigationStack {
                RelayAccountDetailsInfoView()
                    .environmentObject(relayAccountCoordinator)
                    .environmentObject(subscriptionManager)
                    .navigationTitle("Account Details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingAccountDetails = false
                            }
                        }
                    }
            }
        }
    }

    private var accountActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relay Account")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Sign Out") {
                    Task { await relayAccountCoordinator.logout() }
                }
                .buttonStyle(.bordered)
                .disabled(!RelayAccountConfig.isAuthEnabled || relayAccountCoordinator.isBusy)

                DeleteAccountButton(coordinator: relayAccountCoordinator)
            }

            if let message = relayAccountCoordinator.lastErrorMessage {
                if let code = relayAccountCoordinator.lastErrorCode {
                    Text("Last account error (\(code)): \(message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Last account error: \(message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign In to Relay Account")
                .font(.headline)

            Text("Relay is free, so you do not need a Relay Account. Relay Account sign-in (magic link) is no longer needed and will be retired in a future update. If you have signed in, you can delete your account at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch relayAccountCoordinator.state {
            case .waitingForEmail(let waitingEmail):
                waitingForEmailContent(email: waitingEmail)
            default:
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                Button("Send Login Link") {
                    Task { await relayAccountCoordinator.requestMagicLink(email: email) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!RelayAccountConfig.isAuthEnabled || relayAccountCoordinator.isBusy)
            }

            switch relayAccountCoordinator.state {
            case .sendingMagicLink:
                Text("Sending sign-in link…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .signingIn:
                Text("Signing in to Relay Account…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .error(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    @ViewBuilder
    private func waitingForEmailContent(email: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check your email for a Relay sign-in link sent to \(email).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("If it does not show up right away, check your spam or junk folder.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let secondsRemaining = relayAccountCoordinator.secondsUntilMagicLinkRequestAllowed(at: context.date)
                if secondsRemaining > 0 {
                    Text("You can request another sign-in link in \(secondsRemaining) seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Send Another Link") {
                        Task { await relayAccountCoordinator.requestMagicLink(email: email) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!RelayAccountConfig.isAuthEnabled || relayAccountCoordinator.isBusy)
                }
            }

            if let verifyURL = relayAccountCoordinator.lastMagicLinkVerifyURL {
                Link("Open Verification Link", destination: verifyURL)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private var appStoreLinkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Store Linking")
                .font(.headline)

            Text("This device has an App Store Pro subscription that has not been linked to a Relay Account yet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let pending = subscriptionManager.pendingAppStoreSubscriptionLink {
                Text("\(pending.productId) • transaction \(pending.originalTransactionId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if relayAccountCoordinator.isSignedIn {
                if let signedInEmail = relayAccountCoordinator.currentUserEmail ?? relayAccountCoordinator.displayedEntitlements?.user?.email {
                    Text("Signed in as \(signedInEmail).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(subscriptionManager.isLinkingPendingAppStoreSubscription ? "Linking…" : "Link Subscription") {
                    Task { await subscriptionManager.linkPendingAppStoreSubscriptionIfNeeded() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(subscriptionManager.isLinkingPendingAppStoreSubscription)
            } else {
                Text("Sign in to Relay Account first so this App Store purchase can be linked to your account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch relayAccountCoordinator.state {
                case .waitingForEmail(let waitingEmail):
                    waitingForEmailContent(email: waitingEmail)
                default:
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Button("Send Login Link") {
                        Task { await relayAccountCoordinator.requestMagicLink(email: email) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!RelayAccountConfig.isAuthEnabled || relayAccountCoordinator.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                switch relayAccountCoordinator.state {
                case .sendingMagicLink:
                    Text("Sending sign-in link…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .signingIn:
                    Text("Signing in to Relay Account…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .error(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                default:
                    EmptyView()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func accountLicenseProviderBadge(for provider: RelayAccountLicenseProvider) -> some View {
        Label {
            Text("Licensed by \(provider.displayName)")
        } icon: {
            Image(systemName: iconName(for: provider))
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.16))
        )
    }

    private func iconName(for provider: RelayAccountLicenseProvider) -> String {
        switch provider {
        case .appStore:
            return "applelogo"
        case .lemonSqueezy:
            return "key.fill"
        }
    }
}
#endif

#if os(macOS)
private struct SubscriptionDetailsSettingsView: View {
    @EnvironmentObject private var licenseCoordinator: LicenseCoordinator
    @EnvironmentObject private var relayAccountCoordinator: RelayAccountCoordinator
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showUpgradeModal = false
    @State private var showLicenseInfo = false
    @State private var showingAccountDetails = false
    @State private var licenseKeyInput: String = ""
    @State private var accountEmailInput: String = ""

    private let primaryTextColor = Color.white
    private let secondaryTextColor = Color.white.opacity(0.7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Support")
                .font(.title2.bold())

            Text("Relay is free. Support is optional and unlocks nothing.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SupportRelayCard()

            if relayAccountCoordinator.isSignedIn {
                accountActionsCard
            } else if RelayAccountConfig.isAuthEnabled {
                relayAccountSignInCard
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private var licenseKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsResolvedLicense {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("License Active")
                        .font(.headline)

                    Spacer()

                    Button {
                        showLicenseInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showLicenseInfo, arrowEdge: .top) {
                        licenseInfoPopover
                    }
                }
            } else if isInactiveStatus {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text("License Inactive")
                        .font(.headline)

                    Spacer()

                    Button {
                        showLicenseInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showLicenseInfo, arrowEdge: .top) {
                        licenseInfoPopover
                    }
                }
            } else {
                Text("License Key")
                    .font(.headline)

                Text("Enter the license key received after purchase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let entitlement = displayedDirectLicenseEntitlement {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(licenseDisplay(entitlement, maskedOnly: true))
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.primary)

                        if let provider = resolvedLicenseProvider {
                            accountLicenseProviderBadge(for: provider)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                } else if let linkedLicense = resolvedLinkedAccountLicense {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(linkedLicense.licenseKeyMasked)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Linked from your Relay Account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let provider = resolvedLicenseProvider {
                            accountLicenseProviderBadge(for: provider)
                        }
                        if let accountEmail = relayAccountCoordinator.currentUserEmail ?? relayAccountCoordinator.displayedEntitlements?.user?.email {
                            Text("Signed in as \(accountEmail)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let activationSummary = activationUsageSummary(
                            used: linkedLicense.activationUsageCount,
                            limit: linkedLicense.activationLimit
                        ) {
                            Text(activationSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                } else {
                    TextField("Enter license key", text: $licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                }

                if displayedDirectLicenseEntitlement != nil {
                    Button("Deactivate") {
                        Task { await licenseCoordinator.deactivateThisMac() }
                    }
                    .buttonStyle(.borderedProminent)
                } else if resolvedLinkedAccountLicense == nil {
                    Button("Activate") {
                        Task { await licenseCoordinator.activateLicense(licenseKey: licenseKeyInput) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var licenseInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("License Details")
                .font(.headline)

            if let entitlement = displayedDirectLicenseEntitlement {
                detailRow(label: "Product", value: displayValue(entitlement.productName))
                detailRow(label: "Plan", value: displayValue(entitlement.variantName))
                detailRow(label: "Email", value: displayValue(entitlement.customerEmail))
                detailRow(label: "License", value: licenseDisplay(entitlement, maskedOnly: true))
                detailRow(label: "Activations", value: activationUsageSummary(
                    used: entitlement.activationUsageCount,
                    limit: entitlement.activationLimit
                ) ?? "—")
                detailRow(label: "Last Checked", value: formattedDate(entitlement.validatedAt))

                if isInactiveStatus {
                    detailRow(label: "Status", value: inactiveStatusText)
                    Text("Manage your subscription to restore access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } else if let linkedLicense = resolvedLinkedAccountLicense {
                detailRow(label: "Product", value: displayValue(linkedLicense.productName))
                detailRow(label: "Plan", value: displayValue(linkedLicense.variantName))
                detailRow(label: "Email", value: displayValue(linkedLicense.customerEmail))
                detailRow(label: "License", value: linkedLicense.licenseKeyMasked)
                detailRow(label: "Status", value: linkedLicense.status.capitalized)
                detailRow(label: "Activations", value: activationUsageSummary(
                    used: linkedLicense.activationUsageCount,
                    limit: linkedLicense.activationLimit
                ) ?? "—")
                detailRow(label: "Source", value: displayValue(linkedLicense.source))
                detailRow(label: "Linked At", value: formattedDate(linkedLicense.linkedAt))
                detailRow(label: "Last Checked", value: formattedDate(linkedLicense.lastValidatedAt))
            } else {
                Text("No active license details available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 280)
    }

    private var relayAccountSignInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Relay Account")
                .font(.headline)

            switch relayAccountCoordinator.state {
            case .waitingForEmail(let email):
                waitingForEmailCardContent(email: email)
            default:
                Text("Relay is free, so you do not need a Relay Account. Relay Account sign-in (magic link) is no longer needed and will be retired in a future update. If you have signed in, you can delete your account at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Email", text: $accountEmailInput)
                    .textFieldStyle(.roundedBorder)

                Button("Send Login Link") {
                    Task {
                        await relayAccountCoordinator.requestMagicLink(email: accountEmailInput)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(relayAccountCoordinator.isBusy)

                switch relayAccountCoordinator.state {
                case .sendingMagicLink:
                    Text("Sending sign-in link…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .error(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                default:
                    EmptyView()
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Relay Account")
                    .font(.headline)

                Spacer()

                Button {
                    showingAccountDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show account details")
                .popover(isPresented: $showingAccountDetails, arrowEdge: .top) {
                    RelayAccountDetailsInfoView()
                        .environmentObject(relayAccountCoordinator)
                        .environmentObject(subscriptionManager)
                        .frame(minWidth: 320)
                        .padding(12)
                }
            }

            if let email = relayAccountCoordinator.currentUserEmail ?? relayAccountCoordinator.displayedEntitlements?.user?.email {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Sign Out") {
                    Task {
                        await relayAccountCoordinator.logout()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(relayAccountCoordinator.isBusy)

                DeleteAccountButton(coordinator: relayAccountCoordinator)
            }

            if let message = relayAccountCoordinator.lastErrorMessage {
                Text(accountErrorLine(message: message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .frame(width: 110, alignment: .leading)
            Text(value)
            Spacer()
        }
    }

    private var isActiveStatus: Bool {
        switch licenseCoordinator.status {
        case .active, .gracePeriod:
            return true
        default:
            return false
        }
    }

    private var isInactiveStatus: Bool {
        switch licenseCoordinator.status {
        case .expired, .disabled, .networkError, .unknown:
            return true
        default:
            return false
        }
    }

    private var inactiveStatusText: String {
        switch licenseCoordinator.status {
        case .expired:
            return "Expired"
        case .disabled:
            return "Disabled"
        case .networkError:
            return "Unable to validate"
        case .unknown:
            return "Inactive"
        default:
            return "Inactive"
        }
    }

    private var resolvedLinkedAccountLicense: RelayAccountLinkedLicense? {
        guard relayAccountCoordinator.isSignedIn else { return nil }
        return relayAccountCoordinator.displayedEntitlements?.licenses.first(where: { license in
            let normalizedStatus = license.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["active", "trialing", "on_trial"].contains(normalizedStatus)
        }) ?? relayAccountCoordinator.displayedEntitlements?.licenses.first
    }

    private var displayedDirectLicenseEntitlement: LicenseEntitlement? {
        guard !isRelayAccountManagedLicense else { return nil }
        guard licenseCoordinator.isLicensed else { return nil }
        return licenseCoordinator.entitlement
    }

    private var relayAccountResolvedProvider: RelayAccountLicenseProvider? {
        guard let entitlements = relayAccountCoordinator.displayedEntitlements else {
            return nil
        }

        return RelayAccountLicenseProvider.resolve(from: entitlements)
    }

    private var resolvedLicenseProvider: RelayAccountLicenseProvider? {
        if let relayAccountResolvedProvider {
            return relayAccountResolvedProvider
        }

        if displayedDirectLicenseEntitlement != nil {
            return .lemonSqueezy
        }

        return relayAccountResolvedProvider
    }

    private var shouldHideManualLicenseEntry: Bool {
        resolvedLicenseProvider == .appStore
    }

    private var isAppStoreAuthenticated: Bool {
        relayAccountResolvedProvider == .appStore
    }

    private var isRelayAccountManagedLicense: Bool {
        relayAccountCoordinator.isSignedIn && relayAccountResolvedProvider != nil
    }

    private var shouldShowLegacyLicenseSection: Bool {
        !isRelayAccountManagedLicense
    }

    private var shouldShowLegacyLicenseControls: Bool {
        !isRelayAccountManagedLicense
    }

    private var shouldShowRelayAccountSignInSection: Bool {
        !hasManualLicenseEntry
    }

    private var hasManualLicenseEntry: Bool {
        let storedLicenseKey = licenseCoordinator.currentLicenseKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !storedLicenseKey.isEmpty
    }

    private var shouldShowRestorePurchasesButton: Bool {
        resolvedLicenseProvider == .appStore
    }

    private func openManageSubscriptions() async {
        switch resolvedLicenseProvider {
        case .appStore:
            openAppStoreManageSubscriptions()
        case .lemonSqueezy:
            if RelayLicensingConfig.isDirectMacDistribution, licenseCoordinator.isLicensed {
                await licenseCoordinator.openManageSubscriptions()
            } else {
                await openLemonSqueezyManageSubscriptions()
            }
        case nil:
            if RelayLicensingConfig.isDirectMacDistribution {
                await licenseCoordinator.openManageSubscriptions()
            } else {
                openAppStoreManageSubscriptions()
            }
        }
    }

    private func openLemonSqueezyManageSubscriptions() async {
        guard let client = RelayLicensingClient(baseURL: RelayLicensingConfig.apiBaseURL) else {
            return
        }

        do {
            let url = try await client.manageURL()
            openExternalURL(url)
        } catch {
            print("[Licensing] Failed to open Lemon Squeezy management URL: \(error.localizedDescription)")
        }
    }

    private func openAppStoreManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else {
            return
        }
        openExternalURL(url)
    }

    private func openExternalURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private var showsResolvedLicense: Bool {
        isActiveStatus || resolvedLinkedAccountLicense != nil
    }

    private var shouldShowUpgradeButton: Bool {
        !subscriptionManager.effectivePro && !relayAccountCoordinator.isSignedIn
    }

    private func displayValue(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value! : "—"
    }

    private func formattedDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "—"
    }

    private func licenseDisplay(_ entitlement: LicenseEntitlement, maskedOnly: Bool = false) -> String {
        if maskedOnly {
            return "•••• •••• •••• \(licenseSuffix(entitlement))"
        }
        if let suffix = entitlement.licenseKeySuffix?.trimmingCharacters(in: .whitespacesAndNewlines), !suffix.isEmpty {
            let masked = entitlement.licenseKeyMasked
            if masked.contains(suffix) {
                return masked
            }
            let separator = masked.hasSuffix("-") ? "" : "-"
            return masked + separator + suffix
        }
        return displayValue(entitlement.licenseKeyMasked)
    }

    private func licenseSuffix(_ entitlement: LicenseEntitlement) -> String {
        if let suffix = entitlement.licenseKeySuffix?.trimmingCharacters(in: .whitespacesAndNewlines), !suffix.isEmpty {
            return suffix
        }
        let masked = entitlement.licenseKeyMasked
        return String(masked.suffix(4))
    }

    private func linkedLicenseLine(for license: RelayAccountLinkedLicense) -> String {
        let product = license.productName ?? "Relay Pro"
        let variant = license.variantName ?? "License"
        let activationSummary = activationUsageSummary(
            used: license.activationUsageCount,
            limit: license.activationLimit
        )
        let parts = [
            license.licenseKeyMasked,
            product,
            variant,
            license.status
        ] + (activationSummary.map { [$0] } ?? [])
        return parts.joined(separator: " • ")
    }

    private func activationUsageSummary(used: Int?, limit: Int?) -> String? {
        guard let used, let limit, limit > 0 else { return nil }
        return "\(used)/\(limit) activations used"
    }

    private func entitlementSourceLabel(_ entitlements: RelayAccountEntitlementsResponse) -> String {
        let sources = [
            entitlements.sources.subscription ? "subscription" : nil,
            entitlements.sources.license ? "linked license" : nil
        ].compactMap { $0 }

        if sources.isEmpty {
            return "none"
        }

        return sources.joined(separator: ", ")
    }

    private func accountLicenseProviderBadge(for provider: RelayAccountLicenseProvider) -> some View {
        Label {
            Text("Licensed by \(provider.displayName)")
        } icon: {
            Image(systemName: iconName(for: provider))
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.16))
        )
    }

    private func iconName(for provider: RelayAccountLicenseProvider) -> String {
        switch provider {
        case .appStore:
            return "applelogo"
        case .lemonSqueezy:
            return "key.fill"
        }
    }

    private func accountErrorLine(message: String) -> String {
        if let code = relayAccountCoordinator.lastErrorCode {
            return "Last account error (\(code)): \(message)"
        }
        return "Last account error: \(message)"
    }

    @ViewBuilder
    private func waitingForEmailCardContent(email: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check your email for a Relay sign-in link sent to \(email).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("If it does not show up right away, check your spam or junk folder.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let secondsRemaining = relayAccountCoordinator.secondsUntilMagicLinkRequestAllowed(at: context.date)
                if secondsRemaining > 0 {
                    Text("You can request another sign-in link in \(secondsRemaining) seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Send Another Link") {
                        Task {
                            await relayAccountCoordinator.requestMagicLink(email: email)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(relayAccountCoordinator.isBusy)
                }
            }

            if let verifyURL = relayAccountCoordinator.lastMagicLinkVerifyURL {
                Link("Open Verification Link", destination: verifyURL)
                    .font(.caption.weight(.semibold))
            }
        }
    }
}
#endif

private struct RelayAccountDetailsInfoView: View {
    @EnvironmentObject private var relayAccountCoordinator: RelayAccountCoordinator
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Feature Flag") {
                    Text(RelayAccountConfig.isAuthEnabled ? "Enabled" : "Disabled")
                }

                if let email = relayAccountCoordinator.currentUserEmail ?? relayAccountCoordinator.displayedEntitlements?.user?.email {
                    LabeledContent("Signed In") {
                        Text(email)
                            .textSelection(.enabled)
                    }
                } else {
                    LabeledContent("Signed In") {
                        Text("No")
                    }
                }

                if let lastRefreshAt = relayAccountCoordinator.lastRefreshAt {
                    LabeledContent("Last Refresh") {
                        Text(lastRefreshAt.formatted(date: .abbreviated, time: .standard))
                    }
                }

                if let entitlements = relayAccountCoordinator.displayedEntitlements {
                    LabeledContent("Entitlement Source") {
                        Text(entitlementSourceLabel(entitlements))
                    }
                }

                if let entitlements = relayAccountCoordinator.displayedEntitlements,
                   let provider = RelayAccountLicenseProvider.resolve(from: entitlements) {
                    LabeledContent("License Provider") {
                        accountLicenseProviderBadge(for: provider)
                    }
                }

                if let entitlements = relayAccountCoordinator.displayedEntitlements,
                   !entitlements.subscriptions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subscriptions")
                            .font(.headline)
                        ForEach(entitlements.subscriptions) { subscription in
                            Text(subscriptionLine(for: subscription))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let entitlements = relayAccountCoordinator.displayedEntitlements,
                   !entitlements.licenses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Linked Licenses")
                            .font(.headline)
                        ForEach(entitlements.licenses) { license in
                            Text(linkedLicenseLine(for: license))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let message = relayAccountCoordinator.lastErrorMessage {
                    Text(accountErrorLine(message: message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func subscriptionLine(for subscription: RelayAccountSubscription) -> String {
        let endDate = subscription.currentPeriodEnd?.formatted(date: .abbreviated, time: .omitted) ?? "n/a"
        return "\(subscription.provider) • \(subscription.status) • ends \(endDate)"
    }

    private func linkedLicenseLine(for license: RelayAccountLinkedLicense) -> String {
        let product = license.productName ?? "Relay Pro"
        let variant = license.variantName ?? "License"
        let activationSummary = activationUsageSummary(
            used: license.activationUsageCount,
            limit: license.activationLimit
        )
        let parts = [
            license.licenseKeyMasked,
            product,
            variant,
            license.status
        ] + (activationSummary.map { [$0] } ?? [])
        return parts.joined(separator: " • ")
    }

    private func activationUsageSummary(used: Int?, limit: Int?) -> String? {
        guard let used, let limit, limit > 0 else { return nil }
        return "\(used)/\(limit) activations used"
    }

    private func entitlementSourceLabel(_ entitlements: RelayAccountEntitlementsResponse) -> String {
        let sources = [
            entitlements.sources.subscription ? "subscription" : nil,
            entitlements.sources.license ? "linked license" : nil
        ].compactMap { $0 }

        if sources.isEmpty {
            return "none"
        }

        return sources.joined(separator: ", ")
    }

    private func accountLicenseProviderBadge(for provider: RelayAccountLicenseProvider) -> some View {
        Label {
            Text("Licensed by \(provider.displayName)")
        } icon: {
            Image(systemName: iconName(for: provider))
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.16))
        )
    }

    private func iconName(for provider: RelayAccountLicenseProvider) -> String {
        switch provider {
        case .appStore:
            return "applelogo"
        case .lemonSqueezy:
            return "key.fill"
        }
    }

    private func accountErrorLine(message: String) -> String {
        if let code = relayAccountCoordinator.lastErrorCode {
            return "Last account error (\(code)): \(message)"
        }
        return "Last account error: \(message)"
    }
}

private struct SupportRelayCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Support Relay")
                .font(.headline)

            Text("Relay is free and community-driven. Help by reporting bugs, improving documentation, or contributing code on GitHub.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openURL(RelayLicensingConfig.supportURL)
            } label: {
                Label("Relay on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FreeStatusCard: View {
    let isCompact: Bool
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: isCompact ? 10 : 12) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.18))
                    .frame(width: isCompact ? 28 : 34, height: isCompact ? 28 : 34)
                Image(systemName: "heart.fill")
                    .font(.system(size: isCompact ? 13 : 16, weight: .semibold))
                    .foregroundStyle(.pink)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Relay is free")
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                if !isCompact {
                    Text("Every feature is unlocked. Thanks for using Relay.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !isCompact {
                Button("Support") {
                    onAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(.vertical, isCompact ? 8 : 12)
        .padding(.horizontal, isCompact ? 12 : 14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
}

/// Combined settings page for external integrations (PCO, ProPresenter, NDI).
struct ExternalConnectionsSettingsView: View {
    enum ConnectionPage: String, CaseIterable, Identifiable {
        case pco = "Planning Center"
        case propresenter = "ProPresenter"
        case liveStream = "Live Stream"
        case smartLights = "Smart Lights"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .pco: return "link"
            case .liveStream: return "dot.radiowaves.left.and.right"
            case .propresenter: return "play.rectangle.on.rectangle"
            case .smartLights: return "lightbulb.2"
            }
        }
    }

    @State private var selection: ConnectionPage = .pco
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
#if os(iOS)
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
#endif

    private var isProPresenterLocked: Bool {
        !subscriptionManager.hasPro
    }

    private var isLiveStreamLocked: Bool {
        !subscriptionManager.hasPro
    }

    private var isSmartLightsLocked: Bool {
        !subscriptionManager.hasPro
    }

    private var visiblePages: [ConnectionPage] {
        ConnectionPage.allCases.filter { page in
            if page == .liveStream {
                return LiveStreamFeatureFlags.isEnabled
            }
            if page == .smartLights {
                return SmartLightFeatureFlags.isEnabled
            }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("External Connections")
                .font(.title2.bold())

            Text("Configure integrations for Planning Center, live streaming, and ProPresenter.")
                .font(.footnote)
                .foregroundStyle(.secondary)

#if os(macOS)
            ConnectionSegmentedControl(
                selection: $selection,
                isLiveStreamLocked: isLiveStreamLocked,
                isProPresenterLocked: isProPresenterLocked,
                isSmartLightsLocked: isSmartLightsLocked,
                visiblePages: visiblePages
            )
            .padding(.bottom, 4)
            .onAppear {
                if isLiveStreamLocked {
                    selection = .pco
                } else if isProPresenterLocked {
                    selection = .pco
                } else if isSmartLightsLocked {
                    selection = .pco
                }
            }
            .onChange(of: selection, initial: false) { _, newValue in
                if isLiveStreamLocked && newValue == .liveStream {
                    selection = .pco
                } else if isProPresenterLocked && newValue == .propresenter {
                    selection = .pco
                } else if isSmartLightsLocked && newValue == .smartLights {
                    selection = .pco
                }
            }

            Group {
                switch selection {
                case .pco:
                    DashboardPCOSettingsView()
                case .liveStream:
                    DashboardLiveStreamSettingsView()
                case .propresenter:
                    DashboardProPresenterSettingsView()
                case .smartLights:
                    DashboardSmartLightsSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#else
            if isIPad {
                Picker("Connection", selection: $selection) {
                    ForEach(visiblePages) { page in
                        Text(page.rawValue)
                            .tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)
                .onAppear {
                    if isLiveStreamLocked {
                        selection = .pco
                    } else if isProPresenterLocked {
                        selection = .pco
                    } else if isSmartLightsLocked {
                        selection = .pco
                    }
                }
                .onChange(of: selection, initial: false) { _, newValue in
                    if isLiveStreamLocked && newValue == .liveStream {
                        selection = .pco
                    } else if isProPresenterLocked && newValue == .propresenter {
                        selection = .pco
                    } else if isSmartLightsLocked && newValue == .smartLights {
                        selection = .pco
                    }
                }

                Group {
                    switch selection {
                    case .pco:
                        DashboardPCOSettingsView()
                    case .liveStream:
                        DashboardLiveStreamSettingsView()
                    case .propresenter:
                        DashboardProPresenterSettingsView()
                    case .smartLights:
                        DashboardSmartLightsSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // iPhone: show each integration as a navigation list.
                List {
                    ForEach(visiblePages) { page in
                        let locked =
                            (page == .liveStream && isLiveStreamLocked)
                            || (page == .propresenter && isProPresenterLocked)
                            || (page == .smartLights && isSmartLightsLocked)
                        NavigationLink(value: page) {
                            HStack(spacing: 8) {
                                Label(page.rawValue, systemImage: page.iconName)
                                if locked {
                                    ProBadgeView(fontSize: 9)
                                }
                            }
                        }
                        .disabled(locked)
                        .opacity(locked ? 0.5 : 1.0)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: ConnectionPage.self) { page in
                    Group {
                        switch page {
                        case .pco:
                            DashboardPCOSettingsView()
                        case .liveStream:
                            if isLiveStreamLocked {
                                DashboardPCOSettingsView()
                            } else {
                                DashboardLiveStreamSettingsView()
                            }
                        case .propresenter:
                            if isProPresenterLocked {
                                DashboardPCOSettingsView()
                            } else {
                                DashboardProPresenterSettingsView()
                            }
                        case .smartLights:
                            if isSmartLightsLocked {
                                DashboardPCOSettingsView()
                            } else {
                                DashboardSmartLightsSettingsView()
                            }
                        }
                    }
                    .navigationTitle(page.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
#endif
        }
        .padding(24)
    }

#if os(macOS)
    private struct ConnectionSegmentedControl: View {
        @Binding var selection: ConnectionPage
        let isLiveStreamLocked: Bool
        let isProPresenterLocked: Bool
        let isSmartLightsLocked: Bool
        let visiblePages: [ConnectionPage]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(visiblePages.enumerated()), id: \.element) { index, page in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1)
                    }
                    segment(page)
                }
            }
            .frame(height: 30)
            .background(Color.white.opacity(0.06), in: Capsule())
        }

        private func segment(_ page: ConnectionPage) -> some View {
            let locked =
                (page == .liveStream && isLiveStreamLocked)
                || (page == .propresenter && isProPresenterLocked)
                || (page == .smartLights && isSmartLightsLocked)
            let isSelected = selection == page
            let firstPage = visiblePages.first
            let lastPage = visiblePages.last
            return Button {
                guard !locked else { return }
                selection = page
            } label: {
                HStack(spacing: 6) {
                    Text(page.rawValue)
                        .font(.subheadline.weight(.semibold))
                    if locked {
                        ProBadgeView(fontSize: 9)
                    }
                }
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    AsymmetricRoundedRect(
                        topLeft: page == firstPage ? 14 : 0,
                        topRight: page == lastPage ? 14 : 0,
                        bottomLeft: page == firstPage ? 14 : 0,
                        bottomRight: page == lastPage ? 14 : 0
                    )
                    .fill(isSelected ? Color.blue : Color.clear)
                )
                .padding(2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(locked ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: selection)
        }
    }
#endif
}

#if os(macOS)
private struct AsymmetricRoundedRect: Shape {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomLeft: CGFloat
    let bottomRight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = min(min(topLeft, rect.width / 2), rect.height / 2)
        let tr = min(min(topRight, rect.width / 2), rect.height / 2)
        let bl = min(min(bottomLeft, rect.width / 2), rect.height / 2)
        let br = min(min(bottomRight, rect.width / 2), rect.height / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        return path
    }
}
#endif

struct DashboardHelpSettingsView: View {
    @State private var showCopiedToast = false
    @State private var showingReport = false
    @StateObject private var diagnostics = RelayDiagnosticsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Help")
                .font(.title2.bold())

            Text("Export logs for support and debugging. This includes connection details, LAN activity, and OSC events.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button("Export Logs…") {
                        NotificationCenter.default.post(name: .prodLinkExportLogsRequested, object: nil)
                    }

                    Button("Copy Diagnostic Summary") {
                        let summary = buildDiagnosticSummary()
                        copyToPasteboard(summary)
                        showCopiedToast = true
                    }
                }

                HStack(spacing: 12) {
                    Button("Report a Bug…") {
                        showingReport = true
                    }

                    Button("Contact Support") {
                        RelaySupportContact.openSupportEmail()
                    }

                    Button("Help Center") {
                        RelaySupportContact.openHelpCenter()
                    }
                    .dashboardLinkButtonStyle()
                }
            }
            .padding(.top, 4)

            if showCopiedToast {
                Text("Copied to clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCopiedToast = false
                            }
                        }
                    }
            }

            Text("Logs may include connection endpoints, device names, and OSC paths. Please review before sharing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)


            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingReport) {
            RelayBugReportSheet()
        }
    }

    private func buildDiagnosticSummary() -> String {
        diagnostics.diagnosticSummary()
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct RelayBugReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var includeDiagnostics = false
    @State private var diagnosticSummary = RelayDiagnosticsStore.shared.diagnosticSummary()
    @State private var isQueued = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Report a Bug").font(.title2.bold())
                Text("Describe what happened, what you expected, and how to reproduce it. This report is sent to Relay's private Sentry inbox only when you submit it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Your report").font(.headline)
                TextEditor(text: $message)
                    .frame(minHeight: 120)
                    .accessibilityLabel("Bug report description")
                    .disabled(isQueued)

                Toggle("Include diagnostic summary", isOn: $includeDiagnostics)
                    .disabled(isQueued)
                if includeDiagnostics {
                    Text("Review or edit the summary before submitting. It may contain device names, connection addresses, file paths, and recent errors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $diagnosticSummary)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 140)
                        .accessibilityLabel("Diagnostic summary to submit")
                        .disabled(isQueued)
                }

                Text("Submitting a report does not enable automatic crash reporting or usage diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isQueued {
                    Text("Report queued for Sentry. It will be sent when a connection is available.")
                        .accessibilityLabel("Report queued for Sentry")
                }
                HStack {
                    Button(isQueued ? "Done" : "Cancel") { dismiss() }
                    Spacer()
                    Button("Submit Report") {
                        do {
                            try RelaySentry.uploadFeedback(
                                message: message,
                                diagnostics: includeDiagnostics ? diagnosticSummary : nil
                            )
                            isQueued = true
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isQueued || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
        .alert("Report could not be queued", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

struct DashboardPreviewSettingsView: View {
    @StateObject private var loggingPrefs = WirelessLoggingPreferences.shared
    @AppStorage(RelayLicensingConfig.previewFeaturesKey) private var previewFeaturesOn: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.title2.bold())

                GroupBox("Preview features") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable preview features", isOn: $previewFeaturesOn)

                        Text("Preview features are still being tested and may change. They include newer automation triggers, smart lights, extra DAW protocols, and newer device models. Restart Relay after changing this setting.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                if RelayLicensingConfig.isPreviewEnabled {
                    wirelessLoggingSection
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var wirelessLoggingSection: some View {
        GroupBox("Wireless Diagnostics Logging") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Verbose wireless tracing is only active when preview features are on (or in debug builds), after restarting Relay.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Verbose Shure logging", isOn: $loggingPrefs.shureMasterEnabled)

                if loggingPrefs.shureMasterEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(WirelessLoggingPreferences.ShureFamily.allCases) { family in
                            Toggle(family.rawValue, isOn: shureFamilyBinding(for: family))
                        }

                        Button("Reset Shure Defaults") {
                            loggingPrefs.resetShureToDefaults()
                        }
                        .font(.caption)
                    }
                    .padding(.leading, 16)
                }

                Divider()

                Toggle("Verbose Sennheiser logging", isOn: $loggingPrefs.sennheiserMasterEnabled)

                if loggingPrefs.sennheiserMasterEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(WirelessLoggingPreferences.SennheiserFamily.allCases) { family in
                            Toggle(family.rawValue, isOn: sennheiserFamilyBinding(for: family))
                        }

                        Button("Reset Sennheiser Defaults") {
                            loggingPrefs.resetSennheiserToDefaults()
                        }
                        .font(.caption)
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func shureFamilyBinding(for family: WirelessLoggingPreferences.ShureFamily) -> Binding<Bool> {
        Binding(
            get: { loggingPrefs.isFamilyEnabled(family) },
            set: { loggingPrefs.setFamilyEnabled(family, $0) }
        )
    }

    private func sennheiserFamilyBinding(for family: WirelessLoggingPreferences.SennheiserFamily) -> Binding<Bool> {
        Binding(
            get: { loggingPrefs.isFamilyEnabled(family) },
            set: { loggingPrefs.setFamilyEnabled(family, $0) }
        )
    }

}

/// Placeholder for general dashboard settings.
struct GeneralDashboardSettingsPane: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @AppStorage("dashboard_personImageFolder") private var personImageFolder: String = ""
    @AppStorage("dashboard_personImageFolderBookmark") private var personImageFolderBookmarkData: Data?
    @AppStorage("dashboard_gridSize") private var gridSizeSetting: Double = 20.0
    @AppStorage("gridBackgroundOpacity") private var gridBackgroundOpacity: Double = 0.35
    @AppStorage("dashboard_file_autosave_enabled") private var fileAutosaveEnabled: Bool = false
    @AppStorage("dashboard_live_mode_canvas_behavior") private var liveModeCanvasBehaviorRaw: String = LiveModeCanvasBehavior.fitToScreen.rawValue
    @AppStorage("dashboard_live_mode_window_behavior") private var liveModeWindowBehaviorRaw: String = LiveModeWindowBehavior.keepCurrentSize.rawValue
#if DEBUG
    @AppStorage("subscription_forcePro") private var subscriptionForceProRaw: Int = 0
    @AppStorage("pro_upgrade_prompt_seen_v1") private var proUpgradePromptSeen: Bool = false
    @State private var isShowingFactoryResetConfirmation: Bool = false
#if os(iOS)
    @State private var isShowingFactoryResetCompleteIOS: Bool = false
#endif
#endif

    /// Global setting controlling whether tiles are allowed to overlap
    /// in Z-space on the dashboard.
    @AppStorage("dashboard_allowTileOverlap") private var allowTileOverlap: Bool = true

    @AppStorage("dashboard_colorSchemePreference") private var colorSchemePreferenceRaw: String = ColorSchemePreference.system.rawValue

    private var colorSchemePreference: Binding<ColorSchemePreference> {
        Binding(
            get: { ColorSchemePreference(rawValue: colorSchemePreferenceRaw) ?? .system },
            set: { colorSchemePreferenceRaw = $0.rawValue }
        )
    }

    private var liveModeCanvasBehavior: Binding<LiveModeCanvasBehavior> {
        Binding(
            get: { LiveModeCanvasBehavior(rawValue: liveModeCanvasBehaviorRaw) ?? .fitToScreen },
            set: { liveModeCanvasBehaviorRaw = $0.rawValue }
        )
    }

    private var liveModeWindowBehavior: Binding<LiveModeWindowBehavior> {
        Binding(
            get: { LiveModeWindowBehavior(rawValue: liveModeWindowBehaviorRaw) ?? .keepCurrentSize },
            set: { liveModeWindowBehaviorRaw = $0.rawValue }
        )
    }

    @State private var showingPersonFolderPicker: Bool = false


    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                Text("General Settings")
                    .font(.title2.bold())

                Text("Configure global dashboard appearance and layout behavior.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox("Appearance") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose how Relay looks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Appearance", selection: colorSchemePreference) {
                            ForEach(ColorSchemePreference.allCases, id: \.self) { preference in
                                Text(preference.label).tag(preference)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                GroupBox("Layout & Grid") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Grid")
                            .font(.headline)

                        Text("Controls snap-to-grid and background visibility.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Grid size")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Slider(
                                    value: $gridSizeSetting,
                                    in: 8...160,
                                    onEditingChanged: { editing in
                                        // Snap to 2pt increments when the user releases the knob.
                                        if !editing {
                                            gridSizeSetting = (gridSizeSetting / 2.0).rounded() * 2.0
                                        }
                                    }
                                )
                                .frame(maxWidth: .infinity)

                                Text("\(Int(gridSizeSetting)) pt")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }

                            GridRow {
                                Text("Grid opacity")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Slider(
                                    value: $gridBackgroundOpacity,
                                    in: 0.0...1.0,
                                    onEditingChanged: { editing in
                                        // Snap to 1% increments when the user releases the knob.
                                        if !editing {
                                            gridBackgroundOpacity = (gridBackgroundOpacity * 100.0).rounded() / 100.0
                                        }
                                    }
                                )
                                .frame(maxWidth: .infinity)

                                Text("\(Int(gridBackgroundOpacity * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        Toggle(isOn: $allowTileOverlap) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow tiles to overlap")
                                Text("When off, dropping a tile on another reverts the move.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Live Mode") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Configure what happens when entering Live Mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Canvas")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Picker("Canvas", selection: liveModeCanvasBehavior) {
                                    ForEach(LiveModeCanvasBehavior.allCases, id: \.self) { behavior in
                                        Text(behavior.label).tag(behavior)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

#if os(macOS)
                            GridRow {
                                Text("Window")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Picker("Window", selection: liveModeWindowBehavior) {
                                    ForEach(LiveModeWindowBehavior.allCases, id: \.self) { behavior in
                                        Text(behavior.label).tag(behavior)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
#endif
                        }
                    }
                }

                GroupBox("Saving") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $fileAutosaveEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Autosave saved dashboards")
                                Text("When enabled, changes to dashboards that already have a file location are written back automatically.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Person Images Folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose a folder of headshots. Images are matched by name (e.g. \"First Last.png\").")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(personImageFolder.isEmpty ? "No folder selected" : personImageFolder)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        HStack {
                            Button("Choose Folder…") {
                                choosePersonImageFolder()
                            }
#if os(iOS)
                            .fileImporter(
                                isPresented: $showingPersonFolderPicker,
                                allowedContentTypes: [.folder],
                                allowsMultipleSelection: false
                            ) { result in
                                switch result {
                                case .success(let urls):
                                    guard let url = urls.first else { return }
                                    // For iCloud Drive / provider-backed URLs, create the bookmark while coordinating
                                    // access and while the security scope is active. Otherwise `bookmarkData(...)`
                                    // can fail with "doesn't exist" even though the folder is real.
                                    let didStart = url.startAccessingSecurityScopedResource()
                                    defer {
                                        if didStart {
                                            url.stopAccessingSecurityScopedResource()
                                        }
                                    }

                                    var coordinatorError: NSError?
                                    let coordinator = NSFileCoordinator()

                                    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
                                        do {
                                            let bookmark = try coordinatedURL.bookmarkData(
                                                options: [.minimalBookmark],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil
                                            )
                                            personImageFolderBookmarkData = bookmark

                                            // Store a friendly label for the UI.
                                            personImageFolder = coordinatedURL.lastPathComponent
                                        } catch {
                                            print("[GeneralDashboardSettingsPane] Failed to create bookmark for person image folder (iOS):", error.localizedDescription)
                                            personImageFolderBookmarkData = nil
                                            personImageFolder = ""
                                        }
                                    }

                                    if let coordinatorError {
                                        print("[GeneralDashboardSettingsPane] Folder coordination error (iOS):", coordinatorError.localizedDescription)
                                    }
                                case .failure(let error):
                                    print("[GeneralDashboardSettingsPane] Folder pick cancelled/failed:", error.localizedDescription)
                                }
                            }
#endif

                            if !personImageFolder.isEmpty {
                                Button("Clear") {
                                    personImageFolder = ""
                                    personImageFolderBookmarkData = nil
                                }
                            }

                            Spacer()
                        }
                    }
                }

#if DEBUG
                GroupBox("Debug: Subscription") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Override Pro access for local testing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Access", selection: $subscriptionForceProRaw) {
                            Text("Auto").tag(0)
                            Text("Force Free").tag(1)
                            Text("Force Pro").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: subscriptionForceProRaw, initial: false) { _, _ in
                            subscriptionManager.applyDebugOverride()
                        }

                        Divider()
                            .padding(.vertical, 4)

                        Button("Reset Pro Upgrade Prompt") {
                            proUpgradePromptSeen = false
                        }
                        .buttonStyle(.bordered)

                        Button("Reset Auto-Save Announcement") {
                            UserDefaults.standard.removeObject(forKey: "autosave_announcement_shown_v1")
                        }
                        .buttonStyle(.bordered)

                        Divider()
                            .padding(.vertical, 4)

                        Button("Factory Reset…") {
                            isShowingFactoryResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .alert("Factory Reset?", isPresented: $isShowingFactoryResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        DebugFactoryReset.perform()
#if os(iOS)
                        isShowingFactoryResetCompleteIOS = true
#endif
                    }
                } message: {
                    Text("Wipes all local app configuration — devices, audio inputs, connections, onboarding state, window/UI prefs, cached feeds — back to a fresh install. Your Pro license (Keychain-based) is not affected.\n\nOn macOS the app relaunches automatically.")
                }
#if os(iOS)
                .alert("Reset Complete", isPresented: $isShowingFactoryResetCompleteIOS) {
                    Button("OK") {}
                } message: {
                    Text("Force-quit and reopen Relay to finish applying the reset.")
                }
#endif
#endif

                Color.clear
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .toggleStyle(.switch)
    }

    /// Folder picker. On macOS uses NSOpenPanel; on iOS uses a Document Picker via `.fileImporter`.
    private func choosePersonImageFolder() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                personImageFolderBookmarkData = bookmark
                personImageFolder = url.path
            } catch {
                print("[GeneralDashboardSettingsPane] Failed to create bookmark for person image folder:", error.localizedDescription)
                personImageFolderBookmarkData = nil
                personImageFolder = ""
            }
        }
#else
        // iOS: present the Document Picker (handled by `.fileImporter` attached to the button).
        showingPersonFolderPicker = true
#endif
    }
}
