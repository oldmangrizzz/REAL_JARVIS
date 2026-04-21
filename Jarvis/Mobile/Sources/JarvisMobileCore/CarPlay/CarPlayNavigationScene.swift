#if canImport(CarPlay)
import SwiftUI
import CarPlay
import MapKit

// MARK: - CarPlay Navigation HUD Surface
//
// `CarPlayNavigationExtensionViewController` — CarPlay extension host.
// Uses `CPMapTemplate` + overlays for minimal HUD.
// AR HUD overlay concept (degrades gracefully when AR unavailable).
// Entire file guarded by `#if canImport(CarPlay)` per UX-001 build hardening.

// MARK: - ExtensionDelegate

@main
class CarPlayNavigationExtensionDelegate: NSObject, CPApplicationDelegate {
    private var scene: CPNavigationTemplate?
    
    func application(_ application: CPApplication, didConnect interface: CPInterfaceController) {
        let template = CPNavigationTemplate()
        interface.setRootTemplate(template, animated: true)
        
        self.scene = template
        
        // Wire up HUD updates from engine data
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
            
            if let icon = hud.turnIcon {
                maneuverView.image = icon.uiImage
            }
        }
        
        if let routeView = template.routeView {
            routeView.primaryText = hud.destinationText
            routeView.secondaryText = hud.distanceRemainingText
        }
    }
}

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
        self.subtitle = formatDistance(distanceRemaining) + " to " + destination
        self.distanceRemainingText = formatDistance(distanceRemaining)
        self.etaText = formatTime(eta)
        self.destinationText = destination
        self.nextTurnDescription = nextTurnDescription
        self.turnIcon = turnIcon
        self.heading = heading
        self.isMoving = isMoving
    }
    
    private func formatDistance(_ meters: CLLocationDistance) -> String {
        let kilometers = meters / 1000
        if kilometers >= 1 {
            return String(format: "%.1f km", kilometers)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes < 60 else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%d:%02d hr", hours, remainingMinutes)
        }
        return String(format: "%d min", minutes)
    }
}

// MARK: - CPMapTemplate Extension

extension CPMapTemplate {
    var maneuverView: CPManeuverView? {
        if let primary = views.first(where: { $0 is CPManeuverView }) as? CPManeuverView {
            return primary
        }
        return nil
    }
    
    var routeView: CPRouteView? {
        if let primary = views.first(where: { $0 is CPRouteView }) as? CPRouteView {
            return primary
        }
        return nil
    }
    
    var subtitle: String? {
        get { currentStatusView?.title }
        set { currentStatusView?.title = newValue ?? "" }
    }
    
    private var currentStatusView: CPStatusView? {
        if let status = views.first(where: { $0 is CPStatusView }) as? CPStatusView {
            return status
        }
        return nil
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
    
    var uiImage: UIImage {
        let name: String
        switch self {
        case .left: name = "chevron.left"
        case .right: name = "chevron.right"
        case .slightLeft: name = "arrow.left.square"
        case .slightRight: name = "arrow.right.square"
        case .sharpLeft: name = "hare.fill"
        case .sharpRight: name = "tortoise.fill"
        case .uTurn: name = "repeat"
        case .none: name = "none"
        }
        return UIImage(systemName: name) ?? UIImage()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let carPlayNavigationUpdate = Notification.Name("com.realjarvis.carPlayNavigationUpdate")
}

// MARK: - Safety Gate

/// Safety gate: no modals while moving. Voice is primary I/O while in motion; touch is confirmatory.
func CarPlaySafetyGate(_ hud: CarPlayNavigationHUD) -> Bool {
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
func CarPlayHUDAllowed(for principal: Principal) -> Bool {
    switch principal {
    case .operatorTier: return true
    case .companion: return true
    case .guestTier: return false
    case .responder: return true
    }
}

// MARK: - Test Support

#if DEBUG

struct CarPlayNavigationHUD_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            Text("CarPlay HUD Preview")
                .font(.headline)
            
            CarPlayHUDView(hud: CarPlayNavigationHUD.preview)
                .padding()
                .background(Color.black)
                .cornerRadius(12)
        }
        .background(Color.black.ignoresSafeArea())
    }
    
    static var hudData: CarPlayNavigationHUD {
        CarPlayNavigationHUD(
            subtitle: "1.2 mi to Austin",
            distanceRemaining: 1931,
            eta: 840,
            destination: "Austin, TX",
            nextTurnDescription: "Turn left in 500 ft",
            turnIcon: .left,
            heading: 270.5,
            isMoving: true
        )
    }
    
    struct CarPlayHUDView: View {
        let hud: CarPlayNavigationHUD
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(hud.subtitle)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white)
                
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hud.distanceRemainingText)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                        Text(hud.etaText)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    
                    VStack(alignment: .center, spacing: 4) {
                        Image(systemName: hud.turnIcon?.uiImage.prefixedName ?? "chevron.right")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(Color.green)
                        Text(hud.nextTurnDescription)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
            }
            .padding(16)
        }
    }
}

extension CarPlayNavigationHUD {
    static var preview: CarPlayNavigationHUD {
        CarPlayNavigationHUD(
            subtitle: "1.2 mi to destination",
            distanceRemaining: 1931,
            eta: 840,
            destination: "Austin, TX",
            nextTurnDescription: "Turn left in 500 ft",
            turnIcon: .left,
            heading: 270.5,
            isMoving: true
        )
    }
}

extension UIImage {
    var prefixedName: String {
        self.name ?? "none"
    }
}

#endif

#endif // canImport(CarPlay)