import SwiftUI

enum DashboardTileMetrics {
    static let minWidth: CGFloat = 44
    static let minHeight: CGFloat = 44
    static let defaultModuleNaturalHeight: CGFloat = 220
    static let pcoRundownNaturalHeight: CGFloat = 260
    static let shureNaturalHeight: CGFloat = 220
    static let textModuleNaturalHeight: CGFloat = 160

    static func effectiveSize(for tile: DashboardTileModel, defaultTileSize: CGSize) -> CGSize {
        let baseWidth = tile.size?.width ?? defaultTileSize.width
        let width = max(minWidth, baseWidth)

        let height: CGFloat
        if let explicitHeight = tile.size?.height {
            height = explicitHeight
        } else if let modules = tile.modules, !modules.isEmpty {
            let baseHeight = modules.reduce(defaultTileSize.height) { partialResult, module in
                max(partialResult, naturalHeightFloor(for: module))
            }
            let extraPerAdditionalModule: CGFloat = 80
            let additionalModules = max(0, modules.count - 1)
            height = baseHeight + CGFloat(additionalModules) * extraPerAdditionalModule
        } else {
            height = defaultTileSize.height
        }

        return CGSize(
            width: width,
            height: max(minHeight, height)
        )
    }

    private static func naturalHeightFloor(for module: DashboardModuleModel) -> CGFloat {
        switch module.kind {
        case .pcoRundown:
            return pcoRundownNaturalHeight
        case .shureWireless:
            return shureNaturalHeight
        case .shureOverview:
            return shureNaturalHeight
        case .text:
            return textModuleNaturalHeight
        case .image, .document, .dbReader:
            return defaultModuleNaturalHeight + 120
        case .liveTranscription:
            return defaultModuleNaturalHeight + 40
        default:
            return defaultModuleNaturalHeight
        }
    }
}
