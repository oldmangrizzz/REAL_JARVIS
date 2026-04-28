import Foundation
import HomeKit
import Combine

/// HomeKit biome — HMHome API, accessory discovery, device control
///
/// Biological analogue: enteric nervous system (gut brain) — detects
/// environmental state via accessory proximity, temperature, humidity,
/// air quality, light levels.
///
/// Wires into the JARVIS home-state presence model and ambient environment
/// signals. Uses HMAccessoryBrowser for discovery, HMHome for primary
/// home, and fires callbacks on accessory state changes.
@MainActor
public final class JarvisHomeKitBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var homeState: JarvisHomeState = .unknown
    @Published public private(set) var accessoryProximity: JarvisAccessoryProximity = .unknown
    @Published public private(set) var ambientLightLevel: LightLevel = .unknown
    @Published public private(set) var accessories: [HMAccessory] = []

    // MARK: Private State

    private let homeManager = HMHomeManager()
    private var homeManagerDelegate: HMHomeManagerDelegateHandler?
    private var primaryHome: HMHome?
    private var browser: HMAccessoryBrowser?
    private var lights: [HMAccessory] = []
    private var motionSensors: [HMAccessory] = []

    // MARK: Init

    public init() {
        let delegate = HMHomeManagerDelegateHandler(biome: self)
        self.homeManagerDelegate = delegate
        homeManager.delegate = delegate
    }

    // MARK: Public API

    public func start() {
        if !homeManager.homes.isEmpty {
            configurePrimaryHome(homeManager.homes.first!)
        }
    }

    public func stop() {
        primaryHome?.accessories.forEach { acc in
            acc.delegate = nil
        }
    }

    public func requestAuthorization() async {
        // HomeKit doesn't have explicit user authorization separate from
        // the home setup dialog. Authorization is considered satisfied if
        // any HMHome exists with at least one accessory.
        isAuthorized = (primaryHome != nil) && !(primaryHome?.accessories.isEmpty ?? true)
    }

    // MARK: Internal

    fileprivate func configurePrimaryHome(_ home: HMHome) {
        self.primaryHome = home
        isAuthorized = !home.accessories.isEmpty

        accessories = home.accessories
        home.accessories.forEach { acc in
            acc.delegate = AccessoryDelegateHandler(biome: self)
            classifyAccessory(acc)
        }

        updateHomeState()
    }

    fileprivate func classifyAccessory(_ acc: HMAccessory) {
        let serviceTypes: Set<String> = [
            HMServiceTypeLightbulb,
            HMServiceTypeMotionSensor,
            HMServiceTypeTemperatureSensor,
            HMServiceTypeHumiditySensor,
            HMServiceTypeOccupancySensor,
            HMServiceTypeDoor,
            HMServiceTypeWindow,
            HMServiceTypeLockMechanism,
            HMServiceTypeSecuritySystem
        ]

        for service in acc.services where serviceTypes.contains(service.serviceType) {
            switch service.serviceType {
            case HMServiceTypeLightbulb:
                if !lights.contains(where: { $0.uniqueIdentifier == acc.uniqueIdentifier }) {
                    lights.append(acc)
                }
            case HMServiceTypeMotionSensor, HMServiceTypeOccupancySensor:
                if !motionSensors.contains(where: { $0.uniqueIdentifier == acc.uniqueIdentifier }) {
                    motionSensors.append(acc)
                }
            default:
                break
            }
        }
    }

    fileprivate func updateHomeState() {
        guard let home = primaryHome else { return }

        var occupied = false
        var nightTime = false
        var lockdown = false

        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        nightTime = hour >= 22 || hour < 6

        for acc in home.accessories {
            for service in acc.services {
                if service.serviceType == HMServiceTypeMotionSensor ||
                   service.serviceType == HMServiceTypeOccupancySensor {
                    if !service.characteristics.isEmpty {
                        occupied = true
                    }
                }
                if service.serviceType == HMServiceTypeSecuritySystem {
                    lockdown = true
                }
            }
        }

        if lockdown {
            homeState = .lockdown
        } else if nightTime {
            homeState = .nightTime
        } else if occupied {
            homeState = .occupied
        } else {
            homeState = .vacant
        }
    }

    fileprivate func updateLightLevel() {
        guard !lights.isEmpty else { return }

        var anyOn = false
        var allOff = true

        for light in lights {
            for service in light.services where service.serviceType == HMServiceTypeLightbulb {
                let powerState = service.characteristics.first { $0.characteristicType == HMCharacteristicTypePowerState }
                if let on = powerState?.value as? Bool {
                    if on { anyOn = true }
                    else { allOff = false }
                }
            }
        }

        if anyOn { ambientLightLevel = .bright }
        else if allOff { ambientLightLevel = .dark }
        else { ambientLightLevel = .dim }
    }

    fileprivate func addDiscoveredAccessory(_ accessory: HMAccessory) {
        accessory.delegate = AccessoryDelegateHandler(biome: self)
        accessories.append(accessory)
        classifyAccessory(accessory)
        updateLightLevel()
    }

    fileprivate func removeDiscoveredAccessory(_ accessory: HMAccessory) {
        accessories.removeAll { $0.uniqueIdentifier == accessory.uniqueIdentifier }
        lights.removeAll { $0.uniqueIdentifier == accessory.uniqueIdentifier }
        motionSensors.removeAll { $0.uniqueIdentifier == accessory.uniqueIdentifier }
    }

    fileprivate func markAccessoryPresent() {
        accessoryProximity = .present
    }
}

// MARK: - Delegate Handlers

@MainActor
private final class HMHomeManagerDelegateHandler: NSObject, @preconcurrency HMHomeManagerDelegate {
    weak var biome: JarvisHomeKitBiome?

    init(biome: JarvisHomeKitBiome) { self.biome = biome }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        guard let biome, let home = manager.primaryHome ?? manager.homes.first else { return }
        biome.configurePrimaryHome(home)
    }
}

@MainActor
private final class HMAccessoryBrowserDelegateHandler: NSObject, HMAccessoryBrowserDelegate {
    weak var biome: JarvisHomeKitBiome?

    init(biome: JarvisHomeKitBiome) { self.biome = biome }

    nonisolated func accessoryBrowser(_ browser: HMAccessoryBrowser, didFindNewAccessory accessory: HMAccessory) {
        Task { @MainActor [weak self] in
            guard let self, let biome = self.biome else { return }
            biome.addDiscoveredAccessory(accessory)
        }
    }

    nonisolated func accessoryBrowser(_ browser: HMAccessoryBrowser, didRemoveNewAccessory accessory: HMAccessory) {
        Task { @MainActor [weak self] in
            guard let self, let biome = self.biome else { return }
            biome.removeDiscoveredAccessory(accessory)
        }
    }
}

@MainActor
private final class AccessoryDelegateHandler: NSObject, HMAccessoryDelegate {
    weak var biome: JarvisHomeKitBiome?

    init(biome: JarvisHomeKitBiome) { self.biome = biome }

    nonisolated func accessoryDidUpdateServices(_ accessory: HMAccessory) {
        Task { @MainActor [weak self] in
            guard let self, let biome = self.biome else { return }
            biome.updateLightLevel()
            biome.updateHomeState()
            biome.markAccessoryPresent()
        }
    }
}
