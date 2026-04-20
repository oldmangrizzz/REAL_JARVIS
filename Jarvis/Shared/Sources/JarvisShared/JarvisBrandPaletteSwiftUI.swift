import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// SwiftUI bridge for JarvisBrandPalette — turns the canonical hex tokens
/// into native `Color` values and exposes the palette as an `Environment`
/// key so any cockpit surface can branch on the active tier without
/// hardcoding colour per platform target.
///
/// This file is the single place per-platform SwiftUI code should convert
/// from brand hex to `Color`. Every other view reaches it through:
///
///     @Environment(\.jarvisPalette) var palette
///
/// The root app sets `.environment(\.jarvisPalette, .palette(for: principal))`
/// whenever the bound principal changes.
///
/// On non-SwiftUI builds (command-line tools, server hosts) this file still
/// compiles — the bridge is only expanded when SwiftUI is available.

#if canImport(SwiftUI)

public extension JarvisBrandPalette {
    /// Canvas (deep background) as a SwiftUI Color.
    var canvasBlackColor: Color { Color(hex: canvasBlackHex) ?? .black }
    /// Chrome (frames / bezels / structural).
    var chromeSilverColor: Color { Color(hex: chromeSilverHex) ?? .gray }
    /// Alert (crimson — reserved for destructive / red-zone UI).
    var alertCrimsonColor: Color { Color(hex: alertCrimsonHex) ?? .red }
    /// Accent (the tier-changing colour — emerald / teal / duty-blue / dim).
    var accentColor: Color { Color(hex: accentHex) ?? .accentColor }
    /// Accent glow (focus / active state, slightly lighter variant).
    var accentGlowColor: Color { Color(hex: accentGlowHex) ?? accentColor }
}

private struct JarvisPaletteKey: EnvironmentKey {
    /// Default falls back to Grizz OS so bare previews / tests don't crash.
    /// Real rendering surfaces ALWAYS override via `.environment` on bind.
    static let defaultValue: JarvisBrandPalette = .grizzOS
}

public extension EnvironmentValues {
    /// Active tier palette. Cockpit root sets this per bound principal.
    var jarvisPalette: JarvisBrandPalette {
        get { self[JarvisPaletteKey.self] }
        set { self[JarvisPaletteKey.self] = newValue }
    }
}

public extension View {
    /// Convenience: swap tier palette on a view subtree without importing
    /// the environment key type manually.
    func jarvisPalette(_ palette: JarvisBrandPalette) -> some View {
        environment(\.jarvisPalette, palette)
    }

    /// Convenience: bind from a principal directly.
    func jarvisPalette(for principal: Principal) -> some View {
        environment(\.jarvisPalette, JarvisBrandPalette.palette(for: principal))
    }
}

#endif

/// 6-digit `#RRGGBB` hex parser. Exposed separately so non-SwiftUI targets
/// can still resolve palette hex to 0–1 components (e.g. for Unity exports,
/// AppKit NSColor construction, or CLI diagnostics).
public struct JarvisPaletteHex {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6,
              let value = UInt32(cleaned, radix: 16) else { return nil }
        self.red   = Double((value >> 16) & 0xFF) / 255.0
        self.green = Double((value >> 8) & 0xFF) / 255.0
        self.blue  = Double(value & 0xFF) / 255.0
    }
}

#if canImport(SwiftUI)
private extension Color {
    init?(hex: String) {
        guard let rgb = JarvisPaletteHex(hex: hex) else { return nil }
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1.0)
    }
}
#endif
