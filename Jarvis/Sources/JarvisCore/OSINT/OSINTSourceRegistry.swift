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
        ),

        // MARK: Recreation / overlanding / dispersed camping / scenic
        //
        // Every entry below is a public API with published terms we can
        // comply with. See `deniedSources` for explicitly-rejected feeds.
        OSINTSource(
            key: "recreation.gov",
            name: "Recreation.gov (federal reservation system)",
            category: .civic,
            endpointHosts: ["ridb.recreation.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Recreation data: Recreation.gov / RIDB",
            homepage: "https://ridb.recreation.gov/docs",
            rateLimitHint: "Free API key; be a good neighbor on volume.",
            notes: "Campgrounds, permits, tours across USFS / BLM / NPS / USACE."
        ),
        OSINTSource(
            key: "nps.api",
            name: "National Park Service API",
            category: .civic,
            endpointHosts: ["developer.nps.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Park data: US National Park Service",
            homepage: "https://www.nps.gov/subjects/developer/api-documentation.htm",
            rateLimitHint: "Free data.gov API key.",
            notes: "Parks, visitor centers, alerts, activities."
        ),
        OSINTSource(
            key: "blm.arcgis",
            name: "Bureau of Land Management (ArcGIS REST)",
            category: .civic,
            endpointHosts: ["gis.blm.gov", "services.arcgis.com"],
            license: "Public Domain (US Gov) via BLM open data",
            attribution: "Public land: BLM",
            homepage: "https://gis.blm.gov/",
            notes: "Dispersed camping areas, surface management, LTVAs, public land boundaries. Note services.arcgis.com is multi-tenant; filter by layer."
        ),
        OSINTSource(
            key: "usfs.fsgeodata",
            name: "USFS FSGeodata Clearinghouse",
            category: .civic,
            endpointHosts: ["data.fs.usda.gov", "apps.fs.usda.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Forest data: USDA Forest Service",
            homepage: "https://data.fs.usda.gov/geodata/",
            notes: "MVUMs (Motor Vehicle Use Maps), forest roads, dispersed camping corridors, trailheads."
        ),
        OSINTSource(
            key: "osm.overpass",
            name: "OpenStreetMap Overpass API",
            category: .civic,
            endpointHosts: ["overpass-api.de", "overpass.kumi.systems"],
            license: "ODbL-1.0",
            attribution: "© OpenStreetMap contributors",
            homepage: "https://wiki.openstreetmap.org/wiki/Overpass_API",
            rateLimitHint: "Expensive queries: keep bbox small, cache, respect timeout. Consider self-hosting for volume.",
            notes: "Overland / scenic / amenity queries via tourism=*, natural=*, highway=track/unpaved, leisure=*, shop=*."
        ),
        OSINTSource(
            key: "osm.nominatim",
            name: "OSM Nominatim (geocoding)",
            category: .civic,
            endpointHosts: ["nominatim.openstreetmap.org"],
            license: "ODbL-1.0",
            attribution: "© OpenStreetMap contributors",
            homepage: "https://operations.osmfoundation.org/policies/nominatim/",
            rateLimitHint: "≤1 req/s, valid User-Agent with contact, no heavy use. Self-host for volume.",
            notes: "Free-text → coordinate + reverse geocoding."
        ),
        OSINTSource(
            key: "geonames",
            name: "GeoNames",
            category: .civic,
            endpointHosts: ["api.geonames.org", "secure.geonames.org"],
            license: "CC-BY-4.0",
            attribution: "Place data: GeoNames (CC BY 4.0)",
            homepage: "https://www.geonames.org/",
            rateLimitHint: "Free tier: 20k credits/day with username registration.",
            notes: "POIs, populated places, postal codes, nearby features."
        ),
        OSINTSource(
            key: "usgs.gnis",
            name: "USGS Geographic Names Information System",
            category: .civic,
            endpointHosts: ["edits.nationalmap.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Place names: USGS GNIS",
            homepage: "https://www.usgs.gov/us-board-on-geographic-names/domestic-names",
            notes: "Official US place names, historical names, ghost towns."
        ),
        OSINTSource(
            key: "epa.airnow",
            name: "EPA AirNow",
            category: .weather,
            endpointHosts: ["www.airnowapi.org", "airnowapi.org"],
            license: "Public Domain (US Gov) with attribution",
            attribution: "Air quality: EPA AirNow",
            homepage: "https://docs.airnowapi.org/",
            rateLimitHint: "Free API key.",
            notes: "Real-time AQI for route planning and respiratory-sensitive companions."
        ),
        OSINTSource(
            key: "noaa.tides",
            name: "NOAA Tides & Currents (CO-OPS)",
            category: .weather,
            endpointHosts: ["api.tidesandcurrents.noaa.gov"],
            license: "Public Domain (US Gov)",
            attribution: "Tides/currents: NOAA CO-OPS",
            homepage: "https://api.tidesandcurrents.noaa.gov/api/prod/",
            notes: "Coastal route timing, boat-ramp viability, tide windows."
        ),
        OSINTSource(
            key: "wikipedia.rest",
            name: "Wikipedia REST API",
            category: .civic,
            endpointHosts: ["en.wikipedia.org", "en.wikivoyage.org"],
            license: "CC-BY-SA-4.0 (content) / GFDL (legacy)",
            attribution: "Context: Wikipedia / Wikivoyage contributors (CC BY-SA 4.0)",
            homepage: "https://en.wikipedia.org/api/rest_v1/",
            rateLimitHint: "User-Agent with contact required; 200 req/s burst ceiling.",
            notes: "POI context, historical marker narratives, scenic-route background."
        ),
        OSINTSource(
            key: "tpwd.texas",
            name: "Texas Parks & Wildlife Open Data",
            category: .civic,
            endpointHosts: ["tpwd.texas.gov", "gis-tpwd.opendata.arcgis.com"],
            license: "Public (Texas Public Information Act)",
            attribution: "Texas parks data: TPWD",
            homepage: "https://tpwd.texas.gov/",
            notes: "State parks, WMAs, boat ramps, public water access, hunting/fishing zones. Home-region priority."
        ),
        OSINTSource(
            key: "wdpa.protectedplanet",
            name: "Protected Planet (WDPA)",
            category: .civic,
            endpointHosts: ["api.protectedplanet.net"],
            license: "CC-BY-4.0 (with registration)",
            attribution: "Protected areas: UNEP-WCMC / IUCN via Protected Planet",
            homepage: "https://www.protectedplanet.net/en/resources/wdpa-manual",
            rateLimitHint: "Free API token; attribution mandatory.",
            notes: "Global protected-area polygons for overland legality checks."
        )
    ])

    // MARK: - Explicit denylist (documentation, not enforcement)
    //
    // Feeds the operator or a future agent might be tempted to add but
    // which fail the gray-not-black test. Listed here so a human
    // reviewing this file sees WHY they're absent. Do NOT add without
    // a sanctioned API agreement or license change.
    public static let deniedSources: [String: String] = [
        "roadsideamerica.com": "No public API; scraping violates site TOS. Black, not gray.",
        "ioverlander.com": "API access has been locked to sanctioned partners; wait for official agreement before adding.",
        "campendium.com": "Commercial, no open API. Do not scrape.",
        "thedyrt.com": "Commercial, no open API. Do not scrape.",
        "alltrails.com": "Commercial, no open API. Use USFS trails + OSM Overpass natural=* for overland/trail data instead.",
        "freecampsites.net": "No public API; content mostly already represented in BLM/USFS/Recreation.gov + OSM.",
        "strava.com/heatmap": "Requires authenticated scraping beyond ToS. Use OSM Overpass for public trail data."
    ]
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
