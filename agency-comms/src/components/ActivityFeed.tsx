"use client";

import { useQuery } from "convex/react";
import { api } from "../../convex/_generated/api";

type Activity = { _id: string; actorName: string; actorRole: string; verb: string; summary: string; createdAt: number };

const VERB_COLORS: Record<string, string> = {
  created: "#10b981",
  moved: "#3b82f6",
  completed: "#10b981",
  assigned: "#8b5cf6",
  alerted: "#ef4444",
  checked_in: "#10b981",
  deployed: "#f59e0b",
  blocked: "#ef4444",
  handoff: "#8b5cf6",
};

export function ActivityFeed() {
  const activity = useQuery(api.activity.recent, { limit: 30 });

  return (
    <div className="h-full flex flex-col bg-[#12121a]">
      <div className="px-3 py-2 border-b border-[#2a2a40] bg-[#0a0a0f]">
        <span className="text-xs font-bold tracking-wider text-[#555570]">ACTIVITY</span>
      </div>
      <div className="flex-1 overflow-y-auto px-2 py-1 space-y-0.5">
        {!activity?.length && (
          <div className="text-[#555570] text-xs text-center py-4">Awaiting activity...</div>
        )}
        {activity?.map((a: Activity) => {
          const color = VERB_COLORS[a.verb] || "#555570";
          const ago = Date.now() - a.createdAt;
          const mins = Math.floor(ago / 60000);
          const timeStr = mins < 1 ? "now" : mins < 60 ? `${mins}m` : `${Math.floor(mins / 60)}h`;
          return (
            <div key={a._id} className="flex items-start gap-2 px-1 py-1 rounded hover:bg-[#1a1a2e] transition-colors">
              <span className="w-1.5 h-1.5 rounded-full mt-1.5 shrink-0" style={{ background: color }} />
              <div className="flex-1 min-w-0">
                <div className="text-[11px] text-[#e8e8f0] leading-tight">
                  <span className="font-bold">{a.actorName}</span>
                  <span className="text-[#555570]"> {a.verb} </span>
                  <span>{a.summary}</span>
                </div>
                <div className="text-[10px] text-[#555570]">{timeStr}</div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}