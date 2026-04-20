import Foundation

/// NAV-001 Phase C: Scenic routing profile.
///
/// Available to all tiers. Penalizes highways and trunk roads;
/// prefers secondary, tertiary, and "living_street" edges for
/// scenic overlanding and exploration.
public struct ScenicProfile: RoutingProfile, Sendable {
    public let identifier: String = "scenic"
    public let principalScope: Set<PrincipalCategory> = [.grizz, .companion, .guest, .responder]

    public init() {}

    public func edgeWeight(_ edge: RouteEdge, context: RoutingContext) -> Double {
        let baseWeight = edge.lengthMeters

        // Heavy penalty for highways — scenic routing avoids them.
        if let highway = edge.attributes["highway"] {
            switch highway {
            case "motorway":
                return baseWeight * 5.0   // strongly avoid
            case "trunk":
                return baseWeight * 3.0    // avoid
            case "primary":
                return baseWeight * 1.5    // mildly avoid
            case "secondary", "tertiary", "unclassified":
                return baseWeight * 0.8    // prefer
            case "living_street", "residential":
                return baseWeight * 0.9    // slight preference
            default:
                return baseWeight
            }
        }
        return baseWeight
    }
}