import Foundation
import WatchConnectivity
import Combine

/// Watch bridge biome — WCSession, iPhone ↔ Watch bidirectional data transfer
///
/// Biological analogue: vagus nerve — bidirectional parasympathetic
/// signaling between brain (iPhone) and heart (Watch).
///
/// Uses WCSession to send commands to Watch and receive sensor data
/// back. Enables operator health context to flow from Watch → iPhone
/// and command directives to flow from iPhone → Watch.
@MainActor
public final class JarvisWatchBridgeBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var isSessionActive: Bool = false
    @Published public private(set) var isWatchReachable: Bool = false
    @Published public private(set) var lastHeartRateReceived: Date?
    @Published public private(set) var lastMessageSent: Date?
    @Published public private(set) var rogerRogerProfile: RogerRogerSessionProfile = .watchSentinel

    // MARK: Private State

    private var session: WCSession?
    private var sessionDelegate: WCSessionDelegateHandler?
    private var pendingMessages = [String: (result: Result<[String: Any], Error>) -> Void]()

    // MARK: Init

    public init() {
        if WCSession.isSupported() {
            session = WCSession.default
            sessionDelegate = WCSessionDelegateHandler(biome: self)
            session?.delegate = sessionDelegate
        }
    }

    // MARK: Public API

    public func start() {
        guard let session, session.isWatchAppInstalled else {
            print("[JarvisWatchBridgeBiome] Watch app not installed")
            return
        }
        session.activate()
        isAuthorized = true
    }

    public func stop() {
        isSessionActive = false
        isWatchReachable = false
    }

    /// Send a command dict to Watch and await optional reply.
    public func send(message: [String: Any], replyHandler: ((Result<[String: Any], Error>) -> Void)? = nil) {
        guard let session, session.isReachable else {
            replyHandler?(.failure(WatchBridgeError.notReachable))
            return
        }

        let id = UUID().uuidString
        var outgoing = message
        outgoing["_msgId"] = id
        outgoing["_timestamp"] = ISO8601DateFormatter().string(from: Date())

        if let reply = replyHandler {
            pendingMessages[id] = reply
        }

        session.sendMessage(outgoing, replyHandler: { [weak self] response in
            Task { @MainActor [weak self] in
                if let msgId = response["_msgId"] as? String {
                    self?.pendingMessages.removeValue(forKey: msgId)
                }
                self?.lastMessageSent = Date()
            }
        }) { [weak self] error in
            Task { @MainActor [weak self] in
                if let msgId = outgoing["_msgId"] as? String {
                    self?.pendingMessages.removeValue(forKey: msgId)
                }
                print("[JarvisWatchBridgeBiome] send error: \(error)")
            }
        }
    }

    /// Request current heart rate from Watch immediately.
    public func requestHeartRate() {
        send(message: ["command": "getHeartRate"])
    }

    /// Update Watch display with current stress level.
    public func pushStressLevel(_ level: StressEstimate) {
        let payload: [String: Any] = [
            "command": "updateStress",
            "level": level.rawValue
        ]
        send(message: payload)
    }

    // MARK: Internal

    fileprivate func updateSessionState(isActive: Bool, isReachable: Bool) {
        isSessionActive = isActive
        isWatchReachable = isReachable
    }

    fileprivate func handleReceivedApplicationContext(_ context: [String: Any]) {
        if let hr = context["heartRate"] as? Double {
            lastHeartRateReceived = Date()
            NotificationCenter.default.post(
                name: .watchHeartRateReceived,
                object: nil,
                userInfo: ["heartRate": hr]
            )
        }
    }

    fileprivate func handleReceivedMessage(_ message: [String: Any]) {
        if let command = message["command"] as? String, command == "rogerRogerMode" {
            handleRogerRogerMode(message)
            return
        }

        if let type = message["type"] as? String {
            switch type {
            case "heartRateUpdate":
                if let hr = message["value"] as? Double {
                    lastHeartRateReceived = Date()
                }
            case "locationUpdate":
                break
            default:
                break
            }
        }
    }

    private func handleRogerRogerMode(_ message: [String: Any]) {
        guard let modeRaw = message["mode"] as? String,
              let mode = RogerRogerMode(rawValue: modeRaw) else {
            print("[JarvisWatchBridgeBiome] invalid Roger Roger mode payload")
            return
        }

        let endpointRaw = message["preferredEndpoint"] as? String
        let endpoint = endpointRaw.flatMap(GhostLineEndpoint.init(rawValue:)) ?? .unknown
        rogerRogerProfile = RogerRogerSessionProfile(
            mode: mode,
            preferredEndpoint: endpoint,
            watchAvailable: true,
            elehearPreferred: true
        )
        NotificationCenter.default.post(
            name: .rogerRogerModeChanged,
            object: nil,
            userInfo: [
                "mode": mode.rawValue,
                "preferredEndpoint": endpoint.rawValue
            ]
        )
    }
}

// MARK: - Errors

public enum WatchBridgeError: Error, Sendable {
    case notReachable
    case sessionNotActive
    case timeout
}

// MARK: - WCSession Delegate

@MainActor
private final class WCSessionDelegateHandler: NSObject, @preconcurrency WCSessionDelegate {
    weak var biome: JarvisWatchBridgeBiome?

    init(biome: JarvisWatchBridgeBiome) { self.biome = biome }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        biome?.updateSessionState(
            isActive: activationState == .activated,
            isReachable: session.isReachable
        )
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        biome?.updateSessionState(isActive: false, isReachable: false)
    }

    func sessionDidDeactivate(_ session: WCSession) {
        biome?.updateSessionState(isActive: false, isReachable: false)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        biome?.updateSessionState(isActive: session.activationState == .activated, isReachable: session.isReachable)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        biome?.handleReceivedApplicationContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        biome?.handleReceivedMessage(message)
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let watchHeartRateReceived = Notification.Name("jarvis.watch.heartRateReceived")
    static let rogerRogerModeChanged = Notification.Name("jarvis.watch.rogerRogerModeChanged")
}
