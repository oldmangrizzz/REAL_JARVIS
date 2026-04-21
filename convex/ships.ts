import { defineTable } from "convex/server";
import { v } from "convex/values";
import { mutation } from "./_generated/server";

/**
 * Table storing successful deployment (ship) records.
 *
 * Fields:
 * - version: Human‑readable version string (e.g. "v2.3.1").
 * - gitSha: Full Git SHA of the commit that was shipped.
 * - timestamp: Epoch milliseconds when the ship completed.
 * - smokeSummary: Result of the unified smoke test runner.
 *   - passed: Boolean indicating overall success.
 *   - details: Optional free‑form text with failures or notes.
 * - operator: Identifier of the person or CI job that performed the ship.
 */
export const ships = defineTable({
  version: v.string(),
  gitSha: v.string(),
  timestamp: v.number(),
  smokeSummary: v.object({
    passed: v.boolean(),
    details: v.optional(v.string()),
  }),
  operator: v.string(),
});

/**
 * Table storing rollback events linked to a ship.
 *
 * Fields:
 * - shipId: Reference to the ship being rolled back.
 * - rolledBackAt: Epoch milliseconds when the rollback occurred.
 * - rolledBackBy: Identifier of the operator who initiated the rollback.
 * - reason: Optional free‑form explanation for the rollback.
 */
export const rollbacks = defineTable({
  shipId: v.id("ships"),
  rolledBackAt: v.number(),
  rolledBackBy: v.string(),
  reason: v.optional(v.string()),
});

/**
 * Record a new ship deployment.
 *
 * Strict validation is enforced by the argument schema.
 */
export const recordShip = mutation({
  args: {
    version: v.string(),
    gitSha: v.string(),
    timestamp: v.number(),
    smokeSummary: v.object({
      passed: v.boolean(),
      details: v.optional(v.string()),
    }),
    operator: v.string(),
  },
  handler: async (ctx, args) => {
    const shipId = await ctx.db.insert("ships", {
      version: args.version,
      gitSha: args.gitSha,
      timestamp: args.timestamp,
      smokeSummary: args.smokeSummary,
      operator: args.operator,
    });
    return shipId;
  },
});

/**
 * Record a rollback for a previously shipped deployment.
 *
 * Validates that the referenced ship exists before creating the rollback record.
 */
export const rollbackShip = mutation({
  args: {
    shipId: v.id("ships"),
    rolledBackBy: v.string(),
    reason: v.optional(v.string()),
    rolledBackAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    // Verify the ship exists
    const ship = await ctx.db.get(args.shipId);
    if (!ship) {
      throw new Error(`Ship record ${args.shipId} not found`);
    }

    const now = args.rolledBackAt ?? Date.now();

    const rollbackId = await ctx.db.insert("rollbacks", {
      shipId: args.shipId,
      rolledBackAt: now,
      rolledBackBy: args.rolledBackBy,
      reason: args.reason,
    });

    return rollbackId;
  },
});