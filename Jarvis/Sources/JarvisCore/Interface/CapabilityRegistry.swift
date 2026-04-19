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

    public enum DisplayType: String, Codable, Sendable {
        case monitor, tv, projector, tablet, watch
    }

    public enum DisplayTransport: String, Codable, Sendable {
        case airplay, ddcCI = "ddc-ci", http, hdmiCEC = "hdmi-cec", matter, homeKit = "homekit"
    }

    public init(id: String, displayName: String, aliases: [String], type: DisplayType, transport: DisplayTransport, address: String?, capabilities: [String], room: String?) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.type = type
        self.transport = transport
        self.address = address
        self.capabilities = capabilities
        self.room = room
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

    public init(displays: [DisplayEndpoint], accessories: [AccessoryEndpoint]) {
        self.displays = displays
        self.accessories = accessories
    }
}

public final class CapabilityRegistry {
    private var displays: [DisplayEndpoint]
    private var accessories: [AccessoryEndpoint]

    public var allDisplayIDs: [String] { displays.map { $0.id } }
    public var allAccessoryIDs: [String] { accessories.map { $0.id } }

    public init(displays: [DisplayEndpoint], accessories: [AccessoryEndpoint]) {
        self.displays = displays
        self.accessories = accessories
    }

    public convenience init(configURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        let config = try decoder.decode(CapabilityConfig.self, from: data)
        self.init(displays: config.displays, accessories: config.accessories)
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
    }
}
