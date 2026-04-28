import Foundation
import CloudKit
import Combine

/// Cloud sync biome — iCloud/CloudKit, Convex mirror, KV store
///
/// Biological analogue: parasympathetic nervous system — rest, repair,
/// anabolic state. Data at rest (sleep) vs data in motion (active sync).
///
/// Wires CloudKit private database as the off-mesh mirror for JARVIS memory.
/// Syncs health events, location breadcrumbs, and presence signals to iCloud
/// so watch/iOS share a consistent view of operator state.
///
/// CloudKit container: iCloud.ai.realjarvis.cloud
@MainActor
public final class JarvisCloudSyncBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var syncState: SyncState = .idle
    @Published public private(set) var lastSyncTimestamp: Date?

    public enum SyncState: String, Sendable {
        case idle
        case syncing
        case error
        case offline
    }

    // MARK: Private State

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let zoneID: CKRecordZone.ID

    private let recordType = "JarvisBiomeEvent"
    private var subscriptions = [CKSubscription.ID]()

    // MARK: Init

    public init() {
        self.container = CKContainer(identifier: "iCloud.ai.realjarvis.cloud")
        self.privateDatabase = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: "JarvisZone", ownerName: CKCurrentUserDefaultName)
    }

    // MARK: Public API

    public func start() {
        setupZone()
        setupSubscription()
        fetchLastSync()
    }

    public func stop() {
        subscriptions.forEach { subscriptionID in
            privateDatabase.delete(withSubscriptionID: subscriptionID) { _, _ in }
        }
        subscriptions.removeAll()
    }

    public func requestAuthorization() async {
        do {
            let status = try await container.accountStatus()
            isAuthorized = (status == .available)
            if !isAuthorized {
                print("[JarvisCloudSyncBiome] iCloud account not available: \(status.rawValue)")
            }
        } catch {
            print("[JarvisCloudSyncBiome] account status error: \(error)")
            isAuthorized = false
        }
    }

    /// Write a biome event (location, vital, presence signal) to CloudKit.
    public func record(event: BiomeCloudEvent) async {
        guard isAuthorized else { return }
        syncState = .syncing

        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        record["eventType"] = event.eventType
        record["timestamp"] = event.timestamp
        record["payload"] = event.payload
        record["nodeID"] = event.nodeID

        do {
            _ = try await privateDatabase.save(record)
            lastSyncTimestamp = Date()
            syncState = .idle
        } catch {
            print("[JarvisCloudSyncBiome] save error: \(error)")
            syncState = .error
        }
    }

    /// Fetch recent biome events for cross-device reconciliation.
    public func fetchRecentEvents(since: Date) async -> [CKRecord] {
        guard isAuthorized else { return [] }

        let predicate = NSPredicate(format: "timestamp > %@", since as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (results, _) = try await privateDatabase.records(matching: query)
            return results.compactMap { try? $0.1.get() }
        } catch {
            print("[JarvisCloudSyncBiome] fetch error: \(error)")
            return []
        }
    }

    // MARK: Private

    private func setupZone() {
        Task {
            do {
                let zone = CKRecordZone(zoneID: zoneID)
                _ = try await privateDatabase.save(zone)
            } catch {
                print("[JarvisCloudSyncBiome] zone setup error: \(error)")
            }
        }
    }

    private func setupSubscription() {
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: "biome-events",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        Task {
            do {
                let result = try await privateDatabase.save(subscription)
                subscriptions.append(result.subscriptionID)
            } catch {
                print("[JarvisCloudSyncBiome] subscription error: \(error)")
            }
        }
    }

    private func fetchLastSync() {
        let predicate = NSPredicate(format: "recordType == %@", recordType)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        Task {
            do {
                let (results, _) = try await privateDatabase.records(matching: query, resultsLimit: 1)
                if let record = results.first?.1 as? CKRecord {
                    lastSyncTimestamp = record["timestamp"] as? Date
                }
            } catch {
                print("[JarvisCloudSyncBiome] fetch last sync error: \(error)")
            }
        }
    }
}

// MARK: - Event Types

public struct BiomeCloudEvent: Sendable {
    public let eventType: String   // "location", "vital", "presence", "homeState"
    public let timestamp: Date
    public let payload: String      // JSON encoded
    public let nodeID: String      // Source node identifier

    public init(eventType: String, timestamp: Date = Date(), payload: String, nodeID: String = "JARVIS-iOS") {
        self.eventType = eventType
        self.timestamp = timestamp
        self.payload = payload
        self.nodeID = nodeID
    }
}