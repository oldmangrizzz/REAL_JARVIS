import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const logStigmergicSignal = mutation({
  args: {
    nodeSource: v.string(),
    nodeTarget: v.string(),
    ternaryValue: v.union(v.literal(-1), v.literal(0), v.literal(1)),
    agentId: v.string(),
    pheromone: v.float64(),
    timestamp: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("stigmergic_signals", args);
  },
});

export const logRecursiveThought = mutation({
  args: {
    sessionId: v.string(),
    thoughtTrace: v.array(v.string()),
    memoryPageFault: v.boolean(),
    timestamp: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("recursive_thoughts", args);
  },
});

export const logHarnessMutation = mutation({
  args: {
    versionId: v.string(),
    workflowId: v.string(),
    diffPatch: v.string(),
    evaluationScore: v.float64(),
    rollbackHash: v.string(),
    timestamp: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("harness_mutations", args);
  },
});

export const logVagalTone = mutation({
  args: {
    sourceNode: v.string(),
    value: v.float64(),
    state: v.string(),
    timestamp: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("vagal_tone", args);
  },
});

export const syncHomeKitBridge = mutation({
  args: {
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
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("homekit_bridge_status")
      .withIndex("by_bridge", (q) => q.eq("bridgeName", args.bridgeName))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, args);
      return existing._id;
    }
    return await ctx.db.insert("homekit_bridge_status", args);
  },
});

export const upsertObsidianVaultState = mutation({
  args: {
    databaseName: v.string(),
    betaCouchEndpoint: v.string(),
    docCount: v.float64(),
    replicationConfigured: v.boolean(),
    replicationObserved: v.boolean(),
    reseedTriggered: v.boolean(),
    pluginListening: v.boolean(),
    lastSync: v.string(),
    statusLine: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("obsidian_vault")
      .withIndex("by_database", (q) => q.eq("databaseName", args.databaseName))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, args);
      return existing._id;
    }
    return await ctx.db.insert("obsidian_vault", args);
  },
});

export const queueGuiIntent = mutation({
  args: {
    intentId: v.string(),
    sourceNode: v.string(),
    targetNodes: v.array(v.string()),
    action: v.string(),
    payloadJSON: v.optional(v.string()),
    queuedAt: v.string(),
    status: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("gui_intents", args);
  },
});

export const syncRustDeskRegistry = mutation({
  args: {
    nodeName: v.string(),
    rustDeskID: v.optional(v.string()),
    address: v.optional(v.string()),
    relayLocked: v.boolean(),
    lastSeen: v.string(),
    handoffURL: v.optional(v.string()),
    status: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("rustdesk_registry")
      .withIndex("by_node", (q) => q.eq("nodeName", args.nodeName))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, args);
      return existing._id;
    }
    return await ctx.db.insert("rustdesk_registry", args);
  },
});

export const registerMobileDevice = mutation({
  args: {
    deviceId: v.string(),
    deviceName: v.string(),
    platform: v.string(),
    role: v.string(),
    appVersion: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("mobile_devices")
      .withIndex("by_device", (q) => q.eq("deviceId", args.deviceId))
      .unique();

    const payload = {
      ...args,
      tunnelState: "connecting",
      pushToken: undefined,
      lastSeen: new Date().toISOString(),
    };

    if (existing) {
      await ctx.db.patch(existing._id, payload);
      return existing._id;
    }
    return await ctx.db.insert("mobile_devices", payload);
  },
});

export const recordMobileHeartbeat = mutation({
  args: {
    deviceId: v.string(),
    tunnelState: v.string(),
    pushToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("mobile_devices")
      .withIndex("by_device", (q) => q.eq("deviceId", args.deviceId))
      .unique();

    if (!existing) {
      return await ctx.db.insert("mobile_devices", {
        deviceId: args.deviceId,
        deviceName: args.deviceId,
        platform: "unknown",
        role: "unknown",
        appVersion: "unknown",
        tunnelState: args.tunnelState,
        pushToken: args.pushToken,
        lastSeen: new Date().toISOString(),
      });
    }

    await ctx.db.patch(existing._id, {
      tunnelState: args.tunnelState,
      pushToken: args.pushToken,
      lastSeen: new Date().toISOString(),
    });
    return existing._id;
  },
});

export const syncVoiceGateState = mutation({
  args: {
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
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("voice_gate_state")
      .withIndex("by_host", (q) => q.eq("hostNode", args.hostNode))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, args);
      return existing._id;
    }
    return await ctx.db.insert("voice_gate_state", args);
  },
});

export const logVoiceGateEvent = mutation({
  args: {
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
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("voice_gate_events", args);
  },
});

export const currentVoiceGateState = query({
  args: { hostNode: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("voice_gate_state")
      .withIndex("by_host", (q) => q.eq("hostNode", args.hostNode))
      .unique();
  },
});

export const recentVoiceGateEvents = query({
  args: { hostNode: v.string(), limit: v.number() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("voice_gate_events")
      .withIndex("by_timestamp")
      .order("desc")
      .filter((q) => q.eq(q.field("hostNode"), args.hostNode))
      .take(args.limit);
  },
});

export const logPushDirective = mutation({
  args: {
    deviceId: v.string(),
    directiveId: v.string(),
    title: v.string(),
    body: v.string(),
    startupLine: v.string(),
    requiresSpeech: v.boolean(),
    timestamp: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("push_directives", args);
  },
});

export const sharedMobileState = query({
  args: {
    limit: v.number(),
  },
  handler: async (ctx, args) => {
    const [thoughts, signals, pushes, devices, homeKit, vault, nodeRegistry, guiIntents, rustdesk, voiceGate, voiceGateEvents] = await Promise.all([
      ctx.db.query("recursive_thoughts").withIndex("by_timestamp").order("desc").take(args.limit),
      ctx.db.query("stigmergic_signals").withIndex("by_timestamp").order("desc").take(args.limit),
      ctx.db.query("push_directives").withIndex("by_timestamp").order("desc").take(args.limit),
      ctx.db.query("mobile_devices").collect(),
      ctx.db.query("homekit_bridge_status").withIndex("by_sync").order("desc").take(1),
      ctx.db.query("obsidian_vault").withIndex("by_sync").order("desc").take(1),
      ctx.db.query("node_registry").withIndex("by_seen").order("desc").take(args.limit),
      ctx.db.query("gui_intents").withIndex("by_status").collect(),
      ctx.db.query("rustdesk_registry").collect(),
      ctx.db.query("voice_gate_state").withIndex("by_sync").order("desc").take(1),
      ctx.db.query("voice_gate_events").withIndex("by_timestamp").order("desc").take(args.limit),
    ]);

    const mappedThoughts = thoughts.map((thought) => ({
      id: thought._id,
      sessionID: thought.sessionId,
      trace: thought.thoughtTrace,
      memoryPageFault: thought.memoryPageFault,
      timestamp: thought.timestamp,
      sourceDeviceID: undefined,
    }));

    const mappedSignals = signals.map((signal) => ({
      id: signal._id,
      nodeSource: signal.nodeSource,
      nodeTarget: signal.nodeTarget,
      ternaryValue: signal.ternaryValue,
      agentID: signal.agentId,
      pheromone: signal.pheromone,
      timestamp: signal.timestamp,
    }));

    const mappedPushes = pushes.map((push) => ({
      id: push.directiveId,
      title: push.title,
      body: push.body,
      startupLine: push.startupLine,
      requiresSpeech: push.requiresSpeech,
      timestamp: push.timestamp,
    }));

    const mappedHomeKit = homeKit[0]
      ? {
          bridgeName: homeKit[0].bridgeName,
          charlieAddress: homeKit[0].charlieAddress,
          homebridgePort: homeKit[0].homebridgePort,
          reachable: homeKit[0].reachable,
          matterEnabled: homeKit[0].matterEnabled,
          voiceIntercomRoute: homeKit[0].voiceIntercomRoute,
          authorizedCommandSources: homeKit[0].authorizedCommandSources,
          regulationVisibility: homeKit[0].regulationVisibility,
          distressState: homeKit[0].distressState,
          bridgeState: homeKit[0].bridgeState,
          accessories: [],
          lastSync: homeKit[0].lastSync,
        }
      : null;

    const mappedVault = vault[0]
      ? {
          databaseName: vault[0].databaseName,
          betaCouchEndpoint: vault[0].betaCouchEndpoint,
          docCount: vault[0].docCount,
          replicationConfigured: vault[0].replicationConfigured,
          replicationObserved: vault[0].replicationObserved,
          reseedTriggered: vault[0].reseedTriggered,
          pluginListening: vault[0].pluginListening,
          lastSync: vault[0].lastSync,
          statusLine: vault[0].statusLine,
        }
      : null;

    const mappedNodeRegistry = nodeRegistry.map((node) => ({
      id: node.nodeName,
      nodeName: node.nodeName,
      address: node.address,
      source: node.source,
      tunnelState: node.tunnelState,
      guiReachable: node.guiReachable,
      rustDeskID: node.rustDeskID,
      lastSeen: node.lastSeen,
    }));

    const mappedGuiIntents = guiIntents
      .slice(0, args.limit)
      .map((intent) => ({
        id: intent.intentId,
        sourceNode: intent.sourceNode,
        targetNodes: intent.targetNodes,
        action: intent.action,
        payloadJSON: intent.payloadJSON,
        queuedAt: intent.queuedAt,
        status: intent.status,
      }));

    const mappedRustDesk = rustdesk.map((node) => ({
      id: node.nodeName,
      nodeName: node.nodeName,
      rustDeskID: node.rustDeskID,
      address: node.address,
      relayLocked: node.relayLocked,
      lastSeen: node.lastSeen,
      handoffURL: node.handoffURL,
      status: node.status,
    }));

    const mappedVoiceGate = voiceGate[0]
      ? {
          hostNode: voiceGate[0].hostNode,
          state: voiceGate[0].state,
          composite: voiceGate[0].composite,
          expectedComposite: voiceGate[0].expectedComposite,
          referenceAudioDigest: voiceGate[0].referenceAudioDigest,
          referenceTranscriptDigest: voiceGate[0].referenceTranscriptDigest,
          modelRepository: voiceGate[0].modelRepository,
          personaFramingVersion: voiceGate[0].personaFramingVersion,
          operatorLabel: voiceGate[0].operatorLabel,
          approvedAtISO8601: voiceGate[0].approvedAtISO8601,
          notes: voiceGate[0].notes,
          lastSync: voiceGate[0].lastSync,
        }
      : null;

    const mappedVoiceGateEvents = voiceGateEvents.map((event) => ({
      id: event._id,
      hostNode: event.hostNode,
      eventType: event.eventType,
      composite: event.composite,
      expectedComposite: event.expectedComposite,
      operatorLabel: event.operatorLabel,
      notes: event.notes,
      timestamp: event.timestamp,
    }));

    return {
      snapshot: {
        hostName: "Convex Mirror",
        statusLine: `Convex mirrored ${mappedThoughts.length} recursive traces and ${mappedSignals.length} stigmergic signals across ${devices.length} mobile devices.`,
        indexedSkillCount: 0,
        callableSkillCount: 0,
        voiceSampleCount: 0,
        tunnelState: "online",
        activeWorkflow: "jarvis-default",
        lastMutation: pushes[0]?.timestamp ?? "No proactive directive recorded.",
        recentThoughts: mappedThoughts,
        recentSignals: mappedSignals,
        homeKitBridge: mappedHomeKit,
        obsidianVault: mappedVault,
        nodeRegistry: mappedNodeRegistry,
        guiIntents: mappedGuiIntents,
        rustDeskNodes: mappedRustDesk,
        voiceGate: mappedVoiceGate,
        voiceGateEvents: mappedVoiceGateEvents,
      },
      thoughts: mappedThoughts,
      signals: mappedSignals,
      pendingPushDirectives: mappedPushes,
      homeKitBridge: mappedHomeKit,
      obsidianVault: mappedVault,
      nodeRegistry: mappedNodeRegistry,
      guiIntents: mappedGuiIntents,
      rustDeskNodes: mappedRustDesk,
      voiceGate: mappedVoiceGate,
      voiceGateEvents: mappedVoiceGateEvents,
    };
  },
});
