import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

const now = () => new Date().toISOString();

const id = (prefix: string) => `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;

export const heartbeatDevice = mutation({
  args: {
    deviceId: v.string(),
    label: v.string(),
    kind: v.union(
      v.literal("mac"),
      v.literal("ipad"),
      v.literal("iphone"),
      v.literal("jarvis"),
      v.literal("web"),
      v.literal("other"),
    ),
    app: v.string(),
    currentVault: v.optional(v.string()),
    currentFile: v.optional(v.string()),
    selection: v.optional(v.string()),
    status: v.optional(v.union(v.literal("online"), v.literal("idle"), v.literal("offline"))),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("devices")
      .withIndex("by_device", (q) => q.eq("deviceId", args.deviceId))
      .unique();
    const payload = {
      deviceId: args.deviceId,
      label: args.label,
      kind: args.kind,
      app: args.app,
      currentVault: args.currentVault,
      currentFile: args.currentFile,
      selection: args.selection,
      status: args.status ?? "online",
      lastSeen: now(),
    };
    if (existing) {
      await ctx.db.patch(existing._id, payload);
      return existing._id;
    }
    return await ctx.db.insert("devices", payload);
  },
});

export const updateVaultSync = mutation({
  args: {
    vaultId: v.string(),
    label: v.string(),
    nextcloudPath: v.string(),
    status: v.union(v.literal("ready"), v.literal("syncing"), v.literal("degraded"), v.literal("blocked")),
    noteCount: v.optional(v.number()),
    statusLine: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("vaults")
      .withIndex("by_vault", (q) => q.eq("vaultId", args.vaultId))
      .unique();
    const payload = { ...args, lastSync: now() };
    if (existing) {
      await ctx.db.patch(existing._id, payload);
      return existing._id;
    }
    return await ctx.db.insert("vaults", payload);
  },
});

export const queueCommand = mutation({
  args: {
    sourceDeviceId: v.string(),
    target: v.union(
      v.literal("jarvis"),
      v.literal("mac"),
      v.literal("ipad"),
      v.literal("iphone"),
      v.literal("nextcloud"),
      v.literal("human"),
    ),
    action: v.string(),
    payloadJSON: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const commandId = id("cmd");
    const docId = await ctx.db.insert("commandQueue", {
      commandId,
      sourceDeviceId: args.sourceDeviceId,
      target: args.target,
      action: args.action,
      payloadJSON: args.payloadJSON,
      status: "pending",
      createdAt: now(),
    });
    return { commandId, docId };
  },
});

export const claimNextCommand = mutation({
  args: {
    target: v.union(
      v.literal("jarvis"),
      v.literal("mac"),
      v.literal("ipad"),
      v.literal("iphone"),
      v.literal("nextcloud"),
      v.literal("human"),
    ),
  },
  handler: async (ctx, args) => {
    const command = await ctx.db
      .query("commandQueue")
      .withIndex("by_target_status", (q) => q.eq("target", args.target).eq("status", "pending"))
      .order("asc")
      .first();
    if (!command) {
      return null;
    }
    await ctx.db.patch(command._id, { status: "claimed", claimedAt: now() });
    return { ...command, status: "claimed", claimedAt: now() };
  },
});

export const completeCommand = mutation({
  args: {
    commandId: v.string(),
    status: v.union(v.literal("completed"), v.literal("failed"), v.literal("cancelled")),
    result: v.optional(v.string()),
    error: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const command = await ctx.db
      .query("commandQueue")
      .withIndex("by_command", (q) => q.eq("commandId", args.commandId))
      .unique();
    if (!command) {
      return { ok: false, error: "command not found" };
    }
    await ctx.db.patch(command._id, {
      status: args.status,
      result: args.result,
      error: args.error,
      completedAt: now(),
    });
    return { ok: true };
  },
});

export const placeTask = mutation({
  args: {
    title: v.string(),
    source: v.string(),
    targetLane: v.union(
      v.literal("obsidian"),
      v.literal("jarvis"),
      v.literal("echo"),
      v.literal("alpha"),
      v.literal("delta"),
      v.literal("gcp"),
      v.literal("quest"),
      v.literal("maker_shop"),
      v.literal("xcode_cloud"),
      v.literal("human"),
    ),
    rationale: v.string(),
    status: v.optional(v.union(v.literal("candidate"), v.literal("accepted"), v.literal("active"), v.literal("done"), v.literal("blocked"))),
  },
  handler: async (ctx, args) => {
    const timestamp = now();
    const placementId = id("place");
    const docId = await ctx.db.insert("taskPlacements", {
      placementId,
      title: args.title,
      source: args.source,
      targetLane: args.targetLane,
      rationale: args.rationale,
      status: args.status ?? "candidate",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    return { placementId, docId };
  },
});

export const recordEvent = mutation({
  args: {
    source: v.string(),
    kind: v.string(),
    summary: v.string(),
    payloadJSON: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const eventId = id("event");
    const docId = await ctx.db.insert("events", {
      eventId,
      source: args.source,
      kind: args.kind,
      summary: args.summary,
      payloadJSON: args.payloadJSON,
      createdAt: now(),
    });
    return { eventId, docId };
  },
});

export const dashboard = query({
  args: {
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 25;
    const [devices, vaults, pendingCommands, placements, events] = await Promise.all([
      ctx.db.query("devices").withIndex("by_seen").order("desc").take(limit),
      ctx.db.query("vaults").withIndex("by_sync").order("desc").take(limit),
      ctx.db.query("commandQueue").withIndex("by_status", (q) => q.eq("status", "pending")).take(limit),
      ctx.db.query("taskPlacements").withIndex("by_created").order("desc").take(limit),
      ctx.db.query("events").withIndex("by_created").order("desc").take(limit),
    ]);
    return { devices, vaults, pendingCommands, placements, events };
  },
});
