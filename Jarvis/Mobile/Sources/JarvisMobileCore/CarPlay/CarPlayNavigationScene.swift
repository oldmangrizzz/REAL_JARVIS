#if canImport(CarPlay)
import SwiftUI
import CarPlay
import MapKit
import CoreLocation

// MARK: - CarPlay Navigation HUD Surface
//
// JARVIS CarPlay integration using real public CarPlay APIs:
// CPTemplateApplicationSceneDelegate, CPMapTemplate, CPManeuver, CPTrip,
// CPInterfaceController.
//
// Navigation HUD for EMS operations: shows route, next turn, ETA, and
// safety-gated content based on vehicle motion state. Tier-gated so only
// operator/companion/responder tiers get CarPlay access.

public let carPlaySceneIdentifier = "com.realjarvis.carplay"

// MARK: - CarPlayNavigationHUD

/// HUD data struct for CarPlay template updates.
public struct CarPlayNavigationHUD: Equatable, Sendable {
    public let subtitle: String
    public let distanceRemainingText: String
    public let etaText: String
    public let nextTurnDescription: String
    public let destinationText: String
    public let turnIcon: CarPlayTurnIcon?
    public let heading: Double
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

public enum CarPlayTurnIcon: Equatable, Sendable {
    case left, right, slightLeft, slightRight, sharpLeft, sharpRight, uTurn, none

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

public func CarPlaySafetyGate(_ hud: CarPlayNavigationHUD) -> Bool {
    // Moving vehicle: minimal HUD only, no modals, voice-primary
    hud.isMoving
}

// MARK: - Tier Gating

public func CarPlayHUDAllowed(for principal: Principal) -> Bool {
    switch principal {
    case .operatorTier: return true
    case .companion: return true
    case .guestTier: return false
    case .responder: return true
    }
}

// MARK: - CPTemplateApplicationSceneDelegate

/// Real CarPlay scene delegate using public CPTemplateApplicationSceneDelegate API.
///
/// Attach via Info.plist:
///   NSApplicationSceneManifest → CPTemplateApplicationSceneSessionRoleApplication
///   CPTemplateApplicationSceneSessionRoleApplication → CPTemplateApplicationSceneConfiguration
///   CPTemplateApplicationSceneConfiguration → CPCarPlayApplicationSceneSessionRole
///     → CBPMessageReceiverScene / CPRemoteApplicationSceneSessionRole
@MainActor
class JarvisCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: Properties

    var interfaceController: CPInterfaceController?
    private var mapTemplate: CPMapTemplate?
    private var currentHUD: CarPlayNavigationHUD?
    private var observer: NSObjectProtocol?

    // MARK: CPTemplateApplicationSceneDelegate

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        // Create the root map template
        let map = CPMapTemplate()
        map.mapDelegate = self

        // Navigation bar buttons
        let incidentButton = CPBarButton(image: UIImage(systemName: "exclamationmark.triangle.fill")!) { [weak self] _ in
            self?.showEmergencyInfo()
        }
        map.trailingNavigationBarButtons = [incidentButton]

        // Maneuver buttons (turn-by-turn)
        map.mapButtons = []

        interfaceController.setRootTemplate(map, animated: true)
        self.mapTemplate = map

        // Listen for HUD updates from JARVIS
        setupNotificationObserver()

        // Send initial dashboard state
        postReadyState()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didDisconnect interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        self.mapTemplate = nil
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
    }

    // MARK: Notification Observer

    private func setupNotificationObserver() {
        observer = NotificationCenter.default.addObserver(
            forName: .carPlayNavigationUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let hud = notification.userInfo?["hud"] as? CarPlayNavigationHUD else { return }
            Task { @MainActor [weak self] in
                self?.updateHUD(hud)
            }
        }
    }

    // MARK: HUD Updates

    func updateHUD(_ hud: CarPlayNavigationHUD) {
        guard let map = mapTemplate, CarPlaySafetyGate(hud) else { return }
        currentHUD = hud

        // Build maneuver with turn instruction
        var maneuverItems: [CPManeuver] = []

        if let icon = hud.turnIcon {
            let maneuver = CPManeuver()
            maneuver.symbolImage = UIImage(systemName: icon.systemImageName)
            maneuver.instructionVariants = [hud.nextTurnDescription]
            maneuver.initialTravelEstimates = CPTravelEstimates(
                distanceRemaining: Measurement(value: hud.distanceRemainingText.numericMeters, unit: UnitLength.meters),
                timeRemaining: hud.etaText.numericSeconds
            )
            maneuverItems.append(maneuver)
        }

        // Show full navigation list if not moving (stationary = more detail)
        if !hud.isMoving, !maneuverItems.isEmpty {
            let listTemplate = CPListTemplate(title: "Route", sections: [])
            interfaceController?.pushTemplate(listTemplate, animated: true)
        }

        // Refresh map buttons with current turn
        if let icon = hud.turnIcon {
            let turnButton = CPMapButton { [weak self] _ in
                self?.showManeuverDetail()
            }
            turnButton.image = UIImage(systemName: icon.systemImageName)
            map.mapButtons = [turnButton]
        }

        // Update user info panel
        updateUserInfoPanel(hud)
    }

    private func updateUserInfoPanel(_ hud: CarPlayNavigationHUD) {
        guard let map = mapTemplate else { return }

        map.userInfo = [
            "subtitle": hud.subtitle,
            "destination": hud.destinationText,
            "eta": hud.etaText,
            "heading": hud.heading
        ] as [String: Any]
    }

    // MARK: Actions

    private func showManeuverDetail() {
        guard let hud = currentHUD else { return }
        let alertTemplate = CPAlertTemplate(titleVariants: [hud.nextTurnDescription],
                                             actions: [])
        interfaceController?.pushTemplate(alertTemplate, animated: true)
    }

    private func showEmergencyInfo() {
        let alert = CPAlertTemplate(
            titleVariants: ["INCIDENT MODE"],
            actions: [
                CPAlertAction(title: "SCENE LOCATION", style: .default, handler: { [weak self] _ in
                    self?.showSceneLocation()
                }),
                CPAlertAction(title: "DISPATCH", style: .default, handler: { [weak self] _ in
                    self?.requestDispatch()
                }),
                CPAlertAction(title: "DISMISS", style: .cancel, handler: { _ in })
            ]
        )
        interfaceController?.pushTemplate(alert, animated: true)
    }

    private func showSceneLocation() {
        // Post location to JARVIS orchestrator
        NotificationCenter.default.post(name: .jarvisCarPlaySceneLocation, object: nil)
    }

    private func requestDispatch() {
        NotificationCenter.default.post(name: .jarvisCarPlayDispatchRequest, object: nil)
    }

    private func postReadyState() {
        NotificationCenter.default.post(name: .jarvisCarPlayConnected, object: nil)
    }
}

// MARK: - CPMapTemplateDelegate

extension JarvisCarPlaySceneDelegate: CPMapTemplateDelegate {
    func mapTemplate(_ mapTemplate: CPMapTemplate, didSelect maneuver: CPManeuver) {
        showManeuverDetail()
    }

    func mapTemplateDidChangeNavigationSettings(_ mapTemplate: CPMapTemplate) {
        // User changed navigation settings — propagate to JARVIS
        NotificationCenter.default.post(
            name: .jarvisCarPlayNavigationSettingsChanged,
            object: nil,
            userInfo: ["settings": mapTemplate.userInfo as Any]
        )
    }
}

// MARK: - Extensions

private extension String {
    var numericMeters: Double {
        let cleaned = self.replacingOccurrences(of: " km", with: "").replacingOccurrences(of: " m", with: "")
        return Double(cleaned) ?? 0
    }

    var numericSeconds: TimeInterval {
        let cleaned = self.replacingOccurrences(of: " min", with: "").replacingOccurrences(of: " hr", with: "")
        if self.contains("hr"), let hours = Double(cleaned.split(separator: ":").first ?? "0") {
            let minutes = Double(self.split(separator: ":").last?.replacingOccurrences(of: " min", with: "") ?? "0") ?? 0
            return (hours * 60 + minutes) * 60
        }
        return (Double(cleaned) ?? 0) * 60
    }
}

// MARK: - Additional Notifications

public extension Notification.Name {
    static let jarvisCarPlaySceneLocation = Notification.Name("com.realjarvis.carplay.sceneLocation")
    static let jarvisCarPlayDispatchRequest = Notification.Name("com.realjarvis.carplay.dispatchRequest")
    static let jarvisCarPlayConnected = Notification.Name("com.realjarvis.carplay.connected")
    static let jarvisCarPlayNavigationSettingsChanged = Notification.Name("com.realjarvis.carplay.settingsChanged")
}

#endif // canImport(CarPlay)
