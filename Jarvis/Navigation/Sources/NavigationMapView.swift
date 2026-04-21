import SwiftUI

// MARK: - Navigation Tier

/// Represents the feature tier for navigation experiences.
/// Higher tiers unlock additional map layers.
public enum NavigationTier: Int, Comparable {
    case basic = 0
    case advanced = 1
    case premium = 2

    public static func < (lhs: NavigationTier, rhs: NavigationTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Map Tile Provider Protocol

/// Minimal contract required from a GLM‑based tile provider.
/// The concrete implementation will be supplied by the GLM integration layer.
public protocol MapTileProvider {
    /// Returns a URL for the requested tile path.
    func url(for tilePath: String) -> URL

    /// Attribution text that must be displayed on the map surface.
    var attribution: String { get }
}

// MARK: - Map Layers

/// All map layers that the navigation surface may render.
public enum MapLayer: CaseIterable {
    case base
    case traffic
    case incidents
    case navigationGuidance
    case pointsOfInterest
}

// MARK: - Tier‑Based Visibility Rules

private struct LayerVisibility {
    /// Minimum tier required for a given layer to be visible.
    static let requiredTier: [MapLayer: NavigationTier] = [
        .base: .basic,
        .traffic: .advanced,
        .incidents: .advanced,
        .navigationGuidance: .premium,
        .pointsOfInterest: .premium
    ]
}

// MARK: - NavigationMapView

/// SwiftUI view that composes the navigation map surface.
///
/// The view:
///   • Accepts a `MapTileProvider` (injected, GLM‑dependent).
///   • Enumerates the required layer stack.
///   • Applies tier‑based visibility gating.
///   • Renders an attribution footer required by the tile provider.
///   • Exposes a public initializer for consumer use.
public struct NavigationMapView: View {
    // MARK: Stored Properties

    private let tileProvider: MapTileProvider
    private let tier: NavigationTier

    // MARK: Initializer

    /// Creates a navigation map view.
    ///
    /// - Parameters:
    ///   - tileProvider: An object conforming to `MapTileProvider` that supplies map tiles.
    ///   - tier: The navigation tier that determines which layers are displayed. Defaults to `.basic`.
    public init(tileProvider: MapTileProvider, tier: NavigationTier = .basic) {
        self.tileProvider = tileProvider
        self.tier = tier
    }

    // MARK: Body

    public var body: some View {
        ZStack {
            // Render each layer that meets the tier requirement.
            ForEach(MapLayer.allCases, id: \.self) { layer in
                if let required = LayerVisibility.requiredTier[layer],
                   tier >= required {
                    MapLayerView(layer: layer, tileProvider: tileProvider)
                }
            }
        }
        .overlay(attributionFooter, alignment: .bottom)
    }

    // MARK: Attribution Footer

    @ViewBuilder
    private var attributionFooter: some View {
        Text(tileProvider.attribution)
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.4))
            .cornerRadius(4)
            .padding(8)
    }
}

// MARK: - Placeholder Layer View

/// A placeholder implementation for a map layer.
///
/// In a full implementation this view would delegate to the GLM SDK to render
/// raster tiles. For Phase A we provide a lightweight visual placeholder that
/// satisfies compilation and UI‑preview requirements while deferring GLM‑specific
/// code to Phase B.
private struct MapLayerView: View {
    let layer: MapLayer
    let tileProvider: MapTileProvider

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(color(for: layer))
                .opacity(0.3)
                .overlay(
                    Text(layerDisplayName(layer))
                        .font(.caption)
                        .foregroundColor(.white)
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }

    // Simple colour mapping for visual distinction.
    private func color(for layer: MapLayer) -> Color {
        switch layer {
        case .base: return .blue
        case .traffic: return .red
        case .incidents: return .orange
        case .navigationGuidance: return .green
        case .pointsOfInterest: return .purple
        }
    }

    private func layerDisplayName(_ layer: MapLayer) -> String {
        switch layer {
        case .base: return "Base"
        case .traffic: return "Traffic"
        case .incidents: return "Incidents"
        case .navigationGuidance: return "Guidance"
        case .pointsOfInterest: return "POI"
        }
    }
}