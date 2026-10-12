import Foundation

enum LicensingVariant: String, Codable, CaseIterable {
    case proMonthly = "pro-monthly"
    case proYearly = "pro-yearly"
}

struct LicensingCheckoutRequest: Codable {
    let planId: String?
    let variant: String?

    init(planId: String) {
        self.planId = planId
        self.variant = nil
    }

    init(variant: String) {
        self.planId = nil
        self.variant = variant
    }
}

struct LicensingCheckoutResponse: Codable {
    let url: String
}

struct LicensingPlansResponse: Codable {
    let ok: Bool
    let plans: [LicensingPlan]
}

struct LicensingPlan: Codable, Equatable, Identifiable {
    let id: String
    let variantId: String?
    let displayName: String
    let price: Int?
    let priceFormatted: String
    let billingLabel: String
    let isSubscription: Bool
    let interval: String?
    let intervalCount: Int?
    let hasFreeTrial: Bool?
    let trialInterval: String?
    let trialIntervalCount: Int?
    let status: String?
}

struct LicensingActivateRequest: Codable {
    let licenseKey: String
    let instanceName: String
    let deviceFingerprint: String
    let appVersion: String
    let bundleID: String
    let platform: String
}

struct LicensingActivateResponse: Codable {
    let ok: Bool
    let entitlement: LicenseEntitlement?
    let meta: LicensingMeta?
}

struct LicensingValidateRequest: Codable {
    let licenseKey: String
    let instanceID: String
    let deviceFingerprint: String
    let appVersion: String
    let bundleID: String
    let platform: String
}

struct LicensingValidateResponse: Codable {
    let ok: Bool
    let gracePeriod: Bool?
    let entitlement: LicenseEntitlement?
    let meta: LicensingMeta?
}

struct LicensingDeactivateRequest: Codable {
    let licenseKey: String
    let instanceID: String
    let deviceFingerprint: String
}

struct LicensingDeactivateResponse: Codable {
    let ok: Bool
}

struct LicensingManageResponse: Codable {
    let url: String
}

struct LicensingMeta: Codable {
    let activated: Bool?
    let instanceName: String?
    let deviceFingerprint: String?
    let appVersion: String?
    let bundleID: String?
    let platform: String?
    let responseMeta: LicensingResponseMeta?

    private enum CodingKeys: String, CodingKey {
        case activated
        case instanceName
        case deviceFingerprint
        case appVersion
        case bundleID
        case platform
        case responseMeta
    }

    private enum AltCodingKeys: String, CodingKey {
        case instanceName = "instance_name"
        case deviceFingerprint = "device_fingerprint"
        case appVersion = "app_version"
        case bundleID = "bundle_id"
        case responseMeta = "response_meta"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try decoder.container(keyedBy: AltCodingKeys.self)

        activated = try container.decodeIfPresent(Bool.self, forKey: .activated)
        instanceName = try container.decodeIfPresent(String.self, forKey: .instanceName)
            ?? altContainer.decodeIfPresent(String.self, forKey: .instanceName)
        deviceFingerprint = try container.decodeIfPresent(String.self, forKey: .deviceFingerprint)
            ?? altContainer.decodeIfPresent(String.self, forKey: .deviceFingerprint)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
            ?? altContainer.decodeIfPresent(String.self, forKey: .appVersion)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
            ?? altContainer.decodeIfPresent(String.self, forKey: .bundleID)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        responseMeta = try container.decodeIfPresent(LicensingResponseMeta.self, forKey: .responseMeta)
            ?? altContainer.decodeIfPresent(LicensingResponseMeta.self, forKey: .responseMeta)
    }
}

struct LicensingResponseMeta: Codable {
    let storeID: Int?
    let orderID: Int?
    let orderItemID: Int?
    let variantID: Int?
    let variantName: String?
    let productID: Int?
    let productName: String?
    let customerID: Int?
    let customerName: String?
    let customerEmail: String?

    private enum CodingKeys: String, CodingKey {
        case storeID
        case orderID
        case orderItemID
        case variantID
        case variantName
        case productID
        case productName
        case customerID
        case customerName
        case customerEmail
    }

    private enum AltCodingKeys: String, CodingKey {
        case storeID = "store_id"
        case orderID = "order_id"
        case orderItemID = "order_item_id"
        case variantID = "variant_id"
        case variantName = "variant_name"
        case productID = "product_id"
        case productName = "product_name"
        case customerID = "customer_id"
        case customerName = "customer_name"
        case customerEmail = "customer_email"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try decoder.container(keyedBy: AltCodingKeys.self)

        storeID = try container.decodeIfPresent(Int.self, forKey: .storeID)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .storeID)
        orderID = try container.decodeIfPresent(Int.self, forKey: .orderID)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .orderID)
        orderItemID = try container.decodeIfPresent(Int.self, forKey: .orderItemID)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .orderItemID)
        variantID = try container.decodeIfPresent(Int.self, forKey: .variantID)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .variantID)
        variantName = try container.decodeIfPresent(String.self, forKey: .variantName)
            ?? altContainer.decodeIfPresent(String.self, forKey: .variantName)
        productID = try container.decodeIfPresent(Int.self, forKey: .productID)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .productID)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
            ?? altContainer.decodeIfPresent(String.self, forKey: .productName)
        customerID = try container.decodeIfPresent(Int.self, forKey: .customerID)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .customerID)
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName)
            ?? altContainer.decodeIfPresent(String.self, forKey: .customerName)
        customerEmail = try container.decodeIfPresent(String.self, forKey: .customerEmail)
            ?? altContainer.decodeIfPresent(String.self, forKey: .customerEmail)
    }
}
