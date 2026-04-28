import Foundation
import HealthKit
import Combine

/// Vitals biome — HealthKit on iOS + watchOS
///
/// Biological analogue: autonomic nervous system (ANS) — heart rate,
/// HRV, respiratory sinus arrhythmia, galvanic skin response.
///
/// Tracks: heartRate, HRV (SDRR), stepCount, sleepAnalysis, vo2Max,
/// restingHeartRate, bloodGlucose (CGM), workouts.
///
/// Uses HKAnchoredObjectQuery for efficient streaming with observer queries
/// for background delivery.
@MainActor
public final class JarvisVitalsBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var currentContext: JarvisVitalContext = .nominal

    // MARK: Private State

    private let store = HKHealthStore()
    private var observerQueries = [HKObserverQuery]()
    private var anchoredQueries = [HKAnchoredObjectQuery]()

    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
    private let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max)!
    private let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    private let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
    private let workoutType = HKObjectType.workoutType()

    private var lastHeartRate: Double?
    private var lastHRV: Double?
    private var lastSteps: Int?
    private var lastSleepHours: Double?

    private var enableBackgroundDelivery = false

    // MARK: Init

    public init() {}

    // MARK: Public API

    public func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        enableBackgroundDelivery = true
        startObserving()
        fetchMostRecent()
    }

    public func stop() {
        observerQueries.forEach { store.stop($0) }
        anchoredQueries.forEach { store.stop($0) }
        observerQueries.removeAll()
        anchoredQueries.removeAll()
    }

    public func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            return
        }

        let readTypes: Set<HKObjectType> = [
            heartRateType, hrvType, stepsType, sleepType,
            vo2MaxType, restingHRType, glucoseType, workoutType
        ]
        let writeTypes: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
            HKObjectType.workoutType()
        ]

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            if enableBackgroundDelivery { startObserving() }
        } catch {
            print("[JarvisVitalsBiome] authorization failed: \(error)")
            isAuthorized = false
        }
    }

    // MARK: Private

    private func startObserving() {
        let types: [HKSampleType] = [
            heartRateType, hrvType, stepsType, sleepType, workoutType
        ]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                if error == nil {
                    Task { @MainActor [weak self] in
                        self?.fetchMostRecent()
                    }
                }
                completionHandler()
            }
            store.execute(query)
            observerQueries.append(query)

            if enableBackgroundDelivery {
                store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
            }
        }
    }

    private func fetchMostRecent() {
        fetchHeartRate()
        fetchHRV()
        fetchSteps()
        fetchSleep()
    }

    private func fetchHeartRate() {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            Task { @MainActor [weak self] in
                self?.lastHeartRate = bpm
                self?.recompute()
            }
        }
        store.execute(query)
    }

    private func fetchHRV() {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let ms = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            Task { @MainActor [weak self] in
                self?.lastHRV = ms
                self?.recompute()
            }
        }
        store.execute(query)
    }

    private func fetchSteps() {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let query = HKStatisticsQuery(
            quantityType: stepsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            guard let sum = result?.sumQuantity() else { return }
            let count = Int(sum.doubleValue(for: HKUnit.count()))
            Task { @MainActor [weak self] in
                self?.lastSteps = count
                self?.recompute()
            }
        }
        store.execute(query)
    }

    private func fetchSleep() {
        let now = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -12, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let sample = samples?.first as? HKCategorySample else { return }
            let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
            Task { @MainActor [weak self] in
                self?.lastSleepHours = hours
                self?.recompute()
            }
        }
        store.execute(query)
    }

    private func recompute() {
        let hrvStatus: HrvStatus
        if let hrv = lastHRV {
            if hrv < 30 { hrvStatus = .low }
            else if hrv < 60 { hrvStatus = .normal }
            else { hrvStatus = .elevated }
        } else {
            hrvStatus = .unknown
        }

        let stress: StressEstimate
        if let hr = lastHeartRate, let hrv = lastHRV {
            let ratio = hr / max(hrv, 1)
            if ratio < 2.5 { stress = .low }
            else if ratio < 4.0 { stress = .moderate }
            else { stress = .high }
        } else {
            stress = .unknown
        }

        currentContext = JarvisVitalContext(
            heartRateBPM: lastHeartRate,
            hrvMS: lastHRV,
            hrvStatus: hrvStatus,
            stepCount: lastSteps,
            sleepHours: lastSleepHours,
            stressEstimate: stress
        )
    }
}
