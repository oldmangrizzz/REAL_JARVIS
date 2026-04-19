import Foundation

public enum JarvisRemoteAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case status
    case listSkills = "list_skills"
    case selfHeal = "self_heal"
    case startupVoice = "startup_voice"
    case homeKitStatus = "homekit_status"
    case queueGuiIntent = "queue_gui_intent"
    case reseedObsidian = "reseed_obsidian"
    case bridgeIntercom = "bridge_intercom"
    case shutdown
    case runSkill = "run_skill"
    case ping

    public var id: String { rawValue }
}

public enum JarvisTunnelMessageKind: String, Codable, Sendable {
    case register
    case command
    case snapshot
    case response
    case push
    case error
    case heartbeat
}

public enum JarvisConnectionState: String, Codable, Sendable {
    case disconnected
    case connecting
    case online
    case degraded
    case failed
}

public struct JarvisClientRegistration: Codable, Sendable {
    public let deviceID: String
    public let deviceName: String
    public let platform: String
    public let role: String
    public let appVersion: String

    public init(deviceID: String, deviceName: String, platform: String, role: String, appVersion: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.role = role
        self.appVersion = appVersion
    }
}

public struct JarvisRemoteCommand: Codable, Sendable {
    public let action: JarvisRemoteAction
    public let text: String?
    public let skillName: String?
    public let payloadJSON: String?
    public let source: String?

    public init(action: JarvisRemoteAction, text: String? = nil, skillName: String? = nil, payloadJSON: String? = nil, source: String? = nil) {
        self.action = action
        self.text = text
        self.skillName = skillName
        self.payloadJSON = payloadJSON
        self.source = source
    }
}

public struct JarvisThoughtSnapshot: Codable, Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let trace: [String]
    public let memoryPageFault: Bool
    public let timestamp: String
    public let sourceDeviceID: String?

    public init(id: String, sessionID: String, trace: [String], memoryPageFault: Bool, timestamp: String, sourceDeviceID: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.trace = trace
        self.memoryPageFault = memoryPageFault
        self.timestamp = timestamp
        self.sourceDeviceID = sourceDeviceID
    }
}

public struct JarvisSignalSnapshot: Codable, Sendable, Identifiable {
    public let id: String
    public let nodeSource: String
    public let nodeTarget: String
    public let ternaryValue: Int
    public let agentID: String
    public let pheromone: Double
    public let timestamp: String

    public init(id: String, nodeSource: String, nodeTarget: String, ternaryValue: Int, agentID: String, pheromone: Double, timestamp: String) {
        self.id = id
        self.nodeSource = nodeSource
        self.nodeTarget = nodeTarget
        self.ternaryValue = ternaryValue
        self.agentID = agentID
        self.pheromone = pheromone
        self.timestamp = timestamp
    }
}

public struct JarvisHomeKitAccessoryStatus: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let room: String
    public let state: String
    public let severity: String
    public let value: Double?
    public let lastUpdated: String

    public init(id: String, name: String, kind: String, room: String, state: String, severity: String, value: Double?, lastUpdated: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.room = room
        self.state = state
        self.severity = severity
        self.value = value
        self.lastUpdated = lastUpdated
    }
}

public struct JarvisHomeKitBridgeStatus: Codable, Sendable {
    public let bridgeName: String
    public let charlieAddress: String
    public let homebridgePort: Int
    public let reachable: Bool
    public let matterEnabled: Bool
    public let voiceIntercomRoute: String
    public let authorizedCommandSources: [String]
    public let regulationVisibility: String
    public let distressState: String
    public let bridgeState: String
    public let accessories: [JarvisHomeKitAccessoryStatus]
    public let lastSync: String

    public init(
        bridgeName: String,
        charlieAddress: String,
        homebridgePort: Int,
        reachable: Bool,
        matterEnabled: Bool,
        voiceIntercomRoute: String,
        authorizedCommandSources: [String],
        regulationVisibility: String,
        distressState: String,
        bridgeState: String,
        accessories: [JarvisHomeKitAccessoryStatus],
        lastSync: String
    ) {
        self.bridgeName = bridgeName
        self.charlieAddress = charlieAddress
        self.homebridgePort = homebridgePort
        self.reachable = reachable
        self.matterEnabled = matterEnabled
        self.voiceIntercomRoute = voiceIntercomRoute
        self.authorizedCommandSources = authorizedCommandSources
        self.regulationVisibility = regulationVisibility
        self.distressState = distressState
        self.bridgeState = bridgeState
        self.accessories = accessories
        self.lastSync = lastSync
    }
}

public struct JarvisObsidianVaultStatus: Codable, Sendable {
    public let databaseName: String
    public let betaCouchEndpoint: String
    public let docCount: Int
    public let replicationConfigured: Bool
    public let replicationObserved: Bool
    public let reseedTriggered: Bool
    public let pluginListening: Bool
    public let lastSync: String
    public let statusLine: String

    public init(
        databaseName: String,
        betaCouchEndpoint: String,
        docCount: Int,
        replicationConfigured: Bool,
        replicationObserved: Bool,
        reseedTriggered: Bool,
        pluginListening: Bool,
        lastSync: String,
        statusLine: String
    ) {
        self.databaseName = databaseName
        self.betaCouchEndpoint = betaCouchEndpoint
        self.docCount = docCount
        self.replicationConfigured = replicationConfigured
        self.replicationObserved = replicationObserved
        self.reseedTriggered = reseedTriggered
        self.pluginListening = pluginListening
        self.lastSync = lastSync
        self.statusLine = statusLine
    }
}

public struct JarvisGUIIntent: Codable, Sendable, Identifiable {
    public let id: String
    public let sourceNode: String
    public let targetNodes: [String]
    public let action: String
    public let payloadJSON: String?
    public let queuedAt: String
    public let status: String

    public init(id: String, sourceNode: String, targetNodes: [String], action: String, payloadJSON: String?, queuedAt: String, status: String) {
        self.id = id
        self.sourceNode = sourceNode
        self.targetNodes = targetNodes
        self.action = action
        self.payloadJSON = payloadJSON
        self.queuedAt = queuedAt
        self.status = status
    }
}

public struct JarvisRustDeskNode: Codable, Sendable, Identifiable {
    public let id: String
    public let nodeName: String
    public let rustDeskID: String?
    public let address: String?
    public let relayLocked: Bool
    public let lastSeen: String
    public let handoffURL: String?
    public let status: String

    public init(id: String, nodeName: String, rustDeskID: String?, address: String?, relayLocked: Bool, lastSeen: String, handoffURL: String?, status: String) {
        self.id = id
        self.nodeName = nodeName
        self.rustDeskID = rustDeskID
        self.address = address
        self.relayLocked = relayLocked
        self.lastSeen = lastSeen
        self.handoffURL = handoffURL
        self.status = status
    }
}

public struct JarvisNodeHeartbeat: Codable, Sendable, Identifiable {
    public let id: String
    public let nodeName: String
    public let address: String?
    public let source: String
    public let tunnelState: String
    public let guiReachable: Bool
    public let rustDeskID: String?
    public let lastSeen: String

    public init(id: String, nodeName: String, address: String?, source: String, tunnelState: String, guiReachable: Bool, rustDeskID: String?, lastSeen: String) {
        self.id = id
        self.nodeName = nodeName
        self.address = address
        self.source = source
        self.tunnelState = tunnelState
        self.guiReachable = guiReachable
        self.rustDeskID = rustDeskID
        self.lastSeen = lastSeen
    }
}

public struct JarvisPushDirective: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let startupLine: String
    public let requiresSpeech: Bool
    public let timestamp: String

    public init(id: String, title: String, body: String, startupLine: String, requiresSpeech: Bool, timestamp: String) {
        self.id = id
        self.title = title
        self.body = body
        self.startupLine = startupLine
        self.requiresSpeech = requiresSpeech
        self.timestamp = timestamp
    }
}

public struct JarvisHostSnapshot: Codable, Sendable {
    public let hostName: String
    public let statusLine: String
    public let indexedSkillCount: Int
    public let callableSkillCount: Int
    public let voiceSampleCount: Int
    public let tunnelState: JarvisConnectionState
    public let activeWorkflow: String
    public let lastMutation: String
    public let recentThoughts: [JarvisThoughtSnapshot]
    public let recentSignals: [JarvisSignalSnapshot]
    public let homeKitBridge: JarvisHomeKitBridgeStatus?
    public let obsidianVault: JarvisObsidianVaultStatus?
    public let nodeRegistry: [JarvisNodeHeartbeat]
    public let guiIntents: [JarvisGUIIntent]
    public let rustDeskNodes: [JarvisRustDeskNode]
    public let voiceGate: JarvisVoiceGateSnapshot?
    public let spatialHUD: [JarvisSpatialHUDElement]

    public init(
        hostName: String,
        statusLine: String,
        indexedSkillCount: Int,
        callableSkillCount: Int,
        voiceSampleCount: Int,
        tunnelState: JarvisConnectionState,
        activeWorkflow: String,
        lastMutation: String,
        recentThoughts: [JarvisThoughtSnapshot],
        recentSignals: [JarvisSignalSnapshot],
        homeKitBridge: JarvisHomeKitBridgeStatus? = nil,
        obsidianVault: JarvisObsidianVaultStatus? = nil,
        nodeRegistry: [JarvisNodeHeartbeat] = [],
        guiIntents: [JarvisGUIIntent] = [],
        rustDeskNodes: [JarvisRustDeskNode] = [],
        voiceGate: JarvisVoiceGateSnapshot? = nil,
        spatialHUD: [JarvisSpatialHUDElement] = []
    ) {
        self.hostName = hostName
        self.statusLine = statusLine
        self.indexedSkillCount = indexedSkillCount
        self.callableSkillCount = callableSkillCount
        self.voiceSampleCount = voiceSampleCount
        self.tunnelState = tunnelState
        self.activeWorkflow = activeWorkflow
        self.lastMutation = lastMutation
        self.recentThoughts = recentThoughts
        self.recentSignals = recentSignals
        self.homeKitBridge = homeKitBridge
        self.obsidianVault = obsidianVault
        self.nodeRegistry = nodeRegistry
        self.guiIntents = guiIntents
        self.rustDeskNodes = rustDeskNodes
        self.voiceGate = voiceGate
        self.spatialHUD = spatialHUD
    }
}

public struct JarvisTunnelResponse: Codable, Sendable {
    public let action: JarvisRemoteAction
    public let spokenText: String
    public let snapshot: JarvisHostSnapshot?
    public let payloadJSON: String?
    public let outputPath: String?

    public init(action: JarvisRemoteAction, spokenText: String, snapshot: JarvisHostSnapshot? = nil, payloadJSON: String? = nil, outputPath: String? = nil) {
        self.action = action
        self.spokenText = spokenText
        self.snapshot = snapshot
        self.payloadJSON = payloadJSON
        self.outputPath = outputPath
    }
}

public struct JarvisSharedState: Codable, Sendable {
    public let snapshot: JarvisHostSnapshot?
    public let thoughts: [JarvisThoughtSnapshot]
    public let signals: [JarvisSignalSnapshot]
    public let pendingPushDirectives: [JarvisPushDirective]
    public let homeKitBridge: JarvisHomeKitBridgeStatus?
    public let obsidianVault: JarvisObsidianVaultStatus?
    public let nodeRegistry: [JarvisNodeHeartbeat]
    public let guiIntents: [JarvisGUIIntent]
    public let rustDeskNodes: [JarvisRustDeskNode]

    public init(
        snapshot: JarvisHostSnapshot?,
        thoughts: [JarvisThoughtSnapshot],
        signals: [JarvisSignalSnapshot],
        pendingPushDirectives: [JarvisPushDirective],
        homeKitBridge: JarvisHomeKitBridgeStatus? = nil,
        obsidianVault: JarvisObsidianVaultStatus? = nil,
        nodeRegistry: [JarvisNodeHeartbeat] = [],
        guiIntents: [JarvisGUIIntent] = [],
        rustDeskNodes: [JarvisRustDeskNode] = []
    ) {
        self.snapshot = snapshot
        self.thoughts = thoughts
        self.signals = signals
        self.pendingPushDirectives = pendingPushDirectives
        self.homeKitBridge = homeKitBridge
        self.obsidianVault = obsidianVault
        self.nodeRegistry = nodeRegistry
        self.guiIntents = guiIntents
        self.rustDeskNodes = rustDeskNodes
    }
}

public struct JarvisTunnelMessage: Codable, Sendable {
    public let kind: JarvisTunnelMessageKind
    public let registration: JarvisClientRegistration?
    public let command: JarvisRemoteCommand?
    public let snapshot: JarvisHostSnapshot?
    public let response: JarvisTunnelResponse?
    public let push: JarvisPushDirective?
    public let error: String?

    public init(
        kind: JarvisTunnelMessageKind,
        registration: JarvisClientRegistration? = nil,
        command: JarvisRemoteCommand? = nil,
        snapshot: JarvisHostSnapshot? = nil,
        response: JarvisTunnelResponse? = nil,
        push: JarvisPushDirective? = nil,
        error: String? = nil
    ) {
        self.kind = kind
        self.registration = registration
        self.command = command
        self.snapshot = snapshot
        self.response = response
        self.push = push
        self.error = error
    }
}

public struct JarvisTransportPacket: Codable, Sendable {
    public let origin: String
    public let timestamp: String
    public let payload: String

    public init(origin: String, timestamp: String, payload: String) {
        self.origin = origin
        self.timestamp = timestamp
        self.payload = payload
    }
}

// MARK: - Spatial HUD (Stark workshop / GMRI holographic surface)
//
// The cockpit is NOT a DOM. The Mac host is the truth-physics authority and
// publishes a typed scene-state stream over the tunnel. Renderers (Unity,
// RealityKit / AVP, Quest 3, glasses) consume `JarvisHostSnapshot.spatialHUD`
// and project each element into space according to its `anchor`. State colour
// drives the holographic shader (Iron Man wireframe palette).
//
// This file owns the data contract only. No rendering logic lives here.

// MARK: GMRI canonical palette
//
// GrizzlyMedicine Research Institute / Stark workshop holographic palette.
// Renderers MUST source colour from here — no per-renderer guesses.
//
//   Emerald Green — primary, healthy, approved
//   Silver        — attention / neutral / degraded
//   Black         — absent / offline / hologram base
//   Crimson       — refusal / failure / hard stop
//
// Crest: Clan Munro tartan inside a stone bezel, grizzly head on shield.
// Lineage claimed: Munro / Am Freiceadan Dubh (the Black Watch, 42nd
// Highlanders) — "Hell's Ladies" / Ladies from Hell. The crest is canon;
// renderers should pull `crestAssetName` and not substitute.

public enum JarvisGMRIPalette {
    public static let emeraldGreenHex = "#00A86B"
    public static let silverHex       = "#C0C0C0"
    public static let blackHex        = "#0A0A0A"
    public static let crimsonHex      = "#DC143C"
}

public enum JarvisGMRIBrand {
    public static let instituteName     = "GrizzlyMedicine Research Institute"
    public static let shortName         = "GMRI"
    public static let crestAssetName    = "gmri-crest"
    public static let crestResourcePath = "Brand/gmri-crest.png"
    public static let lineage           = "Clan Munro · Am Freiceadan Dubh (42nd Highlanders) · Hell's Ladies"
    public static let tartan            = "Munro"
}

public enum JarvisSpatialIndicatorState: String, Codable, Sendable, CaseIterable {
    case green
    case yellow
    case orange
    case red
    case grey

    /// Canonical GMRI palette hex for this indicator state.
    public var paletteHex: String {
        switch self {
        case .green:           return JarvisGMRIPalette.emeraldGreenHex
        case .yellow, .orange: return JarvisGMRIPalette.silverHex
        case .red:             return JarvisGMRIPalette.crimsonHex
        case .grey:            return JarvisGMRIPalette.blackHex
        }
    }
}

public enum JarvisSpatialAnchor: String, Codable, Sendable, CaseIterable {
    case headLocked = "head_locked"
    case worldFixed = "world_fixed"
    case workshopBench = "workshop_bench"
    case orbiter
}

public struct JarvisSpatialHUDElement: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let label: String
    public let state: JarvisSpatialIndicatorState
    public let anchor: JarvisSpatialAnchor
    public let glyph: String
    public let detail: String?
    public let lastUpdatedISO8601: String

    public init(
        id: String,
        kind: String,
        label: String,
        state: JarvisSpatialIndicatorState,
        anchor: JarvisSpatialAnchor = .headLocked,
        glyph: String,
        detail: String? = nil,
        lastUpdatedISO8601: String
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.state = state
        self.anchor = anchor
        self.glyph = glyph
        self.detail = detail
        self.lastUpdatedISO8601 = lastUpdatedISO8601
    }
}

public struct JarvisVoiceGateSnapshot: Codable, Sendable {
    public let state: JarvisSpatialIndicatorState
    public let stateName: String
    public let composite: String?
    public let modelRepository: String?
    public let personaFramingVersion: String?
    public let approvedAtISO8601: String?
    public let operatorLabel: String?
    public let notes: String?
    public let lastSyncISO8601: String

    public init(
        state: JarvisSpatialIndicatorState,
        stateName: String,
        composite: String? = nil,
        modelRepository: String? = nil,
        personaFramingVersion: String? = nil,
        approvedAtISO8601: String? = nil,
        operatorLabel: String? = nil,
        notes: String? = nil,
        lastSyncISO8601: String
    ) {
        self.state = state
        self.stateName = stateName
        self.composite = composite
        self.modelRepository = modelRepository
        self.personaFramingVersion = personaFramingVersion
        self.approvedAtISO8601 = approvedAtISO8601
        self.operatorLabel = operatorLabel
        self.notes = notes
        self.lastSyncISO8601 = lastSyncISO8601
    }
}
