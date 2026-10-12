import Foundation

struct GraphDashboardPeopleContext {
    let groups: [GraphDashboardView.ModuleGroup]
    let canvasPeopleMembers: [GraphDashboardView.ModuleMember]
    let allPeopleMembers: [GraphDashboardView.ModuleMember]
    let teamOptions: [String]
}

enum GraphDashboardDataModel {
    static func resolvePeopleContext(
        groups: [GraphDashboardView.ModuleGroup],
        canvasPeopleMembers: [GraphDashboardView.ModuleMember],
        cachedSynthesizedPeopleMembersFromPCO: [GraphDashboardView.ModuleMember],
        pcoTeamOptionsFromTab: [String]
    ) -> GraphDashboardPeopleContext {
        let synthesizedPeopleMembers: [GraphDashboardView.ModuleMember] =
            canvasPeopleMembers.isEmpty ? cachedSynthesizedPeopleMembersFromPCO : []

        let allPeopleMembers: [GraphDashboardView.ModuleMember] =
            !canvasPeopleMembers.isEmpty ? canvasPeopleMembers : synthesizedPeopleMembers

        let memberTeams = Array(Set(allPeopleMembers.compactMap { $0.teamName })).sorted()
        let teamOptions = !memberTeams.isEmpty ? memberTeams : pcoTeamOptionsFromTab

        return GraphDashboardPeopleContext(
            groups: groups,
            canvasPeopleMembers: canvasPeopleMembers,
            allPeopleMembers: allPeopleMembers,
            teamOptions: teamOptions
        )
    }
}
