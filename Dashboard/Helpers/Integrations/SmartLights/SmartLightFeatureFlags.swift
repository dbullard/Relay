import Foundation

enum SmartLightFeatureFlags {
    static var isEnabled: Bool {
        RelayBuildConfig.isPreviewEnabled
    }
}

