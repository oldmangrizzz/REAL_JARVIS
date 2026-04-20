import Foundation

/// NAV-001 Phase A: Mapbox tile provider.
///
/// Primary tile source. Uses a public (`pk.*`) token for style URLs.
/// The registry key is `"mapbox.tiles"` with hosts `api.mapbox.com` and
/// `events.mapbox.com`. Every constructed URL is validated through
/// `OSINTFetchGuard.authorize(url:principal:)`.
///
/// The secret token is never used for tile URLs — it is gated separately
/// via `MapboxCredentials.secretToken(for:)`. Only the public token is
/// embedded in style URLs that any tier can render.
public struct MapboxTileProvider: MapTileProvider, Sendable {

    public let identifier: String = "mapbox.tiles"

    public let attribution: String

    private let credentials: MapboxCredentials
    private let styleID: String
    private let guard_: OSINTFetchGuard
    private let transport: any TileTransport

    public init(
        credentials: MapboxCredentials,
        styleID: String = "streets-v12",
        registry: OSINTSourceRegistry = .canonical,
        transport: any TileTransport = URLSessionTileTransport()
    ) {
        self.credentials = credentials
        self.styleID = styleID
        self.guard_ = OSINTFetchGuard(registry: registry)
        self.transport = transport
        self.attribution = "© Mapbox © OpenStreetMap"
    }

    public func styleURL(for principal: Principal) throws -> URL {
        guard let token = credentials.publicToken, !token.isEmpty else {
            throw TileProviderError.unauthorizedTier(principal)
        }
        let urlString = "https://api.mapbox.com/styles/v1/mapbox/\(styleID)/tiles/256/@2x?access_token=\(token)"
        guard let url = URL(string: urlString) else {
            throw TileProviderError.hostNotRegistered(identifier)
        }
        // Fail-closed: every URL must pass through OSINTFetchGuard.
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
        guard let token = credentials.publicToken, !token.isEmpty else {
            return .unhealthy(reason: "No public token configured")
        }
        guard let url = URL(string: "https://api.mapbox.com/styles/v1/mapbox/\(styleID)?access_token=\(token)") else {
            return .unhealthy(reason: "Invalid probe URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let _ = try await transport.fetch(request)
            return .healthy
        } catch {
            return .unhealthy(reason: "Probe failed: \(error.localizedDescription)")
        }
    }
}

/// Production `URLSession`-backed tile transport.
public struct URLSessionTileTransport: TileTransport, Sendable {
    public init() {}

    public func fetch(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}