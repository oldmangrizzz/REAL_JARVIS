import Foundation

/// NAV-001 Phase E: Scene briefing — the fused situational-awareness
/// snapshot that Qwen (UX-001) presents on the navigation surface.
///
/// Constructed by `ScenePreSearch.gather(principal:near:radiusMeters:)`.
/// Tier-gated: guest tier gets an empty briefing; operator gets the
/// full fusion of all registered hazard layers.
public struct SceneBriefing: Sendable, Equatable, Codable {
    public let requestedAt: Date
    public let principal: Principal
    public let hazards: [HazardOverlayFeature]
    /// Registry keys present in this briefing (for layer attribution).
    public let nearbyLayers: [String]
    public let summary: String

    public init(requestedAt: Date, principal: Principal,
                hazards: [HazardOverlayFeature], nearbyLayers: [String],
                summary: String) {
        self.requestedAt = requestedAt
        self.principal = principal
        self.hazards = hazards
        self.nearbyLayers = nearbyLayers
        self.summary = summary
    }
}