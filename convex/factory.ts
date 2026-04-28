import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// ─────────────────────────────────────────────────────────────────────────────
// TASK MANAGEMENT
// ─────────────────────────────────────────────────────────────────────────────

export const createTask = mutation({
  args: {
    taskId: v.string(),
    title: v.string(),
    description: v.optional(v.string()),
    projectType: v.optional(v.string()),
    priority: v.number(),
    effort: v.optional(v.string()),
    tags: v.array(v.string()),
    blockedBy: v.optional(v.array(v.string())),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();
    const docId = await ctx.db.insert("factory_tasks", {
      taskId: args.taskId,
      title: args.title,
      description: args.description,
      projectType: args.projectType || "Custom",
      status: "backlog",
      priority: args.priority,
      effort: args.effort || "Medium",
      assignedLane: undefined,
      attemptCount: 0,
      maxAttempts: 3,
      tags: args.tags,
      blockedBy: args.blockedBy,
      createdAt: now,
      claimedAt: undefined,
      completedAt: undefined,
    });
    return { success: true, docId };
  },
});

export const claimTask = mutation({
  args: {
    agentId: v.string(),
    laneType: v.string(),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();

    // Find highest-priority unclaimed task
    const available = await ctx.db
      .query("factory_tasks")
      .withIndex("by_status", q => q.eq("status", "backlog"))
      .order("desc")
      .collect();

    if (!available.length) {
      return { success: false, taskId: null, reason: "no_tasks_available" };
    }

    const task = available[0];
    await ctx.db.patch(task._id, {
      status: "claimed",
      assignedLane: args.laneType,
      claimedAt: now,
    });

    return {
      success: true,
      taskId: task.taskId,
      title: task.title,
      tags: task.tags,
    };
  },
});

export const listTasksByStatus = query({
  args: { status: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("factory_tasks")
      .withIndex("by_status", q => q.eq("status", args.status as any))
      .collect();
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// EXECUTION RUNS
// ─────────────────────────────────────────────────────────────────────────────

export const logRun = mutation({
  args: {
    runId: v.string(),
    taskId: v.string(),
    agentId: v.string(),
    laneType: v.string(),
    status: v.union(v.literal("running"), v.literal("success"), v.literal("error")),
    logOutput: v.optional(v.string()),
    errorMessage: v.optional(v.string()),
    errorCategory: v.optional(v.union(
      v.literal("transient"),
      v.literal("permanent"),
      v.literal("timeout"),
    )),
    result: v.optional(v.string()),
    durationMs: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();
    const startedAt = now;

    const docId = await ctx.db.insert("factory_runs", {
      runId: args.runId,
      taskId: args.taskId,
      agentId: args.agentId,
      laneType: args.laneType,
      status: args.status,
      logOutput: args.logOutput,
      errorMessage: args.errorMessage,
      errorCategory: args.errorCategory,
      result: args.result,
      startedAt,
      completedAt: args.status !== "running" ? now : undefined,
      durationMs: args.durationMs || 0,
    });

    // Update task status
    const allTasks = await ctx.db.query("factory_tasks").collect();
    const task = allTasks.find(t => t.taskId === args.taskId);

    if (task) {
      console.log(`[logRun] Found task ${args.taskId} with status ${task.status}, updating to ${args.status}`);
      if (args.status === "success") {
        console.log(`[logRun] Patching task ${task._id} to completed`);
        await ctx.db.patch(task._id, {
          status: "completed",
          completedAt: now,
        });
      } else if (args.status === "error") {
        const newCount = task.attemptCount + 1;
        if (newCount >= task.maxAttempts) {
          console.log(`[logRun] Patching task ${task._id} to failed`);
          await ctx.db.patch(task._id, {
            status: "failed",
            attemptCount: newCount,
          });
        } else {
          console.log(`[logRun] Patching task ${task._id} to backlog`);
          await ctx.db.patch(task._id, {
            status: "backlog",
            assignedLane: undefined,
            claimedAt: undefined,
            attemptCount: newCount,
          });
        }
      }
    } else {
      console.log(`[logRun] Task ${args.taskId} not found in database!`);
    }

    return { success: true, docId };
  },
});

export const getRunsByTask = query({
  args: { taskId: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("factory_runs")
      .withIndex("by_task", q => q.eq("taskId", args.taskId))
      .order("desc")
      .collect();
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// AGENT HEARTBEATS & LIVENESS
// ─────────────────────────────────────────────────────────────────────────────

export const heartbeat = mutation({
  args: {
    agentId: v.string(),
    laneType: v.string(),
    status: v.union(
      v.literal("alive"),
      v.literal("idle"),
      v.literal("stalled"),
      v.literal("dead"),
    ),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();

    // Find existing or create new heartbeat
    const existing = await ctx.db
      .query("agent_heartbeats")
      .withIndex("by_agent", q => q.eq("agentId", args.agentId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        status: args.status,
        lastHeartbeat: now,
      });
    } else {
      await ctx.db.insert("agent_heartbeats", {
        agentId: args.agentId,
        laneType: args.laneType,
        status: args.status,
        lastHeartbeat: now,
        lastTaskId: undefined,
        errorCount: 0,
        successCount: 0,
      });
    }

    return { success: true };
  },
});

export const detectStalledAgents = query({
  args: { stalledThresholdMs: v.number() },
  handler: async (ctx, args) => {
    const now = Date.now();
    const allHeartbeats = await ctx.db.query("agent_heartbeats").collect();

    const stalled = allHeartbeats.filter(hb => {
      const lastBeat = new Date(hb.lastHeartbeat).getTime();
      return now - lastBeat > args.stalledThresholdMs;
    });

    return stalled.map(s => ({
      agentId: s.agentId,
      laneType: s.laneType,
      lastHeartbeat: s.lastHeartbeat,
    }));
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// RECOVERY: AUTO-REASSIGN STALLED TASKS
// ─────────────────────────────────────────────────────────────────────────────

export const autoRecoverStalledTasks = mutation({
  args: { stalledThresholdMs: v.number() },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();
    const recovered: string[] = [];

    // Find agents that haven't heartbeated in threshold
    const stalledAgents = await ctx.db
      .query("agent_heartbeats")
      .collect()
      .then(hbs => {
        const now = Date.now();
        return hbs.filter(hb => {
          const lastBeat = new Date(hb.lastHeartbeat).getTime();
          return now - lastBeat > args.stalledThresholdMs;
        });
      });

    // For each stalled agent, find claimed tasks and reassign
    for (const agent of stalledAgents) {
      const claimedTasks = await ctx.db
        .query("factory_tasks")
        .withIndex("by_status", q => q.eq("status", "claimed"))
        .filter(t => t.assignedLane === agent.laneType)
        .collect();

      for (const task of claimedTasks) {
        const newCount = task.attemptCount + 1;
        if (newCount < task.maxAttempts) {
          await ctx.db.patch(task._id, {
            status: "backlog",
            assignedLane: undefined,
            claimedAt: undefined,
            attemptCount: newCount,
          });
          recovered.push(task.taskId);
        } else {
          await ctx.db.patch(task._id, {
            status: "failed",
            attemptCount: newCount,
          });
        }
      }

      // Mark agent as dead
      await ctx.db.patch(agent._id, { status: "dead" });
    }

    return { success: true, recoveredTasks: recovered };
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// PHEROMONE FIELD
// ─────────────────────────────────────────────────────────────────────────────

export const updatePheromone = mutation({
  args: {
    laneName: v.string(),
    capabilityTag: v.string(),
    intensity: v.number(),
    urgency: v.union(
      v.literal("deferred"),
      v.literal("normal"),
      v.literal("urgent"),
      v.literal("critical"),
    ),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();
    const existing = await ctx.db
      .query("pheromone_field")
      .withIndex("by_lane", q => q.eq("laneName", args.laneName))
      .filter(p => p.capabilityTag === args.capabilityTag)
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        intensity: args.intensity,
        urgency: args.urgency,
        updatedAt: now,
      });
    } else {
      await ctx.db.insert("pheromone_field", {
        laneName: args.laneName,
        capabilityTag: args.capabilityTag,
        intensity: args.intensity,
        urgency: args.urgency,
        decayFactor: 0.95,
        updatedAt: now,
      });
    }

    return { success: true };
  },
});

export const queryPheromoneGradient = query({
  args: { laneName: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("pheromone_field")
      .withIndex("by_lane", q => q.eq("laneName", args.laneName))
      .collect();
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// FACTORY STATUS SNAPSHOT
// ─────────────────────────────────────────────────────────────────────────────

export const getFactoryStatus = query({
  handler: async (ctx) => {
    const allTasks = await ctx.db.query("factory_tasks").collect();
    const allHeartbeats = await ctx.db.query("agent_heartbeats").collect();

    const taskCounts = {
      backlog: allTasks.filter(t => t.status === "backlog").length,
      claimed: allTasks.filter(t => t.status === "claimed").length,
      executing: allTasks.filter(t => t.status === "executing").length,
      completed: allTasks.filter(t => t.status === "completed").length,
      stalled: allTasks.filter(t => t.status === "stalled").length,
      failed: allTasks.filter(t => t.status === "failed").length,
    };

    const agentStatus = allHeartbeats.map(hb => ({
      agentId: hb.agentId,
      laneType: hb.laneType,
      status: hb.status,
      lastHeartbeat: hb.lastHeartbeat,
      successCount: hb.successCount,
      errorCount: hb.errorCount,
    }));

    return {
      timestamp: new Date().toISOString(),
      taskCounts,
      agentStatus,
      totalTasks: allTasks.length,
      totalAgents: allHeartbeats.length,
    };
  },
});

export const getAllTasks = query({
  handler: async (ctx) => {
    const tasks = await ctx.db.query("factory_tasks").collect();
    return tasks.map(t => ({
      _id: t._id,
      taskId: t.taskId,
      status: t.status,
      priority: t.priority,
      assignedLane: t.assignedLane,
      projectType: t.projectType,
      effort: t.effort,
      createdAt: t.createdAt,
      claimedBy: t.claimedBy,
      completedAt: t.completedAt,
    }));
  },
});
export const queueCommand = mutation({
  args: {
    type: v.union(v.literal("agent-message"), v.literal("file-upload"), v.literal("file-download"), v.literal("query")),
    agentId: v.optional(v.string()),
    message: v.optional(v.string()),
    filePath: v.optional(v.string()),
    fileContent: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const commandId = `cmd-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
    const now = new Date().toISOString();

    const docId = await ctx.db.insert("commandQueue", {
      commandId,
      type: args.type,
      agentId: args.agentId,
      message: args.message,
      filePath: args.filePath,
      fileContent: args.fileContent,
      status: "pending",
      createdAt: now,
    });

    return { commandId, docId };
  },
});

export const getPendingCommands = query({
  handler: async (ctx) => {
    return await ctx.db
      .query("commandQueue")
      .withIndex("by_status", q => q.eq("status", "pending"))
      .collect();
  },
});

export const completeCommand = mutation({
  args: {
    commandId: v.string(),
    result: v.optional(v.string()),
    error: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const commands = await ctx.db.query("commandQueue").collect();
    const cmd = commands.find(c => c.commandId === args.commandId);

    if (cmd) {
      await ctx.db.patch(cmd._id, {
        status: args.error ? "failed" : "completed",
        result: args.result,
        error: args.error,
        completedAt: new Date().toISOString(),
      });
    }

    return { success: !!cmd };
  },
});

export const getCommandHistory = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("commandQueue")
      .withIndex("by_createdAt", q => q.gte("createdAt", ""))
      .order("desc")
      .take(args.limit || 50);
  },
});
