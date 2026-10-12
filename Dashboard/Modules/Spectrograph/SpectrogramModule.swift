import SwiftUI

struct SpectrogramModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .spectrograph(SpectrogramModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>, tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>, isLiveMode: Bool
    ) -> AnyView {
        AnyView(SpectrogramTileView(tab: tab, tile: tile, module: module, isLiveMode: isLiveMode))
    }

    static func settingsView(showsHeader: Binding<Bool>, onPersist: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }
}
