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