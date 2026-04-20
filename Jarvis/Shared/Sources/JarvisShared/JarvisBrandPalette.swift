import Foundation

/// SPEC-009 / brand tokens: palette for tier-aware UI surfaces.
///
/// Grizz OS (operator) runs the Munro/Stark palette: black hull, silver chrome,
/// crimson alerts, and emerald (Clan Munro green) as the primary accent.
///
/// Companion OS (family) is the same chassis with the accent swapped from
/// emerald to teal-cyan so the tier is legible at a glance from across a
/// room. Everything else — crimson alerts, silver chrome, black canvas —
/// stays identical so safety signals read the same across both tiers.
///
/// Every UI surface (Unity alpha/beta/foxtrot/echo, cockpit PWA, Obsidian
/// plugin, mobile, watch, tvOS, CarPlay) MUST pull its palette from here.
/// The concrete renderer translates these tokens into the native color type
/// (Color / UIColor / NSColor / Unity Color / CSS var).
public struct JarvisBrandPalette: Sendable, Equatable {

    /// Canvas — the deep background all surfaces sit on. Same for both tiers.
    public let canvasBlackHex: String
    /// Chrome — bezels, frames, structural chrome. Same for both tiers.
    public let chromeSilverHex: String
    /// Alert — crimson reserved for destructive/red-zone UI. Same for both
    /// tiers so "this is serious" reads identically across the house.
    public let alertCrimsonHex: String
    /// Accent — the only thing that changes between tiers. Emerald for
    /// Grizz OS, teal-cyan for Companion OS.
    public let accentHex: String
    /// Accent glow — slightly lighter variant for focus / active states.
    public let accentGlowHex: String

    /// Human-readable tier label shown next to the Jarvis wordmark.
    public let tierLabel: String

    // MARK: - Canonical palettes

    /// Grizz OS — operator tier. Clan Munro emerald accent.
    public static let grizzOS = JarvisBrandPalette(
        canvasBlackHex: "#0A0B0F",
        chromeSilverHex: "#C7CBD1",
        alertCrimsonHex: "#C8102E",
        accentHex: "#00A878",      // Munro emerald
        accentGlowHex: "#38E0A6",  // focus/active state
        tierLabel: "powered by Grizz OS"
    )

    /// Companion OS — family tier. Teal-cyan accent, everything else mirrored.
    public static let companionOS = JarvisBrandPalette(
        canvasBlackHex: "#0A0B0F",
        chromeSilverHex: "#C7CBD1",
        alertCrimsonHex: "#C8102E",
        accentHex: "#00B8C4",      // teal-cyan
        accentGlowHex: "#5FE5EE",  // focus/active state
        tierLabel: "powered by Companion OS"
    )

    /// Companion OS guest variant — dimmed accent so unregistered speakers
    /// can tell at a glance they're in a limited context.
    public static let companionGuest = JarvisBrandPalette(
        canvasBlackHex: "#0A0B0F",
        chromeSilverHex: "#8A8E95",  // dimmed chrome
        alertCrimsonHex: "#C8102E",
        accentHex: "#4E7B80",        // dimmed teal
        accentGlowHex: "#7AA3A8",
        tierLabel: "powered by Companion OS (guest)"
    )

    /// Responder OS — first-responder / field-integration tier. Separate
    /// visual identity so a medic / firefighter / officer glancing at a
    /// screen never mistakes it for the domestic Grizz OS or Companion OS
    /// surface. Blue / white / gold / black per operator direction.
    ///
    /// Canvas stays black for night-shift legibility. Chrome is white
    /// (sterile, high-contrast) rather than silver. Alert stays crimson-
    /// adjacent but leans into the gold channel for "attention, not panic"
    /// on a duty device. Accent is duty-blue.
    public static let responderOS = JarvisBrandPalette(
        canvasBlackHex: "#05070C",
        chromeSilverHex: "#F4F6FA",  // sterile white
        alertCrimsonHex: "#C8102E",  // crimson alert stays constant
        accentHex: "#0B5FFF",        // duty blue
        accentGlowHex: "#F2B707",    // gold focus / priority state
        tierLabel: "powered by Responder OS"
    )

    /// Resolve the right palette for a principal.
    public static func palette(for principal: Principal) -> JarvisBrandPalette {
        switch principal {
        case .operatorTier: return .grizzOS
        case .companion: return .companionOS
        case .guestTier: return .companionGuest
        }
    }
}
