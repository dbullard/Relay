import SwiftUI

struct DashboardModuleLayoutPlan {
    let modules: [DashboardModuleModel]
    let layout: TileModuleLayout
    let contentPadding: CGFloat
    let spacing: CGFloat
    let availableHeight: CGFloat
    private let fixedHeights: [UUID: CGFloat]
    private let fixedScale: CGFloat
    private let remainingHeight: CGFloat
    private let flexibleHeightCount: CGFloat
    private let fixedWidths: [UUID: CGFloat]
    private let flexibleWidth: CGFloat

    init(
        modules: [DashboardModuleModel],
        layout: TileModuleLayout,
        tileSize: CGSize,
        contentPadding: CGFloat,
        spacing: CGFloat = 8
    ) {
        let sortedModules = modules.sorted { $0.order < $1.order }
        let totalSpacing = CGFloat(max(0, sortedModules.count - 1)) * spacing
        let baseHeight = max(0, tileSize.height - (2 * contentPadding))
        let baseWidth = max(0, tileSize.width - (2 * contentPadding))

        self.modules = sortedModules
        self.layout = layout
        self.contentPadding = contentPadding
        self.spacing = spacing

        if layout == .vertical {
            var totalModulePadding: CGFloat = 0
            for module in sortedModules {
                totalModulePadding += module.paddingTop + module.paddingBottom
            }
            self.availableHeight = max(0, baseHeight - totalSpacing - totalModulePadding)
        } else {
            self.availableHeight = baseHeight
        }

        var heights: [UUID: CGFloat] = [:]
        for module in sortedModules {
            if let height = module.moduleHeightPoints, height > 0 {
                heights[module.id] = height
            }
        }
        self.fixedHeights = heights

        let fixedTotal = heights.values.reduce(0, +)
        self.fixedScale = (fixedTotal > 0 && fixedTotal > availableHeight)
            ? (availableHeight / fixedTotal)
            : 1.0

        let fixedConsumed = min(availableHeight, fixedTotal * fixedScale)
        self.remainingHeight = max(0, availableHeight - fixedConsumed)

        var flexibleCount = 0
        for module in sortedModules where heights[module.id] == nil {
            flexibleCount += 1
        }
        self.flexibleHeightCount = CGFloat(flexibleCount)

        var widths: [UUID: CGFloat] = [:]
        for module in sortedModules {
            if case .separator(let model) = module.kind {
                widths[module.id] = max(6, CGFloat(model.thickness) + 8)
            }
        }
        self.fixedWidths = widths

        let availableWidth = layout == .horizontal
            ? max(0, baseWidth - totalSpacing)
            : baseWidth
        let fixedWidthTotal = widths.values.reduce(0, +)
        let flexibleWidthCount = max(1, sortedModules.count - widths.count)
        let remainingWidth = max(0, availableWidth - fixedWidthTotal)
        self.flexibleWidth = max(0, remainingWidth / CGFloat(flexibleWidthCount))
    }

    func horizontalHeight(for module: DashboardModuleModel) -> CGFloat? {
        let moduleAvailableHeight = max(0, availableHeight - module.paddingTop - module.paddingBottom)
        if let raw = fixedHeights[module.id] {
            return min(moduleAvailableHeight, max(0, raw))
        }
        return moduleAvailableHeight
    }

    func horizontalWidth(for module: DashboardModuleModel) -> CGFloat? {
        fixedWidths[module.id] ?? flexibleWidth
    }

    func verticalHeight(for module: DashboardModuleModel) -> CGFloat? {
        if let raw = fixedHeights[module.id] {
            return max(0, raw * fixedScale)
        }
        guard flexibleHeightCount > 0 else { return nil }
        return max(0, remainingHeight / flexibleHeightCount)
    }
}
