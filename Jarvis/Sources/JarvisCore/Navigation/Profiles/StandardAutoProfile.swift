import Foundation

/// NAV-001 Phase C: Standard auto routing profile.
///
/// Available to all four principal categories. Baseline Dijkstra weight
/// is edge length in meters. Highway edges get a mild speed bonus but
/// no special penalty — this is the default "get me there fast" profile.
public struct StandardAutoProfile: RoutingProfile, Sendable {
    public let identifier: String = "standard_auto"
    public let principalScope: Set<PrincipalCategory> = [.grizz, .companion, .guest, .responder]

    public init() {}

    public func edgeWeight(_ edge: RouteEdge, context: RoutingContext) -> Double {
        // Baseline: length in meters. Highway gets slight bonus (lower weight).
        let baseWeight = edge.lengthMeters
        if let highway = edge.attributes["highway"] {
            switch highway {
            case "motorway", "trunk":
                return baseWeight * 0.9  // 10% speed advantage
            default:
                return baseWeight
            }
        }
        return baseWeight
    }
}