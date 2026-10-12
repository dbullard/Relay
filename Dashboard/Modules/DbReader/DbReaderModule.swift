import SwiftUI

struct DbReaderModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .dbReader(DbReaderModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        AnyView(DbReaderTileView(tab: tab, tile: tile, module: module, isLiveMode: isLiveMode))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }
}
