import Foundation

public enum JarvisError: Error, CustomStringConvertible {
    case workspaceNotFound(String)
    case invalidInput(String)
    case skillNotFound(String)
    case nativeSkillUnavailable(String)
    case processFailure(String)
    case serializationFailure(String)

    public var description: String {
        switch self {
        case let .workspaceNotFound(message),
             let .invalidInput(message),
             let .skillNotFound(message),
             let .nativeSkillUnavailable(message),
             let .processFailure(message),
             let .serializationFailure(message):
            return message
        }
    }
}

public struct WorkspacePaths: Sendable {
    public let root: URL
    public let agentSkillsRoot: URL
    public let skillDirectory: URL
    public let archonDirectory: URL
    public let convexDirectory: URL
    public let vendorDirectory: URL
    public let mlxAudioPackageDirectory: URL
    public let voiceSamplesDirectory: URL
    public let storageRoot: URL
    public let storageDirectory: URL
    public let voiceCacheDirectory: URL
    public let controlPlaneDirectory: URL
    public let homebridgeDirectory: URL
    public let homebridgeConfigURL: URL
    public let homebridgeStatusURL: URL
    public let obsidianDirectory: URL
    public let obsidianPluginsDirectory: URL
    public let obsidianUATUDataURL: URL
    public let obsidianLiveSyncDataURL: URL
    public let guiIntentQueueURL: URL
    public let nodeRegistryStatusURL: URL
    public let rustDeskRegistryURL: URL
    public let commandRegistryURL: URL
    public let regulationStatusURL: URL
    public let sovereignStatusURL: URL
    public let flatCockpitDirectory: URL
    public let flatCockpitStatusURL: URL
    public let flatCockpitHTMLURL: URL
    public let xrSurfaceDirectory: URL
    public let xrSurfaceStatusURL: URL
    public let xrSurfaceHTMLURL: URL
    public let telemetryDirectory: URL
    public let traceDirectory: URL
    public let interfaceLogURL: URL
    public let interfacePIDURL: URL
    public let rlmScriptURL: URL

    public init(root: URL, storageRoot: URL? = nil) {
        self.root = root
        self.agentSkillsRoot = root.appendingPathComponent("agent-skills", isDirectory: true)
        self.skillDirectory = agentSkillsRoot.appendingPathComponent("skills", isDirectory: true)
        self.archonDirectory = root.appendingPathComponent("Archon", isDirectory: true)
        self.convexDirectory = root.appendingPathComponent("convex", isDirectory: true)
        self.vendorDirectory = root.appendingPathComponent("vendor", isDirectory: true)
        self.mlxAudioPackageDirectory = self.vendorDirectory.appendingPathComponent("mlx-audio-swift", isDirectory: true)
        self.voiceSamplesDirectory = root.appendingPathComponent("voice-samples", isDirectory: true)
        self.storageRoot = storageRoot ?? root.appendingPathComponent(".jarvis", isDirectory: true)
        self.storageDirectory = self.storageRoot.appendingPathComponent("storage", isDirectory: true)
        self.voiceCacheDirectory = self.storageDirectory.appendingPathComponent("voice", isDirectory: true)
        self.controlPlaneDirectory = self.storageRoot.appendingPathComponent("control-plane", isDirectory: true)
        self.homebridgeDirectory = self.controlPlaneDirectory.appendingPathComponent("homebridge", isDirectory: true)
        self.homebridgeConfigURL = self.homebridgeDirectory.appendingPathComponent("config.json")
        self.homebridgeStatusURL = self.homebridgeDirectory.appendingPathComponent("status.json")
        self.obsidianDirectory = root.appendingPathComponent("obsidian", isDirectory: true)
        self.obsidianPluginsDirectory = self.obsidianDirectory
            .appendingPathComponent(".obsidian", isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        self.obsidianUATUDataURL = self.obsidianPluginsDirectory
            .appendingPathComponent("uatu-engine", isDirectory: true)
            .appendingPathComponent("data.json")
        self.obsidianLiveSyncDataURL = self.obsidianPluginsDirectory
            .appendingPathComponent("obsidian-livesync", isDirectory: true)
            .appendingPathComponent("data.json")
        self.guiIntentQueueURL = self.controlPlaneDirectory.appendingPathComponent("gui-intents.json")
        self.nodeRegistryStatusURL = self.controlPlaneDirectory.appendingPathComponent("node-registry.json")
        self.rustDeskRegistryURL = self.controlPlaneDirectory.appendingPathComponent("rustdesk-registry.json")
        self.commandRegistryURL = self.controlPlaneDirectory.appendingPathComponent("command-registry.json")
        self.regulationStatusURL = self.controlPlaneDirectory.appendingPathComponent("regulation.json")
        self.sovereignStatusURL = self.controlPlaneDirectory.appendingPathComponent("sovereign-dashboard.json")
        self.flatCockpitDirectory = root
            .appendingPathComponent("cockpit", isDirectory: true)
            .appendingPathComponent("cmd-interface", isDirectory: true)
        self.flatCockpitStatusURL = self.flatCockpitDirectory.appendingPathComponent("homekit-bridge-status.json")
        self.flatCockpitHTMLURL = self.flatCockpitDirectory.appendingPathComponent("index.html")
        self.xrSurfaceDirectory = root.appendingPathComponent("xr.grizzlymedicine.icu", isDirectory: true)
        self.xrSurfaceStatusURL = self.xrSurfaceDirectory.appendingPathComponent("homekit-bridge-status.json")
        self.xrSurfaceHTMLURL = self.xrSurfaceDirectory.appendingPathComponent("index.html")
        self.telemetryDirectory = self.storageRoot.appendingPathComponent("telemetry", isDirectory: true)
        self.traceDirectory = self.storageRoot.appendingPathComponent("traces", isDirectory: true)
        self.interfaceLogURL = self.storageRoot.appendingPathComponent("interface.log")
        self.interfacePIDURL = self.storageRoot.appendingPathComponent("interface.pid")
        self.rlmScriptURL = root
            .appendingPathComponent("Jarvis", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("JarvisCore", isDirectory: true)
            .appendingPathComponent("RLM", isDirectory: true)
            .appendingPathComponent("rlm_repl.py")
    }

    public static func discover(from startURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> WorkspacePaths {
        var current = startURL.standardizedFileURL
        let fileManager = FileManager.default

        while true {
            let agentSkills = current.appendingPathComponent("agent-skills", isDirectory: true)
            let workspace = current.appendingPathComponent("jarvis.xcworkspace", isDirectory: true)
            if fileManager.fileExists(atPath: agentSkills.path), fileManager.fileExists(atPath: workspace.path) {
                return WorkspacePaths(root: current)
            }

            let parent = current.deletingLastPathComponent()
            if parent == current {
                break
            }
            current = parent
        }

        throw JarvisError.workspaceNotFound("Unable to locate the Real Jarvis workspace root from \(startURL.path).")
    }

    public func ensureSupportDirectories() throws {
        let fileManager = FileManager.default
        for directory in [
            storageRoot,
            storageDirectory,
            voiceCacheDirectory,
            controlPlaneDirectory,
            homebridgeDirectory,
            obsidianDirectory,
            obsidianPluginsDirectory,
            obsidianUATUDataURL.deletingLastPathComponent(),
            obsidianLiveSyncDataURL.deletingLastPathComponent(),
            flatCockpitDirectory,
            xrSurfaceDirectory,
            telemetryDirectory,
            traceDirectory,
            archonDirectory,
            convexDirectory,
            vendorDirectory,
            voiceSamplesDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func resolve(path rawPath: String) -> URL {
        let url = URL(fileURLWithPath: rawPath)
        return url.isFileURL && rawPath.hasPrefix("/") ? url : root.appendingPathComponent(rawPath)
    }

    public func audioSampleURLs() throws -> [URL] {
        let fileManager = FileManager.default
        let normalizedSamples = (try? fileManager.contentsOfDirectory(at: voiceSamplesDirectory, includingPropertiesForKeys: nil)) ?? []
        let normalizedAudio = normalizedSamples
            .filter { ["wav", "mp3", "m4a", "aiff", "aif"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if !normalizedAudio.isEmpty {
            return normalizedAudio
        }

        let rootContents = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return rootContents
            .filter { ["mp3", "wav", "m4a", "aiff", "aif"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
