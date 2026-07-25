import Foundation
import Darwin

/// Sends a Wake-on-LAN "magic packet" (6× 0xFF followed by the 6-byte MAC
/// repeated 16×) as a UDP broadcast. This is the only way to wake a fully-asleep
/// Mac — SSH can't reach it. The Mac needs "Wake for network access" enabled.
enum WakeOnLAN {
    /// Broadcasts a magic packet for `macAddress`. Returns true if at least one
    /// packet was sent. Sends to the host's subnet broadcast (if `host` is an
    /// IPv4 address) and the limited broadcast, on the common WoL ports.
    @discardableResult
    static func wake(macAddress: String, host: String) -> Bool {
        guard let mac = parseMAC(macAddress) else { return false }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: mac) }

        var sentAny = false
        for address in broadcastAddresses(forHost: host) {
            for port: UInt16 in [9, 7] {
                if sendUDP(packet, to: address, port: port) { sentAny = true }
            }
        }
        return sentAny
    }

    // MARK: Helpers

    static func parseMAC(_ string: String) -> [UInt8]? {
        let parts = string.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        return bytes.count == 6 ? bytes : nil
    }

    /// Subnet broadcast derived from an IPv4 host (x.y.z.255), plus the limited
    /// broadcast 255.255.255.255.
    private static func broadcastAddresses(forHost host: String) -> [String] {
        var addresses = ["255.255.255.255"]
        let octets = host.split(separator: ".")
        if octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) {
            addresses.insert("\(octets[0]).\(octets[1]).\(octets[2]).255", at: 0)
        }
        return addresses
    }

    private static func sendUDP(_ bytes: [UInt8], to address: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(address)
        guard addr.sin_addr.s_addr != INADDR_NONE else { return false }

        let sent = bytes.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saddr in
                    sendto(fd, raw.baseAddress, raw.count, 0, saddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == bytes.count
    }
}
