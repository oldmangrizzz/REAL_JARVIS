import { defineSchema } from "convex/server";
import { v } from "convex/values";
import { mutation } from "./_generated/server";

export default defineSchema({
  ships: {
    fields: {
      version: v.string(),
      gitSha: v.string(),
      timestamp: v.float64(),
      smokeSummary: v.object({
        passed: v.int64(),
        failed: v.int64(),
        total: v.int64(),
      }),
      operator: v.string(),
      rolledBack: v.optional(v.boolean()),
      rollbackOperator: v.optional(v.string()),
    },
  },
});

export const record = mutation({
  args: {
    version: v.string(),
    gitSha: v.string(),
    timestamp: v.float64(),
    smokeSummary: v.object({
      passed: v.int64(),
      failed: v.int64(),
      total: v.int64(),
    }),
    operator: v.string(),
  },
  handler: async (ctx, args) => {
    await ctx.db.insert("ships", {
      version: args.version,
      gitSha: args.gitSha,
      timestamp: args.timestamp,
      smokeSummary: args.smokeSummary,
      operator: args.operator,
      rolledBack: false,
    });
  },
});

export const rollback = mutation({
  args: {
    shipId: v.id("ships"),
    operator: v.string(),
  },
  handler: async (ctx, args) => {
    const ship = await ctx.db.get(args.shipId);
    if (!ship) {
      throw new Error("Ship not found");
    }
    await ctx.db.patch(args.shipId, {
      rolledBack: true,
      rollbackOperator: args.operator,
    });
  },
});