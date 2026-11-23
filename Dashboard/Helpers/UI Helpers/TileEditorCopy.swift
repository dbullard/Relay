import Foundation

/// Wording used by the tile editor (inspector) that is worth keeping consistent and testable.
enum TileEditorCopy {
    static let untitledTileName = "Untitled Tile"

    /// The editor header: the tile's name, or "3 Tiles" when several tiles are selected.
    static func headerTitle(tileName: String, selectedTileCount: Int) -> String {
        if selectedTileCount > 1 {
            return "\(selectedTileCount) Tiles"
        }
        let trimmed = tileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitledTileName : trimmed
    }

    /// Undo menu name for a change to a module's settings, e.g. "Change Sennheiser Settings".
    static func moduleSettingsActionName(_ moduleName: String) -> String {
        "Change \(moduleName) Settings"
    }
}
