import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  devices: defineTable({
    deviceId: v.string(),
    label: v.string(),
    kind: v.union(
      v.literal("mac"),
      v.literal("ipad"),
      v.literal("iphone"),
      v.literal("jarvis"),
      v.literal("web"),
      v.literal("other"),
    ),
    app: v.string(),
    currentVault: v.optional(v.string()),
    currentFile: v.optional(v.string()),
    selection: v.optional(v.string()),
    status: v.union(v.literal("online"), v.literal("idle"), v.literal("offline")),
    lastSeen: v.string(),
  })
    .index("by_device", ["deviceId"])
    .index("by_status", ["status"])
    .index("by_seen", ["lastSeen"]),

  vaults: defineTable({
    vaultId: v.string(),
    label: v.string(),
    nextcloudPath: v.string(),
    status: v.union(v.literal("ready"), v.literal("syncing"), v.literal("degraded"), v.literal("blocked")),
    lastSync: v.string(),
    noteCount: v.optional(v.number()),
    statusLine: v.string(),
  })
    .index("by_vault", ["vaultId"])
    .index("by_sync", ["lastSync"]),

  commandQueue: defineTable({
    commandId: v.string(),
    sourceDeviceId: v.string(),
    target: v.union(
      v.literal("jarvis"),
      v.literal("mac"),
      v.literal("ipad"),
      v.literal("iphone"),
      v.literal("nextcloud"),
      v.literal("human"),
    ),
    action: v.string(),
    payloadJSON: v.optional(v.string()),
    status: v.union(
      v.literal("pending"),
      v.literal("claimed"),
      v.literal("running"),
      v.literal("completed"),
      v.literal("failed"),
      v.literal("cancelled"),
    ),
    createdAt: v.string(),
    claimedAt: v.optional(v.string()),
    completedAt: v.optional(v.string()),
    result: v.optional(v.string()),
    error: v.optional(v.string()),
  })
    .index("by_command", ["commandId"])
    .index("by_status", ["status"])
    .index("by_target_status", ["target", "status"])
    .index("by_created", ["createdAt"]),

  taskPlacements: defineTable({
    placementId: v.string(),
    title: v.string(),
    source: v.string(),
    targetLane: v.union(
      v.literal("obsidian"),
      v.literal("jarvis"),
      v.literal("echo"),
      v.literal("alpha"),
      v.literal("delta"),
      v.literal("gcp"),
      v.literal("quest"),
      v.literal("maker_shop"),
      v.literal("xcode_cloud"),
      v.literal("human"),
    ),
    rationale: v.string(),
    status: v.union(v.literal("candidate"), v.literal("accepted"), v.literal("active"), v.literal("done"), v.literal("blocked")),
    createdAt: v.string(),
    updatedAt: v.string(),
  })
    .index("by_lane", ["targetLane"])
    .index("by_status", ["status"])
    .index("by_created", ["createdAt"]),

  events: defineTable({
    eventId: v.string(),
    source: v.string(),
    kind: v.string(),
    summary: v.string(),
    payloadJSON: v.optional(v.string()),
    createdAt: v.string(),
  })
    .index("by_source", ["source"])
    .index("by_kind", ["kind"])
    .index("by_created", ["createdAt"]),
});
