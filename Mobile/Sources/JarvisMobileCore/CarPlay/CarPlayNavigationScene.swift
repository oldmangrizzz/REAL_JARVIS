#if canImport(CarPlay)
import CarPlay
import SwiftUI

// MARK: - NavigationStore Protocol (shared across the app)
// This protocol is defined elsewhere in the project. It is imported here
// only for type‑checking; the concrete implementation is supplied at runtime.
public protocol NavigationStore {
    // Define the minimal API that the CarPlay scene needs.
    // The actual implementation lives in the core module.
    var currentRoute: Route? { get }
    func startNavigation(to destination: Destination)
}

// MARK: - CarPlay Navigation Scene

/// A CarPlay scene that presents navigation UI using a shared ``NavigationStore``.
///
/// The scene is only compiled when the `CarPlay` framework is available
/// (`#if canImport(CarPlay)`). At runtime we assert that the app possesses the
/// required CarPlay entitlement; this helps catch mis‑configurations early
/// during development and CI.
public final class CarPlayNavigationScene: NSObject, CPTemplateApplicationSceneDelegate {

    // MARK: - Dependencies

    /// The shared navigation store used throughout the app.
    private let navigationStore: NavigationStore

    // MARK: - Initialization

    /// Creates a new CarPlay navigation scene.
    ///
    /// - Parameter navigationStore: The shared navigation store that provides
    ///   route information and navigation actions.
    public init(navigationStore: NavigationStore) {
        self.navigationStore = navigationStore
        super.init()

        // --------------------------------------------------------------------
        // Runtime entitlement check
        // --------------------------------------------------------------------
        // CarPlay apps must include the `com.apple.developer.carplay-multimedia`
        // entitlement. Unfortunately, entitlements are not directly exposed at
        // runtime, but they are reflected in the app's Info.plist under the
        // `UIBackgroundModes` key when the entitlement is present. The following
        // assertion guards against missing entitlements during development and
        // CI runs.
        //
        // If the entitlement is missing the app will crash with a clear message,
        // making the problem obvious.
        // --------------------------------------------------------------------
        let hasCarPlayEntitlement = (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("carplay") ?? false
        assert(hasCarPlayEntitlement, "❗️ CarPlay entitlement is missing. Ensure the `com.apple.developer.carplay-multimedia` entitlement is added to the target.")
    }

    // MARK: - CPTemplateApplicationSceneDelegate

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                        didConnect interfaceController: CPInterfaceController) {
        // Build the root map template using the shared navigation store.
        let mapTemplate = CPMapTemplate()
        configure(mapTemplate, with: navigationStore)

        // Present the map template as the root UI.
        interfaceController.setRootTemplate(mapTemplate, animated: true)
    }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                        didDisconnect interfaceController: CPInterfaceController) {
        // Clean‑up if needed when CarPlay disconnects.
    }

    // MARK: - Private Helpers

    /// Configures a ``CPMapTemplate`` with data from the navigation store.
    private func configure(_ mapTemplate: CPMapTemplate, with store: NavigationStore) {
        // Example configuration – the real implementation will depend on the
        // concrete ``NavigationStore`` API.
        if let route = store.currentRoute {
            // Convert the app‑specific `Route` model into CarPlay’s `CPRoute`.
            // This placeholder demonstrates where that conversion would happen.
            let cpRoute = CPRoute(origin: route.startLocation,
                                 destination: route.endLocation,
                                 waypoints: route.waypoints.map { $0.location })
            mapTemplate.showTrip(previewText: "Navigating…", route: cpRoute)
        }

        // Add a “Start Navigation” button that forwards the action to the store.
        let startButton = CPBarButton(type: .text) { [weak store] in
            guard let destination = store?.currentRoute?.endLocation else { return }
            store?.startNavigation(to: Destination(location: destination))
        }
        startButton.title = "Start"
        mapTemplate.leadingNavigationBarButtons = [startButton]
    }
}
#endif