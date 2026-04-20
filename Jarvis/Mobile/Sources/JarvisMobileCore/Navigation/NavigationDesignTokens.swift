import Foundation
import SwiftUI

/// Phase A — Navigation design tokens.
/// 
/// Color roles that resolve to JarvisBrandPalette tokens per tier.
/// Typography scale and iconography set for HUD consistency.
/// 
/// Doctrine: ATAK information density, Stark HUD class, GMRIWorkshop house style.
/// Readable in moving ambulance at night AND on Vision Pro in quiet lab.
public enum NavigationDesignTokens {
    
    // MARK: - Color Roles (HUD)
    
    /// Ground — the base layer everything sits on.
    public enum Ground {
        public static func color(for principal: Principal) -> Color {
            Color(hex: JarvisBrandPalette.palette(for: principal).canvasBlackHex)
        }
        public static let attribution: String = "OS base map overlay"
    }
    
    /// Primary track — active route path (operator/responder).
    public enum PrimaryTrack {
        public static func color(for principal: Principal) -> Color {
            switch principal {
            case .operatorTier, .responder: return Color(hex: JarvisBrandPalette.grizzOS.accentHex) // emerald
            case .companion: return Color(hex: JarvisBrandPalette.companionOS.accentHex) // teal-cyan
            case .guestTier: return Color(hex: "#666666") // dimmed gray for guest
            }
        }
        public static func width(for principal: Principal) -> CGFloat {
            switch principal {
            case .operatorTier, .responder: return 4.0
            case .companion: return 3.5
            case .guestTier: return 2.5
            }
        }
        public static let attribution: String = "Active route track"
    }
    
    /// Alternate track — secondary route options (operator only).
    public enum AlternateTrack {
        public static func color(for principal: Principal) -> Color {
            guard case .operatorTier = principal else { return .clear }
            return Color(hex: "#FFD700") // golden for secondary routes
        }
        public static let attribution: String = "Alternative route (operator)"
    }
    
    /// Hazard — critical severity (fire, severe storm).
    public enum HazardCritical {
        public static func color(for principal: Principal) -> Color {
            Color(hex: JarvisBrandPalette.palette(for: principal).alertCrimsonHex)
        }
        public static let attribution: String = "Critical hazard overlay"
    }
    
    /// Hazard — elevated severity (moderate traffic, light weather).
    public enum HazardElevated {
        public static func color(for principal: Principal) -> Color {
            Color(hex: "#FF8C00") // dark orange
        }
        public static let attribution: String = "Elevated hazard overlay"
    }
    
    /// Hazard — informational (parking, accessibility).
    public enum HazardInfo {
        public static func color(for principal: Principal) -> Color {
            switch principal {
            case .operatorTier, .responder: return Color(hex: "#00BFFF") // deep sky blue
            case .companion: return Color(hex: "#1E90FF") // dodger blue
            case .guestTier: return Color(hex: "#808080") // dimmed
            }
        }
        public static let attribution: String = "Informational hazard overlay"
    }
    
    /// Accessibility aid — curb cuts, elevators, accessible routes (companion tier).
    public enum AccessibilityAid {
        public static func color(for principal: Principal) -> Color {
            guard case .companion = principal else { return .clear }
            return Color(hex: "#00CED1") // dark turquoise
        }
        public static let attribution: String = "Accessibility features"
    }
    
    /// Scene briefing — background panel for briefing cards.
    public enum SceneBriefing {
        public static func color(for principal: Principal) -> Color {
            Color(hex: JarvisBrandPalette.palette(for: principal).canvasBlackHex).opacity(0.85)
        }
        public static func stroke(for principal: Principal) -> Color {
            Color(hex: JarvisBrandPalette.palette(for: principal).chromeSilverHex).opacity(0.4)
        }
    }
    
    /// Attribution — footer text for map layers.
    public enum AttributionFoot {
        public static func color(for principal: Principal) -> Color {
            Color(hex: JarvisBrandPalette.palette(for: principal).chromeSilverHex).opacity(0.7)
        }
        public static let fontSize: CGFloat = 10.0
        public static let attribution: String = "OSINT attribution"
    }
    
    // MARK: - Typography Scale (HUD)
    
    public enum Typography {
        /// HUD small — info tiles, layer toggles.
        public static let hudSmall: CGFloat = 11.0
        /// HUD medium — labels, primary labels.
        public static let hudMedium: CGFloat = 13.0
        /// HUD large — headings, navigation band.
        public static let hudLarge: CGFloat = 17.0
        /// HUD xlarge — ETA, distance, critical readouts.
        public static let hudXlarge: CGFloat = 22.0
    }
    
    // MARK: - Iconography Set (ATALK-derived, original/relicensed)
    
    public enum IconSet {
        /// Fire — FIRMS active fire detection.
        public static let fire: String = "flame" // SF Symbol (original, no license issue)
        
        /// Emergency — EMS/preferred routing (responder).
        public static let emergency: String = "heart.fill" // SF Symbol
        
        /// Traffic — congestion, closures, incidents.
        public static let traffic: String = "car.fill" // SF Symbol
        
        /// Weather — precipitation, storms, alerts.
        public static let weather: String = "cloud.fill" // SF Symbol
        
        /// Seismic — earthquake markers.
        public static let seismic: String = "mountain.fill" // SF Symbol
        
        /// Route — active route track.
        public static let route: String = "map.fill" // SF Symbol
        
        /// Waypoint — user-placed mark.
        public static let waypoint: String = "pin.circle.fill" // SF Symbol
        
        /// self — current position + heading cone.
        public static let selfPosition: String = "person.fill" // SF Symbol
        
        /// accessibility — ADA, curb cuts, elevators.
        public static let accessibility: String = "person.wave.2" // SF Symbol
        
        /// parking — parking zones, lots.
        public static let parking: String = "p.circle.fill" // SF Symbol
        
        /// recreation — parks, trails, campgrounds.
        public static let recreation: String = "tent.fill" // SF Symbol
        
        /// attribution — layer attribution footer.
        public static let attribution: String = "info.circle" // SF Symbol
    }
    
    // MARK: - Layer Stack (ordered, z-indexed)
    
    public enum LayerStack {
        /// Base tiles — Mapbox/OSM base map.
        public static let baseMap: Int = 0
        
        /// Protected lands / recreation polygons — low opacity overlay.
        public static let protectedLands: Int = 1
        
        /// Traffic + closures (TxDOT feed).
        public static let traffic: Int = 2
        
        /// Weather alerts (NOAA).
        public static let weather: Int = 3
        
        /// Active fires (FIRMS).
        public static let fires: Int = 4
        
        /// Seismic markers (USGS).
        public static let seismic: Int = 5
        
        /// Route track(s).
        public static let routes: Int = 6
        
        /// Waypoints / marks.
        public static let waypoints: Int = 7
        
        /// Self-position + heading cone.
        public static let selfPos: Int = 8
        
        /// HUD overlay — CarPlay / mobile HUD (appears above map).
        public static let hudOverlay: Int = 100
    }
    
    // MARK: - Tier Gating Matrix
    
    /// Returns which layers a principal should see.
    public static func visibleLayers(for principal: Principal) -> [(key: String, order: Int)] {
        var layers: [(String, Int)] = [
            (key: "baseMap", LayerStack.baseMap),
            (key: "routes", LayerStack.routes),
            (key: "selfPos", LayerStack.selfPos)
        ]
        
        switch principal {
        case .operatorTier:
            layers.append(contentsOf: [
                (key: "protectedLands", LayerStack.protectedLands),
                (key: "traffic", LayerStack.traffic),
                (key: "weather", LayerStack.weather),
                (key: "fires", LayerStack.fires),
                (key: "seismic", LayerStack.seismic),
                (key: "waypoints", LayerStack.waypoints)
            ])
            
        case .companion:
            layers.append(contentsOf: [
                (key: "protectedLands", LayerStack.protectedLands),
                (key: "traffic", LayerStack.traffic),
                (key: "waypoints", LayerStack.waypoints),
                (key: "accessibility", LayerStack.routes + 1) // placed above routes for companion
            ])
            
        case .guestTier:
            // guest sees only base, routes, selfPos (already added above)
            break
            
        case .responder(let role):
            // Responder sees full overlay set with EMS glyph overlays
            layers.append(contentsOf: [
                (key: "protectedLands", LayerStack.protectedLands),
                (key: "traffic", LayerStack.traffic),
                (key: "weather", LayerStack.weather),
                (key: "fires", LayerStack.fires),
                (key: "seismic", LayerStack.seismic),
                (key: "waypoints", LayerStack.waypoints)
            ])
            // EMS-preferred route paths for responder role
            if role.certLevel >= 2 {
                layers.append((key: "emergency", LayerStack.routes + 2))
            }
        }
        
        return layers
    }
    
    // MARK: - Attribution Dictionary
    
    public static func layerAttributions() -> [String: String] {
        [
            "baseMap": "© Mapbox © OpenStreetMap",
            "protectedLands": "USFS / BLM / NPS / TPWD via Recreation.gov & Open Data",
            "traffic": "© OpenStreetMap contributors, TxDOT DriveTexas data",
            "weather": "Weather: NOAA/NWS",
            "fires": "Fire detections: NASA FIRMS (MODIS/VIIRS)",
            "seismic": "Seismic: USGS",
            "routes": "Calculated path (GLM engine)",
            "waypoints": "User-placed mark",
            "selfPos": "Device GPS + heading",
            "accessibility": "ADA features via TPWD / NPS / BLM open data",
            "emergency": "EMS-preferred routing (Responder OS)"
        ]
    }
}

// MARK: - Convenience Extensions

extension Color {
    /// Initialize Color from hex string (matches JarvisMobileCockpitView pattern).
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
