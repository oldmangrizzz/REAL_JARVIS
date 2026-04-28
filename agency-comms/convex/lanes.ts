import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

export const list = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("lanes").withIndex("by_ordinal").collect();
  },
});

export const create = mutation({
  args: {
    name: v.string(),
    slug: v.string(),
    ordinal: v.number(),
    color: v.string(),
    icon: v.string(),
    description: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("lanes", args);
  },
});

export const seed = mutation({
  args: {},
  handler: async (ctx) => {
    const existing = await ctx.db.query("lanes").first();
    if (existing) return "already_seeded";

    const lanes = [
      { name: "Intake", slug: "intake", ordinal: 0, color: "#3b82f6", icon: "Inbox", description: "New tasks awaiting triage" },
      { name: "Active", slug: "active", ordinal: 1, color: "#f59e0b", icon: "Zap", description: "Tasks in active development" },
      { name: "Executing", slug: "executing", ordinal: 2, color: "#ef4444", icon: "Play", description: "Tasks under execution — voice channel live" },
      { name: "Monitoring", slug: "monitoring", ordinal: 3, color: "#8b5cf6", icon: "Eye", description: "Tasks under observation — awaiting verification" },
      { name: "Resolved", slug: "resolved", ordinal: 4, color: "#10b981", icon: "CheckCircle", description: "Completed and verified tasks" },
    ];

    for (const lane of lanes) {
      await ctx.db.insert("lanes", lane);
    }
    return "seeded";
  },
});