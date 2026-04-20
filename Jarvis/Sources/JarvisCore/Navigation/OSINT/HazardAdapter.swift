import Foundation

/// NAV-001 Phase D: Protocol for OSINT hazard data adapters.
///
/// Each adapter wraps one OSINT source in the registry. The adapter
/// builds a URL from the registry entry, validates it through
/// `OSINTFetchGuard`, fetches via the injected `HazardTransport`,
/// and parses the response into `[HazardOverlayFeature]`.
///
/// Fail-closed: malformed payloads throw `.malformedPayload`;
/// unauthorized hosts throw `.hostNotAuthorized`.
public protocol HazardAdapter: Sendable {
    /// Registry key for the OSINT source this adapter wraps.
    var sourceKey: String { get }
    /// Fetch hazard features for the given principal.
    func fetch(principal: Principal) async throws -> [HazardOverlayFeature]
}

/// Protocol-injected transport for hazard network I/O.
/// Tests inject stubs; production wraps `URLSession`.
public protocol HazardTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> Data
}

/// Production `URLSession`-backed hazard transport.
public struct URLSessionHazardTransport: HazardTransport, Sendable {
    public init() {}
    public func fetch(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}