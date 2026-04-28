import Foundation
import Combine

/// JarvisBiome — Biomimetic API Integration Hub
///
/// JARVIS is a 1:1 biomimetic system. Every biological system has a
/// "biome" — the integrated ecosystem of all sensory and actuating
/// interfaces through which a living system perceives and acts upon
/// its environment.
///
/// JarvisBiome is that layer. It does not implement business logic.
/// It translates Apple platform APIs into PresenceSignals and
/// ControlDirectives that the rest of JARVIS understands.
///
/// Biological analogy:
///   - Cortex = JARVIS core (reasoning, planning, memory)
///   - Biome   = Nervous system + endocrine system (I/O, signal modulation)
///   - Thalamus = OrchestratorRouting (routing, gating, amplification)
///
/// Every subsystem below is modality-specific:
///   - Somatic:  CoreLocation, CoreMotion, HealthKit, SensorKit
///   - Visceral: HomeKit, CoreBluetooth (accessories, proximity)
///   - Auditory: AVFoundation/Audio, Speech, SoundAnalysis
///   - Visual:   Vision, Photos, ARKit
///   - Cognitive:  AppIntents, Siri, Shortcuts
///   - Metabolic: WatchConnectivity, CloudKit sync, APNs
///
/// MARK: Thread Safety
/// All published properties are MainActor-isolated. Background APIs
/// use their own internal actors and publish onto the main thread.
@MainActor
public final class JarvisBiome: ObservableObject {

    // MARK: Singleton

    public static let shared = JarvisBiome()

    // MARK: Published Presence State

    @Published public private(set) var operatorLocation: JarvisLocationPresence = .unknown
    @Published public private(set) var operatorActivity: JarvisActivityState = .unknown
    @Published public private(set) var operatorVitalContext: JarvisVitalContext = .nominal
    @Published public private(set) var ambientEnvironment: JarvisAmbientState = .unknown
    @Published public private(set) var accessoryProximity: JarvisAccessoryProximity = .unknown
    @Published public private(set) var watchSessionActive: Bool = false
    @Published public private(set) var homeState: JarvisHomeState = .unknown
    @Published public private(set) var authorizationStatus: JarvisBiomeAuthorizations = .init()
    @Published public private(set) var allAuthorizationsSatisfied: Bool = false

    // MARK: Subsystem Managers

    public let location:    JarvisLocationBiome
    public let activity:    JarvisActivityBiome
    public let vitals:     JarvisVitalsBiome
    public let homeKit:    JarvisHomeKitBiome
    public let audio:      JarvisAudioBiome
    public let intents:    JarvisIntentsBiome
    public let cloudSync:  JarvisCloudSyncBiome
    public let watchBridge: JarvisWatchBridgeBiome
    public let wallet:     JarvisWalletBiome
    public let notifications: JarvisNotificationBiome

    // MARK: Internals

    private var cancellables = Set<AnyCancellable>()
    private var hasLoggedBiomeStart = false

    // MARK: Init

    private init() {
        self.location    = JarvisLocationBiome()
        self.activity   = JarvisActivityBiome()
        self.vitals     = JarvisVitalsBiome()
        self.homeKit    = JarvisHomeKitBiome()
        self.audio      = JarvisAudioBiome()
        self.intents    = JarvisIntentsBiome()
        self.cloudSync  = JarvisCloudSyncBiome()
        self.watchBridge = JarvisWatchBridgeBiome()
        self.wallet     = JarvisWalletBiome()
        self.notifications = JarvisNotificationBiome()
        subscribeToAllSignals()
    }

    // MARK: Lifecycle

    /// Boot the entire biome. Call once from the app delegate / scene delegate.
    public func start() async {
        guard !hasLoggedBiomeStart else { return }
        hasLoggedBiomeStart = true

        await authorizeAll()
        location.start()
        activity.start()
        vitals.start()
        homeKit.start()
        audio.start()
        intents.start()
        cloudSync.start()
        watchBridge.start()
        wallet.start()
        notifications.start()

        await computeAuthorizationsSatisfied()
    }

    /// Decommission the biome. Call when the JARVIS session ends.
    public func stop() {
        location.stop()
        activity.stop()
        vitals.stop()
        homeKit.stop()
        audio.stop()
        intents.stop()
        cloudSync.stop()
        watchBridge.stop()
        wallet.stop()
        notifications.stop()
    }

    // MARK: Authorization

    private func authorizeAll() async {
        await location.requestAuthorization()
        await activity.requestAuthorization()
        await vitals.requestAuthorization()
        await homeKit.requestAuthorization()
        await audio.requestAuthorization()
        await intents.registerShortcuts()
        await notifications.requestAuthorization()
        await computeAuthorizationsSatisfied()
    }

    private func computeAuthorizationsSatisfied() async {
        authorizationStatus = JarvisBiomeAuthorizations(
            location:    location.isAuthorized,
            activity:    activity.isAuthorized,
            vitals:      vitals.isAuthorized,
            homeKit:     homeKit.isAuthorized,
            audio:       audio.isAuthorized,
            siri:        intents.isAuthorized,
            notifications: notifications.isAuthorized,
            cloudKit:    cloudSync.isAuthorized
        )
        allAuthorizationsSatisfied = authorizationStatus.isSatisfied
    }

    // MARK: Signal Subscription

    private func subscribeToAllSignals() {

        // Location signals → operator location presence
        location.$currentPresence
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presence in
                self?.operatorLocation = presence
            }
            .store(in: &cancellables)

        // Activity signals → operator activity state
        activity.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.operatorActivity = state
            }
            .store(in: &cancellables)

        // Vital signals → vital context
        vitals.$currentContext
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ctx in
                self?.operatorVitalContext = ctx
            }
            .store(in: &cancellables)

        // HomeKit signals → home state
        homeKit.$homeState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.homeState = state
            }
            .store(in: &cancellables)

        // Accessory proximity → proximity state
        homeKit.$accessoryProximity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] proximity in
                self?.accessoryProximity = proximity
            }
            .store(in: &cancellables)

        // Watch connectivity state
        watchBridge.$isSessionActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.watchSessionActive = active
            }
            .store(in: &cancellables)

        // Ambient environment (audio level, light)
        audio.$ambientLevel
            .combineLatest(homeKit.$ambientLightLevel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] audioLevel, lightLevel in
                self?.ambientEnvironment = JarvisAmbientState(audioLevel: audioLevel, lightLevel: lightLevel)
            }
            .store(in: &cancellables)
    }

    // MARK: PresenceSignal Generation

    /// Returns the current aggregate presence signal for all biome inputs.
    /// Used by the OrchestratorRouting layer to drive state decisions.
    public var currentPresenceSignal: JarvisBiomePresenceSignal {
        JarvisBiomePresenceSignal(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            location:      operatorLocation,
            activity:      operatorActivity,
            vitals:        operatorVitalContext,
            ambient:       ambientEnvironment,
            accessory:     accessoryProximity,
            home:          homeState,
            watchActive:   watchSessionActive,
            authorizations: authorizationStatus
        )
    }
}

// MARK: - Supporting Types

// @Published-ready location presence
public enum JarvisLocationPresence: String, Sendable {
    case unknown
    case atHome
    case atWork
    case inVehicle      // automotive — EMS context
    case onScene        // at an emergency scene (geofence trigger)
    case inMedicalFacility
    case elsewhere
}

// @Published-ready activity state
public enum JarvisActivityState: String, Sendable {
    case unknown
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case sleeping
    case workingOut
}

// @Published-ready vital context (from HealthKit)
public struct JarvisVitalContext: Sendable, Equatable {
    public let heartRateBPM: Double?
    public let hrvMS: Double?
    public let hrvStatus: HrvStatus
    public let stepCount: Int?
    public let sleepHours: Double?
    public let stressEstimate: StressEstimate

    public init(
        heartRateBPM: Double? = nil,
        hrvMS: Double? = nil,
        hrvStatus: HrvStatus = .unknown,
        stepCount: Int? = nil,
        sleepHours: Double? = nil,
        stressEstimate: StressEstimate = .unknown
    ) {
        self.heartRateBPM = heartRateBPM
        self.hrvMS = hrvMS
        self.hrvStatus = hrvStatus
        self.stepCount = stepCount
        self.sleepHours = sleepHours
        self.stressEstimate = stressEstimate
    }

    public static let nominal = JarvisVitalContext()
}

public enum HrvStatus: String, Sendable { case unknown, low, normal, elevated }
public enum StressEstimate: String, Sendable { case unknown, low, moderate, high }

// @Published-ready ambient state
public struct JarvisAmbientState: Sendable, Equatable {
    public let audioLevel: AudioLevel
    public let lightLevel: LightLevel

    public init(audioLevel: AudioLevel = .unknown, lightLevel: LightLevel = .unknown) {
        self.audioLevel = audioLevel
        self.lightLevel = lightLevel
    }

    public static let unknown = JarvisAmbientState()
}

public enum AudioLevel: String, Sendable { case unknown, silent, ambient, loud }
public enum LightLevel: String, Sendable { case unknown, dark, dim, bright }

// @Published-ready accessory proximity
public enum JarvisAccessoryProximity: String, Sendable {
    case unknown
    case near     // within BLE range / HomeKit zone
    case present  // actively detected (connected)
    case absent
}

// @Published-ready home state
public enum JarvisHomeState: String, Sendable {
    case unknown
    case occupied
    case vacant
    case nightTime
    case lockdown  // security triggered
}

// Authorization aggregate
public struct JarvisBiomeAuthorizations: Sendable {
    public let location:      Bool
    public let activity:      Bool
    public let vitals:        Bool
    public let homeKit:       Bool
    public let audio:         Bool
    public let siri:          Bool
    public let notifications:  Bool
    public let cloudKit:      Bool

    public init(
        location: Bool = false,
        activity: Bool = false,
        vitals: Bool = false,
        homeKit: Bool = false,
        audio: Bool = false,
        siri: Bool = false,
        notifications: Bool = false,
        cloudKit: Bool = false
    ) {
        self.location = location
        self.activity = activity
        self.vitals = vitals
        self.homeKit = homeKit
        self.audio = audio
        self.siri = siri
        self.notifications = notifications
        self.cloudKit = cloudKit
    }

    public var isSatisfied: Bool {
        location && vitals && audio && notifications
    }
}

// Aggregate presence signal emitted to orchestrator
public struct JarvisBiomePresenceSignal: Sendable {
    public let timestamp: String
    public let location:      JarvisLocationPresence
    public let activity:     JarvisActivityState
    public let vitals:       JarvisVitalContext
    public let ambient:      JarvisAmbientState
    public let accessory:   JarvisAccessoryProximity
    public let home:         JarvisHomeState
    public let watchActive:  Bool
    public let authorizations: JarvisBiomeAuthorizations
}
