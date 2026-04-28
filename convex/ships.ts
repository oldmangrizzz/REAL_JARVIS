import { v } from "convex/values";
import { mutation } from "./_generated/server";

export const record = mutation({
  args: {
    version: v.string(),
    gitSha: v.string(),
    timestamp: v.string(),
    log: v.optional(v.string()),
    operator: v.optional(v.string()),
    smokeSummary: v.optional(v.any()),
  },
  returns: v.id("ships"),
  handler: async (ctx, args) => {
    return await ctx.db.insert("ships", {
      version: args.version,
      gitSha: args.gitSha,
      timestamp: args.timestamp,
      log: args.log ?? null,
      operator: args.operator ?? null,
      smokeSummary: args.smokeSummary ?? null,
    });
  },
});
