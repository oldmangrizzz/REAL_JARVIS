"use client";

import { useQuery, useMutation } from "convex/react";
import { api } from "../../convex/_generated/api";
import { useState, useRef, useEffect } from "react";
import type { Id } from "../../convex/_generated/dataModel";

type Card = { _id: Id<"cards">; title: string; priority: string; status: string; laneId: Id<"lanes"> };
type Message = { _id: Id<"messages">; authorName: string; authorRole: string; body: string; kind: string; createdAt: number };

const KIND_STYLES: Record<string, { bg: string; border: string; text: string; prefix: string }> = {
  text: { bg: "transparent", border: "transparent", text: "#e8e8f0", prefix: "" },
  status: { bg: "#3b82f610", border: "#3b82f630", text: "#3b82f6", prefix: "▸ " },
  alert: { bg: "#ef444410", border: "#ef444430", text: "#ef4444", prefix: "⚠ " },
  checkin: { bg: "#10b98110", border: "#10b98130", text: "#10b981", prefix: "✓ " },
  handoff: { bg: "#8b5cf610", border: "#8b5cf630", text: "#8b5cf6", prefix: "↔ " },
};

export function ChatPanel({ card, onClose }: { card: Card; onClose: () => void }) {
  const messages = useQuery(api.messages.list, { cardId: card._id });
  const sendMessage = useMutation(api.messages.send);
  const agents = useQuery(api.agents.list);
  const [input, setInput] = useState("");
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSend = () => {
    if (!input.trim()) return;
    const operator = (agents as any)?.find?.((a: any) => a.callsign === "GRIZZ-0");
    sendMessage({
      cardId: card._id,
      authorId: operator?._id || ("00000000000000000000000000000000" as Id<"operators">),
      authorName: "GRIZZ-0",
      authorRole: "Commander",
      body: input.trim(),
      kind: "text",
    });
    setInput("");
  };

  const style = KIND_STYLES["text"];

  return (
    <div className="flex flex-col h-full bg-[#12121a]">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-[#2a2a40] bg-[#0a0a0f]">
        <button onClick={onClose} className="text-[#555570] hover:text-[#e8e8f0] text-sm">←</button>
        <div className="flex-1 min-w-0">
          <div className="text-sm font-semibold text-[#e8e8f0] truncate">{card.title}</div>
          <div className="text-[10px] text-[#555570]">{card.priority.toUpperCase()} — {card.status.toUpperCase()}</div>
        </div>
        <div className="flex items-center gap-1">
          <span className="w-2 h-2 rounded-full bg-[#10b981] pulse-dot" />
          <span className="text-[10px] text-[#555570]">LIVE</span>
        </div>
      </div>

      <div ref={scrollRef} className="flex-1 overflow-y-auto p-3 space-y-2">
        {!messages?.length && (
          <div className="text-[#555570] text-xs text-center py-8">No comms yet. Thread starts here.</div>
        )}
        {messages?.map((msg: Message) => {
          const kindStyle = KIND_STYLES[msg.kind] || KIND_STYLES["text"];
          return (
            <div
              key={msg._id}
              className="rounded px-2.5 py-1.5 text-xs"
              style={{
                background: kindStyle.bg,
                borderLeft: `2px solid ${kindStyle.border === "transparent" ? "#2a2a40" : kindStyle.border}`,
              }}
            >
              <div className="flex items-center gap-2 mb-0.5">
                <span className="font-bold" style={{ color: kindStyle.text }}>
                  {kindStyle.prefix}{msg.authorName}
                </span>
                <span className="text-[#555570]">{msg.authorRole}</span>
                <span className="text-[#555570] ml-auto">
                  {new Date(msg.createdAt).toLocaleTimeString("en-US", { hour12: false, hour: "2-digit", minute: "2-digit" })}
                </span>
              </div>
              <div className="text-[#c8c8d0] leading-relaxed">{msg.body}</div>
            </div>
          );
        })}
      </div>

      <div className="border-t border-[#2a2a40] p-2">
        <div className="flex gap-2">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleSend()}
            placeholder="Send to thread..."
            className="flex-1 bg-[#0a0a0f] border border-[#2a2a40] rounded px-3 py-2 text-xs text-[#e8e8f0] placeholder-[#555570] focus:outline-none focus:border-[#4a4a6a]"
          />
          <button
            onClick={handleSend}
            className="bg-[#3b82f6] hover:bg-[#2563eb] text-white px-4 py-2 rounded text-xs font-bold"
          >
            SEND
          </button>
        </div>
      </div>
    </div>
  );
}