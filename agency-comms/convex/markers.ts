import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

export const list = query({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const all = await ctx.db.query("markers").collect();
    return all.filter((m) => !m.expiresAt || m.expiresAt > now);
  },
});

export const create = mutation({
  args: {
    type: v.union(v.literal("poi"), v.literal("hazard"), v.literal("asset"), v.literal("agent"), v.literal("event")),
    label: v.string(),
    description: v.optional(v.string()),
    latitude: v.number(),
    longitude: v.number(),
    icon: v.optional(v.string()),
    color: v.optional(v.string()),
    cardId: v.optional(v.id("cards")),
    agentId: v.optional(v.id("agents")),
    expiresAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("markers", { ...args, createdAt: Date.now() });
  },
});

export const remove = mutation({
  args: { id: v.id("markers") },
  handler: async (ctx, args) => {
    await ctx.db.delete(args.id);
  },
});

export const seed = mutation({
  args: {},
  handler: async (ctx) => {
    const existing = await ctx.db.query("markers").first();
    if (existing) return "already_seeded";

    const markers = [
      { type: "asset" as const, label: "Alpha — iMac 5K", description: "Proxmox node — 32GB RAM, 2TB HD", latitude: 32.7616, longitude: -97.3435, color: "#3b82f6" },
      { type: "asset" as const, label: "Echo — MacBook Air M2", description: "Primary operator workstation — 8GB", latitude: 32.7254, longitude: -97.3452, color: "#10b981" },
      { type: "asset" as const, label: "Charlie — VPS Docker", description: "Hostinger KVM2 — 8GB RAM, Docker host", latitude: 52.2297, longitude: 21.0122, color: "#f59e0b" },
      { type: "asset" as const, label: "Delta — VPS Kali", description: "Hostinger KVM4 — 16GB RAM, Kali Linux", latitude: 50.0647, longitude: 19.9450, color: "#ef4444" },
      { type: "hazard" as const, label: "Network boundary", description: "NAT traversal required for VPS access", latitude: 38.0, longitude: -95.0, color: "#ef4444" },
      { type: "event" as const, label: "GMRI HQ", description: "White Settlement, TX — Research institute", latitude: 32.7254, longitude: -97.3452, color: "#8b5cf6" },
      { type: "poi" as const, label: "JPS Health Network", description: "Nearest Level 1 Trauma — Fort Worth", latitude: 32.7555, longitude: -97.3308, color: "#ef4444" },
      { type: "asset" as const, label: "Beta — Dell Latitude 3189", description: "Proxmox node — 4GB RAM", latitude: 32.7580, longitude: -97.3460, color: "#3b82f6" },
      { type: "asset" as const, label: "Foxtrot — Dell Latitude E3550", description: "Proxmox node — 4GB RAM", latitude: 32.7585, longitude: -97.3465, color: "#3b82f6" },
    ];

    for (const m of markers) {
      await ctx.db.insert("markers", { ...m, createdAt: Date.now() });
    }
    return "seeded";
  },
});