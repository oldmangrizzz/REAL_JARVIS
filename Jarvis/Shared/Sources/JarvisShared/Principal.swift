import Foundation

/// The human principal associated with a connected device or voice utterance.
///
/// Brand surfaces as "Jarvis — powered by Grizz OS" (operator) versus
/// "Jarvis — powered by Companion OS" (family). The principal is always
/// resolved server-side from a trusted source (identity store at tunnel
/// registration, speaker diarization at utterance time). Clients never
/// assert their own principal.
///
/// ## Canon (operator directive)
///
/// - **Grizz OS** — "like me. Raw, unredacted, completely in your face.
///   Full function and full tilt." Operator at home.
/// - **Companion OS** — "how you act in front of your friends and your
///   family." Socialized Jarvis, scoped authority, same warmth.
/// - **Responder OS** (future case) — "1900 Grizz. The operating system
///   when it puts on a uniform and realizes, oh, I got to go to work
///   and be a good boy today, because we got to keep food on the table."
///   Jarvis clocked-in.
public enum Principal: Equatable, Sendable, Hashable {
    /// Grizz: unlimited scope, biometric-bound on his devices. Only one.
    case operatorTier
    /// Family member with scoped access (wife, daughter, etc.). The
    /// `memberID` is the stable companion identifier set at onboarding.
    case companion(memberID: String)
    /// Unknown speaker / unregistered device. Fail-closed default. Gets
    /// the narrowest read-only surface.
    case guestTier

    /// Cockpit subtitle: "powered by Grizz OS" / "powered by Companion OS"
    /// / "powered by Companion OS (guest)".
    public var brandSubtitle: String {
        switch self {
        case .operatorTier: return "powered by Grizz OS"
        case .companion: return "powered by Companion OS"
        case .guestTier: return "powered by Companion OS (guest)"
        }
    }

    /// Stable serialized form for identities.json and telemetry.
    public var tierToken: String {
        switch self {
        case .operatorTier: return "grizz"
        case .companion(let id): return "companion:\(id)"
        case .guestTier: return "guest"
        }
    }

    /// Parses a server-side token. Client-asserted values are ignored;
    /// this is only used by the identity store + telemetry.
    public static func fromTierToken(_ token: String) -> Principal? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "grizz" || trimmed == "operator" { return .operatorTier }
        if trimmed == "guest" { return .guestTier }
        if trimmed.hasPrefix("companion:") {
            let id = String(trimmed.dropFirst("companion:".count))
            guard !id.isEmpty else { return nil }
            return .companion(memberID: id)
        }
        return nil
    }
}
