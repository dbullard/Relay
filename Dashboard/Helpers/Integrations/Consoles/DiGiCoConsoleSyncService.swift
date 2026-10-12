import Combine
import Foundation
import os

@MainActor
final class DiGiCoConsoleSyncService: ObservableObject {

    enum SyncState: Equatable {
        case idle
        case syncing(progress: String)
        case succeeded(inputCount: Int, otherCount: Int, at: Date)
        case noChannelsFound
        case portUnavailable(port: UInt16)
        case consoleNotResponding
        case networkPermissionDenied
        case failed(message: String)
    }

    @Published var state: SyncState = .idle
    @Published var isCancellable: Bool = false

    private var syncTask: Task<Void, Never>?
    private let osc = DiGiCoOSCClient()
    private let log = Logger(subsystem: "com.relay.digico-sync", category: "SyncService")

    // MARK: - Public API

    func sync(deviceId: UUID) {
        syncTask?.cancel()
        state = .syncing(progress: "Connecting…")
        isCancellable = true

        syncTask = Task { [weak self] in
            await self?.runSync(deviceId: deviceId)
        }
    }

    func cancel() {
        syncTask?.cancel()
        syncTask = nil
        osc.disconnect()
        state = .idle
        isCancellable = false
    }

    // MARK: - Sync Workflow

    private func runSync(deviceId: UUID) async {
        defer {
            isCancellable = false
            osc.disconnect()
        }

        guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceId }) else {
            state = .failed(message: "Device not found.")
            return
        }

        let host = device.host
        // device.port is the DiGiCo OSC receive port (what we send TO — default 9000).
        // device.digicoReceivePort is our local receive port (owned by the [OSC] stack — default 8000).
        let consolePort = device.port > 0 ? device.port : 9000
        let localPort = device.digicoLocalListenPort ?? 8000
        log.info("Sync start: host=\(host) consolePort=\(consolePort) localPort=\(localPort)")

        // Step 1: Bind UDP
        do {
            try await osc.configure(consoleHost: host, consolePort: consolePort, localPort: localPort)
            log.info("UDP bind ok")
        } catch DiGiCoOSCError.portUnavailable(let port) {
            state = .portUnavailable(port: port)
            return
        } catch DiGiCoOSCError.invalidHost {
            state = .failed(message: "Invalid console IP address.")
            return
        } catch {
            state = .failed(message: "Network error: \(error.localizedDescription)")
            return
        }

        guard !Task.isCancelled else { state = .idle; return }

        // Step 2: Console info
        state = .syncing(progress: "Querying console…")
        async let nameResult = osc.query(address: "/Console/Name/?", timeout: 2.0)
        async let sessionResult = osc.query(address: "/Console/Session/Filename/?", timeout: 2.0)
        let (consoleName, sessionFilename) = await (nameResult, sessionResult)
        log.info("Console name=\(consoleName ?? "nil") session=\(sessionFilename ?? "nil")")

        if consoleName == nil && sessionFilename == nil {
            state = .consoleNotResponding
            return
        }

        guard !Task.isCancelled else { state = .idle; return }

        // Step 3: Layout banks
        state = .syncing(progress: "Reading layout banks…")
        var bankPackets: [(address: String, data: Data)] = []
        let handlerId = osc.addRawHandler { addr, data in
            if addr == "/Layout/Layout/Banks" {
                bankPackets.append((addr, data))
            }
        }
        osc.sendQuery(address: "/Layout/Layout/Banks/?")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        osc.removeRawHandler(id: handlerId)

        let banks = Self.parseLayoutBanks(bankPackets)
        log.info("Layout banks: \(banks.count) parsed")

        guard !Task.isCancelled else { state = .idle; return }

        // Step 4: Scan all channel types
        let maxScans = device.digicoMaxScanCounts

        let scanJobs: [(type: DashboardGraph.DiGiCoChannelType, max: Int, path: (Int) -> String)] = [
            (.inputChannel,  maxScans["inputChannel"]  ?? 256, { "/Input_Channels/\($0)/Channel_Input/name/?" }),
            (.auxOutput,     maxScans["auxOutput"]     ?? 128, { "/Aux_Outputs/\($0)/Buss_Trim/name/?" }),
            (.groupOutput,   maxScans["groupOutput"]   ?? 128, { "/Group_Outputs/\($0)/Buss_Trim/name/?" }),
            (.matrixOutput,  maxScans["matrixOutput"]  ?? 64,  { "/Matrix_Outputs/\($0)/Buss_Trim/name/?" }),
            (.controlGroup,  maxScans["controlGroup"]  ?? 64,  { "/Control_Groups/\($0)/name/?" }),
        ]

        var discoveredInputs: [Int: String] = [:]
        var discoveredOther: [ExternalDeviceConfig.DiGiCoDiscoveredChannel] = []
        let syncedAt = Date()

        for job in scanJobs {
            guard !Task.isCancelled else { state = .idle; return }
            state = .syncing(progress: "Scanning \(job.type.displayName)…")

            let names = await scanChannelNames(
                channelType: job.type,
                maxCount: job.max,
                queryPath: job.path,
                consecutiveEmptyStop: 8
            )
            log.info("\(job.type.displayName): \(names.count) found")

            if job.type == .inputChannel {
                discoveredInputs = names
            } else {
                for (index, channelName) in names where !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let bank = banks.first {
                        $0.strips.contains { $0.type == job.type.oscBankKey && $0.index == index }
                    }
                    let stripPos = bank.flatMap { b in
                        b.strips.firstIndex { $0.type == job.type.oscBankKey && $0.index == index }
                    }
                    discoveredOther.append(ExternalDeviceConfig.DiGiCoDiscoveredChannel(
                        channelType: job.type,
                        index: index,
                        name: channelName,
                        consoleName: consoleName,
                        sessionFilename: sessionFilename,
                        syncedAt: syncedAt,
                        bankName: bank?.name,
                        bankSection: bank?.section,
                        bankPage: bank?.page,
                        bankLayer: bank?.layer,
                        bankStripPosition: stripPos
                    ))
                }
            }
        }

        guard !Task.isCancelled else { state = .idle; return }

        // Step 5: Write to store
        let merged = Self.mergeInputChannels(existing: device.digicoInputChannels, discovered: discoveredInputs)

        ExternalDevicesStore.shared.updateDevice(id: deviceId) { dev in
            dev.digicoInputChannels = merged
            if !discoveredInputs.isEmpty {
                dev.digicoRTFFileName = nil
                dev.digicoRTFImportedAt = nil
            }
            dev.digicoDiscoveredChannels = discoveredOther
            dev.digicoOSCConsoleName = consoleName
            dev.digicoOSCSessionFilename = sessionFilename
            dev.digicoOSCSyncedAt = syncedAt
            dev.lastChannelSyncAt = syncedAt  // drives the "Sync: date" subtitle in the device list
        }

        log.info("Sync complete: \(merged.count) inputs, \(discoveredOther.count) other")

        if merged.isEmpty && discoveredOther.isEmpty {
            state = .noChannelsFound
        } else {
            state = .succeeded(inputCount: merged.count, otherCount: discoveredOther.count, at: syncedAt)
        }
    }

    // MARK: - Scan

    private func scanChannelNames(
        channelType: DashboardGraph.DiGiCoChannelType,
        maxCount: Int,
        queryPath: (Int) -> String,
        consecutiveEmptyStop: Int
    ) async -> [Int: String] {
        var results: [Int: String] = [:]
        var scannedIndices: [Int] = []
        let batchSize = 16

        var index = 1
        while index <= maxCount {
            guard !Task.isCancelled else { break }

            let batchEnd = min(index + batchSize - 1, maxCount)
            let batchIndices = Array(index...batchEnd)
            let queries = batchIndices.map { queryPath($0) }
            let batchResults = await osc.queryBatch(addresses: queries, timeout: 1.5)

            for i in batchIndices {
                let responseAddr = String(queryPath(i).dropLast(2))
                if let val = batchResults[responseAddr], !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results[i] = val
                }
                scannedIndices.append(i)
            }

            if let stopAt = Self.firstEarlyStopIndex(
                scanned: scannedIndices,
                results: results,
                consecutiveEmptyThreshold: consecutiveEmptyStop
            ) {
                log.info("\(channelType.displayName): early stop at index \(stopAt)")
                break
            }

            index = batchEnd + 1
        }

        return results
    }

    // MARK: - Pure Static Helpers (testable)

    nonisolated static func firstEarlyStopIndex(
        scanned: [Int],
        results: [Int: String],
        consecutiveEmptyThreshold: Int
    ) -> Int? {
        var consecutiveEmpty = 0
        var lastValidIndex: Int? = nil

        for i in scanned {
            let hasValue = results[i].map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
            if hasValue {
                consecutiveEmpty = 0
                lastValidIndex = i
            } else {
                consecutiveEmpty += 1
                if lastValidIndex != nil, consecutiveEmpty >= consecutiveEmptyThreshold {
                    return i
                }
            }
        }
        return nil
    }

    nonisolated static func mergeInputChannels(
        existing: [ExternalDeviceConfig.DiGiCoInputChannel],
        discovered: [Int: String]
    ) -> [ExternalDeviceConfig.DiGiCoInputChannel] {
        var byChannel: [Int: ExternalDeviceConfig.DiGiCoInputChannel] = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.channel, $0) }
        )

        for (index, name) in discovered {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if let existing = byChannel[index] {
                byChannel[index] = ExternalDeviceConfig.DiGiCoInputChannel(
                    channel: existing.channel, stereo: existing.stereo, name: trimmed
                )
            } else {
                byChannel[index] = ExternalDeviceConfig.DiGiCoInputChannel(
                    channel: index, stereo: false, name: trimmed
                )
            }
        }

        return byChannel.values.sorted { $0.channel < $1.channel }
    }

    // MARK: - Layout Bank Parsing

    struct LayoutBank {
        let name: String
        let section: String
        let page: Int
        let layer: Int
        let strips: [(type: String, index: Int)]
    }

    nonisolated static func parseLayoutBanks(_ packets: [(address: String, data: Data)]) -> [LayoutBank] {
        packets.compactMap { (address, data) -> LayoutBank? in
            guard address == "/Layout/Layout/Banks",
                  let parsed = DiGiCoOSCClient.parseOSCArguments(data),
                  parsed.args.count >= 4,
                  case .string(let bankName) = parsed.args[0],
                  case .string(let section) = parsed.args[1],
                  case .int32(let page) = parsed.args[2],
                  case .int32(let layer) = parsed.args[3] else { return nil }

            var strips: [(type: String, index: Int)] = []
            var i = 4
            while i + 1 < parsed.args.count {
                if case .string(let objType) = parsed.args[i],
                   case .int32(let idx) = parsed.args[i + 1] {
                    strips.append((type: objType, index: Int(idx)))
                }
                i += 2
            }
            return LayoutBank(name: bankName, section: section,
                              page: Int(page), layer: Int(layer), strips: strips)
        }
    }
}

// MARK: - DiGiCoChannelType extensions

private extension DashboardGraph.DiGiCoChannelType {
    var oscBankKey: String {
        switch self {
        case .inputChannel:  return "Input_Channels"
        case .auxOutput:     return "Aux_Outputs"
        case .groupOutput:   return "Group_Outputs"
        case .matrixOutput:  return "Matrix_Outputs"
        case .controlGroup:  return "Control_Groups"
        }
    }
}
