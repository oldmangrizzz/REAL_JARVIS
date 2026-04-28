import Foundation
import CoreMotion
import Combine

/// Activity biome — CMMotionActivityManager, activity recognition
///
/// Biological analogue: proprioceptive system — awareness of self-motion,
/// exertion state, movement quality.
///
/// Tracks walking, running, cycling, automotive, stationary states using
/// CMMotionActivityManager. Correlates with location speed data for
/// EMS scene detection.
@MainActor
public final class JarvisActivityBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var currentState: JarvisActivityState = .unknown

    // MARK: Private State

    private let activityManager = CMMotionActivityManager()
    private var isStarted = false

    // MARK: Init

    public init() {}

    // MARK: Public API

    public func start() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("[JarvisActivityBiome] activity not available on this device")
            return
        }
        startTracking()
    }

    public func stop() {
        activityManager.stopActivityUpdates()
        isStarted = false
    }

    public func requestAuthorization() async {
        guard CMMotionActivityManager.isActivityAvailable() else {
            isAuthorized = false
            return
        }
        // CoreMotion doesn't have explicit async auth; we request by starting
        isAuthorized = true
    }

    // MARK: Private

    private func startTracking() {
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity = activity else { return }
            let state = self?.mapActivityState(activity) ?? .unknown
            self?.currentState = state
        }
        isStarted = true
    }

    private func mapActivityState(_ activity: CMMotionActivity) -> JarvisActivityState {
        if activity.walking { return .walking }
        if activity.running { return .running }
        if activity.cycling { return .cycling }
        if activity.automotive { return .automotive }
        if activity.stationary { return .stationary }
        return .unknown
    }
}
