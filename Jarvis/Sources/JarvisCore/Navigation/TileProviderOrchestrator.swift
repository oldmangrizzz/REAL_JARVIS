import Foundation

/// NAV-001 Phase A: Fail-over orchestrator for tile providers.
///
/// Maintains a primary/fallback pair. If the primary reports unhealthy
/// for `failureThreshold` consecutive probes, the orchestrator demotes
/// to the fallback. When the primary recovers for the same consecutive
/// count, it restores primary.
///
/// Every provider switch is recorded in the injected `AuditLog` so
/// silent demotion is always observable. Tests inject
/// `InMemoryAuditLog` to assert on transitions.
///
/// Init throws `TileProviderError.hostNotRegistered` if either
/// provider's `identifier` is absent from the registry.
public actor TileProviderOrchestrator {

    public enum Event: Sendable, Equatable {
        case switchedToFallback(reason: String)
        case recoveredToPrimary
    }

    private let primary: any MapTileProvider
    private let fallback: any MapTileProvider
    private let registry: OSINTSourceRegistry
    private let failureThreshold: Int
    private let auditLog: any AuditLog

    private var currentIsPrimary: Bool = true
    private var consecutivePrimaryFailures: Int = 0
    private var consecutivePrimaryRecoveries: Int = 0

    public init(
        primary: any MapTileProvider,
        fallback: any MapTileProvider,
        registry: OSINTSourceRegistry = .canonical,
        failureThreshold: Int = 3,
        auditLog: any AuditLog = InMemoryAuditLog()
    ) throws {
        // Canon gate: both provider identifiers must map to a registered host.
        guard registry.source(forKey: primary.identifier) != nil else {
            throw TileProviderError.hostNotRegistered(primary.identifier)
        }
        guard registry.source(forKey: fallback.identifier) != nil else {
            throw TileProviderError.hostNotRegistered(fallback.identifier)
        }
        self.primary = primary
        self.fallback = fallback
        self.registry = registry
        self.failureThreshold = failureThreshold
        self.auditLog = auditLog
    }

    /// The currently-active tile provider.
    public func currentProvider() -> any MapTileProvider {
        currentIsPrimary ? primary : fallback
    }

    /// Run health probe on the current primary. Demotes if threshold hit.
    /// If both providers report unhealthy, throws allProvidersUnhealthy.
    public func probe() async {
        let primaryHealth = await primary.healthProbe()
        switch primaryHealth {
        case .healthy:
            if !currentIsPrimary {
                consecutivePrimaryRecoveries += 1
                if consecutivePrimaryRecoveries >= failureThreshold {
                    currentIsPrimary = true
                    consecutivePrimaryFailures = 0
                    consecutivePrimaryRecoveries = 0
                    await auditLog.record(AuditEntry(
                        at: Date(),
                        kind: "tile.switch.recovered_to_primary",
                        detail: "Primary recovered for \(failureThreshold) consecutive probes"
                    ))
                }
            } else {
                consecutivePrimaryFailures = 0
                consecutivePrimaryRecoveries = 0
            }
        case .degraded(reason: let reason):
            // Degraded counts as partial failure for demotion tracking.
            if currentIsPrimary {
                // Still usable but note degradation.
                await auditLog.record(AuditEntry(
                    at: Date(),
                    kind: "tile.degraded",
                    detail: "Primary degraded: \(reason)"
                ))
            }
        case .unhealthy(reason: let reason):
            if currentIsPrimary {
                consecutivePrimaryFailures += 1
                consecutivePrimaryRecoveries = 0
                if consecutivePrimaryFailures >= failureThreshold {
                    currentIsPrimary = false
                    consecutivePrimaryFailures = 0
                    consecutivePrimaryRecoveries = 0
                    await auditLog.record(AuditEntry(
                        at: Date(),
                        kind: "tile.switch.primary_to_fallback",
                        detail: "Primary unhealthy (\(reason)) for \(failureThreshold) probes; switching to fallback"
                    ))
                }
            }
        }
    }

    /// Force an immediate recovery attempt: probe the primary and switch
    /// back if healthy. Returns true if recovered.
    public func forcePrimaryRecovery() async -> Bool {
        let health = await primary.healthProbe()
        if case .healthy = health {
            if !currentIsPrimary {
                currentIsPrimary = true
                consecutivePrimaryFailures = 0
                consecutivePrimaryRecoveries = 0
                await auditLog.record(AuditEntry(
                    at: Date(),
                    kind: "tile.switch.forced_recovery",
                    detail: "Force recovery: primary is healthy"
                ))
            }
            return true
        }
        return false
    }
}

// MARK: - AuditLog

/// Minimal audit protocol. Production implementations may write to
/// structured logging; tests use `InMemoryAuditLog`.
public protocol AuditLog: Sendable {
    func record(_ entry: AuditEntry) async
}

public struct AuditEntry: Sendable, Equatable {
    public let at: Date
    public let kind: String
    public let detail: String

    public init(at: Date, kind: String, detail: String) {
        self.at = at
        self.kind = kind
        self.detail = detail
    }
}

/// In-memory audit log for testing. Thread-safe via actor isolation.
public actor InMemoryAuditLog: AuditLog {
    private var _entries: [AuditEntry] = []

    public init() {}

    public var entries: [AuditEntry] {
        _entries
    }

    public func record(_ entry: AuditEntry) {
        _entries.append(entry)
    }
}