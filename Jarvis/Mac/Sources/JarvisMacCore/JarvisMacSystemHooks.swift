import SwiftUI
import AppKit

public final class JarvisMacSystemHooks {
    private let notificationCenter = NSUserNotificationCenter.default

    public static let shared = JarvisMacSystemHooks()

    private init() {}

    public func showNotification(title: String, subtitle: String? = nil, informational: String? = nil) {
        let notification = NSUserNotification()
        notification.title = title
        if let subtitle = subtitle {
            notification.subtitle = subtitle
        }
        if let informational = informational {
            notification.informationalText = informational
        }
        notification.soundName = NSUserNotificationDefaultSoundName
        notificationCenter.deliver(notification)
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
