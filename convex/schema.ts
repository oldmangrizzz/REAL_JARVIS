import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  execution_traces: defineTable({
    workflowId: v.string(),
    stepId: v.string(),
    inputContext: v.string(),
    outputResult: v.string(),
    status: v.union(v.literal("success"), v.literal("failure"), v.literal("pending")),
    timestamp: v.string(),
  }).index("by_workflow_step", ["workflowId", "stepId"]),

  stigmergic_signals: defineTable({
    nodeSource: v.string(),
    nodeTarget: v.string(),
    ternaryValue: v.union(v.literal(-1), v.literal(0), v.literal(1)),
    agentId: v.string(),
    pheromone: v.float64(),
    timestamp: v.string(),
  })
    .index("by_edge", ["nodeSource", "nodeTarget"])
    .index("by_agent", ["agentId"])
    .index("by_timestamp", ["timestamp"]),

  recursive_thoughts: defineTable({
    sessionId: v.string(),
    thoughtTrace: v.array(v.string()),
    memoryPageFault: v.boolean(),
    timestamp: v.string(),
  })
    .index("by_session", ["sessionId"])
    .index("by_timestamp", ["timestamp"]),

  harness_mutations: defineTable({
    versionId: v.string(),
    workflowId: v.string(),
    diffPatch: v.string(),
    evaluationScore: v.float64(),
    rollbackHash: v.string(),
    timestamp: v.string(),
  })
    .index("by_version", ["versionId"])
    .index("by_workflow", ["workflowId"]),

  mobile_devices: defineTable({
    deviceId: v.string(),
    deviceName: v.string(),
    platform: v.string(),
    role: v.string(),
    appVersion: v.string(),
    tunnelState: v.string(),
    pushToken: v.optional(v.string()),
    lastSeen: v.string(),
  })
    .index("by_device", ["deviceId"])
    .index("by_role", ["role"]),

  push_directives: defineTable({
    deviceId: v.string(),
    directiveId: v.string(),
    title: v.string(),
    body: v.string(),
    startupLine: v.string(),
    requiresSpeech: v.boolean(),
    timestamp: v.string(),
  })
    .index("by_device", ["deviceId"])
    .index("by_timestamp", ["timestamp"]),

  vagal_tone: defineTable({
    sourceNode: v.string(),
    value: v.float64(),
    state: v.string(),
    timestamp: v.string(),
  })
    .index("by_source", ["sourceNode"])
    .index("by_timestamp", ["timestamp"]),

  homekit_bridge_status: defineTable({
    bridgeName: v.string(),
    charlieAddress: v.string(),
    homebridgePort: v.float64(),
    reachable: v.boolean(),
    matterEnabled: v.boolean(),
    voiceIntercomRoute: v.string(),
    authorizedCommandSources: v.array(v.string()),
    regulationVisibility: v.string(),
    distressState: v.string(),
    bridgeState: v.string(),
    lastSync: v.string(),
  })
    .index("by_bridge", ["bridgeName"])
    .index("by_sync", ["lastSync"]),

  obsidian_vault: defineTable({
    databaseName: v.string(),
    betaCouchEndpoint: v.string(),
    docCount: v.float64(),
    replicationConfigured: v.boolean(),
    replicationObserved: v.boolean(),
    reseedTriggered: v.boolean(),
    pluginListening: v.boolean(),
    lastSync: v.string(),
    statusLine: v.string(),
  })
    .index("by_database", ["databaseName"])
    .index("by_sync", ["lastSync"]),

  gui_intents: defineTable({
    intentId: v.string(),
    sourceNode: v.string(),
    targetNodes: v.array(v.string()),
    action: v.string(),
    payloadJSON: v.optional(v.string()),
    queuedAt: v.string(),
    status: v.string(),
  })
    .index("by_source", ["sourceNode"])
    .index("by_status", ["status"]),

  node_registry: defineTable({
    nodeName: v.string(),
    address: v.optional(v.string()),
    source: v.string(),
    tunnelState: v.string(),
    guiReachable: v.boolean(),
    rustDeskID: v.optional(v.string()),
    lastSeen: v.string(),
  })
    .index("by_node", ["nodeName"])
    .index("by_seen", ["lastSeen"]),

  rustdesk_registry: defineTable({
    nodeName: v.string(),
    rustDeskID: v.optional(v.string()),
    address: v.optional(v.string()),
    relayLocked: v.boolean(),
    lastSeen: v.string(),
    handoffURL: v.optional(v.string()),
    status: v.string(),
  })
    .index("by_node", ["nodeName"])
    .index("by_status", ["status"]),

  // Latest known state of the voice approval gate per host node.
  // Singleton-per-host: patched on every state change so the cockpit can
  // show "green / red / drifted" without scanning event history.
  // The gate file itself (`<storageRoot>/voice/approval.json`) remains the
  // local source of truth; this table is observability only.
  voice_gate_state: defineTable({
    hostNode: v.string(),
    state: v.union(
      v.literal("green"),
      v.literal("revoked"),
      v.literal("drifted"),
      v.literal("malformed"),
      v.literal("absent"),
    ),
    composite: v.optional(v.string()),
    expectedComposite: v.optional(v.string()),
    referenceAudioDigest: v.optional(v.string()),
    referenceTranscriptDigest: v.optional(v.string()),
    modelRepository: v.optional(v.string()),
    personaFramingVersion: v.optional(v.string()),
    operatorLabel: v.optional(v.string()),
    approvedAtISO8601: v.optional(v.string()),
    notes: v.optional(v.string()),
    lastSync: v.string(),
  })
    .index("by_host", ["hostNode"])
    .index("by_sync", ["lastSync"]),

  // Append-only audit log of every gate transition. Never mutated.
  // Drives forensic review of "when did the voice change and who approved it."
  voice_gate_events: defineTable({
    hostNode: v.string(),
    eventType: v.union(
      v.literal("approved"),
      v.literal("revoked"),
      v.literal("drift_detected"),
      v.literal("playback_refused"),
      v.literal("malformed_gate_file"),
    ),
    composite: v.optional(v.string()),
    expectedComposite: v.optional(v.string()),
    operatorLabel: v.optional(v.string()),
    notes: v.optional(v.string()),
    timestamp: v.string(),
  })
    .index("by_host", ["hostNode"])
    .index("by_timestamp", ["timestamp"])
    .index("by_event_type", ["eventType"]),

  // ─── Dark Factory ───────────────────────────────────────────────────────────

  factory_tasks: defineTable({
    taskId: v.string(),
    title: v.string(),
    description: v.optional(v.string()),
    status: v.string(),
    priority: v.number(),
    assignedLane: v.optional(v.string()),
    attemptCount: v.number(),
    maxAttempts: v.number(),
    tags: v.array(v.string()),
    blockedBy: v.optional(v.array(v.string())),
    createdAt: v.string(),
    claimedAt: v.optional(v.string()),
    completedAt: v.optional(v.string()),
    projectType: v.optional(v.string()),
    effort: v.optional(v.string()),
  })
    .index("by_status", ["status"])
    .index("by_priority", ["priority"])
    .index("by_lane", ["assignedLane"])
    .index("by_created", ["createdAt"]),

  factory_runs: defineTable({
    runId: v.string(),
    taskId: v.string(),
    agentId: v.string(),
    laneType: v.string(),
    status: v.string(),
    logOutput: v.optional(v.string()),
    errorMessage: v.optional(v.string()),
    errorCategory: v.optional(v.string()),
    result: v.optional(v.string()),
    startedAt: v.string(),
    completedAt: v.optional(v.string()),
    durationMs: v.number(),
  })
    .index("by_task", ["taskId"])
    .index("by_agent", ["agentId"])
    .index("by_status", ["status"]),

  factory_ideas: defineTable({
    ideaId: v.string(),
    title: v.string(),
    description: v.string(),
    source: v.string(),
    tags: v.array(v.string()),
    status: v.string(),
    specId: v.optional(v.string()),
    createdAt: v.string(),
    specGeneratedAt: v.optional(v.string()),
    approvedAt: v.optional(v.string()),
    approvalNotes: v.optional(v.string()),
  })
    .index("by_status", ["status"])
    .index("by_created", ["createdAt"])
    .index("by_idea", ["ideaId"]),

  factory_specs: defineTable({
    specId: v.string(),
    ideaId: v.string(),
    content: v.string(),
    estimatedEffort: v.string(),
    blockers: v.array(v.string()),
    status: v.string(),
    createdAt: v.string(),
    approvedAt: v.optional(v.string()),
  })
    .index("by_status", ["status"])
    .index("by_idea", ["ideaId"])
    .index("by_spec", ["specId"]),

  factory_projects: defineTable({
    projectId: v.string(),
    name: v.string(),
    description: v.string(),
    ideaIds: v.array(v.string()),
    status: v.string(),
    createdAt: v.string(),
    completedAt: v.optional(v.string()),
  })
    .index("by_status", ["status"]),

  agent_heartbeats: defineTable({
    agentId: v.string(),
    laneType: v.string(),
    status: v.string(),
    lastHeartbeat: v.string(),
    lastTaskId: v.optional(v.string()),
    successCount: v.number(),
    errorCount: v.number(),
  })
    .index("by_agent", ["agentId"])
    .index("by_status", ["status"]),

  pheromone_field: defineTable({
    laneName: v.string(),
    capabilityTag: v.string(),
    intensity: v.number(),
    urgency: v.string(),
    decayFactor: v.number(),
    updatedAt: v.string(),
  })
    .index("by_lane", ["laneName"])
    .index("by_tag", ["capabilityTag"]),

  // ─── IDE Backend ─────────────────────────────────────────────────────────────

  ideCommandQueue: defineTable({
    commandId: v.string(),
    type: v.string(),
    payload: v.string(),
    status: v.string(),
    output: v.optional(v.string()),
    error: v.optional(v.string()),
    exitCode: v.optional(v.number()),
    executionTimeMs: v.optional(v.number()),
    createdAt: v.string(),
    startedAt: v.optional(v.string()),
    completedAt: v.optional(v.string()),
    agentId: v.optional(v.string()),
  })
    .index("by_status", ["status"])
    .index("by_createdAt", ["createdAt"]),

  fileCache: defineTable({
    path: v.string(),
    content: v.string(),
    size: v.number(),
    mimeType: v.string(),
    lastModified: v.string(),
    hash: v.string(),
  })
    .index("by_path", ["path"]),

  secretsVault: defineTable({
    key: v.string(),
    value: v.string(),
    scope: v.string(),
    createdAt: v.string(),
  })
    .index("by_key", ["key"]),

  buildArtifacts: defineTable({
    buildId: v.string(),
    type: v.string(),
    path: v.string(),
    size: v.number(),
    hash: v.string(),
    metadata: v.optional(v.string()),
    createdAt: v.string(),
  })
    .index("by_buildId", ["buildId"]),

  executionLogs: defineTable({
    commandId: v.string(),
    line: v.number(),
    level: v.string(),
    text: v.string(),
    timestamp: v.string(),
  })
    .index("by_commandId", ["commandId"]),
});
