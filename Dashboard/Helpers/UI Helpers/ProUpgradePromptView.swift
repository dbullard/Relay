//
//  ProUpgradePromptView.swift
//  Relay
//
//  Created by Codex on 3/4/26.
//

import SwiftUI
import StoreKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ProUpgradePromptView: View {
    let title: String
    let buttonTitle: String
    let action: () -> Void
    let secondaryButtonTitle: String?
    let secondaryAction: (() -> Void)?
    let animateOnAppear: Bool
    let showPlanSelector: Bool
    let showManageLinks: Bool
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var selectedProductID: String? = nil
    @State private var didAppear: Bool = false

    private let primaryTextColor = Color.white
    private let secondaryTextColor = Color.white.opacity(0.7)

    private let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.29, green: 0.35, blue: 0.98),
            Color(red: 0.19, green: 0.55, blue: 1.0),
            Color(red: 0.16, green: 0.84, blue: 0.96)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    init(
        title: String = "Unlock more with Pro",
        buttonTitle: String = "Subscribe",
        secondaryButtonTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        animateOnAppear: Bool = false,
        showPlanSelector: Bool = false,
        showManageLinks: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.buttonTitle = buttonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.secondaryAction = secondaryAction
        self.animateOnAppear = animateOnAppear
        self.showPlanSelector = showPlanSelector
        self.showManageLinks = showManageLinks
        self.action = action
    }

    var body: some View {
#if os(macOS)
        if RelayLicensingConfig.isDirectMacDistribution {
            LicensingGateView(showsStatusView: false)
        } else {
            promptContent
        }
#else
        promptContent
#endif
    }

    private var promptContent: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Unlock more with")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                Text("Pro")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(brandGradient)
                    .shadow(color: Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.6), radius: 4)
            }
            .opacity(didAppear ? 1.0 : 0.0)
            .offset(y: didAppear ? 0 : 10)
            .animation(animateOnAppear ? .easeOut(duration: 0.35) : .none, value: didAppear)

            HStack(spacing: 18) {
                tierCard(
                    title: "Free",
                    subtitle: "Great for getting started",
                    features: [
                        "1 tab",
                        "Unlimited tiles",
                        "Set modules & features",
                        "Planning Center integration",
                    ],
                    isPrimary: false
                )
                .opacity(didAppear ? 1.0 : 0.0)
                .offset(y: didAppear ? 0 : 16)
                .animation(animateOnAppear ? .easeOut(duration: 0.45).delay(0.08) : .none, value: didAppear)

                tierCard(
                    title: "Pro",
                    subtitle: "Full Relay experience",
                    features: [
                        "Unlimited tabs",
                        "All modules and features",
                        "Automations",
                        "External integrations"
                    ],
                    isPrimary: true
                )
                .opacity(didAppear ? 1.0 : 0.0)
                .offset(y: didAppear ? 0 : 16)
                .animation(animateOnAppear ? .easeOut(duration: 0.45).delay(0.16) : .none, value: didAppear)
            }

            if showPlanSelector {
                planSelectorView
            }

            HStack(spacing: 12) {
                if let secondaryButtonTitle, let secondaryAction {
                    Button(secondaryButtonTitle) {
                        secondaryAction()
                    }
                    .buttonStyle(UpgradePillButtonStyle(isPrimary: false))
                }

                Button(primaryButtonTitle) {
                    if showPlanSelector, let product = selectedProduct {
                        Task { await performPurchase(for: product) }
                    } else {
                        action()
                    }
                }
                .buttonStyle(UpgradePillButtonStyle(isPrimary: true))
            }
            .opacity(didAppear ? 1.0 : 0.0)
            .offset(y: didAppear ? 0 : 8)
            .animation(animateOnAppear ? .easeOut(duration: 0.35).delay(0.24) : .none, value: didAppear)

            if showManageLinks {
                manageLinksView
            }
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 14, y: 6)
        .onAppear {
            if animateOnAppear {
                didAppear = false
                DispatchQueue.main.async {
                    didAppear = true
                }
            } else {
                didAppear = true
            }
        }
        .task {
            guard showPlanSelector else { return }
            await subscriptionManager.loadProducts()
            await subscriptionManager.refreshEntitlements()
            if selectedProductID == nil {
                selectedProductID = subscriptionManager.products.first { $0.id == subscriptionManager.productIDs.first }?.id
                    ?? subscriptionManager.products.first?.id
            }
        }
        .onChange(of: subscriptionManager.hasPro, initial: false) { _, newValue in
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
        if showPlanSelector, let product = selectedProduct {
            let price = product.displayPrice
            if hasIntroOffer(product) {
                return "Try It Free • \(price)"
            }
            return "Upgrade • \(price)"
        }
        return buttonTitle
    }

    private func hasIntroOffer(_ product: Product) -> Bool {
        product.subscription?.introductoryOffer != nil
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

    private func introOfferLabel(_ product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer else { return nil }
        let period = offer.period
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }
        return "Includes \(period.value) \(unit) free trial"
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

    private var planSelectorView: some View {
        Group {
            if subscriptionManager.products.isEmpty {
                ProgressView("Loading plans…")
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedProducts, id: \.id) { product in
                        planRow(product: product, isSelected: product.id == selectedProductID)
                            .onTapGesture {
                                selectedProductID = product.id
                            }
                    }
                }
            }
        }
        .opacity(didAppear ? 1.0 : 0.0)
        .offset(y: didAppear ? 0 : 10)
        .animation(animateOnAppear ? .easeOut(duration: 0.35).delay(0.2) : .none, value: didAppear)
    }

    private func planRow(product: Product, isSelected: Bool) -> some View {
        let borderColor = isSelected ? Color.blue : Color.white.opacity(0.12)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Text(periodLabel(product))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                if let offerText = introOfferLabel(product) {
                    Text(offerText)
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundStyle(.white)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : secondaryTextColor)
        }
            .frame(minWidth: 68, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1.5)
        )
    }

    private var manageLinksView: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                HStack(spacing: 6) {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                    if let at = subscriptionManager.lastPurchaseStatusAt {
                        Text("• \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }
        }
        .padding(.top, 4)
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

    private func tierCard(
        title: String,
        subtitle: String,
        features: [String],
        isPrimary: Bool
    ) -> some View {
        let cardFill = Color(red: 0.18, green: 0.18, blue: 0.18)
        let borderStyle: AnyShapeStyle = isPrimary
            ? AnyShapeStyle(brandGradient)
            : AnyShapeStyle(Color.white.opacity(0.12))
        let checkmarkStyle: AnyShapeStyle = isPrimary
            ? AnyShapeStyle(brandGradient)
            : AnyShapeStyle(Color.secondary)
        let titleView: some View = {
            if isPrimary {
                return AnyView(
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(brandGradient)
                )
            }
            return AnyView(Text(title).font(.title3.weight(.semibold)))
        }()
        return VStack(alignment: .leading, spacing: 12) {
            titleView
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(secondaryTextColor)

            Divider()
                .opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(checkmarkStyle)
                        Text(feature)
                            .font(.callout)
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }
        }
        .foregroundStyle(primaryTextColor)
        .padding(14)
        .frame(width: 220, height: 200, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(borderStyle, lineWidth: 1.5)
                )
        )
        .overlay {
            if isPrimary {
                TimelineView(.animation) { context in
                    let phase = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 2.6)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(brandGradient, lineWidth: 2.5)
                        .opacity(0.35 + 0.65 * phase)
                        .shadow(color: Color(red: 0.2, green: 0.45, blue: 1.0).opacity(0.4 * phase), radius: 6)
                }
            }
        }
    }

}

private struct UpgradePillButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .foregroundStyle(isPrimary ? .white : .white.opacity(0.85))
            .clipShape(Capsule())
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPrimary {
            return isPressed ? Color.blue.opacity(0.85) : Color.blue
        }
        return isPressed ? Color.white.opacity(0.14) : Color.white.opacity(0.08)
    }
}

struct ProUpgradeOverlayView: View {
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(Color.black)
                    .ignoresSafeArea()
                ProUpgradePromptView(
                    buttonTitle: "Upgrade to Pro",
                    secondaryButtonTitle: "Continue with Free",
                    secondaryAction: {},
                    showPlanSelector: true,
                    showManageLinks: true
                ) {
                    action()
                }
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .allowsHitTesting(true)
    }
}
