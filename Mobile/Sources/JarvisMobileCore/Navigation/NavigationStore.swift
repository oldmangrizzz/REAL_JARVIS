We need to view repository.We cannot directly list files, but we can try to open other files.Let's open NavigationRoute model.We cannot run search, but we can try to open typical path.Probably not possible. But we can guess.

NavigationStore.swift currently empty? Let's open.Probably there is a model in JarvisMobileCore/Navigation. Let's open other files.import Foundation
import SwiftUI
import CoreLocation

// MARK: - Navigation Payload Types

/// Represents a single navigation maneuver.
public struct Maneuver: Sendable, Identifiable {
    public let id = UUID()
    public let instruction: String
    public let coordinate: CLLocationCoordinate2D

    public init(instruction: String, coordinate: CLLocationCoordinate2D) {
        self.instruction = instruction
        self.coordinate = coordinate
    }
}

/// Represents a full navigation route consisting of a polyline and its associated maneuvers.
public struct NavigationRoute: Sendable, Identifiable {
    public let id = UUID()
    public let polyline: [CLLocationCoordinate2D]
    public let maneuvers: [Maneuver]

    public init(polyline: [CLLocationCoordinate2D], maneuvers: [Maneuver]) {
        self.polyline = polyline
        self.maneuvers = maneuvers
    }
}

// MARK: - Navigation Store

/// A singleton observable store that publishes the current navigation route to any interested UI
/// (iPhone UI, CarPlay scene, WebSocket broadcaster, etc.).
@MainActor
public final class NavigationStore: ObservableObject, Sendable {
    /// Shared singleton instance.
    public static let shared = NavigationStore()

    /// The currently active navigation route. `nil` when no route is active.
    @Published public private(set) var route: NavigationRoute?

    // Private initializer to enforce singleton usage.
    private init() {}

    /// Updates the store with a new navigation route.
    /// - Parameter route: The navigation route to publish.
    public func update(with route: NavigationRoute) {
        self.route = route
    }

    /// Clears the current navigation route.
    public func clear() {
        self.route = nil
    }
}