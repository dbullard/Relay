import Foundation

enum DashboardPlatformCopy {
    static var startupFileHint: String {
        #if os(iOS)
        return "TIP: Touch and hold a file to set it as always-open on launch"
        #else
        return "TIP: Right-click a file to set it as always-open on launch"
        #endif
    }

    static var planningCenterOAuthHelpText: String {
        #if os(iOS)
        return "This dashboard uses OAuth to connect to your Planning Center account. The connection state is stored locally on this device. The Connect button opens a secure browser sign-in, then Relay stores the access token."
        #else
        return "This dashboard uses OAuth to connect to your Planning Center account. The connection state is stored locally on this Mac. The Connect button opens your browser, lets you sign in, and then securely stores the access token."
        #endif
    }

    static var planningCenterConnectHelpStep: String {
        #if os(iOS)
        return "Tap “Connect to Planning Center…”"
        #else
        return "Click “Connect to Planning Center…”"
        #endif
    }
}
