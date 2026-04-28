import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

export const list = query({
  args: {
    cardId: v.optional(v.id("cards")),
    laneId: v.optional(v.id("lanes")),
    channelId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.cardId) {
      return await ctx.db
        .query("messages")
        .withIndex("by_card", (q) => q.eq("cardId", args.cardId!))
        .order("desc")
        .collect();
    }
    if (args.laneId) {
      return await ctx.db
        .query("messages")
        .withIndex("by_lane", (q) => q.eq("laneId", args.laneId!))
        .order("desc")
        .collect();
    }
    if (args.channelId) {
      return await ctx.db
        .query("messages")
        .withIndex("by_channel", (q) => q.eq("channelId", args.channelId!))
        .order("desc")
        .collect();
    }
    return await ctx.db.query("messages").order("desc").collect();
  },
});

export const send = mutation({
  args: {
    cardId: v.optional(v.id("cards")),
    laneId: v.optional(v.id("lanes")),
    channelId: v.optional(v.string()),
    authorId: v.union(v.id("agents"), v.id("operators")),
    authorName: v.string(),
    authorRole: v.string(),
    body: v.string(),
    kind: v.union(v.literal("text"), v.literal("status"), v.literal("alert"), v.literal("checkin"), v.literal("handoff")),
    metadata: v.optional(v.any()),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("messages", { ...args, createdAt: Date.now() });
  },
});

export const recent = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;
    return await ctx.db.query("messages").order("desc").take(limit);
  },
});