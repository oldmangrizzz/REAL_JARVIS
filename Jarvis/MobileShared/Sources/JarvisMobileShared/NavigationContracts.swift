import Foundation

// MARK: - HazardOverlayFeature (GLM engine -> surface contract)

/// Hazard overlay feature from engine to UI surfaces.
/// Same JSON structure used by Swift, JS (PWA), and Unity.
/// 
/// Engine emits: `HazardOverlayFeature[]`
/// Surfaces consume: parsed hazards + tier-filtered visibility
public struct HazardOverlayFeature: Equatable, Sendable, Codable {
    public let id: String
    public let geometry: Geometry
    public let severity: Severity
    public let source: String
    public let observedAt: String // ISO 8601
    public let ttl: Int // time-to-live in milliseconds (engine cache invalidation)
    
    public init(id: String, geometry: Geometry, severity: Severity, source: String, observedAt: String, ttl: Int) {
        self.id = id
        self.geometry = geometry
        self.severity = severity
        self.source = source
        self.observedAt = observedAt
        self.ttl = ttl
    }
}

/// Geometry type (polygon, line, point).
public enum Geometry: Equatable, Sendable, Codable {
    public struct Point: Equatable, Sendable, Codable {
        public let latitude: Double
        public let longitude: Double
        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }
    
    public struct Polygon: Equatable, Sendable, Codable {
        public let coordinates: [[Double]] // [[lat, lon], [lat, lon], ...]
        public init(coordinates: [[Double]]) {
            self.coordinates = coordinates
        }
    }
    
    public struct Line: Equatable, Sendable, Codable {
        public let coordinates: [[Double]] // [[lat, lon], [lat, lon], ...]
        public init(coordinates: [[Double]]) {
            self.coordinates = coordinates
        }
    }
    
    case point(Point)
    case polygon(Polygon)
    case line(Line)
}

/// Severity level for hazards.
public enum Severity: Equatable, Sendable, Codable {
    case critical
    case elevated
    case informational
}

// MARK: - SceneBriefing (GLM engine -> surface contract)

/// Scene briefing for preview/safety-aware surfaces.
/// GLM builds, Qwen surfaces.
/// 
/// Required fields for all tiers (with tier-appropriate filtering).
public struct SceneBriefing: Equatable, Sendable, Codable {
    public let destination: DestinationInfo
    public let accessNotes: AccessNotes
    public let surroundingHazards: [HazardSummary]
    public let sourceAttestations: [SourceAttestation]
    
    public init(
        destination: DestinationInfo,
        accessNotes: AccessNotes,
        surroundingHazards: [HazardSummary],
        sourceAttestations: [SourceAttestation]
    ) {
        self.destination = destination
        self.accessNotes = accessNotes
        self.surroundingHazards = surroundingHazards
        self.sourceAttestations = sourceAttestations
    }
}

/// Destination information for briefing card.
public struct DestinationInfo: Equatable, Sendable, Codable {
    public let name: String
    public let jurisdiction: String? // county / city / agency
    public let nearestCrossStreets: String?
    public let coordinates: [Double] // [lat, lon]
    
    public init(
        name: String,
        jurisdiction: String? = nil,
        nearestCrossStreets: String? = nil,
        coordinates: [Double]
    ) {
        self.name = name
        self.jurisdiction = jurisdiction
        self.nearestCrossStreets = nearestCrossStreets
        self.coordinates = coordinates
    }
}

/// Access notes per tier (companion vs responder vs guest).
public struct AccessNotes: Equatable, Sendable, Codable {
    public let entrances: [Entrance]
    public let accessibility: AccessibilityInfo
    public let ingressEgress: String? // responder specific
    
    public init(
        entrances: [Entrance],
        accessibility: AccessibilityInfo,
        ingressEgress: String? = nil
    ) {
        self.entrances = entrances
        self.accessibility = accessibility
        self.ingressEgress = ingressEgress
    }
}

public struct Entrance: Equatable, Sendable, Codable {
    public let name: String
    public let location: [Double] // [lat, lon]
    public let notes: String?
    public let accessibilityRating: AccessibilityRating
    
    public init(
        name: String,
        location: [Double],
        notes: String? = nil,
        accessibilityRating: AccessibilityRating = .unknown
    ) {
        self.name = name
        self.location = location
        self.notes = notes
        self.accessibilityRating = accessibilityRating
    }
}

public enum AccessibilityRating: Equatable, Sendable, Codable {
    case unknown
    case accessible
    case limited
    case notAccessible
    
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .accessible: return "Accessible"
        case .limited: return "Limited"
        case .notAccessible: return "Not Accessible"
        }
    }
}

public struct AccessibilityInfo: Equatable, Sendable, Codable {
    public let curbCuts: Bool
    public let elevators: Bool
    public let accessibleParking: Bool
    public let notes: String?
    
    public init(curbCuts: Bool, elevators: Bool, accessibleParking: Bool, notes: String? = nil) {
        self.curbCuts = curbCuts
        self.elevators = elevators
        self.accessibleParking = accessibleParking
        self.notes = notes
    }
}

public struct HazardSummary: Equatable, Sendable, Codable {
    public let type: HazardType
    public let severity: Severity
    public let distanceMeters: Double
    public let observedAt: String // ISO 8601
    
    public init(
        type: HazardType,
        severity: Severity,
        distanceMeters: Double,
        observedAt: String
    ) {
        self.type = type
        self.severity = severity
        self.distanceMeters = distanceMeters
        self.observedAt = observedAt
    }
}

public enum HazardType: Equatable, Sendable, Codable {
    case fire
    case severeWeather
    case seismic
    case traffic
    case emergencyServices
    case other(String)
}

public struct SourceAttestation: Equatable, Sendable, Codable {
    public let sourceKey: String
    public let lastUpdated: String // ISO 8601
    public let refreshRate: String? // "5 min", "1 hr", etc.
    
    public init(sourceKey: String, lastUpdated: String, refreshRate: String? = nil) {
        self.sourceKey = sourceKey
        self.lastUpdated = lastUpdated
        self.refreshRate = refreshRate
    }
}

// MARK: - PWA Component Boundaries

/// PWA component hierarchy for navigation surfaces.
public enum PWAComponentBoundaries {
    /// Map shell — wrapper around Mapbox GL JS map.
    public static let mapShell: String = "navigation-map"
    /// Layer manager — toggleable overlay controls.
    public static let layerManager: String = "navigation-layer-controls"
    /// Briefing panel — scene briefing card (accessible routes, hazards).
    public static let briefingPanel: String = "navigation-briefing-card"
    /// HUD overlay — minimal CarPlay-style HUD for driving safety.
    public static let hudOverlay: String = "navigation-hud"
}

// MARK: - Unity Bridge Contract

/// Unity AR bridge JSON contract for GLM → Unity data transfer.
/// Unity owns the rendering; Swift sends JSON data.
public struct UnityNavigationBridge: Equatable, Sendable, Codable {
    public let type: BridgeType
    public let payload: AnyJSON
    
    public enum BridgeType: Equatable, Sendable, Codable {
        case route
        case hazard
        case briefing
        case selfPos
    }
    
    public struct AnyJSON: Sendable, Codable, Equatable {
        public let value: [String: AnyCodable]
        public init(_ value: [String: Any]) {
            self.value = value.mapValues { AnyCodable($0) }
        }
    }
    
    public init(type: BridgeType, payload: [String: Any]) {
        self.type = type
        self.payload = AnyJSON(payload)
    }
    
    public static func == (lhs: UnityNavigationBridge, rhs: UnityNavigationBridge) -> Bool {
        guard lhs.type == rhs.type else { return false }
        guard lhs.payload.value.keys == rhs.payload.value.keys else { return false }
        return lhs.payload.value.elementsEqual(rhs.payload.value) { $0.value == $1.value }
    }
}

// MARK: - AnyCodable wrapper for Equatable JSON
private struct AnyCodable: Equatable, Sendable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case let (lhs as String, rhs as String):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as [Any], rhs as [Any]):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { AnyCodable($0) == AnyCodable($1) }
        case let (lhs as [String: Any], rhs as [String: Any]):
            return lhs.keys == rhs.keys && lhs.elementsEqual(rhs) { AnyCodable($0.value) == AnyCodable($1.value) }
        default:
            return false
        }
    }
}

// MARK: - Test Support (No tests - pure contract types)

#if DEBUG

// Contract validation helpers
func validateHazardOverlayFeatureJSON(_ json: Any) -> Bool {
    guard let dict = json as? [String: Any] else { return false }
    let keys = ["id", "geometry", "severity", "source", "observedAt", "ttl"]
    return keys.allSatisfy { dict[$0] != nil }
}

func validateSceneBriefingJSON(_ json: Any) -> Bool {
    guard let dict = json as? [String: Any] else { return false }
    let keys = ["destination", "accessNotes", "surroundingHazards", "sourceAttestations"]
    return keys.allSatisfy { dict[$0] != nil }
}

#endif

// MARK: - PWA / Unity Parity

public enum ParityPlatform {
    case pwa
    case unity
}

extension HazardOverlayFeature {
    /// Parse hazard from engine JSON (PWA or Unity).
    public static func parse(from json: Any, platform: ParityPlatform) -> [HazardOverlayFeature] {
        guard let array = json as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard
                let id = dict["id"] as? String,
                let geometryDict = dict["geometry"] as? [String: Any],
                let severityRaw = dict["severity"] as? String,
                let source = dict["source"] as? String,
                let observedAt = dict["observedAt"] as? String,
                let ttl = dict["ttl"] as? Int
            else { return nil }
            
            let severity: Severity
            switch severityRaw.lowercased() {
            case "critical": severity = .critical
            case "elevated": severity = .elevated
            case "informational", _:
                severity = .informational
            }
            
            let geometry: Geometry
            switch geometryDict["type"] as? String {
            case "point"?: 
                if let coord = geometryDict["coordinates"] as? [Double], coord.count >= 2 {
                    geometry = .point(Geometry.Point(latitude: coord[0], longitude: coord[1]))
                } else { return nil }
            case "polygon"?: 
                if let coords = geometryDict["coordinates"] as? [[Double]] {
                    geometry = .polygon(Geometry.Polygon(coordinates: coords))
                } else { return nil }
            case "line"?: 
                if let coords = geometryDict["coordinates"] as? [[Double]] {
                    geometry = .line(Geometry.Line(coordinates: coords))
                } else { return nil }
            default:
                return nil
            }
            
            return HazardOverlayFeature(
                id: id,
                geometry: geometry,
                severity: severity,
                source: source,
                observedAt: observedAt,
                ttl: ttl
            )
        }
    }
}

extension SceneBriefing {
    /// Parse scene briefing from engine JSON.
    public static func parse(from json: Any) -> SceneBriefing? {
        guard let dict = json as? [String: Any] else { return nil }
        
        guard
            let destDict = dict["destination"] as? [String: Any],
            let destName = destDict["name"] as? String,
            let destCoords = destDict["coordinates"] as? [Double],
            let accessDict = dict["accessNotes"] as? [String: Any],
            let entrancesArray = accessDict["entrances"] as? [[String: Any]],
            let accessibilityDict = accessDict["accessibility"] as? [String: Any],
            let hazardsArray = dict["surroundingHazards"] as? [[String: Any]],
            let sourcesArray = dict["sourceAttestations"] as? [[String: Any]]
        else { return nil }
        
        // Parse destination
        let destination = DestinationInfo(
            name: destName,
            jurisdiction: destDict["jurisdiction"] as? String,
            nearestCrossStreets: destDict["nearestCrossStreets"] as? String,
            coordinates: destCoords
        )
        
        // Parse accessibility
        let accessibility = AccessibilityInfo(
            curbCuts: accessibilityDict["curbCuts"] as? Bool ?? false,
            elevators: accessibilityDict["elevators"] as? Bool ?? false,
            accessibleParking: accessibilityDict["accessibleParking"] as? Bool ?? false,
            notes: accessibilityDict["notes"] as? String
        )
        
        // Parse entrances
        let entrances = entrancesArray.compactMap { d in
            guard
                let name = d["name"] as? String,
                let loc = d["location"] as? [Double]
            else { return nil }
            
            let ratingRaw = d["accessibilityRating"] as? String ?? "unknown"
            let rating: AccessibilityRating
            switch ratingRaw.lowercased() {
            case "accessible": rating = .accessible
            case "limited": rating = .limited
            case "notaccessible": rating = .notAccessible
            default: rating = .unknown
            }
            
            return Entrance(name: name, location: loc, accessibilityRating: rating)
        }
        
        // Parse access notes
        let accessNotes = AccessNotes(
            entrances: entrances,
            accessibility: accessibility,
            ingressEgress: accessDict["ingressEgress"] as? String
        )
        
        // Parse hazards
        let surroundingHazards = hazardsArray.compactMap { d in
            guard
                let typeRaw = d["type"] as? String,
                let severityRaw = d["severity"] as? String,
                let dist = d["distanceMeters"] as? Double,
                let observedAt = d["observedAt"] as? String
            else { return nil }
            
            let type: HazardType
            switch typeRaw.lowercased() {
            case "fire": type = .fire
            case "severeweather": type = .severeWeather
            case "seismic": type = .seismic
            case "traffic": type = .traffic
            case "emergencyservices": type = .emergencyServices
            default: type = .other(typeRaw)
            }
            
            let severity: Severity
            switch severityRaw.lowercased() {
            case "critical": severity = .critical
            case "elevated": severity = .elevated
            default: severity = .informational
            }
            
            return HazardSummary(type: type, severity: severity, distanceMeters: dist, observedAt: observedAt)
        }
        
        // Parse source attestations
        let sourceAttestations = sourcesArray.compactMap { d in
            guard
                let key = d["sourceKey"] as? String,
                let updatedAt = d["lastUpdated"] as? String
            else { return nil }
            
            return SourceAttestation(sourceKey: key, lastUpdated: updatedAt)
        }
        
        return SceneBriefing(
            destination: destination,
            accessNotes: accessNotes,
            surroundingHazards: surroundingHazards,
            sourceAttestations: sourceAttestations
        )
    }
}
