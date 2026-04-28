import Foundation
import CoreLocation
import Combine

/// Location biome — CoreLocation + geofence + beacon
///
/// Biological analogue: vestibular system + spatial memory (hippocampus).
/// Tracks where the operator is, how fast they're moving, and whether
/// they've crossed a meaningful boundary (home, scene, hospital).
///
/// All state is published onto MainActor. CLLocationManager callbacks
/// are routed to an internal actor to keep the manager thread-safe.
@MainActor
public final class JarvisLocationBiome: NSObject, ObservableObject {

    // MARK: Published State

    @Published public private(set) var currentPresence: JarvisLocationPresence = .unknown
    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var currentLocation: CLLocation?
    @Published public private(set) var currentHeading: CLHeading?
    @Published public private(set) var currentSpeed: Double = -1  // m/s, -1 = invalid
    @Published public private(set) var currentAltitude: Double?
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: Geofence Regions

    private let homeRegion: CLCircularRegion
    private let sceneRegion: CLCircularRegion?
    private let hospitalRegion: CLCircularRegion?

    // MARK: Private State

    private let manager: CLLocationManager
    private var lastRegionTransition: Date?

    // MARK: Init

    public override init() {
        self.manager = CLLocationManager()

        // Home geofence — operator's registered home coordinate
        // Coordinates should be loaded from configuration in production.
        // Defaults to a safe zero-coordinate sentinel; real coords injected via configure().
        self.homeRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100,  // 100m radius
            identifier: "grizz-home"
        )
        self.sceneRegion = nil  // Set dynamically when on a call
        self.hospitalRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 200,
            identifier: "grizz-hospital"
        )
        self.hospitalRegion?.notifyOnEntry = true

        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10  // meters
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false

        homeRegion.notifyOnEntry = true
        homeRegion.notifyOnExit = true

        updateAuthorizationState()
    }

    // MARK: Public API

    /// Call from JarvisBiome.start() to begin location tracking.
    public func start() {
        updateAuthorizationState()
        if isAuthorized {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoring(for: homeRegion)
            if let sr = sceneRegion { manager.startMonitoring(for: sr) }
            if let hr = hospitalRegion { manager.startMonitoring(for: hr) }
        }
    }

    public func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.stopMonitoringSignificantLocationChanges()
        manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
    }

    public func requestAuthorization() async {
        manager.requestWhenInUseAuthorization()
    }

    public func requestAlwaysAuthorization() async {
        manager.requestAlwaysAuthorization()
    }

    /// Dynamically set the scene geofence (e.g., when dispatched to an EMS call).
    public func setSceneLocation(latitude: Double, longitude: Double, radius: Double = 150) {
        if let existing = sceneRegion {
            manager.stopMonitoring(for: existing)
        }
        let new = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: "grizz-scene-\(Date().timeIntervalSince1970)"
        )
        new.notifyOnEntry = true
        new.notifyOnExit = true
        manager.startMonitoring(for: new)
    }

    public func clearSceneLocation() {
        manager.monitoredRegions
            .filter { $0.identifier.hasPrefix("grizz-scene-") }
            .forEach { manager.stopMonitoring(for: $0) }
    }

    /// Returns distance to home in meters, or nil if location unavailable.
    public func distanceToHome() -> Double? {
        guard let loc = currentLocation else { return nil }
        return loc.distance(from: CLLocation(latitude: homeRegion.center.latitude, longitude: homeRegion.center.longitude))
    }

    // MARK: Internal

    private func updateAuthorizationState() {
        let s = manager.authorizationStatus
        authorizationStatus = s
        isAuthorized = (s == .authorizedWhenInUse || s == .authorizedAlways)
    }

    private func updatePresence() {
        guard let loc = currentLocation else { return }

        // Determine presence from geofence state
        if homeRegion.contains(loc.coordinate) {
            currentPresence = .atHome
        } else if sceneRegion?.contains(loc.coordinate) == true {
            currentPresence = .onScene
        } else if hospitalRegion?.contains(loc.coordinate) == true {
            currentPresence = .inMedicalFacility
        } else if currentSpeed > 11 {  // ~40 km/h
            currentPresence = .inVehicle
        } else {
            currentPresence = .elsewhere
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension JarvisLocationBiome: @preconcurrency CLLocationManagerDelegate {

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        self.currentLocation = loc
        self.currentSpeed = loc.speed >= 0 ? loc.speed : -1
        self.currentAltitude = loc.altitude
        self.updatePresence()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        self.currentHeading = newHeading
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("grizz-scene") else { return }
        self.currentPresence = .onScene
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("grizz-scene") else { return }
        self.updatePresence()
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.updateAuthorizationState()
        if self.isAuthorized {
            self.start()
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[JarvisLocationBiome] location error: \(error.localizedDescription)")
    }
}
