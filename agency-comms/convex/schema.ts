import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  lanes: defineTable({
    name: v.string(),
    slug: v.string(),
    ordinal: v.number(),
    color: v.string(),
    icon: v.string(),
    description: v.string(),
  }).index("by_ordinal", ["ordinal"]),

  cards: defineTable({
    laneId: v.id("lanes"),
    title: v.string(),
    body: v.optional(v.string()),
    priority: v.union(
      v.literal("routine"),
      v.literal("priority"),
      v.literal("immediate"),
    ),
    status: v.union(
      v.literal("intake"),
      v.literal("active"),
      v.literal("executing"),
      v.literal("monitoring"),
      v.literal("resolved"),
    ),
    assigneeId: v.optional(v.id("agents")),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
    locationLabel: v.optional(v.string()),
    tags: v.optional(v.array(v.string())),
    dueAt: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_lane", ["laneId"]),

  messages: defineTable({
    cardId: v.optional(v.id("cards")),
    laneId: v.optional(v.id("lanes")),
    channelId: v.optional(v.string()),
    authorId: v.union(v.id("agents"), v.id("operators")),
    authorName: v.string(),
    authorRole: v.string(),
    body: v.string(),
    kind: v.union(
      v.literal("text"),
      v.literal("status"),
      v.literal("alert"),
      v.literal("checkin"),
      v.literal("handoff"),
    ),
    metadata: v.optional(v.any()),
    createdAt: v.number(),
  }).index("by_card", ["cardId"]).index("by_lane", ["laneId"]).index("by_channel", ["channelId"]),

  agents: defineTable({
    callsign: v.string(),
    harness: v.string(),
    model: v.optional(v.string()),
    capabilities: v.optional(v.array(v.string())),
    status: v.union(
      v.literal("online"),
      v.literal("idle"),
      v.literal("working"),
      v.literal("blocked"),
      v.literal("offline"),
    ),
    currentTaskId: v.optional(v.id("cards")),
    lastCheckin: v.number(),
    livekitIdentity: v.optional(v.string()),
  }),

  operators: defineTable({
    callsign: v.string(),
    name: v.string(),
    role: v.string(),
    status: v.union(
      v.literal("active"),
      v.literal("away"),
      v.literal("dnd"),
    ),
    lastSeen: v.number(),
  }),

  markers: defineTable({
    type: v.union(
      v.literal("poi"),
      v.literal("hazard"),
      v.literal("asset"),
      v.literal("agent"),
      v.literal("event"),
    ),
    label: v.string(),
    description: v.optional(v.string()),
    latitude: v.number(),
    longitude: v.number(),
    icon: v.optional(v.string()),
    color: v.optional(v.string()),
    cardId: v.optional(v.id("cards")),
    agentId: v.optional(v.id("agents")),
    expiresAt: v.optional(v.number()),
    createdAt: v.number(),
  }),

  activity: defineTable({
    actorId: v.union(v.id("agents"), v.id("operators")),
    actorName: v.string(),
    actorRole: v.string(),
    verb: v.string(),
    targetKind: v.optional(v.string()),
    targetId: v.optional(v.string()),
    summary: v.string(),
    createdAt: v.number(),
  }).index("by_time", ["createdAt"]),

});