import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

export const list = query({
  args: { laneId: v.optional(v.id("lanes")) },
  handler: async (ctx, args) => {
    if (args.laneId) {
      return await ctx.db
        .query("cards")
        .withIndex("by_lane", (q) => q.eq("laneId", args.laneId!))
        .collect();
    }
    return await ctx.db.query("cards").collect();
  },
});

export const get = query({
  args: { id: v.id("cards") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.id);
  },
});

export const create = mutation({
  args: {
    laneId: v.id("lanes"),
    title: v.string(),
    body: v.optional(v.string()),
    priority: v.union(v.literal("routine"), v.literal("priority"), v.literal("immediate")),
    status: v.union(v.literal("intake"), v.literal("active"), v.literal("executing"), v.literal("monitoring"), v.literal("resolved")),
    assigneeId: v.optional(v.id("agents")),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
    locationLabel: v.optional(v.string()),
    tags: v.optional(v.array(v.string())),
    dueAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    return await ctx.db.insert("cards", { ...args, createdAt: now, updatedAt: now });
  },
});

export const move = mutation({
  args: {
    id: v.id("cards"),
    laneId: v.id("lanes"),
    status: v.optional(v.union(v.literal("intake"), v.literal("active"), v.literal("executing"), v.literal("monitoring"), v.literal("resolved"))),
  },
  handler: async (ctx, args) => {
    const { id, laneId, status } = args;
    const patch: Record<string, any> = { laneId, updatedAt: Date.now() };
    if (status) patch.status = status;
    await ctx.db.patch(id, patch);
  },
});

export const update = mutation({
  args: {
    id: v.id("cards"),
    title: v.optional(v.string()),
    body: v.optional(v.string()),
    priority: v.optional(v.union(v.literal("routine"), v.literal("priority"), v.literal("immediate"))),
    assigneeId: v.optional(v.id("agents")),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
    locationLabel: v.optional(v.string()),
    tags: v.optional(v.array(v.string())),
    dueAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { id, ...rest } = args;
    const patch: Record<string, any> = { updatedAt: Date.now() };
    for (const [k, v] of Object.entries(rest)) {
      if (v !== undefined) patch[k] = v;
    }
    await ctx.db.patch(id, patch);
  },
});

export const seed = mutation({
  args: {},
  handler: async (ctx) => {
    const existing = await ctx.db.query("cards").first();
    if (existing) return "already_seeded";

    const lanes = await ctx.db.query("lanes").collect();
    const agents = await ctx.db.query("agents").collect();
    const laneMap = Object.fromEntries(lanes.map((l) => [l.slug, l._id]));
    const agentMap = Object.fromEntries(agents.map((a) => [a.callsign, a._id]));

    const cards = [
      {
        laneId: laneMap["intake"],
        title: "Recon: Proxmox cluster health audit",
        body: "Full health check across Alpha, Beta, Foxtrot nodes. Disk, memory, uptime, container status.",
        priority: "routine" as const,
        status: "intake" as const,
        latitude: 32.7616,
        longitude: -97.3435,
        locationLabel: "White Settlement, TX — Home Lab",
        tags: ["infra", "proxmox", "audit"],
        assigneeId: agentMap["CIC-OP"],
      },
      {
        laneId: laneMap["active"],
        title: "Build: Jarvis voice pipeline V2",
        body: "F5-TTS refactor complete. Wire LiveKit room per agent. Test latency to Charlie VPS.",
        priority: "priority" as const,
        status: "active" as const,
        latitude: 32.7254,
        longitude: -97.3452,
        locationLabel: "West Fort Worth — GMRI HQ",
        tags: ["voice", "livekit", "jarvis"],
        assigneeId: agentMap["HERMES-7"],
      },
      {
        laneId: laneMap["active"],
        title: "Deploy: Convex agency-comms schema",
        body: "Kanban + LiveKit signaling + agent bus deployed to fastidious-wolverine-481.convex.cloud",
        priority: "routine" as const,
        status: "active" as const,
        latitude: 37.7749,
        longitude: -122.4194,
        locationLabel: "Convex Cloud — us-west-2",
        tags: ["convex", "deploy", "agency"],
      },
      {
        laneId: laneMap["executing"],
        title: "HARDEN: SSH key rotation — Delta",
        body: "Kali node SSH keys past 90-day rotation window. Rotate and distribute new pubkeys to Alpha/Beta/Foxtrot.",
        priority: "immediate" as const,
        status: "executing" as const,
        latitude: 52.2297,
        longitude: 21.0122,
        locationLabel: "Warsaw, PL — Hostinger KVM4",
        tags: ["security", "ssh", "rotation"],
        assigneeId: agentMap["CIC-OP"],
      },
      {
        laneId: laneMap["monitoring"],
        title: "Monitor: Homebridge HA bridge",
        body: "HomeKit bridge flapped twice last week. Monitor for recurrence. Check mDNS responder on Alpha.",
        priority: "routine" as const,
        status: "monitoring" as const,
        latitude: 32.7616,
        longitude: -97.3435,
        locationLabel: "White Settlement, TX — Home Lab",
        tags: ["homekit", "monitoring", "alpha"],
      },
      {
        laneId: laneMap["resolved"],
        title: "COMPLETE: MCP fleet centralization",
        body: "Obsidian, Hostinger-SSH, macOS-remote, HomeAssistant, Convex, Mapbox wired across all 5 harnesses.",
        priority: "routine" as const,
        status: "resolved" as const,
        assigneeId: agentMap["OPUS-4"],
        tags: ["mcp", "infra", "complete"],
      },
    ];

    for (const card of cards) {
      if (!card.laneId) continue;
      const now = Date.now();
      await ctx.db.insert("cards", { ...card, createdAt: now - 86400000 * Math.random(), updatedAt: now });
    }
    return "seeded";
  },
});