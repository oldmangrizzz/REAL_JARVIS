import SwiftUI
import MapKit

// MARK: - NavigationMapView (SwiftUI wrapper for MapKit + MapLibre)

/// Phase B — Navigation Map Surface.
/// 
/// `NavigationCockpitView` — SwiftUI host for map with layer stack.
/// Consumes `MapTileProvider` and `HazardOverlayFeature[]` from engine.
/// Tier-gates visibility of traffic, FIRMS, weather, quake, EMS-preferred routing.
public struct NavigationCockpitView: View {
    @EnvironmentObject private var store: JarvisMobileCockpitStore
    private let tileProvider: any MapTileProvider
    private let principal: Principal
    
    public init(principal: Principal, tileProvider: any MapTileProvider) {
        self.principal = principal
        self.tileProvider = tileProvider
    }
    
    public var body: some View {
        ZStack {
            MapView(principal: principal, tileProvider: tileProvider)
                .ignoresSafeArea()
            
            OverlayLayerStack(principal: principal)
                .environmentObject(store)
            
            AttributionFooter(principal: principal)
        }
    }
}

// MARK: - MapView (MapKit wrapper with tier-gated styling)

private struct MapView: UIViewRepresentable {
    let principal: Principal
    let tileProvider: any MapTileProvider
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .satellite
        mapView.showsUserLocation = true
        mapView.overrideUserInterfaceStyle = .dark // Force dark mode for HUD consistency
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update map layers based on principal tier
        applyLayerConfig(to: mapView, principal: principal)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(principal: principal)
    }
    
    private func applyLayerConfig(to mapView: MKMapView, principal: Principal) {
        // Base map - always visible
        mapView.showsTraffic = NavigationDesignTokens.visibleLayers(for: principal)
            .contains(where: { $0.key == "traffic" })
        
        // Remove existing overlays, add new ones
        mapView.removeOverlays(mapView.overlays)
        
        for layer in NavigationDesignTokens.visibleLayers(for: principal) {
            addLayer(for: layer.key, to: mapView)
        }
    }
    
    private func addLayer(for key: String, to mapView: MKMapView) {
        switch key {
        case "baseMap":
            mapView.mapType = .satellite
        case "routes":
            // TODO(MK3): Wire to JarvisMobileCockpitStore once active route state
            // is modeled on `JarvisSharedState`. Intentionally a no-op so the
            // navigation surface compiles while the engine catches up.
            break
        case "waypoints":
            // TODO(MK3): Same as `routes` — needs store-backed waypoint list.
            break
        case "selfPos":
            // User location handled by showsUserLocation = true
            break
        default:
            // Hazard overlays handled in OverlayLayerStack
            break
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let principal: Principal
        
        init(principal: Principal) {
            self.principal = principal
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(overlay: polyline)
                let color = NavigationDesignTokens.PrimaryTrack.color(for: principal)
                renderer.strokeColor = UIColor(color)
                renderer.lineWidth = NavigationDesignTokens.PrimaryTrack.width(for: principal)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - OverlayLayerStack (Layer composition)

private struct OverlayLayerStack: View {
    @EnvironmentObject private var store: JarvisMobileCockpitStore
    let principal: Principal
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ForEach(NavigationDesignTokens.visibleLayers(for: principal), id: \.key) { layer in
                        LayerControl(key: layer.key, order: layer.order, principal: principal)
                    }
                }
                .padding(12)
                .background(NavigationDesignTokens.SceneBriefing.color(for: principal))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NavigationDesignTokens.SceneBriefing.stroke(for: principal), lineWidth: 1)
                )
                Spacer()
            }
            .padding(.bottom, 32) // Space for attribution footer
        }
    }
}

private struct LayerControl: View {
    let key: String
    let order: Int
    let principal: Principal
    
    @State private var visible: Bool = true
    
    var body: some View {
        HStack {
            Toggle(isOn: $visible) {
                Image(systemName: layerIcon(for: key))
                    .foregroundStyle(layerColor(for: key))
                Text(layerLabel(for: key))
                    .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex))
            }
            .toggleStyle(SwitchToggleStyle(tint: layerColor(for: key)))
            Spacer()
            Text(layerAttribution(for: key))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.6))
        }
        .padding(4)
        .onChange(of: visible) { _, newValue in
            // Layer visibility toggle logic would integrate with engine
            // For now, just a UI toggle
        }
    }
    
    private func layerIcon(for key: String) -> String {
        switch key {
        case "baseMap": return "map.fill"
        case "protectedLands": return "mountain.fill"
        case "traffic": return "car.fill"
        case "weather": return "cloud.fill"
        case "fires": return "flame"
        case "seismic": return "mountain.fill"
        case "routes": return "map.fill"
        case "waypoints": return "pin.circle.fill"
        case "selfPos": return "person.fill"
        case "accessibility": return "person.wave.2"
        case "emergency": return "heart.fill"
        default: return "questionmark.circle"
        }
    }
    
    private func layerColor(for key: String) -> Color {
        switch key {
        case "traffic": return NavigationDesignTokens.HazardElevated.color(for: principal)
        case "weather": return NavigationDesignTokens.HazardElevated.color(for: principal)
        case "fires": return NavigationDesignTokens.HazardCritical.color(for: principal)
        case "seismic": return NavigationDesignTokens.HazardInfo.color(for: principal)
        case "accessibility": return NavigationDesignTokens.AccessibilityAid.color(for: principal)
        case "emergency": return NavigationDesignTokens.HazardInfo.color(for: principal)
        default: return Color(hex: JarvisGMRIPalette.silverHex)
        }
    }
    
    private func layerLabel(for key: String) -> String {
        switch key {
        case "baseMap": return "Base Map"
        case "protectedLands": return "Protected Lands"
        case "traffic": return "Traffic"
        case "weather": return "Weather"
        case "fires": return "Active Fires"
        case "seismic": return "Seismic"
        case "routes": return "Routes"
        case "waypoints": return "Waypoints"
        case "selfPos": return "Self"
        case "accessibility": return "Accessibility"
        case "emergency": return "EMS Route"
        default: return key.capitalized
        }
    }
    
    private func layerAttribution(for key: String) -> String {
        NavigationDesignTokens.layerAttributions()[key] ?? "Source missing"
    }
}

// MARK: - AttributionFooter (Mandatory layer attribution)

private struct AttributionFooter: View {
    let principal: Principal
    
    var body: some View {
        HStack {
            Text("OSINT Attribution:")
                .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .medium, design: .monospaced))
                .foregroundStyle(NavigationDesignTokens.AttributionFoot.color(for: principal))
            
            Spacer()
            
            Text(NavigationDesignTokens.AttributionFoot.attribution)
                .font(.system(size: NavigationDesignTokens.AttributionFoot.fontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(NavigationDesignTokens.AttributionFoot.color(for: principal))
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(6)
        .padding(.bottom, 8)
    }
}

// MARK: - MapTileProvider Protocol (Engine-consumed interface)

/// Protocol for map tile providers (GLM engine provides concrete implementations).
public protocol MapTileProvider: Sendable {
    var baseURL: URL { get }
    var styleURL: URL? { get }
    var apiToken: String? { get }
    var attribution: String { get }
    
    func tileURL(x: Int, y: Int, zoom: Int) -> URL?
}

// MARK: - Test Support

#if DEBUG

struct NavigationCockpitView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationCockpitView(principal: .operatorTier, tileProvider: MockTileProvider())
            .environmentObject(JarvisMobileCockpitStore(role: .phone))
    }
    
    struct MockTileProvider: MapTileProvider {
        var baseURL: URL { URL(string: "https://api.mapbox.com")! }
        var styleURL: URL? { URL(string: "mapbox://styles/mapbox/satellite-v9") }
        var apiToken: String? { "pk.test-preview-token" }
        var attribution: String { "© Mapbox © OpenStreetMap" }
        
        func tileURL(x: Int, y: Int, zoom: Int) -> URL? {
            URL(string: "https://api.mapbox.com/tiles/v1/mapbox.satellite/\(zoom)/\(x)/\(y)?access_token=\(apiToken ?? "")")
        }
    }
}

#endif
