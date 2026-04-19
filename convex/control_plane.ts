import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

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

export const sharedControlPlaneState = query({
  args: {
    limit: v.number(),
  },
  handler: async (ctx, args) => {
    const [homeKit, vault, nodes, intents, rustdesk] = await Promise.all([
      ctx.db.query("homekit_bridge_status").withIndex("by_sync").order("desc").take(1),
      ctx.db.query("obsidian_vault").withIndex("by_sync").order("desc").take(1),
      ctx.db.query("node_registry").withIndex("by_seen").order("desc").take(args.limit),
      ctx.db.query("gui_intents").withIndex("by_status").collect(),
      ctx.db.query("rustdesk_registry").collect(),
    ]);

    return {
      homeKitBridge: homeKit[0] ?? null,
      obsidianVault: vault[0] ?? null,
      nodeRegistry: nodes,
      guiIntents: intents.slice(0, args.limit),
      rustDeskNodes: rustdesk,
    };
  },
});
