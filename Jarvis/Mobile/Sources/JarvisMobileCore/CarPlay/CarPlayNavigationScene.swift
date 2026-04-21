#if canImport(CarPlay)
import SwiftUI
import CarPlay
import MapKit
import CoreLocation

// MARK: - CarPlay Navigation HUD Surface
//
// The original implementation of this file reached for several CarPlay
// symbols that **do not exist** in Apple's public CarPlay framework
// (`CPNavigationTemplate`, `CPApplication`, `CPManeuverView`,
// `CPRouteView`, `CPStatusView`). Those were aspirational stubs from an
// earlier design spike.
//
// Per MK2 ship-gate #1 we preserve the public data surface (HUD struct,
// turn icons, safety gate, tier gating, notification name) so call sites
// compile, and gate the template-wiring half of the file behind
// `#if false` with a TODO to revisit once the CarPlay scene is
// re-architected against real public APIs (`CPMapTemplate`,
// `CPManeuver`, `CPTrip`, `CPListTemplate`, etc.).

// MARK: - CarPlayNavigationHUD

/// HUD data struct for CarPlay template updates.
public struct CarPlayNavigationHUD: Equatable, Sendable {
    /// Subtitle text (e.g., "12 mi to destination")
    public let subtitle: String

    /// Distance remaining text (e.g., "1.2 mi")
    public let distanceRemainingText: String

    /// Estimated time of arrival text (e.g., "14 min")
    public let etaText: String

    /// Next turn description (e.g., "Turn left in 500 ft")
    public let nextTurnDescription: String

    /// Destination name
    public let destinationText: String

    /// Turn icon for next maneuver
    public let turnIcon: CarPlayTurnIcon?

    /// Heading for self-position
    public let heading: Double

    /// Is moving (for safety gate)
    public let isMoving: Bool

    public init(
        subtitle: String,
        distanceRemaining: CLLocationDistance,
        eta: TimeInterval,
        destination: String,
        nextTurnDescription: String,
        turnIcon: CarPlayTurnIcon?,
        heading: Double,
        isMoving: Bool = true
    ) {
        self.subtitle = Self.formatDistance(distanceRemaining) + " to " + destination
        self.distanceRemainingText = Self.formatDistance(distanceRemaining)
        self.etaText = Self.formatTime(eta)
        self.destinationText = destination
        self.nextTurnDescription = nextTurnDescription
        self.turnIcon = turnIcon
        self.heading = heading
        self.isMoving = isMoving
    }

    private static func formatDistance(_ meters: CLLocationDistance) -> String {
        let kilometers = meters / 1000
        if kilometers >= 1 {
            return String(format: "%.1f km", kilometers)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes < 60 else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%d:%02d hr", hours, remainingMinutes)
        }
        return String(format: "%d min", minutes)
    }
}

// MARK: - CarPlayTurnIcon

/// Turn icon for next maneuver.
public enum CarPlayTurnIcon: Equatable, Sendable {
    case left
    case right
    case slightLeft
    case slightRight
    case sharpLeft
    case sharpRight
    case uTurn
    case none

    /// SF Symbol name for the icon (platform-agnostic; callers can render
    /// with SwiftUI `Image(systemName:)` or `UIImage(systemName:)`).
    public var systemImageName: String {
        switch self {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .slightLeft: return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .sharpLeft: return "arrow.uturn.left"
        case .sharpRight: return "arrow.uturn.right"
        case .uTurn: return "arrow.uturn.down"
        case .none: return "arrow.up"
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let carPlayNavigationUpdate = Notification.Name("com.realjarvis.carPlayNavigationUpdate")
}

// MARK: - Safety Gate

/// Safety gate: no modals while moving. Voice is primary I/O while in motion; touch is confirmatory.
public func CarPlaySafetyGate(_ hud: CarPlayNavigationHUD) -> Bool {
    // If moving, show only minimal HUD (no modals, no dense info)
    if hud.isMoving {
        return true // Safe - show basic HUD
    } else {
        return true // Safe - stationary, can show more details
    }
}

// MARK: - Tier Gating

/// CarPlay HUD tier access matrix.
/// - Responder: yes (EMS operations)
/// - Operator: yes (full functionality)
/// - Companion: yes (personal driving)
/// - Guest: no (no CarPlay access)
public func CarPlayHUDAllowed(for principal: Principal) -> Bool {
    switch principal {
    case .operatorTier: return true
    case .companion: return true
    case .guestTier: return false
    case .responder: return true
    }
}

// MARK: - Aspirational CarPlay scene wiring (disabled)
//
// TODO(MK3): Re-implement the CarPlay scene using the real public CarPlay
// APIs (`CPTemplateApplicationSceneDelegate`, `CPMapTemplate`,
// `CPManeuver`, `CPTrip`, `CPNavigationSession`). The code below was
// written against nonexistent types and is kept here as a design
// reference only.
#if false

@main
class CarPlayNavigationExtensionDelegate: NSObject, CPApplicationDelegate {
    private var scene: CPNavigationTemplate?

    func application(_ application: CPApplication, didConnect interface: CPInterfaceController) {
        let template = CPNavigationTemplate()
        interface.setRootTemplate(template, animated: true)
        self.scene = template

        NotificationCenter.default.addObserver(
            forName: .carPlayNavigationUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.updateHUD(from: notification)
        }
    }

    func application(_ application: CPApplication, didDisconnect interface: CPInterfaceController) {
        self.scene = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func updateHUD(from notification: Notification) {
        guard let scene = self.scene else { return }
        if let hudData = notification.userInfo?["HUDData"] as? CarPlayNavigationHUD {
            updateMapTemplate(scene, with: hudData)
        }
    }

    private func updateMapTemplate(_ template: CPMapTemplate, with hud: CarPlayNavigationHUD) {
        template.subtitle = hud.subtitle
        if let maneuverView = template.maneuverView {
            maneuverView.primaryText = hud.distanceRemainingText
            maneuverView.secondaryText = hud.etaText
            maneuverView.tertiaryText = hud.nextTurnDescription
        }
        if let routeView = template.routeView {
            routeView.primaryText = hud.destinationText
            routeView.secondaryText = hud.distanceRemainingText
        }
    }
}

#endif

#endif // canImport(CarPlay)
