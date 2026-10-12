import Foundation
import CoreGraphics

#if os(macOS)
import Darwin
#endif

nonisolated enum NDIReceiverPixelFormat: String, Codable, Hashable {
    case bgra8
    case uyvy
    case rgba16f
    case unknown
}

nonisolated struct NDIReceiverConfiguration: Hashable {
    let sourceID: String
    let sourceName: String
    let sourceURLAddress: String?
    let interfaceID: String?
    let qualityTier: NDIModuleModel.QualityTier
    let fpsCap: Int
    let audioEnabled: Bool
    let preferLowLatency: Bool
}

nonisolated struct NDIReceiverConnectionInfo: Equatable, Hashable {
    var sourceName: String
    var interfaceID: String?
    var resolution: CGSize
    var frameRate: Double
}

nonisolated struct NDIFrame {
    var frameNumber: UInt64
    var width: Int
    var height: Int
    var pixelFormat: NDIReceiverPixelFormat
    var timestamp: Date
    var estimatedFPS: Double
    var cgImage: CGImage?

    var resolutionText: String {
        "\(width)x\(height)"
    }
}

nonisolated enum NDIReceiverEvent {
    case connecting
    case connected(NDIReceiverConnectionInfo)
    case frame(NDIFrame)
    case disconnected(String?)
    case failed(String)
}

protocol NDISDKDiscovering {
    func refreshSources(preferredInterfaceID: String?) async -> [NDISourceDescriptor]
}

protocol NDISDKReceiving {
    // nonisolated so the connection loop (Task.detached, nonisolated static) can
    // call these without main-actor hops. Conformances satisfy this automatically
    // for plain-class implementations that don't inherit actor isolation.
    nonisolated var events: AsyncStream<NDIReceiverEvent> { get }
    nonisolated func start()
    nonisolated func stop()
}

enum NDISDKFactory {
    // nonisolated so NDIStreamRegistry (@MainActor) and the connection loop
    // (nonisolated static Task.detached) can both call these freely.
    nonisolated static func makeDiscoveryBackend() -> any NDISDKDiscovering {
#if os(macOS)
        let runtime = NDIRuntime.shared
        if runtime.isReady {
            return NDIRealtimeDiscovery(runtime: runtime)
        }
        return NDIUnavailableDiscovery(reason: runtime.loadError ?? "NDI runtime failed to load.")
#elseif os(iOS) && !targetEnvironment(simulator)
        let runtime = NDIIOSRuntime.shared
        if runtime.isReady {
            return NDIRealtimeDiscovery(runtime: runtime)
        }
        return NDIUnavailableDiscovery(reason: runtime.loadError ?? "NDI runtime failed to load.")
#else
        return NDINullSDKDiscovery()
#endif
    }

    nonisolated static func makeReceiver(configuration: NDIReceiverConfiguration) -> any NDISDKReceiving {
#if os(macOS)
        let runtime = NDIRuntime.shared
        if runtime.isReady {
            return NDIRealtimeReceiver(configuration: configuration, runtime: runtime)
        }
        return NDIUnavailableReceiver(reason: runtime.loadError ?? "NDI runtime failed to load.")
#elseif os(iOS) && !targetEnvironment(simulator)
        let runtime = NDIIOSRuntime.shared
        if runtime.isReady {
            return NDIRealtimeReceiver(configuration: configuration, runtime: runtime)
        }
        return NDIUnavailableReceiver(reason: runtime.loadError ?? "NDI runtime failed to load.")
#else
        return NDINullSDKReceiver(configuration: configuration)
#endif
    }
}

private struct NDINullSDKDiscovery: NDISDKDiscovering {
    func refreshSources(preferredInterfaceID: String?) async -> [NDISourceDescriptor] {
        return []
    }
}

private final class NDINullSDKReceiver: NDISDKReceiving {
    let events: AsyncStream<NDIReceiverEvent>

    private let configuration: NDIReceiverConfiguration
    private var continuation: AsyncStream<NDIReceiverEvent>.Continuation?
    private var frameTask: Task<Void, Never>?

    init(configuration: NDIReceiverConfiguration) {
        self.configuration = configuration
        var storedContinuation: AsyncStream<NDIReceiverEvent>.Continuation?
        self.events = AsyncStream { continuation in
            storedContinuation = continuation
        }
        self.continuation = storedContinuation
    }

    func start() {
        guard frameTask == nil else { return }
        continuation?.yield(.connecting)

        frameTask = Task { [configuration, continuation] in
            guard let continuation else { return }

            let connectionInfo = NDIReceiverConnectionInfo(
                sourceName: configuration.sourceName.isEmpty ? configuration.sourceID : configuration.sourceName,
                interfaceID: configuration.interfaceID,
                resolution: configuration.qualityTier == .live
                    ? CGSize(width: 1920, height: 1080)
                    : CGSize(width: 1280, height: 720),
                frameRate: min(Double(configuration.fpsCap), configuration.qualityTier.defaultFPS)
            )
            continuation.yield(.connected(connectionInfo))

            let fps = max(1.0, min(Double(configuration.fpsCap), configuration.qualityTier.defaultFPS))
            let intervalNanoseconds = UInt64((1.0 / fps) * 1_000_000_000)

            var frameNumber: UInt64 = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                frameNumber += 1
                let frame = NDIFrame(
                    frameNumber: frameNumber,
                    width: Int(connectionInfo.resolution.width),
                    height: Int(connectionInfo.resolution.height),
                    pixelFormat: .bgra8,
                    timestamp: Date(),
                    estimatedFPS: fps,
                    cgImage: nil
                )
                continuation.yield(.frame(frame))
            }
        }
    }

    func stop() {
        frameTask?.cancel()
        frameTask = nil
        continuation?.yield(.disconnected(nil))
    }
}

private final class NDIUnavailableDiscovery: NDISDKDiscovering {
    private let reason: String

    nonisolated init(reason: String) {
        self.reason = reason
    }

    func refreshSources(preferredInterfaceID: String?) async -> [NDISourceDescriptor] {
        _ = preferredInterfaceID
        return []
    }
}

private final class NDIUnavailableReceiver: NDISDKReceiving {
    let events: AsyncStream<NDIReceiverEvent>

    private let reason: String
    private var continuation: AsyncStream<NDIReceiverEvent>.Continuation?

    nonisolated init(reason: String) {
        self.reason = reason
        var storedContinuation: AsyncStream<NDIReceiverEvent>.Continuation?
        self.events = AsyncStream { continuation in
            storedContinuation = continuation
        }
        self.continuation = storedContinuation
    }

    func start() {
        continuation?.yield(.failed(reason))
    }

    func stop() {
        continuation?.yield(.disconnected(nil))
    }
}

#if os(macOS)
private enum NDILogger {
    nonisolated static func log(_ message: String) {
        print("[NDI] \(message)")
    }
}

private nonisolated final class NDIRuntime: @unchecked Sendable {
    typealias V63LoadFunction = @convention(c) () -> UnsafePointer<NDIlib_v6_3>?
    typealias V6LoadFunction = @convention(c) () -> UnsafePointer<NDIlib_v6>?

    static let shared = NDIRuntime()

    nonisolated(unsafe) let handle: UnsafeMutableRawPointer?
    nonisolated(unsafe) let api: UnsafePointer<NDIlib_v6_3>?
    let loadError: String?
    private var discoveryFinder: NDIlib_find_instance_t?
    private let discoveryQueue = DispatchQueue(label: "relay.ndi.discovery")

    nonisolated var isReady: Bool {
        api != nil
    }

    private init() {
        var loadedHandle: UnsafeMutableRawPointer?
        var loadedAPI: UnsafePointer<NDIlib_v6_3>?
        var failureReason = "NDI runtime could not be loaded."

        for candidate in Self.candidateLibraryPaths() {
            NDILogger.log("Attempting runtime load from \(candidate)")
            guard let handle = dlopen(candidate, RTLD_LOCAL | RTLD_LAZY) else {
                if let message = dlerrorMessage() {
                    failureReason = "dlopen failed for \(candidate): \(message)"
                }
                continue
            }

            let api = Self.loadAPI(handle: handle)
            guard let api else {
                failureReason = "NDI runtime loaded from \(candidate) but NDIlib_v6 load symbol was missing."
                dlclose(handle)
                continue
            }

            guard let initialize = api.pointee.initialize,
                  initialize() else {
                failureReason = "NDI runtime loaded from \(candidate) but initialize() returned false."
                dlclose(handle)
                continue
            }

            loadedHandle = handle
            loadedAPI = api
            failureReason = ""
            NDILogger.log("Runtime loaded successfully from \(candidate)")
            break
        }

        handle = loadedHandle
        api = loadedAPI
        loadError = loadedAPI == nil ? failureReason : nil
        if let loadError {
            NDILogger.log("Runtime unavailable: \(loadError)")
        }
    }

    deinit {
        if let api, let discoveryFinder {
            api.pointee.find_destroy(discoveryFinder)
        }
        if let api {
            api.pointee.destroy()
        }
        if let handle {
            dlclose(handle)
        }
    }

    func discoverSources(preferredInterfaceID: String?) -> [NDISourceDescriptor] {
        discoveryQueue.sync {
            guard let api else { return [] }
            NDILogger.log("Refreshing sources (preferred NIC: \(preferredInterfaceID ?? "auto"))")
            guard let finder = ensureDiscoveryFinder(api: api) else {
                NDILogger.log("Failed to create NDI finder instance")
                return []
            }

            let immediateResults = currentSources(
                finder: finder,
                preferredInterfaceID: preferredInterfaceID
            )
            if !immediateResults.isEmpty {
                logDiscoveredSources(immediateResults)
                return immediateResults
            }

            // 1500 ms is enough for local-network discovery and matches the original
            // value. 5000 ms caused two back-to-back 5-second main-thread hangs at
            // launch when multiple NDI modules triggered concurrent refresh requests.
            let changed = api.pointee.find_wait_for_sources(finder, 1_500)
            NDILogger.log("Source wait completed (changed: \(changed))")

            let waitedResults = currentSources(
                finder: finder,
                preferredInterfaceID: preferredInterfaceID
            )
            logDiscoveredSources(waitedResults)
            return waitedResults
        }
    }

    private func ensureDiscoveryFinder(api: UnsafePointer<NDIlib_v6_3>) -> NDIlib_find_instance_t? {
        if let discoveryFinder {
            return discoveryFinder
        }

        var finderConfig = NDIlib_find_create_t()
        finderConfig.show_local_sources = true
        finderConfig.p_groups = nil
        finderConfig.p_extra_ips = nil

        let finder = api.pointee.find_create_v2(&finderConfig)
        discoveryFinder = finder
        if finder != nil {
            NDILogger.log("Created persistent NDI finder instance")
        }
        return finder
    }

    private func currentSources(
        finder: NDIlib_find_instance_t?,
        preferredInterfaceID: String?
    ) -> [NDISourceDescriptor] {
        var sourceCount: UInt32 = 0
        guard let api,
              let sources = api.pointee.find_get_current_sources(finder, &sourceCount),
              sourceCount > 0 else {
            return []
        }

        let interfaceHint = preferredInterfaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (0..<Int(sourceCount)).compactMap { index in
            let source = sources[index]
            let ndiName = Self.string(from: source.p_ndi_name)
            guard !ndiName.isEmpty else { return nil }
            return NDISourceDescriptor(
                id: ndiName,
                name: ndiName,
                hostName: Self.hostName(from: ndiName),
                interfaceHint: interfaceHint,
                urlAddress: Self.string(from: source.p_url_address)
            )
        }
    }

    private func logDiscoveredSources(_ results: [NDISourceDescriptor]) {
        NDILogger.log("Discovered \(results.count) source(s)")
        guard !results.isEmpty else { return }

        let summary = results
            .map { descriptor in
                if let hostName = descriptor.hostName, !hostName.isEmpty {
                    return "\(descriptor.name) @ \(hostName)"
                }
                return descriptor.name
            }
            .joined(separator: " | ")
        NDILogger.log("Sources: \(summary)")
    }

    private nonisolated static func loadAPI(handle: UnsafeMutableRawPointer) -> UnsafePointer<NDIlib_v6_3>? {
        if let symbol = dlsym(handle, "NDIlib_v6_3_load") {
            let function = unsafeBitCast(symbol, to: V63LoadFunction.self)
            return function()
        }

        if let symbol = dlsym(handle, "NDIlib_v6_load") {
            let function = unsafeBitCast(symbol, to: V6LoadFunction.self)
            return UnsafeRawPointer(function())?.assumingMemoryBound(to: NDIlib_v6_3.self)
        }

        return nil
    }

    private nonisolated static func candidateLibraryPaths() -> [String] {
        var paths: [String] = []

        if let runtimeDirectory = ProcessInfo.processInfo.environment["NDI_RUNTIME_DIR_V6"],
           !runtimeDirectory.isEmpty {
            paths.append(URL(fileURLWithPath: runtimeDirectory).appendingPathComponent("libndi.dylib").path)
        }

        if let frameworksPath = Bundle.main.privateFrameworksPath {
            paths.append(URL(fileURLWithPath: frameworksPath).appendingPathComponent("libndi.dylib").path)
        }

        if let executableURL = Bundle.main.executableURL {
            let sibling = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("libndi.dylib")
                .path
            paths.append(sibling)
        }

        paths.append("/usr/local/lib/libndi.dylib")

        paths.append("libndi.dylib")

        var uniquePaths: [String] = []
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            uniquePaths.append(path)
        }
        return uniquePaths
    }

    private nonisolated static func string(from pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }

    private nonisolated static func hostName(from ndiName: String) -> String? {
        guard let range = ndiName.range(of: " (") else { return nil }
        let host = ndiName[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? nil : host
    }
}

private nonisolated func dlerrorMessage() -> String? {
    guard let rawError = dlerror() else { return nil }
    return String(cString: rawError)
}

private nonisolated final class NDIRealtimeDiscovery: NDISDKDiscovering {
    private let runtime: NDIRuntime

    nonisolated init(runtime: NDIRuntime) {
        self.runtime = runtime
    }

    func refreshSources(preferredInterfaceID: String?) async -> [NDISourceDescriptor] {
        // Bridge the blocking discoveryQueue.sync call through a real GCD background
        // thread so it can never accidentally run on the cooperative thread pool's
        // main-thread slot — which would cause the visible 5-second main-thread hang.
        let runtime = self.runtime
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let sources = runtime.discoverSources(preferredInterfaceID: preferredInterfaceID)
                continuation.resume(returning: sources)
            }
        }
    }
}

private nonisolated final class NDIRealtimeReceiver: NDISDKReceiving {
    let events: AsyncStream<NDIReceiverEvent>

    private let configuration: NDIReceiverConfiguration
    private let runtime: NDIRuntime
    private var continuation: AsyncStream<NDIReceiverEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?

    nonisolated init(configuration: NDIReceiverConfiguration, runtime: NDIRuntime) {
        self.configuration = configuration
        self.runtime = runtime
        var storedContinuation: AsyncStream<NDIReceiverEvent>.Continuation?
        self.events = AsyncStream { continuation in
            storedContinuation = continuation
        }
        self.continuation = storedContinuation
    }

    func start() {
        guard receiveTask == nil else { return }
        continuation?.yield(.connecting)

        receiveTask = Task.detached(priority: .userInitiated) { [configuration, runtime, continuation] in
            guard let continuation else { return }
            Self.runCaptureLoop(
                configuration: configuration,
                runtime: runtime,
                continuation: continuation
            )
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        continuation?.yield(.disconnected(nil))
    }

    private nonisolated static func runCaptureLoop(
        configuration: NDIReceiverConfiguration,
        runtime: NDIRuntime,
        continuation: AsyncStream<NDIReceiverEvent>.Continuation
    ) {
        guard let api = runtime.api else {
            continuation.yield(.failed(runtime.loadError ?? "NDI runtime unavailable."))
            return
        }

        let desiredSourceName = configuration.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSourceName = configuration.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let receiverSourceName = desiredSourceName.isEmpty ? fallbackSourceName : desiredSourceName
        let receiverSourceURL = configuration.sourceURLAddress?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !receiverSourceName.isEmpty else {
            continuation.yield(.failed("Select an NDI source before starting the receiver."))
            return
        }

        let bandwidth = receiverBandwidth(for: configuration.qualityTier)
        let colorFormat = receiverColorFormat(for: configuration.preferLowLatency)
        NDILogger.log("Starting receiver for '\(receiverSourceName)' tier=\(configuration.qualityTier.rawValue) fpsCap=\(configuration.fpsCap) nic=\(configuration.interfaceID ?? "auto")' url='\(receiverSourceURL ?? "<nil>")'")

        let receiverInstance: NDIlib_recv_instance_t? = withReceiverSource(
            receiverSourceName: receiverSourceName,
            receiverSourceURL: receiverSourceURL
        ) { source in
            "Relay".withCString { receiverNameCString in
                var createSettings = NDIlib_recv_create_v3_t()
                createSettings.source_to_connect_to = source
                createSettings.color_format = colorFormat
                createSettings.bandwidth = bandwidth
                createSettings.allow_video_fields = false
                createSettings.p_ndi_recv_name = receiverNameCString

                return api.pointee.recv_create_v3(&createSettings)
            }
        }

        guard let receiverInstance else {
            NDILogger.log("Receiver creation failed for '\(receiverSourceName)'")
            continuation.yield(.failed("NDI receiver could not be created for \(receiverSourceName)."))
            return
        }

        defer {
            api.pointee.recv_destroy(receiverInstance)
        }

        withReceiverSource(
            receiverSourceName: receiverSourceName,
            receiverSourceURL: receiverSourceURL
        ) { source in
            var mutableSource = source
            api.pointee.recv_connect(receiverInstance, &mutableSource)
        }
        NDILogger.log("Receiver connected to '\(receiverSourceName)'")

        var emittedConnectionInfo: NDIReceiverConnectionInfo?
        var frameNumber: UInt64 = 0
        var hasLoggedFirstFrame = false
        var noFrameCounter = 0

        while !Task.isCancelled {
            var videoFrame = NDIlib_video_frame_v2_t()
            let frameType = api.pointee.recv_capture_v3(receiverInstance, &videoFrame, nil, nil, 1_000)

            switch frameType {
            case NDIlib_frame_type_none:
                noFrameCounter += 1
                let connectionCount = api.pointee.recv_get_no_connections(receiverInstance)
                if noFrameCounter % 5 == 0 {
                    NDILogger.log("No video frame yet for '\(receiverSourceName)' after \(noFrameCounter)s; connections=\(connectionCount)")
                }
                if connectionCount == 0, noFrameCounter >= 10 {
                    NDILogger.log("Declaring connection stalled for '\(receiverSourceName)' after \(noFrameCounter)s with zero connections")
                    continuation.yield(.disconnected("Lost connection to \(receiverSourceName). Trying to reconnect."))
                    return
                }
                continue

            case NDIlib_frame_type_video:
                noFrameCounter = 0
                let connectionInfo = NDIReceiverConnectionInfo(
                    sourceName: receiverSourceName,
                    interfaceID: configuration.interfaceID,
                    resolution: CGSize(width: CGFloat(videoFrame.xres), height: CGFloat(videoFrame.yres)),
                    frameRate: estimatedFPS(from: videoFrame)
                )

                if emittedConnectionInfo != connectionInfo {
                    emittedConnectionInfo = connectionInfo
                    continuation.yield(.connected(connectionInfo))
                    NDILogger.log("Video format \(videoFrame.xres)x\(videoFrame.yres) @ \(String(format: "%.2f", connectionInfo.frameRate))fps for '\(receiverSourceName)'")
                }

                frameNumber += 1
                let frame = NDIFrame(
                    frameNumber: frameNumber,
                    width: Int(videoFrame.xres),
                    height: Int(videoFrame.yres),
                    pixelFormat: pixelFormat(from: videoFrame.FourCC),
                    timestamp: Date(),
                    estimatedFPS: connectionInfo.frameRate,
                    cgImage: makeCGImage(from: videoFrame)
                )
                continuation.yield(.frame(frame))
                if !hasLoggedFirstFrame {
                    hasLoggedFirstFrame = true
                    NDILogger.log("First video frame received from '\(receiverSourceName)'")
                }
                api.pointee.recv_free_video_v2(receiverInstance, &videoFrame)

            case NDIlib_frame_type_status_change, NDIlib_frame_type_source_change:
                emittedConnectionInfo = nil
                let connectionCount = api.pointee.recv_get_no_connections(receiverInstance)
                NDILogger.log("Source status changed for '\(receiverSourceName)' connections=\(connectionCount)")

            case NDIlib_frame_type_error:
                NDILogger.log("Connection lost for '\(receiverSourceName)'")
                continuation.yield(.disconnected("The NDI connection was lost."))
                return

            default:
                continue
            }
        }

        NDILogger.log("Receiver loop stopped for '\(receiverSourceName)'")
    }

    private nonisolated static func receiverBandwidth(for tier: NDIModuleModel.QualityTier) -> NDIlib_recv_bandwidth_e {
        // Always use highest bandwidth for reliable connections on all tiers.
        // Poster (1 fps) and preview (15 fps) rates are enforced by NDIFrameProcessor's
        // frame-rate cap, not by NDI bandwidth negotiation — lowest bandwidth can cause
        // sources to drop the connection entirely.
        return NDIlib_recv_bandwidth_highest
    }

    private nonisolated static func receiverColorFormat(for preferLowLatency: Bool) -> NDIlib_recv_color_format_e {
        _ = preferLowLatency
        return NDIlib_recv_color_format_BGRX_BGRA
    }

    private nonisolated static func estimatedFPS(from videoFrame: NDIlib_video_frame_v2_t) -> Double {
        guard videoFrame.frame_rate_D != 0 else { return 0 }
        return Double(videoFrame.frame_rate_N) / Double(videoFrame.frame_rate_D)
    }

    private nonisolated static func pixelFormat(from fourCC: NDIlib_FourCC_video_type_e) -> NDIReceiverPixelFormat {
        switch fourCC {
        case NDIlib_FourCC_video_type_BGRA, NDIlib_FourCC_video_type_BGRX:
            return .bgra8
        case NDIlib_FourCC_video_type_UYVY, NDIlib_FourCC_video_type_UYVA:
            return .uyvy
        case NDIlib_FourCC_video_type_P216, NDIlib_FourCC_video_type_PA16:
            return .rgba16f
        default:
            return .unknown
        }
    }

    private nonisolated static func makeCGImage(from videoFrame: NDIlib_video_frame_v2_t) -> CGImage? {
        guard let dataPointer = videoFrame.p_data,
              videoFrame.xres > 0,
              videoFrame.yres > 0 else {
            return nil
        }

        let supportedFormats: [NDIlib_FourCC_video_type_e] = [
            NDIlib_FourCC_video_type_BGRA,
            NDIlib_FourCC_video_type_BGRX
        ]
        guard supportedFormats.contains(videoFrame.FourCC) else {
            return nil
        }

        let width = Int(videoFrame.xres)
        let height = Int(videoFrame.yres)
        let bytesPerRow = Int(videoFrame.line_stride_in_bytes) > 0
            ? Int(videoFrame.line_stride_in_bytes)
            : width * 4
        let totalByteCount = bytesPerRow * height

        let data = Data(bytes: dataPointer, count: totalByteCount) as CFData
        guard let provider = CGDataProvider(data: data) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = videoFrame.FourCC == NDIlib_FourCC_video_type_BGRA ? .premultipliedFirst : .noneSkipFirst
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: alphaInfo.rawValue))

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private nonisolated static func withReceiverSource<T>(
        receiverSourceName: String,
        receiverSourceURL: String?,
        _ body: (NDIlib_source_t) -> T
    ) -> T {
        receiverSourceName.withCString { sourceNameCString in
            if let receiverSourceURL, !receiverSourceURL.isEmpty {
                return receiverSourceURL.withCString { sourceURLCString in
                    var source = NDIlib_source_t()
                    source.p_ndi_name = sourceNameCString
                    source.p_url_address = sourceURLCString
                    return body(source)
                }
            }

            var source = NDIlib_source_t()
            source.p_ndi_name = sourceNameCString
            source.p_url_address = nil
            return body(source)
        }
    }
}
#endif

#if os(iOS) && !targetEnvironment(simulator)
private enum NDILogger {
    nonisolated static func log(_ message: String) {
        print("[NDI] \(message)")
    }
}

private nonisolated final class NDIIOSRuntime: @unchecked Sendable {
    nonisolated(unsafe) static let shared = NDIIOSRuntime()

    nonisolated(unsafe) let api: UnsafePointer<NDIlib_v6_3>?
    let loadError: String?
    private var discoveryFinder: NDIlib_find_instance_t?
    private let discoveryQueue = DispatchQueue(label: "relay.ndi.discovery.ios")

    nonisolated var isReady: Bool {
        api != nil
    }

    private init() {
        let loadedAPI = Self.loadAPI()

        if let loadedAPI,
           let initialize = loadedAPI.pointee.initialize,
           initialize() {
            api = loadedAPI
            loadError = nil
            NDILogger.log("iOS NDI runtime initialized successfully")
        } else {
            api = nil
            loadError = "The statically linked iOS NDI runtime failed to initialize."
            NDILogger.log("Runtime unavailable: \(loadError!)")
        }
    }

    deinit {
        if let api, let discoveryFinder {
            api.pointee.find_destroy(discoveryFinder)
        }
        if let api {
            api.pointee.destroy()
        }
    }

    func discoverSources(preferredInterfaceID: String?) -> [NDISourceDescriptor] {
        discoveryQueue.sync {
            guard let api else { return [] }
            NDILogger.log("Refreshing sources (preferred NIC: \(preferredInterfaceID ?? "auto"))")
            guard let finder = ensureDiscoveryFinder(api: api) else {
                NDILogger.log("Failed to create NDI finder instance")
                return []
            }

            let immediateResults = currentSources(
                finder: finder,
                preferredInterfaceID: preferredInterfaceID
            )
            if !immediateResults.isEmpty {
                logDiscoveredSources(immediateResults)
                return immediateResults
            }

            let changed = api.pointee.find_wait_for_sources(finder, 1_500)
            NDILogger.log("Source wait completed (changed: \(changed))")

            let waitedResults = currentSources(
                finder: finder,
                preferredInterfaceID: preferredInterfaceID
            )
            logDiscoveredSources(waitedResults)
            return waitedResults
        }
    }

    private func ensureDiscoveryFinder(api: UnsafePointer<NDIlib_v6_3>) -> NDIlib_find_instance_t? {
        if let discoveryFinder {
            return discoveryFinder
        }

        var finderConfig = NDIlib_find_create_t()
        finderConfig.show_local_sources = true
        finderConfig.p_groups = nil
        finderConfig.p_extra_ips = nil

        let finder = api.pointee.find_create_v2(&finderConfig)
        discoveryFinder = finder
        if finder != nil {
            NDILogger.log("Created persistent NDI finder instance")
        }
        return finder
    }

    private func currentSources(
        finder: NDIlib_find_instance_t?,
        preferredInterfaceID: String?
    ) -> [NDISourceDescriptor] {
        var sourceCount: UInt32 = 0
        guard let api,
              let sources = api.pointee.find_get_current_sources(finder, &sourceCount),
              sourceCount > 0 else {
            return []
        }

        let interfaceHint = preferredInterfaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (0..<Int(sourceCount)).compactMap { index in
            let source = sources[index]
            let ndiName = Self.string(from: source.p_ndi_name)
            guard !ndiName.isEmpty else { return nil }
            return NDISourceDescriptor(
                id: ndiName,
                name: ndiName,
                hostName: Self.hostName(from: ndiName),
                interfaceHint: interfaceHint,
                urlAddress: Self.string(from: source.p_url_address)
            )
        }
    }

    private func logDiscoveredSources(_ results: [NDISourceDescriptor]) {
        NDILogger.log("Discovered \(results.count) source(s)")
        guard !results.isEmpty else { return }

        let summary = results
            .map { descriptor in
                if let hostName = descriptor.hostName, !hostName.isEmpty {
                    return "\(descriptor.name) @ \(hostName)"
                }
                return descriptor.name
            }
            .joined(separator: " | ")
        NDILogger.log("Sources: \(summary)")
    }

    private nonisolated static func loadAPI() -> UnsafePointer<NDIlib_v6_3>? {
        if let api = NDIlib_v6_3_load() {
            return api
        }
        if let api = NDIlib_v6_load() {
            return UnsafeRawPointer(api).assumingMemoryBound(to: NDIlib_v6_3.self)
        }
        return nil
    }

    private nonisolated static func string(from pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }

    private nonisolated static func hostName(from ndiName: String) -> String? {
        guard let range = ndiName.range(of: " (") else { return nil }
        let host = ndiName[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? nil : host
    }
}

private final class NDIRealtimeDiscovery: NDISDKDiscovering {
    private let runtime: NDIIOSRuntime

    nonisolated init(runtime: NDIIOSRuntime) {
        self.runtime = runtime
    }

    func refreshSources(preferredInterfaceID: String?) async -> [NDISourceDescriptor] {
        let runtime = self.runtime
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let sources = runtime.discoverSources(preferredInterfaceID: preferredInterfaceID)
                continuation.resume(returning: sources)
            }
        }
    }
}

private final class NDIRealtimeReceiver: NDISDKReceiving {
    let events: AsyncStream<NDIReceiverEvent>

    private let configuration: NDIReceiverConfiguration
    private let runtime: NDIIOSRuntime
    private var continuation: AsyncStream<NDIReceiverEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?

    nonisolated init(configuration: NDIReceiverConfiguration, runtime: NDIIOSRuntime) {
        self.configuration = configuration
        self.runtime = runtime
        var storedContinuation: AsyncStream<NDIReceiverEvent>.Continuation?
        self.events = AsyncStream { continuation in
            storedContinuation = continuation
        }
        self.continuation = storedContinuation
    }

    func start() {
        guard receiveTask == nil else { return }
        continuation?.yield(.connecting)

        receiveTask = Task.detached(priority: .userInitiated) { [configuration, runtime, continuation] in
            guard let continuation else { return }
            Self.runCaptureLoop(
                configuration: configuration,
                runtime: runtime,
                continuation: continuation
            )
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        continuation?.yield(.disconnected(nil))
    }

    private nonisolated static func runCaptureLoop(
        configuration: NDIReceiverConfiguration,
        runtime: NDIIOSRuntime,
        continuation: AsyncStream<NDIReceiverEvent>.Continuation
    ) {
        guard let api = runtime.api else {
            continuation.yield(.failed(runtime.loadError ?? "NDI runtime unavailable."))
            return
        }

        let desiredSourceName = configuration.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSourceName = configuration.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let receiverSourceName = desiredSourceName.isEmpty ? fallbackSourceName : desiredSourceName
        let receiverSourceURL = configuration.sourceURLAddress?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !receiverSourceName.isEmpty else {
            continuation.yield(.failed("Select an NDI source before starting the receiver."))
            return
        }

        let bandwidth = receiverBandwidth(for: configuration.qualityTier)
        let colorFormat = receiverColorFormat(for: configuration.preferLowLatency)
        NDILogger.log("Starting receiver for '\(receiverSourceName)' tier=\(configuration.qualityTier.rawValue) fpsCap=\(configuration.fpsCap) nic=\(configuration.interfaceID ?? "auto")' url='\(receiverSourceURL ?? "<nil>")'")

        let receiverInstance: NDIlib_recv_instance_t? = withReceiverSource(
            receiverSourceName: receiverSourceName,
            receiverSourceURL: receiverSourceURL
        ) { source in
            "Relay".withCString { receiverNameCString in
                var createSettings = NDIlib_recv_create_v3_t()
                createSettings.source_to_connect_to = source
                createSettings.color_format = colorFormat
                createSettings.bandwidth = bandwidth
                createSettings.allow_video_fields = false
                createSettings.p_ndi_recv_name = receiverNameCString

                return api.pointee.recv_create_v3(&createSettings)
            }
        }

        guard let receiverInstance else {
            NDILogger.log("Receiver creation failed for '\(receiverSourceName)'")
            continuation.yield(.failed("NDI receiver could not be created for \(receiverSourceName)."))
            return
        }

        defer {
            api.pointee.recv_destroy(receiverInstance)
        }

        withReceiverSource(
            receiverSourceName: receiverSourceName,
            receiverSourceURL: receiverSourceURL
        ) { source in
            var mutableSource = source
            api.pointee.recv_connect(receiverInstance, &mutableSource)
        }
        NDILogger.log("Receiver connected to '\(receiverSourceName)'")

        var emittedConnectionInfo: NDIReceiverConnectionInfo?
        var frameNumber: UInt64 = 0
        var hasLoggedFirstFrame = false
        var noFrameCounter = 0

        while !Task.isCancelled {
            var videoFrame = NDIlib_video_frame_v2_t()
            let frameType = api.pointee.recv_capture_v3(receiverInstance, &videoFrame, nil, nil, 1_000)

            switch frameType {
            case NDIlib_frame_type_none:
                noFrameCounter += 1
                let connectionCount = api.pointee.recv_get_no_connections(receiverInstance)
                if noFrameCounter % 5 == 0 {
                    NDILogger.log("No video frame yet for '\(receiverSourceName)' after \(noFrameCounter)s; connections=\(connectionCount)")
                }
                if connectionCount == 0, noFrameCounter >= 10 {
                    NDILogger.log("Declaring connection stalled for '\(receiverSourceName)' after \(noFrameCounter)s with zero connections")
                    continuation.yield(.disconnected("Lost connection to \(receiverSourceName). Trying to reconnect."))
                    return
                }
                continue

            case NDIlib_frame_type_video:
                noFrameCounter = 0
                let connectionInfo = NDIReceiverConnectionInfo(
                    sourceName: receiverSourceName,
                    interfaceID: configuration.interfaceID,
                    resolution: CGSize(width: CGFloat(videoFrame.xres), height: CGFloat(videoFrame.yres)),
                    frameRate: estimatedFPS(from: videoFrame)
                )

                if emittedConnectionInfo != connectionInfo {
                    emittedConnectionInfo = connectionInfo
                    continuation.yield(.connected(connectionInfo))
                    NDILogger.log("Video format \(videoFrame.xres)x\(videoFrame.yres) @ \(String(format: "%.2f", connectionInfo.frameRate))fps for '\(receiverSourceName)'")
                }

                frameNumber += 1
                let frame = NDIFrame(
                    frameNumber: frameNumber,
                    width: Int(videoFrame.xres),
                    height: Int(videoFrame.yres),
                    pixelFormat: pixelFormat(from: videoFrame.FourCC),
                    timestamp: Date(),
                    estimatedFPS: connectionInfo.frameRate,
                    cgImage: makeCGImage(from: videoFrame)
                )
                continuation.yield(.frame(frame))
                if !hasLoggedFirstFrame {
                    hasLoggedFirstFrame = true
                    NDILogger.log("First video frame received from '\(receiverSourceName)'")
                }
                api.pointee.recv_free_video_v2(receiverInstance, &videoFrame)

            case NDIlib_frame_type_status_change, NDIlib_frame_type_source_change:
                emittedConnectionInfo = nil
                let connectionCount = api.pointee.recv_get_no_connections(receiverInstance)
                NDILogger.log("Source status changed for '\(receiverSourceName)' connections=\(connectionCount)")

            case NDIlib_frame_type_error:
                NDILogger.log("Connection lost for '\(receiverSourceName)'")
                continuation.yield(.disconnected("The NDI connection was lost."))
                return

            default:
                continue
            }
        }

        NDILogger.log("Receiver loop stopped for '\(receiverSourceName)'")
    }

    private nonisolated static func receiverBandwidth(for tier: NDIModuleModel.QualityTier) -> NDIlib_recv_bandwidth_e {
        _ = tier
        return NDIlib_recv_bandwidth_highest
    }

    private nonisolated static func receiverColorFormat(for preferLowLatency: Bool) -> NDIlib_recv_color_format_e {
        _ = preferLowLatency
        return NDIlib_recv_color_format_BGRX_BGRA
    }

    private nonisolated static func estimatedFPS(from videoFrame: NDIlib_video_frame_v2_t) -> Double {
        guard videoFrame.frame_rate_D != 0 else { return 0 }
        return Double(videoFrame.frame_rate_N) / Double(videoFrame.frame_rate_D)
    }

    private nonisolated static func pixelFormat(from fourCC: NDIlib_FourCC_video_type_e) -> NDIReceiverPixelFormat {
        switch fourCC {
        case NDIlib_FourCC_video_type_BGRA, NDIlib_FourCC_video_type_BGRX:
            return .bgra8
        case NDIlib_FourCC_video_type_UYVY, NDIlib_FourCC_video_type_UYVA:
            return .uyvy
        case NDIlib_FourCC_video_type_P216, NDIlib_FourCC_video_type_PA16:
            return .rgba16f
        default:
            return .unknown
        }
    }

    private nonisolated static func makeCGImage(from videoFrame: NDIlib_video_frame_v2_t) -> CGImage? {
        guard let dataPointer = videoFrame.p_data,
              videoFrame.xres > 0,
              videoFrame.yres > 0 else {
            return nil
        }

        let supportedFormats: [NDIlib_FourCC_video_type_e] = [
            NDIlib_FourCC_video_type_BGRA,
            NDIlib_FourCC_video_type_BGRX
        ]
        guard supportedFormats.contains(videoFrame.FourCC) else {
            return nil
        }

        let width = Int(videoFrame.xres)
        let height = Int(videoFrame.yres)
        let bytesPerRow = Int(videoFrame.line_stride_in_bytes) > 0
            ? Int(videoFrame.line_stride_in_bytes)
            : width * 4
        let totalByteCount = bytesPerRow * height

        let data = Data(bytes: dataPointer, count: totalByteCount) as CFData
        guard let provider = CGDataProvider(data: data) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = videoFrame.FourCC == NDIlib_FourCC_video_type_BGRA ? .premultipliedFirst : .noneSkipFirst
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: alphaInfo.rawValue))

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private nonisolated static func withReceiverSource<T>(
        receiverSourceName: String,
        receiverSourceURL: String?,
        _ body: (NDIlib_source_t) -> T
    ) -> T {
        receiverSourceName.withCString { sourceNameCString in
            if let receiverSourceURL, !receiverSourceURL.isEmpty {
                return receiverSourceURL.withCString { sourceURLCString in
                    var source = NDIlib_source_t()
                    source.p_ndi_name = sourceNameCString
                    source.p_url_address = sourceURLCString
                    return body(source)
                }
            }

            var source = NDIlib_source_t()
            source.p_ndi_name = sourceNameCString
            source.p_url_address = nil
            return body(source)
        }
    }
}
#endif
