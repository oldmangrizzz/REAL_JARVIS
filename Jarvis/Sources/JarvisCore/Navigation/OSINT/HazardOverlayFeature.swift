import Foundation

/// NAV-001 Phase D: Hazard overlay feature for map rendering.
///
/// Represents a single situational-awareness hazard fetched from an
/// OSINT source. Qwen (UX-001) consumes this type to render overlays
/// on the navigation surface.
///
/// This is an advocacy/situational-awareness type, NOT clinical decision
/// support. Responder tier uses this for scene awareness only.
public struct HazardOverlayFeature: Sendable, Equatable, Codable, Hashable {
    public let id: String
    /// Registry key matching `OSINTSourceRegistry.canonical`.
    public let sourceKey: String
    public let category: HazardCategory
    /// `.info | .elevated | .critical`
    public let severity: HazardSeverity
    public let geometry: HazardGeometry
    public let observedAt: Date
    /// Time-to-live in seconds; stale hazards are pruned by `HazardCache`.
    public let ttl: TimeInterval
    public let summary: String

    public init(id: String, sourceKey: String, category: HazardCategory,
                severity: HazardSeverity, geometry: HazardGeometry,
                observedAt: Date, ttl: TimeInterval = 300,
                summary: String) {
        self.id = id
        self.sourceKey = sourceKey
        self.category = category
        self.severity = severity
        self.geometry = geometry
        self.observedAt = observedAt
        self.ttl = ttl
        self.summary = summary
    }
}

public enum HazardCategory: String, Sendable, Codable {
    case traffic
    case fire
    case weather
    case seismic
    case other
}

public enum HazardSeverity: String, Sendable, Codable {
    case info
    case elevated
    case critical
}

/// Geometry of a hazard overlay. Point for spot events, line for
/// road closures, polygon for area warnings.
public enum HazardGeometry: Sendable, Equatable, Hashable, Codable {
    case point(lat: Double, lon: Double)
    case line([LatLon])
    case polygon([LatLon])
}

/// Coordinate pair for hazard geometry.
public struct LatLon: Sendable, Equatable, Hashable, Codable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}