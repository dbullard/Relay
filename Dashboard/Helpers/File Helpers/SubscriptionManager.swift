import Foundation
import Combine
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    let productIDs: [String] = [
        "relay.pro.subscription",
        "relay.pro.subscription.yearly"
    ]
    private let preferredProductID: String = "relay.pro.subscription"
    private let overrideKey: String = "subscription_forcePro"
    private let pendingAppStoreLinkKey: String = "relay_pending_app_store_subscription_v1"
    private let observedAppStoreOriginalTransactionKey: String = "relay_observed_app_store_original_transaction_id"
    private let accountLinkedAppStoreOriginalTransactionKey: String = "relay_account_linked_app_store_original_transaction_id"
    private var relayAccountCoordinator: RelayAccountCoordinator { RelayAccountCoordinator.shared }

    @Published private(set) var hasPro: Bool = true
    @Published private(set) var legacyLicensePro: Bool = false
    @Published private(set) var relayAccountPro: Bool = false
    @Published private(set) var effectivePro: Bool = true
    @Published private(set) var isChecking: Bool = false
    @Published private(set) var pendingAppStoreSubscriptionLink: RelayPendingAppStoreSubscription?
    @Published private(set) var isLinkingPendingAppStoreSubscription: Bool = false
    @Published var isShowingAppStoreAccountLinkSheet: Bool = false
    @Published private(set) var lastErrorMessage: String? = nil
    @Published private(set) var lastPurchaseStatusMessage: String? = nil
    @Published private(set) var lastPurchaseStatusAt: Date? = nil
    @Published private(set) var products: [Product] = []

    private var updatesTask: Task<Void, Never>?
    private var licensingStatusTask: Task<Void, Never>?
    private var licensingBusyTask: Task<Void, Never>?
    private var licensingErrorTask: Task<Void, Never>?
    private var relayAccountTask: Task<Void, Never>?
    private var hasQueuedAppStoreAccountLinkSheet: Bool = false
    private var refreshTask: Task<Void, Never>?

    var isUsingRelayAccountAppStoreEntitlement: Bool {
        guard relayAccountPro,
              !legacyLicensePro,
              let entitlements = relayAccountCoordinator.displayedEntitlements,
              RelayAccountLicenseProvider.resolve(from: entitlements) == .appStore else {
            return false
        }

        return Self.shouldTrustRelayAccountAppStoreEntitlement(
            legacyLicensePro: legacyLicensePro,
            relayAccountProvider: .appStore,
            hasLinkedLocalAppStorePurchase: hasLinkedLocalAppStorePurchase
        )
    }

    var isSuppressingStaleLocalAppStoreEntitlement: Bool {
        guard relayAccountPro,
              !legacyLicensePro,
              let entitlements = relayAccountCoordinator.displayedEntitlements,
              RelayAccountLicenseProvider.resolve(from: entitlements) == .appStore else {
            return false
        }

        return !Self.shouldTrustRelayAccountAppStoreEntitlement(
            legacyLicensePro: legacyLicensePro,
            relayAccountProvider: .appStore,
            hasLinkedLocalAppStorePurchase: hasLinkedLocalAppStorePurchase
        )
    }

    private init() {
#if !DEBUG
        UserDefaults.standard.removeObject(forKey: overrideKey)
#endif
        pendingAppStoreSubscriptionLink = Self.loadPendingAppStoreSubscription()
        // Relay is free: Pro is always on, so there is no license or Relay Account
        // observation and no StoreKit transaction listener to start here.
    }

    deinit {
        updatesTask?.cancel()
        updatesTask = nil
        refreshTask?.cancel()
        licensingStatusTask?.cancel()
        licensingBusyTask?.cancel()
        licensingErrorTask?.cancel()
        relayAccountTask?.cancel()
    }

    func refreshEntitlements() async {
        await enqueueRefreshEntitlements(forceSync: false, promptForLinkUI: false)
    }

    func refreshEntitlements(forceSync: Bool) async {
        await enqueueRefreshEntitlements(forceSync: forceSync, promptForLinkUI: false)
    }

    func presentAppStoreAccountLinkSheet() {
        guard pendingAppStoreSubscriptionLink != nil else { return }
        hasQueuedAppStoreAccountLinkSheet = false
        isShowingAppStoreAccountLinkSheet = true
    }

    func dismissAppStoreAccountLinkSheet() {
        isShowingAppStoreAccountLinkSheet = false
    }

    func queueAppStoreAccountLinkSheetPresentation() {
        guard pendingAppStoreSubscriptionLink != nil else { return }
        hasQueuedAppStoreAccountLinkSheet = true
    }

    func presentQueuedAppStoreAccountLinkSheetIfNeeded() {
        guard hasQueuedAppStoreAccountLinkSheet,
              pendingAppStoreSubscriptionLink != nil,
              !isShowingAppStoreAccountLinkSheet else {
            return
        }
        hasQueuedAppStoreAccountLinkSheet = false
        isShowingAppStoreAccountLinkSheet = true
    }

    func linkPendingAppStoreSubscriptionIfNeeded() async {
        guard RelayAccountConfig.isAuthEnabled else {
            logPurchase("Skipping App Store account link: Relay Account auth disabled.")
            return
        }
        guard let pending = pendingAppStoreSubscriptionLink else {
            logPurchase("Skipping App Store account link: no pending App Store subscription payload.")
            return
        }
        guard relayAccountCoordinator.isSignedIn else {
            logPurchase("Skipping App Store account link: no signed-in Relay Account session.")
            return
        }
        guard !isLinkingPendingAppStoreSubscription else {
            logPurchase("Skipping App Store account link: link already in progress.")
            return
        }

        isLinkingPendingAppStoreSubscription = true
        setPurchaseStatus("Linking App Store subscription to Relay Account…")
        defer { isLinkingPendingAppStoreSubscription = false }

        do {
            logPurchase("Linking App Store subscription \(pending.originalTransactionId) to Relay Account…")
            try await relayAccountCoordinator.linkAppStoreSubscription(pending)
            UserDefaults.standard.set(pending.originalTransactionId, forKey: accountLinkedAppStoreOriginalTransactionKey)
            clearPendingAppStoreSubscriptionLink()
            isShowingAppStoreAccountLinkSheet = false
            lastErrorMessage = nil
            setPurchaseStatus("App Store subscription linked to Relay Account.")
        } catch {
            recordPurchaseError("App Store account link failed: \(error.localizedDescription)")
        }
    }

    private func enqueueRefreshEntitlements(forceSync: Bool, promptForLinkUI: Bool) async {
        // Relay is free: there is nothing to refresh. Pro is always on.
        isChecking = false
        updateEffectivePro()
    }

    private func refreshEntitlements(forceSync: Bool, promptForLinkUI: Bool) async {
#if os(macOS)
        if RelayLicensingConfig.isDirectMacDistribution {
            isChecking = true
            if let override = debugProOverride() {
                legacyLicensePro = override
                updateEffectivePro()
                setPurchaseStatus(override ? "Debug override: Pro enabled." : "Debug override: Pro disabled.")
                isChecking = false
                return
            }
            await LicenseCoordinator.shared.validateLicense(force: forceSync)
            isChecking = false
            return
        }
#endif
        isChecking = true
        if let override = debugProOverride() {
            legacyLicensePro = override
            updateEffectivePro()
            setPurchaseStatus(override ? "Debug override: Pro enabled." : "Debug override: Pro disabled.")
            isChecking = false
            return
        }

#if os(iOS)
        if forceSync {
            do {
                logPurchase("Syncing App Store entitlements before refresh…")
                try await AppStore.sync()
            } catch {
                logPurchase("App Store sync failed before entitlement refresh: \(error.localizedDescription)")
                recordPurchaseError("App Store sync failed: \(error.localizedDescription)")
            }
        }
#endif

        var hasActive = false
        var activeTransaction: Transaction?
        var entitlementSummaries: [String] = []

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard productIDs.contains(transaction.productID) else { continue }
                entitlementSummaries.append(transactionSummary(transaction))
                if isActiveEntitlement(transaction) {
                    hasActive = true
                    activeTransaction = transaction
                }
            case .unverified(let transaction, let error):
                guard productIDs.contains(transaction.productID) else { continue }
                entitlementSummaries.append(
                    "unverified product=\(transaction.productID) tx=\(transaction.id) original=\(transaction.originalID) error=\(error.localizedDescription)"
                )
            }
        }

        if entitlementSummaries.isEmpty {
            logPurchase("Current entitlements: none")
        } else {
            logPurchase("Current entitlements: \(entitlementSummaries.joined(separator: " | "))")
        }

        if let activeTransaction {
            logPurchase("Resolved active entitlement: \(transactionSummary(activeTransaction))")
        }

        if hasActive {
            lastErrorMessage = nil
        }

        if let activeTransaction {
            updatePendingAppStoreSubscriptionLink(from: activeTransaction)
        } else {
            clearPendingAppStoreSubscriptionLink()
        }

        legacyLicensePro = hasActive
        updateEffectivePro()
        setPurchaseStatus(hasActive ? "Entitlements refreshed: Pro active." : "Entitlements refreshed: Pro inactive.")

        if hasActive {
            if relayAccountCoordinator.isSignedIn, pendingAppStoreSubscriptionLink != nil {
                await linkPendingAppStoreSubscriptionIfNeeded()
            } else if promptForLinkUI, pendingAppStoreSubscriptionLink != nil {
                queueAppStoreAccountLinkSheetPresentation()
            }
        }

        isChecking = false
    }

    func loadProducts() async {
#if os(macOS)
        if RelayLicensingConfig.isDirectMacDistribution {
            return
        }
#endif
        do {
            let fetched = try await Product.products(for: productIDs)
            products = fetched
        } catch {
            lastErrorMessage = error.localizedDescription
            recordPurchaseError("Failed to load products: \(error.localizedDescription)")
        }
    }

    func purchasePro() async {
#if os(macOS)
        if RelayLicensingConfig.isDirectMacDistribution {
            setPurchaseStatus("Use the licensing screen to start a subscription.")
            return
        }
#endif
        if products.isEmpty {
            await loadProducts()
        }
        let product = products.first { $0.id == preferredProductID } ?? products.first
        guard let product else {
            lastErrorMessage = "Pro subscription not available."
            return
        }

        setPurchaseStatus("Starting App Store purchase for \(product.displayName)…")
        logPurchase("Starting purchase for product \(product.id)")
        do {
            let result = try await product.purchase()
            await handlePurchaseResult(result, for: product, promptForLinkUI: true)
        } catch {
            handlePurchaseFailure(error, for: product)
        }
    }

    func purchase(product: Product) async {
#if os(macOS)
        if RelayLicensingConfig.isDirectMacDistribution {
            setPurchaseStatus("Use the licensing screen to start a subscription.")
            return
        }
#endif
        setPurchaseStatus("Starting App Store purchase for \(product.displayName)…")
        logPurchase("Starting purchase for product \(product.id)")
        do {
            let result = try await product.purchase()
            await handlePurchaseResult(result, for: product, promptForLinkUI: true)
        } catch {
            handlePurchaseFailure(error, for: product)
        }
    }

    func handlePurchaseResult(
        _ result: Product.PurchaseResult,
        for product: Product,
        promptForLinkUI: Bool
    ) async {
        switch result {
        case .success(let verification):
            switch verification {
            case .verified:
                logPurchase("Purchase verified for product \(product.id)")
                setPurchaseStatus("Purchase succeeded. Refreshing entitlements…")
                await refreshEntitlements(forceSync: true, promptForLinkUI: promptForLinkUI)
            case .unverified(_, let error):
                logPurchase("Purchase returned unverified transaction for product \(product.id): \(error.localizedDescription)")
                recordPurchaseError("Purchase verification failed: \(error.localizedDescription)")
            }
        case .userCancelled:
            logPurchase("Purchase cancelled for product \(product.id)")
            setPurchaseStatus("Purchase cancelled.")
        case .pending:
            logPurchase("Purchase pending for product \(product.id)")
            setPurchaseStatus("Purchase pending approval.")
        @unknown default:
            logPurchase("Purchase returned unknown result for product \(product.id)")
            setPurchaseStatus("Purchase returned an unknown result.")
        }
    }

    func handlePurchaseFailure(_ error: Error, for product: Product) {
        logPurchase("Purchase failed for product \(product.id): \(error.localizedDescription)")
        recordPurchaseError("Purchase failed: \(error.localizedDescription)")
    }

    func restorePurchases() async {
#if os(macOS)
        if RelayLicensingConfig.isDirectMacDistribution {
            setPurchaseStatus("Refreshing license status…")
            await refreshEntitlements(forceSync: true)
            return
        }
#endif
        do {
            setPurchaseStatus("Restoring purchases…")
            try await AppStore.sync()
            await refreshEntitlements(forceSync: false, promptForLinkUI: true)
        } catch {
            recordPurchaseError("Restore failed: \(error.localizedDescription)")
        }
    }

    private func observeTransactions() async {
#if os(macOS)
        if RelayLicensingConfig.isDirectMacDistribution { return }
#endif
        for await _ in Transaction.updates {
            await refreshEntitlements(forceSync: false)
        }
    }

    func applyDebugOverride() {
        Task { await refreshEntitlements(forceSync: false) }
    }

    private func updatePendingAppStoreSubscriptionLink(from transaction: Transaction) {
        let originalTransactionId = String(transaction.originalID)
        persistObservedLocalAppStorePurchase(originalTransactionId)

        if relayAccountCoordinator.isSignedIn {
            if UserDefaults.standard.string(forKey: accountLinkedAppStoreOriginalTransactionKey) == originalTransactionId {
                clearPendingAppStoreSubscriptionLink()
                return
            }
        } else if UserDefaults.standard.string(forKey: accountLinkedAppStoreOriginalTransactionKey) == originalTransactionId {
            clearPendingAppStoreSubscriptionLink()
            return
        }

        let pending = RelayPendingAppStoreSubscription(
            originalTransactionId: originalTransactionId,
            transactionId: String(transaction.id),
            productId: transaction.productID,
            expirationDate: transaction.expirationDate,
            isActive: true
        )

        guard pending != pendingAppStoreSubscriptionLink else { return }
        pendingAppStoreSubscriptionLink = pending
        persistPendingAppStoreSubscription()
    }

    private func clearPendingAppStoreSubscriptionLink() {
        guard pendingAppStoreSubscriptionLink != nil else { return }
        pendingAppStoreSubscriptionLink = nil
        UserDefaults.standard.removeObject(forKey: pendingAppStoreLinkKey)
    }

    private func persistPendingAppStoreSubscription() {
        guard let pendingAppStoreSubscriptionLink,
              let encoded = try? JSONEncoder().encode(pendingAppStoreSubscriptionLink) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: pendingAppStoreLinkKey)
    }

    private func persistObservedLocalAppStorePurchase(_ originalTransactionId: String) {
        let normalized = originalTransactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        UserDefaults.standard.set(normalized, forKey: observedAppStoreOriginalTransactionKey)
    }

    private static func loadPendingAppStoreSubscription() -> RelayPendingAppStoreSubscription? {
        guard let data = UserDefaults.standard.data(forKey: "relay_pending_app_store_subscription_v1") else {
            return nil
        }
        return try? JSONDecoder().decode(RelayPendingAppStoreSubscription.self, from: data)
    }

    private func isActiveEntitlement(_ transaction: Transaction) -> Bool {
        if transaction.revocationDate != nil { return false }
        if transaction.isUpgraded { return false }
        if let expiration = transaction.expirationDate, expiration <= Date() {
            return false
        }
        return true
    }

    private func debugProOverride() -> Bool? {
#if DEBUG
        guard let raw = UserDefaults.standard.object(forKey: overrideKey) as? Int else {
            return nil
        }
        switch raw {
        case 1:
            return false
        case 2:
            return true
        default:
            return nil
        }
#else
        return nil
#endif
    }

    func setPurchaseStatus(_ message: String) {
        lastPurchaseStatusMessage = message
        lastPurchaseStatusAt = Date()
        logPurchase(message)
    }

    private func recordPurchaseError(_ message: String) {
        lastErrorMessage = message
        setPurchaseStatus(message)
        RelayDiagnosticsStore.shared.recordError(message, tag: "IAP")
    }

    func logPurchase(_ message: String) {
        print("[IAP] \(message)")
    }

    private func transactionSummary(_ transaction: Transaction) -> String {
        let expiration = transaction.expirationDate?.formatted(date: .abbreviated, time: .standard) ?? "nil"
        let revoked = transaction.revocationDate?.formatted(date: .abbreviated, time: .standard) ?? "nil"
        return "product=\(transaction.productID) tx=\(transaction.id) original=\(transaction.originalID) purchased=\(transaction.purchaseDate.formatted(date: .abbreviated, time: .standard)) expires=\(expiration) revoked=\(revoked) upgraded=\(transaction.isUpgraded)"
    }

    nonisolated static func resolveEffectivePro(
        legacyLicensePro: Bool,
        relayAccountPro: Bool,
        relayAccountAuthEnabled: Bool
    ) -> Bool {
        legacyLicensePro || (relayAccountAuthEnabled && relayAccountPro)
    }

    nonisolated static func shouldTrustRelayAccountAppStoreEntitlement(
        legacyLicensePro: Bool,
        relayAccountProvider: RelayAccountLicenseProvider?,
        hasLinkedLocalAppStorePurchase: Bool
    ) -> Bool {
        guard relayAccountProvider == .appStore else { return true }
        guard !legacyLicensePro else { return true }
        guard hasLinkedLocalAppStorePurchase else { return true }
        return false
    }

    nonisolated static func hasActiveLinkedAppStoreSubscription(
        _ entitlements: RelayAccountEntitlementsResponse?
    ) -> Bool {
        entitlements?.subscriptions.contains(where: { subscription in
            let provider = subscription.provider
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard provider == "app_store" else { return false }

            let status = subscription.status
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if status == "active" || status == "trialing" || status == "on_trial" || status == "billing_grace_period" {
                return true
            }

            if status == "cancelled", let currentPeriodEnd = subscription.currentPeriodEnd {
                return currentPeriodEnd > Date()
            }

            return false
        }) ?? false
    }

    private func updateEffectivePro() {
        // Relay is free: every user has Pro. The old license and Relay Account
        // inputs (legacyLicensePro, relayAccountPro) no longer affect the result,
        // and the DEBUG override can no longer switch Pro off.
        effectivePro = true
        hasPro = true
    }

    private var hasLinkedLocalAppStorePurchase: Bool {
        guard let originalTransactionId = UserDefaults.standard.string(forKey: observedAppStoreOriginalTransactionKey) else {
            return false
        }
        return !originalTransactionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

#if os(macOS)
    private func attachToLicenseCoordinator() {
        let coordinator = LicenseCoordinator.shared
        legacyLicensePro = coordinator.isLicensed
        isChecking = coordinator.isBusy
        lastErrorMessage = coordinator.lastErrorMessage
        updateEffectivePro()

        licensingStatusTask = Task { [weak self] in
            guard let self else { return }
            for await value in coordinator.$isLicensed.values {
                legacyLicensePro = value
                updateEffectivePro()
            }
        }

        licensingBusyTask = Task { [weak self] in
            guard let self else { return }
            for await value in coordinator.$isBusy.values {
                if debugProOverride() != nil {
                    isChecking = false
                    continue
                }
                isChecking = value
            }
        }

        licensingErrorTask = Task { [weak self] in
            guard let self else { return }
            for await value in coordinator.$lastErrorMessage.values {
                lastErrorMessage = value
            }
        }
    }
#endif

    private func attachToRelayAccountCoordinator() {
        let coordinator = RelayAccountCoordinator.shared
        relayAccountPro = RelayAccountConfig.isAuthEnabled ? coordinator.relayAccountPro : false
        updateEffectivePro()

        relayAccountTask = Task { [weak self] in
            guard let self else { return }
            for await value in coordinator.$relayAccountPro.values {
                relayAccountPro = RelayAccountConfig.isAuthEnabled ? value : false
                updateEffectivePro()
            }
        }
    }
}
