import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

public final class JarvisMobileSystemHooks: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = JarvisMobileSystemHooks()

    private let refreshTaskIdentifier = "ai.realjarvis.mobile.refresh"
    private weak var store: JarvisMobileCockpitStore?
    private var registeredTasks = false

    @MainActor
    public func configure(store: JarvisMobileCockpitStore) {
        self.store = store
        UNUserNotificationCenter.current().delegate = self
        requestNotificationAuthorization()
        UIApplication.shared.registerForRemoteNotifications()
        registerBackgroundTasks()
        scheduleRefresh()
    }

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "jarvis.mobile.push-token")
    }

    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        guard let directive = parseDirective(from: userInfo) else {
            return .noData
        }
        JarvisPendingActionStore.store(push: directive)
        if let store {
            Task { @MainActor in
                await store.receive(push: directive)
            }
        }
        return .newData
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        _ = handleRemoteNotification(notification.request.content.userInfo)
        return [.banner, .sound]
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        _ = handleRemoteNotification(response.notification.request.content.userInfo)
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { _, _ in }
    }

    private func registerBackgroundTasks() {
        guard !registeredTasks else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            self?.handleAppRefresh(task)
        }
        registeredTasks = true
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()
        let semaphore = DispatchSemaphore(value: 0)
        let refresh = Task {
            await store?.refreshSharedState()
            semaphore.signal()
        }
        task.expirationHandler = {
            refresh.cancel()
            task.setTaskCompleted(success: false)
        }
        semaphore.wait()
        task.setTaskCompleted(success: true)
    }

    private func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(300)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func parseDirective(from userInfo: [AnyHashable: Any]) -> JarvisPushDirective? {
        let title = userInfo["jarvis_title"] as? String ?? "Jarvis Event"
        let body = userInfo["jarvis_body"] as? String ?? "The host emitted a proactive event."
        let startupLine = userInfo["jarvis_startup_line"] as? String ?? body
        let requiresSpeech = (userInfo["jarvis_requires_speech"] as? Bool) ?? true
        let timestamp = userInfo["jarvis_timestamp"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let identifier = userInfo["jarvis_id"] as? String ?? UUID().uuidString
        return JarvisPushDirective(
            id: identifier,
            title: title,
            body: body,
            startupLine: startupLine,
            requiresSpeech: requiresSpeech,
            timestamp: timestamp
        )
    }
}
