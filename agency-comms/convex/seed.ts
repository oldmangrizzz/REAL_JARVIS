import { mutation } from "./_generated/server";

export const all = mutation({
  args: {},
  handler: async (ctx) => {
    // Check if already seeded
    const existing = await ctx.db.query("lanes").first();
    if (existing) return "already_seeded";

    // Seed lanes
    const lanes = [
      { name: "Intake", slug: "intake", ordinal: 0, color: "#3b82f6", icon: "Inbox", description: "New tasks awaiting triage" },
      { name: "Active", slug: "active", ordinal: 1, color: "#f59e0b", icon: "Zap", description: "Tasks in active development" },
      { name: "Executing", slug: "executing", ordinal: 2, color: "#ef4444", icon: "Play", description: "Tasks under execution — voice channel live" },
      { name: "Monitoring", slug: "monitoring", ordinal: 3, color: "#8b5cf6", icon: "Eye", description: "Tasks under observation — awaiting verification" },
      { name: "Resolved", slug: "resolved", ordinal: 4, color: "#10b981", icon: "CheckCircle", description: "Completed and verified tasks" },
    ];
    const laneIds: Record<string, any> = {};
    for (const lane of lanes) {
      laneIds[lane.slug] = await ctx.db.insert("lanes", lane);
    }

    // Seed agents
    const agents = [
      { callsign: "OPUS-4", harness: "claude-code", model: "claude-opus-4-7", capabilities: ["architecture", "code-review", "deep-analysis", "deployment"], status: "online" as const },
      { callsign: "GEMMA-4", harness: "gemini-cli", model: "gemma-4-27b", capabilities: ["long-context", "research", "summarization", "multimodal"], status: "idle" as const },
      { callsign: "QWEN-C", harness: "qwen-cli", model: "qwen3-coder", capabilities: ["execution", "cold-resume", "coding", "batch-ops"], status: "idle" as const },
      { callsign: "CIC-OP", harness: "copilot-cli", model: "gpt-4.1", capabilities: ["forge", "delta-ops", "git-workflow", "refactoring"], status: "working" as const },
      { callsign: "HERMES-7", harness: "hermes", model: "qwen3-coder-next", capabilities: ["orchestration", "delegation", "tts", "multi-model"], status: "online" as const },
    ];
    const agentIds: Record<string, any> = {};
    for (const agent of agents) {
      agentIds[agent.callsign] = await ctx.db.insert("agents", { ...agent, lastCheckin: Date.now() - Math.floor(Math.random() * 300000) });
    }

    // Seed operator
    await ctx.db.insert("operators", {
      callsign: "GRIZZ-0",
      name: "Robert Hanson",
      role: "Commander",
      status: "active",
      lastSeen: Date.now(),
    });

    // Seed cards
    const cards = [
      { laneId: laneIds["intake"], title: "Recon: Proxmox cluster health audit", body: "Full health check across Alpha, Beta, Foxtrot nodes. Disk, memory, uptime, container status.", priority: "routine" as const, status: "intake" as const, latitude: 32.7616, longitude: -97.3435, locationLabel: "White Settlement, TX — Home Lab", tags: ["infra", "proxmox", "audit"], assigneeId: agentIds["CIC-OP"] },
      { laneId: laneIds["active"], title: "Build: Jarvis voice pipeline V2", body: "F5-TTS refactor complete. Wire LiveKit room per agent. Test latency to Charlie VPS.", priority: "priority" as const, status: "active" as const, latitude: 32.7254, longitude: -97.3452, locationLabel: "West Fort Worth — GMRI HQ", tags: ["voice", "livekit", "jarvis"], assigneeId: agentIds["HERMES-7"] },
      { laneId: laneIds["active"], title: "Deploy: Convex agency-comms schema", body: "Kanban + LiveKit signaling + agent bus deployed to fastidious-wolverine-481.convex.cloud", priority: "routine" as const, status: "active" as const, latitude: 37.7749, longitude: -122.4194, locationLabel: "Convex Cloud — us-west-2", tags: ["convex", "deploy", "agency"] },
      { laneId: laneIds["executing"], title: "HARDEN: SSH key rotation — Delta", body: "Kali node SSH keys past 90-day rotation window. Rotate and distribute new pubkeys to Alpha/Beta/Foxtrot.", priority: "immediate" as const, status: "executing" as const, latitude: 52.2297, longitude: 21.0122, locationLabel: "Warsaw, PL — Hostinger KVM4", tags: ["security", "ssh", "rotation"], assigneeId: agentIds["CIC-OP"] },
      { laneId: laneIds["monitoring"], title: "Monitor: Homebridge HA bridge", body: "HomeKit bridge flapped twice last week. Monitor for recurrence. Check mDNS responder on Alpha.", priority: "routine" as const, status: "monitoring" as const, latitude: 32.7616, longitude: -97.3435, locationLabel: "White Settlement, TX — Home Lab", tags: ["homekit", "monitoring", "alpha"] },
      { laneId: laneIds["resolved"], title: "COMPLETE: MCP fleet centralization", body: "Obsidian, Hostinger-SSH, macOS-remote, HomeAssistant, Convex, Mapbox wired across all 5 harnesses.", priority: "routine" as const, status: "resolved" as const, assigneeId: agentIds["OPUS-4"], tags: ["mcp", "infra", "complete"] },
    ];
    for (const card of cards) {
      if (!card.laneId) continue;
      const now = Date.now();
      await ctx.db.insert("cards", { ...card, createdAt: now - 86400000 * Math.random(), updatedAt: now });
    }

    // Seed markers
    const markers = [
      { type: "asset" as const, label: "Alpha — iMac 5K", description: "Proxmox node — 32GB RAM, 2TB HD", latitude: 32.7616, longitude: -97.3435, color: "#3b82f6" },
      { type: "asset" as const, label: "Echo — MacBook Air M2", description: "Primary operator workstation — 8GB", latitude: 32.7254, longitude: -97.3452, color: "#10b981" },
      { type: "asset" as const, label: "Charlie — VPS Docker", description: "Hostinger KVM2 — 8GB RAM, Docker host", latitude: 52.2297, longitude: 21.0122, color: "#f59e0b" },
      { type: "asset" as const, label: "Delta — VPS Kali", description: "Hostinger KVM4 — 16GB RAM, Kali Linux", latitude: 50.0647, longitude: 19.9450, color: "#ef4444" },
      { type: "hazard" as const, label: "Network boundary", description: "NAT traversal required for VPS access", latitude: 38.0, longitude: -95.0, color: "#ef4444" },
      { type: "event" as const, label: "GMRI HQ", description: "White Settlement, TX — Research institute", latitude: 32.7254, longitude: -97.3452, color: "#8b5cf6" },
      { type: "poi" as const, label: "JPS Health Network", description: "Nearest Level 1 Trauma — Fort Worth", latitude: 32.7555, longitude: -97.3308, color: "#ef4444" },
      { type: "asset" as const, label: "Beta — Dell Latitude 3189", description: "Proxmox node — 4GB RAM", latitude: 32.758, longitude: -97.346, color: "#3b82f6" },
      { type: "asset" as const, label: "Foxtrot — Dell Latitude E3550", description: "Proxmox node — 4GB RAM", latitude: 32.7585, longitude: -97.3465, color: "#3b82f6" },
    ];
    for (const m of markers) {
      await ctx.db.insert("markers", { ...m, createdAt: Date.now() });
    }

    return "all_seeded";
  },
});