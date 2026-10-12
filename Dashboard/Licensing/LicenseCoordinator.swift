import Foundation
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
final class LicenseCoordinator: ObservableObject {
    static let shared = LicenseCoordinator()

    @Published private(set) var status: LicenseStatus = .unlicensed
    @Published private(set) var entitlement: LicenseEntitlement? = nil
    @Published private(set) var isLicensed: Bool = false
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var lastErrorMessage: String? = nil
    @Published private(set) var availablePlans: [LicensingPlan] = []
    @Published private(set) var plansAreLoading: Bool = false
    @Published private(set) var plansLoadErrorMessage: String? = nil

    private let keychain = LicenseKeychainStore()
    private let gracePeriodDays: Int = 7
    private let validationIntervalSeconds: TimeInterval = 12 * 60 * 60
    private let validationDebounceSeconds: TimeInterval = 15

    private var licensingClient: RelayLicensingClient?
    private var licenseKey: String?
    private var instanceID: String?
    private var deviceFingerprint: String

    private var validateTask: Task<Void, Never>?
    private var activeMonitorTask: Task<Void, Never>?
    private var isValidationInFlight = false
    private var lastValidationRequestAt: Date?

    private let licenseKeyKey = "license_key"
    private let instanceIDKey = "license_instance_id"
    private let entitlementKey = "license_entitlement_json"
    private let deviceFingerprintKey = "license_device_fingerprint"
    private let keychainMigrationKey = "license_keychain_migration_v1"

    private init() {
        if RelayLicensingConfig.isDirectMacDistribution,
           !UserDefaults.standard.bool(forKey: keychainMigrationKey) {
            // Clear legacy items to avoid keychain prompts between signed builds.
            keychain.clearAllForService()
            UserDefaults.standard.set(true, forKey: keychainMigrationKey)
        }

        self.deviceFingerprint = keychain.loadString(forKey: deviceFingerprintKey) ?? UUID().uuidString
        if !keychain.saveString(deviceFingerprint, forKey: deviceFingerprintKey) {
            RelayDiagnosticsStore.shared.recordError(
                "Failed to persist device fingerprint", tag: "Keychain"
            )
        }

        licenseKey = keychain.loadString(forKey: licenseKeyKey)
        instanceID = keychain.loadString(forKey: instanceIDKey)
        entitlement = loadCachedEntitlement()
        status = statusFromCachedEntitlement(entitlement)
        isLicensed = status.isLicensed

        licensingClient = RelayLicensingClient(baseURL: RelayLicensingConfig.apiBaseURL)

        // Relay is free: no launch validation, periodic validation loop, or
        // app-activation validation. Old paid builds keep their own copy of this code.
    }

    deinit {
        validateTask?.cancel()
        activeMonitorTask?.cancel()
    }

    func activateLicense(licenseKey: String) async {
        guard RelayLicensingConfig.isDirectMacDistribution else { return }
        guard let client = licensingClient else {
            lastErrorMessage = "Licensing service is not configured."
            status = .unknown
            return
        }

        isBusy = true
        status = .activating
        lastErrorMessage = nil

        let request = LicensingActivateRequest(
            licenseKey: licenseKey,
            instanceName: instanceName(),
            deviceFingerprint: deviceFingerprint,
            appVersion: appVersion(),
            bundleID: bundleID(),
            platform: "macOS"
        )

        do {
            let response = try await client.activate(request: request)
            guard response.ok, let entitlement = response.entitlement else {
                throw RelayLicensingClient.ClientError(message: "Activation failed.")
            }
            let merged = mergeEntitlement(entitlement, meta: response.meta, previous: self.entitlement)
            self.licenseKey = licenseKey
            self.instanceID = merged.instanceID
            persist(licenseKey: licenseKey, instanceID: merged.instanceID, entitlement: merged)
            applyEntitlement(merged, gracePeriod: false)
        } catch {
            lastErrorMessage = error.localizedDescription
            status = .unknown
            RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Licensing")
        }

        isBusy = false
    }

    func validateLicense(force: Bool = false) async {
        guard RelayLicensingConfig.isDirectMacDistribution else { return }
        let now = Date()
        if isValidationInFlight { return }
        if !force,
           let lastValidationRequestAt,
           now.timeIntervalSince(lastValidationRequestAt) < validationDebounceSeconds {
            return
        }
        guard let client = licensingClient else {
            status = .unknown
            lastErrorMessage = "Licensing service is not configured."
            return
        }
        guard let licenseKey = licenseKey, let instanceID = instanceID else {
            status = .unlicensed
            isLicensed = false
            return
        }

        isValidationInFlight = true
        lastValidationRequestAt = now
        defer { isValidationInFlight = false }

        isBusy = true
        lastErrorMessage = nil

        let request = LicensingValidateRequest(
            licenseKey: licenseKey,
            instanceID: instanceID,
            deviceFingerprint: deviceFingerprint,
            appVersion: appVersion(),
            bundleID: bundleID(),
            platform: "macOS"
        )

        do {
            let response = try await client.validate(request: request)
            guard response.ok, let entitlement = response.entitlement else {
                throw RelayLicensingClient.ClientError(message: "Validation failed.")
            }
            let merged = mergeEntitlement(entitlement, meta: response.meta, previous: self.entitlement)
            persist(licenseKey: licenseKey, instanceID: merged.instanceID, entitlement: merged)
            applyEntitlement(merged, gracePeriod: response.gracePeriod ?? false)
        } catch {
            handleNetworkFailure(error)
        }

        isBusy = false
    }

    func deactivateThisMac() async {
        guard RelayLicensingConfig.isDirectMacDistribution else { return }
        guard let client = licensingClient,
              let licenseKey = licenseKey,
              let instanceID = instanceID
        else {
            clearStoredLicense()
            status = .unlicensed
            isLicensed = false
            return
        }

        isBusy = true
        lastErrorMessage = nil

        let request = LicensingDeactivateRequest(
            licenseKey: licenseKey,
            instanceID: instanceID,
            deviceFingerprint: deviceFingerprint
        )

        do {
            _ = try await client.deactivate(request: request)
            clearStoredLicense()
            status = .unlicensed
            isLicensed = false
        } catch {
            lastErrorMessage = error.localizedDescription
            RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Licensing")
        }

        isBusy = false
    }

    func openCheckout(planId: String) async {
        guard RelayLicensingConfig.isDirectMacDistribution else { return }
        guard let client = licensingClient else {
            lastErrorMessage = "Licensing service is not configured."
            return
        }
        do {
            let url = try await client.checkout(planId: planId)
            openURL(url)
        } catch {
            lastErrorMessage = error.localizedDescription
            RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Licensing")
        }
    }

    @available(*, deprecated, message: "Use openCheckout(planId:) with dynamic plans.")
    func openCheckout(variant: LicensingVariant) async {
        guard RelayLicensingConfig.isDirectMacDistribution else { return }
        guard let client = licensingClient else {
            lastErrorMessage = "Licensing service is not configured."
            return
        }
        do {
            let url = try await client.checkout(variant: variant)
            openURL(url)
        } catch {
            lastErrorMessage = error.localizedDescription
            RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Licensing")
        }
    }

    func openManageSubscriptions() async {
        guard RelayLicensingConfig.isDirectMacDistribution else { return }
        guard let client = licensingClient else {
            lastErrorMessage = "Licensing service is not configured."
            return
        }
        do {
            let url = try await client.manageURL()
            openURL(url)
        } catch {
            lastErrorMessage = error.localizedDescription
            RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "Licensing")
        }
    }

    func cachedEntitlementSummary() -> LicenseEntitlement? {
        entitlement
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func currentLicenseKey() -> String? {
        licenseKey
    }

    func relayAccountActivationRequest() -> RelayAccountActivateLinkedLicenseRequest? {
        guard RelayLicensingConfig.isDirectMacDistribution else { return nil }
        return RelayAccountActivateLinkedLicenseRequest(
            instanceName: instanceName(),
            deviceFingerprint: deviceFingerprint,
            appVersion: appVersion(),
            bundleID: bundleID(),
            platform: "macOS"
        )
    }

    func relayAccountDeactivationRequest() -> RelayAccountDeactivateLinkedLicenseRequest? {
        guard RelayLicensingConfig.isDirectMacDistribution else { return nil }
        return RelayAccountDeactivateLinkedLicenseRequest(
            deviceFingerprint: deviceFingerprint,
            bundleID: bundleID(),
            platform: "macOS"
        )
    }

    func loadPlans(force: Bool = false) async {
        guard RelayLicensingConfig.isDirectMacDistribution else { return }
        guard let client = licensingClient else {
            plansLoadErrorMessage = "Licensing service is not configured."
            return
        }
        if !force, !availablePlans.isEmpty { return }

        plansAreLoading = true
        plansLoadErrorMessage = nil

        do {
            let response = try await client.fetchPlans()
            if response.ok {
                availablePlans = response.plans
            } else {
                availablePlans = []
                plansLoadErrorMessage = "Plans are unavailable."
            }
        } catch {
            availablePlans = []
            plansLoadErrorMessage = error.localizedDescription
            RelayDiagnosticsStore.shared.recordThrottledError(
                error.localizedDescription,
                tag: "Licensing",
                key: "license.plans.network_failure",
                minInterval: 3600
            )
        }

        plansAreLoading = false
    }

    private func statusFromCachedEntitlement(_ entitlement: LicenseEntitlement?) -> LicenseStatus {
        guard let entitlement else { return .unlicensed }
        if isEntitlementActive(entitlement) { return .active(entitlement) }
        let raw = entitlement.statusRaw.lowercased()
        if raw.contains("expired") { return .expired }
        if raw.contains("disabled") { return .disabled }
        return .unknown
    }

    private func mergeEntitlement(
        _ entitlement: LicenseEntitlement,
        meta: LicensingMeta?,
        previous: LicenseEntitlement?
    ) -> LicenseEntitlement {
        let responseMeta = meta?.responseMeta

        let productName = firstNonEmpty(
            entitlement.productName,
            responseMeta?.productName,
            previous?.productName
        )
        let variantName = firstNonEmpty(
            entitlement.variantName,
            responseMeta?.variantName,
            previous?.variantName
        )
        let customerEmail = firstNonEmpty(
            entitlement.customerEmail,
            responseMeta?.customerEmail,
            previous?.customerEmail
        )

        return LicenseEntitlement(
            licenseKeyMasked: entitlement.licenseKeyMasked,
            licenseKeySuffix: entitlement.licenseKeySuffix,
            instanceID: entitlement.instanceID,
            customerEmail: customerEmail,
            productName: productName,
            variantName: variantName,
            statusRaw: entitlement.statusRaw,
            activationUsageCount: entitlement.activationUsageCount,
            activationLimit: entitlement.activationLimit,
            expiresAt: entitlement.expiresAt,
            validatedAt: entitlement.validatedAt,
            isActive: entitlement.isActive,
            source: entitlement.source
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func applyEntitlement(_ entitlement: LicenseEntitlement, gracePeriod: Bool) {
        self.entitlement = entitlement
        if isEntitlementActive(entitlement) {
            status = .active(entitlement)
        } else if gracePeriod {
            status = .gracePeriod(entitlement, expiresAt: gracePeriodDeadline(from: entitlement))
        } else {
            let raw = entitlement.statusRaw.lowercased()
            if raw.contains("expired") {
                status = .expired
            } else if raw.contains("disabled") {
                status = .disabled
            } else {
                status = .unknown
            }
        }
        isLicensed = status.isLicensed
    }

    private func isEntitlementActive(_ entitlement: LicenseEntitlement) -> Bool {
        guard entitlement.isActive else { return false }
        let raw = entitlement.statusRaw.lowercased()
        if raw.contains("expired") || raw.contains("disabled") || raw.contains("inactive") {
            return false
        }
        if raw.contains("active") { return true }
        return entitlement.isActive
    }

    func handleNetworkFailure(_ error: Error) {
        lastErrorMessage = error.localizedDescription
        let errorText = error.localizedDescription.lowercased()
        if errorText.contains("expired") {
            status = .expired
            isLicensed = false
            return
        }
        if errorText.contains("disabled") {
            status = .disabled
            isLicensed = false
            return
        }
        if let entitlement, let deadline = gracePeriodDeadline(from: entitlement), Date() <= deadline {
            status = .gracePeriod(entitlement, expiresAt: deadline)
            isLicensed = true
            return
        }
        RelayDiagnosticsStore.shared.recordThrottledError(
            error.localizedDescription,
            tag: "Licensing",
            key: "license.validate.network_failure",
            minInterval: 3600
        )
        status = .networkError(lastKnown: entitlement)
        isLicensed = false
    }

    private func gracePeriodDeadline(from entitlement: LicenseEntitlement) -> Date? {
        guard let validatedAt = entitlement.validatedAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: gracePeriodDays, to: validatedAt)
    }

    private func loadCachedEntitlement() -> LicenseEntitlement? {
        guard let data = keychain.loadData(forKey: entitlementKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LicenseEntitlement.self, from: data)
    }

    private func persist(licenseKey: String, instanceID: String?, entitlement: LicenseEntitlement) {
        var allSucceeded = keychain.saveString(licenseKey, forKey: licenseKeyKey)
        if let instanceID {
            allSucceeded = keychain.saveString(instanceID, forKey: instanceIDKey) && allSucceeded
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entitlement) {
            allSucceeded = keychain.saveData(data, forKey: entitlementKey) && allSucceeded
        }
        if !allSucceeded {
            RelayDiagnosticsStore.shared.recordError(
                "Keychain write failed while persisting license", tag: "Keychain"
            )
        }
    }

    private func clearStoredLicense() {
        if !keychain.clearAll(keys: [licenseKeyKey, instanceIDKey, entitlementKey]) {
            RelayDiagnosticsStore.shared.recordError(
                "Keychain clear failed while deactivating license", tag: "Keychain"
            )
        }
        entitlement = nil
        licenseKey = nil
        instanceID = nil
    }

    private func instanceName() -> String {
#if os(macOS)
        let host = Host.current().localizedName ?? "Mac"
#elseif os(iOS)
        let host = UIDevice.current.name
#else
        let host = ProcessInfo.processInfo.hostName
#endif
        return "\(host) - Relay"
    }

    private func appVersion() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private func bundleID() -> String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    private func openURL(_ url: URL) {
#if os(macOS)
        NSWorkspace.shared.open(url)
#endif
    }

    private func startPeriodicValidationLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(validationIntervalSeconds * 1_000_000_000))
            await validateLicense()
        }
    }

    private func monitorAppActivation() async {
#if os(macOS)
        for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
            await validateLicense()
        }
#endif
    }
}
