import SwiftUI

struct AppStoreSubscriptionLinkSheet: View {
    enum Presentation {
        case subscriptionLink
        case accountEmailEntry
    }

    @EnvironmentObject private var relayAccountCoordinator: RelayAccountCoordinator
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let presentation: Presentation
    @State private var email: String = ""

    init(presentation: Presentation = .subscriptionLink) {
        self.presentation = presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(presentation == .subscriptionLink ? "Link App Store Purchase" : "Use Relay on Another Device")
                    .font(.title2.bold())
                Spacer()
                Button("Not Now") {
                    if presentation == .subscriptionLink {
                        subscriptionManager.dismissAppStoreAccountLinkSheet()
                    }
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Text(presentation == .subscriptionLink
                ? "Pro is already active on this device. Add your email to link this App Store subscription to a Relay Account for sync and restore across devices."
                : "Connect your email to sign in to Relay Account. This is optional and does not enable crash or usage diagnostics."
            )
                .font(.callout)
                .foregroundStyle(.secondary)

            if presentation == .subscriptionLink, let pending = subscriptionManager.pendingAppStoreSubscriptionLink {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pending Purchase")
                        .font(.headline)
                    Text("\(pending.productId) • transaction \(pending.originalTransactionId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let expirationDate = pending.expirationDate {
                        Text("Renews or expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            if relayAccountCoordinator.isSignedIn, presentation == .subscriptionLink {
                signedInContent
            } else if relayAccountCoordinator.isSignedIn {
                accountConnectedContent
            } else {
                signInContent
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 320)
        .onAppear {
            email = relayAccountCoordinator.currentUserEmail ?? relayAccountCoordinator.displayedEntitlements?.user?.email ?? email
        }
        .onChange(of: relayAccountCoordinator.isSignedIn, initial: relayAccountCoordinator.isSignedIn) { _, signedIn in
            guard signedIn, presentation == .subscriptionLink else { return }
            Task {
                await subscriptionManager.linkPendingAppStoreSubscriptionIfNeeded()
                if subscriptionManager.pendingAppStoreSubscriptionLink == nil {
                    subscriptionManager.dismissAppStoreAccountLinkSheet()
                    dismiss()
                }
            }
        }
    }

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Your Email")
                .font(.headline)

            switch relayAccountCoordinator.state {
            case .waitingForEmail(let waitingEmail):
                waitingForEmailContent(email: waitingEmail)
            default:
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
#endif

                Button("Send Login Link") {
                    Task {
                        await relayAccountCoordinator.requestMagicLink(email: email)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(relayAccountCoordinator.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            statusLine
        }
    }

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish Linking")
                .font(.headline)

            if let email = relayAccountCoordinator.currentUserEmail ?? relayAccountCoordinator.displayedEntitlements?.user?.email {
                Text("Signed in as \(email).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(subscriptionManager.isLinkingPendingAppStoreSubscription ? "Linking…" : "Link Subscription") {
                Task {
                    await subscriptionManager.linkPendingAppStoreSubscriptionIfNeeded()
                    if subscriptionManager.pendingAppStoreSubscriptionLink == nil {
                        subscriptionManager.dismissAppStoreAccountLinkSheet()
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(subscriptionManager.isLinkingPendingAppStoreSubscription)

            statusLine
        }
    }

    private var accountConnectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let email = relayAccountCoordinator.currentUserEmail ?? relayAccountCoordinator.displayedEntitlements?.user?.email {
                Text("Connected as \(email).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
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
            if presentation == .subscriptionLink, let message = subscriptionManager.lastPurchaseStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func waitingForEmailContent(email: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check your email for a Relay sign-in link sent to \(email).")
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
