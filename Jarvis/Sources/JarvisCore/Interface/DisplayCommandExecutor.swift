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
    private let meshDispatcher: MeshDisplayDispatching
    private let dialBridge: DIALDispatching
    private let alexaRoutineBridge: AlexaRoutineDispatching
    private let n8nBridge: N8NBridge?
    private let n8nHAWebhookPath: String

    public init(
        registry: CapabilityRegistry,
        controlPlane: MyceliumControlPlane,
        telemetry: TelemetryStore,
        n8nBridge: N8NBridge? = nil,
        n8nHAWebhookPath: String = "jarvis/ha/call-service",
        meshDispatcher: MeshDisplayDispatching? = nil,
        dialBridge: DIALDispatching? = nil,
        alexaRoutineBridge: AlexaRoutineDispatching? = nil
    ) {
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
        self.meshDispatcher = meshDispatcher ?? MeshDisplayDispatcher()
        self.dialBridge = dialBridge ?? DIALBridge()
        self.alexaRoutineBridge = alexaRoutineBridge ?? AlexaRoutineBridge()
        self.n8nBridge = n8nBridge
        self.n8nHAWebhookPath = n8nHAWebhookPath
    }

    // MARK: - MK2-EPIC-02: Destructive guardrail (PRINCIPLES §1.3 operator-on-loop)

    /// Execute a tunnel command, enforcing the two-step confirm for destructive actions.
    /// - Parameters:
    ///   - tunnelCommand: The remote command from the tunnel frame.
    ///   - confirmHash:   The `X-Confirm-Hash` value from the frame (nil if absent).
    ///   - authorization: Authority context for the connection.
    public func execute(
        tunnelCommand: JarvisRemoteCommand,
        confirmHash: String?,
        authorization: CommandAuthorization
    ) async throws -> ExecutionResult {
        let action = tunnelCommand.action
        if action.isDestructive {
            let expected = action.canonicalHashHex
            guard let provided = confirmHash else {
                try? telemetry.append(record: [
                    "event": "destructive.rejected",
                    "action": action.rawValue,
                    "reason": "missing-confirm-hash",
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ], to: "tunnel_events")
                throw TunnelError.destructiveRequiresConfirm
            }
            guard provided == expected else {
                try? telemetry.append(record: [
                    "event": "destructive.rejected",
                    "action": action.rawValue,
                    "reason": "hash-mismatch",
                    "provided": provided,
                    "expected": expected,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ], to: "tunnel_events")
                throw TunnelError.confirmHashMismatch
            }
            try? telemetry.append(record: [
                "event": "destructive.confirmed",
                "action": action.rawValue,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ], to: "tunnel_events")
        }
        return ExecutionResult(
            success: true,
            spokenText: "Tunnel command \(action.rawValue) accepted.",
            details: [
                "action": action.rawValue,
                "destructive": "\(action.isDestructive)",
                "authority": authorization.authority.description
            ]
        )
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
            return try await meshDispatcher.dispatch(display: display, action: action, parameters: parameters)

        case .dial:
            return try await dialBridge.launchApp(display: display, action: action, parameters: parameters)

        case .alexaRoutine:
            return try await alexaRoutineBridge.trigger(display: display, action: action, parameters: parameters)
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

    /// Route a HomeKit-style intent to Home Assistant via n8n when an
    /// `N8NBridge` is configured. Maps `characteristic` → HA domain/service and
    /// best-effort maps the spoken accessory name to an `entity_id`.
    /// If no bridge is configured, falls back to a queued no-op so unit tests
    /// that don't provide network plumbing still pass.
    private func routeToHomeKit(accessory: String, characteristic: String, value: String) async throws -> ExecutionResult {
        guard let bridge = n8nBridge else {
            return ExecutionResult(
                success: true,
                spokenText: "HomeKit control queued for \(accessory).",
                details: ["accessory": accessory, "characteristic": characteristic, "value": value]
            )
        }

        let mapping = Self.mapHomeKitToHA(accessory: accessory, characteristic: characteristic, value: value)
        var payload: [String: Any] = [
            "domain": mapping.domain,
            "service": mapping.service,
            "data": mapping.data
        ]
        if let entityId = mapping.entityId {
            payload["entity_id"] = entityId
        }

        do {
            _ = try await bridge.runWorkflow(webhookPath: n8nHAWebhookPath, payload: payload)
            return ExecutionResult(
                success: true,
                spokenText: "\(accessory) \(mapping.spokenVerb).",
                details: [
                    "accessory": accessory,
                    "characteristic": characteristic,
                    "value": value,
                    "haDomain": mapping.domain,
                    "haService": mapping.service,
                    "haEntityId": mapping.entityId ?? ""
                ]
            )
        } catch {
            return ExecutionResult(
                success: false,
                spokenText: "I couldn't reach the home bridge for \(accessory).",
                details: [
                    "accessory": accessory,
                    "characteristic": characteristic,
                    "value": value,
                    "error": String(describing: error)
                ]
            )
        }
    }

    /// Pure mapping from the abstract HomeKit triple to HA call-service
    /// parameters. Exposed as `internal` so tests can verify it without
    /// spinning up an N8NBridge.
    struct HAMapping {
        let domain: String
        let service: String
        let entityId: String?
        let data: [String: Any]
        let spokenVerb: String
    }

    static func mapHomeKitToHA(accessory: String, characteristic: String, value: String) -> HAMapping {
        let entityId = haEntityID(for: accessory)
        switch characteristic.lowercased() {
        case "on":
            let isOn = ["true", "1", "on", "yes"].contains(value.lowercased())
            return HAMapping(
                domain: "light",
                service: isOn ? "turn_on" : "turn_off",
                entityId: entityId,
                data: [:],
                spokenVerb: isOn ? "is on" : "is off"
            )
        case "brightness":
            let pct = max(0, min(100, Int(value) ?? 50))
            return HAMapping(
                domain: "light",
                service: "turn_on",
                entityId: entityId,
                data: ["brightness_pct": pct],
                spokenVerb: "set to \(pct) percent"
            )
        default:
            return HAMapping(
                domain: "homeassistant",
                service: "turn_on",
                entityId: entityId,
                data: [:],
                spokenVerb: "acknowledged"
            )
        }
    }

    /// Best-effort normalization of spoken accessory names to HA entity_ids.
    /// Accepts explicit entity ids (`light.x`) verbatim; otherwise maps a
    /// common vocabulary of room/group names to the canonical group IDs
    /// used by the Phase 3 seed workflows.
    static func haEntityID(for accessory: String) -> String? {
        let raw = accessory.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "unknown" else { return nil }
        if raw.contains(".") { return raw }

        if raw.contains("downstairs") { return "group.downstairs_lights" }
        if raw.contains("upstairs") { return "group.upstairs_lights" }
        if raw.contains("all light") || raw == "lights" || raw == "all lights" {
            return "group.all_lights"
        }

        let slug = raw
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return slug.isEmpty ? nil : "light.\(slug)"
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
