import Foundation

struct RelayAccountLinkAppStoreSubscriptionRequest: Codable, Equatable {
    let originalTransactionId: String
    let transactionId: String?
    let productId: String
    let expirationDate: Date?
    let isActive: Bool

    private enum CodingKeys: String, CodingKey {
        case originalTransactionId
        case transactionId
        case productId
        case expirationDate
        case isActive
    }

    init(
        originalTransactionId: String,
        transactionId: String?,
        productId: String,
        expirationDate: Date?,
        isActive: Bool
    ) {
        self.originalTransactionId = originalTransactionId
        self.transactionId = transactionId
        self.productId = productId
        self.expirationDate = expirationDate
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalTransactionId = try container.decode(String.self, forKey: .originalTransactionId)
        transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
        productId = try container.decode(String.self, forKey: .productId)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        if let raw = try container.decodeIfPresent(String.self, forKey: .expirationDate) {
            expirationDate = relayAccountISO8601Date(from: raw)
        } else {
            expirationDate = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalTransactionId, forKey: .originalTransactionId)
        try container.encodeIfPresent(transactionId, forKey: .transactionId)
        try container.encode(productId, forKey: .productId)
        try container.encodeIfPresent(expirationDate.map(relayAccountISO8601String), forKey: .expirationDate)
        try container.encode(isActive, forKey: .isActive)
    }
}

struct RelayPendingAppStoreSubscription: Codable, Equatable, Identifiable {
    let originalTransactionId: String
    let transactionId: String?
    let productId: String
    let expirationDate: Date?
    let isActive: Bool

    var id: String {
        originalTransactionId
    }

    var linkRequest: RelayAccountLinkAppStoreSubscriptionRequest {
        RelayAccountLinkAppStoreSubscriptionRequest(
            originalTransactionId: originalTransactionId,
            transactionId: transactionId,
            productId: productId,
            expirationDate: expirationDate,
            isActive: isActive
        )
    }
}

private func relayAccountISO8601Date(from raw: String) -> Date? {
    let withFractionalSeconds = ISO8601DateFormatter()
    withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractionalSeconds.date(from: raw) {
        return date
    }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: raw)
}

private func relayAccountISO8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
