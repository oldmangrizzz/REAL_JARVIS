import Foundation
import HealthKit

@MainActor
public final class JarvisWatchVitalMonitor: ObservableObject {
    @Published public private(set) var heartRateLine = "Awaiting heart rate"
    @Published public private(set) var lastUpdated = ""

    private let store = HKHealthStore()

    public init() {}

    public func start() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            heartRateLine = "HealthKit unavailable"
            return
        }

        do {
            try await requestAuthorization(for: heartRate)
            try await refresh(using: heartRate)
        } catch {
            heartRateLine = error.localizedDescription
        }
    }

    public func refresh() async {
        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        try? await refresh(using: heartRate)
    }

    private func requestAuthorization(for type: HKQuantityType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: [type]) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "JarvisWatchVitalMonitor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Health authorization was not granted."]))
                }
            }
        }
    }

    private func refresh(using type: HKQuantityType) async throws {
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-7200), end: Date(), options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let sample = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKQuantitySample?, Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKQuantitySample)
                }
            }
            store.execute(query)
        }

        guard let sample else {
            heartRateLine = "No recent heart rate"
            return
        }

        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let bpm = sample.quantity.doubleValue(for: unit)
        heartRateLine = String(format: "%.0f BPM", bpm)
        lastUpdated = ISO8601DateFormatter().string(from: sample.endDate)
    }
}
