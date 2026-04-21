import Foundation

/// NAV-001 Phase C: EMS/first-responder routing profile.
///
/// Responder-tier only (`principalScope == [.responder]`). Routes around
/// active hazard edges with heavy avoidance. Prioritizes highway/trunk
/// for rapid transit. This is situational awareness routing, NOT clinical
/// decision support — the profile knows nothing about medical acts.
///
/// CANON: operator-teachable; persistence ticket pending. EMS-taught
/// parameters live in-memory as `[String: Double]` only. Real persistence
/// is a downstream ticket.
public struct EMSPreferredProfile: RoutingProfile, Sendable {
    public let identifier: String = "ems_preferred"
    public let principalScope: Set<PrincipalCategory> = [.responder]

    /// CANON: operator-teachable; persistence ticket pending.
    /// Keyed override multipliers (e.g. ["avoid_residential": 1.5]).
    public let taughtParameters: [String: Double]

    public init(taughtParameters: [String: Double] = [:]) {
        self.taughtParameters = taughtParameters
    }

    public func edgeWeight(_ edge: RouteEdge, context: RoutingContext) -> Double {
        var weight = edge.lengthMeters

        // Active hazard repulsion: penalize edges that match a hazard by
        // summary-endpoint keyword ("fromNode->toNode" or edge id) or by
        // a coarse proximity check on point hazards if the edge carries
        // lat/lon attributes. Absent a spatial index, the keyword match
        // is the canonical test path.
        for hazard in context.activeHazards {
            let endpointKey = "\(edge.fromNode)->\(edge.toNode)"
            let matchesEdge = hazard.summary.contains(endpointKey) ||
                hazard.summary.contains(edge.id)
            guard matchesEdge else { continue }

            if hazard.severity == .critical {
                weight *= 10.0
                break
            } else if hazard.severity == .elevated {
                weight *= 2.0
            }
        }

        // Highway/trunk priority for EMS: faster roads preferred.
        if let highway = edge.attributes["highway"] {
            switch highway {
            case "motorway", "trunk":
                weight *= 0.75
            case "primary", "secondary":
                weight *= 0.85
            case "residential", "living_street":
                if let avoidMult = taughtParameters["avoid_residential"] {
                    weight *= avoidMult
                } else {
                    weight *= 1.3
                }
            default:
                break
            }
        }

        return weight
    }
}