import SwiftUI

enum DashboardTileModuleMetadata {
    static func cornerStyle(
        for index: Int,
        total count: Int,
        layout: TileModuleLayout
    ) -> ModuleCornerStyle {
        if count == 1 {
            return .single
        }

        if layout == .horizontal {
            if index == 0 {
                return .leading
            } else if index == count - 1 {
                return .trailing
            }
            return .middle
        }

        if index == 0 {
            return .top
        } else if index == count - 1 {
            return .bottom
        }
        return .middle
    }

    static func cornerStyle(
        for module: DashboardModuleModel,
        modulesSorted: [DashboardModuleModel],
        layout: TileModuleLayout
    ) -> ModuleCornerStyle {
        guard let index = modulesSorted.firstIndex(where: { $0.id == module.id }) else {
            return .single
        }
        return cornerStyle(for: index, total: modulesSorted.count, layout: layout)
    }

    static func contentAlignment(
        horizontal: TextJustificationStyle?,
        vertical: TextVerticalAlignmentStyle?
    ) -> Alignment {
        switch (vertical ?? .top, horizontal ?? .leading) {
        case (.top, .leading): return .topLeading
        case (.top, .center): return .top
        case (.top, .trailing): return .topTrailing
        case (.center, .leading): return .leading
        case (.center, .center): return .center
        case (.center, .trailing): return .trailing
        case (.bottom, .leading): return .bottomLeading
        case (.bottom, .center): return .bottom
        case (.bottom, .trailing): return .bottomTrailing
        }
    }

    static func label(for module: DashboardModuleModel) -> String {
        switch module.kind {
        case .person(let model):
            if !model.name.isEmpty {
                return "Person: \(model.name)"
            } else if !model.initials.isEmpty {
                return "Person: \(model.initials)"
            } else {
                return "Person"
            }
        case .pcoRundown:
            return "PCO Rundown"
        case .pcoTeamAssignments:
            return "PCO Team Assignments"
        case .rosterTeamAssignments:
            return "Roster Team Assignments"
        case .shureWireless:
            return "Shure Wireless"
        case .shureOverview:
            return "Shure Overview"
        case .sennheiserWireless:
            return "Sennheiser Wireless"
        case .time:
            return "Time"
        case .timecode:
            return "Timecode"
        case .dawTransport:
            return "DAW Transport"
        case .rosterPicker:
            return "Picker"
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .document:
            return "Document"
        case .ndi:
            return "NDI Feed"
        case .webpage:
            return "Webpage"
        case .youtubeStreamMonitor:
            return "YouTube Stream Monitor"
        case .separator:
            return "Separator"
        case .proPresenter:
            return "ProPresenter"
        case .resolume:
            return "Resolume"
        case .dbReader:
            return "SPL Meter"
        case .liveTranscription:
            return "Live Transcription"
        case .button:
            return "Button"
        case .rta:
            return "RTA"
        case .spectrograph:
            return "Spectrograph"
        }
    }
}
