"use client";

import { useQuery, useMutation } from "convex/react";
import { api } from "../../convex/_generated/api";
import { PRIORITY_COLORS } from "../lib/config";
import { useState } from "react";
import type { Id } from "../../convex/_generated/dataModel";

type Lane = { _id: Id<"lanes">; name: string; slug: string; ordinal: number; color: string; icon: string; description: string };
type Card = { _id: Id<"cards">; laneId: Id<"lanes">; title: string; body?: string; priority: string; status: string; assigneeId?: Id<"agents">; latitude?: number; longitude?: number; locationLabel?: string; tags?: string[]; createdAt: number; updatedAt: number };
type Agent = { _id: Id<"agents">; callsign: string; harness: string; status: string };

function PriorityBadge({ priority }: { priority: string }) {
  const color = PRIORITY_COLORS[priority] || "#555570";
  return (
    <span
      className="text-[10px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded"
      style={{ color, background: `${color}20` }}
    >
      {priority}
    </span>
  );
}

function TimeAgo({ ts }: { ts: number }) {
  const diff = Date.now() - ts;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return <span className="text-[#10b981]">now</span>;
  if (mins < 60) return <span className="text-[#555570]">{mins}m</span>;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return <span className="text-[#555570]">{hrs}h</span>;
  return <span className="text-[#555570]">{Math.floor(hrs / 24)}d</span>;
}

function CardComponent({ card, agents, onSelect }: { card: Card; agents?: Agent[]; onSelect: (c: Card) => void }) {
  const assignee = agents?.find((a) => a._id === card.assigneeId);
  return (
    <div
      className={`priority-${card.priority} bg-[#16162a] border border-[#2a2a40] rounded-md p-3 cursor-pointer hover:border-[#4a4a6a] transition-all duration-150`}
      onClick={() => onSelect(card)}
    >
      <div className="flex items-start justify-between gap-2 mb-1.5">
        <PriorityBadge priority={card.priority} />
        <TimeAgo ts={card.updatedAt} />
      </div>
      <h3 className="text-sm text-[#e8e8f0] font-semibold leading-tight mb-1">{card.title}</h3>
      {card.body && <p className="text-xs text-[#8888a0] leading-relaxed line-clamp-2">{card.body}</p>}
      <div className="flex items-center gap-2 mt-2 flex-wrap">
        {assignee && (
          <span className="text-[10px] text-[#8b5cf6] bg-[#8b5cf615] px-1.5 py-0.5 rounded">
            {assignee.callsign}
          </span>
        )}
        {card.locationLabel && (
          <span className="text-[10px] text-[#555570] flex items-center gap-0.5">
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
              <circle cx="12" cy="10" r="3" />
            </svg>
            {card.locationLabel}
          </span>
        )}
        {card.tags?.slice(0, 2).map((tag) => (
          <span key={tag} className="text-[10px] text-[#555570] bg-[#2a2a40] px-1.5 py-0.5 rounded">
            {tag}
          </span>
        ))}
      </div>
    </div>
  );
}

export function KanbanBoard({ onSelectCard }: { onSelectCard: (card: Card) => void }) {
  const lanes = useQuery(api.lanes.list);
  const cards = useQuery(api.cards.list, {});
  const agents = useQuery(api.agents.list);
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());

  if (!lanes || !cards) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <span className="text-[#555570] text-sm">Loading board...</span>
      </div>
    );
  }

  const cardsByLane = new Map<string, Card[]>();
  for (const card of cards) {
    const key = card.laneId;
    if (!cardsByLane.has(key)) cardsByLane.set(key, []);
    cardsByLane.get(key)!.push(card);
  }

  return (
    <div className="flex-1 flex overflow-x-auto gap-0">
      {lanes.map((lane) => {
        const laneCards = cardsByLane.get(lane._id) || [];
        const isCollapsed = collapsed.has(lane._id);
        return (
          <div
            key={lane._id}
            className={`flex flex-col border-r border-[#2a2a40] min-h-0 ${isCollapsed ? "w-10" : "w-64 shrink-0"}`}
          >
            <div
              className="flex items-center gap-2 px-3 py-2 border-b border-[#2a2a40] bg-[#12121a] cursor-pointer select-none"
              onClick={() => {
                const next = new Set(collapsed);
                if (next.has(lane._id)) next.delete(lane._id);
                else next.add(lane._id);
                setCollapsed(next);
              }}
            >
              <span className="w-2 h-2 rounded-full" style={{ background: lane.color }} />
              {!isCollapsed && (
                <>
                  <span className="text-xs font-bold text-[#e8e8f0] tracking-wider">{lane.name.toUpperCase()}</span>
                  <span className="text-[10px] text-[#555570] ml-auto">{laneCards.length}</span>
                </>
              )}
            </div>
            {!isCollapsed && (
              <div className="flex-1 overflow-y-auto p-2 space-y-2">
                {laneCards.map((card) => (
                  <CardComponent key={card._id} card={card} agents={agents} onSelect={onSelectCard} />
                ))}
                {laneCards.length === 0 && (
                  <div className="text-[10px] text-[#555570] text-center py-4">No tasks</div>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}