import SwiftUI

struct DashboardTileModuleStack<ModuleContent: View>: View {
    let plan: DashboardModuleLayoutPlan
    let alignment: Alignment
    let moduleContent: (DashboardModuleModel, CGFloat?) -> ModuleContent
    let onModuleAppear: (DashboardModuleModel) -> Void

    var body: some View {
        Group {
            if plan.layout == .horizontal {
                HStack(alignment: .top, spacing: plan.spacing) {
                    ForEach(plan.modules) { module in
                        let allocatedHeight = plan.horizontalHeight(for: module)
                        let allocatedWidth = plan.horizontalWidth(for: module)

                        moduleContent(module, allocatedHeight)
                            .frame(width: allocatedWidth, height: allocatedHeight, alignment: alignment)
                            .clipped()
                            .padding(.top, module.paddingTop)
                            .padding(.bottom, module.paddingBottom)
                            .onAppear {
                                onModuleAppear(module)
                            }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: plan.spacing) {
                    ForEach(plan.modules) { module in
                        let allocatedHeight = plan.verticalHeight(for: module)

                        moduleContent(module, allocatedHeight)
                            .frame(height: allocatedHeight, alignment: alignment)
                            .clipped()
                            .padding(.top, module.paddingTop)
                            .padding(.bottom, module.paddingBottom)
                            .onAppear {
                                onModuleAppear(module)
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(plan.contentPadding)
    }
}
