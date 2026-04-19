import Foundation
import JarvisMobileCore
import UIKit
import UserNotifications

public final class JarvisMobileAppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            JarvisMobileSystemHooks.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "jarvis.mobile.push-registration-error")
    }

    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        JarvisMobileSystemHooks.shared.handleRemoteNotification(userInfo)
    }
}
