import SwiftUI

#if os(macOS)
struct LicensingGateView: View {
    @EnvironmentObject private var licenseCoordinator: LicenseCoordinator
    @Environment(\.dismiss) private var dismiss

    let showsStatusView: Bool
    let secondaryButtonTitle: String?
    let secondaryButtonAction: (() -> Void)?
    let showsCloseButton: Bool

    @State private var showingActivateSheet = false
    @State private var selectedPlanId: String? = nil
    @State private var showDetails = false
    @State private var didAppear = false

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
        showsStatusView: Bool = true,
        secondaryButtonTitle: String? = nil,
        secondaryButtonAction: (() -> Void)? = nil,
        showsCloseButton: Bool = true
    ) {
        self.showsStatusView = showsStatusView
        self.secondaryButtonTitle = secondaryButtonTitle
        self.secondaryButtonAction = secondaryButtonAction
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        VStack(spacing: 16) {
            headerView
                .opacity(didAppear ? 1.0 : 0.0)
                .offset(y: didAppear ? 0 : 10)
                .animation(.easeOut(duration: 0.35), value: didAppear)

            if showsStatusView {
                statusView
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 12)
                    .animation(.easeOut(duration: 0.4).delay(0.05), value: didAppear)
            }

            tierCards
                .opacity(didAppear ? 1.0 : 0.0)
                .offset(y: didAppear ? 0 : 16)
                .animation(.easeOut(duration: 0.45).delay(0.1), value: didAppear)

            if !licenseCoordinator.isLicensed {
                planSelectorView
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 12)
                    .animation(.easeOut(duration: 0.45).delay(0.15), value: didAppear)

                actionButtons
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 8)
                    .animation(.easeOut(duration: 0.35).delay(0.2), value: didAppear)

                HStack(spacing: 12) {
                    Link("Privacy Policy", destination: RelayLicensingConfig.privacyPolicyURL)
                    Link("Terms & Conditions", destination: RelayLicensingConfig.termsURL)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if showDetails, let entitlement = licenseCoordinator.entitlement {
                entitlementDetails(entitlement)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            manageLinksView
                .opacity(didAppear ? 1.0 : 0.0)
                .offset(y: didAppear ? 0 : 6)
                .animation(.easeOut(duration: 0.35).delay(0.25), value: didAppear)
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 14, y: 6)
        .sheet(isPresented: $showingActivateSheet) {
            ActivateLicenseSheet()
                .environmentObject(licenseCoordinator)
        }
        .task {
            await licenseCoordinator.loadPlans()
        }
        .onChange(of: licenseCoordinator.availablePlans, initial: false) { _, plans in
            if selectedPlanId == nil {
                selectedPlanId = plans.first?.id
            }
        }
        .onAppear {
            licenseCoordinator.clearLastError()
            withAnimation(.easeOut(duration: 0.35)) {
                didAppear = true
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 6) {
            Text("Unlock more with")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)
            Text("Pro")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(brandGradient)
                .shadow(color: Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.6), radius: 4)

            Spacer()

            if showsCloseButton {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var tierCards: some View {
        HStack(spacing: 18) {
            tierCard(
                title: "Free",
                subtitle: "Great for getting started",
                features: [
                    "1 tab",
                    "Unlimited tiles",
                    "Set modules & features",
                    "Planning Center integration"
                ],
                isPrimary: false
            )

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
        }
    }

    private var planSelectorView: some View {
        Group {
            if licenseCoordinator.plansAreLoading {
                ProgressView("Loading plans…")
                    .padding(.vertical, 12)
            } else if let error = licenseCoordinator.plansLoadErrorMessage {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry Plans") {
                        Task { await licenseCoordinator.loadPlans(force: true) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(licenseCoordinator.availablePlans) { plan in
                        planRow(plan: plan, isSelected: plan.id == selectedPlanId) {
                            selectedPlanId = plan.id
                        }
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let secondaryButtonTitle, let secondaryButtonAction {
                Button(secondaryButtonTitle) {
                    secondaryButtonAction()
                }
                .buttonStyle(UpgradePillButtonStyle(isPrimary: false))
            } else {
                Button("Activate License") {
                    showingActivateSheet = true
                }
                .buttonStyle(UpgradePillButtonStyle(isPrimary: false))
            }

            Button(primaryButtonTitle) {
                guard let selectedPlan else { return }
                Task { await licenseCoordinator.openCheckout(planId: selectedPlan.id) }
            }
            .buttonStyle(UpgradePillButtonStyle(isPrimary: true))
            .disabled(selectedPlan == nil)
        }
    }

    private var primaryButtonTitle: String {
        guard let selectedPlan else {
            return "Subscribe"
        }
        let price = selectedPlan.priceFormatted
        if selectedPlan.hasFreeTrial == true {
            return "Try It Free • \(price)"
        }
        return "Upgrade • \(price)"
    }

    private var manageLinksView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("Manage Subscription") {
                    Task { await licenseCoordinator.openManageSubscriptions() }
                }
                .dashboardLinkButtonStyle()

                if showsStatusView {
                    Button(showDetails ? "Hide Details" : "Show Details") {
                        showDetails.toggle()
                    }
                    .dashboardLinkButtonStyle()
                }

                Spacer()

                if let message = licenseCoordinator.lastErrorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            if case .gracePeriod = licenseCoordinator.status {
                Button("Continue Offline") { dismiss() }
                    .dashboardLinkButtonStyle()
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch licenseCoordinator.status {
        case .unlicensed:
            statusBadge(title: "Unlicensed", detail: "Enter a license key or start a subscription.", color: .orange)
        case .activating:
            statusBadge(title: "Activating…", detail: "Contacting license server.", color: .blue)
        case .active:
            statusBadge(title: "Active", detail: "License validated.", color: .green) {
                Button("Deactivate") {
                    Task { await licenseCoordinator.deactivateThisMac() }
                }
                .buttonStyle(.bordered)
            }
        case .gracePeriod(_, let expiresAt):
            let until = expiresAt?.formatted(date: .abbreviated, time: .shortened) ?? "soon"
            statusBadge(title: "Offline Grace", detail: "Valid until \(until).", color: .yellow) {
                Button("Deactivate") {
                    Task { await licenseCoordinator.deactivateThisMac() }
                }
                .buttonStyle(.bordered)
            }
        case .expired:
            statusBadge(title: "Expired", detail: "Your license has expired.", color: .red)
        case .disabled:
            statusBadge(title: "Disabled", detail: "This license is disabled.", color: .red)
        case .networkError:
            statusBadge(title: "Offline", detail: "Could not reach licensing server.", color: .yellow)
        case .unknown:
            statusBadge(title: "Unknown", detail: "Check your license status.", color: .secondary)
        }
    }

    private func statusBadge(
        title: String,
        detail: String,
        color: Color,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.5), lineWidth: 1)
        )
    }

    private func entitlementDetails(_ entitlement: LicenseEntitlement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("License Details")
                .font(.headline)
            detailRow(label: "Product", value: displayValue(entitlement.productName))
            detailRow(label: "Plan", value: displayValue(entitlement.variantName))
            detailRow(label: "Email", value: displayValue(entitlement.customerEmail))
            detailRow(label: "License", value: licenseDisplay(entitlement))
            detailRow(label: "Activations", value: activationUsageSummary(
                used: entitlement.activationUsageCount,
                limit: entitlement.activationLimit
            ) ?? "—")
            detailRow(label: "Last Checked", value: formattedDate(entitlement.validatedAt))
            detailRow(label: "Expires", value: expiresDisplay(entitlement))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .frame(width: 110, alignment: .leading)
            Text(value)
            Spacer()
        }
    }

    private func displayValue(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value! : "—"
    }

    private func formattedDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "—"
    }

    private func licenseDisplay(_ entitlement: LicenseEntitlement) -> String {
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

    private func activationUsageSummary(used: Int?, limit: Int?) -> String? {
        guard let used, let limit, limit > 0 else { return nil }
        return "\(used)/\(limit) activations used"
    }

    private func expiresDisplay(_ entitlement: LicenseEntitlement) -> String {
        if let expiresAt = entitlement.expiresAt {
            return formattedDate(expiresAt)
        }
        if entitlement.isActive {
            return "Active subscription"
        }
        return "—"
    }

    private var selectedPlan: LicensingPlan? {
        guard let selectedPlanId else { return nil }
        return licenseCoordinator.availablePlans.first { $0.id == selectedPlanId }
    }

    private func trialLabel(for plan: LicensingPlan) -> String {
        if let interval = plan.trialInterval,
           let count = plan.trialIntervalCount,
           count > 0 {
            return "Includes \(count) \(interval) free trial"
        }
        return "Includes free trial"
    }

    private func planRow(
        plan: LicensingPlan,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let borderColor = isSelected ? Color.blue : Color.white.opacity(0.12)
        let subtitle = plan.billingLabel.isEmpty ? "Billing" : plan.billingLabel
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.displayName)
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                if plan.hasFreeTrial == true {
                    Text(trialLabel(for: plan))
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(plan.priceFormatted)
                    .font(.headline)
                    .foregroundStyle(.white)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : secondaryTextColor)
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
        .onTapGesture { action() }
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(brandGradient, lineWidth: 2.5)
                    .opacity(0.8)
                    .shadow(color: Color(red: 0.2, green: 0.45, blue: 1.0).opacity(0.18), radius: 6)
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
            .foregroundStyle(isPrimary ? Color.white : Color.white.opacity(0.85))
            .clipShape(Capsule())
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPrimary {
            return isPressed ? Color.blue.opacity(0.85) : Color.blue
        }
        return isPressed ? Color.white.opacity(0.14) : Color.white.opacity(0.08)
    }
}
#else
struct LicensingGateView: View {
    var body: some View { EmptyView() }
}
#endif
