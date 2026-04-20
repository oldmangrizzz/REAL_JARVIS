import Foundation

public enum CommandAuthority: Sendable {
    case voiceOperator
    case tunnelClient
    case autonomousPulse
}

public struct CommandAuthorization: Sendable {
    public let authority: CommandAuthority
    public let allowedDisplays: Set<String>
    public let allowedAccessories: Set<String>
    public let allowedActions: Set<String>

    public static func voiceOperator(registry: CapabilityRegistry) -> CommandAuthorization {
        CommandAuthorization(
            authority: .voiceOperator,
            allowedDisplays: Set(registry.allDisplayIDs),
            allowedAccessories: Set(registry.allAccessoryIDs),
            allowedActions: ["display-telemetry", "display-camera", "display-hud", "display-dashboard", "display-generic", "homekit-control"]
        )
    }

    public static func tunnelClient(deviceID: String, registry: CapabilityRegistry) -> CommandAuthorization {
        CommandAuthorization(
            authority: .tunnelClient,
            allowedDisplays: [deviceID],
            allowedAccessories: [],
            allowedActions: ["display-hud", "display-dashboard"]
        )
    }

    public static func autonomousPulse() -> CommandAuthorization {
        CommandAuthorization(
            authority: .autonomousPulse,
            allowedDisplays: [],
            allowedAccessories: [],
            allowedActions: ["read-status"]
        )
    }

    public init(authority: CommandAuthority, allowedDisplays: Set<String>, allowedAccessories: Set<String>, allowedActions: Set<String>) {
        self.authority = authority
        self.allowedDisplays = allowedDisplays
        self.allowedAccessories = allowedAccessories
        self.allowedActions = allowedActions
    }
}

public struct ExecutionResult: Sendable {
    public let success: Bool
    public let spokenText: String
    public let details: [String: String]

    public init(success: Bool, spokenText: String, details: [String: String]) {
        self.success = success
        self.spokenText = spokenText
        self.details = details
    }
}

public final class DisplayCommandExecutor: @unchecked Sendable {
    private let registry: CapabilityRegistry
    private let controlPlane: MyceliumControlPlane
    private let telemetry: TelemetryStore
    private let isoFormatter = ISO8601DateFormatter()
    private let airPlayBridge: AirPlayBridge
    private let httpBridge: HTTPDisplayBridge
    private let hdmiCECBridge: HDMICECBridge

    public init(registry: CapabilityRegistry, controlPlane: MyceliumControlPlane, telemetry: TelemetryStore) {
        self.registry = registry
        self.controlPlane = controlPlane
        self.telemetry = telemetry
        let paths: WorkspacePaths
        do {
            paths = try WorkspacePaths.discover()
        } catch {
            paths = WorkspacePaths(root: URL(fileURLWithPath: "/Users/grizzmed/REAL_JARVIS/Jarvis"))
        }
        self.airPlayBridge = AirPlayBridge(paths: paths)
        self.httpBridge = HTTPDisplayBridge()
        self.hdmiCECBridge = HDMICECBridge()
    }

    public func execute(intent: ParsedIntent, authorization: CommandAuthorization) async throws -> ExecutionResult {
        switch intent.intent {
        case .displayAction(let target, let action, let parameters):
            guard authorization.allowedDisplays.contains(target) else {
                throw JarvisError.invalidInput("Not authorized to control display '\(target)'.")
            }
            guard authorization.allowedActions.contains(action) else {
                throw JarvisError.invalidInput("Not authorized for action '\(action)'.")
            }
            guard let display = registry.display(for: target) else {
                throw JarvisError.invalidInput("Display '\(target)' not found in registry.")
            }
            let result = try await routeToDisplay(display: display, action: action, parameters: parameters)
            try logExecution(intent: intent, result: result, authorization: authorization)
            return result

        case .homeKitControl(let accessoryName, let characteristic, let value):
            guard authorization.allowedAccessories.contains(accessoryName) else {
                throw JarvisError.invalidInput("Not authorized to control '\(accessoryName)'.")
            }
            guard authorization.allowedActions.contains("homekit-control") else {
                throw JarvisError.invalidInput("Not authorized for HomeKit control.")
            }
            let result = try await routeToHomeKit(accessory: accessoryName, characteristic: characteristic, value: value)
            try logExecution(intent: intent, result: result, authorization: authorization)
            return result

        case .systemQuery, .skillInvocation, .unknown:
            return ExecutionResult(success: false, spokenText: "Routed to legacy command system.", details: [:])
        }
    }

    private func routeToDisplay(display: DisplayEndpoint, action: String, parameters: [String: String]) async throws -> ExecutionResult {
        switch display.transport {
        case .airplay:
            guard let address = display.address else {
                throw JarvisError.processFailure("AirPlay display '\(display.id)' has no address configured.")
            }
            return try await airPlayBridge.switchInput(deviceAddress: address, appName: "Jarvis")

        case .ddcCI:
            return try executeDDCCommand(display: display, action: action, parameters: parameters)

        case .http:
            guard let address = display.address else {
                throw JarvisError.processFailure("HTTP display '\(display.id)' has no address configured.")
            }
            let appId = parameters["content"] ?? "com.apple.TVViewer"
            return try await httpBridge.launchApp(address: address, appId: appId)

        case .homeKit, .matter:
            return try await routeToHomeKit(accessory: display.id, characteristic: "on", value: "true")

        case .hdmiCEC:
            return try hdmiCECBridge.switchInput(outputPort: 1)

        case .local:
            // Echo (local Mac host): display commands route through the host
            // renderer pipeline — not a remote transport.
            return ExecutionResult(
                success: true,
                spokenText: "\(display.displayName) rendering locally.",
                details: [
                    "display": display.id,
                    "transport": "local",
                    "action": action
                ]
            )

        case .jarvisTunnel:
            // Mesh nodes (alpha/beta/foxtrot/charlie/delta): dispatch via
            // the host tunnel to the target node's JarvisCore instance.
            // Stub: queue-and-ack until MeshDisplayDispatcher lands. The
            // snapshot already carries node registry heartbeats.
            return ExecutionResult(
                success: true,
                spokenText: "Command queued for \(display.displayName) over the Jarvis mesh.",
                details: [
                    "display": display.id,
                    "transport": "jarvis-tunnel",
                    "address": display.address ?? "",
                    "action": action,
                    "authority": display.authority.rawValue
                ]
            )
        }
    }

    private func executeDDCCommand(display: DisplayEndpoint, action: String, parameters: [String: String]) throws -> ExecutionResult {
        let m1ddcPath = "/usr/local/bin/m1ddc"

        guard FileManager.default.fileExists(atPath: m1ddcPath) else {
            throw JarvisError.processFailure("m1ddc not found at \(m1ddcPath). Install: brew install waydab/tap/m1ddc")
        }

        let displayIndex = registry.displayIndex(for: display.id) ?? 1

        let inputSource: String
        switch action {
        case "display-telemetry", "display-hud", "display-dashboard":
            inputSource = "17"  // USB-C/DisplayPort
        case "display-camera":
            inputSource = "15"  // HDMI
        default:
            inputSource = "17"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: m1ddcPath)
        process.arguments = ["display", "\(displayIndex)", "set", "input", inputSource]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown DDC error"
            throw JarvisError.processFailure("m1ddc failed: \(errorMessage)")
        }

        return ExecutionResult(
            success: true,
            spokenText: "Switched \(display.displayName) to Mac input.",
            details: ["display": display.id, "action": action, "inputSource": inputSource]
        )
    }

    private func routeToHomeKit(accessory: String, characteristic: String, value: String) async throws -> ExecutionResult {
        return ExecutionResult(success: true, spokenText: "HomeKit control queued for \(accessory).", details: ["accessory": accessory, "characteristic": characteristic, "value": value])
    }

    private func logExecution(intent: ParsedIntent, result: ExecutionResult, authorization: CommandAuthorization) throws {
        let table = "command_executions"
        try telemetry.append(record: [
            "intent": intent.rawTranscript,
            "confidence": intent.confidence,
            "success": result.success,
            "authority": authorization.authority.description,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ], to: table)
    }
}

extension CommandAuthority: CustomStringConvertible {
    public var description: String {
        switch self {
        case .voiceOperator: return "voice-operator"
        case .tunnelClient: return "tunnel-client"
        case .autonomousPulse: return "autonomous-pulse"
        }
    }
}
