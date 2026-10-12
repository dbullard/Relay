//
//  GraphNotifications.swift
//  Relay
//
//  Shared notification names used by graph automation/runtime and UI.
//

import Foundation

extension Notification.Name {
    /// Posted when a console node is double-clicked/tapped and we want to open that console's External Device settings.
    static let prodlinkOpenExternalDeviceSettings = Notification.Name("Relay.OpenExternalDeviceSettings")

    /// Posted when the Graph view wants all visible console nodes to send to their consoles.
    /// `object` is expected to be `[UUID]` in the order they should be sent.
    /// Optional userInfo:
    ///  - "delayMs": Double (base delay per console index; default 0)
    ///  - "includeAssignments": Bool (default true)
    ///  - "includeSnapshots": Bool (default true)
    static let prodlinkGraphSendAllToConsoles = Notification.Name("Relay.GraphSendAllToConsoles")

    static let relayLiveModeDidChange = Notification.Name("Relay.LiveModeDidChange")
    // userInfo: ["isLiveMode": Bool]

    static let relayTabDidChange = Notification.Name("Relay.TabDidChange")
    // userInfo: ["tabId": UUID, "tabIndex": Int]

    static let relayPCOItemDidChange = Notification.Name("Relay.PCOItemDidChange")
    // userInfo: ["titles": [String]]

    static let relayAutomationDidLaunch = Notification.Name("Relay.AutomationDidLaunch")
    // no userInfo

    static let relayProPresenterStateDidChange = Notification.Name("Relay.ProPresenterStateDidChange")
    // userInfo: ["moduleId": UUID, "resolvedProfileId": UUID?, "event": String (ProPresenterTriggerEvent.rawValue), "value": String?]
}
