import Foundation

/// NAV-001 Phase C: Accessibility-optimized routing profile.
///
/// Available to companion and responder categories. Prefers edges tagged
/// `accessibility=ramp` or `curbramp`. Penalizes steps and steep grades.
/// Companion tier needs accessible routing for family; responder tier
/// needs ADA-compliant approach to incident scenes.
public struct AccessibilityProfile: RoutingProfile, Sendable {
    public let identifier: String = "accessibility"
    public let principalScope: Set<PrincipalCategory> = [.companion, .responder]

    public init() {}

    public func edgeWeight(_ edge: RouteEdge, context: RoutingContext) -> Double {
        let baseWeight = edge.lengthMeters

        // Bonus for accessibility-tagged edges.
        if edge.attributes["accessibility"] == "ramp" || edge.attributes["accessibility"] == "curbramp" {
            return baseWeight * 0.8  // 20% preference
        }

        // Heavy penalty for steps/steep.
        if edge.attributes["highway"] == "steps" {
            return baseWeight * 5.0
        }

        // Moderate penalty for steep grades.
        if let grade = edge.attributes["incline"], grade.hasSuffix("%") {
            if let pct = Double(grade.dropLast()), pct > 8.0 {
                return baseWeight * 2.0
            }
        }

        return baseWeight
    }
}