import SwiftUI

struct RTAModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .rta(RTAModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        AnyView(RTATileView(tab: tab, tile: tile, module: module, isLiveMode: isLiveMode))
    }

    static func settingsView(showsHeader: Binding<Bool>, onPersist: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }
}
