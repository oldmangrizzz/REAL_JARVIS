import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

export const recent = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;
    return await ctx.db.query("activity").withIndex("by_time").order("desc").take(limit);
  },
});

export const log = mutation({
  args: {
    actorId: v.union(v.id("agents"), v.id("operators")),
    actorName: v.string(),
    actorRole: v.string(),
    verb: v.string(),
    targetKind: v.optional(v.string()),
    targetId: v.optional(v.string()),
    summary: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("activity", { ...args, createdAt: Date.now() });
  },
});