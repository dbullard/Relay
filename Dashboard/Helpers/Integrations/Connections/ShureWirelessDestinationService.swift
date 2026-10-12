import Foundation
import Network

enum ShureWirelessDestinationError: Error {
    case invalidHost
    case invalidPort
    case connectionFailed(String)
    case sendFailed(String)
}

struct ShureWirelessDestinationService {
    private static func shouldRecordVerboseTrace(for device: ExternalDeviceConfig) -> Bool {
        WirelessLoggingPreferences.isVerboseShure(forModel: device.shureModelIdentifier)
    }

    private static func isOperationCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.code == 89 {
            return true
        }
        let message = error.localizedDescription
        return message.localizedCaseInsensitiveContains("operation canceled")
            || message.localizedCaseInsensitiveContains("connection cancelled")
    }

    static func sendCommand(
        device: ExternalDeviceConfig,
        command: String,
        timeout: TimeInterval = 2.0
    ) async throws {
        let hostString = device.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostString.isEmpty else {
            Task { @MainActor in
                RelayDiagnosticsStore.shared.recordError("Invalid host for \(device.name) (empty)", tag: "Shure")
            }
            throw ShureWirelessDestinationError.invalidHost
        }
        let portValue = device.port > 0 ? device.port : 2202

        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }
        let payload = trimmedCommand.hasPrefix("<") ? trimmedCommand : "< \(trimmedCommand) >"
        let framedPayload = payload.hasSuffix("\r\n") ? payload : (payload + "\r\n")

        let host = NWEndpoint.Host(hostString)
        guard let port = NWEndpoint.Port(rawValue: portValue) else {
            Task { @MainActor in
                RelayDiagnosticsStore.shared.recordError("Invalid port \(portValue) for \(device.name)", tag: "Shure")
            }
            throw ShureWirelessDestinationError.invalidPort
        }

        let connection = NWConnection(host: host, port: port, using: .tcp)
        let queue = DispatchQueue(label: "ShureWirelessDestinationService")

        final class FinishState: @unchecked Sendable {
            private let lock = NSLock()
            nonisolated(unsafe) private var didFinish = false

            nonisolated func markFinished() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if didFinish { return false }
                didFinish = true
                return true
            }
        }

        let finishState = FinishState()
        let errorKeyBase = "shure_send_\(hostString):\(portValue)"
        let shouldProbeHTTP: Bool = {
            switch device.shureNetworkModel {
            case .anx4, .adtd, .adtq:
                return true
            default:
                return false
            }
        }()
        let tracePrefix = "\(device.name) \(hostString):\(portValue) model=\(device.shureModelIdentifier ?? "unknown")"
        let shouldTrace = shouldRecordVerboseTrace(for: device)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if shouldTrace {
                Task { @MainActor in
                    RelayDiagnosticsStore.shared.recordShureTrace("action send start \(tracePrefix) command=\(trimmedCommand)")
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if shouldTrace {
                        Task { @MainActor in
                            RelayDiagnosticsStore.shared.recordShureTrace("action send ready \(tracePrefix)")
                        }
                    }
                    connection.send(content: Data(framedPayload.utf8), completion: .contentProcessed { error in
                        guard finishState.markFinished() else { return }
                        if let error {
                            if isOperationCancelled(error) {
                                if shouldTrace {
                                    Task { @MainActor in
                                        RelayDiagnosticsStore.shared.recordShureTrace("action send cancelled \(tracePrefix)")
                                    }
                                }
                                continuation.resume(throwing: ShureWirelessDestinationError.connectionFailed("Connection cancelled"))
                                connection.stateUpdateHandler = nil
                                connection.cancel()
                                return
                            }
                            let errorMessage = error.localizedDescription
                            if shouldTrace {
                                Task { @MainActor in
                                    RelayDiagnosticsStore.shared.recordShureTrace("action send failed \(tracePrefix) error=\(errorMessage)")
                                }
                            }
                            Task { @MainActor in
                                RelayDiagnosticsStore.shared.recordThrottledError(
                                    "Send failed to \(hostString):\(portValue) — \(errorMessage)",
                                    tag: "Shure",
                                    key: "\(errorKeyBase)_send",
                                    minInterval: 60
                                )
                            }
                            if shouldTrace {
                                print("[Shure] Send failed to \(hostString):\(portValue) — \(errorMessage)")
                            }
                            continuation.resume(throwing: ShureWirelessDestinationError.sendFailed(errorMessage))
                        } else {
                            if shouldTrace {
                                Task { @MainActor in
                                    RelayDiagnosticsStore.shared.recordShureTrace("action send success \(tracePrefix)")
                                }
                                print("[Shure] Command sent to \(hostString):\(portValue) — \(trimmedCommand)")
                            }
                            continuation.resume()
                        }
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                    })
                case .failed(let error):
                    guard finishState.markFinished() else { return }
                    let errorMessage = error.localizedDescription
                    if shouldTrace {
                        Task { @MainActor in
                            RelayDiagnosticsStore.shared.recordShureTrace("action connect failed \(tracePrefix) error=\(errorMessage)")
                        }
                    }
                    Task { @MainActor in
                        RelayDiagnosticsStore.shared.recordThrottledError(
                            "Connection failed to \(hostString):\(portValue) — \(errorMessage)",
                            tag: "Shure",
                            key: "\(errorKeyBase)_failed",
                            minInterval: 60
                        )
                    }
                    if shouldTrace {
                        print("[Shure] Connection failed to \(hostString):\(portValue) — \(errorMessage)")
                    }
                    if shouldProbeHTTP {
                        probeHTTP(ip: hostString)
                    }
                    continuation.resume(throwing: ShureWirelessDestinationError.connectionFailed(errorMessage))
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                case .cancelled:
                    guard finishState.markFinished() else { return }
                    if shouldTrace {
                        Task { @MainActor in
                            RelayDiagnosticsStore.shared.recordShureTrace("action connect cancelled \(tracePrefix)")
                        }
                    }
                    continuation.resume(throwing: ShureWirelessDestinationError.connectionFailed("Connection cancelled"))
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                guard finishState.markFinished() else { return }
                if shouldTrace {
                    Task { @MainActor in
                        RelayDiagnosticsStore.shared.recordShureTrace("action connect timed out \(tracePrefix) timeout=\(String(format: "%.1f", timeout))s")
                    }
                }
                Task { @MainActor in
                    RelayDiagnosticsStore.shared.recordThrottledError(
                        "Connection timed out to \(hostString):\(portValue) after \(String(format: "%.1f", timeout))s",
                        tag: "Shure",
                        key: "\(errorKeyBase)_timeout",
                        minInterval: 60
                    )
                }
                if shouldTrace {
                    print("[Shure] Connection timed out to \(hostString):\(portValue) after \(String(format: "%.1f", timeout))s")
                }
                if shouldProbeHTTP {
                    probeHTTP(ip: hostString)
                }
                continuation.resume(throwing: ShureWirelessDestinationError.connectionFailed("Timed out"))
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
        }
    }

    nonisolated private static func probeHTTP(ip: String) {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let paths = ["/", "/api", "/status", "/v1"]
        let urls = paths.compactMap { URL(string: "http://\(trimmed)\($0)") }
        guard !urls.isEmpty else { return }

        Task.detached {
            for url in urls {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 2.5

                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if WirelessLoggingPreferences.shureMasterVerbose,
                       let httpResponse = response as? HTTPURLResponse {
                        print("[ShureHTTPProbe] \(url.absoluteString) status=\(httpResponse.statusCode)")
                    }
                } catch {
                    if WirelessLoggingPreferences.shureMasterVerbose {
                        print("[ShureHTTPProbe] \(url.absoluteString) error=\(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
