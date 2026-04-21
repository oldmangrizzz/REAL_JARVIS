import Foundation

/// NAV-001 Phase E: Pre-search protocol.
///
/// Gathers a `SceneBriefing` by fanning out to the configured hazard
/// adapters, filtered by principal tier. The default implementation
/// (`DefaultScenePreSearch`) is tier-agnostic in its infrastructure
/// but tier-gated in its output: guest tier returns an empty briefing.
///
/// Tier policy (documented in module wiki):
///   - Operator: all layers (traffic + fire + weather + seismic)
///   - Companion: traffic + fire + weather (seismic excluded — lower
///     relevance for family routing)
///   - Responder: traffic + fire + weather + seismic (same as operator
///     but filtered for EMS-relevant incidents)
///   - Guest: empty briefing (no hazard data)
public protocol ScenePreSearch: Sendable {
    func gather(principal: Principal, near: LatLon, radiusMeters: Double) async throws -> SceneBriefing
}

/// Default implementation fanning out to hazard adapters per tier.
public struct DefaultScenePreSearch: ScenePreSearch, Sendable {

    private let adapters: [any HazardAdapter]
    private let cache: HazardCache

    /// Which adapter source keys to include per principal category.
    public static func allowedSourceKeys(for category: PrincipalCategory) -> Set<String> {
        switch category {
        case .grizz:
            return ["txdot.drivetexas", "firms.nasa", "noaa.nws", "usgs.quake"]
        case .companion:
            return ["txdot.drivetexas", "firms.nasa", "noaa.nws"]
        case .responder:
            return ["txdot.drivetexas", "firms.nasa", "noaa.nws", "usgs.quake"]
        case .guest:
            return []
        }
    }

    public init(adapters: [any HazardAdapter], cache: HazardCache = HazardCache()) {
        self.adapters = adapters
        self.cache = cache
    }

    public func gather(principal: Principal, near: LatLon, radiusMeters: Double) async throws -> SceneBriefing {
        let category = PrincipalCategory.of(principal)
        let allowed = Self.allowedSourceKeys(for: category)

        // Guest tier: empty briefing, no adapters queried.
        guard !allowed.isEmpty else {
            return SceneBriefing(
                requestedAt: Date(),
                principal: principal,
                hazards: [],
                nearbyLayers: [],
                summary: "Guest tier: no situational-awareness data available."
            )
        }

        var allHazards: [HazardOverlayFeature] = []
        var layers: [String] = []

        for adapter in adapters where allowed.contains(adapter.sourceKey) {
            // Check cache first.
            if let cached = await cache.get(adapter.sourceKey) {
                allHazards.append(contentsOf: cached)
                layers.append(adapter.sourceKey)
                continue
            }
            do {
                let features = try await adapter.fetch(principal: principal)
                await cache.put(adapter.sourceKey, features)
                allHazards.append(contentsOf: features)
                layers.append(adapter.sourceKey)
            } catch {
                // Adapter failure does not kill the entire briefing.
                // Log but continue with other adapters.
                continue
            }
        }

        let summary = buildSummary(hazards: allHazards, category: category)

        return SceneBriefing(
            requestedAt: Date(),
            principal: principal,
            hazards: allHazards,
            nearbyLayers: layers,
            summary: summary
        )
    }

    private func buildSummary(hazards: [HazardOverlayFeature], category: PrincipalCategory) -> String {
        guard !hazards.isEmpty else {
            return "No active hazards in range."
        }
        let critical = hazards.filter { $0.severity == .critical }.count
        let elevated = hazards.filter { $0.severity == .elevated }.count
        let info = hazards.filter { $0.severity == .info }.count
        return "\(hazards.count) hazard(s): \(critical) critical, \(elevated) elevated, \(info) info."
    }
}