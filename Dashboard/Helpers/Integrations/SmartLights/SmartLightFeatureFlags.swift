import Foundation

enum SmartLightFeatureFlags {
    static var isEnabled: Bool {
        RelayLicensingConfig.isPreviewEnabled
    }
}

