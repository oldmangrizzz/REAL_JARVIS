import Foundation

public struct DisplayEndpoint: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let aliases: [String]
    public let type: DisplayType
    public let transport: DisplayTransport
    public let address: String?
    public let capabilities: [String]
    public let room: String?
    /// Authority level this endpoint is granted to Jarvis. Unknown/missing defaults to `.standard`.
    /// `.fullControl` = full display/voice/control authority (echo, alpha, beta, foxtrot).
    /// `.fullAccessAndControl` = full read + write authority including HomeKit bridge / public edge (charlie, delta).
    public let authority: Authority

    public enum DisplayType: String, Codable, Sendable {
        case monitor, tv, projector, tablet, watch
        case host          // echo (local Mac host)
        case meshNode = "mesh-node"  // alpha/beta/foxtrot/charlie/delta
    }

    public enum DisplayTransport: String, Codable, Sendable {
        case airplay, ddcCI = "ddc-ci", http, hdmiCEC = "hdmi-cec", matter, homeKit = "homekit"
        case local
        case jarvisTunnel = "jarvis-tunnel"
        /// DIAL (Discovery and Launch) — used for Fire TV / Chromecast app launch.
        case dial
        /// Alexa routine invoked via webhook. Used for Echo Show cards.
        case alexaRoutine = "alexa-routine"
    }

    public enum Authority: String, Codable, Sendable {
        case standard
        case fullControl = "full-control"
        case fullAccessAndControl = "full-access-and-control"
    }

    public init(id: String, displayName: String, aliases: [String], type: DisplayType, transport: DisplayTransport, address: String?, capabilities: [String], room: String?, authority: Authority = .standard) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.type = type
        self.transport = transport
        self.address = address
        self.capabilities = capabilities
        self.room = room
        self.authority = authority
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, aliases, type, transport, address, capabilities, room, authority
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.aliases = try c.decode([String].self, forKey: .aliases)
        self.type = try c.decode(DisplayType.self, forKey: .type)
        self.transport = try c.decode(DisplayTransport.self, forKey: .transport)
        self.address = try c.decodeIfPresent(String.self, forKey: .address)
        self.capabilities = try c.decode([String].self, forKey: .capabilities)
        self.room = try c.decodeIfPresent(String.self, forKey: .room)
        self.authority = try c.decodeIfPresent(Authority.self, forKey: .authority) ?? .standard
    }
}

public struct AccessoryEndpoint: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let aliases: [String]
    public let homeKitAccessoryID: String?
    public let characteristics: [String]
    public let room: String?

    public init(id: String, displayName: String, aliases: [String], homeKitAccessoryID: String?, characteristics: [String], room: String?) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.homeKitAccessoryID = homeKitAccessoryID
        self.characteristics = characteristics
        self.room = room
    }
}

public struct CapabilityConfig: Codable, Sendable {
    public let displays: [DisplayEndpoint]
    public let accessories: [AccessoryEndpoint]
    /// MK2-EPIC-02: per-client role bindings keyed by device identity key hex.
    /// Backward compatible — missing field defaults to empty (everyone gets .guest).
    public let clientRoles: [ClientRoleEntry]

    public init(displays: [DisplayEndpoint], accessories: [AccessoryEndpoint], clientRoles: [ClientRoleEntry] = []) {
        self.displays = displays
        self.accessories = accessories
        self.clientRoles = clientRoles
    }

    private enum CodingKeys: String, CodingKey {
        case displays, accessories, clientRoles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.displays = try c.decode([DisplayEndpoint].self, forKey: .displays)
        self.accessories = try c.decode([AccessoryEndpoint].self, forKey: .accessories)
        self.clientRoles = try c.decodeIfPresent([ClientRoleEntry].self, forKey: .clientRoles) ?? []
    }
}

/// MK2-EPIC-02: Maps a device identity key hex to a server-assigned TunnelRole.
public struct ClientRoleEntry: Codable, Sendable {
    public let publicKeyHex: String
    public let role: TunnelRole

    public init(publicKeyHex: String, role: TunnelRole) {
        self.publicKeyHex = publicKeyHex
        self.role = role
    }
}

public final class CapabilityRegistry: @unchecked Sendable {
    private var displays: [DisplayEndpoint]
    private var accessories: [AccessoryEndpoint]
    private var clientRoles: [ClientRoleEntry]

    public var allDisplayIDs: [String] { displays.map { $0.id } }
    public var allAccessoryIDs: [String] { accessories.map { $0.id } }

    public init(displays: [DisplayEndpoint], accessories: [AccessoryEndpoint], clientRoles: [ClientRoleEntry] = []) {
        self.displays = displays
        self.accessories = accessories
        self.clientRoles = clientRoles
    }

    public convenience init(configURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        let config = try decoder.decode(CapabilityConfig.self, from: data)
        self.init(displays: config.displays, accessories: config.accessories, clientRoles: config.clientRoles)
    }

    /// MK2-EPIC-02: Look up the server-assigned TunnelRole for a device identity key.
    /// Returns `.guest` if the key is not listed (fail-safe, minimal privilege).
    public func clientIdentity(publicKeyHex: String) -> TunnelRole {
        clientRoles.first(where: { $0.publicKeyHex.lowercased() == publicKeyHex.lowercased() })?.role ?? .guest
    }

    public func matchDisplay(from text: String) -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for display in displays {
            if display.aliases.contains(where: { lower.contains($0) }) {
                return display.id
            }
            if lower.contains(display.displayName.lowercased()) {
                return display.id
            }
        }
        return "unknown"
    }

    public func matchAccessoryName(from text: String) -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for acc in accessories {
            if acc.aliases.contains(where: { lower.contains($0) }) {
                return acc.id
            }
        }
        return "unknown"
    }

    public func matchAction(from text: String) -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("telemetry") || lower.contains("status") { return "display-telemetry" }
        if lower.contains("camera") || lower.contains("feed") { return "display-camera" }
        if lower.contains("map") { return "display-map" }
        if lower.contains("dashboard") || lower.contains("hud") { return "display-dashboard" }
        return "display-generic"
    }

    public func matchParameters(from text: String) -> [String: String] {
        var params: [String: String] = [:]
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("telemetry") { params["content"] = "telemetry" }
        if lower.contains("camera") { params["content"] = "camera" }
        if lower.contains("hud") || lower.contains("cockpit") { params["content"] = "hud" }
        if lower.contains("dashboard") { params["content"] = "dashboard" }
        return params
    }

    public func display(for id: String) -> DisplayEndpoint? {
        displays.first(where: { $0.id == id })
    }

    public func displayIndex(for id: String) -> Int? {
        let index = displays.firstIndex(where: { $0.id == id })
        return index.map { $0 + 1 }
    }

    public func accessory(for id: String) -> AccessoryEndpoint? {
        accessories.first(where: { $0.id == id })
    }

    public func reload(from configURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        let config = try decoder.decode(CapabilityConfig.self, from: data)
        self.displays = config.displays
        self.accessories = config.accessories
        self.clientRoles = config.clientRoles
    }
}
