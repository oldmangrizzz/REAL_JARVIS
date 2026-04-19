import Foundation

public enum JarvisPendingActionStore {
    private static let commandKey = "jarvis.mobile.pending-command"
    private static let pushKey = "jarvis.mobile.pending-push"

    public static func store(command: JarvisRemoteCommand) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        UserDefaults.standard.set(data, forKey: commandKey)
    }

    public static func consumeCommand() -> JarvisRemoteCommand? {
        guard let data = UserDefaults.standard.data(forKey: commandKey),
              let command = try? JSONDecoder().decode(JarvisRemoteCommand.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: commandKey)
        return command
    }

    public static func store(push: JarvisPushDirective) {
        guard let data = try? JSONEncoder().encode(push) else { return }
        UserDefaults.standard.set(data, forKey: pushKey)
    }

    public static func consumePush() -> JarvisPushDirective? {
        guard let data = UserDefaults.standard.data(forKey: pushKey),
              let push = try? JSONDecoder().decode(JarvisPushDirective.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: pushKey)
        return push
    }
}
