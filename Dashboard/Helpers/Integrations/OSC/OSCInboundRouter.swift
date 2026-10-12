//
//  OSCInboundRouter.swift
//  Relay
//
//  Created by David Bullard on 10/16/25.
//


import Foundation
import Network

final class OSCInboundRouter {
    private let port: NWEndpoint.Port
    private let onMessage: (_ path: String, _ rawData: Data) -> Void
    private var listener: NWListener?

    init(port: UInt16, onMessage: @escaping (_ path: String, _ rawData: Data) -> Void) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.onMessage = onMessage
    }

    func start() throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true  // important to avoid “Address already in use”
        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            conn.stateUpdateHandler = { state in
                if case .ready = state {
                    self?.receive(on: conn)
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: break
            case .failed(let err): print("OSC listener failed: \(err)")
            default: break
            }
        }

        listener.start(queue: .global(qos: .userInitiated))
    }

    func cancel() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            defer { self?.receive(on: connection) } // keep receiving
            guard error == nil, let data = data, !data.isEmpty else { return }
            if let path = Self.parseOSCAddress(from: data) {
                self?.onMessage(path, data)
            }
        }
    }

    /// Minimal OSC reader: extracts the address string (null-terminated, 4-byte aligned).
    private static func parseOSCAddress(from data: Data) -> String? {
        // OSC packet begins with address pattern as a C-string.
        guard let zero = data.firstIndex(of: 0) else { return nil }
        let addrData = data[..<zero]
        return String(data: addrData, encoding: .utf8)
    }
}