import Foundation

struct LicenseEntitlement: Codable, Equatable {
    let licenseKeyMasked: String
    let licenseKeySuffix: String?
    let instanceID: String?
    let customerEmail: String?
    let productName: String?
    let variantName: String?
    let statusRaw: String
    let activationUsageCount: Int?
    let activationLimit: Int?
    let expiresAt: Date?
    let validatedAt: Date?
    let isActive: Bool
    let source: String

    private enum CodingKeys: String, CodingKey {
        case licenseKeyMasked
        case licenseKeySuffix
        case instanceID
        case customerEmail
        case productName
        case variantName
        case statusRaw
        case activationUsageCount
        case activationLimit
        case expiresAt
        case validatedAt
        case isActive
        case source
    }

    private enum AltCodingKeys: String, CodingKey {
        case licenseKeyMasked = "license_key_masked"
        case licenseKeySuffix = "license_key_suffix"
        case instanceID = "instance_id"
        case customerEmail = "customer_email"
        case productName = "product_name"
        case variantName = "variant_name"
        case statusRaw = "status_raw"
        case activationUsageCount = "activation_usage_count"
        case activationLimit = "activation_limit"
        case expiresAt = "expires_at"
        case validatedAt = "validated_at"
        case isActive = "is_active"
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try decoder.container(keyedBy: AltCodingKeys.self)

        licenseKeyMasked = try container.decodeIfPresent(String.self, forKey: .licenseKeyMasked)
            ?? altContainer.decodeIfPresent(String.self, forKey: .licenseKeyMasked)
            ?? ""
        licenseKeySuffix = try container.decodeIfPresent(String.self, forKey: .licenseKeySuffix)
            ?? altContainer.decodeIfPresent(String.self, forKey: .licenseKeySuffix)
        instanceID = try container.decodeIfPresent(String.self, forKey: .instanceID)
            ?? altContainer.decodeIfPresent(String.self, forKey: .instanceID)
        customerEmail = try container.decodeIfPresent(String.self, forKey: .customerEmail)
            ?? altContainer.decodeIfPresent(String.self, forKey: .customerEmail)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
            ?? altContainer.decodeIfPresent(String.self, forKey: .productName)
        variantName = try container.decodeIfPresent(String.self, forKey: .variantName)
            ?? altContainer.decodeIfPresent(String.self, forKey: .variantName)
        statusRaw = try container.decodeIfPresent(String.self, forKey: .statusRaw)
            ?? altContainer.decodeIfPresent(String.self, forKey: .statusRaw)
            ?? "unknown"
        activationUsageCount = try container.decodeIfPresent(Int.self, forKey: .activationUsageCount)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .activationUsageCount)
        activationLimit = try container.decodeIfPresent(Int.self, forKey: .activationLimit)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .activationLimit)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
            ?? altContainer.decodeIfPresent(Date.self, forKey: .expiresAt)
        validatedAt = try container.decodeIfPresent(Date.self, forKey: .validatedAt)
            ?? altContainer.decodeIfPresent(Date.self, forKey: .validatedAt)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
            ?? altContainer.decodeIfPresent(Bool.self, forKey: .isActive)
            ?? false
        source = try container.decodeIfPresent(String.self, forKey: .source)
            ?? altContainer.decodeIfPresent(String.self, forKey: .source)
            ?? "unknown"
    }

    init(
        licenseKeyMasked: String,
        licenseKeySuffix: String?,
        instanceID: String?,
        customerEmail: String?,
        productName: String?,
        variantName: String?,
        statusRaw: String,
        activationUsageCount: Int?,
        activationLimit: Int?,
        expiresAt: Date?,
        validatedAt: Date?,
        isActive: Bool,
        source: String
    ) {
        self.licenseKeyMasked = licenseKeyMasked
        self.licenseKeySuffix = licenseKeySuffix
        self.instanceID = instanceID
        self.customerEmail = customerEmail
        self.productName = productName
        self.variantName = variantName
        self.statusRaw = statusRaw
        self.activationUsageCount = activationUsageCount
        self.activationLimit = activationLimit
        self.expiresAt = expiresAt
        self.validatedAt = validatedAt
        self.isActive = isActive
        self.source = source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(licenseKeyMasked, forKey: .licenseKeyMasked)
        try container.encodeIfPresent(licenseKeySuffix, forKey: .licenseKeySuffix)
        try container.encodeIfPresent(instanceID, forKey: .instanceID)
        try container.encodeIfPresent(customerEmail, forKey: .customerEmail)
        try container.encodeIfPresent(productName, forKey: .productName)
        try container.encodeIfPresent(variantName, forKey: .variantName)
        try container.encode(statusRaw, forKey: .statusRaw)
        try container.encodeIfPresent(activationUsageCount, forKey: .activationUsageCount)
        try container.encodeIfPresent(activationLimit, forKey: .activationLimit)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(validatedAt, forKey: .validatedAt)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(source, forKey: .source)
    }
}
