import Foundation

/// NAV-001 Phase B: Categorization of `Principal` for routing scope.
///
/// This enum maps `Principal` cases into routing categories used by
/// `RoutingProfile.principalScope`. The mapping is exhaustive and
/// stored as a `Set<PrincipalCategory>` on each profile — no default
/// fallthrough.
public enum PrincipalCategory: String, Sendable, Hashable, Codable {
    case grizz
    case companion
    case guest
    case responder

    /// Map a `Principal` to its routing category.
    public static func of(_ p: Principal) -> PrincipalCategory {
        switch p {
        case .operatorTier: return .grizz
        case .companion: return .companion
        case .guestTier: return .guest
        case .responder: return .responder
        }
    }
}

/// Protocol describing a routing profile used by the navigation engine.
///
/// A profile defines which `PrincipalCategory` values are within its
/// routing scope and provides a hook for custom edge‑weight calculations.
/// Implementations may supply additional constraints (e.g. hazard
/// avoidance, cost modifiers, etc.) via the `edgeWeight(for:)` method.
public protocol RoutingProfile: Sendable {
    /// The set of principal categories that this profile is allowed to
    /// traverse.  The navigation orchestrator will filter edges based on
    /// whether the edge’s associated principal belongs to this set.
    var principalScope: Set<PrincipalCategory> { get }

    /// Compute a weight for a given edge.  Returning `nil` indicates that
    /// the edge should be considered impassable for this profile.
    ///
    /// - Parameter edge: The edge being evaluated.
    /// - Returns: A `Double` representing the traversal cost, or `nil`
    ///            if the edge is disallowed.
    func edgeWeight(for edge: Edge) -> Double?
}

/// Default implementation that treats all edges as traversable with a
/// neutral weight of `1.0`.  Concrete profiles can override this method
/// to apply custom logic (e.g., hazard penalties, distance scaling, etc.).
extension RoutingProfile {
    public func edgeWeight(for edge: Edge) -> Double? {
        // Placeholder logic – concrete profiles should provide a real
        // implementation.  Returning a constant weight keeps the engine
        // functional while allowing specialization later.
        return 1.0
    }
}