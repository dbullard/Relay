//
//  NetUtils.swift
//  PCODiGiCoApp
//
//  Created by David Bullard on 9/25/25.
//


import Foundation

enum NetUtils {
    /// Resolve A/AAAA records for a hostname using CFHost (sync).
    static func resolve(host: String) -> [String] {
        var result: [String] = []
        guard !host.isEmpty else { return result }

        let cfHost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        var streamError = CFStreamError()
        let ok = CFHostStartInfoResolution(cfHost, .addresses, &streamError)
        guard ok,
              let addresses = CFHostGetAddressing(cfHost, nil)?.takeUnretainedValue() as? [Data]
        else { return result }

        for addrData in addresses {
            addrData.withUnsafeBytes { raw in
                guard let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let _ = getnameinfo(sa,
                                    socklen_t(sa.pointee.sa_len),
                                    &hostBuffer, socklen_t(hostBuffer.count),
                                    nil, 0,
                                    NI_NUMERICHOST)
                let ip = String(cString: hostBuffer)
                if !ip.isEmpty { result.append(ip) }
            }
        }
        return Array(Set(result)) // unique
    }
}
