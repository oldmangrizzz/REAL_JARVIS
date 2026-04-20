import Foundation

/// NAV-001 Phase D: Error type for OSINT hazard adapters.
///
/// Fail-closed: malformed payloads and unauthorized hosts both throw
/// rather than silently returning empty results.
public enum OSINTAdapterError: Error, Sendable, Equatable {
    /// The URL host is not in `OSINTSourceRegistry.canonical`.
    case hostNotAuthorized(String)
    /// The payload could not be parsed into valid hazard features.
    case malformedPayload(String)
    /// The transport (network) request failed.
    case transportFailed(String)
}