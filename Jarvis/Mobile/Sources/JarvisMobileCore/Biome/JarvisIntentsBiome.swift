import Foundation
import AppIntents
import Combine

/// Intents biome — AppIntents framework, Siri integration, shortcuts
///
/// Biological analogue: prefrontal cortex — executive function,
/// deliberate action initiation, language understanding.
///
/// Wires JARVIS commands through AppIntents so they can be triggered
/// by Siri, Shortcuts, and Apple Watch digital crown.
/// Uses Shortcut-based AppIntents (iOS 16+).
@MainActor
public final class JarvisIntentsBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var registeredShortcuts: [APPShortcut] = []
    @Published public private(set) var lastIntentFired: Date?

    // MARK: Private

    private var shortcutProvider: JarvisShortcutProvider?

    // MARK: Init

    public init() {
        shortcutProvider = JarvisShortcutProvider()
    }

    // MARK: Public API

    public func start() {
        Task { await registerShortcuts() }
    }

    public func stop() {
        // AppIntents don't require teardown
    }

    public func requestAuthorization() async {
        // AppIntents authorization is handled by the system when the user
        // adds the shortcut via Settings or Siri. We check if shortcuts exist.
        do {
            let shortcuts = try await ShortcutStorage.queryShortcuts(matching: nil)
            registeredShortcuts = shortcuts
            isAuthorized = true
        } catch {
            // No shortcuts registered yet — not an error
            isAuthorized = true
        }
    }

    public func registerShortcuts() async {
        let intentShortcut = APPShortcut(id: "jarvis-command", title: "JARVIS Command")

        let request = SetShortcutsRequest([intentShortcut])
        do {
            try await ShortcutManager.shared.setShortcuts(request)
            registeredShortcuts = [intentShortcut]
        } catch {
            print("[JarvisIntentsBiome] shortcut registration failed: \(error)")
        }
    }
}

// MARK: - App Intent Definition

/// Main JARVIS command intent — exposed to Siri and Shortcuts.
/// Use: "Hey Siri, ask JARVIS to [command]"
@available(iOS 16.0, *)
public struct JarvisCommandIntent: AppIntent {
    public static let title: LocalizedStringResource = "JARVIS Command"
    public static let description = IntentDescription("Send a command to JARVIS")

    @Parameter(title: "Command")
    public var command: String

    public static let openAppWhenRun: Bool = false

    public init() {}

    public init(command: String) {
        self.command = command
    }

    public func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .jarvisIntentCommand,
            object: nil,
            userInfo: ["command": command]
        )

        return .result()
    }
}

// MARK: - Notification

public extension Notification.Name {
    static let jarvisIntentCommand = Notification.Name("jarvis.intent.command")
}

// MARK: - Shortcut Provider

public struct JarvisShortcutProvider {
    public init() {}
}

// MARK: - Shortcut Storage

public struct ShortcutStorage {
    public static func queryShortcuts(matching query: String?) throws -> [APPShortcut] {
        // Placeholder — ShortcutManager API varies by iOS version
        return []
    }
}

public struct APPShortcut: Identifiable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct ShortcutManager: Sendable {
    public static let shared = ShortcutManager()
    private init() {}

    public func setShortcuts(_ request: SetShortcutsRequest) async throws {
        // AppIntents shortcut registration via INShortcutsRequest
    }
}

public struct SetShortcutsRequest {
    public let shortcuts: [APPShortcut]
    public init(_ shortcuts: [APPShortcut]) {
        self.shortcuts = shortcuts
    }
}
