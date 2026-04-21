import SwiftUI

// MARK: - Navigation Tier Definition

/// Represents the logical tiers used within the navigation system.
public enum NavigationTier {
    case primary
    case secondary
    case tertiary
}

// MARK: - Navigation Design Tokens

/// Centralised design‑token source for the navigation module. It provides:
///   • Tier‑aware colour roles resolved through ``JarvisBrandPalette``
///   • Typography scales for the map surface (Phase A)
///   • A catalogue of reusable SF Symbol icons (Phase B)
public struct NavigationDesignTokens {
    
    // MARK: Colour Roles
    
    /// Colour roles that are required for a navigation UI component.
    public struct Colors {
        public let background: Color
        public let foreground: Color
        public let border: Color
        public let accent: Color
        
        public init(background: Color,
                    foreground: Color,
                    border: Color,
                    accent: Color) {
            self.background = background
            self.foreground = foreground
            self.border = border
            self.accent = accent
        }
    }
    
    /// Returns the colour set for a given navigation tier.
    ///
    /// The colours are resolved via the shared ``JarvisBrandPalette`` instance,
    /// ensuring brand‑consistent values across the app.
    public static func colors(for tier: NavigationTier) -> Colors {
        let palette = JarvisBrandPalette.shared
        
        switch tier {
        case .primary:
            return Colors(
                background: palette.color(.navigationPrimaryBackground),
                foreground: palette.color(.navigationPrimaryForeground),
                border:     palette.color(.navigationPrimaryBorder),
                accent:    palette.color(.navigationPrimaryAccent)
            )
        case .secondary:
            return Colors(
                background: palette.color(.navigationSecondaryBackground),
                foreground: palette.color(.navigationSecondaryForeground),
                border:     palette.color(.navigationSecondaryBorder),
                accent:    palette.color(.navigationSecondaryAccent)
            )
        case .tertiary:
            return Colors(
                background: palette.color(.navigationTertiaryBackground),
                foreground: palette.color(.navigationTertiaryForeground),
                border:     palette.color(.navigationTertiaryBorder),
                accent:    palette.color(.navigationTertiaryAccent)
            )
        }
    }
    
    // MARK: Typography Scales
    
    /// Typography scale used on the map surface.
    public struct Typography {
        public let title: Font
        public let subtitle: Font
        public let body: Font
        public let caption: Font
        
        public init(title: Font,
                    subtitle: Font,
                    body: Font,
                    caption: Font) {
            self.title = title
            self.subtitle = subtitle
            self.body = body
            self.caption = caption
        }
    }
    
    /// Pre‑defined typography for the map surface (Phase A).
    public static let mapSurfaceTypography = Typography(
        title:    .system(size: 20, weight: .semibold, design: .default),
        subtitle: .system(size: 16, weight: .regular,  design: .default),
        body:     .system(size: 14, weight: .regular,  design: .default),
        caption:  .system(size: 12, weight: .light,    design: .default)
    )
    
    // MARK: Icon Catalogue
    
    /// Catalogue of icons used throughout navigation UI.
    ///
    /// The icons are SF Symbols wrapped in ``Image`` for easy reuse.
    public enum Icon {
        case back
        case close
        case location
        case search
        case refresh
        
        /// Returns the ``Image`` representation of the icon.
        public var image: Image {
            switch self {
            case .back:
                return Image(systemName: "chevron.left")
            case .close:
                return Image(systemName: "xmark")
            case .location:
                return Image(systemName: "mappin.and.ellipse")
            case .search:
                return Image(systemName: "magnifyingglass")
            case .refresh:
                return Image(systemName: "arrow.clockwise")
            }
        }
    }
}