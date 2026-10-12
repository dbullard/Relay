import Foundation

struct NDIInterfaceDescriptor: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let displayName: String
    let addresses: [String]
    let isUp: Bool
    let isLoopback: Bool

    var statusSummary: String {
        if addresses.isEmpty {
            return isUp ? "No IPv4 address" : "Disconnected"
        }
        return addresses.joined(separator: ", ")
    }
}

enum NDIInterfaceEnumerator {
    static func currentInterfaces() -> [NDIInterfaceDescriptor] {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        struct InterfaceAccumulator {
            var displayName: String
            var addresses: Set<String> = []
            var isUp: Bool = false
            var isLoopback: Bool = false
        }

        var accumulators: [String: InterfaceAccumulator] = [:]
        var pointer = first

        while true {
            let interface = pointer.pointee
            guard let cName = interface.ifa_name else {
                if let next = interface.ifa_next {
                    pointer = next
                    continue
                }
                break
            }

            let name = String(cString: cName)
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            var accumulator = accumulators[name] ?? InterfaceAccumulator(displayName: displayName(for: name))
            accumulator.isUp = accumulator.isUp || isUp
            accumulator.isLoopback = accumulator.isLoopback || isLoopback

            if let addr = interface.ifa_addr,
               Int32(addr.pointee.sa_family) == AF_INET {
                let address: String? = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                    var ipv4Address = pointer.pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    guard inet_ntop(AF_INET, &ipv4Address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                        return nil
                    }
                    let string = String(cString: buffer)
                    return string.isEmpty ? nil : string
                }

                if let address {
                    accumulator.addresses.insert(address)
                }
            }

            accumulators[name] = accumulator

            if let next = interface.ifa_next {
                pointer = next
            } else {
                break
            }
        }

        return accumulators
            .map { key, value in
                NDIInterfaceDescriptor(
                    id: key,
                    displayName: value.displayName,
                    addresses: value.addresses.sorted(),
                    isUp: value.isUp,
                    isLoopback: value.isLoopback
                )
            }
            .sorted { lhs, rhs in
                if lhs.isLoopback != rhs.isLoopback {
                    return !lhs.isLoopback && rhs.isLoopback
                }
                if lhs.isUp != rhs.isUp {
                    return lhs.isUp && !rhs.isUp
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private static func displayName(for interfaceID: String) -> String {
        switch interfaceID {
        case "en0":
            return "Wi-Fi / Ethernet (en0)"
        case "en1":
            return "Secondary Network (en1)"
        default:
            return interfaceID
        }
    }
}
