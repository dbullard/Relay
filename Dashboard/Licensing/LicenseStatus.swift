import Foundation

enum LicenseStatus: Equatable {
    case unlicensed
    case activating
    case active(LicenseEntitlement)
    case gracePeriod(LicenseEntitlement, expiresAt: Date?)
    case expired
    case disabled
    case networkError(lastKnown: LicenseEntitlement?)
    case unknown

    var isLicensed: Bool {
        switch self {
        case .active, .gracePeriod:
            return true
        default:
            return false
        }
    }
}
