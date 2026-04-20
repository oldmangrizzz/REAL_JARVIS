import Foundation

/// Responder certification level. Strict escalation EMR < EMT < AEMT < EMTP.
///
/// Jarvis in Responder OS tier is an **advocacy + situational awareness**
/// layer, not a clinician. Role level gates the *depth* of protocol and
/// documentation surfaces he can offer, never what clinical act gets
/// performed. Mission: empowerment, not replacement.
///
/// - Emergency Medical Responder (EMR) — basic life support, bleeding
///   control, CPR, AED. Level 1.
/// - Emergency Medical Technician (EMT) — BLS + basic airway, glucose,
///   epi auto-injector, albuterol. Level 2.
/// - Advanced EMT (AEMT) — EMT + IV/IO access, limited medications,
///   supraglottic airway. Level 3.
/// - Paramedic (EMTP) — ALS, advanced airway, cardiac monitoring,
///   full formulary. Level 4.
public enum ResponderRole: String, Equatable, Sendable, Hashable, Codable {
    case emr
    case emt
    case aemt
    case emtp

    /// Ordinal 1…4. Used for capability escalation comparisons so an
    /// EMTP can reference anything an EMR can, and strictly more.
    public var certLevel: Int {
        switch self {
        case .emr: return 1
        case .emt: return 2
        case .aemt: return 3
        case .emtp: return 4
        }
    }
}

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
public enum Principal: Equatable, Sendable, Hashable, Codable {
    /// Grizz: unlimited scope, biometric-bound on his devices. Only one.
    case operatorTier
    /// Family member with scoped access (wife, daughter, etc.). The
    /// `memberID` is the stable companion identifier set at onboarding.
    case companion(memberID: String)
    /// Unknown speaker / unregistered device. Fail-closed default. Gets
    /// the narrowest read-only surface.
    case guestTier
    /// On-duty first responder (EMR/EMT/AEMT/EMTP). "Clocked-in Jarvis."
    /// Advocacy + situational awareness role — never clinical. Role level
    /// modulates protocol-lookup depth; no level grants clinical-execution
    /// authority. Mission: empowerment, not replacement.
    case responder(role: ResponderRole)

    /// Cockpit subtitle: "powered by Grizz OS" / "powered by Companion OS"
    /// / "powered by Companion OS (guest)" / "powered by Responder OS".
    public var brandSubtitle: String {
        switch self {
        case .operatorTier: return "powered by Grizz OS"
        case .companion: return "powered by Companion OS"
        case .guestTier: return "powered by Companion OS (guest)"
        case .responder: return "powered by Responder OS"
        }
    }

    /// Stable serialized form for identities.json and telemetry.
    public var tierToken: String {
        switch self {
        case .operatorTier: return "grizz"
        case .companion(let id): return "companion:\(id)"
        case .guestTier: return "guest"
        case .responder(let role): return "responder:\(role.rawValue)"
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
        if trimmed.hasPrefix("responder:") {
            let raw = String(trimmed.dropFirst("responder:".count))
            guard let role = ResponderRole(rawValue: raw) else { return nil }
            return .responder(role: role)
        }
        return nil
    }

    // MARK: - Codable
    //
    // Serialize as the tierToken string so on-disk form matches
    // identities.json and telemetry rows exactly. No client can encode a
    // malformed principal; unknown tokens fail to decode.

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let token = try container.decode(String.self)
        guard let resolved = Principal.fromTierToken(token) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Principal tier token: \(token)"
            )
        }
        self = resolved
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tierToken)
    }
}
