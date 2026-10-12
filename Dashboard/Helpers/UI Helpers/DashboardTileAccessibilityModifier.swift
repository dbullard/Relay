import SwiftUI

struct DashboardTileAccessibilityModifier: ViewModifier {
    let tile: DashboardTileModel
    let modules: [DashboardModuleModel]
    let isSelected: Bool
    let isLiveMode: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onExitLiveMode: () -> Void

    private var title: String {
        let tileName = tile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tileName.isEmpty {
            return tileName
        }

        guard !modules.isEmpty else {
            return "Empty Tile"
        }

        let moduleNames = modules
            .prefix(3)
            .map { DashboardTileModuleMetadata.label(for: $0) }

        if modules.count > moduleNames.count {
            return moduleNames.joined(separator: ", ") + ", and \(modules.count - moduleNames.count) more"
        }

        return moduleNames.joined(separator: ", ")
    }

    private var value: String {
        var parts: [String] = []

        if isSelected {
            parts.append("Selected")
        }

        if isLiveMode {
            parts.append("Live Mode")
        }

        if !modules.isEmpty {
            let moduleText = modules.count == 1 ? "1 module" : "\(modules.count) modules"
            parts.append(moduleText)
        }

        parts.append("Position \(Int(tile.offset.width.rounded())), \(Int(tile.offset.height.rounded()))")
        return parts.joined(separator: ", ")
    }

    private var hint: String {
        if isLiveMode {
            return "Use the Exit Live Mode action to edit this tile."
        }
        return "Use actions to select, edit, or delete this tile."
    }

    private var traits: AccessibilityTraits {
        var traits: AccessibilityTraits = .isButton
        if isSelected {
            _ = traits.insert(.isSelected)
        }
        return traits
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let accessibleContent = content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(value))
            .accessibilityHint(Text(hint))
            .accessibilityAddTraits(traits)

        if isLiveMode {
            accessibleContent
                .accessibilityAction(named: Text("Exit Live Mode"), onExitLiveMode)
        } else {
            accessibleContent
                .accessibilityAction(named: Text("Select"), onSelect)
                .accessibilityAction(named: Text("Edit"), onEdit)
                .accessibilityAction(named: Text("Delete"), onDelete)
        }
    }
}
