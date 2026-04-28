"use client";

import { useQuery, useMutation } from "convex/react";
import { api } from "../../convex/_generated/api";
import { useState, useRef, useEffect, useMemo } from "react";
import type { Id } from "../../convex/_generated/dataModel";
import { STATUS_COLORS, PRIORITY_COLORS } from "../lib/config";

type Agent = {
  _id: Id<"agents">;
  callsign: string;
  harness: string;
  model?: string;
  capabilities?: string[];
  status: string;
  currentTaskId?: Id<"cards">;
};

type Message = {
  _id: string;
  authorName: string;
  authorRole: string;
  body: string;
  kind: string;
  createdAt: number;
  cardId?: Id<"cards">;
};

type Activity = {
  _id: string;
  actorName: string;
  actorRole: string;
  verb: string;
  summary: string;
  createdAt: number;
};

type Card = {
  _id: Id<"cards">;
  title: string;
  body?: string;
  priority: string;
  status: string;
  assigneeId?: Id<"agents">;
  tags?: string[];
  createdAt: number;
  updatedAt: number;
};

type StreamItem =
  | { type: "message"; data: Message }
  | { type: "activity"; data: Activity }
  | { type: "card"; data: Card };

function timeAgo(ts: number): string {
  const mins = Math.floor((Date.now() - ts) / 60000);
  if (mins < 1) return "now";
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  return `${Math.floor(hrs / 24)}d`;
}

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

const KIND_COLORS: Record<string, string> = {
  text: "#e8e8f0",
  status: "#3b82f6",
  alert: "#ef4444",
  checkin: "#10b981",
  handoff: "#8b5cf6",
};

function TaskCard({ card }: { card: Card }) {
  const [expanded, setExpanded] = useState(false);
  const pColor = PRIORITY_COLORS[card.priority] || "#555570";

  return (
    <div
      onClick={() => setExpanded(!expanded)}
      className="bg-[#1a1a2e] border border-[#2a2a40] rounded px-3 py-2 cursor-pointer hover:border-[#3a3a50] transition-colors"
    >
      <div className="flex items-center gap-2">
        <span className="w-2 h-2 rounded-full shrink-0" style={{ background: pColor }} />
        <span className="text-xs font-bold text-[#e8e8f0] flex-1 truncate">{card.title}</span>
        <span className="text-[10px] text-[#555570] shrink-0">{card.status.toUpperCase()}</span>
      </div>
      {expanded && (
        <div className="mt-2 space-y-1">
          {card.body && <div className="text-[11px] text-[#8888a0]">{card.body}</div>}
          {card.tags && card.tags.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {card.tags.map((t) => (
                <span key={t} className="text-[10px] px-1.5 py-0.5 rounded bg-[#2a2a40] text-[#8888a0]">
                  {t}
                </span>
              ))}
            </div>
          )}
          <div className="text-[10px] text-[#555570]">
            {card.priority.toUpperCase()} · updated {timeAgo(card.updatedAt)}
          </div>
        </div>
      )}
    </div>
  );
}

export function CommandStream() {
  const messages = useQuery(api.messages.recent, { limit: 40 });
  const activity = useQuery(api.activity.recent, { limit: 30 });
  const cards = useQuery(api.cards.list, {});
  const lanes = useQuery(api.lanes.list, {});
  const agents = useQuery(api.agents.list, {});
  const operators = useQuery(api.operators.list, {});
  const sendMessage = useMutation(api.messages.send);
  const createCard = useMutation(api.cards.create);
  const logActivity = useMutation(api.activity.log);

  const [input, setInput] = useState("");
  const [autocomplete, setAutocomplete] = useState<Agent[]>([]);
  const [showCards, setShowCards] = useState(false);
  const streamRef = useRef<HTMLDivElement>(null);

  const operator = operators?.[0];

  const stream: StreamItem[] = useMemo(() => {
    const items: StreamItem[] = [];
    if (messages) {
      for (const m of messages) items.push({ type: "message", data: m as Message });
    }
    if (activity) {
      for (const a of activity) items.push({ type: "activity", data: a as Activity });
    }
    items.sort((a, b) => {
      const ta = a.type === "message" ? a.data.createdAt : a.data.createdAt;
      const tb = b.type === "message" ? b.data.createdAt : b.data.createdAt;
      return tb - ta;
    });
    return items.slice(0, 60);
  }, [messages, activity]);

  useEffect(() => {
    if (streamRef.current) {
      streamRef.current.scrollTop = streamRef.current.scrollHeight;
    }
  }, [stream.length]);

  useEffect(() => {
    if (input.startsWith("/deploy ") || input.startsWith("/assign ")) {
      const prefix = input.split(" ")[1]?.toUpperCase() || "";
      const matches = (agents || []).filter((a: Agent) =>
        a.callsign.toUpperCase().startsWith(prefix)
      );
      setAutocomplete(matches);
    } else {
      setAutocomplete([]);
    }
  }, [input, agents]);

  const handleCommand = async (text: string) => {
    if (!operator) return;
    const trimmed = text.trim();

    if (trimmed.startsWith("/deploy ")) {
      const parts = trimmed.split(/\s+/);
      const callsign = parts[1]?.toUpperCase();
      const taskBody = parts.slice(2).join(" ");
      const agent = (agents || []).find((a: Agent) => a.callsign === callsign);
      if (!agent) {
        await sendMessage({
          authorId: operator._id,
          authorName: operator.callsign,
          authorRole: "Commander",
          body: `Unknown agent: ${callsign}`,
          kind: "alert",
        });
        return;
      }
      const intakeLane = (lanes || []).find((l: { slug: string }) => l.slug === "intake");
      if (!intakeLane) return;
      await createCard({
        laneId: intakeLane._id,
        title: taskBody || `Task for ${callsign}`,
        priority: "routine",
        status: "intake",
        assigneeId: agent._id,
      });
      await logActivity({
        actorId: operator._id,
        actorName: operator.callsign,
        actorRole: "Commander",
        verb: "deployed",
        targetKind: "agent",
        targetId: agent._id,
        summary: `${callsign} → ${taskBody || "new task"}`,
      });
      await sendMessage({
        authorId: operator._id,
        authorName: operator.callsign,
        authorRole: "Commander",
        body: `DEPLOY ${callsign}: ${taskBody || "new task"}`,
        kind: "status",
      });
      return;
    }

    if (trimmed.startsWith("/assign ")) {
      const parts = trimmed.split(/\s+/);
      const callsign = parts[1]?.toUpperCase();
      const taskBody = parts.slice(2).join(" ");
      const agent = (agents || []).find((a: Agent) => a.callsign === callsign);
      if (!agent) {
        await sendMessage({
          authorId: operator._id,
          authorName: operator.callsign,
          authorRole: "Commander",
          body: `Unknown agent: ${callsign}`,
          kind: "alert",
        });
        return;
      }
      await logActivity({
        actorId: operator._id,
        actorName: operator.callsign,
        actorRole: "Commander",
        verb: "assigned",
        targetKind: "agent",
        targetId: agent._id,
        summary: `${callsign} assigned: ${taskBody}`,
      });
      await sendMessage({
        authorId: operator._id,
        authorName: operator.callsign,
        authorRole: "Commander",
        body: `ASSIGN ${callsign}: ${taskBody}`,
        kind: "status",
      });
      return;
    }

    if (trimmed === "/status") {
      const statusLines = (agents || []).map((a: Agent) => {
        const icon = a.status === "online" ? "●" : a.status === "working" ? "◐" : a.status === "idle" ? "○" : "✕";
        return `${icon} ${a.callsign} [${a.status}] ${a.harness}${a.model ? ` ${a.model}` : ""}`;
      });
      await sendMessage({
        authorId: operator._id,
        authorName: operator.callsign,
        authorRole: "Commander",
        body: `FLEET STATUS\n${statusLines.join("\n")}`,
        kind: "status",
      });
      return;
    }

    if (trimmed.startsWith("/task ")) {
      const taskBody = trimmed.slice(6);
      await sendMessage({
        authorId: operator._id,
        authorName: operator.callsign,
        authorRole: "Commander",
        body: `TASK: ${taskBody}`,
        kind: "text",
      });
      return;
    }

    await sendMessage({
      authorId: operator._id,
      authorName: operator.callsign,
      authorRole: "Commander",
      body: trimmed,
      kind: "text",
    });
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim()) return;
    handleCommand(input);
    setInput("");
  };

  const applyAutocomplete = (callsign: string) => {
    const cmd = input.split(" ")[0];
    setInput(`${cmd} ${callsign} `);
    setAutocomplete([]);
  };

  const insertQuickCmd = (cmd: string) => {
    setInput(cmd + " ");
  };

  return (
    <div className="flex flex-col h-full bg-[#0a0a0f]">
      <div ref={streamRef} className="flex-1 overflow-y-auto px-4 py-3 space-y-2">
        {!stream.length && (
          <div className="text-[#555570] text-xs text-center py-8">
            Awaiting transmissions... Type /deploy, /assign, /status, or /task
          </div>
        )}
        {stream.map((item, i) => {
          if (item.type === "message") {
            const m = item.data;
            const color = KIND_COLORS[m.kind] || "#e8e8f0";
            return (
              <div key={`m-${m._id}-${i}`} className="group">
                <div className="flex items-baseline gap-2">
                  <span className="text-[10px] text-[#555570] font-mono shrink-0">{timeAgo(m.createdAt)}</span>
                  <span className="text-xs font-bold shrink-0" style={{ color }}>
                    {m.authorName}
                  </span>
                  {m.kind !== "text" && (
                    <span className="text-[10px] px-1 rounded uppercase font-bold" style={{ color, background: `${color}15` }}>
                      {m.kind}
                    </span>
                  )}
                </div>
                <div className="text-xs text-[#c8c8d0] mt-0.5 ml-8 whitespace-pre-wrap">{m.body}</div>
              </div>
            );
          }

          if (item.type === "activity") {
            const a = item.data;
            const color = VERB_COLORS[a.verb] || "#555570";
            return (
              <div key={`a-${a._id}-${i}`} className="flex items-start gap-2">
                <span className="w-1.5 h-1.5 rounded-full mt-1.5 shrink-0" style={{ background: color }} />
                <span className="text-[11px] text-[#8888a0]">
                  <span className="font-bold text-[#c8c8d0]">{a.actorName}</span>{" "}
                  <span style={{ color }}>{a.verb}</span>{" "}
                  {a.summary}
                </span>
                <span className="text-[10px] text-[#555570] shrink-0 ml-auto">{timeAgo(a.createdAt)}</span>
              </div>
            );
          }

          if (item.type === "card") {
            return (
              <div key={`c-${item.data._id}-${i}`} className="ml-4">
                <TaskCard card={item.data} />
              </div>
            );
          }

          return null;
        })}
      </div>

      {autocomplete.length > 0 && (
        <div className="border-t border-[#2a2a40] bg-[#12121a] px-4 py-1 flex gap-1 flex-wrap">
          {autocomplete.map((a) => (
            <button
              key={a._id}
              onClick={() => applyAutocomplete(a.callsign)}
              className="text-xs px-2 py-0.5 rounded bg-[#1a1a2e] text-[#e8e8f0] hover:bg-[#2a2a40] transition-colors flex items-center gap-1"
            >
              <span className="w-1.5 h-1.5 rounded-full" style={{ background: STATUS_COLORS[a.status] || "#555570" }} />
              {a.callsign}
              <span className="text-[10px] text-[#555570]">{a.harness}</span>
            </button>
          ))}
        </div>
      )}

      <div className="border-t border-[#2a2a40] bg-[#0a0a0f]">
        <div className="flex items-center gap-1 px-3 py-1.5">
          <button
            onClick={() => insertQuickCmd("/deploy")}
            className="text-[10px] px-2 py-0.5 rounded font-bold tracking-wider bg-[#ef4444]15 text-[#ef4444] hover:bg-[#ef4444]25 transition-colors"
          >
            /DEPLOY
          </button>
          <button
            onClick={() => insertQuickCmd("/assign")}
            className="text-[10px] px-2 py-0.5 rounded font-bold tracking-wider bg-[#8b5cf6]15 text-[#8b5cf6] hover:bg-[#8b5cf6]25 transition-colors"
          >
            /ASSIGN
          </button>
          <button
            onClick={() => insertQuickCmd("/status")}
            className="text-[10px] px-2 py-0.5 rounded font-bold tracking-wider bg-[#3b82f6]15 text-[#3b82f6] hover:bg-[#3b82f6]25 transition-colors"
          >
            /STATUS
          </button>
          <button
            onClick={() => insertQuickCmd("/task")}
            className="text-[10px] px-2 py-0.5 rounded font-bold tracking-wider bg-[#10b981]15 text-[#10b981] hover:bg-[#10b981]25 transition-colors"
          >
            /TASK
          </button>
          <div className="flex-1" />
          <button
            onClick={() => setShowCards(!showCards)}
            className={`text-[10px] px-2 py-0.5 rounded font-bold tracking-wider transition-colors ${showCards ? "bg-[#f59e0b]15 text-[#f59e0b]" : "text-[#555570]"}`}
          >
            BOARD {showCards ? "ON" : "OFF"}
          </button>
          <button className="text-[10px] px-2 py-0.5 rounded font-bold tracking-wider text-[#555570] hover:text-[#ef4444] transition-colors">
            MIC
          </button>
          <button className="text-[10px] px-2 py-0.5 rounded font-bold tracking-wider text-[#555570] hover:text-[#3b82f6] transition-colors">
            FILE
          </button>
        </div>
        <form onSubmit={handleSubmit} className="flex items-center gap-2 px-3 pb-3">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Type command or message..."
            className="flex-1 bg-[#12121a] border border-[#2a2a40] rounded px-3 py-2 text-xs text-[#e8e8f0] placeholder-[#555570] focus:border-[#8b5cf6] focus:outline-none transition-colors"
            autoFocus
          />
          <button
            type="submit"
            className="px-3 py-2 bg-[#8b5cf6] hover:bg-[#7c3aed] text-white rounded text-xs font-bold transition-colors"
          >
            SEND
          </button>
        </form>
      </div>

      {showCards && (
        <div className="h-48 border-t border-[#2a2a40] bg-[#12121a] overflow-y-auto px-3 py-2">
          <div className="space-y-1.5">
            {(cards || [])
              .filter((c: Card) => c.status !== "resolved")
              .sort((a: Card, b: Card) => {
                const pri = { immediate: 0, priority: 1, routine: 2 } as const;
                return (pri[a.priority] ?? 3) - (pri[b.priority] ?? 3);
              })
              .map((c: Card) => (
                <TaskCard key={c._id} card={c} />
              ))}
          </div>
        </div>
      )}
    </div>
  );
}