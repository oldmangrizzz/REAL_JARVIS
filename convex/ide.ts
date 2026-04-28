import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

export const queueCommand = mutation({
  args: {
    type: v.string(),
    payload: v.string(),
    agentId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const commandId = `cmd-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
    const now = new Date().toISOString();

    const docId = await ctx.db.insert("ideCommandQueue", {
      commandId,
      type: args.type,
      payload: args.payload,
      status: "pending",
      agentId: args.agentId,
      createdAt: now,
    });

    return { commandId, docId };
  },
});

export const updateCommandStatus = mutation({
  args: {
    commandId: v.string(),
    status: v.string(),
    output: v.optional(v.string()),
    error: v.optional(v.string()),
    exitCode: v.optional(v.number()),
    executionTimeMs: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const commands = await ctx.db.query("ideCommandQueue").collect();
    const cmd = commands.find((c: any) => c.commandId === args.commandId);

    if (cmd) {
      await ctx.db.patch(cmd._id, {
        status: args.status,
        output: args.output,
        error: args.error,
        exitCode: args.exitCode,
        executionTimeMs: args.executionTimeMs,
        completedAt: args.status === "completed" || args.status === "failed" ? new Date().toISOString() : undefined,
        startedAt: args.status === "running" ? new Date().toISOString() : cmd.startedAt,
      });
    }

    return { success: !!cmd };
  },
});

export const cacheFile = mutation({
  args: {
    path: v.string(),
    content: v.string(),
    mimeType: v.string(),
  },
  handler: async (ctx, args) => {
    const hash = Buffer.from(args.content).toString("base64").slice(0, 16);

    const existing = await ctx.db
      .query("fileCache")
      .filter((f: any) => f.path === args.path)
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        content: args.content,
        size: args.content.length,
        hash,
        lastModified: new Date().toISOString(),
      });
    } else {
      await ctx.db.insert("fileCache", {
        path: args.path,
        content: args.content,
        size: args.content.length,
        mimeType: args.mimeType,
        hash,
        lastModified: new Date().toISOString(),
      });
    }

    return { path: args.path, size: args.content.length, hash };
  },
});

export const setSecret = mutation({
  args: {
    key: v.string(),
    value: v.string(),
    scope: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("secretsVault")
      .filter((s: any) => s.key === args.key)
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, { value: args.value });
    } else {
      await ctx.db.insert("secretsVault", {
        key: args.key,
        value: args.value,
        scope: args.scope,
        createdAt: new Date().toISOString(),
      });
    }

    return { key: args.key, stored: true };
  },
});

export const getPendingCommands = query({
  handler: async (ctx) => {
    return await ctx.db
      .query("ideCommandQueue")
      .withIndex("by_status", (q) => q.eq("status", "pending"))
      .collect();
  },
});

export const getCommandStatus = query({
  args: { commandId: v.string() },
  handler: async (ctx, args) => {
    const commands = await ctx.db.query("ideCommandQueue").collect();
    return commands.find((c: any) => c.commandId === args.commandId) || null;
  },
});

export const getCommandHistory = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("ideCommandQueue")
      .withIndex("by_createdAt", (q) => q.gte("createdAt", ""))
      .order("desc")
      .take(args.limit || 50);
  },
});

export const getExecutionLogs = query({
  args: { commandId: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("executionLogs")
      .filter((l: any) => l.commandId === args.commandId)
      .collect();
  },
});

export const getCachedFile = query({
  args: { path: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("fileCache")
      .filter((f: any) => f.path === args.path)
      .first() || null;
  },
});

export const listCachedFiles = query({
  handler: async (ctx) => {
    return await ctx.db.query("fileCache").collect();
  },
});

export const getSecret = query({
  args: { key: v.string() },
  handler: async (ctx, args) => {
    const secret = await ctx.db
      .query("secretsVault")
      .filter((s: any) => s.key === args.key)
      .first();

    return secret ? { key: secret.key, scope: secret.scope } : null;
  },
});
