import Foundation

/// NAV-001 Phase A: Contract for map tile providers.
///
/// Qwen (UX-001) consumes this protocol to render tile layers. Shape is frozen
/// once this ships — do not add requirements without surfacing in Open Questions.
///
/// Tier gating: `styleURL(for:)` throws `.unauthorizedTier` when credentials
/// are missing for the given principal (e.g. Mapbox secret style for guest).
/// The orchestrator never calls this directly; it delegates to the current
/// healthy provider.
public protocol MapTileProvider: Sendable {
    /// Registry key matching an `OSINTSourceRegistry.canonical` entry.
    /// E.g. `"mapbox.tiles"` or `"osm.tiles"`.
    var identifier: String { get }

    /// Human-readable attribution string for map legal compliance.
    var attribution: String { get }

    /// Build a style/raster URL for the given principal.
    /// - Throws: `TileProviderError.unauthorizedTier` if the principal
    ///   lacks access to the tile source.
    func styleURL(for principal: Principal) throws -> URL

    /// Lightweight health check — does not mutate provider state.
    func healthProbe() async -> TileProviderHealth
}

/// Health status reported by a tile provider probe.
public enum TileProviderHealth: Sendable, Equatable {
    case healthy
    case degraded(reason: String)
    case unhealthy(reason: String)
}

/// Errors thrown by tile providers and the orchestrator.
public enum TileProviderError: Error, Sendable, Equatable {
    /// The provider's identifier does not match any registered host.
    case hostNotRegistered(String)
    /// The principal is not authorized for this provider's style.
    case unauthorizedTier(Principal)
    /// All configured providers are below health threshold.
    case allProvidersUnhealthy([String])
}

/// Protocol-injected transport for tile network I/O. Tests inject stubs;
/// production wraps `URLSession`.
public protocol TileTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> Data
}