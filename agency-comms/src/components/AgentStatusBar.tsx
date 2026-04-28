"use client";

import { useQuery } from "convex/react";
import { api } from "../../convex/_generated/api";
import { STATUS_COLORS, HARNESS_COLORS } from "../lib/config";

export function AgentStatusBar() {
  const agents = useQuery(api.agents.list);
  const operators = useQuery(api.operators.list);

  if (!agents || !operators) {
    return (
      <div className="h-10 border-b border-[#2a2a40] bg-[#12121a] flex items-center px-3">
        <span className="text-[#555570] text-xs">Connecting to fleet...</span>
      </div>
    );
  }

  return (
    <div className="h-10 border-b border-[#2a2a40] bg-[#12121a] flex items-center px-3 gap-4 overflow-x-auto">
      <span className="text-[#555570] text-xs font-bold tracking-wider mr-1">FLEET</span>
      {operators?.map((op) => (
        <div key={op._id} className="flex items-center gap-1.5 shrink-0">
          <span className="w-2 h-2 rounded-full bg-[#10b981] pulse-dot" />
          <span className="text-xs text-[#e8e8f0] font-bold">{op.callsign}</span>
          <span className="text-[10px] text-[#555570]">{op.role}</span>
        </div>
      ))}
      <div className="w-px h-4 bg-[#2a2a40]" />
      {agents?.map((agent) => (
        <div key={agent._id} className="flex items-center gap-1.5 shrink-0 group relative">
          <span
            className="w-2 h-2 rounded-full pulse-dot"
            style={{ background: STATUS_COLORS[agent.status] || "#555570" }}
          />
          <span className="text-xs text-[#e8e8f0]">{agent.callsign}</span>
          <span
            className="text-[10px] px-1 rounded"
            style={{
              color: HARNESS_COLORS[agent.harness] || "#8888a0",
              background: `${HARNESS_COLORS[agent.harness] || "#8888a0"}15`,
            }}
          >
            {agent.harness}
          </span>
          {agent.status === "working" && agent.currentTaskId && (
            <span className="text-[10px] text-[#f59e0b]">ACTIVE</span>
          )}
        </div>
      ))}
    </div>
  );
}