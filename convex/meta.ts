import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// ─────────────────────────────────────────────────────────────────────────────
// IDEA INGESTION & SPECIFICATION
// ─────────────────────────────────────────────────────────────────────────────

export const submitIdea = mutation({
  args: {
    ideaTitle: v.string(),
    ideaDescription: v.string(),
    ideaSource: v.union(v.literal("text"), v.literal("voice"), v.literal("video")),
    tags: v.optional(v.array(v.string())),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();
    const ideaId = `idea-${Date.now()}`;

    const docId = await ctx.db.insert("factory_ideas", {
      ideaId,
      title: args.ideaTitle,
      description: args.ideaDescription,
      source: args.ideaSource,
      tags: args.tags || [],
      status: "submitted",
      specId: undefined,
      createdAt: now,
      specGeneratedAt: undefined,
      approvedAt: undefined,
      approvalNotes: undefined,
    });

    return {
      success: true,
      ideaId,
      nextStep: "awaiting_spec_generation",
    };
  },
});

export const getIdeas = query({
  args: { status: v.optional(v.string()) },
  handler: async (ctx, args) => {
    if (args.status) {
      return await ctx.db
        .query("factory_ideas")
        .withIndex("by_status", q => q.eq("status", args.status as any))
        .order("desc")
        .collect();
    }
    return await ctx.db.query("factory_ideas").order("desc").collect();
  },
});

export const recordSpecGeneration = mutation({
  args: {
    ideaId: v.string(),
    specId: v.string(),
    specContent: v.string(),
    estimatedEffort: v.string(),
    blockers: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();

    // Find idea using index
    const idea = await ctx.db
      .query("factory_ideas")
      .withIndex("by_idea", q => q.eq("ideaId", args.ideaId))
      .first();

    if (!idea) {
      return { success: false, error: "idea_not_found" };
    }

    // Update idea
    await ctx.db.patch(idea._id, {
      specId: args.specId,
      status: "spec_generated",
      specGeneratedAt: now,
    });

    // Create spec record
    await ctx.db.insert("factory_specs", {
      specId: args.specId,
      ideaId: args.ideaId,
      content: args.specContent,
      estimatedEffort: args.estimatedEffort,
      blockers: args.blockers,
      status: "pending_approval",
      createdAt: now,
      approvedAt: undefined,
    });

    return {
      success: true,
      specId: args.specId,
      nextStep: "awaiting_operator_approval",
    };
  },
});

export const getSpecById = query({
  args: { specId: v.string() },
  handler: async (ctx, args) => {
    const spec = await ctx.db
      .query("factory_specs")
      .withIndex("by_spec", q => q.eq("specId", args.specId))
      .first();
    return spec;
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// OPERATOR APPROVAL GATE
// ─────────────────────────────────────────────────────────────────────────────

function parseTasksFromSpec(specContent: string, ideaTitle: string): Array<{
  title: string;
  description: string;
  priority: number;
  tags: string[];
  estimatedLaneType: string;
  blockedBy?: string[];
}> {
  const tasks: Array<{
    title: string;
    description: string;
    priority: number;
    tags: string[];
    estimatedLaneType: string;
    blockedBy?: string[];
  }> = [];

  // Parse markdown task list: - [ ] Task title | priority: N | lane: Lane | tags: #tag1
  const taskRegex = /[-*]\s*\[[ x]\]\s\*\*(.+?)\*\*[\s\S]*?(?=\n[-*]\s*\[[ x]\]|```|\n##|\n$)/g;
  const lines = specContent.split('\n');
  let currentTask: {
    title: string;
    description: string;
    priority: number;
    tags: string[];
    estimatedLaneType: string;
    blockedBy?: string[];
  } | null = null;

  for (const line of lines) {
    const trimmed = line.trim();
    // Task item: - [ ] **Title** or - [x] **Title**
    const taskMatch = trimmed.match(/^[-*]\s*\[[ x]\]\s\*\*(.+?)\*\*[^\n]*$/);
    if (taskMatch) {
      if (currentTask) tasks.push(currentTask);
      currentTask = {
        title: taskMatch[1].trim(),
        description: '',
        priority: 50,
        tags: [],
        estimatedLaneType: 'Executor',
      };
    } else if (currentTask) {
      // Priority: p100/p75/p50/p25
      const priMatch = trimmed.match(/priority:\s*(p?\d+)/i);
      if (priMatch) currentTask.priority = parseInt(priMatch[1].replace('p', '')) || 50;
      // Lane: lane:Executor/Planner/Verifier
      const laneMatch = trimmed.match(/lane:\s*(Planner|Executor|Verifier|Scribe)/i);
      if (laneMatch) currentTask.estimatedLaneType = laneMatch[1];
      // Tags: tags:#tag1 #tag2
      const tagsMatch = trimmed.match(/tags:\s*(#[\w-]+(?:\s+#[\w-]+)*)/i);
      if (tagsMatch) currentTask.tags = tagsMatch[1].split(/\s+/).map(t => t.replace(/^#/, ''));
      // Blocked by: blocked:task-id
      const blockedMatch = trimmed.match(/blocked:\s*([\w-]+)/i);
      if (blockedMatch) currentTask.blockedBy = [blockedMatch[1]];
      // Continuation description
      if (!trimmed.startsWith('//') && !trimmed.startsWith('**') && !trimmed.startsWith('>') && trimmed.length > 0) {
        currentTask.description += (currentTask.description ? '\n' : '') + trimmed;
      }
    }
  }
  if (currentTask) tasks.push(currentTask);

  // Fallback: if no tasks parsed, create one task from the spec title
  if (tasks.length === 0) {
    tasks.push({
      title: ideaTitle,
      description: specContent.substring(0, 500),
      priority: 50,
      tags: [],
      estimatedLaneType: 'Executor',
    });
  }

  return tasks;
}

export const approveSpec = mutation({
  args: {
    specId: v.string(),
    operatorApproval: v.union(v.literal("approved"), v.literal("rejected")),
    approvalNotes: v.optional(v.string()),
    tasks: v.optional(v.array(v.object({
      title: v.string(),
      description: v.string(),
      priority: v.number(),
      tags: v.array(v.string()),
      estimatedLaneType: v.string(),
      blockedBy: v.optional(v.array(v.string())),
    }))),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();

    const spec = await ctx.db
      .query("factory_specs")
      .withIndex("by_spec", q => q.eq("specId", args.specId))
      .first();

    if (!spec) {
      return { success: false, error: "spec_not_found" };
    }

    // Get idea for title
    const idea = await ctx.db
      .query("factory_ideas")
      .filter(i => i.ideaId === spec.ideaId)
      .first();

    const approved = args.operatorApproval === "approved";

    await ctx.db.patch(spec._id, {
      status: approved ? "approved" : "rejected",
      approvedAt: now,
    });

    if (idea) {
      await ctx.db.patch(idea._id, {
        status: approved ? "approved" : "rejected",
        approvalNotes: args.approvalNotes,
        approvedAt: now,
      });
    }

    // Auto-decompose approved spec into tasks
    if (approved) {
      const tasksToCreate = args.tasks || parseTasksFromSpec(spec.content, idea?.title || spec.specId);
      const now2 = new Date().toISOString();
      const createdTaskIds: string[] = [];

      for (const taskInput of tasksToCreate) {
        const taskId = `task-${spec.specId}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
        await ctx.db.insert("factory_tasks", {
          taskId,
          title: taskInput.title,
          description: taskInput.description,
          status: "backlog",
          priority: taskInput.priority,
          assignedLane: undefined,
          attemptCount: 0,
          maxAttempts: 3,
          tags: taskInput.tags,
          blockedBy: taskInput.blockedBy,
          createdAt: now2,
          claimedAt: undefined,
          completedAt: undefined,
        });
        createdTaskIds.push(taskId);
      }

      await ctx.db.patch(spec._id, { status: "tasks_created" });

      return {
        success: true,
        tasksCreated: createdTaskIds.length,
        taskIds: createdTaskIds,
        nextStep: "tasks_queued",
      };
    }

    return { success: true, nextStep: "rejected" };
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// TASK DECOMPOSITION & ROUTING
// ─────────────────────────────────────────────────────────────────────────────

export const decomposeSpecToTasks = mutation({
  args: {
    specId: v.string(),
    tasks: v.array(v.object({
      title: v.string(),
      description: v.string(),
      priority: v.number(),
      tags: v.array(v.string()),
      estimatedLaneType: v.string(),
      blockedBy: v.optional(v.array(v.string())),
    })),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();
    const createdTaskIds: string[] = [];

    // Get spec
    const spec = await ctx.db
      .query("factory_specs")
      .withIndex("by_spec", q => q.eq("specId", args.specId))
      .first();

    if (!spec) {
      return { success: false, error: "spec_not_found" };
    }

    // Create tasks
    for (const taskInput of args.tasks) {
      const taskId = `task-${args.specId}-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;

      await ctx.db.insert("factory_tasks", {
        taskId,
        title: taskInput.title,
        description: taskInput.description,
        status: "backlog",
        priority: taskInput.priority,
        assignedLane: undefined,
        attemptCount: 0,
        maxAttempts: 3,
        tags: taskInput.tags,
        blockedBy: taskInput.blockedBy,
        createdAt: now,
        claimedAt: undefined,
        completedAt: undefined,
      });

      createdTaskIds.push(taskId);
    }

    // Update spec
    await ctx.db.patch(spec._id, {
      status: "tasks_created",
    });

    return {
      success: true,
      taskCount: createdTaskIds.length,
      taskIds: createdTaskIds,
      nextStep: "tasks_queued_ready_for_execution",
    };
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// PROJECT TRACKING
// ─────────────────────────────────────────────────────────────────────────────

export const createProject = mutation({
  args: {
    projectName: v.string(),
    description: v.string(),
    ideaIds: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();
    const projectId = `project-${Date.now()}`;

    const docId = await ctx.db.insert("factory_projects", {
      projectId,
      name: args.projectName,
      description: args.description,
      ideaIds: args.ideaIds,
      status: "planning",
      createdAt: now,
      completedAt: undefined,
    });

    return { success: true, projectId };
  },
});

export const getProjectStatus = query({
  args: { projectId: v.string() },
  handler: async (ctx, args) => {
    const project = await ctx.db
      .query("factory_projects")
      .filter(p => p.projectId === args.projectId)
      .first();

    if (!project) return null;

    // Get all tasks for this project's ideas
    const allTasks = await ctx.db.query("factory_tasks").collect();

    const taskStatus = {
      backlog: allTasks.filter(t => t.status === "backlog").length,
      claimed: allTasks.filter(t => t.status === "claimed").length,
      executing: allTasks.filter(t => t.status === "executing").length,
      completed: allTasks.filter(t => t.status === "completed").length,
      failed: allTasks.filter(t => t.status === "failed").length,
    };

    return { project, taskStatus };
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// QUERIES — previously missing from deployed backend
// ─────────────────────────────────────────────────────────────────────────────

export const getPendingSpecs = query({
  handler: async (ctx) => {
    return await ctx.db
      .query("factory_specs")
      .withIndex("by_status", q => q.eq("status", "pending_approval"))
      .collect();
  },
});

export const getHeartbeats = query({
  handler: async (ctx) => {
    const all = await ctx.db.query("agent_heartbeats").collect();
    return all.map(hb => ({
      agentId: hb.agentId,
      laneType: hb.laneType,
      status: hb.status,
      lastHeartbeat: hb.lastHeartbeat,
      lastTaskId: hb.lastTaskId,
      successCount: hb.successCount,
      errorCount: hb.errorCount,
    }));
  },
});
