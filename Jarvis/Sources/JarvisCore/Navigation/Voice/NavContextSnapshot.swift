import Foundation
import CoreLocation

/// NAV-001 §11.4: Summary of a single route step for NavContextSnapshot.
///
/// Provides distance, bearing, and instruction for the conversation engine
/// to answer grounded questions like "how far to next turn?"
///
/// CANON: downstream wiring in NAV-003.
public struct RouteStepSummary: Sendable, Equatable, Codable {
    /// Distance to this step in meters.
    public let distanceMeters: Double
    /// Bearing in degrees (0–360).
    public let bearing: Double
    /// Human-readable instruction, e.g. "Turn right onto Elm St".
    public let instruction: String

    public init(distanceMeters: Double, bearing: Double, instruction: String) {
        self.distanceMeters = distanceMeters
        self.bearing = bearing
        self.instruction = instruction
    }
}

/// NAV-001 §11.4: Read-only snapshot of current navigation state.
///
/// Lets `ConversationEngine` answer grounded questions like
/// "how far to next turn?" without direct access to routing internals.
///
/// Produced by `NavContextProvider`. Consumed by the conversation layer.
/// Pure read, no mutation, always safe to call. Stale snapshots are fine;
/// the caller checks `capturedAt`.
///
/// CANON: downstream wiring in NAV-003.
public struct NavContextSnapshot: Sendable, Equatable {
    /// Active route ID, e.g. "route-abc123". Nil if not navigating.
    public let activeRouteID: String?
    /// Current route step (distance, bearing, instruction).
    public let currentStep: RouteStepSummary?
    /// Next route step.
    public let nextStep: RouteStepSummary?
    /// Estimated seconds to destination. Nil if not navigating.
    public let etaSecondsRemaining: Double?
    /// Remaining distance in meters. Nil if not navigating.
    public let distanceMetersRemaining: Double?
    /// Active hazards already filtered to principal tier.
    public let currentHazards: [HazardOverlayFeature]
    /// Timestamp of this snapshot.
    public let capturedAt: Date

    public init(
        activeRouteID: String? = nil,
        currentStep: RouteStepSummary? = nil,
        nextStep: RouteStepSummary? = nil,
        etaSecondsRemaining: Double? = nil,
        distanceMetersRemaining: Double? = nil,
        currentHazards: [HazardOverlayFeature] = [],
        capturedAt: Date = Date()
    ) {
        self.activeRouteID = activeRouteID
        self.currentStep = currentStep
        self.nextStep = nextStep
        self.etaSecondsRemaining = etaSecondsRemaining
        self.distanceMetersRemaining = distanceMetersRemaining
        self.currentHazards = currentHazards
        self.capturedAt = capturedAt
    }
}

/// Provider protocol for nav context. The routing engine publishes;
/// the conversation layer subscribes.
///
/// CANON: downstream wiring in NAV-003.
public protocol NavContextProvider: Sendable {
    /// Current navigation context snapshot.
    func snapshot() -> NavContextSnapshot
}