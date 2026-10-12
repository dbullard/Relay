import SwiftUI

enum DashboardTileModuleBinding {
    static func binding(
        for module: DashboardModuleModel,
        tile: Binding<DashboardTileModel>
    ) -> Binding<DashboardModuleModel> {
        let moduleID = module.id

        return Binding(
            get: {
                guard let modules = tile.wrappedValue.modules else {
                    return module
                }
                return modules.first(where: { $0.id == moduleID }) ?? module
            },
            set: { newValue in
                var currentTile = tile.wrappedValue
                if var modules = currentTile.modules,
                   let index = modules.firstIndex(where: { $0.id == moduleID }) {
                    modules[index] = newValue
                    currentTile.modules = modules
                } else {
                    currentTile.modules = [newValue]
                }
                tile.wrappedValue = currentTile
            }
        )
    }
}
