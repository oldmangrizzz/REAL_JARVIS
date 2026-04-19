import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const recordNodeHeartbeat = mutation({
  args: {
    nodeName: v.string(),
    address: v.optional(v.string()),
    source: v.string(),
    tunnelState: v.string(),
    guiReachable: v.boolean(),
    rustDeskID: v.optional(v.string()),
    lastSeen: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("node_registry")
      .withIndex("by_node", (q) => q.eq("nodeName", args.nodeName))
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, args);
      return existing._id;
    }

    return await ctx.db.insert("node_registry", args);
  },
});

export const listNodeHeartbeats = query({
  args: {
    limit: v.number(),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("node_registry")
      .withIndex("by_seen")
      .order("desc")
      .take(args.limit);
  },
});
