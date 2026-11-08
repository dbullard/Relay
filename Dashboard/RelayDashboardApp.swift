//
//  RelayDashboardApp.swift
//  Relay
//
//  Created by David Bullard on 11/16/25.
//

import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif
#if canImport(AppKit)
import AppKit
#endif

@main
struct RelayDashboardApp: App {
    /// Must stay the first stored property: it applies a requested import of the previous
    /// Relay's settings before any store reads UserDefaults.
    private let appliedPendingImport: Bool = PreviousRelayImporter.applyPendingImportIfNeeded()
#if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = SparkleUpdateDelegate()
#endif
    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(RelayAppDelegate.self) private var appDelegate
    #endif

    init() {
#if canImport(Sparkle)
        // Sparkle's own docs warn against starting the updater before the app has
        // finished launching — doing so from App.init() races Sparkle's first-run
        // permission prompt against the app's launch/activation sequence and can
        // leave the app appearing to never open. Start it from onAppear instead,
        // once the window is actually up.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        updaterController.updater.clearFeedURLFromUserDefaults()
#endif
        #if canImport(AppKit)
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "dashboard_allowTileOverlap_migrated") {
            defaults.set(true, forKey: "dashboard_allowTileOverlap")
            defaults.set(true, forKey: "dashboard_allowTileOverlap_migrated")
        }

        ensureRelayDocumentsFolder()

        ProPresenterKeychainStore.shared.migrateFromUserDefaultsIfNeeded()

        RelayLogManager.shared.start()
        Task { @MainActor in
            await SharedValueStore.shared.load()
            SharedValueSourceCoordinator.shared.start()
        }
    }

    @AppStorage("dashboard_snap_to_grid_enabled")
    private var snapToGridEnabled: Bool = false

    @AppStorage("dashboard_colorSchemePreference")
    private var colorSchemePreferenceRaw: String = ColorSchemePreference.system.rawValue

    private var colorSchemePreference: ColorSchemePreference {
        ColorSchemePreference(rawValue: colorSchemePreferenceRaw) ?? .system
    }

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var saveState = DashboardSaveState.shared
    @ObservedObject private var whatsNewStore = WhatsNewStore.shared
    // Launch-sequencing gate for the one-time "What's New" popup. Home's sheet (below)
    // stays hidden until this resolves, so the on-launch order is always fixed:
    // What's New (only if there are unseen releases) -> Home.
    @State private var showingWhatsNewSheet = false
    @State private var showingPreviousImportOffer = false
    @State private var hasCheckedWhatsNewThisLaunch = false
    @State private var hasResolvedWhatsNewGate = false
    // Start with home screen already dismissed if a valid startup file is pinned —
    // avoids a flash of the home view before resolveStartupFileIfNeeded runs.
    @State private var launchScreenDismissed: Bool = {
        let data = UserDefaults.standard.data(forKey: "relay_startup_file_bookmark") ?? Data()
        guard !data.isEmpty else { return false }
        #if os(macOS)
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path) else { return false }
        return true
        #else
        return false
        #endif
    }()
    @State private var settingsOpenedFromLaunch: Bool = false
    #if canImport(Sparkle)
    private static var hasStartedUpdater = false
    #endif
    @AppStorage("relay_startup_file_bookmark") private var startupFileBookmarkData: Data = Data()
    @AppStorage("relay_startup_file_name") private var startupFileName: String = ""

    @ViewBuilder
    private var appRootView: some View {
        let baseView = DashboardRootView()
            .environmentObject(saveState)

        let configuredRootView = baseView
        .preferredColorScheme(colorSchemePreference.colorScheme)
        .sheet(isPresented: $showingPreviousImportOffer) {
            if let available = PreviousRelayImporter.availableImport() {
                PreviousRelayImportSheet(summary: available.summary, isFirstLaunchOffer: true) {
                    showingPreviousImportOffer = false
                }
            }
        }
        .sheet(isPresented: $showingWhatsNewSheet, onDismiss: { whatsNewStore.markLatestReleaseSeen() }) {
            WhatsNewSheet(releases: whatsNewStore.unseenReleases) {
                whatsNewStore.markLatestReleaseSeen()
                showingWhatsNewSheet = false
            }
        }
        .modifier(WindowTitleSetter(
            currentFileName: saveState.displayFileName,
            currentFileURL: saveState.currentFileURL,
            hasUnsavedChanges: saveState.hasUnsavedChanges
        ))
        .onAppear {
                #if canImport(Sparkle)
                if !Self.hasStartedUpdater {
                    Self.hasStartedUpdater = true
                    updaterController.startUpdater()
                }
                #endif

                resolveStartupFileIfNeeded()

                // Start global OSC listening on app launch if enabled in Settings.
                let defaults = UserDefaults.standard
                let enabled = defaults.bool(forKey: "osc.global.enabled")
                let portInt = defaults.integer(forKey: "osc.global.port")
                let clamped = max(1, min(65535, portInt == 0 ? 8000 : portInt))
                let port = UInt16(clamped)

                if enabled {
                    OSCManager.shared.setGlobalListening(enabled: true, port: port)
                } else {
                    // Keep manager in sync (ensures we aren't listening unexpectedly).
                    OSCManager.shared.setGlobalListening(enabled: false, port: port)
                }

                let midiEnabled: Bool = {
                    if let existing = defaults.object(forKey: "midi.global.enabled") as? Bool {
                        return existing
                    }
                    defaults.set(true, forKey: "midi.global.enabled")
                    return true
                }()

                let midiSourceId: Int32? = {
                    guard let raw = defaults.object(forKey: "midi.global.sourceId") else {
                        defaults.set(-1, forKey: "midi.global.sourceId")
                        return nil
                    }
                    if let v = raw as? Int {
                        return v >= 0 ? Int32(v) : nil
                    }
                    if let v = raw as? NSNumber {
                        return v.intValue >= 0 ? Int32(v.intValue) : nil
                    }
                    return nil
                }()

                MIDIGlobalReceiveManager.shared.setGlobalListening(enabled: midiEnabled, preferredSourceID: midiSourceId)

                _ = YamahaConsoleServiceRegistry.shared

                advanceLaunchGateIfNeeded()
            }

        configuredRootView
            .sheet(isPresented: Binding(
                get: { !launchScreenDismissed && !showingWhatsNewSheet && !showingPreviousImportOffer && hasResolvedWhatsNewGate },
                set: { shown in if !shown { launchScreenDismissed = true } }
            )) {
                RelayLaunchScreenView(
                    onOpenRecent: { url in
                        // User hasn't touched the blank canvas — discard it silently.
                        DashboardSaveState.shared.hasUnsavedChanges = false
                        DashboardDocumentController.shared.openSpecificDocument(url)
                        launchScreenDismissed = true
                    },
                    onNewDashboard: { size in
                        DashboardSaveState.shared.hasUnsavedChanges = false
                        launchScreenDismissed = true
                        // Delay so the home sheet finishes dismissing, then create the blank document.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NotificationCenter.default.post(
                                name: .createBlankDashboardRequested,
                                object: nil,
                                userInfo: ["width": size.width, "height": size.height]
                            )
                        }
                    },
                    onOpenFile: {
                        DashboardSaveState.shared.hasUnsavedChanges = false
                        launchScreenDismissed = true
                        DashboardHomeScreenState.shared.openPickerLaunchedFromHome = true
                        // Delay so the home sheet finishes dismissing before the
                        // file picker appears — presenting both simultaneously drops the picker.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            DashboardDocumentController.shared.openDocument()
                        }
                    },
                    onOpenSettings: {
                        settingsOpenedFromLaunch = true
                        launchScreenDismissed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                        }
                    },
                    onQuit: {
                        NotificationCenter.default.post(name: .dashboardAppTerminateRequested, object: nil)
                    },
                    onClose: {
                        NotificationCenter.default.post(name: .dismissHomeRequested, object: nil)
                    }
                )
            }
            .onOpenURL { url in
                if url.isFileURL {
                    launchScreenDismissed = true
                    DashboardDocumentController.shared.openSpecificDocument(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsDidDismiss)) { _ in
                if settingsOpenedFromLaunch {
                    settingsOpenedFromLaunch = false
                    launchScreenDismissed = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showHomeRequested)) { _ in
                DashboardSaveState.shared.hasUnsavedChanges = false
                launchScreenDismissed = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissHomeRequested)) { _ in
                launchScreenDismissed = true
            }
            .onChange(of: launchScreenDismissed, initial: true) { _, dismissed in
                DashboardHomeScreenState.shared.isPresented = !dismissed
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardDismissBlockingModalsRequested)) { _ in
                // Also clear this so a subsequent `.settingsDidDismiss` (posted when
                // DashboardRootView reacts to us force-closing Settings below) can't
                // reopen the launch screen out from under a Quit/Close-Window in progress.
                settingsOpenedFromLaunch = false
                launchScreenDismissed = true
            }
    }

    /// Runs the one-time "What's New" check and unblocks the Home sheet once it settles.
    /// Guarded to run at most once per launch.
    private func advanceLaunchGateIfNeeded() {
        guard !hasCheckedWhatsNewThisLaunch else { return }
        hasCheckedWhatsNewThisLaunch = true

        Task { @MainActor in
            whatsNewStore.establishBaselineIfNeeded()

            // Don't let a stalled feed request hold Home hostage -- give it a few
            // seconds, then proceed with whatever was already cached. refresh() itself
            // already fails silently and keeps the cache, so this only bounds how long
            // we wait for genuinely new data before showing Home anyway.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.whatsNewStore.refresh() }
                group.addTask { try? await Task.sleep(nanoseconds: 4_000_000_000) }
                await group.next()
                group.cancelAll()
            }

            if whatsNewStore.shouldPresentAutoPopup() {
                showingWhatsNewSheet = true
            } else if PreviousRelayImporter.shouldOfferOnLaunch() {
                showingPreviousImportOffer = true
            }
            hasResolvedWhatsNewGate = true
        }
    }

    var body: some Scene {
#if os(macOS)
        Window("Relay", id: "main") {
            appRootView
        }
        .defaultSize(
            width: Self.initialWindowSize.width,
            height: Self.initialWindowSize.height
        )
        .commands {
#if canImport(Sparkle)
            RelayCommands(updater: updaterController.updater)
#else
            RelayCommands()
#endif
        }

        Window("Variables", id: "shared-values") {
            SharedValuesWindow()
        }
        .defaultSize(width: 760, height: 620)
        .restorationBehavior(.disabled)
        .windowLevel(.floating)
#else
        WindowGroup {
            appRootView
        }
        .commands {
#if canImport(Sparkle)
            RelayCommands(updater: updaterController.updater)
#else
            RelayCommands()
#endif
        }
#endif
    }

    private func resolveStartupFileIfNeeded() {
        guard !startupFileBookmarkData.isEmpty else { return }
        #if os(macOS)
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: startupFileBookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path) else {
            // Bookmark exists but file is gone — show launch screen normally
            return
        }
        if isStale {
            startupFileBookmarkData = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
        }
        // Clear unsaved-changes flag so no save dialog appears for the blank canvas.
        DashboardSaveState.shared.hasUnsavedChanges = false
        // Skip launch screen and open directly.
        DashboardDocumentController.shared.openSpecificDocument(url)
        launchScreenDismissed = true
        #endif
    }

    static func saveStartupFileBookmark(for url: URL) {
        #if os(macOS)
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: "relay_startup_file_bookmark")
        UserDefaults.standard.set(
            url.deletingPathExtension().lastPathComponent,
            forKey: "relay_startup_file_name"
        )
        #endif
    }

    private func ensureRelayDocumentsFolder() {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            #if DEBUG
            print("[Relay] Documents directory not available.")
            #endif
            return
        }

        let relayFolder = documents.appendingPathComponent("Relay", isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: relayFolder.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return
            }
            do {
                try fileManager.removeItem(at: relayFolder)
            } catch {
                #if DEBUG
                print("[Relay] Failed to remove non-folder Relay path: \(error)")
                #endif
                return
            }
        }

        do {
            try fileManager.createDirectory(at: relayFolder, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("[Relay] Failed to create Documents/Relay: \(error)")
            #endif
        }
    }

#if os(macOS)
    private static var initialWindowSize: CGSize {
        let fallback = CGSize(width: 1280, height: 800)
        guard let screen = NSScreen.main else { return fallback }
        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return fallback }

        let defaults = UserDefaults.standard
        if let rectString = defaults.string(forKey: "RelayLastWindowFrame") {
            let raw = NSRectFromString(rectString)
            if raw.width.isFinite,
               raw.height.isFinite,
               raw.width > 0,
               raw.height > 0,
               raw.width <= visible.width * 1.05,
               raw.height <= visible.height * 1.05 {
                return CGSize(
                    width: min(max(raw.width, min(900, visible.width)), visible.width),
                    height: min(max(raw.height, min(600, visible.height)), visible.height)
                )
            }
        }

        return visible.size
    }
#endif
}

#if canImport(Sparkle)
private final class SparkleUpdateDelegate: NSObject, SPUUpdaterDelegate {
    #if canImport(AppKit)
    private var hasShownDiskImageInstallAlert = false
    #endif

    func feedURLString(for updater: SPUUpdater) -> String? {
        // One feed for everyone: the beta channel was merged into the main build.
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        logSparkle(
            "Found update \(item.displayVersionString) (\(item.versionString)) from \(feedURLString(for: updater) ?? "default feed")"
        )
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        logSparkle("Downloaded update \(item.displayVersionString) (\(item.versionString))")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        SparkleRelaunchCoordinator.shared.markInstallWillStart(item: item)
        logSparkle(
            "Installing update \(item.displayVersionString) (\(item.versionString)) from bundle path \(Bundle.main.bundlePath)"
        )
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        logSparkle("Updater requested permission to relaunch application")
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        SparkleRelaunchCoordinator.shared.markRelaunchRequested()
        logSparkle("Updater will relaunch application")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        SparkleRelaunchCoordinator.shared.markInstallOnQuit(item: item)
        logSparkle("Update \(item.displayVersionString) (\(item.versionString)) scheduled to install on quit")
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        SparkleRelaunchCoordinator.shared.clear()
        let nsError = error as NSError
        let failureReason = nsError.localizedFailureReason ?? "n/a"
        logSparkle(
            """
            Update aborted: domain=\(nsError.domain) code=\(nsError.code) \
            description=\(nsError.localizedDescription) failureReason=\(failureReason) \
            bundlePath=\(Bundle.main.bundlePath)
            """
        )

        #if canImport(AppKit)
        if shouldExplainDiskImageInstall(for: nsError) {
            presentDiskImageInstallAlert()
        }
        #endif
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            SparkleRelaunchCoordinator.shared.clear()
            let nsError = error as NSError
            logSparkle(
                "Update cycle finished with error: check=\(updateCheck.rawValue) domain=\(nsError.domain) code=\(nsError.code)"
            )
        } else {
            logSparkle("Update cycle finished successfully: check=\(updateCheck.rawValue)")
        }
    }

    private func logSparkle(_ message: String) {
        print("[Sparkle] \(message)")
    }

    #if canImport(AppKit)
    private func shouldExplainDiskImageInstall(for error: NSError) -> Bool {
        guard Bundle.main.bundlePath.hasPrefix("/Volumes/") else { return false }

        let message = [
            error.localizedDescription,
            error.localizedFailureReason,
            error.localizedRecoverySuggestion
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return message.contains("installer") || message.contains("authorization")
    }

    private func presentDiskImageInstallAlert() {
        guard !hasShownDiskImageInstallAlert else { return }
        hasShownDiskImageInstallAlert = true

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Relay is running from a disk image"
            alert.informativeText = "Updates cannot be installed while Relay is running from a mounted DMG. Move Relay to Applications, open it from there, and run Check for Updates again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    #endif
}

private final class SparkleRelaunchCoordinator {
    static let shared = SparkleRelaunchCoordinator()

    private(set) var isInstallPrepared = false
    private(set) var isRelaunchRequested = false

    func markInstallWillStart(item: SUAppcastItem) {
        isInstallPrepared = true
        print("[Sparkle] Preparing install for \(item.displayVersionString) (\(item.versionString))")
    }

    func markInstallOnQuit(item: SUAppcastItem) {
        isInstallPrepared = true
        print("[Sparkle] Install on quit armed for \(item.displayVersionString) (\(item.versionString))")
    }

    func markRelaunchRequested() {
        isRelaunchRequested = true
        print("[Sparkle] Relaunch requested")
    }

    func clear() {
        isInstallPrepared = false
        isRelaunchRequested = false
    }
}
#endif

#if canImport(AppKit)
enum MenuItemLocator {
    static func firstItem(in menu: NSMenu, withAction action: Selector) -> NSMenuItem? {
        for item in menu.items {
            if item.action == action {
                return item
            }
            if let submenu = item.submenu, let found = firstItem(in: submenu, withAction: action) {
                return found
            }
        }
        return nil
    }
}

private final class RelayAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        installQuitAndCloseKeyMonitor()
        retargetCloseMenuItem()
    }

    /// Without this override, AppKit's default behavior for a document-controller-backed
    /// app (`NSDocumentController` is in use here) is to quit the whole process the moment
    /// window count transiently hits zero — e.g. mid-transition while the magic-link
    /// callback updates account/entitlement state and briefly tears down and reconstructs
    /// the single `Window(id: "main")` scene. That silently called `NSApp.terminate(nil)`
    /// via `_scheduleCheckForTerminateAfterLastWindowClosed`, with no crash, no signal, and
    /// nothing for Sentry or the debugger to catch — confirmed via a call-stack dump on
    /// `applicationShouldTerminate(_:)`.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// AppKit does not deliver the standard "Quit"/"Close" menu-key-equivalent path
    /// (and therefore never calls `applicationShouldTerminate`/`windowShouldClose`) while
    /// a SwiftUI `.sheet()` is presented on the window. This monitor catches Cmd+Q and
    /// Cmd+W directly so they always reach the app's quit/close logic, sheet or no sheet.
    private func installQuitAndCloseKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
                return event
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q":
                NotificationCenter.default.post(name: .dashboardAppTerminateRequested, object: nil)
                return nil
            case "w":
                NotificationCenter.default.post(name: .dashboardCloseWindowRequested, object: event.window)
                return nil
            default:
                return event
            }
        }
    }

    /// Retargets the default "Close" menu item, if SwiftUI supplies one, so a mouse
    /// click routes through the same already-correct requestCloseWindow() path used
    /// by the Cmd+W keyDown monitor — bypassing NSWindow.performClose(_:) delivery,
    /// which is blocked while any SwiftUI `.sheet()` is presented (the same root cause
    /// documented above for Cmd+Q/Cmd+W, but affecting a mouse click on the menu item
    /// itself rather than the keyboard shortcut).
    ///
    /// As of this app's current scene configuration (`Window(...)`, not `WindowGroup`,
    /// on macOS — see this file's `body`), SwiftUI does not auto-generate a "Close"
    /// item, so this is currently a verified no-op (confirmed via manual testing) that
    /// activates automatically if a future scene change introduces one.
    private func retargetCloseMenuItem() {
        guard let mainMenu = NSApp.mainMenu,
              let item = MenuItemLocator.firstItem(in: mainMenu, withAction: #selector(NSWindow.performClose(_:)))
        else { return }
        item.target = self
        item.action = #selector(closeMenuItemClicked)
    }

    @objc private func closeMenuItemClicked() {
        NotificationCenter.default.post(name: .dashboardCloseWindowRequested, object: NSApp.keyWindow)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        for url in urls {
            if url.isFileURL {
                Task { @MainActor in
                    DashboardDocumentController.shared.openSpecificDocument(url)
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if SparkleRelaunchCoordinator.shared.isInstallPrepared || SparkleRelaunchCoordinator.shared.isRelaunchRequested {
            print("[Sparkle] Allowing application termination for update relaunch")
            return .terminateNow
        }

        if AppTerminationCoordinator.shared.shouldAllowImmediateTermination {
            AppTerminationCoordinator.shared.clear()
            return .terminateNow
        }

        if DashboardSaveState.shared.hasUnsavedChanges {
            AppTerminationCoordinator.shared.beginInteractiveTermination()
            DashboardDocumentController.shared.quitApplication()
            return .terminateLater
        }

        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if SparkleRelaunchCoordinator.shared.isInstallPrepared || SparkleRelaunchCoordinator.shared.isRelaunchRequested {
            print("[Sparkle] Application will terminate for update relaunch")
        }
        SparkleRelaunchCoordinator.shared.clear()
    }

}
#endif

#if canImport(AppKit)
private struct WindowTitleSetter: ViewModifier {
    let currentFileName: String
    let currentFileURL: URL?
    let hasUnsavedChanges: Bool

    private static var configuredWindows: Set<ObjectIdentifier> = []
    private static var observedWindows: Set<ObjectIdentifier> = []
    private static var frameObservers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    private static var pendingFrameSaves: [ObjectIdentifier: DispatchWorkItem] = [:]

    private static var lastPersistedFrameString: String?
    private static let windowFrameDefaultsKey = "RelayLastWindowFrame"

    func body(content: Content) -> some View {
        content
            .background(
                WindowAttachmentReader { window in
                    guard let window else { return }
                    configure(window: window)
                }
            )
    }

    private func configure(window: NSWindow) {
        let saveState = DashboardSaveState.shared
        let trimmedName = saveState.displayFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Untitled" : trimmedName
        let dirtyMarker = saveState.hasUnsavedChanges ? "*" : ""
        let desiredTitle = "\(displayName)\(dirtyMarker) — Relay"

        // Disallow native macOS window tabs for this window.
        window.tabbingMode = .disallowed
        window.isDocumentEdited = false
        window.representedURL = nil
        installFramePersistence(for: window)

        // Keep the saved frame sane, but do not set the window frame here.
        // SwiftUI's defaultSize uses the saved size before the window appears;
        // applying setFrame after attachment causes the visible resize/position jump.
        let windowId = ObjectIdentifier(window)
        if !Self.configuredWindows.contains(windowId) {
            let defaults = UserDefaults.standard
            if let screen = window.screen ?? NSScreen.main {
                if let rectString = defaults.string(forKey: Self.windowFrameDefaultsKey),
                   let rect = Self.sanitizedWindowFrame(NSRectFromString(rectString), screen: screen) {
                    let sanitizedFrameString = NSStringFromRect(rect)
                    defaults.set(sanitizedFrameString, forKey: Self.windowFrameDefaultsKey)
                    Self.lastPersistedFrameString = sanitizedFrameString
                } else if defaults.string(forKey: Self.windowFrameDefaultsKey) == nil {
                    Self.saveFrame(for: window)
                } else {
                    let visibleFrameString = NSStringFromRect(screen.visibleFrame)
                    defaults.set(visibleFrameString, forKey: Self.windowFrameDefaultsKey)
                    Self.lastPersistedFrameString = visibleFrameString
                }
            }
            Self.configuredWindows.insert(windowId)
        }

        if window.title != desiredTitle {
            window.title = desiredTitle
        }

        #if DEBUG
        print("[WindowTitleSetter] title=\(window.title)")
        #endif
    }

    private func installFramePersistence(for window: NSWindow) {
        let windowId = ObjectIdentifier(window)
        guard !Self.observedWindows.contains(windowId) else { return }

        Self.observedWindows.insert(windowId)
        let center = NotificationCenter.default
        let resizeObserver = center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            Self.scheduleFrameSave(for: window)
        }

        let moveObserver = center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            Self.scheduleFrameSave(for: window)
        }

        let closeObserver = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            Self.saveFrame(for: window)
            Self.removeFramePersistence(for: window)
        }

        Self.frameObservers[windowId] = [resizeObserver, moveObserver, closeObserver]
    }

    private static func scheduleFrameSave(for window: NSWindow) {
        let windowId = ObjectIdentifier(window)
        pendingFrameSaves[windowId]?.cancel()

        let workItem = DispatchWorkItem { [weak window] in
            guard let window else { return }
            saveFrame(for: window)
        }
        pendingFrameSaves[windowId] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private static func saveFrame(for window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main,
              let frame = sanitizedWindowFrame(window.frame, screen: screen) else {
            return
        }

        let frameString = NSStringFromRect(frame)
        guard lastPersistedFrameString != frameString else { return }

        UserDefaults.standard.set(frameString, forKey: windowFrameDefaultsKey)
        lastPersistedFrameString = frameString
    }

    private static func removeFramePersistence(for window: NSWindow) {
        let windowId = ObjectIdentifier(window)
        pendingFrameSaves[windowId]?.cancel()
        pendingFrameSaves[windowId] = nil

        let center = NotificationCenter.default
        frameObservers[windowId]?.forEach { center.removeObserver($0) }
        frameObservers[windowId] = nil
        observedWindows.remove(windowId)
        configuredWindows.remove(windowId)
    }

    private static func sanitizedWindowFrame(_ raw: NSRect, screen: NSScreen) -> NSRect? {
        guard raw.origin.x.isFinite,
              raw.origin.y.isFinite,
              raw.size.width.isFinite,
              raw.size.height.isFinite,
              raw.size.width > 0,
              raw.size.height > 0 else {
            return nil
        }

        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return nil }

        let maximumWidth = visible.width * 1.05
        let maximumHeight = visible.height * 1.05
        if raw.width > maximumWidth || raw.height > maximumHeight {
            return visible
        }

        let minimumSize = NSSize(width: min(900, visible.width), height: min(600, visible.height))
        let width = min(max(raw.width, minimumSize.width), visible.width)
        let height = min(max(raw.height, minimumSize.height), visible.height)
        let minX = visible.minX
        let maxX = visible.maxX - width
        let minY = visible.minY
        let maxY = visible.maxY - height
        let x = min(max(raw.origin.x, minX), maxX)
        let y = min(max(raw.origin.y, minY), maxY)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private struct WindowAttachmentReader: NSViewRepresentable {
        let onWindowChanged: (NSWindow?) -> Void

        func makeNSView(context: Context) -> ReaderView {
            let view = ReaderView()
            view.onWindowChanged = onWindowChanged
            return view
        }

        func updateNSView(_ nsView: ReaderView, context: Context) {
            nsView.onWindowChanged = onWindowChanged
            DispatchQueue.main.async { [weak nsView] in
                nsView?.onWindowChanged?(nsView?.window)
            }
        }

        final class ReaderView: NSView {
            var onWindowChanged: ((NSWindow?) -> Void)?
            private var saveStateObserver: NSObjectProtocol?

            deinit {
                if let saveStateObserver {
                    NotificationCenter.default.removeObserver(saveStateObserver)
                }
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                installSaveStateObserverIfNeeded()
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowChanged?(self?.window)
                }
            }

            private func installSaveStateObserverIfNeeded() {
                guard saveStateObserver == nil else { return }
                saveStateObserver = NotificationCenter.default.addObserver(
                    forName: .dashboardSaveStateDidChange,
                    object: DashboardSaveState.shared,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.onWindowChanged?(self.window)
                }
            }
        }
    }
}
@MainActor
final class AppTerminationCoordinator {
    static let shared = AppTerminationCoordinator()

    private(set) var isAwaitingReply: Bool = false
    private(set) var shouldAllowImmediateTermination: Bool = false

    func beginInteractiveTermination() {
        isAwaitingReply = true
        shouldAllowImmediateTermination = false
    }

    func continueTermination() {
        guard isAwaitingReply else {
            // Reached via the Cmd+Q monitor bypass, not through a normal
            // applicationShouldTerminate(_:) → .terminateLater cycle, so there's no
            // pending reply to answer. By this point dismissBlockingModalsForTermination()
            // has already run, so no sheet remains and this reaches applicationShouldTerminate
            // normally, returning .terminateNow immediately.
            NSApp.terminate(nil)
            return
        }
        shouldAllowImmediateTermination = true
        isAwaitingReply = false
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func cancelTermination() {
        guard isAwaitingReply else { return }
        clear()
        NSApp.reply(toApplicationShouldTerminate: false)
    }

    func clear() {
        isAwaitingReply = false
        shouldAllowImmediateTermination = false
    }
}

extension Notification.Name {
    static let dashboardAppTerminateRequested = Notification.Name("Relay.AppTerminateRequested")
    static let dashboardCloseWindowRequested = Notification.Name("Relay.CloseWindowRequested")
}
#else
private struct WindowTitleSetter: ViewModifier {
    let currentFileName: String
    let currentFileURL: URL?
    let hasUnsavedChanges: Bool
    func body(content: Content) -> some View { content }
}
#endif
