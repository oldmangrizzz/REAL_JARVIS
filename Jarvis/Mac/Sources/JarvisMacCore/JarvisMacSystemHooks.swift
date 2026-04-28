import SwiftUI
import AppKit
import UserNotifications

@MainActor
public final class JarvisMacSystemHooks {
    private let notificationCenter = UNUserNotificationCenter.current()

    public static let shared = JarvisMacSystemHooks()

    private init() {}

    public func showNotification(title: String, subtitle: String? = nil, informational: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        if let informational = informational {
            content.body = informational
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { _ in }
    }

    public func setDockBadge(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    public func clearDockBadge() {
        NSApp.dockTile.badgeLabel = nil
    }

    public func menuBarStatus(_ status: String) {
        // Would integrate with NSStatusBar system for menu bar icon
        print("[MenuBar] \(status)")
    }

    public func alertError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    public func alertWarning(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    public func alertInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
