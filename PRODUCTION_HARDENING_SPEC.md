# JARVIS PRODUCTION HARDENING SPEC — Voice-to-Display Command Pipeline

## Mission

"Jarvis, put the telemetry feed on the left monitor" — spoken once, executed instantly, zero trust gaps from eardrum to pixel.

## Architecture: The Missing Pieces

```
[Voice In] → [VoiceCommandRouter] → [IntentParser] → [CapabilityRegistry] → [DisplayCommandExecutor] → [HomeKit/Network]
                EXISTS                MISSING          MISSING              MISSING                PARTIAL
```

The current system has:
- Voice recognition (SFSpeechRecognizer) ✅
- Voice approval gate ✅
- Tunnel server/client ✅
- HomeKit bridge status (read-only) ✅
- VoiceCommandRouter (7 hardcoded commands) ✅

It does NOT have:
- Intent parsing (NLP → structured action) ❌
- Display/capability registry ❌
- Command execution with bounded authority ❌
- Voice-to-tunnel command path ❌

---

## SPEC-001: IntentParser — Voice to Structured Action

**File:** `Jarvis/Sources/JarvisCore/Interface/IntentParser.swift` (NEW)

**Purpose:** Transform a raw transcript into a typed, validated command object. This is the brain between "I heard words" and "I will do a thing."

### 1.1 Type Definitions

```swift
public enum JarvisIntent: Sendable {
    case displayAction(target: String, action: String, parameters: [String: String])
    case homeKitControl(accessoryName: String, characteristic: String, value: String)
    case systemQuery(query: String)
    case skillInvocation(skillName: String, payload: [String: Any])
    case unknown(rawTranscript: String)
}

public struct ParsedIntent: Sendable {
    public let intent: JarvisIntent
    public let confidence: Double  // 0.0-1.0
    public let rawTranscript: String
    public let timestamp: String
}
```

### 1.2 IntentParser Implementation

```swift
public final class IntentParser: Sendable {
    private let capabilityRegistry: CapabilityRegistry
    
    public init(capabilityRegistry: CapabilityRegistry) {
        self.capabilityRegistry = capabilityRegistry
    }
    
    public func parse(transcript: String) -> ParsedIntent {
        let normalized = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern 1: Display commands
        // "put X on the left monitor", "show X on display Y", "send X to the TV"
        if let displayIntent = parseDisplayIntent(normalized) {
            return ParsedIntent(intent: displayIntent, confidence: 0.85, rawTranscript: transcript, timestamp: ISO8601DateFormatter().string(from: Date()))
        }
        
        // Pattern 2: HomeKit control
        // "turn off the lights", "dim the kitchen to 50%", "lock the front door"
        if let homeKitIntent = parseHomeKitIntent(normalized) {
            return ParsedIntent(intent: homeKitIntent, confidence: 0.8, rawTranscript: transcript, timestamp: ISO8601DateFormatter().string(from: Date()))
        }
        
        // Pattern 3: Skill invocation (existing)
        // "run skill X", "execute X"
        if let skillIntent = parseSkillIntent(normalized) {
            return ParsedIntent(intent: skillIntent, confidence: 0.9, rawTranscript: transcript, timestamp: ISO8601DateFormatter().string(from: Date()))
        }
        
        // Pattern 4: System query (existing)
        // "status", "what's running"
        if let systemIntent = parseSystemIntent(normalized) {
            return ParsedIntent(intent: systemIntent, confidence: 0.9, rawTranscript: transcript, timestamp: ISO8601DateFormatter().string(from: Date()))
        }
        
        return ParsedIntent(intent: .unknown(rawTranscript: transcript), confidence: 0.0, rawTranscript: transcript, timestamp: ISO8601DateFormatter().string(from: Date()))
    }
}
```

### 1.3 Display Intent Patterns

```swift
private func parseDisplayIntent(_ text: String) -> JarvisIntent? {
    // Known verb prefixes
    let verbs = ["put", "show", "display", "send", "cast", "stream", "move", "switch", "route", "pull up", "bring up", "open"]
    
    // Known display keywords
    let displayKeywords = ["monitor", "display", "screen", "tv", "television"]
    
    // Known content sources
    let contentSources = ["telemetry", "feed", "camera", "video", "dashboard", "status", "hud", "cockpit", "map", "chart"]
    
    guard verbs.contains(where: { text.hasPrefix($0) }) else { return nil }
    guard displayKeywords.contains(where: { text.contains($0) }) || contentSources.contains(where: { text.contains($0) }) else { return nil }
    
    // Extract target display from capability registry
    let targetDisplay = capabilityRegistry.matchDisplay(from: text)
    let action = capabilityRegistry.matchAction(from: text)
    let parameters = capabilityRegistry.matchParameters(from: text)
    
    return .displayAction(target: targetDisplay, action: action, parameters: parameters)
}
```

### 1.4 HomeKit Intent Patterns

```swift
private func parseHomeKitIntent(_ text: String) -> JarvisIntent? {
    let onVerbs = ["turn on", "switch on", "enable", "activate", "start", "open", "unlock"]
    let offVerbs = ["turn off", "switch off", "disable", "deactivate", "stop", "close", "lock"]
    let dimVerbs = ["dim", "brighten", "set", "adjust", "change"]
    
    // Match against known accessory names from the registry
    let accessoryName = capabilityRegistry.matchAccessoryName(from: text)
    
    if onVerbs.contains(where: { text.contains($0) }) {
        return .homeKitControl(accessoryName: accessoryName, characteristic: "on", value: "true")
    }
    if offVerbs.contains(where: { text.contains($0) }) {
        return .homeKitControl(accessoryName: accessoryName, characteristic: "on", value: "false")
    }
    if dimVerbs.contains(where: { text.contains($0) }) {
        // Extract percentage if present
        if let range = text.range(of: #"(\d{1,3})%"#, options: .regularExpression) {
            let pctStr = String(text[range])
            let pct = pctStr.replacingOccurrences(of: "%", with: "")
            return .homeKitControl(accessoryName: accessoryName, characteristic: "brightness", value: pct)
        }
        return .homeKitControl(accessoryName: accessoryName, characteristic: "brightness", value: "50")
    }
    
    return nil
}
```

### 1.5 Confidence Threshold

- confidence >= 0.8 → execute immediately
- confidence >= 0.5 → execute but speak confirmation first: "I'm about to [action]. Confirm?"
- confidence < 0.5 → refuse, speak: "I heard [transcript] but I'm not confident enough to act on it. Could you rephrase?"

### 1.6 Tests Required

- "Jarvis, put the telemetry feed on the left monitor" → displayAction(target: "left-monitor", action: "display", parameters: ["content": "telemetry"])
- "Jarvis, turn off the kitchen lights" → homeKitControl(accessoryName: "kitchen-lights", characteristic: "on", value: "false")
- "Jarvis, dim the bedroom to 30%" → homeKitControl(accessoryName: "bedroom", characteristic: "brightness", value: "30")
- "Jarvis, show me the status" → systemQuery
- "Jarvis, burn the house down" → unknown with confidence 0.0 — REFUSE
- Ambiguous: "Jarvis, put it on the big screen" → confidence < 0.5 if "it" is unresolved

---

## SPEC-002: CapabilityRegistry — What Exists and What It Can Do

**File:** `Jarvis/Sources/JarvisCore/Interface/CapabilityRegistry.swift` (NEW)

**Purpose:** An inventory of every display, accessory, and controllable endpoint in the house. You can't route to what you can't find.

### 2.1 Type Definitions

```swift
public struct DisplayEndpoint: Codable, Sendable, Identifiable {
    public let id: String              // e.g. "left-monitor"
    public let displayName: String    // e.g. "Left Monitor"
    public let aliases: [String]       // e.g. ["left", "monitor-1", "primary"]
    public let type: DisplayType       // monitor, tv, projector
    public let transport: DisplayTransport // airplay, ddc-ci, http, hdmi-cec
    public let address: String?        // IP or device address
    public let capabilities: [String]  // "video", "telemetry", "hud", "dashboard"
    public let room: String?           // e.g. "lab", "office", "living"
    
    public enum DisplayType: String, Codable, Sendable {
        case monitor, tv, projector, tablet, watch
    }
    
    public enum DisplayTransport: String, Codable, Sendable {
        case airplay, ddcCI = "ddc-ci", http, hdmiCEC = "hdmi-cec", matter, homeKit = "homekit"
    }
}

public struct AccessoryEndpoint: Codable, Sendable, Identifiable {
    public let id: String              // e.g. "kitchen-lights"
    public let displayName: String    // e.g. "Kitchen Lights"
    public let aliases: [String]       // e.g. ["kitchen", "cooking"]
    public let homeKitAccessoryID: String?
    public let characteristics: [String] // "on", "brightness", "hue", "saturation"
    public let room: String?
}

public final class CapabilityRegistry {
    private let displays: [DisplayEndpoint]
    private let accessories: [AccessoryEndpoint]
    
    public init(displays: [DisplayEndpoint], accessories: [AccessoryEndpoint]) {
        self.displays = displays
        self.accessories = accessories
    }
    
    // Load from JSON config file at .jarvis/capabilities.json
    public convenience init(configURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(CapabilityConfig.self, from: data)
        self.init(displays: config.displays, accessories: config.accessories)
    }
    
    public func matchDisplay(from text: String) -> String {
        // Find the best display match in the transcript
        let lower = text.lowercased()
        for display in displays {
            if display.aliases.contains(where: { lower.contains($0) }) {
                return display.id
            }
            if lower.contains(display.displayName.lowercased()) {
                return display.id
            }
        }
        return "unknown"
    }
    
    public func matchAccessoryName(from text: String) -> String {
        let lower = text.lowercased()
        for acc in accessories {
            if acc.aliases.contains(where: { lower.contains($0) }) {
                return acc.id
            }
        }
        return "unknown"
    }
    
    public func matchAction(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("telemetry") || lower.contains("status") { return "display-telemetry" }
        if lower.contains("camera") || lower.contains("feed") { return "display-camera" }
        if lower.contains("map") { return "display-map" }
        if lower.contains("dashboard") || lower.contains("hud") { return "display-dashboard" }
        return "display-generic"
    }
    
    public func matchParameters(from text: String) -> [String: String] {
        var params: [String: String] = [:]
        let lower = text.lowercased()
        if lower.contains("telemetry") { params["content"] = "telemetry" }
        if lower.contains("camera") { params["content"] = "camera" }
        if lower.contains("hud") || lower.contains("cockpit") { params["content"] = "hud" }
        if lower.contains("dashboard") { params["content"] = "dashboard" }
        return params
    }
    
    public func display(for id: String) -> DisplayEndpoint? {
        displays.first(where: { $0.id == id })
    }
    
    public func accessory(for id: String) -> AccessoryEndpoint? {
        accessories.first(where: { $0.id == id })
    }
}
```

### 2.2 Config File Format

**File:** `.jarvis/capabilities.json`

```json
{
  "displays": [
    {
      "id": "left-monitor",
      "displayName": "Left Monitor",
      "aliases": ["left", "monitor-1", "primary"],
      "type": "monitor",
      "transport": "ddc-ci",
      "address": null,
      "capabilities": ["video", "telemetry", "hud", "dashboard"],
      "room": "lab"
    },
    {
      "id": "right-monitor",
      "displayName": "Right Monitor",
      "aliases": ["right", "monitor-2", "secondary"],
      "type": "monitor",
      "transport": "ddc-ci",
      "address": null,
      "capabilities": ["video", "telemetry", "hud", "dashboard"],
      "room": "lab"
    },
    {
      "id": "lab-tv",
      "displayName": "Lab TV",
      "aliases": ["tv", "television", "big screen", "living room"],
      "type": "tv",
      "transport": "airplay",
      "address": "192.168.4.151",
      "capabilities": ["video", "dashboard"],
      "room": "lab"
    }
  ],
  "accessories": [
    {
      "id": "kitchen-lights",
      "displayName": "Kitchen Lights",
      "aliases": ["kitchen", "cooking"],
      "homeKitAccessoryID": "HAP-0001",
      "characteristics": ["on", "brightness"],
      "room": "kitchen"
    }
  ]
}
```

### 2.3 Hot-Reload

The registry watches `.jarvis/capabilities.json` via `DispatchSource.makeFileSystemObjectSource`. On change, reload without restart. Log the reload to telemetry.

### 2.4 Security

The capabilities.json file MUST be mode 0600, owner-only. If permissions are wider, refuse to load and log a CRITICAL telemetry event.

---

## SPEC-003: DisplayCommandExecutor — Bounded Authority Execution

**File:** `Jarvis/Sources/JarvisCore/Interface/DisplayCommandExecutor.swift` (NEW)

**Purpose:** Take a structured intent and actually make it happen. With authority boundaries. No god mode.

### 3.1 Authority Model

```swift
public enum CommandAuthority: Sendable {
    case voiceOperator   // From voice interface — full control over assigned displays and accessories
    case tunnelClient    // From tunnel — limited to read-only + own device display
    case autonomousPulse // From the 60s timer — read-only, no side effects
}

public struct CommandAuthorization: Sendable {
    public let authority: CommandAuthority
    public let allowedDisplays: Set<String>    // display IDs this authority can control
    public let allowedAccessories: Set<String> // accessory IDs this authority can control
    public let allowedActions: Set<String>      // action types this authority can perform
    
    public static func voiceOperator(registry: CapabilityRegistry) -> CommandAuthorization {
        CommandAuthorization(
            authority: .voiceOperator,
            allowedDisplays: Set(registry.allDisplayIDs),
            allowedAccessories: Set(registry.allAccessoryIDs),
            allowedActions: ["display-telemetry", "display-camera", "display-hud", "display-dashboard", "display-generic", "homekit-control"]
        )
    }
    
    public static func tunnelClient(deviceID: String, registry: CapabilityRegistry) -> CommandAuthorization {
        // Tunnel clients can only control the display they're on
        CommandAuthorization(
            authority: .tunnelClient,
            allowedDisplays: [deviceID],  // only own device
            allowedAccessories: [],         // no HomeKit control from tunnel
            allowedActions: ["display-hud", "display-dashboard"]
        )
    }
    
    public static func autonomousPulse() -> CommandAuthorization {
        CommandAuthorization(
            authority: .autonomousPulse,
            allowedDisplays: [],
            allowedAccessories: [],
            allowedActions: ["read-status"]  // no side effects
        )
    }
}
```

### 3.2 Executor

```swift
public final class DisplayCommandExecutor {
    private let registry: CapabilityRegistry
    private let controlPlane: MyceliumControlPlane
    private let telemetry: TelemetryStore
    private let isoFormatter = ISO8601DateFormatter()
    
    public init(registry: CapabilityRegistry, controlPlane: MyceliumControlPlane, telemetry: TelemetryStore) {
        self.registry = registry
        self.controlPlane = controlPlane
        self.telemetry = telemetry
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
            // These route through the existing VoiceCommandRouter — no new executor needed
            return ExecutionResult(success: false, spokenText: "Routed to legacy command system.", details: [:])
        }
    }
}
```

### 3.3 Transport Routing

```swift
private func routeToDisplay(display: DisplayEndpoint, action: String, parameters: [String: String]) async throws -> ExecutionResult {
    switch display.transport {
    case .airplay:
        // Use AirPlay 2 protocol — requires `pyatv` or similar
        // For now: queue a GUI intent via MyceliumControlPlane
        return try queueGUIIntentForDisplay(display: display, action: action, parameters: parameters)
        
    case .ddcCI:
        // DDC/CI — control monitor input source via I2C
        // Requires `/ddcctl` or `m1ddc` binary
        return try executeDDCCommand(display: display, action: action, parameters: parameters)
        
    case .http:
        // Generic HTTP — POST to display's address
        guard let address = display.address else {
            throw JarvisError.processFailure("HTTP display '\(display.id)' has no address configured.")
        }
        return try executeHTTPCommand(address: address, action: action, parameters: parameters)
        
    case .homeKit, .matter:
        // Route through HomeKit bridge on Charlie
        return try await routeToHomeKit(accessory: display.id, characteristic: "on", value: "true")
        
    case .hdmiCEC:
        // HDMI-CEC — requires `cec-client` or tvOS
        throw JarvisError.processFailure("HDMI-CEC transport not yet implemented for '\(display.id)'.")
    }
}
```

### 3.4 DDC/CI Implementation (macOS)

```swift
private func executeDDCCommand(display: DisplayEndpoint, action: String, parameters: [String: String]) throws -> ExecutionResult {
    // m1ddc is the Apple Silicon DDC/CI tool
    // Usage: m1ddc set luminance <value>
    //        m1ddc set input <source>
    
    let displayIndex = registry.displayIndex(for: display.id) ?? 1
    
    switch action {
    case "display-telemetry", "display-hud", "display-dashboard":
        // Switch monitor input to the Mac (source 17 = USB-C/DisplayPort typically)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/m1ddc")
        process.arguments = ["display", "\(displayIndex)", "set", "input", "17"]
        try process.run()
        process.waitUntilExit()
        return ExecutionResult(success: true, spokenText: "Switched \(display.displayName) to Mac input.", details: ["display": display.id, "action": action])
    default:
        return ExecutionResult(success: false, spokenText: "Don't know how to \(action) on \(display.displayName) yet.", details: [:])
    }
}
```

### 3.5 ExecutionResult

```swift
public struct ExecutionResult: Sendable {
    public let success: Bool
    public let spokenText: String
    public let details: [String: Any]
}
```

### 3.6 Telemetry Logging

EVERY command execution — success or failure — gets logged:

```swift
try telemetry.logExecutionTrace(
    workflowID: "command-executor",
    stepID: "\(intent.intent.description)-\(UUID().uuidString.prefix(8))",
    inputContext: intent.rawTranscript,
    outputResult: result.spokenText,
    status: result.success ? "success" : "failure"
)
```

---

## SPEC-004: VoiceCommandRouter Upgrade — Wire the New Pipeline

**File:** `Jarvis/Sources/JarvisCore/Interface/RealJarvisInterface.swift` (MODIFY)

**Purpose:** Replace the 7-hardcoded-command router with the IntentParser → CapabilityRegistry → DisplayCommandExecutor pipeline.

### 4.1 Changes to VoiceCommandRouter

```swift
public final class VoiceCommandRouter {
    private let runtime: JarvisRuntime
    private let registry: JarvisSkillRegistry
    private let intentParser: IntentParser        // NEW
    private let commandExecutor: DisplayCommandExecutor  // NEW
    private let authorization: CommandAuthorization  // NEW
    
    public init(runtime: JarvisRuntime, registry: JarvisSkillRegistry, intentParser: IntentParser, commandExecutor: DisplayCommandExecutor, authorization: CommandAuthority) {
        self.runtime = runtime
        self.registry = registry
        self.intentParser = intentParser
        self.commandExecutor = commandExecutor
        // Build authorization from authority level
        switch authorization {
        case .voiceOperator:
            self.authorization = .voiceOperator(registry: intentParser.capabilityRegistry)
        case .tunnelClient(let deviceID):
            self.authorization = .tunnelClient(deviceID: deviceID, registry: intentParser.capabilityRegistry)
        case .autonomousPulse:
            self.authorization = .autonomousPulse()
        }
    }
    
    public func route(transcript: String) async throws -> VoiceCommandResponse? {
        guard let command = extractCommand(from: transcript) else { return nil }
        
        // NEW: Run through intent parser first
        let parsed = intentParser.parse(transcript: command)
        
        // Confidence gate
        if parsed.confidence < 0.5 {
            return VoiceCommandResponse(
                spokenText: "I heard '\(command)' but I'm not confident enough to act on it. Could you rephrase?",
                details: ["command": "low-confidence", "confidence": parsed.confidence, "transcript": command],
                shouldShutdown: false
            )
        }
        
        if parsed.confidence < 0.8 {
            return VoiceCommandResponse(
                spokenText: "I think you want me to \(describe(parsed.intent)). Should I proceed?",
                details: ["command": "confirm", "confidence": parsed.confidence, "intent": String(describing: parsed.intent)],
                shouldShutdown: false
            )
        }
        
        // High confidence: execute
        switch parsed.intent {
        case .displayAction, .homeKitControl:
            let result = try await commandExecutor.execute(intent: parsed, authorization: authorization)
            return VoiceCommandResponse(
                spokenText: result.spokenText,
                details: result.details,
                shouldShutdown: false
            )
            
        case .systemQuery, .skillInvocation, .unknown:
            // Fall through to existing legacy handler
            return try routeLegacy(command: command)
        }
    }
}
```

### 4.2 Remove hardcoded command matching

Delete the `command.contains("status")` / `command.contains("self heal")` / etc chain. Replace with:

```swift
private func routeLegacy(command: String) throws -> VoiceCommandResponse? {
    // Legacy support for existing commands
    if command.contains("status") {
        // ... existing status handling
    }
    if command.contains("list skills") || command.contains("what can you do") {
        // ... existing skills handling
    }
    if command.contains("self heal") || command.contains("heal the harness") {
        // ... existing heal handling
    }
    if command.contains("shutdown") || command.contains("go quiet") {
        // ... existing shutdown handling
    }
    // run skill and recall also stay
    
    return VoiceCommandResponse(spokenText: "I heard \(command), but that doesn't map to a known command yet.", details: ["command": "unmatched", "transcript": command], shouldShutdown: false)
}
```

### 4.3 Changes to RealJarvisInterface.start()

Add initialization of new components:

```swift
public func start(registry: JarvisSkillRegistry) throws {
    activeRegistry = registry
    
    // NEW: Initialize capability registry, intent parser, command executor
    let capabilityRegistry = try CapabilityRegistry(configURL: runtime.paths.capabilityConfigURL)
    let intentParser = IntentParser(capabilityRegistry: capabilityRegistry)
    let commandExecutor = DisplayCommandExecutor(registry: capabilityRegistry, controlPlane: runtime.controlPlane, telemetry: runtime.telemetry)
    
    commandRouter = VoiceCommandRouter(
        runtime: runtime,
        registry: registry,
        intentParser: intentParser,
        commandExecutor: commandExecutor,
        authorization: .voiceOperator
    )
    
    // ... rest of start() unchanged
}
```

### 4.4 Changes to handleTranscript

The current `handleTranscript` is synchronous. The new `route()` is async. Change:

```swift
private func handleTranscript(_ transcript: String, isFinal: Bool) {
    guard isFinal else { return }
    let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized != lastHandledTranscript else { return }
    lastHandledTranscript = normalized
    
    Task {
        do {
            try appendLog("heard \(normalized)")
            guard let commandRouter, let response = try await commandRouter.route(transcript: normalized) else { return }
            // ... rest unchanged
        } catch {
            try? appendLog("command-error \(error)")
        }
    }
}
```

---

## SPEC-005: CapabilityConfigURL — New WorkspacePath

**File:** `Jarvis/Sources/JarvisCore/Support/WorkspacePaths.swift` (MODIFY)

Add:

```swift
public var capabilityConfigURL: URL {
    storageRoot.appendingPathComponent("capabilities.json")
}
```

---

## SPEC-006: JarvisRemoteAction — New Command Types

**File:** `Jarvis/Shared/Sources/JarvisShared/TunnelModels.swift` (MODIFY)

Add new cases to `JarvisRemoteAction`:

```swift
case controlDisplay = "control_display"      // Voice → display command
case controlAccessory = "control_accessory"  // Voice → HomeKit command
```

Add corresponding handler cases in `JarvisHostTunnelServer.handle(command:)`:

```swift
case .controlDisplay:
    let target = command.text ?? "unknown"
    let payload = try parsePayload(command.payloadJSON)
    let intent = ParsedIntent(intent: .displayAction(target: target, action: payload["action"] as? String ?? "display-generic", parameters: payload), confidence: 1.0, rawTranscript: command.text ?? "", timestamp: isoFormatter.string(from: Date()))
    let result = try await commandExecutor.execute(intent: intent, authorization: tunnelAuthorization)
    return JarvisTunnelResponse(action: .controlDisplay, spokenText: result.spokenText, snapshot: try makeSnapshot(), payloadJSON: try makeJSONString(result.details))

case .controlAccessory:
    // Similar pattern
```

---

## SPEC-007: Tunnel Authorization — Fix the Self-Assertion Problem

**File:** `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` (MODIFY)

### Current Problem

The tunnel currently only allows `authorizedSources = Set(["obsidian-command-bar", "terminal"])`. Mobile clients register with a role string but that role must match one of those two. There's no "voice-operator" role.

### Fix

Add to `authorizedSources`:

```swift
private let authorizedSources = Set(["obsidian-command-bar", "terminal", "voice-operator", "mobile-cockpit"])
```

But `voice-operator` is ONLY granted when the connection's device has passed voice gate verification. Add a new registration flow:

```swift
case .register:
    if let registration = message.registration {
        let identifier = ObjectIdentifier(connection)
        let role = registration.role.lowercased()
        if authorizedSources.contains(role) {
            // NEW: voice-operator requires proof of voice gate clearance
            if role == "voice-operator" {
                // Verify voice gate is green on the host
                let gateSnapshot = runtime.voice.approval.snapshotForSpatialHUD()
                guard gateSnapshot.state == .green else {
                    return JarvisTunnelMessage(kind: .error, error: "Voice gate is not green. Cannot register as voice-operator.")
                }
            }
            clientSources[identifier] = role
        }
    }
```

---

## SPEC-008: Destructive Command Guardrails

**File:** `Jarvis/Sources/JarvisCore/Interface/IntentParser.swift` (NEW, part of SPEC-001)

### 8.1 Blocked Intent Patterns

There are things Jarvis should NEVER do from voice, regardless of confidence:

```swift
private static let blockedPatterns: [String] = [
    "burn", "destroy", "delete", "erase", "wipe", "kill", "terminate system",
    "format", "factory reset", "self destruct", "shutdown all", "disable safety",
    "override", "hack", "exploit", "jailbreak"
]

private func isBlockedIntent(_ text: String) -> Bool {
    let lower = text.lowercased()
    return Self.blockedPatterns.contains(where: { lower.contains($0) })
}
```

If `isBlockedIntent` returns true, the parser returns `JarvisIntent.unknown` with confidence 0.0 regardless of anything else.

### 8.2 Rate Limiting

No more than 5 display/HomeKit commands per 60 seconds. Track with a simple token bucket. Exceeding it returns:

"I'm receiving too many commands too quickly. Give me a moment."

### 8.3 Telemetry for ALL Rejections

Every blocked intent, rate-limit hit, and low-confidence refusal gets a telemetry event with `eventType: "command_refused"` including the raw transcript and reason.

---

## SPEC-009: PheromoneEngine Thread Safety (Known Bug Fix)

**File:** `Jarvis/Sources/JarvisCore/Pheromind/PheromoneEngine.swift` (MODIFY)

Add an NSLock:

```swift
public final class PheromindEngine {
    private let stateLock = NSLock()
    private var states: [EdgeKey: PheromoneEdgeState] = [:]
    // ...
    
    public func register(edge: EdgeKey, pheromone: Double, somaticWeight: Double) {
        stateLock.lock(); defer { stateLock.unlock() }
        states[edge] = PheromoneEdgeState(pheromone: pheromone, somaticWeight: somaticWeight, lastUpdated: Date())
    }
    
    // Wrap ALL mutation points with stateLock.lock()/unlock()
}
```

---

## SPEC-010: MasterOscillator Deadlock Fix (Known Bug Fix)

**File:** `Jarvis/Sources/JarvisCore/Oscillator/MasterOscillator.swift` (MODIFY)

### Current Problem

`fire()` calls `onTick()` on every subscriber while holding `self.lock`. If ANY subscriber calls back into the oscillator, deadlock because NSLock is not reentrant.

### Fix

Build the subscriber snapshot under the lock, THEN call onTick outside the lock:

```swift
private func fire() {
    let tickSubscribers: [(OscillatorSubscriber, OscillatorTick)]
    lock.lock()
    let currentBeat = beat
    let currentDrift = drift
    tickSubscribers = subscribers.map { ($0, OscillatorTick(beat: currentBeat, drift: currentDrift, timestamp: Date())) }
    lock.unlock()  // Release lock BEFORE calling subscribers
    
    for (subscriber, tick) in tickSubscribers {
        subscriber.onTick(tick)
    }
    
    lock.lock()
    lastEmitted = currentBeat
    lock.unlock()
}
```

This creates a brief window where `subscribers` could change between snapshot and dispatch, but that's safe — a subscriber removed after snapshot won't get the tick (acceptable), and a subscriber added after snapshot will get the next tick (also acceptable).

---

## SPEC-011: Tunnel Buffer Accumulation Fix (Known Bug Fix)

**File:** `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` (MODIFY)

The 1MB buffer limit (CX-004) was already added. Verify it's enforced. Also add a CONNECTION TIMEOUT — if a client connects but sends no data for 60 seconds, disconnect:

```swift
private func accept(_ connection: NWConnection) {
    let identifier = ObjectIdentifier(connection)
    clients[identifier] = connection
    buffers[identifier] = Data()
    clientSources[identifier] = "unauthenticated"
    
    // NEW: Connection idle timeout — 60 seconds of no data = disconnect
    queue.asyncAfter(deadline: .now() + 60) { [weak self] in
        guard let self else { return }
        if let source = self.clientSources[identifier], source == "unauthenticated" {
            self.disconnect(connection)
        }
    }
    
    // ... rest of accept unchanged
}
```

---

## IMPLEMENTATION ORDER

1. **SPEC-009** — PheromoneEngine thread safety (5 minutes, critical data race)
2. **SPEC-010** — MasterOscillator deadlock (5 minutes, guaranteed hang)
3. **SPEC-011** — Tunnel connection timeout (5 minutes, resource exhaustion)
4. **SPEC-002** — CapabilityRegistry + JSON config (20 minutes, foundation for everything else)
5. **SPEC-005** — WorkspacePaths addition (2 minutes)
6. **SPEC-001** — IntentParser (30 minutes, core parsing logic)
7. **SPEC-003** — DisplayCommandExecutor (30 minutes, transport routing)
8. **SPEC-008** — Destructive command guardrails (10 minutes, safety)
9. **SPEC-007** — Tunnel authorization upgrade (10 minutes)
10. **SPEC-006** — New tunnel command types (10 minutes)
11. **SPEC-004** — VoiceCommandRouter upgrade (15 minutes, wires everything together)

**Total estimate: ~2.5 hours of implementation**

Build verification: `xcodebuild test -scheme Jarvis -destination 'platform=macOS' -quiet` must still pass 74 tests.

New tests required:
- IntentParserTests: 6 tests (one per pattern in section 1.6)
- CapabilityRegistryTests: 3 tests (load from JSON, match display, match accessory)
- DisplayCommandExecutorTests: 4 tests (authorized execute, unauthorized reject, unknown display, HomeKit route)
- CommandGuardrailTests: 3 tests (blocked pattern, rate limit, telemetry on refusal)