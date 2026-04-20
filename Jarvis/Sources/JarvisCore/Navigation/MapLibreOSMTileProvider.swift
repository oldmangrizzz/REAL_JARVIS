import Foundation

/// NAV-001 Phase A: OpenStreetMap / MapLibre-compatible tile provider.
///
/// Fallback when Mapbox is degraded. Uses the `osm.tiles` registry entry
/// (host: `tile.openstreetmap.org`). No credentials required; any tier
/// can use this provider. User-Agent must identify Real Jarvis per OSM
/// Tile Usage Policy.
public struct MapLibreOSMTileProvider: MapTileProvider, Sendable {

    public let identifier: String = "osm.tiles"

    public let attribution: String

    private let guard_: OSINTFetchGuard
    private let transport: any TileTransport

    /// Default User-Agent identifying Real Jarvis per OSM Tile Usage Policy.
    public static let defaultUserAgent = "RealJarvis/1.0 (https://realjarvis.ai; contact@realjarvis.ai)"

    public init(
        registry: OSINTSourceRegistry = .canonical,
        transport: any TileTransport = URLSessionTileTransport()
    ) {
        self.guard_ = OSINTFetchGuard(registry: registry)
        self.transport = transport
        self.attribution = "© OpenStreetMap contributors"
    }

    public func styleURL(for principal: Principal) throws -> URL {
        // OSM raster tile URL template. No auth needed.
        let urlString = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        guard let url = URL(string: urlString) else {
            throw TileProviderError.hostNotRegistered(identifier)
        }
        let result = guard_.authorize(url: url, principal: principal)
        switch result {
        case .success:
            return url
        case .failure(let denial):
            switch denial {
            case .unlistedHost(let host):
                throw TileProviderError.hostNotRegistered(host)
            case .operatorOnly(let key):
                throw TileProviderError.hostNotRegistered(key)
            case .invalidURL:
                throw TileProviderError.hostNotRegistered("invalid")
            }
        }
    }

    public func healthProbe() async -> TileProviderHealth {
        guard let url = URL(string: "https://tile.openstreetmap.org/0/0/0.png") else {
            return .unhealthy(reason: "Invalid OSM probe URL")
        }
        var request = URLRequest(url: url)
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5
        do {
            let _ = try await transport.fetch(request)
            return .healthy
        } catch {
            return .unhealthy(reason: "OSM probe failed: \(error.localizedDescription)")
        }
    }
}