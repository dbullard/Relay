import Foundation
import Network

enum SennheiserWirelessDestinationError: Error {
    case invalidHost
    case invalidURL
    case requestFailed(Int)
    case invalidPort
    case invalidPayload
    case connectionFailed(String)
    case sendFailed(String)
}

struct SennheiserWirelessDestinationService {
    private static func shouldRecordVerboseTrace(for device: ExternalDeviceConfig) -> Bool {
        WirelessLoggingPreferences.isVerboseSennheiser(forModel: device.sennheiserModelIdentifier)
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

    static func sendSscMessage(
        device: ExternalDeviceConfig,
        message: [String: Any],
        timeout: TimeInterval = 2.0
    ) async throws {
        let hostString = device.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostString.isEmpty else {
            Task { @MainActor in
                RelayDiagnosticsStore.shared.recordError("Invalid host for \(device.name) (empty)", tag: "Sennheiser")
            }
            throw SennheiserWirelessDestinationError.invalidHost
        }

        let portValue = device.port > 0 ? device.port : 45
        guard let port = NWEndpoint.Port(rawValue: portValue) else {
            Task { @MainActor in
                RelayDiagnosticsStore.shared.recordError("Invalid port \(portValue) for \(device.name)", tag: "Sennheiser")
            }
            throw SennheiserWirelessDestinationError.invalidPort
        }

        guard JSONSerialization.isValidJSONObject(message) else {
            Task { @MainActor in
                RelayDiagnosticsStore.shared.recordError("Invalid SSC payload for \(device.name)", tag: "Sennheiser")
            }
            throw SennheiserWirelessDestinationError.invalidPayload
        }

        let payload = try JSONSerialization.data(withJSONObject: message, options: [])
        let host = NWEndpoint.Host(hostString)
        let connection = NWConnection(host: host, port: port, using: .udp)
        let queue = DispatchQueue(label: "SennheiserWirelessDestinationService")
        let errorKeyBase = "sennheiser_ssc_\(hostString):\(portValue)"
        let tracePrefix = "\(device.name) \(hostString):\(portValue) model=\(device.sennheiserModelIdentifier ?? "unknown")"
        let shouldTrace = shouldRecordVerboseTrace(for: device)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class FinishGate: @unchecked Sendable {
                let lock = NSLock()
                var didFinish = false

                func tryFinish() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if didFinish { return false }
                    didFinish = true
                    return true
                }
            }

            let finishGate = FinishGate()
            if shouldTrace {
                Task { @MainActor in
                    RelayDiagnosticsStore.shared.recordSennheiserTrace("action ssc_send_start \(tracePrefix) bytes=\(payload.count)")
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if shouldTrace {
                        Task { @MainActor in
                            RelayDiagnosticsStore.shared.recordSennheiserTrace("action ssc_send_ready \(tracePrefix)")
                        }
                    }
                    connection.send(content: payload, completion: .contentProcessed { error in
                        guard finishGate.tryFinish() else { return }
                        if let error {
                            if isOperationCancelled(error) {
                                if shouldTrace {
                                    Task { @MainActor in
                                        RelayDiagnosticsStore.shared.recordSennheiserTrace("action ssc_send_cancelled \(tracePrefix)")
                                    }
                                }
                                continuation.resume(throwing: SennheiserWirelessDestinationError.connectionFailed("Connection cancelled"))
                                connection.stateUpdateHandler = nil
                                connection.cancel()
                                return
                            }
                            let errorMessage = error.localizedDescription
                            if shouldTrace {
                                Task { @MainActor in
                                    RelayDiagnosticsStore.shared.recordSennheiserTrace("action ssc_send_failed \(tracePrefix) error=\(errorMessage)")
                                }
                            }
                            Task { @MainActor in
                                RelayDiagnosticsStore.shared.recordThrottledError(
                                    "SSC send failed to \(hostString):\(portValue) — \(errorMessage)",
                                    tag: "Sennheiser",
                                    key: "\(errorKeyBase)_send",
                                    minInterval: 60
                                )
                            }
                            if shouldTrace {
                                print("[Sennheiser] SSC send failed to \(hostString):\(portValue) — \(errorMessage)")
                            }
                            continuation.resume(throwing: SennheiserWirelessDestinationError.sendFailed(errorMessage))
                        } else {
                            if shouldTrace {
                                Task { @MainActor in
                                    RelayDiagnosticsStore.shared.recordSennheiserTrace("action ssc_send_success \(tracePrefix)")
                                }
                                print("[Sennheiser] SSC message sent to \(hostString):\(portValue)")
                            }
                            continuation.resume()
                        }
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                    })
                case .failed(let error):
                    guard finishGate.tryFinish() else { return }
                    let errorMessage = error.localizedDescription
                    if shouldTrace {
                        Task { @MainActor in
                            RelayDiagnosticsStore.shared.recordSennheiserTrace("action ssc_connect_failed \(tracePrefix) error=\(errorMessage)")
                        }
                    }
                    Task { @MainActor in
                        RelayDiagnosticsStore.shared.recordThrottledError(
                            "SSC connection failed to \(hostString):\(portValue) — \(errorMessage)",
                            tag: "Sennheiser",
                            key: "\(errorKeyBase)_failed",
                            minInterval: 60
                        )
                    }
                    if shouldTrace {
                        print("[Sennheiser] SSC connection failed to \(hostString):\(portValue) — \(errorMessage)")
                    }
                    continuation.resume(throwing: SennheiserWirelessDestinationError.connectionFailed(errorMessage))
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                case .cancelled:
                    guard finishGate.tryFinish() else { return }
                    if shouldTrace {
                        Task { @MainActor in
                            RelayDiagnosticsStore.shared.recordSennheiserTrace("action ssc_connect_cancelled \(tracePrefix)")
                        }
                    }
                    continuation.resume(throwing: SennheiserWirelessDestinationError.connectionFailed("Connection cancelled"))
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                guard finishGate.tryFinish() else { return }
                if shouldTrace {
                    Task { @MainActor in
                        RelayDiagnosticsStore.shared.recordSennheiserTrace("action ssc_connect_timed_out \(tracePrefix) timeout=\(String(format: "%.1f", timeout))s")
                    }
                }
                Task { @MainActor in
                    RelayDiagnosticsStore.shared.recordThrottledError(
                        "SSC connection timed out to \(hostString):\(portValue) after \(String(format: "%.1f", timeout))s",
                        tag: "Sennheiser",
                        key: "\(errorKeyBase)_timeout",
                        minInterval: 60
                    )
                }
                if shouldTrace {
                    print("[Sennheiser] SSC connection timed out to \(hostString):\(portValue) after \(String(format: "%.1f", timeout))s")
                }
                continuation.resume(throwing: SennheiserWirelessDestinationError.connectionFailed("Timed out"))
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
        }
    }

    static func sendRequest(
        device: ExternalDeviceConfig,
        scheme: String,
        method: DashboardGraph.SennheiserSendActionConfig.HTTPMethod,
        path: String,
        jsonBody: String,
        timeout: TimeInterval = 4.0
    ) async throws {
        let hostString = device.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostString.isEmpty else {
            Task { @MainActor in
                RelayDiagnosticsStore.shared.recordError("Invalid host for \(device.name) (empty)", tag: "Sennheiser")
            }
            throw SennheiserWirelessDestinationError.invalidHost
        }

        var normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPath.isEmpty { normalizedPath = "/" }
        if !normalizedPath.hasPrefix("/") { normalizedPath = "/" + normalizedPath }

        var components = URLComponents()
        components.scheme = scheme.isEmpty ? "http" : scheme
        components.host = hostString
        if device.port > 0 {
            components.port = Int(device.port)
        }
        components.path = normalizedPath

        guard let url = components.url else {
            Task { @MainActor in
                RelayDiagnosticsStore.shared.recordError("Invalid URL for \(device.name) path \(normalizedPath)", tag: "Sennheiser")
            }
            throw SennheiserWirelessDestinationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout
        let errorKeyBase = "sennheiser_http_\(hostString):\(device.port > 0 ? device.port : 0)\(normalizedPath)"
        let tracePrefix = "\(device.name) \(method.rawValue) \(url.absoluteString) model=\(device.sennheiserModelIdentifier ?? "unknown")"
        let shouldTrace = shouldRecordVerboseTrace(for: device)

        let trimmedBody = jsonBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = trimmedBody.data(using: .utf8)
        }

        if shouldTrace {
            await MainActor.run {
                RelayDiagnosticsStore.shared.recordSennheiserTrace("action http_send_start \(tracePrefix)")
            }
        }

        let response: URLResponse
        do {
            let (_, requestResponse) = try await URLSession.shared.data(for: request)
            response = requestResponse
        } catch {
            let errorMessage = error.localizedDescription
            await MainActor.run {
                if shouldTrace {
                    RelayDiagnosticsStore.shared.recordSennheiserTrace("action http_send_failed \(tracePrefix) error=\(errorMessage)")
                }
                RelayDiagnosticsStore.shared.recordThrottledError(
                    "HTTP request failed to \(url.host ?? hostString) \(normalizedPath) — \(errorMessage)",
                    tag: "Sennheiser",
                    key: "\(errorKeyBase)_request",
                    minInterval: 60
                )
            }
            if shouldTrace {
                print("[Sennheiser] HTTP request failed to \(url.absoluteString) — \(errorMessage)")
            }
            throw error
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            await MainActor.run {
                if shouldTrace {
                    RelayDiagnosticsStore.shared.recordSennheiserTrace("action http_send_non_2xx \(tracePrefix) status=\(http.statusCode)")
                }
                RelayDiagnosticsStore.shared.recordThrottledError(
                    "HTTP request failed to \(url.host ?? hostString) \(normalizedPath) — status \(http.statusCode)",
                    tag: "Sennheiser",
                    key: "\(errorKeyBase)_status_\(http.statusCode)",
                    minInterval: 60
                )
            }
            if shouldTrace {
                print("[Sennheiser] HTTP request returned \(http.statusCode) for \(url.absoluteString)")
            }
            throw SennheiserWirelessDestinationError.requestFailed(http.statusCode)
        }

        if shouldTrace {
            await MainActor.run {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                RelayDiagnosticsStore.shared.recordSennheiserTrace("action http_send_success \(tracePrefix) status=\(status)")
            }
            print("[Sennheiser] HTTP request succeeded for \(url.absoluteString)")
        }
    }
}
