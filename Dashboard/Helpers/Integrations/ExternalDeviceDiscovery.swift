//
//  ExternalDeviceDiscovery.swift
//  Relay
//
//  Created by Relay on 4/2026.
//

import Foundation
import Network
import Combine

struct ExternalDeviceDiscoveryResult: Identifiable, Hashable {
    let id = UUID()
    let kind: ExternalDeviceKind
    let name: String
    let model: String?
    let consoleModelIdentifier: String?
    let consoleSubmodelIdentifier: String?
    let host: String
    let displayHost: String
    let storedHost: String
    let port: UInt16
    let serviceType: String
    let isProvisional: Bool
    let shureCID: UUID?
    let shureUacn: String?
    let shureFctn: String?
    let shureSdtHost: String?
    let shureSdtPort: UInt16?
    let shureDdlURL: String?
}

@MainActor
final class ExternalDeviceDiscoveryService: ObservableObject {
    @Published private(set) var results: [ExternalDeviceDiscoveryResult] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var statusText: String = "Idle"
    @Published var showAllHttpFallback: Bool = false
    var debugLoggingEnabled: Bool = false

    private struct ServiceEntry {
        let type: String
        let kind: ExternalDeviceKind
        let isProvisional: Bool
        let isHttpFallback: Bool
        let isDeviceLevel: Bool
    }

    // Provisional Shure service types (user-provided; not yet vendor-confirmed).
    private let serviceEntries: [ServiceEntry] = {
        var entries: [ServiceEntry] = [
            ServiceEntry(type: "_shure-control._tcp", kind: .shureWireless, isProvisional: true, isHttpFallback: false, isDeviceLevel: true),
            ServiceEntry(type: "_shure-audio._udp", kind: .shureWireless, isProvisional: true, isHttpFallback: false, isDeviceLevel: true),
            ServiceEntry(type: "_shure-update._tcp", kind: .shureWireless, isProvisional: true, isHttpFallback: false, isDeviceLevel: true),
            // Skip Dante (_netaudio-*) services to avoid grabbing Dante-only IPs.
            ServiceEntry(type: "_http._tcp", kind: .shureWireless, isProvisional: true, isHttpFallback: true, isDeviceLevel: true)
        ]
        entries.insert(
            ServiceEntry(type: "_ssc._tcp", kind: .sennheiserWireless, isProvisional: false, isHttpFallback: false, isDeviceLevel: true),
            at: 0
        )
        return entries
    }()
    private let useShureMulticast: Bool = true

    private var browsers: [NWBrowser] = []
    private let queue = DispatchQueue(label: "ExternalDeviceDiscoveryService")
    private var seenKeys: Set<String> = []
    private let shureSLPService = ShureSLPDiscoveryService()
    private var shureSLPCancellable: AnyCancellable?
    private var shureSLPActivityCancellable: AnyCancellable?
    private var shureFallbackWorkItem: DispatchWorkItem?
    private var shureMulticastFound: Bool = false
    private var shureFallbackStarted: Bool = false
    private let shureFallbackDelaySeconds: TimeInterval = 8.0
    private let x32M32Service = X32M32DiscoveryService()
    private var x32M32Cancellable: AnyCancellable?
    private var x32M32ActivityCancellable: AnyCancellable?
    private let dLiveService = DLiveDiscoveryService()
    private var dLiveCancellable: AnyCancellable?
    private var dLiveActivityCancellable: AnyCancellable?
    private let quService = QuDiscoveryService()
    private var quCancellable: AnyCancellable?
    private var quActivityCancellable: AnyCancellable?
    private let wingService = WingDiscoveryService()
    private var wingCancellable: AnyCancellable?
    private var wingActivityCancellable: AnyCancellable?
    private var resolvedServiceKeys: [String: Date] = [:]
    private let resolveCooldownSeconds: TimeInterval = 30
    private var scanIdleTimeoutWorkItem: DispatchWorkItem?
    private let scanIdleTimeoutSeconds: TimeInterval = 45
    private var scanStartedAt: Date?

    private func recordShureDiscoveryTrace(_ message: String, model: String? = nil) {
        guard WirelessLoggingPreferences.shureMasterVerbose else { return }
        if let model, !WirelessLoggingPreferences.isVerboseShure(forModel: model) {
            return
        }
        RelayDiagnosticsStore.shared.recordShureTrace("discovery \(message)")
    }

    func startScan() {
        stopScan()
        results.removeAll()
        seenKeys.removeAll()
        resolvedServiceKeys.removeAll()
        shureFallbackWorkItem?.cancel()
        shureFallbackWorkItem = nil
        shureMulticastFound = false
        shureFallbackStarted = false
        scanStartedAt = Date()
        isScanning = true
        statusText = "Scanning local network…"

        scheduleIdleTimeout()

        if shureSLPCancellable == nil {
            shureSLPCancellable = shureSLPService.$devices
                .receive(on: DispatchQueue.main)
                .sink { [weak self] devices in
                    self?.handleShureSLPDevices(devices)
                }
        }
        if shureSLPActivityCancellable == nil {
            shureSLPActivityCancellable = shureSLPService.$didActivity
                .receive(on: DispatchQueue.main)
                .sink { [weak self] didActivity in
                    guard didActivity else { return }
                    self?.scheduleIdleTimeout()
                }
        }
        if x32M32Cancellable == nil {
            x32M32Cancellable = x32M32Service.$devices
                .receive(on: DispatchQueue.main)
                .sink { [weak self] devices in
                    self?.handleX32M32Devices(devices)
                }
        }
        if x32M32ActivityCancellable == nil {
            x32M32ActivityCancellable = x32M32Service.$didActivity
                .receive(on: DispatchQueue.main)
                .sink { [weak self] didActivity in
                    guard didActivity else { return }
                    self?.scheduleIdleTimeout()
                }
        }
        if quCancellable == nil {
            quCancellable = quService.$devices
                .receive(on: DispatchQueue.main)
                .sink { [weak self] devices in
                    self?.handleQuDevices(devices)
                }
        }
        if dLiveCancellable == nil {
            dLiveCancellable = dLiveService.$devices
                .receive(on: DispatchQueue.main)
                .sink { [weak self] devices in
                    self?.handleDLiveDevices(devices)
                }
        }
        if quActivityCancellable == nil {
            quActivityCancellable = quService.$didActivity
                .receive(on: DispatchQueue.main)
                .sink { [weak self] didActivity in
                    guard didActivity else { return }
                    self?.scheduleIdleTimeout()
                }
        }
        if dLiveActivityCancellable == nil {
            dLiveActivityCancellable = dLiveService.$didActivity
                .receive(on: DispatchQueue.main)
                .sink { [weak self] didActivity in
                    guard didActivity else { return }
                    self?.scheduleIdleTimeout()
                }
        }
        if wingCancellable == nil {
            wingCancellable = wingService.$devices
                .receive(on: DispatchQueue.main)
                .sink { [weak self] devices in
                    self?.handleWingDevices(devices)
                }
        }
        if wingActivityCancellable == nil {
            wingActivityCancellable = wingService.$didActivity
                .receive(on: DispatchQueue.main)
                .sink { [weak self] didActivity in
                    guard didActivity else { return }
                    self?.scheduleIdleTimeout()
                }
        }
        #if DEBUG
        shureSLPService.debugLoggingEnabled = debugLoggingEnabled
        x32M32Service.debugLoggingEnabled = debugLoggingEnabled
        dLiveService.debugLoggingEnabled = debugLoggingEnabled
        quService.debugLoggingEnabled = debugLoggingEnabled
        wingService.debugLoggingEnabled = debugLoggingEnabled
        #endif
        quService.preferredTargetIP = nil
        shureSLPService.autoStopOnIdle = false
        RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
            "scan started mode=external_devices",
            key: "network_scan_started",
            minInterval: 15
        )
        x32M32Service.startScan()
        dLiveService.startScan()
        quService.startScan()
        wingService.startScan()

        if useShureMulticast {
            print("[ExternalDeviceScan] Shure multicast scan started; SLP fallback also starting in parallel")
            recordShureDiscoveryTrace("scan_start source=multicast_plus_slp delay=\(Int(shureFallbackDelaySeconds))s")
            startShureSLPFallbackIfNeeded(reason: "parallel with multicast")
            scheduleShureFallbackIfNeeded()
        } else {
            startShureSLPFallbackIfNeeded(reason: "multicast disabled")
        }

        for entry in serviceEntries {
            if entry.kind == .shureWireless, !useShureMulticast {
                continue
            }
            let parameters = entry.type.hasSuffix("._udp") ? NWParameters.udp : NWParameters.tcp
            let descriptor = NWBrowser.Descriptor.bonjour(type: entry.type, domain: nil)
            let browser = NWBrowser(for: descriptor, using: parameters)

            browser.browseResultsChangedHandler = { results, _ in
                Task { @MainActor [weak self] in
                    self?.handleBrowseResults(results, entry: entry)
                }
            }

            browser.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state, entry.kind == .shureWireless {
                    print("[ExternalDeviceScan] multicast browser ready type=\(entry.type)")
                }
                if case .failed(let error) = state {
                    Task { @MainActor in
                        let message = String(describing: error)
                        if message.contains("NoAuth") {
                            self.statusText = "Local Network permission is required to scan. Enable Relay in System Settings → Privacy & Security → Local Network."
                            RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
                                "scan blocked local_network_permission entry=\(entry.type)",
                                key: "network_scan_local_permission",
                                minInterval: 600,
                                level: "warning"
                            )
                        } else {
                            self.statusText = "Scan error: \(error.localizedDescription)"
                            RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
                                "scan browser_failed entry=\(entry.type) error=\(error.localizedDescription)",
                                key: "network_scan_browser_failed_\(entry.type)",
                                minInterval: 300,
                                level: "warning"
                            )
                        }
                        if entry.kind == .shureWireless {
                            self.startShureSLPFallbackIfNeeded(reason: "multicast error: \(error.localizedDescription)")
                        }
                    }
                }
            }

            browsers.append(browser)
            browser.start(queue: queue)
        }

    }

    func stopScan() {
        scanIdleTimeoutWorkItem?.cancel()
        scanIdleTimeoutWorkItem = nil
        shureFallbackWorkItem?.cancel()
        shureFallbackWorkItem = nil

        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
        if shureFallbackStarted {
            shureSLPService.stop()
        }
        x32M32Service.stopScan()
        dLiveService.stopScan()
        quService.stopScan()
        wingService.stopScan()
        isScanning = false
        statusText = results.isEmpty ? "No devices discovered" : "Scan complete"
        logScanSummary()
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, entry: ServiceEntry) {
        #if DEBUG
        if debugLoggingEnabled, !results.isEmpty {
            print("[ExternalDeviceDiscovery] browse results type=\(entry.type) count=\(results.count)")
            if entry.kind == .shureWireless {
                for result in results {
                    print("[ExternalDeviceDiscovery] multicast result entry=\(entry.type) endpoint=\(result.endpoint)")
                }
            }
        }
        #endif
        if entry.kind == .shureWireless, !entry.isHttpFallback, !results.isEmpty {
            markShureMulticastFound()
        }
        for result in results {
            resolve(result: result, entry: entry)
        }
    }

    private func scheduleShureFallbackIfNeeded() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if !self.shureMulticastFound {
                    self.startShureSLPFallbackIfNeeded(reason: "multicast empty")
                } else {
                    print("[ExternalDeviceScan] multicast produced Shure results; SLP fallback skipped")
                    self.recordShureDiscoveryTrace("scan_multicast_found fallback_skipped=true")
                }
            }
        }
        shureFallbackWorkItem = workItem
        queue.asyncAfter(deadline: .now() + shureFallbackDelaySeconds, execute: workItem)
    }

    private func markShureMulticastFound() {
        guard !shureMulticastFound else { return }
        shureMulticastFound = true
        shureFallbackWorkItem?.cancel()
        shureFallbackWorkItem = nil
        print("[ExternalDeviceScan] using multicast for Shure discovery")
        recordShureDiscoveryTrace("scan_multicast_selected")
    }

    private func startShureSLPFallbackIfNeeded(reason: String) {
        guard !shureFallbackStarted else { return }
        shureFallbackStarted = true
        print("[ExternalDeviceScan] using SLP fallback for Shure discovery reason=\(reason)")
        recordShureDiscoveryTrace("scan_slp_fallback reason=\(reason)")
        shureSLPService.start()
    }

    private func resolve(result: NWBrowser.Result, entry: ServiceEntry) {
        switch result.endpoint {
        case .hostPort(let host, let port):
            addResult(
                name: host.debugDescription,
                host: host,
                port: port,
                entry: entry
            )
        case .service(let name, let type, let domain, _):
            if entry.isHttpFallback, !shouldAllowHttpFallback(name: name) {
                return
            }
            let serviceKey = "\(name)|\(type)|\(domain)|\(entry.type)"
            if let last = resolvedServiceKeys[serviceKey],
               Date().timeIntervalSince(last) < resolveCooldownSeconds {
                return
            }
            let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
            let parameters = entry.type.hasSuffix("._udp") ? NWParameters.udp : NWParameters.tcp
            let connection = NWConnection(to: endpoint, using: parameters)
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let endpoint = connection.currentPath?.remoteEndpoint {
                        if case .hostPort(let host, let port) = endpoint {
                            Task { @MainActor in
                                self.addResult(name: name, host: host, port: port, entry: entry)
                            }
                        }
                    }
                    Task { @MainActor in
                        self.resolvedServiceKeys[serviceKey] = Date()
                    }
                    connection.cancel()
                case .failed:
                    Task { @MainActor in
                        self.resolvedServiceKeys[serviceKey] = Date()
                    }
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
        default:
            break
        }
    }

    private func shouldAllowHttpFallback(name: String) -> Bool {
        if showAllHttpFallback { return true }
        let lower = name.lowercased()
        // Match common Shure product/model strings to avoid generic HTTP noise.
        let keywords = [
            "shure", "ulxd", "qlxd", "slxd", "ad4", "axient",
            "psm", "p10t", "ad4q", "ad4d", "anx4", "adtq", "adtd"
        ]
        return keywords.contains { lower.contains($0) }
    }

    private func addResult(name: String, host: NWEndpoint.Host, port: NWEndpoint.Port, entry: ServiceEntry) {
        guard entry.isDeviceLevel else { return }
        let hostString = host.debugDescription
        let displayHost = Self.displayHost(from: hostString)
        let storedHost = Self.storedHost(from: hostString)
        let portValue = UInt16(port.rawValue)
        let key = "\(entry.kind.rawValue)|\(storedHost)|\(portValue)"
        let isNew = !seenKeys.contains(key)
        if isNew {
            seenKeys.insert(key)
        }

        #if DEBUG
        if debugLoggingEnabled {
            print("[ExternalDeviceDiscovery] found type=\(entry.type) kind=\(entry.kind.rawValue) name=\(name) host=\(hostString) port=\(portValue) provisional=\(entry.isProvisional)")
        }
        #endif
        if entry.kind == .shureWireless {
            print("[ExternalDeviceScan] add name=\(name) kind=\(entry.kind.rawValue) host=\(hostString) port=\(portValue) source=multicast")
            recordShureDiscoveryTrace("result name=\(name) host=\(storedHost) port=\(portValue) source=multicast")
        }

        Task { @MainActor in
            results.append(
                ExternalDeviceDiscoveryResult(
                    kind: entry.kind,
                    name: name,
                    model: nil,
                    consoleModelIdentifier: nil,
                    consoleSubmodelIdentifier: nil,
                    host: hostString,
                    displayHost: displayHost,
                    storedHost: storedHost,
                    port: portValue,
                    serviceType: entry.type,
                    isProvisional: entry.isProvisional,
                    shureCID: nil,
                    shureUacn: nil,
                    shureFctn: nil,
                    shureSdtHost: nil,
                    shureSdtPort: nil,
                    shureDdlURL: nil
                )
            )
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if isNew {
                scheduleIdleTimeout()
            }
        }
    }

    private func handleShureSLPDevices(_ devices: [ShureSLPDiscoveredDevice]) {
        #if DEBUG
        if debugLoggingEnabled, !devices.isEmpty {
            print("[ExternalDeviceDiscovery] SLP devices count=\(devices.count)")
        }
        #endif
        for device in devices {
            guard isLikelyShureSLPDevice(device) else {
                #if DEBUG
                if debugLoggingEnabled {
                    print("[ExternalDeviceDiscovery] ignoring non-Shure SLP device host=\(device.ipAddress) name=\(device.name ?? "nil") model=\(device.model ?? "nil")")
                }
                #endif
                continue
            }
            let slpName = device.name ?? device.model ?? "Shure Device"
            addShureSLPResult(
                name: slpName,
                model: device.model,
                ipAddress: device.ipAddress,
                cid: device.cid,
                sdtHost: device.sdtHost,
                sdtPort: device.sdtPort,
                ddlURL: device.ddlURL,
                uacn: device.name,
                fctn: device.model
            )
        }
    }

    private func isLikelyShureSLPDevice(_ device: ShureSLPDiscoveredDevice) -> Bool {
        if device.cid != nil || device.sdtHost != nil || device.sdtPort != nil || device.ddlURL != nil {
            return true
        }

        if ShureNetworkModel.mostSpecific(from: [device.model, device.name, device.ddlURL]) != nil {
            return true
        }

        let haystacks = [
            device.model,
            device.name,
            device.ddlURL,
            device.attributes["device-description"],
            device.attributes["manufacturer"],
            device.attributes["vendor"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.uppercased() }

        let shureKeywords = [
            "SHURE", "AXIENT", "ULX-D", "ULXD", "QLX-D", "QLXD", "SLX-D", "SLXD",
            "PSM", "P10T", "AD4", "ANX4", "ADTD", "ADTQ"
        ]
        if haystacks.contains(where: { text in
            shureKeywords.contains { text.contains($0) }
        }) {
            return true
        }

        return device.attributes.keys.contains { key in
            let lower = key.lowercased()
            return lower.hasPrefix("acn-") || lower.hasPrefix("csl-esta.")
        }
    }

    private func handleX32M32Devices(_ devices: [X32M32DiscoveredConsole]) {
        #if DEBUG
        if debugLoggingEnabled, !devices.isEmpty {
            print("[ExternalDeviceDiscovery] X32/M32 devices count=\(devices.count)")
        }
        #endif
        for device in devices {
            addX32M32Result(
                name: device.name,
                model: device.model,
                ipAddress: device.ipAddress,
                consoleModelIdentifier: device.consoleModelIdentifier
            )
        }
    }

    private func handleWingDevices(_ devices: [WingDiscoveredConsole]) {
        #if DEBUG
        if debugLoggingEnabled, !devices.isEmpty {
            print("[ExternalDeviceDiscovery] WING devices count=\(devices.count)")
        }
        #endif
        for device in devices {
            addWingResult(name: device.name, model: device.model, ipAddress: device.ipAddress)
        }
    }

    private func handleQuDevices(_ devices: [QuDiscoveredConsole]) {
        #if DEBUG
        if debugLoggingEnabled, !devices.isEmpty {
            print("[ExternalDeviceDiscovery] Qu devices count=\(devices.count)")
        }
        #endif
        for device in devices {
            addQuResult(
                name: device.name,
                model: device.model,
                ipAddress: device.ipAddress,
                consoleModelIdentifier: device.consoleModelIdentifier
            )
        }
    }

    private func handleDLiveDevices(_ devices: [DLiveDiscoveredConsole]) {
        #if DEBUG
        if debugLoggingEnabled, !devices.isEmpty {
            print("[ExternalDeviceDiscovery] dLive devices count=\(devices.count)")
        }
        #endif
        for device in devices {
            addDLiveResult(
                name: device.name,
                model: device.model,
                ipAddress: device.ipAddress,
                port: device.port,
                consoleModelIdentifier: device.consoleModelIdentifier,
                consoleSubmodelIdentifier: device.consoleSubmodelIdentifier
            )
        }
    }

    private func addShureSLPResult(
        name: String,
        model: String?,
        ipAddress: String,
        cid: UUID?,
        sdtHost: String?,
        sdtPort: UInt16?,
        ddlURL: String?,
        uacn: String?,
        fctn: String?
    ) {
        let displayHost = Self.displayHost(from: ipAddress)
        let storedHost = Self.storedHost(from: ipAddress)
        let portValue: UInt16 = 8427
        let key = "\(ExternalDeviceKind.shureWireless.rawValue)|\(storedHost)|\(portValue)"
        let alreadySeen = seenKeys.contains(key)
        if !alreadySeen { seenKeys.insert(key) }

        let existingIndex = results.firstIndex {
            $0.kind == .shureWireless && $0.storedHost == storedHost && $0.port == portValue
        }
        if let idx = existingIndex {
            let existing = results[idx]
            let isSame = existing.name == name
                && existing.model == model
                && existing.host == ipAddress
                && existing.port == portValue
                && existing.shureCID == cid
                && existing.shureUacn == uacn
                && existing.shureFctn == fctn
                && existing.shureSdtHost == sdtHost
                && existing.shureSdtPort == sdtPort
                && existing.shureDdlURL == ddlURL
            if isSame {
                return
            }
        }
        let shouldLog = !alreadySeen || existingIndex != nil

        #if DEBUG
        if debugLoggingEnabled {
            print("[ExternalDeviceDiscovery] found type=slp-udp-8427 kind=\(ExternalDeviceKind.shureWireless.rawValue) name=\(name) host=\(ipAddress) port=\(portValue) provisional=false")
        }
        #endif
        if shouldLog {
            print("[ExternalDeviceScan] add name=\(name) kind=shureWireless host=\(ipAddress) port=\(portValue) source=slp")
            recordShureDiscoveryTrace(
                "result name=\(name) host=\(storedHost) port=\(portValue) source=slp model=\(model ?? "unknown")",
                model: model
            )
        }

        let result = ExternalDeviceDiscoveryResult(
            kind: .shureWireless,
            name: name,
            model: model,
            consoleModelIdentifier: nil,
            consoleSubmodelIdentifier: nil,
            host: ipAddress,
            displayHost: displayHost,
            storedHost: storedHost,
            port: portValue,
            serviceType: "slp-udp-8427",
            isProvisional: false,
            shureCID: cid,
            shureUacn: uacn,
            shureFctn: fctn,
            shureSdtHost: sdtHost,
            shureSdtPort: sdtPort,
            shureDdlURL: ddlURL
        )

        Task { @MainActor in
            if let idx = results.firstIndex(where: { $0.kind == .shureWireless && $0.storedHost == storedHost && $0.port == portValue }) {
                results[idx] = result
            } else if !alreadySeen {
                results.append(result)
            }
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !alreadySeen {
                scheduleIdleTimeout()
            }
        }
    }

    private func addX32M32Result(
        name: String,
        model: String?,
        ipAddress: String,
        consoleModelIdentifier: String?
    ) {
        let displayHost = Self.displayHost(from: ipAddress)
        let storedHost = Self.storedHost(from: ipAddress)
        let portValue: UInt16 = 10023
        let key = "\(ExternalDeviceKind.audioConsole.rawValue)|\(displayHost)"
        let alreadySeen = seenKeys.contains(key)
        if !alreadySeen { seenKeys.insert(key) }

        #if DEBUG
        if debugLoggingEnabled {
            print("[ExternalDeviceDiscovery] found type=osc-udp-10023 kind=\(ExternalDeviceKind.audioConsole.rawValue) name=\(name) host=\(ipAddress) port=\(portValue) provisional=false")
        }
        #endif

        let result = ExternalDeviceDiscoveryResult(
            kind: .audioConsole,
            name: name,
            model: model,
            consoleModelIdentifier: consoleModelIdentifier,
            consoleSubmodelIdentifier: nil,
            host: ipAddress,
            displayHost: displayHost,
            storedHost: storedHost,
            port: portValue,
            serviceType: "osc-udp-10023",
            isProvisional: false,
            shureCID: nil,
            shureUacn: nil,
            shureFctn: nil,
            shureSdtHost: nil,
            shureSdtPort: nil,
            shureDdlURL: nil
        )

        Task { @MainActor in
            if let idx = results.firstIndex(where: { $0.kind == .audioConsole && $0.displayHost == displayHost }) {
                results[idx] = result
            } else if !alreadySeen {
                results.append(result)
            }
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !alreadySeen {
                scheduleIdleTimeout()
            }
        }
    }

    private func addWingResult(name: String, model: String?, ipAddress: String) {
        let displayHost = Self.displayHost(from: ipAddress)
        let storedHost = Self.storedHost(from: ipAddress)
        let portValue: UInt16 = 2223
        let key = "\(ExternalDeviceKind.audioConsole.rawValue)|\(displayHost)"
        let alreadySeen = seenKeys.contains(key)
        if !alreadySeen { seenKeys.insert(key) }

        #if DEBUG
        if debugLoggingEnabled {
            print("[ExternalDeviceDiscovery] found type=osc-udp-2223 kind=\(ExternalDeviceKind.audioConsole.rawValue) name=\(name) host=\(ipAddress) port=\(portValue) provisional=false")
        }
        #endif

        let result = ExternalDeviceDiscoveryResult(
            kind: .audioConsole,
            name: name,
            model: model,
            consoleModelIdentifier: AudioConsoleModel.behringerWing.rawValue,
            consoleSubmodelIdentifier: nil,
            host: ipAddress,
            displayHost: displayHost,
            storedHost: storedHost,
            port: portValue,
            serviceType: "osc-udp-2223",
            isProvisional: false,
            shureCID: nil,
            shureUacn: nil,
            shureFctn: nil,
            shureSdtHost: nil,
            shureSdtPort: nil,
            shureDdlURL: nil
        )

        Task { @MainActor in
            if let idx = results.firstIndex(where: { $0.kind == .audioConsole && $0.displayHost == displayHost }) {
                results[idx] = result
            } else if !alreadySeen {
                results.append(result)
            }
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !alreadySeen {
                scheduleIdleTimeout()
            }
        }
    }

    private func addQuResult(
        name: String,
        model: String?,
        ipAddress: String,
        consoleModelIdentifier: String?
    ) {
        let displayHost = Self.displayHost(from: ipAddress)
        let storedHost = Self.storedHost(from: ipAddress)
        let portValue: UInt16 = 51325
        let key = "\(ExternalDeviceKind.audioConsole.rawValue)|\(displayHost)"
        let alreadySeen = seenKeys.contains(key)
        if !alreadySeen { seenKeys.insert(key) }

        #if DEBUG
        if debugLoggingEnabled {
            print("[ExternalDeviceDiscovery] found type=tcp-51325 kind=\(ExternalDeviceKind.audioConsole.rawValue) name=\(name) host=\(ipAddress) port=\(portValue) provisional=false")
        }
        #endif

        let result = ExternalDeviceDiscoveryResult(
            kind: .audioConsole,
            name: name,
            model: model,
            consoleModelIdentifier: consoleModelIdentifier,
            consoleSubmodelIdentifier: nil,
            host: ipAddress,
            displayHost: displayHost,
            storedHost: storedHost,
            port: portValue,
            serviceType: "tcp-51325",
            isProvisional: false,
            shureCID: nil,
            shureUacn: nil,
            shureFctn: nil,
            shureSdtHost: nil,
            shureSdtPort: nil,
            shureDdlURL: nil
        )

        Task { @MainActor in
            if let idx = results.firstIndex(where: { $0.kind == .audioConsole && $0.displayHost == displayHost }) {
                let existing = results[idx]
                if shouldReplaceQuScanResult(existing: existing, replacement: result) {
                    results[idx] = result
                }
            } else if !alreadySeen {
                results.append(result)
            }
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !alreadySeen {
                scheduleIdleTimeout()
            }
        }
    }

    private func shouldReplaceQuScanResult(existing: ExternalDeviceDiscoveryResult,
                                           replacement: ExternalDeviceDiscoveryResult) -> Bool {
        guard existing.kind == .audioConsole, replacement.kind == .audioConsole else { return true }

        if existing.consoleModelIdentifier == AudioConsoleModel.allenHeathDlive.rawValue
            || existing.consoleModelIdentifier == AudioConsoleModel.allenHeathAvantis.rawValue
            || existing.consoleModelIdentifier == AudioConsoleModel.allenHeathSq.rawValue {
            return false
        }

        if existing.consoleModelIdentifier == AudioConsoleModel.allenHeathQu.rawValue {
            if existing.model != nil, replacement.model == nil {
                return false
            }
        }

        return true
    }

    private func addDLiveResult(
        name: String,
        model: String?,
        ipAddress: String,
        port: UInt16,
        consoleModelIdentifier: String?,
        consoleSubmodelIdentifier: String?
    ) {
        let displayHost = Self.displayHost(from: ipAddress)
        let storedHost = Self.storedHost(from: ipAddress)
        let key = "\(ExternalDeviceKind.audioConsole.rawValue)|\(displayHost)"
        let alreadySeen = seenKeys.contains(key)
        if !alreadySeen { seenKeys.insert(key) }

        #if DEBUG
        if debugLoggingEnabled {
            print("[ExternalDeviceDiscovery] found type=tcp-\(port) kind=\(ExternalDeviceKind.audioConsole.rawValue) name=\(name) host=\(ipAddress) port=\(port) provisional=false")
        }
        #endif

        let result = ExternalDeviceDiscoveryResult(
            kind: .audioConsole,
            name: name,
            model: model,
            consoleModelIdentifier: consoleModelIdentifier,
            consoleSubmodelIdentifier: consoleSubmodelIdentifier,
            host: ipAddress,
            displayHost: displayHost,
            storedHost: storedHost,
            port: port,
            serviceType: "tcp-\(port)",
            isProvisional: false,
            shureCID: nil,
            shureUacn: nil,
            shureFctn: nil,
            shureSdtHost: nil,
            shureSdtPort: nil,
            shureDdlURL: nil
        )

        Task { @MainActor in
            if let idx = results.firstIndex(where: { $0.kind == .audioConsole && $0.displayHost == displayHost }) {
                let existing = results[idx]
                if shouldReplaceDLiveScanResult(existing: existing, replacement: result) {
                    results[idx] = result
                }
            } else if !alreadySeen {
                results.append(result)
            }
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !alreadySeen {
                scheduleIdleTimeout()
            }
        }
    }

    private func shouldReplaceDLiveScanResult(existing: ExternalDeviceDiscoveryResult,
                                              replacement: ExternalDeviceDiscoveryResult) -> Bool {
        guard existing.kind == .audioConsole, replacement.kind == .audioConsole else { return true }
        guard existing.consoleModelIdentifier == AudioConsoleModel.allenHeathDlive.rawValue,
              replacement.consoleModelIdentifier == AudioConsoleModel.allenHeathDlive.rawValue else {
            return true
        }

        let preferredPort: UInt16 = 51325
        if existing.port != preferredPort, replacement.port == preferredPort {
            return true
        }
        if existing.port == preferredPort, replacement.port != preferredPort {
            return false
        }

        let existingName = existing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementName = replacement.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isLowValueDLiveScanName(replacementName), isLowValueDLiveScanName(existingName) {
            return true
        }
        return false
    }

    private func isLowValueDLiveScanName(_ name: String) -> Bool {
        guard !name.isEmpty else { return true }
        if name.count < 3 { return true }
        return name.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private func scheduleIdleTimeout() {
        scanIdleTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.stopScan()
        }
        scanIdleTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scanIdleTimeoutSeconds, execute: workItem)
    }

    private static func displayHost(from host: String) -> String {
        if let percentIndex = host.firstIndex(of: "%") {
            return String(host[..<percentIndex])
        }
        return host
    }

    private static func storedHost(from host: String) -> String {
        let trimmed = displayHost(from: host)
        // Keep IPv6 link-local scope if needed; strip for IPv4 or global IPv6.
        if host.contains("%"), host.lowercased().hasPrefix("fe80:") {
            return host
        }
        return trimmed
    }

    private func logScanSummary() {
        let duration = scanStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let groupedByService = Dictionary(grouping: results, by: \.serviceType)
        let serviceSummary = groupedByService
            .map { key, values in "\(key)=\(values.count)" }
            .sorted()
            .joined(separator: ", ")
        let deviceKindSummary = Dictionary(grouping: results, by: \.kind)
            .map { key, values in "\(key.rawValue)=\(values.count)" }
            .sorted()
            .joined(separator: ", ")
        let shureMode = shureFallbackStarted ? "slp_fallback" : (shureMulticastFound ? "multicast" : "none")

        RelayDiagnosticsStore.shared.recordNetworkScannerTrace(
            "scan finished duration=\(String(format: "%.1f", duration))s results=\(results.count) kinds=[\(deviceKindSummary.isEmpty ? "none" : deviceKindSummary)] services=[\(serviceSummary.isEmpty ? "none" : serviceSummary)] shure_mode=\(shureMode)",
            key: "network_scan_summary",
            minInterval: 10
        )
        scanStartedAt = nil
    }
}

struct DLiveDiscoveredConsole: Identifiable, Hashable {
    let id: UUID
    let ipAddress: String
    let name: String
    let model: String?
    let consoleModelIdentifier: String?
    let consoleSubmodelIdentifier: String?
    let port: UInt16

    init(ipAddress: String,
         name: String,
         model: String?,
         consoleModelIdentifier: String?,
         consoleSubmodelIdentifier: String?,
         port: UInt16) {
        self.id = UUID()
        self.ipAddress = ipAddress
        self.name = name
        self.model = model
        self.consoleModelIdentifier = consoleModelIdentifier
        self.consoleSubmodelIdentifier = consoleSubmodelIdentifier
        self.port = port
    }
}

final class DLiveDiscoveryService: ObservableObject {
    @Published private(set) var devices: [DLiveDiscoveredConsole] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var didActivity: Bool = false
    var debugLoggingEnabled: Bool = false

    private struct ProbeEndpoint {
        let port: UInt16
        let name: String
        let submodel: String
    }

    private let probeEndpoints: [ProbeEndpoint] = [
        ProbeEndpoint(port: 51325, name: "dLive MixRack", submodel: "dlive_mixrack"),
        ProbeEndpoint(port: 51328, name: "dLive Surface", submodel: "dlive_surface")
    ]
    private let queue = DispatchQueue(label: "DLiveDiscovery.queue", qos: .utility, attributes: .concurrent)
    private let stateQueue = DispatchQueue(label: "DLiveDiscovery.state")
    private let maxConcurrentProbes = 8
    private let probeTimeout: TimeInterval = 2.0
    private let responseTimeout: TimeInterval = 2.5
    private let probeThrottle: TimeInterval = 0.003

    private var devicesByEndpoint: [String: DLiveDiscoveredConsole] = [:]
    private var activeConnections: [String: NWConnection] = [:]
    private var timeoutWorkItems: [String: DispatchWorkItem] = [:]
    private var isCancelled: Bool = false

    func startScan() {
        guard !isRunning else { return }
        devices.removeAll()
        devicesByEndpoint.removeAll()
        isCancelled = false
        isRunning = true
        log("Started scan")

        queue.async { [weak self] in
            self?.probeSubnets()
        }
    }

    func stopScan() {
        isCancelled = true
        let workItems = stateQueue.sync { timeoutWorkItems }
        for (_, item) in workItems {
            item.cancel()
        }
        stateQueue.sync { timeoutWorkItems.removeAll() }

        let connections = stateQueue.sync { activeConnections }
        for (_, connection) in connections {
            connection.cancel()
        }
        stateQueue.sync { activeConnections.removeAll() }
        isRunning = false
    }

    private func log(_ message: String) {
        #if DEBUG
        if debugLoggingEnabled {
            print("[DLiveDiscovery] \(message)")
        }
        #endif
    }

    private func markActivity() {
        DispatchQueue.main.async { [weak self] in
            self?.didActivity = true
            self?.didActivity = false
        }
    }

    private func probeSubnets() {
        let targets = candidateIPv4Targets()
        guard !targets.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: maxConcurrentProbes)
        var scheduledIndex = 0
        for ip in targets {
            for endpoint in probeEndpoints {
                if isCancelled { break }
                semaphore.wait()
                let delay = probeThrottle * Double(scheduledIndex)
                scheduledIndex += 1
                queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    // self can be nil if the owning service was deallocated (e.g. the
                    // wizard step was popped) while this probe was still staggered/pending.
                    // The signal() must still fire to balance this probe's semaphore.wait()
                    // above — skipping it leaves the semaphore under-signaled and crashes
                    // libdispatch when its last reference is released.
                    guard let self else {
                        semaphore.signal()
                        return
                    }
                    self.probeHost(ip, endpoint: endpoint) {
                        semaphore.signal()
                    }
                }
            }
            if isCancelled { break }
        }
    }

    private func probeHost(_ ip: String, endpoint: ProbeEndpoint, completion: @escaping () -> Void) {
        guard !isCancelled else {
            completion()
            return
        }

        let key = "\(ip):\(endpoint.port)"
        let connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: endpoint.port) ?? 0,
            using: .tcp
        )
        stateQueue.sync {
            activeConnections[key] = connection
        }

        let timeoutWorkItem = DispatchWorkItem { [weak self, weak connection] in
            connection?.cancel()
            self?.stateQueue.sync {
                self?.activeConnections.removeValue(forKey: key)
                self?.timeoutWorkItems.removeValue(forKey: key)
            }
            completion()
        }
        stateQueue.sync {
            timeoutWorkItems[key] = timeoutWorkItem
        }
        queue.asyncAfter(deadline: .now() + probeTimeout, execute: timeoutWorkItem)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Only reachable while self is alive: a connection that outlives
                // DLiveDiscoveryService has already been through stopScan()'s cancel(),
                // and .ready never follows a cancel.
                guard let self else { return }
                self.log("Connected \(key)")
                self.markActivity()
                self.rescheduleTimeout(for: key, seconds: self.responseTimeout, completion: completion)
                let probe = self.buildDetectionProbe()
                connection.send(content: probe, completion: .contentProcessed({ _ in }))
                self.receiveIdentity(on: connection, ip: ip, endpoint: endpoint, completion: completion)
            case .failed:
                // completion() must run even if self has been deallocated (e.g. the
                // owning view was torn down right after stopScan()) — it's what
                // balances this probe's semaphore.wait() in probeSubnets() with a
                // signal(). Skipping it leaves the semaphore under-signaled and
                // crashes when its last reference is released.
                if let self {
                    self.cleanupConnection(for: key)
                }
                completion()
            case .cancelled:
                // Same reasoning as .failed above — must fire unconditionally.
                if let self {
                    self.cleanupConnection(for: key)
                }
                completion()
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveIdentity(on connection: NWConnection,
                                 ip: String,
                                 endpoint: ProbeEndpoint,
                                 completion: @escaping () -> Void) {
        var buffer = Data()

        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, _, error in
                guard let self else { return }

                if let data, !data.isEmpty {
                    buffer.append(data)
                    self.markActivity()
                    if let discovered = self.parseDiscoveryReply(from: buffer, ipAddress: ip, endpoint: endpoint) {
                        Task { @MainActor [weak self] in
                            self?.addDiscovered(discovered)
                        }
                        self.cleanupConnection(for: "\(ip):\(endpoint.port)")
                        completion()
                        return
                    }
                }

                if error != nil {
                    self.cleanupConnection(for: "\(ip):\(endpoint.port)")
                    completion()
                    return
                }

                receiveNext()
            }
        }

        receiveNext()
    }

    private func addDiscovered(_ discovered: DLiveDiscoveredConsole) {
        let key = "\(discovered.ipAddress):\(discovered.port)"
        if let existing = devicesByEndpoint[key] {
            if existing != discovered {
                devicesByEndpoint[key] = discovered
                if let idx = devices.firstIndex(where: { $0.ipAddress == discovered.ipAddress && $0.port == discovered.port }) {
                    devices[idx] = discovered
                }
            }
        } else {
            devicesByEndpoint[key] = discovered
            devices.append(discovered)
        }
    }

    private func cleanupConnection(for key: String) {
        let workItem = stateQueue.sync { timeoutWorkItems[key] }
        workItem?.cancel()
        _ = stateQueue.sync { timeoutWorkItems.removeValue(forKey: key) }
        let connection = stateQueue.sync { activeConnections[key] }
        connection?.cancel()
        _ = stateQueue.sync { activeConnections.removeValue(forKey: key) }
    }

    private func rescheduleTimeout(for key: String, seconds: TimeInterval, completion: @escaping () -> Void) {
        stateQueue.sync {
            if let existing = timeoutWorkItems[key] {
                existing.cancel()
            }

            let workItem = DispatchWorkItem { [weak self] in
                self?.cleanupConnection(for: key)
                completion()
            }
            timeoutWorkItems[key] = workItem
            queue.asyncAfter(deadline: .now() + seconds, execute: workItem)
        }
    }

    private func buildDetectionProbe() -> Data {
        var bytes: [UInt8] = []
        for baseChannel in 0...11 {
            bytes.append(contentsOf: [
                0xF0, 0x00, 0x00, 0x1A, 0x50, 0x10, 0x01, 0x00,
                UInt8(baseChannel), 0x01, 0x60, 0xF7
            ])
        }
        return Data(bytes)
    }

    private func parseDiscoveryReply(from data: Data,
                                     ipAddress: String,
                                     endpoint: ProbeEndpoint) -> DLiveDiscoveredConsole? {
        let messages = extractSysExMessages(from: data)
        for message in messages {
            let bytes = [UInt8](message)
            guard bytes.count >= 12 else { continue }
            let header: [UInt8] = [0xF0, 0x00, 0x00, 0x1A, 0x50, 0x10, 0x01, 0x00]
            guard bytes.starts(with: header) else { continue }
            guard (0x00...0x0B).contains(bytes[8]) else { continue }
            guard bytes[9] == 0x02 else { continue }
            guard bytes[10] == 0x60 else { continue }

            let nameBytes = Array(bytes[11..<(bytes.count - 1)])
            let decodedName = String(bytes: nameBytes, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String = {
                guard let decodedName, !decodedName.isEmpty else { return endpoint.name }
                if decodedName.count < 3 {
                    return endpoint.name
                }
                let isNumericOnly = decodedName.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
                return isNumericOnly ? endpoint.name : decodedName
            }()

            return DLiveDiscoveredConsole(
                ipAddress: ipAddress,
                name: displayName,
                model: "Allen & Heath dLive",
                consoleModelIdentifier: AudioConsoleModel.allenHeathDlive.rawValue,
                consoleSubmodelIdentifier: endpoint.submodel,
                port: endpoint.port
            )
        }

        return nil
    }

    private func extractSysExMessages(from data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var messages: [Data] = []
        var startIndex: Int? = nil

        for (idx, byte) in bytes.enumerated() {
            if byte == 0xF0 {
                startIndex = idx
            } else if byte == 0xF7, let start = startIndex, start <= idx {
                messages.append(Data(bytes[start...idx]))
                startIndex = nil
            }
        }

        return messages
    }

    private struct IPv4Subnet: Hashable {
        let network: UInt32
        let netmask: UInt32
        let address: UInt32
    }

    private func candidateIPv4Targets() -> [String] {
        guard let currentIP = currentIPv4(preferWiFi: true),
              let subnet = subnetFromCurrentIP(currentIP) else {
            return []
        }

        return candidateHosts(for: subnet).map { ipv4String(from: $0) }
    }

    private func subnetFromCurrentIP(_ ipString: String) -> IPv4Subnet? {
        let parts = ipString.split(separator: ".")
        guard parts.count == 4,
              let a = UInt32(parts[0]),
              let b = UInt32(parts[1]),
              let c = UInt32(parts[2]),
              let d = UInt32(parts[3]) else { return nil }
        let ip = (a << 24) | (b << 16) | (c << 8) | d
        let netmask: UInt32 = 0xFFFFFE00
        let network = ip & netmask
        return IPv4Subnet(network: network, netmask: netmask, address: ip)
    }

    private func currentIPv4(preferWiFi: Bool) -> String? {
        #if canImport(Darwin)
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var wifiCandidate: String?
        var firstPrivate: String?

        var ptr = first
        while true {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET else {
                if let next = ifa.ifa_next { ptr = next } else { break }
                continue
            }

            guard let cName = ifa.ifa_name else {
                if let next = ifa.ifa_next { ptr = next } else { break }
                continue
            }
            let name = String(cString: cName)

            var addrIn = unsafeBitCast(addr.pointee, to: sockaddr_in.self)
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let addrPtr = withUnsafePointer(to: &addrIn.sin_addr) {
                $0.withMemoryRebound(to: in_addr.self, capacity: 1) { $0 }
            }
            inet_ntop(AF_INET, addrPtr, &buf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: buf)

            if isPrivateIPv4(ip) {
                if preferWiFi, (name == "en0" || name == "en1") {
                    wifiCandidate = ip
                }
                if firstPrivate == nil {
                    firstPrivate = ip
                }
            }

            if let next = ifa.ifa_next { ptr = next } else { break }
        }

        return wifiCandidate ?? firstPrivate
        #else
        return nil
        #endif
    }

    private func isPrivateIPv4(_ ip: String) -> Bool {
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let comps = ip.split(separator: ".")
            if comps.count >= 2, let second = Int(comps[1]), (16...31).contains(second) {
                return true
            }
        }
        if ip.hasPrefix("192.168.") { return true }
        return false
    }

    private func candidateHosts(for subnet: IPv4Subnet) -> [UInt32] {
        let hostCount = hostCountFor(subnet: subnet)
        let maxHosts = 512

        if hostCount <= 0 { return [] }

        let (start, end): (UInt32, UInt32)
        if hostCount <= maxHosts {
            start = subnet.network + 1
            end = subnet.network + UInt32(hostCount)
        } else {
            let base = subnet.address & 0xFFFFFF00
            start = base + 1
            end = base + 254
        }

        if end < start { return [] }
        return (start...end).map { $0 }
    }

    private func hostCountFor(subnet: IPv4Subnet) -> Int {
        let broadcast = subnet.network | ~subnet.netmask
        if broadcast <= subnet.network { return 0 }
        return Int(broadcast - subnet.network - 1)
    }

    private func ipv4String(from value: UInt32) -> String {
        var addr = in_addr(s_addr: value.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        _ = inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }
}
