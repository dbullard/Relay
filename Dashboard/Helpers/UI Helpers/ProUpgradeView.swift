import SwiftUI
import StoreKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ProUpgradeView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var selectedProductID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("Go Pro")
                    .font(.title2.bold())
                ProBadgeView(fontSize: 12)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }

            Text("Unlock all modules, unlimited tabs, and ProPresenter connectivity.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if subscriptionManager.products.isEmpty {
                ProgressView("Loading plans…")
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedProducts, id: \.id) { product in
                        planRow(product: product, isSelected: product.id == selectedProductID)
                            .onTapGesture {
                                selectedProductID = product.id
                            }
                    }
                }

                Button(primaryButtonTitle) {
                    guard let product = selectedProduct else { return }
                    Task { await performPurchase(for: product) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 12) {
                Button("Restore Purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
#if os(macOS)
                .dashboardLinkButtonStyle()
#else
                .buttonStyle(.bordered)
#endif

                Button("Refresh Entitlements") {
                    Task { await subscriptionManager.refreshEntitlements(forceSync: true) }
                }
#if os(macOS)
                .dashboardLinkButtonStyle()
#else
                .buttonStyle(.bordered)
#endif

                Button("Manage Subscription") {
                    openManageSubscriptions()
                }
#if os(macOS)
                .dashboardLinkButtonStyle()
#else
                .buttonStyle(.bordered)
#endif

                Spacer()

                if let message = subscriptionManager.lastErrorMessage {
                    PurchaseErrorNotice(message: message)
                }
            }

            if let status = subscriptionManager.lastPurchaseStatusMessage {
                HStack(spacing: 8) {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let at = subscriptionManager.lastPurchaseStatusAt {
                        Text("• \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.refreshEntitlements()
            if selectedProductID == nil {
                selectedProductID = subscriptionManager.products.first { $0.id == subscriptionManager.productIDs.first }?.id
                    ?? subscriptionManager.products.first?.id
            }
        }
        .onChange(of: subscriptionManager.hasPro, initial: true) { _, newValue in
            if newValue {
                dismiss()
            }
        }
        .onDisappear {
            subscriptionManager.presentQueuedAppStoreAccountLinkSheetIfNeeded()
        }
    }

    private var sortedProducts: [Product] {
        subscriptionManager.products.sorted { lhs, rhs in
            if lhs.id == subscriptionManager.productIDs.first { return true }
            if rhs.id == subscriptionManager.productIDs.first { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var selectedProduct: Product? {
        if let id = selectedProductID {
            return subscriptionManager.products.first { $0.id == id }
        }
        return subscriptionManager.products.first
    }

    private var primaryButtonTitle: String {
        if let product = selectedProduct {
            let price = product.displayPrice
            if hasIntroOffer(product) {
                return "Try It Free • \(price)"
            }
            return "Upgrade • \(price)"
        }
        return "Upgrade"
    }

    private func hasIntroOffer(_ product: Product) -> Bool {
        product.subscription?.introductoryOffer != nil
    }

    private func periodLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayName }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }
        return "\(period.value) \(unit)"
    }

    private func planRow(product: Product, isSelected: Bool) -> some View {
        let borderColor = isSelected ? Color.blue : Color.white.opacity(0.12)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline)
                Text(periodLabel(product))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if hasIntroOffer(product) {
                    Text("Includes free trial")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(product.displayPrice)
                .font(.headline)
                .foregroundStyle(.white)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1.5)
        )
    }

    private func openManageSubscriptions() {
#if os(macOS)
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(url)
        }
#else
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
#endif
    }

    @MainActor
    private func performPurchase(for product: Product) async {
        subscriptionManager.setPurchaseStatus("Starting App Store purchase for \(product.displayName)…")
        subscriptionManager.logPurchase("Starting purchase for product \(product.id)")

        do {
            let result = try await purchase(product)
            await subscriptionManager.handlePurchaseResult(result, for: product, promptForLinkUI: true)
        } catch {
            subscriptionManager.handlePurchaseFailure(error, for: product)
        }
    }
}
