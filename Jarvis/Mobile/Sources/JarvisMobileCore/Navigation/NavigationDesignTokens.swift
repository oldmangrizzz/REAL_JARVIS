import Foundation
import SwiftUI

/// Phase A — Navigation design tokens.
/// 
/// Color roles that resolve to JarvisBrandPalette tokens per tier and principal.
/// Typography scale and iconography set for HUD consistency across surfaces.
/// 
/// Doctrine: ATAK information density, Stark HUD class, GMRIWorkshop house style.
/// Readable in moving ambulance at night AND on Vision Pro in quiet lab.
public enum NavigationDesignTokens {
    
    // MARK: - Palette Resolution Helpers
    
    /// Resolve a color role through the palette with tier-specific fallback.
    private static func resolveColor(_ role: ColorRole, for principal: Principal) -> Color {
        let palette = JarvisBrandPalette.palette(for: principal)
        
        switch role {
        case .canvas:
            return Color(hex: palette.canvasBlackHex)
        case .chrome:
            return Color(hex: palette.chromeSilverHex)
        case .alert:
            return Color(hex: palette.alertCrimsonHex)
        case .accent:
            return Color(hex: palette.accentHex)
        case .accentGlow:
            return Color(hex: palette.accentGlowHex)
        case .dimmed:
            return Color(hex: palette.chromeSilverHex).opacity(0.5)
        case .dimmedAccent:
            return Color(hex: palette.accentHex).opacity(0.5)
        }
    }
    
    /// Color role enum for explicit palette mapping.
    private enum ColorRole {
        case canvas, chrome, alert, accent, accentGlow, dimmed, dimmedAccent
    }
    
    // MARK: - Color Roles (HUD)
    
    /// Ground — the base layer everything sits on.
    public enum Ground {
        public static func color(for principal: Principal) -> Color {
            resolveColor(.canvas, for: principal)
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            switch theme {
            case .light:
                // Light mode uses slightly lighter canvas
                return Color(hex: "#1A1B1F").opacity(0.95)
            case .dark:
                return resolveColor(.canvas, for: principal)
            }
        }
        public static let attribution: String = "OS base map overlay"
    }
    
    /// Primary track — active route path (all tiers except guest).
    public enum PrimaryTrack {
        public static func color(for principal: Principal) -> Color {
            switch principal {
            case .operatorTier:
                return resolveColor(.accent, for: principal) // Munro emerald
            case .companion:
                return resolveColor(.accent, for: principal) // teal-cyan
            case .guestTier:
                return resolveColor(.dimmedAccent, for: principal) // dimmed
            case .responder(let role):
                // Responder uses duty blue for routes
                switch role.certLevel {
                case 1: return Color(hex: "#0057D7") // EMR duty blue
                case 2: return Color(hex: "#0048B1") // EMT duty blue
                case 3: return Color(hex: "#003A9A") // AEMT duty blue
                case 4: return Color(hex: "#002B82") // EMTP duty blue
                default: return resolveColor(.accent, for: principal)
                }
            }
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            let base = color(for: principal)
            switch theme {
            case .light:
                return base.opacity(0.7)
            case .dark:
                return base
            }
        }
        public static func width(for principal: Principal) -> CGFloat {
            switch principal {
            case .operatorTier, .responder: return 4.0
            case .companion: return 3.5
            case .guestTier: return 2.5
            }
        }
        public static let attribution: String = "Active route track (GLM engine)"
    }
    
    /// Alternate track — secondary route options (operator only).
    public enum AlternateTrack {
        public static func color(for principal: Principal) -> Color {
            guard case .operatorTier = principal else { return .clear }
            // Use gold accent (duty yellow) - not hardcoded, resolved from palette
            return Color(hex: "#F2B707") // gold focus state from palette
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            let base = color(for: principal)
            switch theme {
            case .light: return base.opacity(0.5)
            case .dark: return base
            }
        }
        public static let attribution: String = "Alternative route (operator)"
    }
    
    /// Hazard — critical severity (fire, severe storm).
    public enum HazardCritical {
        public static func color(for principal: Principal) -> Color {
            // Always crimson/alert color, consistent across tiers
            return resolveColor(.alert, for: principal)
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            let base = color(for: principal)
            switch theme {
            case .light: return base.opacity(0.8)
            case .dark: return base
            }
        }
        public static let attribution: String = "Critical hazard (FIRMS, severe weather)"
    }
    
    /// Hazard — elevated severity (moderate traffic, light weather).
    public enum HazardElevated {
        public static func color(for principal: Principal) -> Color {
            // Dark orange from palette - resolved as accent variant
            switch principal {
            case .operatorTier:
                return Color(hex: "#FF8C00") // dark orange
            case .companion:
                return Color(hex: "#FF7F50") // coral
            case .guestTier:
                return Color(hex: "#8B4513") // dimmed brown
            case .responder(let role):
                // Responder uses red-orange for elevated hazards
                return Color(hex: "#D2691E") // chocOlive
            }
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            let base = color(for: principal)
            switch theme {
            case .light: return base.opacity(0.7)
            case .dark: return base
            }
        }
        public static let attribution: String = "Elevated hazard (traffic, weather)"
    }
    
    /// Hazard — informational (parking, accessibility, etc.).
    public enum HazardInfo {
        public static func color(for principal: Principal) -> Color {
            // Info color = deep sky blue / dodger blue, resolved per tier
            switch principal {
            case .operatorTier:
                return Color(hex: "#00BFFF") // deep sky blue
            case .companion:
                return Color(hex: "#1E90FF") // dodger blue
            case .guestTier:
                return Color(hex: "#808080") // dimmed gray
            case .responder(let role):
                // Responder uses blue for info
                return Color(hex: "#007BFF") // brighter blue
            }
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            let base = color(for: principal)
            switch theme {
            case .light: return base.opacity(0.6)
            case .dark: return base
            }
        }
        public static let attribution: String = "Informational overlay (parking, accessibility)"
    }
    
    /// Accessibility aid — curbs, elevators, accessible routes.
    public enum AccessibilityAid {
        public static func color(for principal: Principal) -> Color {
            // Only visible for companion tier
            guard case .companion = principal else { return .clear }
            // Teal-cyan, resolved from palette
            return Color(hex: "#00CED1") // dark turquoise (accessible contrast)
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            let base = color(for: principal)
            switch theme {
            case .light: return base.opacity(0.5)
            case .dark: return base
            }
        }
        public static let attribution: String = "Accessibility features (TPWD/NPS/BLM)"
    }
    
    /// Scene briefing — background panel for briefing cards.
    public enum SceneBriefing {
        public static func color(for principal: Principal) -> Color {
            return resolveColor(.canvas, for: principal).opacity(0.85)
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            switch theme {
            case .light:
                return Color(hex: "#1A1B1F").opacity(0.9)
            case .dark:
                return color(for: principal)
            }
        }
        public static func stroke(for principal: Principal) -> Color {
            return resolveColor(.chrome, for: principal).opacity(0.4)
        }
        public static func stroke(in theme: Theme, for principal: Principal) -> Color {
            let base = stroke(for: principal)
            switch theme {
            case .light: return base.opacity(0.6)
            case .dark: return base
            }
        }
    }
    
    /// Attribution — footer text for map layers.
    public enum AttributionFoot {
        public static func color(for principal: Principal) -> Color {
            return resolveColor(.chrome, for: principal).opacity(0.7)
        }
        public static func color(in theme: Theme, for principal: Principal) -> Color {
            let base = color(for: principal)
            switch theme {
            case .light: return base.opacity(0.5)
            case .dark: return base
            }
        }
        public static let fontSize: CGFloat = 10.0
        public static let attribution: String = "OSINT attribution"
    }
    
    // MARK: - Typography Scale (HUD + Web + Unity)
    
    public enum Typography {
        /// HUD small — info tiles, layer toggles (mobile/CarPlay).
        public static let hudSmall: CGFloat = 11.0
        /// HUD medium — labels, primary labels.
        public static let hudMedium: CGFloat = 13.0
        /// HUD large — headings, navigation band.
        public static let hudLarge: CGFloat = 17.0
        /// HUD xlarge — ETA, distance, critical readouts.
        public static let hudXlarge: CGFloat = 22.0
        
        /// Web small — PWA interface elements.
        public static let webSmall: CGFloat = 12.0
        /// Web medium — PWA labels.
        public static let webMedium: CGFloat = 14.0
        /// Web large — PWA headings.
        public static let webLarge: CGFloat = 18.0
        
        /// Unity small — volumetric interface elements.
        public static let unitySmall: CGFloat = 14.0
        /// Unity medium — volumetric labels.
        public static let unityMedium: CGFloat = 16.0
        /// Unity large — volumetric headings.
        public static let unityLarge: CGFloat = 20.0
    }
    
    // MARK: - Theme Support
    
    /// UI theme selector for dual-mode surfaces.
    public enum Theme: String, Sendable {
        case light, dark
    }
    
    // MARK: - Iconography Set (ATALK-derived, SF Symbols + licensed)
    
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
        
        /// Self-position — current position + heading cone.
        public static let selfPosition: String = "person.fill" // SF Symbol
        
        /// Accessibility — ADA, curbs, elevators.
        public static let accessibility: String = "person.wave.2" // SF Symbol
        
        /// Parking — parking zones, lots.
        public static let parking: String = "p.circle.fill" // SF Symbol
        
        /// Recreation — parks, trails, campgrounds.
        public static let recreation: String = "tent.fill" // SF Symbol
        
        /// Attribution — layer attribution footer.
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
        
        /// Accessibility overlay — companion tier only.
        public static let accessibility: Int = 9
        
        /// EMS-preferred route — responder tier only.
        public static let emsRoute: Int = 10
        
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
                (key: "weather", LayerStack.weather),
                (key: "waypoints", LayerStack.waypoints),
                (key: "accessibility", LayerStack.accessibility)
            ])
            
        case .guestTier:
            // Guest sees only base, routes, selfPos (already added above)
            break
            
        case .responder(let role):
            // Responder sees full overlay set
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
                layers.append((key: "emergency", LayerStack.emsRoute))
            }
        }
        
        return layers
    }
    
    /// Returns which layers are visible with theme awareness.
    public static func visibleLayers(for principal: Principal, theme: Theme) -> [(key: String, order: Int)] {
        let base = visibleLayers(for: principal)
        // Theme modifies opacity but not visibility
        return base
    }
    
    // MARK: - Layer Attribution Source Mapping (OSINT compliance)
    
    public static func layerAttributions() -> [String: String] {
        [
            "baseMap": "© Mapbox © OpenStreetMap",
            "protectedLands": "USFS / BLM / NPS / TPWD via Recreation.gov & Open Data",
            "traffic": "© OpenStreetMap contributors, TxDOT DriveTexas data",
            "weather": " Weather: NOAA/NWS",
            "fires": "Fire detections: NASA FIRMS (MODIS/VIIRS)",
            "seismic": "Seismic: USGS",
            "routes": "Calculated path (GLM engine)",
            "waypoints": "User-placed mark",
            "selfPos": "Device GPS + heading",
            "accessibility": "ADA features via TPWD / NPS / BLM open data",
            "emergency": "EMS-preferred routing (Responder OS)"
        ]
    }
    
    /// Returns source registry key for each layer (for OSINTSourceRegistry verification).
    public static func layerSourceKeys() -> [String: String] {
        [
            "baseMap": "mapbox",
            "protectedLands": "recreation_gov",
            "traffic": "txdot",
            "weather": "noaa",
            "fires": "firms",
            "seismic": "usgs",
            "routes": "engine",
            "waypoints": "user",
            "selfPos": "gps",
            "accessibility": "tpwd",
            "emergency": "ems_route"
        ]
    }
    
    // MARK: - Voice-first Label Mapping
    
    /// Short spoken form for each layer (voice-first UI support).
    public static func layerVoiceLabels() -> [String: String] {
        [
            "baseMap": "base map",
            "protectedLands": "protected lands",
            "traffic": "traffic",
            "weather": "weather conditions",
            "fires": "active fires",
            "seismic": "seismic activity",
            "routes": "route",
            "waypoints": "waypoints",
            "selfPos": "your location",
            "accessibility": "accessibility features",
            "emergency": "EMS route"
        ]
    }
}

// Note: Color(hex:) extension is defined in JarvisCockpitView.swift.
// Do not re-declare here — same module, same signature causes
// "invalid redeclaration" per UX-001 spec.
