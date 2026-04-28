import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

export const list = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("agents").collect();
  },
});

export const get = query({
  args: { id: v.id("agents") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.id);
  },
});

export const create = mutation({
  args: {
    callsign: v.string(),
    harness: v.string(),
    model: v.optional(v.string()),
    capabilities: v.optional(v.array(v.string())),
    status: v.union(v.literal("online"), v.literal("idle"), v.literal("working"), v.literal("blocked"), v.literal("offline")),
    currentTaskId: v.optional(v.id("cards")),
    livekitIdentity: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("agents", { ...args, lastCheckin: Date.now() });
  },
});

export const checkin = mutation({
  args: {
    id: v.id("agents"),
    status: v.optional(v.union(v.literal("online"), v.literal("idle"), v.literal("working"), v.literal("blocked"), v.literal("offline"))),
    currentTaskId: v.optional(v.id("cards")),
  },
  handler: async (ctx, args) => {
    const { id, ...rest } = args;
    const patch: Record<string, any> = { lastCheckin: Date.now() };
    if (rest.status) patch.status = rest.status;
    if (rest.currentTaskId) patch.currentTaskId = rest.currentTaskId;
    await ctx.db.patch(id, patch);
  },
});

export const seed = mutation({
  args: {},
  handler: async (ctx) => {
    const existing = await ctx.db.query("agents").first();
    if (existing) return "already_seeded";

    const agents = [
      {
        callsign: "OPUS-4",
        harness: "claude-code",
        model: "claude-opus-4-7",
        capabilities: ["architecture", "code-review", "deep-analysis", "deployment"],
        status: "online" as const,
      },
      {
        callsign: "GEMMA-4",
        harness: "gemini-cli",
        model: "gemma-4-27b",
        capabilities: ["long-context", "research", "summarization", "multimodal"],
        status: "idle" as const,
      },
      {
        callsign: "QWEN-C",
        harness: "qwen-cli",
        model: "qwen3-coder",
        capabilities: ["execution", "cold-resume", "coding", "batch-ops"],
        status: "idle" as const,
      },
      {
        callsign: "CIC-OP",
        harness: "copilot-cli",
        model: "gpt-4.1",
        capabilities: ["forge", "delta-ops", "git-workflow", "refactoring"],
        status: "working" as const,
      },
      {
        callsign: "HERMES-7",
        harness: "hermes",
        model: "qwen3-coder-next",
        capabilities: ["orchestration", "delegation", "tts", "multi-model"],
        status: "online" as const,
      },
    ];

    for (const agent of agents) {
      await ctx.db.insert("agents", { ...agent, lastCheckin: Date.now() - Math.floor(Math.random() * 300000) });
    }

    await ctx.db.insert("operators", {
      callsign: "GRIZZ-0",
      name: "Robert Hanson",
      role: "Commander",
      status: "active",
      lastSeen: Date.now(),
    });

    return "seeded";
  },
});