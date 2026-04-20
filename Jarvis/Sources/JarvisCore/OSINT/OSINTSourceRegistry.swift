import Foundation

/// SPEC-MAP: OSINT source registry.
///
/// Doctrine (operator-authoritative): **open sources only — gray, not
/// black**. We operate on publicly available data feeds, with full
/// attribution and license compliance. No scraped content behind TOS
/// walls, no dark-web feeds, no unauthorized scopes.
///
/// Every network fetch that backs a map layer, OSINT lookup, traffic
/// overlay, or situational-awareness feed MUST resolve through this
/// registry. Call sites request a source by key; the registry returns
/// the pinned endpoint, license text, attribution line, and rate-limit
/// guidance. Fetches to URLs not present in the registry are denied by
/// `OSINTFetchGuard.authorize(url:)`, fail-closed.
///
/// The registry is tier-agnostic: the same catalog backs operator,
/// companion, and responder surfaces. Per-source operator gating exists
/// for future scoped API keys but is off by default.

public struct OSINTSource: Equatable, Sendable, Codable {
    public let key: String
    public let name: String
    public let category: OSINTCategory
    public let endpointHosts: [String]
    public let license: String
    public let attribution: String
    public let homepage: String
    public let rateLimitHint: String?
    public let operatorGated: Bool
    public let notes: String?

    public init(key: String, name: String, category: OSINTCategory,
                endpointHosts: [String], license: String, attribution: String,
                homepage: String, rateLimitHint: String? = nil,
                operatorGated: Bool = false, notes: String? = nil) {
        self.key = key
        self.name = name
        self.category = category
        self.endpointHosts = endpointHosts
        self.license = license
        self.attribution = attribution
        self.homepage = homepage
        self.rateLimitHint = rateLimitHint
        self.operatorGated = operatorGated
        self.notes = notes
    }
}

public enum OSINTCategory: String, Equatable, Sendable, Codable {
    case baseMap
    case traffic
    case cameras
    case hazards
    case weather
    case imagery
    case elevation
    case airspace
    case seismic
    case civic
}

public struct OSINTSourceRegistry: Sendable {
    public let sources: [String: OSINTSource]

    public init(sources: [OSINTSource]) {
        var map: [String: OSINTSource] = [:]
        for s in sources { map[s.key] = s }
        self.sources = map
    }

    public func source(forKey key: String) -> OSINTSource? { sources[key] }

    /// Lookup by host. A URL host must map to exactly one registered
    /// source or the fetch is denied. Exact or subdomain suffix match.
    public func source(forHost host: String) -> OSINTSource? {
        let lower = host.lowercased()
        for (_, src) in sources {
            if src.endpointHosts.contains(where: { lower == $0 || lower.hasSuffix("." + $0) }) {
                return src
            }
        }
        return nil
    }

    public var attributions: [String] {
        sources.values.map(\.attribution).sorted()
    }

    public static let canonical = OSINTSourceRegistry(sources: [
        OSINTSource(
            key: "osm.tiles",
            name: "OpenStreetMap Standard Tile Server",
            category: .baseMap,
            endpointHosts: ["tile.openstreetmap.org"],
            license: "ODbL-1.0",
            attribution: "© OpenStreetMap contributors",
            homepage: "https://www.openstreetmap.org/copyright",
            rateLimitHint: "Tile Usage Policy: ≤2 req/s, valid User-Agent required. Prefer a mirror for volume.",
            notes: "Public fallback when Mapbox is degraded. Do not use for bulk download."
        ),
        OSINTSource(
            key: "mapbox.tiles",
            name: "Mapbox",
            category: .baseMap,
            endpointHosts: ["api.mapbox.com", "events.mapbox.com"],
            license: "Commercial (Mapbox ToS)",
            attribution: "© Mapbox © OpenStreetMap",
            homepage: "https://www.mapbox.com/legal/tos",
            rateLimitHint: "Per-plan quota; see dashboard.",
            notes: "Primary tile source. Public pk.* token only on clients."
        ),
        OSINTSource(
            key: "txdot.drivetexas",
            name: "TxDOT DriveTexas (CCTV / DMS / Incidents)",
            category: .traffic,
            endpointHosts: ["drivetexas.org", "its.txdot.gov"],
            license: "Public Information Act (open)",
            attribution: "Data: Texas Department of Transportation",
            homepage: "https://drivetexas.org/",
            rateLimitHint: "Be polite; no published quota. Cache aggressively.",
            notes: "Statewide roadway imagery, message signs, incident feed."
        ),
        OSINTSource(
            key: "firms.nasa",
            name: "NASA FIRMS (Fire Information for Resource Management)",
            category: .hazards,
            endpointHosts: ["firms.modaps.eosdis.nasa.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Fire detections: NASA FIRMS (MODIS/VIIRS)",
            homepage: "https://firms.modaps.eosdis.nasa.gov/",
            rateLimitHint: "Free MAP_KEY required; rotate if public-exposed.",
            notes: "Active-fire dots for situational awareness."
        ),
        OSINTSource(
            key: "noaa.nws",
            name: "NOAA / National Weather Service",
            category: .weather,
            endpointHosts: ["api.weather.gov", "radar.weather.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Weather: NOAA/NWS",
            homepage: "https://www.weather.gov/documentation/services-web-api",
            rateLimitHint: "User-Agent with contact required; no hard quota.",
            notes: "Alerts, radar, forecast grids."
        ),
        OSINTSource(
            key: "usgs.quake",
            name: "USGS Earthquake Hazards",
            category: .seismic,
            endpointHosts: ["earthquake.usgs.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Seismic: USGS",
            homepage: "https://earthquake.usgs.gov/fdsnws/event/1/",
            notes: "Live quake feed GeoJSON."
        ),
        OSINTSource(
            key: "usgs.nationalmap",
            name: "USGS The National Map",
            category: .imagery,
            endpointHosts: ["basemap.nationalmap.gov", "carto.nationalmap.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Imagery: USGS The National Map",
            homepage: "https://www.usgs.gov/programs/national-geospatial-program/national-map",
            notes: "High-resolution aerial imagery + elevation."
        ),
        OSINTSource(
            key: "faa.ofd",
            name: "FAA Operational Data (NOTAM / TFR)",
            category: .airspace,
            endpointHosts: ["tfr.faa.gov", "external-api.faa.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Airspace: FAA",
            homepage: "https://tfr.faa.gov/",
            notes: "Temporary flight restrictions, NOTAMs."
        )
    ])
}

/// Enforces the registry at the fetch boundary. Fail-closed.
public struct OSINTFetchGuard: Sendable {
    public enum Denial: Error, Equatable, CustomStringConvertible {
        case unlistedHost(String)
        case operatorOnly(sourceKey: String)
        case invalidURL

        public var description: String {
            switch self {
            case .unlistedHost(let host):
                return "OSINT fetch denied: host '\(host)' not in source registry (open-sources-only)."
            case .operatorOnly(let key):
                return "OSINT fetch denied: source '\(key)' is operator-gated."
            case .invalidURL:
                return "OSINT fetch denied: invalid URL."
            }
        }
    }

    public let registry: OSINTSourceRegistry
    public init(registry: OSINTSourceRegistry = .canonical) { self.registry = registry }

    public func authorize(url: URL, principal: Principal) -> Result<OSINTSource, Denial> {
        guard let host = url.host else { return .failure(.invalidURL) }
        guard let source = registry.source(forHost: host) else {
            return .failure(.unlistedHost(host))
        }
        if source.operatorGated {
            if case .operatorTier = principal { /* ok */ } else {
                return .failure(.operatorOnly(sourceKey: source.key))
            }
        }
        return .success(source)
    }
}
