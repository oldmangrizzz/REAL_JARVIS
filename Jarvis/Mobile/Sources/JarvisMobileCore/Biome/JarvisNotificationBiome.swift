import Foundation
import UserNotifications
import Combine

/// Notifications biome — UNUserNotificationCenter, APNs, local notifications
///
/// Biological analogue: adrenal medulla — epinephrine/norepinephrine
/// release (fast notification) and HPA axis (slower scheduled cortisol).
///
/// Handles APNs remote notifications, local scheduled notifications,
/// and notification authorization state. Routes incoming push directives
/// to the JARVIS orchestrator via JarvisMobileSystemHooks.
@MainActor
public final class JarvisNotificationBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var pendingNotifications: [UNNotification] = []
    @Published public private(set) var lastNotificationReceived: Date?

    // MARK: Private State

    private var delegate: NotificationDelegate?
    private let center = UNUserNotificationCenter.current()

    // MARK: Init

    public init() {
        delegate = NotificationDelegate(biome: self)
        center.delegate = delegate
    }

    // MARK: Public API

    public func start() {
        refreshPendingNotifications()
    }

    public func stop() {
        // UNUserNotificationCenter doesn't require explicit stop
    }

    public func requestAuthorization() async {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound, .provisional, .criticalAlert]
        do {
            let granted = try await center.requestAuthorization(options: options)
            isAuthorized = granted
        } catch {
            print("[JarvisNotificationBiome] auth error: \(error)")
            isAuthorized = false
        }
    }

    /// Schedule a local notification (e.g., medication reminder, appointment).
    public func scheduleLocal(identifier: String, title: String, body: String, triggerDate: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    /// Remove a scheduled notification.
    public func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Clear all delivered notifications from notification center.
    public func clearDelivered() {
        center.removeAllDeliveredNotifications()
    }

    // MARK: Internal

    fileprivate func handleReceivedNotification(_ notification: UNNotification) {
        lastNotificationReceived = Date()
        refreshPendingNotifications()

        let userInfo = notification.request.content.userInfo
        NotificationCenter.default.post(
            name: .jarvisNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
    }

    private func refreshPendingNotifications() {
        center.getPendingNotificationRequests { [weak self] requests in
            Task { @MainActor [weak self] in
                // Convert to observable format if needed
                self?.pendingNotifications = []
            }
        }
    }
}

// MARK: - Delegate

@MainActor
private final class NotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    weak var biome: JarvisNotificationBiome?

    init(biome: JarvisNotificationBiome) { self.biome = biome }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        biome?.handleReceivedNotification(notification)
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(
            name: .jarvisNotificationResponse,
            object: nil,
            userInfo: userInfo
        )
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let jarvisNotificationReceived = Notification.Name("jarvis.notification.received")
    static let jarvisNotificationResponse = Notification.Name("jarvis.notification.response")
}
