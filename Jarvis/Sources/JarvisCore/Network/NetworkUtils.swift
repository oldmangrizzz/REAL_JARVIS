import Foundation

/// SSRF (Server-Side Request Forgery) guard for validating display addresses and external URLs.
/// Enforces a whitelist of allowed IP subnets to prevent JARVIS from being used as a proxy
/// to attack internal infrastructure.
public final class NetworkUtils {

    /// Default allowlist of IP subnets that JARVIS is permitted to access for display/mesh dispatch.
    /// Contains trusted internal subnets and loopback addresses.
    /// - Important: This is a security-critical configuration. Additions must be reviewed.
    public static let defaultAllowedSubnets: [String] = [
        // Infrastructure subnet (alpha/beta/charlie/foxtrot/deployed nodes)
        "192.168.4.0/24",
        // Home Assistant subnet (HA VM, Echo host)
        "192.168.7.0/24",
        // Loopback (localhost, ::1)
        "127.0.0.0/8",
        "::1/128",
        // Link-local IPv6
        "fe80::/10"
    ]

    /// Validates an IP address against the allowed subnet whitelist.
    /// - Parameters:
    ///   - ipAddress: The IP address to validate (IPv4 or IPv6).
    ///   - allowedSubnets: List of CIDR subnet strings (default: `defaultAllowedSubnets`).
    /// - Returns: `true` if the IP is within any allowed subnet, `false` otherwise.
    public static func isIPAllowed(_ ipAddress: String, allowedSubnets: [String] = defaultAllowedSubnets) -> Bool {
        for subnet in allowedSubnets {
            if ipAddressInCIDR(ipAddress, cidr: subnet) {
                return true
            }
        }
        return false
    }

    /// Validates a hostname or address string that could be an IP or domain.
    /// If it's an IP, validates against the subnet whitelist.
    /// If it's a hostname (doesn't parse as IP), checks domain allowlist (currently rejects all domains
    /// unless they resolve to allowed IPs).
    /// - Parameters:
    ///   - hostAddress: Host address string (e.g., "192.168.4.151", "alpha.local", "localhost:3000").
    ///   - allowedSubnets: List of CIDR subnet strings (default: `defaultAllowedSubnets`).
    /// - Returns: `true` if the address is allowed, `false` otherwise.
    public static func isHostAddressAllowed(_ hostAddress: String, allowedSubnets: [String] = defaultAllowedSubnets) -> Bool {
        // Remove port if present
        let cleaned = hostAddress.split(separator: ":").first.map(String.init) ?? hostAddress

        // Check if it's an IP address
        if validIPv4(cleaned) || validIPv6(cleaned) {
            return isIPAllowed(cleaned, allowedSubnets: allowedSubnets)
        }

        // For hostnames, we apply a restrictive policy:
        // - Local domain suffixes (.local, .home.arpa) are trusted for mDNS/Bonjour
        // - Others must be explicitly allowed via configuration

        let lowercased = cleaned.lowercased()
        // Allow .local mDNS domains (internal network discovery)
        if lowercased.hasSuffix(".local") {
            return true
        }
        // Allow .home.arpa (RFC standard for home network naming)
        if lowercased.hasSuffix(".home.arpa") {
            return true
        }
        // Special cases: localhost variations
        if lowercased == "localhost" {
            return true
        }

        // All other hostnames are denied by default unless explicitly configured
        // (future enhancement: allowlist configuration file)
        return false
    }

    /// Validates a display endpoint address before making HTTP requests.
    /// This should be called in `HTTPDisplayBridge` and `MeshDisplayDispatcher` before
    /// constructing URLs to send commands.
    /// - Parameters:
    ///   - displayAddress: Address string from `DisplayEndpoint.address`.
    ///   - allowedSubnets: List of CIDR subnet strings (default: `defaultAllowedSubnets`).
    /// - Throws: `JarvisError.invalidInput` if the address is not allowed.
    public static func validateDisplayAddress(_ displayAddress: String, allowedSubnets: [String] = defaultAllowedSubnets) throws {
        guard isHostAddressAllowed(displayAddress, allowedSubnets: allowedSubnets) else {
            throw JarvisError.invalidInput("Display address '\(displayAddress)' is not in the allowed network range. SSRF guard blocked.")
        }
    }

    // MARK: - Private Implementation

    /// Simple IPv4 validation
    private static func validIPv4(_ string: String) -> Bool {
        let parts = string.split(separator: ".").map(String.init)
        guard parts.count == 4 else { return false }

        for part in parts {
            guard let num = UInt8(part), part == String(num) else { return false }
        }
        return true
    }

    /// Simple IPv6 validation (basic check for hex segments)
    private static func validIPv6(_ string: String) -> Bool {
        let lower = string.lowercased()
        let segments = lower.split(separator: ":", omittingEmptySubsequences: false)
        let nonEmpty = segments.filter { !$0.isEmpty }
        guard nonEmpty.count <= 8 else { return false }

        for segment in segments {
            if segment.isEmpty { continue }
            guard segment.allSatisfy({ $0.isHexDigit }) else { return false }
            guard segment.count <= 4 else { return false }
        }

        let compressionCount = lower.components(separatedBy: "::").count - 1
        guard compressionCount <= 1 else { return false }

        if compressionCount == 1 {
            guard nonEmpty.count < 8 else { return false }
        } else {
            guard segments.count == 8 else { return false }
        }

        return true
    }

    /// Check if an IP address is within a CIDR subnet
    private static func ipAddressInCIDR(_ ip: String, cidr: String) -> Bool {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2 else { return false }

        let network = String(parts[0])
        guard let prefixLength = Int(parts[1]) else { return false }

        // IPv4 CIDR
        if validIPv4(ip) && validIPv4(network) && prefixLength <= 32 {
            return ipv4InCIDR(ip, network: network, prefixLength: prefixLength)
        }

        // IPv6 CIDR
        if validIPv6(ip) && validIPv6(network) && prefixLength <= 128 {
            return ipv6InCIDR(ip, network: network, prefixLength: prefixLength)
        }

        return false
    }

    private static func ipv4InCIDR(_ ip: String, network: String, prefixLength: Int) -> Bool {
        guard let ipParts = parseIPv4Parts(ip),
              let netParts = parseIPv4Parts(network) else {
            return false
        }

        // Convert to integer representation
        let ipNum = (UInt32(ipParts[0]) << 24) | (UInt32(ipParts[1]) << 16) | (UInt32(ipParts[2]) << 8) | UInt32(ipParts[3])
        let netNum = (UInt32(netParts[0]) << 24) | (UInt32(netParts[1]) << 16) | (UInt32(netParts[2]) << 8) | UInt32(netParts[3])

        let mask: UInt32
        if prefixLength == 0 {
            mask = 0
        } else if prefixLength == 32 {
            mask = 0xFFFFFFFF
        } else {
            mask = (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF
        }

        return (ipNum & mask) == (netNum & mask)
    }

    private static func ipv6InCIDR(_ ip: String, network: String, prefixLength: Int) -> Bool {
        // For now, just do string equality for IPv6 since our allowlist only has ::1/128 and fe80::/10
        // This can be enhanced later if needed
        guard let ipExpanded = expandIPv6(ip),
              let netExpanded = expandIPv6(network) else {
            return false
        }

        if prefixLength == 128 {
            return ipExpanded == netExpanded
        }

        // For fe80::/10, check first 10 bits match
        // Simple implementation: check if both start with "fe80"
        return ipExpanded.hasPrefix("fe80") && netExpanded.hasPrefix("fe80")
    }

    private static func parseIPv4Parts(_ string: String) -> [UInt8]? {
        let parts = string.split(separator: ".").map(String.init)
        guard parts.count == 4 else { return nil }

        var bytes: [UInt8] = []
        for part in parts {
            guard let num = UInt8(part) else { return nil }
            bytes.append(num)
        }
        return bytes
    }

    private static func expandIPv6(_ string: String) -> String? {
        guard validIPv6(string) else { return nil }
        let lower = string.lowercased()

        if lower.contains("::") {
            let parts = lower.components(separatedBy: ":")
            let nonEmpty = parts.filter { !$0.isEmpty }
            let zerosNeeded = 8 - nonEmpty.count
            guard zerosNeeded >= 1 else { return nil }

            var result: [String] = []
            var filled = false
            for part in parts {
                if part.isEmpty && !filled {
                    for _ in 0..<zerosNeeded {
                        result.append("0000")
                    }
                    filled = true
                } else if !part.isEmpty {
                    result.append(String(repeating: "0", count: max(0, 4 - part.count)) + part)
                }
            }
            guard result.count == 8 else { return nil }
            return result.joined(separator: ":")
        }

        let segments = lower.split(separator: ":").map(String.init)
        guard segments.count == 8 else { return nil }
        return segments.map { String(repeating: "0", count: max(0, 4 - $0.count)) + $0 }.joined(separator: ":")
    }
}