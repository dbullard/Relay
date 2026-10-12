//
//  NetworkUtils.swift
//  PCODiGiCoApp
//
//  Created by David Bullard on 9/26/25.
//


import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Utilities for resolving local IP addresses (prefers Wi-Fi when available).
enum NetworkUtils {

    /// Returns the current primary IPv4 address on the local LAN.
    /// Prefers Wi-Fi (en0 / en1) if present; otherwise returns the first private IPv4 it finds.
    static func currentIPv4(preferWiFi: Bool = true) -> String? {
        // Try NWPathMonitor first (modern API), then fall back to BSD getifaddrs if needed.
        if let ip = primaryIPv4UsingGetIFAddrs(preferWiFi: preferWiFi) {
            return ip
        }
        return nil
    }

    private static func primaryIPv4UsingGetIFAddrs(preferWiFi: Bool) -> String? {
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

            // Interface name
            guard let cName = ifa.ifa_name else {
                if let next = ifa.ifa_next { ptr = next } else { break }
                continue
            }
            let name = String(cString: cName)

            // Convert to IPv4 string
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

            if let next = ifa.ifa_next {
                ptr = next
            } else {
                break
            }
        }

        return wifiCandidate ?? firstPrivate
    }

    /// Puts a socket in non-blocking mode so a `DispatchSourceRead`-driven drain loop
    /// (`while true { recvfrom(...); if received <= 0 { break } }`) returns as soon as no
    /// more data is queued, instead of parking its thread in a blocking `recvfrom()` call
    /// until the next packet arrives — or forever, if none ever does. Without this, the
    /// drain loop occupies its serial queue for as long as the listener runs, starving any
    /// other work scheduled on that same queue (e.g. a periodic re-probe timer).
    @discardableResult
    static func makeSocketNonBlocking(_ fd: Int32) -> Bool {
        guard fd >= 0 else { return false }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags != -1 else { return false }
        return fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1
    }

    private static func isPrivateIPv4(_ ip: String) -> Bool {
        // 10.0.0.0/8
        if ip.hasPrefix("10.") { return true }
        // 172.16.0.0 – 172.31.255.255
        if ip.hasPrefix("172.") {
            let comps = ip.split(separator: ".")
            if comps.count >= 2, let second = Int(comps[1]), (16...31).contains(second) {
                return true
            }
        }
        // 192.168.0.0/16
        if ip.hasPrefix("192.168.") { return true }
        return false
    }
}
